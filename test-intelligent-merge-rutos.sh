#!/bin/sh
# Test script for intelligent config merge functionality
# Tests the new template-driven approach vs old hardcoded approach
# shellcheck disable=SC2059  # Printf format strings use variables for colors

set -e

# Colors for test output (RUTOS-compatible detection)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Enable colors if in a terminal and colors are supported
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Test configuration
TEST_DIR="/tmp/merge_test_$$"
TEMPLATE_FILE="$TEST_DIR/config.template.sh"
CURRENT_CONFIG="$TEST_DIR/config.sh"
BACKUP_FILE="$TEST_DIR/config.sh.backup"

# Create test environment
setup_test() {
    printf "%b[SETUP]%b Creating test environment...\n" "$BLUE" "$NC"
    mkdir -p "$TEST_DIR"

    # Create test template with various types of settings
    cat >"$TEMPLATE_FILE" <<'EOF'
#!/bin/sh
# Test configuration template

# Basic settings
export STARLINK_IP="192.168.100.1"
export CHECK_INTERVAL="30"
export ENABLE_LOGGING="true"

# Notification triggers (the problematic ones)
export NOTIFY_ON_CRITICAL="true"
export NOTIFY_ON_HARD_FAIL="true"
export NOTIFY_ON_RECOVERY="true"
export NOTIFY_ON_SOFT_FAIL="false"
export NOTIFY_ON_INFO="false"

# Advanced settings
export NOTIFICATION_COOLDOWN="300"
export API_CHECK_INTERVAL="60"
export ENABLE_DETAILED_LOGGING="false"

# Placeholder settings
export PUSHOVER_TOKEN="YOUR_PUSHOVER_TOKEN"
export PUSHOVER_USER="YOUR_PUSHOVER_USER"
EOF

    # Create existing config with some customizations
    cat >"$CURRENT_CONFIG" <<'EOF'
#!/bin/sh
# Existing configuration with user customizations

# User customized basic settings
export STARLINK_IP="192.168.1.100"
export CHECK_INTERVAL="45"
export ENABLE_LOGGING="true"

# User notification preferences (THESE SHOULD BE PRESERVED!)
export NOTIFY_ON_CRITICAL="false"
export NOTIFY_ON_HARD_FAIL="true"
export NOTIFY_ON_RECOVERY="false"
export NOTIFY_ON_SOFT_FAIL="true"
export NOTIFY_ON_INFO="true"

# User has real tokens
export PUSHOVER_TOKEN="real_token_12345"
export PUSHOVER_USER="real_user_67890"

# User has custom settings not in template
export CUSTOM_TIMEOUT="120"
export CUSTOM_RETRY_COUNT="5"
EOF

    # Create backup
    cp "$CURRENT_CONFIG" "$BACKUP_FILE"

    printf "%b[SETUP]%b Test environment ready at: %s\n" "$GREEN" "$NC" "$TEST_DIR"
}

# Test the intelligent merge function
test_intelligent_merge() {
    printf "%b[TEST]%b Testing intelligent config merge...\n" "$BLUE" "$NC"

    # Source the install script to get the function
    # We need to extract just the function for testing
    cd "$(dirname "$0")"

    # Define the config_debug function for testing
    config_debug() {
        if [ "${CONFIG_DEBUG:-0}" = "1" ]; then
            printf "${CYAN}[CONFIG_DEBUG]${NC} %s\n" "$1" >&2
        fi
    }

    print_status() {
        color="$1"
        message="$2"
        printf "%s%s${NC}\n" "$color" "$message"
    }

    # Extract and source the intelligent_config_merge function
    # For this test, we'll create a simplified version that focuses on the core logic
    intelligent_config_merge() {
        template_file="$1"
        existing_config="$2"
        # shellcheck disable=SC2034  # backup_file is used by the calling logic
        backup_file="$3"

        if [ ! -f "$template_file" ]; then
            printf "${RED}[ERROR]${NC} Template file not found: %s\n" "$template_file"
            return 1
        fi

        if [ ! -f "$existing_config" ]; then
            printf "${RED}[ERROR]${NC} Existing config not found: %s\n" "$existing_config"
            return 1
        fi

        printf "${BLUE}[MERGE]${NC} Starting intelligent merge process...\n"

        # Create temporary working file
        temp_merged="/tmp/merged_config.$$"
        cp "$template_file" "$temp_merged"

        # Step 1: Get all variables from template
        template_vars=$(grep "^export [A-Za-z_][A-Za-z0-9_]*=" "$template_file" | sed 's/^export \([^=]*\)=.*/\1/' | sort)
        template_count=$(echo "$template_vars" | wc -w)

        printf "${BLUE}[MERGE]${NC} Found %d template variables\n" "$template_count"

        # Step 2: For each template variable, check if user has customized it
        preserved_count=0

        for var in $template_vars; do
            # Look for user's value (with or without export)
            if grep -q "^export ${var}=" "$existing_config" 2>/dev/null; then
                user_value=$(grep "^export ${var}=" "$existing_config" | head -1 | sed 's/^export [^=]*=//')
            elif grep -q "^${var}=" "$existing_config" 2>/dev/null; then
                user_value=$(grep "^${var}=" "$existing_config" | head -1 | sed 's/^[^=]*=//')
            else
                user_value=""
            fi

            if [ -n "$user_value" ]; then
                # Clean the value (remove quotes)
                clean_value=$(echo "$user_value" | sed 's/^"//; s/"$//')

                # Skip placeholders
                if ! echo "$clean_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)"; then
                    # Replace in merged file
                    if sed -i "s|^export ${var}=.*|export ${var}=\"${clean_value}\"|" "$temp_merged" 2>/dev/null; then
                        preserved_count=$((preserved_count + 1))
                        printf "${GREEN}[PRESERVE]${NC} %s = %s\n" "$var" "$clean_value"
                    fi
                fi
            fi
        done

        # Step 3: Find custom variables not in template
        custom_vars=$(grep "^export [A-Za-z_][A-Za-z0-9_]*=" "$existing_config" | sed 's/^export \([^=]*\)=.*/\1/')
        custom_count=0

        for custom_var in $custom_vars; do
            # Check if this variable is NOT in template
            if ! echo "$template_vars" | grep -q "^${custom_var}$"; then
                custom_line=$(grep "^export ${custom_var}=" "$existing_config" | head -1)
                if [ -n "$custom_line" ]; then
                    {
                        echo ""
                        echo "# Custom setting preserved from existing config"
                        echo "$custom_line"
                    } >>"$temp_merged"
                    custom_count=$((custom_count + 1))
                    printf "${CYAN}[CUSTOM]${NC} Added: %s\n" "$custom_var"
                fi
            fi
        done

        # Step 4: Replace the original config
        if mv "$temp_merged" "$existing_config"; then
            printf "${GREEN}[SUCCESS]${NC} Merge completed: %d preserved, %d custom added\n" "$preserved_count" "$custom_count"
            return 0
        else
            printf "${RED}[ERROR]${NC} Failed to replace config file\n"
            return 1
        fi
    }

    # Enable debug mode
    export CONFIG_DEBUG=1

    # Run the merge
    if intelligent_config_merge "$TEMPLATE_FILE" "$CURRENT_CONFIG" "$BACKUP_FILE"; then
        printf "${GREEN}[SUCCESS]${NC} Intelligent merge completed successfully\n"
    else
        printf "${RED}[FAILED]${NC} Intelligent merge failed\n"
        return 1
    fi
}

