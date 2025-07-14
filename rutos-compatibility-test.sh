#!/bin/bash

# RUTOS Compatibility Test Script
# This script tests all commands and options used in the Starlink deployment
# Run this on your RUTOS device to verify compatibility

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Create test files for testing
setup_test_files() {
    echo "test content" >/tmp/test_file.txt
    echo "1234567890" >/tmp/test_size.txt
}

# Clean up test files
cleanup_test_files() {
    rm -f /tmp/test_file.txt /tmp/test_size.txt /tmp/test_download.txt
}

echo "======================================"
echo "RUTOS Compatibility Test Script"
echo "======================================"
echo "Testing commands used in Starlink deployment..."
echo ""

# System Information
echo "=== SYSTEM INFORMATION ==="
log_info "OS Information:"
if command -v uname >/dev/null 2>&1; then
    uname -a 2>/dev/null || echo "uname failed"
else
    echo "uname command not found"
fi

log_info "Architecture Detection:"
if arch=$(uname -m 2>/dev/null); then
    echo "Architecture: $arch"
else
    echo "uname -m failed"
fi

echo ""

# Basic Commands Test
echo "=== BASIC COMMANDS TEST ==="

# Test shell
log_test "Shell compatibility"
if [ -n "$BASH_VERSION" ]; then
    log_pass "Bash shell available: $BASH_VERSION"
else
    log_warn "Not running in Bash (may affect some features)"
fi

# Test basic utilities
log_test "Basic utilities"
for cmd in cat echo ls mkdir rm chmod date; do
    if command -v $cmd >/dev/null 2>&1; then
        log_pass "$cmd available"
    else
        log_fail "$cmd not found"
    fi
done

echo ""

# Package Manager Test
echo "=== PACKAGE MANAGER TEST ==="
log_test "OpenWrt package manager (opkg)"
if command -v opkg >/dev/null 2>&1; then
    log_pass "opkg available"
    log_info "Testing opkg commands:"

    # Test opkg list-installed
    if opkg list-installed >/dev/null 2>&1; then
        log_pass "opkg list-installed works"
        package_count=$(opkg list-installed | wc -l)
        log_info "Installed packages: $package_count"
    else
        log_fail "opkg list-installed failed"
    fi

    # Test opkg list
    if opkg list >/dev/null 2>&1; then
        log_pass "opkg list works"
    else
        log_fail "opkg list failed"
    fi
else
    log_fail "opkg not found"
fi

echo ""

# UCI Configuration Test
echo "=== UCI CONFIGURATION TEST ==="
log_test "UCI configuration system"
if command -v uci >/dev/null 2>&1; then
    log_pass "uci available"

    # Test uci show
    if uci show system >/dev/null 2>&1; then
        log_pass "uci show works"
    else
        log_fail "uci show failed"
    fi

    # Test uci get
    if hostname=$(uci get system.@system[0].hostname 2>/dev/null); then
        log_pass "uci get works (hostname: $hostname)"
    else
        log_warn "uci get failed (may not have system config)"
    fi
else
    log_fail "uci not found"
fi

echo ""

# Mathematical Operations Test
echo "=== MATHEMATICAL OPERATIONS TEST ==="

# Test bc calculator
log_test "bc calculator"
if command -v bc >/dev/null 2>&1; then
    log_pass "bc available"

    # Test bc functionality
    if result=$(echo "2.5 + 3.7" | bc 2>/dev/null); then
        log_pass "bc math works: 2.5 + 3.7 = $result"
    else
        log_fail "bc math failed"
    fi

    # Test bc comparison
    if result=$(echo "5.5 > 3.2" | bc 2>/dev/null); then
        log_pass "bc comparison works: 5.5 > 3.2 = $result"
    else
        log_fail "bc comparison failed"
    fi
else
    log_warn "bc not available - testing fallbacks"
fi

# Test awk for mathematical operations
log_test "awk mathematical operations"
if command -v awk >/dev/null 2>&1; then
    log_pass "awk available"

    # Test awk division
    if result=$(echo "1000000" | awk '{printf "%.2f", $1 / 1000000}'); then
        log_pass "awk division works: 1000000/1000000 = $result"
    else
        log_fail "awk division failed"
    fi

    # Test awk comparison (integer)
    if echo "5000" | awk '{if($1 > 3000) print "true"; else print "false"}' | grep -q "true"; then
        log_pass "awk comparison works"
    else
        log_fail "awk comparison failed"
    fi
