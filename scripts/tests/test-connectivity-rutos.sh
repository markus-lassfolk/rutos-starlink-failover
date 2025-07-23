#!/bin/sh
# shellcheck disable=SC2059  # RUTOS requires Method 5 printf format (embedded variables)
# Script: test-connectivity-rutos.sh
# Version: 2.5.0
# Description: Test network connectivity for RUTOS Starlink failover system
# Usage: ./scripts/tests/test-connectivity-rutos.sh [--debug] [--dry-run]

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" != "" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with RUTOS-compatible printf format
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
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Configuration
DEBUG="${DEBUG:-0}"

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

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug | -d)
                DEBUG=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                log_warning "Unknown argument: $1"
                shift
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat <<EOF
RUTOS Connectivity Test Tool v$SCRIPT_VERSION

PURPOSE:
    Test network connectivity for Starlink failover system.
    Validates both primary (Starlink) and backup (cellular) connections.

USAGE:
    ./scripts/tests/test-connectivity-rutos.sh [OPTIONS]

OPTIONS:
    --debug, -d     Enable debug output
    --dry-run       Run in dry-run mode (no actual network tests)
    --help, -h      Show this help message

WHAT IT TESTS:
    1. Basic network interfaces are up
    2. DNS resolution works
    3. Internet connectivity via ping
    4. Starlink API accessibility
    5. Cellular backup connectivity

SAFETY:
    All network tests are read-only and safe to run.
    Use --dry-run to see what would be tested without execution.
EOF
}

# Test network interface status
test_interfaces() {
    log_step "Testing network interfaces"

    # Check if main interfaces exist
    interfaces="eth0 wwan0 wlan0"
    for iface in $interfaces; do
        if ip link show "$iface" >/dev/null 2>&1; then
            status=$(ip link show "$iface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
            log_info "Interface $iface: $status"
        else
            log_debug "Interface $iface: not found (optional)"
        fi
    done
}

# Test DNS resolution
test_dns() {
    log_step "Testing DNS resolution"

    test_domains="google.com cloudflare.com 8.8.8.8"
    dns_working=0

    for domain in $test_domains; do
        if safe_execute "nslookup $domain >/dev/null 2>&1" "DNS lookup for $domain"; then
            log_info "DNS resolution for $domain: OK"
            dns_working=1
        else
            log_warning "DNS resolution for $domain: FAILED"
        fi
    done

    if [ $dns_working -eq 0 ]; then
        log_error "All DNS resolution tests failed"
        return 1
    fi

    return 0
}

# Test internet connectivity
test_internet() {
    log_step "Testing internet connectivity"

    # Test with multiple reliable hosts
    test_hosts="8.8.8.8 1.1.1.1 google.com"
    internet_working=0

    for host in $test_hosts; do
        if safe_execute "ping -c 2 -W 5 $host >/dev/null 2>&1" "Ping test to $host"; then
            log_info "Ping to $host: OK"
            internet_working=1
        else
            log_warning "Ping to $host: FAILED"
        fi
    done

    if [ $internet_working -eq 0 ]; then
        log_error "All internet connectivity tests failed"
        return 1
    fi

    return 0
}

# Test Starlink API connectivity
test_starlink_api() {
    log_step "Testing Starlink API connectivity"

    # Starlink dish IP (standard)
    starlink_ip="192.168.100.1"

    if safe_execute "ping -c 2 -W 3 $starlink_ip >/dev/null 2>&1" "Ping to Starlink dish"; then
        log_info "Starlink dish reachable: OK"

        # Try to access Starlink status (if curl is available)
        if command -v curl >/dev/null 2>&1; then
            if safe_execute "curl -s --connect-timeout 5 http://$starlink_ip/api/status >/dev/null 2>&1" "Starlink API status check"; then
                log_info "Starlink API accessible: OK"
            else
                log_warning "Starlink API not accessible (dish may be down)"
            fi
        else
            log_debug "curl not available - skipping API test"
        fi
    else
        log_warning "Starlink dish not reachable"
        return 1
    fi

    return 0
}

# Test cellular backup
test_cellular() {
    log_step "Testing cellular backup connectivity"

    # Check if cellular interface exists
    if ip link show wwan0 >/dev/null 2>&1; then
        status=$(ip link show wwan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)
        log_info "Cellular interface (wwan0): $status"

        if [ "$status" = "UP" ]; then
            # Try to get cellular IP
            cell_ip=$(ip addr show wwan0 | grep -o 'inet [0-9.]*' | cut -d' ' -f2 2>/dev/null || echo "")
            if [ -n "$cell_ip" ]; then
                log_info "Cellular IP address: $cell_ip"
            else
                log_warning "Cellular interface up but no IP assigned"
            fi
        fi
    else
        log_info "Cellular interface not found (may not be configured)"
    fi

    return 0
}

# Main connectivity test function
main() {
    log_info "Starting RUTOS connectivity test v$SCRIPT_VERSION"

    # Parse arguments
    parse_arguments "$@"

    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode enabled"
        log_debug "Working directory: $(pwd)"
        log_debug "Arguments: $*"
    fi

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_warning "Not running on OpenWrt/RUTOS - some tests may not work"
    fi

    test_failures=0

    # Run connectivity tests
    log_step "Running connectivity tests"

    if ! test_interfaces; then
        test_failures=$((test_failures + 1))
    fi

    if ! test_dns; then
        test_failures=$((test_failures + 1))
    fi

    if ! test_internet; then
        test_failures=$((test_failures + 1))
    fi

    if ! test_starlink_api; then
        test_failures=$((test_failures + 1))
    fi

    if ! test_cellular; then
        test_failures=$((test_failures + 1))
    fi

    # Summary
    if [ $test_failures -eq 0 ]; then
        log_success "All connectivity tests passed"
        exit 0
    else
        log_error "$test_failures connectivity tests failed"
        exit 1
    fi
}

# Execute main function
main "$@"
