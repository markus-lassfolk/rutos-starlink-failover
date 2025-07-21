#!/bin/sh
# Script: system-status.sh
# Version: 2.4.12
# Description: Show system status with graceful degradation information

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e # Exit on error

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
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
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    # shellcheck disable=SC2317  # Function is called conditionally based on DEBUG environment variable
    if [ "$DEBUG" = "1" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Status display functions
show_status() {
    status="$1"
    message="$2"

    case "$status" in
        "ok")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${GREEN}✅ %s${NC}\n" "$message"
            ;;
        "warn")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}⚠️  %s${NC}\n" "$message"
            ;;
        "error")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${RED}❌ %s${NC}\n" "$message"
            ;;
        "info")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${BLUE}ℹ️  %s${NC}\n" "$message"
            ;;
        *)
            printf "%s\n" "$message"
            ;;
    esac
}

# Configuration paths
CONFIG_FILE="/etc/starlink-config/config.sh"
# Directory paths - dynamic detection
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$(dirname "$SCRIPT_DIR")}"

# Load system configuration for dynamic testing
SYSTEM_CONFIG_FILE="$INSTALL_DIR/config/system-config.sh"
if [ -f "$SYSTEM_CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$SYSTEM_CONFIG_FILE"
    log_debug() { [ "${DEBUG:-0}" = "1" ] && echo "[DEBUG] $*" >&2; }
    log_debug "System configuration loaded from $SYSTEM_CONFIG_FILE"
else
    log_debug() { [ "${DEBUG:-0}" = "1" ] && echo "[DEBUG] $*" >&2; }
    log_debug "System configuration not found at $SYSTEM_CONFIG_FILE, using defaults"
fi

# Fallback to symlink location if main installation not found
if [ ! -d "$INSTALL_DIR" ] && [ -d "/root/starlink-monitor" ]; then
    INSTALL_DIR="/root/starlink-monitor"
    log_debug "Using symlink installation directory: $INSTALL_DIR"
fi

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Function to check cron scheduling status
check_cron_status() {
    CRON_FILE="/etc/crontabs/root"

    # Check if cron service is running
    if pgrep crond >/dev/null 2>&1; then
        show_status "ok" "Cron service is running"
    else
        show_status "error" "Cron service (crond) is not running"
        return
    fi

    # Check if cron file exists
    if [ ! -f "$CRON_FILE" ]; then
        show_status "error" "Cron file ($CRON_FILE) does not exist"
        return
    fi

    # Count monitoring entries - check ALL expected scripts dynamically
    monitor_entries=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_check_entries=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
    maintenance_entries=$(grep -c "system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    # Clean counts (handle RUTOS busybox grep -c malformed output)
    monitor_entries=$(echo "$monitor_entries" | tr -d '\n\r' | sed 's/[^0-9]//g')
    logger_entries=$(echo "$logger_entries" | tr -d '\n\r' | sed 's/[^0-9]//g')
    api_check_entries=$(echo "$api_check_entries" | tr -d '\n\r' | sed 's/[^0-9]//g')
    maintenance_entries=$(echo "$maintenance_entries" | tr -d '\n\r' | sed 's/[^0-9]//g')

    # Ensure valid numbers
    monitor_entries=${monitor_entries:-0}
    logger_entries=${logger_entries:-0}
    api_check_entries=${api_check_entries:-0}
    maintenance_entries=${maintenance_entries:-0}

    # Show detailed scheduling information
    if [ "$monitor_entries" -gt 0 ]; then
        monitor_schedule=$(grep "starlink_monitor-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1 " " $2 " " $3 " " $4 " " $5}')
        show_status "ok" "Monitor scheduled: $monitor_schedule ($monitor_entries entries)"

        if [ "$monitor_entries" -gt 1 ]; then
            show_status "warn" "Multiple monitor entries may cause conflicts"
        fi
    else
        show_status "error" "Starlink monitor not scheduled in cron"
    fi

    if [ "$logger_entries" -gt 0 ]; then
        logger_schedule=$(grep "starlink_logger-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1 " " $2 " " $3 " " $4 " " $5}')
        show_status "ok" "Logger scheduled: $logger_schedule ($logger_entries entries)"

        if [ "$logger_entries" -gt 1 ]; then
            show_status "warn" "Multiple logger entries may cause conflicts"
        fi
    else
        show_status "warn" "Starlink logger not scheduled in cron"
    fi

    if [ "$api_check_entries" -gt 0 ]; then
        log_debug "Processing API check schedule for $api_check_entries entries"
        api_schedule=$(grep "check_starlink_api" "$CRON_FILE" | head -1 | awk '{print $1 " " $2 " " $3 " " $4 " " $5}' 2>/dev/null || echo "unknown")
        log_debug "API schedule extracted: $api_schedule"
        show_status "ok" "API check scheduled: $api_schedule ($api_check_entries entries)"

        if [ "$api_check_entries" -gt 1 ]; then
            show_status "warn" "Multiple API check entries may cause conflicts"
        fi
    else
        show_status "warn" "API check not scheduled in cron"
    fi

    # Check maintenance scheduling
    if [ "$maintenance_entries" -gt 0 ]; then
        maintenance_schedule=$(grep "system-maintenance-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1 " " $2 " " $3 " " $4 " " $5}' 2>/dev/null || echo "unknown")
        show_status "ok" "Maintenance scheduled: $maintenance_schedule ($maintenance_entries entries)"

        if [ "$maintenance_entries" -gt 1 ]; then
            show_status "warn" "Multiple maintenance entries may cause conflicts"
        fi
    else
        show_status "error" "System maintenance not scheduled in cron - MISSING REQUIRED JOB!"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${YELLOW}  → Add maintenance job: 0 */6 * * * CONFIG_FILE=/etc/starlink-config/config.sh %s/scripts/system-maintenance-rutos.sh auto${NC}\n" "${INSTALL_DIR:-/usr/local/starlink-monitor}"
    fi

    # Check for commented entries
    commented_entries=$(grep -c "# COMMENTED BY.*starlink" "$CRON_FILE" 2>/dev/null || echo "0")
    if [ "$commented_entries" -gt 0 ]; then
        show_status "warn" "Found $commented_entries commented monitoring entries (cleanup recommended)"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}  → Run: sed -i '/# COMMENTED BY.*starlink/d' %s${NC}\n" "$CRON_FILE"
    fi

    # Show total entries summary
    total_entries=$((monitor_entries + logger_entries + api_check_entries + maintenance_entries))
    if [ "$total_entries" -eq 0 ]; then
        show_status "error" "No monitoring entries found in cron - system will not monitor automatically"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}  → Fix by re-running: install-rutos.sh${NC}\n"
    elif [ "$total_entries" -gt 3 ]; then
        show_status "warn" "Found $total_entries total entries - duplicates may exist"
    else
        show_status "ok" "Cron configuration looks good ($total_entries total entries)"
    fi

    # Check for CONFIG_FILE environment variable
    config_missing=0
    while IFS= read -r line; do
        case "$line" in
            *starlink*rutos.sh*)
                if ! echo "$line" | grep -q "CONFIG_FILE="; then
                    config_missing=$((config_missing + 1))
                fi
                ;;
        esac
    done <"$CRON_FILE"

    if [ "$config_missing" -gt 0 ]; then
        show_status "warn" "$config_missing entries missing CONFIG_FILE environment variable"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}  → This may cause configuration loading issues${NC}\n"
    fi
}

# Function to check system status
check_system_status() {
    log_step "Checking system status"

    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${PURPLE}║${NC}                         ${BLUE}STARLINK MONITOR SYSTEM STATUS${NC}                         ${PURPLE}║${NC}\n"
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
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
        # shellcheck disable=SC1091
        . "$script_dir/placeholder-utils.sh"
        show_status "ok" "Placeholder utilities loaded"
    else
        show_status "error" "Placeholder utilities not found"
        log_error "Please run the installation script to restore missing files"
        exit 1
    fi

    # Load configuration
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"

    echo ""
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${PURPLE}║${NC}                              ${BLUE}FEATURE STATUS${NC}                               ${PURPLE}║${NC}\n"
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
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
        printf "${CYAN}  → This is normal for basic installations${NC}\n"
        printf "${CYAN}  → Monitoring will work without notifications${NC}\n"
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
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${PURPLE}║${NC}                            ${BLUE}GRACEFUL DEGRADATION${NC}                            ${PURPLE}║${NC}\n"
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    show_status "info" "Graceful Degradation Status:"
    printf "${CYAN}  → Monitoring will continue even if optional features are not configured${NC}\n"
    printf "${CYAN}  → Features with placeholder values will be automatically disabled${NC}\n"
    printf "${CYAN}  → Core functionality works with minimal configuration${NC}\n"

    if ! is_pushover_configured; then
        echo ""
        show_status "info" "To enable Pushover notifications:"
        printf "${BLUE}  1. Get API token: https://pushover.net/apps/build${NC}\n"
        printf "${BLUE}  2. Get user key: https://pushover.net/${NC}\n"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${BLUE}  3. Edit config: vi %s${NC}\n" "$CONFIG_FILE"
        printf "${BLUE}  4. Replace placeholder values with real tokens${NC}\n"
        printf "${BLUE}  5. Test with: ./scripts/test-pushover-rutos.sh${NC}\n"
    fi

    echo ""
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${PURPLE}║${NC}                             ${BLUE}CRON SCHEDULE STATUS${NC}                            ${PURPLE}║${NC}\n"
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    # Check cron configuration
    check_cron_status

    echo ""
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${PURPLE}║${NC}                               ${BLUE}NEXT STEPS${NC}                                  ${PURPLE}║${NC}\n"
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    show_status "info" "Recommended actions:"
    printf "${BLUE}  • Test monitoring: ./scripts/test-monitoring-rutos.sh${NC}\n"
    printf "${BLUE}  • Test Pushover: ./scripts/test-pushover-rutos.sh${NC}\n"
    printf "${BLUE}  • Validate config: ./scripts/validate-config-rutos.sh${NC}\n"
    printf "${BLUE}  • Upgrade to advanced: ./scripts/upgrade-to-advanced-rutos.sh${NC}\n"

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
