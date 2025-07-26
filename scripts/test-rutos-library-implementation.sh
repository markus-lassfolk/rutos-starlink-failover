#!/bin/sh

# ==============================================================================
# RUTOS Library Implementation Test Script
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script validates the RUTOS library system implementation across all
# scripts, ensuring proper logging levels, complete execution, and library
# functionality.
#
# Tests:
# - Library loading (local development vs fallback)
# - All logging levels (INFO, STEP, DEBUG, TRACE)
# - Complete script execution to end
# - Error handling and graceful degradation
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# Load RUTOS library system for enhanced testing
. "$(dirname "$0")/lib/rutos-lib.sh"

# Initialize script with full RUTOS library features
rutos_init "test-rutos-library-implementation.sh" "$SCRIPT_VERSION"

# Test result counters
TOTAL_SCRIPTS=0
PASSED_SCRIPTS=0
FAILED_SCRIPTS=0
LIBRARY_LOADED_SCRIPTS=0
FALLBACK_MODE_SCRIPTS=0

# Test configuration
TEST_TIMEOUT=60
MIN_LOG_TYPES_REQUIRED=3 # Must see at least INFO, DEBUG, TRACE

# Validate logging levels in script output
validate_logging_levels() {
    output_file="$1"
    script_name="$2"

    log_function_entry "validate_logging_levels" "$script_name"

    # Count different log types
    info_count=$(grep -c "\[INFO\]" "$output_file" 2>/dev/null || echo 0)
    step_count=$(grep -c "\[STEP\]" "$output_file" 2>/dev/null || echo 0)
    debug_count=$(grep -c "\[DEBUG\]" "$output_file" 2>/dev/null || echo 0)
    trace_count=$(grep -c "\[TRACE\]" "$output_file" 2>/dev/null || echo 0)
    warning_count=$(grep -c "\[WARNING\]" "$output_file" 2>/dev/null || echo 0)
    success_count=$(grep -c "\[SUCCESS\]" "$output_file" 2>/dev/null || echo 0)

    # Strip whitespace from all counts
    info_count=$(echo "$info_count" | tr -d ' \n\r')
    step_count=$(echo "$step_count" | tr -d ' \n\r')
    debug_count=$(echo "$debug_count" | tr -d ' \n\r')
    trace_count=$(echo "$trace_count" | tr -d ' \n\r')
    warning_count=$(echo "$warning_count" | tr -d ' \n\r')
    success_count=$(echo "$success_count" | tr -d ' \n\r')

    log_debug "Logging level counts for $script_name:"
    log_debug "  INFO: $info_count, STEP: $step_count, DEBUG: $debug_count"
    log_debug "  TRACE: $trace_count, WARNING: $warning_count, SUCCESS: $success_count"

    # Count unique log types present
    unique_types=0
    if [ "$info_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi
    if [ "$step_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi
    if [ "$debug_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi
    if [ "$trace_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi
    if [ "$warning_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi
    if [ "$success_count" -gt 0 ]; then unique_types=$((unique_types + 1)); fi

    log_debug "Found $unique_types unique log types (minimum required: $MIN_LOG_TYPES_REQUIRED)"

    if [ "$unique_types" -ge "$MIN_LOG_TYPES_REQUIRED" ]; then
        log_success "✅ $script_name: Sufficient logging diversity ($unique_types types)"
        log_function_exit "validate_logging_levels" "0"
        return 0
    else
        log_warning "⚠️  $script_name: Insufficient logging diversity ($unique_types types, need $MIN_LOG_TYPES_REQUIRED)"
        log_function_exit "validate_logging_levels" "1"
        return 1
    fi
}

# Check if script completed to the end
validate_script_completion() {
    output_file="$1"
    script_name="$2"

    log_function_entry "validate_script_completion" "$script_name"

    # Look for completion indicators
    if grep -q "script syntax validated, exiting safely\|script syntax OK, exiting\|RUTOS_TEST_MODE enabled" "$output_file" 2>/dev/null; then
        log_success "✅ $script_name: Script completed successfully (found completion message)"
        log_function_exit "validate_script_completion" "0"
        return 0
    elif grep -q "Cleanup function called\|cleanup completed\|exiting\|exit" "$output_file" 2>/dev/null; then
        log_success "✅ $script_name: Script reached cleanup/exit (normal termination)"
        log_function_exit "validate_script_completion" "0"
        return 0
    else
        log_warning "⚠️  $script_name: No clear completion indicator found"
        log_debug "Last 5 lines of output:"
        tail -5 "$output_file" 2>/dev/null | while read -r line; do
            log_debug "  $line"
        done
        log_function_exit "validate_script_completion" "1"
        return 1
    fi
}

# Check if script is using RUTOS library or fallback
validate_library_usage() {
    output_file="$1"
    script_name="$2"

    log_function_entry "validate_library_usage" "$script_name"

    if grep -q "RUTOS library system loaded\|library system loaded" "$output_file" 2>/dev/null; then
        log_success "✅ $script_name: Using RUTOS library system"
        LIBRARY_LOADED_SCRIPTS=$((LIBRARY_LOADED_SCRIPTS + 1))
        log_function_exit "validate_library_usage" "library"
        return 0
    elif grep -q "Using built-in fallback\|fallback logging\|legacy logging" "$output_file" 2>/dev/null; then
        log_info "ℹ️  $script_name: Using fallback logging system"
        FALLBACK_MODE_SCRIPTS=$((FALLBACK_MODE_SCRIPTS + 1))
        log_function_exit "validate_library_usage" "fallback"
        return 0
    else
        log_warning "⚠️  $script_name: Cannot determine logging system type"
        log_function_exit "validate_library_usage" "unknown"
        return 1
    fi
}

# Test individual script with comprehensive RUTOS library validation
test_script_rutos_library() {
    script_path="$1"
    script_name=$(basename "$script_path")

    log_function_entry "test_script_rutos_library" "$script_name"
    log_step "Testing RUTOS library implementation: $script_name"

    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + 1))

    # Create temporary output file
    temp_output="/tmp/rutos_test_output_$$_$(echo "$script_name" | tr '/' '_')"

    # Set up comprehensive test environment
    export DRY_RUN=1
    export RUTOS_TEST_MODE=1
    export DEBUG=1
    export TEST_MODE=1

    log_debug "Environment: DRY_RUN=1, RUTOS_TEST_MODE=1, DEBUG=1"
    log_trace "Starting execution test for: $script_path"

    # Execute script with timeout and capture all output
    test_start_time=$(date '+%s')
    exit_code=0

    log_trace "Executing: timeout $TEST_TIMEOUT sh '$script_path'"
    if timeout "$TEST_TIMEOUT" sh "$script_path" >"$temp_output" 2>&1; then
        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))
        log_debug "Script executed successfully in ${test_duration}s"
    else
        exit_code=$?
        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))

        if [ $exit_code -eq 124 ]; then
            log_error "❌ $script_name: TIMEOUT after ${TEST_TIMEOUT}s"
        else
            log_error "❌ $script_name: FAILED with exit code $exit_code after ${test_duration}s"
        fi
        log_function_exit "test_script_rutos_library" "$exit_code"
        return 1
    fi

    # Validate the output
    validation_passed=0

    # Check 1: Logging levels validation
    if validate_logging_levels "$temp_output" "$script_name"; then
        validation_passed=$((validation_passed + 1))
    fi

    # Check 2: Script completion validation
    if validate_script_completion "$temp_output" "$script_name"; then
        validation_passed=$((validation_passed + 1))
    fi

    # Check 3: Library usage validation
    if validate_library_usage "$temp_output" "$script_name"; then
        validation_passed=$((validation_passed + 1))
    fi

    # Overall assessment
    if [ $validation_passed -ge 2 ]; then
        log_success "✅ $script_name: PASSED ($validation_passed/3 validations)"
        PASSED_SCRIPTS=$((PASSED_SCRIPTS + 1))
        result=0
    else
        log_error "❌ $script_name: FAILED ($validation_passed/3 validations)"
        FAILED_SCRIPTS=$((FAILED_SCRIPTS + 1))

        # Show sample output for debugging
        log_debug "Sample output from failed script:"
        head -10 "$temp_output" 2>/dev/null | while read -r line; do
            log_debug "  $line"
        done
        result=1
    fi

    # Cleanup
    rm -f "$temp_output" 2>/dev/null || true

    log_function_exit "test_script_rutos_library" "$result"
    return $result
}

