#!/bin/sh
# ==============================================================================
# RUTOS Data Collection Library
#
# Standardized GPS and cellular data collection functions for RUTOS environment.
# Ensures consistent data format, CSV sanitization, and cross-script compatibility.
#
# Functions provided:
# - collect_gps_data()     - GPS location data collection with source priority
# - collect_cellular_data() - Cellular modem data collection with AT commands
# - validate_gps_coordinates() - GPS coordinate validation helper
# - sanitize_csv_field()   - CSV field sanitization helper
# ==============================================================================

# Prevent multiple sourcing

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
if [ "${_RUTOS_DATA_COLLECTION_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_DATA_COLLECTION_LOADED=1

# =============================================================================
# CSV DATA SANITIZATION HELPER
# =============================================================================

# Sanitize a field for CSV output (removes problematic characters)
sanitize_csv_field() {
    field_value="$1"
    max_length="${2:-50}"

    # Remove newlines, carriage returns, and commas that could break CSV format
    cleaned_value=$(echo "$field_value" | tr -d '\n\r,' | head -c "$max_length")

    # Handle empty fields
    if [ -z "$cleaned_value" ]; then
        cleaned_value="Unknown"
    fi

    printf "%s" "$cleaned_value"
}

# =============================================================================
# GPS COORDINATE VALIDATION HELPER
# =============================================================================

# Validate GPS coordinates for reasonable values
validate_gps_coordinates() {
    lat="$1"
    lon="$2"

    # Check if values are empty or zero
    case "$lat" in
        "" | 0 | 0.0 | 0.00 | 0.000 | 0.0000 | 0.00000 | 0.000000) return 1 ;;
        *[!0-9.-]*) return 1 ;; # Contains non-numeric characters
    esac

    case "$lon" in
        "" | 0 | 0.0 | 0.00 | 0.000 | 0.0000 | 0.00000 | 0.000000) return 1 ;;
        *[!0-9.-]*) return 1 ;; # Contains non-numeric characters
    esac

    # Basic range validation (latitude: -90 to 90, longitude: -180 to 180)
    # Using awk for floating point comparison
    lat_valid=$(awk "BEGIN { print ($lat >= -90 && $lat <= 90) }" 2>/dev/null)
    lon_valid=$(awk "BEGIN { print ($lon >= -180 && $lon <= 180) }" 2>/dev/null)

    [ "$lat_valid" = "1" ] && [ "$lon_valid" = "1" ]
}

# =============================================================================
# GPS DATA COLLECTION (Standardized)
# Supports multiple GPS sources with configurable priority
# =============================================================================

