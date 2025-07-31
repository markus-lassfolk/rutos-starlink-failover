#!/bin/sh
# Script: fix-cron-entries.sh
# Purpose: Uncomment the "CLEANUP COMMENTED" cron entries and restart cron

set -e

# Configuration
CRON_FILE="/etc/crontabs/root"

# Color definitions
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

print_status() {
    color="$1"
    message="$2"
    printf "${color}%s${NC}\n" "$message"
}

main() {
    print_status "$BLUE" "=== Fixing Commented Cron Entries ==="

    if [ ! -f "$CRON_FILE" ]; then
        print_status "$RED" "Error: Crontab file not found: $CRON_FILE"
        exit 1
    fi

    print_status "$BLUE" "Current crontab content:"
    cat -n "$CRON_FILE"

    # Create backup
    backup_file="$CRON_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CRON_FILE" "$backup_file"
    print_status "$GREEN" "✓ Backup created: $backup_file"

    # Count commented entries before
    commented_before=$(grep -c "# CLEANUP COMMENTED:" "$CRON_FILE" 2>/dev/null || echo "0")
    print_status "$BLUE" "Found $commented_before commented entries"

    if [ "$commented_before" -gt 0 ]; then
        # Uncomment the entries by removing the "# CLEANUP COMMENTED: " prefix
        print_status "$BLUE" "Uncommenting cron entries..."

        # Create temp file with uncommented entries
        temp_cron="/tmp/crontab_fix.tmp"
        sed 's/^# CLEANUP COMMENTED: //' "$CRON_FILE" >"$temp_cron"

        # Replace the crontab
        mv "$temp_cron" "$CRON_FILE"

        # Count entries after
        active_entries=$(grep -c "CONFIG_FILE=.*starlink" "$CRON_FILE" 2>/dev/null || echo "0")

        print_status "$GREEN" "✓ Uncommented $commented_before entries"
        print_status "$GREEN" "✓ Now have $active_entries active starlink cron entries"

        # Restart cron service
        print_status "$BLUE" "Restarting cron service..."
        if /etc/init.d/cron restart >/dev/null 2>&1; then
            print_status "$GREEN" "✓ Cron service restarted successfully"
        else
            print_status "$YELLOW" "⚠ Warning: Could not restart cron service"
        fi

        print_status "$BLUE" "Final crontab content:"
        cat -n "$CRON_FILE"

        print_status "$GREEN" "=== Cron Fix Complete ==="
        print_status "$BLUE" "Active starlink entries:"
        grep -n "CONFIG_FILE=.*starlink" "$CRON_FILE" 2>/dev/null || print_status "$YELLOW" "No active entries found"

    else
        print_status "$YELLOW" "No commented entries found to fix"
    fi
}

# Run main function
main "$@"
