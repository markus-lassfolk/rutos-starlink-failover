# ================= Starlink Connectivity & API Test =====================
# Test both basic network connectivity (ping/curl) and API access (grpcurl)

test_starlink_connectivity() {
    STARLINK_IP="192.168.100.1"
    STARLINK_API_PORT="9200"
    STARLINK_API_URL="http://$STARLINK_IP:$STARLINK_API_PORT/"
    GRPCURL_BIN="$INSTALL_DIR/grpcurl"

    print_status "$BLUE" "[Starlink Test] Pinging Starlink dish at $STARLINK_IP..."
    if ping -c 2 -W 2 "$STARLINK_IP" >/dev/null 2>&1; then
        print_status "$GREEN" "[Starlink Test] Ping successful: $STARLINK_IP is reachable."
    else
        print_status "$RED" "[Starlink Test] Ping failed: $STARLINK_IP is not reachable."
    fi

    print_status "$BLUE" "[Starlink Test] Testing HTTP access with curl: $STARLINK_API_URL"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --max-time 5 "$STARLINK_API_URL" >/dev/null 2>&1; then
            print_status "$GREEN" "[Starlink Test] curl: HTTP port $STARLINK_API_PORT is open."
        else
            print_status "$YELLOW" "[Starlink Test] curl: No HTTP response, but port may still be open (API is gRPC, not HTTP)."
        fi
    else
        print_status "$YELLOW" "[Starlink Test] curl not available for HTTP test."
    fi

    print_status "$BLUE" "[Starlink Test] Testing Starlink gRPC API with grpcurl..."
    if [ -x "$GRPCURL_BIN" ]; then
        if "$GRPCURL_BIN" -plaintext "$STARLINK_IP:$STARLINK_API_PORT" describe >/tmp/grpcurl_test.out 2>&1; then
            print_status "$GREEN" "[Starlink Test] grpcurl: API is accessible."
            print_status "$CYAN" "[Starlink Test] grpcurl output (first 5 lines):"
            head -5 /tmp/grpcurl_test.out | while read -r line; do
                print_status "$CYAN" "  $line"
            done
        else
            print_status "$RED" "[Starlink Test] grpcurl: API not accessible or error occurred."
            print_status "$YELLOW" "[Starlink Test] grpcurl error output:"
            head -5 /tmp/grpcurl_test.out | while read -r line; do
                print_status "$YELLOW" "  $line"
            done
        fi
        rm -f /tmp/grpcurl_test.out
    else
        print_status "$YELLOW" "[Starlink Test] grpcurl binary not found at $GRPCURL_BIN."
    fi
}

git add .
git commit -a --no-verify -m "Install script: add remote fallback for monitor & notifier"
git push --no-#!/bin/sh

# ==============================================================================
# Starlink Monitoring System Installation Script
#
# This script automates the installation and configuration of the Starlink
# monitoring system on OpenWrt/RUTOS devices.
#
# ==============================================================================

set -eu

# Script version - automatically updated from VERSION file
SCRIPT_VERSION="2.0.2"
# Build: 1.0.2+198.38fb60b-dirty
SCRIPT_NAME="install-rutos.sh"

# Extract build info from comment above
BUILD_INFO=$(grep "# Build:" "$0" | head -1 | sed 's/# Build: //' || echo "unknown")

# Configuration - can be overridden by environment variables
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_REPO="${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Debug mode can be enabled by:
# 1. Setting DEBUG=1 environment variable
# 2. Uncommenting the line below
# DEBUG=1

# Logging configuration
LOG_FILE="${INSTALL_DIR:-/usr/local/starlink-monitor}/installation.log"
LOG_DIR="$(dirname "$LOG_FILE")"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to log messages to file
log_message() {
    level="$1"
    message="$2"
    timestamp=$(get_timestamp)

    # Ensure log directory exists
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    # Log to file with timestamp
    echo "[$timestamp] [$level] $message" >>"$LOG_FILE" 2>/dev/null || true
}

# Function to print colored output with logging
print_status() {
    color="$1"
    message="$2"

    # Print to console
    printf "%b[%s] %s%b\n" "$color" "$(get_timestamp)" "$message" "$NC"

    # Log to file (without color codes)
    log_message "INFO" "$message"
}

