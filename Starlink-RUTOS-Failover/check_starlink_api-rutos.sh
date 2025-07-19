#!/bin/sh
# VALIDATION_SKIP_COLOR_CHECK: This script uses syslog only, no color output needed

# ==============================================================================
# Starlink API Version Monitor
#
# Version: 2.4.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script runs periodically (ideally once per day via cron) to check if the
# Starlink dish's gRPC API version has changed.
#
# The Starlink API is unofficial and can change with firmware updates. A change
# in the API version can break monitoring scripts that rely on specific data
# structures. This script provides an essential early warning by sending a
# Pushover notification when it detects a new version number.
#
# It is stateful, storing the last known version in a text file to compare
# against on each run.
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
    # Source the configuration file
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Your Pushover Application API Token/Key.
# This will be loaded from config file, fallback to placeholder
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-YOUR_PUSHOVER_API_TOKEN}"

# Your Pushover User Key.
# This will be loaded from config file, fallback to placeholder
PUSHOVER_USER="${PUSHOVER_USER:-YOUR_PUSHOVER_USER_KEY}"

# The tag used for logging messages to the system log (syslog/logread).
LOG_TAG="StarlinkApiCheck"

# --- System Configuration (Advanced) ---

# The IP address and port for the Starlink gRPC API.
# This will be loaded from config file, fallback to standard
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"

# The file used to store the last known API version.
# /root/ is a persistent location on RUTOS/OpenWrt.
KNOWN_API_VERSION_FILE="/root/starlink_api_version.txt"

# Location of binaries - use installation directory paths
# These are installed by the install-rutos.sh script
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

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
        printf "[DEBUG] %s\n" "$1" >&2
    fi
}

send_notification() {
    title="$1"
    message="$2"
    log "Sending Pushover -> Title: '$title', Message: '$message'"
    curl -s --max-time 15 \
        -F "token=$PUSHOVER_TOKEN" \
        -F "user=$PUSHOVER_USER" \
        -F "title=$title" \
        -F "message=$message" \
        https://api.pushover.net/1/messages.json >/dev/null
}

# --- Main Script ---
debug_log "Starting API version check script"
debug_log "INSTALL_DIR=$INSTALL_DIR"
debug_log "CONFIG_FILE=$CONFIG_FILE"
# Use POSIX-compliant method to show partial token/user (first 10 chars equivalent)
# shellcheck disable=SC3057  # POSIX compliance: using printf instead of string slicing
debug_log "PUSHOVER_TOKEN=$(printf "%.10s..." "$PUSHOVER_TOKEN")"
debug_log "PUSHOVER_USER=$(printf "%.10s..." "$PUSHOVER_USER")"
debug_log "STARLINK_IP=$STARLINK_IP"
debug_log "GRPCURL_CMD=$GRPCURL_CMD"
debug_log "JQ_CMD=$JQ_CMD"

# Validate required binaries exist
if [ ! -x "$GRPCURL_CMD" ]; then
    log "ERROR: grpcurl not found or not executable at $GRPCURL_CMD"
    exit 1
fi

if [ ! -x "$JQ_CMD" ]; then
    log "ERROR: jq not found or not executable at $JQ_CMD"
    exit 1
fi

log "--- Starting API version check ---"

# Get the last known version from the file, defaulting to "0" if the file doesn't exist.
known_version=$(cat "$KNOWN_API_VERSION_FILE" 2>/dev/null || echo "0")

# Get the current version from the dish. We use 'get_device_info' as it's a lightweight call.
# The 'apiVersion' is a top-level key in the response.
current_version=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.apiVersion // "0"')

# If we couldn't get a valid version number, exit gracefully.
if [ "$current_version" = "0" ] || [ -z "$current_version" ]; then
    log "ERROR: Could not retrieve current API version from dish. Skipping check."
    exit 0
fi

log "INFO: Known version: $known_version, Current version: $current_version"

# Compare the current version with the last known version.
if [ "$current_version" != "$known_version" ]; then
    # --- API VERSION HAS CHANGED ---
    log "WARN: API version has changed from $known_version to $current_version. Sending notification."

    MESSAGE="Starlink API version has changed from $known_version to $current_version. Please check if monitoring scripts need updates."
    TITLE="Starlink API Alert"

    send_notification "$TITLE" "$MESSAGE"

    # Update the known version file with the new version for the next check.
    echo "$current_version" >"$KNOWN_API_VERSION_FILE"
    log "INFO: Updated known version file to $current_version."
else
    log "INFO: API version is unchanged. No action needed."
fi

log "--- API version check finished ---"
exit 0
