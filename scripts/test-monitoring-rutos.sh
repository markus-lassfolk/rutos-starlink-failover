#!/bin/sh
# Script: test-monitoring.sh
# Version: 2.4.12
# Description: Test monitoring system connectivity and configuration

# RUTOS Compatibility - Dynamic sourcing patterns
# shellcheck disable=SC1090  # Can't follow dynamic source - this is intentional
# shellcheck disable=SC1091  # Don't follow dynamic source files

set -e # Exit on error

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Configuration paths
INSTALL_DIR="/root/starlink-monitor"
CONFIG_FILE="/etc/starlink-config/config.sh"

# Debug mode support
DEBUG="${DEBUG:-0}"

# Function to test Starlink connectivity
test_starlink_connectivity() {
    # Load configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    . "$CONFIG_FILE"

    # Check if Starlink IP is configured
    if [ -z "${STARLINK_IP:-}" ] || [ "$STARLINK_IP" = "YOUR_STARLINK_IP" ]; then
        log_error "Starlink IP not configured in $CONFIG_FILE"
        return 1
    fi

    # Test ping connectivity
    if ! ping -c 1 -W 5 "$STARLINK_IP" >/dev/null 2>&1; then
        log_error "Cannot ping Starlink device at $STARLINK_IP"
        return 1
    fi

    # Test gRPC API if grpcurl is available
    if command -v grpcurl >/dev/null 2>&1; then
        if ! grpcurl -plaintext -d '{}' "$STARLINK_IP:9200" SpaceX.API.Device.Device/GetStatus >/dev/null 2>&1; then
            log_error "Starlink gRPC API not responding at $STARLINK_IP:9200"
            return 1
        fi
    fi

    return 0
}

# Function to test network connectivity
test_network_connectivity() {
    # Test basic internet connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity (cannot reach 8.8.8.8)"
        return 1
    fi

    # Test DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        log_error "DNS resolution failed"
        return 1
    fi

    return 0
}

# Function to test monitoring configuration
test_monitoring_config() {
    # Check if configuration file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Load placeholder utilities - check both current dir and parent dir (for tests/ subdirectory)
    script_dir="$(dirname "$0")"
    if [ -f "$script_dir/placeholder-utils.sh" ]; then
        . "$script_dir/placeholder-utils.sh"
    elif [ -f "$script_dir/../placeholder-utils.sh" ]; then
        . "$script_dir/../placeholder-utils.sh"
    else
        log_error "Required placeholder-utils.sh not found in $script_dir or $script_dir/.."
        return 1
    fi

    # Source configuration
    . "$CONFIG_FILE"

    # Check critical configuration variables
    if [ -z "${MWAN_MEMBER:-}" ] || [ "$MWAN_MEMBER" = "YOUR_MWAN_MEMBER" ]; then
        log_error "MWAN_MEMBER not configured in $CONFIG_FILE"
        return 1
    fi

    if [ -z "${MWAN_IFACE:-}" ] || [ "$MWAN_IFACE" = "YOUR_MWAN_IFACE" ]; then
        log_error "MWAN_IFACE not configured in $CONFIG_FILE"
        return 1
    fi

    return 0
}

# Main test function
main() {
    quiet_mode="$1"

    if [ "$quiet_mode" != "--quiet" ]; then
        log_info "Starting monitoring connectivity test v$SCRIPT_VERSION"
        echo ""
    fi

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Check if installation exists
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "Starlink Monitor installation not found at $INSTALL_DIR"
        exit 1
    fi

    # Run tests
    if [ "$quiet_mode" != "--quiet" ]; then
        log_step "Testing monitoring configuration"
    fi

    if ! test_monitoring_config; then
        if [ "$quiet_mode" != "--quiet" ]; then
            log_error "Monitoring configuration test failed"
        fi
        exit 1
    fi

    if [ "$quiet_mode" != "--quiet" ]; then
        log_step "Testing network connectivity"
    fi

    if ! test_network_connectivity; then
        if [ "$quiet_mode" != "--quiet" ]; then
            log_error "Network connectivity test failed"
        fi
        exit 1
    fi

    if [ "$quiet_mode" != "--quiet" ]; then
        log_step "Testing Starlink connectivity"
    fi

    if ! test_starlink_connectivity; then
        if [ "$quiet_mode" != "--quiet" ]; then
            log_error "Starlink connectivity test failed"
        fi
        exit 1
    fi

    if [ "$quiet_mode" != "--quiet" ]; then
        log_success "All monitoring connectivity tests passed!"
    fi

    return 0
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --version          Show script version"
    echo "  --quiet            Run in quiet mode (minimal output)"
    echo ""
    echo "Description:"
    echo "  This script tests the monitoring system connectivity including"
    echo "  network access, Starlink device connectivity, and configuration."
    echo ""
    echo "Examples:"
    echo "  $0                 # Run connectivity tests"
    echo "  $0 --quiet         # Run tests in quiet mode"
    echo "  DEBUG=1 $0         # Run with debug output"
    echo ""
    echo "Exit codes:"
    echo "  0  - All tests passed"
    echo "  1  - One or more tests failed"
}

# Handle command line arguments
case "${1:-}" in
    --help | -h)
        show_usage
        exit 0
        ;;
    --version)
        echo "$SCRIPT_VERSION"
        exit 0
        ;;
    --quiet)
        # Run in quiet mode
        main "--quiet"
        ;;
    *)
        # Run main function
        main "$@"
        ;;
esac
