#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "rutos-factory-reset-recovery-rutos.sh" "$SCRIPT_VERSION"

# === RUTX50 FACTORY RESET RECOVERY SCRIPT ===
# Automated restoration of custom configurations after factory reset

readonly SCRIPT_NAME="rutos-factory-reset-recovery-rutos.sh"

# === CONFIGURATION FILES ===
CONFIG_BACKUP_DIR="/tmp/rutos_recovery"
WG_CONFIG_FILE="$CONFIG_BACKUP_DIR/wireguard_config.conf"
ROUTING_CONFIG_FILE="$CONFIG_BACKUP_DIR/routing_config.sh"
FIREWALL_CONFIG_FILE="$CONFIG_BACKUP_DIR/firewall_config.sh"
MWAN3_CONFIG_FILE="$CONFIG_BACKUP_DIR/mwan3_config.sh"

# Create backup directory
mkdir -p "$CONFIG_BACKUP_DIR"

# === USER INPUT FUNCTIONS ===
prompt_user() {
    local prompt="$1"
    local variable_name="$2"
    local default_value="$3"
    local is_secret="${4:-0}"
    
    if [ -n "$default_value" ]; then
        prompt="$prompt [$default_value]"
    fi
    
    printf "%s: " "$prompt"
    
    if [ "$is_secret" = "1" ]; then
        # For secrets, don't echo the input
        stty -echo 2>/dev/null || true
        read -r user_input
        stty echo 2>/dev/null || true
        printf "\n"
    else
        read -r user_input
    fi
    
    if [ -z "$user_input" ] && [ -n "$default_value" ]; then
        user_input="$default_value"
    fi
    
    eval "$variable_name=\"\$user_input\""
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    printf "%s [y/N]: " "$message"
    read -r response
    
    if [ -z "$response" ]; then
        response="$default"
    fi
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# === WIREGUARD CONFIGURATION ===
configure_wireguard() {
    log_info "=== WireGuard VPN Configuration ==="
    
    # Collect WireGuard information
    prompt_user "WireGuard Private Key for this RUTX50" "WG_PRIVATE_KEY" "" "1"
    prompt_user "WireGuard Public Key for Klara network peer" "WG_PEER_PUBLIC_KEY" "" "0"
    prompt_user "Klara network endpoint (IP:Port)" "WG_ENDPOINT" "your-klara-ip:51820" "0"
    prompt_user "Local VPN IP for this device" "WG_LOCAL_IP" "10.0.0.2/24" "0"
    prompt_user "WireGuard listen port" "WG_LISTEN_PORT" "51820" "0"
    prompt_user "Networks to route through VPN (space-separated)" "WG_ALLOWED_IPS" "192.168.1.0/24 192.168.20.0/24" "0"
    prompt_user "Persistent keepalive interval" "WG_KEEPALIVE" "25" "0"
    
    if [ -z "$WG_PRIVATE_KEY" ] || [ -z "$WG_PEER_PUBLIC_KEY" ] || [ -z "$WG_ENDPOINT" ]; then
        log_error "Missing required WireGuard configuration"
        return 1
    fi
    
    log_step "Configuring WireGuard interface..."
    
    # Create WireGuard configuration script
    cat > "$WG_CONFIG_FILE" << EOF
#!/bin/sh
# WireGuard Configuration for Klara VPN

# Install WireGuard packages
opkg update
opkg install wireguard-tools kmod-wireguard

# Configure WireGuard interface
uci set network.wg_klara=interface
uci set network.wg_klara.proto='wireguard'
uci set network.wg_klara.private_key='$WG_PRIVATE_KEY'
uci set network.wg_klara.listen_port='$WG_LISTEN_PORT'
uci set network.wg_klara.addresses='$WG_LOCAL_IP'

# Add peer configuration
uci add network wireguard_wg_klara
uci set network.@wireguard_wg_klara[0]=wireguard_wg_klara
uci set network.@wireguard_wg_klara[0].public_key='$WG_PEER_PUBLIC_KEY'
uci set network.@wireguard_wg_klara[0].endpoint_host='${WG_ENDPOINT%:*}'
uci set network.@wireguard_wg_klara[0].endpoint_port='${WG_ENDPOINT#*:}'
uci set network.@wireguard_wg_klara[0].allowed_ips='$WG_ALLOWED_IPS'
uci set network.@wireguard_wg_klara[0].persistent_keepalive='$WG_KEEPALIVE'

# Commit and restart network
uci commit network
/etc/init.d/network restart

echo "WireGuard configuration completed"
EOF
    
    chmod +x "$WG_CONFIG_FILE"
    
    if confirm_action "Apply WireGuard configuration now?"; then
        log_step "Applying WireGuard configuration..."
        if safe_execute "$WG_CONFIG_FILE" "Configure WireGuard VPN"; then
            log_success "WireGuard configuration applied"
        else
            log_error "Failed to apply WireGuard configuration"
            return 1
        fi
    else
        log_info "WireGuard configuration saved to: $WG_CONFIG_FILE"
        log_info "Run this script manually when ready"
    fi
}

# === ROUTING CONFIGURATION ===
configure_routing() {
    log_info "=== Routing Configuration ==="
    
    prompt_user "Additional networks to route through VPN" "ADDITIONAL_NETWORKS" "" "0"
    
    # Create routing configuration script
    cat > "$ROUTING_CONFIG_FILE" << EOF
#!/bin/sh
# Custom Routing Configuration

# Add custom routing table for VPN
if ! grep -q "vpn_table" /etc/iproute2/rt_tables; then
    echo "200 vpn_table" >> /etc/iproute2/rt_tables
fi

# Route specific networks through VPN
ip route add 192.168.1.0/24 dev wg_klara table vpn_table 2>/dev/null || true
ip route add 192.168.20.0/24 dev wg_klara table vpn_table 2>/dev/null || true

EOF
    
    # Add additional networks if specified
    if [ -n "$ADDITIONAL_NETWORKS" ]; then
        for network in $ADDITIONAL_NETWORKS; do
            echo "ip route add $network dev wg_klara table vpn_table 2>/dev/null || true" >> "$ROUTING_CONFIG_FILE"
        done
    fi
    
    cat >> "$ROUTING_CONFIG_FILE" << EOF

# Add routing rules for VPN traffic
ip rule add from 192.168.0.0/16 to 192.168.1.0/24 table vpn_table 2>/dev/null || true
ip rule add from 192.168.0.0/16 to 192.168.20.0/24 table vpn_table 2>/dev/null || true

EOF
    
    # Add rules for additional networks
    if [ -n "$ADDITIONAL_NETWORKS" ]; then
        for network in $ADDITIONAL_NETWORKS; do
            echo "ip rule add from 192.168.0.0/16 to $network table vpn_table 2>/dev/null || true" >> "$ROUTING_CONFIG_FILE"
        done
    fi
    
    cat >> "$ROUTING_CONFIG_FILE" << EOF

# Direct route to Starlink management (bypass MWAN3)
ip route add 192.168.100.1/32 dev wan metric 1 2>/dev/null || true

echo "Routing configuration completed"
EOF
    
    chmod +x "$ROUTING_CONFIG_FILE"
    
    if confirm_action "Apply routing configuration now?"; then
        log_step "Applying routing configuration..."
        if safe_execute "$ROUTING_CONFIG_FILE" "Configure custom routing"; then
            log_success "Routing configuration applied"
        else
            log_error "Failed to apply routing configuration"
            return 1
        fi
    else
        log_info "Routing configuration saved to: $ROUTING_CONFIG_FILE"
    fi
}

# === FIREWALL CONFIGURATION ===
configure_firewall() {
    log_info "=== Firewall Configuration ==="
    
    # Create firewall configuration script
    cat > "$FIREWALL_CONFIG_FILE" << EOF
#!/bin/sh
# Firewall Configuration for VPN and Custom Rules

# Create VPN firewall zone
uci set firewall.vpn_zone=zone
uci set firewall.vpn_zone.name='vpn'
uci set firewall.vpn_zone.input='ACCEPT'
uci set firewall.vpn_zone.output='ACCEPT'
uci set firewall.vpn_zone.forward='ACCEPT'
uci set firewall.vpn_zone.network='wg_klara'

# Allow VPN to LAN forwarding
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='vpn'
uci set firewall.@forwarding[-1].dest='lan'

# Allow LAN to VPN forwarding
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='vpn'

# Allow WireGuard port through WAN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='$WG_LISTEN_PORT'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

# Allow access to Starlink management from LAN/VPN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-Starlink-Access'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].dest_ip='192.168.100.1'
uci set firewall.@rule[-1].target='ACCEPT'

# Allow VPN access to Starlink management
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-VPN-Starlink-Access'
uci set firewall.@rule[-1].src='vpn'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].dest_ip='192.168.100.1'
uci set firewall.@rule[-1].target='ACCEPT'

# Commit firewall changes
uci commit firewall
/etc/init.d/firewall restart

echo "Firewall configuration completed"
EOF
    
    chmod +x "$FIREWALL_CONFIG_FILE"
    
    if confirm_action "Apply firewall configuration now?"; then
        log_step "Applying firewall configuration..."
        if safe_execute "$FIREWALL_CONFIG_FILE" "Configure firewall rules"; then
            log_success "Firewall configuration applied"
        else
            log_error "Failed to apply firewall configuration"
            return 1
        fi
    else
        log_info "Firewall configuration saved to: $FIREWALL_CONFIG_FILE"
    fi
}

