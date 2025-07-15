#!/bin/sh

# ==============================================================================
# Complete Starlink Solution Deployment Script for RUTOS (POSIX Shell Version)
#
# This is the RUTOS-optimized version using POSIX shell syntax (ash/dash compatible)
# For development/CI use the bash version: deploy-starlink-solution.sh
#
# This script deploys the complete Starlink monitoring and Azure logging solution
# on a RUTOS device, including all dependencies, configuration, and verification.
#
# Features:
# - Starlink quality monitoring with proactive failover
# - Azure cloud logging integration
# - GPS integration (RUTOS + Starlink fallback)
# - Performance data collection and analysis
# - Automated monitoring and alerting
# - Complete verification and health checks
#
# Version: 1.0-RUTOS
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# ==============================================================================

set -eu

# === COLORS AND FORMATTING ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# === CONFIGURATION DEFAULTS ===
DEFAULT_AZURE_ENDPOINT=""
DEFAULT_ENABLE_AZURE="false"
DEFAULT_ENABLE_STARLINK_MONITORING="true"
DEFAULT_ENABLE_GPS="true"
DEFAULT_ENABLE_PUSHOVER="false"
DEFAULT_RUTOS_IP="192.168.80.1"
DEFAULT_STARLINK_IP="192.168.100.1"

# === PATHS AND DIRECTORIES ===
# INSTALL_DIR="/root/starlink-solution"  # Reserved for future use
BACKUP_DIR="/root/backup-$(date +%Y%m%d-%H%M%S)"
CONFIG_DIR="/root"
SCRIPTS_DIR="/root"
HOTPLUG_DIR="/etc/hotplug.d/iface"

# === BINARY URLS (ARMv7 for RUTX50) ===
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# === LOGGING FUNCTIONS ===
log() {
    printf "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} %s\n" "$1"
    logger -t "starlink-deploy" "$1"
}

log_success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    logger -t "starlink-deploy" "SUCCESS: $1"
}

log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
    logger -t "starlink-deploy" "WARNING: $1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    logger -t "starlink-deploy" "ERROR: $1"
}

log_info() {
    printf "${BLUE}ℹ${NC} %s\n" "$1"
}

log_header() {
    printf "\n"
    printf "${PURPLE}=== %s ===${NC}\n" "$1"
    printf "\n"
}

# === INPUT VALIDATION ===
validate_ip() {
    ip="$1"

    # Check basic format using case statement (ash/dash compatible)
    case "$ip" in
        *[!0-9.]*) return 1 ;; # Contains non-numeric/non-dot chars
        *..*) return 1 ;;      # Contains consecutive dots
        .* | *.) return 1 ;;   # Starts or ends with dot
    esac

    # Count dots
    dot_count=$(echo "$ip" | tr -cd '.' | wc -c)
    if [ "$dot_count" -ne 3 ]; then
        return 1
    fi

    # Check each octet is <= 255 (ash/dash compatible)
    oldIFS="$IFS"
    IFS='.'
    set -- "$ip"
    IFS="$oldIFS"

    for octet in "$1" "$2" "$3" "$4"; do
        if [ -z "$octet" ] || [ "$octet" -gt 255 ] 2>/dev/null; then
            return 1
        fi
    done

    return 0
}

validate_url() {
    url="$1"
    case "$url" in
        http://* | https://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_user() {
    prompt="$1"
    default="$2"
    value=""

    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
        read -r value
        echo "${value:-$default}"
    else
        printf "%s: " "$prompt"
        read -r value
        echo "$value"
    fi
}

prompt_password() {
    prompt="$1"
    printf "%s: " "$prompt"
    stty -echo
    read -r value
    stty echo
    printf "\n"
    echo "$value"
}

# === PREREQUISITE CHECKS ===
check_prerequisites() {
    log_header "Checking Prerequisites"

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check device architecture - RUTOS compatibility
    arch=$(uname -m)
    arch=$(uname -m 2>/dev/null || echo "unknown")
    case "$arch" in
        "armv7l" | "aarch64" | "arm")
            log_success "Compatible ARM architecture detected: $arch"
            ;;
        *)
            log_warn "Device architecture ($arch) may not be compatible with ARM binaries"
            printf "Continue anyway? (y/N): "
            read -r confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                exit 1
            fi
            ;;
    esac

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity detected"
        exit 1
    fi

    # Check available space
    available_space=""
    available_space=$(df /overlay 2>/dev/null | awk 'NR==2 {print $4}' || df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 10240 ]; then # Less than 10MB
        log_warn "Low disk space available ($available_space KB)"
        printf "Continue anyway? (y/N): "
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            exit 1
        fi
    fi

    log_success "Prerequisites check completed"
}

