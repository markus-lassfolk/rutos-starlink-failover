#!/bin/sh

# ==============================================================================
# shellcheck disable=SC2059 # Method 5 printf format required for RUTOS color compatibility
# Auto-Update Setup Script for RUTOS Starlink Failover System
#
# This script can be called during installation to set up automatic updates
# based on user preferences.
#
# Usage:
#   ./scripts/setup-auto-update.sh [--interactive|--enable|--disable]
#
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

CONFIG_FILE="/root/starlink-monitor/config/config.sh"
SELF_UPDATE_SCRIPT="/root/starlink-monitor/scripts/self-update-rutos.sh"

# Colors for output
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034  # RED may be used in future error handling
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034  # CYAN may be used in future debug functionality
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # shellcheck disable=SC2034  # RED may be used in future error handling
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # CYAN may be used in future debug functionality
    CYAN=""
    NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

# Interactive setup
setup_interactive() {
    log_step "Setting up automatic updates for Starlink Monitor"
    echo ""
    echo "Automatic updates help keep your system secure and up-to-date."
    echo "You can configure different policies for different types of updates:"
    echo ""
    echo "- Patch updates (2.1.3 → 2.1.4): Bug fixes, usually safe"
    echo "- Minor updates (2.1.x → 2.2.0): New features, moderate risk"
    echo "- Major updates (2.x.x → 3.0.0): Breaking changes, highest risk"
    echo ""
    printf "Would you like to enable automatic updates? (y/N): "
    read -r enable_updates

    if [ "$enable_updates" = "y" ] || [ "$enable_updates" = "Y" ]; then
        log_info "Enabling automatic updates..."

        # Update config file to enable auto-updates
        if [ -f "$CONFIG_FILE" ]; then
            sed -i 's/AUTO_UPDATE_ENABLED="false"/AUTO_UPDATE_ENABLED="true"/' "$CONFIG_FILE" 2>/dev/null || true
            sed -i 's/AUTO_UPDATE_NOTIFICATIONS_ENABLED="false"/AUTO_UPDATE_NOTIFICATIONS_ENABLED="true"/' "$CONFIG_FILE" 2>/dev/null || true
        fi

        # Install crontab job
        if [ -x "$SELF_UPDATE_SCRIPT" ]; then
            "$SELF_UPDATE_SCRIPT" --install-cron
        else
            log_warning "Self-update script not found or not executable"
            return 1
        fi

        echo ""
        log_info "✅ Automatic updates enabled!"
        log_info "Current update policy: All updates disabled by default (Never)"
        echo ""
        echo "To customize update policies, edit: $CONFIG_FILE"
        echo "Example settings:"
        echo '  UPDATE_PATCH_DELAY="1Hours"    # Apply patches after 1 hour'
        echo '  UPDATE_MINOR_DELAY="3Days"     # Apply minor updates after 3 days'
        echo '  UPDATE_MAJOR_DELAY="2Weeks"    # Apply major updates after 2 weeks'
        echo ""
        echo "The system will check for updates every 4 hours and send notifications"
        echo "about available updates via Pushover (if configured)."

    else
        log_info "Automatic updates disabled"
        log_info "You can enable them later by running: $SELF_UPDATE_SCRIPT --install-cron"
    fi
}

# Enable auto-updates without interaction
setup_enable() {
    log_info "Enabling automatic updates..."

    if [ -f "$CONFIG_FILE" ]; then
        sed -i 's/AUTO_UPDATE_ENABLED="false"/AUTO_UPDATE_ENABLED="true"/' "$CONFIG_FILE" 2>/dev/null || true
        sed -i 's/AUTO_UPDATE_NOTIFICATIONS_ENABLED="false"/AUTO_UPDATE_NOTIFICATIONS_ENABLED="true"/' "$CONFIG_FILE" 2>/dev/null || true
    fi

    if [ -x "$SELF_UPDATE_SCRIPT" ]; then
        "$SELF_UPDATE_SCRIPT" --install-cron
        log_info "✅ Automatic updates enabled successfully"
    else
        log_warning "Self-update script not found"
        return 1
    fi
}

# Disable auto-updates
setup_disable() {
    log_info "Disabling automatic updates..."

    if [ -x "$SELF_UPDATE_SCRIPT" ]; then
        "$SELF_UPDATE_SCRIPT" --remove-cron
        log_info "✅ Automatic updates disabled successfully"
    else
        log_warning "Self-update script not found"
    fi
}

# Show help
show_help() {
    echo "Auto-Update Setup Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --interactive    Interactive setup (default)"
    echo "  --enable         Enable auto-updates without prompting"
    echo "  --disable        Disable auto-updates"
    echo "  --help           Show this help message"
    echo ""
    echo "This script configures automatic updates for the Starlink Monitor system."
}

# Main function
main() {
    case "${1:---interactive}" in
        --interactive)
            setup_interactive
            ;;
        --enable)
            setup_enable
            ;;
        --disable)
            setup_disable
            ;;
        --help | -h)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
