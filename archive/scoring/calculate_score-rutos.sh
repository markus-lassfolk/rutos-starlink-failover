#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "calculate_score-rutos.sh" "$SCRIPT_VERSION"

# === UNIFIED SCORING ENGINE ===
# Implements the stability score algorithm from the architecture document
# Reads latest_metrics.json and calculates normalized weighted scores (0-100)

readonly SCRIPT_NAME="calculate_score-rutos.sh"

# Load common functions
. "$(dirname "$0")/../lib/common_functions.sh"

# === CONFIGURATION ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"
DATA_DIR="${DATA_DIR:-/usr/local/starlink/data}"
METRICS_FILE="$DATA_DIR/latest_metrics.json"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === SCORING WEIGHTS BY CONNECTION TYPE ===
# Weights must add up to 1.0 for each connection type

# Starlink weights (emphasize signal quality and obstructions)
STARLINK_WEIGHTS="
ping_loss=0.25
snr=0.20
fraction_obstructed=0.15
latency=0.15
jitter=0.10
pop_ping_drop_rate=0.10
seconds_to_next_sat=0.05
"

# Cellular weights (emphasize signal strength and technology)
CELLULAR_WEIGHTS="
ping_loss=0.30
sinr=0.25
rsrp=0.20
latency=0.15
jitter=0.10
"

# VPN weights (emphasize tunnel stability and handshake health)
VPN_WEIGHTS="
ping_loss=0.30
handshake_health=0.25
tunnel_status=0.20
latency=0.15
jitter=0.10
"

# === KILL SWITCH THRESHOLDS ===
# Values that immediately set score to 0
KILL_SWITCH_PING_LOSS="20"        # 20% packet loss kills connection
KILL_SWITCH_LATENCY="2000"        # 2 second latency kills connection  
KILL_SWITCH_FRACTION_OBSTRUCTED="80"  # 80% obstruction kills Starlink

# === NORMALIZATION THRESHOLDS ===
# Format: metric_name="worst_value:best_value"

# Common metrics (ping-based)
THRESHOLD_PING_LOSS="100:0"       # 100% worst, 0% best (invert=1)
THRESHOLD_LATENCY="1000:20"       # 1000ms worst, 20ms best (invert=1) 
THRESHOLD_JITTER="500:5"          # 500ms worst, 5ms best (invert=1)

# Starlink-specific metrics
THRESHOLD_SNR="-5:25"             # -5dB worst, 25dB best (invert=0)
THRESHOLD_FRACTION_OBSTRUCTED="100:0"  # 100% worst, 0% best (invert=1)
THRESHOLD_POP_PING_DROP_RATE="100:0"   # 100% worst, 0% best (invert=1)
THRESHOLD_SECONDS_TO_NEXT_SAT="300:0"  # 5min worst, 0s best (invert=1)

# Cellular-specific metrics  
THRESHOLD_RSRP="-120:-70"         # -120dBm worst, -70dBm best (invert=0)
THRESHOLD_RSRQ="-25:-3"           # -25dBm worst, -3dBm best (invert=0)
THRESHOLD_SINR="-10:25"           # -10dB worst, 25dB best (invert=0)

# VPN-specific metrics
THRESHOLD_HANDSHAKE_HEALTH="0:100"     # 0 worst, 100 best (invert=0)
THRESHOLD_TUNNEL_STATUS="0:1"          # 0 (DOWN) worst, 1 (UP) best (invert=0)

# === UTILITY FUNCTIONS ===

# Get normalization threshold for a metric
get_threshold() {
    local metric="$1"
    local threshold_var="THRESHOLD_$(echo "$metric" | tr '[:lower:]' '[:upper:]')"
    
    eval "echo \$$threshold_var"
}

# Get weight for a metric and connection type
get_weight() {
    local connection_type="$1"
    local metric="$2"
    local weights_var="${connection_type}_WEIGHTS"
    
    eval "weights=\$$weights_var"
    echo "$weights" | grep "^$metric=" | cut -d'=' -f2 | head -1
}

