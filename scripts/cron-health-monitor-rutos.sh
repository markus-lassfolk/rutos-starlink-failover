#!/bin/sh
# ==============================================================================
# RUTOS Cron Health Monitor - Monitors Cron System Health
#
# Version: 2.7.1
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script monitors the overall health of the cron system, detects missing
# executions, hung processes, and system-level cron issues.
#
# Usage:
#   # Run as a cron job every 15 minutes:
#   */15 * * * * /root/starlink-monitor/scripts/cron-health-monitor-rutos.sh
#
# Features:
# - Detects missing cron executions (scripts that should have run but didn't)
# - Monitors for hung/zombie cron processes
# - Checks cron daemon health
# - Validates crontab syntax
# - Sends alerts for system-level cron issues
# - Integrates with existing webhook/Pushover notifications
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"

# CRITICAL: Load RUTOS library system (REQUIRED)
if ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # Fallback if library not available
    printf "[ERROR] RUTOS library not found - using minimal fallback\n" >&2
    log_error() { printf "[ERROR] %s\n" "$1" >&2; }
    log_info() { printf "[INFO] %s\n" "$1"; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$1" >&2; }
    log_warning() { printf "[WARNING] %s\n" "$1" >&2; }
    safe_execute() { [ "${DRY_RUN:-0}" = "0" ] && eval "$1" || printf "[DRY_RUN] %s\n" "$1" >&2; }
fi

# Initialize script with library features if available
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "cron-health-monitor-rutos.sh" "$SCRIPT_VERSION"
fi

# --- Configuration ---
HEALTH_LOG_DIR="${HEALTH_LOG_DIR:-/var/log/cron-health}"
HEALTH_STATE_DIR="${HEALTH_STATE_DIR:-/tmp/cron-health}"
MONITOR_LOG_DIR="${MONITOR_LOG_DIR:-/var/log/cron-monitor}"
EXPECTED_SCRIPTS_CONFIG="${EXPECTED_SCRIPTS_CONFIG:-/etc/starlink-config/cron-expected.conf}"

# Load main configuration if available
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Webhook and notification configuration
WEBHOOK_URL="${WEBHOOK_URL:-${CRON_HEALTH_WEBHOOK_URL:-}}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
PUSHOVER_USER="${PUSHOVER_USER:-}"

# Health check thresholds
MAX_MISSED_EXECUTIONS="${MAX_MISSED_EXECUTIONS:-3}"
MAX_HUNG_PROCESS_TIME="${MAX_HUNG_PROCESS_TIME:-1800}"  # 30 minutes
CRON_LOG_FILE="${CRON_LOG_FILE:-/var/log/cron}"

# Create necessary directories
safe_execute "mkdir -p '$HEALTH_LOG_DIR' '$HEALTH_STATE_DIR'"

# --- Helper Functions ---

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

send_health_alert() {
    alert_type="$1"
    message="$2"
    severity="${3:-warning}"
    
    timestamp="$(get_timestamp)"
    hostname="$(hostname 2>/dev/null || echo 'unknown')"
    
    log_error "CRON HEALTH ALERT [$alert_type]: $message"
    
    # Log to health log
    {
        echo "[$timestamp] [$severity] [$alert_type] $message"
    } >> "$HEALTH_LOG_DIR/cron-health.log"
    
    # Send webhook notification if configured
    if [ -n "$WEBHOOK_URL" ]; then
        json_payload=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "alert_type": "$alert_type",
    "message": "$message",
    "severity": "$severity",
    "source": "rutos-cron-health-monitor"
}
EOF
        )
        
        if command -v curl >/dev/null 2>&1; then
            curl -X POST "$WEBHOOK_URL" \
                -H 'Content-Type: application/json' \
                -d "$json_payload" \
                --connect-timeout 10 \
                --max-time 10 \
                --silent --show-error || {
                log_warning "Failed to send health alert webhook"
            }
        fi
    fi
    
    # Send Pushover notification if configured
    if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USER" ]; then
        priority="$([ "$severity" = "critical" ] && echo "2" || echo "1")"
        title="🚨 Cron Health Alert: $alert_type"
        
        if command -v curl >/dev/null 2>&1; then
            curl -s -F "token=$PUSHOVER_TOKEN" \
                -F "user=$PUSHOVER_USER" \
                -F "title=$title" \
                -F "message=$message" \
                -F "priority=$priority" \
                https://api.pushover.net/1/messages.json >/dev/null || {
                log_warning "Failed to send Pushover health alert"
            }
        fi
    fi
}

