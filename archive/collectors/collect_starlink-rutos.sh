#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "collect_starlink-rutos.sh" "$SCRIPT_VERSION"

# === STARLINK METRICS COLLECTOR ===
# Collects Starlink-specific metrics via gRPC API and common metrics via fping
# Outputs single-line JSON for the stability scoring system

readonly SCRIPT_NAME="collect_starlink-rutos.sh"

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

# === STARLINK CONFIGURATION ===
STARLINK_INTERFACE="${STARLINK_INTERFACE:-wan}"
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
PING_TARGET="${PING_TARGET:-8.8.8.8}"
PING_COUNT="${PING_COUNT:-3}"
API_TIMEOUT="${STARLINK_API_TIMEOUT:-8}"

# === STARLINK API FUNCTIONS ===
call_starlink_grpc() {
    local method="$1"
    local grpc_endpoint="$STARLINK_IP:$STARLINK_PORT"
    
    log_trace "Calling Starlink gRPC API: $method"
    
    # Try grpcurl if available (preferred method)
    if command_exists grpcurl; then
        safe_command "Starlink gRPC $method" \
            "timeout $API_TIMEOUT grpcurl -plaintext -d {} $grpc_endpoint SpaceX.API.Device.Device/$method"
    elif command_exists curl; then
        # Fallback to JSON-RPC over HTTP
        log_debug "grpcurl not available, using JSON-RPC fallback"
        safe_command "Starlink JSON-RPC $method" \
            "timeout $API_TIMEOUT curl -s -m $API_TIMEOUT -H 'Content-Type: application/json' \
            -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\"}' \
            http://$STARLINK_IP:$STARLINK_PORT/JSONRpc"
    else
        log_error "Neither grpcurl nor curl available for Starlink API"
        return 1
    fi
}

# === METRIC EXTRACTION FUNCTIONS ===
extract_starlink_metrics() {
    log_debug "Extracting Starlink-specific metrics"
    
    # Get status data from Starlink API
    local status_data
    if ! status_data=$(call_starlink_grpc "Handle" | grep -A 1000 '"getStatus"' 2>/dev/null); then
        log_error "Failed to get Starlink status data"
        return 1
    fi
    
    # Extract specific metrics with validation
    local snr=$(echo "$status_data" | grep -o '"snr":[0-9.-]*' | cut -d':' -f2 | head -1)
    local pop_ping_drop_rate=$(echo "$status_data" | grep -o '"popPingDropRate":[0-9.]*' | cut -d':' -f2 | head -1)
    local fraction_obstructed=$(echo "$status_data" | grep -o '"fractionObstructed":[0-9.]*' | cut -d':' -f2 | head -1)
    local seconds_to_next_sat=$(echo "$status_data" | grep -o '"secondsToFirstNonemptySlot":[0-9.]*' | cut -d':' -f2 | head -1)
    
    # Additional metrics
    local uptime_s=$(echo "$status_data" | grep -o '"uptimeS":[0-9]*' | cut -d':' -f2 | head -1)
    local alert_motors_stuck=$(echo "$status_data" | grep -o '"alertMotorsStuck":[a-z]*' | cut -d':' -f2 | head -1)
    local alert_thermal_throttle=$(echo "$status_data" | grep -o '"alertThermalThrottle":[a-z]*' | cut -d':' -f2 | head -1)
    
    # Convert boolean alerts to numeric (0/1)
    case "$alert_motors_stuck" in
        "true") alert_motors_stuck="1" ;;
        *) alert_motors_stuck="0" ;;
    esac
    
    case "$alert_thermal_throttle" in
        "true") alert_thermal_throttle="1" ;;
        *) alert_thermal_throttle="0" ;;
    esac
    
    # Validate extracted metrics
    validate_metric "snr" "$snr" || snr="0"
    validate_metric "ping_loss" "$pop_ping_drop_rate" || pop_ping_drop_rate="0"
    
    # Convert fraction_obstructed to percentage
    if [ -n "$fraction_obstructed" ] && [ "$fraction_obstructed" != "0" ]; then
        fraction_obstructed=$(awk "BEGIN {printf \"%.2f\", $fraction_obstructed * 100}")
    else
        fraction_obstructed="0"
    fi
    
    # Set defaults for missing values
    snr="${snr:-0}"
    pop_ping_drop_rate="${pop_ping_drop_rate:-0}"
    fraction_obstructed="${fraction_obstructed:-0}"
    seconds_to_next_sat="${seconds_to_next_sat:-0}"
    uptime_s="${uptime_s:-0}"
    
    log_debug "Starlink metrics: SNR=$snr, Drop_Rate=$pop_ping_drop_rate, Obstruction=$fraction_obstructed%, Next_Sat=${seconds_to_next_sat}s"
    
    # Export metrics as variables for JSON creation
    export STARLINK_SNR="$snr"
    export STARLINK_POP_PING_DROP_RATE="$pop_ping_drop_rate" 
    export STARLINK_FRACTION_OBSTRUCTED="$fraction_obstructed"
    export STARLINK_SECONDS_TO_NEXT_SAT="$seconds_to_next_sat"
    export STARLINK_UPTIME_S="$uptime_s"
    export STARLINK_ALERT_MOTORS_STUCK="$alert_motors_stuck"
    export STARLINK_ALERT_THERMAL_THROTTLE="$alert_thermal_throttle"
    
    return 0
}

