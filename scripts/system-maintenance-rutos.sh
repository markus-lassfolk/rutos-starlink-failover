#!/bin/sh
# Script: system-maintenance-rutos.sh
# Version: 1.0.0
# Description: Generic RUTOS system maintenance script that checks for common issues and fixes them

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

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
    # Also log to syslog for system tracking
    logger -t "SystemMaintenance" -p user.info "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    logger -t "SystemMaintenance" -p user.warning "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    logger -t "SystemMaintenance" -p user.error "$1"
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
        logger -t "SystemMaintenance" -p user.debug "$1"
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    logger -t "SystemMaintenance" -p user.notice "SUCCESS: $1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    logger -t "SystemMaintenance" -p user.info "STEP: $1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Maintenance configuration
MAINTENANCE_LOG="/var/log/system-maintenance.log"
ISSUES_FIXED_COUNT=0
ISSUES_FOUND_COUNT=0
CRITICAL_ISSUES_COUNT=0
RUN_MODE="${1:-auto}" # auto, check, fix, report

# Configuration file paths (try multiple locations)
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/usr/local/starlink-monitor/config/config.sh"
fi
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/root/config.sh"
fi

# Load configuration if available
if [ -f "$CONFIG_FILE" ]; then
    log_debug "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    log_warning "Configuration file not found - Pushover notifications disabled"
fi

# Maintenance-specific configuration with defaults
MAINTENANCE_PUSHOVER_ENABLED="${MAINTENANCE_PUSHOVER_ENABLED:-${ENABLE_PUSHOVER_NOTIFICATIONS:-false}}"
MAINTENANCE_PUSHOVER_TOKEN="${MAINTENANCE_PUSHOVER_TOKEN:-${PUSHOVER_TOKEN:-}}"
MAINTENANCE_PUSHOVER_USER="${MAINTENANCE_PUSHOVER_USER:-${PUSHOVER_USER:-}}"
MAINTENANCE_CRITICAL_THRESHOLD="${MAINTENANCE_CRITICAL_THRESHOLD:-3}"          # Send notification if 3+ critical issues
MAINTENANCE_NOTIFICATION_COOLDOWN="${MAINTENANCE_NOTIFICATION_COOLDOWN:-3600}" # 1 hour cooldown
MAINTENANCE_LAST_NOTIFICATION_FILE="/tmp/maintenance_last_notification"

# Enhanced notification configuration with defaults
MAINTENANCE_NOTIFY_ON_FIXES="${MAINTENANCE_NOTIFY_ON_FIXES:-true}"                   # Notify on successful fixes
MAINTENANCE_NOTIFY_ON_FAILURES="${MAINTENANCE_NOTIFY_ON_FAILURES:-true}"             # Notify on failed fixes
MAINTENANCE_NOTIFY_ON_CRITICAL="${MAINTENANCE_NOTIFY_ON_CRITICAL:-true}"             # Notify on critical issues
MAINTENANCE_NOTIFY_ON_FOUND="${MAINTENANCE_NOTIFY_ON_FOUND:-false}"                  # Notify on issues found
MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN="${MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN:-10}" # Max notifications per run
MAINTENANCE_PRIORITY_FIXED="${MAINTENANCE_PRIORITY_FIXED:-0}"                        # Priority for fix notifications
MAINTENANCE_PRIORITY_FAILED="${MAINTENANCE_PRIORITY_FAILED:-1}"                      # Priority for failure notifications
MAINTENANCE_PRIORITY_CRITICAL="${MAINTENANCE_PRIORITY_CRITICAL:-2}"                  # Priority for critical notifications
MAINTENANCE_PRIORITY_FOUND="${MAINTENANCE_PRIORITY_FOUND:-0}"                        # Priority for found notifications
MAINTENANCE_NOTIFICATIONS_SENT=0

# Enhanced maintenance behavior configuration with defaults
MAINTENANCE_AUTO_FIX_ENABLED="${MAINTENANCE_AUTO_FIX_ENABLED:-true}"               # Allow automatic fixes
MAINTENANCE_AUTO_REBOOT_ENABLED="${MAINTENANCE_AUTO_REBOOT_ENABLED:-false}"        # Allow system reboots
MAINTENANCE_REBOOT_THRESHOLD="${MAINTENANCE_REBOOT_THRESHOLD:-5}"                  # Reboot threshold
MAINTENANCE_SERVICE_RESTART_ENABLED="${MAINTENANCE_SERVICE_RESTART_ENABLED:-true}" # Allow service restarts
MAINTENANCE_DATABASE_FIX_ENABLED="${MAINTENANCE_DATABASE_FIX_ENABLED:-true}"       # Allow database fixes
MAINTENANCE_MODE_OVERRIDE="${MAINTENANCE_MODE_OVERRIDE:-}"                         # Mode override
MAINTENANCE_MAX_FIXES_PER_RUN="${MAINTENANCE_MAX_FIXES_PER_RUN:-10}"               # Max fixes per run
MAINTENANCE_COOLDOWN_AFTER_FIXES="${MAINTENANCE_COOLDOWN_AFTER_FIXES:-300}"        # Cooldown after fixes
MAINTENANCE_REBOOT_TRACKING_FILE="/tmp/maintenance_reboot_count"
MAINTENANCE_FIXES_THIS_RUN=0

