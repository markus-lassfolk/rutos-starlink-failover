#!/bin/sh

# === Enhanced Starlink Monitor with Azure Integration ===
# This script extends the existing starlink_monitor.sh to include Azure logging
# It collects performance data in CSV format and ships it to Azure alongside system logs

# Source the main config if it exists

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
if [ -f "/etc/starlink-config/config.sh" ]; then
    # Load configuration from persistent location
    # shellcheck disable=SC1091  # Don't follow dynamic config file
    . "/etc/starlink-config/config.sh"
fi

# --- AZURE INTEGRATION CONFIGURATION ---
# Read configuration from UCI if available, otherwise use defaults
AZURE_INTEGRATION_ENABLED=$(uci get azure.starlink.enabled 2>/dev/null || echo "false")
AZURE_FUNCTION_URL=$(uci get azure.starlink.endpoint 2>/dev/null || echo "")

# Local CSV log file for performance data
CSV_LOG_FILE=$(uci get azure.starlink.csv_file 2>/dev/null || echo "/overlay/starlink_performance.csv")
CSV_MAX_SIZE=$(uci get azure.starlink.max_size 2>/dev/null || echo "1048576") # 1MB default

# --- STARLINK API CONFIGURATION ---
STARLINK_IP=$(uci get azure.starlink.starlink_ip 2>/dev/null || echo "192.168.100.1:9200")
GRPCURL_CMD="${GRPCURL_CMD:-/root/grpcurl}"
JQ_PATH="${JQ_PATH:-/root/jq}"

# --- RUTOS GPS CONFIGURATION ---
# These should match the config from the main repository
RUTOS_IP=$(uci get azure.gps.rutos_ip 2>/dev/null || echo "192.168.80.1")
RUTOS_USERNAME=$(uci get azure.gps.rutos_username 2>/dev/null || echo "")
RUTOS_PASSWORD=$(uci get azure.gps.rutos_password 2>/dev/null || echo "")
# shellcheck disable=SC2034  # GPS_ACCURACY_THRESHOLD may be used for future GPS filtering
GPS_ACCURACY_THRESHOLD=$(uci get azure.gps.accuracy_threshold 2>/dev/null || echo "100")

