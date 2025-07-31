#!/bin/sh

# ==============================================================================
# Variable Consistency Checker for RUTOS Starlink Scripts
#
# Version: 2.8.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script checks for configuration variable consistency across all scripts,
# particularly focusing on common mismatches that cause runtime errors.
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# Load RUTOS library system for standardized logging and utilities
. "$(dirname "$0")/lib/rutos-lib.sh"

# Initialize script with full RUTOS library features
rutos_init "check-variable-consistency-rutos.sh" "$SCRIPT_VERSION"

# Count and report variables
check_variable_usage() {
    var_name="$1"
    description="$2"

    log_function_entry "check_variable_usage" "$var_name, $description"

    log_step "Checking $description usage..."

    total_count=0
    # Use safer while read loop instead of for loop over find output
    find . -name "*.sh" -type f 2>/dev/null | while read -r script; do
        count=$(grep -c "$var_name" "$script" 2>/dev/null || echo 0)
        # Strip whitespace from count to prevent arithmetic errors
        count=$(echo "$count" | tr -d ' \n\r')
        if [ "$count" -gt 0 ]; then
            log_debug "  $script: $count occurrences"
            total_count=$((total_count + count))
        fi
        # Write to temp file to preserve count across subshell
        echo "$total_count" >"/tmp/var_count_temp_$$"
    done
    # Read final count from temp file
    if [ -f "/tmp/var_count_temp_$$" ]; then
        total_count=$(cat "/tmp/var_count_temp_$$")
        rm -f "/tmp/var_count_temp_$$"
    fi

    log_success "Total $description occurrences: $total_count"
    # Return value by writing to temp file instead of echo to avoid output contamination
    echo "$total_count" >"/tmp/var_count_$$"

    log_function_exit "check_variable_usage" "0"
}

# Get variable count (reads from temp file)
get_variable_count() {
    if [ -f "/tmp/var_count_$$" ]; then
        cat "/tmp/var_count_$$"
        rm -f "/tmp/var_count_$$"
    else
        echo "0"
    fi
}

# Check for specific inconsistencies
check_grpcurl_consistency() {
    log_function_entry "check_grpcurl_consistency" ""
    log_step "GRPCURL Variable Consistency Check"

    # Count usage of GRPCURL_CMD (the standard)
    check_variable_usage "GRPCURL_CMD" "GRPCURL_CMD"
    grpcurl_cmd_count=$(get_variable_count)

    # Strip whitespace from count to prevent arithmetic errors
    grpcurl_cmd_count=$(echo "$grpcurl_cmd_count" | tr -d ' \n\r')

    # Analyze results
    if [ "$grpcurl_cmd_count" -gt 0 ]; then
        log_success "Consistent usage of GRPCURL_CMD found ($grpcurl_cmd_count occurrences)"
        log_function_exit "check_grpcurl_consistency" "0"
        return 0
    else
        log_error "No GRPCURL_CMD usage found!"
        log_warning "Configuration files should export GRPCURL_CMD"
        log_function_exit "check_grpcurl_consistency" "1"
        return 1
    fi
}

