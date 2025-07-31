#!/bin/sh

# ==============================================================================
# Starlink Performance Data Logger for OpenWrt/RUTOS
#
# Version: 2.8.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-victron/
#
# Starlink Logger - Enhanced CSV Logging for RUTOS
# This script runs periodically via cron to gather real-time performance data
# from a Starlink dish. It logs latency, packet loss, and obstruction data
# to a CSV file for later analysis.
#
# The primary goal of this script is to help users make data-driven decisions
# when setting the thresholds for the proactive failover script. By analyzing
# the CSV output in a tool like Excel, users can identify normal performance
# ranges and spot the peaks that indicate a genuine problem.
#
# This script is designed to be stateful, meaning it keeps track of the last
# data point it logged and will only append new data on each run, preventing
# duplicate entries.
#
# ==============================================================================

# Exit on first error, undefined variable, or pipe failure for script robustness.
set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Use version for validation
echo "$(basename "$0") v$SCRIPT_VERSION" >/dev/null 2>&1 || true

# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# --- User Configuration ---

# Set default installation directory if not already set
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"

# Load configuration from config file if available
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Debug logging function (defined early for use throughout script)
debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Load placeholder utilities for graceful degradation and notifications
script_dir="$(dirname "$0")/../scripts"
if [ -f "$script_dir/placeholder-utils.sh" ]; then
    # shellcheck source=/dev/null
    . "$script_dir/placeholder-utils.sh"
    debug_log "UTILITY: Loaded placeholder-utils.sh for notifications"
else
    debug_log "WARNING: placeholder-utils.sh not found. Pushover notifications may not work gracefully."
fi

# Set defaults for variables that may not be in config
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
LOG_TAG="${LOG_TAG:-StarlinkLogger}"
OUTPUT_CSV="${OUTPUT_CSV:-/root/starlink_performance_log.csv}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"

# Binary paths - use installation directory (override any config values)
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

# Create necessary directories
mkdir -p "$STATE_DIR" "$(dirname "$OUTPUT_CSV")" 2>/dev/null || true

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        printf "[DRY-RUN] Would execute: %s\n" "$description" >&2
        printf "[DRY-RUN] Command: %s\n" "$cmd" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] Executing: %s\n" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# --- System Configuration (Advanced) ---

# Location of binaries. Assumes they are in the system's PATH.
# If you placed them in /root/, change these to /root/grpcurl and /root/jq.
# Binary commands are now properly configured above from config file or defaults
# GRPCURL_CMD and JQ_CMD are set with full paths during config loading

# --- Helper Functions ---
log() {
    # Use -- to prevent messages starting with - from being treated as options
    logger -t "$LOG_TAG" -- "$1"
    # Also output to stderr if DEBUG is enabled
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[%s] %s\n" "$LOG_TAG" "$1" >&2
    fi
}

# Enhanced error handling with detailed logging
safe_exec() {
    cmd="$1"
    description="$2"

    debug_log "EXECUTING: $cmd"
    debug_log "DESCRIPTION: $description"

    # Execute command and capture both stdout and stderr
    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show all output
        eval "$cmd"
        exit_code=$?
        debug_log "COMMAND EXIT CODE: $exit_code"
        return $exit_code
    else
        # In normal mode, suppress output but capture errors
        eval "$cmd" 2>/tmp/logger_error.log
        exit_code=$?
        if [ $exit_code -ne 0 ] && [ -f /tmp/logger_error.log ]; then
            log "ERROR in $description: $(cat /tmp/logger_error.log)"
            rm -f /tmp/logger_error.log
        fi
        return $exit_code
    fi
}

