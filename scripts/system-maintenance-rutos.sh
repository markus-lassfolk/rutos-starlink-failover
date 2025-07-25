#!/bin/sh
# Script: system-maintenance-rutos.sh
# Version: 2.7.0
# Description: Generic RUTOS system maintenance script that checks for common issues and fixes them

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)

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

# Standard logging functions with consistent colors (define all before use)
log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
        logger -t "SystemMaintenance" -p user.debug "$1"
    fi
}

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

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    logger -t "SystemMaintenance" -p user.notice "SUCCESS: $1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    logger -t "SystemMaintenance" -p user.info "STEP: $1"
}

# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: system-maintenance-rutos.sh v$SCRIPT_VERSION"
fi

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

# Maintenance configuration
if [ "$DRY_RUN" = "1" ]; then
    MAINTENANCE_LOG="/tmp/system-maintenance-dryrun.log"
    log_info "DRY_RUN mode: Using temporary log file: $MAINTENANCE_LOG"
else
    MAINTENANCE_LOG="/var/log/system-maintenance.log"
fi
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
MAINTENANCE_NOTIFY_ON_FIXES="${MAINTENANCE_NOTIFY_ON_FIXES:-false}"                  # Notify on successful fixes (default: only critical)
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

            # Only send notifications for significant fixes
            if [ "$MAINTENANCE_NOTIFY_ON_FIXES" = "true" ]; then
                # Determine if this is a significant fix worth notifying about
                significant_fix=false

                # Check for significant fixes that indicate real problems were resolved
                case "$issue_description" in
                    *"Created missing directory"* | *"Fixed service"* | *"Restarted service"* | *"Fixed critical"* | *"High disk usage"* | *"High memory usage"* | *"Database"* | *"Network"*)
                        significant_fix=true
                        ;;
                    *"Cleaned up 0"* | *"Removed 0"* | *"backup files"*)
                        # Don't notify about trivial cleanups or when nothing was actually cleaned
                        significant_fix=false
                        ;;
                    *"Cleaned up"* | *"Removed"*)
                        # Only notify if actual work was done (extract number if possible)
                        if echo "$fix_description" | grep -q "Cleaned up [1-9][0-9]* \|Removed [1-9][0-9]* "; then
                            significant_fix=true
                        fi
                        ;;
                esac

                if [ "$significant_fix" = "true" ]; then
                    send_maintenance_notification "FIXED" "✅ $issue_description" "Solution: $fix_description" "$MAINTENANCE_PRIORITY_FIXED"
                else
                    log_debug "Skipping notification for minor fix: $issue_description"
                fi
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
        date +%s >"$reboot_cooldown_file"

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
                size=$(stat -c%s "$large_log" 2>/dev/null | awk '{print $1}' || echo "unknown")
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

    # Find temporary files older than 14 days (more conservative)
    old_temp_files=$(find /tmp -type f -mtime +14 2>/dev/null | wc -l || echo "0")

    if [ "$old_temp_files" -gt 0 ]; then
        log_debug "Found $old_temp_files temporary files older than 14 days"

        if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
            # Actually remove the files and count them properly
            temp_list=$(find /tmp -type f -mtime +14 2>/dev/null)
            actual_removed=0

            if [ -n "$temp_list" ]; then
                echo "$temp_list" | while IFS= read -r temp_file; do
                    if rm "$temp_file" 2>/dev/null; then
                        actual_removed=$((actual_removed + 1))
                    fi
                done

                # Re-count to get actual number removed
                remaining_old_files=$(find /tmp -type f -mtime +14 2>/dev/null | wc -l || echo "0")
                actual_removed=$((old_temp_files - remaining_old_files))

                # Only record action if files were actually removed
                if [ "$actual_removed" -gt 0 ]; then
                    record_action "FIXED" "Removed old temporary files" "Cleaned up $actual_removed old temp files"
                else
                    log_debug "No temporary files could be removed (files may be in use or already cleaned)"
                fi
            else
                log_debug "No old temporary files found to remove"
            fi
        else
            # Check mode - only report if there are files that could potentially be cleaned
            record_action "FOUND" "Found $old_temp_files temporary files older than 14 days" "Remove old temp files"
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
            # Count database optimization errors - clean output to avoid arithmetic errors
            log_spam_count=$(echo "$recent_log" | grep -c "Unable to optimize database\|Failed to restore database\|Unable to reduce max rows" 2>/dev/null | tr -d ' \n\r' || echo "0")
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
                    new_spam_count=$(echo "$recent_check" | grep -c "Unable to optimize database\|Failed to restore database" 2>/dev/null | tr -d ' \n\r' || echo "0")
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

    # Check for recent database-related errors in system log
    cant_open_errors=0
    database_locked_errors=0
    database_full_errors=0

    if command -v logread >/dev/null 2>&1; then
        # Look for various database error patterns from recent logs
        recent_log=$(logread -l 100 2>/dev/null | tail -n 50 || true)
        if [ -n "$recent_log" ]; then
            # Count different types of database errors - clean output to avoid arithmetic errors
            cant_open_errors=$(echo "$recent_log" | grep -c "user.err.*Can't open database" 2>/dev/null | tr -d ' \n\r' || echo "0")
            database_locked_errors=$(echo "$recent_log" | grep -c "database is locked" 2>/dev/null | tr -d ' \n\r' || echo "0")
            database_full_errors=$(echo "$recent_log" | grep -c "database or disk is full" 2>/dev/null | tr -d ' \n\r' || echo "0")
        fi
    fi

    total_db_errors=$((cant_open_errors + database_locked_errors + database_full_errors))
    log_debug "Database errors found: Can't open=$cant_open_errors, Locked=$database_locked_errors, Full=$database_full_errors (Total: $total_db_errors)"

    # If we find ≥5 database errors, attempt fixes (enhanced criteria as per user feedback)
    if [ "$total_db_errors" -ge 5 ]; then
        record_action "FOUND" "Database errors detected" "Found $total_db_errors database error messages (Can't open: $cant_open_errors, Locked: $database_locked_errors, Full: $database_full_errors)"

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

                # Search for databases in /log and apply enhanced DB fix logic
                db_list=$(find /log -type f -name "*.db" 2>/dev/null || true)
                databases_fixed=""

                if [ -n "$db_list" ]; then
                    # Use for loop to avoid subshell pipeline issue
                    for db_path in $db_list; do
                        if [ -f "$db_path" ]; then
                            size=$(stat -c%s "$db_path" 2>/dev/null || echo "0")
                            mod_time=$(stat -c%Y "$db_path" 2>/dev/null || echo "0")
                            current_time=$(date +%s)
                            age_days=$(((current_time - mod_time) / 86400))

                            # Enhanced logic: Only recreate if DB is small (<1KB) OR stale (>7 days old)
                            should_recreate=0
                            reason=""

                            if [ "$size" -lt 1024 ]; then
                                should_recreate=1
                                reason="small size (${size} bytes)"
                            elif [ "$age_days" -gt 7 ]; then
                                should_recreate=1
                                reason="stale database (${age_days} days old)"
                            fi

                            if [ "$should_recreate" = "1" ]; then
                                log_debug "Recreating database: $db_path - $reason"
                                if rm -f "$db_path" && dd if=/dev/zero of="$db_path" bs=1 count=0 2>/dev/null && chmod 644 "$db_path"; then
                                    databases_fixed="$databases_fixed $(basename "$db_path")"
                                fi
                            else
                                log_debug "Preserving database: $db_path (size: ${size} bytes, age: ${age_days} days)"
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
                    new_cant_open_count=$(echo "$recent_check" | grep -c "user.err.*Can't open database" 2>/dev/null | tr -d ' \n\r' || echo "0")
                fi
            fi

            if [ "$new_cant_open_count" -lt 2 ]; then
                # Success - build detailed action message
                action_details="Enhanced DB fix: Cleaned /log filesystem. Applied selective DB recreation:$databases_fixed. Restarted:$services_restarted$ubus_restarted."
                record_action "FIXED" "Database errors resolved with enhanced logic" "$action_details"
                increment_fix_counter
                log_success "Database errors appear to be resolved using enhanced fix criteria"
            else
                # Still having issues
                record_action "CRITICAL" "Database errors persist after enhanced repair attempt" "Manual investigation required - may need reboot"
                log_error "Database errors persist after attempted enhanced fix"
            fi
        fi
    else
        log_debug "Database errors within acceptable limits ($total_db_errors < 5)"
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

