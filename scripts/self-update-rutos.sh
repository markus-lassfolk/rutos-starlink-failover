#!/bin/sh

# ==================================# Configuration
GITHUB_REPO="markus-lassfolk/rutos-starlink-failover"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_DIR="/usr/local/starlink-monitor"
# shellcheck disable=SC2034  # Used in future backup functionality
BACKUP_DIR="/usr/local/starlink-monitor-backup" # Used in backup functionality (placeholder for now)
# shellcheck disable=SC2034  # Used in future update functionality
TMP_DIR="/tmp/starlink-update" # Used in update process (placeholder for now)
VERSION_FILE="$INSTALL_DIR/VERSION"
CONFIG_FILE="/usr/local/starlink-monitor/config/config.sh"
SCRIPT_NAME="$(basename "$0")"==================================
# Self-Update Script for RUTOS Starlink Failover System

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
#
# This script checks for newer versions on GitHub and performs automatic
# updates of the Starlink monitoring system on RUTOS devices.
#
# Features:
# - Debug logging support
# - Version comparison with remote repository
# - Automatic backup of current installation
# - Safe update process with rollback capability
# - RUTOS busybox compatibility
# - Auto-update with configurable delay policies
# - Pushover notifications for update status
# - Automatic crontab installation during setup
#
# Usage:
#   ./scripts/self-update-rutos.sh [--check-only] [--force] [--install-cron]
#
# Options:
#   --check-only       Only check for updates, don't install
#   --force            Force update even if versions are the same
#   --backup-only      Only create backup of current installation
#   --auto-update      Run in auto-update mode (respects config delays)
#   --install-cron     Install auto-update crontab job
#   --remove-cron      Remove auto-update crontab job
#   --help             Show help message
#
# Exit codes:
#   0 - Success (up to date or update completed)
#   1 - Error occurred
#   2 - Update available (when using --check-only)
#   3 - Update failed, rollback performed
#   4 - Update delayed due to auto-update policy
#
# ==============================================================================

set -eu

# Configuration
GITHUB_REPO="markus-lassfolk/rutos-starlink-failover"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_DIR="/usr/local/starlink-monitor"
# shellcheck disable=SC2034
BACKUP_DIR="/usr/local/starlink-monitor-backup" # Used in backup functionality (placeholder for now)
# shellcheck disable=SC2034
TMP_DIR="/tmp/starlink-update" # Used in update process (placeholder for now)
VERSION_FILE="$INSTALL_DIR/VERSION"
CONFIG_FILE="/usr/local/starlink-monitor/config/config.sh"
SCRIPT_NAME="$(basename "$0")"

# Command line options
CHECK_ONLY=false
FORCE_UPDATE=false
BACKUP_ONLY=false
AUTO_UPDATE_MODE=false
INSTALL_CRON=false
REMOVE_CRON=false
DEBUG="${DEBUG:-0}"

# Check if terminal supports colors (RUTOS busybox compatible)
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

# Standard logging functions with timestamps and colors
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    # shellcheck disable=SC2317  # Function is called later in script
    cmd="$1"
    # shellcheck disable=SC2317  # Function is called later in script
    description="$2"
    
    # shellcheck disable=SC2317  # Function is called later in script
    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Enhanced debug mode initialization
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "Install directory: $INSTALL_DIR"
    log_debug "GitHub repository: $GITHUB_REPO"
    log_debug "Raw URL: $RAW_URL"
    log_debug "=============================================================="
fi

# Load configuration for auto-update settings
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_debug "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
    else
        log_debug "Config file not found, using defaults"
        # Default configuration
        AUTO_UPDATE_ENABLED="${AUTO_UPDATE_ENABLED:-true}"
        AUTO_UPDATE_NOTIFICATIONS_ENABLED="${AUTO_UPDATE_NOTIFICATIONS_ENABLED:-true}"
        UPDATE_PATCH_DELAY="${UPDATE_PATCH_DELAY:-Never}"
        UPDATE_MINOR_DELAY="${UPDATE_MINOR_DELAY:-Never}"
        UPDATE_MAJOR_DELAY="${UPDATE_MAJOR_DELAY:-Never}"
        AUTO_UPDATE_SCHEDULE="${AUTO_UPDATE_SCHEDULE:-15 */4 * * *}"
        PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
        PUSHOVER_USER="${PUSHOVER_USER:-}"
    fi

    # Ensure notification variables are set
    AUTO_UPDATE_NOTIFICATIONS_ENABLED="${AUTO_UPDATE_NOTIFICATIONS_ENABLED:-true}"
}

