#!/bin/sh
# ==============================================================================
# RUTOS Cron Monitor Wrapper - Universal Cron Job Error Monitoring
#
# Version: 2.8.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script wraps around any cron job to provide comprehensive error monitoring,
# logging, and webhook notifications when failures occur.
#
# Usage:
#   # Wrap any cron job like this:
#   */5 * * * * /root/starlink-monitor/scripts/cron-monitor-wrapper-rutos.sh /path/to/your/script.sh
#
#   # Or with custom webhook:
#   */5 * * * * WEBHOOK_URL="https://your.webhook.url" /root/starlink-monitor/scripts/cron-monitor-wrapper-rutos.sh /path/to/your/script.sh
#
# Features:
# - Captures stdout/stderr from wrapped scripts
# - Detects exit codes and runtime errors
# - Logs all executions with timestamps
# - Sends webhook notifications on failures
# - Rate limiting to prevent notification spam
# - Timeout protection for hung scripts
# - Integration with existing Pushover notifications
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
if ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # Fallback if library not available
    printf "[ERROR] RUTOS library not found - using minimal fallback\n" >&2
    log_error() { printf "[ERROR] %s\n" "$1" >&2; }
    log_info() { printf "[INFO] %s\n" "$1"; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$1" >&2; }
    safe_execute() { [ "${DRY_RUN:-0}" = "0" ] && eval "$1" || printf "[DRY_RUN] %s\n" "$1" >&2; }
fi

# Initialize script with library features if available
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "cron-monitor-wrapper-rutos.sh" "$SCRIPT_VERSION"
fi

# --- Configuration ---
MONITOR_LOG_DIR="${MONITOR_LOG_DIR:-/var/log/cron-monitor}"
MONITOR_STATE_DIR="${MONITOR_STATE_DIR:-/tmp/cron-monitor}"
WEBHOOK_TIMEOUT="${WEBHOOK_TIMEOUT:-10}"
SCRIPT_TIMEOUT="${SCRIPT_TIMEOUT:-300}"        # 5 minutes default timeout
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-3600}" # 1 hour rate limiting window
MAX_NOTIFICATIONS_PER_HOUR="${MAX_NOTIFICATIONS_PER_HOUR:-5}"

# Load main configuration if available
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Webhook configuration (can be overridden via environment)
WEBHOOK_URL="${WEBHOOK_URL:-${CRON_MONITOR_WEBHOOK_URL:-}}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
PUSHOVER_USER="${PUSHOVER_USER:-}"

# Create necessary directories
safe_execute "mkdir -p '$MONITOR_LOG_DIR' '$MONITOR_STATE_DIR'"

# --- Helper Functions ---

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_script_name() {
    basename "$1" .sh
}

get_rate_limit_file() {
    script_name="$(get_script_name "$1")"
    echo "$MONITOR_STATE_DIR/rate_limit_${script_name}"
}

check_rate_limit() {
    script_path="$1"
    rate_file="$(get_rate_limit_file "$script_path")"
    current_time="$(date +%s)"

    if [ -f "$rate_file" ]; then
        notifications_count=0
        cutoff_time=$((current_time - RATE_LIMIT_WINDOW))

        # Count notifications in the last hour
        while IFS= read -r timestamp || [ -n "$timestamp" ]; do
            if [ "$timestamp" -gt "$cutoff_time" ]; then
                notifications_count=$((notifications_count + 1))
            fi
        done <"$rate_file"

        # Clean old entries
        temp_file="$rate_file.tmp"
        while IFS= read -r timestamp || [ -n "$timestamp" ]; do
            if [ "$timestamp" -gt "$cutoff_time" ]; then
                echo "$timestamp" >>"$temp_file"
            fi
        done <"$rate_file"

        if [ -f "$temp_file" ]; then
            mv "$temp_file" "$rate_file"
        else
            rm -f "$rate_file"
        fi

        if [ "$notifications_count" -ge "$MAX_NOTIFICATIONS_PER_HOUR" ]; then
            log_debug "Rate limit exceeded for $(get_script_name "$script_path"): $notifications_count notifications in last hour"
            return 1
        fi
    fi

    # Record this notification
    echo "$current_time" >>"$rate_file"
    return 0
}

