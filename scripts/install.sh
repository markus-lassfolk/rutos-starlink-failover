#!/bin/sh

# ==============================================================================
# Starlink Monitoring System Installation Script
#
# This script automates the installation and configuration of the Starlink
# monitoring system on OpenWrt/RUTOS devices.
#
# ==============================================================================

set -eu

# Script version - automatically updated from VERSION file
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="install.sh"

# Configuration - can be overridden by environment variables
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_REPO="${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Debug mode can be enabled by:
# 1. Setting DEBUG=1 environment variable
# 2. Uncommenting the line below
# DEBUG=1

# Version and compatibility
VERSION_URL="${BASE_URL}/VERSION"
# shellcheck disable=SC2034  # Used for compatibility checks in future
MIN_COMPATIBLE_VERSION="1.0.0" # Used for compatibility checks in future

# Colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;36m"  # Changed to cyan for better readability
NC="\033[0m" # No Color

# Installation configuration
# shellcheck disable=SC2034  # Variables are used throughout the script
INSTALL_DIR="/root/starlink-monitor"
HOTPLUG_DIR="/etc/hotplug.d/iface"
CRON_FILE="/etc/crontabs/root" # Used throughout script

# Binary URLs for ARMv7 (RUTX50)
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# Function to print colored output
print_status() {
    color="$1"
    message="$2"
    printf "%b%s%b\n" "$color" "$message" "$NC"
}