# === CONFIGURATION COLLECTION ===
collect_configuration() {
    log_header "Configuration Setup"

    echo "This script will set up a complete Starlink monitoring solution."
    echo "Please provide the following configuration details:"
    echo

    # Azure configuration
    enable_azure=""
    enable_azure=$(prompt_user "Enable Azure cloud logging integration? (true/false)" "$DEFAULT_ENABLE_AZURE")

    azure_endpoint=""
    if [ "$enable_azure" = "true" ]; then
        azure_endpoint=$(prompt_user "Azure Function endpoint URL" "$DEFAULT_AZURE_ENDPOINT")
        if [ -z "$azure_endpoint" ]; then
            log_error "Azure endpoint URL is required when Azure logging is enabled"
            exit 1
        fi
        if ! validate_url "$azure_endpoint"; then
            log_error "Invalid Azure endpoint URL format"
            exit 1
        fi
    fi

    # Starlink monitoring
    enable_starlink_monitoring=""
    enable_starlink_monitoring=$(prompt_user "Enable Starlink performance monitoring? (true/false)" "$DEFAULT_ENABLE_STARLINK_MONITORING")

    # GPS configuration
    enable_gps=""
    enable_gps=$(prompt_user "Enable GPS integration? (true/false)" "$DEFAULT_ENABLE_GPS")

    rutos_ip=""
    rutos_username=""
    rutos_password=""
    if [ "$enable_gps" = "true" ]; then
        rutos_ip=$(prompt_user "RUTOS device IP address" "$DEFAULT_RUTOS_IP")
        if ! validate_ip "$rutos_ip"; then
            log_error "Invalid RUTOS IP address format"
            exit 1
        fi

        rutos_username=$(prompt_user "RUTOS username (optional)" "")
        if [ -n "$rutos_username" ]; then
            rutos_password=$(prompt_password "RUTOS password")
        fi
    fi

    # Pushover configuration
    enable_pushover=""
    enable_pushover=$(prompt_user "Enable Pushover notifications? (true/false)" "$DEFAULT_ENABLE_PUSHOVER")

    pushover_token=""
    pushover_user=""
    if [ "$enable_pushover" = "true" ]; then
        pushover_token=$(prompt_user "Pushover Application Token" "")
        pushover_user=$(prompt_user "Pushover User Key" "")

        if [ -z "$pushover_token" ] || [ -z "$pushover_user" ]; then
            log_error "Pushover token and user key are required when notifications are enabled"
            exit 1
        fi
    fi

    # Network configuration
    starlink_ip=""
    starlink_ip=$(prompt_user "Starlink dish IP address" "$DEFAULT_STARLINK_IP")
    if ! validate_ip "$starlink_ip"; then
        log_error "Invalid Starlink IP address format"
        exit 1
    fi

    # Export configuration for use by other functions
    export ENABLE_AZURE="$enable_azure"
    export AZURE_ENDPOINT="$azure_endpoint"
    export ENABLE_STARLINK_MONITORING="$enable_starlink_monitoring"
    export ENABLE_GPS="$enable_gps"
    export RUTOS_IP="$rutos_ip"
    export RUTOS_USERNAME="$rutos_username"
    export RUTOS_PASSWORD="$rutos_password"
    export ENABLE_PUSHOVER="$enable_pushover"
    export PUSHOVER_TOKEN="$pushover_token"
    export PUSHOVER_USER="$pushover_user"
    export STARLINK_IP="$starlink_ip"

    # Display configuration summary
    echo
    log_info "Configuration Summary:"
    log_info "  Azure Logging: $enable_azure"
    [ "$enable_azure" = "true" ] && log_info "  Azure Endpoint: $azure_endpoint"
    log_info "  Starlink Monitoring: $enable_starlink_monitoring"
    log_info "  GPS Integration: $enable_gps"
    [ "$enable_gps" = "true" ] && log_info "  RUTOS IP: $rutos_ip"
    log_info "  Pushover Notifications: $enable_pushover"
    log_info "  Starlink IP: $starlink_ip"
    echo

    printf "Proceed with installation? (y/N): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "Installation cancelled by user"
        exit 0
    fi
}

