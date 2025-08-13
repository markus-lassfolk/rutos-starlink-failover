#!/bin/sh
# ==============================================================================
# Enhanced Multi-Interface Starlink Monitor for RUTOS v3.0.0
# Fixed version that properly uses MWAN_ALL_INTERFACES configuration
# ==============================================================================

set -e

# Version information
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="starlink_monitor_unified-rutos.sh"

# === CONFIGURATION LOADING ===
# Default paths for configuration
CONFIG_FILE="/usr/local/starlink/config/config.sh"
LOG_DIR="/usr/local/starlink/logs"
METRICS_DIR="$LOG_DIR/metrics"

# Create directories if they don't exist
mkdir -p "$METRICS_DIR" 2>/dev/null || true

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    echo "[INFO] Configuration loaded from: $CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === LOGGING FUNCTIONS ===
log_info() {
    echo "[INFO] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[DEBUG] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
    fi
}

# === CONNECTION-SPECIFIC SETTINGS VALIDATION ===
# Set defaults for any missing connection-specific configuration values
STARLINK_API_ENDPOINTS="${STARLINK_API_ENDPOINTS:-192.168.100.1:9200 192.168.1.1:9200}"
STARLINK_API_TIMEOUT="${STARLINK_API_TIMEOUT:-8}"
STARLINK_COLLECT_ADVANCED="${STARLINK_COLLECT_ADVANCED:-1}"
CELLULAR_COLLECT_LTE="${CELLULAR_COLLECT_LTE:-1}"
CELLULAR_COLLECT_THERMAL="${CELLULAR_COLLECT_THERMAL:-1}"
CELLULAR_COLLECT_OPERATOR="${CELLULAR_COLLECT_OPERATOR:-1}"
CELLULAR_SIGNAL_THRESHOLD="${CELLULAR_SIGNAL_THRESHOLD:-20}"
WIREGUARD_HANDSHAKE_TIMEOUT="${WIREGUARD_HANDSHAKE_TIMEOUT:-300}"
WIREGUARD_COLLECT_TRANSFER="${WIREGUARD_COLLECT_TRANSFER:-1}"
MONITOR_FREQ_UNLIMITED="${MONITOR_FREQ_UNLIMITED:-3}"
MONITOR_FREQ_LIMITED="${MONITOR_FREQ_LIMITED:-1}"
PING_TARGET_PRIMARY="${PING_TARGET_PRIMARY:-8.8.8.8}"
PING_TARGET_SECONDARY="${PING_TARGET_SECONDARY:-1.1.1.1}"
PING_TARGET_STARLINK="${PING_TARGET_STARLINK:-192.168.100.1}"

log_debug "Connection-specific monitoring settings loaded from centralized config"

# === INTERFACE MONITORING FUNCTIONS ===
get_interface_status() {
    local interface_name="$1"
    
    # Try to get MWAN3 status for this interface
    if command -v mwan3 >/dev/null 2>&1; then
        mwan3 interfaces 2>/dev/null | grep "^ interface $interface_name" | head -1 || echo "interface $interface_name status unknown"
    else
        echo "interface $interface_name status unknown"
    fi
}