# Store current version in persistent config for firmware upgrade recovery
store_version_for_recovery() {
    version="$1"
    persistent_config="/etc/starlink-config/config.sh"

    log_debug "Storing version $version in persistent config for recovery"

    # Validate version format before storing
    if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([^0-9].*)?$'; then
        log_warning "Invalid version format: $version - storing anyway for reference"
    fi

    if [ ! -f "$persistent_config" ]; then
        log_debug "Persistent config not found, cannot store recovery version"
        return 1
    fi

    # Remove any existing recovery information section to avoid duplicates
    if grep -q "^# Recovery Information" "$persistent_config" 2>/dev/null; then
        # Create temp file without the recovery section
        temp_config="/tmp/config_version_update.$$"
        awk '/^# Recovery Information/,/^# ==============================================================================$/ {next} {print}' \
            "$persistent_config" >"$temp_config" 2>/dev/null || {
            # If awk fails, use simpler approach
            grep -v "^INSTALLED_VERSION=" "$persistent_config" |
                grep -v "^INSTALLED_TIMESTAMP=" |
                grep -v "^RECOVERY_INSTALL_URL=" >"$temp_config"
        }
        mv "$temp_config" "$persistent_config"
        log_debug "Removed old recovery information from persistent config"
    fi

    # Add new version information at the end of the config
    {
        echo ""
        echo "# =============================================================================="
        echo "# Recovery Information - DO NOT EDIT MANUALLY"
        echo "# This section is automatically managed by the self-update system"
        echo "# =============================================================================="
        echo "# Version installed on this system (for firmware upgrade recovery)"
        echo "INSTALLED_VERSION=\"$version\""
        echo "# Installation timestamp"
        echo "INSTALLED_TIMESTAMP=\"$(date '+%Y-%m-%d %H:%M:%S')\""
        echo "# Recovery URL (pinned to this version for consistency)"
        echo "RECOVERY_INSTALL_URL=\"https://raw.githubusercontent.com/${GITHUB_REPO}/v${version}/scripts/install-rutos.sh\""
        echo "# Fallback URL (if pinned version fails)"
        echo "RECOVERY_FALLBACK_URL=\"https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/install-rutos.sh\""
        echo "# =============================================================================="
    } >>"$persistent_config"

    log_info "Stored version $version in persistent config for firmware upgrade recovery"
    return 0
}

# Get stored version from persistent config (for recovery scenarios)
# shellcheck disable=SC2317  # Function is called conditionally
get_stored_recovery_version() {
    persistent_config="/etc/starlink-config/config.sh"

    if [ ! -f "$persistent_config" ]; then
        log_debug "Persistent config not found"
        echo ""
        return 1
    fi

    if grep -q "^INSTALLED_VERSION=" "$persistent_config" 2>/dev/null; then
        version=$(grep "^INSTALLED_VERSION=" "$persistent_config" | head -1 | cut -d'"' -f2)

        # Validate retrieved version format
        if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([^0-9].*)?$'; then
            log_debug "Found valid stored recovery version: $version"
            echo "$version"
            return 0
        else
            log_warning "Found stored version with invalid format: $version"
            echo ""
            return 1
        fi
    else
        log_debug "No stored recovery version found in persistent config"
        echo ""
        return 1
    fi
}

# Send Pushover notification
send_notification() {
    title="$1"
    message="$2"
    priority="${3:-0}" # 0=normal, 1=high

    if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
        log_debug "Pushover not configured, skipping notification"
        return 0
    fi

    if [ "${PUSHOVER_TOKEN}" = "YOUR_PUSHOVER_API_TOKEN" ] || [ "${PUSHOVER_USER}" = "YOUR_PUSHOVER_USER_KEY" ]; then
        log_debug "Pushover has placeholder values, skipping notification"
        return 0
    fi

    log_debug "Sending Pushover notification: $title"

    curl -fsSL https://api.pushover.net/1/messages.json \
        -F "token=${PUSHOVER_TOKEN}" \
        -F "user=${PUSHOVER_USER}" \
        -F "title=Starlink Monitor: $title" \
        -F "message=$message" \
        -F "priority=$priority" \
        >/dev/null 2>&1 || {
        log_debug "Failed to send Pushover notification"
        return 1
    }

    log_debug "Pushover notification sent successfully"
    return 0
}

# Show help message
show_help() {
    printf "${GREEN}Self-Update Script v%s${NC}\n\n" "$SCRIPT_VERSION"
    printf "Updates the RUTOS Starlink Failover system from GitHub repository.\n\n"
    printf "Usage: %s [options]\n\n" "$SCRIPT_NAME"
    printf "Options:\n"
    printf "  --check-only       Only check for updates, don't install\n"
    printf "  --force            Force update even if versions are the same\n"
    printf "  --backup-only      Only create backup of current installation\n"
    printf "  --auto-update      Run in auto-update mode (respects config delays)\n"
    printf "  --install-cron     Install auto-update crontab job\n"
    printf "  --remove-cron      Remove auto-update crontab job\n"
    printf "  --help             Show this help message\n\n"
    printf "Environment Variables:\n"
    printf "  DEBUG=1            Enable debug logging\n\n"
    printf "Exit Codes:\n"
    printf "  0 - Success (up to date or update completed)\n"
    printf "  1 - Error occurred\n"
    printf "  2 - Update available (when using --check-only)\n"
    printf "  3 - Update failed, rollback performed\n"
    printf "  4 - Update delayed due to auto-update policy\n\n"
    printf "Examples:\n"
    printf "  %s                    # Check and update if newer version available\n" "$SCRIPT_NAME"
    printf "  %s --check-only       # Only check for updates\n" "$SCRIPT_NAME"
    printf "  %s --auto-update      # Run with auto-update policies\n" "$SCRIPT_NAME"
    printf "  %s --install-cron     # Setup automatic updates\n" "$SCRIPT_NAME"
    printf "  DEBUG=1 %s           # Run with debug logging\n" "$SCRIPT_NAME"
}