else
    log_fail "awk not found"
fi

# Test shell arithmetic
log_test "Shell arithmetic"
if result=$((5 + 3)); then
    log_pass "Shell arithmetic works: 5 + 3 = $result"
else
    log_fail "Shell arithmetic failed"
fi

echo ""

# File Operations Test
echo "=== FILE OPERATIONS TEST ==="
setup_test_files

# Test file size detection methods
log_test "File size detection"

# Method 1: wc -c
if size=$(wc -c </tmp/test_size.txt 2>/dev/null); then
    log_pass "wc -c works: file size = $size bytes"
else
    log_fail "wc -c failed"
fi

# Method 2: stat -c (Linux style)
if size=$(stat -c%s /tmp/test_size.txt 2>/dev/null); then
    log_pass "stat -c%s works: file size = $size bytes"
else
    log_warn "stat -c%s not available"
fi

# Method 3: stat -f (BSD style)
if size=$(stat -f%z /tmp/test_size.txt 2>/dev/null); then
    log_pass "stat -f%z works: file size = $size bytes"
else
    log_warn "stat -f%z not available"
fi

# Test file permissions
log_test "File permissions"
if chmod +x /tmp/test_file.txt 2>/dev/null; then
    log_pass "chmod works"
    if [ -x /tmp/test_file.txt ]; then
        log_pass "File executable test works"
    else
        log_fail "File executable test failed"
    fi
else
    log_fail "chmod failed"
fi

echo ""

# Network Operations Test
echo "=== NETWORK OPERATIONS TEST ==="

# Test curl
log_test "curl command"
if command -v curl >/dev/null 2>&1; then
    log_pass "curl available"

    # Test curl help
    if curl --help >/dev/null 2>&1; then
        log_pass "curl --help works"

        # Test specific flags
        if curl --help 2>/dev/null | grep -q "\-L"; then
            log_pass "curl supports -L flag"
        else
            log_warn "curl -L flag not supported"
        fi

        if curl --help 2>/dev/null | grep -q "\-f"; then
            log_pass "curl supports -f flag"
        else
            log_warn "curl -f flag not supported"
        fi

        if curl --help 2>/dev/null | grep -q "max-time"; then
            log_pass "curl supports --max-time"
        else
            log_warn "curl --max-time not supported"
        fi
    else
        log_fail "curl --help failed"
    fi

    # Test basic curl download (to a safe test URL if available)
    log_info "Testing curl download (requires internet)..."
    if curl "http://httpbin.org/get" -o /tmp/test_download.txt --max-time 5 >/dev/null 2>&1; then
        log_pass "curl download with --max-time works"
    elif curl "http://httpbin.org/get" -o /tmp/test_download.txt >/dev/null 2>&1; then
        log_pass "curl basic download works"
    else
        log_warn "curl download test failed (may be network/internet issue)"
    fi
else
    log_fail "curl not found"
fi

# Test timeout command
log_test "timeout command"
if command -v timeout >/dev/null 2>&1; then
    log_pass "timeout available"

    # Test timeout functionality
    if timeout 2 sleep 1 >/dev/null 2>&1; then
        log_pass "timeout command works"
    else
        log_fail "timeout command failed"
    fi
else
    log_warn "timeout not available (will use alternative methods)"
fi

echo ""

# Text Processing Test
echo "=== TEXT PROCESSING TEST ==="

# Test jq (not installed yet, but test if available)
log_test "jq JSON processor"
if command -v jq >/dev/null 2>&1; then
    log_pass "jq available"

    # Test jq functionality
    if echo '{"test": "value"}' | jq -r '.test' 2>/dev/null | grep -q "value"; then
        log_pass "jq JSON parsing works"
    else
        log_fail "jq JSON parsing failed"
    fi
else
    log_warn "jq not installed (will be downloaded during deployment)"
fi

# Test grep
log_test "grep pattern matching"
if command -v grep >/dev/null 2>&1; then
    log_pass "grep available"

    # Test grep functionality
    if echo "test string" | grep -q "test"; then
        log_pass "grep pattern matching works"
    else
        log_fail "grep pattern matching failed"
    fi

    # Test grep -E (extended regex)
    if echo "test123" | grep -E "[0-9]+" >/dev/null 2>&1; then
        log_pass "grep -E (extended regex) works"
    else
        log_warn "grep -E not available"
    fi