get_interface_metrics() {
    local interface_name="$1"
    local connection_type="$2"
    
    # Initialize metrics with default values
    local latency=0
    local packet_loss=0
    local throughput=0
    local availability=0
    local signal_strength=0
    local snr=0
    local status="offline"
    local method="mwan3"
    local tx_bytes=0
    local rx_bytes=0
    local tx_packets=0
    local rx_packets=0
    local errors=0
    
    log_debug "Collecting metrics for interface: $interface_name"
    
    # 1. Get MWAN3 status for this interface (most accurate for RUTOS)
    if command -v mwan3 >/dev/null 2>&1; then
        mwan3_status=$(mwan3 status 2>/dev/null | grep "interface $interface_name is")
        if echo "$mwan3_status" | grep -q "is online"; then
            status="online"
            availability=100
            # Extract uptime from MWAN3 status
            if echo "$mwan3_status" | grep -q "uptime"; then
                uptime_info=$(echo "$mwan3_status" | grep -o '[0-9]*h:[0-9]*m:[0-9]*s.*uptime [0-9]*h:[0-9]*m:[0-9]*s')
                log_debug "MWAN3 uptime for $interface_name: $uptime_info"
            fi
        elif echo "$mwan3_status" | grep -q "is offline"; then
            status="offline"
            availability=0
        elif echo "$mwan3_status" | grep -q "is disabled"; then
            status="disabled"
            availability=0
            method="mwan3_disabled"
        else
            log_debug "MWAN3 status unknown for $interface_name: $mwan3_status"
        fi
    fi
    
    # 2. Get network interface statistics from /proc/net/dev
    if [ -r "/proc/net/dev" ]; then
        # Find the interface line and extract statistics
        dev_stats=$(grep "^\s*${interface_name}:" /proc/net/dev 2>/dev/null)
        if [ -n "$dev_stats" ]; then
            # Parse /proc/net/dev format: interface: rx_bytes rx_packets rx_errs ... tx_bytes tx_packets tx_errs ...
            # Remove interface name and colons, then extract fields
            stats_cleaned=$(echo "$dev_stats" | sed "s/^\s*${interface_name}:\s*//")
            
            # Extract specific fields (format: rx_bytes rx_packets rx_errs rx_drop rx_fifo rx_frame rx_compressed rx_multicast tx_bytes tx_packets ...)
            rx_bytes=$(echo "$stats_cleaned" | awk '{print $1}')
            rx_packets=$(echo "$stats_cleaned" | awk '{print $2}')
            rx_errors=$(echo "$stats_cleaned" | awk '{print $3}')
            tx_bytes=$(echo "$stats_cleaned" | awk '{print $9}')
            tx_packets=$(echo "$stats_cleaned" | awk '{print $10}')
            tx_errors=$(echo "$stats_cleaned" | awk '{print $11}')
            
            # Calculate total errors
            errors=$((${rx_errors:-0} + ${tx_errors:-0}))
            
            # Calculate simple throughput indicator (bytes per interface check)
            total_bytes=$((${rx_bytes:-0} + ${tx_bytes:-0}))
            if [ "$total_bytes" -gt 1000000 ]; then
                throughput=$((total_bytes / 1000000))  # Convert to MB
            else
                throughput=0
            fi
            
            log_debug "Interface $interface_name stats: RX=${rx_bytes}b/${rx_packets}p, TX=${tx_bytes}b/${tx_packets}p, ERR=${errors}"
            method="proc_dev"
        fi
    fi
    
    # 3. Test connectivity and get latency (if interface is reported as online)
    if [ "$status" = "online" ]; then
        # Determine monitoring frequency based on connection type (configurable)
        local ping_count="$MONITOR_FREQ_LIMITED"
        if [ "$connection_type" = "unlimited" ]; then
            ping_count="$MONITOR_FREQ_UNLIMITED"
        fi
        
        # Test connectivity via ping (with fallback target)
        ping_target="$PING_TARGET_PRIMARY"
        if ! ping -c "$ping_count" -W 3 "$ping_target" >/dev/null 2>&1; then
            log_debug "Primary ping target $ping_target failed, trying secondary"
            ping_target="$PING_TARGET_SECONDARY"
        fi
        
        if ping -c "$ping_count" -W 3 "$ping_target" >/dev/null 2>&1; then
            # Get latency measurement
            if ping_result=$(ping -c "$ping_count" -W 3 "$ping_target" 2>/dev/null | tail -1); then
                # Parse ping statistics line: "round-trip min/avg/max = 45.2/50.1/55.0 ms"
                if echo "$ping_result" | grep -q "round-trip"; then
                    latency=$(echo "$ping_result" | grep -o 'avg = [0-9.]*\|[0-9.]*/' | head -1 | tr -d '/' | cut -d'=' -f2 | cut -d'.' -f1 2>/dev/null)
                    latency=${latency:-0}
                    method="mwan3_ping"
                    log_debug "Connectivity verified via ping to $ping_target (${latency}ms)"
                fi
            fi
        else
            # Interface shows online in MWAN3 but ping fails to both targets
            log_debug "Interface $interface_name: MWAN3 online but ping failed to both $PING_TARGET_PRIMARY and $PING_TARGET_SECONDARY"
            availability=75  # Reduced availability
            status="limited"
        fi
    fi
    
    # 4. CONNECTION-SPECIFIC ENHANCED METRICS based on interface type
    
    # 4a. STARLINK ENHANCED METRICS (wan interface) - Comprehensive API Collection
    if [ "$interface_name" = "wan" ] && [ "$status" = "online" ] && command -v curl >/dev/null 2>&1; then
        log_debug "Collecting comprehensive Starlink API metrics for $interface_name"
        
        # Primary Starlink API endpoints to try (configurable)
        starlink_endpoints="$STARLINK_API_ENDPOINTS"
        starlink_data=""
        
        for endpoint in $starlink_endpoints; do
            log_debug "Trying Starlink API endpoint: $endpoint"
            if starlink_data=$(curl -m "$STARLINK_API_TIMEOUT" -s "http://$endpoint/JSONRpc" \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","id":1,"method":"get_status"}' 2>/dev/null); then
                
                if echo "$starlink_data" | grep -q "ping_latency_ms"; then
                    method="starlink_api"
                    log_debug "Starlink API connection successful via $endpoint"
                    break
                fi
            fi
            log_debug "Starlink API endpoint $endpoint failed, trying next..."
        done
        
        # Process comprehensive Starlink data if API responded
        if [ "$method" = "starlink_api" ]; then
            # Extract core connectivity metrics
            if starlink_latency=$(echo "$starlink_data" | grep -o '"ping_latency_ms":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1 2>/dev/null); then
                latency=$starlink_latency
                log_debug "Starlink API latency: ${latency}ms"
            fi
            
            # *** CRITICAL FAILOVER METRICS ***
            
            # Extract SNR for predictive failover logic
            if snr_val=$(echo "$starlink_data" | grep -o '"snr":[0-9.-]*' | cut -d':' -f2 | cut -d'.' -f1 2>/dev/null); then
                snr=$snr_val
                log_debug "Starlink SNR: ${snr} (critical for predictive failover)"
            fi
            
            # Extract seconds to next satellite (satellite handoff prediction)
            if seconds_to_next_sat=$(echo "$starlink_data" | grep -o '"seconds_to_first_nonempty_slot":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1 2>/dev/null); then
                log_debug "Starlink satellite handoff: ${seconds_to_next_sat}s to next satellite"
                # Store for failover decision logic
            fi
            
            # Extract packet loss rate for immediate failover triggers
            if packet_loss_rate=$(echo "$starlink_data" | grep -o '"pop_ping_drop_rate":[0-9.]*' | cut -d':' -f2 2>/dev/null); then
                # Convert to percentage (0.02 = 2%)
                packet_loss=$(echo "$packet_loss_rate * 100" | bc 2>/dev/null | cut -d'.' -f1)
                log_debug "Starlink packet loss: ${packet_loss_rate} (${packet_loss}%)"
            fi
            
            # Check obstruction status (critical for failover decisions)
            if echo "$starlink_data" | grep -q '"currently_obstructed":true'; then
                availability=60
                status="obstructed"
                log_debug "Starlink obstruction detected - FAILOVER TRIGGER"
            elif echo "$starlink_data" | grep -q '"fraction_obstructed":[0-9.]*'; then
                obstruction_pct=$(echo "$starlink_data" | grep -o '"fraction_obstructed":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1)
                if [ "$obstruction_pct" -gt 5 ]; then
                    availability=$((100 - obstruction_pct))
                    status="partial_obstruction"
                    log_debug "Starlink partial obstruction: ${obstruction_pct}% - potential failover trigger"
                fi
            fi
            
            # Extract signal strength for quality assessment
            if rssi_val=$(echo "$starlink_data" | grep -o '"rssi":[0-9.-]*' | cut -d':' -f2 | cut -d'.' -f1 2>/dev/null); then
                signal_strength=$rssi_val
            fi
            
            # Check for dish heating/snow melt mode (if advanced collection enabled)
            if [ "${STARLINK_COLLECT_ADVANCED:-1}" = "1" ] && echo "$starlink_data" | grep -q '"dish_heating":true'; then
                log_debug "Starlink dish heating active (snow/ice mode) - may affect performance"
                status="heating_${status}"
            fi
            
            # Extract POP latency (more accurate than ping latency)
            if pop_ping_latency=$(echo "$starlink_data" | grep -o '"pop_ping_latency_ms":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1); then
                log_debug "Starlink POP latency: ${pop_ping_latency}ms (primary failover metric)"
                # Use POP latency if available (more accurate for failover decisions)
                latency=$pop_ping_latency
            fi
            
            # Extract throughput metrics if available
            if downlink_throughput=$(echo "$starlink_data" | grep -o '"downlink_throughput_bps":[0-9]*' | cut -d':' -f2); then
                throughput=$((downlink_throughput / 1000000))  # Convert to Mbps
                log_debug "Starlink downlink: ${throughput}Mbps"
            fi
            
            if uplink_throughput=$(echo "$starlink_data" | grep -o '"uplink_throughput_bps":[0-9]*' | cut -d':' -f2); then
                uplink_mbps=$((uplink_throughput / 1000000))
                log_debug "Starlink uplink: ${uplink_mbps}Mbps"
            fi
            
            # *** HISTORICAL DATA COLLECTION FOR FAILBACK DECISIONS ***
            if [ "${STARLINK_COLLECT_HISTORY:-1}" = "1" ]; then
                log_debug "Collecting Starlink historical data for trend analysis"
                # Note: This would require a separate API call to get_history
                # Implementation would store historical SNR, latency, packet loss trends
            fi
            
            log_debug "Starlink FAILOVER metrics: SNR=${snr}, latency=${latency}ms, packet_loss=${packet_loss}%, handoff=${seconds_to_next_sat}s"
        else
            log_debug "Starlink API not available - using basic connectivity test"
            # Fallback to Starlink router ping test (configurable target)
            if ping -c 2 -W 3 "$PING_TARGET_STARLINK" >/dev/null 2>&1; then
                method="starlink_ping"
                log_debug "Starlink router reachable via ping to $PING_TARGET_STARLINK"
            fi
        fi
    fi
    
    # 4b. CELLULAR ENHANCED METRICS (mob* interfaces) - Comprehensive GSM/LTE Collection
    if echo "$interface_name" | grep -q "^mob" && command -v gsmctl >/dev/null 2>&1; then
        log_debug "Collecting comprehensive cellular metrics for $interface_name"
        
        # Core signal strength via AT+CSQ
        if csq_result=$(gsmctl -A AT+CSQ 2>/dev/null | grep "+CSQ:"); then
            # Parse +CSQ: rssi,ber format
            rssi=$(echo "$csq_result" | cut -d' ' -f2 | cut -d',' -f1)
            ber=$(echo "$csq_result" | cut -d' ' -f2 | cut -d',' -f2)
            
            # Convert RSSI to signal strength percentage
            if [ "$rssi" -ne 99 ] && [ "$rssi" -ge 0 ] && [ "$rssi" -le 31 ]; then
                signal_strength=$((rssi * 100 / 31))
                method="cellular_gsm"
                log_debug "Cellular RSSI: $rssi (-${rssi}dBm), Signal: $signal_strength%, BER: $ber"
            else
                signal_strength=0
                log_debug "Cellular signal unavailable (RSSI: $rssi)"
            fi
        fi
        
        # Get comprehensive cellular network information (if enabled)
        if [ "$CELLULAR_COLLECT_OPERATOR" = "1" ]; then
            if operator_info=$(gsmctl -A AT+COPS? 2>/dev/null | grep "+COPS:"); then
                # Parse operator info: +COPS: mode,format,"operator",rat
                cellular_operator=$(echo "$operator_info" | cut -d'"' -f2 2>/dev/null)
                log_debug "Cellular operator: $cellular_operator"
            fi
        fi
        
        # Get network registration status
        if reg_status=$(gsmctl -A AT+CREG? 2>/dev/null | grep "+CREG:"); then
            # Parse +CREG: n,stat[,lac,ci[,rat]] 
            reg_stat=$(echo "$reg_status" | cut -d',' -f2)
            case "$reg_stat" in
                "1") availability=100; status="registered_home" ;;
                "2") availability=50; status="searching" ;;  
                "3") availability=0; status="denied" ;;
                "5") availability=90; status="registered_roaming" ;;
                *) availability=25; status="unknown_reg" ;;
            esac
            log_debug "Cellular registration: status=$reg_stat ($status)"
        fi
        
        # Get LTE-specific signal quality (if LTE collection enabled)
        if [ "$CELLULAR_COLLECT_LTE" = "1" ]; then
            if lte_info=$(gsmctl -A AT+CESQ 2>/dev/null | grep "+CESQ:"); then
                # Parse +CESQ: rxlev,ber,rscp,ecno,rsrq,rsrp
                rsrq=$(echo "$lte_info" | cut -d',' -f5)
                rsrp=$(echo "$lte_info" | cut -d',' -f6)
                
                # RSRP (Reference Signal Received Power) - better LTE metric
                if [ "$rsrp" != "255" ] && [ "$rsrp" -ne 255 ] 2>/dev/null; then
                    # RSRP range: 0-97 maps to -140dBm to -44dBm
                    rsrp_dbm=$((rsrp - 140))
                    if [ "$rsrp_dbm" -gt -100 ]; then
                        signal_strength=90
                    elif [ "$rsrp_dbm" -gt -110 ]; then
                        signal_strength=70
                    elif [ "$rsrp_dbm" -gt -120 ]; then
                        signal_strength=40
                    else
                        signal_strength=20
                    fi
                    method="cellular_lte"
                    log_debug "LTE RSRP: ${rsrp_dbm}dBm, RSRQ: $rsrq, Signal: $signal_strength%"
                fi
            fi
        fi
        
        # Get modem temperature (thermal management) - if thermal monitoring enabled
        if [ "$CELLULAR_COLLECT_THERMAL" = "1" ]; then
            if temp_info=$(gsmctl -A AT+MTSM=1 2>/dev/null | grep "+MTSM:"); then
                modem_temp=$(echo "$temp_info" | cut -d':' -f2 | cut -d',' -f1)
                log_debug "Cellular modem temperature: ${modem_temp}°C"
                
                # Adjust availability based on temperature
                if [ "$modem_temp" -gt 70 ]; then
                    availability=$((availability - 20))
                    status="thermal_${status}"
                    log_debug "Cellular thermal throttling detected"
                fi
            fi
        fi
        
        # Get data session information  
        if session_info=$(gsmctl -A AT+CGACT? 2>/dev/null | grep "+CGACT:"); then
            # Check if PDP context is active
            if echo "$session_info" | grep -q ",1"; then
                log_debug "Cellular data session active"
            else
                availability=$((availability / 2))
                status="no_data_${status}"
                log_debug "Cellular data session inactive"
            fi
        fi
        
        # Get current technology (2G/3G/4G/5G) 
        if tech_info=$(gsmctl -A AT+COPS? 2>/dev/null | grep "+COPS:"); then
            # Extract technology from operator response
            rat=$(echo "$tech_info" | cut -d',' -f4 2>/dev/null)
            case "$rat" in
                "0"|"1"|"3") cellular_tech="GSM/EDGE" ;;
                "2") cellular_tech="3G" ;;
                "7") cellular_tech="LTE" ;;
                "12") cellular_tech="5G" ;;
                *) cellular_tech="unknown" ;;
            esac
            log_debug "Cellular technology: $cellular_tech"
        fi
        
        # Calculate packet loss estimation based on signal quality threshold
        if [ "$signal_strength" -lt "$CELLULAR_SIGNAL_THRESHOLD" ]; then
            packet_loss=$((100 - signal_strength))
        else
            packet_loss=0
        fi
        
        log_debug "Cellular comprehensive metrics: signal=$signal_strength%, status=$status, tech=$cellular_tech, operator=$cellular_operator"
    fi
    
    # 4c. WIREGUARD ENHANCED METRICS (wg_* interfaces)
    if echo "$interface_name" | grep -q "^wg_" && command -v wg >/dev/null 2>&1; then
        log_debug "Collecting WireGuard metrics for $interface_name"
        
        if wg_data=$(wg show "$interface_name" 2>/dev/null); then
            method="wireguard"
            
            # Check for recent handshake (indicates active connection)
            if echo "$wg_data" | grep -q "latest handshake:"; then
                handshake_info=$(echo "$wg_data" | grep "latest handshake:" | head -1)
                
                # Extract handshake timing (using configurable timeout)
                if echo "$handshake_info" | grep -q "seconds ago"; then
                    seconds_ago=$(echo "$handshake_info" | grep -o '[0-9]* seconds ago' | cut -d' ' -f1)
                    if [ "$seconds_ago" -lt "$WIREGUARD_HANDSHAKE_TIMEOUT" ]; then
                        availability=100
                        status="connected"
                    else
                        availability=50
                        status="stale"
                    fi
                elif echo "$handshake_info" | grep -q "minutes ago"; then
                    minutes_ago=$(echo "$handshake_info" | grep -o '[0-9]* minutes ago' | cut -d' ' -f1)
                    if [ "$minutes_ago" -lt 10 ]; then
                        availability=75
                        status="connected"
                    else
                        availability=25
                        status="stale"
                    fi
                fi
                
                log_debug "WireGuard handshake: $handshake_info"
            fi
            
            # Extract transfer statistics for throughput indication (if enabled)
            if [ "$WIREGUARD_COLLECT_TRANSFER" = "1" ]; then
                if transfer_line=$(echo "$wg_data" | grep "transfer:" | head -1); then
                    # Parse "transfer: X.XX MiB received, Y.YY MiB sent"
                    received=$(echo "$transfer_line" | grep -o '[0-9.]*.*received' | cut -d' ' -f1)
                    sent=$(echo "$transfer_line" | grep -o '[0-9.]*.*sent' | cut -d' ' -f1)
                    log_debug "WireGuard transfer: received=$received, sent=$sent"
                fi
            fi
        fi
    fi
    
    # 4d. WIRELESS ENHANCED METRICS (wlan* interfaces) 
    if echo "$interface_name" | grep -q "^wlan" && command -v iw >/dev/null 2>&1; then
        log_debug "Collecting wireless metrics for $interface_name"
        
        if iw_data=$(iw dev "$interface_name" link 2>/dev/null); then
            method="wireless"
            
            # Extract wireless signal strength
            if signal_line=$(echo "$iw_data" | grep "signal:"); then
                signal_dbm=$(echo "$signal_line" | grep -o '\-[0-9]*' | head -1)
                # Convert dBm to percentage (rough approximation)
                if [ -n "$signal_dbm" ]; then
                    signal_strength=$(( (signal_dbm + 100) * 2 ))
                    log_debug "Wireless signal: ${signal_dbm}dBm (${signal_strength}%)"
                fi
            fi
        fi
    fi
    
    # Output CSV format with enhanced connection-specific data
    # Format: timestamp,interface,status,latency,packet_loss,throughput,availability,signal_strength,snr,tx_packets,rx_packets,error_count,location,method,connection_type
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$interface_name,$status,$latency,$packet_loss,$throughput,$availability,$signal_strength,$snr,$tx_packets,$rx_packets,$errors,rutos,$method,$connection_type"
}