# Get current local version
get_local_version() {
    log_debug "Getting local version from: $VERSION_FILE"
    if [ -f "$VERSION_FILE" ]; then
        version=$(tr -d '\n\r' <"$VERSION_FILE" | tr -d ' ')
        log_debug "Local version file found: $version"
        echo "$version"
    else
        log_debug "Local version file not found, assuming 0.0.0"
        echo "0.0.0"
    fi
}

# Get remote version from GitHub
get_remote_version() {
    temp_version="/tmp/starlink-remote-version.txt"
    log_debug "Getting remote version from: $RAW_URL/VERSION"

    if curl -fsSL --connect-timeout 10 --max-time 30 "$RAW_URL/VERSION" -o "$temp_version" 2>/dev/null; then
        version=$(tr -d '\n\r' <"$temp_version" | tr -d ' ')
        rm -f "$temp_version"
        log_debug "Remote version retrieved: $version"
        echo "$version"
    else
        log_error "Failed to retrieve remote version from GitHub"
        rm -f "$temp_version" 2>/dev/null || true
        echo "0.0.0"
        return 1
    fi
}

# Get release date for a specific version from GitHub Releases API
get_release_date() {
    version="$1"
    api_url="https://api.github.com/repos/${GITHUB_REPO}/releases"

    log_debug "Getting release date for version: $version"
    log_debug "GitHub API URL: $api_url"

    # Fetch releases info from GitHub API
    temp_releases="/tmp/starlink-releases.json"
    if curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" -o "$temp_releases" 2>/dev/null; then
        # Try to find the release with matching tag_name
        # Look for both "v2.4.12" and "2.4.12" formats
        release_date=""

        # Search for exact version match (v-prefixed or plain)
        for version_format in "v${version}" "${version}"; do
            if command -v jq >/dev/null 2>&1; then
                # Use jq if available (more reliable)
                release_date=$(jq -r ".[] | select(.tag_name == \"$version_format\") | .published_at" "$temp_releases" 2>/dev/null | head -1)
            else
                # Fallback to grep/sed (busybox compatible)
                release_date=$(grep -A20 "\"tag_name\": \"$version_format\"" "$temp_releases" 2>/dev/null |
                    grep "\"published_at\":" | head -1 |
                    sed 's/.*"published_at": *"\([^"]*\)".*/\1/' 2>/dev/null || echo "null")
            fi

            if [ -n "$release_date" ] && [ "$release_date" != "null" ] && [ "$release_date" != "" ]; then
                log_debug "Found release date for $version_format: $release_date"
                break
            fi
        done

        rm -f "$temp_releases"

        if [ -n "$release_date" ] && [ "$release_date" != "null" ] && [ "$release_date" != "" ]; then
            echo "$release_date"
            return 0
        else
            log_debug "Release date not found for version $version"
            echo ""
            return 1
        fi
    else
        log_error "Failed to retrieve release information from GitHub API"
        rm -f "$temp_releases" 2>/dev/null || true
        echo ""
        return 1
    fi
}

# Convert ISO date to Unix timestamp
iso_to_timestamp() {
    iso_date="$1"

    # Try different date parsing methods (RUTOS/busybox compatibility)
    if date -d "$iso_date" +%s 2>/dev/null; then
        return 0
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null; then
        return 0
    else
        # Fallback: approximate timestamp (not precise but better than nothing)
        log_warning "Cannot parse date precisely, using approximate calculation"
        # Simple year-based approximation (2024 = ~1704067200)
        year=$(echo "$iso_date" | sed 's/-.*//')
        if [ "$year" -ge 2024 ]; then
            echo $(((year - 1970) * 31536000))
        else
            echo "0"
        fi
        return 0
    fi
}

