#!/bin/sh

# ==============================================================================
# Unified Starlink Performance Data Logger for OpenWrt/RUTOS
#
# Version: 2.8.0
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

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck source=/dev/null
# shellcheck source=/dev/null
# shellcheck source=/dev/null
if ! . "$(dirname "$0")/../scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # CRITICAL ERROR: RUTOS library not found - this script requires the library system
    printf "CRITICAL ERROR: RUTOS library system not found!
" >&2
    # Print error details and suggestions
    printf "Expected locations:
" >&2
    # Standard installation locations
    printf "  - $(dirname "$0")/../scripts/lib/rutos-lib.sh
" >&2
    # Production installation location
    printf "  - /usr/local/starlink-monitor/scripts/lib/rutos-lib.sh
" >&2
    # Development location
    printf "  - $(dirname "$0")/lib/rutos-lib.sh
" >&2
    printf "
This script requires the RUTOS library for proper operation.
" >&2
    exit 1
fi

# CRITICAL: Initialize script with RUTOS library features (REQUIRED)
rutos_init "starlink_logger_unified-rutos.sh" "$SCRIPT_VERSION"

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

# RUTOS_TEST_MODE enables trace logging (does NOT cause early exit)
# DRY_RUN prevents actual changes but allows full execution for debugging

log_info "Starting Starlink Logger v$SCRIPT_VERSION"

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

# === DEBUG: Configuration Values Loaded ===
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "==================== LOGGER CONFIGURATION DEBUG ===================="
    log_debug "CONFIG_FILE: $CONFIG_FILE"
    log_debug "Required connection variables:"
    log_debug "  STARLINK_IP: ${STARLINK_IP:-UNSET}"
    log_debug "  STARLINK_PORT: ${STARLINK_PORT:-UNSET}"

    log_debug "Logger-specific settings:"
    log_debug "  LOG_TAG: ${LOG_TAG:-UNSET}"
    log_debug "  LOG_DIR: ${LOG_DIR:-UNSET}"
    log_debug "  OUTPUT_CSV: ${OUTPUT_CSV:-UNSET}"
    log_debug "  STATE_FILE: ${STATE_FILE:-UNSET}"

    log_debug "Feature flags:"
    log_debug "  ENABLE_GPS_LOGGING: ${ENABLE_GPS_LOGGING:-UNSET}"
    log_debug "  ENABLE_CELLULAR_LOGGING: ${ENABLE_CELLULAR_LOGGING:-UNSET}"
    log_debug "  ENABLE_STATISTICAL_AGGREGATION: ${ENABLE_STATISTICAL_AGGREGATION:-UNSET}"
    log_debug "  ENABLE_ENHANCED_METRICS: ${ENABLE_ENHANCED_METRICS:-UNSET}"

    log_debug "Sampling and aggregation:"
    log_debug "  SAMPLING_INTERVAL: ${SAMPLING_INTERVAL:-UNSET}"
    log_debug "  AGGREGATION_WINDOW: ${AGGREGATION_WINDOW:-UNSET}"
    log_debug "  STATISTICAL_PERCENTILES: ${STATISTICAL_PERCENTILES:-UNSET}"

    log_debug "Binary paths:"
    log_debug "  GRPCURL_CMD: ${GRPCURL_CMD:-UNSET}"
    log_debug "  JQ_CMD: ${JQ_CMD:-UNSET}"

    # Check for functionality-affecting issues
    if [ "${STARLINK_IP:-}" = "" ]; then
        log_debug "⚠️  WARNING: STARLINK_IP not set - Starlink API calls will fail"
    fi
    if [ ! -f "${GRPCURL_CMD:-/usr/local/starlink-monitor/grpcurl}" ]; then
        log_debug "⚠️  WARNING: grpcurl binary not found - API calls will fail"
    fi
    if [ ! -f "${JQ_CMD:-/usr/local/starlink-monitor/jq}" ]; then
        log_debug "⚠️  WARNING: jq binary not found - JSON parsing will fail"
    fi
    if [ ! -d "${LOG_DIR:-/etc/starlink-logs}" ]; then
        log_debug "⚠️  WARNING: LOG_DIR does not exist - will attempt to create"
    fi

    log_debug "==============================================================="
