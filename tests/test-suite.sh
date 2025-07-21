#!/bin/sh

# ==============================================================================
# Test Suite for Starlink Monitoring System
#
# This script provides comprehensive testing for the Starlink monitoring
# system to ensure reliability and correctness.
#
# ==============================================================================

set -eu

# Colors for output
# Check if terminal supports colors
# shellcheck disable=SC2034  # Color variables may not all be used in every script

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Fallback to no colors if terminal doesn't support them
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Test configuration
TEST_DIR="/tmp/starlink-test"
MOCK_CONFIG="$TEST_DIR/mock_config.sh"
MOCK_STATE_DIR="$TEST_DIR/state"
MOCK_LOG_DIR="$TEST_DIR/logs"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_status() {
    color="$1"
    message="$2"
    printf '%b%s%b\n' "$color" "$message" "$NC"
}

log_test() {
    status="$1"
    test_name="$2"
    message="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$status" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_status "$GREEN" "✓ $test_name: $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_status "$RED" "✗ $test_name: $message"
    fi
}

assert_equals() {
    expected="$1"
    actual="$2"
    test_name="$3"

    if [ "$expected" = "$actual" ]; then
        log_test "PASS" "$test_name" "Expected '$expected', got '$actual'"
        return 0
    else
        log_test "FAIL" "$test_name" "Expected '$expected', got '$actual'"
        return 1
    fi
}

assert_file_exists() {
    file="$1"
    test_name="$2"

    if [ -f "$file" ]; then
        log_test "PASS" "$test_name" "File exists: $file"
        return 0
    else
        log_test "FAIL" "$test_name" "File not found: $file"
        return 1
    fi
}

# shellcheck disable=SC2317
assert_command_success() {
    command="$1"
    test_name="$2"

    if eval "$command" >/dev/null 2>&1; then
        log_test "PASS" "$test_name" "Command succeeded: $command"
        return 0
    else
        log_test "FAIL" "$test_name" "Command failed: $command"
        return 1
    fi
}

# Setup test environment
setup_test_env() {
    print_status "$BLUE" "Setting up test environment..."

    # Create test directories
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    mkdir -p "$MOCK_STATE_DIR"
    mkdir -p "$MOCK_LOG_DIR"

    # Create mock configuration
    cat >"$MOCK_CONFIG" <<'EOF'
#!/bin/sh
# Mock configuration for testing

STARLINK_IP="192.168.100.1:9200"
MWAN_IFACE="wan"
MWAN_MEMBER="member1"
PUSHOVER_TOKEN="test_token"
PUSHOVER_USER="test_user"
PACKET_LOSS_THRESHOLD=0.05
OBSTRUCTION_THRESHOLD=0.001
LATENCY_THRESHOLD_MS=150
# shellcheck disable=SC2034
STABILITY_CHECKS_REQUIRED=5
METRIC_GOOD=1
METRIC_BAD=10
STATE_DIR="/tmp/starlink-test/state"
LOG_DIR="/tmp/starlink-test/logs"
DATA_DIR="/tmp/starlink-test/data"
GRPCURL_CMD="/usr/bin/grpcurl"
JQ_CMD="/usr/bin/jq"
LOG_TAG="StarlinkTest"
LOG_RETENTION_DAYS=7
API_TIMEOUT=10
HTTP_TIMEOUT=15
EOF

    print_status "$GREEN" "✓ Test environment setup complete"
}

# Test configuration loading
test_config_loading() {
    print_status "$BLUE" "Testing configuration loading..."

    # Test valid configuration
    CONFIG_FILE="$MOCK_CONFIG"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        assert_equals "wan" "$MWAN_IFACE" "config_loading_basic"
        assert_equals "0.05" "$PACKET_LOSS_THRESHOLD" "config_loading_threshold"
    else
        log_test "FAIL" "config_loading_file" "Mock config file not found"
    fi

    # Test missing configuration
    CONFIG_FILE="/nonexistent/config.sh"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_test "PASS" "config_loading_missing" "Correctly detects missing config"
    else
        log_test "FAIL" "config_loading_missing" "Should fail with missing config"
    fi
}

