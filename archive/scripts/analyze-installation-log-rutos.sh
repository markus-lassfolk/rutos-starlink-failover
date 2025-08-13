#!/bin/sh
# ==============================================================================
# RUTOS Installation Log Analysis Script
# Quick analysis tool for bootstrap and deployment logs
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="3.0.0"

# Color output (simple method for compatibility)
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m" # No Color

# Simple logging functions
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$*"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$*"
}

# Help function
show_help() {
    cat <<EOF
RUTOS Installation Log Analysis Tool v${SCRIPT_VERSION}

USAGE:
    $0 [OPTIONS] [LOG_FILE]

OPTIONS:
    -h, --help      Show this help message
    -q, --quiet     Show only errors and warnings
    -s, --summary   Show summary statistics only
    -e, --errors    Show errors only
    -w, --warnings  Show warnings only
    -f, --full      Show full analysis (default)

EXAMPLES:
    # Analyze deployment log
    $0 /tmp/starlink-deployment-install-*.log
    
    # Show only errors
    $0 -e /tmp/starlink-deployment-install-*.log
    
    # Show summary statistics
    $0 -s /tmp/starlink-deployment-install-*.log
    
    # Auto-find and analyze latest log
    $0

EOF
}

# Find latest installation log
find_latest_log() {
    # Look in common log locations
    for log_dir in "/usr/local/starlink/logs" "/opt/starlink/logs" "/var/log" "/tmp"; do
        if [ -d "$log_dir" ]; then
            # Find most recent starlink installation log
            latest_log=$(find "$log_dir" -name "*starlink*install*.log" -type f -exec ls -t {} + 2>/dev/null | head -n 1)
            if [ -n "$latest_log" ]; then
                printf "%s" "$latest_log"
                return 0
            fi
        fi
    done
    return 1
}

# Analyze log file
analyze_log() {
    log_file="$1"
    mode="${2:-full}"
    
    if [ ! -f "$log_file" ]; then
        log_error "Log file not found: $log_file"
        return 1
    fi
    
    log_info "Analyzing installation log: $log_file"
    log_info "Log file size: $(wc -c <"$log_file" 2>/dev/null || echo "unknown") bytes"
    log_info "Log file lines: $(wc -l <"$log_file" 2>/dev/null || echo "unknown") lines"
    printf "\n"
    
    # Count different message types
    error_count=$(grep -c -i "ERROR" "$log_file" 2>/dev/null || echo "0")
    warning_count=$(grep -c -i "WARNING" "$log_file" 2>/dev/null || echo "0")
    success_count=$(grep -c -i "SUCCESS" "$log_file" 2>/dev/null || echo "0")
    debug_count=$(grep -c -i "DEBUG" "$log_file" 2>/dev/null || echo "0")
    
    # Summary statistics
    if [ "$mode" = "summary" ] || [ "$mode" = "full" ]; then
        log_info "📊 MESSAGE SUMMARY:"
        printf "   ✅ Success messages: %d\n" "$success_count"
        printf "   ⚠️  Warning messages: %d\n" "$warning_count"
        printf "   ❌ Error messages: %d\n" "$error_count"
        printf "   🔧 Debug messages: %d\n" "$debug_count"
        printf "\n"
    fi
    
    # Show errors
    if [ "$mode" = "errors" ] || [ "$mode" = "full" ]; then
        if [ "$error_count" -gt 0 ]; then
            log_error "❌ ERRORS FOUND ($error_count):"
            grep -i "ERROR" "$log_file" 2>/dev/null | while IFS= read -r line; do
                printf "   %s\n" "$line"
            done
            printf "\n"
        else
            log_success "✅ No errors found in log file"
        fi
    fi
    
    # Show warnings
    if [ "$mode" = "warnings" ] || [ "$mode" = "full" ]; then
        if [ "$warning_count" -gt 0 ]; then
            log_warning "⚠️ WARNINGS FOUND ($warning_count):"
            grep -i "WARNING" "$log_file" 2>/dev/null | while IFS= read -r line; do
                printf "   %s\n" "$line"
            done
            printf "\n"
        else
            log_success "✅ No warnings found in log file"
        fi
    fi
    
    # Show recent activity (last 10 lines)
    if [ "$mode" = "full" ]; then
        log_info "📝 RECENT ACTIVITY (last 10 lines):"
        tail -n 10 "$log_file" 2>/dev/null | while IFS= read -r line; do
            printf "   %s\n" "$line"
        done
        printf "\n"
    fi
    
    # Provide analysis commands
    if [ "$mode" = "full" ]; then
        log_info "🔧 MANUAL ANALYSIS COMMANDS:"
        printf "   View full log: less '%s'\n" "$log_file"
        printf "   View errors: grep -i error '%s'\n" "$log_file"
        printf "   View warnings: grep -i warning '%s'\n" "$log_file"
        printf "   View success: grep -i success '%s'\n" "$log_file"
        printf "\n"
    fi
}

# Main function
main() {
    mode="full"
    log_file=""
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quiet)
                mode="quiet"
                shift
                ;;
            -s|--summary)
                mode="summary"
                shift
                ;;
            -e|--errors)
                mode="errors"
                shift
                ;;
            -w|--warnings)
                mode="warnings"
                shift
                ;;
            -f|--full)
                mode="full"
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                log_file="$1"
                shift
                ;;
        esac
    done
    
    # If no log file specified, try to find latest
    if [ -z "$log_file" ]; then
        if ! log_file=$(find_latest_log); then
            log_error "No installation log file found"
            log_info "Specify log file manually or check these locations:"
            printf "   /usr/local/starlink/logs/\n"
            printf "   /opt/starlink/logs/\n"
            printf "   /var/log/\n"
            printf "   /tmp/\n"
            exit 1
        fi
        log_info "Auto-discovered log file: $log_file"
    fi
    
    # Analyze the log
    analyze_log "$log_file" "$mode"
}

# Execute main function
main "$@"
