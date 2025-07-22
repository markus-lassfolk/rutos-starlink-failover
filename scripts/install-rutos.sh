#!/bin/sh

# ==============================================================================
# Starlink Monitoring System Installation Script
#
# This script automates the installation and configuration of the Starlink
# monitoring system on OpenWrt/RUTOS devices.
#
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
# Build: 1.0.2+198.38fb60b-dirty
SCRIPT_NAME="install-rutos.sh"

# Extract build info safely (handle remote execution via curl | sh)
if [ -f "$0" ] && [ "$0" != "sh" ]; then
    BUILD_INFO=$(grep "# Build:" "$0" | head -1 | sed 's/# Build: //' 2>/dev/null || echo "1.0.2+198.38fb60b-dirty")
else
    # When run via curl | sh, $0 is "sh", so use embedded build info
    BUILD_INFO="1.0.2+198.38fb60b-dirty"
fi

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
# Using known working versions as primary URLs - more reliable than latest redirects
# grpcurl - latest stable release for ARMv7 (correct filename pattern)
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
# jq - latest stable release for ARM
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# Alternative URLs (if primary fails) - using different versions with correct filenames
GRPCURL_FALLBACK_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_armv7.tar.gz"
JQ_FALLBACK_URL="https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux32"

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

# Function to detect latest grpcurl version dynamically
detect_latest_grpcurl_version() {
    debug_msg "Attempting to detect latest grpcurl version..."

    # Try to get latest version from GitHub API
    latest_version=""
    if command -v curl >/dev/null 2>&1; then
        # GitHub API returns JSON with tag_name field
        latest_version=$(curl -fsSL --max-time 10 "https://api.github.com/repos/fullstorydev/grpcurl/releases/latest" 2>/dev/null |
            grep -o '"tag_name":[[:space:]]*"[^"]*"' |
            sed 's/"tag_name":[[:space:]]*"\([^"]*\)"/\1/' |
            head -1)
    elif command -v wget >/dev/null 2>&1; then
        latest_version=$(wget -qO- --timeout=10 "https://api.github.com/repos/fullstorydev/grpcurl/releases/latest" 2>/dev/null |
            grep -o '"tag_name":[[:space:]]*"[^"]*"' |
            sed 's/"tag_name":[[:space:]]*"\([^"]*\)"/\1/' |
            head -1)
    fi

    # Validate the version format (should be like "v1.9.3")
    if [ -n "$latest_version" ] && echo "$latest_version" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        # Remove the 'v' prefix for filename construction
        version_number=$(echo "$latest_version" | sed 's/^v//')
        dynamic_url="https://github.com/fullstorydev/grpcurl/releases/download/${latest_version}/grpcurl_${version_number}_linux_armv7.tar.gz"
        debug_msg "Detected latest grpcurl version: $latest_version"
        debug_msg "Constructed dynamic URL: $dynamic_url"
        printf "%s" "$dynamic_url"
        return 0
    else
        debug_msg "Failed to detect latest grpcurl version or invalid format: '$latest_version'"
        return 1
    fi
}

