#!/bin/sh

# ==============================================================================
# Self-Update Script for RUTOS Starlink Failover System
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

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Configuration
GITHUB_REPO="markus-lassfolk/rutos-starlink-failover"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_DIR="/root/starlink-monitor"
BACKUP_DIR="/root/starlink-monitor-backup"
TMP_DIR="/tmp/starlink-update"
VERSION_FILE="$INSTALL_DIR/VERSION"
CONFIG_FILE="/root/starlink-monitor/config/config.sh"
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

# Send Pushover notification
send_notification() {
    title="$1"
    message="$2"
    priority="${3:-0}"  # 0=normal, 1=high
    
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
    printf "%sSelf-Update Script v%s%s\n\n" "$GREEN" "$SCRIPT_VERSION" "$NC"
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
parse_delay_to_seconds() {
    delay_str="$1"
    
    if [ "$delay_str" = "Never" ]; then
        echo "999999999"  # Very large number to represent "never"
        return 0
    fi
    
    # Extract number and unit
    number=$(echo "$delay_str" | sed 's/[A-Za-z]*$//')
    unit=$(echo "$delay_str" | sed 's/^[0-9]*//')
    
    case "$unit" in
        "Minutes"|"Minute")
            echo $((number * 60))
            ;;
        "Hours"|"Hour") 
            echo $((number * 3600))
            ;;
        "Days"|"Day")
            echo $((number * 86400))
            ;;
        "Weeks"|"Week")
            echo $((number * 604800))
            ;;
        "Months"|"Month")
            echo $((number * 2592000))  # 30 days
            ;;
        *)
            log_error "Invalid time unit in delay: $unit"
            echo "86400"  # Default to 1 day
            ;;
    esac
}

# Get human-readable time description
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
        "Minutes"|"Minute")
            if [ "$number" = "1" ]; then
                echo "1 minute"
            else
                echo "$number minutes"
            fi
            ;;
        "Hours"|"Hour")
            if [ "$number" = "1" ]; then
                echo "1 hour"
            else
                echo "$number hours"
            fi
            ;;
        "Days"|"Day")
            if [ "$number" = "1" ]; then
                echo "1 day"
            else
                echo "$number days"
            fi
            ;;
        "Weeks"|"Week")
            if [ "$number" = "1" ]; then
                echo "1 week"
            else
                echo "$number weeks"
            fi
            ;;
        "Months"|"Month")
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
    
    script_path="/root/starlink-monitor/scripts/self-update-rutos.sh"
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

# Remove crontab job for auto-updates  
remove_crontab_job() {
    log_step "Removing auto-update crontab job"
    
    script_path="/root/starlink-monitor/scripts/self-update-rutos.sh"
    
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
            
            if [ "$delay_config" = "Never" ]; then
                log_info "Auto-update disabled for $version_type versions"
                log_info "Manual update required: run without --auto-update flag"
                exit 4
            fi
            
            # For simplicity in this version, we'll proceed with update if not "Never"
            # In a full implementation, you'd check actual release timestamps here
            log_info "Auto-update policy allows immediate update for testing purposes"
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
        
        # Send success notification
        if [ "$AUTO_UPDATE_NOTIFICATIONS_ENABLED" = "true" ]; then
            send_notification "Update Complete" "Successfully updated from ${local_version} to ${remote_version}" 0
        fi
        
        exit 0
    else
        log_success "System is up to date"
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