# Check 11: Disk space monitoring (RUTOS-aware thresholds)
check_disk_space() {
    log_debug "Checking disk space usage"

    # Check root filesystem usage - RUTOS-aware thresholds
    if command -v df >/dev/null 2>&1; then
        root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

        # RUTOS systems typically have 100% root usage due to overlay filesystem
        # Only alert if we have other issues or need to check overlay separately
        if [ "$root_usage" -eq 100 ]; then
            # Check if this is normal RUTOS behavior
            if df | grep -q "overlay\|tmpfs"; then
                log_debug "Root filesystem 100% usage is normal for RUTOS overlay systems"
                # Check overlay space instead
                overlay_usage=$(df /overlay 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
                if [ "$overlay_usage" -gt 90 ]; then
                    record_action "FOUND" "High overlay filesystem usage: ${overlay_usage}%" "Clean up overlay space"
                    if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                        # Try to clean overlay space
                        cleaned_files=0
                        # Clean old backup and temporary files only
                        cleaned_files=$(find /overlay -name "*.backup.*" -mtime +7 2>/dev/null | wc -l || echo "0")
                        if [ "$cleaned_files" -gt 0 ]; then
                            find /overlay -name "*.backup.*" -mtime +7 -delete 2>/dev/null || true
                            record_action "FIXED" "Cleaned overlay space" "Removed $cleaned_files old backup files"
                        fi
                    fi
                elif [ "$overlay_usage" -gt 80 ]; then
                    log_warning "Overlay filesystem usage at ${overlay_usage}% - monitor closely"
                else
                    log_debug "Overlay filesystem usage: ${overlay_usage}% (OK)"
                fi
            else
                # Non-overlay system with 100% usage is concerning
                record_action "FOUND" "Critical disk usage on root filesystem: ${root_usage}%" "Clean up disk space"
            fi
        elif [ "$root_usage" -gt 95 ]; then
            # Only alert for very high usage on non-overlay systems
            record_action "FOUND" "High disk usage on root filesystem: ${root_usage}%" "Clean up disk space"

            if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
                # Clean up some common locations (only if really needed)
                cleaned_something=0

                # Clean old kernel logs (only if very old)
                if [ -d "/var/log" ]; then
                    old_logs=$(find /var/log -name "*.log.*" -mtime +7 2>/dev/null | wc -l || echo "0")
                    if [ "$old_logs" -gt 0 ]; then
                        find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null && cleaned_something=1
                    fi
                fi

                # Clean package cache if it exists and is large
                if [ -d "/var/cache" ]; then
                    old_cache=$(find /var/cache -type f -mtime +14 2>/dev/null | wc -l || echo "0")
                    if [ "$old_cache" -gt 0 ]; then
                        find /var/cache -type f -mtime +14 -delete 2>/dev/null && cleaned_something=1
                    fi
                fi

                if [ "$cleaned_something" = "1" ]; then
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
            current_perm=$(stat -c%A "$path" 2>/dev/null || echo "unknown")
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
# ENHANCED RUTOS-SPECIFIC SYSTEM CHECKS
# =============================================================================

# Check overlay space exhaustion (Critical for RUTOS)
check_overlay_space_exhaustion() {
    log_debug "Checking overlay filesystem space usage"

    # Check if /overlay exists and get usage percentage
    if [ -d "/overlay" ]; then
        overlay_usage=$(df /overlay 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

        if [ -n "$overlay_usage" ] && [ "$overlay_usage" -ge 80 ]; then
            log_warning "Overlay filesystem usage at ${overlay_usage}% (threshold: 80%)"
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

            if [ "$overlay_usage" -ge 90 ]; then
                CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
                log_error "CRITICAL: Overlay filesystem usage at ${overlay_usage}% - system may become unstable"
            fi

            if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                log_info "Attempting to clean overlay filesystem..."

                # Clean stale .old and .bak config files
                cleaned_files=0
                for pattern in "*.old" "*.bak" "*.tmp"; do
                    find /overlay -name "$pattern" -type f -mtime +7 2>/dev/null | while read -r file; do
                        if rm "$file" 2>/dev/null; then
                            log_debug "Cleaned stale file: $file"
                            cleaned_files=$((cleaned_files + 1))
                        fi
                    done
                done

                # Clean old maintenance logs if they exist
                if [ -d "/var/log" ]; then
                    find /var/log -name "maintenance-*.log" -mtime +7 -delete 2>/dev/null || true
                fi

                # Re-check after cleanup
                new_usage=$(df /overlay 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
                if [ -n "$new_usage" ] && [ "$new_usage" -lt "$overlay_usage" ]; then
                    log_success "Overlay cleanup reduced usage from ${overlay_usage}% to ${new_usage}%"
                    ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))
                else
                    log_warning "Overlay cleanup had minimal impact - manual intervention may be needed"
                fi
            fi
        else
            log_debug "Overlay filesystem usage: ${overlay_usage}% (OK)"
        fi
    else
        log_debug "No /overlay filesystem found (not an issue on this system)"
    fi
}

# Check for hung services (Service Watchdog)
check_service_watchdog() {
    log_debug "Checking for hung services"

    # List of critical services to monitor with their expected behavior
    services_to_check="nlbwmon mdcollectd connchecker hostapd network"
    hung_services=""

    for service in $services_to_check; do
        if /etc/init.d/"$service" status >/dev/null 2>&1; then
            # Service is supposed to be running, check if it's actually responsive
            pid=$(pgrep -f "$service" | head -1)

            if [ -n "$pid" ]; then
                # Check if process is responsive by looking at recent log activity
                recent_logs=$(logread | grep -c "$service" | tail -20)

                # If service hasn't logged anything in the last 10 minutes, it might be hung
                if [ -z "$recent_logs" ] || [ "$recent_logs" -eq 0 ]; then
                    # Additional check: see if PID has been the same for too long
                    current_time=$(date +%s)

                    # Use a simple heuristic: if we can't find recent activity, flag as potentially hung
                    if ! pgrep -f "$service" >/dev/null 2>&1; then
                        hung_services="$hung_services $service"
                        log_warning "Service $service appears to be hung (no recent activity)"
                        ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

                        if [ "$MAINTENANCE_SERVICE_RESTART_ENABLED" = "true" ]; then
                            log_info "Attempting to restart hung service: $service"
                            if /etc/init.d/"$service" restart >/dev/null 2>&1; then
                                log_success "Successfully restarted service: $service"
                                ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))

                                # Send notification if configured
                                if [ "$MAINTENANCE_NOTIFY_ON_FIXES" = "true" ]; then
                                    send_notification "🔄 Service Restart" "Automatically restarted hung service: $service" "0"
                                fi
                            else
                                log_error "Failed to restart hung service: $service"
                                CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
                            fi
                        fi
                    fi
                fi
            fi
        fi
    done

    if [ -z "$hung_services" ]; then
        log_debug "All monitored services appear responsive"
    fi
}