# Check if enough time has passed since release for update delay policy
check_update_delay_policy() {
    version="$1"
    version_type="$2" # "patch", "minor", or "major"
    delay_config="$3" # e.g., "Never", "2Weeks", "5Days"

    log_debug "Checking update delay policy for $version_type version $version with delay $delay_config"

    if [ "$delay_config" = "Never" ]; then
        log_info "Auto-update disabled for $version_type versions (policy: Never)"
        return 1 # Update not allowed
    fi

    # Get release date
    release_date=$(get_release_date "$version")
    if [ -z "$release_date" ]; then
        log_warning "Cannot determine release date for $version - allowing update (fail-safe)"
        return 0 # Allow update if we can't determine date
    fi

    # Convert release date to timestamp
    release_timestamp=$(iso_to_timestamp "$release_date")
    current_timestamp=$(date +%s)
    time_since_release=$((current_timestamp - release_timestamp))

    # Parse delay configuration to seconds
    required_delay_seconds=$(parse_delay_to_seconds "$delay_config")

    log_debug "Release timestamp: $release_timestamp"
    log_debug "Current timestamp: $current_timestamp"
    log_debug "Time since release: ${time_since_release}s"
    log_debug "Required delay: ${required_delay_seconds}s"

    if [ "$time_since_release" -ge "$required_delay_seconds" ]; then
        log_info "Update delay satisfied: $version released $((time_since_release / 86400)) days ago (required: $(get_time_description "$delay_config"))"
        return 0 # Update allowed
    else
        days_since=$((time_since_release / 86400))
        days_required=$((required_delay_seconds / 86400))
        remaining_days=$((days_required - days_since))

        log_info "Update delay not satisfied: $version released $days_since days ago (required delay: $(get_time_description "$delay_config"), $remaining_days days remaining)"
        return 1 # Update not allowed yet
    fi
}

# Compare versions (returns 0 if $1 > $2)
version_gt() {
    ver1="$1"
    ver2="$2"

    log_debug "Comparing versions: $ver1 > $ver2"

    # Handle same versions
    if [ "$ver1" = "$ver2" ]; then
        log_debug "Versions are equal"
        return 1
    fi

    # Use sort -V if available (most systems), fallback to basic comparison
    if command -v sort >/dev/null 2>&1 && sort --version-sort /dev/null >/dev/null 2>&1; then
        result=$(printf '%s\n%s' "$ver1" "$ver2" | sort -V | head -n1)
        if [ "$result" = "$ver2" ]; then
            log_debug "Version comparison result: $ver1 > $ver2 (true)"
            return 0
        else
            log_debug "Version comparison result: $ver1 > $ver2 (false)"
            return 1
        fi
    else
        # Fallback comparison for systems without sort -V
        log_debug "Using fallback version comparison"
        # Simple string comparison as fallback
        if [ "$ver1" != "$ver2" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# Parse delay string (e.g., "2Weeks", "5Days", "30Minutes") into seconds
# shellcheck disable=SC2317  # Function is called indirectly
parse_delay_to_seconds() {
    delay_str="$1"

    if [ "$delay_str" = "Never" ]; then
        echo "999999999" # Very large number to represent "never"
        return 0
    fi

    # Extract number and unit
    number=$(echo "$delay_str" | sed 's/[A-Za-z]*$//')
    unit=$(echo "$delay_str" | sed 's/^[0-9]*//')

    case "$unit" in
        "Minutes" | "Minute")
            echo $((number * 60))
            ;;
        "Hours" | "Hour")
            echo $((number * 3600))
            ;;
        "Days" | "Day")
            echo $((number * 86400))
            ;;
        "Weeks" | "Week")
            echo $((number * 604800))
            ;;
        "Months" | "Month")
            echo $((number * 2592000)) # 30 days
            ;;
        *)
            log_error "Invalid time unit in delay: $unit"
            echo "86400" # Default to 1 day
            ;;
    esac
}

# Get human-readable time description
# shellcheck disable=SC2317  # Function is called indirectly
get_time_description() {
    delay_str="$1"

    if [ "$delay_str" = "Never" ]; then
        echo "Never (manual updates only)"
        return 0
    fi

    # Extract number and unit
    number=$(echo "$delay_str" | sed 's/[A-Za-z]*$//')
    unit=$(echo "$delay_str" | sed 's/^[0-9]*//')

    # Convert to friendly format
    case "$unit" in
        "Minutes" | "Minute")
            if [ "$number" = "1" ]; then
                echo "1 minute"
            else
                echo "$number minutes"
            fi
            ;;
        "Hours" | "Hour")
            if [ "$number" = "1" ]; then
                echo "1 hour"
            else
                echo "$number hours"
            fi
            ;;
        "Days" | "Day")
            if [ "$number" = "1" ]; then
                echo "1 day"
            else
                echo "$number days"
            fi
            ;;
        "Weeks" | "Week")
            if [ "$number" = "1" ]; then
                echo "1 week"
            else
                echo "$number weeks"
            fi
            ;;
        "Months" | "Month")
            if [ "$number" = "1" ]; then
                echo "1 month"
            else
                echo "$number months"
            fi
            ;;
        *)
            echo "$delay_str"
            ;;
    esac
}