# Function to detect latest jq version dynamically
detect_latest_jq_version() {
    debug_msg "Attempting to detect latest jq version..."

    # Try to get latest version from GitHub API
    latest_version=""
    if command -v curl >/dev/null 2>&1; then
        # GitHub API returns JSON with tag_name field
        latest_version=$(curl -fsSL --max-time 10 "https://api.github.com/repos/jqlang/jq/releases/latest" 2>/dev/null |
            grep -o '"tag_name":[[:space:]]*"[^"]*"' |
            sed 's/"tag_name":[[:space:]]*"\([^"]*\)"/\1/' |
            head -1)
    elif command -v wget >/dev/null 2>&1; then
        latest_version=$(wget -qO- --timeout=10 "https://api.github.com/repos/jqlang/jq/releases/latest" 2>/dev/null |
            grep -o '"tag_name":[[:space:]]*"[^"]*"' |
            sed 's/"tag_name":[[:space:]]*"\([^"]*\)"/\1/' |
            head -1)
    fi

    # Validate the version format (should be like "jq-1.7.1")
    if [ -n "$latest_version" ] && echo "$latest_version" | grep -qE '^jq-[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
        # Construct the dynamic URL for ARM binary
        dynamic_url="https://github.com/jqlang/jq/releases/download/${latest_version}/jq-linux-armhf"
        debug_msg "Detected latest jq version: $latest_version"
        debug_msg "Constructed dynamic URL: $dynamic_url"
        printf "%s" "$dynamic_url"
        return 0
    else
        debug_msg "Failed to detect latest jq version or invalid format: '$latest_version'"
        return 1
    fi
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
            if debug_exec wget -O "$output" "$url"; then
                log_message "INFO" "Download successful: $output"
                return 0
            else
                log_message "ERROR" "Download failed with wget: $url"
                return 1
            fi
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
            if debug_exec curl -fL -o "$output" "$url"; then
                log_message "INFO" "Download successful: $output"
                return 0
            else
                log_message "ERROR" "Download failed with curl: $url"
                return 1
            fi
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

# Function to perform intelligent config merge using improved approach
# This implements the user's suggested logic:
# 1. Read every value in template, find corresponding value in current config
# 2. Any value missing in config.sh keeps the default from template
# 3. Copy any entries from config.sh that are missing in template (preserve custom settings)
# 4. Add comments and descriptions for preserved settings
intelligent_config_merge() {
    template_file="$1"
    current_config="$2"
    output_config="$3"

    config_debug "=== INTELLIGENT CONFIG MERGE START ==="
    config_debug "Template: $template_file"
    config_debug "Current config: $current_config"
    config_debug "Output: $output_config"

    # Step 1: Create temporary working files
    temp_template_vars="/tmp/template_vars.$$"
    temp_current_vars="/tmp/current_vars.$$"
    temp_merged_config="/tmp/merged_config.$$"
    temp_extra_vars="/tmp/extra_vars.$$"

    config_debug "=== STEP 1: EXTRACT VARIABLES FROM TEMPLATE ==="
    # Extract all variable assignments from template (both export and standard)
    grep -E "^(export )?[A-Za-z_][A-Za-z0-9_]*=" "$template_file" 2>/dev/null >"$temp_template_vars" || touch "$temp_template_vars"
    template_count=$(wc -l <"$temp_template_vars" 2>/dev/null || echo 0)
    config_debug "Found $template_count variables in template"

    if [ "${CONFIG_DEBUG:-0}" = "1" ] && [ "$template_count" -gt 0 ]; then
        config_debug "Template variables (first 10):"
        head -10 "$temp_template_vars" | while IFS= read -r line; do
            config_debug "  $line"
        done
        if [ "$template_count" -gt 10 ]; then
            config_debug "  ... and $((template_count - 10)) more"
        fi
    fi

    config_debug "=== STEP 2: EXTRACT VARIABLES FROM CURRENT CONFIG ==="
    # Extract all variable assignments from current config
    if [ -f "$current_config" ]; then
        # Extract variable assignments, but filter out system variables and malformed lines
        {
            # Find proper variable assignments (with export or without)
            grep -E "^(export )?[A-Za-z_][A-Za-z0-9_]*=" "$current_config" 2>/dev/null || true
        } | {
            # Filter out system variables during extraction to prevent conflicts
            while IFS= read -r line; do
                case "$line" in
                    # Skip system/metadata variables
                    *SCRIPT_VERSION=* | *TEMPLATE_VERSION=* | *CONFIG_VERSION=* | *BUILD_INFO=* | *SCRIPT_NAME=*)
                        config_debug "Filtering out system variable during extraction: $(echo "$line" | cut -d'=' -f1)"
                        ;;
                    # Skip recovery information variables
                    *INSTALLED_VERSION=* | *INSTALLED_TIMESTAMP=* | *RECOVERY_INSTALL_URL=* | *RECOVERY_FALLBACK_URL=*)
                        config_debug "Filtering out recovery variable during extraction: $(echo "$line" | cut -d'=' -f1)"
                        ;;
                    # Skip standalone export statements (malformed)
                    "export "*[A-Za-z_][A-Za-z0-9_]*)
                        # Check if this is a standalone export without assignment
                        if ! echo "$line" | grep -q "="; then
                            config_debug "Filtering out standalone export statement: $line"
                        else
                            echo "$line"
                        fi
                        ;;
                    # Keep valid variable assignments
                    *)
                        echo "$line"
                        ;;
                esac
            done
        } >"$temp_current_vars"

        current_count=$(wc -l <"$temp_current_vars" 2>/dev/null || echo 0)
        config_debug "Found $current_count variables in current config (after filtering)"

        if [ "${CONFIG_DEBUG:-0}" = "1" ] && [ "$current_count" -gt 0 ]; then
            config_debug "Current config variables (first 10, sensitive values masked):"
            head -10 "$temp_current_vars" | while IFS= read -r line; do
                case "$line" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "  $(echo "$line" | sed 's/=.*/=***/')"
                        ;;
                    *)
                        config_debug "  $line"
                        ;;
                esac
            done
            if [ "$current_count" -gt 10 ]; then
                config_debug "  ... and $((current_count - 10)) more"
            fi
        fi
    else
        touch "$temp_current_vars"
        current_count=0
        config_debug "Current config file not found, treating as new installation"
    fi

    config_debug "=== STEP 3: START WITH TEMPLATE AS BASE ==="
    # Start with the complete template (preserves structure, comments, formatting)
    if cp "$template_file" "$temp_merged_config"; then
        config_debug "Template copied as base for merged config"
    else
        config_debug "✗ FAILED to copy template as base"
        rm -f "$temp_template_vars" "$temp_current_vars" "$temp_extra_vars" 2>/dev/null
        return 1
    fi

    config_debug "=== STEP 4: PROCESS TEMPLATE VARIABLES ==="
    # Process each variable in the template
    preserved_count=0
    kept_default_count=0
    new_variables_added=0

    while IFS= read -r template_line; do
        if [ -z "$template_line" ]; then
            continue
        fi

        # Extract variable name from template line
        var_name=""
        if echo "$template_line" | grep -q "^export "; then
            var_name=$(echo "$template_line" | sed 's/^export \([^=]*\)=.*/\1/')
        else
            var_name=$(echo "$template_line" | sed 's/^\([^=]*\)=.*/\1/')
        fi

        if [ -n "$var_name" ]; then
            config_debug "--- Processing template variable: $var_name ---"

            # Skip system variables during processing to avoid readonly conflicts
            case "$var_name" in
                SCRIPT_VERSION | TEMPLATE_VERSION | CONFIG_VERSION | BUILD_INFO | SCRIPT_NAME)
                    config_debug "Skipping system variable: $var_name (should not be processed)"
                    continue
                    ;;
                # Skip recovery information variables (managed by self-update system)
                INSTALLED_VERSION | INSTALLED_TIMESTAMP | RECOVERY_INSTALL_URL | RECOVERY_FALLBACK_URL)
                    config_debug "Skipping recovery variable: $var_name (managed by self-update system)"
                    continue
                    ;;
            esac

            # Look for this variable in current config (both formats)
            current_value=""
            if grep -q "^export ${var_name}=" "$current_config" 2>/dev/null; then
                current_line=$(grep "^export ${var_name}=" "$current_config" | head -1)
                current_value=$(echo "$current_line" | sed 's/^export [^=]*=//; s/^"//; s/"$//')
                config_debug "Found current value (export format): $var_name = $current_value"
            elif grep -q "^${var_name}=" "$current_config" 2>/dev/null; then
                current_line=$(grep "^${var_name}=" "$current_config" | head -1)
                current_value=$(echo "$current_line" | sed 's/^[^=]*=//; s/^"//; s/"$//')
                config_debug "Found current value (standard format): $var_name = $current_value"
            else
                config_debug "Variable not found in current config: $var_name (will add new template variable)"
            fi

            # Decide whether to use current value or keep template default
            if [ -n "$current_value" ] && ! echo "$current_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                # Use current value (preserve user setting)
                case "$var_name" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "Preserving user value: $var_name = ***"
                        ;;
                    *)
                        config_debug "Preserving user value: $var_name = $current_value"
                        ;;
                esac

                # Replace in merged config (preserve template format)
                if echo "$template_line" | grep -q "^export "; then
                    replacement="export ${var_name}=\"${current_value}\""
                else
                    replacement="${var_name}=\"${current_value}\""
                fi

                # Replace the line in merged config
                if sed -i "s|^export ${var_name}=.*|$replacement|" "$temp_merged_config" 2>/dev/null ||
                    sed -i "s|^${var_name}=.*|$replacement|" "$temp_merged_config" 2>/dev/null; then
                    preserved_count=$((preserved_count + 1))
                    config_debug "✓ Successfully preserved: $var_name"
                else
                    config_debug "✗ Failed to replace: $var_name"
                fi
            else
                # Check if this is a new variable not in current config
                if [ ! -f "$current_config" ] || ! grep -q "^export ${var_name}=" "$current_config" 2>/dev/null && ! grep -q "^${var_name}=" "$current_config" 2>/dev/null; then
                    # This is a new template variable - it's already in merged config from template copy
                    new_variables_added=$((new_variables_added + 1))
                    config_debug "✓ New template variable added: $var_name"
                else
                    # Keep template default for existing variable with placeholder value
                    kept_default_count=$((kept_default_count + 1))
                    config_debug "Keeping template default: $var_name"
                fi
            fi
        fi
    done <"$temp_template_vars"

    config_debug "=== STEP 5: FIND EXTRA USER SETTINGS ==="
    # Find settings in current config that are NOT in template
    true >"$temp_extra_vars" # Clear file
    extra_count=0

    if [ -f "$current_config" ] && [ "$current_count" -gt 0 ]; then
        while IFS= read -r current_line; do
            if [ -z "$current_line" ]; then
                continue
            fi

            # Extract variable name from current config line
            var_name=""
            if echo "$current_line" | grep -q "^export "; then
                var_name=$(echo "$current_line" | sed 's/^export \([^=]*\)=.*/\1/')
            else
                var_name=$(echo "$current_line" | sed 's/^\([^=]*\)=.*/\1/')
            fi

            if [ -n "$var_name" ]; then
                # Skip system/metadata variables that should not be preserved
                case "$var_name" in
                    SCRIPT_VERSION | TEMPLATE_VERSION | CONFIG_VERSION | BUILD_INFO | SCRIPT_NAME)
                        config_debug "Skipping system variable: $var_name (should not be preserved)"
                        continue
                        ;;
                    # Skip recovery information variables (managed by self-update system)
                    INSTALLED_VERSION | INSTALLED_TIMESTAMP | RECOVERY_INSTALL_URL | RECOVERY_FALLBACK_URL)
                        config_debug "Skipping recovery variable: $var_name (managed by self-update system)"
                        continue
                        ;;
                esac

                # Check if this variable exists in template
                if ! grep -q "^export ${var_name}=" "$temp_template_vars" 2>/dev/null &&
                    ! grep -q "^${var_name}=" "$temp_template_vars" 2>/dev/null; then
                    # This is an extra setting not in template
                    config_debug "Found extra user setting: $var_name"
                    echo "$current_line" >>"$temp_extra_vars"
                    extra_count=$((extra_count + 1))
                fi
            fi
        done <"$temp_current_vars"
    fi

    config_debug "Found $extra_count extra user settings not in template"

    config_debug "=== STEP 6: ADD EXTRA SETTINGS TO MERGED CONFIG ==="
    if [ "$extra_count" -gt 0 ]; then
        config_debug "Adding extra user settings to merged config"

        # Add a section header for extra settings
        cat >>"$temp_merged_config" <<EOF

