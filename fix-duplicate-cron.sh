#!/bin/sh
# =============================================================================
# CRON CLEANUP SCRIPT - Fix Duplicate Entries
# =============================================================================
# Version: 2.8.0
# This script removes duplicate cron entries created during unified script migration

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034
    CYAN=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

# Main cleanup function
cleanup_duplicate_cron_entries() {
    CRON_FILE="/etc/crontabs/root"

    log_step "Cleaning up duplicate cron entries"

    # Check if cron file exists
    if [ ! -f "$CRON_FILE" ]; then
        log_error "Cron file not found: $CRON_FILE"
        return 1
    fi

    # Create backup
    backup_file="$CRON_FILE.cleanup_backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CRON_FILE" "$backup_file"
    log_info "Backup created: $backup_file"

    # Show current state
    log_step "Current cron entries:"
    grep -E "(starlink_monitor|starlink_logger)" "$CRON_FILE" | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done

    # Create cleaned version
    temp_cron="/tmp/crontab_clean.$$"

    # Remove all starlink entries added by install script (both active and commented)
    grep -v -E "# Starlink (monitor|logger|API check|System maintenance|Auto-update check) - Added by install script" "$CRON_FILE" >"$temp_cron"

    # Also remove commented starlink script lines
    sed -i '/^#\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor.*\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^#\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger.*\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^#0 6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/check_starlink_api.*\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^#0 \*\/6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/system-maintenance-rutos\.sh auto$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^#0 3 \* \* 0 CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/self-update-rutos\.sh --auto-update$/d' "$temp_cron" 2>/dev/null || true

    # Also remove the actual cron lines (both old and new script names)
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor_unified-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger_unified-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^0 6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/check_starlink_api.*\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^0 \*\/6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/system-maintenance-rutos\.sh auto$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^0 3 \* \* 0 CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/self-update-rutos\.sh --auto-update$/d' "$temp_cron" 2>/dev/null || true # Add only the unified script entries
    log_step "Adding unified script entries"
    cat >>"$temp_cron" <<EOF
# Starlink monitor - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor_unified-rutos.sh
# Starlink logger - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_logger_unified-rutos.sh
# Starlink API check - Added by install script $(date +%Y-%m-%d)
0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh
# System maintenance - Added by install script $(date +%Y-%m-%d) - runs every 6 hours to check and fix common issues
0 */6 * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh auto
# Auto-update check - Added by install script $(date +%Y-%m-%d) - enabled by default (notifications only due to "Never" delays)
0 3 * * 0 CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/self-update-rutos.sh --auto-update
EOF

    # Replace the crontab
    if mv "$temp_cron" "$CRON_FILE"; then
        log_info "Crontab cleaned successfully"
    else
        log_error "Failed to update crontab"
        rm -f "$temp_cron" 2>/dev/null || true
        return 1
    fi

    # Show final state
    log_step "Cleaned cron entries:"
    grep -E "(starlink_monitor|starlink_logger|check_starlink_api|system-maintenance|self-update)" "$CRON_FILE" | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done

    log_info "Cleanup completed successfully"
    log_info "Backup available at: $backup_file"
}

# Main execution
main() {
    log_info "Starting cron cleanup for unified scripts migration (v$SCRIPT_VERSION)"

    # Check if we're running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    cleanup_duplicate_cron_entries

    log_info "Cron cleanup completed"
    log_info "You should now have only unified script entries in your crontab"
}

# Execute main function
main "$@"