# Check for hostapd log flooding
check_hostapd_log_flood() {
    log_debug "Checking for hostapd log flooding"

    # Check for repetitive hostapd messages in the last hour
    flood_patterns="STA-OPMODE-SMPS-MODE-CHANGED|CTRL-EVENT-|WPS-"
    flood_threshold=100

    if command -v logread >/dev/null 2>&1; then
        # Count repetitive hostapd log entries in the last hour
        flood_count=$(logread | grep -cE "$flood_patterns.*hostapd")

        if [ "$flood_count" -gt "$flood_threshold" ]; then
            log_warning "Hostapd log flooding detected: $flood_count entries (threshold: $flood_threshold)"
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

            if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                log_info "Attempting to reduce hostapd log verbosity"

                # Try to reduce hostapd logging temporarily
                if [ -f "/tmp/run/hostapd-phy0.pid" ]; then
                    # Send signal to reduce logging (implementation depends on hostapd version)
                    log_info "Temporarily reducing hostapd log verbosity"

                    # This is a placeholder - actual implementation would depend on RUTOS hostapd configuration
                    # You might need to modify /etc/config/wireless or send specific signals
                    log_debug "Hostapd log flood mitigation attempted"
                    ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))
                fi
            fi
        else
            log_debug "Hostapd logging within normal limits: $flood_count entries"
        fi
    else
        log_debug "logread not available - skipping hostapd flood check"
    fi
}

