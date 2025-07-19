#!/bin/sh
# Script: test-method5-final.sh
# Purpose: Final validation that Method 5 format works across all converted scripts
# This script tests the Method 5 format that we confirmed works in RUTOS

set -e

# Version information
SCRIPT_VERSION="1.0.0"

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

# Main test function
main() {
    echo "=========================================="
    echo "Method 5 Format Final Validation Test"
    echo "Script Version: $SCRIPT_VERSION"
    echo "=========================================="
    echo ""

    log_step "Testing Method 5 color format (the working format)"
    log_info "This should show in GREEN with proper color codes"
    log_warning "This should show in YELLOW with proper color codes"
    log_error "This should show in RED with proper color codes"
    log_debug "This should show in CYAN with proper color codes"
    log_success "This should show in GREEN with SUCCESS label"

    echo ""
    echo "Direct printf tests using Method 5 format:"
    printf "${GREEN}✓ GREEN${NC} - This should be green\n"
    printf "${YELLOW}⚠ YELLOW${NC} - This should be yellow\n"
    printf "${RED}✗ RED${NC} - This should be red\n"
    printf "${BLUE}▶ BLUE${NC} - This should be blue\n"
    printf "${CYAN}ℹ CYAN${NC} - This should be cyan\n"

    echo ""
    echo "Environment Detection:"
    echo "TERM: ${TERM:-<not set>}"
    echo "SSH_TTY: ${SSH_TTY:-<not set>}"
    echo "Terminal test: $([ -t 1 ] && echo "TTY detected" || echo "No TTY")"
    echo "Colors: $([ -n "$RED" ] && echo "ENABLED" || echo "DISABLED")"

    echo ""
    log_success "Method 5 format validation complete"
    echo ""
    echo "If you see actual colors (not escape codes like \\033[0;32m),"
    echo "then Method 5 format is working correctly in your environment!"
    echo "=========================================="
}

# Execute main function
main "$@"
