#!/bin/sh

# ==============================================================================
# Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.0 (Enhanced Edition)
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

set -euo pipefail

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
STATE_FILE="${STATE_DIR}/starlink_monitor.state"
STABILITY_FILE="${STATE_DIR}/starlink_monitor.stability"
HEALTH_FILE="${STATE_DIR}/starlink_monitor.health"
LOCK_FILE="${STATE_DIR}/starlink_monitor.lock"

# --- Helper Functions ---

##
# log(level, message)
# Enhanced logging with severity levels. Logs to syslog, file, and optionally console.
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to syslog
    logger -t "$LOG_TAG" -p "daemon.$level" -- "$message"
    
    # Log to file with rotation
    local log_file="${LOG_DIR}/starlink_monitor_$(date '+%Y-%m-%d').log"
    echo "$timestamp [$level] $message" >> "$log_file"
    
    # Console output for manual runs
    if [ -t 1 ]; then
        echo "[$level] $message"
    fi
}

##
# rotate_logs()
# Rotates log files, deleting logs older than retention period.
rotate_logs() {
    find "$LOG_DIR" -name 'starlink_monitor_*.log' -mtime +$LOG_RETENTION_DAYS -exec rm {} \; 2>/dev/null || true
}

##
# acquire_lock()
# Ensures only one instance runs at a time using a lock file. Removes stale lock if needed.
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log "warn" "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            log "info" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
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
    local status="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$HEALTH_FILE" << EOF
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
    local method="$1"
    local retry_count=0
    local max_retries=3
    local delay=2
    
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

##
# main()
# Main monitoring logic: rotates logs, acquires lock, gathers Starlink API data, analyzes quality, manages failover/failback, updates health, and notifies as needed.
main() {
    log "info" "Starting Starlink monitor check"
    
    # Rotate logs and acquire lock
    rotate_logs
    acquire_lock
    
    # Read current state from files and mwan3 config
    last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "up")  # up or down
    stability_count=$(cat "$STABILITY_FILE" 2>/dev/null || echo "0")  # consecutive good checks
    current_metric=$(uci -q get mwan3."$MWAN_MEMBER".metric 2>/dev/null || echo "$METRIC_GOOD")  # current routing metric

    log "info" "Current state: $last_state, Stability: $stability_count, Metric: $current_metric"

    # --- Data Gathering ---
    log "debug" "Gathering data from Starlink API"
    
    # Query Starlink API for current status and history (with retry)
    status_data=$(call_starlink_api "get_status" | "$JQ_CMD" -r '.dishGetStatus // empty' 2>/dev/null)
    history_data=$(call_starlink_api "get_history" | "$JQ_CMD" -r '.dishGetHistory // empty' 2>/dev/null)

    # Check if API calls were successful; if not, log and update health, but do not change state
    if [ -z "$status_data" ] || [ -z "$history_data" ]; then
        log "error" "Failed to retrieve data from Starlink API"
        update_health_status "error" "API communication failed"

        # If we can't get data, maintain current state but log the issue
        if [ "$last_state" = "up" ]; then
            log "warn" "Cannot verify connection quality, maintaining current state"
        fi
        return 1
    fi
    
    # --- Data Processing ---
    # Extract metrics from API responses
    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.obstructionStats.fractionObstructed // 0' 2>/dev/null)  # Fraction of time obstructed
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.popPingLatencyMs // 0' 2>/dev/null)  # Latency in ms
    # shellcheck disable=SC1087  # This is a jq JSON path, not a shell array
    loss=$(echo "$history_data" | "$JQ_CMD" -r '.popPingDropRate[-1] // 0' 2>/dev/null)  # Most recent packet loss

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

        # Build detailed reason string for notification/logging
        [ "$is_loss_high" -eq 1 ] && FAIL_REASON="$FAIL_REASON[High Loss: ${loss}] "
        [ "$is_obstructed" -eq 1 ] && FAIL_REASON="$FAIL_REASON[Obstructed: ${obstruction}] "
        [ "$is_latency_high" -eq 1 ] && FAIL_REASON="$FAIL_REASON[High Latency: ${latency_int}ms] "
    fi
    
    # --- Decision Logic ---
    # --- Decision Logic ---
    if [ "$quality_is_bad" = true ]; then
        # If quality is bad, reset stability counter and perform soft failover if not already failed over
        echo "0" > "$STABILITY_FILE"

        if [ "$current_metric" -ne "$METRIC_BAD" ]; then
            log "warn" "Quality degraded below threshold: $FAIL_REASON"
            log "info" "Performing soft failover - setting metric to $METRIC_BAD"

            # Set metric to bad and restart mwan3 for failover
            if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_BAD" && uci commit mwan3; then
                if mwan3 restart; then
                    echo "down" > "$STATE_FILE"
                    update_health_status "degraded" "Soft failover active: $FAIL_REASON"

                    # Notify via external script if enabled
                    if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                        "$NOTIFIER_SCRIPT" "soft_failover" "$FAIL_REASON" || log "warn" "Notification failed"
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
            echo "$stability_count" > "$STABILITY_FILE"

            log "info" "Quality recovered - stability check $stability_count/$STABILITY_CHECKS_REQUIRED"
            update_health_status "recovering" "Stability check $stability_count/$STABILITY_CHECKS_REQUIRED"

            # If enough consecutive good checks, perform soft failback
            if [ "$stability_count" -ge "$STABILITY_CHECKS_REQUIRED" ]; then
                log "info" "Stability threshold met - performing failback"

                if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_GOOD" && uci commit mwan3; then
                    if mwan3 restart; then
                        echo "up" > "$STATE_FILE"
                        echo "0" > "$STABILITY_FILE"
                        update_health_status "healthy" "Connection restored"

                        # Notify via external script if enabled
                        if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                            "$NOTIFIER_SCRIPT" "soft_recovery" || log "warn" "Notification failed"
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
            echo "0" > "$STABILITY_FILE"
            update_health_status "healthy" "Connection quality good"
            log "debug" "Connection quality remains good"
        fi
    fi
    
    log "info" "Monitor check completed"
    return 0
}

# Run main function
main
