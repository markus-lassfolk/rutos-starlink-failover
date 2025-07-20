#!/bin/sh
# Script: fix-database-spam-rutos.sh
# Version: 1.0.0  
# Description: Fix RUTOS database optimization loop spam issue
# Based on user's manual solution but enhanced for safety and integration

set -e  # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
    if [ "${DEBUG:-0}" = "1" ]; then
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

# Check if running on RUTOS system
check_system() {
    if [ ! -f "/etc/openwrt_release" ] && [ ! -f "/etc/rutos_version" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi
}

# Check if we can detect the spam issue
check_database_spam() {
    log_step "Checking for database optimization loop spam"
    
    # Check recent logs for the spam pattern
    spam_count=0
    if command -v logread >/dev/null 2>&1; then
        recent_log=$(logread -l 200 2>/dev/null | tail -n 100 || true)
        if [ -n "$recent_log" ]; then
            spam_count=$(echo "$recent_log" | grep -c "Unable to optimize database\|Failed to restore database\|Unable to reduce max rows" 2>/dev/null || echo "0")
        fi
    fi
    
    log_info "Found $spam_count database optimization error messages in recent log"
    
    if [ "$spam_count" -ge 5 ]; then
        log_warning "Database optimization loop detected ($spam_count errors found)"
        return 0  # Issue detected
    else
        log_info "No significant database spam detected"
        return 1  # No issue
    fi
}

# Stop services that might be causing database issues
stop_database_services() {
    log_step "Stopping services that might be causing database issues"
    
    services_to_stop="nlbwmon ip_block collectd statistics"
    stopped_services=""
    
    for service in $services_to_stop; do
        if [ -f "/etc/init.d/$service" ]; then
            if pgrep "$service" >/dev/null 2>&1; then
                log_info "Stopping service: $service"
                if /etc/init.d/"$service" stop >/dev/null 2>&1; then
                    stopped_services="$stopped_services $service"
                    log_success "Stopped $service successfully"
                    sleep 2
                else
                    log_warning "Failed to stop $service cleanly, trying force kill"
                    if killall "$service" >/dev/null 2>&1; then
                        stopped_services="$stopped_services $service"
                        log_success "Force stopped $service"
                    else
                        log_error "Failed to stop $service"
                    fi
                fi
            else
                log_debug "Service $service not running"
            fi
        else
            log_debug "Service $service not found"
        fi
    done
    
    if [ -n "$stopped_services" ]; then
        log_info "Stopped services:$stopped_services"
        # Let processes finish cleanly
        sleep 5
    else
        log_info "No services needed to be stopped"
    fi
    
    # Return the stopped services list via echo for restart function
    echo "$stopped_services"
}

# Backup and reset databases
backup_and_reset_databases() {
    log_step "Backing up and resetting corrupted databases"
    
    # Create backup directory with timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="/tmp/db_spam_fix_backup_$backup_timestamp"
    
    log_info "Creating backup directory: $backup_dir"
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        log_error "Failed to create backup directory"
        return 1
    fi
    
    # Database paths that commonly cause issues
    db_paths="/usr/local/share/nlbwmon/data.db /usr/local/share/ip_block/attempts.db /tmp/dhcp.leases.db"
    databases_processed=""
    
    for db_path in $db_paths; do
        if [ -f "$db_path" ]; then
            db_name=$(basename "$db_path")
            log_info "Processing database: $db_path"
            
            # Create backup
            backup_file="$backup_dir/$db_name.backup"
            if cp "$db_path" "$backup_file" 2>/dev/null; then
                log_success "Backed up $db_name to $backup_file"
                
                # Remove original (will be recreated by services)
                if rm -f "$db_path" 2>/dev/null; then
                    log_success "Removed corrupted database: $db_path"
                    databases_processed="$databases_processed $db_name"
                else
                    log_error "Failed to remove $db_path"
                fi
            else
                log_error "Failed to backup $db_path"
            fi
        else
            log_debug "Database not found: $db_path"
        fi
    done
    
    if [ -n "$databases_processed" ]; then
        log_success "Processed databases:$databases_processed"
        log_info "All databases backed up to: $backup_dir"
        # Return backup directory path
        echo "$backup_dir"
        return 0
    else
        log_warning "No databases found to process"
        return 1
    fi
}

# Check and restore ubus if needed
check_and_restore_ubus() {
    log_step "Checking ubus status"
    
    if ubus list >/dev/null 2>&1; then
        log_success "ubus is already running properly"
        return 0
    else
        log_warning "ubus not responding, attempting restart"
        
        # Kill existing ubusd if running
        if pidof ubusd >/dev/null; then
            log_info "Killing existing ubusd process"
            killall ubusd 2>/dev/null || true
            sleep 2
        fi
        
        # Start ubusd manually
        log_info "Starting ubusd"
        ubusd >/dev/null 2>&1 &
        sleep 3
        
        # Check if it's working now
        if ubus list >/dev/null 2>&1; then
            log_success "ubus restarted successfully"
            return 0
        else
            log_error "ubus still not responding after restart attempt"
            return 1
        fi
    fi
}

# Restart services that were stopped
restart_database_services() {
    stopped_services="$1"
    
    if [ -z "$stopped_services" ]; then
        log_info "No services to restart"
        return 0
    fi
    
    log_step "Restarting database services"
    
    restarted_services=""
    for service in $stopped_services; do
        if [ -f "/etc/init.d/$service" ]; then
            log_info "Restarting service: $service"
            if /etc/init.d/"$service" start >/dev/null 2>&1; then
                restarted_services="$restarted_services $service"
                log_success "Restarted $service successfully"
            else
                log_error "Failed to restart $service"
            fi
        fi
    done
    
    if [ -n "$restarted_services" ]; then
        log_success "Restarted services:$restarted_services"
    fi
}

# Verify fix worked
verify_fix() {
    log_step "Verifying that the database spam issue is resolved"
    
    log_info "Waiting 30 seconds to observe system behavior..."
    sleep 30
    
    # Check for new spam in logs
    if command -v logread >/dev/null 2>&1; then
        new_spam_count=0
        recent_check=$(logread -l 50 2>/dev/null | tail -n 20 || true)
        if [ -n "$recent_check" ]; then
            new_spam_count=$(echo "$recent_check" | grep -c "Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")
        fi
        
        if [ "$new_spam_count" -lt 2 ]; then
            log_success "Verification passed: Only $new_spam_count optimization errors found"
            log_success "Database spam issue appears to be resolved"
            return 0
        else
            log_error "Verification failed: Still seeing $new_spam_count optimization errors"
            log_error "Manual investigation may be required"
            return 1
        fi
    else
        log_warning "Cannot verify fix - logread not available"
        return 0
    fi
}

# Show current system log status
show_log_status() {
    log_step "Current system log status (last 20 lines)"
    
    if command -v logread >/dev/null 2>&1; then
        # Get last 20 lines and highlight database errors
        log_output=$(logread -l 30 2>/dev/null | tail -n 20 || echo "Could not read logs")
        echo "$log_output" | while IFS= read -r line; do
            case "$line" in
                *"Unable to optimize database"*|*"Failed to restore database"*|*"Unable to reduce max rows"*)
                    printf "${RED}%s${NC}\n" "$line"
                    ;;
                *)
                    printf "%s\n" "$line"
                    ;;
            esac
        done
    else
        log_warning "logread not available - cannot show system log"
    fi
}

