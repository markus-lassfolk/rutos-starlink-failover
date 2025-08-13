#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# === STARLINK PREDICTIVE FAILOVER SYSTEM ===
# Based on intelligent SNR monitoring and satellite handoff prediction
# This script implements proactive failover before connection degrades

readonly SCRIPT_NAME="starlink-predictive-failover-rutos.sh"

# === CONFIGURATION LOADING ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"
LOG_DIR="${LOG_DIR:-/usr/local/starlink/logs}"
STATE_DIR="${STATE_DIR:-/usr/local/starlink/state}"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    echo "[INFO] Configuration loaded from: $CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === LOGGING FUNCTIONS ===
log_info() {
    echo "[INFO] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[DEBUG] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
    fi
}

# === PREDICTIVE FAILOVER CONFIGURATION ===
# Set defaults for any missing configuration values
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
STARLINK_INTERFACE="${STARLINK_INTERFACE:-wan}"

# Predictive failover thresholds (from config template)
SNR_DROP_THRESHOLD="${STARLINK_SNR_DROP_THRESHOLD:-0.5}"
LATENCY_SPIKE_THRESHOLD="${STARLINK_LATENCY_SPIKE_THRESHOLD:-100}"
PACKET_LOSS_SPIKE_THRESHOLD="${STARLINK_PACKET_LOSS_SPIKE_THRESHOLD:-0.02}"
FAILBACK_STABILITY_CHECKS="${STARLINK_FAILBACK_STABILITY_CHECKS:-120}"
SATELLITE_HANDOFF_THRESHOLD="${STARLINK_SATELLITE_HANDOFF_THRESHOLD:-0.5}"

# State files
SNR_STATE_FILE="$STATE_DIR/starlink_snr_history.dat"
FAILOVER_STATE_FILE="$STATE_DIR/starlink_failover_state.dat"

# === STATE VARIABLES ===
current_snr=0
previous_snr=0
is_failed_over=false
failback_counter=0

# === STARLINK API FUNCTIONS ===
call_starlink_api() {
    local method="$1"
    local endpoint="$STARLINK_IP:$STARLINK_PORT"
    
    log_debug "Calling Starlink API: $method"
    
    # Try curl-based JSON-RPC call first
    if command -v curl >/dev/null 2>&1; then
        timeout 10 curl -s -m 10 -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\"}" \
            "http://$endpoint/JSONRpc" 2>/dev/null
    else
        log_error "curl not available for Starlink API calls"
        return 1
    fi
}

# === METRICS EXTRACTION FUNCTIONS ===
extract_snr() {
    local status_data="$1"
    echo "$status_data" | grep -o '"snr":[0-9.-]*' | cut -d':' -f2 | head -1
}