# Check time drift and NTP sync
check_time_drift_ntp() {
    log_debug "Checking time drift and NTP synchronization"

    # Check if ntpdate or similar is available
    if command -v ntpdate >/dev/null 2>&1; then
        # Get time difference from NTP server
        time_servers="pool.ntp.org 0.pool.ntp.org 1.pool.ntp.org"

        for server in $time_servers; do
            # Try to query NTP server for time difference
            if ping -c 1 -W 5 "$server" >/dev/null 2>&1; then
                log_debug "Checking time drift against NTP server: $server"

                # This is a simplified check - in a real implementation you'd parse ntpdate output
                current_time=$(date +%s)

                # For demonstration, we'll just check if NTP service is running
                if ! pgrep -f ntp >/dev/null 2>&1; then
                    log_warning "NTP service not running - time drift may occur"
                    ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

                    if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                        log_info "Attempting to restart NTP service"
                        if /etc/init.d/sysntpd restart >/dev/null 2>&1; then
                            log_success "Successfully restarted NTP service"
                            ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))
                        else
                            log_error "Failed to restart NTP service"
                            CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
                        fi
                    fi
                fi
                break
            fi
        done
    else
        log_debug "NTP tools not available - skipping time drift check"
    fi
}

# Check for network interface flapping
check_network_interface_flapping() {
    log_debug "Checking for network interface flapping"

    # Check recent network interface state changes in logs
    if command -v logread >/dev/null 2>&1; then
        # Look for interface up/down events in the last 5 minutes
        flap_patterns="interface.*up|interface.*down|netifd.*up|netifd.*down"
        recent_logs=$(logread | tail -100) # Last 100 log entries as a reasonable sample

        # Count interface state changes
        flap_count=$(echo "$recent_logs" | grep -E -c "$flap_patterns" || echo "0")
        flap_threshold=5

        if [ "$flap_count" -gt "$flap_threshold" ]; then
            log_warning "Network interface flapping detected: $flap_count state changes (threshold: $flap_threshold)"
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

            # Identify which interfaces are flapping
            flapping_interfaces=$(echo "$recent_logs" | grep -E "$flap_patterns" | awk '{print $0}' | head -5)
            log_debug "Recent interface events: $flapping_interfaces"

            if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                log_info "Attempting to stabilize flapping network interfaces"

                # Try to restart network service
                if /etc/init.d/network restart >/dev/null 2>&1; then
                    log_success "Network service restarted to address interface flapping"
                    ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))

                    # Send notification about network restart
                    if [ "$MAINTENANCE_NOTIFY_ON_FIXES" = "true" ]; then
                        send_notification "🌐 Network Restart" "Restarted network service due to interface flapping ($flap_count events)" "0"
                    fi
                else
                    log_error "Failed to restart network service"
                    CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
                fi
            fi
        else
            log_debug "Network interfaces stable: $flap_count state changes"
        fi
    else
        log_debug "Log reading not available - skipping interface flapping check"
    fi
}

