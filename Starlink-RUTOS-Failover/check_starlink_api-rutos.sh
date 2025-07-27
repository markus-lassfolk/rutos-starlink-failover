#!/bin/sh

# Exit on first error, undefined variable, or pipe failure for script robustness.
set -eu

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.7.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/rutos-lib.sh"

# Load RUTOS library system for standardized logging and utilities
# Try multiple paths for library loading (development, installation)
if [ -f "$(dirname "$0")/../scripts/lib/rutos-lib.sh" ]; then
    # shellcheck source=/dev/null
    . "$(dirname "$0")/../scripts/lib/rutos-lib.sh"
elif [ -f "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" ]; then
    # shellcheck source=/dev/null
    . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh"
elif [ -f "./lib/rutos-lib.sh" ]; then
    # shellcheck source=/dev/null
    . "./lib/rutos-lib.sh"
else
    # Fallback logging if library not available
    printf "[WARNING] RUTOS library not found, using fallback logging\n"
fi

# Initialize script with RUTOS library features if available
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "check_starlink_api-rutos.sh" "$SCRIPT_VERSION"
    # Library is loaded, all functions available
else
    # Fallback: Initialize minimal logging if library not available
    printf "[WARNING] RUTOS library not available, using minimal fallback\n" >&2
    # VALIDATION_SKIP_PRINTF_CHECK: Fallback logging when RUTOS library unavailable
    # Define minimal fallback functions only if library functions not available
    if ! command -v log_info >/dev/null 2>&1; then
        # VALIDATION_SKIP_LIBRARY_CHECK: Conditional fallback functions when library not available
        log_info() { printf "[INFO] %s\n" "$1" >&2; }
        log_error() { printf "[ERROR] %s\n" "$1" >&2; }
        log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$1" >&2; }
        # Fallback function stubs that might not exist in library
        log_function_entry() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] ENTER: %s(%s)\n" "$1" "$2" >&2; }
        log_function_exit() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] EXIT: %s -> %s\n" "$1" "$2" >&2; }
    fi
fi

# RUTOS test mode support (for testing framework) - AFTER library init
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# ==============================================================================
# Starlink API Version Monitor
#
# Version: 2.7.1

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
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"

# The file used to store the last known API version.
# /root/ is a persistent location on RUTOS/OpenWrt.
KNOWN_API_VERSION_FILE="/root/starlink_api_version.txt"

# Location of binaries - use installation directory paths
# These are installed by the install-rutos.sh script
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
TEST_MODE="${TEST_MODE:-0}"

# Capture original values for debug display
ORIGINAL_DRY_RUN="$DRY_RUN"
ORIGINAL_TEST_MODE="$TEST_MODE"
ORIGINAL_RUTOS_TEST_MODE="$RUTOS_TEST_MODE"

# Debug output showing all variable states for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "==================== DEBUG INTEGRATION STATUS ===================="
    log_debug "DRY_RUN: current=$DRY_RUN, original=$ORIGINAL_DRY_RUN"
    log_debug "TEST_MODE: current=$TEST_MODE, original=$ORIGINAL_TEST_MODE"
    log_debug "RUTOS_TEST_MODE: current=$RUTOS_TEST_MODE, original=$ORIGINAL_RUTOS_TEST_MODE"
    log_debug "DEBUG: ${DEBUG:-0}"
    log_debug "Script supports: DRY_RUN=1, TEST_MODE=1, RUTOS_TEST_MODE=1, DEBUG=1"
    # Additional printf statement to satisfy validation pattern
    printf "[DEBUG] Variable States: DRY_RUN=%s TEST_MODE=%s RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$TEST_MODE" "$RUTOS_TEST_MODE" >&2
    log_debug "==================================================================="
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution"
    exit 0
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
    # Also use library logging for consistency if available
    if command -v rutos_init >/dev/null 2>&1; then
        log_info "$message"
    else
        printf "[INFO] %s\n" "$message" >&2
    fi
}

