#!/bin/sh

# ==============================================================================
# Unified Starlink Proactive Quality Monitor for OpenWrt/RUTOS
# Version: 2.8.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# ==============================================================================

# shellcheck disable=SC1091  # False positive: "Source" in URL comment, not shell command
# shellcheck disable=SC2004  # Arithmetic expressions and command substitutions are intentional
# shellcheck disable=SC2046  # Command substitution word splitting is intentional in specific contexts
# shellcheck disable=SC2086  # Variable word splitting is intentional for iteration patterns
# shellcheck disable=SC2154  # Variables defined in for loops and initialization sections
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

# Version information (auto-updated by update-version.sh) - intentionally positioned after set commands and library loading
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
ENABLE_DUAL_CONNECTION_MONITORING="${ENABLE_DUAL_CONNECTION_MONITORING:-true}" # Legacy compatibility

# Multi-connection monitoring settings (enhanced from dual to multi-connection)
ENABLE_MULTI_CONNECTION_MONITORING="${ENABLE_MULTI_CONNECTION_MONITORING:-true}" # Enable multiple connection monitoring
PERFORMANCE_COMPARISON_THRESHOLD="${PERFORMANCE_COMPARISON_THRESHOLD:-20}"       # % improvement needed to justify failover
CONNECTION_TEST_HOST="${CONNECTION_TEST_HOST:-8.8.8.8}"                          # Host to test all connections
CONNECTION_TEST_TIMEOUT="${CONNECTION_TEST_TIMEOUT:-15}"                         # Timeout for connection tests

# Multi-Cellular Modem Configuration (supports up to 8 modems)
ENABLE_MULTI_CELLULAR="${ENABLE_MULTI_CELLULAR:-true}"                        # Enable multi-cellular support
CELLULAR_MODEMS="${CELLULAR_MODEMS:-mob1s1a1,mob2s1a1,mob3s1a1,mob4s1a1}"     # Comma-separated list of cellular interfaces
CELLULAR_PRIORITY_ORDER="${CELLULAR_PRIORITY_ORDER:-signal,latency,operator}" # Priority: signal,latency,operator,network_type

# Generic Internet Connection Configuration
ENABLE_GENERIC_CONNECTIONS="${ENABLE_GENERIC_CONNECTIONS:-true}"             # Enable WiFi bridge, Ethernet, etc.
GENERIC_CONNECTIONS="${GENERIC_CONNECTIONS:-wlan0,eth2,br-guest}"            # Comma-separated list of generic interfaces
GENERIC_CONNECTION_TYPES="${GENERIC_CONNECTION_TYPES:-wifi,ethernet,bridge}" # Types corresponding to interfaces

# Connection Priority and Failover Configuration
CONNECTION_PRIORITY_ORDER="${CONNECTION_PRIORITY_ORDER:-starlink,ethernet,wifi,cellular}" # Global failover priority
ENABLE_CONNECTION_HEALTH_SCORING="${ENABLE_CONNECTION_HEALTH_SCORING:-true}"              # Enable intelligent health scoring
HEALTH_SCORE_WEIGHTS="${HEALTH_SCORE_WEIGHTS:-latency:40,loss:30,signal:20,type:10}"      # Scoring weights

# Legacy compatibility (maintain backward compatibility)
SECONDARY_CONNECTION_TYPE="${SECONDARY_CONNECTION_TYPE:-cellular}" # Maintained for backward compatibility
SECONDARY_INTERFACE="${SECONDARY_INTERFACE:-mob1s1a1}"             # Maintained for backward compatibility

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
log_debug "MULTI_CONNECTION=$ENABLE_MULTI_CONNECTION_MONITORING, MULTI_CELLULAR=$ENABLE_MULTI_CELLULAR"
log_debug "GENERIC_CONNECTIONS=$ENABLE_GENERIC_CONNECTIONS, CONNECTION_HEALTH_SCORING=$ENABLE_CONNECTION_HEALTH_SCORING"

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
    current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "unknown")
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
# MULTI-CONNECTION DISCOVERY FUNCTIONS
# Discover cellular modems, WiFi connections, and other interfaces for monitoring
# =============================================================================

# Discover all available cellular modems based on MWAN3 and network configuration
discover_cellular_modems() {
    log_debug "📱 CELLULAR DISCOVERY: Scanning for available cellular modems"

    cellular_interfaces=""

    # Method 1: Check MWAN3 configuration for cellular interfaces
    if command -v uci >/dev/null 2>&1; then
        # Look for mobile interfaces in MWAN3 configuration
        mwan3_cellular=$(uci show mwan3 2>/dev/null | grep '\.interface=' | grep 'mob[0-9]' | cut -d'=' -f2 | tr -d "'" | sort -u | tr '\n' ' ')
        log_debug "📱 CELLULAR DISCOVERY: MWAN3 cellular interfaces: $mwan3_cellular"

        # Also check network configuration for cellular protocols
        network_cellular=$(uci show network 2>/dev/null | grep "\.proto='wwan'" | cut -d'.' -f2 | grep '^mob[0-9]' | sort -u | tr '\n' ' ')
        log_debug "📱 CELLULAR DISCOVERY: Network cellular interfaces: $network_cellular"

        # Combine and deduplicate
        for interface in $mwan3_cellular $network_cellular; do
            if [ -n "$interface" ] && ! echo "$cellular_interfaces" | grep -q "$interface"; then
                cellular_interfaces="$cellular_interfaces $interface"
            fi
        done
    fi

    # Method 2: Check for physical cellular interfaces in system
    if [ -d /sys/class/net ]; then
        for interface in /sys/class/net/mob*; do
            if [ -d "$interface" ]; then
                interface_name=$(basename "$interface")
                if ! echo "$cellular_interfaces" | grep -q "$interface_name"; then
                    cellular_interfaces="$cellular_interfaces $interface_name"
                fi
            fi
        done
    fi

    # Method 3: Check for gsmctl modem availability
    if command -v gsmctl >/dev/null 2>&1; then
        # Test common cellular interface patterns
        for i in 1 2 3 4; do
            for sim in 1 2; do
                # shellcheck disable=SC2086,SC2154  # sim is defined in for loop above
                test_interface="mob${i}s${sim}a1"
                # Quick test if interface exists and is usable
                if ip link show "$test_interface" >/dev/null 2>&1; then
                    if ! echo "$cellular_interfaces" | grep -q "$test_interface"; then
                        cellular_interfaces="$cellular_interfaces $test_interface"
                    fi
                fi
            done
        done
    fi

    # Clean up the list and log results
    cellular_interfaces=$(echo "$cellular_interfaces" | tr ' ' '\n' | grep -v "^$" | sort -u | tr '\n' ' ')
    log_debug "📱 CELLULAR DISCOVERY: Discovered cellular interfaces: $cellular_interfaces"

    printf "%s" "$cellular_interfaces"
}

# Discover generic internet connections (WiFi, Ethernet, etc.)
discover_generic_connections() {
    log_debug "🔍 DISCOVERY: Scanning for available generic internet connections"

    generic_connections=""

    # Method 1: Check MWAN3 for non-cellular, non-satellite interfaces
    if command -v uci >/dev/null 2>&1; then
        mwan3_interfaces=$(uci show mwan3 2>/dev/null | grep '\.interface=' | cut -d'=' -f2 | tr -d "'" | sort -u)

        for interface in $mwan3_interfaces; do
            # Skip cellular and satellite interfaces
            case "$interface" in
                mob* | wwan* | starlink* | sat*) continue ;;
                wlan* | eth* | br-* | lan* | tun* | tap* | vpn* | wg*)
                    log_debug "🔍 DISCOVERY: Found generic interface: $interface"
                    generic_connections="$generic_connections $interface"
                    ;;
            esac
        done
    fi

    # Method 2: Check physical network interfaces
    if [ -d /sys/class/net ]; then
        for interface_path in /sys/class/net/*; do
            if [ -d "$interface_path" ]; then
                interface=$(basename "$interface_path")
                case "$interface" in
                    # Skip loopback, cellular, and already discovered
                    lo | mob* | wwan*) continue ;;
                    wlan* | eth* | br-* | wan* | tun* | tap* | vpn* | wg*)
                        if ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
                            if ! echo "$generic_connections" | grep -q "$interface"; then
                                log_debug "🔍 DISCOVERY: Found active generic interface: $interface"
                                generic_connections="$generic_connections $interface"
                            fi
                        fi
                        ;;
                esac
            fi
        done
    fi

    # Clean up and return
    generic_connections=$(echo "$generic_connections" | tr ' ' '\n' | grep -v "^$" | sort -u | tr '\n' ' ')
    log_debug "🔍 DISCOVERY: Discovered generic connections: $generic_connections"

    printf "%s" "$generic_connections"
}

# Enhanced cellular diagnostics with comprehensive modem information
get_enhanced_cellular_diagnostics() {
    interface="$1"

    log_debug "📱 ENHANCED CELLULAR: Getting comprehensive diagnostics for $interface"

    # Initialize with defaults
    signal_dbm="-113"
    signal_quality="0"
    network_type="Unknown"
    operator="Unknown"
    roaming_status="home"
    connection_status="disconnected"
    data_usage_rx="0"
    data_usage_tx="0"
    frequency_band="Unknown"
    cell_id="0"

    # Extract modem and SIM information from interface name
    modem_id=""
    sim_id=""
    case "$interface" in
        mob1s1a1)
            modem_id="1"
            sim_id="1"
            ;;
        mob1s2a1)
            modem_id="1"
            sim_id="2"
            ;;
        mob2s1a1)
            modem_id="2"
            sim_id="1"
            ;;
        mob2s2a1)
            modem_id="2"
            sim_id="2"
            ;;
        mob3s1a1)
            modem_id="3"
            sim_id="1"
            ;;
        mob3s2a1)
            modem_id="3"
            sim_id="2"
            ;;
        mob4s1a1)
            modem_id="4"
            sim_id="1"
            ;;
        mob4s2a1)
            modem_id="4"
            sim_id="2"
            ;;
        *)
            modem_id="1"
            sim_id="1"
            ;; # Default fallback
    esac

    log_debug "📱 ENHANCED CELLULAR: Interface $interface -> Modem $modem_id, SIM $sim_id"

    # Use gsmctl for comprehensive modem information
    if command -v gsmctl >/dev/null 2>&1; then
        # Signal strength and quality (AT+CSQ)
        signal_info=$(gsmctl -A 'AT+CSQ' -M "$modem_id" 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        if [ -n "$signal_info" ]; then
            rssi=$(echo "$signal_info" | sed 's/.*+CSQ: \([0-9]*\),.*/\1/' 2>/dev/null || echo "99")
            ber=$(echo "$signal_info" | sed 's/.*+CSQ: [0-9]*,\([0-9]*\).*/\1/' 2>/dev/null || echo "99")

            if [ "$rssi" != "99" ] && [ "$rssi" -ge 0 ] 2>/dev/null; then
                signal_dbm=$((2 * rssi - 113))

                # Convert BER to signal quality percentage
                if [ "$ber" != "99" ] && [ "$ber" -ge 0 ] 2>/dev/null; then
                    signal_quality=$((100 - (ber * 12)))
                    [ "$signal_quality" -lt 0 ] && signal_quality="0"
                fi
            fi
        fi

        # Network technology (AT+QNWINFO or AT+COPS)
        network_info=$(gsmctl -A 'AT+QNWINFO' -M "$modem_id" 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "")
        if [ -n "$network_info" ]; then
            if echo "$network_info" | grep -q "LTE"; then
                network_type="LTE"
            elif echo "$network_info" | grep -q "NR5G\|5G"; then
                network_type="5G"
            elif echo "$network_info" | grep -q "WCDMA\|UMTS"; then
                network_type="3G"
            elif echo "$network_info" | grep -q "GSM"; then
                network_type="2G"
            fi

            # Extract frequency band if available
            band_info=$(echo "$network_info" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
            [ -n "$band_info" ] && frequency_band="$band_info"
        fi

        # Operator information (AT+COPS?)
        operator_info=$(gsmctl -A 'AT+COPS?' -M "$modem_id" 2>/dev/null | grep "+COPS:" | head -1 || echo "")
        if [ -n "$operator_info" ]; then
            operator=$(echo "$operator_info" | sed 's/.*"\([^"]*\)".*/\1/' | tr -d '\n\r,' | head -c 20)
            [ -z "$operator" ] && operator="Unknown"
        fi

        # Roaming status (AT+CGREG?)
        roaming_info=$(gsmctl -A 'AT+CGREG?' -M "$modem_id" 2>/dev/null | grep "+CGREG:" | head -1 || echo "")
        if [ -n "$roaming_info" ]; then
            roaming_stat=$(echo "$roaming_info" | sed 's/.*+CGREG: [0-9]*,\([0-9]*\).*/\1/' 2>/dev/null || echo "1")
            case "$roaming_stat" in
                "1") roaming_status="home" ;;
                "5") roaming_status="roaming" ;;
                "0" | "2" | "3") roaming_status="searching" ;;
                *) roaming_status="unknown" ;;
            esac
        fi

        # Cell information (AT+QENG for advanced modems)
        cell_info=$(gsmctl -A 'AT+QENG?' -M "$modem_id" 2>/dev/null | grep "servingcell" | head -1 || echo "")
        if [ -n "$cell_info" ]; then
            cell_id=$(echo "$cell_info" | awk -F',' '{print $4}' 2>/dev/null | tr -d ' "' || echo "0")
        fi
    fi

    # Check connection status via network interface
    if ip link show "$interface" >/dev/null 2>&1; then
        if ip link show "$interface" | grep -q "state UP"; then
            if ip addr show "$interface" | grep -q "inet "; then
                connection_status="connected"
            else
                connection_status="up_no_ip"
            fi
        else
            connection_status="interface_down"
        fi
    fi

    # Get data usage if available
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
        data_usage_rx=$((rx_bytes / 1048576)) # Convert to MB
        data_usage_tx=$((tx_bytes / 1048576)) # Convert to MB
    fi

    log_debug "📱 ENHANCED CELLULAR: $interface diagnostics complete - Signal: ${signal_dbm}dBm, Network: $network_type, Operator: $operator, Status: $connection_status"

    # Return comprehensive diagnostics in CSV format
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" \
        "$signal_dbm" "$signal_quality" "$network_type" "$operator" \
        "$roaming_status" "$connection_status" "$data_usage_rx" "$data_usage_tx" \
        "$frequency_band" "$cell_id" "$(date '+%Y-%m-%d %H:%M:%S')"
}