# Function to print debug messages with logging
debug_msg() {
    if [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(get_timestamp)
        printf "%b[%s] DEBUG: %s%b\n" "$BLUE" "$timestamp" "$1" "$NC" >&2
        log_message "DEBUG" "$1"
    fi
}

# Function to execute commands with debug output
debug_exec() {
    if [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(get_timestamp)
        printf "%b[%s] DEBUG EXEC: %s%b\n" "$CYAN" "$timestamp" "$*" "$NC" >&2
        log_message "DEBUG_EXEC" "$*"
    fi
    "$@"
}

# Version and compatibility
VERSION_URL="${BASE_URL}/VERSION"
# shellcheck disable=SC2034  # Used for compatibility checks in future
MIN_COMPATIBLE_VERSION="1.0.0" # Used for compatibility checks in future

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;35m" # Bright magenta instead of dark blue for better readability
    CYAN="\033[0;36m"
    NC="\033[0m" # No Color
else
    # Fallback to no colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Installation configuration
# shellcheck disable=SC2034  # Variables are used throughout the script
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}" # Use /usr/local for proper Unix convention
PERSISTENT_CONFIG_DIR="/etc/starlink-config"              # Config backup in /etc for persistence
HOTPLUG_DIR="/etc/hotplug.d/iface"
CRON_FILE="/etc/crontabs/root" # Used throughout script

# Binary URLs for ARMv7 (RUTX50)
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# Early debug detection - show immediately if DEBUG is set
if [ "${DEBUG:-0}" = "1" ]; then
    printf "\n"
    print_status "$BLUE" "==================== DEBUG MODE ENABLED ===================="
    print_status "$BLUE" "DEBUG: Script starting with DEBUG=1"
    print_status "$BLUE" "DEBUG: Environment variables:"
    print_status "$BLUE" "DEBUG:   DEBUG=${DEBUG:-0}"
    print_status "$BLUE" "DEBUG:   GITHUB_BRANCH=${GITHUB_BRANCH:-main}"
    print_status "$BLUE" "DEBUG:   GITHUB_REPO=${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
    print_status "$BLUE" "DEBUG:   LOG_FILE=$LOG_FILE"
    print_status "$BLUE" "==========================================================="
    echo ""
fi

# Log installation start
log_message "INFO" "============================================="
log_message "INFO" "Starlink Monitor Installation Script Started"
log_message "INFO" "Script: $SCRIPT_NAME"
log_message "INFO" "Version: $SCRIPT_VERSION"
log_message "INFO" "Branch: $GITHUB_BRANCH"
log_message "INFO" "Repository: $GITHUB_REPO"
log_message "INFO" "DEBUG Mode: ${DEBUG:-0}"
log_message "INFO" "============================================="

# Function to show version information
show_version() {
    print_status "$GREEN" "==========================================="
    print_status "$GREEN" "Starlink Monitor Installation Script"
    print_status "$GREEN" "Script: $SCRIPT_NAME"
    print_status "$GREEN" "Version: $SCRIPT_VERSION"
    print_status "$GREEN" "Build: $BUILD_INFO"
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
    log_message "INFO" "Starting download: $url -> $output"

    # Try wget first, then curl
    if command -v wget >/dev/null 2>&1; then
        if [ "${DEBUG:-0}" = "1" ]; then
            debug_exec wget -O "$output" "$url"
        else
            if wget -q -O "$output" "$url" 2>/dev/null; then
                log_message "INFO" "Download successful: $output"
                return 0
            else
                log_message "ERROR" "Download failed with wget: $url"
                return 1
            fi
        fi
    elif command -v curl >/dev/null 2>&1; then
        if [ "${DEBUG:-0}" = "1" ]; then
            debug_exec curl -fL -o "$output" "$url"
        else
            if curl -fsSL -o "$output" "$url" 2>/dev/null; then
                log_message "INFO" "Download successful: $output"
                return 0
            else
                log_message "ERROR" "Download failed with curl: $url"
                return 1
            fi
        fi
    else
        log_message "ERROR" "Neither wget nor curl available for downloads"
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
    debug_exec mkdir -p "/etc/starlink-logs"     # Persistent log directory
    debug_exec mkdir -p "$PERSISTENT_CONFIG_DIR" # Persistent config backup
    debug_exec mkdir -p "/tmp/run"
    debug_exec mkdir -p "/var/log"
    debug_exec mkdir -p "$HOTPLUG_DIR"

    # Verify directories were created
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Verifying directory structure:"
        debug_exec ls -la "$INSTALL_DIR"
        debug_exec ls -la "/etc/starlink-logs"
        debug_exec ls -la "$PERSISTENT_CONFIG_DIR"
    fi

    print_status "$GREEN" "✓ Directory structure created"
}

# Download and install binaries
install_binaries() {
    print_status "$BLUE" "Installing required binaries..."

    # Install grpcurl
    if [ ! -f "$INSTALL_DIR/grpcurl" ]; then
        print_status "$YELLOW" "Downloading grpcurl..."
        if curl -fL --progress-bar "$GRPCURL_URL" -o /tmp/grpcurl.tar.gz; then
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
        if curl -fL --progress-bar "$JQ_URL" -o "$INSTALL_DIR/jq"; then
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
install_scripts() {
    print_status "$BLUE" "Installing monitoring scripts..."
    script_dir="$(dirname "$0")"

    # Main monitoring script (enhanced version is now default)
    monitor_script="starlink_monitor-rutos.sh"
    if [ -f "$script_dir/$monitor_script" ]; then
        cp "$script_dir/$monitor_script" "$INSTALL_DIR/scripts/$monitor_script"
        chmod +x "$INSTALL_DIR/scripts/$monitor_script"
        print_status "$GREEN" "✓ Monitor script installed"
    else
        print_status "$BLUE" "Downloading $monitor_script..."
        if download_file "$BASE_URL/Starlink-RUTOS-Failover/$monitor_script" "$INSTALL_DIR/scripts/$monitor_script"; then
            chmod +x "$INSTALL_DIR/scripts/$monitor_script"
            print_status "$GREEN" "✓ $monitor_script downloaded and installed"
        else
            print_status "$RED" "Error: Failed to install $monitor_script"
            return 1
        fi
    fi

    # Notification script (enhanced version is now default)
    notify_script="99-pushover_notify-rutos.sh"
    if [ -f "$script_dir/$notify_script" ]; then
        cp "$script_dir/$notify_script" "$HOTPLUG_DIR/$notify_script"
        chmod +x "$HOTPLUG_DIR/$notify_script"
        print_status "$GREEN" "✓ Notification script installed"
    else
        print_status "$BLUE" "Downloading $notify_script..."
        if download_file "$BASE_URL/Starlink-RUTOS-Failover/$notify_script" "$HOTPLUG_DIR/$notify_script"; then
            chmod +x "$HOTPLUG_DIR/$notify_script"
            print_status "$GREEN" "✓ $notify_script downloaded and installed"
        else
            print_status "$RED" "Error: Failed to install $notify_script"
            return 1
        fi
    fi

    # Other scripts - handle both local and remote installation
    for script in starlink_logger-rutos.sh check_starlink_api-rutos.sh; do
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

    # All scripts must use the *-rutos.sh naming convention
    for script in \
        validate-config-rutos.sh \
        placeholder-utils.sh \
        system-status-rutos.sh \
        test-pushover-rutos.sh \
        test-monitoring-rutos.sh \
        health-check-rutos.sh \
        update-config-rutos.sh \
        upgrade-to-advanced-rutos.sh \
        test-connectivity-rutos.sh \
        merge-config-rutos.sh; do
        # Try local script first
        if [ -f "$script_dir/$script" ]; then
            cp "$script_dir/$script" "$INSTALL_DIR/scripts/$script"
            chmod +x "$INSTALL_DIR/scripts/$script"
            print_status "$GREEN" "✓ $script installed"
        elif [ -f "$script_dir/../scripts/$script" ]; then
            cp "$script_dir/../scripts/$script" "$INSTALL_DIR/scripts/$script"
            chmod +x "$INSTALL_DIR/scripts/$script"
            print_status "$GREEN" "✓ $script installed"
        else
            print_status "$BLUE" "Downloading $script..."
            if download_file "$BASE_URL/scripts/$script" "$INSTALL_DIR/scripts/$script"; then
                chmod +x "$INSTALL_DIR/scripts/$script"
                print_status "$GREEN" "✓ $script downloaded and installed"
            else
                print_status "$YELLOW" "⚠ Warning: Could not download $script"
            fi
        fi
    done
}

# Install configuration
install_config() {
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

    # Intelligent configuration management - preserve user settings
    if [ -f "$INSTALL_DIR/config/config.sh" ]; then
        print_status "$BLUE" "Existing configuration detected - performing intelligent merge"

        # Create backup first
        backup_file="$INSTALL_DIR/config/config.sh.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$INSTALL_DIR/config/config.sh" "$backup_file"
        debug_msg "Configuration backup created: $backup_file"

        # ENHANCED MERGE LOGIC - Multiple fallback strategies
        merge_success=false
        merge_method=""

        # Strategy 1: Try merge script if available
        if [ -f "$INSTALL_DIR/scripts/merge-config-rutos.sh" ]; then
            debug_msg "Attempting merge using merge-config-rutos.sh script"
            if "$INSTALL_DIR/scripts/merge-config-rutos.sh" "$INSTALL_DIR/config/config.template.sh" "$INSTALL_DIR/config/config.sh" 2>/dev/null; then
                merge_success=true
                merge_method="script"
                debug_msg "Merge script succeeded"
            else
                debug_msg "Merge script failed, trying manual merge"
            fi
        else
            debug_msg "No merge script found, proceeding to manual merge"
        fi

        # Strategy 2: Enhanced manual merge with extensive settings preservation
        if [ "$merge_success" = "false" ]; then
            print_status "$BLUE" "Performing enhanced manual configuration merge..."
            debug_msg "Starting manual merge process"

            # Create working copy of template
            temp_config="/tmp/config_merge.tmp"
            if ! cp "$INSTALL_DIR/config/config.template.sh" "$temp_config"; then
                debug_msg "Failed to copy template to temp file"
                merge_success=false
            else
                debug_msg "Template copied to temp file: $temp_config"

                # Extended list of settings to preserve - cover all user-configurable options
                settings_to_preserve="STARLINK_IP MWAN_IFACE MWAN_MEMBER PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD RUTOS_IP PING_TARGETS PING_COUNT PING_TIMEOUT PING_INTERVAL CHECK_INTERVAL FAIL_COUNT_THRESHOLD RECOVERY_COUNT_THRESHOLD INITIAL_DELAY ENABLE_LOGGING LOG_RETENTION_DAYS ENABLE_PUSHOVER_NOTIFICATIONS ENABLE_SYSLOG SYSLOG_PRIORITY ENABLE_HOTPLUG_NOTIFICATIONS ENABLE_STATUS_LOGGING ENABLE_API_MONITORING ENABLE_PING_MONITORING STARLINK_GRPC_PORT API_CHECK_INTERVAL MWAN3_POLICY MWAN3_RULE NOTIFICATION_COOLDOWN NOTIFICATION_RECOVERY_DELAY ENABLE_DETAILED_LOGGING"

                preserved_count=0
                total_count=0

                for setting in $settings_to_preserve; do
                    total_count=$((total_count + 1))
                    debug_msg "Processing setting: $setting"

                    if grep -q "^${setting}=" "$backup_file" 2>/dev/null; then
                        user_value=$(grep "^${setting}=" "$backup_file" | head -1)
                        debug_msg "Found setting in backup: $user_value"

                        # Skip placeholder values (YOUR_, CHANGE_ME, etc.)
                        if [ -n "$user_value" ] && ! echo "$user_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                            # Replace in template
                            if grep -q "^${setting}=" "$temp_config" 2>/dev/null; then
                                # Replace existing line
                                if sed -i "s|^${setting}=.*|${user_value}|" "$temp_config" 2>/dev/null; then
                                    preserved_count=$((preserved_count + 1))
                                    debug_msg "Successfully preserved: $setting"
                                else
                                    debug_msg "Failed to replace setting: $setting"
                                fi
                            else
                                # Add new line if not in template
                                if echo "$user_value" >>"$temp_config" 2>/dev/null; then
                                    preserved_count=$((preserved_count + 1))
                                    debug_msg "Successfully added: $setting"
                                else
                                    debug_msg "Failed to add setting: $setting"
                                fi
                            fi
                        else
                            debug_msg "Skipping placeholder value for: $setting"
                        fi
                    else
                        debug_msg "Setting not found in backup: $setting"
                    fi
                done

                # Verify the merge worked
                if [ -f "$temp_config" ] && [ -s "$temp_config" ]; then
                    if mv "$temp_config" "$INSTALL_DIR/config/config.sh" 2>/dev/null; then
                        merge_success=true
                        merge_method="manual"
                        debug_msg "Manual merge completed successfully"
                        print_status "$GREEN" "✓ Manual merge completed: $preserved_count/$total_count settings preserved"
                    else
                        debug_msg "Failed to move temp config to final location"
                        merge_success=false
                    fi
                else
                    debug_msg "Temp config file is missing or empty"
                    merge_success=false
                fi
            fi
        fi

        # Strategy 3: Last resort - copy template and warn user
        if [ "$merge_success" = "false" ]; then
            print_status "$YELLOW" "⚠ All merge strategies failed - using template as fallback"
            if cp "$INSTALL_DIR/config/config.template.sh" "$INSTALL_DIR/config/config.sh" 2>/dev/null; then
                print_status "$YELLOW" "⚠ Configuration replaced with template (backup: $backup_file)"
                print_status "$YELLOW" "📋 Please restore your settings from the backup manually"
                print_status "$YELLOW" "   Example: grep '^PUSHOVER_TOKEN=' '$backup_file'"
            else
                print_status "$RED" "✗ CRITICAL: Failed to create config file!"
                exit 1
            fi
        else
            case "$merge_method" in
                "script")
                    print_status "$GREEN" "✓ Configuration merged successfully using merge script"
                    ;;
                "manual")
                    print_status "$GREEN" "✓ Configuration merged manually - user settings preserved"
                    ;;
            esac
            print_status "$BLUE" "✓ Backup created: $backup_file"

            # Verify critical settings were preserved
            if [ "$merge_method" = "manual" ]; then
                print_status "$BLUE" "Verifying merge results..."
                critical_preserved=0
                critical_total=0

                for critical_setting in PUSHOVER_TOKEN PUSHOVER_USER MWAN_IFACE MWAN_MEMBER; do
                    critical_total=$((critical_total + 1))
                    if grep -q "^${critical_setting}=" "$backup_file" 2>/dev/null; then
                        backup_value=$(grep "^${critical_setting}=" "$backup_file" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
                        current_value=$(grep "^${critical_setting}=" "$INSTALL_DIR/config/config.sh" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")

                        if [ -n "$backup_value" ] && [ "$backup_value" = "$current_value" ] && ! echo "$backup_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)" 2>/dev/null; then
                            critical_preserved=$((critical_preserved + 1))
                            debug_msg "Verified preserved: $critical_setting"
                        else
                            debug_msg "Failed verification for: $critical_setting (backup: '$backup_value', current: '$current_value')"
                        fi
                    fi
                done

                if [ $critical_preserved -gt 0 ]; then
                    print_status "$GREEN" "✓ Verification: $critical_preserved/$critical_total critical settings preserved"
                else
                    print_status "$YELLOW" "⚠ Verification: No critical settings preserved - check backup manually"
                fi
            fi
        fi
    else
        # First time installation
        cp "$INSTALL_DIR/config/config.template.sh" "$INSTALL_DIR/config/config.sh"
        print_status "$GREEN" "✓ Configuration file created from template"
        print_status "$YELLOW" "📋 Please edit $INSTALL_DIR/config/config.sh before using"
    fi

    # Create convenience symlinks for easy access
    ln -sf "$INSTALL_DIR/config/config.sh" "/root/config.sh"
    ln -sf "$INSTALL_DIR" "/root/starlink-monitor" # Convenience symlink to installation

    # Backup configuration to persistent location
    cp "$INSTALL_DIR/config/config.sh" "$PERSISTENT_CONFIG_DIR/config.sh"
    cp "$INSTALL_DIR/config/config.template.sh" "$PERSISTENT_CONFIG_DIR/config.template.sh"

    print_status "$BLUE" "✓ Convenience symlinks created:"
    print_status "$BLUE" "  /root/config.sh -> $INSTALL_DIR/config/config.sh"
    print_status "$BLUE" "  /root/starlink-monitor -> $INSTALL_DIR"
    print_status "$BLUE" "✓ Configuration backed up to: $PERSISTENT_CONFIG_DIR"

    # If user settings were lost, provide quick restoration commands
    if [ -f "$backup_file" ] && [ -f "$INSTALL_DIR/config/config.sh" ]; then
        # Check if PUSHOVER_TOKEN is still a placeholder
        current_pushover=$(grep "^PUSHOVER_TOKEN=" "$INSTALL_DIR/config/config.sh" 2>/dev/null | head -1)
        if echo "$current_pushover" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)" 2>/dev/null; then
            backup_pushover=$(grep "^PUSHOVER_TOKEN=" "$backup_file" 2>/dev/null | head -1)
            if [ -n "$backup_pushover" ] && ! echo "$backup_pushover" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER)" 2>/dev/null; then
                print_status "$YELLOW" "🔧 QUICK FIX: Your Pushover token was reset. To restore:"
                print_status "$YELLOW" "   grep '^PUSHOVER_TOKEN=' '$backup_file'"
                print_status "$YELLOW" "   grep '^PUSHOVER_USER=' '$backup_file'"
                print_status "$YELLOW" "   Then edit: $INSTALL_DIR/config/config.sh"
            fi
        fi
    fi
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
* * * * * CONFIG_FILE=$INSTALL_DIR/config/config.sh $INSTALL_DIR/scripts/starlink_monitor-rutos.sh
* * * * * CONFIG_FILE=$INSTALL_DIR/config/config.sh $INSTALL_DIR/scripts/starlink_logger-rutos.sh
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
    color="$1"
    message="$2"
    printf "%b%s%b\n" "$color" "$message" "$NC"
}