# Function to print debug messages
debug_msg() {
    if [ "${DEBUG:-0}" = "1" ]; then
        print_status "$BLUE" "DEBUG: $1"
    fi

# Function to execute commands with debug output
debug_exec() {
    if [ "${DEBUG:-0}" = "1" ]; then
        print_status "$BLUE" "DEBUG: Executing: $*"
        "$@"
    else
        "$@" 2>/dev/null
    fi
}

# Early debug detection - show immediately if DEBUG is set
if [ "${DEBUG:-0}" = "1" ]; then
    printf "\n"
    print_status "$BLUE" "==================== DEBUG MODE ENABLED ===================="
    print_status "$BLUE" "DEBUG: Script starting with DEBUG=1"
    print_status "$BLUE" "DEBUG: Environment variables:"
    print_status "$BLUE" "DEBUG:   DEBUG=${DEBUG:-0}"
    print_status "$BLUE" "DEBUG:   GITHUB_BRANCH=${GITHUB_BRANCH:-main}"
    print_status "$BLUE" "DEBUG:   GITHUB_REPO=${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
    print_status "$BLUE" "==========================================================="
    echo ""
fi

# Function to show version information
show_version() {
    print_status "$GREEN" "==========================================="
    print_status "$GREEN" "Starlink Monitor Installation Script"
    print_status "$GREEN" "Script: $SCRIPT_NAME"
    print_status "$GREEN" "Version: $SCRIPT_VERSION"
    print_status "$GREEN" "Branch: $GITHUB_BRANCH"
    print_status "$GREEN" "Repository: $GITHUB_REPO"
    print_status "$GREEN" "==========================================="
}

# Function to detect remote version
detect_remote_version() {
    remote_version=""
    debug_msg "Fetching remote version from $VERSION_URL"
    if command -v wget >/dev/null 2>&1; then
        remote_version=$(wget -q -O - "$VERSION_URL" 2>/dev/null | head -1 | tr -d '\r\n ')
    elif command -v curl >/dev/null 2>&1; then
        remote_version=$(curl -fsSL "$VERSION_URL" 2>/dev/null | head -1 | tr -d '\r\n ')
    else
        debug_msg "Cannot detect remote version - no wget or curl available"
        return 1
    fi
    if [ -n "$remote_version" ]; then
        debug_msg "Remote version detected: $remote_version"
        printf "%s\n" "$remote_version"
    else
        debug_msg "Failed to detect remote version"
        return 1
    fi
}

# Function to compare versions (simplified)
version_compare() {
    version1="$1"
    version2="$2"
    
    # Simple version comparison (assumes semantic versioning)
    # Returns 0 if versions are equal, 1 if v1 > v2, 2 if v1 < v2
    if [ "$version1" = "$version2" ]; then
        return 0
    fi
    
    # For now, just return equal (can be enhanced later)
    return 0
}

# Function to download files with fallback
download_file() {
    url="$1"
    output="$2"
    
    debug_msg "Downloading $url to $output"
    
    # Try wget first, then curl
    if command -v wget >/dev/null 2>&1; then
        if [ "${DEBUG:-0}" = "1" ]; then
            debug_exec wget -O "$output" "$url"
        else
            wget -q -O "$output" "$url" 2>/dev/null
        fi
    elif command -v curl >/dev/null 2>&1; then
        if [ "${DEBUG:-0}" = "1" ]; then
            debug_exec curl -fL -o "$output" "$url"
        else
            curl -fsSL -o "$output" "$url" 2>/dev/null
        fi
    else
        print_status "$RED" "Error: Neither wget nor curl available for downloads"
        return 1
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_status "$RED" "Error: This script must be run as root"
        exit 1
    fi
}

# Check system compatibility
check_system() {
    print_status "$BLUE" "Checking system compatibility..."

check_system() {
    arch=""
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Executing: uname -m"
        arch=$(uname -m)
        debug_msg "System architecture: $arch"
    else
        arch=$(uname -m)
    fi
    if [ "$arch" != "armv7l" ]; then
        print_status "$YELLOW" "Warning: This script is designed for ARMv7 (RUTX50)"
        print_status "$YELLOW" "Your architecture: $arch"
        print_status "$YELLOW" "You may need to adjust binary URLs"
        printf "Continue anyway? (y/N): "
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            exit 1
        fi
    else
        debug_msg "Architecture check passed: $arch matches expected armv7l"
    fi
    debug_msg "Checking for OpenWrt/RUTOS system files"
    if [ ! -f "/etc/openwrt_version" ] && [ ! -f "/etc/rutos_version" ]; then
        print_status "$YELLOW" "Warning: This doesn't appear to be OpenWrt/RUTOS"
        printf "Continue anyway? (y/N): "
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            exit 1
        fi
    else
        if [ -f "/etc/openwrt_version" ]; then
            openwrt_version=$(cat /etc/openwrt_version 2>/dev/null)
            debug_msg "OpenWrt version: $openwrt_version"
        fi
        if [ -f "/etc/rutos_version" ]; then
            rutos_version=$(cat /etc/rutos_version 2>/dev/null)
            debug_msg "RUTOS version: $rutos_version"
        fi
    fi
    print_status "$GREEN" "✓ System compatibility checked"
}
# Create directory structure
create_directories() {
    print_status "$BLUE" "Creating directory structure..."

    debug_msg "Creating main installation directory: $INSTALL_DIR"
    debug_exec mkdir -p "$INSTALL_DIR"
    debug_exec mkdir -p "$INSTALL_DIR/config"
    debug_exec mkdir -p "$INSTALL_DIR/scripts"
    debug_exec mkdir -p "$INSTALL_DIR/logs"
    debug_exec mkdir -p "/tmp/run"
    debug_exec mkdir -p "/var/log"
    debug_exec mkdir -p "$HOTPLUG_DIR"

    # Verify directories were created
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Verifying directory structure:"
        debug_exec ls -la "$INSTALL_DIR"
    fi

    print_status "$GREEN" "✓ Directory structure created"
}

# Download and install binaries
install_binaries() {
    print_status "$BLUE" "Installing required binaries..."

    # Install grpcurl
    if [ ! -f "$INSTALL_DIR/grpcurl" ]; then
        print_status "$YELLOW" "Downloading grpcurl..."
        if curl -fL "$GRPCURL_URL" -o /tmp/grpcurl.tar.gz; then
            tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl
            chmod +x "$INSTALL_DIR/grpcurl"
            rm /tmp/grpcurl.tar.gz
            print_status "$GREEN" "✓ grpcurl installed"
        else
            print_status "$RED" "Error: Failed to download grpcurl"
            exit 1
        fi
    else
        print_status "$GREEN" "✓ grpcurl already installed"
    fi

    # Install jq
    if [ ! -f "$INSTALL_DIR/jq" ]; then
        print_status "$YELLOW" "Downloading jq..."
        if curl -fL "$JQ_URL" -o "$INSTALL_DIR/jq"; then
            chmod +x "$INSTALL_DIR/jq"
            print_status "$GREEN" "✓ jq installed"
        else
            print_status "$RED" "Error: Failed to download jq"
            exit 1
        fi
    else
        print_status "$GREEN" "✓ jq already installed"
    fi
}

# Install scripts
    print_status "$BLUE" "Installing monitoring scripts..."
    script_dir="$(dirname "$0")"

    # Main monitoring script (enhanced version is now default)
    if [ -f "$script_dir/starlink_monitor.sh" ]; then
        cp "$script_dir/starlink_monitor.sh" "$INSTALL_DIR/scripts/starlink_monitor.sh"
        chmod +x "$INSTALL_DIR/scripts/starlink_monitor.sh"
        print_status "$GREEN" "✓ Monitor script installed"
    else
        print_status "$RED" "Error: Monitor script not found"
        return 1
    fi

    # Notification script (enhanced version is now default)
    if [ -f "$script_dir/99-pushover_notify" ]; then
        cp "$script_dir/99-pushover_notify" "$HOTPLUG_DIR/99-pushover_notify"
        chmod +x "$HOTPLUG_DIR/99-pushover_notify"
        print_status "$GREEN" "✓ Notification script installed"
    else
        print_status "$RED" "Error: Notification script not found"
        return 1
    fi

    # Other scripts - handle both local and remote installation
    for script in starlink_logger.sh check_starlink_api.sh; do
        if [ -f "$script_dir/$script" ]; then
            cp "$script_dir/$script" "$INSTALL_DIR/scripts/"
            chmod +x "$INSTALL_DIR/scripts/$script"
            print_status "$GREEN" "✓ $script installed"
        else
            # Download from repository
            print_status "$BLUE" "Downloading $script..."
            if download_file "$BASE_URL/Starlink-RUTOS-Failover/$script" "$INSTALL_DIR/scripts/$script"; then
                chmod +x "$INSTALL_DIR/scripts/$script"
                print_status "$GREEN" "✓ $script installed"
            else
                print_status "$YELLOW" "⚠ Warning: Could not download $script"
            fi
        fi
    done

    # Validation script - handle both local and remote installation
    if [ -f "$script_dir/../scripts/validate-config.sh" ]; then
        cp "$script_dir/../scripts/validate-config.sh" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/validate-config.sh"
        print_status "$GREEN" "✓ Configuration validation script installed"
    else
        # Download from repository
        print_status "$BLUE" "Downloading validate-config.sh..."
        if download_file "$BASE_URL/scripts/validate-config.sh" "$INSTALL_DIR/scripts/validate-config.sh"; then
            chmod +x "$INSTALL_DIR/scripts/validate-config.sh"
            print_status "$GREEN" "✓ Configuration validation script installed"
        else
            print_status "$YELLOW" "⚠ Warning: Could not download validate-config.sh"
        fi
    fi

    # Configuration update script - handle both local and remote installation
    if [ -f "$script_dir/../scripts/update-config.sh" ]; then
        cp "$script_dir/../scripts/update-config.sh" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/update-config.sh"
        print_status "$GREEN" "✓ Configuration update script installed"
    else
        # Download from repository
        print_status "$BLUE" "Downloading update-config.sh..."
        if download_file "$BASE_URL/scripts/update-config.sh" "$INSTALL_DIR/scripts/update-config.sh"; then
            chmod +x "$INSTALL_DIR/scripts/update-config.sh"
            print_status "$GREEN" "✓ Configuration update script installed"
        else
            print_status "$RED" "✗ Error: Could not download update-config.sh"
            print_status "$YELLOW" "  You can manually download it later from:"
            print_status "$YELLOW" "  $BASE_URL/scripts/update-config.sh"
        fi
    fi

    # Configuration upgrade script - handle both local and remote installation
    if [ -f "$script_dir/../scripts/upgrade-to-advanced.sh" ]; then
        cp "$script_dir/../scripts/upgrade-to-advanced.sh" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/upgrade-to-advanced.sh"
        print_status "$GREEN" "✓ Configuration upgrade script installed"
    else
        # Download from repository
        print_status "$BLUE" "Downloading upgrade-to-advanced.sh..."
        if download_file "$BASE_URL/scripts/upgrade-to-advanced.sh" "$INSTALL_DIR/scripts/upgrade-to-advanced.sh"; then
            chmod +x "$INSTALL_DIR/scripts/upgrade-to-advanced.sh"
            print_status "$GREEN" "✓ Configuration upgrade script installed"
        else
            print_status "$RED" "✗ Error: Could not download upgrade-to-advanced.sh"
            print_status "$YELLOW" "  You can manually download it later from:"
            print_status "$YELLOW" "  $BASE_URL/scripts/upgrade-to-advanced.sh"
        fi
    fi
}

# Install configuration
    print_status "$BLUE" "Installing configuration..."
    config_dir="$(dirname "$0")/../config"

    # Handle both local and remote installation
    if [ -f "$config_dir/config.template.sh" ]; then
        cp "$config_dir/config.template.sh" "$INSTALL_DIR/config/"
        print_status "$GREEN" "✓ Configuration template installed"
    else
        # Download from repository
        print_status "$BLUE" "Downloading configuration template..."
        if download_file "$BASE_URL/config/config.template.sh" "$INSTALL_DIR/config/config.template.sh"; then
            print_status "$GREEN" "✓ Configuration template installed"
        else
            print_status "$RED" "✗ Failed to download configuration template"
            exit 1
        fi
    fi

    # Create config.sh from template if it doesn't exist
    if [ ! -f "$INSTALL_DIR/config/config.sh" ]; then
        cp "$INSTALL_DIR/config/config.template.sh" "$INSTALL_DIR/config/config.sh"
        print_status "$YELLOW" "Configuration file created from template"
        print_status "$YELLOW" "Please edit $INSTALL_DIR/config/config.sh before using"
    fi

    # Create convenience symlink
    ln -sf "$INSTALL_DIR/config/config.sh" "/root/config.sh"
}

