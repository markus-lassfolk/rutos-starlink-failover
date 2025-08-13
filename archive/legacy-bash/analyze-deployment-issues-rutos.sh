#!/bin/sh
set -e

# Advanced log analyzer for RUTOS deployment issues
# This script can analyze logs, command output, or live deployment runs

SCRIPT_VERSION="1.0.0"

# Colors for better readability (RUTOS Method 5 format)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' NC=''
fi

# Logging functions using Method 5 printf format
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$*"; }
log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "${PURPLE}[DEBUG]${NC} %s\n" "$*"; }

# Error patterns for different severity levels
CRITICAL_PATTERNS="CRITICAL|FATAL|❌|Failed to|Cannot|Unable to|Permission denied|No such file|command not found|Usage: basename|multi-call binary"
ERROR_PATTERNS="ERROR|FAIL|sed:|uci: Entry not found|curl.*failed|wget.*failed|tar.*failed|BusyBox.*Usage:"
WARNING_PATTERNS="WARNING|WARN|⚠️|may not work|deprecated|falling back"

# RUTOS-specific patterns
RUTOS_PATTERNS="opkg.*failed|mwan3.*not found|gsmctl.*error|UCI.*error|busybox.*not found|BusyBox.*multi-call binary|Usage: basename"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND|LOG_FILE]

Advanced log analyzer for RUTOS deployment and system issues.

OPTIONS:
    -c, --context LINES     Context lines before/after errors (default: 5)
    -s, --severity LEVEL    Filter by severity: critical, error, warning, all (default: all)
    -r, --rutos             Show only RUTOS-specific issues
    -f, --follow           Follow live output (for commands)
    -n, --line-numbers     Show line numbers
    -t, --timestamps       Add analysis timestamps
    --no-color             Disable colored output
    -h, --help             Show this help

EXAMPLES:
    # Analyze existing log file
    $0 /var/log/deployment.log
    
    # Run deployment and analyze in real-time
    $0 -f ./deploy-starlink-solution-v3-rutos.sh
    
    # Show only critical issues with more context
    $0 -s critical -c 10 /var/log/messages
    
    # RUTOS-specific issues only
    $0 -r /var/log/syslog
    
    # Pipe from command
    ./deploy-starlink-solution-v3-rutos.sh 2>&1 | $0

SEVERITY LEVELS:
    critical: CRITICAL, FATAL, major failures
    error:    ERROR, FAIL, command failures
    warning:  WARNING, WARN, potential issues
    all:      All of the above (default)
EOF
}

# Parse arguments
CONTEXT_LINES=5
SEVERITY="all"
RUTOS_ONLY=0
FOLLOW=0
LINE_NUMBERS=""
TIMESTAMPS=0
INPUT_SOURCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--context)
            shift; CONTEXT_LINES="${1:-5}" ;;
        -s|--severity)
            shift; SEVERITY="${1:-all}" ;;
        -r|--rutos)
            RUTOS_ONLY=1 ;;
        -f|--follow)
            FOLLOW=1 ;;
        -n|--line-numbers)
            LINE_NUMBERS="-n" ;;
        -t|--timestamps)
            TIMESTAMPS=1 ;;
        --no-color)
            RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' NC='' ;;
        -h|--help)
            show_usage; exit 0 ;;
        -*)
            log_error "Unknown option: $1"; exit 1 ;;
        *)
            INPUT_SOURCE="$1"; break ;;
    esac
    shift
done

# Build pattern based on severity
build_pattern() {
    case "$SEVERITY" in
        critical) echo "$CRITICAL_PATTERNS" ;;
        error) echo "$ERROR_PATTERNS" ;;
        warning) echo "$WARNING_PATTERNS" ;;
        all) echo "$CRITICAL_PATTERNS|$ERROR_PATTERNS|$WARNING_PATTERNS" ;;
        *) log_error "Invalid severity: $SEVERITY"; exit 1 ;;
    esac
}

# Add RUTOS patterns if requested
PATTERN=$(build_pattern)
if [ "$RUTOS_ONLY" = "1" ]; then
    PATTERN="$RUTOS_PATTERNS"
