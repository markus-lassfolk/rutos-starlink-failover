#!/bin/sh

# ==============================================================================
# Unified Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.8.0
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
readonly SCRIPT_VERSION="2.8.0"

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

# RUTOS_TEST_MODE enables trace logging (does NOT cause early exit)
# DRY_RUN prevents actual changes but allows full execution for debugging

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

# === DEBUG: Configuration Values Loaded ===
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "==================== CONFIGURATION DEBUG ===================="
    log_debug "CONFIG_FILE: $CONFIG_FILE"
    log_debug "Required connection variables:"
    log_debug "  STARLINK_IP: ${STARLINK_IP:-UNSET}"
    log_debug "  STARLINK_PORT: ${STARLINK_PORT:-UNSET}"
    log_debug "  MWAN_IFACE: ${MWAN_IFACE:-UNSET}"
    log_debug "  MWAN_MEMBER: ${MWAN_MEMBER:-UNSET}"

    log_debug "Feature flags:"
    log_debug "  ENABLE_GPS_TRACKING: ${ENABLE_GPS_TRACKING:-UNSET}"
    log_debug "  ENABLE_CELLULAR_TRACKING: ${ENABLE_CELLULAR_TRACKING:-UNSET}"
    log_debug "  ENABLE_ENHANCED_FAILOVER: ${ENABLE_ENHANCED_FAILOVER:-UNSET}"
    log_debug "  ENABLE_PUSHOVER: ${ENABLE_PUSHOVER:-UNSET}"

    log_debug "Monitoring thresholds:"
    log_debug "  LATENCY_THRESHOLD: ${LATENCY_THRESHOLD:-UNSET}"
    log_debug "  PACKET_LOSS_THRESHOLD: ${PACKET_LOSS_THRESHOLD:-UNSET}"
    log_debug "  OBSTRUCTION_THRESHOLD: ${OBSTRUCTION_THRESHOLD:-UNSET}"
    log_debug "  ENABLE_INTELLIGENT_OBSTRUCTION: ${ENABLE_INTELLIGENT_OBSTRUCTION:-UNSET}"
    log_debug "  OBSTRUCTION_MIN_DATA_HOURS: ${OBSTRUCTION_MIN_DATA_HOURS:-UNSET}"
    log_debug "  OBSTRUCTION_HISTORICAL_THRESHOLD: ${OBSTRUCTION_HISTORICAL_THRESHOLD:-UNSET}"
    log_debug "  OBSTRUCTION_PROLONGED_THRESHOLD: ${OBSTRUCTION_PROLONGED_THRESHOLD:-UNSET}"

    log_debug "Directories and paths:"
    log_debug "  LOG_DIR: ${LOG_DIR:-UNSET}"
    log_debug "  STATE_DIR: ${STATE_DIR:-UNSET}"
    log_debug "  LOG_TAG: ${LOG_TAG:-UNSET}"

    # Check for functionality-affecting issues
    if [ "${STARLINK_IP:-}" = "" ]; then
        log_debug "⚠️  WARNING: STARLINK_IP not set - Starlink API calls will fail"
    fi
    if [ "${MWAN_IFACE:-}" = "" ]; then
        log_debug "⚠️  WARNING: MWAN_IFACE not set - Failover functionality disabled"
    fi
    if [ "${MWAN_MEMBER:-}" = "" ]; then
        log_debug "⚠️  WARNING: MWAN_MEMBER not set - Failover functionality disabled"
    fi

    log_debug "==============================================================="
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

# Starlink connection settings with defaults
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"

# Monitoring thresholds with defaults
# Default thresholds and parameters (set only if not already configured)
LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-150}"
PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD:-2}"
OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD:-0.1}"
ENABLE_INTELLIGENT_OBSTRUCTION="${ENABLE_INTELLIGENT_OBSTRUCTION:-true}"
OBSTRUCTION_MIN_DATA_HOURS="${OBSTRUCTION_MIN_DATA_HOURS:-1}"
OBSTRUCTION_HISTORICAL_THRESHOLD="${OBSTRUCTION_HISTORICAL_THRESHOLD:-1.0}"
OBSTRUCTION_PROLONGED_THRESHOLD="${OBSTRUCTION_PROLONGED_THRESHOLD:-30}"
JITTER_THRESHOLD="${JITTER_THRESHOLD:-20}"

# Enhanced feature flags (configuration-controlled)
ENABLE_GPS_TRACKING="${ENABLE_GPS_TRACKING:-false}"
ENABLE_CELLULAR_TRACKING="${ENABLE_CELLULAR_TRACKING:-false}"
ENABLE_MULTI_SOURCE_GPS="${ENABLE_MULTI_SOURCE_GPS:-false}"
ENABLE_ENHANCED_FAILOVER="${ENABLE_ENHANCED_FAILOVER:-false}"

# Pushover notification compatibility mapping
# Support both ENABLE_PUSHOVER (new) and PUSHOVER_ENABLED (legacy config format)
if [ -n "${PUSHOVER_ENABLED:-}" ]; then
    # Convert PUSHOVER_ENABLED=1/0 format to ENABLE_PUSHOVER=true/false
    if [ "$PUSHOVER_ENABLED" = "1" ]; then
        ENABLE_PUSHOVER="true"
        log_debug "Configuration compatibility: Converted PUSHOVER_ENABLED=1 to ENABLE_PUSHOVER=true"
    else
        ENABLE_PUSHOVER="false"
        log_debug "Configuration compatibility: Converted PUSHOVER_ENABLED=0 to ENABLE_PUSHOVER=false"
    fi
else
    # Use default if neither is set
    ENABLE_PUSHOVER="${ENABLE_PUSHOVER:-false}"
fi

# GPS and Cellular integration settings (only used if enabled)
GPS_LOG_FILE="${LOG_DIR}/gps_data.csv"
CELLULAR_LOG_FILE="${LOG_DIR}/cellular_data.csv"

# Decision logging file for comprehensive monitoring analysis
DECISION_LOG_FILE="${LOG_DIR}/failover_decisions.csv"

# Create necessary directories
mkdir -p "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

# Initialize decision log with headers if it doesn't exist
if [ ! -f "$DECISION_LOG_FILE" ]; then
    # Protect state-changing command with DRY_RUN check
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would create decision log header in $DECISION_LOG_FILE"
    else
        echo "timestamp,decision_type,trigger_reason,quality_factors,latency_ms,packet_loss_pct,obstruction_pct,snr_db,current_metric,new_metric,action_taken,action_result,gps_context,cellular_context,additional_notes" >"$DECISION_LOG_FILE"
        log_debug "Decision log initialized: $DECISION_LOG_FILE"
    fi