collect_gps_data() {
    # Configuration parameters (can be set by calling script)
    gps_enabled="${ENABLE_GPS_LOGGING:-false}"
    primary_source="${GPS_PRIMARY_SOURCE:-starlink}"
    secondary_source="${GPS_SECONDARY_SOURCE:-rutos}"

    # Skip if GPS logging is disabled
    if [ "$gps_enabled" != "true" ]; then
        log_debug "📍 GPS COLLECTION: GPS logging disabled (ENABLE_GPS_LOGGING=$gps_enabled), returning default values"
        printf "0,0,0,none,none"
        return 0
    fi

    log_debug "📍 GPS COLLECTION: Starting GPS data collection from available sources"
    log_debug "📍 GPS CONFIG: PRIMARY_SOURCE=$primary_source, SECONDARY_SOURCE=$secondary_source"

    lat="" lon="" alt="" accuracy="" source=""
    rutos_lat="" rutos_lon="" rutos_alt=""
    starlink_lat="" starlink_lon="" starlink_alt=""

    # === RUTOS GPS Collection ===
    log_debug "📍 RUTOS GPS: Attempting to collect RUTOS GPS data..."
    if command -v gpsctl >/dev/null 2>&1; then
        log_debug "📍 RUTOS GPS: gpsctl command found, using individual flags for data collection"

        # Use individual gpsctl flags for each GPS parameter
        rutos_lat=$(gpsctl -i 2>/dev/null | tr -d '\n\r' || echo "")
        rutos_lon=$(gpsctl -x 2>/dev/null | tr -d '\n\r' || echo "")
        rutos_alt=$(gpsctl -a 2>/dev/null | tr -d '\n\r' || echo "")

        log_debug "📍 RUTOS GPS: Individual flag results - lat='$rutos_lat', lon='$rutos_lon', alt='$rutos_alt'"

        # Validate GPS data using helper function
        if validate_gps_coordinates "$rutos_lat" "$rutos_lon"; then
            log_debug "📍 RUTOS GPS: Valid GPS coordinates found - lat=$rutos_lat, lon=$rutos_lon"
            # Set default altitude if empty or invalid
            case "$rutos_alt" in
                *[!0-9.-]* | "") rutos_alt="0" ;;
            esac
        else
            log_debug "📍 RUTOS GPS: Invalid or zero GPS coordinates from gpsctl"
            rutos_lat="" rutos_lon="" rutos_alt=""
        fi
    else
        log_debug "📍 RUTOS GPS: gpsctl command not available"
    fi

    # === Starlink GPS Collection ===
    log_debug "📍 STARLINK GPS: Attempting to collect Starlink GPS data..."
    if [ -n "${status_data:-}" ]; then
        log_debug "📍 STARLINK GPS: status_data available, trying different field paths"

        # Require external dependencies (JQ_CMD, GRPCURL_CMD, STARLINK_IP, STARLINK_PORT)
        if [ -z "${JQ_CMD:-}" ] || [ ! -f "${JQ_CMD:-}" ]; then
            log_debug "📍 STARLINK GPS: jq command not available, skipping Starlink GPS"
        else
            # Try multiple possible field paths for GPS location
            starlink_lat=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.location.lla.lat // .location.lla.lat // .getLocation.lla.lat // empty' 2>/dev/null)
            starlink_lon=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.location.lla.lon // .location.lla.lon // .getLocation.lla.lon // empty' 2>/dev/null)
            starlink_alt=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.location.lla.alt // .location.lla.alt // .getLocation.lla.alt // 0' 2>/dev/null)

            log_debug "📍 STARLINK GPS: Field extraction results - lat=$starlink_lat, lon=$starlink_lon, alt=$starlink_alt"

            if validate_gps_coordinates "$starlink_lat" "$starlink_lon"; then
                log_debug "📍 STARLINK GPS: Valid GPS data found in get_status response"
            else
                log_debug "📍 STARLINK GPS: No location data in get_status, trying separate get_location API call"

                # Try get_location API for more accurate coordinates (higher precision)
                if [ -n "${GRPCURL_CMD:-}" ] && [ -f "${GRPCURL_CMD:-}" ] && [ -n "${STARLINK_IP:-}" ] && [ -n "${STARLINK_PORT:-}" ]; then
                    location_cmd="$GRPCURL_CMD -plaintext -d '{\"get_location\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"
                    log_debug "📍 STARLINK GPS: Executing get_location API call for high-precision coordinates"

                    if location_data=$(eval "$location_cmd" 2>/dev/null); then
                        log_debug "📍 STARLINK GPS: get_location API call successful"
                        starlink_lat=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lat // empty' 2>/dev/null)
                        starlink_lon=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lon // empty' 2>/dev/null)
                        starlink_alt=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.alt // 0' 2>/dev/null)
                        log_debug "📍 STARLINK GPS: get_location high-precision results - lat=$starlink_lat, lon=$starlink_lon, alt=$starlink_alt"

                        if ! validate_gps_coordinates "$starlink_lat" "$starlink_lon"; then
                            log_debug "📍 STARLINK GPS: Invalid coordinates from get_location, trying get_diagnostics"

                            # Fallback to get_diagnostics for location data
                            diag_cmd="$GRPCURL_CMD -plaintext -d '{\"get_diagnostics\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"
                            log_debug "📍 STARLINK GPS: Trying get_diagnostics as fallback"

                            if diag_data=$(eval "$diag_cmd" 2>/dev/null); then
                                starlink_lat=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.latitude // empty' 2>/dev/null)
                                starlink_lon=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.longitude // empty' 2>/dev/null)
                                starlink_alt=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.altitudeMeters // 0' 2>/dev/null)
                                log_debug "📍 STARLINK GPS: get_diagnostics results - lat=$starlink_lat, lon=$starlink_lon, alt=$starlink_alt"

                                if ! validate_gps_coordinates "$starlink_lat" "$starlink_lon"; then
                                    log_debug "📍 STARLINK GPS: No valid coordinates from get_diagnostics either"
                                    starlink_lat="" starlink_lon="" starlink_alt=""
                                fi
                            else
                                log_debug "📍 STARLINK GPS: get_diagnostics API call failed"
                                starlink_lat="" starlink_lon="" starlink_alt=""
                            fi
                        else
                            log_debug "📍 STARLINK GPS: High-precision coordinates validated successfully"
                        fi
                    else
                        log_debug "📍 STARLINK GPS: get_location API call failed, trying get_diagnostics"

                        # Try get_diagnostics if get_location fails
                        diag_cmd="$GRPCURL_CMD -plaintext -d '{\"get_diagnostics\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

                        if diag_data=$(eval "$diag_cmd" 2>/dev/null); then
                            starlink_lat=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.latitude // empty' 2>/dev/null)
                            starlink_lon=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.longitude // empty' 2>/dev/null)
                            starlink_alt=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.altitudeMeters // 0' 2>/dev/null)
                            log_debug "📍 STARLINK GPS: get_diagnostics fallback results - lat=$starlink_lat, lon=$starlink_lon, alt=$starlink_alt"

                            if ! validate_gps_coordinates "$starlink_lat" "$starlink_lon"; then
                                log_debug "📍 STARLINK GPS: No valid coordinates available from any Starlink API"
                                starlink_lat="" starlink_lon="" starlink_alt=""
                            fi
                        else
                            log_debug "📍 STARLINK GPS: All Starlink GPS API calls failed"
                            starlink_lat="" starlink_lon="" starlink_alt=""
                        fi
                    fi
                else
                    log_debug "📍 STARLINK GPS: Required tools for Starlink GPS API not available"
                    starlink_lat="" starlink_lon="" starlink_alt=""
                fi
            fi
        fi
    else
        log_debug "📍 STARLINK GPS: No status_data available for GPS extraction"
    fi

    # === GPS Source Priority Logic ===
    log_debug "📍 GPS PRIORITY: Applying GPS source priority logic"
    log_debug "📍 GPS SOURCES: RUTOS=[${rutos_lat:-empty}], STARLINK=[${starlink_lat:-empty}]"

    log_debug "📍 GPS PRIORITY: Primary=$primary_source, Secondary=$secondary_source"

    # Apply primary source preference
    if [ "$primary_source" = "starlink" ] && [ -n "$starlink_lat" ]; then
        lat="$starlink_lat"
        lon="$starlink_lon"
        alt="${starlink_alt:-0}"
        accuracy="high"
        source="starlink_gps"
        log_debug "📍 GPS SELECTION: Using PRIMARY source (Starlink): lat=$lat, lon=$lon"
    elif [ "$primary_source" = "rutos" ] && [ -n "$rutos_lat" ]; then
        lat="$rutos_lat"
        lon="$rutos_lon"
        alt="${rutos_alt:-0}"
        accuracy="high"
        source="rutos_gps"
        log_debug "📍 GPS SELECTION: Using PRIMARY source (RUTOS): lat=$lat, lon=$lon"
    # Fallback to secondary source
    elif [ "$secondary_source" = "starlink" ] && [ -n "$starlink_lat" ]; then
        lat="$starlink_lat"
        lon="$starlink_lon"
        alt="${starlink_alt:-0}"
        accuracy="medium"
        source="starlink_gps"
        log_debug "📍 GPS SELECTION: Using SECONDARY source (Starlink): lat=$lat, lon=$lon"
    elif [ "$secondary_source" = "rutos" ] && [ -n "$rutos_lat" ]; then
        lat="$rutos_lat"
        lon="$rutos_lon"
        alt="${rutos_alt:-0}"
        accuracy="medium"
        source="rutos_gps"
        log_debug "📍 GPS SELECTION: Using SECONDARY source (RUTOS): lat=$lat, lon=$lon"
    else
        log_debug "📍 GPS SELECTION: No valid GPS data from any source"
    fi

    # Set defaults if no GPS data available
    lat="${lat:-0}"
    lon="${lon:-0}"
    alt="${alt:-0}"
    accuracy="${accuracy:-none}"
    source="${source:-none}"

    log_debug "📍 GPS FINAL: lat=$lat, lon=$lon, alt=$alt, accuracy=$accuracy, source=$source"

    # Return GPS data for CSV logging
    printf "%s,%s,%s,%s,%s" "$lat" "$lon" "$alt" "$accuracy" "$source"
}