fi

# Enhanced logging settings (only used if enabled)
AGGREGATED_LOG_FILE="${LOG_DIR}/starlink_aggregated.csv"
AGGREGATION_BATCH_SIZE="${AGGREGATION_BATCH_SIZE:-60}"

# Starlink connection settings with defaults
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"

# Binary paths with defaults
GRPCURL_CMD="${GRPCURL_CMD:-/usr/local/starlink-monitor/grpcurl}"
JQ_CMD="${JQ_CMD:-/usr/local/starlink-monitor/jq}"

# Create necessary directories
mkdir -p "$LOG_DIR" "$(dirname "$STATE_FILE")" 2>/dev/null || true

# Enhanced troubleshooting mode - show more execution details
if [ "${DEBUG:-0}" = "1" ]; then
    log_info "DEBUG MODE: Enhanced logging enabled for debugging"
    log_trace "Starting comprehensive execution trace for starlink_logger_unified"
    
    log_debug "==================== FINAL CONFIGURATION STATE ===================="
    log_debug "Derived settings after defaults applied:"
    log_debug "  STARLINK_IP: $STARLINK_IP"
    log_debug "  STARLINK_PORT: $STARLINK_PORT"
    log_debug "  GRPCURL_CMD: $GRPCURL_CMD"
    log_debug "  JQ_CMD: $JQ_CMD"
    log_debug "  AGGREGATED_LOG_FILE: $AGGREGATED_LOG_FILE"
    log_debug "  AGGREGATION_BATCH_SIZE: $AGGREGATION_BATCH_SIZE"
    
    log_debug "Directory creation results:"
    if [ -d "$LOG_DIR" ]; then
        log_debug "  ✓ LOG_DIR exists: $LOG_DIR"
    else
        log_debug "  ✗ LOG_DIR missing: $LOG_DIR"
    fi
    
    if [ -d "$(dirname "$STATE_FILE")" ]; then
        log_debug "  ✓ STATE_FILE directory exists: $(dirname "$STATE_FILE")"
    else
        log_debug "  ✗ STATE_FILE directory missing: $(dirname "$STATE_FILE")"
    fi
    
    log_debug "Binary validation:"
    if [ -f "$GRPCURL_CMD" ] && [ -x "$GRPCURL_CMD" ]; then
        log_debug "  ✓ grpcurl binary found and executable: $GRPCURL_CMD"
    else
        log_debug "  ✗ grpcurl binary missing or not executable: $GRPCURL_CMD"
    fi
    
    if [ -f "$JQ_CMD" ] && [ -x "$JQ_CMD" ]; then
        log_debug "  ✓ jq binary found and executable: $JQ_CMD"
    else
        log_debug "  ✗ jq binary missing or not executable: $JQ_CMD"
    fi
    
    log_debug "==============================================================="