# Function to record maintenance actions with enhanced notifications
record_action() {
    action_type="$1" # FIXED, FOUND, CHECK, CRITICAL, FAILED
    issue_description="$2"
    fix_description="${3:-N/A}"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$action_type] $issue_description | Fix: $fix_description" >>"$MAINTENANCE_LOG"

    case "$action_type" in
        "FIXED")
            ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))
            log_success "FIXED: $issue_description"
            # Send notification for successful fix
            if [ "$MAINTENANCE_NOTIFY_ON_FIXES" = "true" ]; then
                send_maintenance_notification "FIXED" "✅ $issue_description" "Solution: $fix_description" "$MAINTENANCE_PRIORITY_FIXED"
            fi
            ;;
        "FOUND")
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))
            log_warning "FOUND: $issue_description"
            # Send notification for found issue (if enabled)
            if [ "$MAINTENANCE_NOTIFY_ON_FOUND" = "true" ]; then
                send_maintenance_notification "FOUND" "⚠️ $issue_description" "Action needed: $fix_description" "$MAINTENANCE_PRIORITY_FOUND"
            fi
            ;;
        "FAILED")
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))
            log_error "FAILED: $issue_description"
            # Send notification for failed fix attempt
            if [ "$MAINTENANCE_NOTIFY_ON_FAILURES" = "true" ]; then
                send_maintenance_notification "FAILED" "❌ Fix Failed: $issue_description" "Attempted: $fix_description" "$MAINTENANCE_PRIORITY_FAILED"
            fi
            ;;
        "CRITICAL")
            CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))
            log_error "CRITICAL: $issue_description"
            # Send notification for critical issue
            if [ "$MAINTENANCE_NOTIFY_ON_CRITICAL" = "true" ]; then
                send_maintenance_notification "CRITICAL" "🚨 CRITICAL: $issue_description" "Action: $fix_description" "$MAINTENANCE_PRIORITY_CRITICAL"
            fi
            ;;
        "CHECK")
            log_debug "CHECK: $issue_description"
            ;;
    esac
}

# Function to send Pushover notification for critical issues
send_critical_notification() {
    notification_title="$1"
    notification_message="$2"
    priority="${3:-1}" # 1 = high priority

    # Check if Pushover is configured and enabled
    if [ "$MAINTENANCE_PUSHOVER_ENABLED" != "true" ] || [ -z "$MAINTENANCE_PUSHOVER_TOKEN" ] || [ -z "$MAINTENANCE_PUSHOVER_USER" ]; then
        log_debug "Pushover not configured or disabled - skipping notification"
        return 0
    fi

    # Check notification cooldown
    current_time=$(date +%s)
    if [ -f "$MAINTENANCE_LAST_NOTIFICATION_FILE" ]; then
        last_notification=$(cat "$MAINTENANCE_LAST_NOTIFICATION_FILE" 2>/dev/null || echo "0")
        time_diff=$((current_time - last_notification))

        if [ "$time_diff" -lt "$MAINTENANCE_NOTIFICATION_COOLDOWN" ]; then
            remaining=$((MAINTENANCE_NOTIFICATION_COOLDOWN - time_diff))
            log_debug "Notification cooldown active - ${remaining}s remaining"
            return 0
        fi
    fi

    log_step "Sending critical maintenance notification via Pushover"

    # Prepare notification payload
    payload="token=$MAINTENANCE_PUSHOVER_TOKEN"
    payload="$payload&user=$MAINTENANCE_PUSHOVER_USER"
    payload="$payload&title=$(echo "$notification_title" | sed 's/ /%20/g')"
    payload="$payload&message=$(echo "$notification_message" | sed 's/ /%20/g; s/\n/%0A/g')"
    payload="$payload&priority=$priority"
    payload="$payload&sound=siren" # Use siren sound for critical issues

    # Send notification using curl or wget
    success=false
    if command -v curl >/dev/null 2>&1; then
        if curl -s -d "$payload" https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            success=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q -O- --post-data="$payload" https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            success=true
        fi
    fi

    if [ "$success" = "true" ]; then
        log_success "Critical maintenance notification sent successfully"
        echo "$current_time" >"$MAINTENANCE_LAST_NOTIFICATION_FILE"
        logger -t "SystemMaintenance" -p user.notice "NOTIFICATION: Critical maintenance alert sent via Pushover"
    else
        log_error "Failed to send critical maintenance notification"
        logger -t "SystemMaintenance" -p user.error "NOTIFICATION_FAILED: Could not send Pushover notification"
    fi
}

# Enhanced notification function for individual maintenance actions
send_maintenance_notification() {
    notification_type="$1" # FIXED, FOUND, FAILED, CRITICAL
    issue_title="$2"       # Brief title for the issue
    issue_details="$3"     # Detailed description
    priority="${4:-0}"     # Pushover priority (-2 to 2)

    # Check if we've hit the notification limit for this run
    if [ "$MAINTENANCE_NOTIFICATIONS_SENT" -ge "$MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN" ]; then
        log_debug "Maximum notifications per run reached ($MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN) - skipping"
        return 0
    fi

    # Check if Pushover is configured and enabled
    if [ "$MAINTENANCE_PUSHOVER_ENABLED" != "true" ] || [ -z "$MAINTENANCE_PUSHOVER_TOKEN" ] || [ -z "$MAINTENANCE_PUSHOVER_USER" ]; then
        log_debug "Pushover not configured or disabled - skipping notification"
        return 0
    fi

    # Skip cooldown for individual notifications to get real-time updates
    # The notification limit per run prevents spam instead

    log_debug "Sending $notification_type notification via Pushover"

    # Create descriptive message
    hostname=$(uname -n 2>/dev/null || echo "RUTX50")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$notification_type" in
        "FIXED")
            title="✅ System Fixed - $hostname"
            message="$issue_title%0A%0AFixed at: $timestamp%0A$issue_details"
            sound="magic"
            ;;
        "FAILED")
            title="❌ Fix Failed - $hostname"
            message="$issue_title%0A%0AFailed at: $timestamp%0A$issue_details%0A%0AManual intervention may be required."
            sound="siren"
            ;;
        "CRITICAL")
            title="🚨 CRITICAL Issue - $hostname"
            message="$issue_title%0A%0ADetected at: $timestamp%0A$issue_details%0A%0AIMMEDIATE ATTENTION REQUIRED!"
            sound="alien"
            ;;
        "FOUND")
            title="⚠️ Issue Detected - $hostname"
            message="$issue_title%0A%0AFound at: $timestamp%0A$issue_details"
            sound="pushover"
            ;;
        *)
            title="📋 Maintenance - $hostname"
            message="$issue_title%0A%0ATime: $timestamp%0A$issue_details"
            sound="pushover"
            ;;
    esac

    # Prepare notification payload
    payload="token=$MAINTENANCE_PUSHOVER_TOKEN"
    payload="$payload&user=$MAINTENANCE_PUSHOVER_USER"
    payload="$payload&title=$title"
    payload="$payload&message=$message"
    payload="$payload&priority=$priority"
    payload="$payload&sound=$sound"

    # Add retry and expire for high priority notifications
    if [ "$priority" -ge 1 ]; then
        payload="$payload&retry=60&expire=3600" # Retry every minute for 1 hour
    fi

    # Send notification
    success=false
    if command -v curl >/dev/null 2>&1; then
        if curl -s -d "$payload" https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            success=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q -O- --post-data="$payload" https://api.pushover.net/1/messages.json >/dev/null 2>&1; then
            success=true
        fi
    fi

    if [ "$success" = "true" ]; then
        MAINTENANCE_NOTIFICATIONS_SENT=$((MAINTENANCE_NOTIFICATIONS_SENT + 1))
        log_debug "$notification_type notification sent successfully ($MAINTENANCE_NOTIFICATIONS_SENT/$MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN)"
        logger -t "SystemMaintenance" -p user.info "NOTIFICATION_SENT: $notification_type - $issue_title"
    else
        log_warning "Failed to send $notification_type notification"
        logger -t "SystemMaintenance" -p user.warning "NOTIFICATION_FAILED: $notification_type - $issue_title"
    fi
}

