#!/bin/sh
# Script: health-check.sh
# Version: 1.0.2
# Description: Comprehensive system health check that orchestrates all other test scripts

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.2"

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

# Health check status functions
show_health_status() {
    status="$1"
    component="$2"
    message="$3"

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
}

# Configuration paths
INSTALL_DIR="/root/starlink-monitor"
CONFIG_FILE="$INSTALL_DIR/config/config.sh"
SCRIPT_DIR="$INSTALL_DIR/scripts"
LOG_DIR="$INSTALL_DIR/logs"
STATE_DIR="$INSTALL_DIR/state"

# Global health counters
HEALTHY_COUNT=0
WARNING_COUNT=0
CRITICAL_COUNT=0
UNKNOWN_COUNT=0

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Function to increment health counters
increment_counter() {
    status="$1"
    case "$status" in
        "healthy") HEALTHY_COUNT=$((HEALTHY_COUNT + 1)) ;;
        "warning") WARNING_COUNT=$((WARNING_COUNT + 1)) ;;
        "critical") CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
        "unknown") UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
    esac
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

    # Test basic internet connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        show_health_status "healthy" "Internet Connectivity" "Can reach 8.8.8.8"
        increment_counter "healthy"
    else
        show_health_status "critical" "Internet Connectivity" "Cannot reach 8.8.8.8"
        increment_counter "critical"
    fi

    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        show_health_status "healthy" "DNS Resolution" "Can resolve google.com"
        increment_counter "healthy"
    else
        show_health_status "critical" "DNS Resolution" "Cannot resolve google.com"
        increment_counter "critical"
    fi
}

# Function to check Starlink connectivity
check_starlink_connectivity() {
    log_step "Checking Starlink connectivity"

    # Load configuration to get Starlink IP
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/placeholder-utils.sh" 2>/dev/null || true

        if [ -n "${STARLINK_IP:-}" ] && [ "$STARLINK_IP" != "YOUR_STARLINK_IP" ]; then
            if ping -c 1 -W 5 "$STARLINK_IP" >/dev/null 2>&1; then
                show_health_status "healthy" "Starlink Device" "Can reach $STARLINK_IP"
                increment_counter "healthy"
            else
                show_health_status "critical" "Starlink Device" "Cannot reach $STARLINK_IP"
                increment_counter "critical"
            fi

            # Test grpcurl if available
            if command -v grpcurl >/dev/null 2>&1; then
                if grpcurl -plaintext -d '{}' "$STARLINK_IP:9200" SpaceX.API.Device.Device/GetStatus >/dev/null 2>&1; then
                    show_health_status "healthy" "Starlink gRPC API" "API responding on $STARLINK_IP:9200"
                    increment_counter "healthy"
                else
                    show_health_status "warning" "Starlink gRPC API" "API not responding on $STARLINK_IP:9200"
                    increment_counter "warning"
                fi
            else
                show_health_status "unknown" "Starlink gRPC API" "grpcurl not available for testing"
                increment_counter "unknown"
            fi
        else
            show_health_status "warning" "Starlink Device" "Starlink IP not configured"
            increment_counter "warning"
        fi
    else
        show_health_status "critical" "Starlink Device" "Configuration file not found"
        increment_counter "critical"
    fi
}

