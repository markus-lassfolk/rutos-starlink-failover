#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2034

# ==============================================================================
# Enhanced Pushover Notifier for Starlink Monitoring System
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script serves as the central notification hub for the Starlink monitoring
# system. It provides enhanced error handling, rate limiting, and better
# message formatting.
#
# ==============================================================================

set -eu

# BusyBox compatibility: set PS4 without LINENO for debug mode
PS4='+ '

# Version information (auto-updated by update-version.sh)
# Load RUTOS library system for standardized logging and utilities
# Try multiple paths for library loading (development, installation, hotplug)
if [ -f "$(dirname "$0")/lib/rutos-lib.sh" ]; then
    . "$(dirname "$0")/lib/rutos-lib.sh"
elif [ -f "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" ]; then
    . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh"
elif [ -f "./lib/rutos-lib.sh" ]; then
    . "./lib/rutos-lib.sh"
else
    # Fallback logging if library not available
    printf "[WARNING] RUTOS library not found, using fallback logging
"
fi

# Initialize script with RUTOS library features if available

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "99-pushover_notify-rutos.sh" "$SCRIPT_VERSION"
else
    # Fallback logging if library not available
    printf "[WARNING] RUTOS library not found, using fallback logging
"

    # Minimal fallback functions
    log_info() { printf "[INFO] %s
" "$1"; }
    log_error() { printf "[ERROR] %s
" "$1" >&2; }
    log_debug() {
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] %s
" "$1" >&2
        fi
    }
    safe_execute() {
        cmd="$1"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            printf "[DRY_RUN] Would execute: %s
" "$cmd" >&2
        else
            if [ "${DEBUG:-0}" = "1" ]; then
                printf "[DEBUG] Executing: %s
" "$cmd" >&2
            fi
            eval "$cmd"
        fi
    }
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# RUTOS_TEST_MODE enables trace logging (does NOT cause early exit)
# Script continues normal execution with enhanced debugging when RUTOS_TEST_MODE=1

# --- Configuration Loading ---
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    if [ "$DRY_RUN" = "1" ]; then
        # In dry-run mode, provide fallback values for testing
        printf "[INFO] DRY_RUN mode: Using fallback configuration (config file not found: %s)
" "$CONFIG_FILE" >&2
        STATE_DIR="${STATE_DIR:-/tmp/starlink-test}"
        LOG_DIR="${LOG_DIR:-/tmp/starlink-test}"
        PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-test-token}"
        PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-test-key}"
        RATE_LIMIT_SECONDS="${RATE_LIMIT_SECONDS:-300}"
        # Create directories for dry-run mode
        mkdir -p "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
    else
        echo "Error: Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
fi

# --- Derived Configuration ---
RATE_LIMIT_FILE="${STATE_DIR}/pushover_rate_limit"
NOTIFICATION_LOG="${LOG_DIR}/notifications.log"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s
" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        printf "[DRY-RUN] Would execute: %s
" "$description" >&2
        printf "[DRY-RUN] Command: %s
" "$cmd" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] Executing: %s
" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# --- Helper Functions ---

# Enhanced logging
log() {
    log_level="$1"
    log_message="$2"
    log_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to syslog with more specific tag for easier filtering
    logger -t "PushoverNotifier" -p "daemon.$log_level" -- "[PUSHOVER] $log_message"

    # Also log to our dedicated notification log
    echo "$log_timestamp [$log_level] $log_message" >>"$NOTIFICATION_LOG"

    # Show on console if terminal available
    if [ -t 1 ]; then
        echo "[$log_level] $log_message"
    fi
}

# Rate limiting function
check_rate_limit() {
    rate_limit_message_type="$1"
    rate_limit_current_time=$(date '+%s')
    rate_limit_seconds=300 # 5 minutes

    if [ -f "$RATE_LIMIT_FILE" ]; then
        while IFS='=' read -r type last_time; do
            if [ "$type" = "$rate_limit_message_type" ]; then
                rate_limit_time_diff=$((rate_limit_current_time - last_time))
                if [ $rate_limit_time_diff -lt $rate_limit_seconds ]; then
                    log "info" "Rate limit active for $rate_limit_message_type (${rate_limit_time_diff}s ago)"
                    return 1
                fi
            fi
        done <"$RATE_LIMIT_FILE"
    fi

    # Update rate limit file
    rate_limit_temp_file=$(mktemp)
    if [ -f "$RATE_LIMIT_FILE" ]; then
        grep -v "^$rate_limit_message_type=" "$RATE_LIMIT_FILE" >"$rate_limit_temp_file" 2>/dev/null || true
    fi
    echo "$rate_limit_message_type=$rate_limit_current_time" >>"$rate_limit_temp_file"
    mv "$rate_limit_temp_file" "$RATE_LIMIT_FILE"

    return 0
}

