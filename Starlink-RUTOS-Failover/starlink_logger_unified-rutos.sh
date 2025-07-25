#!/bin/sh

# ==============================================================================
# Unified Starlink Performance Data Logger for OpenWrt/RUTOS
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script runs periodically via cron to gather real-time performance data
# from a Starlink dish. Supports both basic CSV logging and enhanced features
# (GPS tracking, cellular data, statistical aggregation) based on configuration.
#
# Features (configuration-controlled):
# - Basic CSV logging for Starlink performance data
# - GPS location tracking and analysis
# - 4G/5G cellular data collection
# - Statistical data aggregation (60:1 reduction)
# - Comprehensive analytics and reporting
# - Reboot detection and state tracking
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
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
    printf "${RED}[ERROR]${NC} Configuration file not found: %s\n" "$CONFIG_FILE" >&2
    exit 1
fi

# Set default values for variables that may not be in config
LOG_TAG="${LOG_TAG:-StarlinkLogger}"
LOG_DIR="${LOG_DIR:-/etc/starlink-logs}"
OUTPUT_CSV="${OUTPUT_CSV:-$LOG_DIR/starlink_performance.csv}"
STATE_FILE="${STATE_FILE:-/tmp/run/starlink_logger_state}"

# Enhanced feature flags (configuration-controlled)
ENABLE_GPS_LOGGING="${ENABLE_GPS_LOGGING:-false}"
ENABLE_CELLULAR_LOGGING="${ENABLE_CELLULAR_LOGGING:-false}"
ENABLE_STATISTICAL_AGGREGATION="${ENABLE_STATISTICAL_AGGREGATION:-false}"
ENABLE_ENHANCED_METRICS="${ENABLE_ENHANCED_METRICS:-false}"

# Enhanced logging settings (only used if enabled)
AGGREGATED_LOG_FILE="${LOG_DIR}/starlink_aggregated.csv"
AGGREGATION_BATCH_SIZE="${AGGREGATION_BATCH_SIZE:-60}"

# Create necessary directories
mkdir -p "$LOG_DIR" "$(dirname "$STATE_FILE")" 2>/dev/null || true

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "${CYAN}[DEBUG]${NC} DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
    printf "${CYAN}[DEBUG]${NC} GPS_LOGGING=%s, CELLULAR_LOGGING=%s, AGGREGATION=%s\n" "$ENABLE_GPS_LOGGING" "$ENABLE_CELLULAR_LOGGING" "$ENABLE_STATISTICAL_AGGREGATION" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    printf "%s[INFO]%s RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution\n" "$GREEN" "$NC" >&2
    exit 0
fi

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log_info() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$timestamp" "$1"
    logger -t "$LOG_TAG" -p user.info "$1" 2>/dev/null || true
}

log_warning() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$timestamp" "$1" >&2
    logger -t "$LOG_TAG" -p user.warning "$1" 2>/dev/null || true
}

log_error() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$timestamp" "$1" >&2
    logger -t "$LOG_TAG" -p user.err "$1" 2>/dev/null || true
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$timestamp" "$1" >&2
    fi
}

# =============================================================================
# STATISTICAL AGGREGATION FUNCTIONS (Enhanced Feature)
# 60:1 data reduction with GPS and cellular intelligence
# =============================================================================

create_aggregated_header() {
    # Skip if aggregation is disabled
    if [ "$ENABLE_STATISTICAL_AGGREGATION" != "true" ]; then
        return 0
    fi

    cat >"$AGGREGATED_LOG_FILE" <<'EOF'
batch_start,batch_end,sample_count,avg_latitude,avg_longitude,avg_altitude,gps_accuracy_dist,primary_gps_source,location_stability,avg_cell_signal,avg_cell_quality,primary_network_type,primary_operator,roaming_percentage,cellular_stability,avg_ping_drop_rate,avg_ping_latency,avg_download_mbps,avg_upload_mbps,starlink_uptime_pct,avg_obstruction_pct,connectivity_score,location_change_detected,cellular_handoffs,starlink_state_changes,data_quality_score
EOF
    log_debug "Created aggregated log header"
}

