#!/bin/sh

# ==============================================================================
# Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.4.12
# Source: https://github.com/markus-lassfolk/rutos-starlink-victron/
#
# This script proactively monitors the quality of a Starlink internet connection
# using its unofficial gRPC API. If quality degrades below defined thresholds
# (for latency, packet loss, or obstruction), it performs a "soft" failover
# by increasing the mwan3 metric of the Starlink interface.
#
# Enhanced features:
# - Centralized configuration management
# - Improved error handling and logging
# - Better state management
# - Health checks and diagnostics
# - Graceful degradation on errors
#
# ==============================================================================

set -eu

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034  # Color variables may not all be used in every script
# CRITICAL: Use RUTOS-compatible color detection

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    # shellcheck disable=SC2034
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    # shellcheck disable=SC2034  # Color variables may not all be used
    # shellcheck disable=SC2034
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# --- Configuration Loading ---
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Load placeholder utilities for graceful degradation
script_dir="$(dirname "$0")/../scripts"
if [ -f "$script_dir/placeholder-utils.sh" ]; then
    # shellcheck source=/dev/null
    . "$script_dir/placeholder-utils.sh"
else
    echo "Warning: placeholder-utils.sh not found. Pushover notifications may not work gracefully."
fi

# Set default values for variables that may not be in config
LOG_TAG="${LOG_TAG:-StarlinkMonitor}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LOG_DIR="${LOG_DIR:-/etc/starlink-logs}"

# Create necessary directories
mkdir -p "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

# --- Derived Configuration ---
STATE_FILE="${STATE_DIR}/starlink_monitor.state"
STABILITY_FILE="${STATE_DIR}/starlink_monitor.stability"
HEALTH_FILE="${STATE_DIR}/starlink_monitor.health"
LOCK_FILE="${STATE_DIR}/starlink_monitor.lock"

# --- Helper Functions ---

debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Standard logging functions for consistency with other scripts
log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

##
# log(level, message)
# Enhanced logging with severity levels. Logs to syslog, file, and optionally console.
log() {
    level="$1"
    message="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to syslog
    logger -t "$LOG_TAG" -p "daemon.$level" -- "$message"

    # Log to file with rotation
    log_file="${LOG_DIR}/starlink_monitor_$(date '+%Y-%m-%d').log"
    echo "$timestamp [$level] $message" >>"$log_file"

    # Console output for manual runs
    if [ -t 1 ]; then
        echo "[$level] $message"
    fi

    # Also output to stderr if DEBUG is enabled
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[%s] [%s] %s\n" "$LOG_TAG" "$level" "$message" >&2
    fi
}

##
# rotate_logs()
# Rotates log files, deleting logs older than retention period.
rotate_logs() {
    find "$LOG_DIR" -name 'starlink_monitor_*.log' -mtime +"$LOG_RETENTION_DAYS" -exec rm {} \; 2>/dev/null || true
}

##
# acquire_lock()
# Ensures only one instance runs at a time using a lock file. Removes stale lock if needed.
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log "warn" "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            log "info" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ >"$LOCK_FILE"
}

##
# release_lock()
# Removes the lock file to allow future runs.
release_lock() {
    rm -f "$LOCK_FILE"
}

##
# update_health_status(status, message)
# Writes health status, message, and timestamp to health file for external monitoring.
update_health_status() {
    status="$1"
    message="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >"$HEALTH_FILE" <<EOF
status=$status
message=$message
timestamp=$timestamp
last_check=$(date '+%s')
EOF
}

##
# call_starlink_api(method)
# Calls the Starlink gRPC API with retries and exponential backoff. Returns API response or fails after max retries.
call_starlink_api() {
    method="$1"
    retry_count=0
    max_retries=3
    delay=2

    while [ $retry_count -lt $max_retries ]; do
        if timeout "$API_TIMEOUT" "$GRPCURL_CMD" -plaintext -max-time "$API_TIMEOUT" -d "{\"$method\":{}}" "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null; then
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log "warn" "API call failed, retrying in ${delay}s (attempt $retry_count/$max_retries)"
            sleep $delay
            delay=$((delay * 2))
        fi
    done

    return 1
}