# =============================================================================
# CELLULAR DATA COLLECTION (Standardized)
# Supports comprehensive 4G/5G modem data collection with CSV sanitization
# =============================================================================

collect_cellular_data() {
    # Configuration parameters (can be set by calling script)
    cellular_enabled="${ENABLE_CELLULAR_LOGGING:-false}"
    cellular_enabled="${ENABLE_CELLULAR_TRACKING:-$cellular_enabled}" # Support both naming conventions

    # Skip if cellular logging is disabled
    if [ "$cellular_enabled" != "true" ]; then
        log_debug "📱 CELLULAR: Cellular logging disabled (ENABLE_CELLULAR_LOGGING=$cellular_enabled), returning default values"
        printf "0,0,Unknown,Unknown,home"
        return 0
    fi

    signal_strength="" signal_quality="" network_type="" operator="" roaming_status=""

    log_debug "📱 CELLULAR: Collecting cellular data from primary modem"

    if command -v gsmctl >/dev/null 2>&1; then
        log_debug "📱 CELLULAR: gsmctl command available, executing AT commands"

        # Signal strength and quality
        log_debug "📱 CELLULAR: Getting signal strength with AT+CSQ"
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        log_debug "📱 CELLULAR: Signal info raw: '$signal_info'"
        signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | tr -d '\n\r' | head -1)
        signal_quality=$(echo "$signal_info" | awk -F'[: ,]' '{print $4}' | tr -d '\n\r' | head -1)
        log_debug "📱 CELLULAR: Parsed signal - strength='$signal_strength', quality='$signal_quality'"

        # Network registration and operator
        log_debug "📱 CELLULAR: Getting operator with AT+COPS?"
        reg_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" | head -1 || echo "+COPS: 0,0,\"Unknown\"")
        log_debug "📱 CELLULAR: Operator info raw: '$reg_info'"
        operator_raw=$(echo "$reg_info" | sed 's/.*"\([^"]*\)".*/\1/' | tr -d '\n\r' | head -c 20)
        operator=$(sanitize_csv_field "$operator_raw" 20)
        log_debug "📱 CELLULAR: Parsed operator: '$operator'"

        # Network type
        log_debug "📱 CELLULAR: Getting network type with AT+QNWINFO"
        network_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "+QNWINFO: \"Unknown\"")
        log_debug "📱 CELLULAR: Network info raw: '$network_info'"
        network_type_raw=$(echo "$network_info" | awk -F'"' '{print $2}' | tr -d '\n\r' | head -c 15)
        network_type=$(sanitize_csv_field "$network_type_raw" 15)
        log_debug "📱 CELLULAR: Parsed network type: '$network_type'"

        # Roaming status
        log_debug "📱 CELLULAR: Getting roaming status with AT+CREG?"
        roaming_info=$(gsmctl -A 'AT+CREG?' 2>/dev/null | grep "+CREG:" | head -1 || echo "+CREG: 0,1")
        log_debug "📱 CELLULAR: Roaming info raw: '$roaming_info'"
        roaming_status=$(echo "$roaming_info" | awk -F'[: ,]' '{print $4}' | tr -d '\n\r' | head -1)
        [ "$roaming_status" = "5" ] && roaming_status="roaming" || roaming_status="home"
        log_debug "📱 CELLULAR: Parsed roaming status: '$roaming_status'"

        log_debug "📱 CELLULAR: Final parsed data - signal=$signal_strength, quality=$signal_quality, operator='$operator', network='$network_type', roaming=$roaming_status"
    else
        log_debug "📱 CELLULAR: gsmctl not available, using default cellular values"
    fi

    # Set defaults and clean data if no data available or invalid
    signal_strength="${signal_strength:-0}"
    signal_quality="${signal_quality:-0}"

    # Final sanitization using helper function
    network_type=$(sanitize_csv_field "${network_type:-Unknown}" 15)
    operator=$(sanitize_csv_field "${operator:-Unknown}" 20)

    # Validate roaming status
    case "$roaming_status" in
        roaming | home) ;;
        *) roaming_status="home" ;;
    esac

    log_debug "📱 CELLULAR: Final cleaned data - signal=$signal_strength, quality=$signal_quality, operator='$operator', network='$network_type', roaming=$roaming_status"

    # Return cellular data for CSV logging (ensure no newlines or commas in data)
    printf "%s,%s,%s,%s,%s" "$signal_strength" "$signal_quality" "$network_type" "$operator" "$roaming_status"
}

# =============================================================================
# ENHANCED CELLULAR DATA COLLECTION (For Advanced Monitoring)
# Extended version with additional cellular metrics
# =============================================================================