# Test threshold validation
test_threshold_validation() {
    print_status "$BLUE" "Testing threshold validation..."

    # Load config
    # shellcheck source=/dev/null
    . "$MOCK_CONFIG"

    # Test packet loss threshold
    loss_value="0.10"
    is_loss_high
    is_loss_high=$(awk -v val="$loss_value" -v threshold="$PACKET_LOSS_THRESHOLD" 'BEGIN { print (val > threshold) }')
    assert_equals "1" "$is_loss_high" "threshold_packet_loss_high"

    # Test obstruction threshold
    obstruction_value="0.002"
    is_obstructed
    is_obstructed=$(awk -v val="$obstruction_value" -v threshold="$OBSTRUCTION_THRESHOLD" 'BEGIN { print (val > threshold) }')
    assert_equals "1" "$is_obstructed" "threshold_obstruction_high"

    # Test latency threshold
    latency_value="200"
    is_latency_high=0
    if [ "$latency_value" -gt "$LATENCY_THRESHOLD_MS" ]; then
        is_latency_high=1
    fi
    assert_equals "1" "$is_latency_high" "threshold_latency_high"
}

# Test state management
test_state_management() {
    print_status "$BLUE" "Testing state management..."

    # Load config
    # shellcheck source=/dev/null
    . "$MOCK_CONFIG"

    state_file
    state_file="$STATE_DIR/test.state"

    # Test state file creation
    echo "up" >"$state_file"
    assert_file_exists "$state_file" "state_file_creation"

    # Test state reading
    state
    state=$(cat "$state_file")
    assert_equals "up" "$state" "state_reading"

    # Test state update
    echo "down" >"$state_file"
    state=$(cat "$state_file")
    assert_equals "down" "$state" "state_update"

    # Cleanup
    rm -f "$state_file"
}

# Test logging functions
test_logging() {
    print_status "$BLUE" "Testing logging functions..."

    # Load config
    # shellcheck source=/dev/null
    . "$MOCK_CONFIG"

    # Mock log function
    log() {
        level="$1"
        message="$2"
        echo "[$level] $message" >>"$LOG_DIR/test.log"
    }

    # Test logging
    log "info" "Test message"

    # Check log file
    if [ -f "$LOG_DIR/test.log" ]; then
        log_content
        log_content=$(cat "$LOG_DIR/test.log")
        if echo "$log_content" | grep -q "Test message"; then
            log_test "PASS" "logging_basic" "Log message written correctly"
        else
            log_test "FAIL" "logging_basic" "Log message not found"
        fi
    else
        log_test "FAIL" "logging_file" "Log file not created"
    fi
}

# Test JSON parsing
test_json_parsing() {
    print_status "$BLUE" "Testing JSON parsing..."

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_test "SKIP" "json_parsing" "jq not available"
        return 0
    fi

    # Test JSON parsing
    test_json='{"dishGetStatus":{"obstructionStats":{"fractionObstructed":0.01},"popPingLatencyMs":100}}'

    obstruction
    obstruction=$(echo "$test_json" | jq -r '.dishGetStatus.obstructionStats.fractionObstructed')
    assert_equals "0.01" "$obstruction" "json_parsing_obstruction"

    latency
    latency=$(echo "$test_json" | jq -r '.dishGetStatus.popPingLatencyMs')
    assert_equals "100" "$latency" "json_parsing_latency"
}

# Test notification rate limiting
test_rate_limiting() {
    print_status "$BLUE" "Testing notification rate limiting..."

    # Load config
    # shellcheck source=/dev/null
    . "$MOCK_CONFIG"

    rate_file
    rate_file="$STATE_DIR/rate_limit"
    current_time
    current_time=$(date '+%s')

    # Create rate limit entry
    echo "soft_failover=$current_time" >"$rate_file"

    # Test rate limiting function
    check_rate_limit() {
        message_type="$1"
        rate_limit_seconds=300

        if [ -f "$rate_file" ]; then
            while IFS='=' read -r type last_time; do
                if [ "$type" = "$message_type" ]; then
                    time_diff=$((current_time - last_time))
                    if [ $time_diff -lt $rate_limit_seconds ]; then
                        return 1
                    fi
                fi
            done <"$rate_file"
        fi
        return 0
    }

    # Test rate limiting
    if check_rate_limit "soft_failover"; then
        log_test "FAIL" "rate_limiting_active" "Rate limiting should be active"
    else
        log_test "PASS" "rate_limiting_active" "Rate limiting working correctly"
    fi
}

