#!/bin/sh

# Version information (auto-updated by update-version.sh)
# VALIDATION_SKIP_COLOR_CHECK: This script uses syslog only, no color output needed

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034

# Version information (auto-updated by update-version.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# ==============================================================================
# Starlink API Version Monitor
#
# Version: 2.4.12
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

# Version information (auto-updated by update-version.sh)

# Version information

# Version information

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
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Validate binary with detailed logging
validate_binary() {
    binary_path="$1"
    binary_name="$2"

    debug_log "VALIDATING BINARY: $binary_name at $binary_path"

    if [ ! -f "$binary_path" ]; then
        log "ERROR: $binary_name not found at $binary_path"
        debug_log "FILE CHECK FAILED: $binary_path does not exist"
        return 1
    fi

    if [ ! -x "$binary_path" ]; then
        log "ERROR: $binary_name not executable at $binary_path"
        debug_log "PERMISSION CHECK FAILED: $binary_path is not executable"
        debug_log "FILE PERMISSIONS: $(ls -la "$binary_path" 2>/dev/null || echo 'Cannot read permissions')"
        return 1
    fi

    # Test if binary actually works
    echo "check_starlink_api-rutos.sh v$SCRIPT_VERSION"
    echo ""
    debug_log "TESTING BINARY: $binary_path --help"
    echo "check_starlink_api-rutos.sh v$SCRIPT_VERSION"
    echo ""
    if ! "$binary_path" --help >/dev/null 2>&1; then
        log "WARNING: $binary_name may not be functioning properly"
        echo "check_starlink_api-rutos.sh v$SCRIPT_VERSION"
        echo ""
        debug_log "BINARY TEST FAILED: $binary_path --help returned non-zero"
    else
        debug_log "BINARY TEST PASSED: $binary_name is functional"
    fi

    return 0
}

send_notification() {
    title="$1"
    message="$2"

    debug_log "NOTIFICATION START: Preparing to send Pushover notification"
    debug_log "NOTIFICATION TITLE: '$title'"
    debug_log "NOTIFICATION MESSAGE: '$message'"
    debug_log "PUSHOVER_TOKEN: $(printf "%.10s..." "$PUSHOVER_TOKEN")"
    debug_log "PUSHOVER_USER: $(printf "%.10s..." "$PUSHOVER_USER")"

    log "Sending Pushover -> Title: '$title', Message: '$message'"

    # Validate that we have credentials
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ -z "$PUSHOVER_TOKEN" ]; then
        log "ERROR: PUSHOVER_TOKEN not configured properly"
        debug_log "NOTIFICATION FAILED: Invalid or missing PUSHOVER_TOKEN"
        return 1
    fi

    if [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ] || [ -z "$PUSHOVER_USER" ]; then
        log "ERROR: PUSHOVER_USER not configured properly"
        debug_log "NOTIFICATION FAILED: Invalid or missing PUSHOVER_USER"
        return 1
    fi

    # Execute curl with detailed logging
    debug_log "CURL COMMAND: curl -s --max-time 15 -F 'token=***' -F 'user=***' -F 'title=$title' -F 'message=$message' https://api.pushover.net/1/messages.json"

    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show curl output
        response=$(curl -s --max-time 15 \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "title=$title" \
            -F "message=$message" \
            https://api.pushover.net/1/messages.json 2>&1)
        curl_exit=$?
        debug_log "CURL EXIT CODE: $curl_exit"
        debug_log "CURL RESPONSE: $response"

        if [ $curl_exit -eq 0 ]; then
            log "Pushover notification sent successfully"
            debug_log "NOTIFICATION SUCCESS: Pushover API responded"
        else
            log "ERROR: Failed to send Pushover notification (curl exit: $curl_exit)"
            debug_log "NOTIFICATION FAILED: curl command failed"
        fi
    else
        # In normal mode, suppress output
        if curl -s --max-time 15 \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "title=$title" \
            -F "message=$message" \
            https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            log "Pushover notification sent successfully"
        else
            log "ERROR: Failed to send Pushover notification"
        fi
    fi
}

# --- Main Script ---

# Add test mode for troubleshooting
if [ "${TEST_MODE:-0}" = "1" ]; then
    debug_log "TEST MODE ENABLED: Running in test mode"
    DEBUG=1 # Force debug mode in test mode
    set -x  # Enable command tracing
    debug_log "TEST MODE: All commands will be traced"
fi

