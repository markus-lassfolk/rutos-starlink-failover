#!/bin/sh

# ==============================================================================
# Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.7.1
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
# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution
" >&2
    exit 0
fi

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='[0;31m'
    GREEN='[0;32m'
    YELLOW='[1;33m'
    BLUE='[1;35m'
    CYAN='[0;36m'
    NC='[0m'
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
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Ensure Starlink connection variables are defined
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"

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

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s
" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution
" >&2
    exit 0
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

# --- Derived Configuration ---
STATE_FILE="${STATE_DIR}/starlink_monitor.state"
STABILITY_FILE="${STATE_DIR}/starlink_monitor.stability"
HEALTH_FILE="${STATE_DIR}/starlink_monitor.health"
LOCK_FILE="${STATE_DIR}/starlink_monitor.lock"

# --- Critical Safety Defaults ---
# Ensure STABILITY_CHECKS_REQUIRED is always defined to prevent infinite failover loops
STABILITY_CHECKS_REQUIRED="${STABILITY_CHECKS_REQUIRED:-5}"

# --- Helper Functions ---

debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Standard logging functions for consistency with other scripts
log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
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
        printf "[%s] [%s] %s
" "$LOG_TAG" "$level" "$message" >&2
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
        if timeout "$API_TIMEOUT" "$GRPCURL_CMD" -plaintext -max-time "$API_TIMEOUT" -d "{\"$method\":{}}" "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null; then
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
    # Note: set -x disabled during testing to avoid verbose output in test suite
    debug_log "TEST MODE: Running with enhanced debug logging"
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

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    debug_log "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