# --- Main Script ---

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
    debug_log "==================== STARLINK LOGGER DEBUG MODE ENABLED ===================="
    debug_log "Script version: $SCRIPT_VERSION"
    debug_log "Current working directory: $(pwd)"
    debug_log "Script path: $0"
    debug_log "Process ID: $$"
    debug_log "User: $(whoami 2>/dev/null || echo 'unknown')"
    debug_log "Arguments: $*"
    debug_log "Environment DEBUG: ${DEBUG:-0}"
    debug_log "Environment TEST_MODE: ${TEST_MODE:-0}"

    debug_log "CONFIGURATION VALUES:"
    debug_log "  STARLINK_IP=$STARLINK_IP"
    debug_log "  OUTPUT_CSV=$OUTPUT_CSV"
    debug_log "  LAST_SAMPLE_FILE=$LAST_SAMPLE_FILE"
    debug_log "  GRPCURL_CMD=$GRPCURL_CMD"
    debug_log "  JQ_CMD=$JQ_CMD"
    debug_log "  LOG_TAG=$LOG_TAG"
fi

debug_log "==================== STARLINK LOGGER START ===================="
debug_log "Starting data logging run"
log "--- Starting data logging run ---"

# --- Performance Monitoring Setup ---
# Record start time for execution monitoring
script_start_time=$(date +%s)
debug_log "PERFORMANCE: Script started at epoch $script_start_time"

# Performance thresholds (configurable)
MAX_EXECUTION_TIME_SECONDS="${MAX_EXECUTION_TIME_SECONDS:-60}"   # Maximum acceptable script runtime
MIN_SAMPLES_PER_SECOND="${MIN_SAMPLES_PER_SECOND:-3}"            # Minimum acceptable processing rate (only checked if struggling)
PERFORMANCE_ALERT_THRESHOLD="${PERFORMANCE_ALERT_THRESHOLD:-50}" # Alert if script takes longer than this AND didn't complete all samples

# --- Data Gathering ---
# We make two API calls to get a complete set of metrics.
debug_log "STEP: Making API calls to gather data"
debug_log "API CALL: Getting status data from $STARLINK_IP:$STARLINK_PORT"

status_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetStatus')
status_exit=$?
debug_log "API RESULT: get_status exit code: $status_exit"
debug_log "API RESULT: status_data length: ${#status_data}"

debug_log "API CALL: Getting history data from $STARLINK_IP:$STARLINK_PORT"
history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory')
history_exit=$?
debug_log "API RESULT: get_history exit code: $history_exit"
debug_log "API RESULT: history_data length: ${#history_data}"

# Exit gracefully if the API is unreachable (e.g., dish is powered off).
if [ -z "$status_data" ] || [ -z "$history_data" ]; then
    log "ERROR: Failed to get data from API. Dish may be offline. Skipping run."
    debug_log "API ERROR: One or both API calls returned empty data"
    debug_log "API ERROR: status_data empty: $([ -z "$status_data" ] && echo 'yes' || echo 'no')"
    debug_log "API ERROR: history_data empty: $([ -z "$history_data" ] && echo 'yes' || echo 'no')"
    debug_log "LOGGER: Exiting due to API communication failure"
    exit 0
fi

# --- Enhanced Metrics Extraction ---
# Extract uptime and reboot-related metrics for intelligent auto-fixing
debug_log "STEP: Extracting enhanced metrics for reboot detection"
uptime_s=$(echo "$status_data" | $JQ_CMD -r '.deviceState.uptimeS // 0' 2>/dev/null)
bootcount=$(echo "$status_data" | $JQ_CMD -r '.deviceInfo.bootcount // 0' 2>/dev/null)
uptime_hours=$((uptime_s / 3600))

debug_log "ENHANCED METRICS:"
debug_log "  uptime_s=$uptime_s (${uptime_hours}h)"
debug_log "  bootcount=$bootcount"

# Enhanced reboot detection using uptime correlation
REBOOT_DETECTED=false

if [ "$uptime_s" -lt 1800 ]; then # Less than 30 minutes
    REBOOT_DETECTED=true
    log "INFO: Recent Starlink reboot detected (uptime: ${uptime_hours}h/${uptime_s}s)"
    debug_log "REBOOT DETECTION: Uptime indicates recent reboot"

    # Check if we should reset sample tracking due to reboot
    if [ -f "$LAST_SAMPLE_FILE" ]; then
        stored_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "0")
        debug_log "REBOOT DETECTION: Found existing sample tracking: $stored_sample_index"

        # Reset sample tracking for recent reboots to prevent stale tracking issues
        if echo "0" >"$LAST_SAMPLE_FILE"; then
            log "INFO: Auto-reset sample tracking due to recent reboot (uptime: ${uptime_s}s)"
            debug_log "REBOOT AUTO-FIX: Sample tracking reset from $stored_sample_index to 0"
        else
            log "WARNING: Failed to reset sample tracking file after reboot detection"
        fi
    fi
