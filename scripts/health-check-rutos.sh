#!/bin/sh
# Script: health-check.sh
# Version: 2.5.0
# Description: Comprehensive system health check that orchestrates all other test scripts

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034  # Used in some conditional contexts
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
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

# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: health-check-rutos.sh v$SCRIPT_VERSION"
fi

# Enhanced debug functions for development
debug_exec() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "EXECUTING: $*"
    fi
    "$@"
}

debug_var() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "VARIABLE: $1 = $2"
    fi
}

debug_func() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "FUNCTION: $1"
    fi
}

# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: health-check-rutos.sh v$SCRIPT_VERSION"
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Enhanced error handling with detailed logging and dry-run support
safe_exec() {
    cmd="$1"
    description="$2"

    # Check for dry-run mode first
    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    fi

    debug_exec echo "Starting: $description"

    # Execute command and capture both stdout and stderr
    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show all output
        log_debug "EXECUTING: $cmd"
        log_debug "DESCRIPTION: $description"
        eval "$cmd"
        exit_code=$?
        log_debug "COMMAND EXIT CODE: $exit_code"
        return $exit_code
    else
        # In normal mode, suppress output but capture errors
        eval "$cmd" 2>/tmp/health_check_error.log
        exit_code=$?
        if [ $exit_code -ne 0 ] && [ -f /tmp/health_check_error.log ]; then
            log_debug "ERROR in $description: $(cat /tmp/health_check_error.log)"
            rm -f /tmp/health_check_error.log
        fi
        return $exit_code
    fi
}

# Validate binary with detailed logging
validate_binary() {
    binary_path="$1"
    binary_name="$2"

    debug_func "validate_binary"
    log_debug "VALIDATING BINARY: $binary_name at $binary_path"

    if [ ! -f "$binary_path" ]; then
        log_debug "FILE CHECK FAILED: $binary_path does not exist"
        return 1
    fi

    if [ ! -x "$binary_path" ]; then
        log_debug "PERMISSION CHECK FAILED: $binary_path is not executable"
        log_debug "FILE PERMISSIONS: $(ls -la "$binary_path" 2>/dev/null || echo 'Cannot read permissions')"
        return 1
    fi

    # Test if binary actually works
    log_debug "TESTING BINARY: $binary_path --help"
    if ! "$binary_path" --help >/dev/null 2>&1; then
        log_debug "BINARY TEST FAILED: $binary_path --help returned non-zero"
    else
        log_debug "BINARY TEST PASSED: $binary_name is functional"
    fi

    return 0
}

# Health check status functions
show_health_status() {
    status="$1"
    component="$2"
    message="$3"

    debug_func "show_health_status"
    log_debug "HEALTH STATUS: $status | $component | $message"

    case "$status" in
        "healthy")
            printf "${GREEN}✅ HEALTHY${NC}   | %-25s | %s\n" "$component" "$message"
            ;;
        "warning")
            printf "${YELLOW}⚠️  WARNING${NC}   | %-25s | %s\n" "$component" "$message"
            ;;
        "critical")
            printf "${RED}❌ CRITICAL${NC}  | %-25s | %s\n" "$component" "$message"
            ;;
        "unknown")
            printf "${CYAN}❓ UNKNOWN${NC}    | %-25s | %s\n" "$component" "$message"
            ;;
        *)
            printf "${PURPLE}ℹ️  INFO${NC}      | %-25s | %s\n" "$component" "$message"
            ;;
    esac

    # Log the status change for debugging
    log_debug "STATUS RECORDED: $component -> $status"
}

# Configuration paths - set defaults first
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"

# Load configuration from config file if available
if [ -f "$CONFIG_FILE" ]; then
    # Source the configuration file
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Set derived paths (these can also be overridden in config.sh)
SCRIPT_DIR="${SCRIPT_DIR:-$INSTALL_DIR/scripts}"
LOG_DIR="${LOG_DIR:-$INSTALL_DIR/logs}"
STATE_DIR="${STATE_DIR:-$INSTALL_DIR/state}"

# Configuration variables with fallback defaults
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-YOUR_PUSHOVER_API_TOKEN}"
PUSHOVER_USER="${PUSHOVER_USER:-YOUR_PUSHOVER_USER_KEY}"
GRPCURL_CMD="${GRPCURL_CMD:-$INSTALL_DIR/grpcurl}"
JQ_CMD="${JQ_CMD:-$INSTALL_DIR/jq}"
API_TIMEOUT="${API_TIMEOUT:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

# Global health counters
HEALTHY_COUNT=0
WARNING_COUNT=0
CRITICAL_COUNT=0
UNKNOWN_COUNT=0

# Debug mode support
DEBUG="${DEBUG:-0}"

# Add test mode for troubleshooting
if [ "${TEST_MODE:-0}" = "1" ]; then
    log_debug "TEST MODE ENABLED: Running in test mode"
    DEBUG=1 # Force debug mode in test mode
    # Note: set -x disabled during testing to avoid verbose output in test suite
    log_debug "TEST MODE: Running with enhanced debug logging"
fi

if [ "$DEBUG" = "1" ]; then
    log_debug "==================== HEALTH CHECK DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Script path: $0"
    log_debug "Process ID: $$"
    log_debug "User: $(whoami 2>/dev/null || echo 'unknown')"
    log_debug "Arguments: $*"
    log_debug "Environment DEBUG: ${DEBUG:-0}"
    log_debug "Environment TEST_MODE: ${TEST_MODE:-0}"

    log_debug "CONFIGURATION PATHS:"
    log_debug "  INSTALL_DIR=$INSTALL_DIR"
    log_debug "  CONFIG_FILE=$CONFIG_FILE"
    log_debug "  SCRIPT_DIR=$SCRIPT_DIR"
    log_debug "  LOG_DIR=$LOG_DIR"
    log_debug "  STATE_DIR=$STATE_DIR"

    log_debug "CONFIGURATION VALUES:"
    log_debug "  STARLINK_IP=$STARLINK_IP"
    log_debug "  PUSHOVER_TOKEN=$(printf "%.10s..." "$PUSHOVER_TOKEN")"
    log_debug "  PUSHOVER_USER=$(printf "%.10s..." "$PUSHOVER_USER")"
    log_debug "  GRPCURL_CMD=$GRPCURL_CMD"
    log_debug "  JQ_CMD=$JQ_CMD"
    log_debug "  API_TIMEOUT=$API_TIMEOUT"
    log_debug "  CHECK_INTERVAL=$CHECK_INTERVAL"

    # Check if configuration file was loaded
    if [ -f "$CONFIG_FILE" ]; then
        log_debug "CONFIG FILE: Successfully loaded from $CONFIG_FILE"
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "CONFIG FILE CONTENTS:"
            while IFS= read -r line; do
                # Don't log sensitive information in full
                case "$line" in
                    *PUSHOVER_TOKEN* | *PUSHOVER_USER*)
                        log_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        log_debug "  $line"
                        ;;
                esac
            done <"$CONFIG_FILE" 2>/dev/null || log_debug "  (Cannot read config file contents)"
        fi
    else
        log_debug "CONFIG FILE: Not found at $CONFIG_FILE - using defaults"
    fi
fi

# Function to increment health counters
increment_counter() {
    status="$1"
    debug_func "increment_counter"
    log_debug "COUNTER INCREMENT: $status"

    case "$status" in
        "healthy")
            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
            log_debug "COUNTER UPDATE: HEALTHY_COUNT now $HEALTHY_COUNT"
            ;;
        "warning")
            WARNING_COUNT=$((WARNING_COUNT + 1))
            log_debug "COUNTER UPDATE: WARNING_COUNT now $WARNING_COUNT"
            ;;
        "critical")
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            log_debug "COUNTER UPDATE: CRITICAL_COUNT now $CRITICAL_COUNT"
            ;;
        "unknown")
            UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
            log_debug "COUNTER UPDATE: UNKNOWN_COUNT now $UNKNOWN_COUNT"
            ;;
    esac

    total_checks=$((HEALTHY_COUNT + WARNING_COUNT + CRITICAL_COUNT + UNKNOWN_COUNT))
    log_debug "COUNTER TOTAL: $total_checks checks total"
}