# === BACKUP EXISTING CONFIGURATION ===
create_backup() {
    log_header "Creating Backup"

    mkdir -p "$BACKUP_DIR"

    # Backup UCI configuration
    uci export >"$BACKUP_DIR/uci-backup.conf" 2>/dev/null || true

    # Backup crontab
    crontab -l >"$BACKUP_DIR/crontab-backup" 2>/dev/null || true

    # Backup existing scripts
    if [ -d "$SCRIPTS_DIR" ]; then
        cp -r "$SCRIPTS_DIR"/*.sh "$BACKUP_DIR/" 2>/dev/null || true
    fi

    # Backup hotplug scripts
    if [ -d "$HOTPLUG_DIR" ]; then
        cp -r "$HOTPLUG_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
    fi

    log_success "Backup created in: $BACKUP_DIR"
}

# === PACKAGE INSTALLATION ===
install_packages() {
    log_header "Installing Required Packages"

    # Update package list (optional for Teltonika's limited repository)
    log "Updating package list..."
    opkg update >/dev/null 2>&1 || {
        log_warn "Failed to update package list (Teltonika repository may be limited)"
    }

    # Check basic dependencies (most should be pre-installed on RUTOS)
    log "Checking basic dependencies..."

    # curl is usually pre-installed on RUTOS, but check anyway
    if ! command -v curl >/dev/null 2>&1; then
        log "Attempting to install curl..."
        if ! opkg install curl >/dev/null 2>&1; then
            log_error "curl not available and cannot be installed from Teltonika repository"
            log_error "curl is required for binary downloads and Azure integration"
            exit 1
        fi
    else
        log_success "curl already available"
    fi

    # bc calculator - try to install but don't fail (Teltonika may not have it)
    if ! command -v bc >/dev/null 2>&1; then
        log "Attempting to install bc calculator (optional)..."
        if opkg install bc >/dev/null 2>&1; then
            log_success "bc calculator installed from Teltonika repository"
        else
            log_warn "bc calculator not available in Teltonika repository - using fallbacks"
        fi
    else
        log_success "bc calculator already available"
    fi
}

# === BINARY INSTALLATION ===
install_binaries() {
    log_header "Installing Required Binaries"

    # Install grpcurl
    if [ ! -f "/root/grpcurl" ]; then
        log "Installing grpcurl..."

        # RUTOS-specific curl: no -L flag, but --max-time works
        if curl --max-time 30 "$GRPCURL_URL" -o /tmp/grpcurl.tar.gz 2>/dev/null; then
            if tar -zxf /tmp/grpcurl.tar.gz -C /root/ grpcurl 2>/dev/null; then
                chmod +x /root/grpcurl
                rm -f /tmp/grpcurl.tar.gz
                log_success "grpcurl installed"
            else
                log_error "Failed to extract grpcurl"
                exit 1
            fi
        else
            log_error "Failed to download grpcurl"
            exit 1
        fi
    else
        log_success "grpcurl already installed"
    fi

    # Install jq
    if [ ! -f "/root/jq" ]; then
        log "Installing jq..."

        # RUTOS-specific curl: no -L flag, but --max-time works
        if curl --max-time 30 "$JQ_URL" -o /root/jq 2>/dev/null; then
            chmod +x /root/jq
            log_success "jq installed"
        else
            log_error "Failed to download jq"
            exit 1
        fi
    else
        log_success "jq already installed"
    fi

    # Verify installations
    if /root/grpcurl --version >/dev/null 2>&1; then
        log_success "grpcurl verification passed"
    else
        log_error "grpcurl installation failed"
        exit 1
    fi

    if /root/jq --version >/dev/null 2>&1; then
        log_success "jq verification passed"
    else
        log_error "jq installation failed"
        exit 1
    fi
}

# === SCRIPT DEPLOYMENT ===
deploy_scripts() {
    log_header "Deploying Monitoring Scripts"

    # Create scripts directory
    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$HOTPLUG_DIR"

    # Generate main monitoring script
    create_starlink_monitor_script

    # Generate performance logger
    create_starlink_logger_script

    # Generate API checker
    create_api_checker_script

    # Generate Pushover notifier
    if [ "$ENABLE_PUSHOVER" = "true" ]; then
        create_pushover_notifier_script
    fi

    # Generate Azure logging scripts
    if [ "$ENABLE_AZURE" = "true" ]; then
        create_azure_scripts
    fi

    # Generate configuration file
    create_configuration_file

    log_success "All scripts deployed successfully"
}

# === CONFIGURATION SETUP ===
setup_system_configuration() {
    log_header "Configuring System Settings"

    # Setup persistent logging
    setup_persistent_logging

    # Setup UCI configuration
    setup_uci_configuration

    # Setup network routes
    setup_network_routes

    # Setup mwan3 configuration
    setup_mwan3_configuration

    log_success "System configuration completed"
}

setup_persistent_logging() {
    log "Setting up persistent logging..."

    # Configure system logging
    uci set system.@system[0].log_type='file'
    uci set system.@system[0].log_file='/overlay/messages'
    uci set system.@system[0].log_size='5120'
    uci commit system

    # Restart syslog
    /etc/init.d/log restart >/dev/null 2>&1

    log_success "Persistent logging configured"
}

setup_uci_configuration() {
    log "Setting up UCI configuration..."

    # Create Azure UCI section if Azure is enabled
    if [ "$ENABLE_AZURE" = "true" ]; then
        if ! uci show azure >/dev/null 2>&1; then
            touch /etc/config/azure
        fi

        # System logs configuration
        uci set azure.system=azure_config
        uci set azure.system.endpoint="$AZURE_ENDPOINT"
        uci set azure.system.enabled='1'
        uci set azure.system.log_file='/overlay/messages'
        uci set azure.system.max_size='1048576'

        # Starlink monitoring configuration
        if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
            uci set azure.starlink=starlink_config
            uci set azure.starlink.endpoint="$AZURE_ENDPOINT"
            uci set azure.starlink.enabled='1'
            uci set azure.starlink.csv_file='/overlay/starlink_performance.csv'
            uci set azure.starlink.max_size='1048576'
            uci set azure.starlink.starlink_ip="$STARLINK_IP:9200"
        fi

        # GPS configuration
        if [ "$ENABLE_GPS" = "true" ]; then
            uci set azure.gps=gps_config
            uci set azure.gps.enabled='1'
            uci set azure.gps.rutos_ip="$RUTOS_IP"
            uci set azure.gps.rutos_username="$RUTOS_USERNAME"
            uci set azure.gps.rutos_password="$RUTOS_PASSWORD"
        fi

        uci commit azure
    fi

    log_success "UCI configuration setup completed"
}

setup_network_routes() {
    log "Setting up network routes..."

    # Add static route to Starlink
    if ! ip route show | grep -q "$STARLINK_IP"; then
        # Check if route already exists in UCI
        route_exists=false
        for i in $(seq 0 10); do
            if uci get network.@route["$i"].target 2>/dev/null | grep -q "$STARLINK_IP"; then
                route_exists=true
                break
            fi
        done

        if [ "$route_exists" = "false" ]; then
            uci add network route
            uci set network.@route[-1].interface='wan'
            uci set network.@route[-1].target="$STARLINK_IP"
            uci set network.@route[-1].netmask='255.255.255.255'
            uci commit network

            # Apply immediately
            ip route add "$STARLINK_IP" dev "$(uci get network.wan.ifname 2>/dev/null || echo "eth1")" 2>/dev/null || true
        fi
    fi

    log_success "Network routes configured"
}

setup_mwan3_configuration() {
    log "Setting up mwan3 multi-WAN configuration..."

    # Set member metrics (Starlink priority)
    uci set mwan3.member1.metric='1' 2>/dev/null || true
    uci set mwan3.member3.metric='2' 2>/dev/null || true
    uci set mwan3.member4.metric='4' 2>/dev/null || true

    # Configure Starlink tracking
    uci set mwan3.@condition[1].interface='wan' 2>/dev/null || {
        uci add mwan3 condition
        uci set mwan3.@condition[-1].interface='wan'
    }
    uci set mwan3.@condition[1].track_method='ping'
    uci set mwan3.@condition[1].track_ip='1.0.0.1' '8.8.8.8'
    uci set mwan3.@condition[1].reliability='1'
    uci set mwan3.@condition[1].timeout='1'
    uci set mwan3.@condition[1].interval='1'
    uci set mwan3.@condition[1].count='1'
    uci set mwan3.@condition[1].down='2'
    uci set mwan3.@condition[1].up='3'

    uci commit mwan3

    log_success "mwan3 configuration completed"
}

# === CRON JOBS SETUP ===
setup_cron_jobs() {
    log_header "Setting up Automated Monitoring"

    # Remove existing starlink-related cron jobs
    (crontab -l 2>/dev/null | grep -v "starlink" || true) | crontab -

    # Add main monitoring script (every minute)
    (
        crontab -l 2>/dev/null
        echo "* * * * * $SCRIPTS_DIR/starlink_monitor.sh"
    ) | crontab -
    log_success "Starlink quality monitoring scheduled (every minute)"

    # Add performance logger (every minute)
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        (
            crontab -l 2>/dev/null
            echo "* * * * * $SCRIPTS_DIR/starlink_logger.sh"
        ) | crontab -
        log_success "Performance logging scheduled (every minute)"
    fi

    # Add API checker (daily)
    (
        crontab -l 2>/dev/null
        echo "30 5 * * * $SCRIPTS_DIR/check_starlink_api.sh"
    ) | crontab -
    log_success "API change detection scheduled (daily at 5:30 AM)"

    # Add Azure log shipping (every 5 minutes)
    if [ "$ENABLE_AZURE" = "true" ]; then
        (
            crontab -l 2>/dev/null
            echo "*/5 * * * * $SCRIPTS_DIR/log-shipper.sh"
        ) | crontab -
        log_success "Azure log shipping scheduled (every 5 minutes)"

        # Add Azure Starlink monitoring (every 2 minutes)
        if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
            (
                crontab -l 2>/dev/null
                echo "*/2 * * * * $SCRIPTS_DIR/starlink-azure-monitor.sh"
            ) | crontab -
            log_success "Azure Starlink monitoring scheduled (every 2 minutes)"
        fi
    fi

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1
    log_success "Cron service restarted"
}