elif [ "$uptime_s" -lt 7200 ]; then # Less than 2 hours
    debug_log "REBOOT DETECTION: Uptime relatively low (${uptime_hours}h) - may indicate recent reboot"
else
    debug_log "REBOOT DETECTION: Uptime normal (${uptime_hours}h) - no recent reboot"
fi

# --- Data Processing ---
# The 'current' field is a counter that increments with each new data sample.
# We use this to determine how many new data points are available since our last run.
debug_log "STEP: Processing sample indices"
current_sample_index=$(echo "$history_data" | $JQ_CMD -r '.current')
last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "$((current_sample_index - 1))")

debug_log "SAMPLE INDICES:"
debug_log "  current_sample_index=$current_sample_index (from API)"
debug_log "  last_sample_index=$last_sample_index (from $LAST_SAMPLE_FILE)"
debug_log "  difference=$((current_sample_index - last_sample_index))"

# AUTO-FIX: Detect stale tracking file (tracking index higher than API index)
# This happens when Starlink dish reboots and resets sample indices, but tracking file persists
if [ "$last_sample_index" -gt "$current_sample_index" ]; then
    stale_difference=$((last_sample_index - current_sample_index))
    log "WARNING: Stale sample tracking detected - auto-fixing"
    log "WARNING: Tracked index ($last_sample_index) > API index ($current_sample_index), difference: $stale_difference"
    log "WARNING: This usually happens after Starlink dish reboot/power cycle"

    # Reset tracking to a safe value (current index - 1)
    new_tracking_index=$((current_sample_index - 1))
    if echo "$new_tracking_index" >"$LAST_SAMPLE_FILE"; then
        log "INFO: Auto-fixed sample tracking: reset from $last_sample_index to $new_tracking_index"
        debug_log "SAMPLE TRACKING: Auto-fix successful, continuing with corrected index"
        # Update the variable for the rest of the script
        last_sample_index=$new_tracking_index
    else
        log "ERROR: Failed to auto-fix sample tracking file: $LAST_SAMPLE_FILE"
        debug_log "SAMPLE TRACKING: Auto-fix failed, exiting"
        exit 1
    fi
fi

# If the current index isn't greater than the last one, there's nothing new to log.
if [ "$current_sample_index" -le "$last_sample_index" ]; then
    log "INFO: No new data samples to log. Finishing run."
    debug_log "SAMPLE CHECK: No new samples available, exiting normally"
    debug_log "LOGGER: Completing successfully (no new data)"
    debug_log "==================== STARLINK LOGGER COMPLETE (NO NEW DATA) ===================="
    exit 0
fi

debug_log "SAMPLE CHECK: New samples available for processing"
log "INFO: Processing samples from index $last_sample_index to $current_sample_index."

# Extract the full arrays of data and the single obstruction value.
debug_log "STEP: Extracting data arrays from API response"
latency_array=$(echo "$history_data" | $JQ_CMD -r '.popPingLatencyMs')
loss_array=$(echo "$history_data" | $JQ_CMD -r '.popPingDropRate')
obstruction=$(echo "$status_data" | $JQ_CMD -r '.obstructionStats.fractionObstructed // 0')

# Extract enhanced metrics for CSV logging
is_snr_above_noise_floor=$(echo "$status_data" | $JQ_CMD -r '.isSnrAboveNoiseFloor // true' 2>/dev/null)
is_snr_persistently_low=$(echo "$status_data" | $JQ_CMD -r '.isSnrPersistentlyLow // false' 2>/dev/null)
snr=$(echo "$status_data" | $JQ_CMD -r '.snr // 0' 2>/dev/null)
gps_valid=$(echo "$status_data" | $JQ_CMD -r '.gpsStats.gpsValid // true' 2>/dev/null)
gps_sats=$(echo "$status_data" | $JQ_CMD -r '.gpsStats.gpsSats // 0' 2>/dev/null)

