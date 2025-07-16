#!/bin/sh
# Script: 99-pushover_notify-rutos.sh
# Version: 2.0 (Enhanced Edition)
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# Enhanced Pushover Notifier for Starlink Monitoring System
#
# This script serves as the central notification hub for the Starlink monitoring
# system. It provides enhanced error handling, rate limiting, and better
# message formatting.
#
# ==============================================================================

set -e

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[1;35m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
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
    # shellcheck disable=SC2034
    RED=""
    # shellcheck disable=SC2034
    GREEN=""
    # shellcheck disable=SC2034
    YELLOW=""
    # shellcheck disable=SC2034
    BLUE=""
    # shellcheck disable=SC2034
    CYAN=""
    # shellcheck disable=SC2034
    NC=""
fi

# --- Configuration Loading ---
CONFIG_FILE="${CONFIG_FILE:-/root/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# --- Derived Configuration ---
RATE_LIMIT_FILE="${STATE_DIR}/pushover_rate_limit"
NOTIFICATION_LOG="${LOG_DIR}/notifications.log"

# --- Helper Functions ---

# Enhanced logging
log() {
    log_level="$1"
    log_message="$2"
    log_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    logger -t "PushoverNotifier" -p "daemon.$log_level" -- "$log_message"
    echo "$log_timestamp [$log_level] $log_message" >>"$NOTIFICATION_LOG"

    if [ -t 1 ]; then
        echo "[$log_level] $log_message"
    fi
}

# Rate limiting function
check_rate_limit() {
    check_message_type="$1"
    check_current_time=$(date '+%s')
    check_rate_limit_seconds=300 # 5 minutes

    if [ -f "$RATE_LIMIT_FILE" ]; then
        while IFS='=' read -r type last_time; do
            if [ "$type" = "$check_message_type" ]; then
                check_time_diff=$((check_current_time - last_time))
                if [ $check_time_diff -lt $check_rate_limit_seconds ]; then
                    log "info" "Rate limit active for $check_message_type (${check_time_diff}s ago)"
                    return 1
                fi
            fi
        done <"$RATE_LIMIT_FILE"
    fi

    # Update rate limit file
    check_temp_file=$(mktemp)
    if [ -f "$RATE_LIMIT_FILE" ]; then
        grep -v "^$check_message_type=" "$RATE_LIMIT_FILE" >"$check_temp_file" 2>/dev/null || true
    fi
    echo "$check_message_type=$check_current_time" >>"$check_temp_file"
    mv "$check_temp_file" "$RATE_LIMIT_FILE"

    return 0
}

# Enhanced notification function with retry logic
send_notification() {
    send_title="$1"
    send_message="$2"
    send_priority="${3:-0}"
    send_retry_count=0
    send_max_retries=3
    send_delay=2

    # Check for configuration
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log "warn" "Pushover not configured, skipping notification"
        return 0
    fi

    log "info" "Sending notification: $send_title - $send_message"

    while [ $send_retry_count -lt $send_max_retries ]; do
        send_response=$(curl -s --max-time "$HTTP_TIMEOUT" -w "%{http_code}" \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "title=$send_title" \
            -F "message=$send_message" \
            -F "priority=$send_priority" \
            -F "device=" \
            https://api.pushover.net/1/messages.json 2>/dev/null)

        send_http_code="${send_response##*]}"
        # shellcheck disable=SC2034
        send_response_body="${send_response%"$send_http_code"}"

        if [ "$send_http_code" = "200" ]; then
            log "info" "Notification sent successfully"
            return 0
        else
            send_retry_count=$((send_retry_count + 1))
            if [ $send_retry_count -lt $send_max_retries ]; then
                log "warn" "Notification failed (HTTP $send_http_code), retrying in ${send_delay}s (attempt $send_retry_count/$send_max_retries)"
                sleep $send_delay
                send_delay=$((send_delay * 2))
            else
                log "error" "Notification failed after $send_max_retries attempts (HTTP $send_http_code)"
                return 1
            fi
        fi
    done

    return 1
}

# Format system information for notifications
get_system_info() {
    system_hostname=$(uname -n)
    system_uptime=$(uptime | cut -d, -f1)
    system_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "Host: %s\nTime: %s\nUptime: %s\n" "$system_hostname" "$system_timestamp" "$system_uptime"
}

# Main notification logic
main() {
    main_action="${1:-hotplug}"
    main_detail="${2:-}"

    log "info" "Notification triggered: action=$main_action, detail=$main_detail"

    case "$main_action" in
        soft_failover)
            if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ]; then
                if check_rate_limit "soft_failover"; then
                    soft_failover_title="🔄 Starlink Quality Failover"
                    soft_failover_message="Starlink quality degraded.\nReason: $main_detail\nPerforming soft failover to mobile backup.\n\n$(get_system_info)"
                    send_notification "$soft_failover_title" "$soft_failover_message" 1
                fi
            fi
            ;;
        soft_recovery)
            if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ]; then
                if check_rate_limit "soft_recovery"; then
                    soft_recovery_title="✅ Starlink Recovered"
                    soft_recovery_message="Starlink connection is stable.\nPerforming soft failback to primary.\n\n$(get_system_info)"
                    send_notification "$soft_recovery_title" "$soft_recovery_message" 0
                fi
            fi
            ;;
        api_version_change)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                api_version_title="⚠️ Starlink API Changed"
                api_version_message="Starlink API version changed.\nPrevious: $main_detail\nPlease check monitoring scripts.\n\n$(get_system_info)"
                send_notification "$api_version_title" "$api_version_message" 1
            fi
            ;;
        system_error)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                system_error_title="❌ Starlink Monitor Error"
                system_error_message="System error occurred.\nDetails: $main_detail\n\n$(get_system_info)"
                send_notification "$system_error_title" "$system_error_message" 2
            fi
            ;;
        hotplug)
            # Handle hotplug events
            case "${ACTION:-}" in
                ifdown)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "ifdown_$INTERFACE"; then
                                ifdown_title="🔴 Starlink Offline (Hard)"
                                ifdown_message="Starlink ($INTERFACE) link is down or failed ping test.\nThis is a hard failure event.\n\n$(get_system_info)"
                                send_notification "$ifdown_title" "$ifdown_message" 2
                            fi
                        fi
                    fi
                    ;;
                connected)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                connected_starlink_title="🟢 Starlink Recovered (Hard)"
                                connected_starlink_message="Starlink ($INTERFACE) is back online.\nFailback complete via mwan3.\n\n$(get_system_info)"
                                send_notification "$connected_starlink_title" "$connected_starlink_message" 0
                            fi
                        fi
                    elif [ "${INTERFACE:-}" = "mob1s1a1" ] || [ "${INTERFACE:-}" = "mob1s2a1" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                connected_mobile_title="📱 Mobile Failover Active"
                                connected_mobile_message="Failover complete.\nTraffic is now flowing over mobile interface ($INTERFACE).\n\n$(get_system_info)"
                                send_notification "$connected_mobile_title" "$connected_mobile_message" 1
                            fi
                        fi
                    fi
                    ;;
            esac
            ;;
        test)
            # Test all notification types
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                send_notification "[TEST] Critical Error" "This is a test critical error notification.\n$(get_system_info)" 2
            fi
            if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ]; then
                send_notification "[TEST] Soft Failover" "This is a test soft failover notification.\n$(get_system_info)" 1
            fi
            if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                send_notification "[TEST] Hard Failover" "This is a test hard failover notification.\n$(get_system_info)" 2
            fi
            if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ]; then
                send_notification "[TEST] Recovery" "This is a test recovery notification.\n$(get_system_info)" 0
            fi
            if [ "${NOTIFY_ON_INFO:-0}" = "1" ]; then
                send_notification "[TEST] Info/Status" "This is a test info/status notification.\n$(get_system_info)" -1
            fi
            ;;
        *)
            log "warn" "Unknown notification action: $main_action"
            ;;
    esac

    log "info" "Notification processing completed"
}

# Cleanup old rate limit entries
cleanup_rate_limits() {
    if [ -f "$RATE_LIMIT_FILE" ]; then
        cleanup_current_time=$(date '+%s')
        cleanup_temp_file=$(mktemp)

        while IFS='=' read -r type last_time; do
            cleanup_time_diff=$((cleanup_current_time - last_time))
            if [ $cleanup_time_diff -lt 3600 ]; then # Keep entries for 1 hour
                echo "$type=$last_time" >>"$cleanup_temp_file"
            fi
        done <"$RATE_LIMIT_FILE"

        mv "$cleanup_temp_file" "$RATE_LIMIT_FILE"
    fi
}

# Log rotation
rotate_logs() {
    if [ -f "$NOTIFICATION_LOG" ]; then
        rotate_log_size=$(stat -c%s "$NOTIFICATION_LOG" 2>/dev/null || echo 0)
        if [ "$rotate_log_size" -gt 1048576 ]; then # 1MB
            mv "$NOTIFICATION_LOG" "${NOTIFICATION_LOG}.old"
            touch "$NOTIFICATION_LOG"
        fi
    fi
}

# Run maintenance tasks
cleanup_rate_limits
rotate_logs

# Execute main function
main "$@"