print_status "$RED" "Uninstalling Starlink monitoring system..."

# Backup crontab before modification
if [ -f "$CRON_FILE" ]; then
    cp "$CRON_FILE" "${CRON_FILE}.backup.uninstall.$(date +%Y%m%d_%H%M%S)"
    print_status "$YELLOW" "Crontab backed up before removal"
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
    print_status "$GREEN" "✓ Starlink cron entries commented out (not deleted)"
    print_status "$YELLOW" "ℹ To restore: sed -i 's/^# COMMENTED BY UNINSTALL [0-9-]*: //' $CRON_FILE"
fi

# Remove hotplug script
rm -f /etc/hotplug.d/iface/99-pushover_notify*

# Remove installation directory
rm -rf /usr/local/starlink-monitor

# Remove persistent config backup
rm -rf /etc/starlink-config

# Remove log directory
rm -rf /etc/starlink-logs

# Remove convenience symlinks
rm -f /root/config.sh
rm -f /root/starlink-monitor

# Remove auto-restoration init script
rm -f /etc/init.d/starlink-restore

print_status "$GREEN" "✓ Uninstall completed"
EOF

    chmod +x "$INSTALL_DIR/uninstall.sh"
    print_status "$GREEN" "✓ Uninstall script created"
}

# Create auto-restoration script for firmware upgrade persistence
create_restoration_script() {
    print_status "$BLUE" "Creating auto-restoration script for firmware upgrade persistence..."

    cat >"/etc/init.d/starlink-restore" <<'EOF'
#!/bin/sh /etc/rc.common

START=95
STOP=05
USE_PROCD=1

INSTALL_DIR="/usr/local/starlink-monitor"
PERSISTENT_CONFIG_DIR="/etc/starlink-config"
GITHUB_REPO="markus-lassfolk/rutos-starlink-failover"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
RESTORE_LOG="/var/log/starlink-restore.log"

# Log function for restoration process
log_restore() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESTORE_LOG"
}

