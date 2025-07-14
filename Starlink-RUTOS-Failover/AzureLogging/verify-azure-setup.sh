#!/bin/bash

# Global shellcheck disables for this file
# shellcheck disable=SC2155

# ===========================================================================================
# Azure Logging Verification Script
#
# This script verifies that all components of the Azure logging solution are working:
# - Dependencies are installed correctly
# - RUTOS persistent logging is configured
# - Azure endpoint connectivity works
# - GPS data collection functions
# - Starlink API connectivity
# - Cron jobs are scheduled
# - Scripts have proper permissions
# - UCI configuration is correct
# ===========================================================================================

set -euo pipefail

# --- SCRIPT CONFIGURATION ---
# shellcheck disable=SC2034  # Variables may be used by external functions
# shellcheck disable=SC2155  # Declare and assign separately - acceptable for simple cases
SCRIPT_NAME="verify-azure-setup"
# shellcheck disable=SC2034  # LOG_TAG may be used by external logging functions
LOG_TAG="AzureVerification"

# --- COLORS FOR OUTPUT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- TEST RESULTS ---
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

declare -a FAILURES=()
declare -a WARNINGS=()
declare -a SUGGESTIONS=()

# --- HELPER FUNCTIONS ---
log() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_test() {
    echo -e "${BLUE}[TEST] $1${NC}"
    ((TOTAL_TESTS++))
}

log_pass() {
    echo -e "${GREEN}  ✓ $1${NC}"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}  ✗ $1${NC}"
    ((FAILED_TESTS++))
    FAILURES+=("$1")
}

log_warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
    ((WARNING_TESTS++))
    WARNINGS+=("$1")
}

log_info() {
    echo -e "${CYAN}  ℹ $1${NC}"
}

add_suggestion() {
    SUGGESTIONS+=("$1")
}

# --- DEPENDENCY TESTS ---
test_dependencies() {
    log_test "Checking required dependencies..."

    # Check essential commands
    local deps=("curl" "jq" "timeout" "bc" "crontab")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_pass "$dep is available"
        else
            log_fail "$dep is missing"
            missing_deps+=("$dep")
        fi
    done

    # Check grpcurl
    if [ -f "/root/grpcurl" ] && [ -x "/root/grpcurl" ]; then
        local grpcurl_version
        grpcurl_version=$(/root/grpcurl --version 2>&1 | head -n1 || echo "unknown")
        log_pass "grpcurl is installed ($grpcurl_version)"
    else
        log_fail "grpcurl is not installed or not executable"
        add_suggestion "Install grpcurl: curl -L https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_arm.tar.gz | tar -xz && mv grpcurl /root/ && chmod +x /root/grpcurl"
    fi

    # Check jq binary
    if [ -f "/root/jq" ] && [ -x "/root/jq" ]; then
        local jq_version
        jq_version=$(/root/jq --version 2>&1 || echo "unknown")
        log_pass "jq binary is installed ($jq_version)"
    else
        log_warn "jq binary not found, using system jq"
        if command -v jq >/dev/null 2>&1; then
            log_pass "System jq is available"
        else
            log_fail "No jq available (system or binary)"
            add_suggestion "Install jq binary: curl -L https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-arm -o /root/jq && chmod +x /root/jq"
        fi
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        add_suggestion "Install missing packages: opkg update && opkg install ${missing_deps[*]}"
    fi
}