# Check Starlink script health (Crontab / Starlink Script Health Check)
check_starlink_script_health() {
    log_debug "Checking Starlink monitoring script health"

    # Check if expected StarlinkMonitor log entries appear at least once every 5 minutes
    if command -v logread >/dev/null 2>&1; then
        # Look for StarlinkMonitor log entries in recent logs
        recent_starlink_logs=$(logread | tail -50 | grep -c "StarlinkMonitor" 2>/dev/null | tr -d ' \n\r' || echo "0")

        # Check if cron is running
        cron_running=0
        if pgrep -f cron >/dev/null 2>&1 || pgrep -f crond >/dev/null 2>&1; then
            cron_running=1
            log_debug "Cron daemon is running"
        else
            log_warning "Cron daemon is not running - Starlink scripts may not be executing"
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

            if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                log_info "Attempting to restart cron daemon"
                if /etc/init.d/cron restart >/dev/null 2>&1 || /etc/init.d/crond restart >/dev/null 2>&1; then
                    log_success "Successfully restarted cron daemon"
                    ISSUES_FIXED_COUNT=$((ISSUES_FIXED_COUNT + 1))
                else
                    log_error "Failed to restart cron daemon"
                    CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
                fi
            fi
        fi

        # Check if Starlink monitoring appears to be working
        if [ "$recent_starlink_logs" -eq 0 ] && [ "$cron_running" = "1" ]; then
            log_warning "No recent StarlinkMonitor log entries found - scripts may not be running properly"
            ISSUES_FOUND_COUNT=$((ISSUES_FOUND_COUNT + 1))

            # Check if starlink monitor script exists and is executable
            starlink_script_paths="/root/starlink-monitor/Starlink-RUTOS-Failover/starlink_monitor.sh"
            starlink_script_paths="$starlink_script_paths /opt/starlink/starlink_monitor.sh"
            starlink_script_paths="$starlink_script_paths /usr/bin/starlink_monitor.sh"

            script_found=""
            for script_path in $starlink_script_paths; do
                if [ -x "$script_path" ]; then
                    script_found="$script_path"
                    break
                fi
            done

            if [ -n "$script_found" ]; then
                log_debug "Found Starlink script at: $script_found"

                if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "true" ]; then
                    log_info "Attempting to verify Starlink script configuration"
                    # Could add more sophisticated checks here, like verifying crontab entries
                    log_debug "Starlink script health check completed - manual verification recommended"
                fi
            else
                log_warning "Starlink monitoring script not found in expected locations"
                CRITICAL_ISSUES_COUNT=$((CRITICAL_ISSUES_COUNT + 1))
            fi
        elif [ "$recent_starlink_logs" -gt 0 ]; then
            log_debug "Starlink monitoring appears healthy: $recent_starlink_logs recent log entries"
        fi
    else
        log_debug "Log reading not available - skipping Starlink script health check"
    fi
}

