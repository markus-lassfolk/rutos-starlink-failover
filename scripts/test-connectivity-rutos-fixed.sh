#!/bin/sh
# Script: test-connectivity.sh
# Version: 2.8.0
# Description: Comprehensive connectivity and credential testing for Starlink monitoring system

# RUTOS Compatibility - Dynamic sourcing patterns
# shellcheck disable=SC1090  # Can't follow dynamic source - this is intentional

set -e # Exit on error

# Script version - automatically updated by update-version.sh
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Get the installation directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$(dirname "$SCRIPT_DIR")}"

# RUTOS-compatible color detection (simplified for busybox)
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

# Logging functions with consistent timestamp format
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

# Test runner function
run_test() {
    test_function="$1"
    test_name="$2"

    log_step "Testing: $test_name"

    if "$test_function"; then
        log_success "$test_name - PASSED"
        return 0
    else
        log_error "$test_name - FAILED"
        return 1
    fi
}

# Load configuration
load_config() {
    CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    . "$CONFIG_FILE"
    log_success "Configuration loaded successfully"

    # Ensure Starlink connection variables are defined
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    STARLINK_PORT="${STARLINK_PORT:-9200}"
}

# Test 1: System requirements
test_system_requirements() {
    log_debug "Testing system requirements"

    # Check for required commands
    missing_commands=""

    for cmd in ping curl nc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands="$missing_commands $cmd"
        fi
    done

    if [ -n "$missing_commands" ]; then
        log_error "Missing required commands:$missing_commands"
        return 1
    fi

    # Check if grpcurl is available
    if ! command -v grpcurl >/dev/null 2>&1 && [ ! -f "$INSTALL_DIR/grpcurl" ]; then
        log_error "grpcurl not found in system PATH or $INSTALL_DIR/"
        return 1
    fi

    log_debug "System requirements test passed"
    return 0
}

# Test 2: Basic network connectivity
test_network_connectivity() {
    log_debug "Testing basic network connectivity"

    # Test DNS resolution and internet connectivity
    if ! ping -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_error "Cannot reach Google DNS (8.8.8.8)"
        return 1
    fi

    if ! ping -c 2 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log_error "Cannot reach Cloudflare DNS (1.1.1.1)"
        return 1
    fi

    log_debug "Network connectivity test passed"
    return 0
}

# Test 3a: Starlink basic connectivity (ping/curl)
test_starlink_ping_curl() {
    log_debug "Testing Starlink basic connectivity (ping/curl/nc)"
    starlink_host=$(echo "$STARLINK_IP" | cut -d':' -f1)
    starlink_port=$(echo "$STARLINK_IP" | cut -d':' -f2)

    log_debug "Extracted Starlink host: $starlink_host, port: $starlink_port"

    # Ping test
    if ping -c 2 -W 2 "$starlink_host" >/dev/null 2>&1; then
        log_success "Ping to Starlink dish ($starlink_host) successful."
    else
        log_error "Ping to Starlink dish ($starlink_host) failed."
        return 1
    fi

    # Curl test (HTTP port, may not return data but should connect)
    if command -v curl >/dev/null 2>&1; then
        curl_output="$(curl -v --max-time 5 "http://$starlink_host:$starlink_port/" 2>&1)"
        log_debug "Curl output: $curl_output"
        if echo "$curl_output" | grep -q 'Received HTTP/0.9 when not allowed'; then
            log_success "curl: Port $starlink_port is open and responded (HTTP/0.9 error as expected for gRPC port)."
        elif echo "$curl_output" | grep -q 'Connection refused'; then
            log_error "curl: Connection refused on $starlink_host:$starlink_port."
            return 1
        elif echo "$curl_output" | grep -q 'timed out'; then
            log_error "curl: Connection timed out on $starlink_host:$starlink_port."
            return 1
        elif echo "$curl_output" | grep -q 'Failed to connect'; then
            log_error "curl: Failed to connect to $starlink_host:$starlink_port."
            return 1
        else
            log_warning "curl: No HTTP response, but port may still be open (API is gRPC, not HTTP)."
        fi
    else
        log_warning "curl not available for HTTP test."
    fi

    # BusyBox nc test (TCP port open check)
    if command -v nc >/dev/null 2>&1; then
        nc_output="$(echo | nc "$starlink_host" "$starlink_port" 2>&1)"
        nc_status=$?
        log_debug "nc output: $nc_output, status: $nc_status"
        if [ $nc_status -eq 0 ]; then
            log_success "nc: TCP port $starlink_port is open on $starlink_host (no error, port is reachable)."
        else
            log_error "nc: TCP port $starlink_port is not open on $starlink_host (nc exit code $nc_status)."
            log_info "nc output: $nc_output"
            return 1
        fi
    else
        log_warning "nc (netcat) not available for TCP port test."
    fi
    return 0
}

