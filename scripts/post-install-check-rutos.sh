#!/bin/sh
# Script: post-install-check-rutos.sh
# Version: 2.7.1
# Description: Comprehensive post-installation health check with visual indicators and enhanced debugging
# Compatible with: RUTOS (busybox sh)

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"

# CRITICAL: Load RUTOS library system (REQUIRED)
# Try to load from local development environment first
if [ -f "$(dirname "$0")/lib/rutos-lib.sh" ]; then
    # shellcheck source=lib/rutos-lib.sh
    . "$(dirname "$0")/lib/rutos-lib.sh"
elif [ -f "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" ]; then
    # shellcheck source=/dev/null
    . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh"
else
    # Fallback: basic functionality for standalone operation
    printf "[WARNING] RUTOS library not found - using fallback functions\n" >&2
    
    # Basic fallback functions
    log_info() { printf "[INFO] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
    log_error() { printf "[ERROR] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2; }
    log_debug() { [ "$DEBUG" = "1" ] && printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2; }
    log_warning() { printf "[WARNING] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
    log_success() { printf "[SUCCESS] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
    log_step() { printf "[STEP] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
    log_trace() { [ "${RUTOS_TEST_MODE:-0}" = "1" ] && printf "[TRACE] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2; }
    
    # Basic safe_execute fallback
    safe_execute() {
        cmd="$1"
        description="$2"
        log_debug "Executing: $description"
        log_debug "Command: $cmd"
        if eval "$cmd"; then
            log_debug "Command succeeded: $description"
            return 0
        else
            exit_code=$?
            log_error "Command failed with exit code $exit_code: $description"
            return $exit_code
        fi
    }
fi

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "post-install-check-rutos.sh" "$SCRIPT_VERSION"

# Standard colors for consistent output (using library-compatible format)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Enhanced command execution with detailed logging
debug_execute() {
    cmd="$1"
    description="$2"
    test_mode_ok="${3:-0}"  # Whether this command is safe to run in test mode
    
    log_debug "=== COMMAND EXECUTION ==="
    log_debug "Description: $description"
    log_debug "Command: $cmd"
    log_debug "Test mode safe: $test_mode_ok"
    log_debug "Working directory: $(pwd)"
    
    # In RUTOS_TEST_MODE, only run commands that are safe (read-only operations)
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ] && [ "$test_mode_ok" = "0" ]; then
        log_trace "RUTOS_TEST_MODE: Skipping potentially unsafe command: $description"
        log_trace "Command would be: $cmd"
        return 0
    fi
    
    # Execute command with comprehensive error handling
    if output=$(eval "$cmd" 2>&1); then
        exit_code=0
        log_debug "Command succeeded: $description"
        if [ "${DEBUG:-0}" = "1" ] && [ -n "$output" ]; then
            log_debug "Command output: $output"
        fi
    else
        exit_code=$?
        log_debug "Command failed with exit code $exit_code: $description"
        log_debug "Command output: $output"
        log_error "Failed command details:"
        log_error "  Description: $description"
        log_error "  Command: $cmd"
        log_error "  Exit code: $exit_code"
        log_error "  Output: $output"
    fi
    
    # Store results for caller
    LAST_COMMAND_OUTPUT="$output"
    LAST_COMMAND_EXIT_CODE="$exit_code"
    
    return $exit_code
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# RUTOS_TEST_MODE enables trace logging - does NOT exit early
# Only commands marked as unsafe will be skipped in test mode
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_trace "RUTOS_TEST_MODE enabled - trace logging active, safe commands will execute"
    log_debug "Test mode behavior: Read-only operations continue, unsafe operations are traced but skipped"
fi

# Configuration paths
INSTALL_DIR="/usr/local/starlink-monitor"
CONFIG_FILE="/etc/starlink-config/config.sh"

# Status tracking counters
status_passed=0
status_failed=0
status_warnings=0
status_config=0
status_info=0

# Visual status check function
check_status() {
    status_type="$1"
    description="$2"
    details="$3"

    case "$status_type" in
        "pass")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${GREEN}✅ HEALTHY${NC}   | %-25s | %s\n" "$description" "$details"
            status_passed=$((status_passed + 1))
            ;;
        "fail")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${RED}❌ FAILED${NC}    | %-25s | %s\n" "$description" "$details"
            status_failed=$((status_failed + 1))
            ;;
        "config")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}⚙️  CONFIG${NC}   | %-25s | %s\n" "$description" "$details"
            status_config=$((status_config + 1))
            ;;
        "warn")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}⚠️  WARN${NC}     | %-25s | %s\n" "$description" "$details"
            status_warnings=$((status_warnings + 1))
            ;;
        "info")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${BLUE}ℹ️  INFO${NC}     | %-25s | %s\n" "$description" "$details"
            status_info=$((status_info + 1))
            ;;
    esac
}