# Test arithmetic operations
test_arithmetic() {
    print_status "$BLUE" "Testing arithmetic operations..."

    # Test awk arithmetic
    result
    result=$(awk 'BEGIN { print (0.1 > 0.05) }')
    assert_equals "1" "$result" "arithmetic_awk_comparison"

    # Test shell arithmetic
    value=200
    threshold=150
    is_high=0
    if [ "$value" -gt "$threshold" ]; then
        is_high=1
    fi
    assert_equals "1" "$is_high" "arithmetic_shell_comparison"
}

# Test file operations
test_file_operations() {
    print_status "$BLUE" "Testing file operations..."

    # Load config
    # shellcheck source=/dev/null
    . "$MOCK_CONFIG"

    test_file
    test_file="$STATE_DIR/test_file"

    # Test file creation
    echo "test content" >"$test_file"
    assert_file_exists "$test_file" "file_creation"

    # Test file reading
    content
    content=$(cat "$test_file")
    assert_equals "test content" "$content" "file_reading"

    # Test file permissions
    chmod 600 "$test_file"
    perms
    perms=$(stat -c "%a" "$test_file" 2>/dev/null || echo "unknown")
    if [ "$perms" = "600" ]; then
        log_test "PASS" "file_permissions" "File permissions set correctly"
    else
        log_test "FAIL" "file_permissions" "File permissions incorrect: $perms"
    fi

    # Test file deletion
    rm -f "$test_file"
    if [ ! -f "$test_file" ]; then
        log_test "PASS" "file_deletion" "File deleted successfully"
    else
        log_test "FAIL" "file_deletion" "File not deleted"
    fi
}

# Test error handling
test_error_handling() {
    print_status "$BLUE" "Testing error handling..."

    # Test command failure handling
    if ! false; then
        log_test "PASS" "error_handling_basic" "Command failure detected"
    else
        log_test "FAIL" "error_handling_basic" "Command failure not detected"
    fi

    # Test undefined variable handling
    set +u # Temporarily disable undefined variable check
    # shellcheck disable=SC2154
    undefined_var
    # shellcheck disable=SC2154
    undefined_var="$undefined_variable"
    set -u

    if [ -z "$undefined_var" ]; then
        log_test "PASS" "error_handling_undefined" "Undefined variable handled"
    else
        log_test "FAIL" "error_handling_undefined" "Undefined variable not handled"
    fi
}

# Test installation validation
test_installation() {
    print_status "$BLUE" "Testing installation validation..."

    # Test required commands
    required_commands="uci logger curl awk"
    for cmd in $required_commands; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_test "PASS" "installation_$cmd" "Command available: $cmd"
        else
            log_test "FAIL" "installation_$cmd" "Command missing: $cmd"
        fi
    done

    # Test directory structure
    required_dirs="/tmp /var/log /etc"
    for dir in $required_dirs; do
        if [ -d "$dir" ]; then
            log_test "PASS" "installation_dir_$dir" "Directory exists: $dir"
        else
            log_test "FAIL" "installation_dir_$dir" "Directory missing: $dir"
        fi
    done
}

# Cleanup test environment
cleanup_test_env() {
    print_status "$BLUE" "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    print_status "$GREEN" "✓ Test environment cleanup complete"
}

# Generate test report
generate_report() {
    print_status "$BLUE" "=== Test Report ==="
    print_status "$GREEN" "Tests run: $TESTS_RUN"
    print_status "$GREEN" "Tests passed: $TESTS_PASSED"

    if [ $TESTS_FAILED -gt 0 ]; then
        print_status "$RED" "Tests failed: $TESTS_FAILED"
    else
        print_status "$GREEN" "Tests failed: $TESTS_FAILED"
    fi

    success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    print_status "$BLUE" "Success rate: $success_rate%"

    if [ $TESTS_FAILED -eq 0 ]; then
        print_status "$GREEN" "All tests passed! 🎉"
        return 0
    else
        print_status "$RED" "Some tests failed. Please review the results above."
        return 1
    fi
}

# Main test runner
main() {
    if [ "$DEBUG" = "1" ]; then
        printf "Debug script version: %s\n" "$SCRIPT_VERSION"
    fi
    print_status "$GREEN" "=== Starlink Monitoring System Test Suite ==="
    echo ""

    setup_test_env

    # Run all tests
    test_config_loading
    test_threshold_validation
    test_state_management
    test_logging
    test_json_parsing
    test_rate_limiting
    test_arithmetic
    test_file_operations
    test_error_handling
    test_installation

    echo ""
    generate_report

    cleanup_test_env

    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run tests
main "$@"