##
# cleanup()
# Releases lock and logs monitor stop on exit or signal.
cleanup() {
    release_lock
    log "info" "Monitor stopped"
}

# Set up signal handlers for cleanup on exit or interruption
trap cleanup EXIT INT TERM

# --- Main Logic ---

# Add test mode for troubleshooting
if [ "${TEST_MODE:-0}" = "1" ]; then
    debug_log "TEST MODE ENABLED: Running in test mode"
    DEBUG=1 # Force debug mode in test mode
    set -x  # Enable command tracing
    debug_log "TEST MODE: All commands will be traced"
fi

# Enhanced debug mode with detailed startup logging
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    debug_log "==================== STARLINK MONITOR DEBUG MODE ENABLED ===================="
    debug_log "Script version: $SCRIPT_VERSION"
    debug_log "Current working directory: $(pwd)"
    debug_log "Script path: $0"
    debug_log "Process ID: $$"
    debug_log "User: $(whoami 2>/dev/null || echo 'unknown')"
    debug_log "Arguments: $*"
    debug_log "Environment DEBUG: ${DEBUG:-0}"
    debug_log "Environment TEST_MODE: ${TEST_MODE:-0}"

    debug_log "CONFIGURATION PATHS:"
    debug_log "  CONFIG_FILE=${CONFIG_FILE:-not_set}"
    debug_log "  STATE_DIR=${STATE_DIR:-not_set}"
    debug_log "  LOG_DIR=${LOG_DIR:-not_set}"
    debug_log "  STATE_FILE=${STATE_FILE:-not_set}"
    debug_log "  STABILITY_FILE=${STABILITY_FILE:-not_set}"
    debug_log "  HEALTH_FILE=${HEALTH_FILE:-not_set}"
    debug_log "  LOCK_FILE=${LOCK_FILE:-not_set}"

    debug_log "CONFIGURATION VALUES:"
    debug_log "  STARLINK_IP=${STARLINK_IP:-not_set}"
    debug_log "  GRPCURL_CMD=${GRPCURL_CMD:-not_set}"
    debug_log "  JQ_CMD=${JQ_CMD:-not_set}"
    debug_log "  LOG_TAG=${LOG_TAG:-not_set}"
    debug_log "  PUSHOVER_TOKEN=$(printf "%.10s..." "${PUSHOVER_TOKEN:-not_set}")"
    debug_log "  PUSHOVER_USER=$(printf "%.10s..." "${PUSHOVER_USER:-not_set}")"
fi