# === MULTI-INTERFACE MONITORING ===
monitor_all_interfaces() {
    local metrics_file="$METRICS_DIR/metrics_$(date +%Y%m%d).csv"
    
    log_info "Starting multi-interface monitoring..."
    log_info "Configuration: MWAN_ALL_INTERFACES='${MWAN_ALL_INTERFACES:-}'"
    log_info "Interface types: MWAN_INTERFACE_TYPES='${MWAN_INTERFACE_TYPES:-}'"
    
    # Check if we have the new multi-interface configuration
    if [ -n "${MWAN_ALL_INTERFACES:-}" ]; then
        log_info "Using multi-interface configuration with ${MWAN_INTERFACE_COUNT:-0} interfaces"
        
        # Parse interfaces from comma-separated list
        interface_list=$(echo "${MWAN_ALL_INTERFACES}" | tr ',' ' ')
        type_list="${MWAN_INTERFACE_TYPES:-}"
        
        for interface in $interface_list; do
            log_debug "Processing interface: $interface"
            
            # Get connection type for this interface
            connection_type="unlimited"  # Default
            if [ -n "$type_list" ]; then
                # Extract connection type from format "interface:type,interface:type"
                for type_pair in $(echo "$type_list" | tr ',' ' '); do
                    if echo "$type_pair" | grep -q "^${interface}:"; then
                        connection_type=$(echo "$type_pair" | cut -d':' -f2)
                        break
                    fi
                done
            fi
            
            log_debug "Interface $interface: connection_type=$connection_type"
            
            # Get metrics for this interface
            metrics=$(get_interface_metrics "$interface" "$connection_type")
            
            # Write to metrics file
            echo "$metrics" >> "$metrics_file"
            
            # Log the result
            log_info "Collected metrics for $interface ($connection_type): $(echo "$metrics" | cut -d',' -f3-7)"
        done
        
        log_info "Multi-interface monitoring cycle completed"
        
    else
        # Fall back to legacy single interface mode
        log_info "Using legacy single-interface configuration"
        
        interface="${MWAN_IFACE:-wan}"
        connection_type="unlimited"
        
        metrics=$(get_interface_metrics "$interface" "$connection_type")
        echo "$metrics" >> "$metrics_file"
        
        log_info "Legacy monitoring for $interface completed"
    fi
}