# === MWAN3 CONFIGURATION ===
configure_mwan3() {
    log_info "=== MWAN3 Multi-WAN Configuration ==="
    
    prompt_user "Primary WAN interface name" "WAN_INTERFACE" "wan" "0"
    prompt_user "Cellular interface name" "CELLULAR_INTERFACE" "mob1s1a1" "0"
    prompt_user "VPN ping target (for health checks)" "VPN_PING_TARGET" "192.168.1.1" "0"
    
    # Create MWAN3 configuration script
    cat > "$MWAN3_CONFIG_FILE" << EOF
#!/bin/sh
# MWAN3 Multi-WAN Configuration

# Install MWAN3 if not present
opkg update
opkg install mwan3

# Configure WAN interface
uci set mwan3.$WAN_INTERFACE=interface
uci set mwan3.$WAN_INTERFACE.enabled='1'
uci set mwan3.$WAN_INTERFACE.initial_state='online'
uci set mwan3.$WAN_INTERFACE.family='ipv4'
uci set mwan3.$WAN_INTERFACE.track_method='ping'
uci set mwan3.$WAN_INTERFACE.track_hosts='8.8.8.8 1.1.1.1'
uci set mwan3.$WAN_INTERFACE.ping_timeout='4'
uci set mwan3.$WAN_INTERFACE.ping_interval='10'
uci set mwan3.$WAN_INTERFACE.interface='$WAN_INTERFACE'

# Configure cellular interface
uci set mwan3.$CELLULAR_INTERFACE=interface
uci set mwan3.$CELLULAR_INTERFACE.enabled='1'
uci set mwan3.$CELLULAR_INTERFACE.initial_state='online'
uci set mwan3.$CELLULAR_INTERFACE.family='ipv4'
uci set mwan3.$CELLULAR_INTERFACE.track_method='ping'
uci set mwan3.$CELLULAR_INTERFACE.track_hosts='8.8.8.8'
uci set mwan3.$CELLULAR_INTERFACE.ping_timeout='4'
uci set mwan3.$CELLULAR_INTERFACE.ping_interval='60'
uci set mwan3.$CELLULAR_INTERFACE.interface='$CELLULAR_INTERFACE'

# Configure VPN interface
uci set mwan3.wg_klara=interface
uci set mwan3.wg_klara.enabled='1'
uci set mwan3.wg_klara.initial_state='online'
uci set mwan3.wg_klara.family='ipv4'
uci set mwan3.wg_klara.track_method='ping'
uci set mwan3.wg_klara.track_hosts='$VPN_PING_TARGET'
uci set mwan3.wg_klara.ping_timeout='4'
uci set mwan3.wg_klara.ping_interval='30'
uci set mwan3.wg_klara.interface='wg_klara'

# Basic load balancing policies
uci set mwan3.balanced=policy
uci set mwan3.balanced.type='balance'

# Add interfaces to policy
uci add_list mwan3.balanced.use_member='$WAN_INTERFACE'
uci add_list mwan3.balanced.use_member='$CELLULAR_INTERFACE'

# Default route rule
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule.use_policy='balanced'

# Commit MWAN3 configuration
uci commit mwan3
/etc/init.d/mwan3 restart

echo "MWAN3 configuration completed"
EOF
    
    chmod +x "$MWAN3_CONFIG_FILE"
    
    if confirm_action "Apply MWAN3 configuration now?"; then
        log_step "Applying MWAN3 configuration..."
        if safe_execute "$MWAN3_CONFIG_FILE" "Configure MWAN3 multi-WAN"; then
            log_success "MWAN3 configuration applied"
        else
            log_error "Failed to apply MWAN3 configuration"
            return 1
        fi
    else
        log_info "MWAN3 configuration saved to: $MWAN3_CONFIG_FILE"
    fi
}