debug_log "==================== STARLINK API CHECK START ===================="
debug_log "Starting API version check script"
debug_log "Script version: 2.4.0"
debug_log "Current working directory: $(pwd)"
debug_log "Script path: $0"
debug_log "Process ID: $$"
debug_log "User: $(whoami 2>/dev/null || echo 'unknown')"
debug_log "Environment DEBUG: ${DEBUG:-0}"

debug_log "CONFIGURATION VALUES:"
debug_log "  INSTALL_DIR=$INSTALL_DIR"
debug_log "  CONFIG_FILE=$CONFIG_FILE"
debug_log "  PUSHOVER_TOKEN=$(printf "%.10s..." "$PUSHOVER_TOKEN")"
debug_log "  PUSHOVER_USER=$(printf "%.10s..." "$PUSHOVER_USER")"
debug_log "  STARLINK_IP=$STARLINK_IP"
debug_log "  KNOWN_API_VERSION_FILE=$KNOWN_API_VERSION_FILE"
debug_log "  GRPCURL_CMD=$GRPCURL_CMD"
debug_log "  JQ_CMD=$JQ_CMD"
debug_log "  LOG_TAG=$LOG_TAG"

# Check if configuration file was loaded
if [ -f "$CONFIG_FILE" ]; then
    debug_log "CONFIG FILE: Successfully loaded from $CONFIG_FILE"
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_log "CONFIG FILE CONTENTS:"
        while IFS= read -r line; do
            # Don't log sensitive information in full
            case "$line" in
                *PUSHOVER_TOKEN* | *PUSHOVER_USER*)
                    debug_log "  $(echo "$line" | sed 's/=.*/=***/')"
                    ;;
                *)
                    debug_log "  $line"
                    ;;
            esac
        done <"$CONFIG_FILE" 2>/dev/null || debug_log "  (Cannot read config file contents)"
    fi
else
    debug_log "CONFIG FILE: Not found at $CONFIG_FILE - using defaults"
fi

# Validate required binaries exist
debug_log "BINARY VALIDATION: Starting checks..."
if ! validate_binary "$GRPCURL_CMD" "grpcurl"; then
    debug_log "BINARY VALIDATION: grpcurl failed validation"
    exit 1
fi

if ! validate_binary "$JQ_CMD" "jq"; then
    debug_log "BINARY VALIDATION: jq failed validation"
    exit 1
fi

debug_log "BINARY VALIDATION: All binaries validated successfully"

log "--- Starting API version check ---"
debug_log "API VERSION CHECK: Starting main logic"

# Get the last known version from the file, defaulting to "0" if the file doesn't exist.
debug_log "KNOWN VERSION: Reading from $KNOWN_API_VERSION_FILE"
if [ -f "$KNOWN_API_VERSION_FILE" ]; then
    known_version=$(cat "$KNOWN_API_VERSION_FILE" 2>/dev/null || echo "0")
    debug_log "KNOWN VERSION: File exists, content: '$known_version'"
    # Validate the content
    if [ -z "$known_version" ]; then
        debug_log "KNOWN VERSION: File is empty, defaulting to '0'"
        known_version="0"
    fi
else
    known_version="0"
    debug_log "KNOWN VERSION: File does not exist, defaulting to '0'"
fi

debug_log "KNOWN VERSION: Final value: '$known_version'"

# Get the current version from the dish. We use 'get_device_info' as it's a lightweight call.
debug_log "CURRENT VERSION: Starting gRPC call to Starlink"
debug_log "GRPC CALL: $GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP SpaceX.API.Device.Device/Handle"

# Build the gRPC command step by step for better debugging
grpc_cmd="$GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP SpaceX.API.Device.Device/Handle"
debug_log "GRPC COMMAND: $grpc_cmd"

# Execute gRPC call with detailed error handling
if [ "${DEBUG:-0}" = "1" ]; then
    debug_log "GRPC EXECUTION: Running in debug mode with full output"
    grpc_output=$(eval "$grpc_cmd" 2>&1)
    grpc_exit=$?
    debug_log "GRPC EXIT CODE: $grpc_exit"
    debug_log "GRPC RAW OUTPUT (first 500 chars): $(echo "$grpc_output" | cut -c1-500)$([ ${#grpc_output} -gt 500 ] && echo '...')"

    if [ $grpc_exit -ne 0 ]; then
        log "ERROR: gRPC call failed with exit code $grpc_exit"
        debug_log "GRPC ERROR: Full output: $grpc_output"
        current_version="0"
    else
        debug_log "GRPC SUCCESS: Processing JSON response with jq"
        debug_log "JQ COMMAND: echo \"\$grpc_output\" | $JQ_CMD -r '.apiVersion // \"0\"'"

        current_version=$(echo "$grpc_output" | $JQ_CMD -r '.apiVersion // "0"' 2>&1)
        jq_exit=$?
        debug_log "JQ EXIT CODE: $jq_exit"
        debug_log "JQ OUTPUT: '$current_version'"

        if [ $jq_exit -ne 0 ]; then
            log "ERROR: Failed to parse JSON response with jq"
            debug_log "JQ ERROR: Failed to extract apiVersion"
            current_version="0"
        fi
    fi