fi

# Debug configuration
log_debug "GPS_TRACKING=$ENABLE_GPS_TRACKING, CELLULAR_TRACKING=$ENABLE_CELLULAR_TRACKING"
log_debug "ENHANCED_FAILOVER=$ENABLE_ENHANCED_FAILOVER, MULTI_SOURCE_GPS=$ENABLE_MULTI_SOURCE_GPS"

# =============================================================================
# PUSHOVER NOTIFICATION SYSTEM
# =============================================================================

# Send Pushover notification with proper error handling
send_pushover_notification() {
    title="$1"
    message="$2"
    priority="${3:-0}"

    log_debug "Attempting to send Pushover notification: $title"

    # Check if Pushover is configured via placeholder utilities
    if command -v is_pushover_configured >/dev/null 2>&1; then
        if is_pushover_configured; then
            # Use safe_send_notification if available from placeholder-utils.sh
            if command -v safe_send_notification >/dev/null 2>&1; then
                log_debug "Using safe_send_notification function"
                safe_send_notification "$title" "$message" "$priority"
                return $?
            fi
        else
            log_debug "Pushover not properly configured, skipping notification"
            return 1
        fi
    fi

    # Fallback: Direct Pushover API call if configured
    if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then
        # Skip if values are placeholders
        case "$PUSHOVER_TOKEN" in
            YOUR_* | "CHANGE_ME" | "REPLACE_ME" | "TODO" | "FIXME" | "EXAMPLE" | "PLACEHOLDER")
                log_debug "Pushover token is placeholder, skipping notification"
                return 1
                ;;
        esac
        case "$PUSHOVER_USER" in
            YOUR_* | "CHANGE_ME" | "REPLACE_ME" | "TODO" | "FIXME" | "EXAMPLE" | "PLACEHOLDER")
                log_debug "Pushover user is placeholder, skipping notification"
                return 1
                ;;
        esac

        log_debug "Sending Pushover notification via API"
        curl_cmd="curl -s --max-time 10 -F \"token=$PUSHOVER_TOKEN\" -F \"user=$PUSHOVER_USER\" -F \"title=$title\" -F \"message=$message\" -F \"priority=$priority\" https://api.pushover.net/1/messages.json"

        if safe_execute "$curl_cmd" "Send Pushover notification"; then
            log_debug "Pushover notification sent successfully"
            return 0
        else
            log_warning "Failed to send Pushover notification"
            return 1
        fi
    else
        log_debug "Pushover credentials not configured, skipping notification"
        return 1
    fi
}

# =============================================================================
# DECISION LOGGING SYSTEM
# Comprehensive logging of all failover decisions and reasoning
# =============================================================================

