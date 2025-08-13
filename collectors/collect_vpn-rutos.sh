#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "collect_vpn-rutos.sh" "$SCRIPT_VERSION"

# === VPN METRICS COLLECTOR ===
# Collects VPN-specific metrics (WireGuard focus) and common metrics via fping
# Outputs single-line JSON for the stability scoring system

readonly SCRIPT_NAME="collect_vpn-rutos.sh"

# Load common functions
. "$(dirname "$0")/../lib/common_functions.sh"

# === CONFIGURATION ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === VPN CONFIGURATION ===
VPN_INTERFACE="${1:-wg_klara}"  # Allow interface override via argument
PING_TARGET="${PING_TARGET:-8.8.8.8}"
PING_COUNT="${PING_COUNT:-2}"
HANDSHAKE_TIMEOUT="${WIREGUARD_HANDSHAKE_TIMEOUT:-300}"  # 5 minutes

# === WIREGUARD STATUS FUNCTIONS ===
get_wireguard_status() {
    local interface="$1"
    
    log_debug "Getting WireGuard status for $interface"
    
    if command_exists wg; then
        safe_command "WireGuard status for $interface" "wg show $interface"
    else
        log_error "wg command not available"
        return 1
    fi
}

# === METRIC EXTRACTION FUNCTIONS ===
extract_vpn_metrics() {
    log_debug "Extracting VPN-specific metrics for $VPN_INTERFACE"
    
    # Get WireGuard status
    local wg_status
    if ! wg_status=$(get_wireguard_status "$VPN_INTERFACE"); then
        log_error "Failed to get WireGuard status for $VPN_INTERFACE"
        return 1
    fi
    
    log_trace "WireGuard status: $wg_status"
    
    # Extract metrics from WireGuard status
    # Format varies, but typically includes:
    # interface: wg_klara
    #   public key: ...
    #   private key: (hidden)
    #   listening port: 51820
    #   
    # peer: <peer_public_key>
    #   endpoint: <ip>:<port>
    #   allowed ips: 0.0.0.0/0
    #   latest handshake: 2 minutes, 30 seconds ago
    #   transfer: 1.5 GiB received, 256 MiB sent
    
    # Extract tunnel status (interface exists and has peers)
    local tunnel_status="DOWN"
    if echo "$wg_status" | grep -q "peer:"; then
        tunnel_status="UP"
    fi
    
    # Extract latest handshake time
    local handshake_line=$(echo "$wg_status" | grep "latest handshake:" | head -1)
    local handshake_seconds="999999"  # Default to very old
    
    if [ -n "$handshake_line" ]; then
        # Parse handshake time (various formats possible)
        if echo "$handshake_line" | grep -q "seconds ago"; then
            handshake_seconds=$(echo "$handshake_line" | grep -o '[0-9]* seconds ago' | cut -d' ' -f1)
        elif echo "$handshake_line" | grep -q "minute"; then
            local minutes=$(echo "$handshake_line" | grep -o '[0-9]* minute' | cut -d' ' -f1)
            local seconds=$(echo "$handshake_line" | grep -o '[0-9]* second' | cut -d' ' -f1 || echo "0")
            handshake_seconds=$(awk "BEGIN {printf \"%.0f\", ($minutes * 60) + $seconds}")
        elif echo "$handshake_line" | grep -q "hour"; then
            local hours=$(echo "$handshake_line" | grep -o '[0-9]* hour' | cut -d' ' -f1)
            handshake_seconds=$(awk "BEGIN {printf \"%.0f\", $hours * 3600}")
        fi
    fi
    
    # Extract transfer statistics
    local transfer_line=$(echo "$wg_status" | grep "transfer:" | head -1)
    local rx_bytes="0"
    local tx_bytes="0"
    
    if [ -n "$transfer_line" ]; then
        # Parse transfer data (e.g., "transfer: 1.5 GiB received, 256 MiB sent")
        local rx_part=$(echo "$transfer_line" | sed 's/.*transfer: \([^,]*\) received.*/\1/')
        local tx_part=$(echo "$transfer_line" | sed 's/.*, \([^,]*\) sent.*/\1/')
        
        # Convert to bytes (simple approximation)
        if echo "$rx_part" | grep -q "GiB"; then
            local rx_gib=$(echo "$rx_part" | grep -o '[0-9.]*')
            rx_bytes=$(awk "BEGIN {printf \"%.0f\", $rx_gib * 1073741824}")
        elif echo "$rx_part" | grep -q "MiB"; then
            local rx_mib=$(echo "$rx_part" | grep -o '[0-9.]*')
            rx_bytes=$(awk "BEGIN {printf \"%.0f\", $rx_mib * 1048576}")
        elif echo "$rx_part" | grep -q "KiB"; then
            local rx_kib=$(echo "$rx_part" | grep -o '[0-9.]*')
            rx_bytes=$(awk "BEGIN {printf \"%.0f\", $rx_kib * 1024}")
        fi
        
        if echo "$tx_part" | grep -q "GiB"; then
            local tx_gib=$(echo "$tx_part" | grep -o '[0-9.]*')
            tx_bytes=$(awk "BEGIN {printf \"%.0f\", $tx_gib * 1073741824}")
        elif echo "$tx_part" | grep -q "MiB"; then
            local tx_mib=$(echo "$tx_part" | grep -o '[0-9.]*')
            tx_bytes=$(awk "BEGIN {printf \"%.0f\", $tx_mib * 1048576}")
        elif echo "$tx_part" | grep -q "KiB"; then
            local tx_kib=$(echo "$tx_part" | grep -o '[0-9.]*')
            tx_bytes=$(awk "BEGIN {printf \"%.0f\", $tx_kib * 1024}")
        fi
    fi
    
    # Extract endpoint information
    local endpoint=$(echo "$wg_status" | grep "endpoint:" | head -1 | sed 's/.*endpoint: //' | sed 's/ .*//')
    
    # Calculate handshake health (0-100 based on recency)
    local handshake_health="0"
    if [ "$handshake_seconds" != "999999" ]; then
        if [ "$handshake_seconds" -le 60 ]; then
            handshake_health="100"  # Fresh handshake
        elif [ "$handshake_seconds" -le "$HANDSHAKE_TIMEOUT" ]; then
            # Linear decay from 100 to 20 over timeout period
            handshake_health=$(awk "BEGIN {
                age = $handshake_seconds
                timeout = $HANDSHAKE_TIMEOUT
                health = 100 - ((age / timeout) * 80)
                if (health < 20) health = 20
                printf \"%.0f\", health
            }")
        else
            handshake_health="20"  # Stale handshake but tunnel might still work
        fi
    fi
    
    # Validate and set defaults
    tunnel_status="${tunnel_status:-DOWN}"
    handshake_seconds="${handshake_seconds:-999999}"
    handshake_health="${handshake_health:-0}"
    rx_bytes="${rx_bytes:-0}"
    tx_bytes="${tx_bytes:-0}"
    endpoint="${endpoint:-Unknown}"
    
    log_debug "VPN metrics: Status=$tunnel_status, Handshake=${handshake_seconds}s ago (health: $handshake_health), RX/TX: $rx_bytes/$tx_bytes bytes"
    
    # Export metrics as variables for JSON creation
    export VPN_TUNNEL_STATUS="$tunnel_status"
    export VPN_HANDSHAKE_SECONDS="$handshake_seconds"
    export VPN_HANDSHAKE_HEALTH="$handshake_health"
    export VPN_RX_BYTES="$rx_bytes"
    export VPN_TX_BYTES="$tx_bytes"
    export VPN_ENDPOINT="$endpoint"
    
    return 0
}