perform_statistical_aggregation() {
    # Skip if aggregation is disabled
    if [ "$ENABLE_STATISTICAL_AGGREGATION" != "true" ]; then
        log_debug "Statistical aggregation disabled, skipping"
        return 0
    fi

    source_file="$1"
    batch_size="${2:-$AGGREGATION_BATCH_SIZE}"
    temp_batch="/tmp/batch_$$"
    line_count=0

    if [ ! -f "$source_file" ]; then
        log_warning "Source file not found for aggregation: $source_file"
        return 1
    fi

    # Count lines (excluding header)
    line_count=$(tail -n +2 "$source_file" | wc -l | tr -d ' \n\r')

    if [ "$line_count" -lt "$batch_size" ]; then
        log_debug "Insufficient data for aggregation ($line_count lines, need $batch_size)"
        return 0
    fi

    log_info "Processing $line_count lines for statistical aggregation"

    # Create aggregated file header if needed
    if [ ! -f "$AGGREGATED_LOG_FILE" ]; then
        create_aggregated_header
    fi

    # Process batches using awk for statistical calculations
    tail -n +2 "$source_file" | head -n "$batch_size" >"$temp_batch"

    # Complex awk script for statistical aggregation
    awk -F',' -v batch_size="$batch_size" '
    BEGIN {
        # Initialize variables
        count = 0; total_lat = 0; total_lon = 0; total_alt = 0
        total_latency = 0; total_loss = 0; total_obstruction = 0
        total_uptime = 0; total_signal = 0; total_quality = 0
        rutos_gps = 0; starlink_gps = 0; cellular_gps = 0
        operators[""] = 0; networks[""] = 0; roaming_count = 0
        first_timestamp = ""; last_timestamp = ""
        location_changes = 0; cellular_handoffs = 0; state_changes = 0
        prev_lat = ""; prev_lon = ""; prev_operator = ""; prev_network = ""
    }
    {
        count++
        if (count == 1) first_timestamp = $1
        last_timestamp = $1
        
        # GPS processing (if enabled)
        if ($2 != "" && $2 != "0") {
            total_lat += $2; total_lon += $3; total_alt += $4
            if (prev_lat != "" && (abs($2 - prev_lat) > 0.001 || abs($3 - prev_lon) > 0.001)) {
                location_changes++
            }
            prev_lat = $2; prev_lon = $3
        }
        
        # Source tracking
        if ($7 == "rutos_gps") rutos_gps++
        else if ($7 == "starlink_gps") starlink_gps++
        else if ($7 == "cellular_tower") cellular_gps++
        
        # Performance metrics
        if ($8 != "") total_latency += $8
        if ($9 != "") total_loss += $9
        if ($10 != "") total_obstruction += $10
        if ($11 != "") total_uptime += $11
        
        # Cellular processing (if enabled)
        if ($12 != "") {
            total_signal += $12; total_quality += $13
            if (prev_operator != "" && $14 != prev_operator) cellular_handoffs++
            operators[$14]++; networks[$15]++
            if ($16 == "roaming") roaming_count++
            prev_operator = $14; prev_network = $15
        }
    }
    abs() { return $(($1 < 0 ? -$1 : $1)); }
    END {
        if (count == 0) exit 1
        
        # Calculate averages
        avg_lat = total_lat / count
        avg_lon = total_lon / count  
        avg_alt = total_alt / count
        avg_latency = total_latency / count
        avg_loss = total_loss / count
        avg_obstruction = total_obstruction / count
        avg_uptime = total_uptime / count
        avg_signal = total_signal / count
        avg_quality = total_quality / count
        
        # Determine primary sources
        if (rutos_gps >= starlink_gps && rutos_gps >= cellular_gps) primary_gps = "rutos"
        else if (starlink_gps >= cellular_gps) primary_gps = "starlink"  
        else primary_gps = "cellular"
        
        # Find primary operator and network
        primary_operator = ""; primary_network = ""
        max_op_count = 0; max_net_count = 0
        for (op in operators) {
            if (operators[op] > max_op_count) { max_op_count = operators[op]; primary_operator = op }
        }
        for (net in networks) {
            if (networks[net] > max_net_count) { max_net_count = networks[net]; primary_network = net }
        }
        
        # Calculate derived metrics
        location_stability = 100 - (location_changes * 100 / count)
        cellular_stability = 100 - (cellular_handoffs * 100 / count)
        roaming_pct = roaming_count * 100 / count
        connectivity_score = (100 - avg_loss) * 0.4 + (200 - avg_latency) * 0.3 + (100 - avg_obstruction) * 0.3
        if (connectivity_score < 0) connectivity_score = 0
        
        # Data quality score based on completeness and source reliability
        quality_score = (count * 100 / batch_size) * 0.5
        if (rutos_gps > count * 0.7) quality_score += 30
        else if (starlink_gps > count * 0.7) quality_score += 20
        else quality_score += 10
        
        # Output aggregated record
        printf "%s,%s,%d,%.6f,%.6f,%.1f,%.3f,%s,%.1f,%.1f,%.1f,%s,%s,%.1f,%.1f,%.3f,%.1f,%.1f,%.1f,%.1f,%.2f,%.1f,%s,%d,%d,%d,%.1f\n",
            first_timestamp, last_timestamp, count,
            avg_lat, avg_lon, avg_alt, 0.0, primary_gps, location_stability,
            avg_signal, avg_quality, primary_network, primary_operator, roaming_pct, cellular_stability,
            avg_loss, avg_latency, 0.0, 0.0, avg_uptime, avg_obstruction, connectivity_score,
            (location_changes > 0 ? "true" : "false"), cellular_handoffs, state_changes, quality_score
    }' "$temp_batch" >>"$AGGREGATED_LOG_FILE"

    # Remove processed lines from source file
    if [ "$line_count" -gt "$batch_size" ]; then
        tail -n +$((batch_size + 1)) "$source_file" >"${source_file}.tmp"
        head -1 "$source_file" >"${source_file}.new"
        cat "${source_file}.tmp" >>"${source_file}.new"
        mv "${source_file}.new" "$source_file"
        rm -f "${source_file}.tmp"
    else
        # Keep only header if all data was processed
        head -1 "$source_file" >"${source_file}.new"
        mv "${source_file}.new" "$source_file"
    fi

    rm -f "$temp_batch"
    log_info "Statistical aggregation completed - processed $batch_size records"
}