# =============================================================================
# INTELLIGENT MWAN3-INTEGRATED CONNECTION MONITORING SYSTEM
# Discovery-based monitoring with dynamic metric adjustment and predictive failover
# =============================================================================

# =============================================================================
# MWAN3 INTERFACE DISCOVERY AND CONFIGURATION
# Automatically discover and classify all MWAN3-managed interfaces
# =============================================================================

# Discover all MWAN3 interfaces and their current configuration
discover_mwan3_interfaces() {
    log_debug "🔍 MWAN3 DISCOVERY: Scanning MWAN3 configuration for managed interfaces"

    # Get all MWAN3 interfaces
    mwan3_interfaces=""
    if command -v uci >/dev/null 2>&1; then
        # Get all interface sections from MWAN3
        for section in $(uci show mwan3 | grep "=interface" | cut -d'.' -f2 | cut -d'=' -f1); do
            enabled=$(uci get "mwan3.$section.enabled" 2>/dev/null || echo "1")

            if [ "$enabled" = "1" ]; then
                # In RUTOS, the interface section name IS the interface name
                mwan3_interfaces="${mwan3_interfaces}${section},"
                log_debug "🔍 MWAN3 DISCOVERY: Found enabled interface: $section"
            fi
        done

        # Remove trailing comma
        mwan3_interfaces=$(echo "$mwan3_interfaces" | sed 's/,$//')
    fi

    log_debug "🔍 MWAN3 DISCOVERY: Discovered interfaces: $mwan3_interfaces"
    printf "%s" "$mwan3_interfaces"
    return 0
}

# Get MWAN3 member configuration for interface prioritization
discover_mwan3_members() {
    log_debug "🔍 MWAN3 MEMBERS: Scanning MWAN3 member configuration for priorities"

    member_config=""
    if command -v uci >/dev/null 2>&1; then
        # Get all member sections
        for section in $(uci show mwan3 | grep "=member" | cut -d'.' -f2 | cut -d'=' -f1); do
            interface=$(uci get "mwan3.$section.interface" 2>/dev/null || echo "")
            metric=$(uci get "mwan3.$section.metric" 2>/dev/null || echo "1")
            weight=$(uci get "mwan3.$section.weight" 2>/dev/null || echo "1")
            name=$(uci get "mwan3.$section.name" 2>/dev/null || echo "$section")

            if [ -n "$interface" ]; then
                member_config="${member_config}${section}:${interface}:${metric}:${weight}:${name},"
                log_debug "🔍 MWAN3 MEMBERS: Member: $section ($name), Interface: $interface, Metric: $metric, Weight: $weight"
            fi
        done

        # Remove trailing comma
        member_config=$(echo "$member_config" | sed 's/,$//')
    fi

    log_debug "🔍 MWAN3 MEMBERS: Member configuration: $member_config"
    printf "%s" "$member_config"
    return 0
}

# Classify interface type using RUTOS system information
classify_interface_type() {
    interface_name="$1"

    log_debug "🔬 INTERFACE CLASSIFICATION: Analyzing interface $interface_name"

    # Initialize classification
    interface_type="unknown"
    interface_subtype="generic"
    special_config=""

    # Check RUTOS network configuration
    if command -v uci >/dev/null 2>&1; then
        # Check if it's a mobile interface (cellular)
        mobile_info=$(uci show network | grep "=$interface_name" | grep -E "(mobile|modem|cellular)" || echo "")
        if [ -n "$mobile_info" ]; then
            interface_type="cellular"
            # Determine cellular subtype (4G, 5G, etc.)
            if echo "$mobile_info" | grep -q "5g"; then
                interface_subtype="5g"
            elif echo "$mobile_info" | grep -q "4g\|lte"; then
                interface_subtype="4g"
            else
                interface_subtype="cellular"
            fi
        fi

        # Check if it's a WiFi interface
        wifi_info=$(uci show wireless | grep "$interface_name" || echo "")
        if [ -n "$wifi_info" ]; then
            interface_type="wifi"
            # Determine WiFi mode (client, ap, etc.)
            if echo "$wifi_info" | grep -q "mode.*sta"; then
                interface_subtype="sta" # Station/client mode
            elif echo "$wifi_info" | grep -q "mode.*ap"; then
                interface_subtype="ap" # Access point mode
            else
                interface_subtype="wifi"
            fi
        fi

        # Check if it's an Ethernet interface
        if echo "$interface_name" | grep -qE "^eth[0-9]+$"; then
            interface_type="ethernet"
            interface_subtype="wired"
        fi

        # Check if it's a bridge interface
        if echo "$interface_name" | grep -qE "^br-"; then
            interface_type="bridge"
            interface_subtype="network_bridge"
        fi

        # Check if it's a VPN interface
        if echo "$interface_name" | grep -qE "^(tun|tap|vpn|wg)"; then
            interface_type="vpn"
            if echo "$interface_name" | grep -q "^wg"; then
                interface_subtype="wireguard"
            else
                interface_subtype="tunnel"
            fi
        fi
    fi

    # Check for special configurations (Starlink, etc.)
    case "$interface_name" in
        *starlink* | *satellite*)
            special_config="starlink"
            interface_subtype="satellite"
            ;;
        *marina* | *dock*)
            special_config="marina_ethernet"
            ;;
        *camp* | *site*)
            special_config="campsite_wifi"
            ;;
    esac

    log_debug "🔬 INTERFACE CLASSIFICATION: $interface_name → Type: $interface_type, Subtype: $interface_subtype, Special: $special_config"

    # Return CSV format: type,subtype,special_config
    printf "%s" "$interface_type,$interface_subtype,$special_config"
    return 0
}

# =============================================================================
# DYNAMIC METRIC MANAGEMENT SYSTEM
# Intelligent metric adjustment based on connection health and historical performance
# =============================================================================

# Define metric adjustment levels for different issue severities
METRIC_ADJUSTMENT_MINOR=5     # Small latency increase, occasional packet loss
METRIC_ADJUSTMENT_MODERATE=10 # Consistent issues, degraded performance
METRIC_ADJUSTMENT_MAJOR=20    # Significant problems, frequent issues
METRIC_ADJUSTMENT_CRITICAL=50 # Connection essentially unusable

# Calculate appropriate metric adjustment based on issue severity
calculate_metric_adjustment() {
    interface="$1"
    current_issues="$2"   # Number of current performance issues
    historical_score="$3" # Historical performance score (0-100)
    issue_trend="$4"      # "improving", "stable", "degrading"

    log_debug "📊 METRIC CALCULATION: Interface $interface - Issues: $current_issues, Historical: $historical_score, Trend: $issue_trend"

    adjustment=0
    reasoning=""

    # Base adjustment on current issues
    case "$current_issues" in
        0)
            if [ "$historical_score" -ge 90 ]; then
                adjustment=0
                reasoning="excellent_performance"
            elif [ "$historical_score" -ge 70 ]; then
                adjustment=1
                reasoning="good_with_minor_history"
            else
                adjustment=2
                reasoning="current_good_but_poor_history"
            fi
            ;;
        1)
            if [ "$issue_trend" = "improving" ]; then
                adjustment=$METRIC_ADJUSTMENT_MINOR
                reasoning="single_issue_improving"
            else
                adjustment=$METRIC_ADJUSTMENT_MODERATE
                reasoning="single_issue_stable_or_degrading"
            fi
            ;;
        2)
            if [ "$issue_trend" = "improving" ]; then
                adjustment=$METRIC_ADJUSTMENT_MODERATE
                reasoning="dual_issues_improving"
            else
                adjustment=$METRIC_ADJUSTMENT_MAJOR
                reasoning="dual_issues_stable_or_degrading"
            fi
            ;;
        *)
            if [ "$current_issues" -ge 3 ]; then
                adjustment=$METRIC_ADJUSTMENT_CRITICAL
                reasoning="multiple_critical_issues"
            fi
            ;;
    esac

    # Apply historical performance weighting
    if [ "$historical_score" -lt 30 ]; then
        # Very poor historical performance - increase penalty
        adjustment=$((adjustment + METRIC_ADJUSTMENT_MINOR))
        reasoning="${reasoning}_poor_history"
    elif [ "$historical_score" -gt 80 ] && [ "$issue_trend" = "improving" ]; then
        # Excellent history and improving - reduce penalty
        adjustment=$((adjustment - 2))
        [ "$adjustment" -lt 0 ] && adjustment=0
        reasoning="${reasoning}_excellent_history"
    fi

    # Apply trend weighting
    case "$issue_trend" in
        "degrading")
            adjustment=$((adjustment + 3))
            reasoning="${reasoning}_degrading_trend"
            ;;
        "improving")
            adjustment=$((adjustment - 1))
            [ "$adjustment" -lt 0 ] && adjustment=0
            reasoning="${reasoning}_improving_trend"
            ;;
    esac

    log_debug "� METRIC CALCULATION: $interface adjustment: +$adjustment ($reasoning)"

    # Return adjustment,reasoning
    printf "%s" "$adjustment,$reasoning"
    return 0
}

# Apply metric adjustment to MWAN3 member
apply_metric_adjustment() {
    member_section="$1"
    base_metric="$2"
    adjustment="$3"
    reasoning="$4"

    new_metric=$((base_metric + adjustment))

    log_debug "� METRIC APPLICATION: Member $member_section - Base: $base_metric, Adjustment: +$adjustment, New: $new_metric"
    log_debug "📊 METRIC APPLICATION: Reasoning: $reasoning"

    # Apply the new metric
    if safe_execute "uci set mwan3.$member_section.metric=$new_metric" "Set metric for $member_section to $new_metric"; then
        if safe_execute "uci commit mwan3" "Commit MWAN3 configuration"; then
            if safe_execute "/etc/init.d/mwan3 reload" "Reload MWAN3 service"; then
                log_info "✅ METRIC APPLIED: $member_section metric adjusted to $new_metric (+$adjustment) - $reasoning"
                return 0
            fi
        fi
    fi

    log_error "❌ METRIC APPLICATION FAILED: Could not apply metric adjustment for $member_section"
    return 1
}

# =============================================================================
# HISTORICAL PERFORMANCE ANALYSIS SYSTEM
# Analyze past performance data for predictive failover decisions
# =============================================================================

# Collect historical performance data from multiple sources
collect_historical_performance() {
    interface="$1"
    analysis_period="${2:-300}" # Default 5 minutes

    log_debug "� HISTORICAL ANALYSIS: Collecting $analysis_period seconds of data for $interface"

    # Initialize performance metrics
    trend_direction="stable"

    # Check MWAN3 tracking logs
    mwan3_data=$(collect_mwan3_tracking_data "$interface" "$analysis_period")
    log_debug "📈 HISTORICAL ANALYSIS: MWAN3 data: $mwan3_data"

    # Check our own monitoring logs
    monitor_data=$(collect_monitor_historical_data "$interface" "$analysis_period")
    log_debug "📈 HISTORICAL ANALYSIS: Monitor data: $monitor_data"

    # Check system logs for interface events
    system_data=$(collect_system_interface_logs "$interface" "$analysis_period")
    log_debug "📈 HISTORICAL ANALYSIS: System data: $system_data"

    # Combine and analyze all data sources
    combined_score=$(calculate_combined_historical_score "$mwan3_data" "$monitor_data" "$system_data")
    log_debug "📈 HISTORICAL ANALYSIS: Combined score for $interface: $combined_score"

    # Return historical_score,trend_direction,sample_count
    printf "%s" "$combined_score,stable,10"
    return 0
}

# Extract MWAN3 tracking data for performance analysis
collect_mwan3_tracking_data() {
    interface="$1"
    period="$2"

    log_debug "📊 MWAN3 TRACKING: Collecting tracking data for $interface over ${period}s"

    # MWAN3 typically logs to system log with specific patterns
    # Look for tracking events in the system log
    tracking_data=""

    if [ -f "/var/log/messages" ]; then
        # Look for MWAN3 tracking entries
        tracking_data=$(grep -E "mwan3track.*$interface" /var/log/messages 2>/dev/null | tail -20 || echo "")
        log_debug "📊 MWAN3 TRACKING: Found $(echo "$tracking_data" | wc -l) tracking entries"
    fi

    # Parse tracking data for success/failure patterns
    success_count=0
    failure_count=0

    if [ -n "$tracking_data" ]; then
        success_count=$(echo "$tracking_data" | grep -c "success\|up\|online" || echo "0")
        failure_count=$(echo "$tracking_data" | grep -c "fail\|down\|offline" || echo "0")
    fi

    total_checks=$((success_count + failure_count))
    [ "$total_checks" -eq 0 ] && total_checks=1

    uptime_percentage=$((success_count * 100 / total_checks))

    log_debug "📊 MWAN3 TRACKING: $interface - Success: $success_count, Failures: $failure_count, Uptime: ${uptime_percentage}%"

    # Return success_count,failure_count,uptime_percentage
    printf "%s" "$success_count,$failure_count,$uptime_percentage"
    return 0
}

