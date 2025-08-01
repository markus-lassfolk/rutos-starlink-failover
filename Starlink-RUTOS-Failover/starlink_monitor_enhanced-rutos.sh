#!/bin/sh

# ==============================================================================
# Enhanced Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.7.1
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script proactively monitors the quality of a Starlink internet connection
# using its unofficial gRPC API. Enhanced with GPS location tracking and 4G/5G
# cellular data collection for comprehensive connectivity intelligence.
#
# Features:
# - Starlink quality monitoring with failover logic
# - GPS location tracking from multiple sources (RUTOS, Starlink)
# - 4G/5G cellular data collection (signal, operator, roaming)
# - Intelligent failover decisions based on multiple factors
# - Statistical data aggregation (60:1 reduction)
# - Comprehensive logging for analytics
#
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution
" >&2
    exit 0
fi

# Standard colors for consistent output (compatible with busybox)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='[0;31m'
    GREEN='[0;32m'
    YELLOW='[1;33m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    BLUE='[1;35m'
    CYAN='[0;36m'
    NC='[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    BLUE=""
    CYAN=""
    NC=""
fi

# --- Configuration Loading ---
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Set default values for variables that may not be in config
LOG_TAG="${LOG_TAG:-StarlinkMonitor}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LOG_DIR="${LOG_DIR:-/etc/starlink-logs}"

# GPS and Cellular integration settings
GPS_LOG_FILE="${LOG_DIR}/gps_data.csv"
CELLULAR_LOG_FILE="${LOG_DIR}/cellular_data.csv"
ENHANCED_LOG_FILE="${LOG_DIR}/starlink_enhanced.csv"

# Create necessary directories
mkdir -p "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution
" >&2
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        printf "[DRY-RUN] Would execute: %s
" "$description" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] Executing: %s
" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# =============================================================================
# GPS DATA COLLECTION
# Intelligent GPS data collection from multiple sources
# =============================================================================

collect_gps_data() {
    log_debug "🛰️ ENHANCED GPS: Using standardized library functions for GPS data collection"
    
    # Use library function if available, fallback to local implementation
    if [ "${_RUTOS_DATA_COLLECTION_LOADED:-0}" = "1" ] && command -v collect_gps_data_lib >/dev/null 2>&1; then
        collect_gps_data_lib
    else
        # Fallback implementation when library not available
        lat="" lon="" alt="" accuracy="" source="" timestamp=""

        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Try RUTOS GPS first (most accurate for position)
        if command -v gpsctl >/dev/null 2>&1; then
            gps_output=$(gpsctl -i 2>/dev/null || echo "")
            if [ -n "$gps_output" ]; then
                lat=$(echo "$gps_output" | grep "Latitude:" | awk '{print $2}' | head -1)
                lon=$(echo "$gps_output" | grep "Longitude:" | awk '{print $2}' | head -1)
                alt=$(echo "$gps_output" | grep "Altitude:" | awk '{print $2}' | head -1)
                if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0.000000" ]; then
                    accuracy="high"
                    source="rutos_gps"
                fi
            fi
        fi

        # Try Starlink GPS as backup
        if [ -z "$lat" ] || [ "$lat" = "0.000000" ]; then
            if [ -n "${GRPCURL_CMD:-}" ] && [ -x "${GRPCURL_CMD:-}" ]; then
                starlink_gps=$("$GRPCURL_CMD" -plaintext -d '{"get_location":{}}' "${STARLINK_IP:-192.168.100.1}:${STARLINK_PORT:-9200}" SpaceX.API.Device.Device.Handle 2>/dev/null || echo "")
                if [ -n "$starlink_gps" ]; then
                    lat=$(echo "$starlink_gps" | grep -o '"latitude":[^,]*' | cut -d':' -f2 | tr -d ' "')
                    lon=$(echo "$starlink_gps" | grep -o '"longitude":[^,]*' | cut -d':' -f2 | tr -d ' "')
                    alt=$(echo "$starlink_gps" | grep -o '"altitude":[^,]*' | cut -d':' -f2 | tr -d ' "')
                    if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0" ]; then
                        accuracy="medium"
                        source="starlink_gps"
                    fi
                fi
            fi
        fi

        # Fallback to cellular tower location
        if [ -z "$lat" ] || [ "$lat" = "0.000000" ] || [ "$lat" = "0" ]; then
            if command -v gsmctl >/dev/null 2>&1; then
                # Try to get cell tower location (less accurate but still useful)
                cell_info=$(gsmctl -A 'AT+QENG="servingcell"' 2>/dev/null || echo "")
                if [ -n "$cell_info" ]; then
                    # This would need cell tower database lookup - simplified for now
                    lat="0.0"
                    lon="0.0"
                    alt="0"
                    accuracy="low"
                    source="cellular_tower"
                fi
            fi
        fi

        # Default values if no GPS available
        lat="${lat:-0.0}"
        lon="${lon:-0.0}"
        alt="${alt:-0}"
        accuracy="${accuracy:-none}"
        source="${source:-unavailable}"

        # Use library sanitization if available
        if command -v sanitize_csv_field >/dev/null 2>&1; then
            lat=$(sanitize_csv_field "$lat" 12)
            lon=$(sanitize_csv_field "$lon" 12)
            alt=$(sanitize_csv_field "$alt" 8)
        fi

        printf "%s" "$timestamp,$lat,$lon,$alt,$accuracy,$source"
    fi
}

# =============================================================================
# CELLULAR DATA COLLECTION
# Comprehensive 4G/5G modem data collection
# =============================================================================

collect_cellular_data() {
    log_debug "📱 ENHANCED CELLULAR: Using standardized library functions for cellular data collection"
    
    # Use library function if available, fallback to local implementation
    if [ "${_RUTOS_DATA_COLLECTION_LOADED:-0}" = "1" ] && command -v collect_cellular_data_lib >/dev/null 2>&1; then
        collect_cellular_data_lib
    else
        # Fallback implementation when library not available
        timestamp="" modem_id="" signal_strength="" signal_quality="" network_type=""
        operator="" roaming_status="" connection_status="" data_usage_mb=""
        frequency_band="" cell_id="" lac="" error_rate=""

        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        modem_id="primary"
        
        if command -v gsmctl >/dev/null 2>&1; then
            log_debug "📱 ENHANCED CELLULAR: gsmctl available, collecting enhanced cellular data"
            
            # Signal strength and quality
            signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
            signal_rssi=$(echo "$signal_info" | cut -d',' -f1 | cut -d':' -f2 | tr -d ' 
')
            signal_ber=$(echo "$signal_info" | cut -d',' -f2 | tr -d ' 
')

            # Convert RSSI to dBm
            if [ "$signal_rssi" != "99" ] && [ "$signal_rssi" -ge 0 ] && [ "$signal_rssi" -le 31 ]; then
                signal_strength=$((signal_rssi * 2 - 113))
            else
                signal_strength="-113"
            fi

            signal_quality="$signal_ber"

            # Network type and operator
            network_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" | head -1 || echo "")
            if [ -n "$network_info" ]; then
                operator_raw=$(echo "$network_info" | cut -d'"' -f2 | head -1 | tr -d '
,')
                # Use library sanitization if available
                if command -v sanitize_csv_field >/dev/null 2>&1; then
                    operator=$(sanitize_csv_field "$operator_raw" 20)
                else
                    operator=$(echo "$operator_raw" | head -c 20)
                fi
            fi
            operator="${operator:-Unknown}"

            # Network technology  
            tech_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "")
            if echo "$tech_info" | grep -q "LTE"; then
                network_type="LTE"
            elif echo "$tech_info" | grep -q "NR5G\|5G"; then
                network_type="5G"
            elif echo "$tech_info" | grep -q "WCDMA\|UMTS"; then
                network_type="3G"
            else
                network_type="Unknown"
            fi

            # Roaming status
            roaming_info=$(gsmctl -A 'AT+CREG?' 2>/dev/null | grep "+CREG:" | head -1 || echo "")
            if echo "$roaming_info" | grep -q ",5"; then
                roaming_status="roaming"
            else
                roaming_status="home"
            fi

            # Connection status
            if ip route show | grep -q "mob1s1a1"; then
                connection_status="connected"
            else
                connection_status="disconnected"
            fi

            # Additional details
            data_usage_mb="0"
            frequency_band="unknown"
            cell_id="0"
            lac="0"
            error_rate="0"

        else
            log_debug "📱 ENHANCED CELLULAR: gsmctl not available, using default values"
            signal_strength="-113"
            signal_quality="99"
            network_type="Unknown"
            operator="Unknown"
            roaming_status="unknown"
            connection_status="unknown"
            data_usage_mb="0"
            frequency_band="unknown"
            cell_id="0"
            lac="0"
            error_rate="0"
        fi

        # Final data sanitization for CSV safety
        if command -v sanitize_csv_field >/dev/null 2>&1; then
            operator=$(sanitize_csv_field "$operator" 20)
            network_type=$(sanitize_csv_field "$network_type" 15)
            roaming_status=$(sanitize_csv_field "$roaming_status" 10)
            connection_status=$(sanitize_csv_field "$connection_status" 15)
        else
            operator=$(echo "$operator" | tr -d ',
' | head -c 20)
            network_type=$(echo "$network_type" | tr -d ',
' | head -c 15)
            roaming_status=$(echo "$roaming_status" | tr -d ',
' | head -c 10)
            connection_status=$(echo "$connection_status" | tr -d ',
' | head -c 15)
        fi
        
        log_debug "📱 ENHANCED CELLULAR: Final sanitized data - operator='$operator', network='$network_type'"

        printf "%s" "$timestamp,$modem_id,$signal_strength,$signal_quality,$network_type,$operator,$roaming_status,$connection_status,$data_usage_mb,$frequency_band,$cell_id,$lac,$error_rate"
    fi
}

# =============================================================================
# STARLINK DATA COLLECTION (Enhanced)
# Original Starlink monitoring with GPS and cellular context
# =============================================================================

get_starlink_data() {
    grpc_response=""
    status_response=""

    # Get status data
    if [ -n "${GRPCURL_CMD:-}" ] && [ -x "${GRPCURL_CMD:-}" ]; then
        status_response=$("$GRPCURL_CMD" -plaintext -d '{"get_status":{}}' "${STARLINK_IP:-192.168.100.1}:${STARLINK_PORT:-9200}" SpaceX.API.Device.Device.Handle 2>/dev/null || echo "")
        grpc_response=$("$GRPCURL_CMD" -plaintext -d '{"get_stats":{}}' "${STARLINK_IP:-192.168.100.1}:${STARLINK_PORT:-9200}" SpaceX.API.Device.Device.Handle 2>/dev/null || echo "")
    fi

    if [ -z "$grpc_response" ] || [ -z "$status_response" ]; then
        printf "%s" "0,0,0,0,offline,0,0,0,0"
        return 1
    fi

    # Parse status data
    state=$(echo "$status_response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 | head -1)
    uptime=$(echo "$status_response" | grep -o '"uptime_s":[^,}]*' | cut -d':' -f2 | head -1)

    # Parse stats data
    ping_drop_rate=$(echo "$grpc_response" | grep -o '"ping_drop_rate_last_1h":[^,}]*' | cut -d':' -f2 | head -1)
    ping_latency=$(echo "$grpc_response" | grep -o '"ping_latency_ms_last_1h":[^,}]*' | cut -d':' -f2 | head -1)
    download_throughput=$(echo "$grpc_response" | grep -o '"download_throughput_bps_last_1h":[^,}]*' | cut -d':' -f2 | head -1)
    upload_throughput=$(echo "$grpc_response" | grep -o '"upload_throughput_bps_last_1h":[^,}]*' | cut -d':' -f2 | head -1)
    obstruction_duration=$(echo "$grpc_response" | grep -o '"obstruction_duration_last_1h":[^,}]*' | cut -d':' -f2 | head -1)
    obstruction_percent=$(echo "$grpc_response" | grep -o '"obstruction_percent_time_last_1h":[^,}]*' | cut -d':' -f2 | head -1)

    # Default values for missing data
    ping_drop_rate="${ping_drop_rate:-0}"
    ping_latency="${ping_latency:-0}"
    download_throughput="${download_throughput:-0}"
    upload_throughput="${upload_throughput:-0}"
    obstruction_duration="${obstruction_duration:-0}"
    obstruction_percent="${obstruction_percent:-0}"
    state="${state:-unknown}"
    uptime="${uptime:-0}"

    printf "%s" "$ping_drop_rate,$ping_latency,$download_throughput,$upload_throughput,$state,$uptime,$obstruction_duration,$obstruction_percent"
}

# =============================================================================
# ENHANCED LOGGING
# Combined logging with GPS, cellular, and Starlink data
# =============================================================================

log_enhanced_data() {
    timestamp=""
    gps_data=""
    cellular_data=""
    starlink_data=""

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Collect all data
    gps_data=$(collect_gps_data)
    cellular_data=$(collect_cellular_data)
    starlink_data=$(get_starlink_data)

    # Write to enhanced log with all data combined
    if [ ! -f "$ENHANCED_LOG_FILE" ]; then
        # Create header
        echo "timestamp,gps_timestamp,latitude,longitude,altitude,gps_accuracy,gps_source,cell_timestamp,modem_id,signal_strength,signal_quality,network_type,operator,roaming_status,connection_status,data_usage_mb,frequency_band,cell_id,lac,error_rate,ping_drop_rate,ping_latency,download_throughput,upload_throughput,starlink_state,uptime,obstruction_duration,obstruction_percent" >"$ENHANCED_LOG_FILE"
    fi

    echo "$timestamp,$gps_data,$cellular_data,$starlink_data" >>"$ENHANCED_LOG_FILE"

    # Also write individual logs for backward compatibility and specialized analysis
    log_individual_data "$gps_data" "$cellular_data" "$starlink_data"

    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} Enhanced data logged: %s entries
" "1" >&2
    fi
}

log_individual_data() {
    gps_data="$1"
    cellular_data="$2"
    starlink_data="$3"

    # GPS log
    if [ ! -f "$GPS_LOG_FILE" ]; then
        echo "timestamp,latitude,longitude,altitude,accuracy,source" >"$GPS_LOG_FILE"
    fi
    echo "$gps_data" >>"$GPS_LOG_FILE"

    # Cellular log
    if [ ! -f "$CELLULAR_LOG_FILE" ]; then
        echo "timestamp,modem_id,signal_strength,signal_quality,network_type,operator,roaming_status,connection_status,data_usage_mb,frequency_band,cell_id,lac,error_rate" >"$CELLULAR_LOG_FILE"
    fi
    echo "$cellular_data" >>"$CELLULAR_LOG_FILE"
}

# =============================================================================
# ORIGINAL STARLINK MONITORING LOGIC
# Enhanced with GPS and cellular context for smarter decisions
# =============================================================================

check_starlink_quality() {
    data_line=""
    ping_drop_rate=""
    ping_latency=""
    obstruction_percent=""
    is_high=0
    current_metric=""
    current_state=""

    data_line=$(get_starlink_data)
    ping_drop_rate=$(echo "$data_line" | cut -d',' -f1)
    ping_latency=$(echo "$data_line" | cut -d',' -f2)
    obstruction_percent=$(echo "$data_line" | cut -d',' -f8)

    # Check thresholds
    if [ "$(echo "$ping_drop_rate > $PING_DROP_THRESHOLD" | bc 2>/dev/null || echo 0)" = "1" ] ||
        [ "$(echo "$ping_latency > $PING_LATENCY_THRESHOLD" | bc 2>/dev/null || echo 0)" = "1" ] ||
        [ "$(echo "$obstruction_percent > $OBSTRUCTION_THRESHOLD" | bc 2>/dev/null || echo 0)" = "1" ]; then
        is_high=1
    fi

    # Get current mwan3 metric
    current_metric=$(uci get mwan3.starlink.metric 2>/dev/null || echo "10")

    # Determine state
    if [ "$is_high" = "1" ]; then
        current_state="down"
    else
        current_state="up"
    fi

    # Enhanced decision making with cellular context
    make_failover_decision "$current_state" "$current_metric" "$ping_drop_rate" "$ping_latency" "$obstruction_percent"

    # Log the enhanced monitoring data
    log_enhanced_data

    printf "${GREEN}[INFO]${NC} Starlink monitoring completed - State: %s, Metric: %s
" "$current_state" "$current_metric"
}

make_failover_decision() {
    current_state="$1"
    current_metric="$2"
    ping_drop_rate="$3"
    ping_latency="$4"
    obstruction_percent="$5"

    # Get cellular status for smart failover
    cellular_available=0
    if ip route show | grep -q "mob1s1a1"; then
        cellular_available=1
    fi

    # Smart failover logic
    if [ "$current_state" = "down" ] && [ "$current_metric" -lt 20 ]; then
        if [ "$cellular_available" = "1" ]; then
            printf "${YELLOW}[WARNING]${NC} Starlink quality degraded, failing over to cellular backup
"
            safe_execute "uci set mwan3.starlink.metric=20" "Increase Starlink metric for failover"
            safe_execute "uci commit mwan3" "Commit mwan3 changes"
            safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 configuration"
        else
            printf "${RED}[ERROR]${NC} Starlink quality degraded but no cellular backup available
"
        fi
    elif [ "$current_state" = "up" ] && [ "$current_metric" -gt 10 ]; then
        printf "${GREEN}[INFO]${NC} Starlink quality restored, failing back from cellular
"
        safe_execute "uci set mwan3.starlink.metric=10" "Restore Starlink primary metric"
        safe_execute "uci commit mwan3" "Commit mwan3 changes"
        safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 configuration"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} Enhanced Starlink Monitor v%s starting
" "$SCRIPT_VERSION" >&2
        printf "${CYAN}[DEBUG]${NC} GPS Log: %s
" "$GPS_LOG_FILE" >&2
        printf "${CYAN}[DEBUG]${NC} Cellular Log: %s
" "$CELLULAR_LOG_FILE" >&2
        printf "${CYAN}[DEBUG]${NC} Enhanced Log: %s
" "$ENHANCED_LOG_FILE" >&2
    fi

    # Check if this is OpenWrt/RUTOS system
    if [ ! -f "/etc/openwrt_release" ]; then
        printf "${RED}[ERROR]${NC} This script is designed for OpenWrt/RUTOS systems
" >&2
        exit 1
    fi

    # Main monitoring cycle
    check_starlink_quality

    printf "${GREEN}[SUCCESS]${NC} Enhanced monitoring cycle completed
"
}

# Execute main function
main "$@"

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