debug_log "DATA ARRAYS:"
debug_log "  latency_array length: $(echo "$latency_array" | $JQ_CMD -r 'length // 0')"
debug_log "  loss_array length: $(echo "$loss_array" | $JQ_CMD -r 'length // 0')"
debug_log "  obstruction value: $obstruction"

# Validate arrays are not empty or null
if [ "$latency_array" = "null" ] || [ -z "$latency_array" ]; then
    log "ERROR: latency_array is null or empty"
    debug_log "VALIDATION ERROR: latency_array=$latency_array"
    exit 1
fi

if [ "$loss_array" = "null" ] || [ -z "$loss_array" ]; then
    log "ERROR: loss_array is null or empty"
    debug_log "VALIDATION ERROR: loss_array=$loss_array"
    exit 1
fi

# Get the current system time to work backwards from for timestamping each sample.
now_seconds=$(date +%s)

# Create the CSV file with a header row if it doesn't already exist.
if [ ! -f "$OUTPUT_CSV" ]; then
    echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Reboot Detected" >"$OUTPUT_CSV"
fi

# --- Loop and Log ---
# Calculate how many new samples we need to process.
new_sample_count=$((current_sample_index - last_sample_index))
debug_log "LOOP SETUP: new_sample_count=$new_sample_count"

# PERFORMANCE FIX: Limit the number of samples to process to prevent massive loops
# Only process the most recent samples (default: 60 = 1 hour of data)
MAX_SAMPLES_PER_RUN="${MAX_SAMPLES_PER_RUN:-60}"
ADAPTIVE_SAMPLING_ENABLED="${ADAPTIVE_SAMPLING_ENABLED:-1}"
ADAPTIVE_SAMPLING_INTERVAL="${ADAPTIVE_SAMPLING_INTERVAL:-5}"
FALLBEHIND_THRESHOLD="${FALLBEHIND_THRESHOLD:-100}"

samples_limited=false
adaptive_sampling_active=false

# Check if we're falling significantly behind
if [ "$ADAPTIVE_SAMPLING_ENABLED" = "1" ] && [ "$new_sample_count" -gt "$FALLBEHIND_THRESHOLD" ]; then
    adaptive_sampling_active=true
    debug_log "ADAPTIVE SAMPLING: Activating adaptive sampling mode"
    debug_log "ADAPTIVE SAMPLING: $new_sample_count samples > threshold $FALLBEHIND_THRESHOLD"
    log "INFO: Adaptive sampling activated - processing every ${ADAPTIVE_SAMPLING_INTERVAL}th sample due to high sample count ($new_sample_count)"

    # Calculate effective sample count when using adaptive sampling
    effective_sample_count=$((new_sample_count / ADAPTIVE_SAMPLING_INTERVAL))
    if [ "$effective_sample_count" -gt "$MAX_SAMPLES_PER_RUN" ]; then
        samples_limited=true
        original_sample_count=$new_sample_count
        effective_sample_count=$MAX_SAMPLES_PER_RUN
        # Adjust to process the most recent portion
        samples_to_skip=$((new_sample_count - (effective_sample_count * ADAPTIVE_SAMPLING_INTERVAL)))
        last_sample_index=$((last_sample_index + samples_to_skip))
        new_sample_count=$((effective_sample_count * ADAPTIVE_SAMPLING_INTERVAL))
        debug_log "ADAPTIVE SAMPLING: Limited to $effective_sample_count effective samples"
        debug_log "ADAPTIVE SAMPLING: Skipping $samples_to_skip samples at beginning"
    fi