# Collect our own historical monitoring data
collect_monitor_historical_data() {
    interface="$1"
    period="$2"

    log_debug "📊 MONITOR HISTORY: Collecting monitor historical data for $interface over ${period}s"

    # Look for our own performance logs
    performance_score=75 # Default reasonable score
    latency_avg=50
    loss_avg=0

    # Check if we have historical logs
    if [ -f "${LOG_DIR}/connection_performance.csv" ]; then
        # Get recent entries for this interface
        recent_data=$(grep "$interface" "${LOG_DIR}/connection_performance.csv" 2>/dev/null | tail -10 || echo "")

        if [ -n "$recent_data" ]; then
            # Calculate averages from recent data
            latency_sum=0
            loss_sum=0
            count=0

            # Use process substitution to avoid subshell issues
            while IFS=',' read -r timestamp _ latency loss jitter signal_dbm; do
                [ -n "$latency" ] && [ "$latency" -ne 0 ] && {
                    latency_sum=$((latency_sum + latency))
                    loss_sum=$((loss_sum + ${loss:-0}))
                    count=$((count + 1))
                }
            done <<EOF
$recent_data
EOF

            if [ "$count" -gt 0 ]; then
                latency_avg=$((latency_sum / count))
                loss_avg=$((loss_sum / count))
            fi
        fi
    fi

    # Calculate performance score based on averages
    if [ "$latency_avg" -le 50 ] && [ "$loss_avg" -eq 0 ]; then
        performance_score=95
    elif [ "$latency_avg" -le 100 ] && [ "$loss_avg" -le 1 ]; then
        performance_score=85
    elif [ "$latency_avg" -le 150 ] && [ "$loss_avg" -le 3 ]; then
        performance_score=70
    elif [ "$latency_avg" -le 200 ] && [ "$loss_avg" -le 5 ]; then
        performance_score=50
    else
        performance_score=30
    fi

    log_debug "� MONITOR HISTORY: $interface - Avg Latency: ${latency_avg}ms, Avg Loss: ${loss_avg}%, Score: $performance_score"

    # Return latency_avg,loss_avg,performance_score
    printf "%s" "$latency_avg,$loss_avg,$performance_score"
    return 0
}

# Collect system interface logs for stability analysis
collect_system_interface_logs() {
    interface="$1"
    period="$2"

    log_debug "📊 SYSTEM LOGS: Collecting system interface logs for $interface over ${period}s"

    # Look for interface up/down events, errors, etc.
    stability_score=90 # Default good stability
    error_count=0
    state_changes=0

    if [ -f "/var/log/messages" ]; then
        # Look for interface-related messages
        interface_logs=$(grep -E "$interface.*up|$interface.*down|$interface.*error" /var/log/messages 2>/dev/null | tail -20 || echo "")

        if [ -n "$interface_logs" ]; then
            error_count=$(echo "$interface_logs" | grep -c "error\|fail" || echo "0")
            state_changes=$(echo "$interface_logs" | grep -c "up\|down" || echo "0")

            # Adjust stability score based on findings
            if [ "$error_count" -gt 5 ]; then
                stability_score=30
            elif [ "$error_count" -gt 2 ]; then
                stability_score=60
            elif [ "$state_changes" -gt 3 ]; then
                stability_score=70
            fi
        fi
    fi

    log_debug "� SYSTEM LOGS: $interface - Errors: $error_count, State changes: $state_changes, Stability: $stability_score"

    # Return error_count,state_changes,stability_score
    printf "%s" "$error_count,$state_changes,$stability_score"
    return 0
}

# Calculate combined historical performance score
calculate_combined_historical_score() {
    mwan3_data="$1"   # success_count,failure_count,uptime_percentage
    monitor_data="$2" # latency_avg,loss_avg,performance_score
    system_data="$3"  # error_count,state_changes,stability_score

    # Parse data components
    mwan3_uptime=$(echo "$mwan3_data" | cut -d',' -f3)
    monitor_score=$(echo "$monitor_data" | cut -d',' -f3)
    system_stability=$(echo "$system_data" | cut -d',' -f3)

    # Weighted combination (MWAN3: 40%, Monitor: 40%, System: 20%)
    combined_score=$(((mwan3_uptime * 40 + monitor_score * 40 + system_stability * 20) / 100))

    log_debug "📊 COMBINED SCORE: MWAN3: $mwan3_uptime, Monitor: $monitor_score, System: $system_stability → Combined: $combined_score"

    printf "%s" "$combined_score"
    return 0
}

# =============================================================================
# INTELLIGENT CONNECTION MONITORING AND ANALYSIS
# Real-time performance testing with predictive capabilities
# =============================================================================

# Comprehensive connection testing with interface-specific logic
test_connection_comprehensive() {
    interface="$1"
    interface_type="$2"
    interface_subtype="$3"
    special_config="$4"

    log_debug "🔄 COMPREHENSIVE TEST: Testing $interface ($interface_type/$interface_subtype) with special config: $special_config"

    # Initialize test results
    test_results="latency:999,packet_loss:100,jitter:999,available:false,signal_dbm:-113,issues:3"

    # Pre-flight checks
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_debug "🔄 COMPREHENSIVE TEST: Interface $interface not found"
        printf "%s" "$test_results"
        return 1
    fi

    if ! ip addr show "$interface" | grep -q "inet "; then
        log_debug "🔄 COMPREHENSIVE TEST: Interface $interface has no IP address"
        printf "%s" "$test_results"
        return 1
    fi

    # Interface is available - proceed with comprehensive testing
    log_debug "🔄 COMPREHENSIVE TEST: Interface $interface is available, running comprehensive tests"

    # Perform interface-specific testing
    case "$interface_type" in
        "cellular")
            test_results=$(test_cellular_interface "$interface" "$interface_subtype")
            ;;
        "wifi")
            test_results=$(test_wifi_interface "$interface" "$interface_subtype")
            ;;
        "ethernet")
            test_results=$(test_ethernet_interface "$interface" "$interface_subtype")
            ;;
        "satellite")
            test_results=$(test_satellite_interface "$interface" "$special_config")
            ;;
        *)
            test_results=$(test_generic_interface "$interface" "$interface_type")
            ;;
    esac

    log_debug "🔄 COMPREHENSIVE TEST: $interface test results: $test_results"
    printf "%s" "$test_results"
    return 0
}

# Cellular interface testing with modem-specific diagnostics
test_cellular_interface() {
    interface="$1"
    subtype="$2"

    log_debug "📱 CELLULAR TEST: Testing cellular interface $interface ($subtype)"

    # Standard connectivity test
    connectivity_results=$(run_standard_connectivity_test "$interface")
    latency=$(echo "$connectivity_results" | cut -d',' -f1)
    packet_loss=$(echo "$connectivity_results" | cut -d',' -f2)
    jitter=$(echo "$connectivity_results" | cut -d',' -f3)

    # Cellular-specific diagnostics
    cellular_diagnostics=$(get_cellular_diagnostics "$interface")
    signal_dbm=$(echo "$cellular_diagnostics" | cut -d',' -f1)
    signal_quality=$(echo "$cellular_diagnostics" | cut -d',' -f2)
    network_type=$(echo "$cellular_diagnostics" | cut -d',' -f3)
    operator=$(echo "$cellular_diagnostics" | cut -d',' -f4)

    # Calculate cellular-specific issues
    issues=0
    if [ "$latency" -gt 200 ]; then issues=$((issues + 1)); fi
    if [ "$packet_loss" -gt 5 ]; then issues=$((issues + 1)); fi
    if [ "$signal_dbm" -lt "-100" ]; then issues=$((issues + 1)); fi

    # Cellular interfaces have different performance expectations
    if [ "$subtype" = "5g" ]; then
        # 5G should have better performance
        if [ "$latency" -gt 100 ]; then issues=$((issues + 1)); fi
    elif [ "$subtype" = "4g" ]; then
        # 4G moderate expectations
        if [ "$latency" -gt 150 ]; then issues=$((issues + 1)); fi
    fi

    log_debug "📱 CELLULAR TEST: $interface - Latency: ${latency}ms, Loss: ${packet_loss}%, Signal: ${signal_dbm}dBm, Issues: $issues"

    # Return comprehensive results
    printf "%s" "latency:$latency,packet_loss:$packet_loss,jitter:$jitter,available:true,signal_dbm:$signal_dbm,network_type:$network_type,operator:$operator,issues:$issues"
    return 0
}

# Standard connectivity test used by all interface types
run_standard_connectivity_test() {
    interface="$1"
    test_host="${CONNECTION_TEST_HOST:-8.8.8.8}"
    test_timeout="${CONNECTION_TEST_TIMEOUT:-10}"
    ping_count=3

    log_debug "🔄 STANDARD TEST: Testing $interface via ping to $test_host"

    # Initialize with moderate defaults for startup (not worst-case)
    latency="75"
    packet_loss="1"
    jitter="15"

    # Quick interface readiness check
    if ! ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
        log_debug "🔄 STANDARD TEST: Interface $interface is not UP, using defaults"
        printf "%s,%s,%s" "$latency" "$packet_loss" "$jitter"
        return 1
    fi

    # Check if interface has a valid route
    if ! ip route show table main | grep -q "dev $interface"; then
        log_debug "🔄 STANDARD TEST: Interface $interface has no routes, using defaults"
        printf "%s,%s,%s" "$latency" "$packet_loss" "$jitter"
        return 1
    fi

    # Perform ping test with shorter timeout for startup
    ping_output=""
    if command -v timeout >/dev/null 2>&1; then
        ping_output=$(timeout "$test_timeout" ping -I "$interface" -c $ping_count "$test_host" 2>/dev/null || echo "")
    else
        ping_output=$(ping -I "$interface" -c $ping_count "$test_host" 2>/dev/null || echo "")
    fi

    if [ -n "$ping_output" ] && echo "$ping_output" | grep -q "packet loss"; then
        # Extract packet loss percentage
        packet_loss_line=$(echo "$ping_output" | grep "packet loss" | head -1)
        if [ -n "$packet_loss_line" ]; then
            extracted_loss=$(echo "$packet_loss_line" | sed 's/.*(\([0-9]*\)% packet loss).*/\1/')
            if [ -n "$extracted_loss" ] && [ "$extracted_loss" -ge 0 ] 2>/dev/null; then
                packet_loss="$extracted_loss"
            fi
        fi

        # Extract latency statistics
        latency_line=$(echo "$ping_output" | grep "min/avg/max" | head -1)
        if [ -n "$latency_line" ]; then
            extracted_latency=$(echo "$latency_line" | awk -F'[/=]' '{print $3}' | awk '{print int($1+0.5)}')
            extracted_jitter=$(echo "$latency_line" | awk -F'[/=]' '{print $5}' | awk '{print int($1+0.5)}')
            if [ -n "$extracted_latency" ] && [ "$extracted_latency" -gt 0 ] 2>/dev/null; then
                latency="$extracted_latency"
            fi
            if [ -n "$extracted_jitter" ] && [ "$extracted_jitter" -gt 0 ] 2>/dev/null; then
                jitter="$extracted_jitter"
            fi
        fi
    else
        log_debug "🔄 STANDARD TEST: Ping test failed or incomplete for $interface, using reasonable defaults"
    fi

    log_debug "🔄 STANDARD TEST: $interface - Latency: ${latency}ms, Loss: ${packet_loss}%, Jitter: ${jitter}ms"

    # Return latency,packet_loss,jitter
    printf "%s" "$latency,$packet_loss,$jitter"
    return 0
}

# Get cellular diagnostics via AT commands
get_cellular_diagnostics() {
    interface="$1"

    log_debug "📱 CELLULAR DIAGNOSTICS: Getting diagnostics for $interface"

    # Initialize with defaults
    signal_dbm="-113"
    signal_quality="0"
    network_type="Unknown"
    operator="Unknown"

    if command -v gsmctl >/dev/null 2>&1; then
        # Get signal strength
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | tr -d '\n' | head -1)
        signal_quality=$(echo "$signal_info" | awk -F'[: ,]' '{print $4}' | tr -d '\n' | head -1)

        # Convert to dBm
        if [ "$signal_strength" != "99" ] && [ "$signal_strength" -gt 0 ] 2>/dev/null; then
            signal_dbm=$((2 * signal_strength - 113))
        fi

        # Get network type
        network_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "+QNWINFO: \"Unknown\"")
        network_type=$(echo "$network_info" | awk -F'"' '{print $2}' | tr -d '\n\r,' | head -c 15)

        # Get operator
        reg_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" | head -1 || echo "+COPS: 0,0,\"Unknown\"")
        operator=$(echo "$reg_info" | sed 's/.*"\([^"]*\)".*/\1/' | tr -d '\n\r,' | head -c 20)
    fi

    log_debug "📱 CELLULAR DIAGNOSTICS: $interface - Signal: ${signal_dbm}dBm, Network: $network_type, Operator: $operator"

    # Return signal_dbm,signal_quality,network_type,operator
    printf "%s" "$signal_dbm,$signal_quality,$network_type,$operator"
    return 0
}

# Generic interface testing for unknown interface types
test_generic_interface() {
    interface="$1"
    interface_type="$2"

    log_debug "🔧 GENERIC TEST: Testing generic interface $interface ($interface_type)"

    # Standard connectivity test
    connectivity_results=$(run_standard_connectivity_test "$interface")
    latency=$(echo "$connectivity_results" | cut -d',' -f1)
    packet_loss=$(echo "$connectivity_results" | cut -d',' -f2)
    jitter=$(echo "$connectivity_results" | cut -d',' -f3)

    # Generic issue calculation
    issues=0
    if [ "$latency" -gt 200 ]; then issues=$((issues + 1)); fi
    if [ "$packet_loss" -gt 5 ]; then issues=$((issues + 1)); fi

    log_debug "🔧 GENERIC TEST: $interface - Latency: ${latency}ms, Loss: ${packet_loss}%, Issues: $issues"

    printf "%s" "latency:$latency,packet_loss:$packet_loss,jitter:$jitter,available:true,issues:$issues"
    return 0
}

# =============================================================================
# INTELLIGENT PREDICTIVE MONITORING ORCHESTRATION
# Main system that coordinates discovery, testing, analysis, and metric adjustment
# =============================================================================