# Early exit in test mode to prevent execution errors
# REMOVED: This was causing the script to exit early in RUTOS_TEST_MODE
# Now RUTOS_TEST_MODE continues execution with trace logging enabled

# Show header
printf "\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}                  STARLINK POST-INSTALL HEALTH CHECK${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "\n"

log_info "Starting comprehensive health check v$SCRIPT_VERSION"

# Load configuration if available
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE" 2>/dev/null || {
        check_status "fail" "Configuration File" "Failed to load $CONFIG_FILE"
        exit 1
    }
    check_status "pass" "Configuration File" "Successfully loaded from $CONFIG_FILE"
else
    check_status "fail" "Configuration File" "Missing: $CONFIG_FILE"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "\n${RED}❌ Critical Error: Configuration file not found!${NC}\n"
    printf "Run the installer first: curl -fL install-url | sh\n\n"
    exit 1
fi

# Function to check if a value is a placeholder
is_placeholder() {
    value="$1"
    case "$value" in
        "YOUR_"* | "REPLACE_"* | "SET_"* | "EDIT_"* | "CHANGEME"* | "PLACEHOLDER"* | "TODO"* | "<"*">"* | "***"* | "XXX"* | "")
            return 0 # Is placeholder
            ;;
        *)
            return 1 # Is real value
            ;;
    esac
}

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}1. CORE SYSTEM COMPONENTS${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check installation directory
if [ -d "$INSTALL_DIR" ]; then
    script_count=$(find "$INSTALL_DIR/scripts" -name "*-rutos.sh" -type f 2>/dev/null | wc -l)
    check_status "pass" "Installation Directory" "$script_count scripts installed in $INSTALL_DIR"
else
    check_status "fail" "Installation Directory" "Missing: $INSTALL_DIR"
fi

# Check required binaries
if [ -f "$INSTALL_DIR/grpcurl" ] && [ -x "$INSTALL_DIR/grpcurl" ]; then
    # Extract grpcurl version properly - it outputs "grpcurl v1.x.x"
    version=$("$INSTALL_DIR/grpcurl" --version 2>/dev/null | head -1 | sed 's/^grpcurl //' || echo "unknown")
    check_status "pass" "gRPC Client (grpcurl)" "Installed: v$version"
else
    check_status "fail" "gRPC Client (grpcurl)" "Missing or not executable"
fi

if [ -f "$INSTALL_DIR/jq" ] && [ -x "$INSTALL_DIR/jq" ]; then
    version=$("$INSTALL_DIR/jq" --version 2>/dev/null || echo "unknown")
    check_status "pass" "JSON Processor (jq)" "Installed: $version"
else
    check_status "fail" "JSON Processor (jq)" "Missing or not executable"
fi

# Check hotplug notification script
if [ -f "/etc/hotplug.d/iface/99-pushover_notify-rutos.sh" ]; then
    check_status "pass" "Hotplug Notification" "Installed and active"
else
    check_status "fail" "Hotplug Notification" "Missing notification script"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}2. CRON SCHEDULING${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check cron entries
CRON_FILE="/etc/crontabs/root"
if [ -f "$CRON_FILE" ]; then
    monitor_entries=$(grep -c "starlink_monitor_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_entries=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
    maintenance_entries=$(grep -c "system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    if [ "$monitor_entries" -gt 0 ]; then
        check_status "pass" "Monitor Cron Job" "$monitor_entries entry(s) configured"
    else
        check_status "fail" "Monitor Cron Job" "No cron entries found"
    fi

    if [ "$logger_entries" -gt 0 ]; then
        check_status "pass" "Logger Cron Job" "$logger_entries entry(s) configured"
    else
        check_status "fail" "Logger Cron Job" "No cron entries found"
    fi

    if [ "$api_entries" -gt 0 ]; then
        check_status "pass" "API Check Cron Job" "$api_entries entry(s) configured"
    else
        check_status "warn" "API Check Cron Job" "No cron entries (optional)"
    fi

    if [ "$maintenance_entries" -gt 0 ]; then
        check_status "pass" "Maintenance Cron Job" "$maintenance_entries entry(s) configured"
    else
        check_status "warn" "Maintenance Cron Job" "No cron entries (optional)"
    fi
else
    check_status "fail" "Cron Configuration" "Crontab file missing: $CRON_FILE"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}3. STARLINK CONFIGURATION${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check Starlink IP configuration with enhanced debugging
if [ -n "${STARLINK_IP:-}" ]; then
    if is_placeholder "$STARLINK_IP"; then
        check_status "config" "Starlink IP Address" "Needs configuration: $STARLINK_IP"
    else
        log_debug "=== STARLINK CONNECTIVITY TEST ==="
        log_debug "Testing Starlink IP: $STARLINK_IP"
        
        # Parse IP and port
        grpc_host="${STARLINK_IP%:*}"
        grpc_port="${STARLINK_IP#*:}"
        
        log_debug "Parsed host: $grpc_host"
        log_debug "Parsed port: $grpc_port"
        
        # Test 1: Basic TCP connectivity with detailed logging
        log_debug "=== TEST 1: Basic TCP Connectivity ==="
        tcp_test_cmd="echo | timeout 5 nc '$grpc_host' '$grpc_port'"
        
        if debug_execute "$tcp_test_cmd" "TCP connectivity test to $grpc_host:$grpc_port" "1"; then
            log_debug "TCP connectivity: SUCCESS"
            tcp_reachable=1
        else
            log_debug "TCP connectivity: FAILED"
            log_debug "Exit code: $LAST_COMMAND_EXIT_CODE"
            log_debug "Output: $LAST_COMMAND_OUTPUT"
            tcp_reachable=0
        fi
        
        # Test 2: grpcurl availability check
        log_debug "=== TEST 2: grpcurl Availability ==="
        if [ -f "$INSTALL_DIR/grpcurl" ] && [ -x "$INSTALL_DIR/grpcurl" ]; then
            log_debug "grpcurl found at: $INSTALL_DIR/grpcurl"
            
            # Test grpcurl version
            grpcurl_version_cmd="'$INSTALL_DIR/grpcurl' --version"
            if debug_execute "$grpcurl_version_cmd" "Check grpcurl version" "1"; then
                log_debug "grpcurl version: $LAST_COMMAND_OUTPUT"
                grpcurl_available=1
            else
                log_debug "grpcurl version check failed: $LAST_COMMAND_OUTPUT"
                grpcurl_available=0
            fi
        else
            log_debug "grpcurl not found or not executable at: $INSTALL_DIR/grpcurl"
            grpcurl_available=0
        fi
        
        # Test 3: Starlink API test (only if TCP and grpcurl work)
        if [ "$tcp_reachable" = "1" ] && [ "$grpcurl_available" = "1" ]; then
            log_debug "=== TEST 3: Starlink gRPC API Test ==="
            grpc_test_cmd="timeout 10 '$INSTALL_DIR/grpcurl' -plaintext -d '{\"get_device_info\":{}}' '$grpc_host:$grpc_port' SpaceX.API.Device.Device/Handle"
            
            if debug_execute "$grpc_test_cmd" "Starlink gRPC API test" "1"; then
                log_debug "Starlink API test: SUCCESS"
                log_debug "API response received (truncated): $(echo "$LAST_COMMAND_OUTPUT" | head -c 200)..."
                check_status "pass" "Starlink IP Address" "gRPC API responding: $STARLINK_IP"
            else
                log_debug "Starlink API test: FAILED"
                log_debug "Exit code: $LAST_COMMAND_EXIT_CODE"
                log_debug "Error output: $LAST_COMMAND_OUTPUT"
                
                # Analyze the failure
                case "$LAST_COMMAND_EXIT_CODE" in
                    "124") # timeout
                        check_status "warn" "Starlink IP Address" "API timeout (dish may be offline): $STARLINK_IP"
                        ;;
                    "2"|"14") # grpcurl connection errors
                        check_status "warn" "Starlink IP Address" "TCP works but gRPC service unavailable: $STARLINK_IP"
                        ;;
                    *)
                        check_status "warn" "Starlink IP Address" "TCP works but API error (exit $LAST_COMMAND_EXIT_CODE): $STARLINK_IP"
                        ;;
                esac
            fi
        elif [ "$tcp_reachable" = "1" ]; then
            check_status "pass" "Starlink IP Address" "TCP port reachable: $STARLINK_IP (grpcurl not available for full test)"
        else
            # Enhanced failure analysis for TCP connectivity
            log_debug "=== TCP FAILURE ANALYSIS ==="
            log_debug "Checking if host resolves..."
            
            # Test if it's a hostname resolution issue
            if echo "$grpc_host" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                log_debug "Host is an IP address: $grpc_host"
                
                # Test ping to see if host is reachable at all
                ping_cmd="ping -c 1 -W 2 '$grpc_host'"
                if debug_execute "$ping_cmd" "Ping test to $grpc_host" "1"; then
                    check_status "fail" "Starlink IP Address" "Host responds to ping but port $grpc_port closed: $STARLINK_IP"
                else
                    check_status "fail" "Starlink IP Address" "Host unreachable (no ping response): $STARLINK_IP"
                fi
            else
                log_debug "Host appears to be a hostname: $grpc_host"
                
                # Test hostname resolution
                nslookup_cmd="nslookup '$grpc_host'"
                if debug_execute "$nslookup_cmd" "DNS lookup for $grpc_host" "1"; then
                    check_status "fail" "Starlink IP Address" "DNS resolves but connection failed: $STARLINK_IP"
                else
                    check_status "fail" "Starlink IP Address" "DNS resolution failed: $STARLINK_IP"
                fi
            fi
        fi
        
        log_debug "=== STARLINK TEST COMPLETE ==="
    fi
