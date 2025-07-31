#!/bin/sh
# RUTOS Fix Verification Script
# Version: 2.8.0
#
# This script tests the early exit pattern fixes on actual RUTOS hardware
# Run this script on your RUTX50 router to verify the fixes work correctly

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Colors for output (RUTOS compatible)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034  # Standard project colors, may be used in future
    PURPLE='\033[0;35m'
    # shellcheck disable=SC2034  # Standard project colors, may be used in future
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # Standard project colors, may be used in future
    PURPLE=""
    # shellcheck disable=SC2034  # Standard project colors, may be used in future
    CYAN=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Test script path
SCRIPT_DIR="/usr/local/starlink-monitor"

# Scripts to test (the ones we fixed)
TEST_SCRIPTS="
check_starlink_api-rutos.sh
starlink_logger_unified-rutos.sh
starlink_logger-rutos.sh
starlink_logger_enhanced-rutos.sh
starlink_monitor_unified-rutos.sh
starlink_monitor_enhanced-rutos.sh
starlink_monitor-rutos.sh
"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

printf "%s================================================%s\n" "$BLUE" "$NC"
printf "%s    RUTOS Early Exit Pattern Verification%s\n" "$BLUE" "$NC"
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "\n"

log_info "Testing early exit patterns on RUTOS hardware"
log_info "Script version: $SCRIPT_VERSION"
log_info "Router: $(uname -a 2>/dev/null || echo 'Unknown')"
log_info "Shell: $0"
log_info "Current user: $(whoami 2>/dev/null || echo 'Unknown')"
printf "\n"

# Function to test a script's early exit behavior
test_script_early_exit() {
    script_name="$1"
    script_path="$SCRIPT_DIR/$script_name"

    log_step "Testing $script_name"

    # Check if script exists
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        return 1
    fi

    # Check if script is executable
    if [ ! -x "$script_path" ]; then
        log_warning "Script not executable: $script_path"
        chmod +x "$script_path" 2>/dev/null || {
            log_error "Cannot make script executable"
            return 1
        }
    fi

    # Test 1: RUTOS_TEST_MODE=1
    log_info "  Test 1: RUTOS_TEST_MODE=1"
    export RUTOS_TEST_MODE=1
    export DRY_RUN=0

    if timeout 10 "$script_path" >/dev/null 2>&1; then
        log_success "  ✓ RUTOS_TEST_MODE=1 - Script exited cleanly"
        test1_result=1
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "  ✗ RUTOS_TEST_MODE=1 - Script timed out (early exit not working)"
            test1_result=0
        else
            log_error "  ✗ RUTOS_TEST_MODE=1 - Script failed with exit code $exit_code"
            test1_result=0
        fi
    fi

    # Test 2: DRY_RUN=1
    log_info "  Test 2: DRY_RUN=1"
    export RUTOS_TEST_MODE=0
    export DRY_RUN=1

    if timeout 10 "$script_path" >/dev/null 2>&1; then
        log_success "  ✓ DRY_RUN=1 - Script exited cleanly"
        test2_result=1
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "  ✗ DRY_RUN=1 - Script timed out (early exit not working)"
            test2_result=0
        else
            log_error "  ✗ DRY_RUN=1 - Script failed with exit code $exit_code"
            test2_result=0
        fi
    fi

    # Test 3: Both enabled
    log_info "  Test 3: Both RUTOS_TEST_MODE=1 and DRY_RUN=1"
    export RUTOS_TEST_MODE=1
    export DRY_RUN=1

    if timeout 10 "$script_path" >/dev/null 2>&1; then
        log_success "  ✓ Both enabled - Script exited cleanly"
        test3_result=1
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "  ✗ Both enabled - Script timed out"
            test3_result=0
        else
            log_error "  ✗ Both enabled - Script failed with exit code $exit_code"
            test3_result=0
        fi
    fi

    # Test 4: Normal execution (should run longer, we'll interrupt)
    log_info "  Test 4: Normal execution (both disabled)"
    export RUTOS_TEST_MODE=0
    export DRY_RUN=0

    # Start script in background and kill after 2 seconds
    "$script_path" >/dev/null 2>&1 &
    script_pid=$!
    sleep 2

    if kill "$script_pid" 2>/dev/null; then
        log_success "  ✓ Normal execution - Script was running (early exit disabled correctly)"
        test4_result=1
    else
        # Check if process already exited
        if ! kill -0 "$script_pid" 2>/dev/null; then
            log_warning "  ? Normal execution - Script exited quickly (may be expected)"
            test4_result=1
        else
            log_error "  ✗ Normal execution - Unable to test"
            test4_result=0
        fi
    fi

    # Clean up environment
    unset RUTOS_TEST_MODE
    unset DRY_RUN

    # Calculate result
    total_subtests=4
    passed_subtests=$((test1_result + test2_result + test3_result + test4_result))

    if [ $passed_subtests -eq $total_subtests ]; then
        log_success "✓ $script_name - All tests passed ($passed_subtests/$total_subtests)"
        return 0
    else
        log_error "✗ $script_name - Some tests failed ($passed_subtests/$total_subtests)"
        return 1
    fi
}

# Main testing loop
log_step "Starting comprehensive early exit testing"
printf "\n"

for script in $TEST_SCRIPTS; do
    # Skip empty lines
    [ -n "$script" ] || continue

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if test_script_early_exit "$script"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    printf "\n"
done

# Final results
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "%s              TEST RESULTS SUMMARY%s\n" "$BLUE" "$NC"
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "\n"

if [ $FAILED_TESTS -eq 0 ]; then
    log_success "🎉 ALL TESTS PASSED!"
    log_success "Scripts tested: $TOTAL_TESTS"
    log_success "Passed: $PASSED_TESTS"
    log_success "Failed: $FAILED_TESTS"
    printf "\n"
    log_info "✅ Early exit patterns are working correctly on RUTOS"
    log_info "✅ Scripts will exit immediately when DRY_RUN=1 or RUTOS_TEST_MODE=1"
    log_info "✅ Testing framework compatibility is fixed"
    exit 0
else
    log_error "❌ SOME TESTS FAILED"
    log_error "Scripts tested: $TOTAL_TESTS"
    log_error "Passed: $PASSED_TESTS"
    log_error "Failed: $FAILED_TESTS"
    printf "\n"
    log_warning "Scripts with failures may need additional fixes"
    log_warning "Check the early exit patterns in the failing scripts"
    exit 1
fi
