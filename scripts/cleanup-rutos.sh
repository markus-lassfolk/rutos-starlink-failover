#!/bin/sh
# Script: cleanup-rutos.sh
# Version: 1.0.0
# Description: Cleanup and undo Starlink Monitor installation artifacts for testing

set -eu

# Standard colors for output (RUTOS compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
NC='\033[0m'

print_status() {
    color="$1"
    shift
    printf "%s%s%s\n" "$color" "$*" "$NC"
}

print_status "$BLUE" "==== Cleanup: Removing Starlink Monitor artifacts ===="

# Comment out cron entries
CRON_FILE="/etc/crontabs/root"
if [ -f "$CRON_FILE" ]; then
    print_status "$YELLOW" "Commenting Starlink cron entries in $CRON_FILE"
    sed -i.bak "/starlink_monitor-rutos.sh\|starlink_logger-rutos.sh\|check_starlink_api/r s/^/# /" "$CRON_FILE" || true
    /etc/init.d/cron restart >/dev/null 2>&1 || true
    print_status "$GREEN" "Cron entries commented"
fi

# Disable and remove auto-restore service
if [ -x "/etc/init.d/starlink-restore" ]; then
    print_status "$YELLOW" "Disabling auto-restoration service"
    /etc/init.d/starlink-restore disable >/dev/null 2>&1 || true
    rm -f /etc/init.d/starlink-restore
    print_status "$GREEN" "Auto-restoration service removed"
fi

# Remove installation directory
INSTALL_DIR="/usr/local/starlink-monitor"
if [ -d "$INSTALL_DIR" ]; then
    print_status "$YELLOW" "Removing installation directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    print_status "$GREEN" "Installation directory removed"
fi

# Remove persistent config and logs
for path in "/etc/starlink-config" "/etc/starlink-logs"; do
    if [ -e "$path" ]; then
        print_status "$YELLOW" "Removing $path"
        rm -rf "$path"
        print_status "$GREEN" "$path removed"
    fi
done

# Remove convenience symlinks
for link in "/root/config.sh" "/root/starlink-monitor"; do
    if [ -L "$link" ] || [ -e "$link" ]; then
        print_status "$YELLOW" "Removing symlink or file: $link"
        rm -f "$link"
        print_status "$GREEN" "$link removed"
    fi
done

print_status "$BLUE" "==== Cleanup complete ===="