elif [ "$new_sample_count" -gt "$MAX_SAMPLES_PER_RUN" ]; then
    samples_limited=true
    original_sample_count=$new_sample_count
    debug_log "PERFORMANCE LIMIT: Limiting processing to $MAX_SAMPLES_PER_RUN samples (was $new_sample_count)"
    log "WARNING: Too many new samples ($new_sample_count). Processing only the most recent $MAX_SAMPLES_PER_RUN samples."
    log "WARNING: Logger may be falling behind - $((new_sample_count - MAX_SAMPLES_PER_RUN)) samples will be skipped"

    # Adjust last_sample_index to only process the most recent samples
    last_sample_index=$((current_sample_index - MAX_SAMPLES_PER_RUN))
    new_sample_count=$MAX_SAMPLES_PER_RUN
    debug_log "PERFORMANCE LIMIT: Adjusted last_sample_index to $last_sample_index"
    debug_log "PERFORMANCE LIMIT: Skipping $((original_sample_count - MAX_SAMPLES_PER_RUN)) samples to prevent performance issues"
fi

debug_log "LOOP SETUP: Final new_sample_count=$new_sample_count"
debug_log "LOOP SETUP: adaptive_sampling_active=$adaptive_sampling_active"
debug_log "LOOP SETUP: Starting processing loop"

i=0
samples_processed=0
while [ "$i" -lt "$new_sample_count" ]; do
    # Check if we should process this sample based on adaptive sampling
    should_process_sample=true
    if [ "$adaptive_sampling_active" = "true" ]; then
        # In adaptive mode, only process every Nth sample
        if [ $((i % ADAPTIVE_SAMPLING_INTERVAL)) -ne 0 ]; then
            should_process_sample=false
            debug_log "ADAPTIVE SAMPLING: Skipping sample $i (not divisible by $ADAPTIVE_SAMPLING_INTERVAL)"
        else
            debug_log "ADAPTIVE SAMPLING: Processing sample $i (divisible by $ADAPTIVE_SAMPLING_INTERVAL)"
        fi
    fi

    if [ "$should_process_sample" = "true" ]; then
        debug_log "LOOP ITERATION: Processing iteration $i (sample #$((samples_processed + 1)))"
        # The API provides samples in chronological order. We work backwards from the
        # current time to assign an approximate but accurate timestamp to each sample.
        sample_timestamp=$((now_seconds - (new_sample_count - 1 - i)))
        human_readable_timestamp=$(date -d "@$sample_timestamp" '+%Y-%m-%d %H:%M:%S')
        debug_log "TIMESTAMP: $human_readable_timestamp (epoch: $sample_timestamp)"

        # Extract the specific latency and loss for this sample from the arrays.
        # We use jq's --argjson flag to safely pass shell variables into the jq script.
        debug_log "SAMPLE EXTRACTION: Processing sample $i of $new_sample_count"
        debug_log "JQ VARIABLES: i=$i, count=$new_sample_count"
        debug_log "JQ EXPRESSION: .[length - (4*\$count - 4*\$i)] // 0"

        latency=$(echo "$latency_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" ".[length - (4*\$count - 4*\$i)] // 0" | cut -d'.' -f1)
        debug_log "EXTRACTED LATENCY: $latency"

        loss=$(echo "$loss_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" ".[length - (4*\$count - 4*\$i)] // 0")
        debug_log "EXTRACTED LOSS: $loss"

        # Convert loss and obstruction ratios to percentages for easier analysis in spreadsheets.
        loss_pct=$(awk -v val="$loss" 'BEGIN { printf "%.2f", val * 100 }')
        obstruction_pct=$(awk -v val="$obstruction" 'BEGIN { printf "%.2f", val * 100 }')

        # Format enhanced metrics for CSV
        snr_formatted=$(awk -v val="$snr" 'BEGIN { printf "%.1f", val }')
        snr_above_noise_flag=$([ "$is_snr_above_noise_floor" = "true" ] && echo "1" || echo "0")
        snr_persistently_low_flag=$([ "$is_snr_persistently_low" = "true" ] && echo "1" || echo "0")
        gps_valid_flag=$([ "$gps_valid" = "true" ] && echo "1" || echo "0")
        reboot_detected_flag=$([ "$REBOOT_DETECTED" = "true" ] && echo "1" || echo "0")

        # Append the formatted data as a new line in the CSV file (enhanced format).
        echo "$human_readable_timestamp,$latency,$loss_pct,$obstruction_pct,$uptime_hours,$snr_formatted,$snr_above_noise_flag,$snr_persistently_low_flag,$gps_valid_flag,$gps_sats,$reboot_detected_flag" >>"$OUTPUT_CSV"
        debug_log "CSV WRITE: Sample $i written to CSV with enhanced metrics"

        samples_processed=$((samples_processed + 1))
    else
        debug_log "LOOP ITERATION: Skipping iteration $i (adaptive sampling)"
    fi

    i=$((i + 1))