collect_cellular_data_enhanced() {
    # Configuration parameters
    cellular_enabled="${ENABLE_CELLULAR_LOGGING:-false}"
    cellular_enabled="${ENABLE_CELLULAR_TRACKING:-$cellular_enabled}"

    # Skip if cellular logging is disabled
    if [ "$cellular_enabled" != "true" ]; then
        log_debug "📱 ENHANCED CELLULAR: Cellular logging disabled, returning default values"
        printf "$(date '+%Y-%m-%d %H:%M:%S'),primary,-113,99,Unknown,Unknown,unknown,unknown,0,unknown,0,0,0"
        return 0
    fi

    timestamp="" modem_id="" signal_strength="" signal_quality="" network_type=""
    echo "rutos-data-collection.sh v$SCRIPT_VERSION"
    echo ""
    operator="" roaming_status="" connection_status="" data_usage_mb=""
    frequency_band="" cell_id="" lac="" error_rate=""

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    modem_id="primary"

    if command -v gsmctl >/dev/null 2>&1; then
        log_debug "📱 ENHANCED CELLULAR: gsmctl available, collecting enhanced cellular data"

        # Signal strength and quality
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        signal_rssi=$(echo "$signal_info" | cut -d',' -f1 | cut -d':' -f2 | tr -d ' \n\r')
        signal_ber=$(echo "$signal_info" | cut -d',' -f2 | tr -d ' \n\r')

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
            operator_raw=$(echo "$network_info" | cut -d'"' -f2 | head -1 | tr -d '\n\r,')
            operator=$(sanitize_csv_field "$operator_raw" 20)
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

        # Additional details (simplified for now)
        echo "rutos-data-collection.sh v$SCRIPT_VERSION"
        echo ""
        data_usage_mb="0"
        frequency_band="unknown"
        cell_id="0"
        lac="0"
        error_rate="0"

    else
        log_debug "📱 ENHANCED CELLULAR: gsmctl not available, using default values"
        # Default values when gsmctl not available
        signal_strength="-113"
        signal_quality="99"
        network_type="Unknown"
        operator="Unknown"
        roaming_status="unknown"
        connection_status="unknown"
        echo "rutos-data-collection.sh v$SCRIPT_VERSION"
        echo ""
        data_usage_mb="0"
        frequency_band="unknown"
        cell_id="0"
        lac="0"
        error_rate="0"
    fi

    # Final data sanitization for CSV safety
    operator=$(sanitize_csv_field "$operator" 20)
    network_type=$(sanitize_csv_field "$network_type" 15)
    roaming_status=$(sanitize_csv_field "$roaming_status" 10)
    connection_status=$(sanitize_csv_field "$connection_status" 15)

    log_debug "📱 ENHANCED CELLULAR: Final sanitized data - operator='$operator', network='$network_type'"

    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" \
        "$timestamp" "$modem_id" "$signal_strength" "$signal_quality" \
        "$network_type" "$operator" "$roaming_status" "$connection_status" \
        echo "rutos-data-collection.sh v$SCRIPT_VERSION"
    echo ""
    "$data_usage_mb" "$frequency_band" "$cell_id" "$lac" "$error_rate"
}

# =============================================================================
# STARLINK PACKET DROP RATE CALCULATION
# Calculate popPingDropRate from history when missing from status
# =============================================================================