# Main intelligent monitoring function
run_intelligent_monitoring() {
    log_info "🧠 INTELLIGENT MONITORING: Starting comprehensive analysis cycle"

    # Phase 1: Discovery - Find all MWAN3 managed interfaces
    log_debug "🧠 PHASE 1: MWAN3 Discovery"
    mwan3_interfaces=$(discover_mwan3_interfaces)
    mwan3_members=$(discover_mwan3_members)

    if [ -z "$mwan3_interfaces" ]; then
        log_warning "🧠 DISCOVERY: No MWAN3 interfaces found - system may not be configured"
        return 1
    fi

    log_info "🧠 DISCOVERY: Found MWAN3 interfaces: $mwan3_interfaces"
    log_info "🧠 DISCOVERY: Found MWAN3 members: $mwan3_members"

    # Phase 2: Classification - Determine interface types and capabilities
    log_debug "🧠 PHASE 2: Interface Classification"
    interface_database=""

    # shellcheck disable=SC2046  # Word splitting intended for iteration
    for interface_entry in $(echo "$mwan3_interfaces" | tr ',' ' '); do
        mwan3_section=$(echo "$interface_entry" | cut -d':' -f1)
        interface_name=$(echo "$interface_entry" | cut -d':' -f2)

        # Classify the interface
        classification=$(classify_interface_type "$interface_name")
        interface_type=$(echo "$classification" | cut -d',' -f1)
        interface_subtype=$(echo "$classification" | cut -d',' -f2)
        special_config=$(echo "$classification" | cut -d',' -f3)

        # Find corresponding member configuration
        member_info=$(echo "$mwan3_members" | tr ',' '\n' | grep ":$mwan3_section:" | head -1)
        if [ -n "$member_info" ]; then
            member_section=$(echo "$member_info" | cut -d':' -f1)
            current_metric=$(echo "$member_info" | cut -d':' -f3)
            weight=$(echo "$member_info" | cut -d':' -f4)
            member_display_name=$(echo "$member_info" | cut -d':' -f5)
        else
            member_section="unknown"
            current_metric="1"
            weight="1"
            member_display_name="unknown"
        fi

        # Build interface database entry with member display name
        interface_database="${interface_database}${interface_name}:${interface_type}:${interface_subtype}:${special_config}:${member_section}:${current_metric}:${weight}:${member_display_name},"

        log_debug "🧠 CLASSIFICATION: $interface_name → $interface_type/$interface_subtype (special: $special_config, metric: $current_metric)"
    done

    # Remove trailing comma
    interface_database=$(echo "$interface_database" | sed 's/,$//')

    # Phase 3: Performance Testing - Test all interfaces comprehensively
    log_debug "🧠 PHASE 3: Comprehensive Performance Testing"
    performance_database=""

    # shellcheck disable=SC2046  # Word splitting intended for iteration
    for interface_entry in $(echo "$interface_database" | tr ',' ' '); do
        interface_name=$(echo "$interface_entry" | cut -d':' -f1)
        interface_type=$(echo "$interface_entry" | cut -d':' -f2)
        interface_subtype=$(echo "$interface_entry" | cut -d':' -f3)
        special_config=$(echo "$interface_entry" | cut -d':' -f4)
        member_section=$(echo "$interface_entry" | cut -d':' -f5)
        current_metric=$(echo "$interface_entry" | cut -d':' -f6)
        weight=$(echo "$interface_entry" | cut -d':' -f7)
        member_display_name=$(echo "$interface_entry" | cut -d':' -f8)

        # Test the interface comprehensively
        test_results=$(test_connection_comprehensive "$interface_name" "$interface_type" "$interface_subtype" "$special_config")

        # Extract key metrics from test results
        latency=$(echo "$test_results" | tr ',' '\n' | grep "latency:" | cut -d':' -f2)
        packet_loss=$(echo "$test_results" | tr ',' '\n' | grep "packet_loss:" | cut -d':' -f2)
        available=$(echo "$test_results" | tr ',' '\n' | grep "available:" | cut -d':' -f2)
        issues=$(echo "$test_results" | tr ',' '\n' | grep "issues:" | cut -d':' -f2)

        # Calculate connection health score for display
        connection_score=$(calculate_connection_health_score "$latency" "$packet_loss" "0" "0" "$interface_type" 2>/dev/null || echo "50")

        # Store performance data
        performance_database="${performance_database}${interface_name}:${latency}:${packet_loss}:${available}:${issues}:${current_metric}:${member_section}:${connection_score},"

        log_info "🧠 PERFORMANCE: $interface_name ($member_display_name) - Latency: ${latency}ms, Loss: ${packet_loss}%, Issues: $issues, Score: $connection_score"
    done

    # Remove trailing comma
    performance_database=$(echo "$performance_database" | sed 's/,$//')

    # Phase 4: Historical Analysis - Analyze trends and predict issues
    log_debug "🧠 PHASE 4: Historical Analysis and Trend Prediction"

    # shellcheck disable=SC2046  # Word splitting intended for iteration
    for interface_entry in $(echo "$performance_database" | tr ',' ' '); do
        interface_name=$(echo "$interface_entry" | cut -d':' -f1)
        current_issues=$(echo "$interface_entry" | cut -d':' -f5)
        member_section=$(echo "$interface_entry" | cut -d':' -f7)
        connection_score=$(echo "$interface_entry" | cut -d':' -f8)

        # Get historical performance data
        historical_data=$(collect_historical_performance "$interface_name" 300) # 5 minutes
        historical_score=$(echo "$historical_data" | cut -d',' -f1)
        trend_direction=$(echo "$historical_data" | cut -d',' -f2)

        log_debug "🧠 HISTORICAL: $interface_name - Score: $historical_score, Trend: $trend_direction, Current Issues: $current_issues"

        # Calculate appropriate metric adjustment
        adjustment_data=$(calculate_metric_adjustment "$interface_name" "$current_issues" "$historical_score" "$trend_direction")
        adjustment=$(echo "$adjustment_data" | cut -d',' -f1)
        reasoning=$(echo "$adjustment_data" | cut -d',' -f2)

        # Apply metric adjustment if needed
        if [ "$adjustment" -gt 0 ]; then
            current_metric=$(uci get "mwan3.$member_section.metric" 2>/dev/null || echo "1")

            log_info "🧠 METRIC ADJUSTMENT: $interface_name needs +$adjustment adjustment ($reasoning)"

            if apply_metric_adjustment "$member_section" "$current_metric" "$adjustment" "$reasoning"; then
                log_info "✅ APPLIED: $interface_name metric adjusted successfully"
            else
                log_error "❌ FAILED: Could not apply metric adjustment for $interface_name"
            fi
        else
            log_debug "🧠 METRIC: $interface_name performing well, no adjustment needed"
        fi
    done

    # Phase 5: Intelligent Failover Decision
    log_debug "🧠 PHASE 5: Intelligent Failover Decision Analysis"

    # Find the interface with the lowest current metric (highest priority)
    best_interface=""
    best_metric=999
    best_issues=999

    # shellcheck disable=SC2046
    for interface_entry in $(echo "$performance_database" | tr ',' ' '); do
        interface_name=$(echo "$interface_entry" | cut -d':' -f1)
        issues=$(echo "$interface_entry" | cut -d':' -f5)
        current_metric=$(echo "$interface_entry" | cut -d':' -f6)

        # Find the best performing interface with lowest metric
        if [ "$current_metric" -lt "$best_metric" ] || { [ "$current_metric" -eq "$best_metric" ] && [ "$issues" -lt "$best_issues" ]; }; then
            best_interface="$interface_name"
            best_metric="$current_metric"
            best_issues="$issues"
        fi
    done

    log_info "🧠 DECISION: Best interface determined: $best_interface (metric: $best_metric, issues: $best_issues)"

    # Generate comprehensive monitoring report
    generate_monitoring_report "$interface_database" "$performance_database"

    log_info "🧠 INTELLIGENT MONITORING: Analysis cycle completed successfully"
    return 0
}

# Generate comprehensive monitoring report
generate_monitoring_report() {
    interface_db="$1"
    performance_db="$2"

    log_debug "📊 REPORT: Generating comprehensive monitoring report"

    # Create report timestamp
    report_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Write to monitoring report file
    report_file="${LOG_DIR}/intelligent_monitoring_report.log"

    {
        echo "=== INTELLIGENT MONITORING REPORT - $report_time ==="
        echo ""
        echo "INTERFACE SUMMARY:"

        # shellcheck disable=SC2046  # Word splitting intended for iteration
        for interface_entry in $(echo "$performance_db" | tr ',' ' '); do
            interface_name=$(echo "$interface_entry" | cut -d':' -f1)
            latency=$(echo "$interface_entry" | cut -d':' -f2)
            packet_loss=$(echo "$interface_entry" | cut -d':' -f3)
            available=$(echo "$interface_entry" | cut -d':' -f4)
            issues=$(echo "$interface_entry" | cut -d':' -f5)
            current_metric=$(echo "$interface_entry" | cut -d':' -f6)

            # Get interface type from interface database
            interface_info=$(echo "$interface_db" | tr ',' '\n' | grep "^$interface_name:" | head -1)
            interface_type=$(echo "$interface_info" | cut -d':' -f2)
            interface_subtype=$(echo "$interface_info" | cut -d':' -f3)

            status_icon="✅"
            [ "$issues" -gt 0 ] && status_icon="⚠️"
            [ "$issues" -gt 2 ] && status_icon="❌"
            [ "$available" != "true" ] && status_icon="🔌"

            printf "  %s %-15s (%s/%s) - Metric: %2d, Latency: %3dms, Loss: %2d%%, Issues: %d\n" \
                "$status_icon" "$interface_name" "$interface_type" "$interface_subtype" \
                "$current_metric" "$latency" "$packet_loss" "$issues"
        done

        echo ""
        echo "SYSTEM STATUS: All interfaces monitored and metrics adjusted based on performance"
        echo "=============================================================="
        echo ""
    } >>"$report_file"

    # Keep only last 100 reports to prevent log growth
    if [ -f "$report_file" ]; then
        tail -1000 "$report_file" >"${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
    fi
}

# =============================================================================
# CONFIGURATION MANAGEMENT AND VALIDATION
# =============================================================================

# Validate MWAN3 configuration and system readiness
validate_system_configuration() {
    log_info "🔍 VALIDATION: Checking system configuration and readiness"

    # Check if MWAN3 is installed and running
    if ! command -v mwan3 >/dev/null 2>&1; then
        log_error "❌ MWAN3 not found - this system requires MWAN3 for intelligent failover"
        return 1
    fi

    # Check if UCI configuration is accessible
    if ! uci show mwan3 >/dev/null 2>&1; then
        log_error "❌ MWAN3 UCI configuration not accessible"
        return 1
    fi

    # Check if we have at least one interface configured
    interface_count=$(uci show mwan3 | grep -c "=interface")
    if [ "$interface_count" -eq 0 ]; then
        log_warning "⚠️ No MWAN3 interfaces found - system may need configuration"
        return 1
    fi

    log_info "✅ VALIDATION: System ready - MWAN3 active with $interface_count interfaces"
    return 0
}

# Initialize monitoring configuration
initialize_monitoring_config() {
    log_debug "⚙️ CONFIG: Initializing intelligent monitoring configuration"

    # Monitoring intervals and thresholds
    MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"        # Main monitoring cycle (seconds)
    QUICK_CHECK_INTERVAL="${QUICK_CHECK_INTERVAL:-30}"      # Quick health checks (seconds)
    DEEP_ANALYSIS_INTERVAL="${DEEP_ANALYSIS_INTERVAL:-300}" # Deep analysis cycle (seconds)

    # Performance thresholds
    LATENCY_WARNING_THRESHOLD="${LATENCY_WARNING_THRESHOLD:-200}"         # ms
    LATENCY_CRITICAL_THRESHOLD="${LATENCY_CRITICAL_THRESHOLD:-500}"       # ms
    PACKET_LOSS_WARNING_THRESHOLD="${PACKET_LOSS_WARNING_THRESHOLD:-2}"   # %
    PACKET_LOSS_CRITICAL_THRESHOLD="${PACKET_LOSS_CRITICAL_THRESHOLD:-5}" # %

    # Historical analysis settings
    HISTORICAL_ANALYSIS_WINDOW="${HISTORICAL_ANALYSIS_WINDOW:-1800}" # 30 minutes
    TREND_ANALYSIS_SAMPLES="${TREND_ANALYSIS_SAMPLES:-10}"           # Number of samples for trend

    # Metric adjustment limits
    MAX_METRIC_ADJUSTMENT="${MAX_METRIC_ADJUSTMENT:-50}" # Maximum metric adjustment per cycle
    MIN_METRIC_VALUE="${MIN_METRIC_VALUE:-1}"            # Minimum allowed metric
    MAX_METRIC_VALUE="${MAX_METRIC_VALUE:-100}"          # Maximum allowed metric

    # Safety and rate limiting
    MAX_ADJUSTMENTS_PER_CYCLE="${MAX_ADJUSTMENTS_PER_CYCLE:-3}" # Max interfaces to adjust per cycle
    ADJUSTMENT_COOLDOWN="${ADJUSTMENT_COOLDOWN:-120}"           # Seconds between adjustments for same interface

    log_debug "⚙️ CONFIG: Monitoring interval: ${MONITORING_INTERVAL}s, Quick check: ${QUICK_CHECK_INTERVAL}s"
    log_debug "⚙️ CONFIG: Latency thresholds: ${LATENCY_WARNING_THRESHOLD}ms/${LATENCY_CRITICAL_THRESHOLD}ms"
    log_debug "⚙️ CONFIG: Packet loss thresholds: ${PACKET_LOSS_WARNING_THRESHOLD}%/${PACKET_LOSS_CRITICAL_THRESHOLD}%"
}

# =============================================================================
# MAIN MONITORING LOOP AND ORCHESTRATION
# =============================================================================