# === SCRIPT GENERATORS ===
create_starlink_monitor_script() {
    cat >"$SCRIPTS_DIR/starlink_monitor.sh" <<'EOF'
#!/bin/sh
# Starlink Quality Monitor - Generated by deployment script
set -eu

# Load configuration
CONFIG_FILE="/root/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Default configuration
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
MWAN_IFACE="${MWAN_IFACE:-wan}"
MWAN_MEMBER="${MWAN_MEMBER:-member1}"
METRIC_GOOD="${METRIC_GOOD:-1}"
METRIC_BAD="${METRIC_BAD:-100}"
PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD:-0.05}"
OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD:-0.001}"
LATENCY_THRESHOLD_MS="${LATENCY_THRESHOLD_MS:-150}"
STABILITY_CHECKS_REQUIRED="${STABILITY_CHECKS_REQUIRED:-5}"

# State files
STATE_FILE="/tmp/run/starlink_monitor.state"
STABILITY_FILE="/tmp/run/starlink_monitor.stability"
LOG_TAG="StarlinkMonitor"

# Create state directory
mkdir -p "$(dirname "$STATE_FILE")"

# Logging function
log() {
    logger -t "$LOG_TAG" -- "$1"
}

# Main monitoring logic
main() {
    log "Starting quality check"
    
    # Read current state
    last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "up")
    stability_count=$(cat "$STABILITY_FILE" 2>/dev/null || echo "0")
    current_metric=$(uci -q get mwan3."$MWAN_MEMBER".metric 2>/dev/null || echo "$METRIC_GOOD")
    
    # Gather Starlink data
    if [ -x "/root/grpcurl" ] && [ -x "/root/jq" ]; then
        # Get status data (timeout works on RUTOS)
        status_json=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        # Get history data for packet loss
        history_json=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        if [ -n "$status_json" ] && [ -n "$history_json" ]; then
            # Extract metrics
            latency=$(echo "$status_json" | /root/jq -r '.dishGetStatus.popPingLatencyMs // 0' 2>/dev/null || echo "0")
            obstruction=$(echo "$status_json" | /root/jq -r '.dishGetStatus.obstructionStats.currentlyObstructed // false' 2>/dev/null || echo "false")
            
            # Calculate packet loss from history
            packet_loss=$(echo "$history_json" | /root/jq -r '
                [.dishGetHistory.popPingDropRate // empty] | 
                if length > 0 then (add / length) else 0 end
            ' 2>/dev/null || echo "0")
            
            # Evaluate quality using shell arithmetic fallback for RUTOS compatibility
            quality_good=true
            
            # Compare latency using shell arithmetic (multiply by 1000 to avoid decimals)
            latency_int=$(echo "$latency" | awk '{printf "%.0f", $1 * 1000}')
            threshold_int=$((LATENCY_THRESHOLD_MS * 1000))
            if [ "$latency_int" -gt "$threshold_int" ]; then
                quality_good=false
                log "Quality issue: High latency ($latency ms > $LATENCY_THRESHOLD_MS ms)"
            fi
            
            # Compare packet loss using shell arithmetic (multiply by 10000 to handle decimals)
            packet_loss_int=$(echo "$packet_loss" | awk '{printf "%.0f", $1 * 10000}')
            threshold_loss_int=$(echo "$PACKET_LOSS_THRESHOLD" | awk '{printf "%.0f", $1 * 10000}')
            if [ "$packet_loss_int" -gt "$threshold_loss_int" ]; then
                quality_good=false
                log "Quality issue: High packet loss ($packet_loss > $PACKET_LOSS_THRESHOLD)"
            fi
            
            if [ "$obstruction" = "true" ]; then
                quality_good=false
                log "Quality issue: Dish obstructed"
            fi
            
            # State machine logic
            if [ "$quality_good" = "true" ]; then
                if [ "$last_state" = "down" ]; then
                    stability_count=$((stability_count + 1))
                    if [ "$stability_count" -ge "$STABILITY_CHECKS_REQUIRED" ]; then
                        # Failback to good quality
                        uci set mwan3."$MWAN_MEMBER".metric="$METRIC_GOOD"
                        uci commit mwan3
                        mwan3 restart >/dev/null 2>&1
                        echo "up" > "$STATE_FILE"
                        echo "0" > "$STABILITY_FILE"
                        log "FAILBACK: Connection quality restored"
                        /etc/hotplug.d/iface/99-pushover_notify >/dev/null 2>&1 || true
                    else
                        echo "$stability_count" > "$STABILITY_FILE"
                        log "Quality good, stability count: $stability_count/$STABILITY_CHECKS_REQUIRED"
                    fi
                else
                    echo "0" > "$STABILITY_FILE"
                    log "Quality check passed"
                fi
            else
                if [ "$last_state" = "up" ]; then
                    # Failover due to poor quality
                    uci set mwan3."$MWAN_MEMBER".metric="$METRIC_BAD"
                    uci commit mwan3
                    mwan3 restart >/dev/null 2>&1
                    echo "down" > "$STATE_FILE"
                    echo "0" > "$STABILITY_FILE"
                    log "FAILOVER: Connection quality degraded"
                    /etc/hotplug.d/iface/99-pushover_notify >/dev/null 2>&1 || true
                else
                    log "Quality still poor, staying failed over"
                fi
            fi
        else
            log "Warning: Unable to get Starlink API data"
        fi
    else
        log "Error: grpcurl or jq not available"
    fi
}

# Run main function
main
EOF

    chmod +x "$SCRIPTS_DIR/starlink_monitor.sh"
    log_success "Starlink monitor script created"
}