send_webhook_notification() {
    webhook_url="$1"
    script_path="$2"
    exit_code="$3"
    error_output="$4"
    execution_time="$5"

    if [ -z "$webhook_url" ]; then
        log_debug "No webhook URL configured, skipping webhook notification"
        return 0
    fi

    script_name="$(get_script_name "$script_path")"
    timestamp="$(get_timestamp)"
    hostname="$(hostname 2>/dev/null || echo 'unknown')"

    # Create JSON payload
    json_payload=$(
        cat <<EOF
{
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "script": "$script_name",
    "script_path": "$script_path",
    "exit_code": $exit_code,
    "execution_time": "$execution_time",
    "error_output": $(echo "$error_output" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'),
    "severity": "$([ "$exit_code" -eq 0 ] && echo "info" || echo "error")",
    "source": "rutos-cron-monitor"
}
EOF
    )

    log_debug "Sending webhook notification to: $webhook_url"

    if command -v curl >/dev/null 2>&1; then
        safe_execute "curl -X POST '$webhook_url' \
            -H 'Content-Type: application/json' \
            -d '$json_payload' \
            --connect-timeout '$WEBHOOK_TIMEOUT' \
            --max-time '$WEBHOOK_TIMEOUT' \
            --silent --show-error" || {
            log_error "Failed to send webhook notification via curl"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        temp_file="/tmp/webhook_payload_$$"
        echo "$json_payload" >"$temp_file"
        safe_execute "wget -qO- --post-file='$temp_file' \
            --header='Content-Type: application/json' \
            --timeout='$WEBHOOK_TIMEOUT' \
            '$webhook_url'" || {
            log_error "Failed to send webhook notification via wget"
            rm -f "$temp_file"
            return 1
        }
        rm -f "$temp_file"
    else
        log_error "Neither curl nor wget available for webhook notifications"
        return 1
    fi

    log_info "Webhook notification sent successfully for $script_name"
    return 0
}

send_pushover_notification() {
    script_path="$1"
    exit_code="$2"
    error_output="$3"
    execution_time="$4"

    if [ -z "$PUSHOVER_TOKEN" ] || [ -z "$PUSHOVER_USER" ]; then
        log_debug "Pushover not configured, skipping Pushover notification"
        return 0
    fi

    script_name="$(get_script_name "$script_path")"
    hostname="$(hostname 2>/dev/null || echo 'unknown')"

    if [ "$exit_code" -eq 0 ]; then
        title="✅ Cron Success: $script_name"
        priority="0"
        message="Script completed successfully on $hostname in ${execution_time}s"
    else
        title="❌ Cron Failure: $script_name"
        priority="1" # High priority for failures
        message="Script failed on $hostname with exit code $exit_code after ${execution_time}s.

Error output:
$error_output"
    fi

    log_debug "Sending Pushover notification for $script_name"

    # Use existing Pushover notification system if available
    if [ -f "/etc/hotplug.d/iface/99-pushover_notify-rutos.sh" ]; then
        # Use the existing notification system
        safe_execute "echo 'CRON_MONITOR_NOTIFICATION' | /etc/hotplug.d/iface/99-pushover_notify-rutos.sh" || {
            log_error "Failed to send Pushover notification via hotplug script"
            return 1
        }
    else
        # Direct Pushover API call
        if command -v curl >/dev/null 2>&1; then
            safe_execute "curl -s -F 'token=$PUSHOVER_TOKEN' \
                -F 'user=$PUSHOVER_USER' \
                -F 'title=$title' \
                -F 'message=$message' \
                -F 'priority=$priority' \
                https://api.pushover.net/1/messages.json" || {
                log_error "Failed to send Pushover notification via curl"
                return 1
            }
        else
            log_error "curl not available for Pushover notifications"
            return 1
        fi
    fi

    log_info "Pushover notification sent successfully for $script_name"
    return 0
}

log_execution() {
    script_path="$1"
    exit_code="$2"
    stdout_output="$3"
    stderr_output="$4"
    execution_time="$5"

    script_name="$(get_script_name "$script_path")"
    log_file="$MONITOR_LOG_DIR/${script_name}.log"
    timestamp="$(get_timestamp)"

    # Create comprehensive log entry
    {
        echo "==================== EXECUTION LOG ===================="
        echo "Timestamp: $timestamp"
        echo "Script: $script_path"
        echo "Exit Code: $exit_code"
        echo "Execution Time: ${execution_time}s"
        echo "PID: $$"
        echo ""
        echo "--- STDOUT ---"
        echo "$stdout_output"
        echo ""
        echo "--- STDERR ---"
        echo "$stderr_output"
        echo "==================== END LOG ===================="
        echo ""
    } >>"$log_file"

    log_debug "Execution logged to $log_file"
}

# --- Main Execution ---

main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "cron-monitor-wrapper-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: cron-monitor-wrapper-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    if [ $# -eq 0 ]; then
        log_error "Usage: $0 <script_to_execute> [arguments...]"
        log_error "Example: $0 /root/starlink-monitor/starlink_monitor-rutos.sh"
        exit 1
    fi

    script_to_execute="$1"
    shift # Remove script path from arguments

    if [ ! -f "$script_to_execute" ]; then
        log_error "Script not found: $script_to_execute"
        exit 1
    fi

    if [ ! -x "$script_to_execute" ]; then
        log_error "Script not executable: $script_to_execute"
        exit 1
    fi

    script_name="$(get_script_name "$script_to_execute")"
    log_info "Starting monitored execution of $script_name"

    # Create temporary files for capturing output
    stdout_file="/tmp/cron_stdout_$$"
    stderr_file="/tmp/cron_stderr_$$"

    # Execute the script with timeout and capture output
    start_time="$(date +%s)"

    if command -v timeout >/dev/null 2>&1; then
        # Use timeout command if available
        timeout "$SCRIPT_TIMEOUT" "$script_to_execute" "$@" >"$stdout_file" 2>"$stderr_file"
        exit_code=$?
    else
        # Manual timeout implementation for busybox
        "$script_to_execute" "$@" >"$stdout_file" 2>"$stderr_file" &
        script_pid=$!

        # Wait for script to complete or timeout
        count=0
        while [ $count -lt "$SCRIPT_TIMEOUT" ]; do
            if ! kill -0 "$script_pid" 2>/dev/null; then
                # Script completed
                wait "$script_pid"
                exit_code=$?
                break
            fi
            sleep 1
            count=$((count + 1))
        done

        # Check if we timed out
        if [ $count -ge "$SCRIPT_TIMEOUT" ]; then
            log_error "Script timed out after ${SCRIPT_TIMEOUT}s, killing process"
            kill -TERM "$script_pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$script_pid" 2>/dev/null || true
            exit_code=124 # Standard timeout exit code
            echo "Script timed out after ${SCRIPT_TIMEOUT} seconds" >>"$stderr_file"
        fi
    fi

    end_time="$(date +%s)"
    execution_time=$((end_time - start_time))

    # Read captured output
    stdout_output="$(cat "$stdout_file" 2>/dev/null || echo "")"
    stderr_output="$(cat "$stderr_file" 2>/dev/null || echo "")"

    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file"

    # Log the execution
    log_execution "$script_to_execute" "$exit_code" "$stdout_output" "$stderr_output" "$execution_time"

    # Send notifications on failure (or success if configured)
    if [ "$exit_code" -ne 0 ] || [ "${NOTIFY_ON_SUCCESS:-0}" = "1" ]; then
        error_output="$stderr_output"
        if [ -z "$error_output" ] && [ "$exit_code" -ne 0 ]; then
            error_output="Script exited with code $exit_code (no error output captured)"
        fi

        # Check rate limiting
        if check_rate_limit "$script_to_execute"; then
            # Send webhook notification
            if [ -n "$WEBHOOK_URL" ]; then
                send_webhook_notification "$WEBHOOK_URL" "$script_to_execute" "$exit_code" "$error_output" "$execution_time"
            fi

            # Send Pushover notification (only on failures by default)
            if [ "$exit_code" -ne 0 ] || [ "${PUSHOVER_ON_SUCCESS:-0}" = "1" ]; then
                send_pushover_notification "$script_to_execute" "$exit_code" "$error_output" "$execution_time"
            fi
        else
            log_info "Skipping notifications due to rate limiting for $script_name"
        fi
    fi

    if [ "$exit_code" -eq 0 ]; then
        log_info "Script $script_name completed successfully in ${execution_time}s"
    else
        log_error "Script $script_name failed with exit code $exit_code after ${execution_time}s"
    fi

    # Forward the original exit code
    exit "$exit_code"
}

# Execute main function with all arguments
main "$@"