# Wait for network connectivity with timeout
wait_for_network() {
    local max_wait=300  # 5 minutes maximum wait
    local wait_count=0
    local sleep_interval=10
    
    log_restore "Waiting for network connectivity..."
    
    while [ $wait_count -lt $max_wait ]; do
        # Test multiple connectivity methods
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || \
           ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || \
           wget -q --spider --timeout=5 https://github.com >/dev/null 2>&1 || \
           curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
            log_restore "Network connectivity confirmed"
            return 0
        fi
        
        log_restore "Network not ready, waiting... ($((wait_count + sleep_interval))/${max_wait}s)"
        sleep $sleep_interval
        wait_count=$((wait_count + sleep_interval))
    done
    
    log_restore "WARNING: Network wait timeout, attempting restoration anyway"
    return 1
}

start() {
    # Always ensure symlinks exist (quick operation)
    ln -sf "$INSTALL_DIR/config/config.sh" "/root/config.sh" 2>/dev/null || true
    ln -sf "$INSTALL_DIR" "/root/starlink-monitor" 2>/dev/null || true
    
    # Check if installation exists, if not and we have persistent config, restore it
    if [ ! -d "$INSTALL_DIR" ] && [ -d "$PERSISTENT_CONFIG_DIR" ]; then
        log_restore "=========================================="
        log_restore "Starlink Monitor: Installation missing after firmware upgrade"
        log_restore "Starting auto-restoration process..."
        log_restore "=========================================="
        
        # Wait for network before attempting download
        if ! wait_for_network; then
            log_restore "Network connectivity issues, restoration may fail"
        fi
        
        # Attempt restoration with detailed logging
        log_restore "Downloading and executing installation script..."
        if curl -fsSL "${BASE_URL}/scripts/install-rutos.sh" | sh >>"$RESTORE_LOG" 2>&1; then
            log_restore "Installation script completed successfully"
            
            # Restore user configuration
            if [ -f "$PERSISTENT_CONFIG_DIR/config.sh" ]; then
                if [ -d "$INSTALL_DIR/config" ]; then
                    cp "$PERSISTENT_CONFIG_DIR/config.sh" "$INSTALL_DIR/config/config.sh"
                    log_restore "User configuration restored from persistent storage"
                else
                    log_restore "WARNING: Installation directory not found, config restore skipped"
                fi
            else
                log_restore "No persistent configuration found to restore"
            fi
            
            # Restore any additional persistent files
            if [ -f "$PERSISTENT_CONFIG_DIR/config.template.sh" ] && [ -d "$INSTALL_DIR/config" ]; then
                cp "$PERSISTENT_CONFIG_DIR/config.template.sh" "$INSTALL_DIR/config/config.template.sh"
                log_restore "Configuration template restored"
            fi
            
            log_restore "=========================================="
            log_restore "Starlink Monitor: Auto-restoration completed successfully!"
            log_restore "System will begin monitoring automatically"
            log_restore "=========================================="
            
        else
            log_restore "=========================================="
            log_restore "ERROR: Auto-restoration failed!"
            log_restore "Manual reinstallation required"
            log_restore "Run: curl -fsSL ${BASE_URL}/scripts/install-rutos.sh | sh"
            log_restore "=========================================="
            return 1
        fi
        
    elif [ -d "$INSTALL_DIR" ]; then
        log_restore "Starlink Monitor: Installation exists, no restoration needed"
    else
        log_restore "Starlink Monitor: No persistent configuration found, skipping restoration"
    fi
}

