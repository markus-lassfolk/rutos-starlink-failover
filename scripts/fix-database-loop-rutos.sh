#!/bin/sh
# Script: fix-database-loop-rutos.sh
# Version: 2.7.0
# Description: Fix RUTOS database optimization loop issue

set -e # Exit on error

# Version information
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
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

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
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

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Check for database loop in logs
check_database_loop() {
    log_step "Checking for database optimization loop in system logs"

    # Check recent logs for the database error pattern
    loop_count=$(logread | tail -100 | grep -c "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")

    if [ "$loop_count" -gt 5 ]; then
        log_error "Database optimization loop detected! Found $loop_count related errors in recent logs"
        return 1
    else
        log_info "No database optimization loop detected (found $loop_count related errors)"
        return 0
    fi
}

# Find potential database files
find_database_files() {
    log_step "Locating potential database files"

    # Common RUTOS database locations
    db_locations="/tmp/sqlite_database /var/lib/sqlite /opt/database /etc/database /var/database"
    found_databases=""

    for location in $db_locations; do
        if [ -d "$location" ]; then
            log_debug "Checking database directory: $location"
            db_files=$(find "$location" -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" 2>/dev/null || true)
            if [ -n "$db_files" ]; then
                log_info "Found databases in $location:"
                echo "$db_files" | while IFS= read -r db_file; do
                    log_info "  - $db_file"
                done
                found_databases="$found_databases $db_files"
            fi
        fi
    done

    # Also check for common system database files
    system_dbs="/tmp/system.db /tmp/events.db /tmp/connections.db /tmp/network.db"
    for db in $system_dbs; do
        if [ -f "$db" ]; then
            log_info "Found system database: $db"
            found_databases="$found_databases $db"
        fi
    done

    if [ -z "$found_databases" ]; then
        log_warning "No database files found in common locations"
        # Try a broader search
        log_step "Performing broader database search..."
        all_dbs=$(find / -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" 2>/dev/null | head -20 || true)
        if [ -n "$all_dbs" ]; then
            log_info "Found databases in system:"
            echo "$all_dbs" | while IFS= read -r db_file; do
                log_info "  - $db_file"
            done
        fi
    fi

    echo "$found_databases"
}

# Check database integrity
check_database_integrity() {
    db_file="$1"

    if [ ! -f "$db_file" ]; then
        log_warning "Database file not found: $db_file"
        return 1
    fi

    log_step "Checking integrity of database: $db_file"

    # Check if file is actually a SQLite database
    if ! file "$db_file" | grep -q "SQLite"; then
        log_warning "$db_file is not a SQLite database"
        return 1
    fi

    # Check if database is locked
    if ! sqlite3 "$db_file" ".timeout 1000" ".schema" >/dev/null 2>&1; then
        log_error "Database appears to be locked or corrupted: $db_file"
        return 1
    fi

    # Run integrity check
    log_debug "Running PRAGMA integrity_check on $db_file"
    integrity_result=$(sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null || echo "ERROR")

    if [ "$integrity_result" = "ok" ]; then
        log_success "Database integrity check passed: $db_file"
        return 0
    else
        log_error "Database integrity check failed: $db_file"
        log_error "Result: $integrity_result"
        return 1
    fi
}

# Stop processes that might be using databases
stop_database_processes() {
    log_step "Stopping processes that might be accessing databases"

    # Stop common RUTOS services that might be using databases
    services_to_stop="collectd statistics uhttpd"

    for service in $services_to_stop; do
        if pgrep "$service" >/dev/null 2>&1; then
            log_info "Stopping $service service"
            killall "$service" 2>/dev/null || true
            sleep 2

            # Force kill if still running
            if pgrep "$service" >/dev/null 2>&1; then
                log_warning "Force killing $service processes"
                killall -9 "$service" 2>/dev/null || true
            fi
        else
            log_debug "$service is not running"
        fi
    done

    # Give processes time to cleanly exit
    sleep 3
}

# Restart database processes
restart_database_processes() {
    log_step "Restarting database-related services"

    # Restart services that might use databases
    services_to_restart="collectd statistics"

    for service in $services_to_restart; do
        if [ -f "/etc/init.d/$service" ]; then
            log_info "Starting $service service"
            /etc/init.d/"$service" start 2>/dev/null || log_warning "Failed to start $service"
        fi
    done

    # Restart syslog to ensure clean logging
    log_info "Restarting syslog service"
    /etc/init.d/syslog restart 2>/dev/null || log_warning "Failed to restart syslog"
}

# Repair corrupted database
repair_database() {
    db_file="$1"

    if [ ! -f "$db_file" ]; then
        log_warning "Database file not found: $db_file"
        return 1
    fi

    log_step "Attempting to repair database: $db_file"

    # Create backup first
    backup_file="${db_file}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$db_file" "$backup_file"; then
        log_success "Database backed up to: $backup_file"
    else
        log_error "Failed to create backup of $db_file"
        return 1
    fi

    # Try to repair using sqlite3
    repair_sql="/tmp/repair_db_$$.sql"
    cat >"$repair_sql" <<'EOF'
.timeout 5000
PRAGMA integrity_check;
REINDEX;
VACUUM;
ANALYZE;
PRAGMA optimize;
EOF

    log_info "Running database repair operations..."
    if sqlite3 "$db_file" <"$repair_sql" >/dev/null 2>&1; then
        log_success "Database repair completed: $db_file"
        rm -f "$repair_sql"
        return 0
    else
        log_error "Database repair failed: $db_file"

        # Try to recreate from schema if possible
        log_warning "Attempting to recreate database from schema"
        if sqlite3 "$db_file" ".schema" >"/tmp/schema_$$.sql" 2>/dev/null; then
            # Remove old database and recreate
            rm -f "$db_file"
            if sqlite3 "$db_file" <"/tmp/schema_$$.sql" 2>/dev/null; then
                log_success "Database recreated from schema: $db_file"
                rm -f "/tmp/schema_$$.sql" "$repair_sql"
                return 0
            else
                log_error "Failed to recreate database from schema"
                # Restore backup
                mv "$backup_file" "$db_file"
                log_warning "Database restored from backup"
            fi
        fi

        rm -f "$repair_sql"
        return 1
    fi
}

# Clear system database optimization flags
clear_optimization_flags() {
    log_step "Clearing database optimization flags and temporary files"

    # Remove temporary optimization files that might be causing the loop
    temp_files="/tmp/db_optimize_lock /tmp/database_maintenance /var/lock/database_optimize"

    for temp_file in $temp_files; do
        if [ -f "$temp_file" ]; then
            log_info "Removing optimization lock file: $temp_file"
            rm -f "$temp_file" 2>/dev/null || log_warning "Could not remove $temp_file"
        fi
    done

    # Clear any stuck database maintenance cron jobs
    if [ -f "/tmp/cron_db_maintenance" ]; then
        log_info "Removing stuck database maintenance marker"
        rm -f "/tmp/cron_db_maintenance" 2>/dev/null || true
    fi
}

# Monitor for loop resolution
monitor_fix() {
    log_step "Monitoring system to verify loop resolution"

    log_info "Waiting 60 seconds to observe system behavior..."
    sleep 60

    # Check if errors are still occurring
    new_errors=$(logread | tail -50 | grep -c "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")

    if [ "$new_errors" -eq 0 ]; then
        log_success "✅ Database optimization loop appears to be resolved!"
        return 0
    else
        log_warning "⚠ Still seeing $new_errors database errors - may need additional intervention"
        return 1
    fi
}

# Display system status
show_system_status() {
    log_step "Current system status"

    # Show memory usage
    log_info "Memory usage:"
    printf "${BLUE}%s${NC}\n" "$(free | head -2)"

    # Show disk usage of common database locations
    log_info "Disk usage of database locations:"
    for location in /tmp /var /opt; do
        if [ -d "$location" ]; then
            usage=$(df -h "$location" 2>/dev/null | tail -1 | awk '{print $5}' || echo "unknown")
            printf "${BLUE}%-10s: %s used${NC}\n" "$location" "$usage"
        fi
    done

    # Show recent log summary
    log_info "Recent system log summary (last 10 lines):"
    printf "${CYAN}%s${NC}\n" "$(logread | tail -10)"
}

# Main repair function
main_repair() {
    log_info "Starting RUTOS database loop repair v$SCRIPT_VERSION"

    # Step 1: Confirm the issue exists
    if ! check_database_loop; then
        log_success "No database optimization loop detected - system appears healthy"
        show_system_status
        return 0
    fi

    # Step 2: Show current system status
    show_system_status

    # Step 3: Find database files
    log_step "Locating database files that might be causing the issue"
    databases=$(find_database_files)

    # Step 4: Stop database processes
    stop_database_processes

    # Step 5: Clear optimization flags
    clear_optimization_flags

    # Step 6: Check and repair databases if found
    if [ -n "$databases" ]; then
        echo "$databases" | while IFS= read -r db_file; do
            if [ -f "$db_file" ]; then
                if ! check_database_integrity "$db_file"; then
                    repair_database "$db_file"
                fi
            fi
        done
    fi

    # Step 7: Restart services
    restart_database_processes

    # Step 8: Monitor results
    monitor_fix

    # Step 9: Final status
    log_success "Database loop repair process completed"
    log_info "If the issue persists, try:"
    log_info "  1. Reboot the router: reboot"
    log_info "  2. Check for firmware updates"
    log_info "  3. Contact RUTOS support if problem continues"
}

# Emergency stop function
emergency_stop() {
    log_error "Emergency stop requested - cleaning up"

    # Kill any database processes that might be stuck
    log_warning "Force stopping all database-related processes"
    killall -9 sqlite3 2>/dev/null || true

    # Remove any temporary files we created
    rm -f /tmp/repair_db_*.sql /tmp/schema_*.sql 2>/dev/null || true

    log_warning "Emergency cleanup completed"
    exit 1
}

# Handle script interruption
trap emergency_stop INT TERM

# Usage information
show_usage() {
    cat <<EOF
RUTOS Database Loop Fix Script v$SCRIPT_VERSION

This script diagnoses and repairs database optimization loops in RUTOS.

Usage: $0 [command]

Commands:
  check     - Only check for database loop issues (no fixes)
  repair    - Full repair process (default)
  status    - Show current system status
  emergency - Emergency stop all database processes
  help      - Show this help message

Environment Variables:
  DEBUG=1   - Enable debug output

Examples:
  $0                    # Run full repair
  $0 check              # Just check for issues
  DEBUG=1 $0 repair     # Repair with debug output

EOF
}

# Main script logic
case "${1:-repair}" in
    "check")
        log_info "Running database loop check only"
        check_database_loop
        show_system_status
        ;;
    "repair")
        main_repair
        ;;
    "status")
        show_system_status
        ;;
    "emergency")
        emergency_stop
        ;;
    "help" | "-h" | "--help")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
