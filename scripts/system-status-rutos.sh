#!/bin/sh
# Script: system-status.sh
# Version: 1.0.2
# Description: Show system status with graceful degradation information

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.2"

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
log_info() {
    printf "%s[INFO]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "%s[WARNING]%s [%s] %s\n" "$YELLOW" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "%s[ERROR]%s [%s] %s\n" "$RED" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "%s[DEBUG]%s [%s] %s\n" "$CYAN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "%s[SUCCESS]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "%s[STEP]%s [%s] %s\n" "$BLUE" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Status display functions
show_status() {
    status="$1"
    message="$2"

    case "$status" in
        "ok")
            printf "%s✅ %s%s\n" "$GREEN" "$message" "$NC"
            ;;
        "warn")
            printf "%s⚠️  %s%s\n" "$YELLOW" "$message" "$NC"
            ;;
        "error")
            printf "%s❌ %s%s\n" "$RED" "$message" "$NC"
            ;;
        "info")
            printf "%sℹ️  %s%s\n" "$BLUE" "$message" "$NC"
            ;;
        *)
            printf "%s\n" "$message"
            ;;
    esac
}

# Configuration paths
CONFIG_FILE="/root/starlink-monitor/config/config.sh"
INSTALL_DIR="/root/starlink-monitor"

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Function to check system status
check_system_status() {
    log_step "Checking system status"

    printf "%s╔══════════════════════════════════════════════════════════════════════════╗%s\n" "$PURPLE" "$NC"
    printf "%s║%s                         %sSTARLINK MONITOR SYSTEM STATUS%s                         %s║%s\n" "$PURPLE" "$NC" "$BLUE" "$NC" "$PURPLE" "$NC"
    printf "%s╚══════════════════════════════════════════════════════════════════════════╝%s\n" "$PURPLE" "$NC"
    echo ""

    # Check if installation exists
    if [ -d "$INSTALL_DIR" ]; then
        show_status "ok" "Installation directory exists: $INSTALL_DIR"
    else
        show_status "error" "Installation directory not found: $INSTALL_DIR"
        log_error "Please run the installation script first"
        exit 1
    fi

    # Check configuration file
    if [ -f "$CONFIG_FILE" ]; then
        show_status "ok" "Configuration file exists: $CONFIG_FILE"
    else
        show_status "error" "Configuration file not found: $CONFIG_FILE"
        log_error "Please run the installation script first"
        exit 1
    fi

    # Load placeholder utilities
    script_dir="$(dirname "$0")"
    if [ -f "$script_dir/placeholder-utils.sh" ]; then
        . "$script_dir/placeholder-utils.sh"
        show_status "ok" "Placeholder utilities loaded"
    else
        show_status "error" "Placeholder utilities not found"
        log_error "Please run the installation script to restore missing files"
        exit 1
    fi

    # Load configuration
    . "$CONFIG_FILE"

    echo ""
    printf "%s╔══════════════════════════════════════════════════════════════════════════╗%s\n" "$PURPLE" "$NC"
    printf "%s║%s                              %sFEATURE STATUS%s                               %s║%s\n" "$PURPLE" "$NC" "$BLUE" "$NC" "$PURPLE" "$NC"
    printf "%s╚══════════════════════════════════════════════════════════════════════════╝%s\n" "$PURPLE" "$NC"
    echo ""

    # Check core monitoring features
    show_status "info" "Core Monitoring Features:"

    if [ -n "${STARLINK_IP:-}" ] && [ "$STARLINK_IP" != "YOUR_STARLINK_IP" ]; then
        show_status "ok" "Starlink IP configured: $STARLINK_IP"
    else
        show_status "warn" "Starlink IP not configured (using placeholder)"
    fi

    if [ -n "${MWAN_MEMBER:-}" ] && [ "$MWAN_MEMBER" != "YOUR_MWAN_MEMBER" ]; then
        show_status "ok" "MWAN member configured: $MWAN_MEMBER"
    else
        show_status "warn" "MWAN member not configured (using placeholder)"
    fi

    # Check thresholds
    show_status "info" "Quality Thresholds:"
    # Prefer LATENCY_THRESHOLD_MS, fallback to LATENCY_THRESHOLD, else N/A
    if [ -n "${LATENCY_THRESHOLD_MS:-}" ]; then
        printf "  • Latency: %s ms\n" "$LATENCY_THRESHOLD_MS"
    elif [ -n "${LATENCY_THRESHOLD:-}" ]; then
        printf "  • Latency: %s ms\n" "$LATENCY_THRESHOLD"
    else
        printf "  • Latency: N/A\n"
    fi
    printf "  • Packet Loss: %s%%\n" "${PACKET_LOSS_THRESHOLD:-N/A}"
    printf "  • Obstruction: %s%%\n" "${OBSTRUCTION_THRESHOLD:-N/A}"

    echo ""
    show_status "info" "Optional Features:"

    # Check Pushover configuration
    if is_pushover_configured; then
        show_status "ok" "Pushover notifications: Enabled and configured"
    else
        show_status "warn" "Pushover notifications: Disabled (placeholder tokens)"
        printf "%s  → This is normal for basic installations%s\n" "$CYAN" "$NC"
        printf "%s  → Monitoring will work without notifications%s\n" "$CYAN" "$NC"
    fi

    # Check notification script
    # Only warn about notification script if notifications are enabled and pushover is configured
    if is_pushover_configured && { [ "${NOTIFY_ON_CRITICAL:-0}" = "1" ] || [ "${NOTIFY_ON_HARD_FAIL:-0}" = "1" ] || [ "${NOTIFY_ON_RECOVERY:-0}" = "1" ] || [ "${NOTIFY_ON_SOFT_FAIL:-0}" = "1" ] || [ "${NOTIFY_ON_INFO:-0}" = "1" ]; }; then
        if [ -n "${NOTIFIER_SCRIPT:-}" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
            show_status "ok" "Notification script: $NOTIFIER_SCRIPT"
        else
            show_status "warn" "Notification delivery script (internal): Not found or not executable. This is not your Pushover API config. If you see this warning but Pushover is enabled above, please re-run the installer or check for missing files in /usr/local/starlink-monitor/scripts."
        fi
    fi

    # Check logging configuration
    if [ -n "${LOG_DIR:-}" ] && [ -d "$LOG_DIR" ]; then
        show_status "ok" "Log directory: $LOG_DIR"
    else
        show_status "warn" "Log directory: Not configured or doesn't exist"
    fi

    # Check state directory
    if [ -n "${STATE_DIR:-}" ] && [ -d "$STATE_DIR" ]; then
        show_status "ok" "State directory: $STATE_DIR"
    else
        show_status "warn" "State directory: Not configured or doesn't exist"
    fi

    echo ""
    printf "%s╔══════════════════════════════════════════════════════════════════════════╗%s\n" "$PURPLE" "$NC"
    printf "%s║%s                            %sGRACEFUL DEGRADATION%s                            %s║%s\n" "$PURPLE" "$NC" "$BLUE" "$NC" "$PURPLE" "$NC"
    printf "%s╚══════════════════════════════════════════════════════════════════════════╝%s\n" "$PURPLE" "$NC"
    echo ""

    show_status "info" "Graceful Degradation Status:"
    printf "%s  → Monitoring will continue even if optional features are not configured%s\n" "$CYAN" "$NC"
    printf "%s  → Features with placeholder values will be automatically disabled%s\n" "$CYAN" "$NC"
    printf "%s  → Core functionality works with minimal configuration%s\n" "$CYAN" "$NC"

    if ! is_pushover_configured; then
        echo ""
        show_status "info" "To enable Pushover notifications:"
        printf "%s  1. Get API token: https://pushover.net/apps/build%s\n" "$BLUE" "$NC"
        printf "%s  2. Get user key: https://pushover.net/%s\n" "$BLUE" "$NC"
        printf "%s  3. Edit config: vi %s%s\n" "$BLUE" "$CONFIG_FILE" "$NC"
        printf "%s  4. Replace placeholder values with real tokens%s\n" "$BLUE" "$NC"
        printf "%s  5. Test with: ./scripts/test-pushover-rutos.sh%s\n" "$BLUE" "$NC"
    fi

    echo ""
    printf "%s╔══════════════════════════════════════════════════════════════════════════╗%s\n" "$PURPLE" "$NC"
    printf "%s║%s                               %sNEXT STEPS%s                                  %s║%s\n" "$PURPLE" "$NC" "$BLUE" "$NC" "$PURPLE" "$NC"
    printf "%s╚══════════════════════════════════════════════════════════════════════════╝%s\n" "$PURPLE" "$NC"
    echo ""

    show_status "info" "Recommended actions:"
    printf "%s  • Test monitoring: ./scripts/test-monitoring-rutos.sh%s\n" "$BLUE" "$NC"
    printf "%s  • Test Pushover: ./scripts/test-pushover-rutos.sh%s\n" "$BLUE" "$NC"
    printf "%s  • Validate config: ./scripts/validate-config-rutos.sh%s\n" "$BLUE" "$NC"
    printf "%s  • Upgrade to advanced: ./scripts/upgrade-to-advanced-rutos.sh%s\n" "$BLUE" "$NC"

    echo ""
    log_success "System status check completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --version     Show script version"
    echo ""
    echo "Description:"
    echo "  This script shows the current status of the Starlink monitoring system"
    echo "  including configuration status and graceful degradation information."
    echo ""
    echo "Examples:"
    echo "  $0                    # Show system status"
    echo "  DEBUG=1 $0            # Show status with debug output"
}

# Main function
main() {
    quiet_mode="$1"

    if [ "$quiet_mode" != "--quiet" ]; then
        log_info "Starting system status check v$SCRIPT_VERSION"
    fi

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Check system status
    check_system_status
}

# Handle command line arguments
case "${1:-}" in
    --help | -h)
        show_usage
        exit 0
        ;;
    --version)
        echo "$SCRIPT_VERSION"
        exit 0
        ;;
    --quiet)
        # Run in quiet mode (suppress non-essential output)
        main "--quiet"
        ;;
    *)
        # Run main function
        main "$@"
        ;;
esac