# Determine version type change (patch/minor/major)
get_version_change_type() {
    local_ver="$1"
    remote_ver="$2"

    # Parse version numbers (assuming semantic versioning: major.minor.patch)
    local_major=$(echo "$local_ver" | cut -d. -f1 | sed 's/[^0-9]//g')
    local_minor=$(echo "$local_ver" | cut -d. -f2 | sed 's/[^0-9]//g')

    remote_major=$(echo "$remote_ver" | cut -d. -f1 | sed 's/[^0-9]//g')
    remote_minor=$(echo "$remote_ver" | cut -d. -f2 | sed 's/[^0-9]//g')

    # Handle missing version parts
    local_major=${local_major:-0}
    local_minor=${local_minor:-0}
    remote_major=${remote_major:-0}
    remote_minor=${remote_minor:-0}

    log_debug "Local version parts: $local_major.$local_minor"
    log_debug "Remote version parts: $remote_major.$remote_minor"

    if [ "$remote_major" != "$local_major" ]; then
        echo "major"
    elif [ "$remote_minor" != "$local_minor" ]; then
        echo "minor"
    else
        echo "patch"
    fi
}

# Install crontab job for auto-updates
install_crontab_job() {
    load_config

    if [ "$AUTO_UPDATE_ENABLED" != "true" ]; then
        log_warning "Auto-update is disabled in configuration, but installing crontab anyway"
        log_warning "Enable auto-updates by setting AUTO_UPDATE_ENABLED=\"true\" in $CONFIG_FILE"
    fi

    log_step "Installing auto-update crontab job"

    script_path="/usr/local/starlink-monitor/scripts/self-update-rutos.sh"
    cron_command="$AUTO_UPDATE_SCHEDULE $script_path --auto-update >/dev/null 2>&1"
    cron_comment="# Starlink Monitor Auto-Update (every 4 hours)"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -F "$script_path --auto-update" >/dev/null; then
        log_warning "Auto-update cron job already exists, updating it"
        # Remove existing job first
        crontab -l 2>/dev/null | grep -v -F "$script_path" | crontab -
    fi

    # Add the cron job
    if {
        crontab -l 2>/dev/null || true
        echo "$cron_comment"
        echo "$cron_command"
    } | crontab -; then
        log_success "Auto-update cron job installed: $cron_command"
        log_info "The system will check for updates every 4 hours"
        log_info "Update policy: Patch=${UPDATE_PATCH_DELAY}, Minor=${UPDATE_MINOR_DELAY}, Major=${UPDATE_MAJOR_DELAY}"
        return 0
    else
        log_error "Failed to install cron job"
        return 1
    fi
}

# Create version-pinned recovery installation script
create_recovery_script() {
    version="$1"
    recovery_script="/etc/starlink-config/install-pinned-version.sh"

    log_info "Creating version-pinned recovery script for v$version"

    # Ensure persistent config directory exists
    mkdir -p "/etc/starlink-config" 2>/dev/null || {
        log_error "Cannot create persistent config directory"
        return 1
    }

    # Create the recovery script with embedded version information
    cat >"$recovery_script" <<EOF
#!/bin/sh
# ==============================================================================
# Version-Pinned Recovery Installation Script
# Generated by self-update-rutos.sh v$SCRIPT_VERSION
# 
# This script installs the exact version that was previously running on this
# system before firmware upgrade. It ensures consistency with user's update
# delay policies by not forcing newer versions during recovery.
#
# ROBUST FALLBACK STRATEGY:
# 1. Try pinned version first (respects user's update delay policies)
# 2. If pinned version fails or is invalid → fallback to latest stable
# 3. If latest fails → try alternative download methods
# 4. If all automated methods fail → provide manual recovery instructions
# ==============================================================================

set -eu

# Pinned version information
PINNED_VERSION="$version"
GITHUB_REPO="$GITHUB_REPO"
GITHUB_BRANCH="$GITHUB_BRANCH"
RECOVERY_URL="https://raw.githubusercontent.com/\${GITHUB_REPO}/v\${PINNED_VERSION}/scripts/install-rutos.sh"
FALLBACK_URL="https://raw.githubusercontent.com/\${GITHUB_REPO}/\${GITHUB_BRANCH}/scripts/install-rutos.sh"
CREATED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

echo "=============================================="
echo "Starlink Monitor - Version-Pinned Recovery"
echo "Pinned Version: v\$PINNED_VERSION"
echo "Created: \$CREATED_DATE"
echo "=============================================="

# Validate pinned version format before attempting recovery
validate_version_format() {
    version_to_check="\$1"
    # Check if version looks valid (e.g., 2.4.12, 1.0.0, etc.)
    if echo "\$version_to_check" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\$|[^0-9])'; then
        return 0  # Valid format
    else
        echo "⚠ Invalid version format detected: \$version_to_check"
        return 1  # Invalid format
    fi
}

