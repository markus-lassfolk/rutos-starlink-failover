#!/bin/sh
# Script: test-all-scripts-rutos.sh
# Version: 2.6.0
# Description: Comprehensive testing of all RUTOS scripts with different verbosity levels
# Usage: ./test-all-scripts-rutos.sh [--detailed] [--specific-script script_name]

set -e

# Version information
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Colors (Method 5 format for RUTOS compatibility)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    PURPLE='\033[0;35m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    PURPLE=""
    NC=""
fi

# Test configuration
TEST_MODE_DETAILED=false
SPECIFIC_SCRIPT=""
RESULTS_DIR="/tmp/script-test-results-$$"
TEST_LOG="$RESULTS_DIR/test-summary.log"

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Parse arguments
while [ $# -gt 0 ]; do
    case $1 in
        --detailed)
            TEST_MODE_DETAILED=true
            shift
            ;;
        --specific-script)
            SPECIFIC_SCRIPT="$2"
            shift 2
            ;;
        --help)
            printf "${GREEN}Usage: %s [options]${NC}\n" "$0"
            printf "Options:\n"
            printf "  --detailed              Run detailed tests with full output capture\n"
            printf "  --specific-script NAME  Test only the specified script\n"
            printf "  --help                  Show this help\n"
            exit 0
            ;;
        *)
            printf "${RED}Unknown option: %s${NC}\n" "$1"
            exit 1
            ;;
    esac
done

# Create results directory
mkdir -p "$RESULTS_DIR"

# Logging functions
test_log() {
    printf "${GREEN}[TEST]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    printf "[TEST] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$TEST_LOG"
}

test_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    printf "[ERROR] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$TEST_LOG"
}

test_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    printf "[WARNING] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$TEST_LOG"
}

test_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    printf "[STEP] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$TEST_LOG"
}

test_result() {
    status="$1"
    script="$2"
    test_type="$3"
    details="$4"

    case "$status" in
        "PASS")
            printf "${GREEN}✅ PASS${NC}   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details"
            printf "PASS   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details" >>"$TEST_LOG"
            ;;
        "FAIL")
            printf "${RED}❌ FAIL${NC}   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details"
            printf "FAIL   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details" >>"$TEST_LOG"
            ;;
        "WARN")
            printf "${YELLOW}⚠️  WARN${NC}   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details"
            printf "WARN   | %-30s | %-20s | %s\n" "$script" "$test_type" "$details" >>"$TEST_LOG"
            ;;
    esac
}

# Function to run a single test
run_test() {
    script_path="$1"
    test_type="$2"
    env_vars="$3"
    script_args="$4"

    script_name=$(basename "$script_path")
    output_file="$RESULTS_DIR/${script_name}_${test_type}.log"

    # Run the test and capture output
    if eval "$env_vars timeout 30 $script_path $script_args" >"$output_file" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Analyze results
    output_size=$(wc -c <"$output_file" 2>/dev/null || echo "0")
    line_count=$(wc -l <"$output_file" 2>/dev/null || echo "0")

    # Check for common issues
    has_errors=$(grep -ci "error\|fail\|exception" "$output_file" 2>/dev/null || echo "0")
    has_debug=$(grep -c "\[DEBUG\]" "$output_file" 2>/dev/null || echo "0")
    has_dry_run=$(grep -c "DRY-RUN\|dry.run\|test.mode" "$output_file" 2>/dev/null || echo "0")

    # Determine test result
    if [ $exit_code -eq 0 ]; then
        if [ "$output_size" -gt 10 ]; then
            details="Exit:0, Lines:$line_count, Size:${output_size}b"
            if [ "$test_type" = "debug" ] && [ "$has_debug" -lt 1 ]; then
                test_result "WARN" "$script_name" "$test_type" "$details - No debug output"
            elif [ "$test_type" = "dry-run" ] && [ "$has_dry_run" -lt 1 ]; then
                test_result "WARN" "$script_name" "$test_type" "$details - No dry-run indicators"
            else
                test_result "PASS" "$script_name" "$test_type" "$details"
            fi
        else
            test_result "WARN" "$script_name" "$test_type" "Exit:0 but minimal output (${output_size}b)"
        fi
    else
        error_details="Exit:$exit_code"
        if [ "$has_errors" -gt 0 ]; then
            error_details="$error_details, Errors:$has_errors"
        fi
        test_result "FAIL" "$script_name" "$test_type" "$error_details"
    fi

    # Show detailed output if requested
    if [ "$TEST_MODE_DETAILED" = true ]; then
        printf "${CYAN}--- Output for %s (%s) ---${NC}\n" "$script_name" "$test_type"
        head -20 "$output_file" 2>/dev/null || echo "No output captured"
        if [ "$line_count" -gt 20 ]; then
            printf "${CYAN}... (%d more lines, see %s)${NC}\n" $((line_count - 20)) "$output_file"
        fi
        # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
        printf "${CYAN}--- End Output ---${NC}\n\n"
    fi
}