create_starlink_logger_script() {
    cat >"$SCRIPTS_DIR/starlink_logger.sh" <<'EOF'
#!/bin/sh
# Starlink Performance Logger - Generated by deployment script
set -eu

# Configuration
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
OUTPUT_CSV="/root/starlink_performance_log.csv"
LAST_SAMPLE_FILE="/tmp/run/starlink_last_sample.ts"
LOG_TAG="StarlinkLogger"

# Create state directory
mkdir -p "$(dirname "$LAST_SAMPLE_FILE")"

# Logging function
log() {
    logger -t "$LOG_TAG" -- "$1"
}

# Create CSV header if file doesn't exist
if [ ! -f "$OUTPUT_CSV" ]; then
    echo "timestamp,latency_ms,packet_loss_rate,obstruction_percent,throughput_down_mbps,throughput_up_mbps" > "$OUTPUT_CSV"
fi

# Main logging logic
main() {
    log "Starting performance data collection"
    
    if [ -x "/root/grpcurl" ] && [ -x "/root/jq" ]; then
        # Get status data (timeout works on RUTOS)
        status_json=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        # Get history data
        history_json=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_history":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        if [ -n "$status_json" ] && [ -n "$history_json" ]; then
            # Extract current timestamp from status
            current_timestamp=$(echo "$status_json" | /root/jq -r '.dishGetStatus.uptimeS // 0' 2>/dev/null || echo "0")
            
            # Check if this is a new sample
            last_timestamp=$(cat "$LAST_SAMPLE_FILE" 2>/dev/null || echo "0")
            
            if [ "$current_timestamp" != "$last_timestamp" ]; then
                # Extract metrics
                latency=$(echo "$status_json" | /root/jq -r '.dishGetStatus.popPingLatencyMs // 0' 2>/dev/null || echo "0")
                
                # Calculate packet loss
                packet_loss=$(echo "$history_json" | /root/jq -r '
                    [.dishGetHistory.popPingDropRate // empty] | 
                    if length > 0 then (add / length) else 0 end
                ' 2>/dev/null || echo "0")
                
                # Get obstruction percentage
                obstruction=$(echo "$status_json" | /root/jq -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null || echo "0")
                
                # Get throughput
                throughput_down=$(echo "$status_json" | /root/jq -r '.dishGetStatus.downlinkThroughputBps // 0' 2>/dev/null || echo "0")
                throughput_up=$(echo "$status_json" | /root/jq -r '.dishGetStatus.uplinkThroughputBps // 0' 2>/dev/null || echo "0")
                
                # Convert to Mbps using awk for RUTOS compatibility
                throughput_down_mbps=$(echo "$throughput_down" | awk '{printf "%.2f", $1 / 1000000}')
                throughput_up_mbps=$(echo "$throughput_up" | awk '{printf "%.2f", $1 / 1000000}')
                
                # Create timestamp
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                
                # Append to CSV
                echo "$timestamp,$latency,$packet_loss,$obstruction,$throughput_down_mbps,$throughput_up_mbps" >> "$OUTPUT_CSV"
                
                # Update last sample timestamp
                echo "$current_timestamp" > "$LAST_SAMPLE_FILE"
                
                log "Performance data logged: latency=${latency}ms, packet_loss=${packet_loss}, obstruction=${obstruction}"
            else
                log "No new data available, skipping"
            fi
        else
            log "Warning: Unable to get Starlink API data"
        fi
    else
        log "Error: grpcurl or jq not available"
    fi
}

# Run main function
main
EOF

    chmod +x "$SCRIPTS_DIR/starlink_logger.sh"
    log_success "Starlink logger script created"
}

create_api_checker_script() {
    cat >"$SCRIPTS_DIR/check_starlink_api.sh" <<'EOF'
#!/bin/sh
# Starlink API Change Detector - Generated by deployment script
set -eu

# Configuration
STARLINK_IP="${STARLINK_IP:-192.168.100.1:9200}"
API_VERSION_FILE="/tmp/starlink_api_version"
LOG_TAG="StarlinkAPIChecker"

# Logging function
log() {
    logger -t "$LOG_TAG" -- "$1"
}

# Main checking logic
main() {
    log "Checking for Starlink API changes"
    
    if [ -x "/root/grpcurl" ] && [ -x "/root/jq" ]; then
        # Get current API response structure (timeout works on RUTOS)
        current_response=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        if [ -n "$current_response" ]; then
            # Create a simple hash of the response structure
            current_hash=$(echo "$current_response" | /root/jq -r 'keys_unsorted | @json' 2>/dev/null | md5sum | cut -d' ' -f1)
            
            if [ -f "$API_VERSION_FILE" ]; then
                last_hash=$(cat "$API_VERSION_FILE")
                
                if [ "$current_hash" != "$last_hash" ]; then
                    log "WARNING: Starlink API structure has changed!"
                    log "This may require script updates to maintain compatibility"
                    
                    # Trigger notification
                    /etc/hotplug.d/iface/99-pushover_notify >/dev/null 2>&1 || true
                else
                    log "API structure unchanged"
                fi
            else
                log "First run, recording API structure"
            fi
            
            echo "$current_hash" > "$API_VERSION_FILE"
        else
            log "Warning: Unable to get Starlink API data"
        fi
    else
        log "Error: grpcurl or jq not available"
    fi
}

# Run main function
main
EOF

    chmod +x "$SCRIPTS_DIR/check_starlink_api.sh"
    log_success "API checker script created"
}

create_pushover_notifier_script() {
    cat >"$HOTPLUG_DIR/99-pushover_notify" <<EOF
#!/bin/sh
# Pushover Notification Script - Generated by deployment script

# Load configuration
CONFIG_FILE="/root/config.sh"
if [ -f "\$CONFIG_FILE" ]; then
    . "\$CONFIG_FILE"
fi

# Pushover configuration
PUSHOVER_TOKEN="\${PUSHOVER_TOKEN:-$PUSHOVER_TOKEN}"
PUSHOVER_USER="\${PUSHOVER_USER:-$PUSHOVER_USER}"

# Only proceed if Pushover is configured
if [ -z "\$PUSHOVER_TOKEN" ] || [ -z "\$PUSHOVER_USER" ]; then
    exit 0
fi

# Notification function
send_notification() {
    title="\$1"
    message="\$2"
    priority="\${3:-0}"
    
    curl -s \\
        --form-string "token=\$PUSHOVER_TOKEN" \\
        --form-string "user=\$PUSHOVER_USER" \\
        --form-string "title=\$title" \\
        --form-string "message=\$message" \\
        --form-string "priority=\$priority" \\
        https://api.pushover.net/1/messages.json >/dev/null 2>&1
}

# Determine notification type and send
if grep -q "FAILOVER" /var/log/messages | tail -1; then
    send_notification "Starlink Failover" "Connection quality degraded, switched to backup" "1"
elif grep -q "FAILBACK" /var/log/messages | tail -1; then
    send_notification "Starlink Failback" "Connection quality restored, switched back to Starlink" "0"
elif grep -q "API.*changed" /var/log/messages | tail -1; then
    send_notification "Starlink API Change" "API structure has changed, scripts may need updates" "1"
fi
EOF

    chmod +x "$HOTPLUG_DIR/99-pushover_notify"
    log_success "Pushover notifier script created"
}

create_azure_scripts() {
    # Create log shipper script
    cat >"$SCRIPTS_DIR/log-shipper.sh" <<EOF
#!/bin/sh
# Azure Log Shipper - Generated by deployment script
set -eu

# Configuration from UCI
AZURE_ENDPOINT="\$(uci get azure.system.endpoint 2>/dev/null || echo "")"
LOG_FILE="\$(uci get azure.system.log_file 2>/dev/null || echo "/overlay/messages")"
MAX_SIZE="\$(uci get azure.system.max_size 2>/dev/null || echo "1048576")"

# Exit if Azure not configured
if [ -z "\$AZURE_ENDPOINT" ]; then
    exit 0
fi

# Main log shipping logic
if [ -f "\$LOG_FILE" ] && [ -s "\$LOG_FILE" ]; then
    # Get file size - use wc as fallback for RUTOS compatibility
    file_size=\$(wc -c < "\$LOG_FILE" 2>/dev/null || echo "0")
    
    if [ "\$file_size" -gt 100 ]; then
        # Create filename with current date
        filename="router-\$(date '+%Y-%m-%d').log"
        
        # Send logs to Azure
        curl -X POST "\$AZURE_ENDPOINT" \\
            -H "Content-Type: text/plain" \\
            -d "@\$LOG_FILE" \\
            --max-time 30 >/dev/null 2>&1
        
        # Rotate log if it's too large
        if [ "\$file_size" -gt "\$MAX_SIZE" ]; then
            echo "\$(date): Log rotated" > "\$LOG_FILE"
        else
            # Clear the log file
            > "\$LOG_FILE"
        fi
        
        logger -t "LogShipper" "Logs shipped to Azure (\$file_size bytes)"
    fi
fi
EOF

    chmod +x "$SCRIPTS_DIR/log-shipper.sh"
    log_success "Azure log shipper script created"

    # Create Azure Starlink monitor if enabled
    if [ "$ENABLE_STARLINK_MONITORING" = "true" ]; then
        cat >"$SCRIPTS_DIR/starlink-azure-monitor.sh" <<'EOF'
#!/bin/sh
# Azure Starlink Monitor - Generated by deployment script
set -eu

# Configuration from UCI
AZURE_ENDPOINT="$(uci get azure.starlink.endpoint 2>/dev/null || echo "")"
CSV_FILE="$(uci get azure.starlink.csv_file 2>/dev/null || echo "/overlay/starlink_performance.csv")"
MAX_SIZE="$(uci get azure.starlink.max_size 2>/dev/null || echo "1048576")"
STARLINK_IP="$(uci get azure.starlink.starlink_ip 2>/dev/null || echo "192.168.100.1:9200")"

# Exit if Azure not configured
if [ -z "$AZURE_ENDPOINT" ]; then
    exit 0
fi

# GPS configuration
RUTOS_IP="$(uci get azure.gps.rutos_ip 2>/dev/null || echo "")"
RUTOS_USERNAME="$(uci get azure.gps.rutos_username 2>/dev/null || echo "")"
RUTOS_PASSWORD="$(uci get azure.gps.rutos_password 2>/dev/null || echo "")"

# Main monitoring logic
main() {
    if [ -x "/root/grpcurl" ] && [ -x "/root/jq" ]; then
        # Get Starlink data (timeout works on RUTOS)
        status_json=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        if [ -n "$status_json" ]; then
            # Extract comprehensive metrics
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            latency=$(echo "$status_json" | /root/jq -r '.dishGetStatus.popPingLatencyMs // 0' 2>/dev/null || echo "0")
            throughput_down=$(echo "$status_json" | /root/jq -r '.dishGetStatus.downlinkThroughputBps // 0' 2>/dev/null || echo "0")
            throughput_up=$(echo "$status_json" | /root/jq -r '.dishGetStatus.uplinkThroughputBps // 0' 2>/dev/null || echo "0")
            obstruction=$(echo "$status_json" | /root/jq -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null || echo "0")
            snr=$(echo "$status_json" | /root/jq -r '.dishGetStatus.snr // 0' 2>/dev/null || echo "0")
            
            # Convert to Mbps using awk for RUTOS compatibility
            throughput_down_mbps=$(echo "$throughput_down" | awk '{printf "%.2f", $1 / 1000000}')
            throughput_up_mbps=$(echo "$throughput_up" | awk '{printf "%.2f", $1 / 1000000}')
            
            # Get GPS data (placeholder - can be enhanced)
            gps_data=",,,"
            
            # Create CSV entry
            csv_entry="$timestamp,$latency,$throughput_down_mbps,$throughput_up_mbps,$obstruction,$snr,$gps_data"
            
            # Append to CSV file
            echo "$csv_entry" >> "$CSV_FILE"
            
            # Ship to Azure if file exists and has content
            if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
                file_size=$(wc -c < "$CSV_FILE" 2>/dev/null || echo "0")
                
                if [ "$file_size" -gt 100 ]; then
                    # Send to Azure
                    curl -X POST "$AZURE_ENDPOINT" \
                        -H "Content-Type: text/csv" \
                        -d "@$CSV_FILE" \
                        --max-time 30 >/dev/null 2>&1
                    
                    # Rotate if too large
                    if [ "$file_size" -gt "$MAX_SIZE" ]; then
                        echo "timestamp,latency_ms,throughput_down_mbps,throughput_up_mbps,obstruction_percent,snr,latitude,longitude,altitude" > "$CSV_FILE"
                    fi
                    
                    logger -t "StarlinkAzureMonitor" "Performance data shipped to Azure ($file_size bytes)"
                fi
            fi
        fi
    fi
}

# Run main function
main
EOF

        chmod +x "$SCRIPTS_DIR/starlink-azure-monitor.sh"
        log_success "Azure Starlink monitor script created"
    fi
}

create_configuration_file() {
    cat >"$CONFIG_DIR/config.sh" <<EOF
#!/bin/sh
# Starlink Solution Configuration - Generated by deployment script

# === NETWORK CONFIGURATION ===
STARLINK_IP="$STARLINK_IP"
MWAN_IFACE="wan"
MWAN_MEMBER="member1"

# === QUALITY THRESHOLDS ===
PACKET_LOSS_THRESHOLD="0.05"
OBSTRUCTION_THRESHOLD="0.001"
LATENCY_THRESHOLD_MS="150"
STABILITY_CHECKS_REQUIRED="5"

# === FAILOVER METRICS ===
METRIC_GOOD="1"
METRIC_BAD="100"

# === PUSHOVER CONFIGURATION ===
PUSHOVER_ENABLED="$ENABLE_PUSHOVER"
PUSHOVER_TOKEN="$PUSHOVER_TOKEN"
PUSHOVER_USER="$PUSHOVER_USER"

# === AZURE CONFIGURATION ===
AZURE_ENABLED="$ENABLE_AZURE"
AZURE_ENDPOINT="$AZURE_ENDPOINT"

# === GPS CONFIGURATION ===
GPS_ENABLED="$ENABLE_GPS"
RUTOS_IP="$RUTOS_IP"
RUTOS_USERNAME="$RUTOS_USERNAME"
RUTOS_PASSWORD="$RUTOS_PASSWORD"

# === MONITORING SETTINGS ===
STARLINK_MONITORING_ENABLED="$ENABLE_STARLINK_MONITORING"

# === LOGGING CONFIGURATION ===
LOG_TAG="StarlinkSolution"
STATE_FILE="/tmp/run/starlink_monitor.state"
STABILITY_FILE="/tmp/run/starlink_monitor.stability"
OUTPUT_CSV="/root/starlink_performance_log.csv"
EOF

    chmod 600 "$CONFIG_DIR/config.sh"
    log_success "Configuration file created"
}

# === VERIFICATION SCRIPT ===
create_verification_script() {
    log_header "Creating Verification Script"

    cat >"$SCRIPTS_DIR/verify-starlink-setup.sh" <<'EOF'
#!/bin/sh
# Starlink Solution Verification Script
set -eu

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Logging functions
log_test() {
    printf "%s[TEST]%s %s\n" "$BLUE" "$NC" "$1"
}

log_pass() {
    printf "%s[PASS]%s %s\n" "$GREEN" "$NC" "$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    printf "%s[FAIL]%s %s\n" "$RED" "$NC" "$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warn() {
    printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$1"
    TESTS_WARNED=$((TESTS_WARNED + 1))
}

log_info() {
    printf "%s[INFO]%s %s\n" "$BLUE" "$NC" "$1"
}

# Test functions
test_binaries() {
    log_test "Testing required binaries..."
    
    if [ -x "/root/grpcurl" ]; then
        version=""
        version=$(/root/grpcurl --version 2>&1 | head -1)
        log_pass "grpcurl available: $version"
    else
        log_fail "grpcurl not found or not executable"
    fi
    
    if [ -x "/root/jq" ]; then
        version=""
        version=$(/root/jq --version 2>&1)
        log_pass "jq available: $version"
    else
        log_fail "jq not found or not executable"
    fi
    
    if command -v bc >/dev/null 2>&1; then
        log_pass "bc calculator available"
    else
        log_warn "bc calculator not available (may affect some calculations)"
    fi
}

test_scripts() {
    log_test "Testing deployed scripts..."
    
    scripts=(
        "/root/starlink_monitor.sh"
        "/root/starlink_logger.sh"
        "/root/check_starlink_api.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -x "$script" ]; then
            log_pass "$(basename "$script") deployed and executable"
        else
            log_fail "$(basename "$script") missing or not executable"
        fi
    done
    
    # Check Pushover notifier
    if [ -x "/etc/hotplug.d/iface/99-pushover_notify" ]; then
        log_pass "Pushover notifier deployed"
    else
        log_warn "Pushover notifier not found (notifications disabled)"
    fi
    
    # Check Azure scripts
    if [ -x "/root/log-shipper.sh" ]; then
        log_pass "Azure log shipper deployed"
    else
        log_warn "Azure log shipper not found (Azure logging disabled)"
    fi
    
    if [ -x "/root/starlink-azure-monitor.sh" ]; then
        log_pass "Azure Starlink monitor deployed"
    else
        log_warn "Azure Starlink monitor not found (Azure monitoring disabled)"
    fi
}

test_configuration() {
    log_test "Testing system configuration..."
    
    # Test UCI configuration
    if uci show system | grep -q "log_type='file'"; then
        log_pass "Persistent logging configured"
    else
        log_fail "Persistent logging not configured"
    fi
    
    # Test network routes
    if ip route show | grep -q "192.168.100.1"; then
        log_pass "Starlink route configured"
        route_info=""
        route_info=$(ip route show | grep "192.168.100.1" | head -1)
        log_info "Route: $route_info"
    else
        log_fail "No route to Starlink management interface"
    fi
    
    # Test mwan3 configuration
    if uci show mwan3 | grep -q "member1"; then
        log_pass "mwan3 configuration found"
    else
        log_warn "mwan3 configuration may not be complete"
    fi
}

test_connectivity() {
    log_test "Testing connectivity..."
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_pass "Internet connectivity working"
    else
        log_fail "No internet connectivity"
    fi
    
    # Test Starlink management interface
    if ping -c 1 192.168.100.1 >/dev/null 2>&1; then
        log_pass "Starlink management interface reachable"
    else
        log_warn "Starlink management interface not reachable"
    fi
    
    # Test Starlink API
    if [ -x "/root/grpcurl" ]; then
        api_response=""
        api_response=$(timeout 10 /root/grpcurl -plaintext --max-time 5 \
            -d '{"get_status":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")
        
        if [ -n "$api_response" ]; then
            log_pass "Starlink API responding"
        else
            log_warn "Starlink API not responding (check dish connection)"
        fi
    fi
}

test_cron_jobs() {
    log_test "Testing scheduled jobs..."
    
    cron_jobs=""
    cron_jobs=$(crontab -l 2>/dev/null || echo "")
    
    if echo "$cron_jobs" | grep -q "starlink_monitor.sh"; then
        log_pass "Quality monitoring scheduled"
    else
        log_fail "Quality monitoring not scheduled"
    fi
    
    if echo "$cron_jobs" | grep -q "starlink_logger.sh"; then
        log_pass "Performance logging scheduled"
    else
        log_warn "Performance logging not scheduled"
    fi
    
    if echo "$cron_jobs" | grep -q "check_starlink_api.sh"; then
        log_pass "API change detection scheduled"
    else
        log_warn "API change detection not scheduled"
    fi
    
    # Check cron service
    if pgrep crond >/dev/null; then
        log_pass "Cron service running"
    else
        log_fail "Cron service not running"
    fi
}

test_logs() {
    log_test "Testing logging system..."
    
    # Test log files
    if [ -f "/overlay/messages" ]; then
        log_pass "System log file exists"
        log_size=""
        log_size=$(wc -c < "/overlay/messages" 2>/dev/null || echo "0")
        log_info "Log file size: $log_size bytes"
    else
        log_fail "System log file not found"
    fi
    
    # Test performance log
    if [ -f "/root/starlink_performance_log.csv" ]; then
        log_pass "Performance log file exists"
    else
        log_warn "Performance log file not yet created"
    fi
    
    # Test recent log entries
    if logread | grep -q "StarlinkMonitor\|StarlinkLogger" | tail -1; then
        log_pass "Recent monitoring activity found in logs"
    else
        log_warn "No recent monitoring activity in logs (may need time to start)"
    fi
}

# Main verification
main() {
    echo "========================================="
    echo "Starlink Solution Verification"
    echo "========================================="
    echo
    
    test_binaries
    echo
    test_scripts
    echo
    test_configuration
    echo
    test_connectivity
    echo
    test_cron_jobs
    echo
    test_logs
    echo
    
    # Summary
    echo "========================================="
    echo "Verification Summary"
    echo "========================================="
    printf "%bTests Passed: %d%b\n" "$GREEN" "$TESTS_PASSED" "$NC"
    printf "%bTests Warned: %d%b\n" "$YELLOW" "$TESTS_WARNED" "$NC"
    printf "%bTests Failed: %d%b\n" "$RED" "$TESTS_FAILED" "$NC"
    echo
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        printf "%b✓ Verification completed successfully!%b\n" "$GREEN" "$NC"
        echo "The Starlink monitoring solution is properly deployed and configured."
        echo
        echo "Next steps:"
        echo "1. Wait 5-10 minutes for initial data collection"
        echo "2. Check logs: logread | grep Starlink"
        echo "3. Monitor performance: tail -f /root/starlink_performance_log.csv"
        echo "4. Test failover by setting low thresholds temporarily"
        return 0
    else
        printf "%b✗ Verification found issues that need attention%b\n" "$RED" "$NC"
        echo "Please review the failed tests above and address any configuration issues."
        return 1
    fi
}

# Run verification
main
EOF

    chmod +x "$SCRIPTS_DIR/verify-starlink-setup.sh"
    log_success "Verification script created"
}

# === FINAL DEPLOYMENT ===
finalize_deployment() {
    log_header "Finalizing Deployment"

    # Create verification script
    create_verification_script

    # Final system configuration commit
    uci commit

    # Restart services
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/cron restart >/dev/null 2>&1

    # Set permissions
    chmod -R 755 "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
    chmod 755 "$HOTPLUG_DIR"/99-pushover_notify 2>/dev/null || true

    log_success "Deployment finalized"
}

# === MAIN DEPLOYMENT FUNCTION ===
main() {
    echo
    echo "========================================="
    echo "Starlink Solution Deployment for RUTOS"
    echo "========================================="
    echo
    echo "This script will deploy a complete Starlink monitoring and"
    echo "failover solution with the following features:"
    echo
    echo "• Proactive quality monitoring with automatic failover"
    echo "• Performance data logging and analysis"
    echo "• Optional Azure cloud logging integration"
    echo "• Optional GPS integration for location tracking"
    echo "• Optional Pushover notifications for alerts"
    echo "• Complete verification and health checking"
    echo
    echo "========================================="

    # Run deployment steps
    check_prerequisites
    collect_configuration
    create_backup
    install_packages
    install_binaries
    deploy_scripts
    setup_system_configuration
    setup_cron_jobs
    finalize_deployment

    # Final success message
    echo
    log_success "🎉 Starlink Solution Deployment Completed Successfully! 🎉"
    echo
    log_info "Installation Summary:"
    log_info "  • Backup created: $BACKUP_DIR"
    log_info "  • Scripts installed: $SCRIPTS_DIR"
    log_info "  • Configuration file: $CONFIG_DIR/config.sh"
    log_info "  • Verification script: $SCRIPTS_DIR/verify-starlink-setup.sh"
    echo
    log_info "Next Steps:"
    log_info "  1. Run verification: $SCRIPTS_DIR/verify-starlink-setup.sh"
    log_info "  2. Wait 5-10 minutes for initial monitoring to start"
    log_info "  3. Check logs: logread | grep Starlink"
    log_info "  4. Monitor performance data: tail -f /root/starlink_performance_log.csv"
    echo
    log_info "For support and documentation, visit:"
    log_info "  https://github.com/markus-lassfolk/rutos-starlink-failover"
    echo
}

# Execute main function
main "$@"