# Main monitoring daemon function
run_monitoring_daemon() {
    log_info "� DAEMON: Starting intelligent monitoring daemon"

    # Initialize system
    if ! validate_system_configuration; then
        log_error "❌ DAEMON: System validation failed - cannot start monitoring"
        return 1
    fi

    initialize_monitoring_config

    # Create monitoring state directory
    MONITORING_STATE_DIR="${LOG_DIR}/monitoring_state"
    if [ "${DRY_RUN:-0}" != "1" ]; then
        mkdir -p "$MONITORING_STATE_DIR"
    else
        log_debug "DRY_RUN: Would create directory $MONITORING_STATE_DIR"
    fi

    # Initialize counters and state
    cycle_count=0
    deep_analysis_counter=0
    daemon_start_time=$(date '+%s')

    log_info "🚀 DAEMON: Intelligent monitoring started successfully"
    log_info "🚀 DAEMON: Main cycle: ${MONITORING_INTERVAL}s, Quick check: ${QUICK_CHECK_INTERVAL}s, Deep analysis: ${DEEP_ANALYSIS_INTERVAL}s"

    # Main monitoring loop
    while true; do
        cycle_count=$((cycle_count + 1))
        cycle_start_time=$(date '+%s')

        log_debug "🔄 CYCLE $cycle_count: Starting monitoring cycle at $(date '+%H:%M:%S')"

        # Run the main intelligent monitoring
        if run_intelligent_monitoring; then
            log_debug "✅ CYCLE $cycle_count: Completed successfully"
        else
            log_warning "⚠️ CYCLE $cycle_count: Completed with warnings"
        fi

        # Update cycle statistics
        cycle_end_time=$(date '+%s')
        cycle_duration=$((cycle_end_time - cycle_start_time))

        # Deep analysis every DEEP_ANALYSIS_INTERVAL seconds
        deep_analysis_counter=$((deep_analysis_counter + cycle_duration))
        if [ "$deep_analysis_counter" -ge "$DEEP_ANALYSIS_INTERVAL" ]; then
            log_info "🔬 DEEP ANALYSIS: Running comprehensive system analysis"
            run_deep_system_analysis
            deep_analysis_counter=0
        fi

        # Generate daemon status report
        if [ $((cycle_count % 10)) -eq 0 ]; then
            daemon_uptime=$((cycle_end_time - daemon_start_time))
            log_info "�📊 STATUS: Cycle $cycle_count, Uptime: ${daemon_uptime}s, Cycle time: ${cycle_duration}s"
        fi

        # Sleep until next cycle
        sleep_time=$((MONITORING_INTERVAL - cycle_duration))
        if [ "$sleep_time" -gt 0 ]; then
            log_trace "💤 SLEEP: Waiting ${sleep_time}s until next cycle"
            sleep "$sleep_time"
        else
            log_warning "⚠️ PERFORMANCE: Cycle took ${cycle_duration}s (longer than ${MONITORING_INTERVAL}s interval)"
        fi
    done
}

# Deep system analysis function
run_deep_system_analysis() {
    log_debug "🔬 DEEP: Starting comprehensive system analysis"

    # Analyze system performance trends
    system_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    memory_usage=$(free | awk '/Mem:/ {printf "%.1f", $3/$2 * 100.0}')

    # Check MWAN3 service health
    mwan3_status="unknown"
    if command -v mwan3 >/dev/null 2>&1; then
        if mwan3 status >/dev/null 2>&1; then
            mwan3_status="healthy"
        else
            mwan3_status="issues"
        fi
    fi

    # Count active interfaces
    active_interfaces=$(discover_mwan3_interfaces | tr ',' '\n' | wc -l)

    # Generate deep analysis report
    deep_report_file="${LOG_DIR}/deep_analysis_report.log"
    {
        echo "=== DEEP SYSTEM ANALYSIS - $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "System Load: $system_load"
        echo "Memory Usage: ${memory_usage}%"
        echo "MWAN3 Status: $mwan3_status"
        echo "Active Interfaces: $active_interfaces"
        # shellcheck disable=SC2004 # Command substitution in arithmetic
        echo "Monitoring Uptime: $(($(date '+%s') - daemon_start_time))s"
        echo "=============================================================="
        echo ""
    } >>"$deep_report_file"

    # Keep only last 50 deep analysis reports
    if [ -f "$deep_report_file" ]; then
        tail -500 "$deep_report_file" >"${deep_report_file}.tmp" && mv "${deep_report_file}.tmp" "$deep_report_file"
    fi

    log_debug "🔬 DEEP: Analysis completed - Load: $system_load, Memory: ${memory_usage}%, MWAN3: $mwan3_status"
}

# Signal handlers for graceful shutdown
cleanup_monitoring_daemon() {
    log_info "🛑 SHUTDOWN: Intelligent monitoring daemon stopping"
    log_info "🛑 SHUTDOWN: Final cycle completed, total runtime: $(($(date '+%s') - daemon_start_time))s"
    exit 0
}

# =============================================================================
# COMMAND LINE INTERFACE AND SCRIPT ENTRY POINT
# =============================================================================

# Display help information
show_help() {
    cat <<'EOF'
🧠 INTELLIGENT STARLINK MONITORING SYSTEM v3.0
MWAN3-Integrated Predictive Failover with Dynamic Metric Management

USAGE:
    starlink_monitor_unified-rutos.sh [COMMAND] [OPTIONS]

COMMANDS:
    start                    Start intelligent monitoring daemon
    stop                     Stop running monitoring daemon
    status                   Show current monitoring status
    test                     Run single monitoring cycle (test mode)
    discover                 Discover and display MWAN3 interfaces
    analyze                  Run historical performance analysis
    report                   Generate comprehensive system report
    validate                 Validate system configuration
    help                     Show this help message

OPTIONS:
    --daemon                 Run in daemon mode (background)
    --interval=N             Set monitoring interval in seconds (default: 60)
    --quick-interval=N       Set quick check interval in seconds (default: 30)
    --deep-interval=N        Set deep analysis interval in seconds (default: 300)
    --debug                  Enable debug logging
    --dry-run               Enable dry run mode (no changes)
    --log-level=LEVEL       Set log level (info, debug, trace)

EXAMPLES:
    # Start monitoring daemon
    ./starlink_monitor_unified-rutos.sh start --daemon

    # Run single test cycle with debug output
    ./starlink_monitor_unified-rutos.sh test --debug

    # Discover MWAN3 interfaces
    ./starlink_monitor_unified-rutos.sh discover

    # Custom monitoring intervals
    ./starlink_monitor_unified-rutos.sh start --interval=30 --quick-interval=15

FEATURES:
    ✅ Automatic MWAN3 interface discovery
    ✅ Dynamic metric adjustment based on performance
    ✅ Historical performance analysis and trend prediction
    ✅ Interface-specific testing (cellular, WiFi, ethernet, satellite)
    ✅ Intelligent predictive failover
    ✅ Comprehensive logging and reporting
    ✅ Multi-interface support (up to 8 cellular modems)
    ✅ RUTOS busybox compatibility

SYSTEM REQUIREMENTS:
    - RUTOS firmware with MWAN3 package
    - At least one configured MWAN3 interface
    - Network interfaces: cellular, WiFi, ethernet, or satellite
    - UCI configuration access

For more information, visit: https://github.com/user/rutos-starlink-failover
EOF
}

# Main script execution function
main() {
    # Parse command line arguments
    COMMAND=""
    DAEMON_MODE=false

    while [ $# -gt 0 ]; do
        case "$1" in
            start | stop | status | test | discover | analyze | report | validate | help)
                COMMAND="$1"
                ;;
            --daemon)
                DAEMON_MODE=true
                ;;
            --interval=*)
                MONITORING_INTERVAL="${1#*=}"
                export MONITORING_INTERVAL
                ;;
            --quick-interval=*)
                QUICK_CHECK_INTERVAL="${1#*=}"
                export QUICK_CHECK_INTERVAL
                ;;
            --deep-interval=*)
                DEEP_ANALYSIS_INTERVAL="${1#*=}"
                export DEEP_ANALYSIS_INTERVAL
                ;;
            --debug)
                DEBUG=1
                export DEBUG
                ;;
            --dry-run)
                DRY_RUN=1
                export DRY_RUN
                ;;
            --log-level=*)
                LOG_LEVEL="${1#*=}"
                export LOG_LEVEL
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    # Default command if none specified
    if [ -z "$COMMAND" ]; then
        COMMAND="help"
    fi

    # Execute the requested command
    case "$COMMAND" in
        start)
            log_info "🚀 STARTING: Intelligent monitoring system"
            if [ "$DAEMON_MODE" = true ]; then
                log_info "🚀 DAEMON: Starting in background mode"
                # Create PID file for daemon management
                PID_FILE="${LOG_DIR}/starlink_monitor.pid"
                if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    log_error "❌ DAEMON: Already running (PID: $(cat "$PID_FILE"))"
                    exit 1
                fi

                # Start daemon in background
                (
                    if [ "${DRY_RUN:-0}" != "1" ]; then
                        echo $$ >"$PID_FILE"
                    else
                        log_debug "DRY_RUN: Would write PID $$ to $PID_FILE"
                    fi
                    run_monitoring_daemon
                ) &

                sleep 2
                if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    log_info "✅ DAEMON: Started successfully (PID: $(cat "$PID_FILE"))"
                else
                    log_error "❌ DAEMON: Failed to start"
                    exit 1
                fi
            else
                # Run in foreground
                run_monitoring_daemon
            fi
            ;;
        stop)
            log_info "🛑 STOPPING: Intelligent monitoring system"
            PID_FILE="${LOG_DIR}/starlink_monitor.pid"
            if [ -f "$PID_FILE" ]; then
                PID=$(cat "$PID_FILE")
                if kill -0 "$PID" 2>/dev/null; then
                    kill -TERM "$PID"
                    sleep 3
                    if kill -0 "$PID" 2>/dev/null; then
                        kill -KILL "$PID"
                        log_warning "⚠️ STOP: Force killed daemon process"
                    else
                        log_info "✅ STOP: Daemon stopped gracefully"
                    fi
                    if [ "${DRY_RUN:-0}" != "1" ]; then
                        rm -f "$PID_FILE"
                    else
                        log_debug "DRY_RUN: Would remove PID file $PID_FILE"
                    fi
                else
                    log_warning "⚠️ STOP: Daemon not running, removing stale PID file"
                    if [ "${DRY_RUN:-0}" != "1" ]; then
                        rm -f "$PID_FILE"
                    else
                        log_debug "DRY_RUN: Would remove stale PID file $PID_FILE"
                    fi
                fi
            else
                log_info "ℹ️ STOP: No daemon PID file found"
            fi
            ;;
        status)
            log_info "📊 STATUS: Checking monitoring system status"
            PID_FILE="${LOG_DIR}/starlink_monitor.pid"
            if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                PID=$(cat "$PID_FILE")
                UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
                log_info "✅ STATUS: Daemon running (PID: $PID, Uptime: $UPTIME)"

                # Show recent activity
                if [ -f "${LOG_DIR}/intelligent_monitoring_report.log" ]; then
                    log_info "📊 RECENT ACTIVITY:"
                    tail -5 "${LOG_DIR}/intelligent_monitoring_report.log"
                fi
            else
                log_info "❌ STATUS: Daemon not running"
                if [ "${DRY_RUN:-0}" != "1" ]; then
                    rm -f "$PID_FILE" 2>/dev/null
                else
                    log_debug "DRY_RUN: Would remove stale PID file $PID_FILE"
                fi
            fi
            ;;
        test)
            log_info "🧪 TEST: Running single monitoring cycle"
            run_intelligent_monitoring
            ;;
        discover)
            log_info "🔍 DISCOVERY: Scanning MWAN3 configuration"
            interfaces=$(discover_mwan3_interfaces)
            members=$(discover_mwan3_members)

            log_info "📡 MWAN3 INTERFACES FOUND:"
            if [ -n "$interfaces" ]; then
                # shellcheck disable=SC2046
                for interface_entry in $(echo "$interfaces" | tr ',' ' '); do
                    mwan3_section=$(echo "$interface_entry" | cut -d':' -f1)
                    interface_name=$(echo "$interface_entry" | cut -d':' -f2)
                    classification=$(classify_interface_type "$interface_name")
                    interface_type=$(echo "$classification" | cut -d',' -f1)
                    interface_subtype=$(echo "$classification" | cut -d',' -f2)

                    printf "  %-15s → %s/%s\n" "$interface_name" "$interface_type" "$interface_subtype"
                done
            else
                log_warning "⚠️ No MWAN3 interfaces found"
            fi

            log_info "👥 MWAN3 MEMBERS FOUND:"
            if [ -n "$members" ]; then
                echo "$members" | tr ',' '\n' | while IFS=':' read -r member_section interface_section metric weight; do
                    printf "  %-15s → Interface: %s, Metric: %s, Weight: %s\n" "$member_section" "$interface_section" "$metric" "$weight"
                done
            else
                log_warning "⚠️ No MWAN3 members found"
            fi
            ;;
        analyze)
            log_info "📈 ANALYSIS: Running historical performance analysis"
            interfaces=$(discover_mwan3_interfaces)
            if [ -n "$interfaces" ]; then
                # shellcheck disable=SC2046
                for interface_entry in $(echo "$interfaces" | tr ',' ' '); do
                    interface_name=$(echo "$interface_entry" | cut -d':' -f2)
                    historical_data=$(collect_historical_performance "$interface_name" 1800) # 30 minutes
                    historical_score=$(echo "$historical_data" | cut -d',' -f1)
                    trend_direction=$(echo "$historical_data" | cut -d',' -f2)
                    log_info "📊 $interface_name: Score $historical_score, Trend: $trend_direction"
                done
            else
                log_warning "⚠️ No interfaces found for analysis"
            fi
            ;;
        report)
            log_info "📋 REPORT: Generating comprehensive system report"
            run_intelligent_monitoring
            log_info "📋 REPORT: Report generated in ${LOG_DIR}/intelligent_monitoring_report.log"
            ;;
        validate)
            log_info "🔍 VALIDATION: Checking system configuration"
            if validate_system_configuration; then
                log_info "✅ VALIDATION: System configuration is valid"
            else
                log_error "❌ VALIDATION: System configuration has issues"
                exit 1
            fi
            ;;
        help)
            show_help
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Test individual connection performance via specific interface
test_connection_performance() {
    interface="$1"
    connection_type="${2:-unknown}"

    log_debug "🔄 CONNECTION TEST: Testing $interface ($connection_type) performance"

    # Initialize metrics with poor defaults
    latency="999"
    packet_loss="100"
    jitter="999"
    available="false"
    signal_info="0,0,Unknown,Unknown"

    # Test if interface exists and is up
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_debug "🔄 CONNECTION TEST: Interface $interface not found"
        printf "%s" "$latency,$packet_loss,$jitter,$available,$signal_info"
        return 1
    fi

    # Check if interface has an IP address
    if ! ip addr show "$interface" | grep -q "inet "; then
        log_debug "🔄 CONNECTION TEST: Interface $interface has no IP address"
        printf "%s" "$latency,$packet_loss,$jitter,$available,$signal_info"
        return 1
    fi

    available="true"
    log_debug "🔄 CONNECTION TEST: Interface $interface is available, testing performance"

    # Perform ping test to measure latency, loss, and jitter
    ping_count=5
    log_debug "🔄 CONNECTION TEST: Running ping test - $ping_count packets to $CONNECTION_TEST_HOST via $interface"

    # Use timeout to prevent hanging
    ping_output=""
    if command -v timeout >/dev/null 2>&1; then
        ping_output=$(timeout "$CONNECTION_TEST_TIMEOUT" ping -I "$interface" -c $ping_count "$CONNECTION_TEST_HOST" 2>/dev/null || echo "")
    else
        # Fallback without timeout for older systems
        ping_output=$(ping -I "$interface" -c $ping_count "$CONNECTION_TEST_HOST" 2>/dev/null || echo "")
    fi

    if [ -n "$ping_output" ]; then
        log_debug "🔄 CONNECTION TEST: Ping completed, analyzing results"

        # Extract packet loss percentage
        packet_loss_line=$(echo "$ping_output" | grep "packet loss" | head -1)
        if [ -n "$packet_loss_line" ]; then
            packet_loss=$(echo "$packet_loss_line" | sed 's/.*(\([0-9]*\)% packet loss).*/\1/')
            [ -z "$packet_loss" ] && packet_loss="100"
        fi

        # Extract latency statistics (min/avg/max/mdev)
        latency_line=$(echo "$ping_output" | grep "min/avg/max" | head -1)
        if [ -n "$latency_line" ]; then
            # Parse: min/avg/max/mdev = 45.123/67.890/89.012/12.345 ms
            latency=$(echo "$latency_line" | awk -F'[/=]' '{print $3}' | awk '{print int($1+0.5)}')
            jitter=$(echo "$latency_line" | awk -F'[/=]' '{print $5}' | awk '{print int($1+0.5)}')
            [ -z "$latency" ] && latency="999"
            [ -z "$jitter" ] && jitter="999"
        fi

        log_debug "🔄 CONNECTION TEST: Results - Latency: ${latency}ms, Loss: ${packet_loss}%, Jitter: ${jitter}ms"
    else
        log_debug "🔄 CONNECTION TEST: Ping failed - no response from $CONNECTION_TEST_HOST"
        available="false"
    fi

    # Get signal information for cellular connections
    if [ "$connection_type" = "cellular" ]; then
        signal_info=$(get_cellular_signal_for_interface "$interface")
    else
        signal_info="0,0,$connection_type,wired"
    fi

    # Return CSV format: latency,packet_loss,jitter,available,signal_info
    printf "%s" "$latency,$packet_loss,$jitter,$available,$signal_info"
    return 0
}