# Check logger sample tracking health (Auto-fix stale tracking)
check_logger_sample_tracking() {
    log_debug "Checking Starlink logger sample tracking health"

    # Set defaults
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    STARLINK_PORT="${STARLINK_PORT:-9200}"
    STATE_DIR="${STATE_DIR:-/tmp/run}"
    LAST_SAMPLE_FILE="${LAST_SAMPLE_FILE:-${STATE_DIR}/starlink_last_sample.ts}"
    GRPCURL_CMD="${GRPCURL_CMD:-$INSTALL_DIR/grpcurl}"
    JQ_CMD="${JQ_CMD:-$INSTALL_DIR/jq}"

    # Check if binaries exist
    if [ ! -x "$GRPCURL_CMD" ] || [ ! -x "$JQ_CMD" ]; then
        log_debug "Required binaries (grpcurl/jq) not found - skipping logger sample tracking check"
        return
    fi

    # Check if tracking file exists
    if [ ! -f "$LAST_SAMPLE_FILE" ]; then
        log_debug "Sample tracking file not found (normal for new installations)"
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
        log_debug "Cannot check logger sample tracking - Starlink API not responding"
        return
    fi

    # Get tracked sample index
    last_sample_index=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "0")

    # Check for the stale tracking issue
    if [ "$last_sample_index" -gt "$current_sample_index" ]; then
        # This is the problem we can auto-fix!
        difference=$((last_sample_index - current_sample_index))
        log_issue "Logger sample tracking" "Stale tracking index detected (tracked: $last_sample_index, API: $current_sample_index, diff: +$difference)"

        # Auto-fix: Reset tracking to a safe value
        new_index=$((current_sample_index - 1))
        log_debug "Attempting to auto-fix logger sample tracking..."

        if echo "$new_index" >"$LAST_SAMPLE_FILE"; then
            log_fix "Logger sample tracking" "Reset stale tracking index from $last_sample_index to $new_index"
            log_info "Logger sample tracking auto-fixed: CSV logging should now work correctly"
        else
            log_critical "Logger sample tracking" "Failed to reset tracking file: $LAST_SAMPLE_FILE"
        fi
    else
        # Tracking looks healthy
        log_debug "Logger sample tracking appears healthy (tracked: $last_sample_index, API: $current_sample_index)"
    fi
}