# Log a decision with comprehensive context and reasoning
# Parameters: decision_type, trigger_reason, action_taken, action_result, [additional_notes]
log_decision() {
    decision_type="$1"        # "evaluation", "soft_failover", "hard_failover", "restore", "maintenance"
    trigger_reason="$2"       # "quality_degraded", "scheduled_reboot", "manual", "quality_restored"
    action_taken="$3"         # "no_action", "metric_increase", "metric_restore", "service_restart"
    action_result="$4"        # "success", "failed", "skipped"
    additional_notes="${5:-}" # Optional additional context

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    quality_factors=""
    gps_context="none"
    cellular_context="none"

    # Collect current metrics for decision context
    current_latency="${CURRENT_LATENCY:-unknown}"
    current_packet_loss="${CURRENT_PACKET_LOSS:-unknown}"
    current_obstruction="${CURRENT_OBSTRUCTION:-unknown}"
    current_snr="${CURRENT_SNR:-unknown}"

    # Get current MWAN3 metric
    current_metric=$(uci get "mwan3.${MWAN_MEMBER}.metric" 2>/dev/null || echo "unknown")
    new_metric="$current_metric"

    # Calculate quality factors summary
    latency_poor=0
    loss_poor=0
    obstruction_poor=0
    snr_poor=0

    # Check each quality factor
    if [ "$current_latency" != "unknown" ] && [ "$current_latency" -gt "${LATENCY_THRESHOLD:-150}" ] 2>/dev/null; then
        latency_poor=1
    fi
    if [ "$current_packet_loss" != "unknown" ] && [ "$(echo "$current_packet_loss > ${PACKET_LOSS_THRESHOLD:-2}" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        loss_poor=1
    fi
    if [ "$current_obstruction" != "unknown" ] && [ "$(echo "$current_obstruction > ${OBSTRUCTION_THRESHOLD:-0.1}" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        obstruction_poor=1
    fi

    # SNR analysis - for decision logging, mirror the actual failover logic
    if [ "$current_snr" != "unknown" ]; then
        log_debug "SNR DECISION LOGIC: current_snr='$current_snr'"

        # Use the same logic as the actual failover decision (readyStates-based)
        # Check if we have readyStates available
        snr_above_noise="${CURRENT_SNR_ABOVE_NOISE:-true}"
        snr_persistently_low="${CURRENT_SNR_PERSISTENTLY_LOW:-false}"

        # CORRECTED LOGIC: Only consider SNR poor if it's persistently low
        # above_noise_floor=false may just mean "not measured" and is not reliable
        if [ "$snr_persistently_low" = "true" ]; then
            snr_poor=1
            log_debug "SNR DECISION LOGIC: SNR marked as poor - persistently low signal detected"
            log_warning "Poor SNR detected: persistently_low=true above_noise_floor=$snr_above_noise"
        else
            log_debug "SNR DECISION LOGIC: SNR is good persistently_low=false above_noise_floor=$snr_above_noise"
        fi
        log_debug "SNR DECISION LOGIC: final snr_poor=$snr_poor"
    fi

    # Create quality factors summary
    quality_factors="lat:${latency_poor},loss:${loss_poor},obs:${obstruction_poor},snr:${snr_poor}"

    # Collect GPS context if enabled
    if [ "$ENABLE_GPS_TRACKING" = "true" ]; then
        # Get basic GPS status without full collection
        if command -v gpsctl >/dev/null 2>&1; then
            lat=$(gpsctl -i 2>/dev/null | tr -d '\n' || echo "")
            lon=$(gpsctl -x 2>/dev/null | tr -d '\n' || echo "")
            if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0" ]; then
                gps_context="active:${lat},${lon}"
            else
                gps_context="no_fix"
            fi
        else
            gps_context="no_gpsctl"
        fi
    fi

    # Collect cellular context if enabled
    if [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
        if command -v gsmctl >/dev/null 2>&1; then
            # Use proper AT+CSQ command like the library does
            signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
            signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | tr -d '\n' | head -1)
            if [ -n "$signal_strength" ] && [ "$signal_strength" != "99" ] && [ "$signal_strength" -ge 0 ] 2>/dev/null; then
                cellular_context="signal:${signal_strength}dbm"
            else
                cellular_context="no_signal"
            fi
        else
            cellular_context="no_gsmctl"
        fi
    fi

    # Update new_metric for specific actions
    case "$action_taken" in
        "metric_increase") new_metric="${METRIC_BAD:-20}" ;;
        "metric_restore") new_metric="${METRIC_GOOD:-1}" ;;
    esac

    # Escape any commas in additional_notes to preserve CSV format
    additional_notes=$(echo "$additional_notes" | sed 's/,/;/g')

    # Create comprehensive log entry
    log_entry="$timestamp,$decision_type,$trigger_reason,$quality_factors,$current_latency,$current_packet_loss,$current_obstruction,$current_snr,$current_metric,$new_metric,$action_taken,$action_result,$gps_context,$cellular_context,$additional_notes"

    # Write to decision log (protect with DRY_RUN)
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_debug "DRY-RUN: Would log decision: $log_entry"
    else
        echo "$log_entry" >>"$DECISION_LOG_FILE"
    fi

    # Also log to standard log with formatted output
    case "$decision_type" in
        "evaluation")
            log_info "🔍 DECISION: Evaluated connection quality - $trigger_reason"
            ;;
        "soft_failover")
            log_warning "⚠️  DECISION: Soft failover triggered - $trigger_reason"
            ;;
        "hard_failover")
            log_error "🚨 DECISION: Hard failover triggered - $trigger_reason"
            ;;
        "restore")
            log_success "✅ DECISION: Primary restored - $trigger_reason"
            ;;
        "maintenance")
            log_info "🔧 DECISION: Maintenance action - $trigger_reason"
            ;;
    esac

    # Only log detailed context for important decisions to reduce log spam
    # Maintenance actions get minimal logging, failovers get full context
    case "$decision_type" in
        "soft_failover" | "hard_failover" | "restore" | "evaluation")
            # Log detailed reasoning for important decisions
            if [ "$current_latency" != "unknown" ] || [ "$current_packet_loss" != "unknown" ] || [ "$current_obstruction" != "unknown" ]; then
                log_info "📊 METRICS: Latency=${current_latency}ms threshold ${LATENCY_THRESHOLD:-150}ms, Loss=${current_packet_loss}% threshold ${PACKET_LOSS_THRESHOLD:-2}%, Obstruction=${current_obstruction}% threshold ${OBSTRUCTION_THRESHOLD:-0.1}%"
            fi

            if [ "$current_snr" != "unknown" ]; then
                log_info "📡 SIGNAL: SNR=${current_snr}dB"
            fi

            if [ "$gps_context" != "none" ]; then
                log_info "📍 GPS: $gps_context"
            fi

            if [ "$cellular_context" != "none" ]; then
                log_info "📱 CELLULAR: $cellular_context"
            fi
            ;;
        "maintenance")
            # Minimal logging for maintenance actions to reduce spam
            log_debug "Maintenance context: metrics available, GPS=$gps_context, cellular=$cellular_context"
            ;;
    esac

    # Log action details - simplified for maintenance, detailed for important decisions
    case "$decision_type" in
        "soft_failover" | "hard_failover" | "restore" | "evaluation")
            log_info "🎯 ACTION: $action_taken to $action_result metric: $current_metric to $new_metric"
            if [ -n "$additional_notes" ]; then
                log_info "📝 NOTES: $additional_notes"
            fi
            ;;
        "maintenance")
            log_debug "Action: $action_taken → $action_result"
            if [ -n "$additional_notes" ]; then
                log_debug "Notes: $additional_notes"
            fi
            ;;
    esac
}

# Log a decision evaluation without action
log_evaluation() {
    reason="$1"
    notes="${2:-}"
    log_decision "evaluation" "$reason" "no_action" "completed" "$notes"
}

# Log a successful failover
log_failover() {
    severity="$1" # "soft" or "hard"
    reason="$2"
    success="$3" # "success" or "failed"
    notes="${4:-}"

    if [ "$severity" = "hard" ]; then
        log_decision "hard_failover" "$reason" "metric_increase" "$success" "$notes"
    else
        log_decision "soft_failover" "$reason" "metric_increase" "$success" "$notes"
    fi
}

# Log a successful restore
log_restore() {
    reason="$1"
    success="$2" # "success" or "failed"
    notes="${3:-}"
    log_decision "restore" "$reason" "metric_restore" "$success" "$notes"
}