# Configure cron jobs
configure_cron() {
    print_status "$BLUE" "Configuring cron jobs..."
    if [ -f "$CRON_FILE" ]; then
        backup_file="$CRON_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CRON_FILE" "$backup_file"
        print_status "$GREEN" "✓ Existing crontab backed up to: $backup_file"
    fi

    # Create the cron file if it doesn't exist
    if [ ! -f "$CRON_FILE" ]; then
        touch "$CRON_FILE"
    fi

    # Remove existing starlink monitoring entries (comment them out instead of deleting)
    if [ -f "$CRON_FILE" ]; then
        # Create temp file with old starlink entries commented out
        date_stamp=$(date +%Y-%m-%d)

        # Use basic sed to comment out matching lines (more portable)
        sed "s|^\([^#].*starlink_monitor\.sh.*\)|# COMMENTED BY INSTALL SCRIPT $date_stamp: \1|g; \
             s|^\([^#].*starlink_logger\.sh.*\)|# COMMENTED BY INSTALL SCRIPT $date_stamp: \1|g; \
             s|^\([^#].*check_starlink_api\.sh.*\)|# COMMENTED BY INSTALL SCRIPT $date_stamp: \1|g" \
            "$CRON_FILE" >"$CRON_FILE.tmp" 2>/dev/null || {
            # If sed fails, preserve existing content
            cat "$CRON_FILE" >"$CRON_FILE.tmp" 2>/dev/null || touch "$CRON_FILE.tmp"
        }

        mv "$CRON_FILE.tmp" "$CRON_FILE"
        print_status "$BLUE" "ℹ Old Starlink cron entries commented out (not deleted)"
    fi

    # Add new cron entries with proper spacing
    cat >>"$CRON_FILE" <<EOF

# Starlink monitoring system - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=$INSTALL_DIR/config/config.sh $INSTALL_DIR/scripts/starlink_monitor.sh
* * * * * CONFIG_FILE=$INSTALL_DIR/config/config.sh $INSTALL_DIR/scripts/starlink_logger.sh
0 6 * * * CONFIG_FILE=$INSTALL_DIR/config/config.sh $INSTALL_DIR/scripts/check_starlink_api.sh
EOF

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1 || {
        print_status "$YELLOW" "⚠ Warning: Could not restart cron service"
    }

    print_status "$GREEN" "✓ Cron jobs configured"
    print_status "$BLUE" "ℹ Previous crontab backed up before modification"
    print_status "$YELLOW" "ℹ To restore commented entries: sed -i 's/^# COMMENTED BY INSTALL SCRIPT [0-9-]*: //' \"$CRON_FILE\""
}