else
    # Normal execution (less verbose)
    current_version=$(eval "$grpc_cmd" 2>/dev/null | $JQ_CMD -r '.apiVersion // "0"' 2>/dev/null || echo "0")
fi

debug_log "CURRENT VERSION: Final extracted value: '$current_version'"

# Validate the current version
if [ "$current_version" = "0" ] || [ -z "$current_version" ] || [ "$current_version" = "null" ]; then
    log "ERROR: Could not retrieve current API version from dish. Skipping check."
    debug_log "VERSION VALIDATION: Current version is invalid ('$current_version')"
    debug_log "POSSIBLE CAUSES:"
    debug_log "  - Starlink dish is unreachable at $STARLINK_IP"
    debug_log "  - gRPC API is not responding"
    debug_log "  - API response format has changed"
    debug_log "  - Network connectivity issues"
    debug_log "API VERSION CHECK: Exiting due to invalid current version"
    exit 0
fi

log "INFO: Known version: $known_version, Current version: $current_version"
debug_log "VERSION COMPARISON: Comparing '$current_version' with '$known_version'"

# Compare the current version with the last known version.
if [ "$current_version" != "$known_version" ]; then
    # --- API VERSION HAS CHANGED ---
    log "WARN: API version has changed from $known_version to $current_version. Sending notification."
    debug_log "VERSION CHANGE DETECTED: From '$known_version' to '$current_version'"

    MESSAGE="Starlink API version has changed from $known_version to $current_version. Please check if monitoring scripts need updates."
    TITLE="Starlink API Alert"

    debug_log "NOTIFICATION: Preparing to send alert"
    debug_log "NOTIFICATION TITLE: '$TITLE'"
    debug_log "NOTIFICATION MESSAGE: '$MESSAGE'"

    # Send notification with detailed error handling
    if send_notification "$TITLE" "$MESSAGE"; then
        debug_log "NOTIFICATION: Successfully sent"
    else
        log "ERROR: Failed to send notification, but continuing with version update"
        debug_log "NOTIFICATION: Failed to send, but not blocking version file update"
    fi

    # Update the known version file with the new version for the next check.
    debug_log "VERSION FILE UPDATE: Writing '$current_version' to $KNOWN_API_VERSION_FILE"

    if echo "$current_version" >"$KNOWN_API_VERSION_FILE" 2>/dev/null; then
        log "INFO: Updated known version file to $current_version."
        debug_log "VERSION FILE UPDATE: Successfully wrote to file"

        # Verify the write was successful
        if [ "${DEBUG:-0}" = "1" ]; then
            written_version=$(cat "$KNOWN_API_VERSION_FILE" 2>/dev/null || echo "FAILED_TO_READ")
            debug_log "VERSION FILE VERIFY: File now contains: '$written_version'"
            if [ "$written_version" = "$current_version" ]; then
                debug_log "VERSION FILE VERIFY: Write verification successful"
            else
                debug_log "VERSION FILE VERIFY: Write verification failed!"
                log "WARNING: Version file update may have failed"
            fi
        fi
    else
        log "ERROR: Failed to update known version file"
        debug_log "VERSION FILE UPDATE: Write failed - check permissions on $KNOWN_API_VERSION_FILE"
        debug_log "DIRECTORY PERMISSIONS: $(ls -la "$(dirname "$KNOWN_API_VERSION_FILE")" 2>/dev/null || echo 'Cannot read directory permissions')"
    fi
else
    log "INFO: API version is unchanged. No action needed."
    debug_log "VERSION COMPARISON: No change detected, no action required"
fi

debug_log "API VERSION CHECK: Completing successfully"

log "--- API version check finished ---"
debug_log "==================== STARLINK API CHECK COMPLETE ===================="
debug_log "Final status: SUCCESS"
debug_log "Script execution completed normally"
debug_log "Exit code: 0"

# Clean up any temporary files
if [ -f /tmp/api_check_error.log ]; then
    debug_log "CLEANUP: Removing temporary error log"
    rm -f /tmp/api_check_error.log
fi

exit 0