check_cron_daemon() {
    log_debug "Checking cron daemon health"
    
    # Check if cron process is running
    if ! pgrep -f "crond\|cron" >/dev/null 2>&1; then
        send_health_alert "DAEMON_DOWN" "Cron daemon is not running" "critical"
        return 1
    fi
    
    # Check if cron is accepting new jobs (try to list crontab)
    if ! crontab -l >/dev/null 2>&1; then
        # This might be normal if no crontab exists, so check differently
        if ! echo "# test" | crontab - 2>/dev/null; then
            send_health_alert "DAEMON_UNRESPONSIVE" "Cron daemon is not accepting commands" "critical"
            return 1
        else
            # Remove test crontab if it was added
            crontab -r 2>/dev/null || true
        fi
    fi
    
    log_debug "Cron daemon health check passed"
    return 0
}

check_crontab_syntax() {
    log_debug "Checking crontab syntax"
    
    # Get current crontab
    temp_crontab="/tmp/crontab_check_$$"
    if crontab -l > "$temp_crontab" 2>/dev/null; then
        # Basic syntax validation
        line_num=0
        while IFS= read -r line || [ -n "$line" ]; do
            line_num=$((line_num + 1))
            
            # Skip empty lines and comments
            [ -z "$line" ] && continue
            [ "${line#\#}" != "$line" ] && continue
            
            # Check basic cron syntax (5 or 6 fields for time, then command)
            if ! echo "$line" | grep -qE '^[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+'; then
                send_health_alert "SYNTAX_ERROR" "Invalid crontab syntax at line $line_num: $line" "warning"
            fi
        done < "$temp_crontab"
        
        rm -f "$temp_crontab"
    else
        log_debug "No crontab found for current user"
    fi
    
    log_debug "Crontab syntax check completed"
}

check_hung_processes() {
    log_debug "Checking for hung cron processes"
    
    current_time="$(date +%s)"
    hung_found=0
    
    # Look for long-running processes that might be hung
    # This is approximate since we can't easily track individual cron job start times
    ps_output="$(ps aux 2>/dev/null | grep -v grep | grep -E "(starlink|cron)" || true)"
    
    if [ -n "$ps_output" ]; then
        while IFS= read -r process_line || [ -n "$process_line" ]; do
            # Extract elapsed time (this is system-dependent and approximate)
            elapsed_info="$(echo "$process_line" | awk '{print $10}')"
            
            # Simple check for obviously long-running processes
            # This is a basic implementation - more sophisticated tracking would require
            # keeping state between runs
            if echo "$elapsed_info" | grep -qE '^[0-9]+:[0-5][0-9]:[0-5][0-9]$'; then
                # Format is hours:minutes:seconds
                hours="$(echo "$elapsed_info" | cut -d: -f1)"
                if [ "$hours" -gt 1 ]; then
                    process_name="$(echo "$process_line" | awk '{print $11}')"
                    send_health_alert "HUNG_PROCESS" "Long-running process detected: $process_name (running for $elapsed_info)" "warning"
                    hung_found=1
                fi
            fi
        done <<EOF
$ps_output
EOF
    fi
    
    if [ "$hung_found" -eq 0 ]; then
        log_debug "No hung processes detected"
    fi
}

check_missing_executions() {
    log_debug "Checking for missing cron executions"
    
    if [ ! -f "$EXPECTED_SCRIPTS_CONFIG" ]; then
        log_debug "No expected scripts configuration found at $EXPECTED_SCRIPTS_CONFIG"
        return 0
    fi
    
    current_time="$(date +%s)"
    missing_found=0
    
    # Read expected scripts configuration
    while IFS='|' read -r script_name interval_minutes last_run_file || [ -n "$script_name" ]; do
        # Skip empty lines and comments
        [ -z "$script_name" ] && continue
        [ "${script_name#\#}" != "$script_name" ] && continue
        
        # Check if script should have run recently
        expected_interval=$((interval_minutes * 60))  # Convert to seconds
        
        if [ -f "$MONITOR_LOG_DIR/${script_name}.log" ]; then
            # Get last execution time from log
            last_execution="$(tail -1 "$MONITOR_LOG_DIR/${script_name}.log" 2>/dev/null | grep "Timestamp:" | awk '{print $2, $3}' || echo "")"
            
            if [ -n "$last_execution" ]; then
                last_execution_epoch="$(date -d "$last_execution" +%s 2>/dev/null || echo "0")"
                time_since_last=$((current_time - last_execution_epoch))
                
                # Allow 20% grace period for timing variations
                max_acceptable_delay=$((expected_interval + expected_interval / 5))
                
                if [ "$time_since_last" -gt "$max_acceptable_delay" ]; then
                    minutes_late=$((time_since_last / 60))
                    send_health_alert "MISSING_EXECUTION" "Script $script_name is $minutes_late minutes overdue (expected every $interval_minutes minutes)" "warning"
                    missing_found=1
                fi
            else
                send_health_alert "MISSING_EXECUTION" "No execution log found for expected script: $script_name" "warning"
                missing_found=1
            fi
        else
            send_health_alert "MISSING_EXECUTION" "No log file found for expected script: $script_name" "warning"
            missing_found=1
        fi
    done < "$EXPECTED_SCRIPTS_CONFIG"
    
    if [ "$missing_found" -eq 0 ]; then
        log_debug "All expected scripts are running on schedule"
    fi
}

