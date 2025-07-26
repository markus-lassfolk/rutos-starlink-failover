#!/bin/sh

# ===========================================================================================
# Unified Azure Logging Setup Script
#
# This script provides a complete, automated setup for:
# - RUTOS persistent logging configuration
# - System log shipping to Azure
# - Starlink performance monitoring with GPS integration
# - Azure Function endpoint configuration
# - Dependency installation and validation
# ===========================================================================================

set -eu

# --- SCRIPT CONFIGURATION ---
# shellcheck disable=SC2034  # SCRIPT_NAME may be used by external functions

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
SCRIPT_NAME="unified-azure-setup"

# Use script name for logging
echo "Starting $SCRIPT_NAME" >/dev/null 2>&1 || true
LOG_TAG="UnifiedAzureSetup"
WORK_DIR="/tmp/azure-setup"
BACKUP_DIR="/root/azure-setup-backup-$(date +%Y%m%d-%H%M%S)"

# --- DEFAULT CONFIGURATION ---
DEFAULT_AZURE_ENDPOINT=""
DEFAULT_RUTOS_IP="192.168.80.1"
DEFAULT_STARLINK_IP="192.168.100.1"
DEFAULT_STARLINK_PORT="9200"
DEFAULT_ENABLE_GPS="true"
DEFAULT_ENABLE_STARLINK_MONITORING="true"

# --- GLOBAL VARIABLES ---
# shellcheck disable=SC2034  # ENABLE_STARLINK_MONITORING is used in the setup process
ENABLE_STARLINK_MONITORING=""
# shellcheck disable=SC2034  # AZURE_FUNCTION_URL is used for configuration
AZURE_FUNCTION_URL=""

# --- COLORS FOR OUTPUT ---
# Check if terminal supports colors
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Fallback to no colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support - capture originals for debug display
ORIGINAL_DRY_RUN="${DRY_RUN:-0}"
ORIGINAL_RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "${CYAN}[DEBUG]${NC} DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$ORIGINAL_DRY_RUN" "$ORIGINAL_RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    echo "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution" >&2
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY-RUN] Would execute: $description"
        echo "[DRY-RUN] Command: $cmd" >&2
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# --- HELPER FUNCTIONS ---
log() {
    printf "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] %s${NC}\n" "$1"
    logger -t "$LOG_TAG" "$1"
}

log_success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
    logger -t "$LOG_TAG" "SUCCESS: $1"
}

log_warn() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
    logger -t "$LOG_TAG" "WARNING: $1"
}

log_error() {
    printf "${RED}✗ %s${NC}\n" "$1"
    logger -t "$LOG_TAG" "ERROR: $1"
}

prompt_user() {
    prompt="$1"
    default="$2"
    response=""

    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
        read -r response
        echo "${response:-$default}"
    else
        printf "%s: " "$prompt"
        read -r response
        echo "$response"
    fi
}

check_command() {
    cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        log_success "$cmd is available"
        return 0
    else
        log_error "$cmd is not available"
        return 1
    fi
}

# --- DEPENDENCY INSTALLATION ---
install_dependencies() {
    log "Installing required dependencies..."

    # Create work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Install essential packages
    log "Updating package lists..."
    opkg update >/dev/null 2>&1 || log_warn "Failed to update package lists"

    # Install required packages
    packages="curl jq coreutils-timeout bc"
    for package in $packages; do
        if opkg list-installed | grep -q "^$package "; then
            log_success "$package is already installed"
        else
            log "Installing $package..."
            if opkg install "$package" >/dev/null 2>&1; then
                log_success "$package installed successfully"
            else
                log_warn "Failed to install $package, but continuing..."
            fi
        fi
    done

    # Install grpcurl if not present
    if [ ! -f "/root/grpcurl" ]; then
        log "Installing grpcurl..."
        grpcurl_url="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_arm.tar.gz"

        if curl -L -o grpcurl.tar.gz "$grpcurl_url" >/dev/null 2>&1; then
            tar -xzf grpcurl.tar.gz >/dev/null 2>&1
            mv grpcurl /root/grpcurl
            chmod +x /root/grpcurl
            log_success "grpcurl installed successfully"
        else
            log_error "Failed to download grpcurl"
            return 1
        fi
    else
        log_success "grpcurl is already installed"
    fi

    # Install jq binary if system jq is not sufficient
    if [ ! -f "/root/jq" ]; then
        log "Installing jq binary..."
        jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-arm"

        if curl -L -o /root/jq "$jq_url" >/dev/null 2>&1; then
            chmod +x /root/jq
            log_success "jq binary installed successfully"
        else
            log_warn "Failed to download jq binary, using system jq"
        fi
    else
        log_success "jq binary is already installed"
    fi

    # Clean up
    cd /
    rm -rf "$WORK_DIR"
}