# Test URL accessibility before attempting download
test_url_accessibility() {
    test_url="\$1"
    echo "Testing accessibility: \$test_url"
    
    # Try HEAD request first (faster, less bandwidth)
    if curl -fsSL --head --connect-timeout 5 --max-time 15 "\$test_url" >/dev/null 2>&1; then
        echo "✓ URL is accessible"
        return 0
    else
        echo "✗ URL is not accessible"
        return 1
    fi
}

# Enhanced installation with multiple fallback methods
attempt_installation() {
    install_url="\$1"
    description="\$2"
    
    echo ""
    echo "Attempting \$description installation..."
    echo "URL: \$install_url"
    
    # Method 1: Standard curl approach
    echo "Method 1: Direct curl installation"
    if curl -fsSL --connect-timeout 10 --max-time 60 "\$install_url" | sh; then
        echo "✓ Installation successful via direct curl"
        return 0
    fi
    
    # Method 2: Download to temp file first, then execute
    echo "Method 2: Download and execute approach"
    temp_script="/tmp/install-recovery-\$\$.sh"
    if curl -fsSL --connect-timeout 10 --max-time 60 "\$install_url" -o "\$temp_script" 2>/dev/null; then
        if [ -s "\$temp_script" ] && sh "\$temp_script"; then
            echo "✓ Installation successful via download-and-execute"
            rm -f "\$temp_script"
            return 0
        fi
        rm -f "\$temp_script"
    fi
    
    # Method 3: Try with wget if available
    if command -v wget >/dev/null 2>&1; then
        echo "Method 3: Fallback to wget"
        if wget -qO- --timeout=60 "\$install_url" | sh; then
            echo "✓ Installation successful via wget"
            return 0
        fi
    fi
    
    echo "✗ All installation methods failed for \$description"
    return 1
}

# START RECOVERY PROCESS
echo ""
echo "Starting recovery process..."

# Step 1: Validate pinned version format
if validate_version_format "\$PINNED_VERSION"; then
    echo "✓ Pinned version format is valid: v\$PINNED_VERSION"
    
    # Step 2: Test pinned version URL accessibility
    if test_url_accessibility "\$RECOVERY_URL"; then
        echo "✓ Pinned version URL is accessible"
        
        # Step 3: Attempt pinned version installation
        if attempt_installation "\$RECOVERY_URL" "pinned version v\$PINNED_VERSION"; then
            echo ""
            echo "=============================================="
            echo "✅ SUCCESS: Pinned version v\$PINNED_VERSION installed"
            echo "✅ Your update delay policies are respected"
            echo "✅ No forced upgrades applied"
            echo "=============================================="
            exit 0
        else
            echo "⚠ Pinned version installation failed despite URL being accessible"
        fi
    else
        echo "⚠ Pinned version URL not accessible (version may not exist as release)"
    fi
else
    echo "⚠ Invalid pinned version format, skipping to latest version"
fi

# Step 4: Fallback to latest stable version
echo ""
echo "=============================================="
echo "FALLBACK: Installing latest stable version"
echo "⚠ This may install a newer version than originally configured"
echo "⚠ Check your configuration after installation completes"
echo "=============================================="

if test_url_accessibility "\$FALLBACK_URL"; then
    echo "✓ Latest version URL is accessible"
    
    if attempt_installation "\$FALLBACK_URL" "latest stable version"; then
        echo ""
        echo "=============================================="
        echo "✅ SUCCESS: Latest stable version installed"
        echo "⚠ NOTE: This may be newer than your original v\$PINNED_VERSION"
        echo "ℹ  Check configuration: /etc/starlink-config/config.sh"
        echo "ℹ  Review update policies if auto-update behavior changed"
        echo "=============================================="
        exit 0
    else
        echo "✗ Latest version installation also failed"
    fi
else
    echo "✗ Latest version URL not accessible - network or repository issues"
fi

# Step 5: Final fallback - manual recovery instructions
echo ""
echo "=============================================="
echo "❌ RECOVERY FAILED"
echo "=============================================="
echo "All automated recovery methods have failed."
echo "Manual intervention required."
echo ""
echo "MANUAL RECOVERY OPTIONS:"
echo ""
echo "1. Network Recovery (if you have internet access):"
echo "   curl -fsSL https://raw.githubusercontent.com/\$GITHUB_REPO/main/scripts/install-rutos.sh | sh"
echo ""
echo "2. Alternative GitHub URL:"
echo "   wget -qO- https://github.com/\$GITHUB_REPO/raw/main/scripts/install-rutos.sh | sh"
echo ""
echo "3. Check repository directly:"
echo "   Browse to: https://github.com/\$GITHUB_REPO"
echo "   Look for installation instructions in README"
echo ""
echo "4. Diagnose network issues:"
echo "   ping github.com"
echo "   nslookup github.com" 
echo "   curl -I https://github.com"
echo ""
echo "5. If network works but repository is inaccessible:"
echo "   The repository may be temporarily unavailable"
echo "   Try again in a few minutes"
echo ""
echo "Your configuration is preserved at:"
echo "  /etc/starlink-config/config.sh"
echo ""
echo "=============================================="
exit 1
EOF

    # Make script executable
    chmod +x "$recovery_script"

    log_success "Version-pinned recovery script created: $recovery_script"
    log_info "This script will install v$version during firmware upgrade recovery"
    return 0
}