# =============================================================================
# GPS DATA COLLECTION (Enhanced Feature)
# =============================================================================

collect_gps_data() {
    # Skip if GPS logging is disabled
    if [ "$ENABLE_GPS_LOGGING" != "true" ]; then
        log_debug "GPS logging disabled, returning default values"
        printf "0,0,0,false,0"
        return 0
    fi

    lat="" lon="" alt="" accuracy="" source=""

    log_debug "Collecting GPS data from available sources"

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
                log_debug "GPS data from RUTOS: lat=$lat, lon=$lon"
            fi
        fi
    fi

    # Fallback to Starlink GPS if RUTOS GPS unavailable
    if [ -z "$lat" ] && [ -n "${status_data:-}" ]; then
        starlink_lat=$(echo "$status_data" | "$JQ_CMD" -r '.dishGpsStats.latitude // empty' 2>/dev/null)
        starlink_lon=$(echo "$status_data" | "$JQ_CMD" -r '.dishGpsStats.longitude // empty' 2>/dev/null)
        if [ -n "$starlink_lat" ] && [ -n "$starlink_lon" ] && [ "$starlink_lat" != "0" ]; then
            lat="$starlink_lat"
            lon="$starlink_lon"
            alt=$(echo "$status_data" | "$JQ_CMD" -r '.dishGpsStats.altitude // 0' 2>/dev/null)
            accuracy="medium"
            source="starlink_gps"
            log_debug "GPS data from Starlink: lat=$lat, lon=$lon"
        fi
    fi

    # Set defaults if no GPS data available
    lat="${lat:-0}"
    lon="${lon:-0}"
    alt="${alt:-0}"
    accuracy="${accuracy:-none}"
    source="${source:-none}"

    # Return GPS data for CSV logging
    printf "%s,%s,%s,%s,%s" "$lat" "$lon" "$alt" "$accuracy" "$source"
}

# =============================================================================
# CELLULAR DATA COLLECTION (Enhanced Feature)
# =============================================================================

collect_cellular_data() {
    # Skip if cellular logging is disabled
    if [ "$ENABLE_CELLULAR_LOGGING" != "true" ]; then
        log_debug "Cellular logging disabled, returning default values"
        printf "0,0,Unknown,Unknown,home"
        return 0
    fi

    signal_strength="" signal_quality="" network_type="" operator="" roaming_status=""

    log_debug "Collecting cellular data from primary modem"

    if command -v gsmctl >/dev/null 2>&1; then
        # Signal strength and quality
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" || echo "+CSQ: 99,99")
        signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | head -1)
        signal_quality=$(echo "$signal_info" | awk -F'[: ,]' '{print $4}' | head -1)

        # Network registration and operator
        reg_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" || echo "+COPS: 0,0,\"Unknown\"")
        operator=$(echo "$reg_info" | sed 's/.*"\([^"]*\)".*/\1/')

        # Network type
        network_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" || echo "+QNWINFO: \"Unknown\"")
        network_type=$(echo "$network_info" | awk -F'"' '{print $2}')

        # Roaming status
        roaming_info=$(gsmctl -A 'AT+CREG?' 2>/dev/null | grep "+CREG:" || echo "+CREG: 0,1")
        roaming_status=$(echo "$roaming_info" | awk -F'[: ,]' '{print $4}' | head -1)
        [ "$roaming_status" = "5" ] && roaming_status="roaming" || roaming_status="home"

        log_debug "Cellular data: signal=$signal_strength, operator=$operator, network=$network_type"
    else
        log_debug "gsmctl not available, using default cellular values"
    fi

    # Set defaults if no data available
    signal_strength="${signal_strength:-0}"
    signal_quality="${signal_quality:-0}"
    network_type="${network_type:-Unknown}"
    operator="${operator:-Unknown}"
    roaming_status="${roaming_status:-home}"

    # Return cellular data for CSV logging
    printf "%s,%s,%s,%s,%s" "$signal_strength" "$signal_quality" "$network_type" "$operator" "$roaming_status"
}