# Function to check configuration health
check_configuration_health() {
    log_step "Checking configuration health"

    # Run configuration validation
    if [ -x "$SCRIPT_DIR/validate-config-rutos.sh" ]; then
        if "$SCRIPT_DIR/validate-config-rutos.sh" --quiet >/dev/null 2>&1; then
            show_health_status "healthy" "Configuration" "Configuration validation passed"
            increment_counter "healthy"
        else
            show_health_status "warning" "Configuration" "Configuration validation failed"
            increment_counter "warning"
        fi
    else
        show_health_status "unknown" "Configuration" "validate-config-rutos.sh not found or not executable"
        increment_counter "unknown"
    fi

    # Check for placeholder values
    if [ -f "$SCRIPT_DIR/placeholder-utils.sh" ]; then
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/placeholder-utils.sh"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE" 2>/dev/null || true

        if is_pushover_configured; then
            show_health_status "healthy" "Pushover Config" "Pushover properly configured"
            increment_counter "healthy"
        else
            show_health_status "warning" "Pushover Config" "Pushover using placeholder values"
            increment_counter "warning"
        fi
    fi
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

    # Check state files
    if [ -f "$STATE_DIR/starlink_monitor.state" ]; then
        state_content=$(cat "$STATE_DIR/starlink_monitor.state" 2>/dev/null || echo "unknown")
        show_health_status "healthy" "Monitor State" "State: $state_content"
        increment_counter "healthy"
    else
        show_health_status "warning" "Monitor State" "State file not found (monitoring may not have run)"
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

    # Check system uptime and load
    check_system_uptime

    # Check disk space
    check_disk_space "/" 80 "Root Filesystem"
    check_disk_space "$INSTALL_DIR" 80 "Install Directory"

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
    if [ -x "$SCRIPT_DIR/system-status.sh" ]; then
        if "$SCRIPT_DIR/system-status.sh" --quiet >/dev/null 2>&1; then
            show_health_status "healthy" "System Status" "System status check passed"
            increment_counter "healthy"
        else
            show_health_status "warning" "System Status" "System status check failed"
            increment_counter "warning"
        fi
    else
        show_health_status "unknown" "System Status" "system-status.sh not found"
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

    printf "%s✅ HEALTHY:   %3d checks%s\n" "$GREEN" "$HEALTHY_COUNT" "$NC"
    printf "%s⚠️  WARNING:   %3d checks%s\n" "$YELLOW" "$WARNING_COUNT" "$NC"
    printf "%s❌ CRITICAL:  %3d checks%s\n" "$RED" "$CRITICAL_COUNT" "$NC"
    printf "%s❓ UNKNOWN:    %3d checks%s\n" "$CYAN" "$UNKNOWN_COUNT" "$NC"
    printf "%s──────────────────────%s\n" "$PURPLE" "$NC"
    printf "%s📊 TOTAL:     %3d checks%s\n" "$BLUE" "$total_checks" "$NC"

    echo ""

    # Calculate overall health percentage
    if [ "$total_checks" -gt 0 ]; then
        health_percentage=$(((HEALTHY_COUNT * 100) / total_checks))

        if [ "$CRITICAL_COUNT" -gt 0 ]; then
            printf "%s🚨 OVERALL STATUS: CRITICAL%s\n" "$RED" "$NC"
            printf "%s   System has critical issues that need immediate attention%s\n" "$RED" "$NC"
            exit_code=2
        elif [ "$WARNING_COUNT" -gt 0 ]; then
            printf "%s⚠️  OVERALL STATUS: WARNING%s\n" "$YELLOW" "$NC"
            printf "%s   System is functional but has issues that should be addressed%s\n" "$YELLOW" "$NC"
            exit_code=1
        else
            printf "%s🎉 OVERALL STATUS: HEALTHY%s\n" "$GREEN" "$NC"
            printf "%s   System is operating normally%s\n" "$GREEN" "$NC"
            exit_code=0
        fi

        printf "%s📈 HEALTH SCORE: %d%%%s\n" "$BLUE" "$health_percentage" "$NC"
    else
        printf "%s❌ OVERALL STATUS: NO CHECKS PERFORMED%s\n" "$RED" "$NC"
        exit_code=3
    fi

    echo ""
    printf "%s💡 Recommendations:%s\n" "$CYAN" "$NC"

    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        printf "%s   • Address critical issues immediately%s\n" "$RED" "$NC"
        printf "%s   • Check connectivity and configuration%s\n" "$RED" "$NC"
    fi

    if [ "$WARNING_COUNT" -gt 0 ]; then
        printf "%s   • Review warning items when convenient%s\n" "$YELLOW" "$NC"
        printf "%s   • Consider enabling optional features%s\n" "$YELLOW" "$NC"
    fi

    if [ "$UNKNOWN_COUNT" -gt 0 ]; then
        printf "%s   • Install missing testing tools%s\n" "$CYAN" "$NC"
        printf "%s   • Run individual tests for more details%s\n" "$CYAN" "$NC"
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
    echo ""
    echo "Exit codes:"
    echo "  0  - All healthy"
    echo "  1  - Warnings found"
    echo "  2  - Critical issues found"
    echo "  3  - No checks performed"
}

# Main function
main() {
    log_info "Starting comprehensive health check v$SCRIPT_VERSION"

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Check if installation exists
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "Starlink Monitor installation not found at $INSTALL_DIR"
        log_error "Please run the installation script first"
        exit 1
    fi

    # Parse command line arguments
    run_mode="${1:-full}"

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

    # Run health checks based on mode
    case "$run_mode" in
        "--quick")
            check_system_resources
            check_configuration_health
            check_monitoring_health
            check_firmware_persistence
            ;;
        "--connectivity")
            check_network_connectivity
            check_starlink_connectivity
            ;;
        "--monitoring")
            check_monitoring_health
            ;;
        "--config")
            check_configuration_health
            ;;
        "--resources")
            check_system_resources
            check_firmware_persistence
            ;;
        "--full" | *)
            check_system_resources
            check_network_connectivity
            check_starlink_connectivity
            check_configuration_health
            check_monitoring_health
            check_firmware_persistence
            run_integrated_tests
            ;;
    esac

    # Show final summary
    show_health_summary
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