# ==============================================================================
# Additional User Settings (not in template)
# These settings were found in your existing config but are not part of the
# standard template. They are preserved here to maintain your customizations.
# ==============================================================================
EOF

        # Add each extra setting with some context
        while IFS= read -r extra_line; do
            if [ -n "$extra_line" ]; then
                # Extract variable name for comment
                var_name=""
                if echo "$extra_line" | grep -q "^export "; then
                    var_name=$(echo "$extra_line" | sed 's/^export \([^=]*\)=.*/\1/')
                else
                    var_name=$(echo "$extra_line" | sed 's/^\([^=]*\)=.*/\1/')
                fi

                {
                    echo "# Custom setting: $var_name (preserved from existing config)"
                    echo "$extra_line"
                    echo ""
                } >>"$temp_merged_config"

                config_debug "Added extra setting: $var_name"
            fi
        done <"$temp_extra_vars"
    fi

    config_debug "=== STEP 7: FINALIZE MERGE ==="
    # Copy merged config to final destination
    if cp "$temp_merged_config" "$output_config" 2>/dev/null; then
        config_debug "✓ Merged config successfully written to: $output_config"

        # Generate summary
        total_template_vars=$template_count
        total_preserved=$preserved_count
        total_defaults=$kept_default_count
        total_new_added=$new_variables_added
        total_extra=$extra_count

        config_debug "=== MERGE SUMMARY ==="
        config_debug "Template variables: $total_template_vars"
        config_debug "User values preserved: $total_preserved"
        config_debug "Template defaults kept: $total_defaults"
        config_debug "New variables added: $total_new_added"
        config_debug "Extra user settings: $total_extra"
        config_debug "Final config size: $(wc -c <"$output_config" 2>/dev/null || echo 'unknown') bytes"

        # Show notification settings specifically
        config_debug "=== NOTIFICATION SETTINGS VERIFICATION ==="
        for notify_setting in "NOTIFY_ON_CRITICAL" "NOTIFY_ON_HARD_FAIL" "NOTIFY_ON_RECOVERY" "NOTIFY_ON_SOFT_FAIL" "NOTIFY_ON_INFO"; do
            if grep -q "^export ${notify_setting}=" "$output_config" 2>/dev/null; then
                notify_value=$(grep "^export ${notify_setting}=" "$output_config" | head -1)
                config_debug "✓ $notify_value"
            elif grep -q "^${notify_setting}=" "$output_config" 2>/dev/null; then
                notify_value=$(grep "^${notify_setting}=" "$output_config" | head -1)
                config_debug "✓ $notify_value"
            else
                config_debug "✗ MISSING: $notify_setting"
            fi
        done

        # Show maintenance settings specifically
        config_debug "=== MAINTENANCE SETTINGS VERIFICATION ==="
        for maintenance_setting in "MAINTENANCE_PUSHOVER_ENABLED" "MAINTENANCE_NOTIFY_ON_START" "MAINTENANCE_NOTIFY_ON_COMPLETION" "MAINTENANCE_AUTO_FIX_ENABLED"; do
            if grep -q "^export ${maintenance_setting}=" "$output_config" 2>/dev/null; then
                maintenance_value=$(grep "^export ${maintenance_setting}=" "$output_config" | head -1)
                config_debug "✓ $maintenance_value"
            elif grep -q "^${maintenance_setting}=" "$output_config" 2>/dev/null; then
                maintenance_value=$(grep "^${maintenance_setting}=" "$output_config" | head -1)
                config_debug "✓ $maintenance_value"
            else
                config_debug "✗ MISSING: $maintenance_setting"
            fi
        done

        cleanup_result=0
    else
        config_debug "✗ FAILED to write merged config to: $output_config"
        cleanup_result=1
    fi

    # If merge was successful, copy the merged config back to the primary location
    if [ "$cleanup_result" = 0 ]; then
        config_debug "Copying merged config from backup location to primary config..."
        if cp "$output_config" "$current_config" 2>/dev/null; then
            config_debug "✓ Merged config successfully restored to: $current_config"
        else
            config_debug "✗ Failed to restore merged config to primary location"
            cleanup_result=1
        fi
    fi

    # Cleanup temporary files
    rm -f "$temp_template_vars" "$temp_current_vars" "$temp_merged_config" "$temp_extra_vars" 2>/dev/null

    if [ "$cleanup_result" = 0 ]; then
        config_debug "=== INTELLIGENT CONFIG MERGE COMPLETE ==="
        print_status "$GREEN" "✓ Configuration merged successfully: $total_preserved values preserved, $total_new_added new variables added, $total_extra custom settings preserved"
        return 0
    else
        config_debug "=== INTELLIGENT CONFIG MERGE FAILED ==="
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
    debug_exec mkdir -p "$INSTALL_DIR/scripts/tests" # Subdirectory for test scripts
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
        # Try to detect latest version dynamically first
        print_status "$YELLOW" "Detecting latest grpcurl version..."
        dynamic_grpcurl_url=""
        if dynamic_grpcurl_url=$(detect_latest_grpcurl_version); then
            debug_log "GRPCURL INSTALL: Dynamic detection successful, trying latest version"
            print_status "$YELLOW" "Downloading grpcurl (latest detected version)..."

            if curl -fL --progress-bar "$dynamic_grpcurl_url" -o /tmp/grpcurl.tar.gz; then
                debug_log "GRPCURL INSTALL: Latest version download successful, extracting archive"
                if tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl 2>/dev/null; then
                    chmod +x "$INSTALL_DIR/grpcurl"
                    rm /tmp/grpcurl.tar.gz
                    debug_log "GRPCURL INSTALL: Latest version installation completed successfully"
                    # Get version for display
                    grpcurl_version=$("$INSTALL_DIR/grpcurl" --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
                    print_status "$GREEN" "✓ grpcurl installed (latest: $grpcurl_version)"
                else
                    debug_log "GRPCURL INSTALL: Latest version extraction failed, trying fallback to stable version"
                    rm -f /tmp/grpcurl.tar.gz
                    print_status "$YELLOW" "Latest version extraction failed, trying stable version..."
                    # Fall through to stable version logic below
                    dynamic_grpcurl_url=""
                fi
            else
                debug_log "GRPCURL INSTALL: Latest version download failed, trying fallback to stable version"
                print_status "$YELLOW" "Latest version download failed, trying stable version..."
                # Fall through to stable version logic below
                dynamic_grpcurl_url=""
            fi
        else
            debug_log "GRPCURL INSTALL: Dynamic detection failed, trying stable version"
            print_status "$YELLOW" "Could not detect latest version, using stable version..."
        fi

        # If dynamic detection failed, use our known stable version
        if [ -z "$dynamic_grpcurl_url" ]; then
            debug_log "GRPCURL INSTALL: Using stable version from $GRPCURL_URL"
            print_status "$YELLOW" "Downloading grpcurl (stable version v1.9.3)..."

            # Try primary stable version
            if curl -fL --progress-bar "$GRPCURL_URL" -o /tmp/grpcurl.tar.gz; then
                debug_log "GRPCURL INSTALL: Stable version download successful, extracting archive"
                if tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl 2>/dev/null; then
                    chmod +x "$INSTALL_DIR/grpcurl"
                    rm /tmp/grpcurl.tar.gz
                    debug_log "GRPCURL INSTALL: Stable version installation completed successfully"
                    print_status "$GREEN" "✓ grpcurl installed (stable v1.9.3)"
                else
                    debug_log "GRPCURL INSTALL: Stable version extraction failed, trying fallback"
                    rm -f /tmp/grpcurl.tar.gz
                    print_status "$YELLOW" "Stable version failed, trying alternative version..."

                    # Fallback to alternative version
                    if curl -fL --progress-bar "$GRPCURL_FALLBACK_URL" -o /tmp/grpcurl.tar.gz; then
                        tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl
                        chmod +x "$INSTALL_DIR/grpcurl"
                        rm /tmp/grpcurl.tar.gz
                        debug_log "GRPCURL INSTALL: Fallback version installation completed successfully"
                        print_status "$GREEN" "✓ grpcurl installed (fallback version v1.9.1)"
                    else
                        print_status "$RED" "Error: Failed to download grpcurl (all versions tried)"
                        return 1
                    fi
                fi
            else
                debug_log "GRPCURL INSTALL: Stable version download failed, trying fallback"
                print_status "$YELLOW" "Stable version download failed, trying alternative version..."

                # Try fallback version
                if curl -fL --progress-bar "$GRPCURL_FALLBACK_URL" -o /tmp/grpcurl.tar.gz; then
                    if tar -zxf /tmp/grpcurl.tar.gz -C "$INSTALL_DIR" grpcurl 2>/dev/null; then
                        chmod +x "$INSTALL_DIR/grpcurl"
                        rm /tmp/grpcurl.tar.gz
                        debug_log "GRPCURL INSTALL: Fallback version installation completed successfully"
                        print_status "$GREEN" "✓ grpcurl installed (fallback version v1.9.1)"
                    else
                        rm -f /tmp/grpcurl.tar.gz
                        print_status "$RED" "Error: Failed to extract grpcurl fallback version"
                        return 1
                    fi
                else
                    debug_log "GRPCURL INSTALL: All download attempts failed"
                    print_status "$RED" "Error: Failed to download grpcurl (all versions tried)"
                    return 1
                fi
            fi
        fi
    else
        debug_log "GRPCURL INSTALL: Already exists, skipping download"
        print_status "$GREEN" "✓ grpcurl already installed"
    fi

    # Install jq
    debug_log "JQ INSTALL: Checking for existing jq at $INSTALL_DIR/jq"
    if [ ! -f "$INSTALL_DIR/jq" ]; then
        # Try to detect latest version dynamically first
        print_status "$YELLOW" "Detecting latest jq version..."
        dynamic_jq_url=""
        if dynamic_jq_url=$(detect_latest_jq_version); then
            debug_log "JQ INSTALL: Dynamic detection successful, trying latest version"
            print_status "$YELLOW" "Downloading jq (latest detected version)..."

            if curl -fL --progress-bar "$dynamic_jq_url" -o "$INSTALL_DIR/jq" && [ -s "$INSTALL_DIR/jq" ]; then
                if chmod +x "$INSTALL_DIR/jq" && "$INSTALL_DIR/jq" --version >/dev/null 2>&1; then
                    debug_log "JQ INSTALL: Latest version installation completed successfully"
                    # Get version for display
                    jq_version=$("$INSTALL_DIR/jq" --version 2>/dev/null || echo "unknown")
                    print_status "$GREEN" "✓ jq installed (latest: $jq_version)"
                else
                    debug_log "JQ INSTALL: Latest version validation failed, trying fallback to stable version"
                    rm -f "$INSTALL_DIR/jq"
                    print_status "$YELLOW" "Latest version validation failed, trying stable version..."
                    # Fall through to stable version logic below
                    dynamic_jq_url=""
                fi
            else
                debug_log "JQ INSTALL: Latest version download failed, trying fallback to stable version"
                rm -f "$INSTALL_DIR/jq"
                print_status "$YELLOW" "Latest version download failed, trying stable version..."
                # Fall through to stable version logic below
                dynamic_jq_url=""
            fi
        else
            debug_log "JQ INSTALL: Dynamic detection failed, trying stable version"
            print_status "$YELLOW" "Could not detect latest version, using stable version..."
        fi

        # If dynamic detection failed, use our known stable version
        if [ -z "$dynamic_jq_url" ]; then
            debug_log "JQ INSTALL: Using stable version from $JQ_URL"
            print_status "$YELLOW" "Downloading jq (stable version v1.7.1)..."

            # Try primary stable version first
            if curl -fL --progress-bar "$JQ_URL" -o "$INSTALL_DIR/jq" && [ -s "$INSTALL_DIR/jq" ]; then
                if chmod +x "$INSTALL_DIR/jq" && "$INSTALL_DIR/jq" --version >/dev/null 2>&1; then
                    debug_log "JQ INSTALL: Stable version installation completed successfully"
                    jq_version=$("$INSTALL_DIR/jq" --version 2>/dev/null || echo "unknown")
                    print_status "$GREEN" "✓ jq installed (stable: $jq_version)"
                else
                    debug_log "JQ INSTALL: Stable version validation failed, trying fallback"
                    rm -f "$INSTALL_DIR/jq"
                    print_status "$YELLOW" "Stable version failed validation, trying alternative version..."

                    # Fallback to alternative version
                    if curl -fL --progress-bar "$JQ_FALLBACK_URL" -o "$INSTALL_DIR/jq" && [ -s "$INSTALL_DIR/jq" ]; then
                        if chmod +x "$INSTALL_DIR/jq" && "$INSTALL_DIR/jq" --version >/dev/null 2>&1; then
                            debug_log "JQ INSTALL: Fallback version installation completed successfully"
                            print_status "$GREEN" "✓ jq installed (fallback version v1.6)"
                        else
                            debug_log "JQ INSTALL: Fallback version validation failed"
                            print_status "$RED" "Error: Fallback jq version failed validation"
                            return 1
                        fi
                    else
                        print_status "$RED" "Error: Failed to download jq fallback version"
                        return 1
                    fi
                fi
            else
                debug_log "JQ INSTALL: Stable version download failed, trying fallback"
                rm -f "$INSTALL_DIR/jq"
                print_status "$YELLOW" "Stable version download failed, trying alternative version..."

                # Try fallback version
                if curl -fL --progress-bar "$JQ_FALLBACK_URL" -o "$INSTALL_DIR/jq" && [ -s "$INSTALL_DIR/jq" ]; then
                    if chmod +x "$INSTALL_DIR/jq" && "$INSTALL_DIR/jq" --version >/dev/null 2>&1; then
                        debug_log "JQ INSTALL: Fallback version installation completed successfully"
                        print_status "$GREEN" "✓ jq installed (fallback version v1.6)"
                    else
                        debug_log "JQ INSTALL: Fallback version validation failed"
                        print_status "$RED" "Error: Fallback jq version failed validation"
                        return 1
                    fi
                else
                    debug_log "JQ INSTALL: All download attempts failed"
                    print_status "$RED" "Error: Failed to download jq (all versions tried)"
                    return 1
                fi
            fi
        fi
    else
        print_status "$GREEN" "✓ jq already installed"
    fi
}