# === COMMON METRICS (PING) ===
collect_ping_metrics() {
    log_debug "Collecting ping metrics for $VPN_INTERFACE"
    
    # Use interface-specific ping if possible
    local ping_cmd="fping -I $VPN_INTERFACE -c $PING_COUNT -q $PING_TARGET 2>&1"
    
    # Try interface-specific ping first
    local ping_result
    if ! ping_result=$(safe_command "fping via $VPN_INTERFACE" "$ping_cmd"); then
        log_debug "Interface-specific fping failed, trying general ping"
        
        # Fallback to general ping
        if ! ping_result=$(safe_command "fping to $PING_TARGET" \
            "fping -c $PING_COUNT -q $PING_TARGET 2>&1"); then
            log_warning "fping failed for $VPN_INTERFACE, using fallback ping"
            
            # Final fallback to regular ping
            if ! ping_result=$(safe_command "ping to $PING_TARGET" \
                "ping -c $PING_COUNT -W 10 $PING_TARGET 2>/dev/null"); then
                log_error "All ping methods failed for $VPN_INTERFACE"
                export PING_LATENCY="0"
                export PING_LOSS="100"
                export PING_JITTER="0"
                return 1
            fi
        fi
    fi
    
    # Parse ping output (support both fping and ping formats)
    local latency="0"
    local loss="100"
    local jitter="0"
    
    if echo "$ping_result" | grep -q "min/avg/max"; then
        # fping format
        latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f2)
        loss=$(echo "$ping_result" | grep -o '[0-9]*%' | sed 's/%//' | head -1)
        local min_latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f1)
        local max_latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f3)
        
        # Calculate jitter
        if [ -n "$min_latency" ] && [ -n "$max_latency" ]; then
            jitter=$(awk "BEGIN {printf \"%.2f\", $max_latency - $min_latency}")
        fi
    elif echo "$ping_result" | grep -q "packet loss"; then
        # Standard ping format
        latency=$(echo "$ping_result" | grep "rtt min/avg/max/mdev" | cut -d'=' -f2 | cut -d'/' -f2)
        loss=$(echo "$ping_result" | grep "packet loss" | grep -o '[0-9]*%' | sed 's/%//')
        jitter=$(echo "$ping_result" | grep "rtt min/avg/max/mdev" | cut -d'=' -f2 | cut -d'/' -f4)
    fi
    
    # Validate and set defaults
    validate_metric "latency" "$latency" || latency="0"
    validate_metric "ping_loss" "$loss" || loss="100"
    validate_metric "jitter" "$jitter" || jitter="0"
    
    # Set defaults for missing values
    latency="${latency:-0}"
    loss="${loss:-100}"
    jitter="${jitter:-0}"
    
    log_debug "Ping metrics: Latency=${latency}ms, Loss=${loss}%, Jitter=${jitter}ms"
    
    # Export for JSON creation
    export PING_LATENCY="$latency"
    export PING_LOSS="$loss"
    export PING_JITTER="$jitter"
    
    return 0
}