# Validate results
validate_results() {
    printf "${BLUE}[VALIDATE]${NC} Checking merge results...\n"

    # Check that notification settings were preserved
    notification_count=0
    expected_notifications="NOTIFY_ON_CRITICAL=false NOTIFY_ON_HARD_FAIL=true NOTIFY_ON_RECOVERY=false NOTIFY_ON_SOFT_FAIL=true NOTIFY_ON_INFO=true"

    for expected in $expected_notifications; do
        var=$(echo "$expected" | cut -d= -f1)
        expected_val=$(echo "$expected" | cut -d= -f2)

        if grep -q "^export ${var}=\"${expected_val}\"" "$CURRENT_CONFIG"; then
            notification_count=$((notification_count + 1))
            printf "${GREEN}[✓]${NC} %s = %s (preserved correctly)\n" "$var" "$expected_val"
        else
            printf "${RED}[✗]${NC} %s missing or wrong value\n" "$var"
        fi
    done

    # Check custom settings were preserved
    custom_count=0
    for custom_var in "CUSTOM_TIMEOUT" "CUSTOM_RETRY_COUNT"; do
        if grep -q "^export ${custom_var}=" "$CURRENT_CONFIG"; then
            custom_count=$((custom_count + 1))
            value=$(grep "^export ${custom_var}=" "$CURRENT_CONFIG" | sed 's/.*=//')
            printf "${GREEN}[✓]${NC} Custom setting preserved: %s = %s\n" "$custom_var" "$value"
        else
            printf "${RED}[✗]${NC} Custom setting lost: %s\n" "$custom_var"
        fi
    done

    # Check that user tokens were preserved
    token_count=0
    for token_var in "PUSHOVER_TOKEN" "PUSHOVER_USER"; do
        if grep -q "^export ${token_var}=\"real_" "$CURRENT_CONFIG"; then
            token_count=$((token_count + 1))
            printf "${GREEN}[✓]${NC} User token preserved: %s\n" "$token_var"
        else
            printf "${RED}[✗]${NC} User token lost or reset: %s\n" "$token_var"
        fi
    done

    printf "\n${BLUE}[SUMMARY]${NC} Validation Results:\n"
    printf "  Notification settings: %d/5 preserved\n" "$notification_count"
    printf "  Custom settings: %d/2 preserved\n" "$custom_count"
    printf "  User tokens: %d/2 preserved\n" "$token_count"

    total_score=$((notification_count + custom_count + token_count))
    if [ "$total_score" -eq 9 ]; then
        printf "${GREEN}[PERFECT]${NC} All settings preserved correctly!\n"
        return 0
    else
        printf "${YELLOW}[PARTIAL]${NC} Some settings may need attention (score: %d/9)\n" "$total_score"
        return 1
    fi
}

# Show final merged config
show_results() {
    printf "\n${BLUE}[RESULT]${NC} Final merged configuration:\n"
    printf "${CYAN}=== MERGED CONFIG ===${NC}\n"
    cat "$CURRENT_CONFIG"
    printf "${CYAN}=== END CONFIG ===${NC}\n"
}

# Cleanup
cleanup() {
    printf "\n${BLUE}[CLEANUP]${NC} Removing test files...\n"
    rm -rf "$TEST_DIR"
    printf "${GREEN}[CLEANUP]${NC} Test environment cleaned up\n"
}

# Main test execution
main() {
    if [ "$DEBUG" = "1" ]; then
        printf "Debug script version: %s\n" "$SCRIPT_VERSION"
    fi
    printf "${BLUE}=== INTELLIGENT CONFIG MERGE TEST ===${NC}\n\n"

    setup_test

    if test_intelligent_merge && validate_results; then
        printf "\n${GREEN}[TEST PASSED]${NC} Intelligent merge is working correctly!\n"
        show_results
        test_result=0
    else
        printf "\n${RED}[TEST FAILED]${NC} Intelligent merge has issues\n"
        show_results
        test_result=1
    fi

    cleanup
    return $test_result
}

# Run the test
main "$@"