# --- LOGGING CONFIGURATION TESTS ---
test_logging_config() {
    log_test "Checking RUTOS logging configuration..."

    # Check log type
    local log_type
    log_type=$(uci get system.@system[0].log_type 2>/dev/null || echo "")
    if [ "$log_type" = "file" ]; then
        log_pass "Logging type is set to 'file'"
    else
        log_fail "Logging type is '$log_type', should be 'file'"
        add_suggestion "Fix logging type: uci set system.@system[0].log_type='file' && uci commit system"
    fi

    # Check log size
    local log_size
    log_size=$(uci get system.@system[0].log_size 2>/dev/null || echo "0")
    if [ "$log_size" -ge "5120" ]; then
        log_pass "Log size is ${log_size}KB (≥5MB)"
    else
        log_fail "Log size is ${log_size}KB, should be ≥5120KB"
        add_suggestion "Fix log size: uci set system.@system[0].log_size='5120' && uci commit system"
    fi

    # Check log file
    local log_file
    log_file=$(uci get system.@system[0].log_file 2>/dev/null || echo "")
    if [ "$log_file" = "/overlay/messages" ]; then
        log_pass "Log file is set to '/overlay/messages'"
    else
        log_fail "Log file is '$log_file', should be '/overlay/messages'"
        add_suggestion "Fix log file: uci set system.@system[0].log_file='/overlay/messages' && uci commit system"
    fi

    # Check if log file exists and is writable
    if [ -f "/overlay/messages" ]; then
        log_pass "Log file /overlay/messages exists"

        if [ -w "/overlay/messages" ]; then
            log_pass "Log file is writable"

            # Test writing to log file
            local test_message="Azure logging verification test: $(date)"
            if echo "$test_message" >>/overlay/messages 2>/dev/null; then
                log_pass "Successfully wrote test message to log file"
            else
                log_fail "Cannot write to log file"
            fi
        else
            log_fail "Log file is not writable"
        fi
    else
        log_fail "Log file /overlay/messages does not exist"
        add_suggestion "Create log file and restart logging: touch /overlay/messages && /etc/init.d/log restart"
    fi
}

# --- UCI CONFIGURATION TESTS ---
test_uci_config() {
    log_test "Checking UCI Azure configuration..."

    # Check if Azure UCI section exists
    if uci show azure >/dev/null 2>&1; then
        log_pass "Azure UCI configuration section exists"

        # Check system config
        local system_endpoint=$(uci get azure.system.endpoint 2>/dev/null || echo "")
        local system_enabled=$(uci get azure.system.enabled 2>/dev/null || echo "0")

        if [ -n "$system_endpoint" ]; then
            log_pass "System logging endpoint is configured"
            log_info "Endpoint: $system_endpoint"
        else
            log_fail "System logging endpoint is not configured"
            add_suggestion "Set Azure endpoint: uci set azure.system.endpoint='YOUR_AZURE_FUNCTION_URL' && uci commit azure"
        fi

        if [ "$system_enabled" = "1" ]; then
            log_pass "System logging is enabled"
        else
            log_warn "System logging is disabled"
        fi

        # Check Starlink config
        local starlink_enabled=$(uci get azure.starlink.enabled 2>/dev/null || echo "0")
        if [ "$starlink_enabled" = "1" ]; then
            log_pass "Starlink monitoring is enabled"

            local starlink_endpoint=$(uci get azure.starlink.endpoint 2>/dev/null || echo "")
            if [ -n "$starlink_endpoint" ]; then
                log_pass "Starlink monitoring endpoint is configured"
            else
                log_warn "Starlink monitoring endpoint is not configured"
            fi
        else
            log_info "Starlink monitoring is disabled (optional)"
        fi

        # Check GPS config
        local gps_enabled=$(uci get azure.gps.enabled 2>/dev/null || echo "0")
        if [ "$gps_enabled" = "1" ]; then
            log_pass "GPS integration is enabled"

            local rutos_ip=$(uci get azure.gps.rutos_ip 2>/dev/null || echo "")
            if [ -n "$rutos_ip" ]; then
                log_pass "RUTOS IP is configured: $rutos_ip"
            else
                log_warn "RUTOS IP is not configured"
            fi
        else
            log_info "GPS integration is disabled (optional)"
        fi

    else
        log_fail "Azure UCI configuration section does not exist"
        add_suggestion "Create Azure UCI config and run setup script again"
    fi
}

