#!/bin/sh
# shellcheck disable=SC1091 # Dynamic source files
# Script: test-connectivity.sh
# Version: 1.0.2
# Description: Comprehensive connectivity and credential testing for Starlink monitoring system

set -e # Exit on error

# Script version - automatically updated by update-version.sh
SCRIPT_VERSION="1.0.2"

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[1;35m' # Bright magenta instead of dark blue for better readability
	CYAN='\033[0;36m'
	NC='\033[0m' # No Color
else
	# Fallback to no colors if terminal doesn't support them
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

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Function to run a test with proper status tracking
run_test() {
	test_name="$1"
	test_description="$2"

	log_step "Testing: $test_description"

	if eval "$test_name"; then
		log_success "$test_description - PASSED"
		TESTS_PASSED=$((TESTS_PASSED + 1))
		return 0
	else
		log_error "$test_description - FAILED"
		TESTS_FAILED=$((TESTS_FAILED + 1))
		return 1
	fi
}

# Function to skip a test
skip_test() {
	test_description="$1"
	reason="$2"

	log_warning "SKIPPING: $test_description - $reason"
	TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Load configuration
load_config() {
	log_step "Loading configuration"

	# Default installation directory
	INSTALL_DIR="/root/starlink-monitor"
	CONFIG_FILE="$INSTALL_DIR/config/config.sh"

	# Allow override via environment variable
	if [ -n "${CONFIG_FILE:-}" ]; then
		log_debug "Using CONFIG_FILE from environment: $CONFIG_FILE"
	fi

	# Check if config file exists
	if [ ! -f "$CONFIG_FILE" ]; then
		log_error "Configuration file not found: $CONFIG_FILE"
		log_error "Please run the installation script first or set CONFIG_FILE environment variable"
		exit 1
	fi

	# Source the configuration
	log_debug "Sourcing configuration from: $CONFIG_FILE"
	. "$CONFIG_FILE"

	log_success "Configuration loaded successfully"
}

# Test 1: Basic system requirements
test_system_requirements() {
	log_debug "Checking system requirements"

	# Check if we're on OpenWrt/RUTOS
	if [ ! -f "/etc/openwrt_version" ] && [ ! -f "/etc/rutos_version" ]; then
		log_warning "Not running on OpenWrt/RUTOS - some tests may not be applicable"
	fi

	# Check for required binaries
	missing_binaries=""
	for binary in curl wget; do
		if ! command -v "$binary" >/dev/null 2>&1; then
			missing_binaries="$missing_binaries $binary"
		fi
	done

	if [ -n "$missing_binaries" ]; then
		log_error "Missing required binaries:$missing_binaries"
		return 1
	fi

	# Check for grpcurl and jq
	if [ ! -f "$INSTALL_DIR/grpcurl" ] && ! command -v grpcurl >/dev/null 2>&1; then
		log_error "grpcurl not found in $INSTALL_DIR/ or PATH"
		return 1
	fi

	if [ ! -f "$INSTALL_DIR/jq" ] && ! command -v jq >/dev/null 2>&1; then
		log_error "jq not found in $INSTALL_DIR/ or PATH"
		return 1
	fi

	log_debug "System requirements check passed"
	return 0
}

# Test 2: Network connectivity
test_network_connectivity() {
	log_debug "Testing basic network connectivity"

	# Test DNS resolution
	if ! nslookup google.com >/dev/null 2>&1 && ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
		log_error "No internet connectivity - cannot resolve DNS or reach external servers"
		return 1
	fi

	log_debug "Basic network connectivity works"
	return 0
}

# Test 3: Starlink API connectivity
test_starlink_api() {
	log_debug "Testing Starlink API connectivity"

	# Extract IP and port from STARLINK_IP
	starlink_host=$(echo "$STARLINK_IP" | cut -d':' -f1)
	starlink_port=$(echo "$STARLINK_IP" | cut -d':' -f2)

	if [ -z "$starlink_host" ] || [ -z "$starlink_port" ]; then
		log_error "Invalid STARLINK_IP format: $STARLINK_IP (expected format: IP:PORT)"
		return 1
	fi

	# Test basic TCP connectivity
	if ! nc -z "$starlink_host" "$starlink_port" 2>/dev/null; then
		log_error "Cannot connect to Starlink API at $STARLINK_IP"
		log_error "Make sure Starlink dish is connected and accessible"
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

	if ! timeout 10 "$grpcurl_cmd" -plaintext -d '{}' "$STARLINK_IP" SpaceX.API.Device.Device/GetStatus >/dev/null 2>&1; then
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

	# Check for placeholder values
	if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
		log_error "Pushover credentials still contain placeholder values"
		log_error "Please update PUSHOVER_TOKEN and PUSHOVER_USER in your config"
		return 1
	fi

	# Test Pushover API call
	log_debug "Sending test notification to Pushover"

	if ! response=$(curl -s -f -m 10 \
		--data "token=$PUSHOVER_TOKEN" \
		--data "user=$PUSHOVER_USER" \
		--data "title=Starlink Monitor Test" \
		--data "message=This is a test notification from your Starlink monitoring system. Configuration test completed successfully!" \
		https://api.pushover.net/1/messages.json); then
		log_error "Failed to send Pushover notification"
		log_error "Check your PUSHOVER_TOKEN and PUSHOVER_USER credentials"
		return 1
	fi

	# Check response for success
	if echo "$response" | grep -q '"status":1'; then
		log_success "Pushover test notification sent successfully!"
		log_info "Check your Pushover app for the test message"
	else
		log_error "Pushover API returned error: $response"
		return 1
	fi

	log_debug "Pushover notification test passed"
	return 0
}

# Test 6: File system permissions and directories
test_filesystem() {
	log_debug "Testing filesystem permissions and directories"

	# Check if installation directory exists and is writable
	if [ ! -d "$INSTALL_DIR" ]; then
		log_error "Installation directory does not exist: $INSTALL_DIR"
		return 1
	fi

	if [ ! -w "$INSTALL_DIR" ]; then
		log_error "Installation directory is not writable: $INSTALL_DIR"
		return 1
	fi

	# Check required subdirectories
	for dir in config scripts logs; do
		if [ ! -d "$INSTALL_DIR/$dir" ]; then
			log_error "Required directory missing: $INSTALL_DIR/$dir"
			return 1
		fi
	done

	# Test log directory write permissions
	test_file="$INSTALL_DIR/logs/test_write.tmp"
	if ! echo "test" >"$test_file" 2>/dev/null; then
		log_error "Cannot write to log directory: $INSTALL_DIR/logs"
		return 1
	fi
	rm -f "$test_file" 2>/dev/null

	log_debug "Filesystem permissions test passed"
	return 0
}

# Test 7: Configuration file validation
test_config_validation() {
	log_debug "Testing configuration file validation"

	# Check for critical configuration variables
	critical_vars="STARLINK_IP MWAN_IFACE MWAN_MEMBER"
	for var in $critical_vars; do
		eval "value=\$$var"
		if [ -z "$value" ]; then
			log_error "Critical configuration variable is empty: $var"
			return 1
		fi
	done

	# Check for valid IP format in STARLINK_IP
	if ! echo "$STARLINK_IP" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$' >/dev/null; then
		log_error "Invalid STARLINK_IP format: $STARLINK_IP (expected: IP:PORT)"
		return 1
	fi

	log_debug "Configuration validation test passed"
	return 0
}

# Show comprehensive results
show_results() {
	echo ""
	log_step "=== CONNECTIVITY TEST RESULTS ==="
	echo ""

	total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

	if [ $TESTS_PASSED -gt 0 ]; then
		log_success "✅ Tests passed: $TESTS_PASSED"
	fi

	if [ $TESTS_FAILED -gt 0 ]; then
		log_error "❌ Tests failed: $TESTS_FAILED"
	fi

	if [ $TESTS_SKIPPED -gt 0 ]; then
		log_warning "⏭️ Tests skipped: $TESTS_SKIPPED"
	fi

	echo ""
	log_info "📊 Total tests: $total_tests"

	if [ $TESTS_FAILED -eq 0 ]; then
		log_success "🎉 All tests passed! Your Starlink monitoring system is properly configured."
		echo ""
		log_info "Next steps:"
		log_info "• Your system is ready for monitoring"
		log_info "• The monitoring scripts should work correctly"
		log_info "• Check that cron jobs are configured properly"
		return 0
	else
		log_error "❌ Some tests failed. Please fix the issues above before deploying."
		echo ""
		log_info "Common solutions:"
		log_info "• Check network connectivity to Starlink dish"
		log_info "• Verify Pushover credentials at https://pushover.net"
		log_info "• Update RUTOS admin credentials if needed"
		log_info "• Run validate-config.sh to check configuration"
		return 1
	fi
}

# Main main() {
	log_info "Starting Starlink Monitor Connectivity Tests v$SCRIPT_VERSION"
	echo ""

	# Load configuration first
	load_config

	# Run all tests
	run_test "test_system_requirements" "System Requirements"
	run_test "test_network_connectivity" "Network Connectivity"
	run_test "test_starlink_api" "Starlink API Connectivity"
	run_test "test_rutos_credentials" "RUTOS Admin Credentials"
	run_test "test_pushover" "Pushover Notifications"
	run_test "test_filesystem" "Filesystem Permissions"
	run_test "test_config_validation" "Configuration Validation"

	# Show results
	show_results
}

# Handle command line arguments
case "${1:-}" in
--help | -h)
	echo "Usage: $0 [options]"
	echo ""
	echo "Options:"
	echo "  --help, -h     Show this help message"
	echo "  --version      Show version information"
	echo ""
	echo "Environment variables:"
	echo "  CONFIG_FILE    Path to configuration file (default: /root/starlink-monitor/config/config.sh)"
	echo "  DEBUG          Enable debug output (DEBUG=1)"
	echo ""
	echo "This script tests all connectivity and credentials required for the Starlink monitoring system:"
	echo "• System requirements and binaries"
	echo "• Network connectivity"
	echo "• Starlink API accessibility"
	echo "• RUTOS admin credentials (if configured)"
	echo "• Pushover notification credentials (if configured)"
	echo "• Filesystem permissions"
	echo "• Configuration validation"
	echo ""
	echo "Examples:"
	echo "  $0                    # Run all tests"
	echo "  DEBUG=1 $0            # Run with debug output"
	echo "  CONFIG_FILE=/path/to/config.sh $0  # Use custom config file"
	exit 0
	;;
--version)
	echo "test-connectivity.sh version $SCRIPT_VERSION"
	exit 0
	;;
"")
	# No arguments, run normally
	;;
*)
	echo "Unknown option: $1"
	echo "Use --help for usage information"
	exit 1
	;;
esac

# Run main function
main "$@"