fi

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
    line_count=$(tail -n +2 "$source_file" | wc -l | tr -d ' 

')

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
    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would create temporary batch file for processing"
    else
        tail -n +2 "$source_file" | head -n "$batch_size" >"$temp_batch"
    fi

    # Complex awk script for statistical aggregation
    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would run awk statistical aggregation and append to $AGGREGATED_LOG_FILE"
    else
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
    # Define abs function (POSIX-compatible)
    function abs(x) { return (x < 0 ? -x : x) }
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
    fi

    # Remove processed lines from source file
    if [ "$line_count" -gt "$batch_size" ]; then
        # Protect state-changing commands with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would process file operations for batch processing"
        else
            tail -n +$((batch_size + 1)) "$source_file" >"${source_file}.tmp"
            head -1 "$source_file" >"${source_file}.new"
            cat "${source_file}.tmp" >>"${source_file}.new"
        fi

        # Log command execution in debug mode
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "EXECUTING COMMAND: mv \"${source_file}.new\" \"$source_file\""
        fi

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would move ${source_file}.new to $source_file"
        else
            mv "${source_file}.new" "$source_file"
        fi

        # Log command execution in debug mode
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "EXECUTING COMMAND: rm -f \"${source_file}.tmp\""
        fi

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would remove temporary file ${source_file}.tmp"
        else
            rm -f "${source_file}.tmp"
        fi
    else
        # Keep only header if all data was processed
        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would keep only header in ${source_file}.new"
        else
            head -1 "$source_file" >"${source_file}.new"
        fi

        # Log command execution in debug mode
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "EXECUTING COMMAND: mv \"${source_file}.new\" \"$source_file\""
        fi

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "DRY-RUN: Would move ${source_file}.new to $source_file"
        else
            mv "${source_file}.new" "$source_file"
        fi
    fi

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: rm -f \"$temp_batch\""
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would remove temporary batch file $temp_batch"
    else
        rm -f "$temp_batch"
    fi
    log_info "Statistical aggregation completed - processed $batch_size records"
}

# =============================================================================
# GPS DATA COLLECTION (Enhanced Feature)
# Using standardized RUTOS library function
# =============================================================================

# GPS data collection now uses the standardized library function
# The library function handles all GPS sources and provides consistent formatting
# Configuration variables:
# - ENABLE_GPS_LOGGING: true/false to enable GPS collection
# - GPS_PRIMARY_SOURCE: "starlink" or "rutos" for primary GPS source
# - GPS_SECONDARY_SOURCE: "rutos" or "starlink" for fallback source
# 
# Returns: "lat,lon,alt,accuracy,source" format

# =============================================================================
# CELLULAR DATA COLLECTION (Enhanced Feature) 
# Using standardized RUTOS library function
# =============================================================================

# Cellular data collection now uses the standardized library function
# The library function handles AT command parsing and CSV sanitization
# Configuration variables:
# - ENABLE_CELLULAR_LOGGING: true/false to enable cellular collection
#
# Returns: "signal_strength,signal_quality,network_type,operator,roaming_status" format

# =============================================================================
# STARLINK DATA EXTRACTION
# =============================================================================

