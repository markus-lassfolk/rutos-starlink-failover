#!/bin/sh
# Script: health-check.sh
# Version: 1.0.2
# Description: Comprehensive system health check that orchestrates all other test scripts

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.0"

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
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

# Enhanced error handling with detailed logging
safe_exec() {
    cmd="$1"
    description="$2"
    
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
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
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
    DEBUG=1  # Force debug mode in test mode
    set -x   # Enable command tracing
    log_debug "TEST MODE: All commands will be traced"
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
                    *PUSHOVER_TOKEN*|*PUSHOVER_USER*)
                        log_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        log_debug "  $line"
                        ;;
                esac
            done < "$CONFIG_FILE" 2>/dev/null || log_debug "  (Cannot read config file contents)"
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
    monitor_entries=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_check_entries=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")

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
            monitor_schedule=$(grep "starlink_monitor-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
            show_health_status "healthy" "Monitor Schedule" "Monitor: $monitor_schedule ($monitor_entries entry)"
            increment_counter "healthy"
        else
            show_health_status "warning" "Monitor Schedule" "Multiple monitor entries ($monitor_entries) - may cause conflicts"
            increment_counter "warning"
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "Monitor entries found:"
                grep "starlink_monitor-rutos.sh" "$CRON_FILE" | while IFS= read -r line; do
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
            logger_schedule=$(grep "starlink_logger-rutos.sh" "$CRON_FILE" | head -1 | awk '{print $1" "$2" "$3" "$4" "$5}')
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
    duplicate_lines=$(grep -E "(starlink_monitor-rutos\.sh|starlink_logger-rutos\.sh|check_starlink_api)" "$CRON_FILE" | sort | uniq -d | wc -l)
    if [ "$duplicate_lines" -gt 0 ]; then
        show_health_status "warning" "Duplicate Entries" "Found $duplicate_lines duplicate cron lines"
        increment_counter "warning"
    else
        show_health_status "healthy" "Duplicate Check" "No duplicate entries detected"
        increment_counter "healthy"
    fi

    # Check for commented out entries (from old install scripts)
    commented_entries=$(grep -c "# COMMENTED BY.*starlink" "$CRON_FILE" 2>/dev/null || echo "0")
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
                done < /etc/resolv.conf
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

        if [ -n "${STARLINK_IP:-}" ] && [ "$STARLINK_IP" != "YOUR_STARLINK_IP" ]; then
            # Extract IP without port for ping test
            STARLINK_HOST=$(echo "$STARLINK_IP" | cut -d: -f1)
            log_debug "STARLINK HOST: Extracted $STARLINK_HOST from $STARLINK_IP"
            
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
                log_debug "GRPC COMMAND: $GRPCURL_CMD -plaintext -max-time 10 -d '{\"get_device_info\":{}}' $STARLINK_IP SpaceX.API.Device.Device/Handle"
                
                # Use the same endpoint as the API check script for consistency
                if [ "${DEBUG:-0}" = "1" ]; then
                    # In debug mode, capture and log the response
                    grpc_output=$("$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>&1)
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
                    if "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
                        show_health_status "healthy" "Starlink gRPC API" "API responding on $STARLINK_IP"
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

# Function to check configuration health
check_configuration_health() {
    log_step "Checking configuration health"
    debug_func "check_configuration_health"

    # Run configuration validation with timeout to prevent hanging
    validation_script="$SCRIPT_DIR/validate-config-rutos.sh"
    log_debug "CONFIG VALIDATION: Checking for validation script at $validation_script"
    
    if [ -x "$validation_script" ]; then
        log_debug "CONFIG VALIDATION: Script found and executable"
        
        # Test if the script can be executed at all
        log_debug "CONFIG VALIDATION: Testing script execution capability..."
        if ! "$validation_script" --help >/dev/null 2>&1; then
            log_debug "CONFIG VALIDATION: WARNING - Script --help test failed, may have execution issues"
        else
            log_debug "CONFIG VALIDATION: Script responds to --help, appears functional"
        fi
        
        # Add a progress indicator
        log_debug "CONFIG VALIDATION: Starting validation process..."
        
        # Use timeout command if available, otherwise rely on the script's own timeout
        if command -v timeout >/dev/null 2>&1; then
            log_debug "CONFIG VALIDATION: Using timeout command (30 seconds)"
            log_debug "CONFIG VALIDATION: Executing timeout 30 $validation_script --quiet"
            
            # Test if timeout command works with a simple command first
            log_debug "CONFIG VALIDATION: Testing timeout command functionality..."
            if timeout 5 echo "timeout test" >/dev/null 2>&1; then
                log_debug "CONFIG VALIDATION: Timeout command test successful"
            else
                log_debug "CONFIG VALIDATION: Timeout command test failed, falling back to direct execution"
                # Skip timeout and go directly to fallback
                validation_output=$("$validation_script" --quiet 2>&1 || echo "Script execution failed")
                validation_exit_code=$?
                validation_end_time=$(date '+%s')
                validation_duration=$((validation_end_time - validation_start_time))
                log_debug "CONFIG VALIDATION: Direct execution completed in ${validation_duration} seconds"
                log_debug "CONFIG VALIDATION: Exit code: $validation_exit_code"
                log_debug "CONFIG VALIDATION: Output length: ${#validation_output} characters"
                
                # Skip the rest of the timeout logic
                if [ $validation_exit_code -eq 0 ]; then
                    show_health_status "healthy" "Configuration" "Configuration validation passed"
                    increment_counter "healthy"
                    log_debug "CONFIG VALIDATION: SUCCESS"
                else
                    error_summary=$(echo "$validation_output" | head -n1 | cut -c1-60)
                    show_health_status "warning" "Configuration" "Validation failed: $error_summary"
                    increment_counter "warning"
                    log_debug "CONFIG VALIDATION: FAILED - $error_summary"
                fi
                
                log_debug "CONFIG VALIDATION: Proceeding to placeholder check"
                # Continue to placeholder check section...
                placeholder_script="$SCRIPT_DIR/placeholder-utils.sh"
                log_debug "PLACEHOLDER CHECK: Checking for placeholder utils at $placeholder_script"
                
                if [ -f "$placeholder_script" ]; then
                    log_debug "PLACEHOLDER CHECK: Utils script found, loading..."
                    # shellcheck disable=SC1091
                    . "$placeholder_script"
                    # shellcheck disable=SC1090
                    . "$CONFIG_FILE" 2>/dev/null || log_debug "Could not source config file for placeholder check"

                    log_debug "PUSHOVER CHECK: Testing if Pushover is configured properly"
                    if is_pushover_configured; then
                        show_health_status "healthy" "Pushover Config" "Pushover properly configured"
                        increment_counter "healthy"
                        log_debug "PUSHOVER CHECK: SUCCESS - properly configured"
                    else
                        show_health_status "warning" "Pushover Config" "Pushover using placeholder values"
                        increment_counter "warning"
                        log_debug "PUSHOVER CHECK: WARNING - using placeholder values"
                    fi
                else
                    log_debug "PLACEHOLDER CHECK: Utils script not found, skipping placeholder validation"
                fi
                
                log_debug "Configuration health checks completed"
                return  # Exit the function here
            fi
            
            # Execute with detailed debugging - avoid command substitution in busybox
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "CONFIG VALIDATION: Running in debug mode, will capture full output"
                validation_start_time=$(date '+%s')
                
                # Use a completely different approach - run script and capture to file
                temp_output="/tmp/health_check_validation_direct.out"
                temp_error="/tmp/health_check_validation_direct.err"
                
                log_debug "CONFIG VALIDATION: Using direct file capture approach"
                log_debug "CONFIG VALIDATION: Output file: $temp_output"
                log_debug "CONFIG VALIDATION: Error file: $temp_error"
                
                # Clean up any existing temp files
                rm -f "$temp_output" "$temp_error"
                
                # Execute the validation script directly with file redirection
                log_debug "CONFIG VALIDATION: Executing: timeout 30 $validation_script --quiet >$temp_output 2>$temp_error"
                timeout 30 "$validation_script" --quiet >"$temp_output" 2>"$temp_error"
                validation_exit_code=$?
                
                log_debug "CONFIG VALIDATION: Command completed with exit code: $validation_exit_code"
                
                # Read output from files
                validation_output=""
                if [ -f "$temp_output" ]; then
                    validation_output=$(cat "$temp_output" 2>/dev/null || echo "")
                    output_size=$(wc -c < "$temp_output" 2>/dev/null || echo "0")
                    log_debug "CONFIG VALIDATION: Read ${output_size} bytes from stdout"
                fi
                
                if [ -f "$temp_error" ] && [ -s "$temp_error" ]; then
                    error_content=$(cat "$temp_error" 2>/dev/null || echo "")
                    error_size=$(wc -c < "$temp_error" 2>/dev/null || echo "0") 
                    log_debug "CONFIG VALIDATION: Read ${error_size} bytes from stderr"
                    validation_output="${validation_output}${error_content}"
                fi
                
                # Clean up temp files
                rm -f "$temp_output" "$temp_error"
                
                validation_end_time=$(date '+%s')
                validation_duration=$((validation_end_time - validation_start_time))
                log_debug "CONFIG VALIDATION: Completed in ${validation_duration} seconds"
            else
                log_debug "CONFIG VALIDATION: Running in normal mode with simple execution"
                # Even in normal mode, avoid command substitution with timeout
                temp_output="/tmp/health_check_validation_simple.out"
                timeout 30 "$validation_script" --quiet >"$temp_output" 2>&1
                validation_exit_code=$?
                validation_output=$(cat "$temp_output" 2>/dev/null || echo "")
                rm -f "$temp_output"
            fi
        else
            log_debug "CONFIG VALIDATION: No timeout command available, using manual timeout approach"
            log_debug "CONFIG VALIDATION: Executing $validation_script --quiet with background monitoring"
            
            # Create temporary files for output
            temp_output="/tmp/health_check_validation_bg.out"
            temp_error="/tmp/health_check_validation_bg.err"
            temp_pid="/tmp/health_check_validation_bg.pid"
            
            # Clean up any existing temp files
            rm -f "$temp_output" "$temp_error" "$temp_pid"
            
            if [ "${DEBUG:-0}" = "1" ]; then
                validation_start_time=$(date '+%s')
                log_debug "CONFIG VALIDATION: Starting background process with manual timeout"
                
                # Start validation script in background
                ("$validation_script" --quiet >"$temp_output" 2>"$temp_error"; echo $? >"/tmp/health_check_validation_exit.code") &
                bg_pid=$!
                echo $bg_pid > "$temp_pid"
                log_debug "CONFIG VALIDATION: Background process started with PID $bg_pid"
                
                # Monitor the process with timeout
                timeout_seconds=30
                elapsed=0
                while [ $elapsed -lt $timeout_seconds ]; do
                    if ! kill -0 "$bg_pid" 2>/dev/null; then
                        log_debug "CONFIG VALIDATION: Background process completed after ${elapsed} seconds"
                        break
                    fi
                    sleep 1
                    elapsed=$((elapsed + 1))
                    if [ $((elapsed % 10)) -eq 0 ]; then
                        log_debug "CONFIG VALIDATION: Still running... ${elapsed}s elapsed"
                    fi
                done
                
                # Check if process is still running (timed out)
                if kill -0 "$bg_pid" 2>/dev/null; then
                    log_debug "CONFIG VALIDATION: Process timed out, terminating..."
                    kill "$bg_pid" 2>/dev/null || true
                    sleep 1
                    kill -9 "$bg_pid" 2>/dev/null || true
                    validation_exit_code=124  # timeout exit code
                    validation_output="Validation script timed out after ${timeout_seconds} seconds"
                else
                    # Process completed normally
                    if [ -f "/tmp/health_check_validation_exit.code" ]; then
                        validation_exit_code=$(cat "/tmp/health_check_validation_exit.code" 2>/dev/null || echo "1")
                        rm -f "/tmp/health_check_validation_exit.code"
                    else
                        validation_exit_code=1
                    fi
                    
                    validation_output=""
                    if [ -f "$temp_output" ]; then
                        validation_output=$(cat "$temp_output" 2>/dev/null)
                    fi
                    if [ -f "$temp_error" ] && [ -s "$temp_error" ]; then
                        error_content=$(cat "$temp_error" 2>/dev/null)
                        validation_output="${validation_output}${error_content}"
                    fi
                fi
                
                validation_end_time=$(date '+%s')
                validation_duration=$((validation_end_time - validation_start_time))
                log_debug "CONFIG VALIDATION: Manual timeout process completed in ${validation_duration} seconds"
                
                # Clean up temp files
                rm -f "$temp_output" "$temp_error" "$temp_pid"
                
            else
                # Fallback to simple execution without timeout in normal mode
                validation_output=$("$validation_script" --quiet 2>&1)
                validation_exit_code=$?
            fi
        fi

        log_debug "CONFIG VALIDATION: Exit code: $validation_exit_code"
        log_debug "CONFIG VALIDATION: Output length: ${#validation_output} characters"
        
        if [ $validation_exit_code -eq 0 ]; then
            show_health_status "healthy" "Configuration" "Configuration validation passed"
            increment_counter "healthy"
            log_debug "CONFIG VALIDATION: SUCCESS"
        elif [ $validation_exit_code -eq 124 ]; then
            show_health_status "warning" "Configuration" "Validation timed out (>30s)"
            increment_counter "warning"
            log_debug "CONFIG VALIDATION: TIMEOUT - validation took longer than 30 seconds"
        else
            # Extract first line of error for concise display
            error_summary=$(echo "$validation_output" | head -n1 | cut -c1-60)
            show_health_status "warning" "Configuration" "Validation failed: $error_summary"
            increment_counter "warning"
            log_debug "CONFIG VALIDATION: FAILED - $error_summary"

            # Log full details for debugging
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "CONFIG VALIDATION: Full output (first 1000 chars):"
                log_debug "$(echo "$validation_output" | cut -c1-1000)$([ ${#validation_output} -gt 1000 ] && echo '...')"
            fi
        fi
    else
        show_health_status "unknown" "Configuration" "validate-config-rutos.sh not found or not executable"
        increment_counter "unknown"
        log_debug "CONFIG VALIDATION: Script not found or not executable at $validation_script"
        
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "VALIDATION SCRIPT DEBUG:"
            if [ -f "$validation_script" ]; then
                log_debug "  File exists but not executable"
                log_debug "  Permissions: $(ls -la "$validation_script")"
            else
                log_debug "  File does not exist"
                log_debug "  Directory contents: $(ls -la "$SCRIPT_DIR" | grep validate || echo 'No validate scripts found')"
            fi
        fi
    fi

    log_debug "CONFIG VALIDATION: Proceeding to placeholder check"

    # Check for placeholder values
    placeholder_script="$SCRIPT_DIR/placeholder-utils.sh"
    log_debug "PLACEHOLDER CHECK: Checking for placeholder utils at $placeholder_script"
    
    if [ -f "$placeholder_script" ]; then
        log_debug "PLACEHOLDER CHECK: Utils script found, loading..."
        # shellcheck disable=SC1091
        . "$placeholder_script"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE" 2>/dev/null || log_debug "Could not source config file for placeholder check"

        log_debug "PUSHOVER CHECK: Testing if Pushover is configured properly"
        if is_pushover_configured; then
            show_health_status "healthy" "Pushover Config" "Pushover properly configured"
            increment_counter "healthy"
            log_debug "PUSHOVER CHECK: SUCCESS - properly configured"
        else
            show_health_status "warning" "Pushover Config" "Pushover using placeholder values"
            increment_counter "warning"
            log_debug "PUSHOVER CHECK: WARNING - using placeholder values"
            
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "PUSHOVER DEBUG: Token check: $([ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ] && echo "using placeholder" || echo "appears configured")"
                log_debug "PUSHOVER DEBUG: User check: $([ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ] && echo "using placeholder" || echo "appears configured")"
            fi
        fi
    else
        log_debug "PLACEHOLDER CHECK: Utils script not found, skipping placeholder validation"
    fi
    
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

    # Check if persistent config backup exists
    if [ -d "/etc/starlink-config" ]; then
        if [ -f "/etc/starlink-config/config.sh" ]; then
            show_health_status "healthy" "Config Backup" "Persistent configuration backup exists"
            increment_counter "healthy"
        else
            show_health_status "warning" "Config Backup" "Backup directory exists but no config.sh"
            increment_counter "warning"
        fi
    else
        show_health_status "critical" "Config Backup" "No persistent config backup - settings will be lost"
        increment_counter "critical"
    fi

    # Check restoration log if available
    if [ -f "/var/log/starlink-restore.log" ]; then
        # Check if log is recent (within last 30 days, indicating recent restoration activity)
        if [ -n "$(find "/var/log/starlink-restore.log" -mtime -30 2>/dev/null)" ]; then
            log_lines=$(wc -l <"/var/log/starlink-restore.log" 2>/dev/null || echo "0")
            show_health_status "healthy" "Restore Activity" "Recent activity logged ($log_lines lines)"
            increment_counter "healthy"
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
    if [ -f "$INSTALL_DIR/scripts/starlink_monitor-rutos.sh" ]; then
        show_health_status "healthy" "Monitor Script" "Script exists and is readable"
        increment_counter "healthy"
    else
        show_health_status "critical" "Monitor Script" "starlink_monitor-rutos.sh not found"
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

# Function to check system resources
check_system_resources() {
    log_step "Checking system resources"
    log_debug "Starting system resource checks..."

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
        if "$SCRIPT_DIR/test-pushover-rutos.sh" --quiet >/dev/null 2>&1; then
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
        if "$SCRIPT_DIR/test-monitoring-rutos.sh" --quiet >/dev/null 2>&1; then
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
        if "$SCRIPT_DIR/system-status-rutos.sh" --quiet >/dev/null 2>&1; then
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
            ;;
        "--config")
            log_debug "CONFIG MODE: Running configuration checks only"
            check_configuration_health
            ;;
        "--resources")
            log_debug "RESOURCES MODE: Running system resource checks only"
            check_system_resources
            check_firmware_persistence
            ;;
        "--full" | *)
            log_debug "FULL MODE: Running comprehensive health checks"
            check_system_resources
            check_network_connectivity
            check_starlink_connectivity
            check_configuration_health
            check_monitoring_health
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