# Calculate packet drop rate from Starlink history data
calculate_starlink_drop_rate() {
    drop_rate=""

    # Check if required tools are available
    if [ -z "${GRPCURL_CMD:-}" ] || [ ! -f "${GRPCURL_CMD:-}" ] || [ -z "${JQ_CMD:-}" ] || [ ! -f "${JQ_CMD:-}" ]; then
        log_debug "📊 STARLINK DROP RATE: Required tools (grpcurl/jq) not available"
        printf "0"
        return 1
    fi

    if [ -z "${STARLINK_IP:-}" ] || [ -z "${STARLINK_PORT:-}" ]; then
        log_debug "📊 STARLINK DROP RATE: Starlink IP/port not configured"
        printf "0"
        return 1
    fi

    log_debug "📊 STARLINK DROP RATE: Fetching history data to calculate drop rate"

    # Get history data from Starlink API
    history_cmd="$GRPCURL_CMD -plaintext -d '{\"get_history\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

    if history_data=$(eval "$history_cmd" 2>/dev/null); then
        log_debug "📊 STARLINK DROP RATE: History data retrieved successfully"

        # Extract drop rate array from history
        drop_rates=$(echo "$history_data" | "$JQ_CMD" -r '.dishGetHistory.popPingDropRate[]? // empty' 2>/dev/null)

        if [ -n "$drop_rates" ]; then
            log_debug "📊 STARLINK DROP RATE: Found drop rate data in history"

            # Calculate average drop rate from recent samples (last 10 samples)
            drop_rate=$(echo "$drop_rates" | tail -10 | awk '
                BEGIN { sum = 0; count = 0 }
                /^[0-9]*\.?[0-9]+$/ { 
                    sum += $1; count++ 
                }
                END { 
                    if (count > 0) 
                        printf "%.6f", sum/count
                    else 
                        print "0"
                }
            ')

            log_debug "📊 STARLINK DROP RATE: Calculated average drop rate: $drop_rate"
        else
            log_debug "📊 STARLINK DROP RATE: No drop rate data found in history"
            drop_rate="0"
        fi
    else
        log_debug "📊 STARLINK DROP RATE: Failed to retrieve history data"
        drop_rate="0"
    fi

    printf "%s" "${drop_rate:-0}"
}

# Get enhanced Starlink status with calculated drop rate fallback
get_starlink_status_enhanced() {
    status_data=""
    drop_rate=""

    # Check if required tools are available
    if [ -z "${GRPCURL_CMD:-}" ] || [ ! -f "${GRPCURL_CMD:-}" ] || [ -z "${JQ_CMD:-}" ] || [ ! -f "${JQ_CMD:-}" ]; then
        log_debug "📡 STARLINK STATUS: Required tools not available"
        return 1
    fi

    if [ -z "${STARLINK_IP:-}" ] || [ -z "${STARLINK_PORT:-}" ]; then
        log_debug "📡 STARLINK STATUS: Starlink IP/port not configured"
        return 1
    fi

    # Get status data
    status_cmd="$GRPCURL_CMD -plaintext -d '{\"get_status\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

    if status_data=$(eval "$status_cmd" 2>/dev/null); then
        log_debug "📡 STARLINK STATUS: Status data retrieved successfully"

        # Check if popPingDropRate is available in status
        drop_rate=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // empty' 2>/dev/null)

        if [ -z "$drop_rate" ] || [ "$drop_rate" = "null" ]; then
            log_debug "📡 STARLINK STATUS: popPingDropRate missing from status, calculating from history"
            drop_rate=$(calculate_starlink_drop_rate)

            # Add calculated drop rate to status data for consistent processing
            if [ -n "$drop_rate" ] && [ "$drop_rate" != "0" ]; then
                log_debug "📡 STARLINK STATUS: Adding calculated drop rate ($drop_rate) to status data"
                status_data=$(echo "$status_data" | "$JQ_CMD" --arg rate "$drop_rate" '.dishGetStatus.popPingDropRate = ($rate | tonumber)' 2>/dev/null)
            fi
        else
            log_debug "📡 STARLINK STATUS: popPingDropRate found in status: $drop_rate"
        fi

        # Export status data for use by other functions
        STARLINK_STATUS_DATA="$status_data"
        export STARLINK_STATUS_DATA

        printf "%s" "$status_data"
        return 0
    else
        log_debug "📡 STARLINK STATUS: Failed to retrieve status data"
        return 1
    fi
}

# =============================================================================
# ENHANCED GPS DATA COLLECTION WITH DIAGNOSTICS
# Collects GPS data with additional diagnostic information from get_diagnostics
# =============================================================================

collect_gps_data_enhanced() {
    # Configuration parameters
    gps_enabled="${ENABLE_GPS_LOGGING:-false}"
    primary_source="${GPS_PRIMARY_SOURCE:-starlink}"

    # Skip if GPS logging is disabled
    if [ "$gps_enabled" != "true" ]; then
        log_debug "📍 ENHANCED GPS: GPS logging disabled, returning default values"
        printf "0,0,0,none,none,0,0,0"
        return 0
    fi

    log_debug "📍 ENHANCED GPS: Collecting enhanced GPS data with diagnostics"

    lat="" lon="" alt="" accuracy="" source=""
    uncertainty_meters="" gps_time_s="" utc_offset_s=""

    # Try get_diagnostics first (most comprehensive GPS data)
    if [ -n "${GRPCURL_CMD:-}" ] && [ -f "${GRPCURL_CMD:-}" ] && [ -n "${JQ_CMD:-}" ] && [ -f "${JQ_CMD:-}" ]; then
        if [ -n "${STARLINK_IP:-}" ] && [ -n "${STARLINK_PORT:-}" ]; then
            log_debug "📍 ENHANCED GPS: Trying get_diagnostics for comprehensive GPS data"
            diag_cmd="$GRPCURL_CMD -plaintext -d '{\"get_diagnostics\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

            if diag_data=$(eval "$diag_cmd" 2>/dev/null); then
                log_debug "📍 ENHANCED GPS: get_diagnostics API call successful"

                # Extract GPS location data
                lat=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.latitude // empty' 2>/dev/null)
                lon=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.longitude // empty' 2>/dev/null)
                alt=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.altitudeMeters // 0' 2>/dev/null)

                # Extract enhanced GPS diagnostic data
                uncertainty_meters=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.uncertaintyMeters // 0' 2>/dev/null)
                gps_time_s=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.location.gpsTimeS // 0' 2>/dev/null)
                utc_offset_s=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.utcOffsetS // 0' 2>/dev/null)

                log_debug "📍 ENHANCED GPS: Diagnostics GPS data - lat=$lat, lon=$lon, alt=$alt, uncertainty=$uncertainty_meters"

                if validate_gps_coordinates "$lat" "$lon"; then
                    accuracy="high"
                    source="starlink_diagnostics"
                    log_debug "📍 ENHANCED GPS: Valid GPS data from get_diagnostics"
                else
                    log_debug "📍 ENHANCED GPS: Invalid GPS data from get_diagnostics, trying get_location"
                    # Fallback to get_location for high-precision coordinates
                    location_cmd="$GRPCURL_CMD -plaintext -d '{\"get_location\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

                    if location_data=$(eval "$location_cmd" 2>/dev/null); then
                        lat=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lat // empty' 2>/dev/null)
                        lon=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lon // empty' 2>/dev/null)
                        alt=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.alt // 0' 2>/dev/null)

                        if validate_gps_coordinates "$lat" "$lon"; then
                            accuracy="medium"
                            source="starlink_location"
                            log_debug "📍 ENHANCED GPS: Valid GPS data from get_location fallback"
                        else
                            lat="" lon="" alt=""
                        fi
                    fi
                fi
            else
                log_debug "📍 ENHANCED GPS: get_diagnostics API call failed"
            fi
        fi
    fi

    # Fallback to RUTOS GPS if Starlink not available
    if [ -z "$lat" ] && command -v gpsctl >/dev/null 2>&1; then
        log_debug "📍 ENHANCED GPS: Falling back to RUTOS GPS"
        rutos_lat=$(gpsctl -i 2>/dev/null | tr -d '\n\r' || echo "")
        rutos_lon=$(gpsctl -x 2>/dev/null | tr -d '\n\r' || echo "")
        rutos_alt=$(gpsctl -a 2>/dev/null | tr -d '\n\r' || echo "")

        if validate_gps_coordinates "$rutos_lat" "$rutos_lon"; then
            lat="$rutos_lat"
            lon="$rutos_lon"
            alt="${rutos_alt:-0}"
            accuracy="medium"
            source="rutos_gps"
            uncertainty_meters="0"
            gps_time_s="0"
            utc_offset_s="0"
            log_debug "📍 ENHANCED GPS: Using RUTOS GPS fallback"
        fi
    fi

    # Set defaults if no GPS data available
    lat="${lat:-0}"
    lon="${lon:-0}"
    alt="${alt:-0}"
    accuracy="${accuracy:-none}"
    source="${source:-none}"
    uncertainty_meters="${uncertainty_meters:-0}"
    gps_time_s="${gps_time_s:-0}"
    utc_offset_s="${utc_offset_s:-0}"

    log_debug "📍 ENHANCED GPS FINAL: lat=$lat, lon=$lon, alt=$alt, accuracy=$accuracy, source=$source, uncertainty=$uncertainty_meters"

    # Return enhanced GPS data (lat,lon,alt,accuracy,source,uncertainty,gps_time,utc_offset)
    printf "%s,%s,%s,%s,%s,%s,%s,%s" "$lat" "$lon" "$alt" "$accuracy" "$source" "$uncertainty_meters" "$gps_time_s" "$utc_offset_s"
}

# =============================================================================
# STARLINK HEALTH MONITORING AND FAILOVER DETECTION
# Monitors critical Starlink health indicators for failover decisions
# =============================================================================

check_starlink_health() {
    # Configuration
    health_enabled="${ENABLE_HEALTH_MONITORING:-true}"

    if [ "$health_enabled" != "true" ]; then
        log_debug "🏥 HEALTH CHECK: Health monitoring disabled, returning healthy status"
        printf "healthy,PASSED,NO_LIMIT,NO_LIMIT,false,false,false,false,0"
        return 0
    fi

    log_debug "🏥 HEALTH CHECK: Starting comprehensive Starlink health assessment with reboot monitoring"

    overall_status="" hardware_self_test="" dl_bandwidth_reason="" ul_bandwidth_reason=""
    thermal_throttle="" thermal_shutdown="" roaming_alert="" reboot_imminent=""
    reboot_countdown="0"

    # Require external dependencies
    if [ -z "${GRPCURL_CMD:-}" ] || [ ! -f "${GRPCURL_CMD:-}" ] || [ -z "${JQ_CMD:-}" ] || [ ! -f "${JQ_CMD:-}" ]; then
        log_debug "🏥 HEALTH CHECK: Required tools not available, returning unknown status"
        printf "unknown,UNKNOWN,UNKNOWN,UNKNOWN,false,false,false,false,0"
        return 1
    fi

    if [ -z "${STARLINK_IP:-}" ] || [ -z "${STARLINK_PORT:-}" ]; then
        log_debug "🏥 HEALTH CHECK: Starlink IP/port not configured"
        printf "unknown,UNKNOWN,UNKNOWN,UNKNOWN,false,false,false,false,0"
        return 1
    fi

    # Get diagnostics data for health assessment
    log_debug "🏥 HEALTH CHECK: Fetching diagnostics data for health assessment"
    diag_cmd="$GRPCURL_CMD -plaintext -d '{\"get_diagnostics\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

    if diag_data=$(eval "$diag_cmd" 2>/dev/null); then
        log_debug "🏥 HEALTH CHECK: Diagnostics data retrieved successfully"

        # Extract critical health indicators
        hardware_self_test=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.hardwareSelfTest // "UNKNOWN"' 2>/dev/null)
        dl_bandwidth_reason=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.dlBandwidthRestrictedReason // "UNKNOWN"' 2>/dev/null)
        ul_bandwidth_reason=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.ulBandwidthRestrictedReason // "UNKNOWN"' 2>/dev/null)

        # Extract alert conditions
        thermal_throttle=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.alerts.thermalThrottle // false' 2>/dev/null)
        thermal_shutdown=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.alerts.thermalShutdown // false' 2>/dev/null)
        roaming_alert=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.alerts.roaming // false' 2>/dev/null)

        # PREDICTIVE FAILOVER: Extract software update and reboot information
        software_update_state=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateState // "UNKNOWN"' 2>/dev/null)
        update_requires_reboot=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateStats.updateRequiresReboot // false' 2>/dev/null)
        reboot_scheduled_utc=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateStats.rebootScheduledUtcTime // "0"' 2>/dev/null)

        # Also check get_status for reboot readiness
        status_cmd="$GRPCURL_CMD -plaintext -d '{\"get_status\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"
        if status_data=$(eval "$status_cmd" 2>/dev/null); then
            swupdate_reboot_ready=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.swupdateRebootReady // false' 2>/dev/null)
            log_debug "🏥 REBOOT CHECK: Software update reboot ready: $swupdate_reboot_ready"
        else
            swupdate_reboot_ready="false"
        fi

        log_debug "🏥 REBOOT CHECK: Software update state: $software_update_state"
        log_debug "🏥 REBOOT CHECK: Update requires reboot: $update_requires_reboot"
        log_debug "🏥 REBOOT CHECK: Reboot scheduled UTC: $reboot_scheduled_utc"

        # Calculate reboot countdown if scheduled
        reboot_imminent="false"
        if [ "$reboot_scheduled_utc" != "0" ] && [ "$reboot_scheduled_utc" != "null" ]; then
            current_utc=$(date +%s)
            reboot_countdown=$((reboot_scheduled_utc - current_utc))

            log_debug "🏥 REBOOT CHECK: Current UTC: $current_utc, Scheduled: $reboot_scheduled_utc, Countdown: ${reboot_countdown}s"

            # Consider reboot imminent if within configurable window (default 5 minutes)
            reboot_warning_window="${REBOOT_WARNING_SECONDS:-300}"
            if [ "$reboot_countdown" -le "$reboot_warning_window" ] && [ "$reboot_countdown" -gt 0 ]; then
                reboot_imminent="true"
                log_warning "🏥 REBOOT CHECK: PREDICTIVE FAILOVER - Reboot scheduled in ${reboot_countdown} seconds (within ${reboot_warning_window}s warning window)"
            elif [ "$reboot_countdown" -le 0 ]; then
                reboot_imminent="true"
                log_warning "🏥 REBOOT CHECK: PREDICTIVE FAILOVER - Reboot time has passed or is overdue"
            fi
        fi

        # Check for immediate reboot indicators
        if [ "$software_update_state" = "REBOOT_REQUIRED" ] || [ "$swupdate_reboot_ready" = "true" ]; then
            if [ "$reboot_imminent" = "false" ]; then
                # Reboot required but no scheduled time - assume imminent
                reboot_imminent="true"
                log_warning "🏥 REBOOT CHECK: PREDICTIVE FAILOVER - Reboot required but no scheduled time (assuming imminent)"
            fi
        fi

        log_debug "🏥 HEALTH CHECK: Hardware self-test: $hardware_self_test"
        log_debug "🏥 HEALTH CHECK: DL bandwidth restriction: $dl_bandwidth_reason"
        log_debug "🏥 HEALTH CHECK: UL bandwidth restriction: $ul_bandwidth_reason"
        log_debug "🏥 HEALTH CHECK: Thermal throttle: $thermal_throttle"
        log_debug "🏥 HEALTH CHECK: Thermal shutdown: $thermal_shutdown"
        log_debug "🏥 HEALTH CHECK: Roaming alert: $roaming_alert"
        log_debug "🏥 HEALTH CHECK: Reboot imminent: $reboot_imminent (countdown: ${reboot_countdown}s)"

        # Determine overall health status with predictive failover
        if [ "$reboot_imminent" = "true" ]; then
            overall_status="reboot_imminent"
            log_warning "🏥 HEALTH CHECK: REBOOT IMMINENT - Predictive failover recommended (countdown: ${reboot_countdown}s)"
        elif [ "$hardware_self_test" != "PASSED" ] && [ "$hardware_self_test" != "UNKNOWN" ]; then
            overall_status="critical"
            log_warning "🏥 HEALTH CHECK: CRITICAL - Hardware self-test failed: $hardware_self_test"
        elif [ "$thermal_shutdown" = "true" ]; then
            overall_status="critical"
            log_warning "🏥 HEALTH CHECK: CRITICAL - Thermal shutdown alert active"
        elif [ "$thermal_throttle" = "true" ]; then
            overall_status="degraded"
            log_warning "🏥 HEALTH CHECK: DEGRADED - Thermal throttling active"
        elif [ "$dl_bandwidth_reason" != "NO_LIMIT" ] || [ "$ul_bandwidth_reason" != "NO_LIMIT" ]; then
            overall_status="degraded"
            log_warning "🏥 HEALTH CHECK: DEGRADED - Bandwidth restrictions active: DL=$dl_bandwidth_reason, UL=$ul_bandwidth_reason"
        elif [ "$roaming_alert" = "true" ]; then
            overall_status="degraded"
            log_warning "🏥 HEALTH CHECK: DEGRADED - Roaming alert active"
        else
            overall_status="healthy"
            log_debug "🏥 HEALTH CHECK: System health appears normal"
        fi

    else
        log_error "🏥 HEALTH CHECK: Failed to retrieve diagnostics data"
        overall_status="unknown"
        hardware_self_test="UNKNOWN"
        dl_bandwidth_reason="UNKNOWN"
        ul_bandwidth_reason="UNKNOWN"
        thermal_throttle="false"
        thermal_shutdown="false"
        roaming_alert="false"
        reboot_imminent="false"
        reboot_countdown="0"
    fi

    log_debug "🏥 HEALTH CHECK: Final status - $overall_status"

    # Return enhanced health status (overall,hardware_test,dl_bw_reason,ul_bw_reason,thermal_throttle,thermal_shutdown,roaming,reboot_imminent,reboot_countdown)
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s" \
        "$overall_status" "$hardware_self_test" "$dl_bandwidth_reason" "$ul_bandwidth_reason" \
        "$thermal_throttle" "$thermal_shutdown" "$roaming_alert" "$reboot_imminent" "$reboot_countdown"
}

# Check if Starlink failover should be triggered based on health status
should_trigger_failover() {
    health_status="$1"

    # Parse health status components (enhanced format)
    overall_status=$(echo "$health_status" | cut -d',' -f1)
    hardware_test=$(echo "$health_status" | cut -d',' -f2)
    thermal_shutdown=$(echo "$health_status" | cut -d',' -f6)
    reboot_imminent=$(echo "$health_status" | cut -d',' -f8)
    reboot_countdown=$(echo "$health_status" | cut -d',' -f9)

    log_debug "🚨 FAILOVER CHECK: Evaluating failover conditions - status=$overall_status, hardware=$hardware_test, shutdown=$thermal_shutdown, reboot=$reboot_imminent"

    # PREDICTIVE FAILOVER: Trigger on imminent reboot
    if [ "$reboot_imminent" = "true" ]; then
        if [ "$reboot_countdown" != "0" ] && [ "$reboot_countdown" -gt 0 ]; then
            log_warning "🚨 PREDICTIVE FAILOVER: Reboot scheduled in ${reboot_countdown} seconds - triggering preemptive failover"
        else
            log_warning "🚨 PREDICTIVE FAILOVER: Reboot required or overdue - triggering immediate failover"
        fi
        return 0
    fi

    # Trigger failover on critical conditions
    case "$overall_status" in
        reboot_imminent)
            log_warning "🚨 FAILOVER TRIGGER: Reboot imminent - predictive failover recommended"
            return 0
            ;;
        critical)
            log_warning "🚨 FAILOVER TRIGGER: Critical health status detected - failover recommended"
            return 0
            ;;
        unknown)
            log_warning "🚨 FAILOVER TRIGGER: Health status unknown - failover may be needed"
            return 0
            ;;
        degraded)
            log_warning "🚨 FAILOVER CHECK: Degraded status - monitoring closely but not triggering failover yet"
            return 1
            ;;
        healthy)
            log_debug "🚨 FAILOVER CHECK: System healthy - no failover needed"
            return 1
            ;;
        *)
            log_warning "🚨 FAILOVER TRIGGER: Unknown health status '$overall_status' - failover recommended as precaution"
            return 0
            ;;
    esac
}