# === VERIFICATION FUNCTIONS ===
verify_configuration() {
    log_info "=== Configuration Verification ==="
    
    # Check WireGuard interface
    if ip link show wg_klara >/dev/null 2>&1; then
        log_success "WireGuard interface 'wg_klara' exists"
        
        # Check if interface is up
        if ip link show wg_klara | grep -q "state UP"; then
            log_success "WireGuard interface is UP"
        else
            log_warning "WireGuard interface is DOWN"
        fi
    else
        log_error "WireGuard interface 'wg_klara' not found"
    fi
    
    # Check MWAN3 status
    if command -v mwan3 >/dev/null 2>&1; then
        log_success "MWAN3 is installed"
        
        # Get MWAN3 status
        log_info "MWAN3 Interface Status:"
        mwan3 status || log_warning "MWAN3 status check failed"
    else
        log_warning "MWAN3 not installed or not found"
    fi
    
    # Check firewall zones
    if uci show firewall | grep -q "vpn_zone"; then
        log_success "VPN firewall zone configured"
    else
        log_warning "VPN firewall zone not found"
    fi
    
    # Test connectivity
    log_info "Testing connectivity..."
    
    # Test Starlink access
    if ping -c 1 -W 3 192.168.100.1 >/dev/null 2>&1; then
        log_success "Starlink management (192.168.100.1) is reachable"
    else
        log_warning "Cannot reach Starlink management (192.168.100.1)"
    fi
    
    # Test VPN target
    if [ -n "$VPN_PING_TARGET" ]; then
        if ping -c 1 -W 3 "$VPN_PING_TARGET" >/dev/null 2>&1; then
            log_success "VPN target ($VPN_PING_TARGET) is reachable"
        else
            log_warning "Cannot reach VPN target ($VPN_PING_TARGET)"
        fi
    fi
}

