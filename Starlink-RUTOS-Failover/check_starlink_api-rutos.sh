#!/bin/sh

# Exit on first error, undefined variable, or pipe failure for script robustness.
set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# VALIDATION_SKIP_COLOR_CHECK: Uses RUTOS library for colors
# CRITICAL: Load RUTOS library system (REQUIRED)
if ! . "$(dirname "$0")/../scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # CRITICAL ERROR: RUTOS library not found - this script requires the library system
    printf "CRITICAL ERROR: RUTOS library system not found!\n" >&2
    printf "Expected locations:\n" >&2
    printf "  - $(dirname "$0")/../scripts/lib/rutos-lib.sh\n" >&2
    printf "  - /usr/local/starlink-monitor/scripts/lib/rutos-lib.sh\n" >&2
    printf "  - $(dirname "$0")/lib/rutos-lib.sh\n" >&2
    printf "\nThis script requires the RUTOS library for proper operation.\n" >&2
    exit 1
fi

# Initialize script with RUTOS library features if available
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "check_starlink_api-rutos.sh" "$SCRIPT_VERSION"
else
    # Fallback: Initialize minimal logging if library not available
    printf "[WARNING] RUTOS library not available, using minimal fallback\n" >&2
    # VALIDATION_SKIP_PRINTF_CHECK: Fallback logging when RUTOS library unavailable
    # Define minimal fallback functions
    log_info() { printf "[INFO] %s\n" "$1" >&2; }
    log_error() { printf "[ERROR] %s\n" "$1" >&2; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$1" >&2; }
fi

# RUTOS_TEST_MODE enables trace logging (does NOT cause early exit)
# Script continues normal execution with enhanced debugging when RUTOS_TEST_MODE=1

# ==============================================================================
# Starlink API Version Monitor
#
# Version: 2.8.0
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
    log_debug "Attempting to load configuration from: $CONFIG_FILE"
    # Source the configuration file with error handling
    # shellcheck source=/dev/null
    if ! . "$CONFIG_FILE" 2>/dev/null; then
        log_error "CONFIGURATION ERROR: Failed to load $CONFIG_FILE"
        log_error "This usually indicates a syntax error in the configuration file."
        log_error "Common issues:"
        log_error "  - Missing quotes around values"
        log_error "  - Unescaped special characters"
        log_error "  - Missing 'export' keyword"
        log_error "  - Comments starting with words instead of #"
        log_error ""
        log_error "Please check line 775 and surrounding lines for syntax errors."
        log_error "Each variable should be: export VARIABLE_NAME=\"value\""
        log_error "Each comment should start with: # Comment text"
        exit 1
    fi
    log_debug "Configuration loaded successfully from: $CONFIG_FILE"
else
    log_debug "Configuration file not found: $CONFIG_FILE (using defaults)"
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
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"

# The file used to store the last known API version.
# /root/ is a persistent location on RUTOS/OpenWrt.
KNOWN_API_VERSION_FILE="/root/starlink_api_version.txt"

# Location of binaries - use installation directory paths
# These are installed by the install-rutos.sh script
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

# === DEBUG: Configuration Values Loaded ===
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "==================== API CHECKER CONFIGURATION DEBUG ===================="
    log_debug "CONFIG_FILE: $CONFIG_FILE"
    log_debug "Core connection settings:"
    log_debug "  STARLINK_IP: ${STARLINK_IP}"
    log_debug "  STARLINK_PORT: ${STARLINK_PORT}"
    log_debug "  INSTALL_DIR: ${INSTALL_DIR:-UNSET}"
    
    log_debug "Binary paths:"
    log_debug "  GRPCURL_CMD: ${GRPCURL_CMD}"
    log_debug "  JQ_CMD: ${JQ_CMD}"
    
    log_debug "Notification settings:"
    if [ "${#PUSHOVER_TOKEN}" -gt 10 ]; then
        log_debug "  PUSHOVER_TOKEN: ${PUSHOVER_TOKEN%"${PUSHOVER_TOKEN#??????????}"}... (length: ${#PUSHOVER_TOKEN})"
    else
        log_debug "  PUSHOVER_TOKEN: ${PUSHOVER_TOKEN} (length: ${#PUSHOVER_TOKEN})"
    fi
    if [ "${#PUSHOVER_USER}" -gt 10 ]; then
        log_debug "  PUSHOVER_USER: ${PUSHOVER_USER%"${PUSHOVER_USER#??????????}"}... (length: ${#PUSHOVER_USER})"
    else
        log_debug "  PUSHOVER_USER: ${PUSHOVER_USER} (length: ${#PUSHOVER_USER})"
    fi
    log_debug "  LOG_TAG: ${LOG_TAG}"
    
    log_debug "State files:"
    log_debug "  KNOWN_API_VERSION_FILE: ${KNOWN_API_VERSION_FILE}"
    
    # Check for functionality-affecting issues
    if [ "${STARLINK_IP:-}" = "" ]; then
        log_debug "⚠️  WARNING: STARLINK_IP not set - API calls will fail"
    fi
    if [ ! -f "${GRPCURL_CMD}" ]; then
        log_debug "⚠️  WARNING: grpcurl binary not found at ${GRPCURL_CMD} - API calls will fail"
    elif [ ! -x "${GRPCURL_CMD}" ]; then
        log_debug "⚠️  WARNING: grpcurl binary not executable at ${GRPCURL_CMD}"
    else
        log_debug "✓ grpcurl binary found and executable: ${GRPCURL_CMD}"
    fi
    if [ ! -f "${JQ_CMD}" ]; then
        log_debug "⚠️  WARNING: jq binary not found at ${JQ_CMD} - JSON parsing will fail"
    elif [ ! -x "${JQ_CMD}" ]; then
        log_debug "⚠️  WARNING: jq binary not executable at ${JQ_CMD}"
    else
        log_debug "✓ jq binary found and executable: ${JQ_CMD}"
    fi
    
    log_debug "Pushover notification validation:"
    if [ "${PUSHOVER_TOKEN}" = "YOUR_PUSHOVER_API_TOKEN" ]; then
        log_debug "⚠️  WARNING: PUSHOVER_TOKEN not configured - notifications will fail"
    elif [ "${#PUSHOVER_TOKEN}" -lt 30 ]; then
        log_debug "⚠️  WARNING: PUSHOVER_TOKEN appears too short (${#PUSHOVER_TOKEN} chars)"
    else
        log_debug "✓ PUSHOVER_TOKEN appears valid (${#PUSHOVER_TOKEN} chars)"
    fi
    
    if [ "${PUSHOVER_USER}" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log_debug "⚠️  WARNING: PUSHOVER_USER not configured - notifications will fail"
    elif [ "${#PUSHOVER_USER}" -lt 30 ]; then
        log_debug "⚠️  WARNING: PUSHOVER_USER appears too short (${#PUSHOVER_USER} chars)"
    else
        log_debug "✓ PUSHOVER_USER appears valid (${#PUSHOVER_USER} chars)"
    fi
    
    log_debug "======================================================================"
fi

# Dry-run and test mode support (FIXED: No early exit for RUTOS_TEST_MODE)
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "DRY_RUN=${DRY_RUN:-0}, RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0}"
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        log_debug "RUTOS_TEST_MODE enabled - trace logging active, script will continue normally"
    fi
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY_RUN enabled - no actual changes will be made"
    fi
fi

# Function to safely execute commands
# shellcheck disable=SC2317  # Function defined for dry-run support, called conditionally
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_debug "DRY-RUN: Would execute: $description"
        log_debug "DRY-RUN: Command: $cmd"
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "Executing: $cmd"
        fi
        eval "$cmd"
    fi
}

# --- Helper Functions ---
# Note: log_info, log_error, log_debug etc. are provided by RUTOS library

# Helper function for syslog integration - uses RUTOS library logging
log_syslog() {
    message="$1"
    # Use -- to prevent messages starting with - from being treated as options
    logger -t "$LOG_TAG" -- "$message"
    # Also use library logging for consistency
    log_info "$message"
}

# Validate binary with detailed logging
validate_binary() {
    binary_path="$1"
    binary_name="$2"

    log_debug "VALIDATING BINARY: $binary_name at $binary_path"

    if [ ! -f "$binary_path" ]; then
        log_syslog "ERROR: $binary_name not found at $binary_path"
        log_debug "FILE CHECK FAILED: $binary_path does not exist"
        return 1
    fi

    if [ ! -x "$binary_path" ]; then
        log_syslog "ERROR: $binary_name not executable at $binary_path"
        log_debug "PERMISSION CHECK FAILED: $binary_path is not executable"
        log_debug "FILE PERMISSIONS: $(ls -la "$binary_path" 2>/dev/null || echo 'Cannot read permissions')"
        return 1
    fi

    # Test if binary actually works
    log_debug "TESTING BINARY: $binary_path --help"
    if ! "$binary_path" --help >/dev/null 2>&1; then
        log_syslog "WARNING: $binary_name may not be functioning properly"
        log_debug "BINARY TEST FAILED: $binary_path --help returned non-zero"
    else
        log_debug "BINARY TEST PASSED: $binary_name is functional"
    fi

    return 0
}

send_notification() {
    title="$1"
    message="$2"

    log_debug "NOTIFICATION START: Preparing to send Pushover notification"
    log_debug "NOTIFICATION TITLE: '$title'"
    log_debug "NOTIFICATION MESSAGE: '$message'"
    log_debug "PUSHOVER_TOKEN: $(printf "%.10s..." "$PUSHOVER_TOKEN")"
    log_debug "PUSHOVER_USER: $(printf "%.10s..." "$PUSHOVER_USER")"

    log_syslog "Sending Pushover -> Title: '$title', Message: '$message'"

    # Validate that we have credentials
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ -z "$PUSHOVER_TOKEN" ]; then
        log_syslog "ERROR: PUSHOVER_TOKEN not configured properly"
        log_debug "NOTIFICATION FAILED: Invalid or missing PUSHOVER_TOKEN"
        return 1
    fi

    if [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ] || [ -z "$PUSHOVER_USER" ]; then
        log_syslog "ERROR: PUSHOVER_USER not configured properly"
        log_debug "NOTIFICATION FAILED: Invalid or missing PUSHOVER_USER"
        return 1
    fi

    # Execute curl with detailed logging
    log_debug "CURL COMMAND: curl -s --max-time 15 -F 'token=***' -F 'user=***' -F 'title=$title' -F 'message=$message' https://api.pushover.net/1/messages.json"

    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show curl output
        response=$(curl -s --max-time 15 \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "title=$title" \
            -F "message=$message" \
            https://api.pushover.net/1/messages.json 2>&1)
        curl_exit=$?
        log_debug "CURL EXIT CODE: $curl_exit"
        log_debug "CURL RESPONSE: $response"

        if [ $curl_exit -eq 0 ]; then
            log_syslog "Pushover notification sent successfully"
            log_debug "NOTIFICATION SUCCESS: Pushover API responded"
        else
            log_syslog "ERROR: Failed to send Pushover notification (curl exit: $curl_exit)"
            log_debug "NOTIFICATION FAILED: curl command failed"
        fi
    else
        # In normal mode, suppress output
        if curl -s --max-time 15 \
            -F "token=$PUSHOVER_TOKEN" \
            -F "user=$PUSHOVER_USER" \
            -F "title=$title" \
            -F "message=$message" \
            https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            log_syslog "Pushover notification sent successfully"
        else
            log_syslog "ERROR: Failed to send Pushover notification"
        fi
    fi
}

# --- Main Script ---

# Add test mode for troubleshooting
if [ "${TEST_MODE:-0}" = "1" ]; then
    log_debug "TEST MODE ENABLED: Running in test mode"
    DEBUG=1 # Force debug mode in test mode
    # Note: set -x disabled during testing to avoid verbose output in test suite
    log_debug "TEST MODE: Running with enhanced debug logging"
fi

log_debug "==================== STARLINK API CHECK START ===================="
log_debug "Starting API version check script"
log_debug "Script version: $SCRIPT_VERSION"
log_debug "Current working directory: $(pwd)"
log_debug "Script path: $0"
log_debug "Process ID: $$"
log_debug "User: $(whoami 2>/dev/null || echo 'unknown')"
log_debug "Environment DEBUG: ${DEBUG:-0}"

log_debug "CONFIGURATION VALUES:"
log_debug "  INSTALL_DIR=$INSTALL_DIR"
log_debug "  CONFIG_FILE=$CONFIG_FILE"
log_debug "  PUSHOVER_TOKEN=$(printf "%.10s..." "$PUSHOVER_TOKEN")"
log_debug "  PUSHOVER_USER=$(printf "%.10s..." "$PUSHOVER_USER")"
log_debug "  STARLINK_IP=$STARLINK_IP"
log_debug "  KNOWN_API_VERSION_FILE=$KNOWN_API_VERSION_FILE"
log_debug "  GRPCURL_CMD=$GRPCURL_CMD"
log_debug "  JQ_CMD=$JQ_CMD"
log_debug "  LOG_TAG=$LOG_TAG"

# Check if configuration file was loaded
if [ -f "$CONFIG_FILE" ]; then
    log_debug "CONFIG FILE: Successfully loaded from $CONFIG_FILE"
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "CONFIG FILE CONTENTS:"
        while IFS= read -r line; do
            # Don't log sensitive information in full
            case "$line" in
                *PUSHOVER_TOKEN* | *PUSHOVER_USER*)
                    log_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                    ;;
                *)
                    log_debug "  $line"
                    ;;
            esac
        done <"$CONFIG_FILE" 2>/dev/null || log_debug "  (Cannot read config file contents)"
    fi
else
    log_debug "CONFIG FILE: Not found at $CONFIG_FILE - using defaults"
fi

# Validate required binaries exist
log_debug "BINARY VALIDATION: Starting checks..."
if ! validate_binary "$GRPCURL_CMD" "grpcurl"; then
    log_debug "BINARY VALIDATION: grpcurl failed validation"
    exit 1
fi

if ! validate_binary "$JQ_CMD" "jq"; then
    log_debug "BINARY VALIDATION: jq failed validation"
    exit 1
fi

log_debug "BINARY VALIDATION: All binaries validated successfully"

log_syslog "--- Starting API version check ---"
log_debug "API VERSION CHECK: Starting main logic"

# Get the last known version from the file, defaulting to "0" if the file doesn't exist.
log_debug "KNOWN VERSION: Reading from $KNOWN_API_VERSION_FILE"
if [ -f "$KNOWN_API_VERSION_FILE" ]; then
    known_version=$(cat "$KNOWN_API_VERSION_FILE" 2>/dev/null || echo "0")
    log_debug "KNOWN VERSION: File exists, content: '$known_version'"
    # Validate the content
    if [ -z "$known_version" ]; then
        log_debug "KNOWN VERSION: File is empty, defaulting to '0'"
        known_version="0"
    fi
else
    known_version="0"
    log_debug "KNOWN VERSION: File does not exist, defaulting to '0'"
fi

log_debug "KNOWN VERSION: Final value: '$known_version'"

# Get the current version from the dish. We use 'get_device_info' as it's a lightweight call.
log_debug "CURRENT VERSION: Starting gRPC call to Starlink"
log_debug "GRPC CALL: $GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle"

# Build the gRPC command step by step for better debugging
grpc_cmd="$GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle"
log_debug "GRPC COMMAND: $grpc_cmd"

# Execute gRPC call with detailed error handling
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "GRPC EXECUTION: Running in debug mode with full output"
    grpc_output=$(eval "$grpc_cmd" 2>&1)
    grpc_exit=$?
    log_debug "GRPC EXIT CODE: $grpc_exit"
    log_debug "GRPC RAW OUTPUT (first 500 chars): $(echo "$grpc_output" | cut -c1-500)$([ ${#grpc_output} -gt 500 ] && echo '...')"

    if [ $grpc_exit -ne 0 ]; then
        log_syslog "ERROR: gRPC call failed with exit code $grpc_exit"
        log_debug "GRPC ERROR: Full output: $grpc_output"
        current_version="0"
    else
        log_debug "GRPC SUCCESS: Processing JSON response with jq"
        log_debug "JQ COMMAND: echo \"\$grpc_output\" | $JQ_CMD -r '.apiVersion // \"0\"'"

        current_version=$(echo "$grpc_output" | $JQ_CMD -r '.apiVersion // "0"' 2>&1)
        jq_exit=$?
        log_debug "JQ EXIT CODE: $jq_exit"
        log_debug "JQ OUTPUT: '$current_version'"

        if [ $jq_exit -ne 0 ]; then
            log_syslog "ERROR: Failed to parse JSON response with jq"
            log_debug "JQ ERROR: Failed to extract apiVersion"
            current_version="0"
        fi
    fi
else
    # Normal execution (less verbose)
    current_version=$(eval "$grpc_cmd" 2>/dev/null | $JQ_CMD -r '.apiVersion // "0"' 2>/dev/null || echo "0")
fi

log_debug "CURRENT VERSION: Final extracted value: '$current_version'"

# Validate the current version
if [ "$current_version" = "0" ] || [ -z "$current_version" ] || [ "$current_version" = "null" ]; then
    log_syslog "ERROR: Could not retrieve current API version from dish. Skipping check."
    log_debug "VERSION VALIDATION: Current version is invalid ('$current_version')"
    log_debug "POSSIBLE CAUSES:"
    log_debug "  - Starlink dish is unreachable at $STARLINK_IP"
    log_debug "  - gRPC API is not responding"
    log_debug "  - API response format has changed"
    log_debug "  - Network connectivity issues"
    log_debug "API VERSION CHECK: Exiting due to invalid current version"
    exit 0
fi

log_syslog "INFO: Known version: $known_version, Current version: $current_version"
log_debug "VERSION COMPARISON: Comparing '$current_version' with '$known_version'"

# Compare the current version with the last known version.
if [ "$current_version" != "$known_version" ]; then
    # --- API VERSION HAS CHANGED ---
    log_syslog "WARN: API version has changed from $known_version to $current_version. Sending notification."
    log_debug "VERSION CHANGE DETECTED: From '$known_version' to '$current_version'"

    MESSAGE="Starlink API version has changed from $known_version to $current_version. Please check if monitoring scripts need updates."
    TITLE="Starlink API Alert"

    log_debug "NOTIFICATION: Preparing to send alert"
    log_debug "NOTIFICATION TITLE: '$TITLE'"
    log_debug "NOTIFICATION MESSAGE: '$MESSAGE'"

    # Send notification with detailed error handling
    if send_notification "$TITLE" "$MESSAGE"; then
        log_debug "NOTIFICATION: Successfully sent"
    else
        log_syslog "ERROR: Failed to send notification, but continuing with version update"
        log_debug "NOTIFICATION: Failed to send, but not blocking version file update"
    fi

    # Update the known version file with the new version for the next check.
    log_debug "VERSION FILE UPDATE: Writing '$current_version' to $KNOWN_API_VERSION_FILE"

    if echo "$current_version" >"$KNOWN_API_VERSION_FILE" 2>/dev/null; then
        log_syslog "INFO: Updated known version file to $current_version."
        log_debug "VERSION FILE UPDATE: Successfully wrote to file"

        # Verify the write was successful
        if [ "${DEBUG:-0}" = "1" ]; then
            written_version=$(cat "$KNOWN_API_VERSION_FILE" 2>/dev/null || echo "FAILED_TO_READ")
            log_debug "VERSION FILE VERIFY: File now contains: '$written_version'"
            if [ "$written_version" = "$current_version" ]; then
                log_debug "VERSION FILE VERIFY: Write verification successful"
            else
                log_debug "VERSION FILE VERIFY: Write verification failed!"
                log_syslog "WARNING: Version file update may have failed"
            fi
        fi
    else
        log_syslog "ERROR: Failed to update known version file"
        log_debug "VERSION FILE UPDATE: Write failed - check permissions on $KNOWN_API_VERSION_FILE"
        log_debug "DIRECTORY PERMISSIONS: $(ls -la "$(dirname "$KNOWN_API_VERSION_FILE")" 2>/dev/null || echo 'Cannot read directory permissions')"
    fi
else
    log_syslog "INFO: API version is unchanged. No action needed."
    log_debug "VERSION COMPARISON: No change detected, no action required"
fi

log_debug "API VERSION CHECK: Completing successfully"

log_syslog "--- API version check finished ---"
log_debug "==================== STARLINK API CHECK COMPLETE ===================="
log_debug "Final status: SUCCESS"
log_debug "Script execution completed normally"
log_debug "Exit code: 0"

# Clean up any temporary files
if [ -f /tmp/api_check_error.log ]; then
    log_debug "CLEANUP: Removing temporary error log"
    rm -f /tmp/api_check_error.log
fi

exit 0