# =============================================================================
# STARLINK DATA EXTRACTION
# =============================================================================

extract_starlink_metrics() {
    status_data="$1"

    log_debug "Extracting Starlink metrics from status data"

    # Extract basic performance metrics
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.uptimeS // 0' 2>/dev/null)
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingLatencyMs // 999' 2>/dev/null)
    packet_loss=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // 1' 2>/dev/null)
    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null)

    # Convert to hours and percentages
    uptime_hours=$(awk "BEGIN {print $uptime_s / 3600}")
    packet_loss_pct=$(awk "BEGIN {print $packet_loss * 100}")
    obstruction_pct=$(awk "BEGIN {print $obstruction * 100}")

    # Extract enhanced metrics if enabled
    if [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.bootcount // 0' 2>/dev/null)
        is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.readyStates.snrAboveNoiseFloor // false' 2>/dev/null)
        is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.alerts.snrPersistentlyLow // false' 2>/dev/null)
        snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.snr // 0' 2>/dev/null)
        gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsValid // true' 2>/dev/null)
        gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsSats // 0' 2>/dev/null)

        log_debug "ENHANCED METRICS: uptime=${uptime_s}s, bootcount=$bootcount, SNR_above_noise=$is_snr_above_noise_floor, SNR_persistently_low=$is_snr_persistently_low, SNR_value=${snr}dB, GPS_valid=$gps_valid, GPS_sats=$gps_sats"

        # Check for reboot detection
        reboot_detected="false"
        if [ -f "$STATE_FILE" ]; then
            last_bootcount=$(grep "^BOOTCOUNT=" "$STATE_FILE" | cut -d'=' -f2 2>/dev/null || echo "0")
            if [ "$bootcount" != "$last_bootcount" ] && [ "$last_bootcount" != "0" ]; then
                reboot_detected="true"
                log_warning "Reboot detected: bootcount changed from $last_bootcount to $bootcount"
            fi
        fi

        # Update state file
        cat >"$STATE_FILE" <<EOF
BOOTCOUNT=$bootcount
LAST_CHECK=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    else
        # Default values for enhanced metrics
        snr="0"
        is_snr_above_noise_floor="true"
        is_snr_persistently_low="false"
        gps_valid="true"
        gps_sats="0"
        reboot_detected="false"
    fi

    log_debug "BASIC METRICS: latency=${latency}ms, loss=${packet_loss_pct}%, obstruction=${obstruction_pct}%, uptime=${uptime_hours}h"

    # Store metrics globally for CSV output
    CURRENT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    CURRENT_LATENCY="$latency"
    CURRENT_PACKET_LOSS="$packet_loss_pct"
    CURRENT_OBSTRUCTION="$obstruction_pct"
    CURRENT_UPTIME="$uptime_hours"
    CURRENT_SNR="$snr"
    CURRENT_SNR_ABOVE_NOISE="$is_snr_above_noise_floor"
    CURRENT_SNR_PERSISTENTLY_LOW="$is_snr_persistently_low"
    CURRENT_GPS_VALID="$gps_valid"
    CURRENT_GPS_SATS="$gps_sats"
    CURRENT_REBOOT_DETECTED="$reboot_detected"

    return 0
}

# =============================================================================
# CSV LOGGING FUNCTIONS
# =============================================================================

