#!/bin/sh

# ==============================================================================
# Update Cron Configuration Path Script
#
# This script updates existing cron entries to use the new persistent
# configuration path /etc/starlink-config/config.sh instead of the old
# path in the installation directory.
#
# ==============================================================================

set -e

# Script version
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Color definitions for output formatting (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034
    CYAN=""
    NC=""
fi

print_status() {
    color="$1"
    message="$2"
    printf "${color}%s${NC}\n" "$message"
}

print_status "$BLUE" "╔══════════════════════════════════════════════════════════════════════════╗"
print_status "$BLUE" "║                    CRON CONFIG PATH UPDATER                             ║"
print_status "$BLUE" "║                         Version $SCRIPT_VERSION                                ║"
print_status "$BLUE" "╚══════════════════════════════════════════════════════════════════════════╝"
print_status "" ""

# Check if running on OpenWrt/RUTOS
if [ ! -f "/etc/openwrt_release" ]; then
    print_status "$RED" "❌ Error: This script is designed for OpenWrt/RUTOS systems"
    exit 1
fi

# Get current crontab
temp_cron="/tmp/crontab_current_$$.tmp"
crontab -l >"$temp_cron" 2>/dev/null || touch "$temp_cron"

# Check if we have any old entries
old_entries=$(grep -c "CONFIG_FILE=.*/starlink-monitor/config/config.sh" "$temp_cron" 2>/dev/null || echo "0")

if [ "$old_entries" -eq 0 ]; then
    print_status "$GREEN" "✅ No old cron entries found - crontab is already up to date"
    rm -f "$temp_cron"
    exit 0
fi

print_status "$YELLOW" "📋 Found $old_entries cron entries using old CONFIG_FILE path:"
grep "CONFIG_FILE=.*/starlink-monitor/config/config.sh" "$temp_cron" | while IFS= read -r line; do
    print_status "$YELLOW" "   $line"
done

print_status "" ""
print_status "$BLUE" "🔄 Updating cron entries to use persistent configuration path..."

# Create updated crontab
temp_new_cron="/tmp/crontab_updated_$$.tmp"
sed 's|CONFIG_FILE=.*/starlink-monitor/config/config.sh|CONFIG_FILE=/etc/starlink-config/config.sh|g' "$temp_cron" >"$temp_new_cron"

# Show the changes
print_status "$GREEN" "📋 Updated entries will be:"
grep "CONFIG_FILE=/etc/starlink-config/config.sh" "$temp_new_cron" | while IFS= read -r line; do
    print_status "$GREEN" "   $line"
done

print_status "" ""
printf "Continue with update? [y/N]: "
read -r response

case "$response" in
    [yY] | [yY][eE][sS])
        if crontab "$temp_new_cron" 2>/dev/null; then
            print_status "$GREEN" "✅ Successfully updated crontab"
            print_status "$GREEN" "✅ All cron entries now use persistent configuration path"

            # Restart cron to ensure changes take effect
            /etc/init.d/cron restart >/dev/null 2>&1 || {
                print_status "$YELLOW" "⚠️  Warning: Could not restart cron service"
            }

            print_status "$BLUE" "ℹ️  Cron service restarted to apply changes"
        else
            print_status "$RED" "❌ Failed to update crontab"
            rm -f "$temp_cron" "$temp_new_cron"
            exit 1
        fi
        ;;
    *)
        print_status "$YELLOW" "⏹️  Operation cancelled by user"
        rm -f "$temp_cron" "$temp_new_cron"
        exit 0
        ;;
esac

rm -f "$temp_cron" "$temp_new_cron"
print_status "$GREEN" "✅ Cron configuration update complete"
