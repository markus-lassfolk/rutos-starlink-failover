#!/bin/sh
# Debug script to manually run cron configuration
# Extracted from install-rutos.sh for debugging purposes

set -e

# Debug mode for verbose output

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
DEBUG="${DEBUG:-1}"

# Configuration from install-rutos.sh
INSTALL_DIR="/usr/local/starlink-monitor"
CRON_FILE="/etc/crontabs/root"

# Color definitions for output
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

# Logging functions
print_status() {
    color="$1"
    message="$2"
    printf "${color}%s${NC}\n" "$message"
}

debug_msg() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${BLUE}[DEBUG] %s${NC}\n" "$1"
    fi
}

# Configure cron jobs - exact copy from install-rutos.sh
configure_cron() {
    print_status "$BLUE" "=== DEBUGGING CRON CONFIGURATION ==="
    print_status "$BLUE" "Configuring cron jobs..."

    # Show current crontab status
    print_status "$BLUE" "Current crontab content:"
    if [ -f "$CRON_FILE" ]; then
        cat -n "$CRON_FILE"
    else
        print_status "$YELLOW" "No crontab file exists at $CRON_FILE"
    fi

    # Create backup of existing crontab
    if [ -f "$CRON_FILE" ]; then
        backup_file="$CRON_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CRON_FILE" "$backup_file"
        print_status "$GREEN" "✓ Existing crontab backed up to: $backup_file"
    fi

    # Create the cron file if it doesn't exist
    if [ ! -f "$CRON_FILE" ]; then
        touch "$CRON_FILE"
        print_status "$BLUE" "Created new crontab file: $CRON_FILE"
    fi

    # Remove any existing entries added by this install script to prevent duplicates
    # Only remove entries that match our exact pattern (default install script entries)
    if [ -f "$CRON_FILE" ]; then
        debug_msg "Cleaning up previous install script entries"

        # Create temp file for clean crontab
        temp_cron="/tmp/crontab_clean.tmp"

        # Remove lines that match our install script patterns (both old and new)
        # Look for the specific comment markers and the exact default entries
        grep -v -E "# Starlink (monitoring system|monitor|logger|API check|System maintenance|Auto-update check) - Added by install script" "$CRON_FILE" >"$temp_cron" || true

        # Remove the exact default entries (in case comment is missing)
        # Handle both old and new script names
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor_unified-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger_unified-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^0 6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/check_starlink_api.*\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^0 \*\/6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/system-maintenance-rutos\.sh auto$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^0 3 \* \* 0 CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/self-update-rutos\.sh --auto-update$/d' "$temp_cron" 2>/dev/null || true

        # Also clean up any previously commented entries from old install script behavior
        sed -i '/^# COMMENTED BY INSTALL SCRIPT.*starlink/d' "$temp_cron" 2>/dev/null || true

        # Remove excessive blank lines (more than 1 consecutive blank line)
        # This keeps single blank lines for readability but removes excessive gaps
        debug_msg "Removing excessive blank lines from crontab"
        awk '
        BEGIN { blank_count = 0 }
        /^$/ { 
            blank_count++
            if (blank_count <= 1) print
        }
        /^./ { 
            blank_count = 0
            print 
        }
        ' "$temp_cron" >"${temp_cron}.clean" && mv "${temp_cron}.clean" "$temp_cron"

        # Replace the crontab with cleaned version
        if mv "$temp_cron" "$CRON_FILE" 2>/dev/null; then
            debug_msg "Crontab cleaned successfully and blank lines normalized"
        else
            # If move failed, ensure we don't lose the original
            debug_msg "Failed to update crontab, preserving original"
            rm -f "$temp_cron" 2>/dev/null || true
        fi
    fi

    print_status "$BLUE" "Crontab after cleanup:"
    cat -n "$CRON_FILE"

    # Check if our scripts already have cron entries (check each script individually)
    existing_monitor=$(grep -c "starlink_monitor_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_logger=$(grep -c "starlink_logger_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_api_check=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_maintenance=$(grep -c "system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    # Clean any whitespace/newlines from the counts (fix for RUTOS busybox grep -c behavior)
    existing_monitor=$(echo "$existing_monitor" | tr -d '\n\r' | sed 's/[^0-9]//g')
    existing_logger=$(echo "$existing_logger" | tr -d '\n\r' | sed 's/[^0-9]//g')
    existing_api_check=$(echo "$existing_api_check" | tr -d '\n\r' | sed 's/[^0-9]//g')
    existing_maintenance=$(echo "$existing_maintenance" | tr -d '\n\r' | sed 's/[^0-9]//g')

    # Ensure we have valid numbers (default to 0 if empty)
    existing_monitor=${existing_monitor:-0}
    existing_logger=${existing_logger:-0}
    existing_api_check=${existing_api_check:-0}
    existing_maintenance=${existing_maintenance:-0}

    print_status "$BLUE" "Checking existing cron entries:"
    print_status "$BLUE" "  starlink_monitor_unified-rutos.sh: $existing_monitor entries"
    print_status "$BLUE" "  starlink_logger_unified-rutos.sh: $existing_logger entries"
    print_status "$BLUE" "  check_starlink_api: $existing_api_check entries"
    print_status "$BLUE" "  system-maintenance-rutos.sh: $existing_maintenance entries"

    # Add cron entries for scripts that don't have any entries yet
    entries_added=0

    # Add monitoring script if not present
    if [ "$existing_monitor" -eq 0 ]; then
        print_status "$BLUE" "Adding starlink_monitor cron entry..."
        cat >>"$CRON_FILE" <<EOF
# Starlink monitor - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_monitor_unified-rutos.sh
EOF
        entries_added=$((entries_added + 1))
    else
        print_status "$YELLOW" "⚠ Preserving existing starlink_monitor cron configuration"
    fi

    # Add logger script if not present
    if [ "$existing_logger" -eq 0 ]; then
        print_status "$BLUE" "Adding starlink_logger cron entry..."
        cat >>"$CRON_FILE" <<EOF
# Starlink logger - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_logger_unified-rutos.sh
EOF
        entries_added=$((entries_added + 1))
    else
        print_status "$YELLOW" "⚠ Preserving existing starlink_logger cron configuration"
    fi

    # Add API check script if not present
    if [ "$existing_api_check" -eq 0 ]; then
        print_status "$BLUE" "Adding check_starlink_api cron entry..."
        cat >>"$CRON_FILE" <<EOF
# Starlink API check - Added by install script $(date +%Y-%m-%d)
0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/check_starlink_api-rutos.sh
EOF
        entries_added=$((entries_added + 1))
    else
        print_status "$YELLOW" "⚠ Preserving existing check_starlink_api cron configuration"
    fi

    # Add maintenance script if not present
    if [ "$existing_maintenance" -eq 0 ]; then
        print_status "$BLUE" "Adding system-maintenance cron entry..."
        cat >>"$CRON_FILE" <<EOF
# System maintenance - Added by install script $(date +%Y-%m-%d) - runs every 6 hours to check and fix common issues
0 */6 * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/system-maintenance-rutos.sh auto
EOF
        entries_added=$((entries_added + 1))
    else
        print_status "$YELLOW" "⚠ Preserving existing system-maintenance cron configuration"
    fi

    # Check for existing auto-update entries
    existing_autoupdate=$(grep -c "self-update-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_autoupdate=$(echo "$existing_autoupdate" | tr -d '\n\r' | sed 's/[^0-9]//g')
    existing_autoupdate=${existing_autoupdate:-0}

    # Add auto-update script if not present (enabled by default with "Never" policy = notifications only)
    if [ "$existing_autoupdate" -eq 0 ]; then
        print_status "$BLUE" "Adding auto-update cron entry (enabled with notifications-only mode)..."
        cat >>"$CRON_FILE" <<EOF
# Auto-update check - Added by install script $(date +%Y-%m-%d) - enabled by default (notifications only due to "Never" delays)
0 3 * * 0 CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/self-update-rutos.sh --auto-update
EOF
        entries_added=$((entries_added + 1))
        print_status "$GREEN" "💡 Auto-update enabled with 'Never' delays - will only send notifications, not install updates"
    else
        print_status "$YELLOW" "⚠ Preserving existing auto-update cron configuration"
    fi

    # Report summary
    if [ "$entries_added" -gt 0 ]; then
        print_status "$GREEN" "✓ Added $entries_added new cron entries"
    else
        print_status "$BLUE" "✓ All scripts already have cron entries - preserved existing configuration"
    fi

    print_status "$BLUE" "Final crontab content:"
    cat -n "$CRON_FILE"

    # Restart cron service
    print_status "$BLUE" "Restarting cron service..."
    if /etc/init.d/cron restart >/dev/null 2>&1; then
        print_status "$GREEN" "✓ Cron service restarted successfully"
    else
        print_status "$YELLOW" "⚠ Warning: Could not restart cron service"
    fi

    print_status "$GREEN" "✓ Cron jobs configured"

    # Show current cron status for verification
    print_status "$BLUE" "Current cron entries for our scripts:"
    grep -n "starlink.*rutos\|check_starlink_api" "$CRON_FILE" 2>/dev/null || print_status "$YELLOW" "No entries found"

    print_status "$BLUE" "=== DEBUG CRON CONFIGURATION COMPLETE ==="
}

# Main execution
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "debug-cron-setup.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: debug-cron-setup.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    print_status "$GREEN" "Starting cron configuration debugging..."
    print_status "$BLUE" "Install directory: $INSTALL_DIR"
    print_status "$BLUE" "Cron file: $CRON_FILE"

    # Check if install directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        print_status "$RED" "ERROR: Install directory not found: $INSTALL_DIR"
        exit 1
    fi

    configure_cron

    print_status "$GREEN" "Cron debugging complete!"
}

# Run main function
main "$@"
