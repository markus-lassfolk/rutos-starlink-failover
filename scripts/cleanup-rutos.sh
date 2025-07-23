#!/bin/sh
# Script: cleanup-rutos.sh
# Version: 2.4.12
# Description: Cleanup and undo Starlink Monitor installation artifacts for testing

set -eu

# Standard colors for output (RUTOS compatible)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034  # CYAN may not be used but should be defined for consistency

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Use version for logging
echo "cleanup-rutos.sh v$SCRIPT_VERSION started" >/dev/null 2>&1 || true
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
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
        "$RED") printf "${RED}%s${NC}\n" "$message" ;;
        "$GREEN") printf "${GREEN}%s${NC}\n" "$message" ;;
        "$YELLOW") printf "${YELLOW}%s${NC}\n" "$message" ;;
        "$BLUE") printf "${BLUE}%s${NC}\n" "$message" ;;
        *) printf "%s\n" "$message" ;;
    esac
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    print_status "$CYAN" "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
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

    # Comment out starlink entries and clean up blank lines
    temp_cron="/tmp/crontab_cleanup.tmp"
    safe_execute "sed 's|^\([^#].*\(starlink_monitor-rutos\.sh\|starlink_logger-rutos\.sh\|check_starlink_api\).*\)|# CLEANUP COMMENTED: \1|g' '$CRON_FILE' >'$temp_cron'" "Process crontab entries"

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

# Remove persistent config and logs
for path in "/etc/starlink-config" "/etc/starlink-logs"; do
    if [ -e "$path" ]; then
        print_status "$YELLOW" "Removing $path"
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