else
    log_fail "grep not found"
fi

echo ""

# Starlink Specific Test
echo "=== STARLINK SPECIFIC TEST ==="

# Test grpcurl (not installed yet)
log_test "grpcurl"
if command -v grpcurl >/dev/null 2>&1; then
    log_pass "grpcurl available"
else
    log_warn "grpcurl not installed (will be downloaded during deployment)"
fi

# Test Starlink API connectivity
log_test "Starlink API connectivity"
log_info "Checking if Starlink dish is connected..."

# Test ping to Starlink dish
if ping -c 1 -W 2 192.168.100.1 >/dev/null 2>&1; then
    log_pass "Starlink dish reachable (192.168.100.1)"

    # Test if port 9200 is accessible (basic connectivity)
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 192.168.100.1 9200 2>/dev/null; then
            log_pass "Starlink gRPC port (9200) accessible"
        else
            log_warn "Starlink gRPC port (9200) not accessible"
        fi
    else
        log_warn "netcat (nc) not available for port testing"
    fi
else
    log_warn "Starlink dish not reachable (may not be connected)"
fi

echo ""

# Storage and Filesystem Test
echo "=== STORAGE AND FILESYSTEM TEST ==="

# Test available space
log_test "Disk space"
if df /overlay >/dev/null 2>&1; then
    space=$(df /overlay | tail -1 | awk '{print $4}')
    log_pass "Overlay filesystem available space: ${space}KB"

    # Check if we have enough space (at least 10MB)
    if [ "$space" -gt 10240 ]; then
        log_pass "Sufficient storage space available"
    else
        log_warn "Low storage space (less than 10MB available)"
    fi
else
    log_warn "Could not check /overlay disk space"
fi

# Test /tmp directory
log_test "Temporary directory"
if [ -d "/tmp" ] && [ -w "/tmp" ]; then
    log_pass "/tmp directory writable"
else
    log_fail "/tmp directory not writable"
fi

# Test /root directory
log_test "Root directory"
if [ -d "/root" ] && [ -w "/root" ]; then
    log_pass "/root directory writable"
else
    log_fail "/root directory not writable"
fi

echo ""

# Cron and Scheduling Test
echo "=== CRON AND SCHEDULING TEST ==="

# Test cron
log_test "Cron scheduling"
if command -v crontab >/dev/null 2>&1; then
    log_pass "crontab available"

    # Test crontab listing
    if crontab -l >/dev/null 2>&1; then
        log_pass "crontab -l works"
    else
        log_warn "crontab -l failed (may have no crontab)"
    fi
else
    log_warn "crontab not available"
fi

# Test crond
if pgrep crond >/dev/null 2>&1; then
    log_pass "crond daemon running"
else
    log_warn "crond daemon not running"
fi

echo ""

# Network Configuration Test
echo "=== NETWORK CONFIGURATION TEST ==="

# Test mwan3
log_test "mwan3 multi-WAN"
if command -v mwan3 >/dev/null 2>&1; then
    log_pass "mwan3 available"

    # Test mwan3 status
    if mwan3 status >/dev/null 2>&1; then
        log_pass "mwan3 status works"
    else
        log_warn "mwan3 status failed"
    fi
else
    log_warn "mwan3 not available"
fi

# Test network interfaces
log_test "Network interfaces"
if ip link show >/dev/null 2>&1; then
    log_pass "ip command available"
    interface_count=$(ip link show | grep -c "^[0-9]")
    log_info "Network interfaces found: $interface_count"
elif ifconfig >/dev/null 2>&1; then
    log_pass "ifconfig available"
else
    log_warn "No network interface tools found"
fi

echo ""

cleanup_test_files

# Summary
echo "======================================"
echo "TEST SUMMARY"
echo "======================================"
echo "Total tests: $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All critical tests passed!${NC}"
    echo "Your RUTOS system appears compatible with the Starlink deployment."
else
    echo -e "${YELLOW}Some tests failed or warnings were issued.${NC}"
    echo "Review the failed tests above before proceeding with deployment."
fi

echo ""
echo "Save this output and share it for deployment script optimization."
echo "======================================"