# --- RUTOS PERSISTENT LOGGING SETUP ---
setup_persistent_logging() {
    log "Configuring RUTOS persistent logging..."

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup current configuration
    uci export system >"$BACKUP_DIR/system.backup" 2>/dev/null || true
    cp /etc/config/system "$BACKUP_DIR/system.config.backup" 2>/dev/null || true

    # Get current logging configuration
    current_log_type current_log_size current_log_file
    current_log_type=$(uci get system.@system[0].log_type 2>/dev/null || echo "circular")
    current_log_size=$(uci get system.@system[0].log_size 2>/dev/null || echo "200")
    current_log_file=$(uci get system.@system[0].log_file 2>/dev/null || echo "")

    log "Current logging configuration:"
    log "  Type: $current_log_type"
    log "  Size: ${current_log_size}KB"
    log "  File: ${current_log_file:-"(none)"}"

    # Configure persistent logging
    if [ "$current_log_type" != "file" ] || [ "$current_log_size" -lt "5120" ] || [ "$current_log_file" != "/overlay/messages" ]; then
        log "Updating logging configuration..."

        uci set system.@system[0].log_type='file'
        uci set system.@system[0].log_size='5120'
        uci set system.@system[0].log_file='/overlay/messages'
        uci commit system

        log_success "Logging configuration updated"

        # Restart syslog to apply changes
        /etc/init.d/log restart >/dev/null 2>&1
        log_success "Syslog service restarted"

        # Wait for log file to be created
        sleep 2
    else
        log_success "Persistent logging is already configured correctly"
    fi

    # Verify log file exists and is writable
    if [ -f "/overlay/messages" ]; then
        log_success "Log file /overlay/messages exists"

        # Test writing to log file
        if echo "$(date): Azure logging setup test" >>/overlay/messages; then
            log_success "Log file is writable"
        else
            log_error "Log file is not writable"
            return 1
        fi
    else
        log_error "Log file /overlay/messages does not exist"
        return 1
    fi
}

# --- UCI CONFIGURATION FOR AZURE ---
setup_azure_uci_config() {
    azure_endpoint="$1"
    rutos_ip="$2"
    rutos_username="$3"
    rutos_password="$4"
    enable_gps="$5"

    log "Configuring UCI settings for Azure integration..."

    # Create Azure UCI section if it doesn't exist
    if ! uci show azure >/dev/null 2>&1; then
        log "Creating Azure UCI configuration section..."
        touch /etc/config/azure
    fi

    # Configure system logs
    uci set azure.system=azure_config
    uci set azure.system.endpoint="$azure_endpoint"
    uci set azure.system.enabled='1'
    uci set azure.system.log_file='/overlay/messages'
    uci set azure.system.max_size='1048576'

    # Configure Starlink monitoring
    uci set azure.starlink=starlink_config
    uci set azure.starlink.endpoint="$azure_endpoint"
    uci set azure.starlink.enabled='1'
    uci set azure.starlink.csv_file='/overlay/starlink_performance.csv'
    uci set azure.starlink.max_size='1048576'
    uci set azure.starlink.starlink_ip="$DEFAULT_STARLINK_IP"

    # Configure GPS if enabled
    if [ "$enable_gps" = "true" ]; then
        uci set azure.gps=gps_config
        uci set azure.gps.enabled='1'
        uci set azure.gps.rutos_ip="$rutos_ip"

        if [ -n "$rutos_username" ] && [ -n "$rutos_password" ]; then
            uci set azure.gps.rutos_username="$rutos_username"
            uci set azure.gps.rutos_password="$rutos_password"
        fi

        uci set azure.gps.accuracy_threshold='100'
    fi

    # Commit all changes
    uci commit azure
    log_success "UCI configuration updated"
}

# --- SCRIPT INSTALLATION ---
install_scripts() {
    log "Installing Azure logging scripts..."

    # List of required scripts and their target locations
    # Using space-separated strings instead of arrays for busybox compatibility
    SCRIPTS="setup-persistent-logging-rutos.sh log-shipper-rutos.sh starlink-azure-monitor-rutos.sh test-azure-logging-rutos.sh"

    # Install each script
    for script in $SCRIPTS; do
        case "$script" in
            "setup-persistent-logging-rutos.sh") target="/usr/bin/setup-persistent-logging-rutos.sh" ;;
            "log-shipper-rutos.sh") target="/usr/bin/log-shipper-rutos.sh" ;;
            "starlink-azure-monitor-rutos.sh") target="/usr/bin/starlink-azure-monitor-rutos.sh" ;;
            "test-azure-logging-rutos.sh") target="/usr/bin/test-azure-logging-rutos.sh" ;;
        esac

        if [ -f "./$script" ]; then
            log "Installing $script to $target..."
            cp "./$script" "$target"
            chmod +x "$target"
            log_success "$script installed successfully"
        else
            log_warn "$script not found in current directory, skipping..."
        fi
    done
}