# === JSON OUTPUT GENERATION ===
generate_json_output() {
    local timestamp=$(get_unix_timestamp)
    local interface="$VPN_INTERFACE"
    
    log_debug "Generating JSON output for $interface"
    
    # Create metrics object
    local metrics_json=$(json_object \
        "$(json_field "ping_latency_ms" "${PING_LATENCY:-0}" 1)" \
        "$(json_field "ping_loss_percent" "${PING_LOSS:-100}" 1)" \
        "$(json_field "jitter_ms" "${PING_JITTER:-0}" 1)" \
        "$(json_field "tunnel_status" "${VPN_TUNNEL_STATUS:-DOWN}")" \
        "$(json_field "handshake_seconds_ago" "${VPN_HANDSHAKE_SECONDS:-999999}" 1)" \
        "$(json_field "handshake_health" "${VPN_HANDSHAKE_HEALTH:-0}" 1)" \
        "$(json_field "rx_bytes" "${VPN_RX_BYTES:-0}" 1)" \
        "$(json_field "tx_bytes" "${VPN_TX_BYTES:-0}" 1)" \
        "$(json_field "endpoint" "${VPN_ENDPOINT:-Unknown}")" \
    )
    
    # Create main JSON object
    local json_output=$(json_object \
        "$(json_field "iface" "$interface")" \
        "$(json_field "timestamp" "$timestamp" 1)" \
        "$(json_field "type" "vpn")" \
        "\"metrics\": $metrics_json" \
    )
    
    echo "$json_output"
}

# === MAIN COLLECTOR LOGIC ===
main() {
    log_info "Starting VPN metrics collection for interface: $VPN_INTERFACE"
    
    # Check if interface exists
    if ! check_interface_exists "$VPN_INTERFACE"; then
        log_error "VPN interface $VPN_INTERFACE does not exist or is down"
        exit 1
    fi
    
    # Initialize metric variables
    export PING_LATENCY="0"
    export PING_LOSS="100"
    export PING_JITTER="0"
    export VPN_TUNNEL_STATUS="DOWN"
    export VPN_HANDSHAKE_SECONDS="999999"
    export VPN_HANDSHAKE_HEALTH="0"
    export VPN_RX_BYTES="0"
    export VPN_TX_BYTES="0"
    export VPN_ENDPOINT="Unknown"
    
    # Collect metrics (continue even if one fails)
    local ping_success=0
    local vpn_success=0
    
    if collect_ping_metrics; then
        ping_success=1
        log_debug "Ping metrics collection successful"
    else
        log_warning "Ping metrics collection failed"
    fi
    
    if extract_vpn_metrics; then
        vpn_success=1
        log_debug "VPN-specific metrics collection successful"
    else
        log_warning "VPN-specific metrics collection failed"
    fi
    
    # Generate output even if some metrics failed
    if [ "$ping_success" = "1" ] || [ "$vpn_success" = "1" ]; then
        generate_json_output
        log_info "VPN metrics collection completed successfully"
        exit 0
    else
        log_error "All metric collection failed for VPN interface"
        exit 1
    fi
}

# Run main function with interface argument support
main "$@"