elif [ "$SEVERITY" = "all" ]; then
    PATTERN="$PATTERN|$RUTOS_PATTERNS"
fi

# Analysis function
analyze_with_context() {
    local input="$1"
    local pattern="$2"
    local context="$3"
    
    if [ "$TIMESTAMPS" = "1" ]; then
        log_info "Analysis started at: $(date)"
    fi
    
    log_info "🔍 Analyzing with pattern: $SEVERITY level"
    log_info "📋 Context lines: ±$context"
    
    # Use appropriate grep command
    GREP_CMD="grep -E -i -A $context -B $context $LINE_NUMBERS"
    
    if [ -f "$input" ]; then
        log_info "📂 Source: $input (file)"
        $GREP_CMD "$pattern" "$input" 2>/dev/null || {
            log_success "✅ No issues found at $SEVERITY level"
            return 1
        }
    elif [ -x "$input" ] && [ "$FOLLOW" = "1" ]; then
        log_info "🚀 Source: $input (live execution)"
        "$input" 2>&1 | $GREP_CMD "$pattern" || {
            log_success "✅ No issues found during execution"
            return 1
        }
    else
        log_info "📥 Source: stdin"
        $GREP_CMD "$pattern" || {
            log_success "✅ No issues found in input"
            return 1
        }
    fi
}

# Count and categorize issues
analyze_issue_summary() {
    local temp_file="/tmp/analysis_$$"
    
    if analyze_with_context "$INPUT_SOURCE" "$PATTERN" "$CONTEXT_LINES" > "$temp_file" 2>&1; then
        
        # Count different types
        critical_count=$(grep -c -E -i "$CRITICAL_PATTERNS" "$temp_file" 2>/dev/null || echo "0")
        error_count=$(grep -c -E -i "$ERROR_PATTERNS" "$temp_file" 2>/dev/null || echo "0")
        warning_count=$(grep -c -E -i "$WARNING_PATTERNS" "$temp_file" 2>/dev/null || echo "0")
        rutos_count=$(grep -c -E -i "$RUTOS_PATTERNS" "$temp_file" 2>/dev/null || echo "0")
        
        # Show summary
        printf "${CYAN}=========================================${NC}\n"
        printf "${WHITE}         ISSUE ANALYSIS SUMMARY${NC}\n"
        printf "${CYAN}=========================================${NC}\n"
        printf "${RED}Critical issues: %s${NC}\n" "$critical_count"
        printf "${YELLOW}Error issues: %s${NC}\n" "$error_count"
        printf "${BLUE}Warning issues: %s${NC}\n" "$warning_count"
        printf "${PURPLE}RUTOS-specific: %s${NC}\n" "$rutos_count"
        printf "${CYAN}=========================================${NC}\n"
        echo ""
        
        # Show the content
        cat "$temp_file"
        
        echo ""
        printf "${CYAN}=========================================${NC}\n"
        printf "${WHITE}            END ANALYSIS${NC}\n"
        printf "${CYAN}=========================================${NC}\n"
        
        if [ "$TIMESTAMPS" = "1" ]; then
            log_info "Analysis completed at: $(date)"
        fi
        
        rm -f "$temp_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Main execution
main() {
    log_info "🔧 RUTOS Advanced Log Analyzer v$SCRIPT_VERSION"
    
    # Handle input validation
    if [ -n "$INPUT_SOURCE" ]; then
        if [ -f "$INPUT_SOURCE" ]; then
            if [ ! -r "$INPUT_SOURCE" ]; then
                log_error "File not readable: $INPUT_SOURCE"
                exit 1
            fi
        elif [ -x "$INPUT_SOURCE" ] && [ "$FOLLOW" = "1" ]; then
            log_info "Will execute and analyze: $INPUT_SOURCE"
        elif [ ! -f "$INPUT_SOURCE" ] && [ "$FOLLOW" = "0" ]; then
            log_error "File not found: $INPUT_SOURCE"
            exit 1
        fi
    fi
    
    # Perform analysis
    if analyze_issue_summary; then
        log_warning "⚠️  Issues found - review the analysis above"
        exit 1
    else
        log_success "✅ Analysis completed - no issues found"
        exit 0
    fi
}

# Execute main function
main "$@"
