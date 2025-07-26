#!/bin/sh

# ==============================================================================
# Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.5.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-victron/
#
# This script proactively monitors the quality of a Starlink internet connection
# using its unofficial gRPC API. If quality degrades below defined thresholds
# (for latency, packet loss, or obstruction), it performs a "soft" failover
# by increasing the mwan3 metric of the Starlink interface. This makes it
# less preferred than a cellular backup without dropping existing connections.
#
# It also features a stability-aware recovery, waiting for a configurable
# period of good quality before failing back to Starlink.
#
# This script is designed to be the "brain" of the operation and calls a
# separate notifier script to handle user alerts (e.g., via Pushover).
#
# ==============================================================================

# Exit on first error, undefined variable, or pipe failure for script robustness.
set -eu

# Configuration validation

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
if [ -z "${STARLINK_IP:-}" ] || [ -z "${MWAN_IFACE:-}" ] || [ -z "${MWAN_MEMBER:-}" ]; then
    echo "Error: Critical configuration variables not set"
    exit 1
fi

# Create required directories
mkdir -p "$(dirname "$STATE_FILE")"
mkdir -p "$(dirname "$STABILITY_FILE")"
mkdir -p "$LOG_DIR"

# --- User Configuration ---

# The IP address and port for the Starlink gRPC API. This is standard.
STARLINK_IP="192.168.100.1"
STARLINK_PORT="9200"

# The logical interface name for Starlink in OpenWrt/RUTOS (e.g., 'wan').
MWAN_IFACE="wan"

# The mwan3 'member' name that corresponds to the Starlink interface.
# Find this by running `uci show mwan3` and looking for the member
# section where `option interface` is set to your MWAN_IFACE.
MWAN_MEMBER="member1"

# The tag used for logging messages to the system log (syslog/logread).
LOG_TAG="StarlinkMonitor"

# The full path to your separate notifier script.
# This monitor script will call the notifier with arguments like:
# /path/to/script.sh soft_failover "[Reason]"
# /path/to/script.sh soft_recovery
NOTIFIER_SCRIPT="/etc/hotplug.d/iface/99-pushover_notify"

# --- mwan3 Metrics ---
# The metric for the Starlink interface when quality is GOOD.
# This should be the lowest metric in your mwan3 setup.
METRIC_GOOD=1
# The metric for the Starlink interface when quality is BAD.
# This should be higher than your primary cellular backup's metric.
METRIC_BAD=10

# --- Failover Thresholds ---
# These values determine when a soft failover is triggered.
# It is highly recommended to use the companion `starlink_logger.sh`
# script to gather data and fine-tune these for your specific environment.

# Packet Loss: Failover if packet loss is > 5%
# This value is a ratio (0.0 to 1.0).
PACKET_LOSS_THRESHOLD=0.05

# Obstruction: Failover if the sky view is > 0.1% obstructed.
# This is a sensitive setting to react to physical blockages.
OBSTRUCTION_THRESHOLD=0.001

# Latency: Failover if POP ping latency is > 150ms.
LATENCY_THRESHOLD_MS=150

# --- Recovery Thresholds ---
# How many consecutive 1-minute checks must pass before failing back.
# `5` means the connection must be stable for 5 minutes.
STABILITY_CHECKS_REQUIRED=5

# --- System Configuration (Advanced) ---
# Location of state files. /tmp/run/ is recommended as it's a tmpfs.
STATE_FILE="/tmp/run/starlink_monitor.state"
STABILITY_FILE="/tmp/run/starlink_monitor.stability"

# Location of binaries. Assumes they are in the system's PATH.
# If you placed them in /root/, use /root/grpcurl and /root/jq instead.
GRPCURL_CMD="grpcurl"
JQ_CMD="jq"

# --- Log Rotation ---
LOG_DIR="/var/log"
# shellcheck disable=SC2034
LOG_FILE="${LOG_DIR}/starlink_monitor_$(date '+%Y-%m-%d').log"
find "$LOG_DIR" -name 'starlink_monitor_*.log' -mtime +6 -exec rm {} \;

# --- Helper Functions ---
log() {
    # Use -- to prevent messages starting with - from being treated as options
    logger -t "$LOG_TAG" -- "$1"
    # Also print to the console when run manually for debugging.
    echo "$1"
}

# --- Main Logic ---
log "--- Starting check ---"

# Read the last known state from files, defaulting to 'up' and 0.
last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "up")
stability_count=$(cat "$STABILITY_FILE" 2>/dev/null || echo "0")
# Get the current metric directly from the UCI configuration.
current_metric=$(uci -q get mwan3."$MWAN_MEMBER".metric || echo "$METRIC_GOOD")

log "INFO: Current state: $last_state, Stability count: $stability_count, Metric: $current_metric"

# --- Data Gathering ---
# We make two API calls to get the best of all available data:
# 1. get_status: Provides real-time Latency and Obstruction.
# 2. get_history: Provides a real-time array of Packet Loss.

# Check if required binaries exist
if [ ! -x "$GRPCURL_CMD" ] && ! command -v grpcurl >/dev/null 2>&1; then
    log ERROR "grpcurl not found. Please install it first."
    exit 1
fi

if [ ! -x "$JQ_CMD" ] && ! command -v jq >/dev/null 2>&1; then
    log ERROR "jq not found. Please install it first."
    exit 1
fi

status_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetStatus')
history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory')