# Create uninstall script
create_uninstall() {
    print_status "$BLUE" "Creating uninstall script..."

    cat >"$INSTALL_DIR/uninstall.sh" <<'EOF'
#!/bin/sh
set -eu

CRON_FILE="/etc/crontabs/root"

print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}\033[0m"
}

print_status "\033[0;31m" "Uninstalling Starlink monitoring system..."

# Backup crontab before modification
if [ -f "$CRON_FILE" ]; then
    cp "$CRON_FILE" "${CRON_FILE}.backup.uninstall.$(date +%Y%m%d_%H%M%S)"
    print_status "\033[0;33m" "Crontab backed up before removal"
fi

# Remove cron entries (comment them out instead of deleting)
if [ -f "$CRON_FILE" ]; then
    # Create temp file with starlink entries commented out
    date_stamp=$(date +%Y-%m-%d)
    
    # Use basic sed to comment out matching lines (more portable)
    sed "s|^\([^#].*starlink_monitor\.sh.*\)|# COMMENTED BY UNINSTALL $date_stamp: \1|g; \
         s|^\([^#].*starlink_logger\.sh.*\)|# COMMENTED BY UNINSTALL $date_stamp: \1|g; \
         s|^\([^#].*check_starlink_api\.sh.*\)|# COMMENTED BY UNINSTALL $date_stamp: \1|g; \
         s|^\([^#].*Starlink monitoring system.*\)|# COMMENTED BY UNINSTALL $date_stamp: \1|g" \
        "$CRON_FILE" > /tmp/crontab.tmp 2>/dev/null || {
        # If sed fails, preserve the file
        cat "$CRON_FILE" > /tmp/crontab.tmp 2>/dev/null || touch /tmp/crontab.tmp
    }
    mv /tmp/crontab.tmp "$CRON_FILE"
    /etc/init.d/cron restart >/dev/null 2>&1 || true
    print_status "\033[0;32m" "✓ Starlink cron entries commented out (not deleted)"
    print_status "\033[0;33m" "ℹ To restore: sed -i 's/^# COMMENTED BY UNINSTALL [0-9-]*: //' $CRON_FILE"
