#!/bin/sh
# Script: enhanced-cron-logging-rutos.sh
# Version: 2.7.0
# Description: Enhanced cron job logging and monitoring for Starlink monitor

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "enhanced-cron-logging-rutos.sh" "$SCRIPT_VERSION"

# =============================================================================
# ENHANCED CRON JOB LOGGING SYSTEM
# =============================================================================
# This script provides comprehensive logging and monitoring for Starlink cron jobs
# Features:
# - Individual log files for each cron job execution
# - Status tracking and error detection
# - Health check and diagnostic capabilities
# - Log rotation and cleanup management
# =============================================================================

# Configuration
CRON_LOG_DIR="/etc/starlink-logs/cron"
MONITOR_LOG_DIR="/etc/starlink-logs"
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
MAX_LOG_FILES="50"  # Keep last 50 executions per job
LOG_RETENTION_DAYS="7"  # Keep logs for 7 days

# Ensure log directories exist
mkdir -p "$CRON_LOG_DIR"
mkdir -p "$MONITOR_LOG_DIR"

# =============================================================================
# CRON LOGGING FUNCTIONS
# =============================================================================

# Function to create a timestamped log file for cron execution
create_cron_log() {
    local job_name="$1"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$CRON_LOG_DIR/${job_name}_${timestamp}.log"
    
    log_info "Creating cron log: $log_file"
    
    # Create log file with header
    cat > "$log_file" << EOF
# Starlink Monitor Cron Execution Log
# Job: $job_name
# Started: $(date '+%Y-%m-%d %H:%M:%S')
# PID: $$
# User: $(id -un 2>/dev/null || echo 'unknown')
# Working Dir: $(pwd)
# =============================================================================

EOF
    
    echo "$log_file"
}

# Function to log cron job completion status
log_cron_completion() {
    local log_file="$1"
    local exit_code="$2"
    local job_name="$3"
    
    cat >> "$log_file" << EOF

# =============================================================================
# Job Completion Summary
# =============================================================================
# Finished: $(date '+%Y-%m-%d %H:%M:%S')
# Exit Code: $exit_code
# Status: $([ "$exit_code" = "0" ] && echo "SUCCESS" || echo "FAILED")
# Duration: $(($(date +%s) - START_TIME)) seconds
EOF
    
    if [ "$exit_code" = "0" ]; then
        log_success "Cron job '$job_name' completed successfully"
    else
        log_error "Cron job '$job_name' failed with exit code $exit_code"
    fi
    
    # Update status file
    echo "$(date '+%Y-%m-%d %H:%M:%S') $job_name $exit_code" >> "$CRON_LOG_DIR/job_status.log"
}

# Function to wrap script execution with enhanced logging
execute_with_cron_logging() {
    local script_path="$1"
    local job_name="$2"
    shift 2
    local script_args="$*"
    
    START_TIME=$(date +%s)
    local log_file=$(create_cron_log "$job_name")
    
    log_info "Executing $script_path with cron logging"
    log_debug "Log file: $log_file"
    log_debug "Arguments: $script_args"
    
    # Execute script with logging
    if [ -n "$script_args" ]; then
        "$script_path" "$@" >> "$log_file" 2>&1
    else
        "$script_path" >> "$log_file" 2>&1
    fi
    
    local exit_code=$?
    log_cron_completion "$log_file" "$exit_code" "$job_name"
    
    return $exit_code
}

# =============================================================================
# CRON HEALTH MONITORING
# =============================================================================

# Function to check cron job health and recent execution status
check_cron_health() {
    log_step "Checking cron job health status"
    
    local status_file="$CRON_LOG_DIR/job_status.log"
    local health_report="$CRON_LOG_DIR/health_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    cat > "$health_report" << EOF
# Starlink Monitor Cron Health Report
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

EOF
    
    if [ ! -f "$status_file" ]; then
        log_warning "No cron job status file found - jobs may not be running"
        echo "WARNING: No execution history found" >> "$health_report"
        return 1
    fi
    
    # Analyze recent job executions
    local recent_jobs=$(tail -20 "$status_file" 2>/dev/null || echo "")
    local failed_jobs=$(echo "$recent_jobs" | grep -v " 0$" | wc -l)
    local total_jobs=$(echo "$recent_jobs" | wc -l)
    
    log_info "Recent cron job statistics:"
    log_info "  Total executions: $total_jobs"
    log_info "  Failed executions: $failed_jobs"
    log_info "  Success rate: $(( (total_jobs - failed_jobs) * 100 / total_jobs ))%" 2>/dev/null || echo "  Success rate: N/A"
    
    # Add to health report
    cat >> "$health_report" << EOF
## Recent Job Execution Summary (Last 20 runs)
Total Executions: $total_jobs
Failed Executions: $failed_jobs
Success Rate: $(( (total_jobs - failed_jobs) * 100 / total_jobs ))%

## Recent Job Details
$recent_jobs

## Failed Jobs Analysis
EOF
    
    if [ "$failed_jobs" -gt 0 ]; then
        log_warning "Found $failed_jobs failed job executions"
        echo "$recent_jobs" | grep -v " 0$" >> "$health_report"
    else
        log_success "All recent cron jobs completed successfully"
        echo "No failed jobs in recent history" >> "$health_report"
    fi
    
    log_info "Health report saved to: $health_report"
    return 0
}