# === COMMON METRICS (PING) ===
collect_ping_metrics() {
    log_debug "Collecting ping metrics for $STARLINK_INTERFACE"
    
    # Use fping for common metrics
    local ping_result
    if ! ping_result=$(safe_command "fping to $PING_TARGET" \
        "fping -c $PING_COUNT -q $PING_TARGET 2>&1"); then
        log_warning "fping failed for $STARLINK_INTERFACE, using fallback ping"
        
        # Fallback to regular ping
        if ! ping_result=$(safe_command "ping to $PING_TARGET" \
            "ping -c $PING_COUNT -W 5 $PING_TARGET 2>/dev/null"); then
            log_error "Both fping and ping failed for $STARLINK_INTERFACE"
            export PING_LATENCY="0"
            export PING_LOSS="100"
            export PING_JITTER="0"
            return 1
        fi
    fi
    
    # Parse fping output (format: "8.8.8.8 : xmt/rcv/%loss = 3/3/0%, min/avg/max = 12.1/15.2/18.3")
    local latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f2)
    local loss=$(echo "$ping_result" | grep -o '[0-9]*%' | sed 's/%//')
    local min_latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f1)
    local max_latency=$(echo "$ping_result" | grep -o 'min/avg/max = [0-9.]*\/[0-9.]*\/[0-9.]*' | cut -d'=' -f2 | cut -d'/' -f3)
    
    # Calculate jitter (max - min)
    local jitter="0"
    if [ -n "$min_latency" ] && [ -n "$max_latency" ]; then
        jitter=$(awk "BEGIN {printf \"%.2f\", $max_latency - $min_latency}")
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
    local interface="$STARLINK_INTERFACE"
    
    log_debug "Generating JSON output for $interface"
    
    # Create metrics object
    local metrics_json=$(json_object \
        "$(json_field "ping_latency_ms" "${PING_LATENCY:-0}" 1)" \
        "$(json_field "ping_loss_percent" "${PING_LOSS:-100}" 1)" \
        "$(json_field "jitter_ms" "${PING_JITTER:-0}" 1)" \
        "$(json_field "snr" "${STARLINK_SNR:-0}" 1)" \
        "$(json_field "pop_ping_drop_rate" "${STARLINK_POP_PING_DROP_RATE:-0}" 1)" \
        "$(json_field "fraction_obstructed" "${STARLINK_FRACTION_OBSTRUCTED:-0}" 1)" \
        "$(json_field "seconds_to_next_sat" "${STARLINK_SECONDS_TO_NEXT_SAT:-0}" 1)" \
        "$(json_field "uptime_s" "${STARLINK_UPTIME_S:-0}" 1)" \
        "$(json_field "alert_motors_stuck" "${STARLINK_ALERT_MOTORS_STUCK:-0}" 1)" \
        "$(json_field "alert_thermal_throttle" "${STARLINK_ALERT_THERMAL_THROTTLE:-0}" 1)" \
    )
    
    # Create main JSON object
    local json_output=$(json_object \
        "$(json_field "iface" "$interface")" \
        "$(json_field "timestamp" "$timestamp" 1)" \
        "$(json_field "type" "starlink")" \
        "\"metrics\": $metrics_json" \
    )
    
    echo "$json_output"
}

# === MAIN COLLECTOR LOGIC ===
main() {
    log_info "Starting Starlink metrics collection for interface: $STARLINK_INTERFACE"
    
    # Check if interface exists
    if ! check_interface_exists "$STARLINK_INTERFACE"; then
        log_error "Starlink interface $STARLINK_INTERFACE does not exist or is down"
        exit 1
    fi
    
    # Initialize metric variables
    export PING_LATENCY="0"
    export PING_LOSS="100"
    export PING_JITTER="0"
    export STARLINK_SNR="0"
    export STARLINK_POP_PING_DROP_RATE="0"
    export STARLINK_FRACTION_OBSTRUCTED="0"
    export STARLINK_SECONDS_TO_NEXT_SAT="0"
    export STARLINK_UPTIME_S="0"
    export STARLINK_ALERT_MOTORS_STUCK="0"
    export STARLINK_ALERT_THERMAL_THROTTLE="0"
    
    # Collect metrics (continue even if one fails)
    local ping_success=0
    local starlink_success=0
    
    if collect_ping_metrics; then
        ping_success=1
        log_debug "Ping metrics collection successful"
    else
        log_warning "Ping metrics collection failed"
    fi
    
    if extract_starlink_metrics; then
        starlink_success=1
        log_debug "Starlink-specific metrics collection successful" 
    else
        log_warning "Starlink-specific metrics collection failed"
    fi
    
    # Generate output even if some metrics failed
    if [ "$ping_success" = "1" ] || [ "$starlink_success" = "1" ]; then
        generate_json_output
        log_info "Starlink metrics collection completed successfully"
        exit 0
    else
        log_error "All metric collection failed for Starlink interface"
        exit 1
    fi
}

# Run main function
main "$@"