check_disk_space() {
    log_debug "Checking disk space for log directories"
    
    # Check available space in log directories
    for dir in "$HEALTH_LOG_DIR" "$MONITOR_LOG_DIR" "/var/log" "/tmp"; do
        if [ -d "$dir" ]; then
            available_kb="$(df "$dir" | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")"
            available_mb=$((available_kb / 1024))
            
            if [ "$available_mb" -lt 50 ]; then  # Less than 50MB
                send_health_alert "LOW_DISK_SPACE" "Low disk space in $dir: only ${available_mb}MB available" "warning"
            fi
        fi
    done
}

generate_health_report() {
    timestamp="$(get_timestamp)"
    report_file="$HEALTH_LOG_DIR/health-report-$(date +%Y%m%d).log"
    
    {
        echo "==================== CRON HEALTH REPORT ===================="
        echo "Generated: $timestamp"
        echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
        echo ""
        
        echo "--- CRON DAEMON STATUS ---"
        if pgrep -f "crond\|cron" >/dev/null 2>&1; then
            echo "✓ Cron daemon is running"
            pgrep -f "crond\|cron" | while read -r pid; do
                echo "  PID: $pid"
            done
        else
            echo "✗ Cron daemon is NOT running"
        fi
        echo ""
        
        echo "--- CURRENT CRONTAB ---"
        crontab -l 2>/dev/null || echo "No crontab found"
        echo ""
        
        echo "--- MONITORED SCRIPTS STATUS ---"
        if [ -d "$MONITOR_LOG_DIR" ]; then
            for log_file in "$MONITOR_LOG_DIR"/*.log; do
                if [ -f "$log_file" ]; then
                    script_name="$(basename "$log_file" .log)"
                    last_run="$(tail -1 "$log_file" 2>/dev/null | grep "Timestamp:" | awk '{print $2, $3}' || echo "Never")"
                    echo "  $script_name: Last run $last_run"
                fi
            done
        else
            echo "No monitoring logs found"
        fi
        echo ""
        
        echo "--- SYSTEM RESOURCES ---"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}' || echo 'unknown')"
        echo "Memory: $(free -h 2>/dev/null | grep Mem: || echo 'unknown')"
        echo "Disk Space:"
        df -h / /tmp /var 2>/dev/null || echo "  unknown"
        echo "==================== END REPORT ===================="
        echo ""
    } >> "$report_file"
    
    log_info "Health report generated: $report_file"
}

# --- Main Execution ---

main() {
    log_info "Starting cron health monitoring check"
    
    # Perform health checks
    check_cron_daemon
    check_crontab_syntax
    check_hung_processes
    check_missing_executions
    check_disk_space
    
    # Generate daily health report (only once per day)
    today="$(date +%Y%m%d)"
    report_file="$HEALTH_LOG_DIR/health-report-$today.log"
    if [ ! -f "$report_file" ]; then
        generate_health_report
    fi
    
    log_info "Cron health monitoring check completed"
}

# Create expected scripts configuration template if it doesn't exist
create_expected_scripts_config() {
    if [ ! -f "$EXPECTED_SCRIPTS_CONFIG" ]; then
        log_info "Creating expected scripts configuration template"
        safe_execute "mkdir -p '$(dirname "$EXPECTED_SCRIPTS_CONFIG")'"
        
        cat > "$EXPECTED_SCRIPTS_CONFIG" <<'EOF'
# Expected Cron Scripts Configuration
# Format: script_name|interval_minutes|description
# This file tells the health monitor which scripts should be running and how often
#
# Examples:
# starlink_monitor-rutos|5|Starlink quality monitoring
# system-maintenance-rutos|60|System maintenance tasks
# backup-logs-rutos|1440|Daily log backup
#
# Add your monitored scripts below:

EOF
        log_info "Expected scripts configuration created at $EXPECTED_SCRIPTS_CONFIG"
        log_info "Please edit this file to add your cron scripts for monitoring"
    fi
}

# Create the configuration if needed
create_expected_scripts_config

# Execute main function
main "$@"