# Check for DRY_RUN variable handling
check_dry_run_consistency() {
    log_function_entry "check_dry_run_consistency" ""
    log_step "DRY_RUN Variable Handling Check"

    # Look for scripts that capture DRY_RUN before assignment
    scripts_with_capture=0
    scripts_with_dry_run=0

    # Use safer while read loop instead of for loop over find output
    find . -name "*unified*.sh" -type f 2>/dev/null | while read -r script; do
        # Skip configuration templates - they just export defaults
        case "$script" in
            */config.unified.template.sh | */config/*)
                continue
                ;;
        esac

        if grep -q "DRY_RUN" "$script" 2>/dev/null; then
            scripts_with_dry_run=$((scripts_with_dry_run + 1))
            log_debug "Found DRY_RUN usage in: $script"

            if grep -q "ORIGINAL_DRY_RUN" "$script" 2>/dev/null; then
                scripts_with_capture=$((scripts_with_capture + 1))
                log_debug "  ✓ Captures original value for debug output"
            else
                log_warning "  ⚠ May have debug display issues in: $script"
            fi
        fi
        # Write counts to temp files to preserve across subshell
        echo "$scripts_with_dry_run" >"/tmp/dry_run_count_$$"
        echo "$scripts_with_capture" >"/tmp/capture_count_$$"
    done

    # Read final counts from temp files
    if [ -f "/tmp/dry_run_count_$$" ]; then
        scripts_with_dry_run=$(cat "/tmp/dry_run_count_$$")
        rm -f "/tmp/dry_run_count_$$"
    fi
    if [ -f "/tmp/capture_count_$$" ]; then
        scripts_with_capture=$(cat "/tmp/capture_count_$$")
        rm -f "/tmp/capture_count_$$"
    fi

    if [ "$scripts_with_dry_run" -gt 0 ]; then
        log_success "Found $scripts_with_dry_run scripts with DRY_RUN support"
        if [ "$scripts_with_capture" -lt "$scripts_with_dry_run" ]; then
            log_warning "$((scripts_with_dry_run - scripts_with_capture)) scripts may have DRY_RUN debug display issues"
        else
            log_success "All scripts properly handle DRY_RUN debug output"
        fi
    else
        log_info "No unified scripts with DRY_RUN found"
    fi

    log_function_exit "check_dry_run_consistency" "0"
}

# Check for common variable mismatches
check_common_mismatches() {
    log_function_entry "check_common_mismatches" ""
    log_step "Common Variable Mismatch Check"

    # Common variable pairs that should be consistent
    common_vars="JQ_CMD STARLINK_IP STARLINK_PORT LOG_DIR STATE_DIR"

    for var in $common_vars; do
        count=$(find . -name "*.sh" -type f -exec grep -l "$var" {} \; 2>/dev/null | wc -l)
        count=$(echo "$count" | tr -d ' \n\r') # Strip whitespace
        if [ "$count" -gt 0 ]; then
            log_debug "  $var: used in $count scripts"
        fi
    done

    log_success "Common variable usage analysis complete"
    log_function_exit "check_common_mismatches" "0"
}

# Demonstrate command tracing capabilities
demonstrate_command_tracing() {
    log_function_entry "demonstrate_command_tracing" ""
    log_step "Command Tracing Demonstration"

    # Example 1: Regular command (no tracing)
    log_info "Example 1: Regular command execution (no tracing)"
    log_trace "About to execute regular command without safe_execute"
    ls -la /tmp >/dev/null 2>&1
    log_info "Command executed silently"

    # Example 2: Using safe_execute with tracing
    log_info "Example 2: Using safe_execute() with full tracing"
    safe_execute "ls -la /tmp | head -5" "List temporary directory contents"

    # Example 3: Variable change tracking
    log_info "Example 3: Variable change tracking"
    OLD_VALUE="initial"
    log_trace "Variable DEMO_VAR about to change from: $OLD_VALUE"
    NEW_VALUE="updated"
    log_variable_change "DEMO_VAR" "$OLD_VALUE" "$NEW_VALUE"
    log_trace "Variable DEMO_VAR changed successfully to: $NEW_VALUE"

    # Example 4: Command that would be dangerous in non-dry-run
    log_info "Example 4: Potentially dangerous command (safe in dry-run)"
    log_trace "Preparing to execute potentially dangerous file creation command"
    safe_execute "echo 'This would modify system files' > /tmp/demo_trace_$$" "Create demonstration file"
    log_trace "Dangerous command handling completed"

    # Example 5: Multiple commands with different logging levels
    log_info "Example 5: Multiple commands with different verbosity"
    log_trace "Starting sequence of system information commands"
    safe_execute "date" "Get current timestamp"
    log_trace "Timestamp command completed"
    safe_execute "whoami" "Check current user"
    log_trace "User check command completed"
    safe_execute "pwd" "Show current directory"
    log_trace "Directory check command completed"

    # Example 6: Demonstrate function call tracing
    log_info "Example 6: Function call with traced execution"
    demo_traced_function "test parameter"

    # Cleanup demonstration files
    log_trace "Beginning cleanup of demonstration files"
    safe_execute "rm -f /tmp/demo_trace_$$" "Clean up demonstration files"
    log_trace "Cleanup completed successfully"

    log_function_exit "demonstrate_command_tracing" "0"
}

# Demo function to show function tracing
demo_traced_function() {
    param="$1"
    log_function_entry "demo_traced_function" "$param"

    log_trace "Processing parameter: $param"
    log_trace "Simulating complex processing steps..."

    # Simulate some processing
    if [ "$param" = "test parameter" ]; then
        log_trace "Parameter validation successful"
        safe_execute "echo 'Processing: $param'" "Process parameter"
        result="processed_$param"
        log_variable_change "result" "" "$result"
    else
        log_trace "Parameter validation failed"
        result="error"
    fi

    log_trace "Function processing complete, returning result: $result"
    log_function_exit "demo_traced_function" "0"
    return 0
}

# Main execution
main() {
    log_info "RUTOS Starlink Variable Consistency Checker v$SCRIPT_VERSION"
    log_step "Starting variable consistency analysis"

    # Change to script directory for relative path searches
    cd "$(dirname "$0")/.." || exit 1
    log_debug "Working directory: $(pwd)"

    # Demonstrate command tracing if requested
    if [ "${DEMO_TRACING:-0}" = "1" ]; then
        demonstrate_command_tracing
        log_step "Command tracing demonstration complete - continuing with normal analysis"
    fi

    issues_found=0

    # Run all checks
    if ! check_grpcurl_consistency; then
        issues_found=$((issues_found + 1))
    fi

    check_dry_run_consistency
    check_common_mismatches

    # Summary
    log_step "Analysis Summary"
    if [ "$issues_found" -eq 0 ]; then
        log_success "No critical variable consistency issues found"
        exit 0
    else
        log_error "Found $issues_found critical variable consistency issues"
        log_warning "Please review and fix the issues above"
        exit 1
    fi
}

# Run main function
main "$@"
