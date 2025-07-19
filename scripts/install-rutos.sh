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
SCRIPT_VERSION="2.4.0"
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

    # Print to console using Method 5 format (the one that works!)
    printf "${color}[%s] %s${NC}\n" "$(get_timestamp)" "$message"

    # Log to file (without color codes)
    log_message "INFO" "$message"
}

# Function to print debug messages with logging
debug_msg() {
    if [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(get_timestamp)
        printf "${BLUE}[%s] DEBUG: %s${NC}\n" "$timestamp" "$1" >&2
        log_message "DEBUG" "$1"
    fi
}

# Function to print config-specific debug messages
config_debug() {
    if [ "${CONFIG_DEBUG:-0}" = "1" ] || [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(get_timestamp)
        printf "${CYAN}[%s] CONFIG DEBUG: %s${NC}\n" "$timestamp" "$1" >&2
        log_message "CONFIG_DEBUG" "$1"
    fi
}

# Enhanced debug_log function (consistent with other scripts)
debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "[DEBUG] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
        log_message "DEBUG" "$1"
    fi
}

# Function to execute commands with debug output
debug_exec() {
    if [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(get_timestamp)
        printf "${CYAN}[%s] DEBUG EXEC: %s${NC}\n" "$timestamp" "$*" >&2
        log_message "DEBUG_EXEC" "$*"
    fi
    "$@"
}

# Enhanced error handling with detailed logging
safe_exec() {
    cmd="$1"
    description="$2"

    debug_log "EXECUTING: $cmd"
    debug_log "DESCRIPTION: $description"

    # Execute command and capture both stdout and stderr
    if [ "${DEBUG:-0}" = "1" ]; then
        # In debug mode, show all output
        eval "$cmd"
        exit_code=$?
        debug_log "COMMAND EXIT CODE: $exit_code"
        return $exit_code
    else
        # In normal mode, suppress output but capture errors
        eval "$cmd" 2>/tmp/install_error.log
        exit_code=$?
        if [ $exit_code -ne 0 ] && [ -f /tmp/install_error.log ]; then
            print_status "$RED" "ERROR in $description: $(cat /tmp/install_error.log)"
            rm -f /tmp/install_error.log
        fi
        return $exit_code
    fi
}

# Version and compatibility
VERSION_URL="${BASE_URL}/VERSION"
# shellcheck disable=SC2034  # Used for compatibility checks in future
MIN_COMPATIBLE_VERSION="1.0.0" # Used for compatibility checks in future

# Colors for output
# RUTOS-compatible color detection - RESTORED TO WORKING VERSION
# This approach showed colors successfully in user testing
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Only enable colors if explicitly requested or in very specific conditions
if [ "${FORCE_COLOR:-}" = "1" ]; then
    # Only enable if user explicitly forces colors
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;35m" # Bright magenta instead of dark blue for better readability
    CYAN="\033[0;36m"
    NC="\033[0m" # No Color
elif [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    # Additional conservative check: only if stdout is a terminal and TERM is set properly
    # But still be very conservative about RUTOS
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            # Known terminal types that support colors
            RED="\033[0;31m"
            GREEN="\033[0;32m"
            YELLOW="\033[1;33m"
            BLUE="\033[1;35m" # Bright magenta instead of dark blue for better readability
            CYAN="\033[0;36m"
            NC="\033[0m" # No Color
            ;;
        *)
            # Unknown or limited terminal - stay safe with no colors
            ;;
    esac
fi

# Installation configuration
# shellcheck disable=SC2034  # Variables are used throughout the script
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}" # Use /usr/local for proper Unix convention
PERSISTENT_CONFIG_DIR="/etc/starlink-config"              # Primary persistent config location
HOTPLUG_DIR="/etc/hotplug.d/iface"
CRON_FILE="/etc/crontabs/root" # Used throughout script

# Binary URLs for ARMv7 (RUTX50)
# Latest release URLs (preferred) - GitHub redirects to actual latest
# The script tries latest versions first, then falls back to known stable versions
GRPCURL_LATEST_URL="https://github.com/fullstorydev/grpcurl/releases/latest/download/grpcurl_linux_armv7.tar.gz"
JQ_LATEST_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-armhf"

# Fallback URLs (known working versions) - used if latest fails
GRPCURL_FALLBACK_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_FALLBACK_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# Set primary URLs to latest (we'll try fallback if these fail)
GRPCURL_URL="$GRPCURL_LATEST_URL"
JQ_URL="$JQ_LATEST_URL"

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
    debug_log "FUNCTION: check_system"
    debug_log "SYSTEM CHECK: Starting system compatibility validation"
    print_status "$BLUE" "Checking system compatibility..."

    arch=""
    debug_log "ARCH CHECK: Getting system architecture"
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Executing: uname -m"
        arch=$(uname -m)
        debug_msg "System architecture: $arch"
    else
        arch=$(uname -m)
    fi

    debug_log "ARCH CHECK: Detected architecture: $arch"
    if [ "$arch" != "armv7l" ]; then
        debug_log "ARCH CHECK: Non-standard architecture detected"
        print_status "$YELLOW" "Warning: This script is designed for ARMv7 (RUTX50)"
        print_status "$YELLOW" "Your architecture: $arch"
        print_status "$YELLOW" "You may need to adjust binary URLs"
        printf "Continue anyway? (y/N): "
        read -r answer
        debug_log "ARCH CHECK: User response: $answer"
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            debug_log "ARCH CHECK: User declined to continue with non-standard architecture"
            exit 1
        fi
        debug_log "ARCH CHECK: User chose to continue despite architecture mismatch"
    else
        debug_log "ARCH CHECK: Architecture validation passed"
        debug_msg "Architecture check passed: $arch matches expected armv7l"
    fi

    debug_log "SYSTEM CHECK: Checking for OpenWrt/RUTOS system files"
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
    debug_log "FUNCTION: install_binaries"
    debug_log "BINARY INSTALLATION: Starting binary installation process"
    print_status "$BLUE" "Installing required binaries..."

    # Install grpcurl
    debug_log "GRPCURL INSTALL: Checking for existing grpcurl at $INSTALL_DIR/grpcurl"
    if [ ! -f "$INSTALL_DIR/grpcurl" ]; then
        debug_log "GRPCURL INSTALL: Not found, trying latest version from $GRPCURL_URL"
        print_status "$YELLOW" "Downloading grpcurl (latest version)..."

        # Try latest version first
        if curl -fL --progress-bar "$GRPCURL_URL" -o /tmp/grpcurl.tar.gz; then
            debug_log "GRPCURL INSTALL: Latest version download successful, extracting archive"
            if tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl 2>/dev/null; then
                chmod +x "$INSTALL_DIR/grpcurl"
                rm /tmp/grpcurl.tar.gz
                debug_log "GRPCURL INSTALL: Latest version installation completed successfully"
                print_status "$GREEN" "✓ grpcurl installed (latest version)"
            else
                debug_log "GRPCURL INSTALL: Latest version extraction failed, trying fallback"
                rm -f /tmp/grpcurl.tar.gz
                print_status "$YELLOW" "Latest version failed, trying known stable version..."

                # Fallback to known working version
                if curl -fL --progress-bar "$GRPCURL_FALLBACK_URL" -o /tmp/grpcurl.tar.gz; then
                    tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl
                    chmod +x "$INSTALL_DIR/grpcurl"
                    rm /tmp/grpcurl.tar.gz
                    debug_log "GRPCURL INSTALL: Fallback version installation completed successfully"
                    print_status "$GREEN" "✓ grpcurl installed (stable version v1.9.3)"
                else
                    print_status "$RED" "Error: Failed to download grpcurl (both latest and fallback)"
                    return 1
                fi
            fi
        else
            debug_log "GRPCURL INSTALL: Download failed"
            print_status "$RED" "Error: Failed to download grpcurl"
            exit 1
        fi
    else
        debug_log "GRPCURL INSTALL: Already exists, skipping download"
        print_status "$GREEN" "✓ grpcurl already installed"
    fi

    # Install jq
    debug_log "JQ INSTALL: Checking for existing jq at $INSTALL_DIR/jq"
    if [ ! -f "$INSTALL_DIR/jq" ]; then
        debug_log "JQ INSTALL: Not found, trying latest version from $JQ_URL"
        print_status "$YELLOW" "Downloading jq (latest version)..."

        # Try latest version first
        if curl -fL --progress-bar "$JQ_URL" -o "$INSTALL_DIR/jq" && [ -s "$INSTALL_DIR/jq" ]; then
            if chmod +x "$INSTALL_DIR/jq" && "$INSTALL_DIR/jq" --version >/dev/null 2>&1; then
                debug_log "JQ INSTALL: Latest version installation completed successfully"
                jq_version=$("$INSTALL_DIR/jq" --version 2>/dev/null || echo "unknown")
                print_status "$GREEN" "✓ jq installed (latest version: $jq_version)"
            else
                debug_log "JQ INSTALL: Latest version validation failed, trying fallback"
                rm -f "$INSTALL_DIR/jq"
                print_status "$YELLOW" "Latest version failed validation, trying known stable version..."

                # Fallback to known working version
                if curl -fL --progress-bar "$JQ_FALLBACK_URL" -o "$INSTALL_DIR/jq"; then
                    chmod +x "$INSTALL_DIR/jq"
                    debug_log "JQ INSTALL: Fallback version installation completed successfully"
                    print_status "$GREEN" "✓ jq installed (stable version v1.7.1)"
                else
                    print_status "$RED" "Error: Failed to download jq (both latest and fallback)"
                    return 1
                fi
            fi
        else
            debug_log "JQ INSTALL: Latest version download failed, trying fallback"
            rm -f "$INSTALL_DIR/jq"
            print_status "$YELLOW" "Latest version download failed, trying known stable version..."

            # Fallback to known working version
            if curl -fL --progress-bar "$JQ_FALLBACK_URL" -o "$INSTALL_DIR/jq"; then
                chmod +x "$INSTALL_DIR/jq"
                debug_log "JQ INSTALL: Fallback version installation completed successfully"
                print_status "$GREEN" "✓ jq installed (stable version v1.7.1)"
            else
                print_status "$RED" "Error: Failed to download jq (both latest and fallback)"
                return 1
            fi
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
        test-colors-rutos.sh \
        test-method5-rutos.sh \
        merge-config-rutos.sh \
        verify-cron-rutos.sh; do
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

    # Ensure persistent configuration directory exists first
    mkdir -p "$PERSISTENT_CONFIG_DIR" 2>/dev/null || {
        print_status "$RED" "✗ Failed to create persistent config directory: $PERSISTENT_CONFIG_DIR"
        exit 1
    }

    # Download/copy templates to temporary location first
    temp_basic_template="/tmp/config.template.sh.$$"
    temp_advanced_template="/tmp/config.advanced.template.sh.$$"

    # Handle both local and remote installation
    if [ -f "$config_dir/config.template.sh" ]; then
        cp "$config_dir/config.template.sh" "$temp_basic_template"
        cp "$config_dir/config.advanced.template.sh" "$temp_advanced_template" 2>/dev/null || {
            print_status "$YELLOW" "⚠ Advanced template not found locally, downloading..."
            download_file "$BASE_URL/config/config.advanced.template.sh" "$temp_advanced_template" || {
                print_status "$YELLOW" "⚠ Could not download advanced template, using basic only"
                cp "$temp_basic_template" "$temp_advanced_template"
            }
        }
        print_status "$GREEN" "✓ Configuration templates loaded locally"
    else
        # Download from repository
        print_status "$BLUE" "Downloading configuration templates..."
        if download_file "$BASE_URL/config/config.template.sh" "$temp_basic_template"; then
            print_status "$GREEN" "✓ Basic configuration template downloaded"
        else
            print_status "$RED" "✗ Failed to download basic configuration template"
            exit 1
        fi

        if download_file "$BASE_URL/config/config.advanced.template.sh" "$temp_advanced_template"; then
            print_status "$GREEN" "✓ Advanced configuration template downloaded"
        else
            print_status "$YELLOW" "⚠ Advanced template not available, using basic template"
            cp "$temp_basic_template" "$temp_advanced_template"
        fi
    fi

    # NEW LOGIC: Check for existing persistent configuration
    primary_config="$PERSISTENT_CONFIG_DIR/config.sh"
    config_debug "=== CONFIG MERGE DEBUG START ==="
    config_debug "Looking for existing config at: $primary_config"
    config_debug "File exists: $([ -f "$primary_config" ] && echo 'yes' || echo 'no')"

    if [ -f "$primary_config" ]; then
        config_debug "Found existing persistent configuration at $primary_config"
        config_debug "File size: $(wc -c <"$primary_config" 2>/dev/null || echo 'unknown') bytes"
        config_debug "File permissions: $(ls -la "$primary_config" 2>/dev/null || echo 'unknown')"
        print_status "$BLUE" "Found existing persistent configuration at $primary_config"

        # Show first few lines of existing config for debugging
        if [ "${CONFIG_DEBUG:-0}" = "1" ]; then
            config_debug "First 10 lines of existing config:"
            head -10 "$primary_config" 2>/dev/null | while IFS= read -r line; do
                case "$line" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        config_debug "  $line"
                        ;;
                esac
            done || config_debug "  (Cannot read config file)"
        fi

        # Detect configuration type (basic vs advanced)
        config_type="basic"
        config_debug "Starting config type detection..."
        # Look for advanced-only variables to detect advanced config
        if grep -qE "^(ENABLE_DETAILED_LOGGING|NOTIFICATION_COOLDOWN|API_CHECK_INTERVAL|MWAN3_POLICY)" "$primary_config" 2>/dev/null; then
            config_type="advanced"
            config_debug "Advanced markers found in config"
        else
            config_debug "No advanced markers found, assuming basic config"
        fi

        config_debug "Detected configuration type: $config_type"
        print_status "$BLUE" "Detected $config_type configuration type"

        # Select appropriate template
        if [ "$config_type" = "advanced" ]; then
            selected_template="$temp_advanced_template"
            config_debug "Selected advanced template: $selected_template"
        else
            selected_template="$temp_basic_template"
            config_debug "Selected basic template: $selected_template"
        fi

        config_debug "Template file exists: $([ -f "$selected_template" ] && echo 'yes' || echo 'no')"
        config_debug "Template file size: $(wc -c <"$selected_template" 2>/dev/null || echo 'unknown') bytes"

        # Create timestamped backup of existing config
        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="$PERSISTENT_CONFIG_DIR/config.sh.backup.$backup_timestamp"
        config_debug "Creating backup: $backup_file"
        if cp "$primary_config" "$backup_file"; then
            config_debug "Backup created successfully"
            config_debug "Backup file size: $(wc -c <"$backup_file" 2>/dev/null || echo 'unknown') bytes"
            print_status "$GREEN" "✓ Configuration backed up to: $backup_file"
        else
            config_debug "BACKUP FAILED!"
            print_status "$RED" "✗ Failed to backup existing configuration!"
            exit 1
        fi

        # Perform intelligent merge
        config_debug "=== STARTING INTELLIGENT MERGE ==="
        print_status "$BLUE" "Merging settings from existing configuration..."
        temp_merged_config="/tmp/config_merged.sh.$$"
        config_debug "Temp merged config file: $temp_merged_config"

        if ! cp "$selected_template" "$temp_merged_config"; then
            config_debug "MERGE PREP FAILED! Could not copy template to temp file"
            print_status "$RED" "✗ Failed to prepare template for merge"
            exit 1
        fi

        config_debug "Template copied to temp file successfully"
        config_debug "Temp file size after copy: $(wc -c <"$temp_merged_config" 2>/dev/null || echo 'unknown') bytes"

        # Enhanced settings preservation
        settings_to_preserve="STARLINK_IP MWAN_IFACE MWAN_MEMBER PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD RUTOS_IP PING_TARGETS PING_COUNT PING_TIMEOUT PING_INTERVAL CHECK_INTERVAL FAIL_COUNT_THRESHOLD RECOVERY_COUNT_THRESHOLD INITIAL_DELAY ENABLE_LOGGING LOG_RETENTION_DAYS ENABLE_PUSHOVER_NOTIFICATIONS ENABLE_SYSLOG SYSLOG_PRIORITY ENABLE_HOTPLUG_NOTIFICATIONS ENABLE_STATUS_LOGGING ENABLE_API_MONITORING ENABLE_PING_MONITORING STARLINK_GRPC_PORT API_CHECK_INTERVAL MWAN3_POLICY MWAN3_RULE NOTIFICATION_COOLDOWN NOTIFICATION_RECOVERY_DELAY ENABLE_DETAILED_LOGGING"

        preserved_count=0
        total_count=0
        config_debug "=== PROCESSING INDIVIDUAL SETTINGS ==="
        config_debug "Settings to check: $(echo "$settings_to_preserve" | wc -w)"

        # Show what settings actually exist in the current config
        if [ "${CONFIG_DEBUG:-0}" = "1" ]; then
            config_debug "=== CURRENT CONFIG FILE ANALYSIS ==="
            config_debug "All lines with '=' assignments found in existing config:"
            grep "^[A-Za-z_][A-Za-z0-9_]*=" "$primary_config" 2>/dev/null | while IFS= read -r line; do
                case "$line" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        config_debug "  $line"
                        ;;
                esac
            done || config_debug "  (No variable assignments found)"
            config_debug "=== END CONFIG FILE ANALYSIS ==="
        fi

        for setting in $settings_to_preserve; do
            total_count=$((total_count + 1))
            config_debug "--- Processing setting $total_count: $setting ---"
            debug_msg "Processing setting: $setting"

            # Check if setting exists in existing config
            config_debug "Checking for setting in existing config..."
            config_debug "SEARCH PATTERN: '^${setting}=' in $primary_config"

            # Enhanced debugging: show what we're looking for and what's similar
            if [ "${CONFIG_DEBUG:-0}" = "1" ]; then
                # Show lines that might match (for debugging)
                matching_lines=$(grep -i "$setting" "$primary_config" 2>/dev/null || true)
                if [ -n "$matching_lines" ]; then
                    config_debug "SIMILAR LINES FOUND (case-insensitive):"
                    echo "$matching_lines" | while IFS= read -r line; do
                        config_debug "  $line"
                    done
                else
                    config_debug "NO SIMILAR LINES FOUND for '$setting'"
                fi

                # Show exact pattern match attempt
                exact_matches=$(grep "^${setting}=" "$primary_config" 2>/dev/null || true)
                if [ -n "$exact_matches" ]; then
                    config_debug "EXACT PATTERN MATCHES:"
                    echo "$exact_matches" | while IFS= read -r line; do
                        config_debug "  $line"
                    done
                else
                    config_debug "NO EXACT PATTERN MATCHES for '^${setting}='"
                fi
            fi

            # Try to find the setting with or without export prefix
            if grep -q "^${setting}=" "$primary_config" 2>/dev/null; then
                user_value=$(grep "^${setting}=" "$primary_config" | head -1)
                config_debug "Found setting without export prefix: $setting"
            elif grep -q "^export ${setting}=" "$primary_config" 2>/dev/null; then
                user_value=$(grep "^export ${setting}=" "$primary_config" | head -1)
                config_debug "Found setting with export prefix: $setting"
            else
                user_value=""
            fi

            if [ -n "$user_value" ]; then
                config_debug "Found in existing config: $setting"

                # Mask sensitive values in debug output
                case "$setting" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "Value: $(echo "$user_value" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        config_debug "Value: $user_value"
                        ;;
                esac

                debug_msg "Found setting in existing config: $user_value"

                # Skip placeholder values
                config_debug "Checking if value is placeholder..."

                # Extract just the value part (handle both export and non-export formats)
                if echo "$user_value" | grep -q "^export "; then
                    # Extract value from: export VAR="value"
                    actual_value=$(echo "$user_value" | sed 's/^export [^=]*=//; s/^"//; s/"$//')
                    config_debug "Extracted value from export format: '$actual_value'"
                else
                    # Extract value from: VAR="value"
                    actual_value=$(echo "$user_value" | sed 's/^[^=]*=//; s/^"//; s/"$//')
                    config_debug "Extracted value from standard format: '$actual_value'"
                fi

                if [ -n "$actual_value" ] && ! echo "$actual_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                    config_debug "Value is not a placeholder, proceeding with merge"

                    # Check if setting exists in template
                    if grep -q "^export ${setting}=" "$temp_merged_config" 2>/dev/null; then
                        config_debug "Setting exists in template with export, replacing..."
                        # Create the replacement line in export format to match template
                        replacement_line="export ${setting}=\"${actual_value}\""
                        # Replace existing line
                        if sed -i "s|^export ${setting}=.*|${replacement_line}|" "$temp_merged_config" 2>/dev/null; then
                            preserved_count=$((preserved_count + 1))
                            config_debug "✓ Successfully replaced export: $setting with value '$actual_value'"
                            debug_msg "Successfully preserved: $setting"
                        else
                            config_debug "✗ Failed to replace export: $setting"
                            debug_msg "Failed to replace setting: $setting"
                        fi
                    elif grep -q "^${setting}=" "$temp_merged_config" 2>/dev/null; then
                        config_debug "Setting exists in template without export, replacing..."
                        # Create the replacement line in standard format
                        replacement_line="${setting}=\"${actual_value}\""
                        # Replace existing line
                        if sed -i "s|^${setting}=.*|${replacement_line}|" "$temp_merged_config" 2>/dev/null; then
                            preserved_count=$((preserved_count + 1))
                            config_debug "✓ Successfully replaced: $setting with value '$actual_value'"
                            debug_msg "Successfully preserved: $setting"
                        else
                            config_debug "✗ Failed to replace: $setting"
                            debug_msg "Failed to replace setting: $setting"
                        fi
                    else
                        config_debug "Setting not in template, adding as new line..."
                        # Add new line if not in template (use export format to match template style)
                        replacement_line="export ${setting}=\"${actual_value}\""
                        if echo "$replacement_line" >>"$temp_merged_config" 2>/dev/null; then
                            preserved_count=$((preserved_count + 1))
                            config_debug "✓ Successfully added: $setting with value '$actual_value'"
                            debug_msg "Successfully added: $setting"
                        else
                            config_debug "✗ Failed to add: $setting"
                            debug_msg "Failed to add setting: $setting"
                        fi
                    fi
                else
                    config_debug "⚠ Skipping placeholder value: $setting"
                    debug_msg "Skipping placeholder value for: $setting"
                fi
            else
                config_debug "⚠ Setting not found in existing config: $setting"
                debug_msg "Setting not found in existing config: $setting"
            fi
        done

        config_debug "=== MERGE PROCESSING COMPLETE ==="
        config_debug "Total settings processed: $total_count"
        config_debug "Settings preserved: $preserved_count"
        config_debug "Merged file size: $(wc -c <"$temp_merged_config" 2>/dev/null || echo 'unknown') bytes"

        # Clean up duplicate variables (remove non-export duplicates of export variables)
        config_debug "=== CLEANING UP DUPLICATE VARIABLES ==="
        temp_cleaned_config="/tmp/config_cleaned.sh.$$"

        # Create a list of export variables in the file
        export_vars=$(grep "^export [A-Za-z_][A-Za-z0-9_]*=" "$temp_merged_config" 2>/dev/null | sed 's/^export \([^=]*\)=.*/\1/' || true)

        if [ -n "$export_vars" ]; then
            config_debug "Found export variables to check for duplicates:"
            echo "$export_vars" | while read -r var; do
                [ -n "$var" ] && config_debug "  $var"
            done || true

            # Copy file and remove non-export duplicates of export variables
            cp "$temp_merged_config" "$temp_cleaned_config"

            # For each export variable, remove any non-export duplicate
            echo "$export_vars" | while read -r var; do
                if [ -n "$var" ]; then
                    config_debug "Removing non-export duplicates of: $var"
                    # Remove lines that match: VAR="value" but not: export VAR="value"
                    sed -i "/^${var}=/d" "$temp_cleaned_config" 2>/dev/null || true
                fi
            done

            # Update the merged config with cleaned version
            mv "$temp_cleaned_config" "$temp_merged_config"
            config_debug "Duplicate cleanup completed"
            config_debug "Cleaned file size: $(wc -c <"$temp_merged_config" 2>/dev/null || echo 'unknown') bytes"
        else
            config_debug "No export variables found, skipping duplicate cleanup"
        fi

        # Replace the primary config with merged version
        config_debug "=== FINALIZING MERGE ==="
        config_debug "Checking merged config file..."
        if [ -f "$temp_merged_config" ] && [ -s "$temp_merged_config" ]; then
            config_debug "Merged config file exists and is not empty"
            config_debug "Final merged file size: $(wc -c <"$temp_merged_config" 2>/dev/null || echo 'unknown') bytes"

            # Show sample of merged config for debugging
            if [ "${CONFIG_DEBUG:-0}" = "1" ]; then
                config_debug "First 15 lines of merged config:"
                head -15 "$temp_merged_config" 2>/dev/null | while IFS= read -r line; do
                    case "$line" in
                        *TOKEN* | *PASSWORD* | *USER*)
                            config_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                            ;;
                        *)
                            config_debug "  $line"
                            ;;
                    esac
                done || config_debug "  (Cannot read merged config file)"
            fi

            config_debug "Replacing primary config with merged version..."
            if mv "$temp_merged_config" "$primary_config" 2>/dev/null; then
                config_debug "✓ Primary config replacement successful"
                config_debug "Final config file size: $(wc -c <"$primary_config" 2>/dev/null || echo 'unknown') bytes"
                print_status "$GREEN" "✓ Configuration merged successfully: $preserved_count/$total_count settings preserved"
                print_status "$GREEN" "✓ Updated persistent configuration: $primary_config"
            else
                config_debug "✗ FAILED to replace primary config!"
                print_status "$RED" "✗ Failed to update primary configuration!"
                # Restore backup
                mv "$backup_file" "$primary_config" 2>/dev/null
                exit 1
            fi
        else
            config_debug "✗ Merged config file is missing or empty!"
            config_debug "Temp merged config file: $temp_merged_config"
            if [ -f "$temp_merged_config" ]; then
                config_debug "File exists but size: $(wc -c < "$temp_merged_config" 2>/dev/null || echo 'unknown') bytes"
            else
                config_debug "File does not exist"
            fi
            print_status "$RED" "✗ Merged configuration is empty or missing!"
            print_status "$RED" "  This usually indicates a problem with the merge process"
            # Restore backup
            mv "$backup_file" "$primary_config" 2>/dev/null
            exit 1
        fi

        config_debug "=== CONFIG INSTALLATION COMPLETE ==="
        config_debug "Final validation of installed config..."
        if [ -f "$primary_config" ]; then
            config_debug "✓ Primary config file exists: $primary_config"
            config_debug "✓ Final config size: $(wc -c <"$primary_config" 2>/dev/null || echo 'unknown') bytes"

            # Quick validation of critical settings
            config_critical_count=0
            for setting in "PUSHOVER_APP_TOKEN" "PUSHOVER_USER_KEY" "STARLINK_CHECK_INTERVAL"; do
                if grep -q "^${setting}=" "$primary_config" 2>/dev/null; then
                    config_critical_count=$((config_critical_count + 1))
                    config_debug "✓ Critical setting found: $setting"
                else
                    config_debug "⚠ Critical setting missing: $setting"
                fi
            done
            config_debug "Critical settings found: $config_critical_count/3"
        else
            config_debug "✗ Primary config file missing after installation!"
            return 1
        fi

    else
        # First time installation - no existing config
        print_status "$BLUE" "First time installation - creating new configuration"

        # Use basic template by default
        if cp "$temp_basic_template" "$primary_config"; then
            print_status "$GREEN" "✓ Initial configuration created from template"
            print_status "$YELLOW" "📋 Please edit $primary_config with your settings"
        else
            print_status "$RED" "✗ Failed to create initial configuration"
            exit 1
        fi
    fi

    # Copy final config to install directory for backwards compatibility
    mkdir -p "$INSTALL_DIR/config" 2>/dev/null
    cp "$primary_config" "$INSTALL_DIR/config/config.sh" 2>/dev/null || true
    cp "$temp_basic_template" "$INSTALL_DIR/config/config.template.sh" 2>/dev/null || true
    cp "$temp_advanced_template" "$INSTALL_DIR/config/config.advanced.template.sh" 2>/dev/null || true

    # Create convenience symlinks pointing to persistent config
    ln -sf "$primary_config" "/root/config.sh" 2>/dev/null || true
    ln -sf "$INSTALL_DIR" "/root/starlink-monitor" 2>/dev/null || true

    print_status "$GREEN" "✓ Configuration system initialized"
    print_status "$BLUE" "  Primary config: $primary_config"
    print_status "$BLUE" "  Convenience link: /root/config.sh -> $primary_config"
    print_status "$BLUE" "  Installation link: /root/starlink-monitor -> $INSTALL_DIR"

    # Cleanup temporary files
    rm -f "$temp_basic_template" "$temp_advanced_template" "$temp_merged_config" 2>/dev/null || true
}

