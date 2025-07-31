#!/bin/sh
# ==============================================================================
# Debug Starlink API and Logger Issue
#
# Version: 2.8.0
# Description: Diagnoses why the logger reports "No new data samples"
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Standard colors for output
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_debug() {
    printf "${CYAN}[DEBUG]${NC} %s\n" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Load configuration
CONFIG_FILE="/etc/starlink-config/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

# Set defaults
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"

# Binary paths
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

main() {
    log_info "Starlink API Debug Tool v$SCRIPT_VERSION"
    echo ""

    # Check if we're on RUTOS
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Step 1: Check binary availability
    log_step "Checking required binaries"

    if [ ! -x "$GRPCURL_CMD" ]; then
        log_error "grpcurl not found at: $GRPCURL_CMD"
        exit 1
    else
        log_info "grpcurl found: $GRPCURL_CMD"
    fi

    if [ ! -x "$JQ_CMD" ]; then
        log_error "jq not found at: $JQ_CMD"
        exit 1
    else
        log_info "jq found: $JQ_CMD"
    fi
    echo ""

    # Step 2: Test API connectivity
    log_step "Testing Starlink API connectivity"
    log_debug "Endpoint: $STARLINK_IP:$STARLINK_PORT"

    log_debug "Making get_status API call..."
    status_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetStatus' 2>/dev/null)
    status_exit=$?

    if [ $status_exit -eq 0 ] && [ -n "$status_data" ]; then
        log_info "✅ get_status API call successful"
        log_debug "Status data length: ${#status_data} characters"
    else
        log_error "❌ get_status API call failed (exit code: $status_exit)"
        echo ""
        log_error "This explains why the logger says 'No new data' - API is not responding!"
        exit 1
    fi

    log_debug "Making get_history API call..."
    history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory' 2>/dev/null)
    history_exit=$?

    if [ $history_exit -eq 0 ] && [ -n "$history_data" ]; then
        log_info "✅ get_history API call successful"
        log_debug "History data length: ${#history_data} characters"
    else
        log_error "❌ get_history API call failed (exit code: $history_exit)"
        echo ""
        log_error "This explains why the logger says 'No new data' - API is not responding!"
        exit 1
    fi
    echo ""

    # Step 3: Analyze sample indices
    log_step "Analyzing sample indices (logger logic)"

    # Extract current sample index from API
    current_sample_index=$(echo "$history_data" | $JQ_CMD -r '.current' 2>/dev/null)
    if [ -z "$current_sample_index" ] || [ "$current_sample_index" = "null" ]; then
        log_error "Failed to extract current sample index from API response"
        log_debug "Raw history_data preview: $(echo "$history_data" | head -c 200)"
        exit 1
    fi

    # Get last sample index from tracking file
    last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "$((current_sample_index - 1))")

    log_info "Current sample index (from API): $current_sample_index"
    log_info "Last logged sample index: $last_sample_index"
    log_info "Difference: $((current_sample_index - last_sample_index))"

    # This is the exact logic from the logger
    if [ "$current_sample_index" -le "$last_sample_index" ]; then
        log_warn "⚠️  Logger logic: No new samples to log"
        log_warn "This is why you see 'No new data samples to log' message"
        echo ""
        log_step "Possible causes:"
        log_info "1. Starlink not generating new samples (normal during stable operation)"
        log_info "2. Logger running too frequently (every minute may be too often)"
        log_info "3. Sample tracking file has incorrect index"
        log_info "4. Starlink in failover mode may reduce sample generation"
    else
        log_info "✅ New samples available for logging"
        log_info "Logger should process samples from $last_sample_index to $current_sample_index"
    fi
    echo ""

    # Step 4: Check sample timing
    log_step "Checking sample generation timing"

    # Wait and check again to see if samples are being generated
    log_debug "Waiting 30 seconds to check for new samples..."
    sleep 30

    new_history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory' 2>/dev/null)
    new_sample_index=$(echo "$new_history_data" | $JQ_CMD -r '.current' 2>/dev/null)

    if [ "$new_sample_index" -gt "$current_sample_index" ]; then
        log_info "✅ New samples generated in 30 seconds"
        log_info "Old index: $current_sample_index, New index: $new_sample_index"
        log_info "Sample generation rate: $((new_sample_index - current_sample_index)) samples/30s"
    else
        log_warn "⚠️  No new samples in 30 seconds"
        log_warn "This suggests Starlink generates samples slower than every minute"
        log_warn "OR Starlink reduces sampling during failover/stable periods"
    fi
    echo ""

    # Step 5: Check tracking file
    log_step "Checking sample tracking file"

    if [ -f "$LAST_SAMPLE_FILE" ]; then
        log_info "Tracking file exists: $LAST_SAMPLE_FILE"
        log_info "Content: $(cat "$LAST_SAMPLE_FILE")"
        log_info "Last modified: $(stat -c '%y' "$LAST_SAMPLE_FILE" 2>/dev/null || echo 'unknown')"
    else
        log_warn "Tracking file does not exist: $LAST_SAMPLE_FILE"
        log_info "This would cause logger to use default: $((current_sample_index - 1))"
    fi
    echo ""

    # Step 6: Summary and recommendations
    log_step "Summary and Recommendations"

    if [ "$current_sample_index" -le "$last_sample_index" ]; then
        log_info "🔍 Root Cause: No new samples available for logging"
        log_info ""
        log_info "📊 This is likely normal behavior when:"
        log_info "   • Starlink connection is stable (fewer samples needed)"
        log_info "   • Running in failover mode (reduced monitoring)"
        log_info "   • Logger runs more frequently than sample generation"
        log_info ""
        log_info "💡 Recommendations:"
        log_info "   • Consider reducing logger frequency (every 5-15 minutes instead of 1)"
        log_info "   • This behavior may change when Starlink becomes primary again"
        log_info "   • The CSV logging is still valuable for when samples ARE generated"
    else
        log_info "✅ Logger should be working - new samples are available"
        log_warn "If you still see 'No new data' messages, there may be another issue"
    fi

    log_info ""
    log_info "The 'No new data' messages are informational, not errors"
    log_info "CSV logging will work properly when new samples are available"
}

# Execute main function
main "$@"
