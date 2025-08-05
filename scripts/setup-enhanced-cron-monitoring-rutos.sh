#!/bin/sh
# Script: setup-enhanced-cron-monitoring-rutos.sh
# Version: 2.7.0
# Description: Set up enhanced cron monitoring with comprehensive logging

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "setup-enhanced-cron-monitoring-rutos.sh" "$SCRIPT_VERSION"

# =============================================================================
# ENHANCED CRON SETUP WITH COMPREHENSIVE LOGGING
# =============================================================================
# This script sets up cron jobs with enhanced logging, monitoring, and
# health checking capabilities for the Starlink monitoring system.
# =============================================================================

# Configuration
INSTALL_DIR="/usr/local/starlink-monitor"
CRON_LOG_DIR="/etc/starlink-logs/cron"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
CONFIG_FILE="/etc/starlink-config/config.sh"

# =============================================================================
# CRON SETUP FUNCTIONS
# =============================================================================

# Function to set up enhanced cron jobs with logging
setup_enhanced_cron_jobs() {
    log_step "Setting up enhanced cron jobs with comprehensive logging"
    
    # Ensure log directory exists
    mkdir -p "$CRON_LOG_DIR"
    
    # Install enhanced logging script
    if [ ! -f "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" ]; then
        log_warning "Enhanced logging script not found, copying from current location"
        if [ -f "$(dirname "$0")/enhanced-cron-logging-rutos.sh" ]; then
            cp "$(dirname "$0")/enhanced-cron-logging-rutos.sh" "$SCRIPTS_DIR/"
            chmod +x "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh"
        else
            log_error "Cannot find enhanced-cron-logging-rutos.sh to install"
            return 1
        fi
    fi
    
    # Get current crontab
    local temp_cron="/tmp/crontab_$$"
    crontab -l > "$temp_cron" 2>/dev/null || echo "# Crontab" > "$temp_cron"
    
    # Remove old Starlink entries
    log_info "Removing old Starlink cron entries"
    sed -i '/starlink/d' "$temp_cron"
    
    # Add enhanced cron jobs with logging
    cat >> "$temp_cron" << EOF

# =============================================================================
# Starlink Monitor Enhanced Cron Jobs with Logging
# =============================================================================
# These jobs use enhanced logging for better monitoring and troubleshooting

# Main Starlink Monitor - Every 2 minutes with enhanced logging
*/2 * * * * CONFIG_FILE=$CONFIG_FILE $SCRIPTS_DIR/enhanced-cron-logging-rutos.sh execute $INSTALL_DIR/Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh starlink_monitor 2>&1

# Starlink Logger - Every 5 minutes with enhanced logging
*/5 * * * * CONFIG_FILE=$CONFIG_FILE $SCRIPTS_DIR/enhanced-cron-logging-rutos.sh execute $INSTALL_DIR/scripts/starlink_logger-rutos.sh starlink_logger 2>&1

# System Maintenance - Daily at 3:30 AM with enhanced logging
30 3 * * * CONFIG_FILE=$CONFIG_FILE $SCRIPTS_DIR/enhanced-cron-logging-rutos.sh execute $INSTALL_DIR/scripts/system-maintenance-rutos.sh system_maintenance 2>&1

# Cron Health Check - Daily at 6:00 AM
0 6 * * * $SCRIPTS_DIR/enhanced-cron-logging-rutos.sh health 2>&1 | logger -t starlink-cron-health

# Log Cleanup - Weekly on Sunday at 4:00 AM
0 4 * * 0 $SCRIPTS_DIR/enhanced-cron-logging-rutos.sh cleanup 2>&1 | logger -t starlink-log-cleanup

EOF
    
    # Install new crontab
    if safe_execute "crontab '$temp_cron'" "Install enhanced cron jobs"; then
        log_success "Enhanced cron jobs installed successfully"
        rm -f "$temp_cron"
    else
        log_error "Failed to install cron jobs"
        rm -f "$temp_cron"
        return 1
    fi
    
    # Set up logrotate for cron logs
    setup_logrotate
    
    # Install initial health check
    setup_health_monitoring
    
    return 0
}