# Enhanced notification function with retry logic
send_notification() {
    notify_title="$1"
    notify_message="$2"
    notify_priority="${3:-0}"
    notify_retry_count=0
    notify_max_retries=3
    notify_delay=2

    # Check for configuration
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log "warn" "Pushover not configured, skipping notification"
        return 0
    fi

    log "info" "Sending notification: $notify_title - $notify_message"

    while [ $notify_retry_count -lt $notify_max_retries ]; do
        notify_response=$(
            curl -s --max-time "$HTTP_TIMEOUT" -w "%{http_code}" \
                -F "token=$PUSHOVER_TOKEN" \
                -F "user=$PUSHOVER_USER" \
                -F "title=$notify_title" \
                -F "message=$notify_message" \
                -F "priority=$notify_priority" \
                -F "device=" \
                https://api.pushover.net/1/messages.json 2>/dev/null
        )

        notify_http_code="${notify_response##*]}"
        # shellcheck disable=SC2034
        notify_response_body="${notify_response%"$notify_http_code"}"

        if [ "$notify_http_code" = "200" ]; then
            log "info" "Notification sent successfully"
            return 0
        else
            notify_retry_count=$((notify_retry_count + 1))
            if [ $notify_retry_count -lt $notify_max_retries ]; then
                log "warn" "Notification failed (HTTP $notify_http_code), retrying in ${notify_delay}s (attempt $notify_retry_count/$notify_max_retries)"
                sleep $notify_delay
                notify_delay=$((notify_delay * 2))
            else
                log "error" "Notification failed after $notify_max_retries attempts (HTTP $notify_http_code)"
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
    printf "Host: %s
Time: %s
Uptime: %s
" "$system_hostname" "$system_timestamp" "$system_uptime"
}

# Main notification logic
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s
" "99-pushover_notify-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: 99-pushover_notify-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    main_action="${1:-hotplug}"
    main_detail="${2:-}"

    log "info" "Notification triggered: action=$main_action, detail=$main_detail"

    case "$main_action" in
        soft_failover)
            if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ]; then
                if check_rate_limit "soft_failover"; then
                    main_title="🔄 Starlink Quality Failover"
                    main_message="Starlink quality degraded.
Reason: $main_detail
Performing soft failover to mobile backup.

$(get_system_info)"
                    send_notification "$main_title" "$main_message" 1
                fi
            fi
            ;;
        soft_recovery)
            if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ]; then
                if check_rate_limit "soft_recovery"; then
                    main_title="✅ Starlink Recovered"
                    main_message="Starlink connection is stable.
Performing soft failback to primary.

$(get_system_info)"
                    send_notification "$main_title" "$main_message" 0
                fi
            fi
            ;;
        api_version_change)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                main_title="⚠️ Starlink API Changed"
                main_message="Starlink API version changed.
Previous: $main_detail
Please check monitoring scripts.

$(get_system_info)"
                send_notification "$main_title" "$main_message" 1
            fi
            ;;
        system_error)
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                main_title="❌ Starlink Monitor Error"
                main_message="System error occurred.
Details: $main_detail

$(get_system_info)"
                send_notification "$main_title" "$main_message" 2
            fi
            ;;
        hotplug)
            # Handle hotplug events
            case "${ACTION:-}" in
                ifdown)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "ifdown_$INTERFACE"; then
                                main_title="🔴 Starlink Offline (Hard)"
                                main_message="Starlink ($INTERFACE) link is down or failed ping test.
This is a hard failure event.

$(get_system_info)"
                                send_notification "$main_title" "$main_message" 2
                            fi
                        fi
                    fi
                    ;;
                connected)
                    if [ "${INTERFACE:-}" = "$MWAN_IFACE" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                main_title="🟢 Starlink Recovered (Hard)"
                                main_message="Starlink ($INTERFACE) is back online.
Failback complete via mwan3.

$(get_system_info)"
                                send_notification "$main_title" "$main_message" 0
                            fi
                        fi
                    elif [ "${INTERFACE:-}" = "mob1s1a1" ] || [ "${INTERFACE:-}" = "mob1s2a1" ]; then
                        if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                            if check_rate_limit "connected_$INTERFACE"; then
                                main_title="📱 Mobile Failover Active"
                                main_message="Failover complete.
Traffic is now flowing over mobile interface ($INTERFACE).

$(get_system_info)"
                                send_notification "$main_title" "$main_message" 1
                            fi
                        fi
                    fi
                    ;;
            esac
            ;;
        test)
            # Test all notification types
            if [ "${NOTIFY_ON_CRITICAL:-1}" = "1" ]; then
                send_notification "[TEST] Critical Error" "This is a test critical error notification.
$(get_system_info)" 2
            fi
            if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ]; then
                send_notification "[TEST] Soft Failover" "This is a test soft failover notification.
$(get_system_info)" 1
            fi
            if [ "${NOTIFY_ON_HARD_FAIL:-1}" = "1" ]; then
                send_notification "[TEST] Hard Failover" "This is a test hard failover notification.
$(get_system_info)" 2
            fi
            if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ]; then
                send_notification "[TEST] Recovery" "This is a test recovery notification.
$(get_system_info)" 0
            fi
            if [ "${NOTIFY_ON_INFO:-0}" = "1" ]; then
                send_notification "[TEST] Info/Status" "This is a test info/status notification.
$(get_system_info)" -1
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