stop() {
    # Backup current configuration to persistent storage before shutdown
    if [ -f "$INSTALL_DIR/config/config.sh" ]; then
        mkdir -p "$PERSISTENT_CONFIG_DIR"
        cp "$INSTALL_DIR/config/config.sh" "$PERSISTENT_CONFIG_DIR/config.sh"
        log_restore "Configuration backed up to persistent storage"
    fi
    
    # Backup template for future use
    if [ -f "$INSTALL_DIR/config/config.template.sh" ]; then
        cp "$INSTALL_DIR/config/config.template.sh" "$PERSISTENT_CONFIG_DIR/config.template.sh"
        log_restore "Configuration template backed up"
    fi
}
EOF

    chmod +x "/etc/init.d/starlink-restore"

    # Enable the service
    /etc/init.d/starlink-restore enable 2>/dev/null || true

    print_status "$GREEN" "✓ Auto-restoration script created and enabled"
    print_status "$BLUE" "  This will automatically restore the installation after firmware upgrades"
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
    create_restoration_script
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
    print_status "$YELLOW" "1. Edit basic configuration: $available_editor $INSTALL_DIR/config/config.sh"
    print_status "$YELLOW" "   - Update network settings (MWAN_IFACE, MWAN_MEMBER)"
    print_status "$YELLOW" "   - Configure Pushover notifications (optional)"
    print_status "$YELLOW" "   - Adjust failover thresholds if needed"
    print_status "$YELLOW" "2. Validate configuration: $INSTALL_DIR/scripts/validate-config-rutos.sh"
    print_status "$YELLOW" "3. Test connectivity: $INSTALL_DIR/scripts/test-connectivity-rutos.sh"
    print_status "$YELLOW" "4. Check system status: $INSTALL_DIR/scripts/system-status-rutos.sh"
    print_status "$YELLOW" "5. Run health check: $INSTALL_DIR/scripts/health-check-rutos.sh"
    print_status "$YELLOW" "6. Configure mwan3 according to documentation"
    print_status "$YELLOW" "7. Test the system manually"
    printf "\n"
    print_status "$CYAN" "🎯 NEW ARCHITECTURE - Graceful Degradation:"
    print_status "$CYAN" "• BASIC CONFIG: 14 essential settings for core monitoring"
    print_status "$CYAN" "• GRACEFUL DEGRADATION: Features disable safely if not configured"
    print_status "$CYAN" "• PLACEHOLDER DETECTION: Notifications skip if tokens are placeholders"
    print_status "$CYAN" "• UPGRADE PATH: Run upgrade-to-advanced-rutos.sh for full features"
    print_status "$CYAN" "• SMART VALIDATION: Distinguishes critical vs optional settings"
    printf "\n"
    print_status "$BLUE" "Available tools:"
    print_status "$BLUE" "• Comprehensive health check: $INSTALL_DIR/scripts/health-check-rutos.sh"
    print_status "$BLUE" "• Check system status: $INSTALL_DIR/scripts/system-status-rutos.sh"
    print_status "$BLUE" "• Test Pushover notifications: $INSTALL_DIR/scripts/test-pushover-rutos.sh"
    print_status "$BLUE" "• Test monitoring: $INSTALL_DIR/scripts/test-monitoring-rutos.sh"
    print_status "$BLUE" "• Update config with new options: $INSTALL_DIR/scripts/update-config-rutos.sh"
    print_status "$BLUE" "• Upgrade to advanced features: $INSTALL_DIR/scripts/upgrade-to-advanced-rutos.sh"
    printf "\n"

    # Print recommended actions with correct filenames
    print_status "$BLUE" "  • Test monitoring: ./scripts/test-monitoring-rutos.sh"
    print_status "$BLUE" "  • Test Pushover: ./scripts/test-pushover-rutos.sh"
    print_status "$BLUE" "  • Validate config: ./scripts/validate-config-rutos.sh"
    print_status "$BLUE" "  • Upgrade to advanced: ./scripts/upgrade-to-advanced-rutos.sh"
    print_status "$BLUE" "Installation directory: $INSTALL_DIR"
    print_status "$BLUE" "Configuration file: $INSTALL_DIR/config/config.sh"
    print_status "$BLUE" "Uninstall script: $INSTALL_DIR/uninstall.sh"
    print_status "$BLUE" "Scripts downloaded from: https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
    printf "\n"
    print_status "$GREEN" "🚀 System will start monitoring automatically after configuration"
    print_status "$GREEN" "🔧 Monitoring works with minimal configuration - advanced features are optional"
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

    # Log successful completion
    log_message "INFO" "============================================="
    log_message "INFO" "Installation completed successfully!"
    log_message "INFO" "Installation directory: $INSTALL_DIR"
    log_message "INFO" "Log file: $LOG_FILE"
    log_message "INFO" "============================================="

    printf "\n"
    print_status "$GREEN" "📋 Installation log saved to: $LOG_FILE"
}

# Error handling function
handle_error() {
    exit_code=$?
    log_message "ERROR" "Installation failed with exit code: $exit_code"
    log_message "ERROR" "Check the log file for details: $LOG_FILE"
    print_status "$RED" "❌ Installation failed! Check log: $LOG_FILE"
    exit $exit_code
}

# Set up signal handling (busybox compatible)
trap handle_error INT TERM

# Run main function
main "$@"