# === DEPLOY MONITORING SYSTEM ===
deploy_monitoring() {
    log_info "=== Deploy Monitoring System ==="
    
    if confirm_action "Deploy the Starlink monitoring and failover system?"; then
        local deploy_script="$(dirname "$0")/deploy-starlink-solution-rutos.sh"
        
        if [ -f "$deploy_script" ]; then
            log_step "Deploying monitoring system..."
            if safe_execute "$deploy_script" "Deploy monitoring system"; then
                log_success "Monitoring system deployed"
            else
                log_error "Failed to deploy monitoring system"
            fi
        else
            log_error "Deploy script not found: $deploy_script"
        fi
    fi
}

# === MAIN SCRIPT LOGIC ===
main() {
    local action="${1:-interactive}"
    
    case "$action" in
        "interactive"|"setup")
            log_info "Starting RUTX50 Factory Reset Recovery"
            log_info "This will guide you through restoring your custom configuration"
            echo ""
            
            if ! confirm_action "Continue with interactive setup?"; then
                log_info "Setup cancelled"
                exit 0
            fi
            
            # Run configuration steps
            configure_wireguard || exit 1
            configure_routing || exit 1
            configure_firewall || exit 1
            configure_mwan3 || exit 1
            
            log_info "Waiting 10 seconds for services to stabilize..."
            sleep 10
            
            verify_configuration
            deploy_monitoring
            
            log_success "Factory reset recovery completed!"
            log_info "Configuration files saved to: $CONFIG_BACKUP_DIR"
            ;;
        "verify")
            verify_configuration
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action]"
            echo ""
            echo "Actions:"
            echo "  interactive  - Interactive setup (default)"
            echo "  setup        - Same as interactive"
            echo "  verify       - Verify current configuration"
            echo "  help         - Show this help"
            echo ""
            echo "This script helps restore RUTX50 configuration after factory reset"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