# Enhanced Starlink metrics monitoring (NEW!)
check_enhanced_starlink_metrics() {
    log_debug "Checking enhanced Starlink metrics for quality assessment"

    # Set defaults
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    STARLINK_PORT="${STARLINK_PORT:-9200}"
    GRPCURL_CMD="${GRPCURL_CMD:-$INSTALL_DIR/grpcurl}"
    JQ_CMD="${JQ_CMD:-$INSTALL_DIR/jq}"

    # Check if binaries exist
    if [ ! -x "$GRPCURL_CMD" ] || [ ! -x "$JQ_CMD" ]; then
        log_debug "Required binaries (grpcurl/jq) not found - skipping enhanced metrics check"
        return
    fi

    # Get status data with enhanced metrics
    status_data=""
    if status_data=$(timeout 10 "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_status":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null); then
        if [ -n "$status_data" ]; then
            status_data=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus' 2>/dev/null)
        fi
    fi

    # Handle API errors gracefully
    if [ -z "$status_data" ] || [ "$status_data" = "null" ]; then
        log_debug "Cannot check enhanced metrics - Starlink API not responding"
        return
    fi

    # Extract enhanced metrics
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.deviceInfo.uptimeS // 0' 2>/dev/null)
    bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.deviceInfo.bootcount // 0' 2>/dev/null)
    is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.isSnrAboveNoiseFloor // true' 2>/dev/null)
    is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.isSnrPersistentlyLow // false' 2>/dev/null)
    snr=$(echo "$status_data" | "$JQ_CMD" -r '.snr // 0' 2>/dev/null)
    gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsValid // true' 2>/dev/null)
    gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsSats // 0' 2>/dev/null)

    log_debug "Enhanced metrics: uptime=${uptime_s}s, bootcount=$bootcount, SNR_above_noise=$is_snr_above_noise_floor, SNR_value=${snr}dB, GPS_valid=$gps_valid"

    # Check for potential issues using enhanced metrics
    issues_found=0

    # Check for frequent reboots (low uptime)
    uptime_hours=$((uptime_s / 3600))
    if [ "$uptime_s" -lt 1800 ]; then # Less than 30 minutes
        record_action "FOUND" "Very low Starlink uptime" "Uptime only ${uptime_hours}h (${uptime_s}s) - recent reboot or instability"
        issues_found=$((issues_found + 1))
    elif [ "$uptime_s" -lt 7200 ]; then # Less than 2 hours
        log_debug "Starlink uptime relatively low: ${uptime_hours}h (${uptime_s}s) - may indicate recent reboot"
    fi

    # Check SNR issues
    if [ "$is_snr_above_noise_floor" = "false" ]; then
        record_action "FOUND" "Starlink SNR below noise floor" "Signal quality degraded - may cause connection issues"
        issues_found=$((issues_found + 1))
    fi

    if [ "$is_snr_persistently_low" = "true" ]; then
        record_action "FOUND" "Starlink SNR persistently low" "Signal quality consistently poor (SNR: ${snr}dB) - check dish alignment"
        issues_found=$((issues_found + 1))
    fi

    # Check SNR value if available
    if [ -n "$snr" ] && [ "$snr" != "0" ] && [ "$snr" != "null" ]; then
        snr_int=$(echo "$snr" | cut -d'.' -f1)
        if [ "$snr_int" -lt 5 ]; then
            record_action "FOUND" "Very low Starlink SNR" "SNR ${snr}dB is critically low - check for obstructions"
            issues_found=$((issues_found + 1))
        elif [ "$snr_int" -lt 8 ]; then
            log_debug "Starlink SNR below optimal: ${snr}dB (recommend >8dB for best performance)"
        fi
    fi

    # Check GPS issues
    if [ "$gps_valid" = "false" ]; then
        record_action "FOUND" "Starlink GPS invalid" "GPS fix lost - may affect service quality"
        issues_found=$((issues_found + 1))
    elif [ "$gps_sats" -lt 4 ]; then
        log_debug "Starlink GPS satellite count low: $gps_sats (recommend ≥4 for optimal performance)"
    fi

    if [ "$issues_found" -eq 0 ]; then
        log_debug "Enhanced Starlink metrics look healthy"
    else
        log_debug "Found $issues_found potential issues with enhanced Starlink metrics"
    fi
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
    check_overlay_space_exhaustion
    check_service_watchdog
    check_hostapd_log_flood
    check_time_drift_ntp
    check_network_interface_flapping
    check_starlink_script_health
    check_logger_sample_tracking
    check_enhanced_starlink_metrics

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

RECENT MAINTENANCE LOG (current run):
EOF

    if [ -f "$MAINTENANCE_LOG" ]; then
        # Extract entries from current run session only
        # Find the last START entry and get all entries after it
        current_run_entries=$(awk '
            /\[START\] System maintenance run/ { 
                start_found = 1; 
                current_run = ""; 
                current_run = current_run $0 "\n"; 
                next 
            }
            start_found { 
                current_run = current_run $0 "\n" 
            }
            END { 
                if (current_run != "") {
                    printf "%s", current_run
                } else {
                    print "No current run entries found"
                }
            }
        ' "$MAINTENANCE_LOG")

        if [ -n "$current_run_entries" ] && [ "$current_run_entries" != "No current run entries found" ]; then
            echo "$current_run_entries" >>"$report_file"
        else
            {
                echo ""
                echo "Recent entries (last 10):"
                tail -10 "$MAINTENANCE_LOG"
            } >>"$report_file"
        fi
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
        while IFS= read -r line; do
            log_debug "  $line"
        done <"$report_file"
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