# Find and test all RUTOS scripts
find_and_test_scripts() {
    log_function_entry "find_and_test_scripts" ""
    log_step "Finding all RUTOS scripts for library implementation testing"

    # Change to project root
    cd "$(dirname "$0")/.." || exit 1
    log_debug "Working directory: $(pwd)"

    # Create temporary file to collect script paths
    script_list="/tmp/rutos_scripts_$$"

    # Find all RUTOS scripts (avoiding test scripts)
    log_trace "Searching for *-rutos.sh scripts..."
    find . -name "*-rutos.sh" -type f 2>/dev/null | grep -v "/tmp/" | sort >"$script_list"

    # Count total scripts
    script_count=$(wc -l <"$script_list" | tr -d ' \n\r')
    log_info "Found $script_count RUTOS scripts to test"

    # Test each script
    while read -r script_path; do
        test_script_rutos_library "$script_path"
    done <"$script_list"

    # Cleanup
    rm -f "$script_list" 2>/dev/null || true

    log_function_exit "find_and_test_scripts" "0"
}

# Generate comprehensive test report
generate_test_report() {
    log_function_entry "generate_test_report" ""
    log_step "Generating RUTOS Library Implementation Test Report"

    # Calculate percentages
    if [ $TOTAL_SCRIPTS -gt 0 ]; then
        success_rate=$((PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS))
        library_adoption_rate=$((LIBRARY_LOADED_SCRIPTS * 100 / TOTAL_SCRIPTS))
    else
        success_rate=0
        library_adoption_rate=0
    fi

    log_info "=========================================="
    log_info "RUTOS Library Implementation Test Results"
    log_info "=========================================="
    log_info "Total Scripts Tested: $TOTAL_SCRIPTS"
    log_info "Passed: $PASSED_SCRIPTS"
    log_info "Failed: $FAILED_SCRIPTS"
    log_success "Success Rate: ${success_rate}%"
    log_info ""
    log_info "Library Implementation Status:"
    log_info "  Using RUTOS Library: $LIBRARY_LOADED_SCRIPTS scripts"
    log_info "  Using Fallback Mode: $FALLBACK_MODE_SCRIPTS scripts"
    log_success "Library Adoption Rate: ${library_adoption_rate}%"
    log_info "=========================================="

    # Assessment
    if [ $success_rate -ge 80 ]; then
        log_success "🎉 EXCELLENT: RUTOS library implementation is working well!"
    elif [ $success_rate -ge 60 ]; then
        log_warning "⚠️  GOOD: RUTOS library implementation mostly working, some issues"
    else
        log_error "❌ NEEDS WORK: RUTOS library implementation has significant issues"
    fi

    log_function_exit "generate_test_report" "0"
}

