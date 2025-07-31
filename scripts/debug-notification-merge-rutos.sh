#!/bin/sh
# ==============================================================================
# Debug script for notification settings merge issue
# This script helps troubleshoot why notification trigger settings might be lost
# during config.sh merge operations
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Enable colors if stdout is a terminal
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions using Method 5 format (RUTOS compatible)
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_debug() {
    printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
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

# Configuration paths
PERSISTENT_CONFIG_DIR="/etc/starlink-config"
INSTALL_DIR="/usr/local/starlink-monitor"
PRIMARY_CONFIG="$PERSISTENT_CONFIG_DIR/config.sh"

# Notification settings to check
NOTIFICATION_SETTINGS="NOTIFY_ON_CRITICAL NOTIFY_ON_HARD_FAIL NOTIFY_ON_RECOVERY NOTIFY_ON_SOFT_FAIL NOTIFY_ON_INFO"

# Main debug function
debug_notification_settings() {
    log_info "Starting notification settings debug v$SCRIPT_VERSION"
    echo ""

    log_step "=== ENVIRONMENT CHECK ==="
    log_debug "Primary config path: $PRIMARY_CONFIG"
    log_debug "Install directory: $INSTALL_DIR"
    log_debug "Script location: $(dirname "$0")"
    echo ""

    # Check if primary config exists
    if [ -f "$PRIMARY_CONFIG" ]; then
        log_info "✓ Primary config file exists: $PRIMARY_CONFIG"
        file_size=$(wc -c <"$PRIMARY_CONFIG" 2>/dev/null || echo 'unknown')
        log_debug "File size: $file_size bytes"
    else
        log_error "✗ Primary config file not found: $PRIMARY_CONFIG"
        return 1
    fi
    echo ""

    log_step "=== NOTIFICATION SETTINGS ANALYSIS ==="

    # Check each notification setting
    found_count=0
    total_count=0

    for setting in $NOTIFICATION_SETTINGS; do
        total_count=$((total_count + 1))
        log_debug "Checking: $setting"

        # Check for export format
        if grep -q "^export ${setting}=" "$PRIMARY_CONFIG" 2>/dev/null; then
            value=$(grep "^export ${setting}=" "$PRIMARY_CONFIG" | head -1)
            log_info "  ✓ FOUND (export): $value"
            found_count=$((found_count + 1))
        # Check for standard format
        elif grep -q "^${setting}=" "$PRIMARY_CONFIG" 2>/dev/null; then
            value=$(grep "^${setting}=" "$PRIMARY_CONFIG" | head -1)
            log_info "  ✓ FOUND (standard): $value"
            found_count=$((found_count + 1))
        else
            log_warning "  ✗ MISSING: $setting"
        fi
    done
    echo ""

    log_step "=== SUMMARY ==="
    log_info "Notification settings found: $found_count/$total_count"

    if [ "$found_count" -eq "$total_count" ]; then
        log_info "✓ All notification settings are present"
        echo ""
        log_step "=== CURRENT VALUES ==="
        for setting in $NOTIFICATION_SETTINGS; do
            if grep -q "^export ${setting}=" "$PRIMARY_CONFIG" 2>/dev/null; then
                value=$(grep "^export ${setting}=" "$PRIMARY_CONFIG" | head -1)
                log_info "  $value"
            elif grep -q "^${setting}=" "$PRIMARY_CONFIG" 2>/dev/null; then
                value=$(grep "^${setting}=" "$PRIMARY_CONFIG" | head -1)
                log_info "  $value"
            fi
        done
    else
        log_error "✗ Missing $((total_count - found_count)) notification settings!"
        echo ""

        log_step "=== TROUBLESHOOTING RECOMMENDATIONS ==="
        log_warning "1. Check if settings exist in backup files:"

        # Look for recent backups
        backup_files=$(find "$PERSISTENT_CONFIG_DIR" -name "config.sh.backup.*" -type f 2>/dev/null | sort -r | head -3 || true)
        if [ -n "$backup_files" ]; then
            log_info "Recent backup files found:"
            echo "$backup_files" | while IFS= read -r backup; do
                log_info "  - $backup"
                if [ -f "$backup" ]; then
                    backup_found=0
                    for setting in $NOTIFICATION_SETTINGS; do
                        if grep -q "NOTIFY_ON" "$backup" 2>/dev/null; then
                            backup_found=1
                            break
                        fi
                    done
                    if [ "$backup_found" = "1" ]; then
                        log_info "    ✓ Contains NOTIFY_ON settings"
                    else
                        log_warning "    ✗ No NOTIFY_ON settings found"
                    fi
                fi
            done
        else
            log_warning "No backup files found in $PERSISTENT_CONFIG_DIR"
        fi

        echo ""
        log_warning "2. Enable CONFIG_DEBUG=1 during next install/upgrade:"
        log_info "   CONFIG_DEBUG=1 ./install-rutos.sh"

        echo ""
        log_warning "3. Manual recovery options:"
        log_info "   a) Restore from backup: cp backup_file $PRIMARY_CONFIG"
        log_info "   b) Manually add missing settings to $PRIMARY_CONFIG"
        log_info "   c) Re-run installation with debug enabled"
    fi
    echo ""

    log_step "=== TEMPLATE ANALYSIS ==="
    # Check available templates
    for template in "$INSTALL_DIR/config/config.template.sh" "$INSTALL_DIR/config/config.advanced.template.sh"; do
        if [ -f "$template" ]; then
            log_info "Template: $(basename "$template")"
            template_found=0
            for setting in $NOTIFICATION_SETTINGS; do
                if grep -q "$setting" "$template" 2>/dev/null; then
                    template_found=1
                    break
                fi
            done
            if [ "$template_found" = "1" ]; then
                log_info "  ✓ Contains notification settings"
            else
                log_warning "  ✗ No notification settings found"
            fi
        else
            log_warning "Template not found: $template"
        fi
    done

    echo ""
    log_info "Debug analysis complete"
}

# Check if running as root (recommended for config access)
if [ "$(id -u)" -ne 0 ]; then
    log_warning "Not running as root - some files may not be accessible"
    echo ""
fi

# Execute main debug function
debug_notification_settings

# Show usage instructions
echo ""
log_step "=== USAGE INSTRUCTIONS ==="
log_info "To enable enhanced debugging during installation:"
log_info "  CONFIG_DEBUG=1 DEBUG=1 ./install-rutos.sh"
log_info ""
log_info "To restore missing settings manually:"
log_info "  1. Edit $PRIMARY_CONFIG"
log_info "  2. Add the missing NOTIFY_ON_* settings"
log_info "  3. Use export format: export NOTIFY_ON_CRITICAL=1"
log_info ""
log_info "For persistent troubleshooting, check logs:"
log_info "  - Installation log: $INSTALL_DIR/installation.log"
log_info "  - System logs: /var/log/messages"
