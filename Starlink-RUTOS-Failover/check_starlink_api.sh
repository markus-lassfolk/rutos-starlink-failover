#!/bin/sh

# ==============================================================================
# Starlink API Version Monitor
#
# Version: 1.0 (Public Edition)
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
set -euo pipefail

# --- User Configuration ---

# Your Pushover Application API Token/Key.
# Replace this placeholder with your actual token.
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"

# Your Pushover User Key.
# Replace this placeholder with your actual key.
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# The tag used for logging messages to the system log (syslog/logread).
LOG_TAG="StarlinkApiCheck"

# --- System Configuration (Advanced) ---

# The IP address and port for the Starlink gRPC API. This is standard.
STARLINK_IP="192.168.100.1:9200"

# The file used to store the last known API version.
# /root/ is a persistent location on RUTOS/OpenWrt.
KNOWN_API_VERSION_FILE="/root/starlink_api_version.txt"

# Location of binaries. Assumes they are in the system's PATH.
# If you placed them in /root/, change these to /root/grpcurl and /root/jq.
GRPCURL_CMD="grpcurl"
JQ_CMD="jq"

# --- Helper Functions ---
log() {
    # Use -- to prevent messages starting with - from being treated as options
    logger -t "$LOG_TAG" -- "$1"
}

send_notification() {
    local title="$1"
    local message="$2"
    log "Sending Pushover -> Title: '$title', Message: '$message'"
    curl -s --max-time 15 \
        -F "token=$PUSHOVER_TOKEN" \
        -F "user=$PUSHOVER_USER" \
        -F "title=$title" \
        -F "message=$message" \
        https://api.pushover.net/1/messages.json > /dev/null
}

# --- Main Script ---
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
    echo "$current_version" > "$KNOWN_API_VERSION_FILE"
    log "INFO: Updated known version file to $current_version."
else
    log "INFO: API version is unchanged. No action needed."
fi

log "--- API version check finished ---"
exit 0