# Function to show current cron job status
show_cron_status() {
    log_step "Displaying current cron job status"
    
    printf "%s[CRON STATUS]%s Current Starlink Monitor Cron Jobs\n" "$BLUE" "$NC"
    printf "=====================================\n"
    
    # Check if cron jobs are configured
    if crontab -l 2>/dev/null | grep -q "starlink"; then
        printf "%s✓ CONFIGURED%s | Starlink cron jobs found in crontab\n" "$GREEN" "$NC"
        
        # Show configured jobs
        printf "\n%sConfigured Jobs:%s\n" "$BLUE" "$NC"
        crontab -l 2>/dev/null | grep "starlink" | while IFS= read -r line; do
            printf "  %s\n" "$line"
        done
    else
        printf "%s✗ NOT CONFIGURED%s | No Starlink cron jobs found\n" "$RED" "$NC"
    fi
    
    # Check recent execution status
    printf "\n%sRecent Execution Status:%s\n" "$BLUE" "$NC"
    local status_file="$CRON_LOG_DIR/job_status.log"
    
    if [ -f "$status_file" ] && [ -s "$status_file" ]; then
        # Show last 5 executions
        tail -5 "$status_file" | while IFS= read -r line; do
            local exit_code=$(echo "$line" | awk '{print $NF}')
            if [ "$exit_code" = "0" ]; then
                printf "  %s✓ SUCCESS%s | %s\n" "$GREEN" "$NC" "$line"
            else
                printf "  %s✗ FAILED%s  | %s\n" "$RED" "$NC" "$line"
            fi
        done
    else
        printf "  %s⚠ NO DATA%s   | No execution history found\n" "$YELLOW" "$NC"
    fi
    
    # Check log file status
    printf "\n%sLog Files:%s\n" "$BLUE" "$NC"
    local log_count=$(find "$CRON_LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    printf "  Log files available: %s\n" "$log_count"
    
    if [ "$log_count" -gt 0 ]; then
        printf "  Latest logs:\n"
        find "$CRON_LOG_DIR" -name "*.log" -type f -printf "%T@ %p\n" 2>/dev/null | \
            sort -nr | head -3 | while IFS= read -r line; do
            local log_file=$(echo "$line" | cut -d' ' -f2-)
            local log_name=$(basename "$log_file")
            printf "    %s\n" "$log_name"
        done
    fi
}

# =============================================================================
# LOG MANAGEMENT FUNCTIONS
# =============================================================================

# Function to clean old log files
cleanup_old_logs() {
    log_step "Cleaning up old cron log files"
    
    local cleaned_count=0
    
    # Remove logs older than retention period
    if [ -d "$CRON_LOG_DIR" ]; then
        find "$CRON_LOG_DIR" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} | while IFS= read -r old_log; do
            if [ -f "$old_log" ]; then
                log_debug "Removing old log: $(basename "$old_log")"
                rm -f "$old_log"
                cleaned_count=$((cleaned_count + 1))
            fi
        done
    fi
    
    # Keep only the most recent logs per job type
    for job_type in monitor logger maintenance; do
        local job_logs=$(find "$CRON_LOG_DIR" -name "${job_type}_*.log" -type f 2>/dev/null | sort -r)
        local log_count=$(echo "$job_logs" | wc -l)
        
        if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
            local excess_count=$((log_count - MAX_LOG_FILES))
            echo "$job_logs" | tail -n "$excess_count" | while IFS= read -r excess_log; do
                if [ -f "$excess_log" ]; then
                    log_debug "Removing excess log: $(basename "$excess_log")"
                    rm -f "$excess_log"
                    cleaned_count=$((cleaned_count + 1))
                fi
            done
        fi
    done
    
    log_info "Log cleanup completed - removed approximately $cleaned_count old files"
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Function to install enhanced cron logging
install_cron_logging() {
    log_step "Installing enhanced cron logging system"
    
    # Create directories
    mkdir -p "$CRON_LOG_DIR"
    mkdir -p "$MONITOR_LOG_DIR"
    
    # Set up log rotation
    cat > "/etc/logrotate.d/starlink-cron" << 'EOF'
/etc/starlink-logs/cron/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    log_success "Enhanced cron logging system installed"
    log_info "Log directory: $CRON_LOG_DIR"
    log_info "Use: enhanced-cron-logging-rutos.sh status - to check job status"
    log_info "Use: enhanced-cron-logging-rutos.sh health - to run health check"
}

# Main function
main() {
    case "${1:-status}" in
        "install")
            install_cron_logging
            ;;
        "status")
            show_cron_status
            ;;
        "health")
            check_cron_health
            ;;
        "cleanup")
            cleanup_old_logs
            ;;
        "execute")
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 execute <script_path> <job_name> [args...]"
                exit 1
            fi
            script_path="$2"
            job_name="$3"
            shift 3
            execute_with_cron_logging "$script_path" "$job_name" "$@"
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Enhanced Cron Logging for Starlink Monitor

Usage: $0 [command]

Commands:
  status    - Show current cron job status and recent execution history
  health    - Run comprehensive health check on cron jobs
  cleanup   - Clean up old log files
  install   - Install enhanced cron logging system
  execute   - Execute script with enhanced logging
  help      - Show this help message

Examples:
  $0 status              # Check current status
  $0 health              # Run health check
  $0 execute /path/to/script.sh monitor_job  # Execute with logging

Log Files:
  Cron logs: $CRON_LOG_DIR
  Status:    $CRON_LOG_DIR/job_status.log
  Health:    $CRON_LOG_DIR/health_report_*.txt
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
