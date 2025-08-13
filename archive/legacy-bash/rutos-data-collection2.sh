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
        ""|0|0.0|0.00|0.000|0.0000|0.00000|0.000000) return 1 ;;
        *[!0-9.-]*) return 1 ;;  # Contains non-numeric characters
    esac
    
    case "$lon" in
        ""|0|0.0|0.00|0.000|0.0000|0.00000|0.000000) return 1 ;;
        *[!0-9.-]*) return 1 ;;  # Contains non-numeric characters
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
                *[!0-9.-]*|"") rutos_alt="0" ;;
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
                
                # Try separate get_location API call if tools are available
                if [ -n "${GRPCURL_CMD:-}" ] && [ -f "${GRPCURL_CMD:-}" ] && [ -n "${STARLINK_IP:-}" ] && [ -n "${STARLINK_PORT:-}" ]; then
                    location_cmd="$GRPCURL_CMD -plaintext -d '{\"getLocation\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"
                    log_debug "📍 STARLINK GPS: Executing get_location API call"
                    
                    if location_data=$(eval "$location_cmd" 2>/dev/null); then
                        log_debug "📍 STARLINK GPS: get_location API call successful"
                        starlink_lat=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lat // empty' 2>/dev/null)
                        starlink_lon=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.lon // empty' 2>/dev/null)
                        starlink_alt=$(echo "$location_data" | "$JQ_CMD" -r '.getLocation.lla.alt // 0' 2>/dev/null)
                        log_debug "📍 STARLINK GPS: get_location results - lat=$starlink_lat, lon=$starlink_lon, alt=$starlink_alt"
                        
                        if ! validate_gps_coordinates "$starlink_lat" "$starlink_lon"; then
                            log_debug "📍 STARLINK GPS: No valid location data from get_location API either"
                            starlink_lat="" starlink_lon="" starlink_alt=""
                        fi
                    else
                        log_debug "📍 STARLINK GPS: get_location API call failed"
                        starlink_lat="" starlink_lon="" starlink_alt=""
                    fi
                else
                    log_debug "📍 STARLINK GPS: Required tools for get_location API not available"
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
    cellular_enabled="${ENABLE_CELLULAR_TRACKING:-$cellular_enabled}"  # Support both naming conventions
    
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
        roaming|home) ;;
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
        "$data_usage_mb" "$frequency_band" "$cell_id" "$lac" "$error_rate"
}

# =============================================================================
# LIBRARY MODULE INFORMATION
# =============================================================================

# Display data collection library information
rutos_data_collection_info() {
    printf "RUTOS Data Collection Library Information:\n"
    printf "  GPS Functions: collect_gps_data(), validate_gps_coordinates()\n"
    printf "  Cellular Functions: collect_cellular_data(), collect_cellular_data_enhanced()\n"
    printf "  Utility Functions: sanitize_csv_field()\n"
    printf "  Loaded: %s\n" "${_RUTOS_DATA_COLLECTION_LOADED:-no}"
}

# =============================================================================
# LIBRARY FUNCTION ALIASES (avoid naming conflicts)
# =============================================================================

# Aliases to avoid conflicts with local functions
collect_gps_data_lib() {
    collect_gps_data
}

collect_cellular_data_lib() {
    collect_cellular_data
}

collect_cellular_data_enhanced_lib() {
    collect_cellular_data_enhanced
}

log_debug "RUTOS Data Collection Library loaded successfully"