# Show usage
show_usage() {
    cat << EOF
RUTOS Database Spam Fix Script v$SCRIPT_VERSION

This script fixes the database optimization loop spam issue on Teltonika RUTX50 routers.
Based on user's manual solution but enhanced for safety and integration.

Usage: $0 [command]

Commands:
  fix       - Fix the database spam issue (default)
  check     - Only check if the issue exists
  status    - Show current system log status
  help      - Show this help message

Environment Variables:
  DEBUG=1   - Enable debug output

The script will:
1. Check for database optimization spam in system logs
2. Stop problematic services (nlbwmon, ip_block, collectd, statistics)
3. Backup corrupted databases to /tmp/db_spam_fix_backup_<timestamp>/
4. Remove corrupted databases (they will be recreated)
5. Check and restart ubus if needed
6. Restart the stopped services
7. Verify the fix worked

Examples:
  $0                    # Run automatic fix
  $0 check              # Check only
  $0 status             # Show log status
  DEBUG=1 $0 fix        # Fix with debug output

Note: This script is also integrated into the system maintenance framework
      and will run automatically via cron if enabled.

EOF
}

# Main function
main() {
    command="${1:-fix}"
    
    case "$command" in
        "fix")
            log_info "Starting RUTOS Database Spam Fix v$SCRIPT_VERSION"
            printf "${BLUE}===============================================${NC}\n"
            printf "${BLUE}🔧 RUTOS Database Spam Fix - $(date)${NC}\n"
            printf "${BLUE}===============================================${NC}\n"
            
            # Check system
            check_system
            
            # Check if issue exists
            if ! check_database_spam; then
                log_info "No database spam issue detected. Exiting."
                exit 0
            fi
            
            # Perform fix
            stopped_services=$(stop_database_services)
            backup_dir=$(backup_and_reset_databases)
            check_and_restore_ubus
            restart_database_services "$stopped_services"
            
            # Verify and report
            if verify_fix; then
                printf "${BLUE}===============================================${NC}\n"
                printf "${GREEN}🏁 Database spam fix completed successfully!${NC}\n"
                if [ -n "$backup_dir" ]; then
                    printf "${CYAN}📦 Backups saved to: $backup_dir${NC}\n"
                fi
                printf "${BLUE}===============================================${NC}\n"
            else
                printf "${BLUE}===============================================${NC}\n"
                printf "${YELLOW}⚠️  Fix applied but verification inconclusive${NC}\n"
                printf "${CYAN}📦 Monitor system logs and check manually if needed${NC}\n"
                printf "${BLUE}===============================================${NC}\n"
            fi
            ;;
        "check")
            log_info "Checking for database spam issue..."
            if check_database_spam; then
                log_warning "Database spam issue detected - run '$0 fix' to resolve"
                exit 1
            else
                log_success "No database spam issue detected"
                exit 0
            fi
            ;;
        "status")
            show_log_status
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