# Exit if Starlink monitoring is disabled
if [ "$AZURE_INTEGRATION_ENABLED" != "true" ] && [ "$AZURE_INTEGRATION_ENABLED" != "1" ]; then
    exit 0
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    echo "[DEBUG] DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    echo "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution" >&2
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY-RUN] Would execute: $description"
        echo "[DRY-RUN] Command: $cmd" >&2
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# --- LOGGING FUNCTIONS ---
log_info() {
    logger -t "starlink-azure-monitor" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

log_error() {
    logger -t "starlink-azure-monitor" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
}

# --- CSV HEADER INITIALIZATION ---
initialize_csv() {
    if [ ! -f "$CSV_LOG_FILE" ]; then
        cat >"$CSV_LOG_FILE" <<EOF
timestamp,uptime_s,downlink_throughput_bps,uplink_throughput_bps,ping_drop_rate,ping_latency_ms,obstruction_duration_s,obstruction_fraction,currently_obstructed,snr,alerts_thermal_throttle,alerts_thermal_shutdown,alerts_mast_not_near_vertical,alerts_motors_stuck,alerts_slow_ethernet_speeds,alerts_software_install_pending,dishy_state,mobility_class,latitude,longitude,altitude_m,speed_kmh,heading_deg,gps_source,gps_satellites,gps_accuracy_m
EOF
        log_info "Initialized CSV log file with GPS support: $CSV_LOG_FILE"
    fi
}

# --- GPS DATA COLLECTION ---
collect_gps_data() {
    gps_data=""
    gps_source="none"

    # Try RUTOS GPS first (if available)
    if [ -f "/tmp/gps_data" ] || command -v gpspipe >/dev/null 2>&1; then
        gps_data=$(collect_rutos_gps)
        if [ -n "$gps_data" ]; then
            gps_source="rutos"
            echo "$gps_data,$gps_source"
            return 0
        fi
    fi

    # Fallback to Starlink GPS if RUTOS GPS unavailable
    gps_data=$(collect_starlink_gps)
    if [ -n "$gps_data" ]; then
        gps_source="starlink"
        echo "$gps_data,$gps_source"
        return 0
    fi

    # No GPS data available
    echo ",,,,,,0,"
}

collect_rutos_gps() {
    latitude longitude altitude speed heading satellites accuracy

    # Method 1: Try RUTOS API (consistent with VenusOS GPS flow)
    if [ -n "${RUTOS_IP:-}" ] && [ -n "${RUTOS_USERNAME:-}" ] && [ -n "${RUTOS_PASSWORD:-}" ]; then
        # Get session token
        session_token
        session_token=$(curl -s --max-time 5 -X POST \
            "https://${RUTOS_IP}/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$RUTOS_USERNAME\",\"password\":\"$RUTOS_PASSWORD\"}" \
            --insecure 2>/dev/null | "$JQ_PATH" -r '.token // ""' 2>/dev/null)

        if [ -n "$session_token" ] && [ "$session_token" != "null" ]; then
            # Get GPS data using API
            gps_response
            gps_response=$(curl -s --max-time 5 \
                "https://${RUTOS_IP}/api/gps/position/status" \
                -H "Authorization: Bearer $session_token" \
                --insecure 2>/dev/null)

            if [ -n "$gps_response" ]; then
                gps_data
                gps_data=$(echo "$gps_response" | "$JQ_PATH" -r '.data // ""' 2>/dev/null)

                if [ -n "$gps_data" ] && [ "$gps_data" != "null" ]; then
                    latitude=$(echo "$gps_data" | "$JQ_PATH" -r '.latitude // ""' 2>/dev/null)
                    longitude=$(echo "$gps_data" | "$JQ_PATH" -r '.longitude // ""' 2>/dev/null)
                    altitude=$(echo "$gps_data" | "$JQ_PATH" -r '.altitude // ""' 2>/dev/null)
                    speed=$(echo "$gps_data" | "$JQ_PATH" -r '.speed // ""' 2>/dev/null)
                    satellites=$(echo "$gps_data" | "$JQ_PATH" -r '.satellites // ""' 2>/dev/null)
                    accuracy=$(echo "$gps_data" | "$JQ_PATH" -r '.accuracy // ""' 2>/dev/null)

                    # Check fix status (consistent with VenusOS flow)
                    fix_status
                    fix_status=$(echo "$gps_data" | "$JQ_PATH" -r '.fix_status // "0"' 2>/dev/null)

                    if [ "$fix_status" != "0" ] && [ -n "$latitude" ] && [ -n "$longitude" ]; then
                        # Speed is typically in km/h from RUTOS API
                        if [ -n "$speed" ] && [ "$speed" != "null" ] && [ "$speed" != "" ]; then
                            # Ensure speed is numeric
                            speed=$(echo "$speed" | grep -E '^[0-9]*\.?[0-9]+$' || echo "")
                        else
                            speed=""
                        fi

                        # Calculate heading if not provided (placeholder for future enhancement)
                        heading=""

                        echo "$latitude,$longitude,$altitude,$speed,$heading,$satellites,$accuracy"
                        return 0
                    fi
                fi
            fi
        fi
    fi

    # Method 2: Try gpsd/gpspipe if available
    if command -v gpspipe >/dev/null 2>&1; then
        gps_json
        gps_json=$(timeout 5 gpspipe -w -n 10 2>/dev/null | head -n 1)

        if [ -n "$gps_json" ] && echo "$gps_json" | grep -q '"class":"TPV"'; then
            latitude=$(echo "$gps_json" | "$JQ_PATH" -r '.lat // ""' 2>/dev/null)
            longitude=$(echo "$gps_json" | "$JQ_PATH" -r '.lon // ""' 2>/dev/null)
            altitude=$(echo "$gps_json" | "$JQ_PATH" -r '.alt // ""' 2>/dev/null)
            speed=$(echo "$gps_json" | "$JQ_PATH" -r '.speed // ""' 2>/dev/null)
            heading=$(echo "$gps_json" | "$JQ_PATH" -r '.track // ""' 2>/dev/null)

            # Convert speed from m/s to km/h if available
            if [ -n "$speed" ] && [ "$speed" != "null" ]; then
                speed=$(echo "$speed * 3.6" | bc 2>/dev/null || echo "$speed")
            fi

            # Get satellite info
            sky_json
            sky_json=$(timeout 3 gpspipe -w -n 5 2>/dev/null | grep '"class":"SKY"' | head -n 1)
            if [ -n "$sky_json" ]; then
                satellites=$(echo "$sky_json" | "$JQ_PATH" -r '.satellites | length' 2>/dev/null)
            fi

            if [ -n "$latitude" ] && [ -n "$longitude" ]; then
                echo "$latitude,$longitude,$altitude,$speed,$heading,$satellites,$accuracy"
                return 0
            fi
        fi
    fi

    # Method 2: Try RUTOS UCI GPS configuration
    if [ -z "$latitude" ] && command -v uci >/dev/null 2>&1; then
        # Check if GPS is configured in UCI
        gps_enabled
        gps_enabled=$(uci get gps.gps.enabled 2>/dev/null)

        if [ "$gps_enabled" = "1" ]; then
            # Try to read GPS data from RUTOS GPS interface
            if [ -f "/tmp/gps_data" ]; then
                gps_line
                gps_line=$(tail -n 1 /tmp/gps_data 2>/dev/null)

                # Parse NMEA format if available
                if echo "$gps_line" | grep -q "GPGGA\|GPRMC"; then
                    latitude=$(echo "$gps_line" | awk -F',' '{print $3}' | sed 's/[^0-9.-]//g')
                    longitude=$(echo "$gps_line" | awk -F',' '{print $5}' | sed 's/[^0-9.-]//g')
                    altitude=$(echo "$gps_line" | awk -F',' '{print $9}' | sed 's/[^0-9.-]//g')
                fi
            fi
        fi
    fi

    # Method 3: Try reading from common GPS device files
    if [ -z "$latitude" ]; then
        for gps_device in /dev/ttyUSB* /dev/ttyACM*; do
            if [ -c "$gps_device" ]; then
                nmea_data
                nmea_data=$(timeout 3 cat "$gps_device" 2>/dev/null | head -n 5 | grep "GPGGA\|GPRMC" | head -n 1)

                if [ -n "$nmea_data" ]; then
                    # Parse basic NMEA data
                    if echo "$nmea_data" | grep -q "GPGGA"; then
                        latitude=$(echo "$nmea_data" | awk -F',' '{print $3}')
                        longitude=$(echo "$nmea_data" | awk -F',' '{print $5}')
                        altitude=$(echo "$nmea_data" | awk -F',' '{print $10}')
                        satellites=$(echo "$nmea_data" | awk -F',' '{print $8}')
                    fi
                    break
                fi
            fi
        done
    fi

    # Format and validate GPS data
    if [ -n "$latitude" ] && [ -n "$longitude" ] && [ "$latitude" != "" ] && [ "$longitude" != "" ]; then
        # Convert NMEA format to decimal degrees if needed
        latitude=$(convert_nmea_to_decimal "$latitude")
        longitude=$(convert_nmea_to_decimal "$longitude")

        # Default values for missing data
        altitude=${altitude:-""}
        speed=${speed:-""}
        heading=${heading:-""}
        satellites=${satellites:-"0"}
        accuracy="5" # Estimated accuracy for RUTOS GPS

        echo "$latitude,$longitude,$altitude,$speed,$heading,$satellites,$accuracy"
        return 0
    fi

    return 1
}

collect_starlink_gps() {
    latitude longitude altitude speed heading satellites accuracy

    # Use get_diagnostics to get location data (consistent with VenusOS GPS flow)
    diagnostics_data
    diagnostics_data=$(timeout 10 "$GRPCURL_CMD" -plaintext -max-time 10 \
        -d '{"get_diagnostics":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null |
        "$JQ_PATH" -r '.dishGetDiagnostics // ""' 2>/dev/null)

    if [ -n "$diagnostics_data" ] && [ "$diagnostics_data" != "null" ]; then
        # Extract location data from diagnostics
        location_data
        location_data=$(echo "$diagnostics_data" | "$JQ_PATH" -r '.location // ""' 2>/dev/null)

        if [ -n "$location_data" ] && [ "$location_data" != "null" ]; then
            latitude=$(echo "$location_data" | "$JQ_PATH" -r '.latitude // ""' 2>/dev/null)
            longitude=$(echo "$location_data" | "$JQ_PATH" -r '.longitude // ""' 2>/dev/null)
            altitude=$(echo "$location_data" | "$JQ_PATH" -r '.altitudeMeters // ""' 2>/dev/null)

            # Check if location data is valid
            if [ -n "$latitude" ] && [ -n "$longitude" ] && [ "$latitude" != "null" ] && [ "$longitude" != "null" ]; then
                # Get accuracy from uncertainty meters (consistent with VenusOS flow)
                uncertainty_valid
                uncertainty_valid=$(echo "$location_data" | "$JQ_PATH" -r '.uncertaintyMetersValid // false' 2>/dev/null)

                if [ "$uncertainty_valid" = "true" ]; then
                    accuracy=$(echo "$location_data" | "$JQ_PATH" -r '.uncertaintyMeters // ""' 2>/dev/null)
                else
                    # Default accuracy for Starlink when uncertainty not available
                    accuracy=""
                fi

                # Try to get GPS stats for satellite count from status
                status_data gps_stats
                status_data=$(timeout 5 "$GRPCURL_CMD" -plaintext -max-time 5 \
                    -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null |
                    "$JQ_PATH" -r '.dishGetStatus // ""' 2>/dev/null)

                if [ -n "$status_data" ] && [ "$status_data" != "null" ]; then
                    gps_stats=$(echo "$status_data" | "$JQ_PATH" -r '.gpsStats // ""' 2>/dev/null)
                    if [ -n "$gps_stats" ] && [ "$gps_stats" != "null" ]; then
                        satellites=$(echo "$gps_stats" | "$JQ_PATH" -r '.gpsSats // ""' 2>/dev/null)
                    fi
                fi

                # Starlink doesn't provide speed/heading in location API, leave empty
                speed=""
                heading=""

                echo "$latitude,$longitude,$altitude,$speed,$heading,$satellites,$accuracy"
                return 0
            fi
        fi
    fi

    # Return empty if no valid GPS data
    return 1
}

convert_nmea_to_decimal() {
    nmea_coord="$1"

    # Check if already in decimal format
    if echo "$nmea_coord" | grep -q "^-\?[0-9]\+\.[0-9]\+$"; then
        echo "$nmea_coord"
        return
    fi

    # Convert NMEA DDMM.MMMM format to decimal degrees
    if [ ${#nmea_coord} -ge 7 ]; then
        degrees minutes decimal
        degrees=$(echo "$nmea_coord" | cut -c1-2)
        minutes=$(echo "$nmea_coord" | cut -c3-)

        # Convert to decimal degrees: DD + MM.MMMM/60
        decimal=$(echo "scale=6; $degrees + $minutes/60" | bc 2>/dev/null)
        echo "$decimal"
    else
        echo "$nmea_coord"
    fi
}

# --- STARLINK DATA COLLECTION ---
collect_starlink_data() {
    timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Query Starlink API for status data
    if ! command -v "$GRPCURL_CMD" >/dev/null 2>&1; then
        log_error "grpcurl not found at $GRPCURL_CMD"
        return 1
    fi

    if ! command -v "$JQ_PATH" >/dev/null 2>&1; then
        log_error "jq not found at $JQ_PATH"
        return 1
    fi

    # Get status data from Starlink
    status_json
    status_json=$("$GRPCURL_CMD" -plaintext -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null)

    if ! "$GRPCURL_CMD" -plaintext -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle >/dev/null 2>&1 || [ -z "$status_json" ]; then
        log_error "Failed to get Starlink status data"
        return 1
    fi

    # Extract metrics using jq
    uptime_s downlink_throughput_bps uplink_throughput_bps ping_drop_rate ping_latency_ms
    obstruction_duration_s obstruction_fraction currently_obstructed snr
    alerts_thermal_throttle alerts_thermal_shutdown alerts_mast_not_near_vertical
    alerts_motors_stuck alerts_slow_ethernet_speeds alerts_software_install_pending
    dishy_state mobility_class

    uptime_s=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.deviceInfo.uptimeS // "0"')
    downlink_throughput_bps=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.downlinkThroughputBps // "0"')
    uplink_throughput_bps=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.uplinkThroughputBps // "0"')
    ping_drop_rate=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.popPingDropRate // "0"')
    ping_latency_ms=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.popPingLatencyMs // "0"')
    obstruction_duration_s=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.obstructionStats.fractionObstructedRecently // "0"')
    obstruction_fraction=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.obstructionStats.fractionObstructed // "0"')
    currently_obstructed=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.obstructionStats.currentlyObstructed // false')
    snr=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.snr // "0"')

    # Extract alerts
    alerts_thermal_throttle=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.thermalThrottle // false')
    alerts_thermal_shutdown=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.thermalShutdown // false')
    alerts_mast_not_near_vertical=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.mastNotNearVertical // false')
    alerts_motors_stuck=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.motorsStuck // false')
    alerts_slow_ethernet_speeds=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.slowEthernetSpeeds // false')
    alerts_software_install_pending=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.alerts.softwareInstallPending // false')

    dishy_state=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.state // "UNKNOWN"')
    mobility_class=$(echo "$status_json" | "$JQ_PATH" -r '.dishGetStatus.mobilityClass // "UNKNOWN"')

    # Collect GPS data (RUTOS GPS with Starlink fallback)
    gps_data
    gps_data=$(collect_gps_data)

    # Append to CSV with GPS data
    cat >>"$CSV_LOG_FILE" <<EOF
$timestamp,$uptime_s,$downlink_throughput_bps,$uplink_throughput_bps,$ping_drop_rate,$ping_latency_ms,$obstruction_duration_s,$obstruction_fraction,$currently_obstructed,$snr,$alerts_thermal_throttle,$alerts_thermal_shutdown,$alerts_mast_not_near_vertical,$alerts_motors_stuck,$alerts_slow_ethernet_speeds,$alerts_software_install_pending,$dishy_state,$mobility_class,$gps_data
EOF

    log_info "Collected Starlink performance data with GPS information"
    return 0
}

# --- CSV LOG ROTATION ---
rotate_csv_if_needed() {
    if [ ! -f "$CSV_LOG_FILE" ]; then
        return 0
    fi

    file_size
    file_size=$(stat -c%s "$CSV_LOG_FILE" 2>/dev/null || echo "0")

    if [ "$file_size" -gt "$CSV_MAX_SIZE" ]; then
        backup_file
        backup_file="${CSV_LOG_FILE}.$(date +%Y%m%d-%H%M%S)"
        mv "$CSV_LOG_FILE" "$backup_file"
        log_info "Rotated CSV log file to $backup_file"
        initialize_csv
    fi
}

# --- AZURE INTEGRATION ---
ship_csv_to_azure() {
    if [ "$AZURE_INTEGRATION_ENABLED" != "true" ] || [ -z "$AZURE_FUNCTION_URL" ]; then
        return 0
    fi

    if [ ! -f "$CSV_LOG_FILE" ] || [ ! -s "$CSV_LOG_FILE" ]; then
        return 0
    fi

    # Create a temporary file with CSV data for Azure
    temp_csv
    temp_csv="/tmp/starlink_csv_$(date +%s).csv"
    cp "$CSV_LOG_FILE" "$temp_csv"

    # Send CSV data to Azure with a special header to identify it as CSV data
    http_status
    http_status=$(curl -sS -w '%{http_code}' -o /dev/null --max-time 30 \
        -H "Content-Type: text/csv" \
        -H "X-Log-Type: starlink-performance" \
        --data-binary "@$temp_csv" \
        "$AZURE_FUNCTION_URL" 2>/dev/null)

    curl_exit_code=$?
    rm -f "$temp_csv"

    if [ $curl_exit_code -eq 0 ] && [ "$http_status" -eq 200 ]; then
        log_info "Successfully shipped CSV data to Azure"
        # Clear the CSV file after successful upload
        initialize_csv
        return 0
    else
        log_error "Failed to ship CSV data to Azure (HTTP: $http_status, curl: $curl_exit_code)"
        return 1
    fi
}

# --- MAIN EXECUTION ---
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "starlink-azure-monitor-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: starlink-azure-monitor-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    log_info "Starting enhanced Starlink monitoring with Azure integration"

    # Initialize CSV file if needed
    initialize_csv

    # Collect Starlink performance data
    if collect_starlink_data; then
        log_info "Starlink data collection successful"
    else
        log_error "Starlink data collection failed"
        exit 1
    fi

    # Ship to Azure if enabled
    if [ "$AZURE_INTEGRATION_ENABLED" = "true" ]; then
        ship_csv_to_azure
    fi

    # Rotate CSV if it's getting too large
    rotate_csv_if_needed

    log_info "Enhanced Starlink monitoring cycle completed"
}

# Execute main function
main "$@"
