#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh" 2>/dev/null || {
    # Fallback if library not available
    log_info() { printf "[INFO] %s\n" "$*"; }
    log_error() { printf "[ERROR] %s\n" "$*"; }
    log_success() { printf "[SUCCESS] %s\n" "$*"; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$*"; }
}

# CRITICAL: Initialize script with library features (REQUIRED)
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "filter-errors-rutos.sh" "$SCRIPT_VERSION"
else
    log_info "RUTOS library not available - using fallback logging"
fi

# Default values
DEFAULT_CONTEXT_LINES=5
DEFAULT_ERROR_PATTERNS="ERROR|FAIL|CRITICAL|❌|⚠️|WARN"

# Usage function
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [LOG_FILE]

Filter log files for errors and warnings with context lines.

OPTIONS:
    -c, --context LINES    Number of context lines before/after error (default: $DEFAULT_CONTEXT_LINES)
    -p, --pattern PATTERN  Custom error pattern (default: $DEFAULT_ERROR_PATTERNS)
    -i, --ignore-case      Case insensitive matching
    -n, --line-numbers     Show line numbers
    -h, --help             Show this help

LOG_FILE:
    Path to log file to analyze. If not provided, reads from stdin.

EXAMPLES:
    # Filter deployment log for errors with 5 lines context
    $0 /var/log/starlink-deployment.log
    
    # Custom context and pattern
    $0 -c 10 -p "CRITICAL|FATAL" /var/log/messages
    
    # From command output
    ./deploy-starlink-solution-v3-rutos.sh 2>&1 | $0
    
    # Show line numbers and ignore case
    $0 -n -i /var/log/syslog

ERROR PATTERNS:
    Default patterns: $DEFAULT_ERROR_PATTERNS
    
    Common RUTOS patterns:
    - ERROR, FAIL, CRITICAL: Standard error levels
    - ❌, ⚠️: Visual error indicators
    - WARN: Warning messages
    - "sed: .* No such file": sed command errors
    - "uci: .* not found": UCI configuration errors
    - "command not found": Missing command errors
EOF
}

# Parse command line arguments
CONTEXT_LINES="$DEFAULT_CONTEXT_LINES"
ERROR_PATTERN="$DEFAULT_ERROR_PATTERNS"
IGNORE_CASE=""
SHOW_LINE_NUMBERS=""
LOG_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--context)
            shift
            CONTEXT_LINES="${1:-$DEFAULT_CONTEXT_LINES}"
            if ! echo "$CONTEXT_LINES" | grep -q '^[0-9]\+$'; then
                log_error "Context lines must be a number: $CONTEXT_LINES"
                exit 1
            fi
            ;;
        -p|--pattern)
            shift
            ERROR_PATTERN="${1:-$DEFAULT_ERROR_PATTERNS}"
            ;;
        -i|--ignore-case)
            IGNORE_CASE="-i"
            ;;
        -n|--line-numbers)
            SHOW_LINE_NUMBERS="-n"
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$LOG_FILE" ]; then
                LOG_FILE="$1"
            else
                log_error "Multiple log files specified: $LOG_FILE and $1"
                exit 1
            fi
            ;;
    esac
    shift
done

# Function to filter errors with context
filter_errors_with_context() {
    local input_file="$1"
    local context="$2"
    local pattern="$3"
    local ignore_case="$4"
    local line_numbers="$5"
    
    log_info "🔍 Filtering for errors with ±$context lines context"
    log_info "📋 Error pattern: $pattern"
    log_info "📄 Input: ${input_file:-stdin}"
    
    # Use grep to find errors with context
    # -E: extended regex, -A: after context, -B: before context
    grep_cmd="grep -E $ignore_case -A $context -B $context"
    
    if [ -n "$line_numbers" ]; then
        grep_cmd="$grep_cmd -n"
    fi
    
    # Add the pattern
    grep_cmd="$grep_cmd '$pattern'"
    
    # Execute the grep command
    if [ -n "$input_file" ] && [ -f "$input_file" ]; then
        log_debug "Executing: $grep_cmd '$input_file'"
        eval "$grep_cmd '$input_file'" 2>/dev/null || {
            log_info "ℹ️  No errors found matching pattern: $pattern"
            return 1
        }
    else
        log_debug "Executing: $grep_cmd (from stdin)"
        eval "$grep_cmd" 2>/dev/null || {
            log_info "ℹ️  No errors found matching pattern: $pattern"
            return 1
        }
    fi
}

# Function to add visual separators and analysis
analyze_filtered_output() {
    local temp_file="/tmp/error_filter_$$"
    
    # Capture the filtered output
    if filter_errors_with_context "$LOG_FILE" "$CONTEXT_LINES" "$ERROR_PATTERN" "$IGNORE_CASE" "$SHOW_LINE_NUMBERS" > "$temp_file"; then
        
        # Count matches
        error_count=$(grep -c -E $IGNORE_CASE "$ERROR_PATTERN" "$temp_file" 2>/dev/null || echo "0")
        
        log_success "📊 Found $error_count error lines"
        echo ""
        echo "=========================================="
        echo "           ERROR ANALYSIS REPORT"
        echo "=========================================="
        echo "Context lines: ±$CONTEXT_LINES"
        echo "Error pattern: $ERROR_PATTERN"
        echo "Total matches: $error_count"
        echo "=========================================="
        echo ""
        
        # Show the filtered content with separators
        cat "$temp_file"
        
        echo ""
        echo "=========================================="
        echo "           END ERROR REPORT"
        echo "=========================================="
        
        # Cleanup
        rm -f "$temp_file"
        
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Main execution
main() {
    log_info "🔧 RUTOS Error Log Filter v$SCRIPT_VERSION"
    
    # Validate input
    if [ -n "$LOG_FILE" ]; then
        if [ ! -f "$LOG_FILE" ]; then
            log_error "Log file not found: $LOG_FILE"
            exit 1
        fi
        if [ ! -r "$LOG_FILE" ]; then
            log_error "Log file not readable: $LOG_FILE"
            exit 1
        fi
        log_info "📂 Analyzing log file: $LOG_FILE"
    else
        log_info "📥 Reading from stdin..."
    fi
    
    # Perform the analysis
    if analyze_filtered_output; then
        log_success "✅ Error analysis completed"
    else
        log_info "✅ No errors found - log appears clean"
    fi
}

# Execute main function
main "$@"
