#!/bin/sh
# Script: cleanup-rutos.sh
# Version: 2.5.0
# Description: Cleanup and undo Starlink Monitor installation artifacts for testing

set -eu

# Standard colors for output (RUTOS compatible)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034  # CYAN may not be used but should be defined for consistency

# Version information (auto-updated by update-version.sh)
# Use version for logging
echo "cleanup-rutos.sh v$SCRIPT_VERSION started" >/dev/null 2>&1 || true
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED='[0;31m'
    GREEN='[0;32m'
    YELLOW='[1;33m'
    BLUE='[1;35m'
    CYAN='[0;36m'
    NC='[0m'
else
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

print_status() {
    color="$1"
    message="$2"
    # Use Method 5 format that works in RUTOS (embed variables in format string)
    case "$color" in
        "$RED") printf "${RED}%s${NC}
" "$message" ;;
        "$GREEN") printf "${GREEN}%s${NC}
" "$message" ;;
        "$YELLOW") printf "${YELLOW}%s${NC}
" "$message" ;;
        "$BLUE") printf "${BLUE}%s${NC}
" "$message" ;;
        *) printf "%s
" "$message" ;;
    esac
}

# CRITICAL SAFETY: Default to dry-run mode to prevent accidental cleanup
DRY_RUN="${DRY_RUN:-1}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
FORCE_CLEANUP="${FORCE_CLEANUP:-0}"

# Parse command line arguments for safety
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --execute | --force)
                DRY_RUN=0
                FORCE_CLEANUP=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help and safety information
show_help() {
    cat <<EOF
RUTOS Cleanup Script v$SCRIPT_VERSION - SAFETY FIRST!

⚠️  WARNING: This script removes ALL Starlink Monitor installation artifacts!

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run       Show what would be removed (DEFAULT - SAFE)
    --execute       Actually perform cleanup (DESTRUCTIVE!)
    --force         Same as --execute (DESTRUCTIVE!)
    --help, -h      Show this help

SAFETY FEATURES:
    - Runs in DRY-RUN mode by default (shows what would happen)
    - Requires explicit --execute or --force flag for real cleanup
    - Creates backups before modifying crontab
    - Comprehensive logging of all actions

WHAT GETS REMOVED:
    - All cron entries (starlink_monitor, starlink_logger, check_starlink_api, system-maintenance, self-update)
    - Auto-restoration service (/etc/init.d/starlink-restore)
    - Installation directory (/usr/local/starlink-monitor)
    - Configuration directory (/etc/starlink-config)
    - Log directory (/etc/starlink-logs)
    - Convenience symlinks (/root/config.sh, /root/starlink-monitor)
    - Version-pinned recovery script (/etc/starlink-config/install-pinned-version.sh)

EXAMPLES:
    # See what would be removed (SAFE)
    $0
    $0 --dry-run

    # Actually perform cleanup (DESTRUCTIVE)
    $0 --execute
    $0 --force

EOF
}

# Parse arguments
parse_arguments "$@"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    print_status "$CYAN" "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE, FORCE_CLEANUP=$FORCE_CLEANUP"
fi

# Safety warning for real execution
if [ "$DRY_RUN" = "0" ]; then
    print_status "$RED" "⚠️  WARNING: REAL CLEANUP MODE ENABLED!"
    print_status "$RED" "This will permanently remove ALL Starlink Monitor components!"
    print_status "$YELLOW" "Press Ctrl+C within 5 seconds to cancel..."
    sleep 5
    print_status "$RED" "Proceeding with REAL cleanup..."
else
    print_status "$YELLOW" "🛡️  SAFE MODE: Running in DRY-RUN mode (no changes will be made)"
    print_status "$BLUE" "Use --execute or --force to actually perform cleanup"
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        print_status "$YELLOW" "[DRY-RUN] Would execute: $description"
        if [ "${DEBUG:-0}" = "1" ]; then
            print_status "$CYAN" "[DRY-RUN] Command: $cmd"
        fi
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            print_status "$CYAN" "Executing: $cmd"
        fi
        eval "$cmd"
    fi
}

print_status "$BLUE" "==== Cleanup: Removing Starlink Monitor artifacts ===="

# Comment out cron entries
CRON_FILE="/etc/crontabs/root"
if [ -f "$CRON_FILE" ]; then
    print_status "$YELLOW" "Commenting Starlink cron entries in $CRON_FILE"

    # Create backup
    safe_execute "cp '$CRON_FILE' '${CRON_FILE}.cleanup.backup.$(date +%Y%m%d_%H%M%S)'" "Create crontab backup"

    # Comment out ALL starlink entries and clean up blank lines
    temp_cron="/tmp/crontab_cleanup.tmp"
    safe_execute "sed 's|^\([^#].*\(starlink_monitor-rutos\.sh\|starlink_logger-rutos\.sh\|check_starlink_api\|system-maintenance-rutos\.sh\|self-update-rutos\.sh\).*\)|# CLEANUP COMMENTED: |g' '$CRON_FILE' >'$temp_cron'" "Process crontab entries"

    # Remove excessive blank lines (more than 1 consecutive blank line)
    safe_execute "awk 'BEGIN { blank_count = 0 } /^$/ { blank_count++; if (blank_count <= 1) print } /^./ { blank_count = 0; print }' '$temp_cron' >'${temp_cron}.clean' && mv '${temp_cron}.clean' '$temp_cron'" "Clean up blank lines"

    # Apply the cleaned crontab
    safe_execute "mv '$temp_cron' '$CRON_FILE'" "Update crontab file"
    safe_execute "/etc/init.d/cron restart >/dev/null 2>&1" "Restart cron service"
    print_status "$GREEN" "Cron entries commented and blank lines normalized"
