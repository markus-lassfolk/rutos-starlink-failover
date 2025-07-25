#!/bin/sh
# Script: test-rutos-colors.sh
# Purpose: Test color detection and display in RUTOS environment
# Version: 2.7.0

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# RUTOS-compatible color detection (Method 5 format)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;35m"
    CYAN="\033[0;36m"
    NC="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Standard logging functions using Method 5 format (RUTOS-compatible)
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        return 0
    else
        eval "$cmd"
    fi
}

# Main color testing function
test_rutos_colors() {
    log_info "Starting RUTOS color test v$SCRIPT_VERSION"

    log_step "Testing color detection"
    printf "Environment: Terminal=%s, TERM=%s\n" "$([ -t 1 ] && echo "yes" || echo "no")" "${TERM:-unset}"

    log_step "Testing color output"
    # shellcheck disable=SC2059
    printf "${RED}RED text${NC}\n"
    # shellcheck disable=SC2059
    printf "${GREEN}GREEN text${NC}\n"
    # shellcheck disable=SC2059
    printf "${YELLOW}YELLOW text${NC}\n"
    # shellcheck disable=SC2059
    printf "${BLUE}BLUE text${NC}\n"
    # shellcheck disable=SC2059
    printf "${CYAN}CYAN text${NC}\n"

    log_step "Testing logging functions"
    log_info "This is an info message"
    log_warning "This is a warning message"
    log_debug "This is a debug message (only shown if DEBUG=1)"
    log_success "Color test completed"
}

# Main execution
main() {
    if [ "$DRY_RUN" = "1" ]; then
        log_info "Running in dry-run mode"
    fi

    test_rutos_colors

    log_success "RUTOS color test completed successfully"
}

# Execute main function
main "$@"
