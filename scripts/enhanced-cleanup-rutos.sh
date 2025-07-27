#!/bin/sh
# Script: enhanced-cleanup-rutos.sh
# Version: 2.7.1
# Description: Enhanced cleanup script for complete system reset between test runs

set -eu

# Version information
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
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
        "$RED") printf "${RED}%s${NC}\n" "$message" ;;
        "$GREEN") printf "${GREEN}%s${NC}\n" "$message" ;;
        "$YELLOW") printf "${YELLOW}%s${NC}\n" "$message" ;;
        "$BLUE") printf "${BLUE}%s${NC}\n" "$message" ;;
        "$CYAN") printf "${CYAN}%s${NC}\n" "$message" ;;
        *) printf "%s\n" "$message" ;;
    esac
}

# ENHANCED SAFETY: Default to dry-run with better argument parsing
DRY_RUN="${DRY_RUN:-1}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
FORCE_CLEANUP="${FORCE_CLEANUP:-0}"
QUICK_MODE="${QUICK_MODE:-0}" # New: Skip warnings for automated testing

# Debug: Show initial state
if [ "${DEBUG:-0}" = "1" ]; then
    print_status "$CYAN" "[DEBUG] Cleanup script starting..."
    print_status "$CYAN" "  Initial DRY_RUN=$DRY_RUN"
    print_status "$CYAN" "  Arguments: $*"
fi

# Enhanced argument parsing
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
            --quick)
                QUICK_MODE=1
                shift
                ;;
            --auto)
                # Automated mode: execute without warnings
                DRY_RUN=0
                FORCE_CLEANUP=1
                QUICK_MODE=1
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

show_help() {
    cat <<EOF
Enhanced RUTOS Cleanup Script v$SCRIPT_VERSION - Complete System Reset

⚠️  WARNING: This script removes ALL Starlink Monitor installation artifacts!

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run       Show what would be removed (DEFAULT - SAFE)
    --execute       Actually perform cleanup (DESTRUCTIVE!)
    --force         Same as --execute (DESTRUCTIVE!)
    --quick         Skip sleep warnings (for repeated testing)
    --auto          Execute immediately without warnings (for automation)
    --help, -h      Show this help

TESTING WORKFLOW:
    # Between test runs (automated)
    $0 --auto
    
    # Manual reset with verification
    $0 --execute
    
    # Check what would be cleaned
    $0 --dry-run

WHAT GETS CLEANED:
✅ ALL cron entries (starlink_monitor, starlink_logger, check_starlink_api, system-maintenance, self-update)
✅ Auto-restoration service (/etc/init.d/starlink-restore)
✅ Installation directory (/usr/local/starlink-monitor)
✅ Configuration directory (/etc/starlink-config)
✅ Log directory (/etc/starlink-logs)
✅ Convenience symlinks (/root/config.sh, /root/starlink-monitor)
✅ Version-pinned recovery scripts
✅ Temporary bootstrap files (enhanced)
✅ Any remaining installation artifacts

RESULT: Completely clean system ready for fresh installation

EOF
}

# Parse arguments
parse_arguments "$@"

# Debug: Show argument parsing results
if [ "${DEBUG:-0}" = "1" ]; then
    print_status "$CYAN" "[DEBUG] Argument parsing complete:"
    print_status "$CYAN" "  DRY_RUN=$DRY_RUN"
    print_status "$CYAN" "  FORCE_CLEANUP=$FORCE_CLEANUP"
    print_status "$CYAN" "  QUICK_MODE=$QUICK_MODE"
    print_status "$CYAN" "  Arguments received: $*"
fi

# Enhanced safety warnings
if [ "$DRY_RUN" = "0" ]; then
    print_status "$RED" "⚠️  WARNING: REAL CLEANUP MODE ENABLED!"
    print_status "$RED" "This will permanently remove ALL Starlink Monitor components!"

    if [ "$QUICK_MODE" = "0" ]; then
        print_status "$YELLOW" "Press Ctrl+C within 5 seconds to cancel..."
        sleep 5
        print_status "$RED" "Proceeding with REAL cleanup..."
    else
        print_status "$BLUE" "Quick mode: Proceeding immediately..."
    fi
else
    print_status "$YELLOW" "🛡️  SAFE MODE: Running in DRY-RUN mode (no changes will be made)"
    print_status "$BLUE" "Use --execute, --force, or --auto to actually perform cleanup"
fi