# Create documentation for installed scripts
create_script_documentation() {
    print_status "$BLUE" "Creating script documentation..."

    doc_file="$INSTALL_DIR/INSTALLED_SCRIPTS.md"

    cat >"$doc_file" <<'EOF'
# Starlink Monitor - Installed Scripts

This document lists all scripts installed by the Starlink monitoring system.

## Installation Directory Structure
```
/usr/local/starlink-monitor/
├── scripts/                 # Main utility scripts
│   ├── tests/              # Test and debug scripts  
│   └── [utility scripts]
├── config/                 # Configuration files
└── logs/                   # Log files
```

## Core Monitoring Scripts

### Main Scripts (in Starlink-RUTOS-Failover/)
- `starlink_monitor-rutos.sh` - Main monitoring daemon
- `starlink_logger-rutos.sh` - Logging system
- `check_starlink_api-rutos.sh` - API connectivity checker
- `99-pushover_notify-rutos.sh` - Hotplug notification handler

### Utility Scripts (in scripts/)
- `validate-config-rutos.sh` - Configuration validation
- `auto-detect-config-rutos.sh` - Autonomous system configuration detection
- `post-install-check-rutos.sh` - Unified post-install health check
- `system-status-rutos.sh` - System status checker
- `health-check-rutos.sh` - Health monitoring  
- `update-config-rutos.sh` - Configuration updater
- `upgrade-to-advanced-rutos.sh` - Config upgrade tool
- `merge-config-rutos.sh` - Configuration merger
- `restore-config-rutos.sh` - Configuration restore
- `cleanup-rutos.sh` - System cleanup utility
- `self-update-rutos.sh` - Self-update system
- `uci-optimizer-rutos.sh` - UCI configuration optimizer
- `verify-cron-rutos.sh` - Cron job verifier
- `update-cron-config-path-rutos.sh` - Cron path updater
- `upgrade-rutos.sh` - System upgrade helper
- `placeholder-utils.sh` - Utility functions library
- `fix-database-loop-rutos.sh` - Database loop repair tool
- `diagnose-database-loop-rutos.sh` - Database loop diagnostic
- `fix-database-spam-rutos.sh` - Fix database spam issues including "Can't open database" and optimization loops
- `system-maintenance-rutos.sh` - Generic system maintenance and issue fixing

### Test Scripts (in scripts/tests/)
- `test-pushover-rutos.sh` - Test Pushover notifications
- `test-monitoring-rutos.sh` - Test monitoring system
- `test-connectivity-rutos.sh` - Test network connectivity
- `test-colors-rutos.sh` - Test color output
- `test-method5-rutos.sh` - Test Method5 format compatibility
- `test-cron-cleanup-rutos.sh` - Test cron cleanup
- `test-notification-merge-rutos.sh` - Test notification merging
- `debug-notification-merge-rutos.sh` - Debug notification settings

## Usage Examples

### Running Tests
```bash
# Test all functionality
/usr/local/starlink-monitor/scripts/tests/test-monitoring-rutos.sh

# Test Pushover notifications
/usr/local/starlink-monitor/scripts/tests/test-pushover-rutos.sh

# Test configuration merge
/usr/local/starlink-monitor/scripts/tests/test-notification-merge-rutos.sh
```

### System Management  
```bash
# Check system status
/usr/local/starlink-monitor/scripts/system-status-rutos.sh

# Validate configuration
/usr/local/starlink-monitor/scripts/validate-config-rutos.sh

# Perform health check
/usr/local/starlink-monitor/scripts/health-check-rutos.sh
```

### Configuration Management
```bash
# Autonomous system detection and configuration
/usr/local/starlink-monitor/scripts/auto-detect-config-rutos.sh

# Update configuration
/usr/local/starlink-monitor/scripts/update-config-rutos.sh

# Merge configurations
/usr/local/starlink-monitor/scripts/merge-config-rutos.sh

# Restore from backup
/usr/local/starlink-monitor/scripts/restore-config-rutos.sh
```

### Database Troubleshooting
```bash
# Diagnose database loop issues
/usr/local/starlink-monitor/scripts/diagnose-database-loop-rutos.sh

# Fix database optimization loops
/usr/local/starlink-monitor/scripts/fix-database-loop-rutos.sh

# Fix database spam issue (enhanced user solution)
/usr/local/starlink-monitor/scripts/fix-database-spam-rutos.sh

# Check system status only
/usr/local/starlink-monitor/scripts/fix-database-loop-rutos.sh status
```

### System Maintenance
```bash
# Run automatic system maintenance (check and fix issues)
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh

# Check for issues only (no fixes)
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh check

# Generate maintenance report
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh report

# Run with debug output
DEBUG=1 /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh
```

## Debug Mode

Most scripts support debug mode by setting `DEBUG=1`:

```bash
DEBUG=1 /usr/local/starlink-monitor/scripts/test-monitoring-rutos.sh
```

## Configuration Debug

For configuration-related debugging, use `CONFIG_DEBUG=1`:

```bash
CONFIG_DEBUG=1 /usr/local/starlink-monitor/scripts/validate-config-rutos.sh
```

---
Generated by install-rutos.sh on $(date)
EOF

    print_status "$GREEN" "✓ Script documentation created: $doc_file"
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

    # Install all utility and test scripts with *-rutos.sh naming convention
    # Core utility scripts
    for script in \
        validate-config-rutos.sh \
        auto-detect-config-rutos.sh \
        post-install-check-rutos.sh \
        system-status-rutos.sh \
        health-check-rutos.sh \
        update-config-rutos.sh \
        upgrade-to-advanced-rutos.sh \
        merge-config-rutos.sh \
        restore-config-rutos.sh \
        cleanup-rutos.sh \
        self-update-rutos.sh \
        uci-optimizer-rutos.sh \
        verify-cron-rutos.sh \
        update-cron-config-path-rutos.sh \
        upgrade-rutos.sh \
        placeholder-utils.sh \
        fix-database-loop-rutos.sh \
        diagnose-database-loop-rutos.sh \
        fix-database-spam-rutos.sh \
        system-maintenance-rutos.sh \
        view-logs-rutos.sh; do
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

    # Install test and debug scripts (separate section for better organization)
    print_status "$BLUE" "Installing test and debug scripts..."
    for script in \
        test-pushover-rutos.sh \
        test-monitoring-rutos.sh \
        test-connectivity-rutos.sh \
        test-colors-rutos.sh \
        test-method5-rutos.sh \
        test-cron-cleanup-rutos.sh \
        test-notification-merge-rutos.sh \
        debug-notification-merge-rutos.sh; do
        # Try local script first
        if [ -f "$script_dir/$script" ]; then
            cp "$script_dir/$script" "$INSTALL_DIR/scripts/tests/$script"
            chmod +x "$INSTALL_DIR/scripts/tests/$script"
            print_status "$GREEN" "✓ $script installed (tests/)"
        elif [ -f "$script_dir/../scripts/$script" ]; then
            cp "$script_dir/../scripts/$script" "$INSTALL_DIR/scripts/tests/$script"
            chmod +x "$INSTALL_DIR/scripts/tests/$script"
            print_status "$GREEN" "✓ $script installed (tests/)"
        else
            print_status "$BLUE" "Downloading $script..."
            if download_file "$BASE_URL/scripts/$script" "$INSTALL_DIR/scripts/tests/$script"; then
                chmod +x "$INSTALL_DIR/scripts/tests/$script"
                print_status "$GREEN" "✓ $script downloaded and installed (tests/)"
            else
                print_status "$YELLOW" "⚠ Warning: Could not download $script"
            fi
        fi
    done

    print_status "$GREEN" "✓ All scripts installation completed"

    # Create script documentation
    create_script_documentation

    # Verify installation completeness
    print_status "$BLUE" "Verifying script installation..."

    utility_count=$(find "$INSTALL_DIR/scripts" -name "*-rutos.sh" -type f | wc -l)
    test_count=$(find "$INSTALL_DIR/scripts/tests" -name "*-rutos.sh" -type f 2>/dev/null | wc -l)

    print_status "$GREEN" "✓ Installation verification complete:"
    print_status "$BLUE" "  - Utility scripts installed: $utility_count"
    print_status "$BLUE" "  - Test scripts installed: $test_count"
    print_status "$BLUE" "  - Documentation: $INSTALL_DIR/INSTALLED_SCRIPTS.md"

    if [ "${DEBUG:-0}" = "1" ]; then
        debug_msg "Detailed script listing:"
        debug_msg "Utility scripts:"
        find "$INSTALL_DIR/scripts" -name "*-rutos.sh" -type f | sort | while IFS= read -r script; do
            debug_msg "  $(basename "$script")"
        done
        debug_msg "Test scripts:"
        find "$INSTALL_DIR/scripts/tests" -name "*-rutos.sh" -type f 2>/dev/null | sort | while IFS= read -r script; do
            debug_msg "  $(basename "$script")"
        done || debug_msg "  (No test scripts directory or scripts found)"
    fi
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
        if grep -qE "^(DEBUG_MODE|DRY_RUN|CELLULAR_.*_MEMBER|BACKUP_DIR|DATA_LIMIT_.*_THRESHOLD|ENABLE_PERFORMANCE_LOGGING|CELLULAR_BACKUP_IFACE)" "$primary_config" 2>/dev/null; then
            config_type="advanced"
            config_debug "Advanced markers found in config"
            if [ "$DEBUG" = "1" ]; then
                advanced_markers=$(grep -E "^(DEBUG_MODE|DRY_RUN|CELLULAR_.*_MEMBER|BACKUP_DIR|DATA_LIMIT_.*_THRESHOLD|ENABLE_PERFORMANCE_LOGGING|CELLULAR_BACKUP_IFACE)" "$primary_config" 2>/dev/null | head -3)
                config_debug "Advanced markers detected: $advanced_markers"
            fi
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

        # OPTIMIZATION: Efficient configuration update process
        # Old flow: Backup -> Merge -> Save -> Validate -> Backup -> Fix -> Save (4+ writes)
        # New flow: Backup -> Merge -> Validate -> Save (2 writes total)
        # This reduces I/O operations and eliminates redundant backup creation

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

        # Use the new intelligent merge system with integrated validation
        config_debug "=== STARTING OPTIMIZED MERGE WITH VALIDATION ==="
        print_status "$BLUE" "Merging settings from existing configuration..."

        # Call the new intelligent config merge function
        if intelligent_config_merge "$selected_template" "$primary_config" "$backup_file"; then
            print_status "$GREEN" "✓ Configuration merged successfully using intelligent merge"

            # Apply validation and formatting fixes in-place (without additional backups)
            print_status "$BLUE" "Applying configuration formatting validation..."

            # Check if we have the validation script available
            validate_script_path=""
            if [ -f "$INSTALL_DIR/scripts/validate-config-rutos.sh" ]; then
                validate_script_path="$INSTALL_DIR/scripts/validate-config-rutos.sh"
            elif [ -f "$(dirname "$0")/validate-config-rutos.sh" ]; then
                validate_script_path="$(dirname "$0")/validate-config-rutos.sh"
            fi

            if [ -n "$validate_script_path" ]; then
                # Run validation with repair but skip backup creation (we already have one)
                if SKIP_BACKUP=1 "$validate_script_path" "$primary_config" --repair; then
                    print_status "$GREEN" "✓ Configuration formatting validation completed"
                else
                    print_status "$YELLOW" "⚠ Configuration validation completed with warnings"
                fi
            else
                print_status "$YELLOW" "⚠ Validation script not found, skipping automatic formatting"
            fi

            print_status "$GREEN" "✓ Updated persistent configuration: $primary_config"
        else
            print_status "$RED" "✗ Intelligent merge failed!"
            # Restore backup
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$primary_config" 2>/dev/null
                print_status "$YELLOW" "✓ Configuration restored from backup"
            fi
            exit 1
        fi

    else
        # First time installation - no existing config
        print_status "$BLUE" "First time installation - creating new configuration"

        # Use basic template by default
        if cp "$temp_basic_template" "$primary_config"; then
            print_status "$GREEN" "✓ Initial configuration created from template"
            print_status "$YELLOW" "📋 Please edit $primary_config with your settings"

            # Apply validation formatting to new configuration as well
            print_status "$BLUE" "Applying configuration formatting validation..."

            # Check if we have the validation script available
            validate_script_path=""
            if [ -f "$INSTALL_DIR/scripts/validate-config-rutos.sh" ]; then
                validate_script_path="$INSTALL_DIR/scripts/validate-config-rutos.sh"
            elif [ -f "$(dirname "$0")/validate-config-rutos.sh" ]; then
                validate_script_path="$(dirname "$0")/validate-config-rutos.sh"
            fi

            if [ -n "$validate_script_path" ]; then
                # Run validation with repair for new config (no backup needed for fresh install)
                if SKIP_BACKUP=1 "$validate_script_path" "$primary_config" --repair; then
                    print_status "$GREEN" "✓ Configuration formatting validation completed"
                else
                    print_status "$YELLOW" "⚠ Configuration validation completed with warnings"
                fi
            fi

            # 🎯 AUTONOMOUS CONFIGURATION DETECTION - "Just make it work!"
            print_status "$BLUE" "🎯 Running autonomous configuration detection..."

            # Check if auto-detect script is available
            autodetect_script_path=""
            if [ -f "$INSTALL_DIR/scripts/auto-detect-config-rutos.sh" ]; then
                autodetect_script_path="$INSTALL_DIR/scripts/auto-detect-config-rutos.sh"
            elif [ -f "$(dirname "$0")/auto-detect-config-rutos.sh" ]; then
                autodetect_script_path="$(dirname "$0")/auto-detect-config-rutos.sh"
            fi

            if [ -n "$autodetect_script_path" ] && [ -x "$autodetect_script_path" ]; then
                print_status "$BLUE" "Running system auto-detection..."

                # Run auto-detection and capture results
                detection_results="/tmp/autodetect_results.$$"
                if "$autodetect_script_path" >"$detection_results" 2>/dev/null; then
                    print_status "$GREEN" "✓ System auto-detection completed successfully"

                    # Apply detected settings to configuration
                    print_status "$BLUE" "Applying auto-detected settings to configuration..."

                    # Source the detection results
                    # shellcheck disable=SC1090  # Dynamic file sourcing
                    . "$detection_results" 2>/dev/null || true

                    # Create a backup before applying auto-detected settings
                    cp "$primary_config" "${primary_config}.pre-autodetect" 2>/dev/null || true

                    # Apply auto-detected settings using sed (busybox compatible)
                    config_updated=0

                    # Update MWAN member and interface if detected
                    if [ -n "${DETECTED_MWAN_MEMBER:-}" ] && [ -n "${DETECTED_MWAN_INTERFACE:-}" ]; then
                        # Use busybox-compatible sed with explicit backup
                        if sed "s/^MWAN_MEMBER=.*/MWAN_MEMBER=\"$DETECTED_MWAN_MEMBER\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured MWAN member: $DETECTED_MWAN_MEMBER"
                            config_updated=1
                        fi

                        if sed "s/^MWAN_IFACE=.*/MWAN_IFACE=\"$DETECTED_MWAN_INTERFACE\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured MWAN interface: $DETECTED_MWAN_INTERFACE"
                            config_updated=1
                        fi
                    fi

                    # Update Starlink endpoint if detected
                    if [ -n "${DETECTED_STARLINK_IP:-}" ]; then
                        if sed "s/^STARLINK_IP=.*/STARLINK_IP=\"$DETECTED_STARLINK_IP\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured Starlink endpoint: $DETECTED_STARLINK_IP"
                            config_updated=1
                        fi
                    fi

                    # Update monitoring intervals if detected
                    if [ -n "${DETECTED_CHECK_INTERVAL:-}" ]; then
                        if sed "s/^CHECK_INTERVAL=.*/CHECK_INTERVAL=\"$DETECTED_CHECK_INTERVAL\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured check interval: ${DETECTED_CHECK_INTERVAL}s"
                            config_updated=1
                        fi
                    fi

                    # Update failure/recovery thresholds if detected
                    if [ -n "${DETECTED_FAILURE_THRESHOLD:-}" ]; then
                        if sed "s/^FAILURE_THRESHOLD=.*/FAILURE_THRESHOLD=\"$DETECTED_FAILURE_THRESHOLD\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured failure threshold: $DETECTED_FAILURE_THRESHOLD"
                            config_updated=1
                        fi
                    fi

                    if [ -n "${DETECTED_RECOVERY_THRESHOLD:-}" ]; then
                        if sed "s/^RECOVERY_THRESHOLD=.*/RECOVERY_THRESHOLD=\"$DETECTED_RECOVERY_THRESHOLD\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured recovery threshold: $DETECTED_RECOVERY_THRESHOLD"
                            config_updated=1
                        fi
                    fi

                    # Update routing metrics if detected (for failover control)
                    if [ -n "${DETECTED_METRIC_GOOD:-}" ]; then
                        if sed "s/^METRIC_GOOD=.*/METRIC_GOOD=\"$DETECTED_METRIC_GOOD\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured good routing metric: $DETECTED_METRIC_GOOD"
                            config_updated=1
                        fi
                    fi

                    if [ -n "${DETECTED_METRIC_BAD:-}" ]; then
                        if sed "s/^METRIC_BAD=.*/METRIC_BAD=\"$DETECTED_METRIC_BAD\"/" "$primary_config" >"${primary_config}.tmp" &&
                            mv "${primary_config}.tmp" "$primary_config"; then
                            print_status "$GREEN" "  ✓ Auto-configured bad routing metric: $DETECTED_METRIC_BAD"
                            config_updated=1
                        fi
                    fi

                    if [ "$config_updated" -eq 1 ]; then
                        print_status "$GREEN" "✓ Configuration automatically optimized for your system"
                        print_status "$BLUE" "  Backup of original: ${primary_config}.pre-autodetect"
                        print_status "$YELLOW" "💡 Review auto-detected settings: vi $primary_config"
                    else
                        print_status "$YELLOW" "⚠ No auto-configuration applied (settings may already be optimal)"
                    fi

                    # Cleanup detection results
                    rm -f "$detection_results" 2>/dev/null || true
                else
                    print_status "$YELLOW" "⚠ Auto-detection completed with warnings - using template defaults"
                    rm -f "$detection_results" 2>/dev/null || true
                fi
            else
                print_status "$YELLOW" "⚠ Auto-detection script not available - using template defaults"
                print_status "$BLUE" "💡 Manual configuration required: vi $primary_config"
            fi
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

    # Install system configuration for dynamic testing and validation
    if [ -f "$config_dir/system-config.sh" ]; then
        cp "$config_dir/system-config.sh" "$INSTALL_DIR/config/system-config.sh" 2>/dev/null || true
        print_status "$GREEN" "✓ System configuration installed for dynamic testing"
    elif download_file "$BASE_URL/config/system-config.sh" "$INSTALL_DIR/config/system-config.sh" 2>/dev/null; then
        print_status "$GREEN" "✓ System configuration downloaded and installed"
    else
        print_status "$YELLOW" "⚠ System configuration not available (tests will use defaults)"
    fi

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
        sed -i '/^0 \*\/6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/system-maintenance-rutos\.sh auto$/d' "$temp_cron" 2>/dev/null || true

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

    # Check if our scripts already have cron entries (check each script individually)
    existing_monitor=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    existing_logger=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
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
    print_status "$BLUE" "  starlink_monitor-rutos.sh: $existing_monitor entries"
    print_status "$BLUE" "  starlink_logger-rutos.sh: $existing_logger entries"
    print_status "$BLUE" "  check_starlink_api: $existing_api_check entries"
    print_status "$BLUE" "  system-maintenance-rutos.sh: $existing_maintenance entries"

    # Add cron entries for scripts that don't have any entries yet
    entries_added=0

    # Add monitoring script if not present
    if [ "$existing_monitor" -eq 0 ]; then
        print_status "$BLUE" "Adding starlink_monitor cron entry..."
        cat >>"$CRON_FILE" <<EOF
# Starlink monitor - Added by install script $(date +%Y-%m-%d)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_monitor-rutos.sh
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
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh $INSTALL_DIR/scripts/starlink_logger-rutos.sh
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
         s|^\([^#].*system-maintenance-rutos\.sh.*\)|# COMMENTED BY UNINSTALL $date_stamp: \1|g; \
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

# Setup recovery information for firmware upgrade scenarios
setup_recovery_information() {
    print_status "$BLUE" "Setting up firmware upgrade recovery information..."

    # Get current version
    current_version=""
    if [ -f "$VERSION_FILE" ]; then
        current_version=$(tr -d '\n\r ' <"$VERSION_FILE" 2>/dev/null || echo "")
    fi

    # Fallback to script version if VERSION file not available
    if [ -z "$current_version" ]; then
        current_version="$SCRIPT_VERSION"
    fi

    print_status "$BLUE" "Current version: $current_version"

    # Store version information in persistent config
    if store_version_in_persistent_config "$current_version"; then
        print_status "$GREEN" "✓ Version information stored for recovery"
    else
        print_status "$YELLOW" "⚠ Warning: Could not store version information"
    fi

    # Create version-pinned recovery script
    if create_version_pinned_recovery_script "$current_version"; then
        print_status "$GREEN" "✓ Version-pinned recovery script created"
    else
        print_status "$YELLOW" "⚠ Warning: Could not create recovery script"
    fi

    print_status "$GREEN" "✓ Firmware upgrade recovery configured"
    print_status "$BLUE" "  Recovery will reinstall v$current_version to respect your update policies"
}

# Store version information in persistent config for recovery
store_version_in_persistent_config() {
    version="$1"
    persistent_config="$PERSISTENT_CONFIG_DIR/config.sh"

    if [ ! -f "$persistent_config" ]; then
        log_message "ERROR" "Persistent config not found: $persistent_config"
        return 1
    fi

    # Remove any existing recovery information section
    if grep -q "^# Recovery Information" "$persistent_config" 2>/dev/null; then
        # Create temp file without the recovery section
        temp_config="/tmp/config_recovery_update.$$"
        awk '/^# Recovery Information/,/^# ==============================================================================$/ {next} {print}' \
            "$persistent_config" >"$temp_config"
        mv "$temp_config" "$persistent_config"
    fi

    # Add new recovery information section
    cat >>"$persistent_config" <<EOF

# ==============================================================================
# Recovery Information - DO NOT EDIT MANUALLY
# This section is automatically managed by the installation and self-update system
# ==============================================================================
# Version installed on this system (for firmware upgrade recovery)
INSTALLED_VERSION="$version"
# Installation timestamp  
INSTALLED_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
# Recovery URL (pinned to this version for consistency)
RECOVERY_INSTALL_URL="https://raw.githubusercontent.com/$GITHUB_REPO/v$version/scripts/install-rutos.sh"
# ==============================================================================
EOF

    log_message "INFO" "Stored version $version in persistent config for recovery"
    return 0
}

# Create version-pinned recovery installation script
create_version_pinned_recovery_script() {
    version="$1"
    recovery_script="$PERSISTENT_CONFIG_DIR/install-pinned-version.sh"

    # Ensure persistent config directory exists
    mkdir -p "$PERSISTENT_CONFIG_DIR" 2>/dev/null || {
        log_message "ERROR" "Cannot create persistent config directory"
        return 1
    }

    # Create the recovery script with embedded version information
    cat >"$recovery_script" <<EOF
#!/bin/sh
# ==============================================================================
# Version-Pinned Recovery Installation Script
# Generated by install-rutos.sh v$SCRIPT_VERSION
# 
# This script installs the exact version that was previously running on this
# system before firmware upgrade. It ensures consistency with user's update
# delay policies by not forcing newer versions during recovery.
# ==============================================================================

set -eu

# Pinned version information
PINNED_VERSION="$version"
GITHUB_REPO="$GITHUB_REPO"
GITHUB_BRANCH="$GITHUB_BRANCH"
RECOVERY_URL="https://raw.githubusercontent.com/\$GITHUB_REPO/v\$PINNED_VERSION/scripts/install-rutos.sh"
FALLBACK_URL="https://raw.githubusercontent.com/\$GITHUB_REPO/\$GITHUB_BRANCH/scripts/install-rutos.sh"
CREATED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

echo "=============================================="
echo "Starlink Monitor - Version-Pinned Recovery"
echo "Pinned Version: v\$PINNED_VERSION"
echo "Created: \$CREATED_DATE"
echo "=============================================="

echo "Attempting to install pinned version v\$PINNED_VERSION..."

# Try pinned version first
if curl -fsSL --connect-timeout 10 --max-time 60 "\$RECOVERY_URL" | sh; then
    echo "✓ Successfully installed pinned version v\$PINNED_VERSION"
    echo "✓ Your update delay policies are respected - no forced upgrades"
    exit 0
else
    echo "⚠ Pinned version installation failed, trying current stable version"
    echo "⚠ This may install a newer version than originally configured"
    
    if curl -fsSL --connect-timeout 10 --max-time 60 "\$FALLBACK_URL" | sh; then
        echo "✓ Fallback installation completed"
        echo "ℹ Check your configuration: newer version may have been installed"
        exit 0
    else
        echo "✗ Both pinned and fallback installations failed"
        echo "✗ Manual installation required"
        exit 1
    fi
fi
EOF

    # Make script executable
    chmod +x "$recovery_script"

    log_message "INFO" "Version-pinned recovery script created: $recovery_script"
    return 0
}
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

# Enhanced configuration restoration with validation and safety features
restore_user_configuration() {
    log_restore "Starting enhanced configuration restoration..."
    
    # Check if persistent config exists
    if [ ! -f "$PERSISTENT_CONFIG_DIR/config.sh" ]; then
        log_restore "No persistent configuration found to restore"
        return 0
    fi
    
    # Check if installation directory exists
    if [ ! -d "$INSTALL_DIR/config" ]; then
        log_restore "WARNING: Installation directory not found, config restore skipped"
        return 1
    fi
    
    # Step 1: Validate persistent configuration
    log_restore "Step 1: Validating persistent configuration..."
    if ! validate_persistent_config "$PERSISTENT_CONFIG_DIR/config.sh"; then
        log_restore "ERROR: Persistent configuration validation failed"
        log_restore "Keeping fresh installation configuration for safety"
        return 1
    fi
    
    # Step 2: Create backup of fresh installation config
    log_restore "Step 2: Creating backup of fresh installation configuration..."
    fresh_config_backup="$INSTALL_DIR/config/config.sh.pre-restore.$(date +%Y%m%d_%H%M%S)"
    if cp "$INSTALL_DIR/config/config.sh" "$fresh_config_backup"; then
        log_restore "Fresh configuration backed up to: $fresh_config_backup"
    else
        log_restore "WARNING: Failed to backup fresh configuration"
    fi
    
    # Step 3: Check template version compatibility
    log_restore "Step 3: Checking template version compatibility..."
    check_template_compatibility
    
    # Step 4: Use intelligent merge instead of direct overwrite
    log_restore "Step 4: Performing intelligent configuration merge..."
    temp_merged_config="/tmp/merged_config_restore.tmp"
    
    if merge_configurations "$INSTALL_DIR/config/config.sh" "$PERSISTENT_CONFIG_DIR/config.sh" "$temp_merged_config"; then
        # Validate merged configuration
        if validate_persistent_config "$temp_merged_config"; then
            cp "$temp_merged_config" "$INSTALL_DIR/config/config.sh"
            log_restore "Configuration successfully restored using intelligent merge"
            log_restore "Fresh config backup available at: $fresh_config_backup"
        else
            log_restore "ERROR: Merged configuration validation failed"
            log_restore "Keeping fresh installation configuration"
            rm -f "$temp_merged_config"
            return 1
        fi
    else
        log_restore "WARNING: Intelligent merge failed, using direct restore with validation"
        # Fallback to direct copy but with validation
        if cp "$PERSISTENT_CONFIG_DIR/config.sh" "$INSTALL_DIR/config/config.sh"; then
            log_restore "User configuration restored from persistent storage (direct copy)"
        else
            log_restore "ERROR: Failed to restore user configuration"
            return 1
        fi
    fi
    
    # Cleanup
    rm -f "$temp_merged_config"
    log_restore "Configuration restoration completed successfully"
    return 0
}

# Validate persistent configuration for corruption and required settings
validate_persistent_config() {
    config_file="$1"
    
    # Use dedicated validation script if available
    if [ -f "$INSTALL_DIR/scripts/validate-persistent-config-rutos.sh" ]; then
        log_restore "Using dedicated validation script"
        if "$INSTALL_DIR/scripts/validate-persistent-config-rutos.sh" "$config_file" >>"$RESTORE_LOG" 2>&1; then
            return 0
        else
            return 1
        fi
    fi
    
    # Fallback to embedded validation
    log_restore "Using embedded validation (dedicated script not available)"
    
    # Check if file is readable
    if [ ! -r "$config_file" ]; then
        log_restore "Configuration file is not readable"
        return 1
    fi
    
    # Check file size (should not be empty or too small)
    file_size=$(wc -c < "$config_file" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 100 ]; then
        log_restore "Configuration file is too small ($file_size bytes) - likely corrupted"
        return 1
    fi
    
    # Check for shell syntax errors
    if ! sh -n "$config_file" 2>/dev/null; then
        log_restore "Configuration file has shell syntax errors"
        return 1
    fi
    
    # Check for required settings (not placeholder values)
    required_settings="STARLINK_IP MWAN_IFACE MWAN_MEMBER"
    for setting in $required_settings; do
        if ! grep -q "^${setting}=" "$config_file" 2>/dev/null; then
            log_restore "Missing required setting: $setting"
            return 1
        fi
    done
    
    log_restore "Embedded validation passed"
    return 0
}

# Check template version compatibility
check_template_compatibility() {
    # Get current template version if available
    current_template_version=""
    if [ -f "$INSTALL_DIR/config/config.template.sh" ]; then
        current_template_version=$(grep "^# Template Version:" "$INSTALL_DIR/config/config.template.sh" 2>/dev/null | cut -d':' -f2- | tr -d ' ')
    fi
    
    # Get persistent config template info if available
    persistent_template_info=""
    if grep -q "^# Template Version:" "$PERSISTENT_CONFIG_DIR/config.sh" 2>/dev/null; then
        persistent_template_info=$(grep "^# Template Version:" "$PERSISTENT_CONFIG_DIR/config.sh" | cut -d':' -f2- | tr -d ' ')
    fi
    
    if [ -n "$current_template_version" ] && [ -n "$persistent_template_info" ]; then
        if [ "$current_template_version" != "$persistent_template_info" ]; then
            log_restore "Template version mismatch detected:"
            log_restore "  Current: $current_template_version"
            log_restore "  Persistent: $persistent_template_info"
            log_restore "Will use intelligent merge to handle compatibility"
        else
            log_restore "Template versions match: $current_template_version"
        fi
    else
        log_restore "Template version information not available for comparison"
    fi
}

# Merge configurations intelligently (simplified version for restore context)
merge_configurations() {
    fresh_config="$1"
    persistent_config="$2"
    output_config="$3"
    
    log_restore "Merging configurations: fresh + persistent -> output"
    
    # Start with fresh config as base
    cp "$fresh_config" "$output_config"
    
    # Extract user settings from persistent config and apply to output
    user_settings="STARLINK_IP MWAN_IFACE MWAN_MEMBER PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD RUTOS_IP"
    
    for setting in $user_settings; do
        if grep -q "^${setting}=" "$persistent_config" 2>/dev/null; then
            persistent_value=$(grep "^${setting}=" "$persistent_config" | head -1)
            
            # Skip placeholder values
            if echo "$persistent_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE)" 2>/dev/null; then
                log_restore "Skipping placeholder value for $setting"
                continue
            fi
            
            # Apply setting to output config
            if grep -q "^${setting}=" "$output_config" 2>/dev/null; then
                # Replace existing setting
                setting_escaped=$(echo "$setting" | sed 's/[[\.*^$()+?{|]/\\&/g')
                sed -i "s|^${setting_escaped}=.*|${persistent_value}|" "$output_config" 2>/dev/null
            else
                # Add new setting
                echo "$persistent_value" >> "$output_config"
            fi
            log_restore "Merged setting: $setting"
        fi
    done
    
    # Verify output config is valid
    if [ -f "$output_config" ] && [ -s "$output_config" ]; then
        return 0
    else
        return 1
    fi
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
        
        # Try version-pinned recovery first (respects user's update delay policies)
        if [ -f "$PERSISTENT_CONFIG_DIR/install-pinned-version.sh" ]; then
            log_restore "Using version-pinned recovery to respect update delay policies"
            log_restore "Executing: $PERSISTENT_CONFIG_DIR/install-pinned-version.sh"
            
            if sh "$PERSISTENT_CONFIG_DIR/install-pinned-version.sh" >>"$RESTORE_LOG" 2>&1; then
                log_restore "Version-pinned installation completed successfully"
                restoration_success=true
            else
                log_restore "Version-pinned installation failed, checking recovery script for details"
                # Log last few lines of recovery script output for debugging
                if [ -f "$RESTORE_LOG" ]; then
                    log_restore "Last 5 lines of recovery output:"
                    tail -5 "$RESTORE_LOG" 2>/dev/null | while IFS= read -r line; do
                        log_restore "  $line"
                    done || log_restore "  (Unable to read recovery log)"
                fi
                
                log_restore "Trying fallback to latest version"
                restoration_success=false
            fi
        else
            log_restore "No version-pinned recovery script available"
            restoration_success=false
        fi
        
        # Fallback to latest version if version-pinned recovery failed or unavailable
        if [ "$restoration_success" != "true" ]; then
            log_restore "Attempting latest version installation (fallback)"
            
            # Try multiple methods for maximum reliability
            installation_methods="
                curl_direct:curl -fsSL \"\${BASE_URL}/scripts/install-rutos.sh\" | sh
                curl_download:curl -fsSL \"\${BASE_URL}/scripts/install-rutos.sh\" -o /tmp/install.sh && sh /tmp/install.sh && rm -f /tmp/install.sh
                wget_direct:wget -qO- \"\${BASE_URL}/scripts/install-rutos.sh\" | sh
                wget_download:wget -qO /tmp/install.sh \"\${BASE_URL}/scripts/install-rutos.sh\" && sh /tmp/install.sh && rm -f /tmp/install.sh
            "
            
            method_success=false
            for method_line in \$installation_methods; do
                method_name=\$(echo "\$method_line" | cut -d: -f1)
                method_command=\$(echo "\$method_line" | cut -d: -f2-)
                
                log_restore "Trying installation method: \$method_name"
                log_restore "Command: \$method_command"
                
                if eval "\$method_command" >>\"\$RESTORE_LOG\" 2>&1; then
                    log_restore "\$method_name installation completed successfully"
                    method_success=true
                    break
                else
                    log_restore "\$method_name installation failed, trying next method"
                fi
            done
            
            if [ "\$method_success" = "true" ]; then
                restoration_success=true
                log_restore "Installation completed using fallback method"
            else
                log_restore "All installation methods failed"
                restoration_success=false
            fi
        fi
        
        # Final check for restoration success
        if [ "\$restoration_success" = "true" ]; then
            
        # Final check for restoration success
        if [ "$restoration_success" = "true" ]; then
            # Enhanced configuration restoration with validation and backup
            restore_user_configuration
            
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
            log_restore "ERROR: All restoration methods failed!"
            log_restore "Manual reinstallation required"
            log_restore ""
            log_restore "Manual recovery options:"
            log_restore "1. Standard installation:"
            log_restore "   curl -fsSL ${BASE_URL}/scripts/install-rutos.sh | sh"
            log_restore "2. Alternative with wget:"
            log_restore "   wget -qO- ${BASE_URL}/scripts/install-rutos.sh | sh"
            log_restore "3. Download and inspect first:"
            log_restore "   curl -fsSL ${BASE_URL}/scripts/install-rutos.sh -o /tmp/install.sh"
            log_restore "   cat /tmp/install.sh  # inspect the script"
            log_restore "   sh /tmp/install.sh   # run if it looks correct"
            log_restore "4. Check network connectivity:"
            log_restore "   ping github.com"
            log_restore "   curl -I https://github.com/markus-lassfolk/rutos-starlink-failover"
            log_restore ""
            log_restore "Your configuration is preserved at: $PERSISTENT_CONFIG_DIR/config.sh"
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
    # Enhanced backup with validation before shutdown
    log_restore "Performing enhanced configuration backup before shutdown..."
    
    if [ -f "$INSTALL_DIR/config/config.sh" ]; then
        mkdir -p "$PERSISTENT_CONFIG_DIR"
        
        # Validate current config before backing it up
        if validate_persistent_config "$INSTALL_DIR/config/config.sh"; then
            # Create timestamped backup
            backup_timestamp=$(date +%Y%m%d_%H%M%S)
            backup_file="$PERSISTENT_CONFIG_DIR/config.sh.backup.$backup_timestamp"
            
            # Keep current config as main backup
            cp "$INSTALL_DIR/config/config.sh" "$PERSISTENT_CONFIG_DIR/config.sh"
            cp "$INSTALL_DIR/config/config.sh" "$backup_file"
            
            log_restore "Configuration backed up to persistent storage"
            log_restore "Timestamped backup created: $backup_file"
            
            # Add template version info to backup for compatibility tracking
            if [ -f "$INSTALL_DIR/config/config.template.sh" ]; then
                template_version=$(grep "^# Template Version:" "$INSTALL_DIR/config/config.template.sh" 2>/dev/null | head -1)
                if [ -n "$template_version" ]; then
                    echo "$template_version" >> "$PERSISTENT_CONFIG_DIR/config.sh"
                    log_restore "Template version info added to backup"
                fi
            fi
            
            # Cleanup old backups (keep last 5)
            find "$PERSISTENT_CONFIG_DIR" -name "config.sh.backup.*" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
            
        else
            log_restore "WARNING: Current configuration failed validation, not backing up"
            log_restore "This may indicate configuration corruption - manual review recommended"
        fi
    else
        log_restore "No configuration file found to backup"
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

    debug_log "STEP 10: Setting up firmware upgrade recovery"
    setup_recovery_information

    debug_log "==================== INSTALLATION COMPLETE ===================="
    print_status "$GREEN" "=== Installation Complete ==="
    printf "\n"

    # Determine available editor
    available_editor=""
    for editor in nano vi vim; do
        if command -v "$editor" >/dev/null 2>&1; then
            available_editor="$editor"
            break
        fi
    done

    # Streamlined next steps - essential actions only
    print_status "$CYAN" "🎯 Next Steps:"
    print_status "$YELLOW" "1. Edit configuration: $available_editor $PERSISTENT_CONFIG_DIR/config.sh"
    print_status "$YELLOW" "   • Update MWAN_IFACE and MWAN_MEMBER for your network"
    print_status "$YELLOW" "   • Configure Pushover tokens (optional but recommended)"
    print_status "$YELLOW" "2. Run post-install validation: $INSTALL_DIR/scripts/post-install-check-rutos.sh"
    print_status "$YELLOW" "3. Configure mwan3 according to documentation"
    print_status "$YELLOW" "4. Start monitoring: The system will auto-start after configuration"
    printf "\n"

    print_status "$GREEN" "✅ READY TO GO:"
    print_status "$GREEN" "• Basic monitoring works with minimal configuration"
    print_status "$GREEN" "• Advanced features are optional and can be enabled later"
    print_status "$GREEN" "• Run the post-install check to verify everything is working"
    printf "\n"

    print_status "$BLUE" "📁 Important Paths:"
    print_status "$BLUE" "• Config: $PERSISTENT_CONFIG_DIR/config.sh"
    print_status "$BLUE" "• Scripts: $INSTALL_DIR/scripts/"
    print_status "$BLUE" "• Logs: $LOG_FILE"
    print_status "$BLUE" "• Uninstall: $INSTALL_DIR/uninstall.sh"
    printf "\n"

    if [ "${DEBUG:-0}" != "1" ]; then
        print_status "$CYAN" "💡 Need help? Run with DEBUG=1 for detailed output"
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