# Function to comprehensively check cron configuration
check_cron_configuration() {
    log_debug "Starting comprehensive cron configuration check"

    # RUTOS uses /etc/crontabs/root instead of user crontabs
    CRON_FILE="/etc/crontabs/root"

    # Check if cron file exists
    if [ ! -f "$CRON_FILE" ]; then
        show_health_status "critical" "Cron File" "Cron file $CRON_FILE does not exist"
        increment_counter "critical"
        return
    fi

    # Check if cron service is running
    if pgrep crond >/dev/null 2>&1; then
        show_health_status "healthy" "Cron Service" "Cron daemon (crond) is running"
        increment_counter "healthy"
    else
        show_health_status "critical" "Cron Service" "Cron daemon (crond) is not running"
        increment_counter "critical"
    fi

    # Count our starlink monitoring entries
    monitor_entries=$(grep -c "starlink_monitor_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_check_entries=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")

    # Strip whitespace from counts to prevent arithmetic errors
    monitor_entries=$(echo "$monitor_entries" | tr -d ' \n\r')
    logger_entries=$(echo "$logger_entries" | tr -d ' \n\r')
    api_check_entries=$(echo "$api_check_entries" | tr -d ' \n\r')

    total_entries=$((monitor_entries + logger_entries + api_check_entries))

    if [ "$total_entries" -eq 0 ]; then
        show_health_status "critical" "Cron Entries" "No Starlink monitoring entries found"
        increment_counter "critical"
        log_debug "No monitoring entries found in crontab"
    else
        show_health_status "healthy" "Cron Entries" "Found $total_entries monitoring entries"
        increment_counter "healthy"
        log_debug "Found $total_entries total monitoring entries"
    fi

    # Detailed analysis of each script type
    if [ "$monitor_entries" -gt 0 ]; then
        if [ "$monitor_entries" -eq 1 ]; then
            # Extract the timing for the monitor entry
            monitor_schedule=$(grep "starlink_monitor_unified-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
            show_health_status "healthy" "Monitor Schedule" "Monitor: $monitor_schedule ($monitor_entries entry)"
            increment_counter "healthy"
        else
            show_health_status "warning" "Monitor Schedule" "Multiple monitor entries ($monitor_entries) - may cause conflicts"
            increment_counter "warning"
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "Monitor entries found:"
                grep "starlink_monitor_unified-rutos.sh" "$CRON_FILE" | while IFS= read -r line; do
                    log_debug "  $line"
                done
            fi
        fi
    else
        show_health_status "warning" "Monitor Schedule" "No monitor entries found"
        increment_counter "warning"
    fi

    if [ "$logger_entries" -gt 0 ]; then
        if [ "$logger_entries" -eq 1 ]; then
            logger_schedule=$(grep "starlink_logger_unified-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
            show_health_status "healthy" "Logger Schedule" "Logger: $logger_schedule ($logger_entries entry)"
            increment_counter "healthy"
        else
            show_health_status "warning" "Logger Schedule" "Multiple logger entries ($logger_entries) - may cause conflicts"
            increment_counter "warning"
        fi
    else
        show_health_status "warning" "Logger Schedule" "No logger entries found"
        increment_counter "warning"
    fi

    if [ "$api_check_entries" -gt 0 ]; then
        if [ "$api_check_entries" -eq 1 ]; then
            api_schedule=$(grep "check_starlink_api" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
            show_health_status "healthy" "API Check Schedule" "API Check: $api_schedule ($api_check_entries entry)"
            increment_counter "healthy"
        else
            show_health_status "warning" "API Check Schedule" "Multiple API check entries ($api_check_entries)"
            increment_counter "warning"
        fi
    else
        show_health_status "warning" "API Check Schedule" "No API check entries found"
        increment_counter "warning"
    fi

    # Check for duplicate/conflicting entries
    duplicate_lines=$(grep -E "(starlink_monitor-rutos\.sh|starlink_logger-rutos\.sh|check_starlink_api)" "$CRON_FILE" | sort | uniq -d | wc -l | tr -d ' \n\r')
    if [ "$duplicate_lines" -gt 0 ]; then
        show_health_status "warning" "Duplicate Entries" "Found $duplicate_lines duplicate cron lines"
        increment_counter "warning"
    else
        show_health_status "healthy" "Duplicate Check" "No duplicate entries detected"
        increment_counter "healthy"
    fi

    # Check for commented out entries (from old install scripts)
    commented_entries=$(grep -c "# COMMENTED BY.*starlink" "$CRON_FILE" 2>/dev/null || echo "0")
    # Strip whitespace from count to prevent arithmetic errors
    commented_entries=$(echo "$commented_entries" | tr -d ' \n\r')
    if [ "$commented_entries" -gt 0 ]; then
        show_health_status "warning" "Commented Entries" "Found $commented_entries commented entries (cleanup recommended)"
        increment_counter "warning"
    else
        show_health_status "healthy" "Clean Crontab" "No commented monitoring entries"
        increment_counter "healthy"
    fi

    # Validate cron syntax (basic check)
    if [ -f "$CRON_FILE" ] && [ -s "$CRON_FILE" ]; then
        # Count invalid cron lines (very basic validation)
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
            show_health_status "warning" "Cron Syntax" "Found $invalid_lines potentially invalid cron lines"
            increment_counter "warning"
        else
            show_health_status "healthy" "Cron Syntax" "Cron syntax appears valid"
            increment_counter "healthy"
        fi
    else
        show_health_status "warning" "Cron File" "Cron file is empty or cannot be read"
        increment_counter "warning"
    fi

    # Check if CONFIG_FILE is properly set in cron entries
    config_missing=0
    if [ "$total_entries" -gt 0 ]; then
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
            show_health_status "warning" "Config Environment" "Found $config_missing entries without CONFIG_FILE variable"
            increment_counter "warning"
        else
            show_health_status "healthy" "Config Environment" "All entries have CONFIG_FILE properly set"
            increment_counter "healthy"
        fi
    fi

    log_debug "Cron configuration check completed"
}

# Function to check if a service/process is running
check_process() {
    process_name="$1"
    if pgrep -f "$process_name" >/dev/null 2>&1; then
        return 0 # Running
    else
        return 1 # Not running
    fi
}

# Function to check log freshness
check_log_freshness() {
    log_file="$1"
    max_age_minutes="$2"
    component_name="$3"

    if [ ! -f "$log_file" ]; then
        show_health_status "critical" "$component_name" "Log file not found: $log_file"
        increment_counter "critical"
        return 1
    fi

    # Get file modification time in seconds since epoch
    file_mtime=$(stat -c %Y "$log_file" 2>/dev/null || echo "0")
    current_time=$(date +%s)

    # Validate that we got valid numbers
    if [ -z "$file_mtime" ] || [ "$file_mtime" = "0" ] || [ -z "$current_time" ]; then
        show_health_status "unknown" "$component_name" "Cannot determine log age (stat/date issue)"
        increment_counter "unknown"
        return 1
    fi

    age_seconds=$((current_time - file_mtime))
    age_minutes=$((age_seconds / 60))

    if [ "$age_minutes" -gt "$max_age_minutes" ]; then
        show_health_status "warning" "$component_name" "Log stale: $age_minutes minutes old (max: $max_age_minutes)"
        increment_counter "warning"
        return 1
    else
        show_health_status "healthy" "$component_name" "Log fresh: $age_minutes minutes old"
        increment_counter "healthy"
        return 0
    fi
}

# Function to check disk space
check_disk_space() {
    path="$1"
    threshold_percent="$2"
    component_name="$3"

    if [ ! -d "$path" ]; then
        show_health_status "critical" "$component_name" "Directory not found: $path"
        increment_counter "critical"
        return 1
    fi

    # Get disk usage percentage
    usage=$(df "$path" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$usage" -gt "$threshold_percent" ]; then
        show_health_status "warning" "$component_name" "Disk usage high: ${usage}% (threshold: ${threshold_percent}%)"
        increment_counter "warning"
        return 1
    else
        show_health_status "healthy" "$component_name" "Disk usage OK: ${usage}%"
        increment_counter "healthy"
        return 0
    fi
}

# Function to check RUTOS-specific disk space
check_rutos_disk_space() {
    # Check overlay filesystem (where user data and configs are stored)
    if df | grep -q "/overlay"; then
        overlay_usage=$(df /overlay | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ "$overlay_usage" -gt 80 ]; then
            show_health_status "critical" "Overlay Filesystem" "Disk usage critical: ${overlay_usage}% (threshold: 80%)"
            increment_counter "critical"
        elif [ "$overlay_usage" -gt 60 ]; then
            show_health_status "warning" "Overlay Filesystem" "Disk usage high: ${overlay_usage}% (threshold: 60%)"
            increment_counter "warning"
        else
            show_health_status "healthy" "Overlay Filesystem" "Disk usage OK: ${overlay_usage}%"
            increment_counter "healthy"
        fi
    else
        show_health_status "unknown" "Overlay Filesystem" "Overlay filesystem not found"
        increment_counter "unknown"
    fi

    # Check /tmp filesystem (memory-based, can affect performance)
    if df | grep -q "tmpfs.*tmp"; then
        tmp_usage=$(df /tmp | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ "$tmp_usage" -gt 90 ]; then
            show_health_status "warning" "Temp Filesystem" "Memory usage high: ${tmp_usage}% (threshold: 90%)"
            increment_counter "warning"
        else
            show_health_status "healthy" "Temp Filesystem" "Memory usage OK: ${tmp_usage}%"
            increment_counter "healthy"
        fi
    fi

    # Check /log filesystem (can fill up with logs)
    if df | grep -q "/log"; then
        log_usage=$(df /log | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ "$log_usage" -gt 85 ]; then
            show_health_status "warning" "Log Filesystem" "Disk usage high: ${log_usage}% (threshold: 85%)"
            increment_counter "warning"
        else
            show_health_status "healthy" "Log Filesystem" "Disk usage OK: ${log_usage}%"
            increment_counter "healthy"
        fi
    fi

    # Root filesystem note - explain why it might be 100% (this is normal in RUTOS)
    root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$root_usage" -gt 95 ]; then
        show_health_status "info" "Root Filesystem" "Read-only root at ${root_usage}% (normal for RUTOS)"
    else
        show_health_status "healthy" "Root Filesystem" "Usage: ${root_usage}%"
        increment_counter "healthy"
    fi

    # Check install directory specifically if it exists
    if [ -d "$INSTALL_DIR" ]; then
        # The install directory is typically on the overlay, so this gives us specific info
        install_usage=$(df "$INSTALL_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
        show_health_status "info" "Install Directory" "Usage: ${install_usage}% (on overlay)"
    fi
}

# Function to check system uptime
check_system_uptime() {
    uptime_info=$(uptime)
    load_avg=$(echo "$uptime_info" | sed 's/.*load average: //')

    show_health_status "healthy" "System Uptime" "$uptime_info"
    show_health_status "healthy" "Load Average" "$load_avg"
    increment_counter "healthy"
    increment_counter "healthy"
}

# Function to check network connectivity
check_network_connectivity() {
    log_step "Checking network connectivity"
    debug_func "check_network_connectivity"
    log_debug "Starting network connectivity checks..."
    log_debug "Testing basic internet connectivity..."

    # Basic internet connectivity test
    log_debug "PING TEST: Testing connectivity to 8.8.8.8"
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        show_health_status "healthy" "Internet Connectivity" "Can reach 8.8.8.8"
        increment_counter "healthy"
        log_debug "PING TEST: SUCCESS - 8.8.8.8 is reachable"
    else
        show_health_status "critical" "Internet Connectivity" "Cannot reach 8.8.8.8"
        increment_counter "critical"
        log_debug "PING TEST: FAILED - 8.8.8.8 is not reachable"

        # Additional debugging for ping failure
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "PING DEBUG: Attempting ping with verbose output..."
            ping_output=$(ping -c 1 -W 5 8.8.8.8 2>&1 || echo "ping command failed")
            log_debug "PING OUTPUT: $ping_output"
        fi
    fi

    # Test DNS resolution
    log_debug "DNS TEST: Testing DNS resolution for google.com"
    if nslookup google.com >/dev/null 2>&1; then
        show_health_status "healthy" "DNS Resolution" "Can resolve google.com"
        increment_counter "healthy"
        log_debug "DNS TEST: SUCCESS - google.com resolved"
    else
        show_health_status "critical" "DNS Resolution" "Cannot resolve google.com"
        increment_counter "critical"
        log_debug "DNS TEST: FAILED - google.com cannot be resolved"

        # Additional debugging for DNS failure
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "DNS DEBUG: Attempting nslookup with verbose output..."
            dns_output=$(nslookup google.com 2>&1 || echo "nslookup command failed")
            log_debug "DNS OUTPUT: $dns_output"

            # Check if DNS servers are configured
            log_debug "DNS SERVERS: Checking /etc/resolv.conf"
            if [ -f /etc/resolv.conf ]; then
                log_debug "RESOLV.CONF CONTENTS:"
                while IFS= read -r line; do
                    log_debug "  $line"
                done </etc/resolv.conf
            else
                log_debug "RESOLV.CONF: File not found"
            fi
        fi
    fi

    log_debug "Network connectivity checks completed"
}

# Function to check Starlink connectivity
check_starlink_connectivity() {
    log_step "Checking Starlink connectivity"
    debug_func "check_starlink_connectivity"
    log_debug "Starting Starlink connectivity checks..."
    log_debug "STARLINK_IP: $STARLINK_IP"
    log_debug "GRPCURL_CMD: $GRPCURL_CMD"

    # Load configuration to get Starlink IP
    if [ -f "$CONFIG_FILE" ]; then
        log_debug "CONFIG FILE: Loading configuration from $CONFIG_FILE"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/placeholder-utils.sh" 2>/dev/null || log_debug "placeholder-utils.sh not found"

        log_debug "POST-CONFIG STARLINK_IP: $STARLINK_IP"
        log_debug "POST-CONFIG STARLINK_PORT: $STARLINK_PORT"

        if [ -n "${STARLINK_IP:-}" ] && [ "$STARLINK_IP" != "YOUR_STARLINK_IP" ]; then
            # Use STARLINK_IP directly (no port extraction needed)
            STARLINK_HOST="$STARLINK_IP"
            log_debug "STARLINK HOST: Using $STARLINK_HOST for connectivity test"

            log_debug "PING TEST: Testing connectivity to Starlink device at $STARLINK_HOST"
            if ping -c 1 -W 5 "$STARLINK_HOST" >/dev/null 2>&1; then
                show_health_status "healthy" "Starlink Device" "Can reach $STARLINK_HOST"
                increment_counter "healthy"
                log_debug "STARLINK PING: SUCCESS - Device is reachable"
            else
                show_health_status "critical" "Starlink Device" "Cannot reach $STARLINK_HOST"
                increment_counter "critical"
                log_debug "STARLINK PING: FAILED - Device is not reachable"

                # Additional debugging for Starlink ping failure
                if [ "${DEBUG:-0}" = "1" ]; then
                    ping_output=$(ping -c 1 -W 5 "$STARLINK_HOST" 2>&1 || echo "ping command failed")
                    log_debug "STARLINK PING OUTPUT: $ping_output"
                fi
            fi

            # Test grpcurl if available (use configured GRPCURL_CMD and full STARLINK_IP)
            log_debug "GRPC TEST: Checking if grpcurl is available"
            if validate_binary "$GRPCURL_CMD" "grpcurl"; then
                log_debug "GRPC TEST: grpcurl validated, testing API connection"
                log_debug "GRPC COMMAND: $GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle"

                # Use the same endpoint as the API check script for consistency
                if [ "${DEBUG:-0}" = "1" ]; then
                    # In debug mode, capture and log the response
                    grpc_output=$("$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>&1)
                    grpc_exit=$?
                    log_debug "GRPC EXIT CODE: $grpc_exit"
                    log_debug "GRPC OUTPUT (first 200 chars): $(echo "$grpc_output" | cut -c1-200)$([ ${#grpc_output} -gt 200 ] && echo '...')"

                    if [ $grpc_exit -eq 0 ]; then
                        show_health_status "healthy" "Starlink gRPC API" "API responding on $STARLINK_IP"
                        increment_counter "healthy"
                        log_debug "GRPC TEST: SUCCESS - API is responding"
                    else
                        show_health_status "warning" "Starlink gRPC API" "API not responding on $STARLINK_IP"
                        increment_counter "warning"
                        log_debug "GRPC TEST: FAILED - API is not responding"
                    fi
                else
                    # Normal mode (less verbose)
                    if "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
                        show_health_status "healthy" "Starlink gRPC API" "API responding on $STARLINK_IP:$STARLINK_PORT"
                        increment_counter "healthy"
                    else
                        show_health_status "warning" "Starlink gRPC API" "API not responding on $STARLINK_IP"
                        increment_counter "warning"
                    fi
                fi
            else
                show_health_status "unknown" "Starlink gRPC API" "grpcurl not available for testing"
                increment_counter "unknown"
                log_debug "GRPC TEST: SKIPPED - grpcurl not available or not executable"
            fi
        else
            show_health_status "warning" "Starlink Device" "Starlink IP not configured"
            increment_counter "warning"
            log_debug "STARLINK CONFIG: IP not configured or using placeholder value"
        fi
    else
        show_health_status "critical" "Starlink Device" "Configuration file not found"
        increment_counter "critical"
        log_debug "CONFIG FILE: Not found at $CONFIG_FILE"
    fi

    log_debug "Starlink connectivity checks completed"
}

# Function to check notification system files and permissions
check_notification_system() {
    log_step "Checking notification system components"
    debug_func "check_notification_system"

    # Define expected paths for notification components
    HOTPLUG_NOTIFY="/etc/hotplug.d/iface/99-pushover_notify-rutos.sh"
    STARLINK_NOTIFY="/usr/local/starlink-monitor/scripts/99-pushover_notify-rutos.sh"
    MAIN_MONITOR="/usr/local/starlink-monitor/scripts/starlink_monitor_unified-rutos.sh"
    UTILS_SCRIPT="/usr/local/starlink-monitor/scripts/placeholder-utils.sh"

    # Check hotplug notification script (critical for failover notifications)
    log_debug "NOTIFICATION CHECK: Checking hotplug notification script"
    if [ -f "$HOTPLUG_NOTIFY" ]; then
        if [ -x "$HOTPLUG_NOTIFY" ]; then
            file_size=$(wc -c <"$HOTPLUG_NOTIFY" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 100 ]; then
                show_health_status "healthy" "Hotplug Notify" "Installed and executable ($file_size bytes)"
                increment_counter "healthy"
                log_debug "NOTIFICATION CHECK: HEALTHY - Hotplug script exists, executable, and has content"
            else
                show_health_status "warning" "Hotplug Notify" "File too small ($file_size bytes) - may be corrupted"
                increment_counter "warning"
                log_debug "NOTIFICATION CHECK: WARNING - Hotplug script too small"
            fi
        else
            show_health_status "critical" "Hotplug Notify" "File exists but not executable"
            increment_counter "critical"
            log_debug "NOTIFICATION CHECK: CRITICAL - Hotplug script not executable"
        fi
    else
        show_health_status "critical" "Hotplug Notify" "Missing: $HOTPLUG_NOTIFY"
        increment_counter "critical"
        log_debug "NOTIFICATION CHECK: CRITICAL - Hotplug script missing"
    fi

    # Check Starlink notification script (backup location)
    log_debug "NOTIFICATION CHECK: Checking Starlink notification script"
    if [ -f "$STARLINK_NOTIFY" ]; then
        if [ -x "$STARLINK_NOTIFY" ]; then
            file_size=$(wc -c <"$STARLINK_NOTIFY" 2>/dev/null || echo "0")
            show_health_status "healthy" "Starlink Notify" "Available and executable ($file_size bytes)"
            increment_counter "healthy"
            log_debug "NOTIFICATION CHECK: HEALTHY - Starlink notify script OK"
        else
            show_health_status "warning" "Starlink Notify" "File exists but not executable"
            increment_counter "warning"
            log_debug "NOTIFICATION CHECK: WARNING - Starlink notify script not executable"
        fi
    else
        show_health_status "warning" "Starlink Notify" "Missing backup script: $STARLINK_NOTIFY"
        increment_counter "warning"
        log_debug "NOTIFICATION CHECK: WARNING - Starlink notify script missing"
    fi

    # Check main monitoring script
    log_debug "NOTIFICATION CHECK: Checking main monitoring script"
    if [ -f "$MAIN_MONITOR" ]; then
        if [ -x "$MAIN_MONITOR" ]; then
            show_health_status "healthy" "Main Monitor" "Installed and executable"
            increment_counter "healthy"
            log_debug "NOTIFICATION CHECK: HEALTHY - Main monitor script OK"
        else
            show_health_status "critical" "Main Monitor" "File exists but not executable"
            increment_counter "critical"
            log_debug "NOTIFICATION CHECK: CRITICAL - Main monitor script not executable"
        fi
    else
        show_health_status "critical" "Main Monitor" "Missing: $MAIN_MONITOR"
        increment_counter "critical"
        log_debug "NOTIFICATION CHECK: CRITICAL - Main monitor script missing"
    fi

    # Check utility functions script
    log_debug "NOTIFICATION CHECK: Checking utility functions script"
    if [ -f "$UTILS_SCRIPT" ]; then
        if [ -r "$UTILS_SCRIPT" ]; then
            show_health_status "healthy" "Utils Script" "Available and readable"
            increment_counter "healthy"
            log_debug "NOTIFICATION CHECK: HEALTHY - Utils script OK"
        else
            show_health_status "warning" "Utils Script" "File exists but not readable"
            increment_counter "warning"
            log_debug "NOTIFICATION CHECK: WARNING - Utils script not readable"
        fi
    else
        show_health_status "warning" "Utils Script" "Missing: $UTILS_SCRIPT"
        increment_counter "warning"
        log_debug "NOTIFICATION CHECK: WARNING - Utils script missing"
    fi

    log_debug "NOTIFICATION CHECK: Notification system component check completed"
}

# Function to check configuration health
check_configuration_health() {
    log_step "Checking configuration health"
    debug_func "check_configuration_health"

    # Perform basic configuration validation inline (avoid hanging on interactive validate-config-rutos.sh)
    log_debug "CONFIG VALIDATION: Performing basic configuration checks inline"

    # Check if config file exists and is readable
    log_debug "CONFIG VALIDATION: Checking config file at $CONFIG_FILE"
    if [ ! -f "$CONFIG_FILE" ]; then
        show_health_status "critical" "Configuration" "Config file not found: $CONFIG_FILE"
        increment_counter "critical"
        log_debug "CONFIG VALIDATION: CRITICAL - Config file missing"
    elif [ ! -r "$CONFIG_FILE" ]; then
        show_health_status "critical" "Configuration" "Config file not readable: $CONFIG_FILE"
        increment_counter "critical"
        log_debug "CONFIG VALIDATION: CRITICAL - Config file not readable"
    else
        log_debug "CONFIG VALIDATION: Config file exists and is readable"

        # Check for required variables in config
        missing_vars=""
        required_vars="STARLINK_IP CHECK_INTERVAL API_TIMEOUT PUSHOVER_TOKEN PUSHOVER_USER"

        for var in $required_vars; do
            log_debug "CONFIG VALIDATION: Checking for required variable: $var"
            if ! grep -q "^${var}=" "$CONFIG_FILE" 2>/dev/null; then
                if [ -z "$missing_vars" ]; then
                    missing_vars="$var"
                else
                    missing_vars="$missing_vars, $var"
                fi
                log_debug "CONFIG VALIDATION: Missing variable: $var"
            else
                log_debug "CONFIG VALIDATION: Found variable: $var"
            fi
        done

        if [ -n "$missing_vars" ]; then
            show_health_status "warning" "Configuration" "Missing variables: $missing_vars"
            increment_counter "warning"
            log_debug "CONFIG VALIDATION: WARNING - Missing variables: $missing_vars"
        else
            show_health_status "healthy" "Configuration" "Essential configuration variables present"
            increment_counter "healthy"
            log_debug "CONFIG VALIDATION: SUCCESS - All essential variables found"
        fi
    fi

    # Continue to placeholder check section...
    placeholder_script="$SCRIPT_DIR/placeholder-utils.sh"
    log_debug "PLACEHOLDER CHECK: Checking for placeholder utils at $placeholder_script"

    if [ -f "$placeholder_script" ]; then
        log_debug "PLACEHOLDER CHECK: Utils script found, loading..."
        # shellcheck disable=SC1091,SC1090
        . "$placeholder_script"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE" 2>/dev/null || log_debug "Could not load config file for placeholder check"

        log_debug "PUSHOVER CHECK: Testing if Pushover is configured properly"
        if is_pushover_configured; then
            log_debug "PUSHOVER CHECK: Configuration valid, testing API connectivity"

            # Test actual Pushover API if curl is available
            if command -v curl >/dev/null 2>&1; then
                test_message="Health check test from RUTOS router at $(date '+%Y-%m-%d %H:%M:%S')"
                api_response=$(curl -s \
                    -F "token=$PUSHOVER_TOKEN" \
                    -F "user=$PUSHOVER_USER" \
                    -F "message=$test_message" \
                    -F "title=🏥 RUTOS Health Check" \
                    -F "priority=-2" \
                    https://api.pushover.net/1/messages.json 2>&1)

                if echo "$api_response" | grep -q '"status":1'; then
                    show_health_status "healthy" "Pushover API" "Pushover API test successful"
                    increment_counter "healthy"
                    log_debug "PUSHOVER CHECK: SUCCESS - API test passed"
                else
                    show_health_status "warning" "Pushover API" "API test failed: $(echo "$api_response" | grep -o '"errors":\[[^]]*\]' || echo "Unknown error")"
                    increment_counter "warning"
                    log_debug "PUSHOVER CHECK: WARNING - API test failed: $api_response"
                fi
            else
                show_health_status "healthy" "Pushover Config" "Pushover properly configured (no curl for API test)"
                increment_counter "healthy"
                log_debug "PUSHOVER CHECK: SUCCESS - properly configured (API test skipped)"
            fi
        else
            show_health_status "warning" "Pushover Config" "Pushover using placeholder values"
            increment_counter "warning"
            log_debug "PUSHOVER CHECK: WARNING - using placeholder values"
        fi
    else
        log_debug "PLACEHOLDER CHECK: Utils script not found, skipping placeholder validation"
    fi

    # Check notification system components (files, permissions, locations)
    check_notification_system

    log_debug "Configuration health checks completed"
}

# Function to check firmware upgrade persistence
check_firmware_persistence() {
    log_step "Checking firmware upgrade persistence"

    # Check if restoration service exists
    if [ -f "/etc/init.d/starlink-restore" ]; then
        show_health_status "healthy" "Restore Service" "Service file exists"
        increment_counter "healthy"

        # Check if service is executable
        if [ -x "/etc/init.d/starlink-restore" ]; then
            show_health_status "healthy" "Restore Service" "Service is executable"
            increment_counter "healthy"
        else
            show_health_status "warning" "Restore Service" "Service exists but not executable"
            increment_counter "warning"
        fi

        # Check if service is enabled
        if /etc/init.d/starlink-restore enabled 2>/dev/null; then
            show_health_status "healthy" "Restore Service" "Service is enabled for startup"
            increment_counter "healthy"
        else
            show_health_status "critical" "Restore Service" "Service NOT enabled - won't survive firmware upgrade"
            increment_counter "critical"
        fi
    else
        show_health_status "critical" "Restore Service" "Restoration service not found"
        show_health_status "critical" "Firmware Upgrade" "System won't survive firmware upgrades"
        increment_counter "critical"
        increment_counter "critical"
    fi

    # Check if persistent config backup exists and is valid
    if [ -d "/etc/starlink-config" ]; then
        if [ -f "/etc/starlink-config/config.sh" ]; then
            # Check if persistent config is valid
            if sh -n "/etc/starlink-config/config.sh" 2>/dev/null; then
                # Check file size (should not be too small)
                config_size=$(wc -c <"/etc/starlink-config/config.sh" 2>/dev/null || echo "0")
                if [ "$config_size" -gt 100 ]; then
                    show_health_status "healthy" "Config Backup" "Valid persistent configuration backup exists (${config_size} bytes)"
                    increment_counter "healthy"

                    # Check for required settings
                    missing_settings=""
                    for setting in STARLINK_IP MWAN_IFACE MWAN_MEMBER; do
                        if ! grep -q "^${setting}=" "/etc/starlink-config/config.sh" 2>/dev/null; then
                            missing_settings="$missing_settings $setting"
                        fi
                    done

                    if [ -z "$missing_settings" ]; then
                        show_health_status "healthy" "Config Completeness" "All required settings present in backup"
                        increment_counter "healthy"
                    else
                        show_health_status "warning" "Config Completeness" "Missing settings in backup:$missing_settings"
                        increment_counter "warning"
                    fi
                else
                    show_health_status "critical" "Config Backup" "Persistent config too small ($config_size bytes) - likely corrupted"
                    increment_counter "critical"
                fi
            else
                show_health_status "critical" "Config Backup" "Persistent configuration has syntax errors"
                increment_counter "critical"
            fi
        else
            show_health_status "warning" "Config Backup" "Backup directory exists but no config.sh"
            increment_counter "warning"
        fi

        # Check for backup history
        backup_count=$(find "/etc/starlink-config" -name "config.sh.backup.*" -type f 2>/dev/null | wc -l | tr -d ' \n\r')
        if [ "$backup_count" -gt 0 ]; then
            show_health_status "healthy" "Backup History" "Found $backup_count timestamped configuration backups"
            increment_counter "healthy"
        fi
    else
        show_health_status "critical" "Config Backup" "No persistent config backup - settings will be lost on firmware upgrade"
        increment_counter "critical"
    fi

    # Check restoration log if available
    if [ -f "/var/log/starlink-restore.log" ]; then
        # Check if log is recent (within last 30 days, indicating recent restoration activity)
        if [ -n "$(find "/var/log/starlink-restore.log" -mtime -30 2>/dev/null)" ]; then
            log_lines=$(wc -l <"/var/log/starlink-restore.log" 2>/dev/null | tr -d ' \n\r' || echo "0")
            show_health_status "healthy" "Restore Activity" "Recent activity logged ($log_lines lines)"
            increment_counter "healthy"

            # Check for enhanced restoration features in log
            if grep -q "enhanced configuration restoration" "/var/log/starlink-restore.log" 2>/dev/null; then
                show_health_status "healthy" "Enhanced Restore" "Enhanced restoration system detected in logs"
                increment_counter "healthy"

                # Check for validation and backup activities
                validation_count=$(grep -c "Configuration validation" "/var/log/starlink-restore.log" 2>/dev/null || echo "0")
                backup_count=$(grep -c "Fresh configuration backed up" "/var/log/starlink-restore.log" 2>/dev/null || echo "0")

                if [ "$validation_count" -gt 0 ] && [ "$backup_count" -gt 0 ]; then
                    show_health_status "healthy" "Restore Safety" "Validation ($validation_count) and backup ($backup_count) activities logged"
                    increment_counter "healthy"
                else
                    show_health_status "warning" "Restore Safety" "Limited safety logging detected (V:$validation_count B:$backup_count)"
                    increment_counter "warning"
                fi
            else
                show_health_status "warning" "Restore Version" "Legacy restoration system detected - consider upgrading"
                increment_counter "warning"
            fi
        else
            show_health_status "warning" "Restore Activity" "Restore log exists but no recent activity"
            increment_counter "warning"
        fi
    else
        show_health_status "warning" "Restore Activity" "No restoration activity logged yet"
        increment_counter "warning"
    fi
}

# Function to check monitoring system health
check_monitoring_health() {
    log_step "Checking monitoring system health"

    # Check if monitoring script exists
    if [ -f "$INSTALL_DIR/scripts/starlink_monitor_unified-rutos.sh" ]; then
        show_health_status "healthy" "Monitor Script" "Script exists and is readable"
        increment_counter "healthy"
    else
        show_health_status "critical" "Monitor Script" "starlink_monitor_unified-rutos.sh not found"
        increment_counter "critical"
    fi

    # Comprehensive cron monitoring checks
    check_cron_configuration

    # Check state files to see if monitoring has run
    monitor_state_file="$STATE_DIR/starlink_monitor.state"
    if [ -f "$monitor_state_file" ]; then
        state_content=$(cat "$monitor_state_file" 2>/dev/null || echo "unknown")
        case "$state_content" in
            "up") show_health_status "healthy" "Monitor State" "Starlink connection: UP" ;;
            "down") show_health_status "warning" "Monitor State" "Starlink connection: DOWN" ;;
            *) show_health_status "unknown" "Monitor State" "State: $state_content" ;;
        esac
        increment_counter "healthy"
    else
        # Check if state directory exists
        if [ ! -d "$STATE_DIR" ]; then
            show_health_status "warning" "Monitor State" "State directory missing: $STATE_DIR"
        else
            show_health_status "warning" "Monitor State" "State file not found (monitoring may not have run yet)"
        fi
        increment_counter "warning"
    fi

    # Check for recent monitoring activity
    if [ -f "$LOG_DIR/starlink_monitor.log" ]; then
        check_log_freshness "$LOG_DIR/starlink_monitor.log" 30 "Monitor Activity"
    elif [ -f "$LOG_DIR/starlink_monitor_$(date '+%Y-%m-%d').log" ]; then
        check_log_freshness "$LOG_DIR/starlink_monitor_$(date '+%Y-%m-%d').log" 30 "Monitor Activity"
    else
        show_health_status "warning" "Monitor Activity" "No monitoring log files found"
        increment_counter "warning"
    fi
}

# Function to check logger sample tracking health
check_logger_sample_tracking() {
    log_step "Checking logger sample tracking health"

    # Set defaults
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    STARLINK_PORT="${STARLINK_PORT:-9200}"
    STATE_DIR="${STATE_DIR:-/tmp/run}"
    LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"
    GRPCURL_CMD="${GRPCURL_CMD:-$INSTALL_DIR/grpcurl}"
    JQ_CMD="${JQ_CMD:-$INSTALL_DIR/jq}"

    # Check if binaries exist
    if [ ! -x "$GRPCURL_CMD" ] || [ ! -x "$JQ_CMD" ]; then
        show_health_status "warning" "Logger Sample Tracking" "Required binaries (grpcurl/jq) not found"
        increment_counter "warning"
        return
    fi

    # Check if tracking file exists
    if [ ! -f "$LAST_SAMPLE_FILE" ]; then
        show_health_status "info" "Logger Sample Tracking" "Tracking file not found (normal for new installations)"
        increment_counter "healthy"
        return
    fi

    # Get current API sample index (with timeout and error handling)
    log_debug "Checking Starlink API for current sample index..."
    current_sample_index=""
    if history_data=$(timeout 10 "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_history":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null); then
        if [ -n "$history_data" ]; then
            current_sample_index=$(echo "$history_data" | "$JQ_CMD" -r '.dishGetHistory.current' 2>/dev/null)
        fi
    fi

    # Handle API errors gracefully
    if [ -z "$current_sample_index" ] || [ "$current_sample_index" = "null" ]; then
        show_health_status "warning" "Logger Sample Tracking" "Cannot check - Starlink API not responding"
        increment_counter "warning"
        return
    fi

    # Get tracked sample index
    last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "0")

    # Check for the stale tracking issue
    if [ "$last_sample_index" -gt "$current_sample_index" ]; then
        # This is the problem we found!
        difference=$((last_sample_index - current_sample_index))
        show_health_status "critical" "Logger Sample Tracking" "Stale tracking index detected (tracked: $last_sample_index, API: $current_sample_index, diff: +$difference)"
        increment_counter "critical"

        # Add recommendation
        log_warning "Logger sample tracking issue detected:"
        log_warning "  Tracked index: $last_sample_index"
        log_warning "  Current API index: $current_sample_index"
        log_warning "  This prevents CSV logging from working"
        log_warning "  Run: $INSTALL_DIR/scripts/fix-logger-tracking-rutos.sh"
    else
        # Tracking looks healthy
        if [ "$current_sample_index" -gt "$last_sample_index" ]; then
            pending_samples=$((current_sample_index - last_sample_index))
            show_health_status "healthy" "Logger Sample Tracking" "Working correctly ($pending_samples new samples pending)"
        else
            show_health_status "healthy" "Logger Sample Tracking" "Working correctly (up to date)"
        fi
        increment_counter "healthy"
    fi
}

# Function to check system resources
check_system_resources() {
    log_step "Checking system resources"
    log_debug "Starting system monitoring checks..."

    # Check system uptime and load
    check_system_uptime

    # Check disk space - RUTOS-specific filesystem monitoring
    check_rutos_disk_space

    # Check memory usage
    if command -v free >/dev/null 2>&1; then
        mem_usage=$(free | awk 'NR==2{printf "%.0f", ($3/$2)*100}')
        if [ "$mem_usage" -gt 80 ]; then
            show_health_status "warning" "Memory Usage" "${mem_usage}% used (threshold: 80%)"
            increment_counter "warning"
        else
            show_health_status "healthy" "Memory Usage" "${mem_usage}% used"
            increment_counter "healthy"
        fi
    else
        show_health_status "unknown" "Memory Usage" "free command not available"
        increment_counter "unknown"
    fi
}

# Function to run integrated tests
run_integrated_tests() {
    log_step "Running integrated tests"

    # Test Pushover notifications
    if [ -x "$SCRIPT_DIR/test-pushover-rutos.sh" ]; then
        if "$SCRIPT_DIR/test-pushover-rutos.sh" >/dev/null 2>&1; then
            show_health_status "healthy" "Pushover Test" "Notification test passed"
            increment_counter "healthy"
        else
            show_health_status "warning" "Pushover Test" "Notification test failed (may be disabled)"
            increment_counter "warning"
        fi
    else
        show_health_status "unknown" "Pushover Test" "test-pushover-rutos.sh not found"
        increment_counter "unknown"
    fi

    # Test monitoring connectivity
    if [ -x "$SCRIPT_DIR/test-monitoring-rutos.sh" ]; then
        if "$SCRIPT_DIR/test-monitoring-rutos.sh" >/dev/null 2>&1; then
            show_health_status "healthy" "Monitoring Test" "Connectivity test passed"
            increment_counter "healthy"
        else
            show_health_status "warning" "Monitoring Test" "Connectivity test failed"
            increment_counter "warning"
        fi
    else
        show_health_status "unknown" "Monitoring Test" "test-monitoring-rutos.sh not found"
        increment_counter "unknown"
    fi

    # Run system status check
    if [ -x "$SCRIPT_DIR/system-status-rutos.sh" ]; then
        if "$SCRIPT_DIR/system-status-rutos.sh" >/dev/null 2>&1; then
            show_health_status "healthy" "System Status" "System status check passed"
            increment_counter "healthy"
        else
            show_health_status "warning" "System Status" "System status check failed"
            increment_counter "warning"
        fi
    else
        show_health_status "unknown" "System Status" "system-status-rutos.sh not found"
        increment_counter "unknown"
    fi
}

# Test script execution in dry-run mode
test_script_execution() {
    debug_func "test_script_execution"
    log_step "Testing script execution in dry-run mode"

    # Critical scripts that should be tested
    MAIN_MONITOR="/usr/local/starlink-monitor/scripts/starlink_monitor_unified-rutos.sh"
    MAIN_LOGGER="/usr/local/starlink-monitor/scripts/starlink_logger_unified-rutos.sh"

    # Test main monitoring script
    if [ -x "$MAIN_MONITOR" ]; then
        log_debug "Testing main monitor script execution"
        if error_output=$(DRY_RUN=1 RUTOS_TEST_MODE=1 "$MAIN_MONITOR" 2>&1); then
            show_health_status "healthy" "Monitor Execution" "Script executes successfully in dry-run mode"
            increment_counter "healthy"
            log_debug "Monitor script dry-run test: PASSED"
        else
            show_health_status "critical" "Monitor Execution" "Script execution failed: $error_output"
            increment_counter "critical"
            log_debug "Monitor script dry-run test: FAILED - $error_output"
        fi
    else
        show_health_status "unknown" "Monitor Execution" "Monitor script not found or not executable"
        increment_counter "unknown"
    fi

    # Test main logger script
    if [ -x "$MAIN_LOGGER" ]; then
        log_debug "Testing main logger script execution"
        if error_output=$(DRY_RUN=1 RUTOS_TEST_MODE=1 "$MAIN_LOGGER" 2>&1); then
            show_health_status "healthy" "Logger Execution" "Script executes successfully in dry-run mode"
            increment_counter "healthy"
            log_debug "Logger script dry-run test: PASSED"
        else
            show_health_status "critical" "Logger Execution" "Script execution failed: $error_output"
            increment_counter "critical"
            log_debug "Logger script dry-run test: FAILED - $error_output"
        fi
    else
        show_health_status "unknown" "Logger Execution" "Logger script not found or not executable"
        increment_counter "unknown"
    fi

    # Test configuration validation script
    VALIDATE_CONFIG="$SCRIPT_DIR/validate-config-rutos.sh"
    if [ -x "$VALIDATE_CONFIG" ]; then
        log_debug "Testing config validation script execution"
        if error_output=$(DRY_RUN=1 "$VALIDATE_CONFIG" 2>&1); then
            show_health_status "healthy" "Config Validation" "Script executes successfully"
            increment_counter "healthy"
            log_debug "Config validation test: PASSED"
        else
            show_health_status "warning" "Config Validation" "Config validation issues detected"
            increment_counter "warning"
            log_debug "Config validation test: WARNING - $error_output"
        fi
    else
        show_health_status "unknown" "Config Validation" "validate-config-rutos.sh not found"
        increment_counter "unknown"
    fi
}

# Function to check system logs for script errors
check_system_log_errors() {
    debug_func "check_system_log_errors"
    check_name="$1"
    # Updated pattern to match our actual error formats
    pattern="${2:-\[ERROR\].*starlink|\[ERROR\].*Failed to fetch|\[ERROR\].*Failed to get|starlink.*error|parameter.*not set|failed.*load|command.*not found}"
    max_age_hours="${3:-2}" # Default 2 hours

    log_debug "Checking system logs for errors: $pattern"

    # Use logread if available (RUTOS), otherwise check syslog files
    if command -v logread >/dev/null 2>&1; then
        # Use logread to check system logs (look for [ERROR] messages)
        recent_errors=$(logread 2>/dev/null | grep -iE "$pattern" | tail -20 2>/dev/null || echo "")
    elif [ -f "/var/log/messages" ]; then
        # Check /var/log/messages for recent errors
        recent_errors=$(find /var/log/messages -mmin -$((max_age_hours * 60)) -exec grep -iE "$pattern" {} \; 2>/dev/null | tail -20 || echo "")
    elif [ -f "/var/log/syslog" ]; then
        # Check /var/log/syslog for recent errors
        recent_errors=$(find /var/log/syslog -mmin -$((max_age_hours * 60)) -exec grep -iE "$pattern" {} \; 2>/dev/null | tail -20 || echo "")
    else
        # Also check for any recent starlink log files
        if [ -d "/var/log/starlink" ]; then
            recent_errors=$(find /var/log/starlink -name "*.log" -mmin -$((max_age_hours * 60)) -exec grep -iE "$pattern" {} \; 2>/dev/null | tail -20 || echo "")
        fi

        if [ -z "$recent_errors" ]; then
            show_health_status "warning" "$check_name" "No system logs available for error checking"
            increment_counter "warning"
            return 1
        fi
    fi

    if [ -n "$recent_errors" ]; then
        error_count=$(echo "$recent_errors" | wc -l | tr -d ' \n\r')
        if [ "$error_count" -gt 0 ]; then
            # Show first few lines of recent errors for context
            sample_errors=$(echo "$recent_errors" | head -3 | tr '\n' '; ')
            show_health_status "warning" "$check_name" "Found $error_count recent errors: $sample_errors"
            increment_counter "warning"
            return 1
        fi
    fi

    show_health_status "healthy" "$check_name" "No recent errors found in system logs"
    increment_counter "healthy"
    return 0
}

# Function to test actual runtime functionality
check_runtime_functionality() {
    debug_func "check_runtime_functionality"

    log_debug "Testing actual runtime functionality"

    # Check for configuration issues first
    log_debug "Checking STARLINK variable configuration"
    if echo "${STARLINK_IP:-}" | grep -q ":"; then
        show_health_status "critical" "Starlink Config Format" "STARLINK_IP contains port (${STARLINK_IP:-}) - should be IP only"
        increment_counter "critical"
        log_debug "CRITICAL: STARLINK_IP contains port - this causes connection failures"
        return 1
    fi

    # Test if grpcurl can actually connect to Starlink
    if [ -n "${GRPCURL_CMD:-}" ] && [ -n "${STARLINK_IP:-}" ] && [ -n "${STARLINK_PORT:-}" ]; then
        log_debug "Testing actual grpcurl connection to $STARLINK_IP:$STARLINK_PORT"

        # Check if grpcurl command exists and is executable
        if [ ! -x "${GRPCURL_CMD:-}" ]; then
            show_health_status "critical" "GRPCURL Command" "grpcurl not found or not executable: ${GRPCURL_CMD:-}"
            increment_counter "critical"
            return 1
        fi

        # Try to get device info with a short timeout
        log_debug "Attempting grpcurl connection test..."
        if timeout 5 "$GRPCURL_CMD" -plaintext -d '{}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
            show_health_status "healthy" "Starlink Runtime API" "grpcurl successfully connected to Starlink device"
            increment_counter "healthy"
        else
            # This is the actual error that's happening!
            show_health_status "critical" "Starlink Runtime API" "grpcurl cannot connect to $STARLINK_IP:$STARLINK_PORT (check network/Starlink status)"
            increment_counter "critical"
            log_debug "grpcurl connection test: FAILED - this explains why monitor/logger scripts are failing"
        fi
    else
        show_health_status "warning" "Starlink Runtime API" "Missing GRPCURL_CMD ($GRPCURL_CMD), STARLINK_IP ($STARLINK_IP), or STARLINK_PORT ($STARLINK_PORT)"
        increment_counter "warning"
    fi

    # Test if we can execute the monitor script with real connection
    if [ -x "${MAIN_MONITOR:-/usr/local/starlink-monitor/scripts/starlink_monitor_unified-rutos.sh}" ]; then
        log_debug "Testing monitor script with actual runtime execution"

        # Run the monitor in test mode but with real connection (short timeout)
        log_debug "Running monitor script test with 10 second timeout..."
        monitor_output=$(timeout 10 "$MAIN_MONITOR" 2>&1 || echo "timeout_or_error")

        if echo "$monitor_output" | grep -q "\[ERROR\].*Failed to fetch"; then
            show_health_status "critical" "Monitor Runtime Status" "Monitor script failing with connection errors"
            increment_counter "critical"
            log_debug "Monitor runtime test: FAILED - connection errors detected"
        elif echo "$monitor_output" | grep -q "timeout_or_error"; then
            show_health_status "warning" "Monitor Runtime Status" "Monitor script timeout or execution error"
            increment_counter "warning"
            log_debug "Monitor runtime test: TIMEOUT"
        else
            show_health_status "healthy" "Monitor Runtime Status" "Monitor script executing successfully"
            increment_counter "healthy"
            log_debug "Monitor runtime test: PASSED"
        fi
    fi
}

# Function to show final health summary
show_health_summary() {
    echo ""
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}║${NC}                            ${BLUE}HEALTH CHECK SUMMARY${NC}                            ${PURPLE}║${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    total_checks=$((HEALTHY_COUNT + WARNING_COUNT + CRITICAL_COUNT + UNKNOWN_COUNT))

    printf "${GREEN}✅ HEALTHY:   %3d checks${NC}\n" "$HEALTHY_COUNT"
    printf "${YELLOW}⚠️  WARNING:   %3d checks${NC}\n" "$WARNING_COUNT"
    printf "${RED}❌ CRITICAL:  %3d checks${NC}\n" "$CRITICAL_COUNT"
    printf "${CYAN}❓ UNKNOWN:    %3d checks${NC}\n" "$UNKNOWN_COUNT"
    printf "${PURPLE}──────────────────────${NC}\n"
    printf "${BLUE}📊 TOTAL:     %3d checks${NC}\n" "$total_checks"

    echo ""

    # Calculate overall health percentage
    if [ "$total_checks" -gt 0 ]; then
        health_percentage=$(((HEALTHY_COUNT * 100) / total_checks))

        if [ "$CRITICAL_COUNT" -gt 0 ]; then
            printf "${RED}🚨 OVERALL STATUS: CRITICAL${NC}\n"
            printf "${RED}   System has critical issues that need immediate attention${NC}\n"
            exit_code=2
        elif [ "$WARNING_COUNT" -gt 0 ]; then
            printf "${YELLOW}⚠️  OVERALL STATUS: WARNING${NC}\n"
            printf "${YELLOW}   System is functional but has issues that should be addressed${NC}\n"
            exit_code=1
        else
            printf "${GREEN}🎉 OVERALL STATUS: HEALTHY${NC}\n"
            printf "${GREEN}   System is operating normally${NC}\n"
            exit_code=0
        fi

        printf "${BLUE}📈 HEALTH SCORE: %d%%${NC}\n" "$health_percentage"
    else
        printf "${RED}❌ OVERALL STATUS: NO CHECKS PERFORMED${NC}\n"
        exit_code=3
    fi

    echo ""
    printf "${CYAN}💡 Recommendations:${NC}\n"

    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        printf "${RED}   • Address critical issues immediately${NC}\n"
        printf "${RED}   • Check connectivity and configuration${NC}\n"
    fi

    if [ "$WARNING_COUNT" -gt 0 ]; then
        printf "${YELLOW}   • Review warning items when convenient${NC}\n"
        printf "${YELLOW}   • Consider enabling optional features${NC}\n"
    fi

    if [ "$UNKNOWN_COUNT" -gt 0 ]; then
        printf "${CYAN}   • Install missing testing tools${NC}\n"
        printf "${CYAN}   • Run individual tests for more details${NC}\n"
    fi

    printf "${BLUE}   • Run 'DEBUG=1 %s' for detailed troubleshooting${NC}\n" "$0"
    printf "${BLUE}   • Check individual component logs in %s${NC}\n" "$LOG_DIR"

    echo ""
    return $exit_code
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --version          Show script version"
    echo "  --quick            Run quick health check (skip tests)"
    echo "  --full             Run full health check (default)"
    echo "  --connectivity     Check connectivity only"
    echo "  --monitoring       Check monitoring system only"
    echo "  --config           Check configuration only"
    echo "  --resources        Check system resources only"
    echo "  --test-pushover    Test Pushover notifications only"
    echo ""
    echo "Environment variables:"
    echo "  DEBUG=1            Enable detailed debug output"
    echo "  TEST_MODE=1        Enable test mode with command tracing"
    echo ""
    echo "Description:"
    echo "  This script provides a comprehensive health check of the Starlink"
    echo "  monitoring system by orchestrating all other test scripts and"
    echo "  checking system components for proper operation."
    echo ""
    echo "Examples:"
    echo "  $0                 # Full health check"
    echo "  $0 --quick         # Quick health check"
    echo "  $0 --connectivity  # Check connectivity only"
    echo "  DEBUG=1 $0         # Full health check with debug output"
    echo "  TEST_MODE=1 $0     # Full health check with command tracing"
    echo ""
    echo "Debug modes:"
    echo "  DEBUG=1            - Detailed logging and error information"
    echo "  TEST_MODE=1        - Maximum debugging with command tracing (set -x)"
    echo ""
    echo "Exit codes:"
    echo "  0  - All healthy"
    echo "  1  - Warnings found"
    echo "  2  - Critical issues found"
    echo "  3  - No checks performed"
}

# Main function
main() {
    debug_func "main"
    log_debug "==================== HEALTH CHECK START ===================="
    log_debug "Starting main health check function"
    log_debug "Startup environment validation beginning..."

    log_info "Starting comprehensive health check v$SCRIPT_VERSION"

    # Validate environment
    log_debug "ENVIRONMENT CHECK: Validating RUTOS/OpenWrt environment"
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        log_debug "ENVIRONMENT CHECK: /etc/openwrt_release not found"
        exit 1
    fi
    log_debug "ENVIRONMENT CHECK: OpenWrt release file found"

    # Check if installation exists
    log_debug "INSTALLATION CHECK: Validating installation directory $INSTALL_DIR"
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "Starlink Monitor installation not found at $INSTALL_DIR"
        log_error "Please run the installation script first"
        log_debug "INSTALLATION CHECK: Installation directory not found"
        exit 1
    fi
    log_debug "INSTALLATION CHECK: Installation directory found"

    # Parse command line arguments
    run_mode="${1:-full}"
    log_debug "RUN MODE: $run_mode"
    debug_var "run_mode" "$run_mode"

    echo ""
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}║${NC}                    ${BLUE}STARLINK MONITOR HEALTH CHECK${NC}                     ${PURPLE}║${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}║${NC}                           ${CYAN}Version ${SCRIPT_VERSION}${NC}                            ${PURPLE}║${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}%-15s | %-25s | %s${NC}\n" "STATUS" "COMPONENT" "DETAILS"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}%-15s | %-25s | %s${NC}\n" "===============" "=========================" "================================"

    # Initialize counters
    log_debug "COUNTER INIT: Resetting all health counters"
    HEALTHY_COUNT=0
    WARNING_COUNT=0
    CRITICAL_COUNT=0
    UNKNOWN_COUNT=0

    # Run health checks based on mode
    case "$run_mode" in
        "--quick")
            log_debug "QUICK MODE: Running essential checks only"
            check_system_resources
            check_configuration_health
            check_monitoring_health
            check_logger_sample_tracking
            check_firmware_persistence
            ;;
        "--connectivity")
            log_debug "CONNECTIVITY MODE: Running connectivity checks only"
            check_network_connectivity
            check_starlink_connectivity
            ;;
        "--monitoring")
            log_debug "MONITORING MODE: Running monitoring system checks only"
            check_monitoring_health
            test_script_execution
            check_runtime_functionality
            check_system_log_errors "System Log Errors"
            ;;
        "--config")
            log_debug "CONFIG MODE: Running configuration checks only"
            check_configuration_health
            ;;
        "--resources")
            log_debug "MONITORING MODE: Running system monitoring checks only"
            check_system_resources
            check_firmware_persistence
            ;;
        "--test-pushover")
            log_debug "PUSHOVER TEST MODE: Running dedicated Pushover notification test"
            echo ""
            log_step "Testing Pushover notification system"

            # Load configuration if available
            if [ -f "$CONFIG_FILE" ]; then
                # shellcheck source=/dev/null
                . "$CONFIG_FILE" 2>/dev/null || {
                    log_error "Failed to load configuration file: $CONFIG_FILE"
                    exit 1
                }
            else
                log_warning "Configuration file not found: $CONFIG_FILE"
                log_info "Using environment variables or defaults"
            fi

            # Check configuration
            if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
                log_error "Pushover credentials not configured"
                printf "PUSHOVER_TOKEN: %s\n" "${PUSHOVER_TOKEN:-NOT_SET}"
                printf "PUSHOVER_USER: %s\n" "${PUSHOVER_USER:-NOT_SET}"
                exit 1
            fi

            # Check for placeholders
            if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
                log_error "Pushover credentials still have placeholder values"
                printf "Please update your configuration with real Pushover credentials\n"
                exit 1
            fi

            # Test API
            if command -v curl >/dev/null 2>&1; then
                log_step "Sending test notification via Pushover API"
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                test_response=$(curl -s \
                    -F "token=$PUSHOVER_TOKEN" \
                    -F "user=$PUSHOVER_USER" \
                    -F "message=Test notification from RUTOS health check at $timestamp. Your Pushover notifications are working correctly!" \
                    -F "title=🧪 RUTOS Health Check Test" \
                    -F "priority=0" \
                    https://api.pushover.net/1/messages.json 2>&1)

                if echo "$test_response" | grep -q '"status":1'; then
                    show_health_status "healthy" "Pushover Test" "Test notification sent successfully"
                    log_info "✅ SUCCESS! Check your Pushover app for the test message"
                    printf "\n${GREEN}Test completed successfully!${NC}\n"
                    printf "If you received the notification, your Pushover system is working.\n"
                    printf "If no notification arrived, check your Pushover app settings.\n"
                    exit 0
                else
                    show_health_status "critical" "Pushover Test" "API call failed"
                    log_error "❌ API test failed"
                    printf "Response: %s\n" "$test_response"
                    exit 1
                fi
            else
                log_error "curl not available - cannot test Pushover API"
                exit 1
            fi
            ;;
        "--full" | *)
            log_debug "FULL MODE: Running comprehensive health checks"
            check_system_resources
            check_network_connectivity
            check_starlink_connectivity
            check_configuration_health
            check_monitoring_health
            test_script_execution
            check_runtime_functionality
            check_system_log_errors "System Log Errors"
            check_logger_sample_tracking
            check_firmware_persistence
            run_integrated_tests
            ;;
    esac

    log_debug "HEALTH CHECKS COMPLETED: All requested checks have been run"
    log_debug "FINAL COUNTERS: H:$HEALTHY_COUNT W:$WARNING_COUNT C:$CRITICAL_COUNT U:$UNKNOWN_COUNT"

    # Show final summary
    log_debug "SUMMARY: Displaying health summary and determining exit code"
    show_health_summary
    exit_code=$?

    log_debug "EXIT CODE: Determined exit code: $exit_code"
    log_debug "==================== HEALTH CHECK COMPLETE ===================="

    # Clean up any temporary files
    if [ -f /tmp/health_check_error.log ]; then
        log_debug "CLEANUP: Removing temporary error log"
        rm -f /tmp/health_check_error.log
    fi

    return $exit_code
}

# Handle command line arguments
case "${1:-}" in
    --help | -h)
        show_usage
        exit 0
        ;;
    --version)
        echo "$SCRIPT_VERSION"
        exit 0
        ;;
    *)
        # Run main function
        main "$@"
        ;;
esac