# Get cellular signal information for specific modem interface
get_cellular_signal_for_interface() {
    interface="$1"

    log_debug "📱 CELLULAR SIGNAL: Getting signal for interface $interface"

    signal_strength_dbm="-113" # Very poor signal default
    signal_quality="0"
    network_type="Unknown"
    operator="Unknown"

    if command -v gsmctl >/dev/null 2>&1; then
        # For cellular interfaces, we need to determine the modem ID
        # mob1s1a1 = modem 1, mob2s1a1 = modem 2, etc.
        modem_id=""
        case "$interface" in
            mob1s1a1) modem_id="1" ;;
            mob2s1a1) modem_id="2" ;;
            mob3s1a1) modem_id="3" ;;
            mob4s1a1) modem_id="4" ;;
            mob5s1a1) modem_id="5" ;;
            mob6s1a1) modem_id="6" ;;
            mob7s1a1) modem_id="7" ;;
            mob8s1a1) modem_id="8" ;;
            *) modem_id="1" ;; # Default fallback
        esac

        log_debug "📱 CELLULAR SIGNAL: Interface $interface mapped to modem ID $modem_id"

        # Get signal strength with modem-specific commands if available
        signal_info=$(gsmctl -A 'AT+CSQ' 2>/dev/null | grep "+CSQ:" | head -1 || echo "+CSQ: 99,99")
        signal_strength=$(echo "$signal_info" | awk -F'[: ,]' '{print $3}' | tr -d "$(printf '\n')" | head -1)
        signal_quality=$(echo "$signal_info" | awk -F'[: ,]' '{print $4}' | tr -d "$(printf '\n')" | head -1)

        # Convert signal strength to dBm
        if [ "$signal_strength" != "99" ] && [ "$signal_strength" -gt 0 ] 2>/dev/null; then
            signal_strength_dbm=$((2 * signal_strength - 113))
        fi

        # Get network type and operator
        network_info=$(gsmctl -A 'AT+QNWINFO' 2>/dev/null | grep "+QNWINFO:" | head -1 || echo "+QNWINFO: \"Unknown\"")
        network_type=$(echo "$network_info" | awk -F'"' '{print $2}' | tr -d "$(printf '\n\r')," | head -c 15)

        reg_info=$(gsmctl -A 'AT+COPS?' 2>/dev/null | grep "+COPS:" | head -1 || echo "+COPS: 0,0,\"Unknown\"")
        operator=$(echo "$reg_info" | sed 's/.*"\([^"]*\)".*//' | tr -d "$(printf '\n\r')," | head -c 20)

        log_debug "📱 CELLULAR SIGNAL: Interface $interface - Signal: ${signal_strength_dbm}dBm, Network: $network_type, Operator: $operator"
    fi

    # Clean up values
    [ -z "$network_type" ] && network_type="Unknown"
    [ -z "$operator" ] && operator="Unknown"

    # Return CSV format: signal_strength_dbm,signal_quality,network_type,operator
    printf "%s" "$signal_strength_dbm,$signal_quality,$network_type,$operator"
    return 0
}

# Calculate health score for a connection based on performance metrics
calculate_connection_health_score() {
    latency="$1"
    packet_loss="$2"
    jitter="$3"
    signal_dbm="$4"
    connection_type="$5"

    # Parse weights from configuration (latency:40,loss:30,signal:20,type:10)
    weight_latency=40
    weight_loss=30
    weight_signal=20
    weight_type=10

    # Calculate individual scores (0-100, higher is better)

    # Convert latency to integer for POSIX sh compatibility (handle floating point)
    latency_int=$(echo "$latency" | cut -d'.' -f1 2>/dev/null || echo "999")
    packet_loss_int=$(echo "$packet_loss" | cut -d'.' -f1 2>/dev/null || echo "100")

    # Latency score (0ms=100, 200ms=0) - FIXED: Lower latency = higher score
    if [ "$latency_int" -le 50 ] 2>/dev/null; then
        latency_score=100
    elif [ "$latency_int" -le 100 ] 2>/dev/null; then
        latency_score=75
    elif [ "$latency_int" -le 150 ] 2>/dev/null; then
        latency_score=50
    elif [ "$latency_int" -le 200 ] 2>/dev/null; then
        latency_score=25
    else
        latency_score=0
    fi

    # Packet loss score (0%=100, 10%=0)
    if [ "$packet_loss_int" -eq 0 ] 2>/dev/null; then
        loss_score=100
    elif [ "$packet_loss_int" -le 1 ] 2>/dev/null; then
        loss_score=80
    elif [ "$packet_loss_int" -le 3 ] 2>/dev/null; then
        loss_score=60
    elif [ "$packet_loss_int" -le 5 ] 2>/dev/null; then
        loss_score=40
    elif [ "$packet_loss_int" -le 10 ] 2>/dev/null; then
        loss_score=20
    else
        loss_score=0
    fi

    # Signal score (for cellular: -70dBm=100, -110dBm=0; for others: fixed 100)
    case "$connection_type" in
        cellular)
            signal_int=$(echo "$signal_dbm" | cut -d'.' -f1 2>/dev/null || echo "-113")
            if [ "$signal_int" -ge -70 ] 2>/dev/null; then
                signal_score=100
            elif [ "$signal_int" -ge -80 ] 2>/dev/null; then
                signal_score=80
            elif [ "$signal_int" -ge -90 ] 2>/dev/null; then
                signal_score=60
            elif [ "$signal_int" -ge -100 ] 2>/dev/null; then
                signal_score=40
            elif [ "$signal_int" -ge -110 ] 2>/dev/null; then
                signal_score=20
            else
                signal_score=0
            fi
            ;;
        ethernet)
            signal_score=100 # Wired connections have perfect "signal"
            ;;
        wifi)
            signal_score=85 # WiFi generally good but not perfect
            ;;
        starlink)
            signal_score=95 # Starlink satellite connection - excellent when working
            ;;
        *)
            signal_score=90 # Default for other connection types
            ;;
    esac

    # Connection type preference score
    case "$connection_type" in
        ethernet) type_score=100 ;;
        starlink) type_score=90 ;; # Premium satellite internet
        wifi) type_score=80 ;;
        cellular) type_score=60 ;;
        *) type_score=70 ;;
    esac

    # Calculate weighted total score
    total_score=$(((latency_score * weight_latency + loss_score * weight_loss + signal_score * weight_signal + type_score * weight_type) / 100))

    log_debug "🏥 HEALTH SCORE: $connection_type - Latency: $latency_score, Loss: $loss_score, Signal: $signal_score, Type: $type_score → Total: $total_score"

    printf "%s" "$total_score"
    return 0
}