done

# Save the latest processed index so we know where to start on the next run.
debug_log "STEP: Saving current sample index for next run"
echo "$current_sample_index" >"$LAST_SAMPLE_FILE"
debug_log "SAVED INDEX: $current_sample_index to $LAST_SAMPLE_FILE"

debug_log "CSV OUTPUT: Successfully wrote $samples_processed rows to $OUTPUT_CSV"
if [ "$adaptive_sampling_active" = "true" ]; then
    log "--- Successfully logged $samples_processed data points (adaptive sampling: every ${ADAPTIVE_SAMPLING_INTERVAL}th of $new_sample_count samples). Finishing run. ---"
else
    log "--- Successfully logged $samples_processed new data points. Finishing run. ---"
fi

# --- Performance Analysis and Alerting ---
script_end_time=$(date +%s)
execution_time=$((script_end_time - script_start_time))
debug_log "PERFORMANCE: Script completed at epoch $script_end_time"
debug_log "PERFORMANCE: Total execution time: ${execution_time} seconds"
debug_log "PERFORMANCE: Processed $samples_processed samples in ${execution_time} seconds"
debug_log "PERFORMANCE: Total available samples: $new_sample_count"

# Calculate processing rate
if [ "$execution_time" -gt 0 ]; then
    samples_per_second=$((samples_processed / execution_time))
    debug_log "PERFORMANCE: Processing rate: $samples_per_second samples/second"
else
    samples_per_second="$samples_processed"
    debug_log "PERFORMANCE: Processing rate: $samples_per_second samples/second (instant)"
fi

# Check for performance issues and generate alerts
performance_issues=""

# Check execution time threshold (only warn if actually problematic)
if [ "$execution_time" -gt "$MAX_EXECUTION_TIME_SECONDS" ]; then
    performance_issues="${performance_issues}Execution time ($execution_time s) exceeded maximum ($MAX_EXECUTION_TIME_SECONDS s). "
    log "WARNING: Logger execution took ${execution_time} seconds, exceeding maximum of ${MAX_EXECUTION_TIME_SECONDS} seconds"
fi

# Check processing rate (only if we're actually struggling - slow AND didn't complete samples)
# This prevents false alarms when processing rate is reasonable but we're catching up on a backlog
if [ "$execution_time" -gt "$PERFORMANCE_ALERT_THRESHOLD" ] && [ "$samples_limited" = "true" ]; then
    if [ "$samples_per_second" -lt "$MIN_SAMPLES_PER_SECOND" ] && [ "$samples_processed" -gt 5 ]; then
        performance_issues="${performance_issues}Processing rate ($samples_per_second samples/s) below minimum ($MIN_SAMPLES_PER_SECOND samples/s) while struggling with large sample count. "
        log "WARNING: Logger processing rate ($samples_per_second samples/s) is too slow while handling large sample backlog"
    fi
fi

# Alert threshold check (only if we took too long AND couldn't complete all samples)
if [ "$execution_time" -gt "$PERFORMANCE_ALERT_THRESHOLD" ] && [ "$samples_limited" = "true" ]; then
    performance_issues="${performance_issues}Script performance degraded (${execution_time}s > ${PERFORMANCE_ALERT_THRESHOLD}s) and couldn't process all samples. "
    log "ALERT: Logger performance degraded - execution time ${execution_time} seconds exceeded alert threshold while unable to complete all samples"
elif [ "$execution_time" -gt "$PERFORMANCE_ALERT_THRESHOLD" ]; then
    debug_log "PERFORMANCE: Script took ${execution_time}s but completed all samples successfully - no alert needed"