# =============================================================================
# ENHANCED MAINTENANCE CONTROL FUNCTIONS
# =============================================================================

# Determine effective run mode based on configuration
determine_effective_mode() {
    # Use config override if specified, otherwise use command line parameter
    if [ -n "$MAINTENANCE_MODE_OVERRIDE" ]; then
        EFFECTIVE_MODE="$MAINTENANCE_MODE_OVERRIDE"
        log_info "Using config override mode: $EFFECTIVE_MODE"
    else
        EFFECTIVE_MODE="${RUN_MODE:-auto}"
        log_debug "Using default/parameter mode: $EFFECTIVE_MODE"
    fi

    # If auto-fix is disabled, downgrade auto to check
    if [ "$MAINTENANCE_AUTO_FIX_ENABLED" != "true" ] && [ "$EFFECTIVE_MODE" = "auto" ]; then
        EFFECTIVE_MODE="check"
        log_warning "Auto-fix disabled - running in check-only mode"
    fi
}

# Check if fixes are allowed and within limits
should_attempt_fix() {
    fix_type="$1" # service, database, system

    # Check if we've hit the fix limit
    if [ "$MAINTENANCE_FIXES_THIS_RUN" -ge "$MAINTENANCE_MAX_FIXES_PER_RUN" ]; then
        log_warning "Maximum fixes per run reached ($MAINTENANCE_MAX_FIXES_PER_RUN) - skipping $fix_type fix"
        return 1
    fi

    # Check mode allows fixes
    if [ "$EFFECTIVE_MODE" != "fix" ] && [ "$EFFECTIVE_MODE" != "auto" ]; then
        log_debug "Fix mode disabled - skipping $fix_type fix"
        return 1
    fi

    # Check specific fix type permissions
    case "$fix_type" in
        "service")
            if [ "$MAINTENANCE_SERVICE_RESTART_ENABLED" != "true" ]; then
                log_debug "Service restart disabled by configuration"
                return 1
            fi
            ;;
        "database")
            if [ "$MAINTENANCE_DATABASE_FIX_ENABLED" != "true" ]; then
                log_debug "Database fix disabled by configuration"
                return 1
            fi
            ;;
        "system")
            if [ "$MAINTENANCE_AUTO_FIX_ENABLED" != "true" ]; then
                log_debug "System fix disabled by configuration"
                return 1
            fi
            ;;
    esac

    return 0
}

# Increment fix counter
increment_fix_counter() {
    MAINTENANCE_FIXES_THIS_RUN=$((MAINTENANCE_FIXES_THIS_RUN + 1))
    log_debug "Fixes this run: $MAINTENANCE_FIXES_THIS_RUN/$MAINTENANCE_MAX_FIXES_PER_RUN"
}

# Consider system reboot for persistent critical issues
consider_system_reboot() {
    # Check if reboots are enabled
    if [ "$MAINTENANCE_AUTO_REBOOT_ENABLED" != "true" ]; then
        log_debug "System reboot disabled by configuration"
        return 1
    fi

    # Check if we have critical issues to warrant reboot consideration
    if [ "$CRITICAL_ISSUES_COUNT" -eq 0 ]; then
        log_debug "No critical issues - reboot not needed"
        return 1
    fi

    # Track consecutive critical runs
    current_count=1
    if [ -f "$MAINTENANCE_REBOOT_TRACKING_FILE" ]; then
        current_count=$(cat "$MAINTENANCE_REBOOT_TRACKING_FILE" 2>/dev/null || echo "1")
        current_count=$((current_count + 1))
    fi
    echo "$current_count" >"$MAINTENANCE_REBOOT_TRACKING_FILE"

    log_debug "Consecutive critical maintenance runs: $current_count/$MAINTENANCE_REBOOT_THRESHOLD"

    # Check if we've reached reboot threshold
    if [ "$current_count" -ge "$MAINTENANCE_REBOOT_THRESHOLD" ]; then
        # Check reboot cooldown to prevent loops
        reboot_cooldown_file="/tmp/last_maintenance_reboot"
        if [ -f "$reboot_cooldown_file" ]; then
            last_reboot=$(cat "$reboot_cooldown_file" 2>/dev/null || echo "0")
            current_time=$(date +%s)
            time_since_reboot=$((current_time - last_reboot))

            # Require at least 1 hour between reboots
            if [ "$time_since_reboot" -lt 3600 ]; then
                log_warning "Reboot attempted recently (${time_since_reboot}s ago) - skipping (cooldown)"
                return 1
            fi
        fi

        log_error "Critical issues persist after $current_count maintenance runs - scheduling reboot"

        # Reset counter and record reboot time
        echo "0" >"$MAINTENANCE_REBOOT_TRACKING_FILE"
        echo "$(date +%s)" >"$reboot_cooldown_file"

        # Record and notify
        record_action "CRITICAL" "System reboot scheduled" "Persistent critical issues: $CRITICAL_ISSUES_COUNT"
        send_critical_notification "SYSTEM REBOOT" "Rebooting due to persistent maintenance issues after $current_count runs" "2"

        # Schedule reboot in 60 seconds to allow notification
        log_warning "System will reboot in 60 seconds due to persistent critical issues"
        (
            sleep 60
            reboot
        ) &

        return 0
    else
        # Reset counter if we have no critical issues for a run
        if [ "$CRITICAL_ISSUES_COUNT" -eq 0 ]; then
            echo "0" >"$MAINTENANCE_REBOOT_TRACKING_FILE"
            log_debug "No critical issues - reset reboot counter"
        fi
        return 1
    fi
}

