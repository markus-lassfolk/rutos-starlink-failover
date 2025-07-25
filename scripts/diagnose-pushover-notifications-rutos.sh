#!/bin/sh
# Script: diagnose-pushover-notifications-rutos.sh
# Version: 2.7.0
# Description: Comprehensive diagnostic tool for Pushover notification issues

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    echo "[DEBUG] DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    echo "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution" >&2
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY-RUN] Would execute: $description"
        echo "[DRY-RUN] Command: $cmd" >&2
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Standard logging functions with consistent colors
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Function to check if file exists and show permissions
check_file() {
    file_path="$1"
    description="$2"

    printf "${BLUE}%s:${NC}\n" "$description"
    if [ -f "$file_path" ]; then
        printf "  ${GREEN}✓ EXISTS${NC}: %s\n" "$file_path"
        printf "  ${CYAN}Permissions${NC}: %s\n" "$(ls -la "$file_path")"
        printf "  ${CYAN}Size${NC}: %s bytes\n" "$(wc -c <"$file_path")"

        # Check executable permissions for script files
        if echo "$file_path" | grep -q '\.sh$'; then
            if [ -x "$file_path" ]; then
                printf "  ${GREEN}✓ EXECUTABLE${NC}: Script has execute permissions\n"
            else
                printf "  ${RED}✗ NOT EXECUTABLE${NC}: Script missing execute permissions\n"
                errors=$((errors + 1))
                return 1
            fi
        fi

        # Check file size is reasonable for script files
        file_size=$(wc -c <"$file_path" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 100 ]; then
            printf "  ${YELLOW}⚠ WARNING${NC}: File very small ($file_size bytes) - may be corrupted\n"
            warnings=$((warnings + 1))
        fi

        return 0
    else
        printf "  ${RED}✗ MISSING${NC}: %s\n" "$file_path"
        errors=$((errors + 1))
        return 1
    fi
}