# Configure cron jobs
configure_cron() {
    print_status "$BLUE" "Configuring cron jobs..."

    # Create backup of existing crontab
    if [ -f "$CRON_FILE" ]; then
        backup_file="$CRON_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CRON_FILE" "$backup_file"
        print_status "$GREEN" "✓ Existing crontab backed up to: $backup_file"
    fi

    # Create the cron file if it doesn't exist
    if [ ! -f "$CRON_FILE" ]; then
        touch "$CRON_FILE"
    fi

    # Remove any existing entries added by this install script to prevent duplicates
    # Only remove entries that match our exact pattern (default install script entries)
    if [ -f "$CRON_FILE" ]; then
        debug_msg "Cleaning up previous install script entries"

        # Create temp file for clean crontab
        temp_cron="/tmp/crontab_clean.tmp"

        # Remove lines that match our default install patterns, but preserve custom ones
        # Look for the specific comment marker and the exact default entries
        grep -v "# Starlink monitoring system - Added by install script" "$CRON_FILE" >"$temp_cron" || true

        # Remove the exact default entries (in case comment is missing)
        # But be very specific to avoid removing custom timing configurations
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
        sed -i '/^0 6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/check_starlink_api.*\.sh$/d' "$temp_cron" 2>/dev/null || true

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

    # Check if our scripts already have cron entries (possibly with custom timing)
    existing_monitor=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_logger=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_api_check=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")

    if [ "$existing_monitor" -gt 0 ] || [ "$existing_logger" -gt 0 ] || [ "$existing_api_check" -gt 0 ]; then
        print_status "$YELLOW" "⚠ Found existing cron entries for our scripts:"
        print_status "$YELLOW" "  starlink_monitor-rutos.sh: $existing_monitor entries"
        print_status "$YELLOW" "  starlink_logger-rutos.sh: $existing_logger entries"
        print_status "$YELLOW" "  check_starlink_api: $existing_api_check entries"
        print_status "$YELLOW" "📋 Preserving existing custom timing - not adding default entries"
        print_status "$BLUE" "✓ Custom cron configuration preserved"
        return 0
    fi

    # Add our default cron entries only if none exist
    print_status "$BLUE" "Adding default cron entries..."
    # Clean up any old cron entries using the old CONFIG_FILE path
    old_entries_found=0
    if grep -q "CONFIG_FILE=.*/config/config.sh" "$CRON_FILE" 2>/dev/null; then
        # Check if they contain the old pattern (not /etc/starlink-config)
        if grep -q "CONFIG_FILE=.*/config/config.sh" "$CRON_FILE" 2>/dev/null && ! grep -q "CONFIG_FILE=/etc/starlink-config/config.sh" "$CRON_FILE" 2>/dev/null; then
            # shellcheck disable=SC2034  # Variable tracks cleanup status for logging/debugging
            old_entries_found=1
            print_status "$YELLOW" "🧹 Removing old cron entries with deprecated CONFIG_FILE path..."

            # Create temporary file without old entries - remove entries with old pattern but keep /etc/starlink-config ones
            temp_cron="/tmp/crontab_update_$$.tmp"
            grep -v "CONFIG_FILE=.*/starlink-monitor/config/config.sh" "$CRON_FILE" >"$temp_cron" 2>/dev/null || touch "$temp_cron"

            # Update crontab
            if crontab "$temp_cron" 2>/dev/null; then
                rm -f "$temp_cron"
                print_status "$GREEN" "✓ Cleaned up old cron entries"
            else
                rm -f "$temp_cron"
                print_status "$YELLOW" "⚠ Warning: Could not clean old cron entries"
            fi

            # Reload cron file
            CRON_FILE="/tmp/crontab_current_$$.tmp"
            crontab -l >"$CRON_FILE" 2>/dev/null || touch "$CRON_FILE"
        fi
    fi

    cat >>"$CRON_FILE" <<EOF

# Starlink monitoring system - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_monitor-rutos.sh
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_logger-rutos.sh
0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/check_starlink_api-rutos.sh
EOF

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1 || {
        print_status "$YELLOW" "⚠ Warning: Could not restart cron service"
    }

    print_status "$GREEN" "✓ Cron jobs configured"
    print_status "$BLUE" "ℹ Previous crontab backed up before modification"

    # Show current cron status for verification
    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Current cron entries for our scripts:"
        grep -n "starlink.*rutos\|check_starlink_api" "$CRON_FILE" 2>/dev/null || debug_msg "No entries found"
    fi
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
    printf "${color}%s${NC}\n" "$message"
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

    # Check if restoration service already exists and is working
    if [ -f "/etc/init.d/starlink-restore" ]; then
        # Check if it's enabled
        if /etc/init.d/starlink-restore enabled 2>/dev/null; then
            print_status "$GREEN" "✓ Auto-restoration service already exists and is enabled"
            print_status "$BLUE" "  Skipping recreation to avoid duplication"
            return 0
        else
            print_status "$YELLOW" "⚠ Auto-restoration service exists but is not enabled"
            print_status "$BLUE" "  Re-enabling existing service"
            /etc/init.d/starlink-restore enable 2>/dev/null || true
            print_status "$GREEN" "✓ Auto-restoration service re-enabled"
            return 0
        fi
    fi

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
    max_wait=300  # 5 minutes maximum wait
    wait_count=0
    sleep_interval=10
    
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
    # Add test mode for troubleshooting
    if [ "${TEST_MODE:-0}" = "1" ]; then
        debug_log "TEST MODE ENABLED: Running in test mode"
        DEBUG=1 # Force debug mode in test mode
        set -x  # Enable command tracing
        debug_log "TEST MODE: All commands will be traced"
    fi

    # Enhanced debug mode with detailed startup logging
    DEBUG="${DEBUG:-0}"
    if [ "$DEBUG" = "1" ]; then
        debug_log "==================== INSTALL SCRIPT DEBUG MODE ENABLED ===================="
        debug_log "Script version: $SCRIPT_VERSION"
        debug_log "Script build: $BUILD_INFO"
        debug_log "Script name: $SCRIPT_NAME"
        debug_log "Current working directory: $(pwd)"
        debug_log "Script path: $0"
        debug_log "Process ID: $$"
        debug_log "User: $(whoami 2>/dev/null || echo 'unknown')"
        debug_log "Arguments: $*"
        debug_log "Environment DEBUG: ${DEBUG:-0}"
        debug_log "Environment TEST_MODE: ${TEST_MODE:-0}"

        debug_log "CONFIGURATION PATHS:"
        debug_log "  GITHUB_REPO=$GITHUB_REPO"
        debug_log "  GITHUB_BRANCH=$GITHUB_BRANCH"
        debug_log "  BASE_URL=$BASE_URL"
        debug_log "  LOG_FILE=$LOG_FILE"
        debug_log "  LOG_DIR=$LOG_DIR"

        debug_log "RUNTIME ENVIRONMENT:"
        debug_log "  OpenWRT Release: $(head -3 /etc/openwrt_release 2>/dev/null | tr '\n' ' ' || echo 'not found')"
        debug_log "  Available disk space: $(df -h /tmp 2>/dev/null | tail -1 | awk '{print $4}' || echo 'unknown')"
        debug_log "  Available memory: $(free -m 2>/dev/null | grep Mem | awk '{print $7"M available"}' || echo 'unknown')"
        debug_log "  Network connectivity: $(ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && echo 'online' || echo 'offline/limited')"

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

    debug_log "==================== INSTALLATION START ===================="
    debug_log "Starting installation process"
    debug_msg "Starting installation process"

    debug_log "STEP 1: Checking root privileges and system compatibility"
    check_root

    debug_log "STEP 2: Validating system requirements"
    check_system

    debug_log "STEP 3: Creating directory structure"
    create_directories

    debug_log "STEP 4: Installing binary dependencies"
    install_binaries

    debug_log "STEP 5: Installing monitoring scripts"
    install_scripts

    debug_log "STEP 6: Installing configuration files"
    install_config

    debug_log "STEP 7: Configuring cron jobs"
    configure_cron

    debug_log "STEP 8: Creating uninstall script"
    create_uninstall

    debug_log "STEP 9: Setting up auto-restoration"
    create_restoration_script

    debug_log "==================== INSTALLATION COMPLETE ===================="
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
    print_status "$YELLOW" "1. Edit basic configuration: $available_editor $PERSISTENT_CONFIG_DIR/config.sh"
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
    print_status "$BLUE" "• Verify cron scheduling: $INSTALL_DIR/scripts/verify-cron-rutos.sh"
    print_status "$BLUE" "• Test Pushover notifications: $INSTALL_DIR/scripts/test-pushover-rutos.sh"
    print_status "$BLUE" "• Test monitoring: $INSTALL_DIR/scripts/test-monitoring-rutos.sh"
    print_status "$BLUE" "• Test connectivity: $INSTALL_DIR/scripts/test-connectivity-rutos.sh"
    print_status "$BLUE" "• Test color support: $INSTALL_DIR/scripts/test-colors-rutos.sh"
    print_status "$BLUE" "• Test Method 5 color format: $INSTALL_DIR/scripts/test-method5-rutos.sh"
    print_status "$BLUE" "• Update config with new options: $INSTALL_DIR/scripts/update-config-rutos.sh"
    print_status "$BLUE" "• Upgrade to advanced features: $INSTALL_DIR/scripts/upgrade-to-advanced-rutos.sh"
    printf "\n"

    # Print recommended actions with correct filenames
    print_status "$BLUE" "  • Test monitoring: ./scripts/test-monitoring-rutos.sh"
    print_status "$BLUE" "  • Test Pushover: ./scripts/test-pushover-rutos.sh"
    print_status "$BLUE" "  • Test connectivity: ./scripts/test-connectivity-rutos.sh"
    print_status "$BLUE" "  • Test colors (for troubleshooting): ./scripts/test-colors-rutos.sh"
    print_status "$BLUE" "  • Test Method 5 colors: ./scripts/test-method5-rutos.sh"
    print_status "$BLUE" "  • Validate config: ./scripts/validate-config-rutos.sh"
    print_status "$BLUE" "  • Upgrade to advanced: ./scripts/upgrade-to-advanced-rutos.sh"
    print_status "$BLUE" "Installation directory: $INSTALL_DIR"
    print_status "$BLUE" "Configuration file: $PERSISTENT_CONFIG_DIR/config.sh"
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
    debug_log "INSTALLATION: Completing successfully"
    log_message "INFO" "============================================="
    log_message "INFO" "Installation completed successfully!"
    log_message "INFO" "Installation directory: $INSTALL_DIR"
    log_message "INFO" "Log file: $LOG_FILE"
    log_message "INFO" "============================================="

    printf "\n"
    print_status "$GREEN" "📋 Installation log saved to: $LOG_FILE"

    debug_log "==================== INSTALLATION SCRIPT COMPLETE ===================="
    debug_log "Final status: SUCCESS"
    debug_log "Script execution completed normally"
    debug_log "Exit code: 0"
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
debug_log "==================== INSTALL SCRIPT EXECUTION START ===================="
main "$@"
debug_log "==================== INSTALL SCRIPT EXECUTION END ===================="