# Apply cooldown after fixes
apply_fix_cooldown() {
    if [ "$MAINTENANCE_FIXES_THIS_RUN" -gt 0 ] && [ "$MAINTENANCE_COOLDOWN_AFTER_FIXES" -gt 0 ]; then
        log_info "Applied $MAINTENANCE_FIXES_THIS_RUN fixes - cooling down for ${MAINTENANCE_COOLDOWN_AFTER_FIXES}s"
        sleep "$MAINTENANCE_COOLDOWN_AFTER_FIXES"
    fi
}

# =============================================================================
# MAINTENANCE CHECKS - Add new checks here
# =============================================================================

# Check 1: Missing /var/lock directory (your example issue)
check_var_lock_directory() {
    log_debug "Checking for /var/lock directory existence"

    if [ ! -d "/var/lock" ]; then
        record_action "FOUND" "Missing /var/lock directory" "Create directory with proper permissions"

        if should_attempt_fix "system"; then
            if mkdir -p /var/lock 2>/dev/null; then
                # Set proper permissions for lock directory
                if chmod 755 /var/lock 2>/dev/null; then
                    record_action "FIXED" "Created missing /var/lock directory" "mkdir -p /var/lock && chmod 755"
                    increment_fix_counter
                else
                    record_action "FAILED" "Created /var/lock but failed to set permissions" "chmod 755 /var/lock failed"
                fi
            else
                log_error "Failed to create /var/lock directory"
                record_action "FAILED" "Failed to create /var/lock directory" "mkdir -p /var/lock failed - check filesystem and permissions"
            fi
        fi
    else
        log_debug "/var/lock directory exists"
        record_action "CHECK" "/var/lock directory exists" "No action needed"
    fi
}

# Check 2: Missing /var/run directory
check_var_run_directory() {
    log_debug "Checking for /var/run directory existence"

    if [ ! -d "/var/run" ]; then
        record_action "FOUND" "Missing /var/run directory" "Create directory with proper permissions"

        if should_attempt_fix "system"; then
            if mkdir -p /var/run 2>/dev/null; then
                if chmod 755 /var/run 2>/dev/null; then
                    record_action "FIXED" "Created missing /var/run directory" "mkdir -p /var/run && chmod 755"
                    increment_fix_counter
                else
                    record_action "FAILED" "Created /var/run but failed to set permissions" "chmod 755 /var/run failed"
                fi
            else
                log_error "Failed to create /var/run directory"
                record_action "FAILED" "Failed to create /var/run directory" "mkdir -p /var/run failed - check filesystem and permissions"
            fi
        fi
    else
        log_debug "/var/run directory exists"
        record_action "CHECK" "/var/run directory exists" "No action needed"
    fi
}

# Check 3: Missing critical system directories
check_critical_directories() {
    log_debug "Checking critical system directories"

    # List of critical directories that should exist
    critical_dirs="/tmp /var/log /var/tmp /var/cache /var/lib"

    for dir in $critical_dirs; do
        if [ ! -d "$dir" ]; then
            record_action "FOUND" "Missing critical directory: $dir" "Create directory"

            if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                if mkdir -p "$dir" 2>/dev/null; then
                    chmod 755 "$dir" 2>/dev/null || true
                    record_action "FIXED" "Created missing directory: $dir" "mkdir -p $dir"
                else
                    log_error "Failed to create directory: $dir"
                    record_action "CRITICAL" "Failed to create critical directory: $dir" "Manual intervention required"
                fi
            fi
        else
            log_debug "Directory exists: $dir"
        fi
    done
}

# Check 4: Log file rotation and size management
check_log_file_sizes() {
    log_debug "Checking log file sizes"

    # Find large log files (over 10MB)
    large_logs=$(find /var/log -type f -size +10M 2>/dev/null | head -10 || true)

    if [ -n "$large_logs" ]; then
        echo "$large_logs" | while IFS= read -r large_log; do
            if [ -n "$large_log" ]; then
                size=$(ls -lh "$large_log" 2>/dev/null | awk '{print $5}' || echo "unknown")
                record_action "FOUND" "Large log file: $large_log ($size)" "Truncate or rotate log"

                if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                    # Keep last 1000 lines and truncate
                    if [ -f "$large_log" ]; then
                        temp_file="/tmp/log_truncate_$$"
                        if tail -1000 "$large_log" >"$temp_file" 2>/dev/null; then
                            if mv "$temp_file" "$large_log" 2>/dev/null; then
                                record_action "FIXED" "Truncated large log file: $large_log" "Kept last 1000 lines"
                            else
                                rm -f "$temp_file" 2>/dev/null || true
                            fi
                        else
                            rm -f "$temp_file" 2>/dev/null || true
                        fi
                    fi
                fi
            fi
        done
    else
        log_debug "No large log files found"
    fi
}

