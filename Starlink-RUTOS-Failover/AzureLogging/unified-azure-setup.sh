#!/bin/bash

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

set -euo pipefail

# --- SCRIPT CONFIGURATION ---
SCRIPT_NAME="unified-azure-setup"
LOG_TAG="UnifiedAzureSetup"
WORK_DIR="/tmp/azure-setup"
BACKUP_DIR="/root/azure-setup-backup-$(date +%Y%m%d-%H%M%S)"

# --- DEFAULT CONFIGURATION ---
DEFAULT_AZURE_ENDPOINT=""
DEFAULT_RUTOS_IP="192.168.80.1"
DEFAULT_STARLINK_IP="192.168.100.1:9200"
DEFAULT_ENABLE_GPS="true"
DEFAULT_ENABLE_STARLINK_MONITORING="true"

# --- COLORS FOR OUTPUT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- HELPER FUNCTIONS ---
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    logger -t "$LOG_TAG" "$1"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
    logger -t "$LOG_TAG" "SUCCESS: $1"
}

log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
    logger -t "$LOG_TAG" "WARNING: $1"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
    logger -t "$LOG_TAG" "ERROR: $1"
}

prompt_user() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$prompt: " response
        echo "$response"
    fi
}

check_command() {
    local cmd="$1"
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
    local packages=("curl" "jq" "coreutils-timeout" "bc")
    for package in "${packages[@]}"; do
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
        local grpcurl_url="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_arm.tar.gz"
        
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
        local jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-arm"
        
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
    uci export system > "$BACKUP_DIR/system.backup" 2>/dev/null || true
    cp /etc/config/system "$BACKUP_DIR/system.config.backup" 2>/dev/null || true
    
    # Get current logging configuration
    local current_log_type=$(uci get system.@system[0].log_type 2>/dev/null || echo "circular")
    local current_log_size=$(uci get system.@system[0].log_size 2>/dev/null || echo "200")
    local current_log_file=$(uci get system.@system[0].log_file 2>/dev/null || echo "")
    
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
        echo "$(date): Azure logging setup test" >> /overlay/messages
        if [ $? -eq 0 ]; then
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
    local azure_endpoint="$1"
    local rutos_ip="$2"
    local rutos_username="$3"
    local rutos_password="$4"
    local enable_gps="$5"
    
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
    declare -A scripts=(
        ["setup-persistent-logging.sh"]="/usr/bin/setup-persistent-logging.sh"
        ["log-shipper.sh"]="/usr/bin/log-shipper.sh"
        ["starlink-azure-monitor.sh"]="/usr/bin/starlink-azure-monitor.sh"
        ["test-azure-logging.sh"]="/usr/bin/test-azure-logging.sh"
    )
    
    # Install each script
    for script in "${!scripts[@]}"; do
        local target="${scripts[$script]}"
        
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
    local enable_starlink_monitoring="$1"
    
    log "Setting up cron jobs..."
    
    # Backup existing crontab
    crontab -l > "$BACKUP_DIR/crontab.backup" 2>/dev/null || touch "$BACKUP_DIR/crontab.backup"
    
    # Remove any existing Azure logging cron jobs
    crontab -l 2>/dev/null | grep -v "log-shipper.sh\|starlink-azure-monitor.sh" | crontab - 2>/dev/null || true
    
    # Add system log shipping (every 5 minutes)
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/log-shipper.sh") | crontab -
    log_success "System log shipping cron job added"
    
    # Add Starlink monitoring if enabled (every 2 minutes)
    if [ "$enable_starlink_monitoring" = "true" ]; then
        (crontab -l 2>/dev/null; echo "*/2 * * * * /usr/bin/starlink-azure-monitor.sh") | crontab -
        log_success "Starlink monitoring cron job added"
    fi
    
    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1
    log_success "Cron service restarted"
}