else
    check_status "config" "Starlink IP Address" "Not configured (using default 192.168.100.1:9200)"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}4. NETWORK CONFIGURATION${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check MWAN interface configuration with enhanced debugging
if [ -n "${MWAN_IFACE:-}" ]; then
    if is_placeholder "$MWAN_IFACE"; then
        check_status "config" "MWAN Interface" "Needs configuration: $MWAN_IFACE"
    else
        log_debug "=== MWAN INTERFACE CHECK ==="
        log_debug "Checking MWAN interface: $MWAN_IFACE"
        
        # Check if interface exists in UCI network config
        uci_check_cmd="uci get network.'$MWAN_IFACE'"
        if debug_execute "$uci_check_cmd" "Check UCI network interface $MWAN_IFACE" "1"; then
            log_debug "UCI interface check: SUCCESS"
            log_debug "Interface config: $LAST_COMMAND_OUTPUT"
            
            # Get interface details
            interface_proto=$(uci get "network.$MWAN_IFACE.proto" 2>/dev/null || echo "unknown")
            log_debug "Interface protocol: $interface_proto"
            
            check_status "pass" "MWAN Interface" "Configured: $MWAN_IFACE (proto: $interface_proto)"
        else
            log_debug "UCI interface check: FAILED"
            log_debug "Exit code: $LAST_COMMAND_EXIT_CODE"
            log_debug "Error: $LAST_COMMAND_OUTPUT"
            
            # List available interfaces for debugging
            available_interfaces_cmd="uci show network | grep '=interface$' | cut -d'.' -f2 | cut -d'=' -f1"
            if debug_execute "$available_interfaces_cmd" "List available network interfaces" "1"; then
                available_list=$(echo "$LAST_COMMAND_OUTPUT" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                check_status "fail" "MWAN Interface" "Interface '$MWAN_IFACE' not found. Available: $available_list"
            else
                check_status "fail" "MWAN Interface" "Interface '$MWAN_IFACE' not found in UCI"
            fi
        fi
    fi
else
    check_status "config" "MWAN Interface" "Not configured"
fi

# Check MWAN member configuration with enhanced debugging
if [ -n "${MWAN_MEMBER:-}" ]; then
    if is_placeholder "$MWAN_MEMBER"; then
        check_status "config" "MWAN Member" "Needs configuration: $MWAN_MEMBER"
    else
        log_debug "=== MWAN MEMBER CHECK ==="
        log_debug "Checking MWAN member: $MWAN_MEMBER"
        
        # Check if member exists in MWAN3 config
        mwan_check_cmd="uci get 'mwan3.$MWAN_MEMBER'"
        if debug_execute "$mwan_check_cmd" "Check MWAN3 member $MWAN_MEMBER" "1"; then
            log_debug "MWAN member check: SUCCESS"
            
            # Get member details
            member_interface_cmd="uci get 'mwan3.$MWAN_MEMBER.interface'"
            if debug_execute "$member_interface_cmd" "Get member interface" "1"; then
                member_interface="$LAST_COMMAND_OUTPUT"
                log_debug "Member interface: $member_interface"
                check_status "pass" "MWAN Member" "Configured: $MWAN_MEMBER (interface: $member_interface)"
            else
                check_status "pass" "MWAN Member" "Configured: $MWAN_MEMBER (interface: unknown)"
            fi
        else
            log_debug "MWAN member check: FAILED"
            log_debug "Exit code: $LAST_COMMAND_EXIT_CODE"
            log_debug "Error: $LAST_COMMAND_OUTPUT"
            
            # List available members for debugging
            available_members_cmd="uci show mwan3 | grep '=member$' | cut -d'.' -f2 | cut -d'=' -f1"
            if debug_execute "$available_members_cmd" "List available MWAN members" "1"; then
                if [ -n "$LAST_COMMAND_OUTPUT" ]; then
                    members_list=$(echo "$LAST_COMMAND_OUTPUT" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                    check_status "warn" "MWAN Member" "Member '$MWAN_MEMBER' not found. Available: $members_list"
                else
                    check_status "warn" "MWAN Member" "Member '$MWAN_MEMBER' not found. No MWAN members configured"
                fi
            else
                check_status "warn" "MWAN Member" "Member '$MWAN_MEMBER' not found in MWAN3 config"
            fi
        fi
    fi
else
    check_status "config" "MWAN Member" "Not configured"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}5. NOTIFICATION SYSTEM${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check Pushover configuration with enhanced debugging
if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then
    if is_placeholder "$PUSHOVER_TOKEN" || is_placeholder "$PUSHOVER_USER"; then
        check_status "config" "Pushover Notifications" "Needs configuration: TOKEN and USER required"
    else
        log_debug "=== PUSHOVER NOTIFICATION TEST ==="
        log_debug "Testing Pushover API connectivity"
        log_debug "Token length: ${#PUSHOVER_TOKEN} characters"
        log_debug "User length: ${#PUSHOVER_USER} characters"
        
        # Check if curl is available
        if command -v curl >/dev/null 2>&1; then
            log_debug "curl is available for API testing"
            
            # Test Pushover API with enhanced error handling
            pushover_cmd="curl -s --max-time 10 -d 'token=$PUSHOVER_TOKEN' -d 'user=$PUSHOVER_USER' -d 'message=Starlink Monitor Test' https://api.pushover.net/1/messages.json"
            
            if debug_execute "$pushover_cmd" "Pushover API test" "1"; then
                log_debug "Pushover API call completed"
                log_debug "Response: $LAST_COMMAND_OUTPUT"
                
                # Check response status
                if echo "$LAST_COMMAND_OUTPUT" | grep -q '"status":1'; then
                    log_debug "Pushover API test: SUCCESS"
                    check_status "pass" "Pushover Notifications" "API test successful"
                else
                    log_debug "Pushover API test: FAILED"
                    
                    # Extract error details from response
                    if echo "$LAST_COMMAND_OUTPUT" | grep -q '"errors"'; then
                        error_details=$(echo "$LAST_COMMAND_OUTPUT" | sed -n 's/.*"errors":\["\([^"]*\)".*/\1/p')
                        check_status "fail" "Pushover Notifications" "API error: $error_details"
                    else
                        check_status "fail" "Pushover Notifications" "API test failed - check credentials"
                    fi
                fi
            else
                log_debug "Pushover API call failed"
                log_debug "Exit code: $LAST_COMMAND_EXIT_CODE"
                log_debug "Error: $LAST_COMMAND_OUTPUT"
                
                case "$LAST_COMMAND_EXIT_CODE" in
                    "28"|"124") # timeout
                        check_status "fail" "Pushover Notifications" "API timeout - check network connectivity"
                        ;;
                    "6") # DNS resolution failed
                        check_status "fail" "Pushover Notifications" "DNS resolution failed for api.pushover.net"
                        ;;
                    "7") # Connection failed
                        check_status "fail" "Pushover Notifications" "Connection failed - check network/firewall"
                        ;;
                    *)
                        check_status "fail" "Pushover Notifications" "API test failed (exit $LAST_COMMAND_EXIT_CODE)"
                        ;;
                esac
            fi
        else
            log_debug "curl not available for API testing"
            check_status "warn" "Pushover Notifications" "Configured but curl not available for testing"
        fi
    fi
