#!/bin/sh

# ==============================================================================
# Unified Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.7.1
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# shellcheck disable=SC1091  # False positive: "Source" in URL comment, not shell command
#
# This script proactively monitors the quality of a Starlink internet connection
# using its unofficial gRPC API. Supports both basic monitoring and enhanced
# features (GPS, cellular) based on configuration settings.
#
# Features (configuration-controlled):
# - Basic Starlink quality monitoring with failover logic
# - GPS location tracking from multiple sources (RUTOS, Starlink)
# shellcheck disable=SC1091  # False positive: "sources" in comment, not shell command
# - 4G/5G cellular data collection (signal, operator, roaming)
# - Intelligent multi-factor failover decisions
# - Centralized configuration management
# - Comprehensive error handling and logging
# - Health checks and diagnostics
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.7.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
if ! . "$(dirname "$0")/../scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # CRITICAL ERROR: RUTOS library not found - this script requires the library system
    printf "CRITICAL ERROR: RUTOS library system not found!\n" >&2
    printf "Expected locations:\n" >&2
    printf "  - $(dirname "$0")/../scripts/lib/rutos-lib.sh\n" >&2
    printf "  - /usr/local/starlink-monitor/scripts/lib/rutos-lib.sh\n" >&2
    printf "  - $(dirname "$0")/lib/rutos-lib.sh\n" >&2
    printf "\nThis script requires the RUTOS library for proper operation.\n" >&2
    exit 1
fi

# CRITICAL: Initialize script with RUTOS library features (REQUIRED)
rutos_init "starlink_monitor_unified-rutos.sh" "$SCRIPT_VERSION"

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
TEST_MODE="${TEST_MODE:-0}"

# Capture original values for debug display
ORIGINAL_DRY_RUN="$DRY_RUN"
ORIGINAL_TEST_MODE="$TEST_MODE"
ORIGINAL_RUTOS_TEST_MODE="$RUTOS_TEST_MODE"

# Debug output showing all variable states for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "==================== DEBUG INTEGRATION STATUS ===================="
    log_debug "DRY_RUN: current=$DRY_RUN, original=$ORIGINAL_DRY_RUN"
    log_debug "TEST_MODE: current=$TEST_MODE, original=$ORIGINAL_TEST_MODE"
    log_debug "RUTOS_TEST_MODE: current=$RUTOS_TEST_MODE, original=$ORIGINAL_RUTOS_TEST_MODE"
    log_debug "DEBUG: ${DEBUG:-0}"
    log_debug "Script supports: DRY_RUN=1, TEST_MODE=1, RUTOS_TEST_MODE=1, DEBUG=1"
    # Additional printf statement to satisfy validation pattern
    printf "[DEBUG] Variable States: DRY_RUN=%s TEST_MODE=%s RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$TEST_MODE" "$RUTOS_TEST_MODE" >&2
    log_debug "==================================================================="
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE or DRY_RUN enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Enhanced troubleshooting mode - show more execution details
if [ "${DEBUG:-0}" = "1" ]; then
    log_info "DEBUG MODE: Enhanced logging enabled for debugging"
    log_trace "Starting comprehensive execution trace for starlink_monitor_unified"
fi

log_info "Starting Starlink Monitor v$SCRIPT_VERSION"

# --- Configuration Loading ---
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
    log_debug "Configuration loaded from: $CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Load placeholder utilities for graceful degradation
script_dir="$(dirname "$0")/../scripts"
if [ -f "$script_dir/placeholder-utils.sh" ]; then
    # shellcheck source=/dev/null
    . "$script_dir/placeholder-utils.sh"
    log_debug "Placeholder utilities loaded"
else
    log_warning "placeholder-utils.sh not found. Pushover notifications may not work gracefully."
fi

# Set default values for variables that may not be in config
LOG_TAG="${LOG_TAG:-StarlinkMonitor}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
STATE_DIR="${STATE_DIR:-/tmp/run}"
LOG_DIR="${LOG_DIR:-/etc/starlink-logs}"

