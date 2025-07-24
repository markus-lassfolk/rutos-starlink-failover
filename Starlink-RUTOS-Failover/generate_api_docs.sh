#!/bin/sh

# ==============================================================================
# Starlink API Documentation Generator
#
# Version: 2.6.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script is a utility for developers and enthusiasts who want to explore
# the Starlink gRPC API. It systematically calls a list of known "get" methods,
# formats the JSON response, and saves everything to a single, timestamped
# Markdown file.
#
# The resulting file serves as a perfect snapshot of the API structure for a
# given firmware version, making it invaluable for tracking changes over time
# and discovering new data points for monitoring.
#
# ==============================================================================

# Exit on first error, undefined variable, or pipe failure for script robustness.
set -eu

# Standard colors for consistent output (compatible with busybox)
# Note: Colors defined for consistency but not used in this documentation script
# shellcheck disable=SC2034  # Colors may not be used but should be defined for consistency

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    YELLOW=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    BLUE=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    CYAN=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    NC=""
fi

# --- User Configuration ---

# The IP address and port for the Starlink gRPC API. This is standard.
STARLINK_IP="192.168.100.1:9200"

# The directory where the final documentation file will be saved.
OUTPUT_DIR="/root"

# --- System Configuration (Advanced) ---

# Location of binaries. Assumes they are in the system's PATH.
# If you placed them in /root/, change these to /root/grpcurl and /root/jq.
GRPCURL_CMD="grpcurl"
JQ_CMD="jq"

# --- API Methods to Call ---
# This list contains the known safe, read-only "get" commands.
# Action commands like 'reboot' or 'dish_stow' are intentionally excluded.
METHODS_TO_CALL="
get_status
get_history
get_device_info
get_diagnostics
get_location
"

# --- Main Script ---

# --- 1. Get API Version for Filename ---
echo "Fetching current API version..."
# We use 'get_device_info' as it's a lightweight and reliable call.
# The 'apiVersion' is a top-level key in the response.
api_version=$($GRPCURL_CMD -plaintext -max-time 5 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.apiVersion // "UNKNOWN"')

if [ "$api_version" = "UNKNOWN" ]; then
    echo "Warning: Could not determine API version. Using default filename."
fi
echo "API version found: $api_version"

# --- 2. Define Output File ---
# The filename includes the API version and current date for easy tracking.
# The .md extension allows for nice formatting on GitHub.
FILENAME="${OUTPUT_DIR}/starlink_api_dump_v${api_version}_$(date '+%Y-%m-%d').md"

# --- 3. Generate Documentation ---
echo "================================================="
echo "Full output will be saved to: $FILENAME"
echo "================================================="

# Clear the output file to start fresh.
true >"$FILENAME"

# Loop through each method in the list.
for method in $METHODS_TO_CALL; do
    # Print status to the console.
    echo ""
    echo "--- Executing: $method ---"

    # The JSON payload required by grpcurl.
    json_data="{\"${method}\":{}}"

    # Add a Markdown header for this section to the output file.
    {
        echo ""
        echo "## Command: ${method}"
        echo '```json'
    } >>"$FILENAME"

    # Execute the grpcurl command.
    # The output is piped to jq to be pretty-printed, then appended to our file.

    if ! $GRPCURL_CMD -plaintext -max-time 10 -d "$json_data" "$STARLINK_IP" SpaceX.API.Device.Device/Handle | $JQ_CMD '.' >>"$FILENAME"; then
        echo "ERROR: grpcurl command failed for method: $method"
        echo "ERROR: grpcurl command failed for method: $method" >>"$FILENAME"
    fi

    # Close the Markdown code block.
    echo '```' >>"$FILENAME"
done

echo ""
echo "================================================="
# Version information for troubleshooting
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

echo "Done. API documentation saved to $FILENAME"