# Check 5: Temporary file cleanup
check_temporary_files() {
    log_debug "Checking for old temporary files"

    # Find temporary files older than 7 days
    old_temp_files=$(find /tmp -type f -mtime +7 2>/dev/null | wc -l || echo "0")

    if [ "$old_temp_files" -gt 0 ]; then
        record_action "FOUND" "Found $old_temp_files temporary files older than 7 days" "Remove old temp files"

        if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
            removed_count=$(find /tmp -type f -mtime +7 -delete 2>/dev/null | wc -l || echo "0")
            record_action "FIXED" "Removed old temporary files" "Cleaned up $removed_count old temp files"
        fi
    else
        log_debug "No old temporary files found"
    fi
}

# Check 6: Memory usage monitoring
check_memory_usage() {
    log_debug "Checking memory usage"

    # Get memory usage percentage (rough calculation for busybox)
    if command -v free >/dev/null 2>&1; then
        memory_info=$(free | grep "^Mem:")
        total_mem=$(echo "$memory_info" | awk '{print $2}')
        used_mem=$(echo "$memory_info" | awk '{print $3}')

        if [ "$total_mem" -gt 0 ]; then
            # Calculate percentage using integer arithmetic
            mem_percent=$((used_mem * 100 / total_mem))

            if [ "$mem_percent" -gt 90 ]; then
                record_action "FOUND" "High memory usage: ${mem_percent}%" "Consider restarting memory-intensive processes"

                if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                    # Try to free page cache (safe operation)
                    sync 2>/dev/null || true
                    echo 1 >/proc/sys/vm/drop_caches 2>/dev/null || true
                    record_action "FIXED" "Cleared system caches to free memory" "echo 1 > /proc/sys/vm/drop_caches"
                fi
            else
                log_debug "Memory usage is normal: ${mem_percent}%"
            fi
        fi
    fi
}

# Check 7: Database optimization loop (RUTOS-specific issue)
check_database_optimization_loop() {
    log_debug "Checking for database optimization loop spam"

    # Check for recent database optimization errors in system log
    log_spam_count=0
    if command -v logread >/dev/null 2>&1; then
        # Look for the specific error pattern from the last 5 minutes
        recent_log=$(logread -l 100 2>/dev/null | tail -n 50 || true)
        if [ -n "$recent_log" ]; then
            # Count database optimization errors
            log_spam_count=$(echo "$recent_log" | grep -c "Unable to optimize database\|Failed to restore database\|Unable to reduce max rows" 2>/dev/null || echo "0")
        fi
    fi

    log_debug "Found $log_spam_count database optimization error messages"

    # If we find more than 5 database errors, this indicates a loop
    if [ "$log_spam_count" -ge 5 ]; then
        record_action "FOUND" "Database optimization loop detected" "Found $log_spam_count error messages - services may be stuck"

        if should_attempt_fix "database"; then
            log_info "Attempting to fix database optimization loop"

            # Stop services that might be causing the loop
            services_stopped=""
            for service in nlbwmon ip_block collectd statistics; do
                if pgrep "$service" >/dev/null 2>&1; then
                    log_debug "Stopping service: $service"
                    if /etc/init.d/"$service" stop >/dev/null 2>&1 || killall "$service" >/dev/null 2>&1; then
                        services_stopped="$services_stopped $service"
                        sleep 1
                    fi
                fi
            done

            # Create backup directory
            backup_dir="/tmp/db_maintenance_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir" 2>/dev/null || true

            # Reset problematic databases
            databases_fixed=""
            db_paths="/usr/local/share/nlbwmon/data.db /usr/local/share/ip_block/attempts.db /tmp/dhcp.leases.db"

            for db_path in $db_paths; do
                if [ -f "$db_path" ]; then
                    log_debug "Backing up and resetting database: $db_path"
                    # Backup original
                    cp "$db_path" "$backup_dir/$(basename "$db_path").backup" 2>/dev/null || true
                    # Remove problematic database (will be recreated)
                    if rm -f "$db_path" 2>/dev/null; then
                        databases_fixed="$databases_fixed $(basename "$db_path")"
                    fi
                fi
            done

            # Check and restart ubus if needed
            ubus_restarted=""
            if ! ubus list >/dev/null 2>&1; then
                log_debug "ubus not responding, attempting restart"
                if pidof ubusd >/dev/null; then
                    killall ubusd 2>/dev/null || true
                    sleep 2
                fi
                ubusd >/dev/null 2>&1 &
                sleep 2
                if ubus list >/dev/null 2>&1; then
                    ubus_restarted=" ubus"
                fi
            fi

            # Restart services
            services_restarted=""
            for service in $services_stopped; do
                if /etc/init.d/"$service" start >/dev/null 2>&1; then
                    services_restarted="$services_restarted $service"
                fi
            done

            # Wait and check if loop is resolved
            sleep 10
            new_spam_count=0
            if command -v logread >/dev/null 2>&1; then
                recent_check=$(logread -l 20 2>/dev/null | tail -n 10 || true)
                if [ -n "$recent_check" ]; then
                    new_spam_count=$(echo "$recent_check" | grep -c "Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")
                fi
            fi

            if [ "$new_spam_count" -lt 2 ]; then
                # Success - build detailed action message
                action_details="Reset databases:$databases_fixed. Restarted:$services_restarted$ubus_restarted. Backup: $backup_dir"
                record_action "FIXED" "Database optimization loop resolved" "$action_details"
                increment_fix_counter
                log_success "Database optimization loop appears to be resolved"
            else
                # Still having issues
                record_action "CRITICAL" "Database optimization loop persists after repair attempt" "Manual investigation required - backup saved to $backup_dir"
                log_error "Database loop persists after attempted fix"
            fi
        fi
    else
        log_debug "No database optimization loop detected"
    fi
}

