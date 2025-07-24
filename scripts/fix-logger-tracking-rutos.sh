#!/bin/sh
# ==============================================================================
# Fix Starlink Logger Sample Tracking Issue
#
# Version: 1.0.0
# Description: Fixes the sample tracking file when it has a stale high index
# shellcheck disable=SC2059 # Method 5 printf format required for RUTOS color compatibility
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Standard colors for output
# shellcheck disable=SC2034  # Color variables may not all be used but are needed for printf compatibility
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

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

# Parse arguments
DRY_RUN=0
DEBUG=0

case "${1:-}" in
    --dry-run)
        DRY_RUN=1
        ;;
    --debug)
        DEBUG=1
        export DEBUG # Export so it can be used by debug_log function
        ;;
    --help | -h)
        cat <<EOF
Starlink Logger Sample Tracking Fix v$SCRIPT_VERSION

DESCRIPTION:
    Fixes the sample tracking file when it contains a stale high index
    that prevents new samples from being logged.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run       Show what would be done without making changes
    --debug         Enable verbose debug logging
    --help, -h      Show this help message

EXAMPLES:
    # Test what would be fixed (safe)
    $0 --dry-run

    # Apply the fix
    $0
EOF
        exit 0
        ;;
esac

# Load configuration
CONFIG_FILE="/etc/starlink-config/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null  # Config file path is dynamic
    . "$CONFIG_FILE"
fi

# Set defaults
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"

# Binary paths
GRPCURL_CMD="$INSTALL_DIR/grpcurl"
JQ_CMD="$INSTALL_DIR/jq"

main() {
    log_info "Starlink Logger Sample Tracking Fix v$SCRIPT_VERSION"
    echo ""

    if [ "$DRY_RUN" = "1" ]; then
        log_warn "DRY-RUN MODE: No changes will be made"
    fi

    # Check if we're on RUTOS
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Check required binaries
    log_step "Checking required binaries"
    if [ ! -x "$GRPCURL_CMD" ] || [ ! -x "$JQ_CMD" ]; then
        log_error "Required binaries not found. Please run installation script first."
        exit 1
    fi

    # Get current API sample index
    log_step "Getting current API sample index"
    history_data=$($GRPCURL_CMD -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | $JQ_CMD -r '.dishGetHistory' 2>/dev/null)

    if [ -z "$history_data" ]; then
        log_error "Failed to get data from Starlink API"
        exit 1
    fi

    current_sample_index=$(echo "$history_data" | $JQ_CMD -r '.current' 2>/dev/null)
    if [ -z "$current_sample_index" ] || [ "$current_sample_index" = "null" ]; then
        log_error "Failed to extract current sample index from API"
        exit 1
    fi

    log_info "Current API sample index: $current_sample_index"

    # Check tracking file
    log_step "Checking sample tracking file"
    if [ -f "$LAST_SAMPLE_FILE" ]; then
        last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null)
        log_info "Tracking file exists: $LAST_SAMPLE_FILE"
        log_info "Last logged sample index: $last_sample_index"

        # Check if tracking index is higher than current API index (the problem)
        if [ "$last_sample_index" -gt "$current_sample_index" ]; then
            log_warn "PROBLEM DETECTED: Tracking index ($last_sample_index) > API index ($current_sample_index)"
            log_warn "This prevents new samples from being logged"

            # Calculate a good reset value (current index - 1)
            new_index=$((current_sample_index - 1))
            log_info "Recommended reset value: $new_index"

            if [ "$DRY_RUN" = "1" ]; then
                log_warn "DRY-RUN: Would reset tracking file to: $new_index"
            else
                log_step "Resetting tracking file"
                if echo "$new_index" >"$LAST_SAMPLE_FILE"; then
                    log_success "Tracking file reset to: $new_index"
                    log_success "Logger should now process new samples!"
                else
                    log_error "Failed to update tracking file"
                    exit 1
                fi
            fi
        else
            log_info "✅ Tracking file looks correct (not higher than API index)"
            log_info "The issue may be something else"
        fi
    else
        log_warn "Tracking file does not exist: $LAST_SAMPLE_FILE"
        log_info "This should cause logger to use default: $((current_sample_index - 1))"

        if [ "$DRY_RUN" = "1" ]; then
            log_warn "DRY-RUN: Would create tracking file with: $((current_sample_index - 1))"
        else
            log_step "Creating tracking file"
            mkdir -p "$(dirname "$LAST_SAMPLE_FILE")"
            if echo "$((current_sample_index - 1))" >"$LAST_SAMPLE_FILE"; then
                log_success "Created tracking file with: $((current_sample_index - 1))"
            else
                log_error "Failed to create tracking file"
                exit 1
            fi
        fi
    fi

    # Test that samples will now be logged
    log_step "Verification"
    if [ "$DRY_RUN" = "0" ]; then
        # Re-read the tracking file
        new_last_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null)
        log_info "Updated tracking index: $new_last_index"
        log_info "Current API index: $current_sample_index"

        if [ "$new_last_index" -lt "$current_sample_index" ]; then
            log_success "✅ Fix applied successfully!"
            log_success "Logger should now log $((current_sample_index - new_last_index)) samples on next run"
        else
            log_warn "Tracking index is still not less than API index"
        fi
    fi

    echo ""
    log_info "🔍 Check the logger output in the next few minutes:"
    log_info "   logread | grep 'Processing samples'"
    log_info "   (Should show samples being processed instead of 'No new data')"
}

# Execute main function
main "$@"
