#!/bin/sh

# ==============================================================================
# Starlink API Documentation Generator
#
# Version: 1.0.2 (Public Edition)
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

# Script version information
SCRIPT_VERSION="1.0.2"

# Standard colors for consistent output (compatible with busybox)
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

# Standard logging functions with consistent colors
log_info() {
    printf "%s[INFO]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "%s[WARNING]%s [%s] %s\n" "$YELLOW" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "%s[ERROR]%s [%s] %s\n" "$RED" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "%s[DEBUG]%s [%s] %s\n" "$CYAN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "%s[SUCCESS]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "%s[STEP]%s [%s] %s\n" "$BLUE" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"

# Debug mode initialization
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Debug function for command execution
debug_exec() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "EXECUTING: $*"
    fi
    "$@"
}

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
log_info "Starting Starlink API documentation generator v$SCRIPT_VERSION"
log_debug "Starlink IP: $STARLINK_IP"
log_debug "Output directory: $OUTPUT_DIR"
log_debug "grpcurl command: $GRPCURL_CMD"
log_debug "jq command: $JQ_CMD"

log_info "Fetching current API version..."
# We use 'get_device_info' as it's a lightweight and reliable call.
# The 'apiVersion' is a top-level key in the response.
api_version=$($GRPCURL_CMD -plaintext -max-time 5 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.apiVersion // "UNKNOWN"')

if [ "$api_version" = "UNKNOWN" ]; then
	log_warning "Could not determine API version. Using default filename."
fi
log_info "API version found: $api_version"

# --- 2. Define Output File ---
# The filename includes the API version and current date for easy tracking.
# The .md extension allows for nice formatting on GitHub.
FILENAME="${OUTPUT_DIR}/starlink_api_dump_v${api_version}_$(date '+%Y-%m-%d').md"
log_debug "Output filename: $FILENAME"

# --- 3. Generate Documentation ---
log_step "Starting API documentation generation"
log_info "Full output will be saved to: $FILENAME"
log_step "Processing API methods..."

# Clear the output file to start fresh.
true >"$FILENAME"

# Loop through each method in the list.
for method in $METHODS_TO_CALL; do
	# Print status to the console.
	log_step "Executing API method: $method"
	log_debug "JSON payload: {\"${method}\":{}}"

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
		log_error "grpcurl command failed for method: $method"
		echo "ERROR: grpcurl command failed for method: $method" >>"$FILENAME"
	else
		log_debug "Successfully processed method: $method"
	fi

	# Close the Markdown code block.
	echo '```' >>"$FILENAME"
done

log_success "API documentation generation completed successfully"
log_info "Documentation saved to: $FILENAME"