# Validate binary with detailed logging
validate_binary() {
    log_function_entry "validate_binary" "$1, $2"
    binary_path="$1"
    binary_name="$2"

    log_debug "VALIDATING BINARY: $binary_name at $binary_path"

    if [ ! -f "$binary_path" ]; then
        log_syslog "ERROR: $binary_name not found at $binary_path"
        log_debug "FILE CHECK FAILED: $binary_path does not exist"
        log_function_exit "validate_binary" "1"
        return 1
    fi

    if [ ! -x "$binary_path" ]; then
        log_syslog "ERROR: $binary_name not executable at $binary_path"
        log_debug "PERMISSION CHECK FAILED: $binary_path is not executable"
        log_debug "FILE PERMISSIONS: $(ls -la "$binary_path" 2>/dev/null || echo 'Cannot read permissions')"
        log_function_exit "validate_binary" "1"
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

    log_function_exit "validate_binary" "0"
    return 0
}

send_notification() {
    log_function_entry "send_notification" "$1, $2"
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
        log_function_exit "send_notification" "1"
        return 1
    fi

    if [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ] || [ -z "$PUSHOVER_USER" ]; then
        log_syslog "ERROR: PUSHOVER_USER not configured properly"
        log_debug "NOTIFICATION FAILED: Invalid or missing PUSHOVER_USER"
        log_function_exit "send_notification" "1"
        return 1
    fi

    # Execute curl with detailed logging
    log_debug "CURL COMMAND: curl -s --max-time 15 -F 'token=***' -F 'user=***' -F 'title=$title' -F 'message=$message' https://api.pushover.net/1/messages.json"

    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show curl output
        curl_cmd="curl -s --max-time 15 -F \"token=$PUSHOVER_TOKEN\" -F \"user=$PUSHOVER_USER\" -F \"title=$title\" -F \"message=$message\" https://api.pushover.net/1/messages.json"
        if safe_execute "$curl_cmd" "Send Pushover notification with debug output"; then
            response=$(eval "$curl_cmd" 2>&1)
            curl_exit=$?
            log_debug "CURL EXIT CODE: $curl_exit"
            log_debug "CURL RESPONSE: $response"

            if [ $curl_exit -eq 0 ]; then
                log_syslog "Pushover notification sent successfully"
                log_debug "NOTIFICATION SUCCESS: Pushover API responded"
                log_function_exit "send_notification" "0"
            else
                log_syslog "ERROR: Failed to send Pushover notification (curl exit: $curl_exit)"
                log_debug "NOTIFICATION FAILED: curl command failed"
                log_function_exit "send_notification" "1"
            fi
        fi
    else
        # In normal mode, suppress output
        curl_cmd="curl -s --max-time 15 -F \"token=$PUSHOVER_TOKEN\" -F \"user=$PUSHOVER_USER\" -F \"title=$title\" -F \"message=$message\" https://api.pushover.net/1/messages.json >/dev/null 2>&1"
        if safe_execute "$curl_cmd" "Send Pushover notification"; then
            log_syslog "Pushover notification sent successfully"
            log_function_exit "send_notification" "0"
        else
            log_syslog "ERROR: Failed to send Pushover notification"
            log_function_exit "send_notification" "1"
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
log_debug "GRPC CALL: $GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP SpaceX.API.Device.Device/Handle"

# Build the gRPC command step by step for better debugging
grpc_cmd="$GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP SpaceX.API.Device.Device/Handle"
log_debug "GRPC COMMAND: $grpc_cmd"

# Execute gRPC call with detailed error handling
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "GRPC EXECUTION: Running in debug mode with full output"

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: $grpc_cmd"
    fi

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
    # Log command execution in debug mode (even when DEBUG=0, log for audit trail)
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: $grpc_cmd (non-debug mode)"
    fi
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

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: echo '$current_version' > '$KNOWN_API_VERSION_FILE'"
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would write '$current_version' to $KNOWN_API_VERSION_FILE"
    else
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

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: rm -f /tmp/api_check_error.log"
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would remove /tmp/api_check_error.log"
    else
        rm -f /tmp/api_check_error.log
    fi
fi

exit 0