# --- GPS CONFIGURATION ---
setup_gps_config() {
    local enable_gps="$1"
    
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
    echo -e "${BLUE}"
    echo "========================================"
    echo "  Unified Azure Logging Setup Script"
    echo "========================================"
    echo -e "${NC}"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Gather configuration from user
    log "Gathering configuration information..."
    echo
    
    local azure_endpoint
    azure_endpoint=$(prompt_user "Azure Function endpoint URL" "$DEFAULT_AZURE_ENDPOINT")
    
    if [ -z "$azure_endpoint" ]; then
        log_error "Azure endpoint URL is required"
        exit 1
    fi
    
    local enable_starlink_monitoring
    enable_starlink_monitoring=$(prompt_user "Enable Starlink performance monitoring? (true/false)" "$DEFAULT_ENABLE_STARLINK_MONITORING")
    
    local enable_gps
    enable_gps=$(prompt_user "Enable GPS integration? (true/false)" "$DEFAULT_ENABLE_GPS")
    
    local rutos_ip rutos_username rutos_password
    if [ "$enable_gps" = "true" ]; then
        rutos_ip=$(prompt_user "RUTOS device IP address" "$DEFAULT_RUTOS_IP")
        rutos_username=$(prompt_user "RUTOS username (optional)" "")
        
        if [ -n "$rutos_username" ]; then
            read -s -p "RUTOS password: " rutos_password
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
    read -p "Proceed with installation? (y/N): " confirm
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

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
    
    # Validate URL format
    if ! echo "$AZURE_FUNCTION_URL" | grep -q "^https://.*\.azurewebsites\.net/api/HttpLogIngestor"; then
        log_warn "URL format doesn't match expected pattern. Continuing anyway..."
    fi
    
    echo ""
    echo "Do you want to enable Starlink performance monitoring? (y/N)"
    echo -n "Enable Starlink monitoring: "
    read -r enable_starlink
    
    case "$enable_starlink" in
        [Yy]|[Yy][Ee][Ss])
            ENABLE_STARLINK_MONITORING="true"
            log_info "Starlink monitoring will be enabled"
            ;;
        *)
            ENABLE_STARLINK_MONITORING="false"
            log_info "Starlink monitoring will be disabled"
            ;;
    esac
}

# --- PERSISTENT LOGGING SETUP ---
setup_persistent_logging() {
    log_step "Setting up persistent logging..."
    
    # Backup current configuration
    cp /etc/config/system /etc/config/system.backup.$(date +%Y%m%d-%H%M%S)
    log_info "Backed up current system configuration"
    
    # Configure persistent logging
    uci set system.@system[0].log_type='file'
    uci set system.@system[0].log_file='/overlay/messages'
    uci set system.@system[0].log_size='5120'  # 5MB
    uci commit system
    
    log_info "Updated logging configuration:"
    log_info "  - Type: file (persistent)"
    log_info "  - File: /overlay/messages"
    log_info "  - Size: 5MB"
    
    # Restart logging service
    /etc/init.d/log restart
    sleep 2
    
    # Test logging
    logger -t "azure-setup" "Test log entry for persistent logging setup"
    sleep 1
    
    if [ -f "/overlay/messages" ] && grep -q "Test log entry for persistent logging setup" /overlay/messages; then
        log_info "✓ Persistent logging is working correctly"
    else
        log_error "✗ Persistent logging test failed"
        exit 1
    fi
}

# --- LOG SHIPPER INSTALLATION ---
install_log_shipper() {
    log_step "Installing system log shipper..."
    
    # Create the log shipper script
    cat > /overlay/log-shipper.sh << 'EOF'
#!/bin/sh

# === RUTOS Log Shipper for Azure ===
# Ships system logs from /overlay/messages to Azure Function

# --- CONFIGURATION ---
AZURE_FUNCTION_URL="AZURE_FUNCTION_URL_PLACEHOLDER"
LOG_FILE="/overlay/messages"

# --- VALIDATION ---
if [ "$AZURE_FUNCTION_URL" = "AZURE_FUNCTION_URL_PLACEHOLDER" ]; then
    logger -t "azure-log-shipper" "Error: AZURE_FUNCTION_URL not configured"
    exit 1
fi

if ! echo "$AZURE_FUNCTION_URL" | grep -q "^https://.*\.azurewebsites\.net/api/HttpLogIngestor"; then
    logger -t "azure-log-shipper" "Error: Invalid Azure Function URL format"
    exit 1
fi

# --- MAIN LOGIC ---
if [ ! -s "$LOG_FILE" ]; then
    exit 0
fi

HTTP_STATUS=$(curl -sS -w '%{http_code}' -o /dev/null --max-time 30 \
    -H "X-Log-Type: system-logs" \
    --data-binary "@$LOG_FILE" \
    "$AZURE_FUNCTION_URL" 2>/dev/null)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -eq 0 ] && [ "$HTTP_STATUS" -eq 200 ]; then
    > "$LOG_FILE"
    logger -t "azure-log-shipper" "Successfully sent system logs to Azure"
else
    logger -t "azure-log-shipper" "Failed to send logs to Azure (HTTP: $HTTP_STATUS, curl: $CURL_EXIT_CODE)"
    exit 1
fi

exit 0
EOF
    
    # Replace placeholder with actual URL
    sed -i "s|AZURE_FUNCTION_URL_PLACEHOLDER|$AZURE_FUNCTION_URL|g" /overlay/log-shipper.sh
    
    chmod +x /overlay/log-shipper.sh
    log_info "✓ System log shipper installed"
}

