#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "collect_cellular-rutos.sh" "$SCRIPT_VERSION"

# === CELLULAR METRICS COLLECTOR ===
# Collects cellular-specific metrics via gsmctl and common metrics via fping
# Outputs single-line JSON for the stability scoring system

readonly SCRIPT_NAME="collect_cellular-rutos.sh"

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

# === CELLULAR CONFIGURATION ===
CELLULAR_INTERFACE="${1:-mob1s1a1}"  # Allow interface override via argument
PING_TARGET="${PING_TARGET:-8.8.8.8}"
PING_COUNT="${PING_COUNT:-2}"        # Fewer pings for metered connections
GSM_TIMEOUT="${CELLULAR_AT_TIMEOUT:-5}"

# === CELLULAR AT COMMAND FUNCTIONS ===
execute_at_commands() {
    log_debug "Executing cellular AT commands via gsmctl"
    
    # Combined AT command for efficiency (fewer modem interactions)
    local at_command="AT+QCSQ;+COPS?;+QENG=\"servingcell\";+CSQ"
    
    if command_exists gsmctl; then
        safe_command "Cellular AT commands" \
            "timeout $GSM_TIMEOUT gsmctl -A '$at_command'"
    else
        log_error "gsmctl command not available"
        return 1
    fi
}

# === METRIC EXTRACTION FUNCTIONS ===
extract_cellular_metrics() {
    log_debug "Extracting cellular-specific metrics"
    
    # Get AT command response
    local at_response
    if ! at_response=$(execute_at_commands); then
        log_error "Failed to get cellular AT command response"
        return 1
    fi
    
    log_trace "AT command response: $at_response"
    
    # Extract RSRP, RSRQ, SINR from +QCSQ response
    # Format: +QCSQ: "LTE",<rssi>,<rsrp>,<sinr>,<rsrq>
    local qcsq_line=$(echo "$at_response" | grep '+QCSQ:' | head -1)
    local rsrp=$(echo "$qcsq_line" | sed 's/.*,\([^,]*\),\([^,]*\),\([^,]*\)$/\2/' 2>/dev/null)
    local rsrq=$(echo "$qcsq_line" | sed 's/.*,\([^,]*\),\([^,]*\),\([^,]*\)$/\3/' 2>/dev/null)
    local sinr=$(echo "$qcsq_line" | sed 's/.*,\([^,]*\),\([^,]*\),\([^,]*\),\([^,]*\)$/\3/' 2>/dev/null)
    
    # Extract operator from +COPS response  
    # Format: +COPS: 0,0,"Operator Name",7
    local cops_line=$(echo "$at_response" | grep '+COPS:' | head -1)
    local operator=$(echo "$cops_line" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null)
    
    # Extract cell information from +QENG response
    # Format: +QENG: "servingcell","NOCONN","LTE","FDD",<mcc>,<mnc>,<cellid>,<pcid>,...
    local qeng_line=$(echo "$at_response" | grep '+QENG:' | head -1) 
    local cell_id=$(echo "$qeng_line" | cut -d',' -f7 2>/dev/null)
    local technology=$(echo "$qeng_line" | cut -d',' -f3 | sed 's/"//g' 2>/dev/null)
    
    # Extract basic signal strength from +CSQ
    # Format: +CSQ: <rssi>,<ber>
    local csq_line=$(echo "$at_response" | grep '+CSQ:' | head -1)
    local rssi_raw=$(echo "$csq_line" | cut -d',' -f1 | sed 's/.*: //' 2>/dev/null)
    
    # Convert RSSI from CSQ scale (0-31) to dBm
    local rssi="0"
    if [ -n "$rssi_raw" ] && [ "$rssi_raw" != "99" ] && [ "$rssi_raw" != "0" ]; then
        rssi=$(awk "BEGIN {printf \"%.0f\", -113 + ($rssi_raw * 2)}")
    fi
    
    # Validate extracted metrics and apply defaults
    validate_metric "rsrp" "$rsrp" || rsrp="-120"
    validate_metric "rsrq" "$rsrq" || rsrq="-20"  
    validate_metric "sinr" "$sinr" || sinr="0"
    validate_metric "rssi" "$rssi" || rssi="-100"
    
    # Clean up string values
    operator=$(echo "$operator" | sed 's/[^a-zA-Z0-9 -]//g' | head -c 20)
    technology=$(echo "$technology" | sed 's/[^a-zA-Z0-9]//g')
    cell_id=$(echo "$cell_id" | sed 's/[^0-9A-Fa-f]//g')
    
    # Set defaults for missing values
    rsrp="${rsrp:--120}"
    rsrq="${rsrq:--20}"
    sinr="${sinr:-0}"
    rssi="${rssi:--100}"
    operator="${operator:-Unknown}"
    technology="${technology:-Unknown}"
    cell_id="${cell_id:-0}"
    
    log_debug "Cellular metrics: RSRP=${rsrp}dBm, RSRQ=${rsrq}dBm, SINR=${sinr}dB, Operator=$operator"
    
    # Export metrics as variables for JSON creation
    export CELLULAR_RSRP="$rsrp"
    export CELLULAR_RSRQ="$rsrq"
    export CELLULAR_SINR="$sinr"
    export CELLULAR_RSSI="$rssi"
    export CELLULAR_OPERATOR="$operator"
    export CELLULAR_TECHNOLOGY="$technology"
    export CELLULAR_CELL_ID="$cell_id"
    
    return 0
}

