#!/bin/sh
# Script: test-pushover-quick-rutos.sh
# Version: 1.0.0
# Description: Quick Pushover test for RUTOS environment

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034  # Used in some conditional contexts
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

log_info() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_error() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

# Quick test function
quick_test() {
    log_info "Quick Pushover Test v$SCRIPT_VERSION"

    # Try to find config
    CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
    if [ ! -f "$CONFIG_FILE" ]; then
        # Try alternative locations
        for alt_config in "/usr/local/starlink-monitor/config.sh" "/tmp/config.sh" "$(pwd)/config.sh"; do
            if [ -f "$alt_config" ]; then
                CONFIG_FILE="$alt_config"
                break
            fi
        done
    fi

    if [ -f "$CONFIG_FILE" ]; then
        log_step "Loading config from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
    else
        log_error "No config file found. Please provide PUSHOVER_TOKEN and PUSHOVER_USER"
        printf "Usage examples:\n"
        printf "  PUSHOVER_TOKEN=your_token PUSHOVER_USER=your_user %s\n" "$0"
        printf "  Or create config at: %s\n" "$CONFIG_FILE"
        exit 1
    fi

    # Check credentials
    if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
        log_error "Pushover credentials not configured"
        printf "PUSHOVER_TOKEN: %s\n" "${PUSHOVER_TOKEN:-NOT_SET}"
        printf "PUSHOVER_USER: %s\n" "${PUSHOVER_USER:-NOT_SET}"
        exit 1
    fi

    # Check for placeholders
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log_error "Pushover credentials still have placeholder values"
        printf "Please update your config file with real credentials\n"
        exit 1
    fi

    log_step "Credentials configured - testing API"

    # Test notification
    if command -v curl >/dev/null 2>&1; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        response=$(curl -s \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "message=Quick test from RUTOS router at $timestamp. If you receive this, your Pushover notifications are working!" \
            -F "title=🧪 RUTOS Pushover Test" \
            -F "priority=0" \
            https://api.pushover.net/1/messages.json 2>&1)

        if echo "$response" | grep -q '"status":1'; then
            printf "${GREEN}✅ SUCCESS!${NC} Test notification sent successfully\n"
            printf "Check your Pushover app/device for the test message\n"

            # Show response details if debug
            if [ "${DEBUG:-0}" = "1" ]; then
                printf "\nAPI Response: %s\n" "$response"
            fi

            printf "\n${BLUE}Next steps:${NC}\n"
            printf "1. Check your Pushover app for the test message\n"
            printf "2. If received, your notifications are working\n"
            printf "3. If no message, check your Pushover app settings\n"
            printf "4. Monitor your system logs for actual failover events\n"

        else
            printf "${RED}❌ FAILED${NC} - API call unsuccessful\n"
            printf "Response: %s\n" "$response"

            if echo "$response" | grep -q "invalid"; then
                printf "\n${YELLOW}Possible issues:${NC}\n"
                printf "- Invalid token or user key\n"
                printf "- Check your Pushover credentials\n"
            fi
            exit 1
        fi
    else
        log_error "curl not available - cannot test API"
        exit 1
    fi
}

# Execute
quick_test "$@"
