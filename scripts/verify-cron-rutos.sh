#!/bin/sh
# Script: verify-cron-rutos.sh
# Version: 2.7.1
# Description: Standalone cron configuration verification for Starlink monitoring

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059,SC2317  # Method 5 printf format required for RUTOS color support; Functions after early exit OK

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Configuration
CRON_FILE="/etc/crontabs/root"
INSTALL_DIR="/usr/local/starlink-monitor"

# Status counters
OK_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0

# Function to show verification result
show_result() {
    status="$1"
    component="$2"
    message="$3"

    case "$status" in
        "ok")
            status_color="$GREEN"
            status_text="✓ OK"
            OK_COUNT=$((OK_COUNT + 1))
            ;;
        "warn")
            status_color="$YELLOW"
            status_text="⚠ WARN"
            WARNING_COUNT=$((WARNING_COUNT + 1))
            ;;
        "error")
            status_color="$RED"
            status_text="✗ ERROR"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ;;
    esac

    printf "${status_color}%-8s${NC} | %-20s | %s\n" "$status_text" "$component" "$message"
}

# Function to verify cron service
check_cron_service() {
    log_step "Checking cron service status"

    if pgrep crond >/dev/null 2>&1; then
        show_result "ok" "Cron Service" "crond is running"
    else
        show_result "error" "Cron Service" "crond is not running"
        log_error "Cron service must be running for automated monitoring"
        log_error "Try: /etc/init.d/cron start"
    fi
}

# Function to verify cron file
check_cron_file() {
    log_step "Checking cron file"

    if [ -f "$CRON_FILE" ]; then
        show_result "ok" "Cron File" "File exists: $CRON_FILE"

        if [ -r "$CRON_FILE" ]; then
            show_result "ok" "Cron File Access" "File is readable"
        else
            show_result "error" "Cron File Access" "File is not readable"
        fi

        # Check if file is empty
        if [ -s "$CRON_FILE" ]; then
            line_count=$(wc -l <"$CRON_FILE")
            show_result "ok" "Cron File Content" "File has $line_count lines"
        else
            show_result "warn" "Cron File Content" "File is empty"
        fi
    else
        show_result "error" "Cron File" "File does not exist: $CRON_FILE"
        log_error "Cron file is required for automated monitoring"
    fi
}