# --- SCRIPT INSTALLATION TESTS ---
test_scripts() {
    log_test "Checking installed scripts..."

    local scripts=(
        "/usr/bin/log-shipper.sh"
        "/usr/bin/starlink-azure-monitor.sh"
        "/usr/bin/setup-persistent-logging.sh"
        "/usr/bin/test-azure-logging.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                log_pass "$(basename "$script") is installed and executable"
            else
                log_fail "$(basename "$script") is installed but not executable"
                add_suggestion "Make script executable: chmod +x $script"
            fi
        else
            log_warn "$(basename "$script") is not installed"
        fi
    done
}

# --- CRON JOB TESTS ---
test_cron_jobs() {
    log_test "Checking cron job configuration..."

    if crontab -l >/dev/null 2>&1; then
        local cron_content=$(crontab -l 2>/dev/null)

        # Check for system log shipping
        if echo "$cron_content" | grep -q "log-shipper.sh"; then
            log_pass "System log shipping cron job is configured"
            local log_schedule=$(echo "$cron_content" | grep "log-shipper.sh" | awk '{print $1, $2, $3, $4, $5}')
            log_info "Schedule: $log_schedule"
        else
            log_fail "System log shipping cron job is missing"
            add_suggestion "Add log shipping cron job: (crontab -l; echo '*/5 * * * * /usr/bin/log-shipper.sh') | crontab -"
        fi

        # Check for Starlink monitoring
        if echo "$cron_content" | grep -q "starlink-azure-monitor.sh"; then
            log_pass "Starlink monitoring cron job is configured"
            local starlink_schedule=$(echo "$cron_content" | grep "starlink-azure-monitor.sh" | awk '{print $1, $2, $3, $4, $5}')
            log_info "Schedule: $starlink_schedule"
        else
            log_info "Starlink monitoring cron job is not configured (optional)"
        fi

        # Check if cron service is running
        if pgrep -f "crond\|cron" >/dev/null 2>&1; then
            log_pass "Cron service is running"
        else
            log_fail "Cron service is not running"
            add_suggestion "Start cron service: /etc/init.d/cron start && /etc/init.d/cron enable"
        fi

    else
        log_fail "No crontab is configured"
        add_suggestion "Configure crontab and run setup script again"
    fi
}

# --- NETWORK CONNECTIVITY TESTS ---
test_network() {
    log_test "Checking network connectivity..."

    # Test internet connectivity
    if curl -s --max-time 10 --head "https://www.google.com" >/dev/null 2>&1; then
        log_pass "Internet connectivity is working"
    else
        log_fail "No internet connectivity"
        add_suggestion "Check network configuration and internet connection"
    fi

    # Test Starlink management interface
    if ping -c 1 -W 3 192.168.100.1 >/dev/null 2>&1; then
        log_pass "Starlink management interface (192.168.100.1) is reachable"
    else
        log_warn "Starlink management interface is not reachable"
        add_suggestion "Check Starlink connection and routing: ip route show | grep 192.168.100.1"
    fi

    # Check static route to Starlink
    if ip route show | grep -q "192.168.100.1"; then
        log_pass "Static route to Starlink exists"
        local route_info=$(ip route show | grep "192.168.100.1")
        log_info "Route: $route_info"
    else
        log_warn "No static route to Starlink found"
        add_suggestion "Add static route: uci add network route && uci set network.@route[-1].interface='wan' && uci set network.@route[-1].target='192.168.100.1' && uci set network.@route[-1].netmask='255.255.255.255' && uci commit network && /etc/init.d/network reload"
    fi
}

# --- STARLINK API TESTS ---
test_starlink_api() {
    log_test "Testing Starlink API connectivity..."

    if [ -f "/root/grpcurl" ] && [ -x "/root/grpcurl" ]; then
        # Test get_status call
        local status_response
        status_response=$(timeout 10 /root/grpcurl -plaintext -max-time 5 \
            -d '{"get_status":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")

        if [ -n "$status_response" ]; then
            log_pass "Starlink get_status API call successful"

            # Check for basic status fields
            if echo "$status_response" | /root/jq -e '.dishGetStatus.popPingLatencyMs' >/dev/null 2>&1; then
                local latency=$(echo "$status_response" | /root/jq -r '.dishGetStatus.popPingLatencyMs // "N/A"')
                log_pass "Latency data available: ${latency}ms"
            else
                log_warn "Latency data not available in API response"
            fi
        else
            log_fail "Starlink API call failed"
            add_suggestion "Check Starlink connection and ensure dish is in Bypass Mode"
        fi

        # Test get_diagnostics for GPS
        local diag_response
        diag_response=$(timeout 10 /root/grpcurl -plaintext -max-time 5 \
            -d '{"get_diagnostics":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")

        if [ -n "$diag_response" ]; then
            log_pass "Starlink get_diagnostics API call successful"

            # Check for GPS data
            if echo "$diag_response" | /root/jq -e '.dishGetDiagnostics.location.latitude' >/dev/null 2>&1; then
                log_pass "Starlink GPS data is available"
            else
                log_info "Starlink GPS data not available (may need GPS fix)"
            fi
        else
            log_warn "Starlink diagnostics API call failed"
        fi

    else
        log_fail "grpcurl not available for Starlink API testing"
    fi
}

# --- RUTOS GPS TESTS ---
test_rutos_gps() {
    log_test "Testing RUTOS GPS functionality..."

    # Check if GPS UCI config exists
    if uci show gps >/dev/null 2>&1; then
        local gps_enabled=$(uci get gps.gps.enabled 2>/dev/null || echo "0")
        if [ "$gps_enabled" = "1" ]; then
            log_pass "RUTOS GPS is enabled in UCI"
        else
            log_warn "RUTOS GPS is disabled in UCI"
            add_suggestion "Enable RUTOS GPS: uci set gps.gps.enabled='1' && uci commit gps"
        fi
    else
        log_info "RUTOS GPS UCI configuration not available (device may not have GPS)"
    fi

    # Check for gpsd
    if command -v gpspipe >/dev/null 2>&1; then
        log_pass "gpspipe command is available"

        # Test GPS data
        local gps_data
        gps_data=$(timeout 5 gpspipe -w -n 5 2>/dev/null | head -n1 || echo "")
        if [ -n "$gps_data" ] && echo "$gps_data" | grep -q '"class":"TPV"'; then
            log_pass "GPS data is available via gpspipe"
        else
            log_warn "No GPS data available via gpspipe"
        fi
    else
        log_info "gpspipe not available (GPS may use different interface)"
    fi

    # Check RUTOS API if credentials are configured
    local rutos_ip=$(uci get azure.gps.rutos_ip 2>/dev/null || echo "")
    local rutos_username=$(uci get azure.gps.rutos_username 2>/dev/null || echo "")

    if [ -n "$rutos_ip" ] && [ -n "$rutos_username" ]; then
        log_info "Testing RUTOS GPS API access..."
        # Note: We won't test with actual credentials for security reasons
        log_info "RUTOS GPS API credentials are configured"
    else
        log_info "RUTOS GPS API credentials not configured (using alternative GPS methods)"
    fi
}

# --- AZURE CONNECTIVITY TESTS ---
test_azure_connectivity() {
    log_test "Testing Azure endpoint connectivity..."

    local azure_endpoint=$(uci get azure.system.endpoint 2>/dev/null || echo "")

    if [ -n "$azure_endpoint" ]; then
        log_pass "Azure endpoint is configured"

        # Extract host from URL for connectivity test
        local host=$(echo "$azure_endpoint" | sed -n 's|https\?://\([^/]*\).*|\1|p')

        if [ -n "$host" ]; then
            # Test DNS resolution
            if nslookup "$host" >/dev/null 2>&1; then
                log_pass "Azure endpoint DNS resolution successful"
            else
                log_fail "Azure endpoint DNS resolution failed"
                add_suggestion "Check DNS configuration and internet connectivity"
            fi

            # Test HTTPS connectivity
            if curl -s --max-time 10 --head "$azure_endpoint" >/dev/null 2>&1; then
                log_pass "Azure endpoint is reachable"
            else
                log_warn "Azure endpoint connectivity test failed"
                log_info "This may be normal if the endpoint requires POST data"
            fi
        fi
    else
        log_fail "Azure endpoint is not configured"
        add_suggestion "Configure Azure endpoint in UCI: uci set azure.system.endpoint='YOUR_AZURE_FUNCTION_URL' && uci commit azure"
    fi
}

# --- LIVE DATA TESTS ---
test_data_collection() {
    log_test "Testing data collection functionality..."

    # Test log file has recent data
    if [ -f "/overlay/messages" ]; then
        local log_size=$(stat -c%s "/overlay/messages" 2>/dev/null || echo "0")
        if [ "$log_size" -gt "0" ]; then
            log_pass "Log file contains data (${log_size} bytes)"

            # Check for recent entries (last 10 minutes)
            local recent_entries
            recent_entries=$(tail -n 50 "/overlay/messages" | grep -c "$(date '+%Y-%m-%d %H:%M')\|$(date -d '1 minute ago' '+%Y-%m-%d %H:%M')" 2>/dev/null || echo "0")

            if [ "$recent_entries" -gt "0" ]; then
                log_pass "Log file has recent entries"
            else
                log_warn "No recent log entries found"
            fi
        else
            log_warn "Log file is empty"
        fi
    fi

    # Test Starlink CSV file if monitoring is enabled
    local starlink_enabled=$(uci get azure.starlink.enabled 2>/dev/null || echo "0")
    if [ "$starlink_enabled" = "1" ]; then
        local csv_file="/overlay/starlink_performance.csv"
        if [ -f "$csv_file" ]; then
            local csv_size=$(stat -c%s "$csv_file" 2>/dev/null || echo "0")
            if [ "$csv_size" -gt "0" ]; then
                log_pass "Starlink CSV file contains data (${csv_size} bytes)"

                # Check CSV header
                local header=$(head -n1 "$csv_file" 2>/dev/null || echo "")
                if echo "$header" | grep -q "timestamp.*latitude.*longitude"; then
                    log_pass "Starlink CSV has correct header with GPS fields"
                else
                    log_warn "Starlink CSV header may be incorrect"
                fi
            else
                log_warn "Starlink CSV file is empty"
            fi
        else
            log_info "Starlink CSV file not yet created (monitoring may not have run)"
        fi
    fi
}

# --- MAIN FUNCTION ---
run_verification() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "    Azure Logging Verification Script"
    echo "=========================================="
    echo -e "${NC}"
    echo

    log "Starting comprehensive verification of Azure logging setup..."
    echo

    # Run all tests
    test_dependencies
    echo
    test_logging_config
    echo
    test_uci_config
    echo
    test_scripts
    echo
    test_cron_jobs
    echo
    test_network
    echo
    test_starlink_api
    echo
    test_rutos_gps
    echo
    test_azure_connectivity
    echo
    test_data_collection
    echo

    # Print summary
    echo -e "${BLUE}"
    echo "=========================================="
    echo "           VERIFICATION SUMMARY"
    echo "=========================================="
    echo -e "${NC}"

    echo -e "Total Tests: ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
    echo -e "${YELLOW}Warnings: ${WARNING_TESTS}${NC}"
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo

    # Calculate success rate
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))

    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}✓ All critical tests passed!${NC}"
        if [ "$WARNING_TESTS" -gt 0 ]; then
            echo -e "${YELLOW}⚠ Some optional features have warnings${NC}"
        fi
    elif [ "$success_rate" -ge 80 ]; then
        echo -e "${YELLOW}⚠ Setup is mostly working but has some issues${NC}"
    else
        echo -e "${RED}✗ Setup has significant problems that need to be addressed${NC}"
    fi

    echo -e "Overall Success Rate: ${success_rate}%"
    echo

    # Print failures
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo -e "${RED}CRITICAL ISSUES:${NC}"
        for failure in "${FAILURES[@]}"; do
            echo -e "${RED}  ✗ $failure${NC}"
        done
        echo
    fi

    # Print warnings
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}WARNINGS:${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "${YELLOW}  ⚠ $warning${NC}"
        done
        echo
    fi

    # Print suggestions
    if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
        echo -e "${CYAN}SUGGESTED FIXES:${NC}"
        local i=1
        for suggestion in "${SUGGESTIONS[@]}"; do
            echo -e "${CYAN}$i. $suggestion${NC}"
            ((i++))
        done
        echo
    fi

    # Final recommendation
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}🎉 Your Azure logging setup is working correctly!${NC}"
        echo "You can now monitor your logs in Azure storage."
    else
        echo -e "${YELLOW}📋 Please address the issues above and run this script again.${NC}"
        echo "If you need help, check the documentation or run the setup script again."
    fi

    echo
    log "Verification completed."
}

# Run verification if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_verification "$@"
fi