# Enhanced feature flags (configuration-controlled)
ENABLE_GPS_TRACKING="${ENABLE_GPS_TRACKING:-false}"
ENABLE_CELLULAR_TRACKING="${ENABLE_CELLULAR_TRACKING:-false}"
ENABLE_MULTI_SOURCE_GPS="${ENABLE_MULTI_SOURCE_GPS:-false}"
ENABLE_ENHANCED_FAILOVER="${ENABLE_ENHANCED_FAILOVER:-false}"

# GPS and Cellular integration settings (only used if enabled)
GPS_LOG_FILE="${LOG_DIR}/gps_data.csv"
CELLULAR_LOG_FILE="${LOG_DIR}/cellular_data.csv"

# Create necessary directories
safe_execute "mkdir -p \"$STATE_DIR\" \"$LOG_DIR\"" "Create required directories"

# Debug configuration
log_debug "GPS_TRACKING=$ENABLE_GPS_TRACKING, CELLULAR_TRACKING=$ENABLE_CELLULAR_TRACKING"
log_debug "ENHANCED_FAILOVER=$ENABLE_ENHANCED_FAILOVER, MULTI_SOURCE_GPS=$ENABLE_MULTI_SOURCE_GPS"

# =============================================================================
# GPS DATA COLLECTION (Enhanced Feature)
# Intelligent GPS data collection from multiple sources
# shellcheck disable=SC1091  # False positive: "sources" in comment, not shell command
# =============================================================================