# --- CRON JOB SETUP ---
setup_cron_jobs() {
    enable_starlink_monitoring="$1"

    log "Setting up cron jobs..."

    # Backup existing crontab
    crontab -l >"$BACKUP_DIR/crontab.backup" 2>/dev/null || touch "$BACKUP_DIR/crontab.backup"

    # Remove any existing Azure logging cron jobs
    crontab -l 2>/dev/null | grep -v "log-shipper.sh\|starlink-azure-monitor.sh" | crontab - 2>/dev/null || true

    # Add system log shipping (every 5 minutes)
    (
        crontab -l 2>/dev/null
        echo "*/5 * * * * /usr/bin/log-shipper.sh"
    ) | crontab -
    log_success "System log shipping cron job added"

    # Add Starlink monitoring if enabled (every 2 minutes)
    if [ "$enable_starlink_monitoring" = "true" ]; then
        (
            crontab -l 2>/dev/null
            echo "*/2 * * * * /usr/bin/starlink-azure-monitor.sh"
        ) | crontab -
        log_success "Starlink monitoring cron job added"
    fi

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1
    log_success "Cron service restarted"
}

# --- GPS CONFIGURATION ---
setup_gps_config() {
    enable_gps="$1"

    if [ "$enable_gps" = "true" ]; then
        log "Configuring GPS settings..."

        # Enable GPS if available
        if uci show gps >/dev/null 2>&1; then
            uci set gps.gps.enabled='1'
            uci commit gps

            # Restart GPS service if it exists
            if [ -f "/etc/init.d/gps" ]; then
                /etc/init.d/gps restart >/dev/null 2>&1
                log_success "GPS service restarted"
            fi

            # Start gpsd if available
            if [ -f "/etc/init.d/gpsd" ]; then
                /etc/init.d/gpsd start >/dev/null 2>&1
                log_success "GPSD service started"
            fi
        else
            log_warn "GPS configuration not available on this device"
        fi
    fi
}

# --- NETWORK ROUTES ---
setup_network_routes() {
    log "Verifying network routes..."

    # Check for Starlink route
    if ! ip route show | grep -q "192.168.100.1"; then
        log_warn "No route to Starlink management interface found"
        log "You may need to add a static route:"
        log "  uci add network route"
        log "  uci set network.@route[-1].interface='wan'"
        log "  uci set network.@route[-1].target='192.168.100.1'"
        log "  uci set network.@route[-1].netmask='255.255.255.255'"
        log "  uci commit network"
        log "  /etc/init.d/network reload"
    else
        log_success "Route to Starlink management interface exists"
    fi
}

# --- MAIN SETUP FUNCTION ---
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "unified-azure-setup-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: unified-azure-setup-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    printf "${BLUE}========================================\n"
    printf "${BLUE}  Unified Azure Logging Setup Script\n"
    printf "${BLUE}========================================${NC}\n"

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Gather configuration from user
    log "Gathering configuration information..."
    echo

    azure_endpoint
    azure_endpoint=$(prompt_user "Azure Function endpoint URL" "$DEFAULT_AZURE_ENDPOINT")

    if [ -z "$azure_endpoint" ]; then
        log_error "Azure endpoint URL is required"
        exit 1
    fi

    enable_starlink_monitoring
    enable_starlink_monitoring=$(prompt_user "Enable Starlink performance monitoring? (true/false)" "$DEFAULT_ENABLE_STARLINK_MONITORING")

    enable_gps
    enable_gps=$(prompt_user "Enable GPS integration? (true/false)" "$DEFAULT_ENABLE_GPS")

    rutos_ip rutos_username rutos_password
    if [ "$enable_gps" = "true" ]; then
        rutos_ip=$(prompt_user "RUTOS device IP address" "$DEFAULT_RUTOS_IP")
        rutos_username=$(prompt_user "RUTOS username (optional)" "")

        if [ -n "$rutos_username" ]; then
            printf "RUTOS password: "
            # Use stty to hide password input for POSIX compatibility
            stty -echo
            read -r rutos_password
            stty echo
            echo
        fi
    fi

    echo
    log "Starting installation with the following configuration:"
    log "  Azure Endpoint: $azure_endpoint"
    log "  Starlink Monitoring: $enable_starlink_monitoring"
    log "  GPS Integration: $enable_gps"
    if [ "$enable_gps" = "true" ]; then
        log "  RUTOS IP: $rutos_ip"
        log "  RUTOS Username: ${rutos_username:-"(none)"}"
    fi
    echo

    # Confirm before proceeding
    printf "Proceed with installation? (y/N): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "Installation cancelled by user"
        exit 0
    fi

    # Installation steps
    log "Starting installation process..."

    # Step 1: Install dependencies
    install_dependencies

    # Step 2: Setup persistent logging
    setup_persistent_logging

    # Step 3: Configure UCI settings
    setup_azure_uci_config "$azure_endpoint" "$rutos_ip" "$rutos_username" "$rutos_password" "$enable_gps"

    # Step 4: Install scripts
    install_scripts

    # Step 5: Setup GPS if enabled
    setup_gps_config "$enable_gps"

    # Step 6: Setup network routes
    setup_network_routes

    # Step 7: Setup cron jobs
    setup_cron_jobs "$enable_starlink_monitoring"

    echo
    log_success "Installation completed successfully!"
    echo
    log "Backup files saved to: $BACKUP_DIR"
    log "You can now run the verification script: ./verify-azure-setup.sh"
    echo
    log "Next steps:"
    log "1. Wait 5-10 minutes for initial data collection"
    log "2. Check Azure storage for incoming logs"
    log "3. Run verification script to ensure everything is working"
    echo
}

# Execute main function
main "$@"