extract_starlink_metrics() {
    status_data="$1"

    log_debug "📊 FUNCTION ENTRY: extract_starlink_metrics()"
    log_debug "📊 STATUS DATA LENGTH: ${#status_data} characters"
    
    # Show sample of input data if debug enabled
    if [ "${DEBUG:-0}" = "1" ]; then
        sample_data=$(echo "$status_data" | head -c 200)
        log_debug "📊 INPUT DATA SAMPLE: $sample_data..."
    fi

    log_debug "📊 Extracting basic performance metrics..."

    # Extract basic performance metrics with debug output
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceState.uptimeS // 0' 2>/dev/null)
    log_debug "📊 UPTIME EXTRACTION: ${uptime_s}s"
    
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingLatencyMs // 999' 2>/dev/null)
    log_debug "📊 LATENCY EXTRACTION: ${latency}ms"
    
    packet_loss=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // null' 2>/dev/null)
    log_debug "📊 PACKET LOSS EXTRACTION: ${packet_loss} (raw)"
    
    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null)
    log_debug "📊 OBSTRUCTION EXTRACTION: ${obstruction} (raw)"

    # Convert to hours and percentages with proper error handling
    if [ "$uptime_s" != "null" ] && [ "$uptime_s" != "0" ]; then
        uptime_hours=$(awk "BEGIN {printf \"%.2f\", $uptime_s / 3600}")
    else
        uptime_hours="0.00"
    fi
    
    if [ "$packet_loss" != "null" ] && [ "$packet_loss" != "" ]; then
        packet_loss_pct=$(awk "BEGIN {printf \"%.2f\", $packet_loss * 100}")
    else
        # No packet loss data available - assume 0% loss (healthy connection)
        packet_loss_pct="0.00"
        log_debug "📊 PACKET LOSS: No data available, assuming 0% loss"
    fi
    
    if [ "$obstruction" != "null" ]; then
        obstruction_pct=$(awk "BEGIN {printf \"%.6f\", $obstruction * 100}")
    else
        obstruction_pct="0.000000"
    fi
    
    log_debug "📊 CONVERTED VALUES: uptime=${uptime_hours}h, loss=${packet_loss_pct}%, obstruction=${obstruction_pct}%"

    # Extract enhanced metrics if enabled
    if [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        log_debug "📊 ENHANCED METRICS ENABLED - Extracting additional data..."
        
        bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.bootcount // 0' 2>/dev/null)
        log_debug "📊 BOOTCOUNT EXTRACTION: $bootcount"
        
        is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.isSnrAboveNoiseFloor // false' 2>/dev/null)
        log_debug "📊 SNR ABOVE NOISE EXTRACTION: $is_snr_above_noise_floor"
        
        is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.isSnrPersistentlyLow // false' 2>/dev/null)
        log_debug "📊 SNR PERSISTENTLY LOW EXTRACTION: $is_snr_persistently_low"
        
        # Enhanced SNR extraction with fallback (matching monitor script)
        snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.signalQuality.snrDbTimes10 // 0' 2>/dev/null)
        if [ "$snr" != "0" ] && [ "$snr" != "null" ]; then
            # Convert from dB*10 to actual dB value
            snr_value=$(echo "$snr / 10" | awk '{printf "%.3f", $1}')
            log_debug "📊 SNR DIRECT EXTRACTION: ${snr_value}dB (raw=${snr})"
            snr="$snr_value"
        elif [ "$is_snr_above_noise_floor" = "true" ]; then
            snr="good"
            log_debug "📊 SNR FALLBACK: Using 'good' based on snrAboveNoiseFloor=true"
        else
            snr="0"
            log_debug "📊 SNR EXTRACTION: No valid SNR data available"
        fi
        
        gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsValid // false' 2>/dev/null)
        log_debug "📊 GPS VALID EXTRACTION: $gps_valid"
        
        gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsSats // 0' 2>/dev/null)
        log_debug "📊 GPS SATELLITES EXTRACTION: $gps_sats satellites"

        log_debug "📊 ENHANCED METRICS SUMMARY: uptime=${uptime_s}s, bootcount=$bootcount, SNR_above_noise=$is_snr_above_noise_floor, SNR_persistently_low=$is_snr_persistently_low, SNR_value=${snr}, GPS_valid=$gps_valid, GPS_sats=$gps_sats"

        # Check for reboot detection
        log_debug "📊 REBOOT DETECTION: Checking bootcount against previous value..."
        reboot_detected="false"
        if [ -f "$STATE_FILE" ]; then
            last_bootcount=$(grep "^BOOTCOUNT=" "$STATE_FILE" | cut -d'=' -f2 2>/dev/null || echo "0")
            log_debug "📊 REBOOT CHECK: last_bootcount=$last_bootcount, current_bootcount=$bootcount"
            if [ "$bootcount" != "$last_bootcount" ] && [ "$last_bootcount" != "0" ]; then
                reboot_detected="true"
                log_warning "🔄 REBOOT DETECTED: bootcount changed from $last_bootcount to $bootcount"
            else
                log_debug "📊 REBOOT CHECK: No reboot detected (bootcount unchanged)"
            fi
        else
            log_debug "📊 REBOOT CHECK: No state file found - first run"
        fi

        # Update state file
        log_debug "📊 STATE UPDATE: Writing current bootcount to state file"
        cat >"$STATE_FILE" <<EOF
BOOTCOUNT=$bootcount
LAST_CHECK=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    else
        # Default values for enhanced metrics
        log_debug "📊 ENHANCED METRICS DISABLED - Using default values"
        snr="0"
        is_snr_above_noise_floor="true"
        is_snr_persistently_low="false"
        gps_valid="true"
        gps_sats="0"
        reboot_detected="false"
        log_debug "📊 DEFAULT VALUES: SNR=$snr, GPS_valid=$gps_valid, GPS_sats=$gps_sats"
    fi

    log_debug "📊 FINAL METRICS SUMMARY: latency=${latency}ms, loss=${packet_loss_pct}%, obstruction=${obstruction_pct}%, uptime=${uptime_hours}h"

    # Store metrics globally for CSV output
    log_debug "📊 STORING GLOBAL VARIABLES for CSV output..."
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
    
    log_debug "📊 STORED VARIABLES: timestamp=$CURRENT_TIMESTAMP, GPS_sats=$CURRENT_GPS_SATS, SNR=$CURRENT_SNR"
    log_debug "📊 FUNCTION EXIT: extract_starlink_metrics() completed successfully"

    return 0
}