# Test 3b: Starlink gRPC Device/Handle API
test_starlink_api_device_info() {
    log_debug "Testing Starlink gRPC Device/Handle API (get_device_info)"
    starlink_host=$(echo "$STARLINK_IP" | cut -d':' -f1)
    starlink_port=$(echo "$STARLINK_IP" | cut -d':' -f2)
    grpcurl_cmd="$INSTALL_DIR/grpcurl"
    if ! command -v grpcurl >/dev/null 2>&1; then
        if [ ! -f "$grpcurl_cmd" ]; then
            log_error "grpcurl not found"
            return 1
        fi
    else
        grpcurl_cmd="grpcurl"
    fi
    # Use the provided payload for get_device_info
    payload='{"get_device_info":{}}'
    if response=$(timeout 10 "$grpcurl_cmd" -plaintext -d "$payload" "$starlink_host:$starlink_port" SpaceX.API.Device.Device/Handle 2>/dev/null); then
        if echo "$response" | grep -q 'deviceInfo'; then
            log_success "Starlink Device/Handle API returned device info."
            log_info "Device Info (truncated): $(echo "$response" | grep -o '"deviceInfo".*' | head -c 120)"
        else
            log_warning "Starlink Device/Handle API call succeeded but no deviceInfo found."
            log_info "Response: $response"
        fi
        return 0
    else
        log_error "Starlink Device/Handle API call failed."
        return 1
    fi
}

# Test 3c: Starlink gRPC GetStatus API (FIXED - BusyBox compatible nc test)
test_starlink_api() {
    log_debug "Testing Starlink API connectivity"

    # Extract IP and port from STARLINK_IP
    starlink_host=$(echo "$STARLINK_IP" | cut -d':' -f1)
    starlink_port=$(echo "$STARLINK_IP" | cut -d':' -f2)

    if [ -z "$starlink_host" ] || [ -z "$starlink_port" ]; then
        log_error "Invalid STARLINK_IP format: $STARLINK_IP (expected format: IP:PORT)"
        return 1
    fi

    # Test basic TCP connectivity using BusyBox-compatible nc
    nc_output="$(echo | nc "$starlink_host" "$starlink_port" 2>&1)"
    nc_status=$?
    log_debug "API connectivity nc output: $nc_output, status: $nc_status"
    if [ $nc_status -ne 0 ]; then
        log_error "Cannot connect to Starlink API at $STARLINK_IP"
        log_error "Make sure Starlink dish is connected and accessible"
        log_debug "nc failed with exit code $nc_status: $nc_output"
        return 1
    fi

    # Test gRPC API call
    grpcurl_cmd="$INSTALL_DIR/grpcurl"
    if ! command -v grpcurl >/dev/null 2>&1; then
        if [ ! -f "$grpcurl_cmd" ]; then
            log_error "grpcurl not found"
            return 1
        fi
    else
        grpcurl_cmd="grpcurl"
    fi

    if ! timeout 10 "$grpcurl_cmd" -plaintext -d '{}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/GetStatus >/dev/null 2>&1; then
        log_error "Starlink gRPC API call failed"
        log_error "Check if Starlink dish is online and API is accessible"
        return 1
    fi

    log_debug "Starlink API connectivity test passed"
    return 0
}

# Test 4: RUTOS admin credentials
test_rutos_credentials() {
    log_debug "Testing RUTOS admin credentials"

    # Check if RUTOS credentials are configured
    if [ -z "${RUTOS_USERNAME:-}" ] || [ -z "${RUTOS_PASSWORD:-}" ] || [ -z "${RUTOS_IP:-}" ]; then
        log_warning "RUTOS credentials not configured - skipping RUTOS admin test"
        return 0
    fi

    # Test login to RUTOS web interface
    if ! curl -s -f -m 10 --data "username=$RUTOS_USERNAME&password=$RUTOS_PASSWORD" \
        "http://$RUTOS_IP/cgi-bin/luci/admin/system/admin" >/dev/null 2>&1; then
        log_error "Cannot login to RUTOS web interface at $RUTOS_IP"
        log_error "Check RUTOS_USERNAME, RUTOS_PASSWORD, and RUTOS_IP in config"
        return 1
    fi

    log_debug "RUTOS admin credentials test passed"
    return 0
}