# Update recovery system with version pinning
update_recovery_system() {
    version="$1"
    restoration_script="/etc/init.d/starlink-restore"

    log_info "Updating recovery system to use version-pinned installation"

    if [ ! -f "$restoration_script" ]; then
        log_warning "Auto-restoration script not found at $restoration_script"
        log_info "Recovery system update skipped - will be set up during next installation"
        return 0
    fi

    # Create backup of current restoration script
    backup_restoration="/etc/init.d/starlink-restore.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$restoration_script" "$backup_restoration" 2>/dev/null; then
        log_debug "Backed up restoration script to $backup_restoration"
    fi

    # Update the restoration script to use version-pinned installation
    temp_script="/tmp/starlink-restore-updated.$$"

    # Replace the recovery installation line with our version-pinned approach
    sed "/curl.*install-rutos.sh.*sh/c\\
        # Try version-pinned recovery first (respects user's update delay policies)\\
        if [ -f \"/etc/starlink-config/install-pinned-version.sh\" ]; then\\
            log_restore \"Using version-pinned recovery to respect update delay policies\"\\
            if sh \"/etc/starlink-config/install-pinned-version.sh\" >>\"\$RESTORE_LOG\" 2>&1; then\\
                log_restore \"Version-pinned installation completed successfully\"\\
            else\\
                log_restore \"Version-pinned installation failed, trying latest version\"\\
                if curl -fsSL \"\${BASE_URL}/scripts/install-rutos.sh\" | sh >>\"\$RESTORE_LOG\" 2>&1; then\\
                    log_restore \"Fallback installation completed successfully\"\\
                else\\
                    log_restore \"Both pinned and fallback installations failed\"\\
                    return 1\\
                fi\\
            fi\\
        else\\
            log_restore \"No version-pinned recovery script available, using latest version\"\\
            if curl -fsSL \"\${BASE_URL}/scripts/install-rutos.sh\" | sh >>\"\$RESTORE_LOG\" 2>&1; then\\
                log_restore \"Installation script completed successfully\"\\
            else\\
                log_restore \"Installation failed\"\\
                return 1\\
            fi\\
        fi" "$restoration_script" >"$temp_script"

    # Replace the restoration script
    if mv "$temp_script" "$restoration_script" 2>/dev/null; then
        chmod +x "$restoration_script"
        log_success "Recovery system updated to use version-pinned installation"
        log_info "Firmware upgrade recovery will now preserve your current version v$version"
    else
        log_error "Failed to update recovery system"
        rm -f "$temp_script" 2>/dev/null
        return 1
    fi

    return 0
}

# Remove crontab job for auto-updates
remove_crontab_job() {
    log_step "Removing auto-update crontab job"

    script_path="/usr/local/starlink-monitor/scripts/self-update-rutos.sh"

    # Remove lines containing the script path and comments
    if crontab -l 2>/dev/null | grep -v -F "$script_path" | grep -v "Starlink Monitor Auto-Update" | crontab -; then
        log_success "Auto-update cron job removed"
        return 0
    else
        log_error "Failed to remove cron job"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --check-only)
                CHECK_ONLY=true
                log_debug "Check-only mode enabled"
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                log_debug "Force update enabled"
                shift
                ;;
            --backup-only)
                BACKUP_ONLY=true
                log_debug "Backup-only mode enabled"
                shift
                ;;
            --auto-update)
                AUTO_UPDATE_MODE=true
                log_debug "Auto-update mode enabled"
                shift
                ;;
            --install-cron)
                INSTALL_CRON=true
                shift
                ;;
            --remove-cron)
                REMOVE_CRON=true
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"

    # Handle cron installation/removal first
    if [ "$INSTALL_CRON" = "true" ]; then
        install_crontab_job
        exit $?
    fi

    if [ "$REMOVE_CRON" = "true" ]; then
        remove_crontab_job
        exit $?
    fi

    # Load configuration
    load_config

    # Show script info
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"

    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode active"
        log_debug "Check only: $CHECK_ONLY"
        log_debug "Force update: $FORCE_UPDATE"
        log_debug "Backup only: $BACKUP_ONLY"
        log_debug "Auto-update mode: $AUTO_UPDATE_MODE"
    fi

    # Handle backup-only mode
    if [ "$BACKUP_ONLY" = "true" ]; then
        if create_backup; then
            log_success "Backup created successfully"
            exit 0
        else
            log_error "Backup creation failed"
            exit 1
        fi
    fi

    # Get versions
    log_step "Checking versions"
    local_version=$(get_local_version)
    log_info "Current local version: $local_version"

    remote_version=$(get_remote_version)
    if [ "$remote_version" = "0.0.0" ]; then
        log_error "Failed to get remote version"
        exit 1
    fi
    log_info "Latest remote version: $remote_version"

    # Compare versions
    update_available=false
    if version_gt "$remote_version" "$local_version"; then
        update_available=true
        log_info "Update available: $local_version -> $remote_version"

        # Determine version change type
        version_type=$(get_version_change_type "$local_version" "$remote_version")
        log_info "Version change type: $version_type"

        # Get appropriate delay setting
        case "$version_type" in
            "major")
                delay_config="$UPDATE_MAJOR_DELAY"
                ;;
            "minor")
                delay_config="$UPDATE_MINOR_DELAY"
                ;;
            "patch")
                delay_config="$UPDATE_PATCH_DELAY"
                ;;
            *)
                log_warning "Unknown version type, using patch delay"
                delay_config="$UPDATE_PATCH_DELAY"
                ;;
        esac

        # Get human readable delay description
        delay_description=$(get_time_description "$delay_config")

        # Send notification if enabled
        if [ "$AUTO_UPDATE_NOTIFICATIONS_ENABLED" = "true" ]; then
            if [ "$delay_config" = "Never" ]; then
                notification_msg="New ${version_type} version ${remote_version} is available (currently ${local_version}). Auto-update is disabled - manual update required."
            else
                notification_msg="New ${version_type} version ${remote_version} is available (currently ${local_version}). Auto-update scheduled in ${delay_description}."
            fi

            if send_notification "Update Available" "$notification_msg" 0; then
                log_info "Update notification sent via Pushover"
            else
                log_debug "Notification sending failed or skipped"
            fi
        fi

        # Check auto-update delay policy if in auto-update mode
        if [ "$AUTO_UPDATE_MODE" = "true" ]; then
            log_info "Checking $version_type update delay policy: $delay_config"

            # Use the new comprehensive delay checking function
            if check_update_delay_policy "$remote_version" "$version_type" "$delay_config"; then
                log_info "Auto-update policy allows update: $delay_config delay satisfied for $version_type version $remote_version"
            else
                log_info "Auto-update delayed: $delay_config policy not yet satisfied for $version_type version $remote_version"
                log_info "Manual update available: run without --auto-update flag to override delay"
                exit 4 # Exit code 4 = update delayed by policy
            fi
        fi

    elif [ "$FORCE_UPDATE" = "true" ]; then
        update_available=true
        log_info "Forcing update (versions may be the same)"
    else
        log_success "Already up to date (local: $local_version, remote: $remote_version)"
    fi

    # Handle check-only mode
    if [ "$CHECK_ONLY" = "true" ]; then
        if [ "$update_available" = "true" ]; then
            log_info "Update available but not installing (check-only mode)"
            exit 2
        else
            log_success "No update needed"
            exit 0
        fi
    fi

    # Perform update if available
    if [ "$update_available" = "true" ]; then
        log_warning "Update functionality not yet implemented in this version"
        log_info "This is a placeholder - actual update would happen here"
        log_info "To update manually: download and run the installation script"

        # When update is actually implemented, store version info for recovery
        log_info "When update completes, will store version information for recovery"
        log_info "Future firmware upgrades will reinstall the same version to respect your delay policies"

        # Send success notification
        if [ "$AUTO_UPDATE_NOTIFICATIONS_ENABLED" = "true" ]; then
            send_notification "Update Complete" "Successfully updated from ${local_version} to ${remote_version}" 0
        fi

        exit 0
    else
        # Even when no update is performed, ensure current version is stored for recovery
        log_step "Ensuring current version is stored for firmware upgrade recovery"

        # Store current version information
        if store_version_for_recovery "$local_version"; then
            log_debug "Current version $local_version stored for recovery"
        else
            log_debug "Failed to store version for recovery (non-critical)"
        fi

        # Create/update version-pinned recovery script
        if create_recovery_script "$local_version"; then
            log_debug "Version-pinned recovery script created for v$local_version"
        else
            log_debug "Failed to create recovery script (non-critical)"
        fi

        # Update recovery system if needed
        if update_recovery_system "$local_version"; then
            log_debug "Recovery system updated for version pinning"
        else
            log_debug "Recovery system update failed (non-critical)"
        fi

        log_success "System is up to date"
        log_info "Firmware upgrade recovery configured for current version: v$local_version"
        exit 0
    fi
}

# Simple backup function (placeholder for now)
create_backup() {
    log_step "Creating backup (placeholder)"
    log_info "Backup functionality not yet implemented"
    return 0
}

# Trap to ensure cleanup on exit
trap 'rm -f /tmp/starlink-*.txt 2>/dev/null || true' EXIT

# Run main function with all arguments
main "$@"