# =============================================================================
# PREDICTIVE REBOOT MONITORING
# Dedicated function for monitoring and predicting Starlink reboots
# =============================================================================

# Get detailed reboot information for predictive failover
get_reboot_status() {
    log_debug "🔄 REBOOT STATUS: Checking Starlink reboot status for predictive monitoring"

    # Require external dependencies
    if [ -z "${GRPCURL_CMD:-}" ] || [ ! -f "${GRPCURL_CMD:-}" ] || [ -z "${JQ_CMD:-}" ] || [ ! -f "${JQ_CMD:-}" ]; then
        log_debug "🔄 REBOOT STATUS: Required tools not available"
        printf "unknown,false,0,0,false"
        return 1
    fi

    if [ -z "${STARLINK_IP:-}" ] || [ -z "${STARLINK_PORT:-}" ]; then
        log_debug "🔄 REBOOT STATUS: Starlink IP/port not configured"
        printf "unknown,false,0,0,false"
        return 1
    fi

    # Get diagnostics data for reboot information
    diag_cmd="$GRPCURL_CMD -plaintext -d '{\"get_diagnostics\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"
    status_cmd="$GRPCURL_CMD -plaintext -d '{\"get_status\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

    software_update_state="unknown"
    update_requires_reboot="false"
    reboot_scheduled_utc="0"
    update_progress="0"
    swupdate_reboot_ready="false"

    # Get diagnostics data
    if diag_data=$(eval "$diag_cmd" 2>/dev/null); then
        log_debug "🔄 REBOOT STATUS: Diagnostics data retrieved"

        software_update_state=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateState // "unknown"' 2>/dev/null)
        update_requires_reboot=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateStats.updateRequiresReboot // false' 2>/dev/null)
        reboot_scheduled_utc=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateStats.rebootScheduledUtcTime // "0"' 2>/dev/null)
        update_progress=$(echo "$diag_data" | "$JQ_CMD" -r '.dishGetDiagnostics.softwareUpdateStats.softwareUpdateProgress // 0' 2>/dev/null)

        log_debug "🔄 REBOOT STATUS: Update state: $software_update_state"
        log_debug "🔄 REBOOT STATUS: Requires reboot: $update_requires_reboot"
        log_debug "🔄 REBOOT STATUS: Scheduled UTC: $reboot_scheduled_utc"
        log_debug "🔄 REBOOT STATUS: Update progress: $update_progress"
    fi

    # Get status data for additional reboot indicators
    if status_data=$(eval "$status_cmd" 2>/dev/null); then
        log_debug "🔄 REBOOT STATUS: Status data retrieved"
        swupdate_reboot_ready=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.swupdateRebootReady // false' 2>/dev/null)
        log_debug "🔄 REBOOT STATUS: Software update reboot ready: $swupdate_reboot_ready"
    fi

    # Calculate countdown if reboot is scheduled
    current_utc=$(date +%s)
    if [ "$reboot_scheduled_utc" != "0" ] && [ "$reboot_scheduled_utc" != "null" ]; then
        reboot_countdown=$((reboot_scheduled_utc - current_utc))
        log_debug "🔄 REBOOT STATUS: Countdown calculated: ${reboot_countdown}s"
    else
        reboot_countdown="0"
    fi

    # Return reboot status (update_state,requires_reboot,scheduled_utc,countdown,reboot_ready)
    printf "%s,%s,%s,%s,%s" \
        "$software_update_state" "$update_requires_reboot" "$reboot_scheduled_utc" "$reboot_countdown" "$swupdate_reboot_ready"
}

