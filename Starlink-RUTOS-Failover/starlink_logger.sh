#!/bin/sh

# ==============================================================================
# Starlink Performance Data Logger for OpenWrt/RUTOS
#
# Version: 1.0 (Public Edition)
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
set -euo pipefail

# --- User Configuration ---

# The IP address and port for the Starlink gRPC API. This is standard.
STARLINK_IP="192.168.100.1:9200"

# The tag used for logging messages to the system log (syslog/logread).
LOG_TAG="StarlinkLogger"

# The full path where the final CSV log file will be stored.
OUTPUT_CSV="/root/starlink_performance_log.csv"

# --- System Configuration (Advanced) ---
# Location of state files. /tmp/run/ is recommended as it's a tmpfs.
LAST_SAMPLE_FILE="/tmp/run/starlink_last_sample.ts"

# Location of binaries. Assumes they are in the system's PATH.
# If you placed them in /root/, change these to /root/grpcurl and /root/jq.
GRPCURL_CMD="grpcurl"
JQ_CMD="jq"

# --- Helper Functions ---
log() {
    # Use -- to prevent messages starting with - from being treated as options
    logger -t "$LOG_TAG" -- "$1"
}

# --- Main Script ---
log "--- Starting data logging run ---"

# --- Data Gathering ---
# We make two API calls to get a complete set of metrics.
status_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetStatus')
history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory')

# Exit gracefully if the API is unreachable (e.g., dish is powered off).
if [ -z "$status_data" ] || [ -z "$history_data" ]; then
    log "ERROR: Failed to get data from API. Dish may be offline. Skipping run."
    exit 0
fi

# --- Data Processing ---
# The 'current' field is a counter that increments with each new data sample.
# We use this to determine how many new data points are available since our last run.
current_sample_index=$(echo "$history_data" | $JQ_CMD -r '.current')
last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "$((current_sample_index - 1))")

# If the current index isn't greater than the last one, there's nothing new to log.
if [ "$current_sample_index" -le "$last_sample_index" ]; then
    log "INFO: No new data samples to log. Finishing run."
    exit 0
fi

log "INFO: Processing samples from index $last_sample_index to $current_sample_index."

# Extract the full arrays of data and the single obstruction value.
latency_array=$(echo "$history_data" | $JQ_CMD -r '.popPingLatencyMs')
loss_array=$(echo "$history_data" | $JQ_CMD -r '.popPingDropRate')
obstruction=$(echo "$status_data" | $JQ_CMD -r '.obstructionStats.fractionObstructed // 0')

# Get the current system time to work backwards from for timestamping each sample.
now_seconds=$(date +%s)

# Create the CSV file with a header row if it doesn't already exist.
if [ ! -f "$OUTPUT_CSV" ]; then
    echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%)" > "$OUTPUT_CSV"
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
    latency=$(echo "$latency_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" '.[length - ($count - $i)] // 0' | cut -d'.' -f1)
    loss=$(echo "$loss_array" | $JQ_CMD -r --argjson i "$i" --argjson count "$new_sample_count" '.[length - ($count - $i)] // 0')
    
    # Convert loss and obstruction ratios to percentages for easier analysis in spreadsheets.
    loss_pct=$(awk -v val="$loss" 'BEGIN { printf "%.2f", val * 100 }')
    obstruction_pct=$(awk -v val="$obstruction" 'BEGIN { printf "%.2f", val * 100 }')
    
    # Append the formatted data as a new line in the CSV file.
    echo "$human_readable_timestamp,$latency,$loss_pct,$obstruction_pct" >> "$OUTPUT_CSV"
    
    i=$((i + 1))
done

# Save the latest processed index so we know where to start on the next run.
echo "$current_sample_index" > "$LAST_SAMPLE_FILE"

log "--- Successfully logged $new_sample_count new data points. Finishing run. ---"