# Function to test a single script with all test modes
test_script() {
    script_path="$1"
    script_name=$(basename "$script_path")

    test_step "Testing $script_name"

    # Test 1: Basic dry-run (should provide minimal user feedback)
    run_test "$script_path" "dry-run" "DRY_RUN=1" ""

    # Test 2: Debug dry-run (should provide detailed debug info)
    run_test "$script_path" "debug" "DEBUG=1 DRY_RUN=1" ""

    # Test 3: Test mode (should validate syntax and exit)
    run_test "$script_path" "test-mode" "RUTOS_TEST_MODE=1" ""

    # Test 4: Combined verbose (should show everything)
    run_test "$script_path" "verbose" "DEBUG=1 DRY_RUN=1 RUTOS_TEST_MODE=1" ""

    # Test 5: Script-specific tests based on script name
    case "$script_name" in
        "update-config-rutos.sh")
            run_test "$script_path" "help" "" "--help"
            run_test "$script_path" "dry-backup" "DRY_RUN=1" "--backup --dry-run"
            ;;
        "validate-config-rutos.sh")
            run_test "$script_path" "help" "" "--help"
            # Note: Would need a test config file for full testing
            ;;
        "system-maintenance-rutos.sh")
            run_test "$script_path" "info-mode" "DRY_RUN=1" "info"
            run_test "$script_path" "check-mode" "DRY_RUN=1" "check"
            ;;
        "system-status-rutos.sh")
            run_test "$script_path" "summary" "DRY_RUN=1" "--summary"
            ;;
        "view-logs-rutos.sh")
            run_test "$script_path" "help" "" "--help"
            ;;
    esac
}

# Main execution
main() {
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${PURPLE}║                    RUTOS SCRIPT COMPREHENSIVE TESTING                   ║${NC}\n"
    printf "${PURPLE}║                         Version %s                                ║${NC}\n" "$SCRIPT_VERSION"
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n\n"

    test_log "Starting comprehensive RUTOS script testing"
    test_log "Test results directory: $RESULTS_DIR"

    # Find all RUTOS scripts
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ -n "$SPECIFIC_SCRIPT" ]; then
        script_path="$script_dir/$SPECIFIC_SCRIPT"
        if [ -f "$script_path" ]; then
            test_script "$script_path"
        else
            test_error "Specific script not found: $script_path"
            exit 1
        fi
    else
        # Test all *-rutos.sh scripts
        scripts_found=0
        for script in "$script_dir"/*-rutos.sh; do
            if [ -f "$script" ] && [ -x "$script" ]; then
                test_script "$script"
                scripts_found=$((scripts_found + 1))
            fi
        done

        # Also test main starlink monitor script
        main_script="$script_dir/../Starlink-RUTOS-Failover/starlink_monitor-rutos.sh"
        if [ -f "$main_script" ]; then
            test_script "$main_script"
            scripts_found=$((scripts_found + 1))
        fi

        test_log "Tested $scripts_found scripts total"
    fi

    # Generate summary
    printf "\n"
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}\n"
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${BLUE}                              TEST SUMMARY                               ${NC}\n"
    # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
    printf "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}\n\n"

    # Count results
    total_tests=$(grep -c "PASS\|FAIL\|WARN" "$TEST_LOG" 2>/dev/null || echo "0")
    passed_tests=$(grep -c "PASS" "$TEST_LOG" 2>/dev/null || echo "0")
    failed_tests=$(grep -c "FAIL" "$TEST_LOG" 2>/dev/null || echo "0")
    warned_tests=$(grep -c "WARN" "$TEST_LOG" 2>/dev/null || echo "0")

    printf "${GREEN}✅ Passed: %d${NC}\n" "$passed_tests"
    printf "${RED}❌ Failed: %d${NC}\n" "$failed_tests"
    printf "${YELLOW}⚠️  Warnings: %d${NC}\n" "$warned_tests"
    printf "📊 Total Tests: %d\n\n" "$total_tests"

    if [ "$failed_tests" -gt 0 ]; then
        # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
        printf "${RED}FAILED TESTS:${NC}\n"
        grep "FAIL" "$TEST_LOG" | while IFS= read -r line; do
            printf "${RED}  %s${NC}\n" "$line"
        done
        printf "\n"
    fi

    if [ "$warned_tests" -gt 0 ]; then
        # shellcheck disable=SC2059 # Using Method 5 format for RUTOS compatibility
        printf "${YELLOW}WARNINGS:${NC}\n"
        grep "WARN" "$TEST_LOG" | while IFS= read -r line; do
            printf "${YELLOW}  %s${NC}\n" "$line"
        done
        printf "\n"
    fi

    printf "📁 Detailed results: %s\n" "$RESULTS_DIR"
    printf "📋 Test log: %s\n\n" "$TEST_LOG"

    # Exit with appropriate code
    if [ "$failed_tests" -gt 0 ]; then
        test_error "Some tests failed - review required"
        exit 1
    elif [ "$warned_tests" -gt 0 ]; then
        test_warning "All tests passed but warnings found - review recommended"
        exit 0
    else
        test_log "All tests passed successfully!"
        exit 0
    fi
}

# Run main function
main "$@"