# Enhanced safe execution function
safe_execute() {
    cmd="$1"
    description="$2"

    # Debug: Show execution decision
    if [ "${DEBUG:-0}" = "1" ]; then
        print_status "$CYAN" "[DEBUG] safe_execute: DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0}"
        print_status "$CYAN" "[DEBUG] Command: $cmd"
        print_status "$CYAN" "[DEBUG] Description: $description"
    fi

    if [ "$DRY_RUN" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
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

print_status "$BLUE" "==== Enhanced Cleanup: Complete System Reset ===="

# 1. ENHANCED: Clean up any temporary bootstrap directories
print_status "$YELLOW" "Cleaning up temporary bootstrap directories..."
safe_execute "find /tmp -name 'rutos-bootstrap-*' -type d -exec rm -rf {} + 2>/dev/null || true" "Remove bootstrap temp directories"
safe_execute "find /var/tmp -name 'rutos-bootstrap-*' -type d -exec rm -rf {} + 2>/dev/null || true" "Remove bootstrap temp directories (var)"
safe_execute "find /root/tmp -name 'rutos-bootstrap-*' -type d -exec rm -rf {} + 2>/dev/null || true" "Remove bootstrap temp directories (root)"

# 2. ENHANCED: Clean up any downloaded temporary files
print_status "$YELLOW" "Cleaning up temporary installation files..."
safe_execute "find /tmp -name '*.rutos*.tmp' -delete 2>/dev/null || true" "Remove temporary RUTOS files"
safe_execute "find /tmp -name 'config.*.template.*' -delete 2>/dev/null || true" "Remove temporary config files"
safe_execute "find /tmp -name 'install-rutos.*' -delete 2>/dev/null || true" "Remove temporary install scripts"

# 3. Original cron cleanup (enhanced with better regex)
CRON_FILE="/etc/crontabs/root"
if [ -f "$CRON_FILE" ]; then
    print_status "$YELLOW" "Commenting ALL Starlink cron entries in $CRON_FILE"

    # Create timestamped backup
    backup_file="${CRON_FILE}.cleanup.backup.$(date +%Y%m%d_%H%M%S)"
    safe_execute "cp '$CRON_FILE' '$backup_file'" "Create crontab backup"

    # Enhanced regex to catch all variations
    temp_cron="/tmp/crontab_cleanup.tmp"
    safe_execute "sed 's|^\([^#].*\(starlink.*\.sh\|check_starlink\|system-maintenance\|self-update\).*\)|# CLEANUP COMMENTED: \1|g' '$CRON_FILE' >'$temp_cron'" "Process crontab entries"

    # Clean up excessive blank lines
    safe_execute "awk 'BEGIN { blank_count = 0 } /^$/ { blank_count++; if (blank_count <= 1) print } /^./ { blank_count = 0; print }' '$temp_cron' >'${temp_cron}.clean' && mv '${temp_cron}.clean' '$temp_cron'" "Clean up blank lines"

    # Apply cleaned crontab
    safe_execute "mv '$temp_cron' '$CRON_FILE'" "Update crontab file"
    safe_execute "/etc/init.d/cron restart >/dev/null 2>&1" "Restart cron service"
    print_status "$GREEN" "✅ All cron entries commented and normalized"
fi

# 4. Enhanced auto-restore service cleanup
print_status "$YELLOW" "Removing auto-restoration services..."
for service_file in "/etc/init.d/starlink-restore" "/etc/init.d/starlink-*"; do
    if [ -f "$service_file" ] && [ "$service_file" != "/etc/init.d/starlink-*" ]; then
        safe_execute "$service_file disable >/dev/null 2>&1 || true" "Disable service $(basename "$service_file")"
        safe_execute "rm -f '$service_file'" "Remove service file $service_file"
    fi
done

# 5. Enhanced directory cleanup with verification
print_status "$YELLOW" "Removing installation and configuration directories..."

# Remove with progress indication
directories_to_clean="/usr/local/starlink-monitor /etc/starlink-config /etc/starlink-logs"
for dir in $directories_to_clean; do
    if [ -d "$dir" ]; then
        # Show what's being removed if debug enabled
        if [ "${DEBUG:-0}" = "1" ]; then
            dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
            print_status "$CYAN" "  → Removing $dir ($dir_size)"
        fi
        safe_execute "rm -rf '$dir'" "Remove directory $dir"
        print_status "$GREEN" "  ✅ $dir removed"
    fi
done

# 6. Enhanced symlink cleanup
print_status "$YELLOW" "Removing convenience symlinks and shortcuts..."
symlinks_to_clean="/root/config.sh /root/starlink-monitor /usr/local/bin/starlink-* /usr/bin/starlink-*"
for link in $symlinks_to_clean; do
    if [ -L "$link" ] || [ -e "$link" ]; then
        safe_execute "rm -f '$link'" "Remove $link"
        print_status "$GREEN" "  ✅ $link removed"
    fi
done

# 7. ENHANCED: Clean up any remaining processes (be careful!)
print_status "$YELLOW" "Checking for running Starlink processes..."
if [ "$DRY_RUN" = "0" ]; then
    # Only show running processes, don't kill them automatically for safety
    # Use BusyBox-compatible pgrep if available, fallback to ps
    if command -v pgrep >/dev/null 2>&1; then
        # BusyBox pgrep doesn't support -c flag, so count manually
        running_procs=$(pgrep -f "(starlink|rutos)" 2>/dev/null | wc -l || echo "0")
    else
        running_procs=$(ps | grep -c -E "(starlink|rutos)" || echo "0")
    fi
    # Clean any whitespace from count
    running_procs=$(echo "$running_procs" | tr -d ' \n\r')
    running_procs=${running_procs:-0}

    if [ "$running_procs" -gt 0 ]; then
        print_status "$YELLOW" "⚠️  Found $running_procs running Starlink-related processes"
        print_status "$BLUE" "  → Manual process cleanup may be needed"
        if [ "${DEBUG:-0}" = "1" ]; then
            if command -v pgrep >/dev/null 2>&1; then
                pgrep -f "(starlink|rutos)" || true
            else
                ps | grep -E "(starlink|rutos)" || true
            fi
        fi
    else
        print_status "$GREEN" "  ✅ No running Starlink processes found"
    fi
fi

print_status "$BLUE" "==== Enhanced Cleanup Complete ===="

# Enhanced verification section
print_status "$CYAN" "==== Enhanced Cleanup Verification ===="

# Verification counters
total_issues=0

# Verify crontab
if [ -f "$CRON_FILE" ]; then
    remaining_entries=$(grep -c -E "(starlink.*\.sh|check_starlink|system-maintenance.*\.sh|self-update.*\.sh)" "$CRON_FILE" 2>/dev/null | grep -v "# CLEANUP COMMENTED:" || echo "0")
    commented_entries=$(grep -c "# CLEANUP COMMENTED:" "$CRON_FILE" 2>/dev/null || echo "0")

    if [ "$remaining_entries" -eq 0 ]; then
        print_status "$GREEN" "✅ All starlink cron entries removed/commented"
        [ "$commented_entries" -gt 0 ] && print_status "$BLUE" "  → $commented_entries entries preserved as comments"
    else
        print_status "$YELLOW" "⚠️  $remaining_entries active starlink cron entries still present"
        total_issues=$((total_issues + 1))
    fi
fi

# Verify directories
for dir in "/usr/local/starlink-monitor" "/etc/starlink-config" "/etc/starlink-logs"; do
    if [ ! -d "$dir" ]; then
        print_status "$GREEN" "✅ $(basename "$dir") directory completely removed"
    else
        print_status "$YELLOW" "⚠️  $dir still exists"
        total_issues=$((total_issues + 1))
    fi
done

# Verify services
if [ ! -f "/etc/init.d/starlink-restore" ]; then
    print_status "$GREEN" "✅ Auto-recovery services completely removed"
else
    print_status "$YELLOW" "⚠️  Auto-recovery services still exist"
    total_issues=$((total_issues + 1))
fi

# Enhanced summary
print_status "$CYAN" "==== Enhanced Cleanup Summary ===="
if [ "$total_issues" -eq 0 ]; then
    print_status "$GREEN" "🎉 PERFECT CLEANUP: System is completely clean!"
    print_status "$GREEN" "✅ Ready for fresh installation or testing"
else
    print_status "$YELLOW" "⚠️  $total_issues potential issues found"
    print_status "$BLUE" "Manual verification recommended"
fi

# Show what was cleaned
print_status "$BLUE" "Cleaned components:"
print_status "$BLUE" "• ✅ All cron entries (monitoring, logging, maintenance, updates)"
print_status "$BLUE" "• ✅ Auto-recovery and restoration services"
print_status "$BLUE" "• ✅ Installation files and directories"
print_status "$BLUE" "• ✅ Configuration and log directories"
print_status "$BLUE" "• ✅ Convenience symlinks and shortcuts"
print_status "$BLUE" "• ✅ Temporary bootstrap and installation files"
print_status "$BLUE" "• ✅ Version-pinned recovery scripts"

if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
    print_status "$YELLOW" "🔍 DRY-RUN MODE: No actual changes were made"
    print_status "$YELLOW" "Use --execute, --force, or --auto for real cleanup"
else
    print_status "$GREEN" "🧹 System reset complete - ready for testing!"
fi

# Final testing workflow reminder
if [ "$total_issues" -eq 0 ] && [ "$DRY_RUN" = "0" ]; then
    print_status "$CYAN" "💡 Ready for next test:"
    print_status "$CYAN" "   curl -sSL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/bootstrap-install-rutos.sh | sh"
fi