##
# main()
# Main monitoring logic: rotates logs, acquires lock, gathers Starlink API data, analyzes quality, manages failover/failback, updates health, and notifies as needed.
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "starlink_monitor-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: starlink_monitor-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    debug_log "FUNCTION: main"
    debug_log "==================== STARLINK MONITOR START ===================="
    debug_log "Starting main monitoring function"
    log "info" "Starting Starlink monitor check"

    # Rotate logs and acquire lock
    debug_log "STEP: Rotating logs and acquiring lock"
    rotate_logs
    acquire_lock

    # Read current state from files and mwan3 config
    debug_log "STEP: Reading current state from files and mwan3 config"
    last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "up")                                    # up or down
    stability_count=$(cat "$STABILITY_FILE" 2>/dev/null || echo "0")                            # consecutive good checks
    current_metric=$(uci -q get mwan3."$MWAN_MEMBER".metric 2>/dev/null || echo "$METRIC_GOOD") # current routing metric

    debug_log "STATE VALUES:"
    debug_log "  last_state=$last_state (from $STATE_FILE)"
    debug_log "  stability_count=$stability_count (from $STABILITY_FILE)"
    debug_log "  current_metric=$current_metric (from mwan3.$MWAN_MEMBER.metric)"
    debug_log "  MWAN_MEMBER=${MWAN_MEMBER:-not_set}"
    debug_log "  METRIC_GOOD=${METRIC_GOOD:-not_set}"

    log "info" "Current state: $last_state, Stability: $stability_count, Metric: $current_metric"

    # --- Data Gathering ---
    debug_log "STEP: Gathering data from Starlink API"
    log "debug" "Gathering data from Starlink API"

    # Query Starlink API for current status and history (with retry)
    debug_log "API CALL: Calling get_status"
    status_data=$(call_starlink_api "get_status" | "$JQ_CMD" -r '.dishGetStatus // empty' 2>/dev/null)
    status_exit=$?
    debug_log "API RESULT: get_status exit code: $status_exit"
    debug_log "API RESULT: status_data length: ${#status_data}"

    debug_log "API CALL: Calling get_history"
    history_data=$(call_starlink_api "get_history" | "$JQ_CMD" -r '.dishGetHistory // empty' 2>/dev/null)
    history_exit=$?
    debug_log "API RESULT: get_history exit code: $history_exit"
    debug_log "API RESULT: history_data length: ${#history_data}"

    # Check if API calls were successful; if not, log and update health, but do not change state
    if [ -z "$status_data" ] || [ -z "$history_data" ]; then
        log "error" "Failed to retrieve data from Starlink API"
        debug_log "API ERROR: One or both API calls returned empty data"
        debug_log "API ERROR: status_data empty: $([ -z "$status_data" ] && echo 'yes' || echo 'no')"
        debug_log "API ERROR: history_data empty: $([ -z "$history_data" ] && echo 'yes' || echo 'no')"
        update_health_status "error" "API communication failed"

        # If we can't get data, maintain current state but log the issue
        if [ "$last_state" = "up" ]; then
            log "warn" "Cannot verify connection quality, maintaining current state"
        fi
        return 1
    fi

    # --- Data Processing ---
    # Extract metrics from API responses
    debug_log "STEP: Extracting metrics from API responses"
    debug_log "RAW API DATA: status_data length=${#status_data}, history_data length=${#history_data}"

    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.obstructionStats.fractionObstructed // 0' 2>/dev/null) # Fraction of time obstructed
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.popPingLatencyMs // 0' 2>/dev/null)                        # Latency in ms
    # shellcheck disable=SC1087  # This is a jq JSON path, not a shell array
    loss=$(echo "$history_data" | "$JQ_CMD" -r '.popPingDropRate[-1] // 0' 2>/dev/null) # Most recent packet loss

    debug_log "EXTRACTED RAW VALUES:"
    debug_log "  obstruction (raw)=$obstruction"
    debug_log "  latency (raw)=$latency"
    debug_log "  loss (raw)=$loss"

    # Show sample of recent loss data from history to verify we're getting real data
    if [ "${DEBUG:-0}" = "1" ]; then
        recent_loss_samples=$(echo "$history_data" | "$JQ_CMD" -r '.popPingDropRate[-5:] // []' 2>/dev/null | tr -d '[]," ')
        debug_log "RECENT LOSS SAMPLES (last 5): $recent_loss_samples"

        # Show some status fields to verify API connectivity
        uptime=$(echo "$status_data" | "$JQ_CMD" -r '.deviceState.uptimeS // "unknown"' 2>/dev/null)
        software_version=$(echo "$status_data" | "$JQ_CMD" -r '.softwareVersion // "unknown"' 2>/dev/null)
        debug_log "API VERIFICATION: uptime=${uptime}s, software_version=$software_version"
    fi

    # Validate extracted data; if missing, treat as error
    if [ -z "$obstruction" ] || [ -z "$latency" ] || [ -z "$loss" ]; then
        log "error" "Failed to parse API response data"
        update_health_status "error" "Data parsing failed"
        return 1
    fi

    # --- Quality Analysis ---
    # --- Quality Analysis ---
    # Convert latency to integer, check if metrics exceed thresholds
    latency_int=$(echo "$latency" | cut -d'.' -f1)
    is_loss_high=$(awk -v val="$loss" -v threshold="$PACKET_LOSS_THRESHOLD" 'BEGIN { print (val > threshold) }')
    is_obstructed=$(awk -v val="$obstruction" -v threshold="$OBSTRUCTION_THRESHOLD" 'BEGIN { print (val > threshold) }')
    is_latency_high=0

    # Validate latency is numeric and above threshold
    if [ "$latency_int" -gt 0 ] 2>/dev/null && [ "$latency_int" -gt "$LATENCY_THRESHOLD_MS" ]; then
        is_latency_high=1
    fi

    log "debug" "Metrics - Loss: $loss (threshold: $PACKET_LOSS_THRESHOLD, high: $is_loss_high), Obstruction: $obstruction (threshold: $OBSTRUCTION_THRESHOLD, high: $is_obstructed), Latency: ${latency_int}ms (threshold: ${LATENCY_THRESHOLD_MS}ms, high: $is_latency_high)"

    # Determine if quality is bad based on thresholds; build reason string for notifications
    quality_is_bad=false
    FAIL_REASON=""

    if [ "$is_loss_high" -eq 1 ] || [ "$is_obstructed" -eq 1 ] || [ "$is_latency_high" -eq 1 ]; then
        quality_is_bad=true

        # Build detailed reason string for notification/logging (use literal brackets, not arrays)
        [ "$is_loss_high" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[High Loss: ${loss}] "
        [ "$is_obstructed" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[Obstructed: ${obstruction}] "
        [ "$is_latency_high" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[High Latency: ${latency_int}ms] "
    fi

    # --- Decision Logic ---
    # --- Decision Logic ---
    if [ "$quality_is_bad" = true ]; then
        # If quality is bad, reset stability counter and perform soft failover if not already failed over
        echo "0" >"$STABILITY_FILE"

        if [ "$current_metric" -ne "$METRIC_BAD" ]; then
            log "warn" "Quality degraded below threshold: $FAIL_REASON"
            log "info" "Performing soft failover - setting metric to $METRIC_BAD"

            # Set metric to bad and restart mwan3 for failover
            if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_BAD" && uci commit mwan3; then
                if mwan3 restart; then
                    echo "down" >"$STATE_FILE"
                    update_health_status "degraded" "Soft failover active: $FAIL_REASON"

                    # Notify via external script if enabled
                    if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                        safe_notify "soft_failover" "$FAIL_REASON" || log "warn" "Notification failed"
                    fi

                    log "info" "Soft failover completed successfully"
                else
                    log "error" "Failed to restart mwan3 service"
                fi
            else
                log "error" "Failed to update UCI configuration"
            fi
        else
            log "debug" "Quality still bad, already in failover state"
        fi
    else
        # If quality is good, increment stability counter if recovering, else keep state up
        if [ "$last_state" != "up" ]; then
            # In recovery process: increment stability counter and check if enough for failback
            stability_count=$((stability_count + 1))
            echo "$stability_count" >"$STABILITY_FILE"

            log "info" "Quality recovered - stability check $stability_count/$STABILITY_CHECKS_REQUIRED"
            update_health_status "recovering" "Stability check $stability_count/$STABILITY_CHECKS_REQUIRED"

            # If enough consecutive good checks, perform soft failback
            if [ "$stability_count" -ge "$STABILITY_CHECKS_REQUIRED" ]; then
                log "info" "Stability threshold met - performing failback"

                if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_GOOD" && uci commit mwan3; then
                    if mwan3 restart; then
                        echo "up" >"$STATE_FILE"
                        echo "0" >"$STABILITY_FILE"
                        update_health_status "healthy" "Connection restored"

                        # Notify via external script if enabled
                        if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                            safe_notify "soft_recovery" || log "warn" "Notification failed"
                        fi

                        log "info" "Soft failback completed successfully"
                    else
                        log "error" "Failed to restart mwan3 service during failback"
                    fi
                else
                    log "error" "Failed to update UCI configuration during failback"
                fi
            fi
        else
            # Already in good state; reset stability counter and update health
            echo "0" >"$STABILITY_FILE"
            update_health_status "healthy" "Connection quality good"
            log "debug" "Connection quality remains good"
        fi
    fi

    log "info" "Monitor check completed"
    debug_log "STARLINK MONITOR: Completing successfully"
    debug_log "==================== STARLINK MONITOR COMPLETE ===================="
    debug_log "Final status: SUCCESS"
    debug_log "Script execution completed normally"
    debug_log "Exit code: 0"
    return 0
}

# Run main function
debug_log "==================== SCRIPT EXECUTION START ===================="
main "$@"
debug_log "==================== SCRIPT EXECUTION END ===================="