# Check if API calls were successful
if [ -z "$status_data" ] || [ -z "$history_data" ]; then
    log "ERROR: Failed to get data from API. Dish may be unreachable."
    quality_is_bad=true
    FAIL_REASON="[API Unreachable]"
else
    # Parse the JSON to extract the required metrics.
    obstruction=$(echo "$status_data" | $JQ_CMD -r '.obstructionStats.fractionObstructed // 0' 2>/dev/null)
    latency=$(echo "$status_data" | $JQ_CMD -r '.popPingLatencyMs // 0' 2>/dev/null)
    # shellcheck disable=SC1087  # This is a jq JSON path, not a shell array
    loss=$(echo "$history_data" | $JQ_CMD -r '.popPingDropRate[-1] // 0' 2>/dev/null)

    # Validate extracted data
    if [ -z "$obstruction" ] || [ -z "$latency" ] || [ -z "$loss" ]; then
        log "ERROR: Failed to parse API response data"
        quality_is_bad=true
        FAIL_REASON="[Data Parse Error]"
    else
        # --- Quality Analysis ---
        latency_int=$(echo "$latency" | cut -d'.' -f1)
        is_loss_high=$(awk -v val="$loss" -v threshold="$PACKET_LOSS_THRESHOLD" 'BEGIN { print (val > threshold) }')
        is_obstructed=$(awk -v val="$obstruction" -v threshold="$OBSTRUCTION_THRESHOLD" 'BEGIN { print (val > threshold) }')
        is_latency_high=0

        # Validate latency is numeric before comparison
        if [ "$latency_int" -eq "$latency_int" ] 2>/dev/null && [ "$latency_int" -gt "$LATENCY_THRESHOLD_MS" ]; then
            is_latency_high=1
        fi

        log "DEBUG INFO:
        - Loss Check:      value=${loss}, threshold=${PACKET_LOSS_THRESHOLD}, triggered=${is_loss_high}
        - Obstruction Check: value=${obstruction}, threshold=${OBSTRUCTION_THRESHOLD}, triggered=${is_obstructed}
        - Latency Check:     value=${latency_int}ms, threshold=${LATENCY_THRESHOLD_MS}ms, triggered=${is_latency_high}"

        if [ "$is_loss_high" -eq 1 ] || [ "$is_obstructed" -eq 1 ] || [ "$is_latency_high" -eq 1 ]; then
            quality_is_bad=true
            # Construct a detailed reason string for the notification.
            FAIL_REASON=""
            # shellcheck disable=SC1087  # Square brackets are literal text, not arrays
            [ "$is_loss_high" -eq 1 ] && FAIL_REASON="$FAIL_REASON[High Loss] "
            # shellcheck disable=SC1087  # Square brackets are literal text, not arrays
            [ "$is_obstructed" -eq 1 ] && FAIL_REASON="$FAIL_REASON[Obstructed] "
            # shellcheck disable=SC1087  # Square brackets are literal text, not arrays
            [ "$is_latency_high" -eq 1 ] && FAIL_REASON="$FAIL_REASON[High Latency] "
        else
            quality_is_bad=false
        fi
    fi
fi

# --- Decision Logic ---
if [ "$quality_is_bad" = true ]; then
    # --- QUALITY IS BAD ---
    # Reset the stability counter and record the failure time.
    echo "0" >"$STABILITY_FILE"

    # Only take action if the metric isn't already set to bad.
    if [ "$current_metric" -ne "$METRIC_BAD" ]; then
        log "STATE CHANGE: Quality is BELOW threshold. Setting metric to $METRIC_BAD."
        # Use uci to perform the "soft failover".
        if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_BAD" && uci commit mwan3; then
            if mwan3 restart; then
                echo "down" >"$STATE_FILE"
                # Call the external notifier script with the failure reason.
                if [ -x "$NOTIFIER_SCRIPT" ]; then
                    "$NOTIFIER_SCRIPT" "soft_failover" "$FAIL_REASON" || log "WARNING: Notification failed"
                fi
            else
                log "ERROR: Failed to restart mwan3 service"
            fi
        else
            log "ERROR: Failed to update UCI configuration"
        fi
    fi
else
    # --- QUALITY IS GOOD ---
    # If the last known state was 'down', start the recovery process.
    if [ "$last_state" != "up" ]; then
        stability_count=$((stability_count + 1))
        echo "$stability_count" >"$STABILITY_FILE"
        log "INFO: Quality is good. Stability check $stability_count of $STABILITY_CHECKS_REQUIRED passed."

        # Check if the connection has been stable for long enough.
        if [ "$stability_count" -ge "$STABILITY_CHECKS_REQUIRED" ]; then
            log "STATE CHANGE: Stability threshold met. Restoring metric to $METRIC_GOOD."
            # Use uci to perform the "soft failback".
            if uci set mwan3."$MWAN_MEMBER".metric="$METRIC_GOOD" && uci commit mwan3; then
                if mwan3 restart; then
                    echo "up" >"$STATE_FILE"
                    # Call the external notifier script.
                    if [ -x "$NOTIFIER_SCRIPT" ]; then
                        "$NOTIFIER_SCRIPT" "soft_recovery" || log "WARNING: Notification failed"
                    fi
                else
                    log "ERROR: Failed to restart mwan3 service during recovery"
                fi
            else
                log "ERROR: Failed to update UCI configuration during recovery"
            fi
        fi
    else
        # Quality is good and we are already in the 'up' state. Reset stability counter.
        echo "0" >"$STABILITY_FILE"
    fi
fi

# Version information for troubleshooting
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

log "--- Check finished ---"