# Check if metric triggers kill switch
check_kill_switch_trigger() {
    local connection_type="$1"
    local metric="$2"
    local value="$3"
    
    case "$metric" in
        "ping_loss"|"ping_loss_percent")
            if awk "BEGIN {exit ($value > $KILL_SWITCH_PING_LOSS) ? 0 : 1}"; then
                log_warning "Kill switch triggered: $metric=$value > $KILL_SWITCH_PING_LOSS"
                return 0
            fi
            ;;
        "latency"|"ping_latency_ms")
            if awk "BEGIN {exit ($value > $KILL_SWITCH_LATENCY) ? 0 : 1}"; then
                log_warning "Kill switch triggered: $metric=$value > $KILL_SWITCH_LATENCY"
                return 0
            fi
            ;;
        "fraction_obstructed")
            if [ "$connection_type" = "starlink" ]; then
                if awk "BEGIN {exit ($value > $KILL_SWITCH_FRACTION_OBSTRUCTED) ? 0 : 1}"; then
                    log_warning "Kill switch triggered: $metric=$value > $KILL_SWITCH_FRACTION_OBSTRUCTED"
                    return 0
                fi
            fi
            ;;
    esac
    
    return 1
}

# Convert tunnel status to numeric value
convert_tunnel_status() {
    local status="$1"
    case "$status" in
        "UP"|"up"|"connected"|"1")
            echo "1"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# === CORE SCORING FUNCTION ===
calculate_stability_score() {
    local connection_type="$1"
    local metrics_json="$2"
    
    log_debug "Calculating stability score for $connection_type"
    log_trace "Metrics JSON: $metrics_json"
    
    local total_score=0
    local total_weight=0
    local connection_type_upper=$(echo "$connection_type" | tr '[:lower:]' '[:upper:]')
    
    # Get metrics list based on connection type
    local metrics_to_process=""
    case "$connection_type" in
        "starlink")
            metrics_to_process="ping_loss_percent ping_latency_ms jitter_ms snr fraction_obstructed pop_ping_drop_rate seconds_to_next_sat"
            ;;
        "cellular")
            metrics_to_process="ping_loss_percent ping_latency_ms jitter_ms rsrp rsrq sinr"
            ;;
        "vpn")
            metrics_to_process="ping_loss_percent ping_latency_ms jitter_ms handshake_health tunnel_status"
            ;;
        *)
            log_error "Unknown connection type: $connection_type"
            echo "0"
            return 1
            ;;
    esac
    
    # Process each metric
    for metric in $metrics_to_process; do
        # Extract metric value from JSON (simple grep-based parsing)
        local value=$(echo "$metrics_json" | grep -o "\"$metric\":[^,}]*" | cut -d':' -f2 | sed 's/"//g' | head -1)
        
        # Skip if metric not found
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            log_debug "Metric $metric not found or null, skipping"
            continue
        fi
        
        # Handle special cases
        if [ "$metric" = "tunnel_status" ]; then
            value=$(convert_tunnel_status "$value")
        fi
        
        log_trace "Processing metric: $metric = $value"
        
        # Check kill switch
        if check_kill_switch_trigger "$connection_type" "$metric" "$value"; then
            log_warning "Kill switch activated for $connection_type ($metric=$value) - score set to 0"
            echo "0"
            return 0
        fi
        
        # Get weight for this metric
        local weight=$(get_weight "$connection_type_upper" "$metric")
        if [ -z "$weight" ]; then
            log_debug "No weight defined for $metric in $connection_type, skipping"
            continue
        fi
        
        # Get normalization thresholds
        local threshold=$(get_threshold "$metric")
        if [ -z "$threshold" ]; then
            log_debug "No threshold defined for $metric, skipping"
            continue
        fi
        
        local worst_value=$(echo "$threshold" | cut -d':' -f1)
        local best_value=$(echo "$threshold" | cut -d':' -f2)
        
        # Determine if metric should be inverted (lower is better)
        local invert=0
        case "$metric" in
            "ping_loss"*|"latency"*|"jitter"*|"fraction_obstructed"|"pop_ping_drop_rate"|"seconds_to_next_sat")
                invert=1
                ;;
        esac
        
        # Normalize metric
        local normalized=$(normalize_metric "$value" "$best_value" "$worst_value" "$invert")
        
        # Calculate weighted contribution
        local weighted_score=$(awk "BEGIN {printf \"%.6f\", $normalized * $weight}")
        
        log_trace "  $metric: value=$value, normalized=$normalized, weight=$weight, contribution=$weighted_score"
        
        # Add to totals
        total_score=$(awk "BEGIN {printf \"%.6f\", $total_score + $weighted_score}")
        total_weight=$(awk "BEGIN {printf \"%.6f\", $total_weight + $weight}")
    done
    
    # Calculate final score (0-100)
    local final_score
    if awk "BEGIN {exit ($total_weight > 0) ? 0 : 1}"; then
        # Normalize by total weight and scale to 0-100
        final_score=$(awk "BEGIN {
            score = ($total_score / $total_weight) * 100
            if (score < 0) score = 0
            if (score > 100) score = 100
            printf \"%.1f\", score
        }")
    else
        final_score="0"
    fi
    
    log_debug "$connection_type stability score: $final_score/100 (total_weight: $total_weight)"
    echo "$final_score"
}