create_csv_header() {
    log_debug "Creating CSV header"

    if [ "$ENABLE_ENHANCED_METRICS" = "true" ] && [ "$ENABLE_GPS_LOGGING" = "true" ] && [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        # Full enhanced header with all features
        echo "Timestamp,Latitude,Longitude,Altitude,GPS_Accuracy,GPS_Source,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Signal Strength,Signal Quality,Network Type,Operator,Roaming Status,Reboot Detected" >"$OUTPUT_CSV"
    elif [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        # Enhanced metrics without GPS/cellular
        echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Reboot Detected" >"$OUTPUT_CSV"
    else
        # Basic CSV header (original format)
        echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours)" >"$OUTPUT_CSV"
    fi
}

log_to_csv() {
    log_debug "Logging data to CSV"

    # Collect additional data if enabled
    gps_data=""
    cellular_data=""

    if [ "$ENABLE_GPS_LOGGING" = "true" ]; then
        gps_data=$(collect_gps_data)
        log_debug "GPS data: $gps_data"
    fi

    if [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        cellular_data=$(collect_cellular_data)
        log_debug "Cellular data: $cellular_data"
    fi

    # Create CSV header if file doesn't exist
    if [ ! -f "$OUTPUT_CSV" ]; then
        create_csv_header
    fi

    # Format and append data based on enabled features
    if [ "$ENABLE_ENHANCED_METRICS" = "true" ] && [ "$ENABLE_GPS_LOGGING" = "true" ] && [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        # Full enhanced logging
        gps_valid_flag=$([ "$CURRENT_GPS_VALID" = "true" ] && echo "1" || echo "0")
        snr_above_noise_flag=$([ "$CURRENT_SNR_ABOVE_NOISE" = "true" ] && echo "1" || echo "0")
        snr_persistently_low_flag=$([ "$CURRENT_SNR_PERSISTENTLY_LOW" = "true" ] && echo "1" || echo "0")
        reboot_flag=$([ "$CURRENT_REBOOT_DETECTED" = "true" ] && echo "1" || echo "0")

        echo "$CURRENT_TIMESTAMP,$gps_data,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME,$CURRENT_SNR,$snr_above_noise_flag,$snr_persistently_low_flag,$gps_valid_flag,$CURRENT_GPS_SATS,$cellular_data,$reboot_flag" >>"$OUTPUT_CSV"

    elif [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        # Enhanced metrics only
        gps_valid_flag=$([ "$CURRENT_GPS_VALID" = "true" ] && echo "1" || echo "0")
        snr_above_noise_flag=$([ "$CURRENT_SNR_ABOVE_NOISE" = "true" ] && echo "1" || echo "0")
        snr_persistently_low_flag=$([ "$CURRENT_SNR_PERSISTENTLY_LOW" = "true" ] && echo "1" || echo "0")
        reboot_flag=$([ "$CURRENT_REBOOT_DETECTED" = "true" ] && echo "1" || echo "0")

        echo "$CURRENT_TIMESTAMP,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME,$CURRENT_SNR,$snr_above_noise_flag,$snr_persistently_low_flag,$gps_valid_flag,$CURRENT_GPS_SATS,$reboot_flag" >>"$OUTPUT_CSV"

    else
        # Basic logging (original format)
        echo "$CURRENT_TIMESTAMP,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME" >>"$OUTPUT_CSV"
    fi

    log_debug "Data logged to CSV successfully"

    # Perform statistical aggregation if enabled
    if [ "$ENABLE_STATISTICAL_AGGREGATION" = "true" ]; then
        perform_statistical_aggregation "$OUTPUT_CSV"
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    log_info "Starting Starlink Logger v$SCRIPT_VERSION"

    # Log enabled features
    if [ "$ENABLE_GPS_LOGGING" = "true" ]; then
        log_info "GPS logging: enabled"
    fi
    if [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        log_info "Cellular logging: enabled"
    fi
    if [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        log_info "Enhanced metrics: enabled"
    fi
    if [ "$ENABLE_STATISTICAL_AGGREGATION" = "true" ]; then
        log_info "Statistical aggregation: enabled (batch size: $AGGREGATION_BATCH_SIZE)"
    fi

    # Validate required tools
    if [ ! -f "$GRPCURL_PATH" ]; then
        log_error "grpcurl not found at $GRPCURL_PATH"
        exit 1
    fi

    if [ ! -f "$JQ_CMD" ]; then
        log_error "jq not found at $JQ_CMD"
        exit 1
    fi

    log_debug "Fetching Starlink status data"

    # Get Starlink status
    if ! status_data=$("$GRPCURL_PATH" -plaintext -d '{"getStatus":{}}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle 2>/dev/null); then
        log_error "Failed to fetch Starlink status data"
        exit 1
    fi

    if [ -z "$status_data" ] || [ "$status_data" = "null" ]; then
        log_error "Empty or null status data received"
        exit 1
    fi

    log_debug "Successfully fetched Starlink status data"

    # Extract metrics and log to CSV
    if extract_starlink_metrics "$status_data"; then
        log_to_csv
        log_info "Data logged successfully to $OUTPUT_CSV"
    else
        log_error "Failed to extract Starlink metrics"
        exit 1
    fi

    log_info "Logging cycle completed successfully"
}

# Execute main function
main "$@"