fi

# Disable and remove auto-restore service
if [ -x "/etc/init.d/starlink-restore" ]; then
    print_status "$YELLOW" "Disabling auto-restoration service"
    safe_execute "/etc/init.d/starlink-restore disable >/dev/null 2>&1" "Disable auto-restore service"
    safe_execute "rm -f /etc/init.d/starlink-restore" "Remove auto-restore service file"
    print_status "$GREEN" "Auto-restoration service removed"
fi

# Remove installation directory
INSTALL_DIR="/usr/local/starlink-monitor"
if [ -d "$INSTALL_DIR" ]; then
    print_status "$YELLOW" "Removing installation directory: $INSTALL_DIR"
    safe_execute "rm -rf '$INSTALL_DIR'" "Remove installation directory"
    print_status "$GREEN" "Installation directory removed"
fi

# Remove persistent config and logs (including recovery scripts)
for path in "/etc/starlink-config" "/etc/starlink-logs"; do
    if [ -e "$path" ]; then
        print_status "$YELLOW" "Removing $path"
        # Show what version-pinned recovery scripts will be removed
        if [ "$path" = "/etc/starlink-config" ] && [ -f "$path/install-pinned-version.sh" ]; then
            print_status "$BLUE" "  → Removing version-pinned recovery script"
        fi
        safe_execute "rm -rf '$path'" "Remove $path"
        print_status "$GREEN" "$path removed"
    fi
done

# Remove convenience symlinks
for link in "/root/config.sh" "/root/starlink-monitor"; do
    if [ -L "$link" ] || [ -e "$link" ]; then
        print_status "$YELLOW" "Removing symlink or file: $link"
        safe_execute "rm -f '$link'" "Remove $link"
        print_status "$GREEN" "$link removed"
    fi
done

print_status "$BLUE" "==== Cleanup complete ===="

# Verification section
print_status "$CYAN" "==== Cleanup Verification ===="

# Verify crontab cleanup
if [ -f "$CRON_FILE" ]; then
    remaining_entries=$(grep -c -E "(starlink_monitor-rutos\.sh|starlink_logger-rutos\.sh|check_starlink_api|system-maintenance-rutos\.sh|self-update-rutos\.sh)" "$CRON_FILE" 2>/dev/null || echo "0")
    commented_entries=$(grep -c "# CLEANUP COMMENTED:" "$CRON_FILE" 2>/dev/null || echo "0")

    if [ "$remaining_entries" -eq 0 ]; then
        print_status "$GREEN" "✅ All starlink cron entries removed/commented"
        if [ "$commented_entries" -gt 0 ]; then
            print_status "$BLUE" "  → $commented_entries entries commented (preserved for reference)"
        fi
    else
        print_status "$YELLOW" "⚠️  $remaining_entries active starlink cron entries still present"
        print_status "$BLUE" "  → Manual cleanup may be required"
    fi
else
    print_status "$BLUE" "ℹ️  Cron file not found (expected if completely cleaned)"
fi

# Verify auto-recovery cleanup
if [ ! -f "/etc/init.d/starlink-restore" ]; then
    print_status "$GREEN" "✅ Auto-recovery service completely removed"
else
    print_status "$YELLOW" "⚠️  Auto-recovery service still exists"
fi

# Verify installation directory cleanup
if [ ! -d "/usr/local/starlink-monitor" ]; then
    print_status "$GREEN" "✅ Installation directory completely removed"
else
    print_status "$YELLOW" "⚠️  Installation directory still exists"
fi

# Verify persistent config cleanup
if [ ! -d "/etc/starlink-config" ]; then
    print_status "$GREEN" "✅ Persistent configuration completely removed"
    print_status "$BLUE" "  → Version-pinned recovery scripts also removed"
else
    print_status "$YELLOW" "⚠️  Persistent configuration still exists"
fi

print_status "$CYAN" "==== Summary ===="
print_status "$BLUE" "The following components have been cleaned up:"
print_status "$BLUE" "• Cron entries: starlink_monitor, starlink_logger, check_starlink_api"
print_status "$BLUE" "• System maintenance: system-maintenance-rutos.sh (every 6 hours)"
print_status "$BLUE" "• Auto-updates: self-update-rutos.sh (weekly updates)"
print_status "$BLUE" "• Auto-recovery: /etc/init.d/starlink-restore (firmware upgrade persistence)"
print_status "$BLUE" "• Version-pinned recovery: install-pinned-version.sh"
print_status "$BLUE" "• Installation files: /usr/local/starlink-monitor/"
print_status "$BLUE" "• Configuration: /etc/starlink-config/"
print_status "$BLUE" "• Logs: /etc/starlink-logs/"
print_status "$BLUE" "• Symlinks: /root/config.sh, /root/starlink-monitor"

if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
    print_status "$YELLOW" "🔍 DRY-RUN MODE: No actual changes were made"
    print_status "$YELLOW" "Run without DRY_RUN=1 to perform actual cleanup"
else
    print_status "$GREEN" "🧹 System is now clean - ready for fresh installation or testing"
fi

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