# Check if reboot should trigger immediate failover
should_failover_for_reboot() {
    reboot_status="$1"
    warning_window="${REBOOT_WARNING_SECONDS:-300}" # Default 5 minutes

    # Parse reboot status
    update_state=$(echo "$reboot_status" | cut -d',' -f1)
    requires_reboot=$(echo "$reboot_status" | cut -d',' -f2)
    scheduled_utc=$(echo "$reboot_status" | cut -d',' -f3)
    countdown=$(echo "$reboot_status" | cut -d',' -f4)
    reboot_ready=$(echo "$reboot_status" | cut -d',' -f5)

    log_debug "🔄 REBOOT FAILOVER: Evaluating reboot conditions - state=$update_state, requires=$requires_reboot, countdown=${countdown}s, ready=$reboot_ready"

    # Immediate failover conditions
    if [ "$reboot_ready" = "true" ]; then
        log_warning "🔄 REBOOT FAILOVER: Software update reboot ready - immediate failover recommended"
        return 0
    fi

    if [ "$update_state" = "REBOOT_REQUIRED" ]; then
        log_warning "🔄 REBOOT FAILOVER: Reboot required state - immediate failover recommended"
        return 0
    fi

    # Time-based failover for scheduled reboots
    if [ "$countdown" != "0" ] && [ "$countdown" -gt 0 ]; then
        if [ "$countdown" -le "$warning_window" ]; then
            log_warning "🔄 REBOOT FAILOVER: Reboot in ${countdown}s (within ${warning_window}s window) - predictive failover recommended"
            return 0
        else
            log_debug "🔄 REBOOT FAILOVER: Reboot in ${countdown}s (outside warning window) - no failover needed yet"
            return 1
        fi
    elif [ "$countdown" -le 0 ] && [ "$scheduled_utc" != "0" ] && [ "$scheduled_utc" != "null" ]; then
        log_warning "🔄 REBOOT FAILOVER: Scheduled reboot time has passed - immediate failover recommended"
        return 0
    fi

    # No reboot imminent
    log_debug "🔄 REBOOT FAILOVER: No immediate reboot concerns"
    return 1
}