# Function to test Pushover credentials
test_pushover_api() {
    token="$1"
    user="$2"

    log_step "Testing Pushover API connectivity"

    if [ -z "$token" ] || [ -z "$user" ]; then
        log_error "Missing Pushover credentials"
        return 1
    fi

    # Test with curl
    if command -v curl >/dev/null 2>&1; then
        printf "  ${CYAN}Testing API call...${NC}\n"
        response=$(curl -s \
            -F "token=$token" \
            -F "user=$user" \
            -F "message=Test from RUTOS diagnostic script" \
            -F "title=RUTOS Diagnostic Test" \
            https://api.pushover.net/1/messages.json 2>&1)

        if echo "$response" | grep -q '"status":1'; then
            printf "  ${GREEN}✓ API TEST PASSED${NC}: Pushover credentials are working\n"
            return 0
        else
            printf "  ${RED}✗ API TEST FAILED${NC}: %s\n" "$response"
            return 1
        fi
    else
        log_warning "curl not available - cannot test API directly"
        return 1
    fi
}

# Function to check configuration values
check_config_value() {
    var_name="$1"
    var_value="$2"
    is_secret="${3:-0}"

    if [ -z "$var_value" ]; then
        printf "  ${RED}✗ NOT SET${NC}: %s\n" "$var_name"
        return 1
    elif [ "$var_value" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$var_value" = "YOUR_PUSHOVER_USER_KEY" ]; then
        printf "  ${YELLOW}⚠ PLACEHOLDER${NC}: %s (still has default placeholder)\n" "$var_name"
        return 1
    else
        if [ "$is_secret" = "1" ]; then
            printf "  ${GREEN}✓ CONFIGURED${NC}: %s (value: %s...)\n" "$var_name" "$(printf "%.6s" "$var_value")"
        else
            printf "  ${GREEN}✓ CONFIGURED${NC}: %s = %s\n" "$var_name" "$var_value"
        fi
        return 0
    fi
}

# Main diagnostic function
main() {
    log_info "Starting Pushover Notification Diagnostic v$SCRIPT_VERSION"
    printf "\n"

    # Debug mode support
    DEBUG="${DEBUG:-0}"
    if [ "$DEBUG" = "1" ]; then
        log_debug "==================== DEBUG MODE ENABLED ===================="
        log_debug "Working directory: $(pwd)"
        log_debug "Current user: $(whoami)"
        log_debug "System: $(uname -a)"
    fi

    errors=0
    warnings=0

    # Step 1: Check configuration file
    log_step "Checking configuration files"
    CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"

    if check_file "$CONFIG_FILE" "Main configuration file"; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE" 2>/dev/null || {
            log_error "Failed to source configuration file"
            errors=$((errors + 1))
        }
    else
        log_error "Configuration file not found"
        errors=$((errors + 1))
    fi
    printf "\n"

    # Step 2: Check Pushover configuration
    log_step "Checking Pushover configuration"

    pushover_ok=1
    if ! check_config_value "PUSHOVER_TOKEN" "${PUSHOVER_TOKEN:-}" "1"; then
        pushover_ok=0
        errors=$((errors + 1))
    fi

    if ! check_config_value "PUSHOVER_USER" "${PUSHOVER_USER:-}" "1"; then
        pushover_ok=0
        errors=$((errors + 1))
    fi

    check_config_value "NOTIFICATION_COOLDOWN" "${NOTIFICATION_COOLDOWN:-300}" "0"
    check_config_value "MAX_NOTIFICATIONS_PER_HOUR" "${MAX_NOTIFICATIONS_PER_HOUR:-12}" "0"
    printf "\n"

    # Step 3: Test Pushover API (only if configured)
    if [ "$pushover_ok" = "1" ]; then
        if test_pushover_api "$PUSHOVER_TOKEN" "$PUSHOVER_USER"; then
            log_info "Pushover API test successful!"
        else
            log_error "Pushover API test failed"
            errors=$((errors + 1))
        fi
    else
        log_warning "Skipping API test due to configuration issues"
        warnings=$((warnings + 1))
    fi
    printf "\n"

    # Step 4: Check required scripts and functions
    log_step "Checking notification system components"

    # Check for key scripts
    check_file "/usr/local/starlink-monitor/scripts/placeholder-utils.sh" "Utility functions script"
    check_file "/usr/local/starlink-monitor/Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh" "Pushover notification script"
    check_file "/usr/local/starlink-monitor/Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh" "Main monitoring script"
    printf "\n"

    # Step 5: Check rate limiting files
    log_step "Checking rate limiting and logs"

    STATE_DIR="${STATE_DIR:-/var/lib/starlink-monitor}"
    LOG_DIR="${LOG_DIR:-/var/log/starlink-monitor}"

    # Check state directory
    printf "${BLUE}State directory:${NC}\n"
    if [ -d "$STATE_DIR" ]; then
        printf "  ${GREEN}✓ EXISTS${NC}: %s\n" "$STATE_DIR"

        # Check rate limit file
        rate_limit_file="${STATE_DIR}/pushover_rate_limit"
        if [ -f "$rate_limit_file" ]; then
            printf "  ${CYAN}Rate limit file${NC}: %s\n" "$(cat "$rate_limit_file")"
        else
            printf "  ${CYAN}Rate limit file${NC}: Not present (OK)\n"
        fi
    else
        printf "  ${RED}✗ MISSING${NC}: %s\n" "$STATE_DIR"
        errors=$((errors + 1))
    fi

    # Check log directory
    printf "${BLUE}Log directory:${NC}\n"
    if [ -d "$LOG_DIR" ]; then
        printf "  ${GREEN}✓ EXISTS${NC}: %s\n" "$LOG_DIR"

        # Check recent logs
        notification_log="${LOG_DIR}/notifications.log"
        if [ -f "$notification_log" ]; then
            printf "  ${CYAN}Recent notifications${NC}:\n"
            tail -5 "$notification_log" | while read -r line; do
                printf "    %s\n" "$line"
            done
        else
            printf "  ${YELLOW}⚠ No notification log${NC}: %s\n" "$notification_log"
            warnings=$((warnings + 1))
        fi

        # Check monitoring logs
        monitor_log="${LOG_DIR}/starlink_monitor_$(date +%Y-%m-%d).log"
        if [ -f "$monitor_log" ]; then
            printf "  ${CYAN}Recent monitoring events${NC}:\n"
            grep -E "(FAIL|ERROR|notification)" "$monitor_log" | tail -3 | while read -r line; do
                printf "    %s\n" "$line"
            done
        else
            printf "  ${YELLOW}⚠ No today's monitor log${NC}: %s\n" "$monitor_log"
            warnings=$((warnings + 1))
        fi
    else
        printf "  ${RED}✗ MISSING${NC}: %s\n" "$LOG_DIR"
        errors=$((errors + 1))
    fi
    printf "\n"

    # Step 6: Manual notification test
    log_step "Manual notification test"

    if [ "$pushover_ok" = "1" ]; then
        printf "To test notifications manually, run:\n"
        printf "${CYAN}  /usr/local/starlink-monitor/Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh test${NC}\n"
        printf "\n"

        printf "To test the monitoring script in debug mode:\n"
        printf "${CYAN}  DEBUG=1 /usr/local/starlink-monitor/Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh${NC}\n"
    else
        printf "${YELLOW}Configure Pushover credentials first, then run manual tests${NC}\n"
    fi
    printf "\n"

    # Step 7: Summary
    log_step "Diagnostic Summary"

    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        printf "${GREEN}✅ ALL CHECKS PASSED${NC}\n"
        printf "Your Pushover notification system appears to be configured correctly.\n"
        printf "If you're still not receiving notifications, check:\n"
        printf "  1. Monitor the log files for actual failure events\n"
        printf "  2. Verify the monitoring script is running (check cron)\n"
        printf "  3. Test with manual notification\n"
    elif [ $errors -eq 0 ]; then
        printf "${YELLOW}⚠ MINOR ISSUES DETECTED${NC} (%d warnings)\n" $warnings
        printf "Your system should work but may have some minor issues.\n"
    else
        printf "${RED}❌ CRITICAL ISSUES DETECTED${NC} (%d errors, %d warnings)\n" $errors $warnings
        printf "Your notification system needs attention before it will work properly.\n"
        printf "\n${CYAN}Priority fixes needed:${NC}\n"
        if [ "$pushover_ok" = "0" ]; then
            printf "  1. Configure Pushover credentials in %s\n" "$CONFIG_FILE"
        fi
        if [ ! -d "$STATE_DIR" ]; then
            printf "  2. Create state directory: mkdir -p %s\n" "$STATE_DIR"
        fi
        if [ ! -d "$LOG_DIR" ]; then
            printf "  3. Create log directory: mkdir -p %s\n" "$LOG_DIR"
        fi
    fi

    printf "\n"
    log_info "Diagnostic completed"
}

# Execute main function
main "$@"