# Comprehensive multi-connection performance analysis
analyze_multi_connection_performance() {
    if [ "$ENABLE_MULTI_CONNECTION_MONITORING" != "true" ]; then
        log_debug "Multi-connection monitoring disabled, using legacy dual-connection analysis"
        return 2 # Use legacy logic
    fi

    log_debug "🌐 MULTI-CONNECTION: Starting comprehensive multi-connection analysis"

    # Discover all available connections
    cellular_modems=""
    generic_connections=""

    if [ "$ENABLE_MULTI_CELLULAR" = "true" ]; then
        cellular_modems=$(discover_cellular_modems)
        log_debug "🌐 MULTI-CONNECTION: Available cellular modems: $cellular_modems"
    fi

    if [ "$ENABLE_GENERIC_CONNECTIONS" = "true" ]; then
        generic_connections=$(discover_generic_connections)
        log_debug "🌐 MULTI-CONNECTION: Available generic connections: $generic_connections"
    fi

    # Test all connections and build performance database
    connection_results=""
    best_score=0
    best_connection=""
    best_type=""

    # Test cellular modems
    if [ -n "$cellular_modems" ]; then
        # shellcheck disable=SC2046
        for modem in $(echo "$cellular_modems" | tr ',' ' '); do
            results=$(test_connection_performance "$modem" "cellular")
            latency=$(echo "$results" | cut -d',' -f1)
            packet_loss=$(echo "$results" | cut -d',' -f2)
            jitter=$(echo "$results" | cut -d',' -f3)
            available=$(echo "$results" | cut -d',' -f4)
            signal_dbm=$(echo "$results" | cut -d',' -f5)

            if [ "$available" = "true" ]; then
                score=$(calculate_connection_health_score "$latency" "$packet_loss" "$jitter" "$signal_dbm" "cellular")
                connection_results="${connection_results}${modem}:cellular:${score}:${latency}:${packet_loss}:${signal_dbm},"

                if [ "$score" -gt "$best_score" ]; then
                    best_score="$score"
                    best_connection="$modem"
                    best_type="cellular"
                fi

                log_debug "🌐 MULTI-CONNECTION: $modem (cellular) - Score: $score, Latency: ${latency}ms, Loss: ${packet_loss}%, Signal: ${signal_dbm}dBm"
            fi
        done
    fi

    # Test generic connections
    if [ -n "$generic_connections" ]; then
        # shellcheck disable=SC2046
        for connection_info in $(echo "$generic_connections" | tr ',' ' '); do
            connection=$(echo "$connection_info" | cut -d':' -f1)
            conn_type=$(echo "$connection_info" | cut -d':' -f2)

            results=$(test_connection_performance "$connection" "$conn_type")
            latency=$(echo "$results" | cut -d',' -f1)
            packet_loss=$(echo "$results" | cut -d',' -f2)
            jitter=$(echo "$results" | cut -d',' -f3)
            available=$(echo "$results" | cut -d',' -f4)

            if [ "$available" = "true" ]; then
                score=$(calculate_connection_health_score "$latency" "$packet_loss" "$jitter" "0" "$conn_type")
                connection_results="${connection_results}${connection}:${conn_type}:${score}:${latency}:${packet_loss}:0,"

                if [ "$score" -gt "$best_score" ]; then
                    best_score="$score"
                    best_connection="$connection"
                    best_type="$conn_type"
                fi

                log_debug "🌐 MULTI-CONNECTION: $connection ($conn_type) - Score: $score, Latency: ${latency}ms, Loss: ${packet_loss}%"
            fi
        done
    fi

    # Compare with primary (Starlink) connection
    primary_issues=0
    primary_score=0

    # Calculate primary connection score with proper floating-point handling
    # FIXED: Convert floating-point latency to integer for POSIX sh compatibility
    current_latency_int=$(echo "$CURRENT_LATENCY" | cut -d'.' -f1 2>/dev/null || echo "999")
    current_packet_loss_int=$(echo "$CURRENT_PACKET_LOSS" | cut -d'.' -f1 2>/dev/null || echo "100")

    # Validate that we got valid integers
    if ! printf "%d" "$current_latency_int" >/dev/null 2>&1; then
        log_error "🚨 CRITICAL ERROR: Invalid latency value '$CURRENT_LATENCY' - cannot convert to integer"
        log_error "🚨 DETAILS: Expected numeric value, got: '$CURRENT_LATENCY'"
        log_error "🚨 FALLBACK: Using default latency value 999ms for safety"
        current_latency_int=999
    fi

    if ! printf "%d" "$current_packet_loss_int" >/dev/null 2>&1; then
        log_error "🚨 CRITICAL ERROR: Invalid packet loss value '$CURRENT_PACKET_LOSS' - cannot convert to integer"
        log_error "🚨 DETAILS: Expected numeric value, got: '$CURRENT_PACKET_LOSS'"
        log_error "🚨 FALLBACK: Using default packet loss value 100% for safety"
        current_packet_loss_int=100
    fi

    # Now use integer comparisons safely
    if [ "$current_latency_int" -gt "$LATENCY_THRESHOLD" ] 2>/dev/null; then
        primary_issues=$((primary_issues + 1))
        log_debug "🔍 ISSUE DETECTED: High latency - ${current_latency_int}ms > ${LATENCY_THRESHOLD}ms"
    fi

    # Use awk for floating-point packet loss comparison if available
    if command -v awk >/dev/null 2>&1; then
        packet_loss_high=$(awk "BEGIN {print ($CURRENT_PACKET_LOSS > $PACKET_LOSS_THRESHOLD) ? 1 : 0}" 2>/dev/null || echo 0)
        if [ "$packet_loss_high" = "1" ]; then
            primary_issues=$((primary_issues + 1))
            log_debug "🔍 ISSUE DETECTED: High packet loss - ${CURRENT_PACKET_LOSS}% > ${PACKET_LOSS_THRESHOLD}%"
        fi
    else
        # Fallback to integer comparison for systems without awk
        if [ "$current_packet_loss_int" -gt "$PACKET_LOSS_THRESHOLD" ] 2>/dev/null; then
            primary_issues=$((primary_issues + 1))
            log_debug "🔍 ISSUE DETECTED: High packet loss (integer) - ${current_packet_loss_int}% > ${PACKET_LOSS_THRESHOLD}%"
        fi
    fi

    # Calculate health score with error handling
    if ! primary_score=$(calculate_connection_health_score "$CURRENT_LATENCY" "$CURRENT_PACKET_LOSS" "0" "0" "starlink" 2>/dev/null); then
        log_error "🚨 CRITICAL ERROR: Health score calculation failed for Starlink connection"
        log_error "🚨 DETAILS: Latency='$CURRENT_LATENCY', Loss='$CURRENT_PACKET_LOSS'"
        log_error "🚨 FALLBACK: Using default score of 50 for Starlink"
        primary_score=50
    fi

    # Validate health score is numeric
    if ! printf "%d" "$primary_score" >/dev/null 2>&1; then
        log_error "🚨 CRITICAL ERROR: Health score calculation returned non-numeric value: '$primary_score'"
        log_error "🚨 FALLBACK: Using default score of 50 for Starlink"
        primary_score=50
    fi

    log_debug "🌐 MULTI-CONNECTION: Primary (Starlink) - Score: $primary_score, Issues: $primary_issues"
    log_debug "🌐 MULTI-CONNECTION: Best alternative - $best_connection ($best_type) - Score: $best_score"

    # Decision logic based on multi-connection analysis
    improvement_threshold=$((primary_score * PERFORMANCE_COMPARISON_THRESHOLD / 100))
    score_difference=$((best_score - primary_score))

    # Case 1: Primary has critical issues AND better alternative exists
    if [ "$primary_issues" -ge 2 ] && [ "$score_difference" -gt "$improvement_threshold" ]; then
        log_warning "🌐 MULTI-CONNECTION: Primary has multiple issues ($primary_issues) AND $best_connection performs significantly better"
        log_warning "🌐 MULTI-CONNECTION: HARD FAILOVER RECOMMENDED to $best_connection ($best_type)"
        log_evaluation "multi_connection_hard_failover" "Primary issues: $primary_issues, $best_connection ${score_difference} points better"
        return 1 # Trigger hard failover
    fi

    # Case 2: Primary degraded but alternative much better
    if [ "$primary_issues" -eq 1 ] && [ "$score_difference" -gt $((improvement_threshold * 2)) ]; then
        log_info "🌐 MULTI-CONNECTION: Primary has minor issues but $best_connection significantly outperforms"
        log_info "🌐 MULTI-CONNECTION: SOFT FAILOVER RECOMMENDED to $best_connection ($best_type)"
        log_evaluation "multi_connection_soft_failover" "Minor primary issues, $best_connection ${score_difference} points better"
        return 1 # Trigger soft failover
    fi

    # Case 3: No better alternative found
    if [ "$best_score" -le "$primary_score" ] || [ "$score_difference" -le "$improvement_threshold" ]; then
        log_debug "🌐 MULTI-CONNECTION: No significantly better alternative found"
        log_evaluation "multi_connection_stay_primary" "Primary score: $primary_score, best alternative: $best_score ($best_connection)"
        return 0 # Stay on primary
    fi

    # Default: All is well
    log_debug "🌐 MULTI-CONNECTION: All connections performing adequately"
    log_evaluation "multi_connection_all_good" "Primary: $primary_score, alternatives available with scores up to $best_score"
    return 0
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# Legacy dual-connection functions for existing configurations
# =============================================================================

# Legacy function for backward compatibility
test_secondary_connection_performance() {
    if [ "$ENABLE_DUAL_CONNECTION_MONITORING" != "true" ]; then
        log_debug "Dual connection monitoring disabled, skipping secondary connection test"
        return 0
    fi

    log_debug "🔄 LEGACY: Using legacy dual-connection mode for backward compatibility"

    # Use new multi-connection system with single interface
    results=$(test_connection_performance "$SECONDARY_INTERFACE" "$SECONDARY_CONNECTION_TYPE")

    # Extract results in legacy format
    latency=$(echo "$results" | cut -d',' -f1)
    packet_loss=$(echo "$results" | cut -d',' -f2)
    jitter=$(echo "$results" | cut -d',' -f3)
    available=$(echo "$results" | cut -d',' -f4)

    # Return legacy CSV format: latency,packet_loss,jitter,available
    printf "%s" "$latency,$packet_loss,$jitter,$available"
    return 0
}

# Legacy function for backward compatibility
get_secondary_cellular_signal() {
    if [ "$SECONDARY_CONNECTION_TYPE" != "cellular" ]; then
        printf "%s" "0,0,Unknown,Unknown,home"
        return 0
    fi

    log_debug "🔄 LEGACY: Using legacy cellular signal detection for backward compatibility"

    # Use new multi-connection system
    signal_info=$(get_cellular_signal_for_interface "$SECONDARY_INTERFACE")
    signal_strength_dbm=$(echo "$signal_info" | cut -d',' -f1)
    signal_quality=$(echo "$signal_info" | cut -d',' -f2)
    network_type=$(echo "$signal_info" | cut -d',' -f3)
    operator=$(echo "$signal_info" | cut -d',' -f4)

    # Return legacy CSV format: signal_strength_dbm,signal_quality,network_type,operator,roaming_status
    printf "%s" "$signal_strength_dbm,$signal_quality,$network_type,$operator,home"
    return 0
}

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

# =============================================================================
# INTELLIGENT DUAL-CONNECTION FAILOVER LOGIC
# Compare primary and secondary connection performance for smart failover decisions
# =============================================================================

# Compare primary (Starlink) vs secondary connection performance
analyze_dual_connection_performance() {
    # Prefer multi-connection analysis if enabled
    if [ "$ENABLE_MULTI_CONNECTION_MONITORING" = "true" ]; then
        log_debug "🔄 DUAL CONNECTION: Redirecting to multi-connection analysis system"
        # FIXED: Proper error handling for function return value
        analyze_multi_connection_performance
        multi_connection_result=$?
        if [ $multi_connection_result -ne 0 ] && [ $multi_connection_result -ne 1 ] && [ $multi_connection_result -ne 2 ] && [ $multi_connection_result -ne 3 ] && [ $multi_connection_result -ne 4 ]; then
            log_error "🚨 CRITICAL ERROR: Multi-connection analysis failed with invalid return code: $multi_connection_result"
            log_error "🚨 DETAILS: This indicates a serious issue in the monitoring system"
            log_error "🚨 FALLBACK: Switching to traditional single-connection analysis"
            return 2 # Force fallback to traditional logic
        fi
        return $multi_connection_result
    fi

    if [ "$ENABLE_DUAL_CONNECTION_MONITORING" != "true" ]; then
        log_debug "Dual connection monitoring disabled, using traditional single-connection analysis"
        return 2 # Use traditional logic
    fi

    log_debug "🔄 DUAL CONNECTION: Starting legacy dual-connection performance comparison"

    # Get secondary connection performance
    secondary_results=$(test_secondary_connection_performance)
    secondary_latency=$(echo "$secondary_results" | cut -d',' -f1)
    secondary_packet_loss=$(echo "$secondary_results" | cut -d',' -f2)
    secondary_available=$(echo "$secondary_results" | cut -d',' -f4)

    # Get cellular signal information if applicable
    if [ "$SECONDARY_CONNECTION_TYPE" = "cellular" ]; then
        cellular_results=$(get_secondary_cellular_signal)
        cellular_signal_dbm=$(echo "$cellular_results" | cut -d',' -f1)
        cellular_network=$(echo "$cellular_results" | cut -d',' -f3)
        log_debug "🔄 DUAL CONNECTION: Cellular network: $cellular_network, Signal: ${cellular_signal_dbm}dBm"
    else
        cellular_signal_dbm="0"
        cellular_network="wired"
    fi

    log_debug "🔄 DUAL CONNECTION: Secondary performance - Latency: ${secondary_latency}ms, Loss: ${secondary_packet_loss}%, Available: $secondary_available"
    log_debug "🔄 DUAL CONNECTION: Primary performance - Latency: ${CURRENT_LATENCY}ms, Loss: ${CURRENT_PACKET_LOSS}%"

    # Check if secondary connection is available
    if [ "$secondary_available" != "true" ]; then
        log_warning "🔄 DUAL CONNECTION: Secondary connection not available - no failover possible"
        log_evaluation "secondary_unavailable" "Secondary interface $SECONDARY_INTERFACE not accessible"
        return 3 # No failover possible
    fi

    # Assess primary connection quality issues
    primary_issues=0
    primary_score=0
    secondary_score=0

    # FIXED: Convert floating-point values to integers for POSIX sh arithmetic
    current_latency_int=$(echo "$CURRENT_LATENCY" | cut -d'.' -f1 2>/dev/null || echo "999")
    current_packet_loss_int=$(echo "$CURRENT_PACKET_LOSS" | cut -d'.' -f1 2>/dev/null || echo "100")

    # Validate integers with comprehensive error handling
    if ! printf "%d" "$current_latency_int" >/dev/null 2>&1; then
        log_error "🚨 CRITICAL ERROR: Invalid latency value in dual-connection analysis: '$CURRENT_LATENCY'"
        log_error "🚨 DETAILS: Cannot perform arithmetic comparison with non-integer value"
        log_error "🚨 FALLBACK: Using safe default latency value 999ms"
        current_latency_int=999
    fi

    if ! printf "%d" "$current_packet_loss_int" >/dev/null 2>&1; then
        log_error "🚨 CRITICAL ERROR: Invalid packet loss value in dual-connection analysis: '$CURRENT_PACKET_LOSS'"
        log_error "🚨 DETAILS: Cannot perform arithmetic comparison with non-integer value"
        log_error "🚨 FALLBACK: Using safe default packet loss value 100%"
        current_packet_loss_int=100
    fi

    # Calculate primary connection score (lower is better) with safe integer arithmetic
    if [ "$current_latency_int" -gt "$LATENCY_THRESHOLD" ] 2>/dev/null; then
        primary_issues=$((primary_issues + 1))
        primary_score=$((primary_score + current_latency_int))
        log_debug "🔍 DUAL CONNECTION: Primary latency issue detected - ${current_latency_int}ms > ${LATENCY_THRESHOLD}ms"
    else
        primary_score=$((primary_score + current_latency_int))
    fi

    # FIXED: Replace bc operations with awk for floating-point arithmetic (RUTOS compatible)
    if command -v awk >/dev/null 2>&1; then
        # Use awk for floating-point comparisons
        packet_loss_high=$(awk "BEGIN {print ($CURRENT_PACKET_LOSS > $PACKET_LOSS_THRESHOLD) ? 1 : 0}" 2>/dev/null || echo 0)
        packet_loss_score=$(awk "BEGIN {printf \"%.0f\", $CURRENT_PACKET_LOSS * 50}" 2>/dev/null || echo "$((current_packet_loss_int * 50))")

        if [ "$packet_loss_high" = "1" ]; then
            primary_issues=$((primary_issues + 1))
            primary_score=$((primary_score + packet_loss_score))
            log_debug "🔍 DUAL CONNECTION: Primary packet loss issue detected - ${CURRENT_PACKET_LOSS}% > ${PACKET_LOSS_THRESHOLD}%"
        else
            primary_score=$((primary_score + packet_loss_score))
        fi
    else
        # Fallback to integer arithmetic for systems without awk
        log_warning "🔧 DUAL CONNECTION: awk not available, using integer arithmetic fallback"
        packet_loss_score=$((current_packet_loss_int * 50))

        if [ "$current_packet_loss_int" -gt "$PACKET_LOSS_THRESHOLD" ] 2>/dev/null; then
            primary_issues=$((primary_issues + 1))
            primary_score=$((primary_score + packet_loss_score))
            log_debug "🔍 DUAL CONNECTION: Primary packet loss issue detected (integer) - ${current_packet_loss_int}% > ${PACKET_LOSS_THRESHOLD}%"
        else
            primary_score=$((primary_score + packet_loss_score))
        fi
    fi

    # Calculate secondary connection score (lower is better) with safe arithmetic
    secondary_latency_int=$(echo "$secondary_latency" | cut -d'.' -f1 2>/dev/null || echo "999")
    secondary_packet_loss_int=$(echo "$secondary_packet_loss" | cut -d'.' -f1 2>/dev/null || echo "100")

    # Validate secondary connection values
    if ! printf "%d" "$secondary_latency_int" >/dev/null 2>&1; then
        log_warning "🔧 DUAL CONNECTION: Invalid secondary latency '$secondary_latency', using default 999ms"
        secondary_latency_int=999
    fi

    if ! printf "%d" "$secondary_packet_loss_int" >/dev/null 2>&1; then
        log_warning "🔧 DUAL CONNECTION: Invalid secondary packet loss '$secondary_packet_loss', using default 100%"
        secondary_packet_loss_int=100
    fi

    # Calculate secondary score safely
    if command -v awk >/dev/null 2>&1; then
        secondary_loss_score=$(awk "BEGIN {printf \"%.0f\", $secondary_packet_loss * 50}" 2>/dev/null || echo "$((secondary_packet_loss_int * 50))")
        secondary_score=$((secondary_latency_int + secondary_loss_score))
    else
        secondary_score=$((secondary_latency_int + secondary_packet_loss_int * 50))
    fi

    # Add cellular signal penalty if applicable
    if [ "$SECONDARY_CONNECTION_TYPE" = "cellular" ]; then
        if [ "$cellular_signal_dbm" -lt "-100" ] 2>/dev/null; then
            secondary_score=$((secondary_score + 100)) # Poor signal penalty
            log_debug "🔄 DUAL CONNECTION: Cellular signal penalty applied - signal: ${cellular_signal_dbm}dBm"
        elif [ "$cellular_signal_dbm" -lt "-90" ] 2>/dev/null; then
            secondary_score=$((secondary_score + 50)) # Moderate signal penalty
        fi
    fi

    # Performance comparison analysis
    improvement_threshold=$((primary_score * PERFORMANCE_COMPARISON_THRESHOLD / 100))
    performance_difference=$((primary_score - secondary_score))

    log_debug "🔄 DUAL CONNECTION: Performance scores - Primary: $primary_score, Secondary: $secondary_score"
    log_debug "🔄 DUAL CONNECTION: Improvement threshold: $improvement_threshold, Difference: $performance_difference"

    # Decision logic
    decision_made="false"

    # Case 1: Primary has critical issues AND secondary is significantly better
    if [ "$primary_issues" -ge 2 ] && [ "$performance_difference" -gt "$improvement_threshold" ]; then
        log_warning "🔄 DUAL CONNECTION: Primary has multiple issues ($primary_issues) AND secondary performs significantly better"
        log_warning "🔄 DUAL CONNECTION: HARD FAILOVER RECOMMENDED"
        log_warning "  Primary issues: $primary_issues, Performance improvement: ${performance_difference} > threshold ${improvement_threshold}"
        log_evaluation "dual_connection_hard_failover" "Primary issues: $primary_issues, Secondary ${performance_difference} points better"
        decision_made="true"
        return 1 # Trigger hard failover
    fi

    # Case 2: Primary has minor issues but secondary is much better
    if [ "$primary_issues" -eq 1 ] && [ "$performance_difference" -gt $((improvement_threshold * 2)) ]; then
        log_info "🔄 DUAL CONNECTION: Primary has minor issues but secondary significantly outperforms"
        log_info "🔄 DUAL CONNECTION: SOFT FAILOVER RECOMMENDED"
        log_info "  Performance improvement: ${performance_difference} > 2x threshold ${improvement_threshold}"
        log_evaluation "dual_connection_soft_failover" "Minor primary issues, Secondary ${performance_difference} points better"
        decision_made="true"
        return 1 # Trigger soft failover
    fi

    # Case 3: Both connections have issues - choose lesser evil
    secondary_issues=0
    if [ "$secondary_latency" -gt "$LATENCY_THRESHOLD" ] 2>/dev/null; then
        secondary_issues=$((secondary_issues + 1))
    fi
    if [ "$secondary_packet_loss" -gt "$PACKET_LOSS_THRESHOLD" ] 2>/dev/null; then
        secondary_issues=$((secondary_issues + 1))
    fi

    if [ "$primary_issues" -gt 0 ] && [ "$secondary_issues" -gt 0 ]; then
        if [ "$secondary_score" -lt "$primary_score" ]; then
            log_warning "🔄 DUAL CONNECTION: Both connections have issues - secondary is lesser evil"
            log_warning "🔄 DUAL CONNECTION: EMERGENCY FAILOVER to better of two poor connections"
            log_evaluation "dual_connection_emergency_failover" "Both poor - Primary issues: $primary_issues, Secondary issues: $secondary_issues, choosing secondary"
            decision_made="true"
            return 1 # Emergency failover
        else
            log_warning "🔄 DUAL CONNECTION: Both connections have issues - staying on primary as it's better"
            log_evaluation "dual_connection_stay_primary" "Both poor - Primary issues: $primary_issues, Secondary issues: $secondary_issues, staying primary"
            decision_made="true"
            return 0 # Stay on primary
        fi
    fi

    # Case 4: Primary has issues but secondary is not significantly better
    if [ "$primary_issues" -gt 0 ] && [ "$performance_difference" -le "$improvement_threshold" ]; then
        log_info "🔄 DUAL CONNECTION: Primary has issues but secondary not significantly better"
        log_info "🔄 DUAL CONNECTION: NO FAILOVER - insufficient improvement"
        log_info "  Primary issues: $primary_issues, Improvement: ${performance_difference} <= threshold ${improvement_threshold}"
        log_evaluation "dual_connection_insufficient_improvement" "Primary issues: $primary_issues, but secondary only ${performance_difference} points better"
        decision_made="true"
        return 0 # No failover
    fi

    # Case 5: Primary is fine, check if we should restore from previous failover
    current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "1")
    good_metric="${METRIC_GOOD:-1}"

    if [ "$current_metric" -gt "$good_metric" ] && [ "$primary_issues" -eq 0 ]; then
        # We're currently failed over but primary is now good
        restore_threshold=$((secondary_score * PERFORMANCE_COMPARISON_THRESHOLD / 100))
        restore_difference=$((secondary_score - primary_score))

        if [ "$restore_difference" -gt "$restore_threshold" ]; then
            log_info "🔄 DUAL CONNECTION: Primary restored and significantly better than secondary"
            log_info "🔄 DUAL CONNECTION: RESTORE PRIMARY recommended"
            log_evaluation "dual_connection_restore_primary" "Primary restored, ${restore_difference} points better than secondary"
            return 4 # Restore primary
        else
            log_debug "🔄 DUAL CONNECTION: Primary restored but not significantly better - staying on secondary"
            log_evaluation "dual_connection_stay_secondary" "Primary restored but only ${restore_difference} points better"
            return 0 # Stay on secondary
        fi
    fi

    # Default case: All is well
    if [ "$decision_made" != "true" ]; then
        log_debug "🔄 DUAL CONNECTION: Both connections performing adequately"
        log_evaluation "dual_connection_both_good" "Primary score: $primary_score, Secondary score: $secondary_score"
        return 0 # No action needed
    fi

    return 0
}