# Check 8: Can't open database spam (user-reported RUTX50 issue)
check_cant_open_database_spam() {
    log_debug "Checking for 'Can't open database' spam issue"

    # Check for recent "Can't open database" errors in system log
    cant_open_errors=0
    if command -v logread >/dev/null 2>&1; then
        # Look for the specific error pattern from recent logs
        recent_log=$(logread -l 100 2>/dev/null | tail -n 50 || true)
        if [ -n "$recent_log" ]; then
            # Count "Can't open database" errors
            cant_open_errors=$(echo "$recent_log" | grep -c "user.err.*Can't open database" 2>/dev/null || echo "0")
        fi
    fi

    log_debug "Found $cant_open_errors 'Can't open database' error messages"

    # If we find more than 5 "Can't open database" errors, this indicates spam
    if [ "$cant_open_errors" -ge 5 ]; then
        record_action "FOUND" "Can't open database spam detected" "Found $cant_open_errors error messages - database corruption likely"

        if should_attempt_fix "database"; then
            log_info "Attempting to fix 'Can't open database' spam using user's proven solution"

            # Stop services that might be causing the issue
            services_stopped=""
            for service in nlbwmon ip_block collectd statistics; do
                if pgrep "$service" >/dev/null 2>&1; then
                    log_debug "Stopping service: $service"
                    if /etc/init.d/"$service" stop >/dev/null 2>&1 || killall "$service" >/dev/null 2>&1; then
                        services_stopped="$services_stopped $service"
                        sleep 1
                    fi
                fi
            done

            # Check /log filesystem usage and clean if critical
            if [ -d "/log" ]; then
                log_usage=$(df /log 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
                log_debug "/log filesystem usage: ${log_usage}%"

                if [ "$log_usage" -gt 80 ]; then
                    log_debug "Cleaning /log filesystem due to high usage and database errors"
                    if rm -rf /log/* 2>/dev/null; then
                        sync
                        log_debug "/log cleaned successfully"
                    fi
                fi

                # Search for databases in /log and recreate small/corrupted ones
                db_list=$(find /log -type f -name "*.db" 2>/dev/null || true)
                databases_fixed=""

                if [ -n "$db_list" ]; then
                    echo "$db_list" | while IFS= read -r db_path; do
                        if [ -f "$db_path" ]; then
                            size=$(stat -c%s "$db_path" 2>/dev/null || echo "0")
                            if [ "$size" -lt 1024 ]; then
                                log_debug "Recreating small database: $db_path (${size} bytes)"
                                if rm -f "$db_path" && dd if=/dev/zero of="$db_path" bs=1 count=0 2>/dev/null && chmod 644 "$db_path"; then
                                    databases_fixed="$databases_fixed $(basename "$db_path")"
                                fi
                            fi
                        fi
                    done
                fi
            fi

            # Check and restart ubus if needed
            ubus_restarted=""
            if ! ubus list >/dev/null 2>&1; then
                log_debug "ubus not responding, attempting restart"
                if pidof ubusd >/dev/null; then
                    killall ubusd 2>/dev/null || true
                    sleep 2
                fi
                ubusd >/dev/null 2>&1 &
                sleep 2
                if ubus list >/dev/null 2>&1; then
                    ubus_restarted=" ubus"
                fi
            fi

            # Restart services
            services_restarted=""
            for service in $services_stopped; do
                if /etc/init.d/"$service" start >/dev/null 2>&1; then
                    services_restarted="$services_restarted $service"
                fi
            done

            # Wait and check if spam is resolved
            sleep 10
            new_cant_open_count=0
            if command -v logread >/dev/null 2>&1; then
                recent_check=$(logread -l 20 2>/dev/null | tail -n 10 || true)
                if [ -n "$recent_check" ]; then
                    new_cant_open_count=$(echo "$recent_check" | grep -c "user.err.*Can't open database" 2>/dev/null || echo "0")
                fi
            fi

            if [ "$new_cant_open_count" -lt 2 ]; then
                # Success - build detailed action message
                action_details="Cleaned /log filesystem. Fixed databases:$databases_fixed. Restarted:$services_restarted$ubus_restarted."
                record_action "FIXED" "'Can't open database' spam resolved" "$action_details"
                increment_fix_counter
                log_success "'Can't open database' spam appears to be resolved"
            else
                # Still having issues
                record_action "CRITICAL" "'Can't open database' spam persists after repair attempt" "Manual investigation required - may need reboot"
                log_error "'Can't open database' spam persists after attempted fix"
            fi
        fi
    else
        log_debug "No 'Can't open database' spam detected"
    fi
}

# Check 9: Network interface issues
check_network_interfaces() {
    log_debug "Checking network interfaces"

    # Check if critical interfaces are up
    if command -v ip >/dev/null 2>&1; then
        # Get list of interfaces that should be up but are down
        down_interfaces=$(ip link show | grep -E "state DOWN" | grep -v "lo:" | awk -F': ' '{print $2}' | head -5 || true)

        if [ -n "$down_interfaces" ]; then
            echo "$down_interfaces" | while IFS= read -r interface; do
                if [ -n "$interface" ]; then
                    record_action "FOUND" "Network interface down: $interface" "Interface may need attention"

                    # Don't automatically bring up interfaces - too risky
                    # Just report the issue for manual review
                fi
            done
        else
            log_debug "All network interfaces appear to be functioning"
        fi
    fi
}

# Check 10: System service health
check_system_services() {
    log_debug "Checking system services"

    # Check critical services
    critical_services="network dnsmasq cron"

    for service in $critical_services; do
        if [ -f "/etc/init.d/$service" ]; then
            # Check if service is running
            if ! /etc/init.d/"$service" status >/dev/null 2>&1; then
                record_action "FOUND" "Service not running: $service" "Restart service"

                if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                    if /etc/init.d/"$service" start >/dev/null 2>&1; then
                        record_action "FIXED" "Restarted service: $service" "/etc/init.d/$service start"
                    else
                        log_error "Failed to restart service: $service"
                        record_action "CRITICAL" "Critical service failed to restart: $service" "Manual intervention required"
                    fi
                fi
            else
                log_debug "Service running: $service"
            fi
        fi
    done
}

# Check 11: Disk space monitoring
check_disk_space() {
    log_debug "Checking disk space usage"

    # Check root filesystem usage
    if command -v df >/dev/null 2>&1; then
        root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

        if [ "$root_usage" -gt 85 ]; then
            record_action "FOUND" "High disk usage on root filesystem: ${root_usage}%" "Clean up disk space"

            if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                # Clean up some common locations
                cleaned=0

                # Clean old kernel logs
                if [ -d "/var/log" ]; then
                    find /var/log -name "*.log.*" -mtime +3 -delete 2>/dev/null && cleaned=1 || true
                fi

                # Clean package cache if it exists
                if [ -d "/var/cache" ]; then
                    find /var/cache -type f -mtime +7 -delete 2>/dev/null && cleaned=1 || true
                fi

                if [ "$cleaned" = "1" ]; then
                    record_action "FIXED" "Cleaned up disk space" "Removed old logs and cache files"
                fi
            fi
        else
            log_debug "Disk space usage is normal: ${root_usage}%"
        fi
    fi
}

# Check 12: Permission issues on critical files
check_critical_permissions() {
    log_debug "Checking permissions on critical files and directories"

    # Critical files/directories and their expected permissions
    check_permission() {
        path="$1"
        expected_perm="$2"
        description="$3"

        if [ -e "$path" ]; then
            current_perm=$(ls -ld "$path" 2>/dev/null | cut -c1-10 || echo "unknown")
            if [ "$current_perm" != "$expected_perm" ]; then
                record_action "FOUND" "Incorrect permissions on $description: $path ($current_perm, expected $expected_perm)" "Fix permissions"

                if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                    # Convert permission string to octal (simplified)
                    case "$expected_perm" in
                        "drwxr-xr-x")
                            chmod 755 "$path" 2>/dev/null && record_action "FIXED" "Fixed permissions on $path" "chmod 755"
                            ;;
                        "drwx------")
                            chmod 700 "$path" 2>/dev/null && record_action "FIXED" "Fixed permissions on $path" "chmod 700"
                            ;;
                        "-rw-r--r--")
                            chmod 644 "$path" 2>/dev/null && record_action "FIXED" "Fixed permissions on $path" "chmod 644"
                            ;;
                    esac
                fi
            fi
        fi
    }

    # Check critical paths
    check_permission "/var/lock" "drwxr-xr-x" "lock directory"
    check_permission "/var/run" "drwxr-xr-x" "run directory"
    check_permission "/tmp" "drwxrwxrwt" "temp directory"
    check_permission "/var/log" "drwxr-xr-x" "log directory"
}

# =============================================================================
# MAIN EXECUTION FUNCTIONS
# =============================================================================

# Run all maintenance checks
run_all_checks() {
    log_step "Starting system maintenance checks"

    # Reset counters
    ISSUES_FIXED_COUNT=0
    ISSUES_FOUND_COUNT=0

    # Run all checks
    check_var_lock_directory
    check_var_run_directory
    check_critical_directories
    check_log_file_sizes
    check_temporary_files
    check_memory_usage
    check_database_optimization_loop
    check_cant_open_database_spam
    check_network_interfaces
    check_system_services
    check_disk_space
    check_critical_permissions

    # Add more checks here in the future

    log_step "System maintenance checks completed"

    # Check if we need to send critical notifications
    if [ "$CRITICAL_ISSUES_COUNT" -ge "$MAINTENANCE_CRITICAL_THRESHOLD" ]; then
        log_warning "Found $CRITICAL_ISSUES_COUNT critical issues that could not be fixed automatically"

        # Prepare notification message
        notification_title="🚨 RUTOS System Maintenance Alert"
        notification_message="CRITICAL: Found $CRITICAL_ISSUES_COUNT issues that require manual intervention on your RUTX50 router.

Summary:
• Critical Issues: $CRITICAL_ISSUES_COUNT
• Total Issues Found: $ISSUES_FOUND_COUNT  
• Issues Fixed: $ISSUES_FIXED_COUNT

Recent critical issues may include:
- Failed directory creation (/var/lock, /var/run)
- Service restart failures
- Filesystem permission problems

Check maintenance log: $MAINTENANCE_LOG

Run 'system-maintenance-rutos.sh check' for detailed analysis."

        send_critical_notification "$notification_title" "$notification_message" "1"
    elif [ "$CRITICAL_ISSUES_COUNT" -gt 0 ]; then
        log_info "Found $CRITICAL_ISSUES_COUNT critical issues (below notification threshold of $MAINTENANCE_CRITICAL_THRESHOLD)"
    fi
}

# Generate maintenance report
generate_report() {
    log_step "Generating maintenance report"

    report_file="/var/log/system-maintenance-report.txt"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >"$report_file" <<EOF
========================================
RUTOS System Maintenance Report
========================================
Generated: $timestamp
Script Version: $SCRIPT_VERSION
Run Mode: $RUN_MODE

SUMMARY:
- Issues Found: $ISSUES_FOUND_COUNT
- Issues Fixed: $ISSUES_FIXED_COUNT
- Critical Issues: $CRITICAL_ISSUES_COUNT

CONFIGURATION:
- Pushover Notifications: $MAINTENANCE_PUSHOVER_ENABLED
- Critical Threshold: $MAINTENANCE_CRITICAL_THRESHOLD
- Notification Cooldown: ${MAINTENANCE_NOTIFICATION_COOLDOWN}s
- Config File: ${CONFIG_FILE:-Not found}

RECENT MAINTENANCE LOG (last 20 entries):
EOF

    if [ -f "$MAINTENANCE_LOG" ]; then
        tail -20 "$MAINTENANCE_LOG" >>"$report_file"
    else
        echo "No maintenance log found" >>"$report_file"
    fi

    cat >>"$report_file" <<EOF

SYSTEM STATUS:
EOF

    # Add system info
    uname -a >>"$report_file" 2>/dev/null || echo "System info unavailable" >>"$report_file"
    echo "" >>"$report_file"

    # Add memory info
    echo "Memory Usage:" >>"$report_file"
    free >>"$report_file" 2>/dev/null || echo "Memory info unavailable" >>"$report_file"
    echo "" >>"$report_file"

    # Add disk usage
    echo "Disk Usage:" >>"$report_file"
    df -h >>"$report_file" 2>/dev/null || echo "Disk info unavailable" >>"$report_file"

    log_success "Maintenance report generated: $report_file"

    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "Report contents:"
        cat "$report_file" | while IFS= read -r line; do
            log_debug "  $line"
        done
    fi
}

# Show usage information
show_usage() {
    cat <<EOF
RUTOS System Maintenance Script v$SCRIPT_VERSION

This script performs automated system maintenance checks and fixes common issues.

Usage: $0 [mode]

Modes:
  auto    - Check for issues and automatically fix them (default)
  check   - Only check for issues, don't fix anything
  fix     - Check for issues and fix them (same as auto)
  report  - Generate a maintenance report
  help    - Show this help message

Environment Variables:
  DEBUG=1   - Enable debug output
  CONFIG_FILE - Override config file path (default: /etc/starlink-config/config.sh)

Configuration:
  The script uses your main Starlink monitoring configuration file for:
  - MAINTENANCE_PUSHOVER_ENABLED (default: uses ENABLE_PUSHOVER_NOTIFICATIONS)
  - MAINTENANCE_PUSHOVER_TOKEN (default: uses PUSHOVER_TOKEN)  
  - MAINTENANCE_PUSHOVER_USER (default: uses PUSHOVER_USER)
  - MAINTENANCE_CRITICAL_THRESHOLD (default: 3 - send notification after 3+ critical issues)
  - MAINTENANCE_NOTIFICATION_COOLDOWN (default: 3600 seconds)

Examples:
  $0                    # Run automatic maintenance
  $0 check              # Check only, don't fix
  $0 report             # Generate report
  DEBUG=1 $0 auto       # Run with debug output

Current Issues Detected:
  - Missing /var/lock directory (qmimux.lock error) ✅ FIXED
  - Database optimization loops (nlbwmon/ip_block spam) ✅ FIXED
  - "Can't open database" spam (user.err messages) ✅ FIXED  
  - Large log files requiring rotation
  - Old temporary files cleanup
  - High memory/disk usage monitoring
  - Service health checking
  - Critical issue notifications via Pushover

The script logs all actions to: $MAINTENANCE_LOG
Critical issues (3+ by default) trigger Pushover notifications if configured.

EOF
}

# Initialize maintenance environment
initialize_maintenance() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$MAINTENANCE_LOG")" 2>/dev/null || true

    # Initialize log file with header
    if [ ! -f "$MAINTENANCE_LOG" ]; then
        echo "# RUTOS System Maintenance Log - Created $(date '+%Y-%m-%d %H:%M:%S')" >"$MAINTENANCE_LOG"
    fi

    # Log start of maintenance run
    echo "" >>"$MAINTENANCE_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [START] System maintenance run - Mode: $RUN_MODE, Version: $SCRIPT_VERSION" >>"$MAINTENANCE_LOG"
}

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

main() {
    log_info "Starting RUTOS System Maintenance v$SCRIPT_VERSION"
    log_info "Run mode: $RUN_MODE"

    # Determine effective mode based on configuration
    determine_effective_mode "$RUN_MODE"

    if [ "$EFFECTIVE_MODE" != "$RUN_MODE" ]; then
        log_info "Effective mode after configuration: $EFFECTIVE_MODE"
    fi

    # Initialize maintenance environment
    initialize_maintenance

    case "$EFFECTIVE_MODE" in
        "auto" | "fix")
            log_info "Running automatic maintenance (check and fix issues)"
            run_all_checks
            apply_fix_cooldown
            generate_report
            consider_system_reboot
            ;;
        "check")
            log_info "Running check-only mode (no fixes applied)"
            run_all_checks
            generate_report
            ;;
        "report")
            log_info "Generating maintenance report"
            generate_report
            ;;
        "help" | "-h" | "--help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown mode: $EFFECTIVE_MODE"
            show_usage
            exit 1
            ;;
    esac

    # Log completion
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [COMPLETE] Maintenance run completed - Found: $ISSUES_FOUND_COUNT, Fixed: $ISSUES_FIXED_COUNT, Critical: $CRITICAL_ISSUES_COUNT" >>"$MAINTENANCE_LOG"

    # Final summary
    log_success "System maintenance completed"
    log_info "Issues found: $ISSUES_FOUND_COUNT"
    log_info "Issues fixed: $ISSUES_FIXED_COUNT"
    if [ "$CRITICAL_ISSUES_COUNT" -gt 0 ]; then
        log_error "Critical issues requiring manual intervention: $CRITICAL_ISSUES_COUNT"
    fi
    log_info "Maintenance log: $MAINTENANCE_LOG"

    if [ "$ISSUES_FOUND_COUNT" -gt 0 ] && [ "$RUN_MODE" = "check" ]; then
        log_warning "Run '$0 fix' to automatically fix the issues found"
    fi
}

# Execute main function with all arguments
main "$@"