# =============================================================================
# LIBRARY MODULE INFORMATION
# =============================================================================

# Display data collection library information
rutos_data_collection_info() {
    printf "RUTOS Data Collection Library Information:\n"
    printf "  GPS Functions: collect_gps_data(), collect_gps_data_enhanced(), validate_gps_coordinates()\n"
    printf "  Cellular Functions: collect_cellular_data(), collect_cellular_data_enhanced()\n"
    printf "  Health Functions: check_starlink_health(), should_trigger_failover()\n"
    printf "  Reboot Functions: get_reboot_status(), should_failover_for_reboot()\n"
    printf "  Starlink Functions: calculate_starlink_drop_rate(), get_starlink_status_enhanced()\n"
    printf "  Utility Functions: sanitize_csv_field()\n"
    printf "  GPS Sources: RUTOS gpsctl, Starlink get_location, Starlink get_diagnostics\n"
    printf "  Health Monitoring: Hardware self-test, bandwidth restrictions, thermal alerts\n"
    printf "  Predictive Failover: Scheduled reboot detection and countdown monitoring\n"
    printf "  Drop Rate: Auto-calculated from history when missing from status\n"
    printf "  Loaded: %s\n" "${_RUTOS_DATA_COLLECTION_LOADED:-no}"
}

# =============================================================================
# LIBRARY FUNCTION ALIASES (avoid naming conflicts)
# =============================================================================

# Aliases to avoid conflicts with local functions
collect_gps_data_lib() {
    collect_gps_data
}

collect_gps_data_enhanced_lib() {
    collect_gps_data_enhanced
}

collect_cellular_data_lib() {
    collect_cellular_data
}

collect_cellular_data_enhanced_lib() {
    collect_cellular_data_enhanced
}

check_starlink_health_lib() {
    check_starlink_health
}

should_trigger_failover_lib() {
    should_trigger_failover "$@"
}

get_reboot_status_lib() {
    get_reboot_status
}

should_failover_for_reboot_lib() {
    should_failover_for_reboot "$@"
}

log_debug "RUTOS Data Collection Library loaded successfully"