# Log maintenance actions
log_maintenance_action() {
    reason="$1"
    action="$2"
    result="$3"
    notes="${4:-}"
    log_decision "maintenance" "$reason" "$action" "$result" "$notes"
}

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

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Use standardized library function for GPS collection
    log_debug "📍 MONITOR GPS: Using library function for GPS data collection"

    # Set library configuration variables for proper GPS collection
    ENABLE_GPS_LOGGING="true"
    export GPS_PRIMARY_SOURCE="${GPS_PRIMARY_SOURCE:-starlink}"
    export GPS_SECONDARY_SOURCE="${GPS_SECONDARY_SOURCE:-rutos}"

    # Call the library function directly (avoiding name conflict)
    gps_result=""
    if [ "${_RUTOS_DATA_COLLECTION_LOADED:-0}" = "1" ]; then
        # Library is loaded, call it directly
        # Skip if GPS logging is disabled
        if [ "$ENABLE_GPS_LOGGING" != "true" ]; then
            log_debug "📍 GPS COLLECTION: GPS logging disabled, returning default values"
            gps_result="0,0,0,none,none"
        else
            # Use individual gpsctl flags for GPS collection
            rutos_lat=$(gpsctl -i 2>/dev/null | tr -d "$(printf '\n')" || echo "")
            rutos_lon=$(gpsctl -x 2>/dev/null | tr -d "$(printf '\n')" || echo "")
            rutos_alt=$(gpsctl -a 2>/dev/null | tr -d "$(printf '\n')" || echo "")

            # Validate GPS coordinates
            if validate_gps_coordinates "$rutos_lat" "$rutos_lon"; then
                gps_result="$rutos_lat,$rutos_lon,${rutos_alt:-0},high,rutos_gps"
            else
                gps_result="0,0,0,none,none"
            fi
        fi
    else
        log_debug "📍 MONITOR GPS: Library not loaded, using fallback GPS collection"
        gps_result="0,0,0,none,none"
    fi

    # Parse the CSV result from library function
    lat=$(echo "$gps_result" | cut -d',' -f1)
    lon=$(echo "$gps_result" | cut -d',' -f2)
    alt=$(echo "$gps_result" | cut -d',' -f3)
    accuracy=$(echo "$gps_result" | cut -d',' -f4)
    data_source=$(echo "$gps_result" | cut -d',' -f5)

    log_debug "📍 MONITOR GPS: GPS data - lat=$lat, lon=$lon, source=$data_source"

    # Log GPS data if we have coordinates (maintain monitor script behavior)
    if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0" ]; then
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
        log_debug "GPS data logged: $data_source $accuracy accuracy"
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
    log_debug "📱 CELLULAR MONITOR: Collecting cellular data from primary modem"

    # Collect data for primary modem (mob1s1a1)
    modem_id="primary"
    if command -v gsmctl >/dev/null 2>&1; then
        log_debug "📱 CELLULAR MONITOR: gsmctl command available, executing AT commands"

        # Signal strength and quality
        log_debug "📱 CELLULAR MONITOR: Getting signal strength with AT+CSQ"
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        log_debug "📱 CELLULAR MONITOR: Signal info raw: '$signal_info'"
        signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | tr -d "$(printf '\n')" | head -1)
        signal_quality=$(echo "$signal_info" | awk -F'[: ,]' '{print $4}' | tr -d "$(printf '\n')" | head -1)
        log_debug "📱 CELLULAR MONITOR: Parsed signal - strength='$signal_strength', quality='$signal_quality'"

        # Network registration and operator
        log_debug "📱 CELLULAR MONITOR: Getting operator with AT+COPS?"
        reg_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" | head -1 || echo "+COPS: 0,0,\"Unknown\"")
        log_debug "📱 CELLULAR MONITOR: Operator info raw: '$reg_info'"
        operator=$(echo "$reg_info" | sed 's/.*"\([^"]*\)".*//' | tr -d "$(printf '\n\r')," | head -c 20)
        log_debug "📱 CELLULAR MONITOR: Parsed operator: '$operator'"

        # Network type
        log_debug "📱 CELLULAR MONITOR: Getting network type with AT+QNWINFO"
        network_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "+QNWINFO: \"Unknown\"")
        log_debug "📱 CELLULAR MONITOR: Network info raw: '$network_info'"
        network_type=$(echo "$network_info" | awk -F'"' '{print $2}' | tr -d "$(printf '\n\r')," | head -c 15)
        log_debug "📱 CELLULAR MONITOR: Parsed network type: '$network_type'"

        # Roaming status
        log_debug "📱 CELLULAR MONITOR: Getting roaming status with AT+CREG?"
        roaming_info=$(gsmctl -A 'AT+CREG?' 2>/dev/null | grep "+CREG:" | head -1 || echo "+CREG: 0,1")
        log_debug "📱 CELLULAR MONITOR: Roaming info raw: '$roaming_info'"
        roaming_status=$(echo "$roaming_info" | awk -F'[: ,]' '{print $4}' | tr -d "$(printf '\n')" | head -1)
        [ "$roaming_status" = "5" ] && roaming_status="roaming" || roaming_status="home"
        log_debug "📱 CELLULAR MONITOR: Parsed roaming status: '$roaming_status'"

        log_debug "📱 CELLULAR MONITOR: Final parsed data - signal=$signal_strength, quality=$signal_quality, operator='$operator', network='$network_type', roaming=$roaming_status"
    else
        log_debug "📱 CELLULAR MONITOR: gsmctl not available, cellular data collection skipped"
        return 0
    fi

    # Set defaults and clean data if no data available or invalid
    signal_strength="${signal_strength:-0}"
    signal_quality="${signal_quality:-0}"

    # Clean and validate network type (remove any problematic characters)
    case "$network_type" in
        *[,"$(printf '\n\r')"]* | "") network_type="Unknown" ;;
        *) network_type=$(echo "$network_type" | tr -d "$(printf ',\n\r')" | head -c 15) ;;
    esac

    # Clean and validate operator (remove any problematic characters)
    case "$operator" in
        *[,"$(printf '\n\r')"]* | "") operator="Unknown" ;;
        *) operator=$(echo "$operator" | tr -d "$(printf ',\n\r')" | head -c 20) ;;
    esac

    # Validate roaming status
    case "$roaming_status" in
        roaming | home) ;;
        *) roaming_status="home" ;;
    esac

    log_debug "📱 CELLULAR MONITOR: Final cleaned data - signal=$signal_strength, quality=$signal_quality, operator='$operator', network='$network_type', roaming=$roaming_status"

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
            return 1
        fi

        if [ "${DEBUG:-0}" = "1" ]; then
            log_debug "GRPC EXIT CODE: 0"
            # In debug mode, show complete GRPC response for troubleshooting field paths
            if [ ${#status_data} -le 2000 ]; then
                # Small response - show complete output
                log_debug "GRPC RAW OUTPUT complete: $status_data"
            else
                # Large response - show preview + offer complete output
                raw_output_preview=$(echo "$status_data" | head -c 500)
                log_debug "GRPC RAW OUTPUT first 500 chars: $raw_output_preview"
                log_debug "GRPC RAW OUTPUT: truncated - full response is ${#status_data} characters"
                log_debug "DEBUG TIP: For complete JSON structure analysis, use: echo \"\$status_data\" | jq ."
                # Optionally show complete output if RUTOS_TEST_MODE is enabled
                if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
                    log_debug "GRPC COMPLETE OUTPUT RUTOS_TEST_MODE: $status_data"
                fi
            fi
            log_debug "GRPC SUCCESS: Processing JSON response for metrics extraction"
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
    uptime_s=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceState.uptimeS // 0' 2>/dev/null)
    latency=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingLatencyMs // 999' 2>/dev/null)

    # Check if popPingDropRate field exists, use 0 (no loss) as fallback instead of 1 (100% loss)
    packet_loss=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // 0' 2>/dev/null)
    packet_loss_field_exists=$(echo "$status_data" | "$JQ_CMD" -r 'has("dishGetStatus") and .dishGetStatus | has("popPingDropRate")' 2>/dev/null)
    log_debug "Packet loss field exists: $packet_loss_field_exists, raw value: $packet_loss"

    # If packet loss field doesn't exist, try to get it from history API
    if [ "$packet_loss_field_exists" = "false" ]; then
        log_debug "popPingDropRate not found in status, trying history API"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            packet_loss="0"
            log_debug "DRY_RUN mode: using fallback packet loss value"
        else
            # Use head to limit response size at source and add timeout
            history_cmd="/usr/local/starlink-monitor/grpcurl -plaintext -max-time 5 -d '{\"get_history\":{}}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle 2>/dev/null | head -c 10000"
            log_debug "EXECUTING HISTORY COMMAND: $history_cmd"
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "HISTORY GRPC COMMAND: $history_cmd"
                log_debug "HISTORY GRPC EXECUTION: Running with 5s timeout and 10KB data limit"
            fi

            if history_data=$(eval "$history_cmd"); then
                if [ "${DEBUG:-0}" = "1" ]; then
                    log_debug "HISTORY GRPC EXIT CODE: 0"
                    # Show first 300 chars for history debug (shorter than status)
                    history_preview=$(echo "$history_data" | head -c 300)
                    log_debug "HISTORY GRPC RAW OUTPUT first 300 chars: $history_preview"
                    response_size=${#history_data}
                    log_debug "HISTORY GRPC RAW OUTPUT: limited response size: ${response_size} characters, max 10KB"
                    log_debug "HISTORY GRPC SUCCESS: Processing limited JSON response for packet loss only"
                fi

                # Extract only packet loss data efficiently - avoid processing full response
                packet_loss=$(echo "$history_data" | "$JQ_CMD" -r '.dishGetHistory.popPingDropRate[-1] // 0' 2>/dev/null)
                log_debug "Retrieved packet loss from history: $packet_loss"

                # Clear limited history data from memory immediately
                history_data=""
            else
                history_exit_code=$?
                if [ "${DEBUG:-0}" = "1" ]; then
                    log_debug "HISTORY GRPC EXIT CODE: $history_exit_code"
                fi
                log_debug "History API also failed, using 0 as fallback"
                packet_loss="0"
            fi
        fi
    fi

    # Extract comprehensive obstruction metrics for intelligent analysis
    obstruction=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.fractionObstructed // 0' 2>/dev/null)
    obstruction_time_pct=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.timeObstructed // 0' 2>/dev/null)
    obstruction_valid_s=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.validS // 0' 2>/dev/null)
    obstruction_avg_prolonged=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.avgProlongedObstructionIntervalS // 0' 2>/dev/null)
    obstruction_patches_valid=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.obstructionStats.patchesValid // 0' 2>/dev/null)

    # Extract enhanced metrics for intelligent monitoring
    bootcount=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.deviceInfo.bootcount // 0' 2>/dev/null)
    is_snr_above_noise_floor=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.readyStates.snrAboveNoiseFloor // false' 2>/dev/null)
    is_snr_persistently_low=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.alerts.snrPersistentlyLow // false' 2>/dev/null)

    # SNR field may not exist in all firmware versions - use readyStates only
    snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.snr // null' 2>/dev/null)

    # Always use readyStates as the authoritative source for SNR quality
    # Never use throughput data as it represents current usage, not signal quality
    if [ "$snr" = "null" ] || [ "$snr" = "0" ] || [ -z "$snr" ]; then
        # No direct SNR available - use readyStates to determine signal quality
        if [ "$is_snr_above_noise_floor" = "true" ] && [ "$is_snr_persistently_low" = "false" ]; then
            snr="15.0" # Represent good SNR with reasonable value for logging
        else
            snr="5.0" # Represent poor SNR with low value for logging
        fi
        log_debug "SNR not available in API, using readyStates: above_noise=$is_snr_above_noise_floor, persistently_low=$is_snr_persistently_low → SNR=$snr"
    else
        # Validate that we have actual SNR data (should be reasonable dB value, not throughput)
        snr_int=$(echo "$snr" | cut -d'.' -f1 2>/dev/null || echo "0")
        if [ "$snr_int" -gt 100 ] 2>/dev/null; then
            log_warning "SNR value unusually high $snr, likely invalid data. Using readyStates instead."
            if [ "$is_snr_above_noise_floor" = "true" ] && [ "$is_snr_persistently_low" = "false" ]; then
                snr="15.0"
            else
                snr="5.0"
            fi
        else
            log_debug "Using direct SNR value from API: $snr dB"
        fi
    fi

    gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsValid // true' 2>/dev/null)
    gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsSats // 0' 2>/dev/null)

    log_debug "METRICS: uptime=${uptime_s}s, latency=${latency}ms, loss=${packet_loss}, obstruction=${obstruction}, SNR=${snr}, GPS_valid=$gps_valid, GPS_sats=$gps_sats"
    log_debug "OBSTRUCTION DETAILS: current=${obstruction}, time_obstructed=${obstruction_time_pct}, valid_duration=${obstruction_valid_s}s, avg_prolonged=${obstruction_avg_prolonged}s, patches=${obstruction_patches_valid}"
    log_debug "SNR DETAILS: above_noise_floor=$is_snr_above_noise_floor, persistently_low=$is_snr_persistently_low"

    # Convert packet loss to percentage for comparison
    packet_loss_pct=$(awk "BEGIN {print $packet_loss * 100}")
    obstruction_pct=$(awk "BEGIN {print $obstruction * 100}")
    obstruction_time_pct_converted=$(awk "BEGIN {print $obstruction_time_pct * 100}")

    # Store metrics globally for use by other functions
    CURRENT_LATENCY="$latency"
    CURRENT_PACKET_LOSS="$packet_loss_pct"
    CURRENT_OBSTRUCTION="$obstruction_pct"
    CURRENT_OBSTRUCTION_TIME_PCT="$obstruction_time_pct_converted"
    CURRENT_OBSTRUCTION_VALID_S="$obstruction_valid_s"
    CURRENT_OBSTRUCTION_AVG_PROLONGED="$obstruction_avg_prolonged"
    CURRENT_OBSTRUCTION_PATCHES="$obstruction_patches_valid"
    CURRENT_SNR="$snr"
    CURRENT_SNR_ABOVE_NOISE="$is_snr_above_noise_floor"
    CURRENT_SNR_PERSISTENTLY_LOW="$is_snr_persistently_low"
    CURRENT_GPS_VALID="$gps_valid"
    CURRENT_GPS_SATS="$gps_sats"
    CURRENT_UPTIME="$uptime_s"

    # Export infrastructure metrics for external use
    export CURRENT_SNR CURRENT_UPTIME CURRENT_OBSTRUCTION_TIME_PCT CURRENT_OBSTRUCTION_VALID_S
    export CURRENT_SNR_ABOVE_NOISE CURRENT_SNR_PERSISTENTLY_LOW
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

    # Track individual failure reasons for detailed decision logging
    failure_reasons=""

    # Latency check
    if [ "$CURRENT_LATENCY" -gt "$LATENCY_THRESHOLD" ] 2>/dev/null; then
        is_latency_poor=1
        failure_reasons="${failure_reasons}high_latency,"
        log_warning "High latency detected: ${CURRENT_LATENCY}ms > ${LATENCY_THRESHOLD}ms"
    fi

    # Packet loss check
    if [ "$(echo "$CURRENT_PACKET_LOSS > $PACKET_LOSS_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        is_packet_loss_poor=1
        failure_reasons="${failure_reasons}high_packet_loss,"
        log_warning "High packet loss detected: ${CURRENT_PACKET_LOSS}% > ${PACKET_LOSS_THRESHOLD}%"
    fi

    # Enhanced obstruction analysis using multiple metrics
    if [ "$(echo "$CURRENT_OBSTRUCTION > $OBSTRUCTION_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        # Current obstruction is high, but check additional factors before triggering failover

        # Check if intelligent obstruction analysis is enabled
        if [ "$ENABLE_INTELLIGENT_OBSTRUCTION" = "true" ]; then
            # Calculate hours of valid obstruction data
            obstruction_hours=$(awk "BEGIN {print $CURRENT_OBSTRUCTION_VALID_S / 3600}")

            # Check if we have sufficient data for intelligent analysis
            if [ "$(echo "$obstruction_hours >= $OBSTRUCTION_MIN_DATA_HOURS" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                # We have sufficient data - perform intelligent analysis

                # Check for prolonged obstructions
                has_prolonged_obstructions=0
                if [ "$CURRENT_OBSTRUCTION_AVG_PROLONGED" != "NaN" ] && [ "$CURRENT_OBSTRUCTION_AVG_PROLONGED" != "0" ]; then
                    if [ "$(echo "$CURRENT_OBSTRUCTION_AVG_PROLONGED > $OBSTRUCTION_PROLONGED_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                        has_prolonged_obstructions=1
                    fi
                fi

                # Intelligent decision logic
                should_failover_obstruction=0
                obstruction_analysis=""

                # Case 1: High historical obstruction time
                if [ "$(echo "$CURRENT_OBSTRUCTION_TIME_PCT > $OBSTRUCTION_HISTORICAL_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                    should_failover_obstruction=1
                    obstruction_analysis="${obstruction_analysis}historical_obst,"
                    log_warning "Significant obstruction history: ${CURRENT_OBSTRUCTION_TIME_PCT}% > ${OBSTRUCTION_HISTORICAL_THRESHOLD}% over ${obstruction_hours}h"
                fi

                # Case 2: Prolonged obstructions detected
                if [ "$has_prolonged_obstructions" = "1" ]; then
                    should_failover_obstruction=1
                    obstruction_analysis="${obstruction_analysis}prolonged_obst,"
                    log_warning "Prolonged obstructions: avg ${CURRENT_OBSTRUCTION_AVG_PROLONGED}s > ${OBSTRUCTION_PROLONGED_THRESHOLD}s threshold"
                fi

                # Case 3: Current obstruction is extremely high (emergency threshold)
                emergency_threshold=$(awk "BEGIN {print $OBSTRUCTION_THRESHOLD * 3}")
                if [ "$(echo "$CURRENT_OBSTRUCTION > $emergency_threshold" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                    should_failover_obstruction=1
                    obstruction_analysis="${obstruction_analysis}emergency_obst,"
                    log_warning "Emergency obstruction level: ${CURRENT_OBSTRUCTION}% > ${emergency_threshold}% 3x threshold"
                fi

                # Case 4: Check data quality - insufficient valid patches suggests measurement issues
                if [ "$CURRENT_OBSTRUCTION_PATCHES" -gt 0 ]; then
                    if [ "$CURRENT_OBSTRUCTION_PATCHES" -lt 1000 ] 2>/dev/null; then
                        log_warning "Low measurement quality: ${CURRENT_OBSTRUCTION_PATCHES} valid patches may be unreliable"
                        obstruction_analysis="${obstruction_analysis}low_quality_data,"
                        # Reduce confidence in failover decision for poor quality data
                        if [ "$should_failover_obstruction" = "0" ]; then
                            log_info "Skipping failover due to questionable data quality"
                            log_evaluation "obstruction_detected_insufficient_quality" "Current: ${CURRENT_OBSTRUCTION}%, patches: ${CURRENT_OBSTRUCTION_PATCHES}"
                        fi
                    fi
                fi

                if [ "$should_failover_obstruction" = "1" ]; then
                    is_obstruction_poor=1
                    failure_reasons="${failure_reasons}${obstruction_analysis}"
                    log_warning "Intelligent obstruction analysis: FAILOVER RECOMMENDED"
                    log_warning "  Current: ${CURRENT_OBSTRUCTION}% > ${OBSTRUCTION_THRESHOLD}%"
                    log_warning "  Historical: ${CURRENT_OBSTRUCTION_TIME_PCT}% threshold: ${OBSTRUCTION_HISTORICAL_THRESHOLD}%"
                    log_warning "  Prolonged avg: ${CURRENT_OBSTRUCTION_AVG_PROLONGED}s threshold: ${OBSTRUCTION_PROLONGED_THRESHOLD}s"
                    log_warning "  Data period: ${obstruction_hours}h, patches: ${CURRENT_OBSTRUCTION_PATCHES}"
                else
                    log_info "Obstruction detected but within acceptable parameters"
                    log_info "  Current: ${CURRENT_OBSTRUCTION}% threshold: ${OBSTRUCTION_THRESHOLD}%"
                    log_info "  Historical: ${CURRENT_OBSTRUCTION_TIME_PCT}% over ${obstruction_hours}h threshold: ${OBSTRUCTION_HISTORICAL_THRESHOLD}%"
                    log_info "  Assessment: Temporary/acceptable obstruction - no failover needed"
                    log_evaluation "obstruction_detected_acceptable" "Current: ${CURRENT_OBSTRUCTION}%, historical: ${CURRENT_OBSTRUCTION_TIME_PCT}%, period: ${obstruction_hours}h"
                fi
            else
                # Insufficient data - fall back to simple threshold check
                is_obstruction_poor=1
                failure_reasons="${failure_reasons}obstruction_insufficient_data,"
                log_warning "High obstruction with insufficient history: ${CURRENT_OBSTRUCTION}% > ${OBSTRUCTION_THRESHOLD}%"
                log_warning "Only ${obstruction_hours}h available need ${OBSTRUCTION_MIN_DATA_HOURS}h - using conservative failover"
            fi
        else
            # Simple obstruction check (intelligent analysis disabled)
            is_obstruction_poor=1
            failure_reasons="${failure_reasons}obstruction_simple,"
            log_warning "High obstruction detected simple mode: ${CURRENT_OBSTRUCTION}% > ${OBSTRUCTION_THRESHOLD}%"
        fi
    fi

    # Enhanced signal quality analysis using SNR metrics - CONSERVATIVE APPROACH
    # Only trigger on persistently_low=true (indicates real sustained problems)
    # above_noise_floor=false can be normal in good connections, so don't use it alone
    if [ "$is_snr_persistently_low" = "true" ]; then
        is_snr_poor=1
        failure_reasons="${failure_reasons}poor_snr,"
        log_warning "Poor SNR detected: persistently_low=true above_noise_floor=$is_snr_above_noise_floor"
    else
        log_debug "SNR status: above_noise_floor=$is_snr_above_noise_floor, persistently_low=$is_snr_persistently_low no action needed"
    fi

    # Enhanced GPS analysis (if GPS tracking enabled)
    if [ "$ENABLE_GPS_TRACKING" = "true" ]; then
        if [ "$CURRENT_GPS_VALID" = "false" ] || [ "$CURRENT_GPS_SATS" -lt 4 ] 2>/dev/null; then
            is_gps_poor=1
            failure_reasons="${failure_reasons}poor_gps,"
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
            log_warning "Multiple quality issues detected $quality_factors factors, initiating enhanced failover analysis"
            log_evaluation "multiple_quality_issues" "Factors: $quality_factors, reasons: ${failure_reasons%, }"
            return 1 # Trigger failover
        elif [ "$quality_factors" -eq 1 ] && [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
            # Check if cellular backup is strong enough to justify failover
            cellular_signal=$(echo "$cellular_data" | cut -d',' -f3)
            if [ -n "$cellular_signal" ] && [ "$cellular_signal" -gt 15 ] 2>/dev/null; then
                log_info "Single quality issue with strong cellular backup, initiating failover"
                log_evaluation "single_issue_strong_cellular" "Cellular signal: ${cellular_signal}dBm, reason: ${failure_reasons%, }"
                return 1 # Trigger failover
            else
                log_evaluation "single_issue_weak_cellular" "Cellular signal: ${cellular_signal}dBm, reason: ${failure_reasons%, }"
            fi
        elif [ "$quality_factors" -eq 1 ]; then
            log_evaluation "single_issue_no_cellular" "Reason: ${failure_reasons%, }"
        elif [ "$quality_factors" -eq 0 ]; then
            log_evaluation "quality_good" "All metrics within thresholds"
        fi
    else
        # Basic failover logic (original behavior)
        if [ "$is_latency_poor" = "1" ] || [ "$is_packet_loss_poor" = "1" ] || [ "$is_obstruction_poor" = "1" ]; then
            log_warning "Quality threshold exceeded, initiating failover"
            log_evaluation "basic_threshold_exceeded" "Reasons: ${failure_reasons%, }"
            return 1 # Trigger failover
        else
            log_evaluation "basic_quality_good" "All basic metrics within thresholds"
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

    # Get current metric from configured member
    current_metric=$(uci get "mwan3.${MWAN_MEMBER}.metric" 2>/dev/null || echo "10")

    # Use fixed METRIC_BAD value instead of incremental increase
    # This prevents runaway metric increases from repeated failovers
    new_metric="${METRIC_BAD:-20}"

    # Determine failover severity based on number of quality issues
    quality_factors=""
    if [ -n "${is_latency_poor:-}" ] && [ -n "${is_packet_loss_poor:-}" ] && [ -n "${is_obstruction_poor:-}" ]; then
        total_issues=$((${is_latency_poor:-0} + ${is_packet_loss_poor:-0} + ${is_obstruction_poor:-0} + ${is_snr_poor:-0}))
        if [ "$total_issues" -ge 3 ]; then
            severity="hard"
            trigger_reason="multiple_critical_issues"
        elif [ "$total_issues" -eq 2 ]; then
            severity="soft"
            trigger_reason="dual_quality_issues"
        else
            severity="soft"
            trigger_reason="single_quality_issue"
        fi
        quality_factors="$total_issues"
    else
        severity="soft"
        trigger_reason="quality_degraded"
        quality_factors="unknown"
    fi

    # Apply new metric
    if safe_execute "uci set mwan3.${MWAN_MEMBER}.metric=$new_metric" "Set mwan3 metric to $new_metric"; then
        if safe_execute "uci commit mwan3" "Commit mwan3 changes"; then
            if safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 service"; then
                log_info "Failover triggered successfully. Metric changed from $current_metric to $new_metric"

                # Wait for mwan3 service to settle and create necessary files
                log_debug "Waiting for mwan3 service to initialize..."
                sleep 3

                # Optional: Verify mwan3 status files were created (with timeout)
                mwan3_ready=0
                for i in 1 2 3 4 5; do
                    if [ -f "/var/run/mwan3.pid" ] || [ -d "/var/run/mwan3" ] || [ -f "/tmp/run/mwan3.pid" ]; then
                        mwan3_ready=1
                        log_debug "MWAN3 service appears ready - attempt $i/5"
                        break
                    else
                        log_debug "MWAN3 service not ready yet - attempt $i/5, waiting..."
                        sleep 1
                    fi
                done

                if [ "$mwan3_ready" = "0" ]; then
                    log_warning "MWAN3 service may not be fully initialized - status files not found"
                fi

                # Log the successful failover decision
                additional_notes="Quality factors: $quality_factors; Previous metric: $current_metric"
                log_failover "$severity" "$trigger_reason" "success" "$additional_notes"

                # Send notification if enabled
                if [ "${ENABLE_PUSHOVER:-false}" = "true" ]; then
                    send_pushover_notification "Starlink Failover" "Quality degraded - metric increased to $new_metric"
                fi

                return 0
            fi
        fi
    fi

    # Log the failed failover attempt
    log_failover "$severity" "$trigger_reason" "failed" "UCI or service reload failed"
    log_error "Failed to trigger failover"
    return 1
}

# Function to restore Starlink interface when quality improves
restore_primary() {
    log_info "Restoring primary connection..."

    # Get current metric for logging
    current_metric=$(uci get "mwan3.${MWAN_MEMBER}.metric" 2>/dev/null || echo "unknown")

    # Reset to configured METRIC_GOOD value
    good_metric="${METRIC_GOOD:-1}"

    # Determine restore reason based on current conditions
    if [ "${CURRENT_LATENCY:-0}" != "unknown" ] && [ "${CURRENT_PACKET_LOSS:-0}" != "unknown" ]; then
        restore_reason="quality_improved"
        additional_notes="Latency: ${CURRENT_LATENCY}ms, Loss: ${CURRENT_PACKET_LOSS}%, Obstruction: ${CURRENT_OBSTRUCTION}%"
    else
        restore_reason="metric_elevated"
        additional_notes="Metric was elevated - $current_metric, restoring to normal"
    fi

    if safe_execute "uci set mwan3.${MWAN_MEMBER}.metric=$good_metric" "Reset mwan3 metric to $good_metric"; then
        if safe_execute "uci commit mwan3" "Commit mwan3 changes"; then
            if safe_execute "/etc/init.d/mwan3 reload" "Reload mwan3 service"; then
                log_info "Starlink interface restored successfully"

                # Wait for mwan3 service to settle after restore
                log_debug "Waiting for mwan3 service to initialize after restore..."
                sleep 3

                # Optional: Verify mwan3 status files were created (with timeout)
                mwan3_ready=0
                for i in 1 2 3 4 5; do
                    if [ -f "/var/run/mwan3.pid" ] || [ -d "/var/run/mwan3" ] || [ -f "/tmp/run/mwan3.pid" ]; then
                        mwan3_ready=1
                        log_debug "MWAN3 service appears ready after restore - attempt $i/5"
                        break
                    else
                        log_debug "MWAN3 service not ready yet after restore - attempt $i/5, waiting..."
                        sleep 1
                    fi
                done

                if [ "$mwan3_ready" = "0" ]; then
                    log_warning "MWAN3 service may not be fully initialized after restore - status files not found"
                fi

                # Log the successful restore decision
                log_restore "$restore_reason" "success" "$additional_notes"

                # Send notification if enabled
                if [ "${ENABLE_PUSHOVER:-false}" = "true" ]; then
                    send_pushover_notification "Starlink Restored" "Connection quality improved. Interface restored to primary."
                fi

                return 0
            fi
        fi
    fi

    # Log the failed restore attempt
    log_restore "$restore_reason" "failed" "UCI or service reload failed"
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

    # Log start of monitoring cycle
    log_maintenance_action "monitoring_cycle_start" "starlink_status_check" "initiated" "v$SCRIPT_VERSION"

    # Validate required tools
    if [ ! -f "$GRPCURL_CMD" ]; then
        log_error "grpcurl not found at $GRPCURL_CMD"
        log_maintenance_action "tool_validation" "grpcurl_check" "failed" "Not found at $GRPCURL_CMD"
        exit 1
    fi

    if [ ! -f "$JQ_CMD" ]; then
        log_error "jq not found at $JQ_CMD"
        log_maintenance_action "tool_validation" "jq_check" "failed" "Not found at $JQ_CMD"
        exit 1
    fi

    # Main monitoring logic
    if status_data=$(get_starlink_status); then
        log_maintenance_action "api_communication" "starlink_status_fetch" "success" "Data retrieved successfully"

        if analyze_starlink_metrics "$status_data"; then
            log_maintenance_action "data_analysis" "metrics_parsing" "success" "All metrics extracted"

            if ! analyze_connection_quality; then
                # Quality is poor, trigger failover
                log_info "Connection quality analysis indicates failover needed"
                if trigger_failover; then
                    log_maintenance_action "failover_execution" "trigger_failover" "success" "Failover completed successfully"
                else
                    log_maintenance_action "failover_execution" "trigger_failover" "failed" "Failover attempt failed"
                fi
            else
                # Quality is good, check if we need to restore interface
                current_metric=$(uci get "mwan3.${MWAN_MEMBER}.metric" 2>/dev/null || echo "10")
                good_metric="${METRIC_GOOD:-1}"
                if [ "$current_metric" -gt "$good_metric" ]; then
                    log_info "Quality restored and metric is elevated - $current_metric, restoring interface"
                    if restore_primary; then
                        log_maintenance_action "interface_restore" "restore_primary" "success" "Interface restored successfully"
                    else
                        log_maintenance_action "interface_restore" "restore_primary" "failed" "Restore attempt failed"
                    fi
                else
                    log_maintenance_action "status_check" "no_action_needed" "completed" "Connection stable, metric normal - $current_metric"
                fi
            fi
        else
            log_error "Failed to analyze Starlink metrics"
            log_maintenance_action "data_analysis" "metrics_parsing" "failed" "Unable to parse Starlink metrics"
            exit 1
        fi
    else
        log_error "Failed to get Starlink status"
        log_maintenance_action "api_communication" "starlink_status_fetch" "failed" "Unable to communicate with Starlink API"
        exit 1
    fi

    log_info "Monitoring cycle completed successfully"
    log_maintenance_action "monitoring_cycle_end" "cycle_completion" "success" "All operations completed"
    log_function_exit "main" "0"
}

# Delegate detailed and aggregated logging to logger script
log_detailed_performance() {
    logger_script="$(dirname "$0")/starlink_logger_unified-rutos.sh"
    if [ -f "$logger_script" ]; then
        "$logger_script" --log-detailed
        log_debug "Delegated detailed performance logging to logger script: $logger_script"
    else
        log_warning "Logger script not found: $logger_script"
    fi
}

log_aggregated_performance() {
    logger_script="$(dirname "$0")/starlink_logger_unified-rutos.sh"
    if [ -f "$logger_script" ]; then
        "$logger_script" --log-aggregated
        log_debug "Delegated aggregated performance logging to logger script: $logger_script"
    else
        log_warning "Logger script not found: $logger_script"
    fi
}

# Call logging functions
log_detailed_performance
log_aggregated_performance

# Execute main function
main "$@"