# === JSON PROCESSING ===
process_latest_metrics() {
    log_info "Processing latest metrics file: $METRICS_FILE"
    
    if [ ! -f "$METRICS_FILE" ]; then
        log_error "Metrics file not found: $METRICS_FILE"
        return 1
    fi
    
    # Read the JSON file
    local json_content
    if ! json_content=$(cat "$METRICS_FILE"); then
        log_error "Failed to read metrics file"
        return 1
    fi
    
    # Create output file with scores added
    local output_file="$METRICS_FILE.tmp"
    echo "{" > "$output_file"
    
    local first_entry=1
    
    # Process each interface entry in the JSON
    # Note: This is a simplified JSON parser - in production, use jq if available
    echo "$json_content" | grep -o '"[^"]*":{[^}]*}' | while IFS=: read -r interface_part metrics_part; do
        local interface=$(echo "$interface_part" | sed 's/"//g')
        local metrics_json="$metrics_part"
        
        # Get connection type from metrics
        local connection_type=$(echo "$metrics_json" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$connection_type" ]; then
            log_warning "No connection type found for interface $interface, skipping"
            continue
        fi
        
        log_debug "Processing interface: $interface (type: $connection_type)"
        
        # Calculate stability score
        local stability_score=$(calculate_stability_score "$connection_type" "$metrics_json")
        
        # Add comma if not first entry
        if [ "$first_entry" = "0" ]; then
            echo "," >> "$output_file"
        fi
        first_entry=0
        
        # Add the interface entry with stability score
        echo "  \"$interface\": {" >> "$output_file"
        echo "    \"timestamp\": $(echo "$metrics_json" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)," >> "$output_file"
        echo "    \"type\": \"$connection_type\"," >> "$output_file"
        echo "    \"stability_score\": $stability_score," >> "$output_file"
        echo "    \"metrics\": $(echo "$metrics_json" | grep -o '"metrics":{[^}]*}'  | cut -d':' -f2-)" >> "$output_file"
        echo "  }" >> "$output_file"
        
        log_info "Interface $interface ($connection_type): stability score = $stability_score/100"
    done
    
    echo "}" >> "$output_file"
    
    # Replace original file
    if mv "$output_file" "$METRICS_FILE"; then
        log_success "Updated metrics file with stability scores"
        return 0
    else
        log_error "Failed to update metrics file"
        return 1
    fi
}

# === MAIN SCRIPT LOGIC ===
main() {
    local action="${1:-calculate}"
    
    case "$action" in
        "calculate"|"calc")
            # Calculate scores for latest metrics
            ensure_directory "$DATA_DIR"
            process_latest_metrics
            ;;
        "test")
            # Test scoring with sample data
            local interface="${2:-test_interface}"
            local connection_type="${3:-starlink}"
            local sample_metrics='{"ping_loss_percent":2,"ping_latency_ms":45,"jitter_ms":12,"snr":15,"fraction_obstructed":5}'
            
            log_info "Testing scoring engine with sample data"
            log_info "Interface: $interface, Type: $connection_type"
            log_info "Sample metrics: $sample_metrics"
            
            local score=$(calculate_stability_score "$connection_type" "$sample_metrics")
            log_info "Calculated stability score: $score/100"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action]"
            echo ""
            echo "Actions:"
            echo "  calculate     - Calculate scores for all interfaces in latest_metrics.json (default)"
            echo "  test [iface] [type] - Test scoring with sample data"
            echo "  help          - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 calculate           - Process latest metrics and add stability scores"
            echo "  $0 test wan starlink   - Test scoring with sample Starlink data"
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