# === DAEMON MODE ===
run_daemon() {
    log_info "Starting monitoring daemon (PID: $$)"
    
    # Create PID file
    echo $$ > "$LOG_DIR/starlink_monitor.pid"
    
    # Monitoring loop
    while true; do
        monitor_all_interfaces
        
        # Wait before next cycle - vary based on interface types
        if [ -n "${MWAN_ALL_INTERFACES:-}" ]; then
            # Multi-interface mode: use shortest interval
            sleep 60
        else
            # Legacy mode: standard interval
            sleep "${MONITORING_INTERVAL:-60}"
        fi
    done
}

# === MAIN SCRIPT LOGIC ===
main() {
    case "${1:-daemon}" in
        "test")
            log_info "=== TEST MODE ==="
            log_info "Configuration verification:"
            log_info "  MWAN_ALL_INTERFACES='${MWAN_ALL_INTERFACES:-UNSET}'"
            log_info "  MWAN_INTERFACE_TYPES='${MWAN_INTERFACE_TYPES:-UNSET}'"
            log_info "  MWAN_INTERFACE_COUNT='${MWAN_INTERFACE_COUNT:-UNSET}'"
            log_info "  Legacy MWAN_IFACE='${MWAN_IFACE:-UNSET}'"
            
            log_info "Running single monitoring cycle..."
            monitor_all_interfaces
            log_info "Test completed - check $METRICS_DIR for output"
            ;;
        "daemon")
            run_daemon
            ;;
        "status")
            if [ -f "$LOG_DIR/starlink_monitor.pid" ]; then
                pid=$(cat "$LOG_DIR/starlink_monitor.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Monitoring daemon is running (PID: $pid)"
                    exit 0
                else
                    echo "Monitoring daemon is not running (stale PID file)"
                    exit 1
                fi
            else
                echo "Monitoring daemon is not running (no PID file)"
                exit 1
            fi
            ;;
        "stop")
            if [ -f "$LOG_DIR/starlink_monitor.pid" ]; then
                pid=$(cat "$LOG_DIR/starlink_monitor.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    rm -f "$LOG_DIR/starlink_monitor.pid"
                    log_info "Monitoring daemon stopped"
                else
                    rm -f "$LOG_DIR/starlink_monitor.pid"
                    log_info "Monitoring daemon was not running (removed stale PID file)"
                fi
            else
                log_info "Monitoring daemon is not running"
            fi
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [daemon|test|status|stop|help]"
            echo "  daemon  - Run in daemon mode (default)"
            echo "  test    - Run single monitoring cycle and exit"  
            echo "  status  - Check if daemon is running"
            echo "  stop    - Stop the daemon"
            echo "  help    - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
