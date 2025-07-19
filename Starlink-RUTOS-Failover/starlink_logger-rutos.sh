#!/bin/sh

# ==============================================================================
# Starlink Performance Data Logger for OpenWrt/RUTOS
#
# Version: 2.4.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-victron/
#
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

# --- User Configuration ---

# Set default installation directory if not already set
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"

# Load configuration from config file if available
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Set defaults for variables that may not be in config
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
LOG_TAG="${LOG_TAG:-StarlinkLogger}"
OUTPUT_CSV="${OUTPUT_CSV:-/root/starlink_performance_log.csv}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"

# Binary paths - use installation directory (override any config values)
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

# Create necessary directories
mkdir -p "$STATE_DIR" "$(dirname "$OUTPUT_CSV")" 2>/dev/null || true

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

debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
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
    DEBUG=1  # Force debug mode in test mode
    set -x   # Enable command tracing
    debug_log "TEST MODE: All commands will be traced"
fi

# Enhanced debug mode with detailed startup logging
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    debug_log "==================== STARLINK LOGGER DEBUG MODE ENABLED ===================="
    debug_log "Script version: 2.4.0"
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

# --- Data Gathering ---
# We make two API calls to get a complete set of metrics.
debug_log "STEP: Making API calls to gather data"
debug_log "API CALL: Getting status data from $STARLINK_IP"

status_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetStatus')
status_exit=$?
debug_log "API RESULT: get_status exit code: $status_exit"
debug_log "API RESULT: status_data length: ${#status_data}"

debug_log "API CALL: Getting history data from $STARLINK_IP"
history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory')
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

debug_log "DATA ARRAYS:"
debug_log "  latency_array length: $(echo "$latency_array" | $JQ_CMD -r 'length // 0')"
debug_log "  loss_array length: $(echo "$loss_array" | $JQ_CMD -r 'length // 0')"
debug_log "  obstruction value: $obstruction"

# Get the current system time to work backwards from for timestamping each sample.
now_seconds=$(date +%s)

# Create the CSV file with a header row if it doesn't already exist.
if [ ! -f "$OUTPUT_CSV" ]; then
    echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%)" >"$OUTPUT_CSV"
fi

# --- Loop and Log ---
# Calculate how many new samples we need to process.
new_sample_count=$((current_sample_index - last_sample_index))
i=0
while [ "$i" -lt "$new_sample_count" ]; do
    # The API provides samples in chronological order. We work backwards from the
    # current time to assign an approximate but accurate timestamp to each sample.
    sample_timestamp=$((now_seconds - (new_sample_count - 1 - i)))
    human_readable_timestamp=$(date -d "@$sample_timestamp" '+%Y-%m-%d %H:%M:%S')

    # Extract the specific latency and loss for this sample from the arrays.
    # We use jq's --argjson flag to safely pass shell variables into the jq script.
    latency=$(echo "$latency_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" ".[length - (4count - 4i)] // 0" | cut -d'.' -f1)
    loss=$(echo "$loss_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" ".[length - (4count - 4i)] // 0")

    # Convert loss and obstruction ratios to percentages for easier analysis in spreadsheets.
    loss_pct=$(awk -v val="$loss" 'BEGIN { printf "%.2f", val * 100 }')
    obstruction_pct=$(awk -v val="$obstruction" 'BEGIN { printf "%.2f", val * 100 }')

    # Append the formatted data as a new line in the CSV file.
    echo "$human_readable_timestamp,$latency,$loss_pct,$obstruction_pct" >>"$OUTPUT_CSV"

    i=$((i + 1))
done

# Save the latest processed index so we know where to start on the next run.
debug_log "STEP: Saving current sample index for next run"
echo "$current_sample_index" >"$LAST_SAMPLE_FILE"
debug_log "SAVED INDEX: $current_sample_index to $LAST_SAMPLE_FILE"

debug_log "CSV OUTPUT: Successfully wrote $new_sample_count rows to $OUTPUT_CSV"
log "--- Successfully logged $new_sample_count new data points. Finishing run. ---"

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