fi

# Calculate if we're falling behind (samples accumulating faster than processing)
# Only warn if we're both taking too long AND unable to keep up
expected_samples_per_run=1                               # Normally expect 1-2 new samples per minute for frequent runs
high_sample_threshold=$((expected_samples_per_run * 20)) # Only consider "high" if >20x normal

if [ "$new_sample_count" -gt "$high_sample_threshold" ]; then
    if [ "$adaptive_sampling_active" = "true" ]; then
        # Adaptive sampling is working - this is informational, not a problem
        debug_log "INFO: Adaptive sampling handled high load - $new_sample_count samples available, processed $samples_processed (every ${ADAPTIVE_SAMPLING_INTERVAL}th sample)"
    elif [ "$execution_time" -gt "$PERFORMANCE_ALERT_THRESHOLD" ]; then
        # Only warn if high sample count AND slow execution - indicates real problem
        performance_issues="${performance_issues}Falling behind data generation - processed $samples_processed of $new_sample_count samples in ${execution_time}s. "
        log "WARNING: Logger falling behind - processed $samples_processed of $new_sample_count samples and took ${execution_time}s"
    else
        # High sample count but fast processing - no problem
        debug_log "INFO: Processed large sample backlog efficiently ($samples_processed samples in ${execution_time}s)"
    fi
fi

# Check if we had to limit sample processing (only warn if it indicates a real problem)
if [ "$samples_limited" = "true" ] && [ "$execution_time" -gt "$PERFORMANCE_ALERT_THRESHOLD" ]; then
    performance_issues="${performance_issues}Sample processing was limited and still took too long ($execution_time s > $PERFORMANCE_ALERT_THRESHOLD s). "
    log "WARNING: Sample processing was limited but still took ${execution_time}s - $((original_sample_count - new_sample_count)) samples were skipped"
elif [ "$samples_limited" = "true" ]; then
    # Sample limiting worked effectively - this is informational
    debug_log "INFO: Sample limiting prevented performance issues - processed $new_sample_count of $original_sample_count samples efficiently"
fi

# Send consolidated alert if there are performance issues
if [ -n "$performance_issues" ]; then
    alert_message="Starlink Logger Performance Issues: ${performance_issues}Runtime: ${execution_time}s, Rate: ${samples_per_second} samples/s, Processed: $samples_processed of $new_sample_count available"
    log "PERFORMANCE_ALERT: $alert_message"
    debug_log "PERFORMANCE_ALERT: Generated alert for performance issues"

    # Try to send notification if available (from placeholder-utils.sh)
    if command -v safe_notify >/dev/null 2>&1; then
        safe_notify "Starlink Logger Performance Alert" "$alert_message" 1
        debug_log "PERFORMANCE_ALERT: Notification sent via safe_notify"
    else
        debug_log "PERFORMANCE_ALERT: safe_notify not available, alert logged only"
    fi
else
    debug_log "PERFORMANCE: No performance issues detected"
    if [ "$execution_time" -lt "$PERFORMANCE_ALERT_THRESHOLD" ]; then
        debug_log "PERFORMANCE: Script completed efficiently ($execution_time s < $PERFORMANCE_ALERT_THRESHOLD s)"
        debug_log "PERFORMANCE: Processing rate: $samples_per_second samples/s, Total: $samples_processed samples"

        # Positive feedback for good performance
        if [ "$samples_processed" -gt 30 ] && [ "$execution_time" -lt 15 ]; then
            debug_log "PERFORMANCE: Excellent performance - processed $samples_processed samples in ${execution_time}s"
        fi
    fi
fi

debug_log "LOGGER: Completing successfully"
debug_log "==================== STARLINK LOGGER COMPLETE ===================="
debug_log "Final status: SUCCESS"
debug_log "Script execution completed normally"
debug_log "Exit code: 0"

# Clean up any temporary files
if [ -f /tmp/logger_error.log ]; then
    debug_log "CLEANUP: Removing temporary error log"
    rm -f /tmp/logger_error.log
fi