else
    check_status "info" "Pushover Notifications" "Not configured (optional feature)"
fi

# Check Slack configuration (if implemented)
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    if is_placeholder "$SLACK_WEBHOOK_URL"; then
        check_status "config" "Slack Notifications" "Needs configuration: WEBHOOK_URL required"
    else
        check_status "pass" "Slack Notifications" "Configured"
    fi
else
    check_status "info" "Slack Notifications" "Not configured (optional feature)"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}6. MONITORING THRESHOLDS${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check critical monitoring values
if [ -n "${CHECK_INTERVAL:-}" ]; then
    if is_placeholder "$CHECK_INTERVAL"; then
        check_status "config" "Check Interval" "Needs configuration: $CHECK_INTERVAL"
    else
        # Validate interval is reasonable (30-600 seconds)
        if [ "$CHECK_INTERVAL" -ge 30 ] && [ "$CHECK_INTERVAL" -le 600 ]; then
            check_status "pass" "Check Interval" "Set to ${CHECK_INTERVAL}s (recommended: 30-600s)"
        else
            check_status "warn" "Check Interval" "Set to ${CHECK_INTERVAL}s (recommended: 30-600s)"
        fi
    fi
else
    check_status "config" "Check Interval" "Not configured (using default 60s)"
fi

# Check failure threshold for Starlink connectivity monitoring
if [ -n "${FAILURE_THRESHOLD:-}" ]; then
    if is_placeholder "$FAILURE_THRESHOLD"; then
        check_status "config" "Connectivity Failure Threshold" "Needs configuration: $FAILURE_THRESHOLD"
    else
        check_status "pass" "Connectivity Failure Threshold" "Set to $FAILURE_THRESHOLD failures before failover"
    fi
else
    check_status "config" "Connectivity Failure Threshold" "Not configured (using default 3 failures before failover)"
fi

# Check recovery threshold for Starlink connectivity monitoring
if [ -n "${RECOVERY_THRESHOLD:-}" ]; then
    if is_placeholder "$RECOVERY_THRESHOLD"; then
        check_status "config" "Connectivity Recovery Threshold" "Needs configuration: $RECOVERY_THRESHOLD"
    else
        check_status "pass" "Connectivity Recovery Threshold" "Set to $RECOVERY_THRESHOLD successes before failback"
    fi
else
    check_status "config" "Connectivity Recovery Threshold" "Not configured (using default 3 successes before failback)"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}7. SYSTEM HEALTH${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check log directory and space
log_dir="${LOG_DIR:-/etc/starlink-logs}"
if [ -d "$log_dir" ]; then
    if [ -w "$log_dir" ]; then
        log_count=$(find "$log_dir" -name "*.log" 2>/dev/null | wc -l)
        check_status "pass" "Log Directory" "Writable with $log_count log files"
    else
        check_status "fail" "Log Directory" "Exists but not writable: $log_dir"
    fi
else
    check_status "fail" "Log Directory" "Missing: $log_dir"
fi

# Check disk space - focus on relevant partitions for RUTOS
if command -v df >/dev/null 2>&1; then
    # Check root filesystem but be less strict since RUTOS manages this
    root_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "100")
    if [ "$root_usage" -eq 100 ]; then
        # Check if this is a RUTOS system where 100% is normal for root
        if df | grep -q "overlay\|tmpfs"; then
            check_status "pass" "Root Filesystem" "RUTOS overlay filesystem (100% normal for embedded systems)"
        else
            check_status "fail" "Root Filesystem" "Root filesystem ${root_usage}% used (critical)"
        fi
    elif [ "$root_usage" -lt 90 ]; then
        check_status "pass" "Root Filesystem" "Root filesystem ${root_usage}% used (healthy)"
    else
        check_status "warn" "Root Filesystem" "Root filesystem ${root_usage}% used (monitor closely)"
    fi

    # Check if we have a separate data partition that we care about more
    data_partition=""
    for partition in "/mnt/data" "/opt" "/var" "/tmp"; do
        if df "$partition" >/dev/null 2>&1 && df "$partition" 2>/dev/null | tail -1 | awk '{print $6}' | grep -q "^$partition$"; then
            data_partition="$partition"
            break
        fi
    done

    if [ -n "$data_partition" ]; then
        data_usage=$(df "$data_partition" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
        if [ "$data_usage" -lt 80 ]; then
            check_status "pass" "Data Partition ($data_partition)" "${data_usage}% used (healthy)"
        elif [ "$data_usage" -lt 90 ]; then
            check_status "warn" "Data Partition ($data_partition)" "${data_usage}% used (monitor closely)"
        else
            check_status "fail" "Data Partition ($data_partition)" "${data_usage}% used (critical)"
        fi
    fi
else
    check_status "warn" "Disk Space" "Cannot check - df command unavailable"
fi

# Check memory usage
if [ -f "/proc/meminfo" ]; then
    mem_total=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
    mem_available=$(grep "MemAvailable:" /proc/meminfo | awk '{print $2}' || grep "MemFree:" /proc/meminfo | awk '{print $2}')
    if [ -n "$mem_total" ] && [ -n "$mem_available" ] && [ "$mem_total" -gt 0 ]; then
        mem_used_percent=$(((mem_total - mem_available) * 100 / mem_total))
        if [ "$mem_used_percent" -lt 80 ]; then
            check_status "pass" "Memory Usage" "${mem_used_percent}% used (healthy)"
        elif [ "$mem_used_percent" -lt 90 ]; then
            check_status "warn" "Memory Usage" "${mem_used_percent}% used (monitor closely)"
        else
            check_status "fail" "Memory Usage" "${mem_used_percent}% used (critical)"
        fi
    else
        check_status "warn" "Memory Usage" "Cannot calculate usage"
    fi
else
    check_status "warn" "Memory Usage" "Cannot check - /proc/meminfo unavailable"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}8. CONNECTIVITY TESTS${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Test internet connectivity
if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    check_status "pass" "Internet Connectivity" "External connectivity working"
else
    check_status "fail" "Internet Connectivity" "Cannot reach external hosts"
fi

# Test DNS resolution
if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1; then
    check_status "pass" "DNS Resolution" "DNS queries working"
else
    check_status "fail" "DNS Resolution" "Cannot resolve domain names"
fi

# Additional connectivity tests can be added here if needed

# Calculate totals and display summary
printf "\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}                               SUMMARY${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

printf "\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}Results Overview:${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${GREEN}✅ Passed:${NC}      %d\n" "$status_passed"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${RED}❌ Failed:${NC}      %d\n" "$status_failed"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${YELLOW}⚠️  Warnings:${NC}    %d\n" "$status_warnings"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${CYAN}⚙️  Config Needed:${NC} %d\n" "$status_config"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${BLUE}ℹ️  Info:${NC}        %d\n" "$status_info"
printf "\n"

# Determine overall system status
overall_status="unknown"
if [ "$status_failed" -eq 0 ] && [ "$status_config" -eq 0 ]; then
    overall_status="excellent"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}🎉 SYSTEM STATUS: EXCELLENT${NC}\n"
    printf "Your Starlink monitoring system is fully operational and properly configured.\n"
    printf "All components are working correctly.\n"