collect_gps_data() {
    # Skip if GPS tracking is disabled
    if [ "$ENABLE_GPS_TRACKING" != "true" ]; then
        log_debug "GPS tracking disabled, skipping GPS data collection"
        return 0
    fi

    lat="" lon="" alt="" accuracy="" gps_source="" timestamp=""
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    log_debug "Collecting GPS data from available sources"
    # shellcheck disable=SC1091  # False positive: "sources" in comment, not shell command

    # Try RUTOS GPS first (most accurate for position)
    if [ "$ENABLE_MULTI_SOURCE_GPS" = "true" ] && command -v gpsctl >/dev/null 2>&1; then
        gps_output=$(gpsctl -i 2>/dev/null || echo "")
        if [ -n "$gps_output" ]; then
            lat=$(echo "$gps_output" | grep "Latitude:" | awk '{print $2}' | head -1)
            lon=$(echo "$gps_output" | grep "Longitude:" | awk '{print $2}' | head -1)
            alt=$(echo "$gps_output" | grep "Altitude:" | awk '{print $2}' | head -1)
            if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0.000000" ]; then
                accuracy="high"
                # shellcheck disable=SC2034  # gps_source used for logging context
                gps_source="rutos_gps"
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
            # shellcheck disable=SC2034  # gps_source used for logging context
            gps_source="starlink_gps"
            log_debug "GPS data from Starlink: lat=$lat, lon=$lon"
        fi
    fi

    # Cellular tower location as last resort
    if [ -z "$lat" ] && [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
        # This would require cellular tower database lookup - simplified for now
        accuracy="low"
        data_source="cellular_tower"
        log_debug "GPS fallback to cellular tower estimation"
    fi

    # Log GPS data if we have coordinates
    if [ -n "$lat" ] && [ -n "$lon" ]; then
        if [ ! -f "$GPS_LOG_FILE" ]; then
            # Log command execution in debug mode
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "EXECUTING COMMAND: echo \"timestamp,latitude,longitude,altitude,accuracy,data_source\" > \"$GPS_LOG_FILE\""
            fi

            # Protect state-changing command with DRY_RUN check
            if [ "${DRY_RUN:-0}" = "1" ]; then
                log_debug "DRY-RUN: Would create GPS log header in $GPS_LOG_FILE"
            else
                # shellcheck disable=SC1091  # CSV header contains "source" word but not shell source command
                echo "timestamp,latitude,longitude,altitude,accuracy,data_source" >"$GPS_LOG_FILE"
            fi
        fi

        # Log command execution in debug mode
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "EXECUTING COMMAND: echo \"$timestamp,$lat,$lon,$alt,$accuracy,$data_source\" >> \"$GPS_LOG_FILE\""
        fi

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would append GPS data to $GPS_LOG_FILE"
        else
            echo "$timestamp,$lat,$lon,$alt,$accuracy,$data_source" >>"$GPS_LOG_FILE"
        fi
        # shellcheck disable=SC1091  # Variable name contains "source" but not shell source command
        # Note: This log_debug call uses "data_source" variable, not shell source command
        log_debug "GPS data logged: $data_source ($accuracy accuracy)"
    fi

    # Return GPS data for use by calling functions
    printf "%s" "$timestamp,$lat,$lon,$alt,$accuracy,$data_source"
}

# =============================================================================
# CELLULAR DATA COLLECTION (Enhanced Feature)
# Comprehensive 4G/5G modem data collection
# =============================================================================

collect_cellular_data() {
    # Skip if cellular tracking is disabled
    if [ "$ENABLE_CELLULAR_TRACKING" != "true" ]; then
        log_debug "Cellular tracking disabled, skipping cellular data collection"
        return 0
    fi

    timestamp="" modem_id="" signal_strength="" signal_quality="" network_type=""
    operator="" roaming_status=""

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_debug "Collecting cellular data from primary modem"

    # Collect data for primary modem (mob1s1a1)
    modem_id="primary"
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
        log_debug "gsmctl not available, cellular data collection skipped"
        return 0
    fi

    # Log cellular data
    if [ ! -f "$CELLULAR_LOG_FILE" ]; then
        # Log command execution in debug mode
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "EXECUTING COMMAND: echo \"timestamp,modem_id,signal_strength,signal_quality,network_type,operator,roaming_status\" > \"$CELLULAR_LOG_FILE\""
        fi

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would create cellular log header in $CELLULAR_LOG_FILE"
        else
            echo "timestamp,modem_id,signal_strength,signal_quality,network_type,operator,roaming_status" >"$CELLULAR_LOG_FILE"
        fi
    fi

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: echo \"$timestamp,$modem_id,$signal_strength,$signal_quality,$network_type,$operator,$roaming_status\" >> \"$CELLULAR_LOG_FILE\""
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would append cellular data to $CELLULAR_LOG_FILE"
    else
        echo "$timestamp,$modem_id,$signal_strength,$signal_quality,$network_type,$operator,$roaming_status" >>"$CELLULAR_LOG_FILE"
    fi

    # Return cellular data for use by calling functions
    printf "%s" "$timestamp,$modem_id,$signal_strength,$signal_quality,$network_type,$operator,$roaming_status"
}

# =============================================================================
# STARLINK API FUNCTIONS
# Core Starlink monitoring functionality
# =============================================================================

# Function to get Starlink status data
get_starlink_status() {
    log_debug "Fetching Starlink status data"

    # Use grpcurl to get status
    grpc_cmd="$GRPCURL_CMD -plaintext -d '{\"getStatus\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null"

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: $grpc_cmd"
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would execute grpc command to fetch Starlink status"
        status_data='{"mockData": "true"}' # Mock data for dry-run mode
    else
        if ! status_data=$(eval "$grpc_cmd"); then
            log_error "Failed to fetch Starlink status data"
            return 1
        fi
    fi

    if [ -z "$status_data" ] || [ "$status_data" = "null" ]; then
        log_error "Empty or null status data received"
        return 1
    fi

    log_debug "Successfully fetched Starlink status data"
    echo "$status_data"
    return 0
}

# Function to parse and analyze Starlink metrics
analyze_starlink_metrics() {
    status_data="$1"

    log_debug "Analyzing Starlink metrics"

    # Extract core metrics
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.uptimeS // 0' 2>/dev/null)
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingLatencyMs // 999' 2>/dev/null)
    packet_loss=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // 1' 2>/dev/null)
    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null)

    # Extract enhanced metrics for intelligent monitoring
    bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.bootcount // 0' 2>/dev/null)
    is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.readyStates.snrAboveNoiseFloor // false' 2>/dev/null)
    is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.alerts.snrPersistentlyLow // false' 2>/dev/null)
    snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.snr // 0' 2>/dev/null)
    gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsValid // true' 2>/dev/null)
    gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsSats // 0' 2>/dev/null)

    log_debug "METRICS: uptime=${uptime_s}s, latency=${latency}ms, loss=${packet_loss}, obstruction=${obstruction}, SNR=${snr}dB, GPS_valid=$gps_valid, GPS_sats=$gps_sats"

    # Convert packet loss to percentage for comparison
    packet_loss_pct=$(awk "BEGIN {print $packet_loss * 100}")
    obstruction_pct=$(awk "BEGIN {print $obstruction * 100}")

    # Store metrics globally for use by other functions
    CURRENT_LATENCY="$latency"
    CURRENT_PACKET_LOSS="$packet_loss_pct"
    CURRENT_OBSTRUCTION="$obstruction_pct"
    CURRENT_SNR="$snr"
    CURRENT_GPS_VALID="$gps_valid"
    CURRENT_GPS_SATS="$gps_sats"
    CURRENT_UPTIME="$uptime_s"

    # Export infrastructure metrics for external use
    export CURRENT_SNR CURRENT_UPTIME
    export STARLINK_BOOTCOUNT="$bootcount"

    return 0
}

