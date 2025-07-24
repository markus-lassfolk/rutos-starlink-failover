#!/bin/sh
# Script: test-method5-final.sh
# Purpose: Final validation that Method 5 format works across all converted scripts
# This script tests the Method 5 format that we confirmed works in RUTOS

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Method 5 color definitions (the working format for RUTOS)
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

# Method 5 logging functions (confirmed working format)
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
    printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
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

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Main test function
main() {
    printf "==========================================\n"
    printf "Method 5 Format Final Validation Test\n"
    printf "Script Version: %s\n" "$SCRIPT_VERSION"
    printf "==========================================\n"
    printf "\n"

    log_step "Testing Method 5 color format (the working format)"
    log_info "This should show in GREEN with proper color codes"
    log_warning "This should show in YELLOW with proper color codes"
    log_error "This should show in RED with proper color codes"
    log_debug "This should show in CYAN with proper color codes"
    log_success "This should show in GREEN with SUCCESS label"

    printf "\n"
    printf "Direct printf tests using Method 5 format:\n"
    # shellcheck disable=SC2059
    printf "${GREEN}✓ GREEN${NC} - This should be green\n"
    # shellcheck disable=SC2059
    printf "${YELLOW}⚠ YELLOW${NC} - This should be yellow\n"
    # shellcheck disable=SC2059
    printf "${RED}✗ RED${NC} - This should be red\n"
    # shellcheck disable=SC2059
    printf "${BLUE}▶ BLUE${NC} - This should be blue\n"
    # shellcheck disable=SC2059
    printf "${CYAN}ℹ CYAN${NC} - This should be cyan\n"

    printf "\n"
    printf "Environment Detection:\n"
    printf "TERM: %s\n" "${TERM:-<not set>}"
    printf "SSH_TTY: %s\n" "${SSH_TTY:-<not set>}"
    printf "Terminal test: %s\n" "$([ -t 1 ] && echo "TTY detected" || echo "No TTY")"
    printf "Colors: %s\n" "$([ -n "$RED" ] && echo "ENABLED" || echo "DISABLED")"

    printf "\n"
    log_success "Method 5 format validation complete"
    printf "\n"
    printf "If you see actual colors (not raw escape codes),\n"
    printf "then Method 5 format is working correctly in your environment!\n"
    printf "==========================================\n"
}

# Execute main function
main "$@"