# Add completion tracking to scripts
add_completion_messages() {
    log_function_entry "add_completion_messages" ""
    log_step "Adding completion messages to scripts for better testing"

    # Find scripts that need completion messages
    scripts_needing_completion=0

    # This would add debug/trace messages at the end of scripts
    log_info "Script completion message enhancement suggestions:"
    log_info "1. Add 'log_debug \"Script execution completed successfully\"' at end of main functions"
    log_info "2. Add 'log_trace \"Exiting script gracefully\"' before exit statements"
    log_info "3. Ensure cleanup functions log their completion"

    log_function_exit "add_completion_messages" "0"
}

# Main execution
main() {
    log_info "RUTOS Library Implementation Test v$SCRIPT_VERSION"
    log_step "Starting comprehensive RUTOS library validation"

    # Test library implementation
    find_and_test_scripts

    # Generate report
    generate_test_report

    # Provide enhancement suggestions
    add_completion_messages

    # Final assessment
    if [ $FAILED_SCRIPTS -eq 0 ]; then
        log_success "🎯 All scripts passed RUTOS library implementation tests!"
        log_debug "Test completed successfully - library system is working properly"
        log_trace "Exiting test script with success status"
        exit 0
    else
        log_error "⚠️  Some scripts failed RUTOS library implementation tests"
        log_warning "Review failed scripts and enhance their library integration"
        log_debug "Test completed with failures - improvements needed"
        log_trace "Exiting test script with failure status"
        exit 1
    fi
}

# Run main function
main "$@"