elif [ "$status_failed" -eq 0 ] && [ "$status_config" -gt 0 ]; then
    overall_status="good"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}⚙️ SYSTEM STATUS: NEEDS CONFIGURATION${NC}\n"
    printf "Your system is installed correctly but needs configuration to be fully functional.\n"
    printf "Please address the configuration items marked above.\n"
elif [ "$status_failed" -le 2 ] && [ "$status_warnings" -le 3 ]; then
    overall_status="needs_attention"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}⚠️ SYSTEM STATUS: NEEDS ATTENTION${NC}\n"
    printf "Your system has some issues that should be addressed for optimal operation.\n"
    printf "Most functionality should work, but reliability may be affected.\n"
else
    overall_status="critical"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}❌ SYSTEM STATUS: CRITICAL ISSUES${NC}\n"
    printf "Your system has significant problems that prevent proper operation.\n"
    printf "Please resolve the failed checks before relying on the monitoring system.\n"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}Quick Actions:${NC}\n"

# Configuration guidance
if [ "$status_config" -gt 0 ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Configure system:  ${CYAN}vi $CONFIG_FILE${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Re-run validation: ${CYAN}$INSTALL_DIR/scripts/validate-config-rutos.sh${NC}\n"
fi

# Standard management commands
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Test monitoring:   ${CYAN}$INSTALL_DIR/scripts/tests/test-monitoring-rutos.sh${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Check system:      ${CYAN}$INSTALL_DIR/scripts/system-status-rutos.sh${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• View logs:         ${CYAN}$INSTALL_DIR/scripts/view-logs-rutos.sh${NC}\n"

if [ "$status_failed" -gt 0 ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Repair issues:     ${CYAN}$INSTALL_DIR/scripts/repair-system-rutos.sh${NC}\n"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}Configuration File Location:${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${CYAN}$CONFIG_FILE${NC}\n"

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "\n${BLUE}Documentation:${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Installation Guide: ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/INSTALLATION.md${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Configuration Help: ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/CONFIGURATION.md${NC}\n"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Troubleshooting:    ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/TROUBLESHOOTING.md${NC}\n"

printf "\n"

# Exit with appropriate code based on status
# In dry-run or test mode, always exit with 0 for successful completion
if [ "${DRY_RUN:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "${GREEN}[SUCCESS]${NC} [%s] Post-installation check completed in test mode\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
fi

case "$overall_status" in
    "excellent")
        exit 0
        ;;
    "good")
        exit 10 # Configuration needed
        ;;
    "needs_attention")
        exit 20 # Warnings present
        ;;
    "critical")
        exit 30 # Critical failures
        ;;
    *)
        exit 1 # Unknown status
        ;;
esac