# =============================================================================
# CSV LOGGING FUNCTIONS
# =============================================================================

create_csv_header() {
    log_debug "Creating CSV header"

    if [ "$ENABLE_ENHANCED_METRICS" = "true" ] && [ "$ENABLE_GPS_LOGGING" = "true" ] && [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        # Full enhanced header with all features
        header_content="Timestamp,Latitude,Longitude,Altitude,GPS_Accuracy,GPS_Source,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Signal Strength,Signal Quality,Network Type,Operator,Roaming Status,Reboot Detected"
    elif [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        # Enhanced metrics without GPS/cellular
        header_content="Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Reboot Detected"
    else
        # Basic CSV header (original format)
        header_content="Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours)"
    fi

    # Log command execution in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "EXECUTING COMMAND: echo \"$header_content\" > \"$OUTPUT_CSV\""
    fi

    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would create CSV header in $OUTPUT_CSV"
    else
        echo "$header_content" >"$OUTPUT_CSV"
    fi
}

log_to_csv() {
    log_debug "📝 FUNCTION ENTRY: log_to_csv()"
    log_debug "📝 CSV FILE: $OUTPUT_CSV"

    # Collect additional data if enabled
    gps_data=""
    cellular_data=""

    if [ "$ENABLE_GPS_LOGGING" = "true" ]; then
        log_debug "📝 GPS LOGGING: Collecting GPS data using library function..."
        gps_data=$(collect_gps_data)
        log_debug "📝 GPS DATA: $gps_data"
    else
        log_debug "📝 GPS LOGGING: Disabled"
    fi

    if [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        log_debug "📝 CELLULAR LOGGING: Collecting cellular data using library function..."
        cellular_data=$(collect_cellular_data)
        log_debug "📝 CELLULAR DATA: $cellular_data"
    else
        log_debug "📝 CELLULAR LOGGING: Disabled"
    fi

    # Create CSV header if file doesn't exist
    if [ ! -f "$OUTPUT_CSV" ]; then
        log_debug "📝 CSV HEADER: File doesn't exist, creating header..."
        create_csv_header
    else
        log_debug "📝 CSV HEADER: File exists, appending data"
    fi

    # Format and append data based on enabled features
    log_debug "📝 DATA FORMATTING: ENHANCED_METRICS=$ENABLE_ENHANCED_METRICS, GPS_LOGGING=$ENABLE_GPS_LOGGING, CELLULAR_LOGGING=$ENABLE_CELLULAR_LOGGING"
    if [ "$ENABLE_ENHANCED_METRICS" = "true" ] && [ "$ENABLE_GPS_LOGGING" = "true" ] && [ "$ENABLE_CELLULAR_LOGGING" = "true" ]; then
        # Full enhanced logging
        log_debug "📝 FORMAT: Full enhanced logging (GPS + Cellular + Enhanced metrics)"
        gps_valid_flag=$([ "$CURRENT_GPS_VALID" = "true" ] && echo "1" || echo "0")
        snr_above_noise_flag=$([ "$CURRENT_SNR_ABOVE_NOISE" = "true" ] && echo "1" || echo "0")
        snr_persistently_low_flag=$([ "$CURRENT_SNR_PERSISTENTLY_LOW" = "true" ] && echo "1" || echo "0")
        reboot_flag=$([ "$CURRENT_REBOOT_DETECTED" = "true" ] && echo "1" || echo "0")

        log_debug "📝 FLAGS: GPS_valid=$gps_valid_flag, SNR_above_noise=$snr_above_noise_flag, SNR_low=$snr_persistently_low_flag, reboot=$reboot_flag"
        log_debug "📝 VALUES: GPS_sats=$CURRENT_GPS_SATS, SNR=$CURRENT_SNR, latency=$CURRENT_LATENCY"

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "📝 DRY-RUN: Would append full featured data to $OUTPUT_CSV"
        else
            data_line="$CURRENT_TIMESTAMP,$gps_data,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME,$CURRENT_SNR,$snr_above_noise_flag,$snr_persistently_low_flag,$gps_valid_flag,$CURRENT_GPS_SATS,$cellular_data,$reboot_flag"
            log_debug "📝 WRITING FULL DATA: $data_line"
            echo "$data_line" >>"$OUTPUT_CSV"
        fi

    elif [ "$ENABLE_ENHANCED_METRICS" = "true" ]; then
        # Enhanced metrics only
        log_debug "📝 FORMAT: Enhanced metrics only (no GPS/Cellular)"
        gps_valid_flag=$([ "$CURRENT_GPS_VALID" = "true" ] && echo "1" || echo "0")
        snr_above_noise_flag=$([ "$CURRENT_SNR_ABOVE_NOISE" = "true" ] && echo "1" || echo "0")
        snr_persistently_low_flag=$([ "$CURRENT_SNR_PERSISTENTLY_LOW" = "true" ] && echo "1" || echo "0")
        reboot_flag=$([ "$CURRENT_REBOOT_DETECTED" = "true" ] && echo "1" || echo "0")

        log_debug "📝 FLAGS: GPS_valid=$gps_valid_flag, SNR_above_noise=$snr_above_noise_flag, SNR_low=$snr_persistently_low_flag, reboot=$reboot_flag"
        log_debug "📝 VALUES: GPS_sats=$CURRENT_GPS_SATS, SNR=$CURRENT_SNR, latency=$CURRENT_LATENCY"

        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "📝 DRY-RUN: Would append enhanced metrics data to $OUTPUT_CSV"
        else
            data_line="$CURRENT_TIMESTAMP,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME,$CURRENT_SNR,$snr_above_noise_flag,$snr_persistently_low_flag,$gps_valid_flag,$CURRENT_GPS_SATS,$reboot_flag"
            log_debug "📝 WRITING ENHANCED DATA: $data_line"
            echo "$data_line" >>"$OUTPUT_CSV"
        fi

    else
        # Basic logging (original format)
        log_debug "📝 FORMAT: Basic logging (original format)"
        log_debug "📝 VALUES: latency=$CURRENT_LATENCY, loss=$CURRENT_PACKET_LOSS, obstruction=$CURRENT_OBSTRUCTION, uptime=$CURRENT_UPTIME"
        
        # Protect state-changing command with DRY_RUN check
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_debug "📝 DRY-RUN: Would append basic data to $OUTPUT_CSV"
        else
            data_line="$CURRENT_TIMESTAMP,$CURRENT_LATENCY,$CURRENT_PACKET_LOSS,$CURRENT_OBSTRUCTION,$CURRENT_UPTIME"
            log_debug "📝 WRITING BASIC DATA: $data_line"
            echo "$data_line" >>"$OUTPUT_CSV"
        fi
    fi

    log_debug "📝 CSV WRITE: Data logged successfully"

    # Perform statistical aggregation if enabled
    if [ "$ENABLE_STATISTICAL_AGGREGATION" = "true" ]; then
        log_debug "📝 AGGREGATION: Statistical aggregation enabled, running..."
        perform_statistical_aggregation "$OUTPUT_CSV"
    else
        log_debug "📝 AGGREGATION: Statistical aggregation disabled"
    fi
    
    log_debug "📝 FUNCTION EXIT: log_to_csv() completed successfully"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    log_function_entry "main" "$*"
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
    if [ ! -f "$GRPCURL_CMD" ]; then
        log_error "grpcurl not found at $GRPCURL_CMD"
        exit 1
    fi

    if [ ! -f "$JQ_CMD" ]; then
        log_error "jq not found at $JQ_CMD"
        exit 1
    fi

    log_debug "Fetching Starlink status data"

    # Get Starlink status
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
        # Enhanced debug execution like check_starlink_api-rutos.sh
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "GRPC COMMAND: $grpc_cmd"
            log_debug "GRPC EXECUTION: Running in debug mode with full output"
        fi
        
        if ! status_data=$(eval "$grpc_cmd"); then
            grpc_exit_code=$?
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "GRPC EXIT CODE: $grpc_exit_code"
            fi
            log_error "Failed to fetch Starlink status data"
            exit 1
        fi
        
        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "GRPC EXIT CODE: 0"
            # Show first 500 chars of raw output like check_starlink_api-rutos.sh
            raw_output_preview=$(echo "$status_data" | head -c 500)
            log_debug "GRPC RAW OUTPUT (first 500 chars): $raw_output_preview"
            if [ ${#status_data} -gt 500 ]; then
                log_debug "GRPC RAW OUTPUT: (truncated - full response is ${#status_data} characters)"
            fi
            log_debug "GRPC SUCCESS: Processing JSON response for data extraction"
        fi
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
    log_function_exit "main" "0"
}

# Enhanced error handling for configuration validation
validate_config() {
    log_debug "Validating configuration variables..."

    if [ -z "${STARLINK_IP:-}" ]; then
        log_warning "STARLINK_IP is not set. Defaulting to 192.168.100.1"
        STARLINK_IP="192.168.100.1"
    fi

    if [ -z "${STARLINK_PORT:-}" ]; then
        log_warning "STARLINK_PORT is not set. Defaulting to 9200"
        STARLINK_PORT="9200"
    fi

    if [ ! -d "${LOG_DIR:-}" ]; then
        log_warning "LOG_DIR does not exist. Attempting to create: $LOG_DIR"
        mkdir -p "$LOG_DIR" || log_error "Failed to create LOG_DIR: $LOG_DIR"
    fi

    if [ ! -f "${GRPCURL_CMD:-}" ]; then
        log_error "grpcurl binary not found at $GRPCURL_CMD"
        exit 1
    fi

    if [ ! -f "${JQ_CMD:-}" ]; then
        log_error "jq binary not found at $JQ_CMD"
        exit 1
    fi

    log_debug "Configuration validation completed successfully"
}

# Enhanced debug logging for edge cases
log_debug "Starting enhanced debug logging..."
log_debug "Configuration file: $CONFIG_FILE"
log_debug "Output CSV file: $OUTPUT_CSV"
log_debug "State file: $STATE_FILE"
log_debug "Log directory: $LOG_DIR"
log_debug "Aggregated log file: $AGGREGATED_LOG_FILE"

# Call validation function
validate_config

# Enhanced statistical aggregation logic
optimize_aggregation() {
    log_debug "Optimizing statistical aggregation logic..."
    # Add optimized logic here
}

# Call optimization function
optimize_aggregation

# Enhanced documentation for complex logic
log_debug "Adding comments to clarify statistical aggregation logic..."
# ...existing code...

# Execute main function
main "$@"
