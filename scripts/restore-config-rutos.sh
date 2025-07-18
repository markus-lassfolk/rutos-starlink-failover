#!/bin/sh
# Script: restore-config-rutos.sh
# Version: 1.0.0
# Description: Restore user configuration from backup after installation

set -e

# Colors for output (busybox compatible)
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

# Installation directory
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"

# Function to print colored output
print_status() {
    color="$1"
    message="$2"
    printf "%b[%s] %s%b\n" "$color" "$(date '+%Y-%m-%d %H:%M:%S')" "$message" "$NC"
}

print_status "$GREEN" "=== Configuration Restoration Utility ==="

# Find the most recent backup
if [ ! -d "$INSTALL_DIR/config" ]; then
    print_status "$RED" "Error: Installation directory not found: $INSTALL_DIR"
    exit 1
fi

# Look for backup files
backup_file=""
if [ $# -gt 0 ]; then
    backup_file="$1"
    if [ ! -f "$backup_file" ]; then
        print_status "$RED" "Error: Specified backup file not found: $backup_file"
        exit 1
    fi
else
    # Find most recent backup
    backup_file=$(find "$INSTALL_DIR/config" -name "config.sh.backup.*" -type f | sort | tail -1)
    if [ -z "$backup_file" ]; then
        print_status "$RED" "Error: No backup files found in $INSTALL_DIR/config"
        print_status "$YELLOW" "Usage: $0 [backup_file_path]"
        exit 1
    fi
fi

print_status "$BLUE" "Using backup file: $backup_file"

# Verify backup file has user settings
has_user_settings=false
for setting in PUSHOVER_TOKEN PUSHOVER_USER MWAN_IFACE MWAN_MEMBER; do
    if grep -q "^${setting}=" "$backup_file" 2>/dev/null; then
        value=$(grep "^${setting}=" "$backup_file" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$value" ] && ! echo "$value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)" 2>/dev/null; then
            has_user_settings=true
            break
        fi
    fi
done

if [ "$has_user_settings" = "false" ]; then
    print_status "$YELLOW" "Warning: Backup file appears to contain only default/placeholder values"
    printf "Continue anyway? (y/N): "
    read -r answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        exit 1
    fi
fi

# Show current vs backup settings
print_status "$BLUE" "Current vs Backup comparison:"
for setting in PUSHOVER_TOKEN PUSHOVER_USER MWAN_IFACE MWAN_MEMBER RUTOS_USERNAME RUTOS_PASSWORD STARLINK_IP; do
    current_value=$(grep "^${setting}=" "$INSTALL_DIR/config/config.sh" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    backup_value=$(grep "^${setting}=" "$backup_file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -n "$backup_value" ]; then
        if [ "$current_value" = "$backup_value" ]; then
            print_status "$GREEN" "  $setting: MATCH"
        else
            # Mask sensitive values for display
            case "$setting" in
                *TOKEN* | *PASSWORD*)
                    display_current=$(echo "$current_value" | sed 's/\(.\{3\}\).*/\1***/')
                    display_backup=$(echo "$backup_value" | sed 's/\(.\{3\}\).*/\1***/')
                    print_status "$YELLOW" "  $setting: DIFFERENT (current: $display_current, backup: $display_backup)"
                    ;;
                *)
                    print_status "$YELLOW" "  $setting: DIFFERENT (current: $current_value, backup: $backup_value)"
                    ;;
            esac
        fi
    fi
done

printf "\nRestore settings from backup? (y/N): "
read -r answer
if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    print_status "$BLUE" "Restoration cancelled"
    exit 0
fi

# Create backup of current config
current_backup="$INSTALL_DIR/config/config.sh.pre-restore.$(date +%Y%m%d_%H%M%S)"
cp "$INSTALL_DIR/config/config.sh" "$current_backup"
print_status "$GREEN" "Current config backed up to: $current_backup"

# Restore settings
temp_config="/tmp/restore_config.tmp"
cp "$INSTALL_DIR/config/config.sh" "$temp_config"

restored_count=0
total_settings=0

# List of all possible settings to restore
all_settings="STARLINK_IP MWAN_IFACE MWAN_MEMBER PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD RUTOS_IP PING_TARGETS PING_COUNT PING_TIMEOUT PING_INTERVAL CHECK_INTERVAL FAIL_COUNT_THRESHOLD RECOVERY_COUNT_THRESHOLD INITIAL_DELAY ENABLE_LOGGING LOG_RETENTION_DAYS ENABLE_PUSHOVER_NOTIFICATIONS ENABLE_SYSLOG SYSLOG_PRIORITY ENABLE_HOTPLUG_NOTIFICATIONS ENABLE_STATUS_LOGGING ENABLE_API_MONITORING ENABLE_PING_MONITORING STARLINK_GRPC_PORT API_CHECK_INTERVAL MWAN3_POLICY MWAN3_RULE NOTIFICATION_COOLDOWN NOTIFICATION_RECOVERY_DELAY ENABLE_DETAILED_LOGGING"

for setting in $all_settings; do
    if grep -q "^${setting}=" "$backup_file" 2>/dev/null; then
        total_settings=$((total_settings + 1))
        backup_value=$(grep "^${setting}=" "$backup_file" | head -1)

        # Skip placeholder values
        if echo "$backup_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
            continue
        fi

        # Replace in current config
        if grep -q "^${setting}=" "$temp_config" 2>/dev/null; then
            if sed -i "s|^${setting}=.*|${backup_value}|" "$temp_config" 2>/dev/null; then
                restored_count=$((restored_count + 1))
                print_status "$GREEN" "✓ Restored: $setting"
            fi
        else
            # Add if not present
            echo "$backup_value" >>"$temp_config"
            restored_count=$((restored_count + 1))
            print_status "$GREEN" "✓ Added: $setting"
        fi
    fi
done

# Apply the restored configuration
if mv "$temp_config" "$INSTALL_DIR/config/config.sh" 2>/dev/null; then
    print_status "$GREEN" "=== Restoration Complete ==="
    print_status "$GREEN" "Settings restored: $restored_count/$total_settings"
    print_status "$BLUE" "Current config backup: $current_backup"
    print_status "$BLUE" "Configuration file: $INSTALL_DIR/config/config.sh"
    print_status "$YELLOW" "Please verify your settings and test the system"
else
    print_status "$RED" "Error: Failed to apply restored configuration"
    print_status "$YELLOW" "Restoring from backup: $current_backup"
    cp "$current_backup" "$INSTALL_DIR/config/config.sh"
    exit 1
fi