# Test 5: Pushover notifications
test_pushover() {
    log_debug "Testing Pushover notification credentials"

    # Check if Pushover is configured
    if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
        log_warning "Pushover credentials not configured - skipping Pushover test"
        return 0
    fi

    # Skip test if using placeholder values
    if echo "${PUSHOVER_TOKEN:-}" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)"; then
        log_warning "Pushover token appears to be a placeholder - skipping Pushover test"
        return 0
    fi

    if echo "${PUSHOVER_USER:-}" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)"; then
        log_warning "Pushover user key appears to be a placeholder - skipping Pushover test"
        return 0
    fi

    # Test Pushover API
    if ! curl -s -f -m 10 \
        --data "token=$PUSHOVER_TOKEN" \
        --data "user=$PUSHOVER_USER" \
        --data "message=Test connectivity check from Starlink Monitor" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
        log_error "Cannot send test notification via Pushover"
        log_error "Check PUSHOVER_TOKEN and PUSHOVER_USER in config"
        return 1
    fi

    log_debug "Pushover notification test passed"
    return 0
}

# Test 6: mwan3 configuration
test_mwan3_config() {
    log_debug "Testing mwan3 configuration"

    # Check if mwan3 is available
    if ! command -v mwan3 >/dev/null 2>&1; then
        log_warning "mwan3 command not available - skipping mwan3 test"
        return 0
    fi

    # Check if configured interfaces exist
    if [ -n "${MWAN_IFACE:-}" ]; then
        if ! mwan3 status | grep -q "$MWAN_IFACE"; then
            log_warning "MWAN interface '$MWAN_IFACE' not found in mwan3 status"
        else
            log_debug "MWAN interface '$MWAN_IFACE' found in mwan3 configuration"
        fi
    else
        log_warning "MWAN_IFACE not configured - cannot test mwan3 interface"
    fi

    log_debug "mwan3 configuration test passed"
    return 0
}

# Help function
show_help() {
    cat <<EOF
Starlink Monitor Connectivity Test v$SCRIPT_VERSION

Usage: $0 [options]

Options:
    --help                Show this help message
    --debug              Enable debug output

Environment Variables:
    CONFIG_FILE          Path to configuration file (default: /etc/starlink-config/config.sh)
    DEBUG                Enable debug output (set to 1)
    INSTALL_DIR          Installation directory (default: auto-detected)

Tests Performed:
    1. System Requirements    - Check for required commands
    2. Network Connectivity   - Test basic internet connectivity  
    3. Starlink Dish Tests    - Ping, HTTP port, gRPC API
    4. RUTOS Admin Access     - Test admin credentials (if configured)
    5. Pushover Notifications - Test notification service (if configured)
    6. mwan3 Configuration    - Check mwan3 setup (if available)

Examples:
    $0                       # Run all tests
    $0 --debug              # Run with debug output
    CONFIG_FILE=/path/to/config.sh $0  # Use custom config file

EOF
}

# Main function
main() {
    log_info "Starting Starlink Monitor Connectivity Tests v$SCRIPT_VERSION"
    echo ""

    # Load configuration first
    load_config

    # Run all tests
    run_test "test_system_requirements" "System Requirements"
    run_test "test_network_connectivity" "Network Connectivity"
    run_test "test_starlink_ping_curl" "Starlink Dish Ping & HTTP Port"
    run_test "test_starlink_api" "Starlink API Connectivity (gRPC GetStatus)"
    run_test "test_starlink_api_device_info" "Starlink API Device/Handle (get_device_info)"
    run_test "test_rutos_credentials" "RUTOS Admin Credentials"
    run_test "test_pushover" "Pushover Notifications"
    run_test "test_mwan3_config" "mwan3 Configuration"

    echo ""
    log_info "Connectivity tests completed"
}

# Parse command line arguments
case "${1:-}" in
    --help | -h)
        show_help
        exit 0
        ;;
    --debug)
        DEBUG=1
        export DEBUG
        shift
        ;;
    --*)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"