extract_latency() {
    local status_data="$1"
    # Try POP latency first (more accurate), fallback to ping latency
    local pop_latency=$(echo "$status_data" | grep -o '"pop_ping_latency_ms":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1)
    if [ -n "$pop_latency" ]; then
        echo "$pop_latency"
    else
        echo "$status_data" | grep -o '"ping_latency_ms":[0-9.]*' | cut -d':' -f2 | cut -d'.' -f1
    fi
}

extract_packet_loss() {
    local status_data="$1"
    echo "$status_data" | grep -o '"pop_ping_drop_rate":[0-9.]*' | cut -d':' -f2
}

extract_seconds_to_next_sat() {
    local status_data="$1"
    echo "$status_data" | grep -o '"seconds_to_first_nonempty_slot":[0-9.]*' | cut -d':' -f2
}

# === STATE MANAGEMENT ===
load_previous_snr() {
    if [ -f "$SNR_STATE_FILE" ]; then
        previous_snr=$(tail -1 "$SNR_STATE_FILE" 2>/dev/null || echo "0")
    else
        previous_snr=0
    fi
    log_debug "Previous SNR: $previous_snr"
}

save_current_snr() {
    echo "$current_snr" >> "$SNR_STATE_FILE"
    # Keep only last 100 entries
    tail -100 "$SNR_STATE_FILE" > "$SNR_STATE_FILE.tmp" && mv "$SNR_STATE_FILE.tmp" "$SNR_STATE_FILE"
}

load_failover_state() {
    if [ -f "$FAILOVER_STATE_FILE" ]; then
        . "$FAILOVER_STATE_FILE"
    fi
    log_debug "Failover state: is_failed_over=$is_failed_over, failback_counter=$failback_counter"
}

save_failover_state() {
    cat > "$FAILOVER_STATE_FILE" << EOF
is_failed_over=$is_failed_over
failback_counter=$failback_counter
EOF
}

# === FAILOVER LOGIC ===
execute_failover() {
    local reason="$1"
    log_info "EXECUTING FAILOVER: $reason"
    
    if command -v mwan3 >/dev/null 2>&1; then
        mwan3 ifdown "$STARLINK_INTERFACE"
        log_info "MWAN3 interface $STARLINK_INTERFACE disabled"
    else
        log_error "mwan3 command not available - cannot execute failover"
        return 1
    fi
    
    is_failed_over=true
    failback_counter=0
    save_failover_state
}

execute_failback() {
    local reason="$1"
    log_info "EXECUTING FAILBACK: $reason"
    
    if command -v mwan3 >/dev/null 2>&1; then
        mwan3 ifup "$STARLINK_INTERFACE"
        log_info "MWAN3 interface $STARLINK_INTERFACE enabled"
    else
        log_error "mwan3 command not available - cannot execute failback"
        return 1
    fi
    
    is_failed_over=false
    failback_counter=0
    save_failover_state
}

# === PREDICTIVE ANALYSIS ===
analyze_snr_trend() {
    local current="$1"
    local previous="$2"
    
    if [ "$previous" = "0" ] || [ -z "$previous" ] || [ "$current" = "0" ] || [ -z "$current" ]; then
        log_debug "No valid SNR data for trend analysis (current=$current, previous=$previous)"
        return 1
    fi
    
    # Convert to integer comparison (multiply by 10 to handle decimal)
    current_int=$(echo "$current * 10" | awk '{print int($1)}' 2>/dev/null || echo "0")
    previous_int=$(echo "$previous * 10" | awk '{print int($1)}' 2>/dev/null || echo "0")
    threshold_int=$(echo "$SNR_DROP_THRESHOLD * 10" | awk '{print int($1)}' 2>/dev/null || echo "5")
    
    drop_threshold=$((previous_int - threshold_int))
    
    if [ "$current_int" -lt "$drop_threshold" ]; then
        log_debug "SNR drop detected: $previous -> $current (threshold: $SNR_DROP_THRESHOLD)"
        return 0
    else
        log_debug "SNR stable: $previous -> $current"
        return 1
    fi
}

# === MAIN MONITORING LOOP ===
monitor_cycle() {
    log_debug "Starting predictive failover monitoring cycle"
    
    # Load previous state
    load_previous_snr
    load_failover_state
    
    # Get current status from Starlink API
    status_data=$(call_starlink_api "get_status")
    
    if [ -z "$status_data" ]; then
        log_error "Starlink API call failed - assuming Starlink is down"
        if [ "$is_failed_over" = "false" ]; then
            execute_failover "API unreachable"
        fi
        return 1
    fi
    
    # Extract key metrics
    current_snr=$(extract_snr "$status_data")
    latency=$(extract_latency "$status_data")
    packet_loss=$(extract_packet_loss "$status_data")
    seconds_to_next_sat=$(extract_seconds_to_next_sat "$status_data")
    
    log_debug "Current metrics: SNR=$current_snr, Latency=${latency}ms, Loss=$packet_loss, NextSat=${seconds_to_next_sat}s"
    
    # === FAILOVER DECISION LOGIC ===
    if [ "$is_failed_over" = "false" ]; then
        
        # Predictive Trigger 1: SNR Drop with Satellite Handoff Prediction
        if analyze_snr_trend "$current_snr" "$previous_snr"; then
            log_info "PREDICTIVE TRIGGER: SNR dropping trend detected"
            
            # Check if next satellite is far away (handoff will be problematic)
            if [ -n "$seconds_to_next_sat" ]; then
                # Convert to integer comparison
                sat_time_int=$(echo "$seconds_to_next_sat" | awk '{print int($1 * 10)}' 2>/dev/null || echo "0")
                threshold_int=$(echo "$SATELLITE_HANDOFF_THRESHOLD" | awk '{print int($1 * 10)}' 2>/dev/null || echo "5")
                
                if [ "$sat_time_int" -gt "$threshold_int" ]; then
                    execute_failover "SNR drop + satellite handoff delay (${seconds_to_next_sat}s)"
                else
                    log_debug "SNR dropping but next satellite is close - monitoring"
                fi
            fi
        fi
        
        # Reactive Trigger 2: Immediate Performance Issues
        if [ -n "$latency" ]; then
            latency_int=$(echo "$latency" | awk '{print int($1)}' 2>/dev/null || echo "0")
            if [ "$latency_int" -gt "$LATENCY_SPIKE_THRESHOLD" ]; then
                execute_failover "Latency spike: ${latency}ms > ${LATENCY_SPIKE_THRESHOLD}ms"
            fi
        fi
        
        if [ -n "$packet_loss" ]; then
            # Convert packet loss to percentage comparison (multiply by 100)
            loss_pct=$(echo "$packet_loss * 100" | awk '{print int($1)}' 2>/dev/null || echo "0")
            threshold_pct=$(echo "$PACKET_LOSS_SPIKE_THRESHOLD * 100" | awk '{print int($1)}' 2>/dev/null || echo "2")
            
            if [ "$loss_pct" -gt "$threshold_pct" ]; then
                execute_failover "Packet loss spike: ${packet_loss} > ${PACKET_LOSS_SPIKE_THRESHOLD}"
            fi
        fi
    fi
    
    # === FAILBACK DECISION LOGIC ===
    if [ "$is_failed_over" = "true" ]; then
        log_debug "In failover state - checking for failback conditions"
        
        # Get historical data for stability analysis
        if [ "${STARLINK_COLLECT_HISTORY:-1}" = "1" ]; then
            history_data=$(call_starlink_api "get_history")
            
            if [ -n "$history_data" ]; then
                # Simplified stability check - in production, implement full historical analysis
                log_debug "Analyzing Starlink stability for failback decision"
                
                # Check current metrics are good
                current_stable=true
                if [ -n "$packet_loss" ]; then
                    # Convert to percentage comparison
                    loss_pct=$(echo "$packet_loss * 100" | awk '{print int($1)}' 2>/dev/null || echo "0")
                    if [ "$loss_pct" -gt 1 ]; then  # > 1% packet loss
                        current_stable=false
                    fi
                fi
                
                if [ "$current_stable" = "true" ]; then
                    failback_counter=$((failback_counter + 1))
                    log_info "Starlink appears stable - failback counter: $failback_counter/$FAILBACK_STABILITY_CHECKS"
                else
                    failback_counter=0
                    log_debug "Starlink still unstable - resetting failback counter"
                fi
                
                if [ "$failback_counter" -ge "$FAILBACK_STABILITY_CHECKS" ]; then
                    execute_failback "Sustained stability achieved"
                fi
            else
                failback_counter=0
                log_debug "History API failed - resetting failback counter"
            fi
        fi
    fi
    
    # Save current state
    save_current_snr
    save_failover_state
    
    log_debug "Monitoring cycle completed"
}

# === DAEMON MODE ===
run_daemon() {
    log_info "Starting Starlink predictive failover daemon"
    log_info "Thresholds: SNR_DROP=$SNR_DROP_THRESHOLD, LATENCY=$LATENCY_SPIKE_THRESHOLD, LOSS=$PACKET_LOSS_SPIKE_THRESHOLD"
    
    while true; do
        monitor_cycle
        sleep 2  # 2-second monitoring interval
    done
}

# === MAIN SCRIPT LOGIC ===
main() {
    case "${1:-daemon}" in
        "test")
            log_info "=== PREDICTIVE FAILOVER TEST MODE ==="
            monitor_cycle
            log_info "Test completed"
            ;;
        "daemon")
            run_daemon
            ;;
        "status")
            load_failover_state
            if [ "$is_failed_over" = "true" ]; then
                echo "Starlink is in FAILOVER state (counter: $failback_counter)"
            else
                echo "Starlink is ACTIVE"
            fi
            ;;
        "reset")
            rm -f "$SNR_STATE_FILE" "$FAILOVER_STATE_FILE"
            log_info "Predictive failover state reset"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [test|daemon|status|reset|help]"
            echo "  test   - Run single monitoring cycle"
            echo "  daemon - Run continuous predictive monitoring"
            echo "  status - Show current failover state"
            echo "  reset  - Reset all state data"
            echo "  help   - Show this help"
            ;;
        *)
            log_error "Invalid command: $1"
            main "help"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
