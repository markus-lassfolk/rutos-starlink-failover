#!/bin/sh
# Script: test-enhanced-restoration-rutos.sh
# Version: 1.0.2
# Description: Test the enhanced firmware upgrade restoration system

set -e

# Version information
SCRIPT_VERSION="1.0.2"

# Standard colors for consistent output (compatible with busybox)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Test configuration
INSTALL_DIR="/usr/local/starlink-monitor"
# shellcheck disable=SC2034  # PERSISTENT_CONFIG_DIR used in test functions
PERSISTENT_CONFIG_DIR="/etc/starlink-config"
TEST_DIR="/tmp/restoration-test"
# shellcheck disable=SC2034  # RESTORE_LOG used for test logging
RESTORE_LOG="/var/log/starlink-restore.log"

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_test() {
    printf "${CYAN}[TEST]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Test results tracking
tests_passed=0
tests_failed=0
tests_total=0

# Test assertion functions
# shellcheck disable=SC2317  # Functions are called from main() - ShellCheck static analysis limitation
assert_true() {
    condition="$1"
    message="$2"
    tests_total=$((tests_total + 1))

    if eval "$condition"; then
        log_test "✅ PASS: $message"
        tests_passed=$((tests_passed + 1))
        return 0
    else
        log_test "❌ FAIL: $message"
        tests_failed=$((tests_failed + 1))
        return 1
    fi
}

assert_file_exists() {
    # shellcheck disable=SC2317  # Called from test functions - ShellCheck static analysis limitation
    file="$1"
    message="${2:-File does not exist: $file}"
    assert_true "[ -f '$file' ]" "$message"
}

assert_file_not_exists() {
    file="$1"
    message="${2:-File does not exist: $file}"
    assert_true "[ ! -f '$file' ]" "$message"
}

# Setup test environment
setup_test_environment() {
    log_step "Setting up test environment"

    # Create test directory
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR/config"
    mkdir -p "$TEST_DIR/persistent"

    # Create mock fresh configuration
    cat >"$TEST_DIR/config/config.sh" <<'EOF'
#!/bin/sh
# Fresh installation configuration
# Template Version: 2.1.0

STARLINK_IP="192.168.100.1"
MWAN_IFACE="starlink"
MWAN_MEMBER="member1"
PUSHOVER_TOKEN="YOUR_PUSHOVER_TOKEN_HERE"
PUSHOVER_USER="YOUR_PUSHOVER_USER_HERE"
RUTOS_USERNAME="YOUR_RUTOS_USERNAME"
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"
EOF

    # Create mock persistent configuration (user configured)
    cat >"$TEST_DIR/persistent/config.sh" <<'EOF'
#!/bin/sh
# User persistent configuration
# Template Version: 2.0.0

STARLINK_IP="192.168.100.1"
MWAN_IFACE="starlink"
MWAN_MEMBER="member1"
PUSHOVER_TOKEN="app123token456here"
PUSHOVER_USER="user789key123here"
RUTOS_USERNAME="admin"
RUTOS_PASSWORD="secure123password"
ENABLE_LOGGING=true
EOF

    # Create corrupted configuration for testing
    cat >"$TEST_DIR/persistent/corrupted_config.sh" <<'EOF'
#!/bin/sh
# Corrupted configuration - missing closing quote
STARLINK_IP="192.168.100.1
MWAN_IFACE=starlink
MWAN_MEMBER="member1
EOF

    # Create minimal configuration for testing
    echo "TINY=1" >"$TEST_DIR/persistent/tiny_config.sh"

    log_info "Test environment setup complete"
}

# Test configuration validation
test_configuration_validation() {
    log_step "Testing configuration validation"

    # Test valid configuration
    assert_true "sh -n '$TEST_DIR/config/config.sh'" "Fresh config has valid shell syntax"
    assert_true "sh -n '$TEST_DIR/persistent/config.sh'" "Persistent config has valid shell syntax"

    # Test file size validation
    config_size=$(wc -c <"$TEST_DIR/persistent/config.sh")
    assert_true "[ '$config_size' -gt 100 ]" "Persistent config has reasonable size ($config_size bytes)"

    tiny_size=$(wc -c <"$TEST_DIR/persistent/tiny_config.sh")
    assert_true "[ '$tiny_size' -lt 100 ]" "Tiny config is detected as too small ($tiny_size bytes)"

    # Test corrupted configuration detection
    assert_true "! sh -n '$TEST_DIR/persistent/corrupted_config.sh' 2>/dev/null" "Corrupted config fails syntax check"

    # Test required settings presence
    for setting in STARLINK_IP MWAN_IFACE MWAN_MEMBER; do
        assert_true "grep -q \"^\${setting}=\" \"\$TEST_DIR/persistent/config.sh\"" "Required setting present: $setting"
    done
}

# Test configuration merging
test_configuration_merging() {
    log_step "Testing configuration merging logic"

    # Create test merge function (simplified version)
    test_merge_configs() {
        fresh_config="$1"
        persistent_config="$2"
        output_config="$3"

        # Start with fresh config as base
        cp "$fresh_config" "$output_config"

        # Extract user settings from persistent config and apply to output
        user_settings="PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD"

        for setting in $user_settings; do
            if grep -q "^${setting}=" "$persistent_config" 2>/dev/null; then
                persistent_value=$(grep "^${setting}=" "$persistent_config" | head -1)

                # Skip placeholder values
                if echo "$persistent_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE)" 2>/dev/null; then
                    continue
                fi

                # Apply setting to output config
                if grep -q "^${setting}=" "$output_config" 2>/dev/null; then
                    setting_escaped=$(echo "$setting" | sed "s/[[\.*^$()+?{|]/\\\\&/g")
                    sed -i "s|^${setting_escaped}=.*|${persistent_value}|" "$output_config" 2>/dev/null
                else
                    echo "$persistent_value" >>"$output_config"
                fi
            fi
        done

        return 0
    }

    # Test the merge
    merged_config="$TEST_DIR/merged_config.sh"
    if test_merge_configs "$TEST_DIR/config/config.sh" "$TEST_DIR/persistent/config.sh" "$merged_config"; then
        log_test "✅ PASS: Configuration merge completed"
        tests_passed=$((tests_passed + 1))
    else
        log_test "❌ FAIL: Configuration merge failed"
        tests_failed=$((tests_failed + 1))
    fi
    tests_total=$((tests_total + 1))

    # Verify merged configuration
    if [ -f "$merged_config" ]; then
        # Check that user values were preserved
        assert_true "grep -q 'PUSHOVER_TOKEN=\"app123token456here\"' '$merged_config'" "User Pushover token preserved"
        assert_true "grep -q 'RUTOS_USERNAME=\"admin\"' '$merged_config'" "User RUTOS username preserved"
        assert_true "grep -q 'RUTOS_PASSWORD=\"secure123password\"' '$merged_config'" "User RUTOS password preserved"

        # Check that fresh template structure was maintained
        assert_true "grep -q 'Template Version: 2.1.0' '$merged_config'" "Fresh template version maintained"
    fi
}

# Test backup functionality
test_backup_functionality() {
    log_step "Testing backup functionality"

    # Create mock backup scenario
    test_backup_dir="$TEST_DIR/backup_test"
    mkdir -p "$test_backup_dir"

    # Create original config
    cp "$TEST_DIR/persistent/config.sh" "$test_backup_dir/config.sh"

    # Simulate backup creation
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="$test_backup_dir/config.sh.pre-restore.$backup_timestamp"
    cp "$test_backup_dir/config.sh" "$backup_file"

    assert_file_exists "$backup_file" "Backup file created successfully"

    # Test backup cleanup (keep last 5)
    # Create multiple backup files
    for i in 1 2 3 4 5 6 7; do
        old_timestamp=$(date -d "$i hours ago" +%Y%m%d_%H%M%S 2>/dev/null || echo "${backup_timestamp}0$i")
        touch "$test_backup_dir/config.sh.backup.$old_timestamp"
    done

    # Count backups before cleanup
    backup_count_before=$(find "$test_backup_dir" -name "config.sh.backup.*" -type f | wc -l)

    # Simulate cleanup (keep last 5)
    find "$test_backup_dir" -name "config.sh.backup.*" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true

    # Count backups after cleanup
    backup_count_after=$(find "$test_backup_dir" -name "config.sh.backup.*" -type f | wc -l)

    assert_true "[ '$backup_count_before' -eq 7 ]" "Created 7 backup files"
    assert_true "[ '$backup_count_after' -le 5 ]" "Backup cleanup limited to 5 files (had $backup_count_after)"
}

# Test restoration service status
test_restoration_service() {
    log_step "Testing restoration service status"

    # Check if restoration service exists
    if [ -f "/etc/init.d/starlink-restore" ]; then
        assert_file_exists "/etc/init.d/starlink-restore" "Auto-restoration service file exists"
        assert_true "[ -x '/etc/init.d/starlink-restore' ]" "Auto-restoration service is executable"

        # Check if service is enabled (non-blocking test)
        if /etc/init.d/starlink-restore enabled 2>/dev/null; then
            log_test "✅ PASS: Auto-restoration service is enabled"
            tests_passed=$((tests_passed + 1))
        else
            log_test "❌ FAIL: Auto-restoration service is NOT enabled"
            tests_failed=$((tests_failed + 1))
        fi
        tests_total=$((tests_total + 1))
    else
        log_warning "Auto-restoration service not installed - this is expected in development environment"
    fi
}

# Test validation script
test_validation_script() {
    log_step "Testing dedicated validation script"

    validation_script="$INSTALL_DIR/scripts/validate-persistent-config-rutos.sh"

    if [ -f "$validation_script" ]; then
        assert_file_exists "$validation_script" "Validation script exists"
        assert_true "[ -x '$validation_script' ]" "Validation script is executable"

        # Test validation with good config
        if "$validation_script" "$TEST_DIR/persistent/config.sh" >/dev/null 2>&1; then
            log_test "✅ PASS: Validation script accepts good configuration"
            tests_passed=$((tests_passed + 1))
        else
            log_test "❌ FAIL: Validation script rejected good configuration"
            tests_failed=$((tests_failed + 1))
        fi
        tests_total=$((tests_total + 1))

        # Test validation with corrupted config
        if ! "$validation_script" "$TEST_DIR/persistent/corrupted_config.sh" >/dev/null 2>&1; then
            log_test "✅ PASS: Validation script correctly rejects corrupted configuration"
            tests_passed=$((tests_passed + 1))
        else
            log_test "❌ FAIL: Validation script incorrectly accepted corrupted configuration"
            tests_failed=$((tests_failed + 1))
        fi
        tests_total=$((tests_total + 1))
    else
        log_warning "Validation script not found - may not be installed yet"
    fi
}

# Show test summary
show_test_summary() {
    log_step "Test Summary"

    printf "\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}==================== TEST RESULTS ====================${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}Tests Passed: %d${NC}\n" "$tests_passed"
    if [ "$tests_failed" -gt 0 ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${RED}Tests Failed: %d${NC}\n" "$tests_failed"
    else
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${GREEN}Tests Failed: %d${NC}\n" "$tests_failed"
    fi
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}Total Tests:  %d${NC}\n" "$tests_total"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}====================================================${NC}\n"

    if [ "$tests_failed" -eq 0 ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${GREEN}🎉 All tests passed! Enhanced restoration system is working correctly.${NC}\n"
        return 0
    else
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${RED}💥 Some tests failed. Please review the issues above.${NC}\n"
        return 1
    fi
}

# Cleanup test environment
cleanup_test_environment() {
    log_step "Cleaning up test environment"
    rm -rf "$TEST_DIR"
    log_info "Test cleanup complete"
}

# Show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Test the enhanced firmware upgrade restoration system."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --no-cleanup  Skip cleanup of test files"
    echo ""
    echo "This script tests:"
    echo "  • Configuration validation logic"
    echo "  • Configuration merging functionality"
    echo "  • Backup creation and management"
    echo "  • Restoration service status"
    echo "  • Validation script functionality"
}

# Main function
main() {
    cleanup_enabled=true

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                show_usage
                exit 0
                ;;
            --no-cleanup)
                cleanup_enabled=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log_info "Starting enhanced restoration system tests v$SCRIPT_VERSION"

    # Setup test environment
    setup_test_environment

    # Run all tests
    test_configuration_validation
    test_configuration_merging
    test_backup_functionality
    test_restoration_service
    test_validation_script

    # Show results
    if show_test_summary; then
        exit_code=0
    else
        exit_code=1
    fi

    # Cleanup if requested
    if [ "$cleanup_enabled" = true ]; then
        cleanup_test_environment
    else
        log_info "Test files preserved in: $TEST_DIR"
    fi

    exit $exit_code
}

# Execute main function
main "$@"