fi

# Remove hotplug script
rm -f /etc/hotplug.d/iface/99-pushover_notify

# Remove installation directory
rm -rf /root/starlink-monitor

# Remove config symlink
rm -f /root/config.sh

print_status "\033[0;32m" "✓ Uninstall completed"
EOF

    chmod +x "$INSTALL_DIR/uninstall.sh"
    print_status "$GREEN" "✓ Uninstall script created"
}

# Main installation function
main() {
    if [ "${DEBUG:-0}" = "1" ]; then
        show_version
        printf "\n"
        if remote_version=$(detect_remote_version); then
            if [ "$remote_version" != "$SCRIPT_VERSION" ]; then
                print_status "$YELLOW" "WARNING: Remote version ($remote_version) differs from script version ($SCRIPT_VERSION)"
            else
                debug_msg "Script version matches remote version: $SCRIPT_VERSION"
            fi
        fi
        printf "\n"
    fi
    print_status "$GREEN" "=== Starlink Monitoring System Installer ==="
    printf "\n"
    debug_msg "Starting installation process"
    check_root
    check_system
    create_directories
    install_binaries
    install_scripts
    install_config
    configure_cron
    create_uninstall
    print_status "$GREEN" "=== Installation Complete ==="
    printf "\n"
    available_editor=""
    for editor in nano vi vim; do
        if command -v "$editor" >/dev/null 2>&1; then
            available_editor="$editor"
            break
        fi
    done
    print_status "$YELLOW" "Next steps:"
    if [ -n "$available_editor" ]; then
        print_status "$YELLOW" "1. Edit configuration: $available_editor $INSTALL_DIR/config/config.sh"
    else
        print_status "$YELLOW" "1. Edit configuration: $INSTALL_DIR/config/config.sh"
        print_status "$YELLOW" "   Note: No standard editor found. You may need to install nano or use vi"
    fi
    print_status "$YELLOW" "2. Validate configuration: $INSTALL_DIR/scripts/validate-config.sh"
    print_status "$YELLOW" "3. Configure mwan3 according to documentation"
    print_status "$YELLOW" "4. Test the system manually"
    printf "\n"
    print_status "$BLUE" "Available tools:"
    print_status "$BLUE" "• Update config with new options: $INSTALL_DIR/scripts/update-config.sh"
    print_status "$BLUE" "• Upgrade to advanced features: $INSTALL_DIR/scripts/upgrade-to-advanced.sh"
    printf "\n"
    print_status "$BLUE" "Installation directory: $INSTALL_DIR"
    print_status "$BLUE" "Configuration file: $INSTALL_DIR/config/config.sh"
    print_status "$BLUE" "Uninstall script: $INSTALL_DIR/uninstall.sh"
    print_status "$BLUE" "Scripts downloaded from: $BASE_URL"
    printf "\n"
    print_status "$GREEN" "System will start monitoring automatically after configuration"
    printf "\n"
    if [ "${DEBUG:-0}" != "1" ]; then
        print_status "$BLUE" "💡 Troubleshooting:"
        print_status "$BLUE" "   For detailed debug output, run with DEBUG=1:"
        print_status "$BLUE" "   DEBUG=1 GITHUB_BRANCH=\"$GITHUB_BRANCH\" \\"
        print_status "$BLUE" "   curl -fL https://raw.githubusercontent.com/..../install.sh | sh -s --"
        printf "\n"
    fi
    if [ "$GITHUB_BRANCH" != "main" ]; then
        print_status "$YELLOW" "⚠ Development Mode: Using branch '$GITHUB_BRANCH'"
        print_status "$YELLOW" "  This is a testing/development installation"
    fi
}

# Run main function
main "$@"
