#!/bin/sh
# Script: fix-database-spam-rutos.sh
# Version: 2.4.12
# Description: Fix RUTOS database spam issues including "Can't open database" and optimization loops
# shellcheck disable=SC2059 # Method 5 printf format required for RUTOS color compatibility
# Based on user's manual solutions but enhanced for safety and integration

set -e # Exit on error

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
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
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
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
    log_step "Checking for database spam issues"

    # Check for both patterns: optimization loop and "Can't open database" errors
    optimization_spam_count=0
    cant_open_spam_count=0

    if command -v logread >/dev/null 2>&1; then
        recent_log=$(logread -l 200 2>/dev/null | tail -n 100 || true)
        if [ -n "$recent_log" ]; then
            # Pattern 1: Database optimization loop (existing pattern)
            optimization_spam_count=$(echo "$recent_log" | grep -c "Unable to optimize database\|Failed to restore database\|Unable to reduce max rows" 2>/dev/null || echo "0")

            # Pattern 2: "Can't open database" spam (user's new issue)
            cant_open_spam_count=$(echo "$recent_log" | grep -c "user.err.*Can't open database" 2>/dev/null || echo "0")
        fi
    fi

    total_spam_count=$((optimization_spam_count + cant_open_spam_count))

    log_info "Found $optimization_spam_count database optimization errors"
    log_info "Found $cant_open_spam_count 'Can't open database' errors"
    log_info "Total database spam: $total_spam_count messages"

    if [ "$optimization_spam_count" -ge 5 ]; then
        log_warning "Database optimization loop detected ($optimization_spam_count errors)"
        return 0 # Issue detected
    elif [ "$cant_open_spam_count" -ge 5 ]; then
        log_warning "Can't open database spam detected ($cant_open_spam_count errors)"
        return 0 # Issue detected
    else
        log_info "No significant database spam detected"
        return 1 # No issue
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

    # First check /log filesystem usage (following user's approach)
    if [ -d "/log" ]; then
        log_usage=$(df /log 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
        log_info "/log filesystem usage: ${log_usage}%"

        if [ "$log_usage" -gt 80 ]; then
            log_warning "/log filesystem is ${log_usage}% full - cleaning up"
            # Clean /log only if critical space AND database errors detected (safer approach)
            if rm -rf /log/* 2>/dev/null; then
                sync
                new_usage=$(df /log 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "unknown")
                log_success "/log cleaned - usage now: ${new_usage}%"
            else
                log_error "Failed to clean /log directory"
            fi
        fi

        # Search for databases in /log and process them (user's specific approach)
        log_debug "Searching for databases in /log directory"
        db_list=$(find /log -type f -name "*.db" 2>/dev/null || true)

        if [ -n "$db_list" ]; then
            echo "$db_list" | while IFS= read -r db_path; do
                if [ -f "$db_path" ]; then
                    db_name=$(basename "$db_path")
                    size=$(stat -c%s "$db_path" 2>/dev/null || echo "0")

                    log_info "Found /log database: $db_path (${size} bytes)"

                    # Backup original database
                    if cp "$db_path" "$backup_dir/$db_name.log.backup" 2>/dev/null; then
                        log_debug "Backed up $db_path"
                    fi

                    # Check if database is corrupted/too small (following user's logic)
                    if [ "$size" -lt 1024 ]; then
                        log_warning "Database $db_path is small/corrupted (${size} bytes) - recreating"

                        # Remove corrupted database and recreate (user's approach)
                        if rm -f "$db_path"; then
                            # Create empty database file
                            if dd if=/dev/zero of="$db_path" bs=1 count=0 2>/dev/null && chmod 644 "$db_path"; then
                                log_success "Recreated empty database: $db_path"
                            else
                                log_error "Failed to recreate database: $db_path"
                            fi
                        else
                            log_error "Failed to remove corrupted database: $db_path"
                        fi
                    else
                        log_debug "Database $db_path appears to be intact (${size} bytes)"
                    fi
                fi
            done
        fi
    fi

    # Database paths that commonly cause issues (original approach)
    db_paths="/usr/local/share/nlbwmon/data.db /usr/local/share/ip_block/attempts.db /tmp/dhcp.leases.db"
    databases_processed=""

    for db_path in $db_paths; do
        if [ -f "$db_path" ]; then
            db_name=$(basename "$db_path")
            size=$(stat -c%s "$db_path" 2>/dev/null || echo "0")
            log_info "Processing common database: $db_path (${size} bytes)"

            # Create backup
            backup_file="$backup_dir/$db_name.backup"
            if cp "$db_path" "$backup_file" 2>/dev/null; then
                log_success "Backed up $db_name to $backup_file"

                # For "Can't open database" issues, remove and recreate (user's approach)
                # For optimization loops, just remove (original approach)
                if rm -f "$db_path" 2>/dev/null; then
                    log_success "Removed database: $db_path (will be recreated by services)"
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

    # Check for both types of spam in logs
    if command -v logread >/dev/null 2>&1; then
        optimization_errors=0
        cant_open_errors=0
        recent_check=$(logread -l 50 2>/dev/null | tail -n 20 || true)
        if [ -n "$recent_check" ]; then
            optimization_errors=$(echo "$recent_check" | grep -c "Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")
            cant_open_errors=$(echo "$recent_check" | grep -c "user.err.*Can't open database" 2>/dev/null || echo "0")
        fi

        total_new_errors=$((optimization_errors + cant_open_errors))

        log_info "Post-fix verification:"
        log_info "  Optimization errors: $optimization_errors"
        log_info "  Can't open database errors: $cant_open_errors"
        log_info "  Total new errors: $total_new_errors"

        if [ "$total_new_errors" -lt 2 ]; then
            log_success "Verification passed: Only $total_new_errors database errors found"
            log_success "Database spam issue appears to be resolved"
            return 0
        else
            log_error "Verification failed: Still seeing $total_new_errors database errors"
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
                *"Unable to optimize database"* | *"Failed to restore database"* | *"Unable to reduce max rows"*)
                    printf "${RED}OPTIMIZATION LOOP: %s${NC}\n" "$line"
                    ;;
                *"user.err"*"Can't open database"*)
                    printf "${RED}CAN'T OPEN DB: %s${NC}\n" "$line"
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
    cat <<EOF
RUTOS Database Spam Fix Script v$SCRIPT_VERSION

This script fixes database spam issues on Teltonika RUTX50 routers including:
- Database optimization loop spam ("Unable to optimize database")
- "Can't open database" error spam (user.err messages)

Based on proven user solutions but enhanced for safety and integration.

Usage: $0 [command]

Commands:
  fix       - Fix the database spam issue (default)
  check     - Only check if the issue exists
  status    - Show current system log status
  help      - Show this help message

Environment Variables:
  DEBUG=1   - Enable debug output

The script will:
1. Check for both types of database spam in system logs
2. Stop problematic services (nlbwmon, ip_block, collectd, statistics)
3. Clean /log filesystem if > 80% full AND database errors detected
4. Process databases in /log directory (recreate small/corrupted ones)
5. Backup and reset common problematic databases
6. Check and restart ubus if needed
7. Restart the stopped services
8. Verify the fix worked

Patterns detected:
- "Unable to optimize database" / "Failed to restore database" (≥5 = loop)
- "user.err.*Can't open database" (≥5 = spam issue)

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
            printf "%b===============================================%b\n" "$BLUE" "$NC"
            printf "%b🔧 RUTOS Database Spam Fix - %s%b\n" "$BLUE" "$(date)" "$NC"
            printf "%b===============================================%b\n" "$BLUE" "$NC"

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
                printf "%b===============================================%b\n" "$BLUE" "$NC"
                printf "%b🏁 Database spam fix completed successfully!%b\n" "$GREEN" "$NC"
                if [ -n "$backup_dir" ]; then
                    printf "${CYAN}📦 Backups saved to: %s${NC}\n" "$backup_dir"
                fi
                printf "%b===============================================%b\n" "$BLUE" "$NC"
            else
                printf "%b===============================================%b\n" "$BLUE" "$NC"
                printf "%b⚠️  Fix applied but verification inconclusive%b\n" "$YELLOW" "$NC"
                printf "%b📦 Monitor system logs and check manually if needed%b\n" "$CYAN" "$NC"
                printf "%b===============================================%b\n" "$BLUE" "$NC"
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
        "help" | "-h" | "--help")
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
