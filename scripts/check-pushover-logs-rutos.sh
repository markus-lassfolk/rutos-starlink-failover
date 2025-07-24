#!/bin/sh
# Script: check-pushover-logs-rutos.sh
# Version: 1.0.0
# Description: Check Pushover notification logs and system status

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
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

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

main() {
    log_info "Pushover Notification Log Checker v$SCRIPT_VERSION"
    echo ""
    
    # Check recent syslog entries for Pushover
    log_step "Recent Pushover entries in syslog (logread)"
    if command -v logread >/dev/null 2>&1; then
        echo "Looking for PUSHOVER entries in last 100 log lines:"
        logread | tail -100 | grep -i "pushover\|PushoverNotifier\|SafeNotify\|StarLinkMonitor.*PUSHOVER" || {
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}No PUSHOVER entries found in recent syslog${NC}\n"
        }
    else
        echo "logread not available"
    fi
    echo ""
    
    # Check notification log file
    log_step "Checking notification log file"
    CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE" 2>/dev/null || echo "Failed to source config"
        
        NOTIFICATION_LOG="${LOG_DIR:-/var/log/starlink-monitor}/notifications.log"
        if [ -f "$NOTIFICATION_LOG" ]; then
            echo "Recent notification log entries:"
            tail -20 "$NOTIFICATION_LOG" || echo "Failed to read notification log"
        else
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}Notification log not found: %s${NC}\n" "$NOTIFICATION_LOG"
        fi
    else
        echo "Config file not found: $CONFIG_FILE"
    fi
    echo ""
    
    # Check monitoring script status
    log_step "Checking monitoring script configuration"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE" 2>/dev/null || echo "Failed to source config"
        
        echo "Notification settings:"
        echo "  NOTIFY_ON_SOFT_FAIL: ${NOTIFY_ON_SOFT_FAIL:-1}"
        echo "  NOTIFY_ON_RECOVERY: ${NOTIFY_ON_RECOVERY:-1}"
        echo "  NOTIFIER_SCRIPT: ${NOTIFIER_SCRIPT:-/usr/local/starlink-monitor/Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh}"
        
        if [ -n "${NOTIFIER_SCRIPT:-}" ] && [ -f "$NOTIFIER_SCRIPT" ]; then
            if [ -x "$NOTIFIER_SCRIPT" ]; then
                # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
                printf "  Notifier script: ${GREEN}EXECUTABLE${NC}\n"
            else
                # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
                printf "  Notifier script: ${RED}NOT EXECUTABLE${NC}\n"
            fi
        else
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "  Notifier script: ${RED}NOT FOUND${NC}\n"
        fi
    fi
    echo ""
    
    # Check recent monitoring activity
    log_step "Recent monitoring activity"
    if [ -n "${LOG_DIR:-}" ] && [ -d "$LOG_DIR" ]; then
        MONITOR_LOG="$LOG_DIR/starlink_monitor_$(date +%Y-%m-%d).log"
        if [ -f "$MONITOR_LOG" ]; then
            echo "Recent monitoring events (last 10 lines with 'PUSHOVER' or failures):"
            grep -E "(PUSHOVER|FAIL|ERROR|down|up)" "$MONITOR_LOG" | tail -10 || {
                echo "No recent failure/PUSHOVER events found in monitor log"
            }
        else
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}Today's monitor log not found: %s${NC}\n" "$MONITOR_LOG"
        fi
    fi
    echo ""
    
    # Show current connection status
    log_step "Current system status"
    STATE_FILE="${STATE_DIR:-/var/lib/starlink-monitor}/starlink_state"
    if [ -f "$STATE_FILE" ]; then
        current_state=$(cat "$STATE_FILE")
        echo "Current Starlink state: $current_state"
        
        if [ "$current_state" = "down" ]; then
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${RED}System is currently in failover mode${NC}\n"
            echo "This should have triggered a notification when it failed over"
        else
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${GREEN}System is currently up${NC}\n"
        fi
    else
        echo "State file not found: $STATE_FILE"
    fi
    echo ""
    
    log_step "Manual test recommendation"
    echo "To manually test notifications:"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}  %s test${NC}\n" "${NOTIFIER_SCRIPT:-/usr/local/starlink-monitor/Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh}"
    echo ""
    echo "To monitor notifications in real-time:"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}  logread -f | grep -i pushover${NC}\n"
}

main "$@"