# --- STARLINK MONITORING INSTALLATION ---
install_starlink_monitor() {
    if [ "$ENABLE_STARLINK_MONITORING" != "true" ]; then
        log_info "Skipping Starlink monitoring installation"
        return 0
    fi
    
    log_step "Installing Starlink performance monitor..."
    
    # Check for required tools
    local missing_tools=""
    if ! command -v /root/grpcurl >/dev/null 2>&1; then
        missing_tools="$missing_tools grpcurl"
    fi
    if ! command -v /root/jq >/dev/null 2>&1; then
        missing_tools="$missing_tools jq"
    fi
    
    if [ -n "$missing_tools" ]; then
        log_error "Missing required tools:$missing_tools"
        log_error "Please install grpcurl and jq first (see main repository documentation)"
        exit 1
    fi
    
    # Copy the Starlink monitoring script
    if [ ! -f "/tmp/starlink-azure-monitor.sh" ]; then
        log_error "starlink-azure-monitor.sh not found in /tmp/"
        log_error "Please copy all Azure logging scripts to /tmp/ first"
        exit 1
    fi
    
    cp /tmp/starlink-azure-monitor.sh /overlay/starlink-azure-monitor.sh
    chmod +x /overlay/starlink-azure-monitor.sh
    
    # Create configuration for Starlink monitoring
    cat > /overlay/starlink-azure-config.sh << EOF
#!/bin/sh
# Azure integration configuration for Starlink monitoring

# Enable Azure integration
AZURE_INTEGRATION_ENABLED="true"
AZURE_FUNCTION_URL="$AZURE_FUNCTION_URL"

# Starlink API settings
STARLINK_IP="192.168.100.1:9200"
GRPCURL_PATH="/root/grpcurl"
JQ_PATH="/root/jq"

# CSV logging settings
CSV_LOG_FILE="/overlay/starlink_performance.csv"
CSV_MAX_SIZE="1048576"  # 1MB
EOF
    
    log_info "✓ Starlink performance monitor installed"
}

# --- CRON JOBS SETUP ---
setup_cron_jobs() {
    log_step "Setting up automated scheduling..."
    
    # Remove any existing Azure logging cron jobs
    crontab -l 2>/dev/null | grep -v "log-shipper.sh" | grep -v "starlink-azure-monitor.sh" | crontab -
    
    # Add new cron jobs
    local new_cron=""
    
    # System log shipping every 5 minutes
    new_cron="*/5 * * * * /overlay/log-shipper.sh"
    
    # Starlink monitoring if enabled
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        new_cron="$new_cron
*/2 * * * * . /overlay/starlink-azure-config.sh && /overlay/starlink-azure-monitor.sh"
    fi
    
    # Install new cron jobs
    (crontab -l 2>/dev/null; echo "$new_cron") | crontab -
    
    log_info "✓ Scheduled jobs configured:"
    log_info "  - System logs: every 5 minutes"
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        log_info "  - Starlink monitoring: every 2 minutes"
    fi
}

# --- TESTING ---
test_installation() {
    log_step "Testing installation..."
    
    # Test system log shipping
    logger -t "azure-setup-test" "Test system log entry $(date)"
    sleep 2
    
    log_info "Testing system log shipping..."
    if /overlay/log-shipper.sh; then
        log_info "✓ System log shipping test passed"
    else
        log_error "✗ System log shipping test failed"
    fi
    
    # Test Starlink monitoring if enabled
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        log_info "Testing Starlink monitoring..."
        . /overlay/starlink-azure-config.sh
        if /overlay/starlink-azure-monitor.sh; then
            log_info "✓ Starlink monitoring test passed"
        else
            log_warn "⚠ Starlink monitoring test failed (may be normal if Starlink is not connected)"
        fi
    fi
}

# --- MAIN EXECUTION ---
main() {
    echo ""
    echo "=================================================="
    echo "    Unified Azure Logging Setup for RUTOS"
    echo "=================================================="
    echo ""
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Configure Azure integration
    configure_azure_integration
    
    # Setup persistent logging
    setup_persistent_logging
    
    # Install log shipper
    install_log_shipper
    
    # Install Starlink monitor if requested
    install_starlink_monitor
    
    # Setup cron jobs
    setup_cron_jobs
    
    # Test installation
    test_installation
    
    echo ""
    log_info "🎉 Unified Azure logging setup completed successfully!"
    echo ""
    log_info "Summary of what was configured:"
    log_info "✓ Persistent system logging (5MB, survives reboot)"
    log_info "✓ System log shipping to Azure (every 5 minutes)"
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        log_info "✓ Starlink performance monitoring (every 2 minutes)"
        log_info "✓ Performance data shipping to Azure"
    fi
    echo ""
    log_info "You can monitor the logs with:"
    log_info "  logread -f | grep azure"
    log_info "  cat /overlay/messages"
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        log_info "  cat /overlay/starlink_performance.csv"
    fi
    echo ""
}

# Execute main function
main "$@"
