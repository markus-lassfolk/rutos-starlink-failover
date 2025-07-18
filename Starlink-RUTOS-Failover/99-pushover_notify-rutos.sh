#!/bin/sh
# shellcheck shell=sh

# ==============================================================================
# Enhanced Pushover Notifier for Starlink Monitoring System
#
# Version: 2.0 (Enhanced Edition)
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script serves as the central notification hub for the Starlink monitoring
# system. It provides enhanced error handling, rate limiting, and better
# message formatting.
#
# ==============================================================================

set -eu

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034  # Color variables may not all be used in every script
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
    level="$1"
    message="$2"
    timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    logger -t "PushoverNotifier" -p "daemon.$level" -- "$message"
    echo "$timestamp [$level] $message" >>"$NOTIFICATION_LOG"

    if [ -t 1 ]; then
        echo "[$level] $message"
    fi
}

# Rate limiting function
check_rate_limit() {
    message_type="$1"
    current_time
    current_time=$(date '+%s')
    rate_limit_seconds=300 # 5 minutes

    if [ -f "$RATE_LIMIT_FILE" ]; then
        while IFS='=' read -r type last_time; do
            if [ "$type" = "$message_type" ]; then
                time_diff=$((current_time - last_time))
                if [ $time_diff -lt $rate_limit_seconds ]; then
                    log "info" "Rate limit active for $message_type (${time_diff}s ago)"
                    return 1
                fi
            fi
        done <"$RATE_LIMIT_FILE"
    fi

    # Update rate limit file
    temp_file
    temp_file=$(mktemp)
    if [ -f "$RATE_LIMIT_FILE" ]; then
        grep -v "^$message_type=" "$RATE_LIMIT_FILE" >"$temp_file" 2>/dev/null || true
    fi
    echo "$message_type=$current_time" >>"$temp_file"
    mv "$temp_file" "$RATE_LIMIT_FILE"

    return 0
}

# Enhanced notification function with retry logic
send_notification() {
    title="$1"
    message="$2"
    priority="${3:-0}"
    retry_count=0
    max_retries=3
    delay=2

    # Check for configuration
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log "warn" "Pushover not configured, skipping notification"
        return 0
    fi

    log "info" "Sending notification: $title - $message"

    while [ $retry_count -lt $max_retries ]; do
        response
        response=$(
            curl -s --max-time "$HTTP_TIMEOUT" -w "%{http_code}" \
                -F "token=$PUSHOVER_TOKEN" \
                -F "user=$PUSHOVER_USER" \
                -F "title=$title" \
                -F "message=$message" \
                -F "priority=$priority" \
                -F "device=" \
                https://api.pushover.net/1/messages.json 2>/dev/null
        )

        http_code
        http_code="${response##*]}"
        response_body
        # shellcheck disable=SC2034
        response_body="${response%"$http_code"}"

        if [ "$http_code" = "200" ]; then
            log "info" "Notification sent successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log "warn" "Notification failed (HTTP $http_code), retrying in ${delay}s (attempt $retry_count/$max_retries)"
                sleep $delay
                delay=$((delay * 2))
            else
                log "error" "Notification failed after $max_retries attempts (HTTP $http_code)"
                return 1
            fi
        fi
    done

    return 1
}

# Format system information for notifications
get_system_info() {
    hostname
    hostname=$(uname -n)
    uptime
    uptime=$(uptime | cut -d, -f1)
    timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "Host: %s\nTime: %s\nUptime: %s\n" "$hostname" "$timestamp" "$uptime"
}

# Main notification logic
main() {
    action="${1:-hotplug}"
    detail="${2:-}"

    log "info" "Notification triggered: action=$action, detail=$detail"

    case "$action" in
        soft_failover)
            if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ]; then
                if check_rate_limit "soft_failover"; then
                    title
                    title="🔄 Starlink Quality Failover"
                    message
                    message="Starlink quality degraded.\nReason: $detail\nPerforming soft failover to mobile backup.\n\n$(get_system_info)"
                    send_notification "$title" "$message" 1
                fi
            fi
            ;;
        soft_recovery)
            if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ]; then
                if check_rate_limit "soft_recovery"; then
                    title
                    title="✅ Starlink Recovered"
                    message
                    message="Starlink connection is stable.\nPerforming soft failback to primary.\n\n$(get_system_info)"
                    send_notification "$title" "$message" 0
                fi
            fi
            ;;
        api_version_change)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                title
                title="⚠️ Starlink API Changed"
                message
                message="Starlink API version changed.\nPrevious: $detail\nPlease check monitoring scripts.\n\n$(get_system_info)"
                send_notification "$title" "$message" 1
            fi
            ;;
        system_error)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                title
                title="❌ Starlink Monitor Error"
                message
                message="System error occurred.\nDetails: $detail\n\n$(get_system_info)"
                send_notification "$title" "$message" 2
            fi
            ;;
        hotplug)
            # Handle hotplug events
            case "${ACTION:-}" in
                ifdown)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "ifdown_$INTERFACE"; then
                                title
                                title="🔴 Starlink Offline (Hard)"
                                message
                                message="Starlink ($INTERFACE) link is down or failed ping test.\nThis is a hard failure event.\n\n$(get_system_info)"
                                send_notification "$title" "$message" 2
                            fi
                        fi
                    fi
                    ;;
                connected)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                title
                                title="🟢 Starlink Recovered (Hard)"
                                message
                                message="Starlink ($INTERFACE) is back online.\nFailback complete via mwan3.\n\n$(get_system_info)"
                                send_notification "$title" "$message" 0
                            fi
                        fi
                    elif [ "${INTERFACE:-}" = "mob1s1a1" ] || [ "${INTERFACE:-}" = "mob1s2a1" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                title
                                title="📱 Mobile Failover Active"
                                message
                                message="Failover complete.\nTraffic is now flowing over mobile interface ($INTERFACE).\n\n$(get_system_info)"
                                send_notification "$title" "$message" 1
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
            log "warn" "Unknown notification action: $action"
            ;;
    esac

    log "info" "Notification processing completed"
}

# Cleanup old rate limit entries
cleanup_rate_limits() {
    if [ -f "$RATE_LIMIT_FILE" ]; then
        current_time
        current_time=$(date '+%s')
        temp_file
        temp_file=$(mktemp)

        while IFS='=' read -r type last_time; do
            time_diff=$((current_time - last_time))
            if [ $time_diff -lt 3600 ]; then # Keep entries for 1 hour
                echo "$type=$last_time" >>"$temp_file"
            fi
        done <"$RATE_LIMIT_FILE"

        mv "$temp_file" "$RATE_LIMIT_FILE"
    fi
}

# Log rotation
rotate_logs() {
    if [ -f "$NOTIFICATION_LOG" ]; then
        log_size
        log_size=$(stat -c%s "$NOTIFICATION_LOG" 2>/dev/null || echo 0)
        if [ "$log_size" -gt 1048576 ]; then # 1MB
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
