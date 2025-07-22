#!/bin/sh
# ==============================================================================
# Test script for notification settings merge simulation
# This script helps test the config merge process specifically for notification settings
# ==============================================================================

set -eu

# Script version
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Colors for output (Method 5 format - RUTOS compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Enable colors if stdout is a terminal
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions
test_log() {
    printf "${GREEN}[TEST]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

test_debug() {
    printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

test_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

test_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

test_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Test configuration
TEST_DIR="/tmp/starlink-merge-test.$$"
NOTIFICATION_SETTINGS="NOTIFY_ON_CRITICAL NOTIFY_ON_HARD_FAIL NOTIFY_ON_RECOVERY NOTIFY_ON_SOFT_FAIL NOTIFY_ON_INFO"

# Create test files
create_test_files() {
    test_step "Creating test environment in $TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Create a sample existing config with notification settings (your format)
    cat >"$TEST_DIR/existing_config.sh" <<'EOF'
#!/bin/sh
# Sample existing config with notification settings

# Basic settings
export STARLINK_IP="192.168.100.1"
export PUSHOVER_TOKEN="your_app_token_here"
export PUSHOVER_USER="your_user_key_here"

# Notification triggers (1=enabled, 0=disabled)
export NOTIFY_ON_CRITICAL=1  # Critical errors (recommended: 1)
export NOTIFY_ON_HARD_FAIL=1 # Complete failures (recommended: 1)
export NOTIFY_ON_RECOVERY=1  # System recovery (recommended: 1)
export NOTIFY_ON_SOFT_FAIL=1 # Degraded performance (0=disabled for basic setup)
export NOTIFY_ON_INFO=1      # Status updates (0=disabled for basic setup)

# Other settings
export CHECK_INTERVAL=60
export ENABLE_LOGGING="true"
EOF

    # Create a sample template (simulating what would be in config.advanced.template.sh)
    cat >"$TEST_DIR/template.sh" <<'EOF'
#!/bin/sh
# Sample template file

# Basic configuration
export STARLINK_IP="192.168.100.1"
export PUSHOVER_TOKEN="YOUR_APP_TOKEN_HERE"
export PUSHOVER_USER="YOUR_USER_KEY_HERE"

# Advanced notification settings
export NOTIFY_ON_CRITICAL=1
export NOTIFY_ON_HARD_FAIL=1
export NOTIFY_ON_RECOVERY=0
export NOTIFY_ON_SOFT_FAIL=0
export NOTIFY_ON_INFO=0

# System settings
export CHECK_INTERVAL=30
export ENABLE_LOGGING="true"
export LOG_RETENTION_DAYS=7
EOF

    test_log "✓ Test files created"
    test_debug "Existing config: $TEST_DIR/existing_config.sh"
    test_debug "Template file: $TEST_DIR/template.sh"
}

# Simulate the merge process used in install-rutos.sh
simulate_merge() {
    test_step "Simulating config merge process"

    existing_config="$TEST_DIR/existing_config.sh"
    template="$TEST_DIR/template.sh"
    merged_config="$TEST_DIR/merged_config.sh"

    # Copy template as base (this is what install-rutos.sh does)
    cp "$template" "$merged_config"
    test_debug "Template copied to merged config"

    # Settings to preserve (including notification settings)
    settings_to_preserve="STARLINK_IP PUSHOVER_TOKEN PUSHOVER_USER NOTIFY_ON_CRITICAL NOTIFY_ON_HARD_FAIL NOTIFY_ON_RECOVERY NOTIFY_ON_SOFT_FAIL NOTIFY_ON_INFO CHECK_INTERVAL ENABLE_LOGGING"

    test_debug "Settings to preserve: $settings_to_preserve"
    echo ""

    preserved_count=0
    total_count=0

    # Process each setting
    for setting in $settings_to_preserve; do
        total_count=$((total_count + 1))
        test_debug "--- Processing setting $total_count: $setting ---"

        # Look for setting in existing config (both formats)
        user_value=""
        if grep -q "^${setting}=" "$existing_config" 2>/dev/null; then
            user_value=$(grep "^${setting}=" "$existing_config" | head -1)
            test_debug "Found without export: $user_value"
        elif grep -q "^export ${setting}=" "$existing_config" 2>/dev/null; then
            user_value=$(grep "^export ${setting}=" "$existing_config" | head -1)
            test_debug "Found with export: $user_value"
        fi

        if [ -n "$user_value" ]; then
            # Extract the value
            if echo "$user_value" | grep -q "^export "; then
                actual_value=$(echo "$user_value" | sed 's/^export [^=]*=//; s/^"//; s/"$//')
            else
                actual_value=$(echo "$user_value" | sed 's/^[^=]*=//; s/^"//; s/"$//')
            fi

            test_debug "Extracted value: '$actual_value'"

            # Skip placeholder values
            if [ -n "$actual_value" ] && ! echo "$actual_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                test_debug "Value is not a placeholder, proceeding with merge"

                # Replace in merged config
                if grep -q "^export ${setting}=" "$merged_config" 2>/dev/null; then
                    # Replace export line
                    replacement_line="export ${setting}=\"${actual_value}\""
                    if sed -i "s|^export ${setting}=.*|${replacement_line}|" "$merged_config" 2>/dev/null; then
                        preserved_count=$((preserved_count + 1))
                        test_log "✓ Preserved (export): $setting = $actual_value"
                    else
                        test_error "✗ Failed to replace: $setting"
                    fi
                elif grep -q "^${setting}=" "$merged_config" 2>/dev/null; then
                    # Replace standard line
                    replacement_line="${setting}=\"${actual_value}\""
                    if sed -i "s|^${setting}=.*|${replacement_line}|" "$merged_config" 2>/dev/null; then
                        preserved_count=$((preserved_count + 1))
                        test_log "✓ Preserved (standard): $setting = $actual_value"
                    else
                        test_error "✗ Failed to replace: $setting"
                    fi
                else
                    # Add new line
                    replacement_line="export ${setting}=\"${actual_value}\""
                    if echo "$replacement_line" >>"$merged_config" 2>/dev/null; then
                        preserved_count=$((preserved_count + 1))
                        test_log "✓ Added new: $setting = $actual_value"
                    else
                        test_error "✗ Failed to add: $setting"
                    fi
                fi
            else
                test_warning "Skipping placeholder value: $setting"
            fi
        else
            test_warning "Setting not found: $setting"
        fi
    done

    echo ""
    test_step "Merge Results"
    test_log "Settings processed: $total_count"
    test_log "Settings preserved: $preserved_count"

    # Validate notification settings specifically
    notification_count=0
    echo ""
    test_step "Notification Settings Validation"
    for setting in $NOTIFICATION_SETTINGS; do
        if grep -q "^export ${setting}=" "$merged_config" 2>/dev/null; then
            value=$(grep "^export ${setting}=" "$merged_config" | head -1)
            test_log "✓ $value"
            notification_count=$((notification_count + 1))
        elif grep -q "^${setting}=" "$merged_config" 2>/dev/null; then
            value=$(grep "^${setting}=" "$merged_config" | head -1)
            test_log "✓ $value"
            notification_count=$((notification_count + 1))
        else
            test_error "✗ MISSING: $setting"
        fi
    done

    echo ""
    if [ "$notification_count" -eq 5 ]; then
        test_log "✓ SUCCESS: All 5 notification settings preserved"
    else
        test_error "✗ FAILURE: Only $notification_count/5 notification settings preserved"
    fi
}

# Show file contents for analysis
show_analysis() {
    echo ""
    test_step "=== FILE ANALYSIS ==="

    echo ""
    test_debug "ORIGINAL CONFIG (notification settings only):"
    grep -E "NOTIFY_ON|# Notification" "$TEST_DIR/existing_config.sh" 2>/dev/null || test_warning "No notification settings found in original"

    echo ""
    test_debug "TEMPLATE (notification settings only):"
    grep -E "NOTIFY_ON|# notification" "$TEST_DIR/template.sh" 2>/dev/null || test_warning "No notification settings found in template"

    echo ""
    test_debug "MERGED RESULT (notification settings only):"
    grep -E "NOTIFY_ON|# notification" "$TEST_DIR/merged_config.sh" 2>/dev/null || test_warning "No notification settings found in merged result"
}

# Cleanup
cleanup() {
    if [ -d "$TEST_DIR" ]; then
        test_step "Cleaning up test files"
        rm -rf "$TEST_DIR"
        test_log "✓ Cleanup complete"
    fi
}

# Main test execution
main() {
    test_log "Starting notification settings merge test v$SCRIPT_VERSION"
    echo ""

    create_test_files
    echo ""
    simulate_merge
    show_analysis

    echo ""
    test_step "=== RECOMMENDATIONS ==="
    test_log "1. The enhanced install-rutos.sh now includes notification settings in the preserve list"
    test_log "2. Enable debugging: CONFIG_DEBUG=1 DEBUG=1 ./install-rutos.sh"
    test_log "3. Use the debug script: ./debug-notification-merge-rutos.sh"
    test_log "4. Check templates contain the notification settings you expect"

    echo ""
    cleanup

    test_log "Test complete!"
}

# Trap cleanup on exit
trap cleanup EXIT INT TERM

# Run main function
main