# Function to set up log rotation
setup_logrotate() {
    log_step "Setting up log rotation for cron logs"
    
    cat > "/etc/logrotate.d/starlink-cron" << 'EOF'
/etc/starlink-logs/cron/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # Clean up old logs after rotation
        /usr/local/starlink-monitor/scripts/enhanced-cron-logging-rutos.sh cleanup >/dev/null 2>&1 || true
    endscript
}

/etc/starlink-logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    log_success "Log rotation configured"
}

# Function to set up health monitoring
setup_health_monitoring() {
    log_step "Setting up health monitoring scripts"
    
    # Create health monitoring script
    cat > "$SCRIPTS_DIR/cron-health-monitor-rutos.sh" << 'EOF'
#!/bin/sh
# Cron Health Monitor - Check for cron job failures and system issues

. "$(dirname "$0")/lib/rutos-lib.sh"
rutos_init "cron-health-monitor-rutos.sh" "2.7.0"

CRON_LOG_DIR="/etc/starlink-logs/cron"
ALERT_THRESHOLD="3"  # Alert after 3 failures

check_recent_failures() {
    local status_file="$CRON_LOG_DIR/job_status.log"
    
    if [ ! -f "$status_file" ]; then
        log_warning "No cron status file found"
        return 0
    fi
    
    # Check last 10 executions for failures
    local recent_failures=$(tail -10 "$status_file" | grep -v " 0$" | wc -l)
    
    if [ "$recent_failures" -ge "$ALERT_THRESHOLD" ]; then
        log_error "High failure rate detected: $recent_failures failures in last 10 executions"
        
        # Log details to syslog
        logger -t starlink-health "ALERT: $recent_failures cron job failures detected"
        
        # Show failed jobs
        tail -10 "$status_file" | grep -v " 0$" | while IFS= read -r line; do
            logger -t starlink-health "FAILED: $line"
        done
        
        return 1
    else
        log_info "Cron job health check passed: $recent_failures recent failures"
        return 0
    fi
}

# Check disk space
check_disk_space() {
    local log_dir_usage=$(df /etc/starlink-logs | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$log_dir_usage" -gt 80 ]; then
        log_warning "Log directory usage high: ${log_dir_usage}%"
        logger -t starlink-health "WARNING: Log directory usage at ${log_dir_usage}%"
        
        # Trigger cleanup
        /usr/local/starlink-monitor/scripts/enhanced-cron-logging-rutos.sh cleanup
    fi
}

# Main health check
main() {
    log_info "Running cron health check"
    
    check_recent_failures
    check_disk_space
    
    log_success "Health check completed"
}

main "$@"
EOF
    
    chmod +x "$SCRIPTS_DIR/cron-health-monitor-rutos.sh"
    log_success "Health monitoring script created"
}

# =============================================================================
# STATUS AND VERIFICATION FUNCTIONS
# =============================================================================

# Function to show enhanced cron status
show_enhanced_status() {
    log_step "Showing enhanced cron monitoring status"
    
    printf "%s[ENHANCED CRON STATUS]%s Starlink Monitor Cron Jobs\n" "$BLUE" "$NC"
    printf "==============================================\n"
    
    # Check if enhanced logging is available
    if [ -f "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" ]; then
        printf "%s✓ ENHANCED LOGGING%s | Available\n" "$GREEN" "$NC"
        
        # Run status check
        printf "\n"
        "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" status
    else
        printf "%s✗ ENHANCED LOGGING%s | Not available\n" "$RED" "$NC"
    fi
    
    # Check cron configuration
    printf "\n%s[CRON CONFIGURATION]%s\n" "$BLUE" "$NC"
    if crontab -l 2>/dev/null | grep -q "enhanced-cron-logging"; then
        printf "%s✓ ENHANCED CRON%s   | Enhanced logging cron jobs configured\n" "$GREEN" "$NC"
    else
        printf "%s✗ BASIC CRON%s     | Using basic cron jobs (no enhanced logging)\n" "$YELLOW" "$NC"
    fi
    
    # Check log rotation
    printf "\n%s[LOG MANAGEMENT]%s\n" "$BLUE" "$NC"
    if [ -f "/etc/logrotate.d/starlink-cron" ]; then
        printf "%s✓ LOG ROTATION%s   | Configured\n" "$GREEN" "$NC"
    else
        printf "%s✗ LOG ROTATION%s   | Not configured\n" "$YELLOW" "$NC"
    fi
    
    # Check health monitoring
    if [ -f "$SCRIPTS_DIR/cron-health-monitor-rutos.sh" ]; then
        printf "%s✓ HEALTH MONITOR%s | Available\n" "$GREEN" "$NC"
    else
        printf "%s✗ HEALTH MONITOR%s | Not available\n" "$YELLOW" "$NC"
    fi
    
    # Show log directory status
    printf "\n%s[LOG DIRECTORY STATUS]%s\n" "$BLUE" "$NC"
    if [ -d "$CRON_LOG_DIR" ]; then
        local log_count=$(find "$CRON_LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
        local dir_size=$(du -sh "$CRON_LOG_DIR" 2>/dev/null | cut -f1)
        printf "%sLog files:%s      %s\n" "$CYAN" "$NC" "$log_count"
        printf "%sDirectory size:%s %s\n" "$CYAN" "$NC" "$dir_size"
        
        # Show recent activity
        if [ "$log_count" -gt 0 ]; then
            local latest_log=$(find "$CRON_LOG_DIR" -name "*.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
            if [ -n "$latest_log" ]; then
                local latest_time=$(stat -c %y "$latest_log" 2>/dev/null | cut -d'.' -f1)
                printf "%sLatest activity:%s %s\n" "$CYAN" "$NC" "$latest_time"
            fi
        fi
    else
        printf "%s✗ LOG DIRECTORY%s  | Not found: $CRON_LOG_DIR\n" "$RED" "$NC"
    fi
}

# Function to test enhanced logging
test_enhanced_logging() {
    log_step "Testing enhanced cron logging system"
    
    if [ ! -f "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" ]; then
        log_error "Enhanced logging script not found"
        return 1
    fi
    
    # Test status command
    log_info "Testing status command..."
    if "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" status >/dev/null 2>&1; then
        log_success "Status command working"
    else
        log_error "Status command failed"
        return 1
    fi
    
    # Test health command
    log_info "Testing health check..."
    if "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" health >/dev/null 2>&1; then
        log_success "Health check working"
    else
        log_error "Health check failed"
        return 1
    fi
    
    # Test log directory
    if [ -d "$CRON_LOG_DIR" ] && [ -w "$CRON_LOG_DIR" ]; then
        log_success "Log directory accessible"
    else
        log_error "Log directory not accessible"
        return 1
    fi
    
    log_success "Enhanced logging system test completed successfully"
    return 0
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

main() {
    case "${1:-setup}" in
        "setup"|"install")
            setup_enhanced_cron_jobs
            ;;
        "status")
            show_enhanced_status
            ;;
        "test")
            test_enhanced_logging
            ;;
        "health")
            if [ -f "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" ]; then
                "$SCRIPTS_DIR/enhanced-cron-logging-rutos.sh" health
            else
                log_error "Enhanced logging script not found"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Enhanced Cron Monitoring Setup for Starlink Monitor

Usage: $0 [command]

Commands:
  setup     - Set up enhanced cron jobs with comprehensive logging (default)
  status    - Show enhanced cron monitoring status
  test      - Test enhanced logging system
  health    - Run cron job health check
  help      - Show this help message

Features:
  - Individual log files for each cron execution
  - Comprehensive status tracking and health monitoring
  - Automatic log rotation and cleanup
  - Enhanced error detection and alerting
  - Integration with system logging

Examples:
  $0                  # Set up enhanced cron monitoring
  $0 setup            # Same as above
  $0 status           # Check current status
  $0 test             # Test the logging system
  $0 health           # Run health check

Log Files:
  Cron execution logs: $CRON_LOG_DIR
  System integration:  /var/log/messages (search for starlink-*)
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
