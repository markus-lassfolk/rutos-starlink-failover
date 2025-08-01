#!/bin/sh
# Script: view-logs-rutos.sh
# Version: 2.7.1
# Description: View and analyze system logs for troubleshooting
# Compatible with: RUTOS (busybox sh)

set -e # Exit on error

# Version information (used for version tracking and logging)
# shellcheck disable=SC2034  # SCRIPT_VERSION used for version reporting
# Version information (auto-updated by update-version.sh)
# Standard colors for consistent output (compatible with busybox)
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='[0;35m'
CYAN='[0;36m'
NC='[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions (Method 5 format for RUTOS compatibility)
log_info() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[WARNING]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}[DEBUG]${NC} [%s] DRY_RUN=%s, RUTOS_TEST_MODE=%s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$DRY_RUN" "$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        if [ "${DEBUG:-0}" = "1" ]; then
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${CYAN}[DEBUG]${NC} [%s] [DRY-RUN] Command: %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$cmd"
        fi
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${CYAN}[DEBUG]${NC} [%s] Executing: %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$cmd"
        fi
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Constants
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"
LOG_DIR="$INSTALL_DIR/logs"

# Print header
print_header() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}                    STARLINK SYSTEM LOGS VIEWER${NC}
"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

"
}

# Show usage
show_usage() {
    printf "Usage: %s [OPTION]

" "$(basename "$0")"
    printf "Options:
"
    printf "  --monitor       Show monitoring system logs
"
    printf "  --system        Show system logs (syslog, dmesg)
"
    printf "  --errors        Show error logs only
"
    printf "  --recent        Show recent logs (last 100 lines)
"
    printf "  --tail          Tail logs in real-time
"
    printf "  --help          Show this help message

"
    printf "Examples:
"
    printf "  %s --monitor      # View monitoring logs
" "$(basename "$0")"
    printf "  %s --errors       # View error logs only
" "$(basename "$0")"
    printf "  %s --tail         # Follow logs in real-time
" "$(basename "$0")"
    printf "  %s --recent       # Show last 100 log entries
" "$(basename "$0")"
}

# View monitoring logs
view_monitor_logs() {
    log_step "Displaying monitoring system logs"

    if [ -f "$LOG_DIR/starlink_monitor.log" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "
${GREEN}=== Starlink Monitor Log ===${NC}
"
        tail -50 "$LOG_DIR/starlink_monitor.log" || log_warning "Could not read monitor log"
    else
        log_warning "Monitor log not found: $LOG_DIR/starlink_monitor.log"
    fi

    if [ -f "$LOG_DIR/starlink_logger.log" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "
${GREEN}=== Starlink Logger Log ===${NC}
"
        tail -50 "$LOG_DIR/starlink_logger.log" || log_warning "Could not read logger log"
    else
        log_warning "Logger log not found: $LOG_DIR/starlink_logger.log"
    fi

    if [ -f "$LOG_DIR/api_check.log" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "
${GREEN}=== API Check Log ===${NC}
"
        tail -50 "$LOG_DIR/api_check.log" || log_warning "Could not read API check log"
    else
        log_warning "API check log not found: $LOG_DIR/api_check.log"
    fi
}

# View system logs
view_system_logs() {
    log_step "Displaying system logs"

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${GREEN}=== System Messages (last 50 lines) ===${NC}
"
    if [ -f "/var/log/messages" ]; then
        tail -50 /var/log/messages
    elif [ -f "/var/log/syslog" ]; then
        tail -50 /var/log/syslog
    else
        log_warning "System log not found"
    fi

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${GREEN}=== Kernel Messages (last 20 lines) ===${NC}
"
    dmesg | tail -20 || log_warning "Could not read kernel messages"
}

# View error logs only
view_error_logs() {
    log_step "Displaying error logs"

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${RED}=== Recent Errors from Monitoring Logs ===${NC}
"
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            log_name=$(basename "$log_file")
            errors=$(grep -i "error\|fail\|critical" "$log_file" | tail -10 2>/dev/null || true)
            if [ -n "$errors" ]; then
                printf "
${YELLOW}--- %s ---${NC}
" "$log_name"
                echo "$errors"
            fi
        fi
    done

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${RED}=== Recent System Errors ===${NC}
"
    if [ -f "/var/log/messages" ]; then
        grep -i "error\|fail\|critical" /var/log/messages | tail -20 2>/dev/null || log_info "No recent system errors found"
    elif [ -f "/var/log/syslog" ]; then
        grep -i "error\|fail\|critical" /var/log/syslog | tail -20 2>/dev/null || log_info "No recent system errors found"
    else
        log_warning "System log not found"
    fi
}

# View recent logs
view_recent_logs() {
    log_step "Displaying recent logs (last 100 lines)"

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${GREEN}=== All Recent Starlink Logs ===${NC}
"
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            log_name=$(basename "$log_file")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "
${CYAN}--- %s (last 20 lines) ---${NC}
" "$log_name"
            tail -20 "$log_file" 2>/dev/null || log_warning "Could not read $log_name"
        fi
    done
}

# Tail logs in real-time
tail_logs() {
    log_step "Following logs in real-time (press Ctrl+C to stop)"

    # Find available log files
    log_files=""
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            log_files="$log_files $log_file"
        fi
    done

    if [ -n "$log_files" ]; then
        printf "
${GREEN}Following logs: %s${NC}

" "$log_files"
        # shellcheck disable=SC2086  # We want word splitting for multiple files
        tail -f $log_files
    else
        log_warning "No log files found to tail"
        return 1
    fi
}

# Main function
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s
" "view-logs-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: view-logs-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    print_header

    case "${1:-}" in
        --monitor)
            view_monitor_logs
            ;;
        --system)
            view_system_logs
            ;;
        --errors)
            view_error_logs
            ;;
        --recent)
            view_recent_logs
            ;;
        --tail)
            tail_logs
            ;;
        --help)
            show_usage
            ;;
        "")
            # Default: show monitor logs and recent errors
            view_monitor_logs
            view_error_logs
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