# === COMMON METRICS (PING) ===
collect_ping_metrics() {
    log_debug "Collecting ping metrics for $CELLULAR_INTERFACE"
    
    # Use interface-specific ping if possible
    local ping_cmd="fping -I $CELLULAR_INTERFACE -c $PING_COUNT -q $PING_TARGET 2>&1"
    
    # Try interface-specific ping first
    local ping_result
    if ! ping_result=$(safe_command "fping via $CELLULAR_INTERFACE" "$ping_cmd"); then
        log_debug "Interface-specific fping failed, trying general ping"
        
        # Fallback to general ping
        if ! ping_result=$(safe_command "fping to $PING_TARGET" \
            "fping -c $PING_COUNT -q $PING_TARGET 2>&1"); then
            log_warning "fping failed for $CELLULAR_INTERFACE, using fallback ping"
            
            # Final fallback to regular ping
            if ! ping_result=$(safe_command "ping to $PING_TARGET" \
                "ping -c $PING_COUNT -W 10 $PING_TARGET 2>/dev/null"); then
                log_error "All ping methods failed for $CELLULAR_INTERFACE"
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
        # fping format: "8.8.8.8 : xmt/rcv/%loss = 2/2/0%, min/avg/max = 45.1/67.2/89.3"
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
    local interface="$CELLULAR_INTERFACE"
    
    log_debug "Generating JSON output for $interface"
    
    # Create metrics object
    local metrics_json=$(json_object \
        "$(json_field "ping_latency_ms" "${PING_LATENCY:-0}" 1)" \
        "$(json_field "ping_loss_percent" "${PING_LOSS:-100}" 1)" \
        "$(json_field "jitter_ms" "${PING_JITTER:-0}" 1)" \
        "$(json_field "rsrp" "${CELLULAR_RSRP:--120}" 1)" \
        "$(json_field "rsrq" "${CELLULAR_RSRQ:--20}" 1)" \
        "$(json_field "sinr" "${CELLULAR_SINR:-0}" 1)" \
        "$(json_field "rssi" "${CELLULAR_RSSI:--100}" 1)" \
        "$(json_field "operator" "${CELLULAR_OPERATOR:-Unknown}")" \
        "$(json_field "technology" "${CELLULAR_TECHNOLOGY:-Unknown}")" \
        "$(json_field "cell_id" "${CELLULAR_CELL_ID:-0}")" \
    )
    
    # Create main JSON object
    local json_output=$(json_object \
        "$(json_field "iface" "$interface")" \
        "$(json_field "timestamp" "$timestamp" 1)" \
        "$(json_field "type" "cellular")" \
        "\"metrics\": $metrics_json" \
    )
    
    echo "$json_output"
}

# === MAIN COLLECTOR LOGIC ===
main() {
    log_info "Starting cellular metrics collection for interface: $CELLULAR_INTERFACE"
    
    # Check if interface exists
    if ! check_interface_exists "$CELLULAR_INTERFACE"; then
        log_error "Cellular interface $CELLULAR_INTERFACE does not exist or is down"
        exit 1
    fi
    
    # Initialize metric variables
    export PING_LATENCY="0"
    export PING_LOSS="100"
    export PING_JITTER="0"
    export CELLULAR_RSRP="-120"
    export CELLULAR_RSRQ="-20"
    export CELLULAR_SINR="0"
    export CELLULAR_RSSI="-100"
    export CELLULAR_OPERATOR="Unknown"
    export CELLULAR_TECHNOLOGY="Unknown"
    export CELLULAR_CELL_ID="0"
    
    # Collect metrics (continue even if one fails)
    local ping_success=0
    local cellular_success=0
    
    if collect_ping_metrics; then
        ping_success=1
        log_debug "Ping metrics collection successful"
    else
        log_warning "Ping metrics collection failed"
    fi
    
    if extract_cellular_metrics; then
        cellular_success=1
        log_debug "Cellular-specific metrics collection successful"
    else
        log_warning "Cellular-specific metrics collection failed"
    fi
    
    # Generate output even if some metrics failed
    if [ "$ping_success" = "1" ] || [ "$cellular_success" = "1" ]; then
        generate_json_output
        log_info "Cellular metrics collection completed successfully"
        exit 0
    else
        log_error "All metric collection failed for cellular interface"
        exit 1
    fi
}

# Run main function with interface argument support
main "$@"