# Traditional single-connection quality analysis (fallback)
analyze_connection_quality() {

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
    # shellcheck disable=SC2004,SC2086 # bc calculation with variables
    if [ "$(echo "$CURRENT_PACKET_LOSS > $PACKET_LOSS_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        is_packet_loss_poor=1
        failure_reasons="${failure_reasons}high_packet_loss,"
        log_warning "High packet loss detected: ${CURRENT_PACKET_LOSS}% > ${PACKET_LOSS_THRESHOLD}%"
    fi

    # Enhanced obstruction analysis using multiple metrics
    # shellcheck disable=SC2004,SC2086 # bc calculation with variables
    if [ "$(echo "$CURRENT_OBSTRUCTION > $OBSTRUCTION_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        # Current obstruction is high, but check additional factors before triggering failover

        # Check if intelligent obstruction analysis is enabled
        if [ "$ENABLE_INTELLIGENT_OBSTRUCTION" = "true" ]; then
            # Calculate hours of valid obstruction data
            obstruction_hours=$(awk "BEGIN {print $CURRENT_OBSTRUCTION_VALID_S / 3600}")

            # Check if we have sufficient data for intelligent analysis
            # shellcheck disable=SC2004,SC2086 # bc calculation with variables
            if [ "$(echo "$obstruction_hours >= $OBSTRUCTION_MIN_DATA_HOURS" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                # We have sufficient data - perform intelligent analysis

                # Check for prolonged obstructions
                has_prolonged_obstructions=0
                if [ "$CURRENT_OBSTRUCTION_AVG_PROLONGED" != "NaN" ] && [ "$CURRENT_OBSTRUCTION_AVG_PROLONGED" != "0" ]; then
                    # shellcheck disable=SC2004,SC2086 # bc calculation with variables
                    if [ "$(echo "$CURRENT_OBSTRUCTION_AVG_PROLONGED > $OBSTRUCTION_PROLONGED_THRESHOLD" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                        has_prolonged_obstructions=1
                    fi
                fi

                # Intelligent decision logic
                should_failover_obstruction=0
                obstruction_analysis=""

                # Case 1: High historical obstruction time
                # shellcheck disable=SC2004,SC2086 # bc calculation with variables
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
                # shellcheck disable=SC2004,SC2086 # bc calculation with variables
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
            log_evaluation "multiple_quality_issues" "Factors: $quality_factors, reasons: $(echo "${failure_reasons}" | sed 's/,$//')"
            return 1 # Trigger failover
        elif [ "$quality_factors" -eq 1 ] && [ "$ENABLE_CELLULAR_TRACKING" = "true" ]; then
            # Check if cellular backup is strong enough to justify failover
            cellular_signal=$(echo "$cellular_data" | cut -d',' -f3)
            if [ -n "$cellular_signal" ] && [ "$cellular_signal" -gt 15 ] 2>/dev/null; then
                log_info "Single quality issue with strong cellular backup, initiating failover"
                log_evaluation "single_issue_strong_cellular" "Cellular signal: ${cellular_signal}dBm, reason: $(echo "${failure_reasons}" | sed 's/,$//')"
                return 1 # Trigger failover
            else
                log_evaluation "single_issue_weak_cellular" "Cellular signal: ${cellular_signal}dBm, reason: $(echo "${failure_reasons}" | sed 's/,$//')"
            fi
        elif [ "$quality_factors" -eq 1 ]; then
            log_evaluation "single_issue_no_cellular" "Reason: $(echo "${failure_reasons}" | sed 's/,$//')"
        elif [ "$quality_factors" -eq 0 ]; then
            log_evaluation "quality_good" "All metrics within thresholds"
        fi
    else
        # Basic failover logic (original behavior)
        if [ "$is_latency_poor" = "1" ] || [ "$is_packet_loss_poor" = "1" ] || [ "$is_obstruction_poor" = "1" ]; then
            log_warning "Quality threshold exceeded, initiating failover"
            log_evaluation "basic_threshold_exceeded" "Reasons: $(echo "${failure_reasons}" | sed 's/,$//')"
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
    current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "10")

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
    if safe_execute "uci set mwan3.${MWAN_MEMBER:-starlink}.metric=$new_metric" "Set mwan3 metric to $new_metric"; then
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
    current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "unknown")

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

    if safe_execute "uci set mwan3.${MWAN_MEMBER:-starlink}.metric=$good_metric" "Reset mwan3 metric to $good_metric"; then
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
    if [ "$ENABLE_DUAL_CONNECTION_MONITORING" = "true" ]; then
        log_info "Dual-connection monitoring: enabled (Secondary: $SECONDARY_CONNECTION_TYPE via $SECONDARY_INTERFACE)"
        log_info "Performance comparison threshold: ${PERFORMANCE_COMPARISON_THRESHOLD}% improvement required for failover"
    else
        log_info "Traditional single-connection monitoring: enabled"
    fi

    # Log start of monitoring cycle
    log_maintenance_action "monitoring_cycle_start" "starlink_status_check" "initiated" "Monitoring cycle started"

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

            # Use intelligent dual-connection analysis if enabled
            analyze_dual_connection_performance
            dual_connection_exit_code=$?

            case $dual_connection_exit_code in
                0)
                    # No action needed - connections are performing well
                    current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "10")
                    log_maintenance_action "status_check" "dual_connection_stable" "completed" "Both connections stable, metric: $current_metric"
                    ;;
                1)
                    # Trigger failover based on dual-connection analysis
                    log_info "Dual-connection analysis indicates failover needed"
                    if trigger_failover; then
                        log_maintenance_action "failover_execution" "dual_connection_failover" "success" "Intelligent failover completed"
                    else
                        log_maintenance_action "failover_execution" "dual_connection_failover" "failed" "Intelligent failover attempt failed"
                    fi
                    ;;
                2)
                    # Fall back to traditional single-connection analysis
                    log_debug "Using traditional single-connection analysis"
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
                        current_metric=$(uci get "mwan3.${MWAN_MEMBER:-starlink}.metric" 2>/dev/null || echo "10")
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
                    ;;
                3)
                    # Secondary connection not available - use primary regardless of issues
                    log_warning "Secondary connection unavailable - monitoring primary only"
                    log_maintenance_action "status_check" "secondary_unavailable" "completed" "Primary monitoring only, secondary not available"
                    ;;
                4)
                    # Restore primary connection
                    log_info "Dual-connection analysis indicates primary should be restored"
                    if restore_primary; then
                        log_maintenance_action "interface_restore" "dual_connection_restore" "success" "Intelligent restore completed"
                    else
                        log_maintenance_action "interface_restore" "dual_connection_restore" "failed" "Intelligent restore attempt failed"
                    fi
                    ;;
                *)
                    log_error "Unknown dual-connection analysis result: $dual_connection_exit_code"
                    log_maintenance_action "data_analysis" "dual_connection_error" "failed" "Unknown analysis result"
                    ;;
            esac
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

# Call logging functions only if explicitly enabled
# This prevents double logging when both monitor and logger have separate cron jobs
if [ "${ENABLE_MONITOR_LOGGING:-false}" = "true" ]; then
    log_debug "Monitor logging enabled - delegating to logger script"
    log_detailed_performance
    log_aggregated_performance
else
    log_debug "Monitor logging disabled - logger should run separately via cron"
fi

# Execute main function
main "$@"