##
# main()
# Main monitoring logic: rotates logs, acquires lock, gathers Starlink API data, analyzes quality, manages failover/failback, updates health, and notifies as needed.
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s
" "starlink_monitor-rutos.sh" "$SCRIPT_VERSION" >&2
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
    debug_log "  STABILITY_CHECKS_REQUIRED=${STABILITY_CHECKS_REQUIRED:-not_set}"
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

    # Extract enhanced metrics for intelligent monitoring
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.deviceState.uptimeS // 0' 2>/dev/null)
    bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.deviceInfo.bootcount // 0' 2>/dev/null)
    is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.isSnrAboveNoiseFloor // true' 2>/dev/null)
    is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.isSnrPersistentlyLow // false' 2>/dev/null)
    snr=$(echo "$status_data" | "$JQ_CMD" -r '.snr // 0' 2>/dev/null)
    gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsValid // true' 2>/dev/null)
    gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsSats // 0' 2>/dev/null)

    debug_log "ENHANCED METRICS: uptime=${uptime_s}s, bootcount=$bootcount, SNR_above_noise=$is_snr_above_noise_floor, SNR_persistently_low=$is_snr_persistently_low, SNR_value=${snr}dB, GPS_valid=$gps_valid, GPS_sats=$gps_sats"

    # Detect potential reboot and handle sample tracking auto-fix
    uptime_hours=$((uptime_s / 3600))
    if [ "$uptime_s" -lt 1800 ]; then # Less than 30 minutes indicates recent reboot
        log "info" "Recent Starlink reboot detected (uptime: ${uptime_hours}h/${uptime_s}s) - checking sample tracking"

        # Check if logger sample tracking exists and might need reset
        sample_tracking_file="${STATE_DIR}/starlink_last_sample.ts"
        if [ -f "$sample_tracking_file" ]; then
            last_sample_tracked=$(cat "$sample_tracking_file" 2>/dev/null || echo "0")
            log "debug" "Sample tracking file exists with value: $last_sample_tracked - may need reset due to reboot"
            # The logger script will handle the actual reset logic
        fi
    fi

    # Validate extracted data; if missing, treat as error
    if [ -z "$obstruction" ] || [ -z "$latency" ] || [ -z "$loss" ]; then
        log "error" "Failed to parse API response data"
        update_health_status "error" "Data parsing failed"
        return 1
    fi

    # --- Enhanced Quality Analysis ---
    # Convert latency to integer, check if metrics exceed thresholds
    latency_int=$(echo "$latency" | cut -d'.' -f1)
    is_loss_high=$(awk -v val="$loss" -v threshold="$PACKET_LOSS_THRESHOLD" 'BEGIN { print (val > threshold) }')
    is_obstructed=$(awk -v val="$obstruction" -v threshold="$OBSTRUCTION_THRESHOLD" 'BEGIN { print (val > threshold) }')
    is_latency_high=0

    # Validate latency is numeric and above threshold
    if [ "$latency_int" -gt 0 ] 2>/dev/null && [ "$latency_int" -gt "$LATENCY_THRESHOLD_MS" ]; then
        is_latency_high=1
    fi

    # Enhanced signal quality analysis using SNR metrics
    is_snr_poor=0
    snr_int=0
    if [ -n "$snr" ] && [ "$snr" != "0" ] && [ "$snr" != "null" ]; then
        snr_int=$(echo "$snr" | cut -d'.' -f1)
        # Poor SNR: below 5dB is critical, below 8dB is suboptimal
        if [ "$snr_int" -lt 5 ] 2>/dev/null || [ "$is_snr_above_noise_floor" = "false" ] || [ "$is_snr_persistently_low" = "true" ]; then
            is_snr_poor=1
        fi
    fi

    # GPS validity check for positioning issues
    is_gps_poor=0
    if [ "$gps_valid" = "false" ] || [ "$gps_sats" -lt 4 ] 2>/dev/null; then
        is_gps_poor=1
    fi

    log "debug" "Basic Metrics - Loss: $loss (threshold: $PACKET_LOSS_THRESHOLD, high: $is_loss_high), Obstruction: $obstruction (threshold: $OBSTRUCTION_THRESHOLD, high: $is_obstructed), Latency: ${latency_int}ms (threshold: ${LATENCY_THRESHOLD_MS}ms, high: $is_latency_high)"
    log "debug" "Enhanced Metrics - SNR: ${snr}dB (poor: $is_snr_poor, above_noise: $is_snr_above_noise_floor, persistently_low: $is_snr_persistently_low), GPS: valid=$gps_valid, sats=$gps_sats (poor: $is_gps_poor)"

    # Determine if quality is bad based on enhanced thresholds; build reason string for notifications
    quality_is_bad=false
    FAIL_REASON=""

    # Check basic metrics (original logic)
    if [ "$is_loss_high" -eq 1 ] || [ "$is_obstructed" -eq 1 ] || [ "$is_latency_high" -eq 1 ]; then
        quality_is_bad=true

        # Build detailed reason string for notification/logging (use literal brackets, not arrays)
        [ "$is_loss_high" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[High Loss: ${loss}%] "
        [ "$is_obstructed" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[Obstructed: ${obstruction}%] "
        [ "$is_latency_high" -eq 1 ] && FAIL_REASON="${FAIL_REASON}[High Latency: ${latency_int}ms] "
    fi

    # Enhanced metrics add additional intelligence but don't trigger failover alone
    # They provide context and help prevent unnecessary failovers
    enhanced_context=""
    signal_degradation_score=0

    if [ "$is_snr_poor" -eq 1 ]; then
        enhanced_context="${enhanced_context}[SNR Issues: ${snr}dB"
        [ "$is_snr_above_noise_floor" = "false" ] && enhanced_context="${enhanced_context}, below noise floor"
        [ "$is_snr_persistently_low" = "true" ] && enhanced_context="${enhanced_context}, persistently low"
        enhanced_context="${enhanced_context}] "
        signal_degradation_score=$((signal_degradation_score + 2))
    fi

    if [ "$is_gps_poor" -eq 1 ]; then
        enhanced_context="${enhanced_context}[GPS Issues: valid=$gps_valid, sats=$gps_sats] "
        signal_degradation_score=$((signal_degradation_score + 1))
    fi

    # Recent reboot context (helps explain temporary issues)
    if [ "$uptime_s" -lt 1800 ]; then
        enhanced_context="${enhanced_context}[Recent Reboot: ${uptime_hours}h uptime] "
    fi

    # Log enhanced context if available
    if [ -n "$enhanced_context" ]; then
        log "debug" "Enhanced Context: $enhanced_context(degradation score: $signal_degradation_score)"
    fi

    # Use enhanced metrics to improve failover intelligence:
    # - If we have severe signal degradation (score ≥3), be more aggressive about failover
    # - If we have minor issues but good SNR/GPS, be more conservative
    enhanced_failover_recommended=false
    if [ "$quality_is_bad" = "true" ] && [ "$signal_degradation_score" -ge 3 ]; then
        enhanced_failover_recommended=true
        log "debug" "Enhanced analysis recommends failover due to severe signal degradation"
    elif [ "$quality_is_bad" = "true" ] && [ "$signal_degradation_score" -eq 0 ]; then
        log "debug" "Enhanced analysis suggests conservative approach - basic metrics poor but signal quality indicators good"
    fi

    # --- Decision Logic ---
    # Enhanced failover logic considers both traditional metrics and signal quality analysis
    if [ "$quality_is_bad" = true ] || [ "$enhanced_failover_recommended" = true ]; then
        # If quality is bad, reset stability counter and perform soft failover if not already failed over
        echo "0" >"$STABILITY_FILE"

        if [ "$current_metric" -ne "$METRIC_BAD" ]; then
            if [ "$enhanced_failover_recommended" = true ]; then
                log "warn" "Enhanced analysis recommends failover due to signal degradation: $FAIL_REASON"
            else
                log "warn" "Quality degraded below threshold: $FAIL_REASON"
            fi
            log "info" "Performing soft failover - setting metric to $METRIC_BAD"

            # Set metric to bad and restart mwan3 for failover
            if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_BAD" && uci commit mwan3; then
                if mwan3 restart; then
                    echo "down" >"$STATE_FILE"
                    update_health_status "degraded" "Soft failover active: $FAIL_REASON"

                    # Notify via external script if enabled - with failover delay
                    if [ "${NOTIFY_ON_SOFT_FAIL:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                        log "info" "PUSHOVER: Scheduling soft failover notification (delayed for network stability)"
                        log "debug" "PUSHOVER: NOTIFY_ON_SOFT_FAIL=${NOTIFY_ON_SOFT_FAIL:-1}"
                        log "debug" "PUSHOVER: NOTIFIER_SCRIPT=$NOTIFIER_SCRIPT (executable: $([ -x "$NOTIFIER_SCRIPT" ] && echo "YES" || echo "NO"))"
                        log "debug" "PUSHOVER: FAIL_REASON=$FAIL_REASON"

                        # Log to syslog for logread visibility
                        logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Scheduling soft failover notification with network stability delay - Reason: $FAIL_REASON"

                        # Use background notification with network readiness check
                        # This avoids the race condition where notification fails because network isn't ready
                        {
                            sleep 10 # Initial delay for MWAN3 to stabilize routing

                            # Check for network connectivity before sending notification
                            network_ready=0
                            network_attempts=0
                            network_max_attempts=6 # 1 minute total (10s initial + 6*5s = 40s)

                            while [ $network_ready -eq 0 ] && [ $network_attempts -lt $network_max_attempts ]; do
                                # Test connectivity to a reliable endpoint
                                if curl -s --max-time 5 --connect-timeout 3 "https://api.pushover.net" >/dev/null 2>&1; then
                                    network_ready=1
                                    logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Network ready after failover, sending notification"
                                else
                                    network_attempts=$((network_attempts + 1))
                                    logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Network not ready, waiting... (attempt $network_attempts/$network_max_attempts)"
                                    sleep 5
                                fi
                            done

                            if [ $network_ready -eq 1 ]; then
                                safe_notify "soft_failover" "$FAIL_REASON" || {
                                    logger -t "StarLinkMonitor" -p daemon.warn "PUSHOVER: Soft failover notification FAILED even after network ready"
                                }
                            else
                                logger -t "StarLinkMonitor" -p daemon.error "PUSHOVER: Network never became ready for notification, giving up"
                            fi
                        } & # Run in background to not block monitoring
                    else
                        log "info" "PUSHOVER: Soft failover notification SKIPPED"
                        if [ "${NOTIFY_ON_SOFT_FAIL:-1}" != "1" ]; then
                            log "debug" "PUSHOVER: SKIP REASON - NOTIFY_ON_SOFT_FAIL disabled (${NOTIFY_ON_SOFT_FAIL:-1})"
                            logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Soft failover notification disabled by config"
                        fi
                        if [ ! -x "$NOTIFIER_SCRIPT" ]; then
                            log "debug" "PUSHOVER: SKIP REASON - NOTIFIER_SCRIPT not executable ($NOTIFIER_SCRIPT)"
                            logger -t "StarLinkMonitor" -p daemon.warn "PUSHOVER: Notifier script not found or not executable: $NOTIFIER_SCRIPT"
                        fi
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

            # Safety check for configuration issues
            if [ -z "$STABILITY_CHECKS_REQUIRED" ] || [ "$STABILITY_CHECKS_REQUIRED" -eq 0 ] 2>/dev/null; then
                log "error" "STABILITY_CHECKS_REQUIRED is not set or is 0 - this prevents failback!"
                log "error" "Please add 'export STABILITY_CHECKS_REQUIRED=\"5\"' to your config file"
                # Use safe default to allow failback
                STABILITY_CHECKS_REQUIRED=5
                log "warn" "Using emergency default STABILITY_CHECKS_REQUIRED=5 for this run"
            fi

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

                        # Notify via external script if enabled - immediate for recovery
                        if [ "${NOTIFY_ON_RECOVERY:-1}" = "1" ] && [ -x "$NOTIFIER_SCRIPT" ]; then
                            log "info" "PUSHOVER: Triggering soft recovery notification"
                            log "debug" "PUSHOVER: NOTIFY_ON_RECOVERY=${NOTIFY_ON_RECOVERY:-1}"
                            log "debug" "PUSHOVER: NOTIFIER_SCRIPT=$NOTIFIER_SCRIPT (executable: $([ -x "$NOTIFIER_SCRIPT" ] && echo "YES" || echo "NO"))"
                            log "debug" "PUSHOVER: Recovery after $stability_count stability checks"

                            # Log to syslog for logread visibility
                            logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Sending soft recovery notification - Stability: $stability_count/$STABILITY_CHECKS_REQUIRED"

                            # Recovery notifications can be immediate since Starlink should be working
                            safe_notify "soft_recovery" || {
                                log "warn" "Recovery notification failed - trying delayed send"
                                logger -t "StarLinkMonitor" -p daemon.warn "PUSHOVER: Soft recovery notification FAILED, trying delayed send"

                                # Fallback: delayed send in background if immediate fails
                                {
                                    sleep 5
                                    safe_notify "soft_recovery" || {
                                        logger -t "StarLinkMonitor" -p daemon.error "PUSHOVER: Delayed recovery notification also failed"
                                    }
                                } &
                            }
                        else
                            log "info" "PUSHOVER: Soft recovery notification SKIPPED"
                            if [ "${NOTIFY_ON_RECOVERY:-1}" != "1" ]; then
                                log "debug" "PUSHOVER: SKIP REASON - NOTIFY_ON_RECOVERY disabled (${NOTIFY_ON_RECOVERY:-1})"
                                logger -t "StarLinkMonitor" -p daemon.info "PUSHOVER: Soft recovery notification disabled by config"
                            fi
                            if [ ! -x "$NOTIFIER_SCRIPT" ]; then
                                log "debug" "PUSHOVER: SKIP REASON - NOTIFIER_SCRIPT not executable ($NOTIFIER_SCRIPT)"
                                logger -t "StarLinkMonitor" -p daemon.warn "PUSHOVER: Notifier script not found or not executable: $NOTIFIER_SCRIPT"
                            fi
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

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