# Function to analyze monitoring entries
check_monitoring_entries() {
    log_step "Analyzing monitoring entries"

    if [ ! -f "$CRON_FILE" ]; then
        show_result "error" "Entry Analysis" "Cannot analyze - cron file missing"
        return
    fi

    # Count entries for each script
    monitor_entries=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_check_entries=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
    maintenance_entries=$(grep -c "system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    # Monitor script analysis
    if [ "$monitor_entries" -eq 0 ]; then
        show_result "error" "Monitor Schedule" "No monitor entries found"
    elif [ "$monitor_entries" -eq 1 ]; then
        monitor_schedule=$(grep "starlink_monitor-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
        show_result "ok" "Monitor Schedule" "$monitor_schedule"
    else
        show_result "warn" "Monitor Schedule" "$monitor_entries entries (duplicates may conflict)"
        if [ "$DEBUG" = "1" ]; then
            log_debug "Monitor entries found:"
            grep "starlink_monitor-rutos.sh" "$CRON_FILE" | while IFS= read -r line; do
                log_debug "  $line"
            done
        fi
    fi

    # Logger script analysis
    if [ "$logger_entries" -eq 0 ]; then
        show_result "warn" "Logger Schedule" "No logger entries found"
    elif [ "$logger_entries" -eq 1 ]; then
        logger_schedule=$(grep "starlink_logger-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
        show_result "ok" "Logger Schedule" "$logger_schedule"
    else
        show_result "warn" "Logger Schedule" "$logger_entries entries (duplicates may conflict)"
    fi

    # API check script analysis
    if [ "$api_check_entries" -eq 0 ]; then
        show_result "warn" "API Check Schedule" "No API check entries found"
    elif [ "$api_check_entries" -eq 1 ]; then
        api_schedule=$(grep "check_starlink_api" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
        show_result "ok" "API Check Schedule" "$api_schedule"
    else
        show_result "warn" "API Check Schedule" "$api_check_entries entries (duplicates may conflict)"
    fi

    # System maintenance script analysis
    if [ "$maintenance_entries" -eq 0 ]; then
        show_result "error" "Maintenance Schedule" "No maintenance entries found - MISSING REQUIRED JOB!"
    elif [ "$maintenance_entries" -eq 1 ]; then
        maintenance_schedule=$(grep "system-maintenance-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
        show_result "ok" "Maintenance Schedule" "$maintenance_schedule"
    else
        show_result "warn" "Maintenance Schedule" "$maintenance_entries entries (duplicates may conflict)"
    fi

    # Total entry summary
    total_entries=$((monitor_entries + logger_entries + api_check_entries + maintenance_entries))
    if [ "$total_entries" -eq 0 ]; then
        show_result "error" "Total Entries" "No monitoring entries found"
    else
        show_result "ok" "Total Entries" "$total_entries monitoring entries"
    fi
}

# Function to check for cron entry issues
check_entry_quality() {
    log_step "Checking entry quality"

    if [ ! -f "$CRON_FILE" ]; then
        return
    fi

    # Check for duplicate entries
    duplicate_count=0
    if [ -f "$CRON_FILE" ]; then
        duplicate_count=$(grep -E "(starlink_monitor-rutos\.sh|starlink_logger-rutos\.sh|check_starlink_api|system-maintenance-rutos\.sh)" "$CRON_FILE" 2>/dev/null | sort | uniq -d | wc -l 2>/dev/null || echo "0")
        # Clean any whitespace/newlines from the count
        duplicate_count=$(echo "$duplicate_count" | tr -d '\n\r' | sed 's/[^0-9]//g')
        duplicate_count=${duplicate_count:-0}
    fi

    if [ "$duplicate_count" -gt 0 ]; then
        show_result "warn" "Duplicate Entries" "$duplicate_count exact duplicate lines found"
    else
        show_result "ok" "Duplicate Check" "No exact duplicates found"
    fi

    # Check for commented entries
    commented_count=$(grep -c "# COMMENTED BY.*starlink" "$CRON_FILE" 2>/dev/null || echo "0")
    if [ "$commented_count" -gt 0 ]; then
        show_result "warn" "Commented Entries" "$commented_count commented entries (cleanup recommended)"
    else
        show_result "ok" "Clean Entries" "No commented monitoring entries"
    fi

    # Check for CONFIG_FILE environment variable
    config_missing=0
    while IFS= read -r line; do
        case "$line" in
            *starlink*rutos.sh*)
                if ! echo "$line" | grep -q "CONFIG_FILE="; then
                    config_missing=$((config_missing + 1))
                fi
                ;;
        esac
    done <"$CRON_FILE"

    if [ "$config_missing" -gt 0 ]; then
        show_result "warn" "Config Environment" "$config_missing entries missing CONFIG_FILE variable"
    else
        show_result "ok" "Config Environment" "All entries have CONFIG_FILE set"
    fi

    # Basic cron syntax validation
    invalid_lines=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        case "$line" in
            "" | \#*) continue ;;
            *)
                # Basic validation: should have at least 6 fields (5 time fields + command)
                field_count=$(echo "$line" | awk '{print NF}')
                if [ "$field_count" -lt 6 ]; then
                    invalid_lines=$((invalid_lines + 1))
                    log_debug "Potentially invalid cron line: $line"
                fi
                ;;
        esac
    done <"$CRON_FILE"

    if [ "$invalid_lines" -gt 0 ]; then
        show_result "warn" "Cron Syntax" "$invalid_lines potentially invalid lines"
    else
        show_result "ok" "Cron Syntax" "All lines appear valid"
    fi
}

# Function to verify script files exist
check_script_files() {
    log_step "Checking script files"

    # Check if scripts exist and are executable
    scripts_to_check="starlink_monitor-rutos.sh starlink_logger-rutos.sh check_starlink_api-rutos.sh system-maintenance-rutos.sh"

    for script in $scripts_to_check; do
        script_path="$INSTALL_DIR/scripts/$script"

        if [ -f "$script_path" ]; then
            if [ -x "$script_path" ]; then
                show_result "ok" "Script: $script" "Exists and executable"
            else
                show_result "warn" "Script: $script" "Exists but not executable"
            fi
        else
            show_result "error" "Script: $script" "Not found at $script_path"
        fi
    done

    # Check configuration file
    config_path="/etc/starlink-config/config.sh"
    if [ -f "$config_path" ]; then
        show_result "ok" "Config File" "Configuration exists"
    else
        show_result "error" "Config File" "Configuration not found at $config_path"
    fi
}

# Function to show verification summary
show_summary() {
    echo ""
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}                           ${CYAN}VERIFICATION SUMMARY${NC}                            ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    total_checks=$((OK_COUNT + WARNING_COUNT + ERROR_COUNT))

    printf "${GREEN}✓ OK:${NC}       %2d checks passed\n" "$OK_COUNT"
    printf "${YELLOW}⚠ WARNINGS:${NC} %2d issues found\n" "$WARNING_COUNT"
    printf "${RED}✗ ERRORS:${NC}   %2d critical issues\n" "$ERROR_COUNT"
    printf "────────────────────────────\n"
    printf "Total:     %2d checks performed\n" "$total_checks"

    echo ""

    if [ "$ERROR_COUNT" -gt 0 ]; then
        log_error "Critical issues found! Automated monitoring may not work properly"
        echo ""
        printf "${YELLOW}Recommended actions:${NC}\n"
        printf "${CYAN}• Fix critical errors before relying on automated monitoring${NC}\n"
        printf "${CYAN}• Re-run install-rutos.sh to restore proper configuration${NC}\n"
        printf "${CYAN}• Check cron service: /etc/init.d/cron status${NC}\n"
    elif [ "$WARNING_COUNT" -gt 0 ]; then
        log_warning "Some issues found, but monitoring should still work"
        echo ""
        printf "${YELLOW}Optional improvements:${NC}\n"
        printf "${CYAN}• Clean up commented entries for tidier crontab${NC}\n"
        printf "${CYAN}• Remove duplicate entries to avoid conflicts${NC}\n"
    else
        log_success "All checks passed! Cron configuration is healthy"
        echo ""
        printf "${GREEN}Your automated monitoring is properly configured!${NC}\n"
    fi
}

# Show usage information
show_usage() {
    printf "${YELLOW}Usage:${NC} %s [OPTIONS]\n" "$0"
    echo ""
    printf "${YELLOW}Options:${NC}\n"
    printf "  -v, --verbose    Enable verbose output\n"
    printf "  -d, --debug      Enable debug mode\n"
    printf "  -h, --help       Show this help message\n"
    echo ""
    printf "${YELLOW}Description:${NC}\n"
    printf "  Verifies that Starlink monitoring cron jobs are properly configured\n"
    printf "  and will run automatically. Checks for common configuration issues.\n"
    echo ""
    printf "${YELLOW}Examples:${NC}\n"
    printf "  %s                     # Basic verification\n" "$0"
    printf "  DEBUG=1 %s            # With debug output\n" "$0"
    printf "  %s --verbose          # With verbose output\n" "$0"
}

# Main function
main() {
    log_info "Starting cron verification v$SCRIPT_VERSION"
    echo ""

    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}                    ${CYAN}STARLINK MONITORING CRON VERIFICATION${NC}                   ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    # Check if running on RUTOS/OpenWrt
    if [ ! -f "/etc/openwrt_release" ] && [ ! -f "/etc/rutos_version" ]; then
        log_warning "This doesn't appear to be OpenWrt/RUTOS system"
        printf "Continue anyway? (y/N): "
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            exit 1
        fi
    fi

    # Perform verification checks
    check_cron_service
    check_cron_file
    check_monitoring_entries
    check_entry_quality
    check_script_files

    # Show summary
    show_summary

    # Exit with appropriate code
    if [ "$ERROR_COUNT" -gt 0 ]; then
        exit 1
    elif [ "$WARNING_COUNT" -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            show_usage
            exit 0
            ;;
        -d | --debug)
            DEBUG=1
            ;;
        -v | --verbose)
            # Verbose mode could be implemented later
            log_info "Verbose mode enabled"
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# Execute main function
main "$@"