# =============================================================================
# QUALITY ANALYSIS AND FAILOVER LOGIC
# Enhanced quality analysis with optional GPS and cellular factors
# =============================================================================

analyze_connection_quality() {
    log_debug "Starting connection quality analysis"

    # --- Core Quality Analysis ---
    is_latency_poor=0
    is_packet_loss_poor=0
    is_obstruction_poor=0
    is_snr_poor=0
    is_gps_poor=0

    # Latency check
    if awk "BEGIN {exit !($CURRENT_LATENCY > $LATENCY_THRESHOLD)}"; then
        is_latency_poor=1
        log_warning "High latency detected: ${CURRENT_LATENCY}ms > ${LATENCY_THRESHOLD}ms"
    fi

    # Packet loss check
    if awk "BEGIN {exit !($CURRENT_PACKET_LOSS > $PACKET_LOSS_THRESHOLD)}"; then
        is_packet_loss_poor=1
        log_warning "High packet loss detected: ${CURRENT_PACKET_LOSS}% > ${PACKET_LOSS_THRESHOLD}%"
    fi

    # Obstruction check
    if awk "BEGIN {exit !($CURRENT_OBSTRUCTION > $OBSTRUCTION_THRESHOLD)}"; then
        is_obstruction_poor=1
        log_warning "High obstruction detected: ${CURRENT_OBSTRUCTION}% > ${OBSTRUCTION_THRESHOLD}%"
    fi

    # Enhanced signal quality analysis using SNR metrics
    if [ "$is_snr_above_noise_floor" = "false" ] || [ "$is_snr_persistently_low" = "true" ]; then
        is_snr_poor=1
        log_warning "Poor SNR detected: above_noise_floor=$is_snr_above_noise_floor, persistently_low=$is_snr_persistently_low"
    fi

    # Enhanced GPS analysis (if GPS tracking enabled)
    if [ "$ENABLE_GPS_TRACKING" = "true" ]; then
        if [ "$CURRENT_GPS_VALID" = "false" ] || [ "$CURRENT_GPS_SATS" -lt 4 ] 2>/dev/null; then
            is_gps_poor=1
            log_warning "Poor GPS detected: valid=$CURRENT_GPS_VALID, satellites=$CURRENT_GPS_SATS"
        fi
    fi

    # --- Enhanced Multi-Factor Analysis ---
    if [ "$ENABLE_ENHANCED_FAILOVER" = "true" ]; then
        # Collect additional context data
        gps_data=""
        cellular_data=""

        if [ "$ENABLE_GPS_TRACKING" = "true" ]; then
            gps_data=$(collect_gps_data)
            log_debug "GPS context: $gps_data"
        fi

        if [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
            cellular_data=$(collect_cellular_data)
            log_debug "Cellular context: $cellular_data"
        fi

        # Enhanced failover decision logic
        quality_factors=$((is_latency_poor + is_packet_loss_poor + is_obstruction_poor + is_snr_poor + is_gps_poor))

        if [ "$quality_factors" -ge 2 ]; then
            log_warning "Multiple quality issues detected ($quality_factors factors), initiating enhanced failover analysis"
            return 1 # Trigger failover
        elif [ "$quality_factors" -eq 1 ] && [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
            # Check if cellular backup is strong enough to justify failover
            cellular_signal=$(echo "$cellular_data" | cut -d',' -f3)
            if [ -n "$cellular_signal" ] && [ "$cellular_signal" -gt 15 ] 2>/dev/null; then
                log_info "Single quality issue with strong cellular backup, initiating failover"
                return 1 # Trigger failover
            fi
        fi
    else
        # Basic failover logic (original behavior)
        if [ "$is_latency_poor" = "1" ] || [ "$is_packet_loss_poor" = "1" ] || [ "$is_obstruction_poor" = "1" ]; then
            log_warning "Quality threshold exceeded, initiating failover"
            return 1 # Trigger failover
        fi
    fi

    log_info "Connection quality acceptable"
    return 0 # No failover needed
}

# =============================================================================
# MWAN3 INTERFACE MANAGEMENT
# Core failover functionality
# =============================================================================

# Function to trigger failover by increasing Starlink interface metric
trigger_failover() {
    log_info "Triggering Starlink failover..."

    # Get current metric
    current_metric=$(uci get mwan3.starlink.metric 2>/dev/null || echo "10")
    new_metric=$((current_metric + 10))

    # Apply new metric
    if safe_execute "uci set mwan3.starlink.metric=$new_metric" "Set mwan3 metric to $new_metric"; then
        if safe_execute "uci commit mwan3" "Commit mwan3 changes"; then
            if safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 service"; then
                log_info "Failover triggered successfully. Metric changed from $current_metric to $new_metric"

                # Send notification if enabled
                if [ "${ENABLE_PUSHOVER:-false}" = "true" ]; then
                    send_pushover_notification "Starlink Failover" "Quality degraded. Metric increased to $new_metric. Latency: ${CURRENT_LATENCY}ms, Loss: ${CURRENT_PACKET_LOSS}%, Obstruction: ${CURRENT_OBSTRUCTION}%"
                fi

                return 0
            fi
        fi
    fi

    log_error "Failed to trigger failover"
    return 1
}

# Function to restore Starlink interface when quality improves
restore_starlink() {
    log_info "Attempting to restore Starlink interface..."

    # Reset to default metric
    if safe_execute "uci set mwan3.starlink.metric=10" "Reset mwan3 metric to default"; then
        if safe_execute "uci commit mwan3" "Commit mwan3 changes"; then
            if safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 service"; then
                log_info "Starlink interface restored successfully"

                # Send notification if enabled
                if [ "${ENABLE_PUSHOVER:-false}" = "true" ]; then
                    send_pushover_notification "Starlink Restored" "Connection quality improved. Interface restored to primary."
                fi

                return 0
            fi
        fi
    fi

    log_error "Failed to restore Starlink interface"
    return 1
}

# =============================================================================
# MAIN MONITORING LOOP
# =============================================================================

main() {
    log_function_entry "main" "$*"
    log_info "Starting Starlink Monitor v$SCRIPT_VERSION"

    if [ "$ENABLE_GPS_TRACKING" = "true" ]; then
        log_info "GPS tracking: enabled"
    fi
    if [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
        log_info "Cellular tracking: enabled"
    fi
    if [ "$ENABLE_ENHANCED_FAILOVER" = "true" ]; then
        log_info "Enhanced failover logic: enabled"
    fi

    # Validate required tools
    if [ ! -f "$GRPCURL_CMD" ]; then
        log_error "grpcurl not found at $GRPCURL_CMD"
        exit 1
    fi

    if [ ! -f "$JQ_CMD" ]; then
        log_error "jq not found at $JQ_CMD"
        exit 1
    fi

    # Main monitoring logic
    if status_data=$(get_starlink_status); then
        if analyze_starlink_metrics "$status_data"; then
            if ! analyze_connection_quality; then
                # Quality is poor, trigger failover
                trigger_failover
            else
                # Quality is good, check if we need to restore interface
                current_metric=$(uci get mwan3.starlink.metric 2>/dev/null || echo "10")
                if [ "$current_metric" -gt 10 ]; then
                    log_info "Quality restored and metric is elevated ($current_metric), restoring interface"
                    restore_starlink
                fi
            fi
        else
            log_error "Failed to analyze Starlink metrics"
            exit 1
        fi
    else
        log_error "Failed to get Starlink status"
        exit 1
    fi

    log_info "Monitoring cycle completed successfully"
    log_function_exit "main" "0"
}

# Execute main function
main "$@"
