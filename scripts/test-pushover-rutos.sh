#!/bin/sh
# Script: test-pushover.sh
# Version: 2.7.0
# Description: Simple Pushover notification test script

# RUTOS Compatibility - Dynamic sourcing and intentional variables
# shellcheck disable=SC1090  # Can't follow dynamic source - this is intentional
# shellcheck disable=SC1091  # Don't follow dynamic source files
# shellcheck disable=SC2034  # Variables may appear unused but are referenced dynamically

set -e # Exit on error

# Script version - automatically updated by update-version.sh
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
# shellcheck disable=SC2034
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m' # Bright magenta instead of dark blue for better readability
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Fallback to no colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        printf "[DRY-RUN] Command: %s\n" "$cmd" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] Executing: %s\n" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# Load configuration
load_config() {
    # Default installation directory
    INSTALL_DIR="/root/starlink-monitor"
    CONFIG_FILE="/etc/starlink-config/config.sh"

    # Allow override via environment variable
    if [ -n "${CONFIG_FILE:-}" ]; then
        log_info "Using CONFIG_FILE from environment: $CONFIG_FILE"
    fi

    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Please run the installation script first or set CONFIG_FILE environment variable"
        exit 1
    fi

    # Load placeholder utilities - check both current dir and parent dir (for tests/ subdirectory)
    script_dir="$(dirname "$0")"
    if [ -f "$script_dir/placeholder-utils.sh" ]; then
        . "$script_dir/placeholder-utils.sh"
    elif [ -f "$script_dir/../placeholder-utils.sh" ]; then
        . "$script_dir/../placeholder-utils.sh"
    else
        log_error "Required placeholder-utils.sh not found in $script_dir or $script_dir/.."
        log_error "Please run the installation script to restore missing files"
        exit 1
    fi

    # Source the configuration
    log_info "Loading configuration from: $CONFIG_FILE"
    . "$CONFIG_FILE"

    log_success "Configuration loaded successfully"
}

# Test Pushover notification
test_pushover() {
    log_step "Testing Pushover notification"

    # Check if Pushover is configured using the new utility
    if is_pushover_configured; then
        log_success "✅ Pushover is properly configured"

        # Get custom message if provided
        custom_message="${1:-This is a test notification from your Starlink monitoring system. If you received this, your Pushover configuration is working correctly!}"

        # Send test notification
        log_info "Sending test notification to Pushover..."
        log_info "Message: $custom_message"

        if ! response=$(curl -s -f -m 10 \
            --data-urlencode "token=$PUSHOVER_TOKEN" \
            --data-urlencode "user=$PUSHOVER_USER" \
            --data-urlencode "title=Starlink Monitor - Test Notification" \
            --data-urlencode "message=$custom_message" \
            --data-urlencode "priority=0" \
            https://api.pushover.net/1/messages.json 2>&1); then
            log_error "Failed to send Pushover notification"
            log_error "Error: $response"
            log_error ""
            log_error "Common issues:"
            log_error "• Check your internet connection"
            log_error "• Verify PUSHOVER_TOKEN and PUSHOVER_USER are correct"
            log_error "• Make sure your Pushover app is set up to receive notifications"
            exit 1
        fi

        # Parse response
        if echo "$response" | grep -q '"status":1'; then
            log_success "✅ Pushover test notification sent successfully!"
            log_info ""
            log_info "📱 Check your Pushover app for the test message"
            log_info "🔔 If you don't see it within a few seconds, check:"
            log_info "   • Your phone's notification settings"
            log_info "   • Pushover app notification settings"
            log_info "   • Your user key is correct"
            log_info ""
            log_success "🎉 Pushover integration is working correctly!"

            # Show API response details if requested
            if [ "${DEBUG:-0}" = "1" ]; then
                log_info "API Response: $response"
            fi

            return 0
        else
            log_error "❌ Pushover API returned an error"
            log_error "Response: $response"
            log_error ""
            log_error "Common solutions:"
            log_error "• Verify your API token at https://pushover.net/apps"
            log_error "• Verify your user key at https://pushover.net/"
            log_error "• Make sure your Pushover app is installed and logged in"
            exit 1
        fi
    else
        log_info "⚠️  Pushover notifications are not configured"
        log_info "This is normal for basic installations"
        log_info ""
        log_info "To enable Pushover notifications:"
        log_info "1. Get your API token from: https://pushover.net/apps/build"
        log_info "2. Get your user key from: https://pushover.net/"
        log_info "3. Edit your config: vi $CONFIG_FILE"
        log_info "4. Replace the placeholder values:"
        log_info "   export PUSHOVER_TOKEN=\"your_actual_token_here\""
        log_info "   export PUSHOVER_USER=\"your_actual_user_key_here\""
        log_info "5. Run this test again"
        log_info ""
        log_success "✅ The monitoring system will work without Pushover notifications"
        exit 0
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [custom_message]"
    echo ""
    echo "This script tests Pushover notification functionality by sending a test message."
    echo ""
    echo "Arguments:"
    echo "  custom_message   Optional custom message to send (default: standard test message)"
    echo ""
    echo "Environment variables:"
    echo "  CONFIG_FILE      Path to configuration file (default: /root/starlink-monitor/config/config.sh)"
    echo "  DEBUG           Enable debug output (DEBUG=1)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Send default test message"
    echo "  $0 \"Hello from RUTX50!\"         # Send custom message"
    echo "  DEBUG=1 $0                      # Send test with debug output"
    echo "  CONFIG_FILE=/path/config.sh $0  # Use custom config file"
    echo ""
    echo "Prerequisites:"
    echo "• Pushover account and app installed on your device"
    echo "• PUSHOVER_TOKEN and PUSHOVER_USER configured in config file"
    echo "• Internet connectivity"
    echo ""
    echo "Get your Pushover credentials from:"
    echo "• API Token: https://pushover.net/apps/build"
    echo "• User Key: https://pushover.net/ (after login)"
}

# Main function
main() {
    quiet_mode="$1"
    custom_message="$2"

    if [ "$quiet_mode" != "--quiet" ]; then
        log_info "Starting Pushover Test v$SCRIPT_VERSION"
        echo ""
    fi

    # Load configuration
    load_config

    # Test Pushover
    test_pushover "$custom_message"
}

# Handle command line arguments
case "${1:-}" in
    --help | -h)
        show_usage
        exit 0
        ;;
    --version)
        echo "test-pushover.sh version $SCRIPT_VERSION"
        exit 0
        ;;
    --quiet)
        # Run in quiet mode (suppress non-essential output)
        main "--quiet" "$2"
        ;;
    *)
        # Run with optional custom message
        main "" "$1"
        ;;
esac
