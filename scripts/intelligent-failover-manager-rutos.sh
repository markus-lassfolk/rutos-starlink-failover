#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "intelligent-failover-manager-rutos.sh" "$SCRIPT_VERSION"

# === INTELLIGENT FAILOVER MANAGER ===
# Uses connection scoring system for smart failover decisions
# Replaces simple threshold-based failover with sophisticated multi-metric analysis

readonly SCRIPT_NAME="intelligent-failover-manager-rutos.sh"

# === CONFIGURATION LOADING ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"
LOG_DIR="${LOG_DIR:-/usr/local/starlink/logs}"
STATE_DIR="${STATE_DIR:-/usr/local/starlink/state}"
SCRIPTS_DIR="$(dirname "$0")"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    log_info "Configuration loaded from: $CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === FAILOVER STATE MANAGEMENT ===
FAILOVER_STATE_FILE="$STATE_DIR/intelligent_failover_state.dat"
FAILOVER_HISTORY_FILE="$LOG_DIR/failover_history.log"
CURRENT_PRIMARY_FILE="$STATE_DIR/current_primary_interface.dat"

# === FAILOVER CONFIGURATION ===
CHECK_INTERVAL="${SCORE_CALCULATION_INTERVAL:-60}"     # How often to check scores
FAILOVER_THRESHOLD="${SCORE_FAILOVER_THRESHOLD:-10}"   # Min score difference for failover
FAILBACK_THRESHOLD="${SCORE_FAILBACK_THRESHOLD:-15}"   # Min score difference for failback
FAILOVER_COOLDOWN="${FAILOVER_COOLDOWN_SECONDS:-300}"  # Cooldown between failovers (5 min)
STABILITY_CHECKS="${FAILOVER_STABILITY_CHECKS:-3}"     # Number of consecutive checks required

# === STATE VARIABLES ===
current_primary=""
last_failover_time=0
consecutive_stability_checks=0
failover_pending=false

# === STATE PERSISTENCE ===
load_failover_state() {
    if [ -f "$FAILOVER_STATE_FILE" ]; then
        . "$FAILOVER_STATE_FILE"
        log_debug "Loaded failover state: primary=$current_primary, last_failover=$last_failover_time"
    fi
    
    # Load current primary interface
    if [ -f "$CURRENT_PRIMARY_FILE" ]; then
        current_primary=$(cat "$CURRENT_PRIMARY_FILE")
        log_debug "Current primary interface: $current_primary"
    else
        # Default to wan if no primary set
        current_primary="${DEFAULT_PRIMARY_INTERFACE:-wan}"
        save_current_primary "$current_primary"
        log_info "Set default primary interface: $current_primary"
    fi
}

save_failover_state() {
    cat > "$FAILOVER_STATE_FILE" << EOF
current_primary="$current_primary"
last_failover_time=$last_failover_time
consecutive_stability_checks=$consecutive_stability_checks
failover_pending=$failover_pending
EOF
    log_debug "Saved failover state"
}

save_current_primary() {
    local interface="$1"
    echo "$interface" > "$CURRENT_PRIMARY_FILE"
    current_primary="$interface"
    log_debug "Updated current primary: $interface"
}

log_failover_event() {
    local event_type="$1"
    local from_interface="$2"
    local to_interface="$3"
    local reason="$4"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "$timestamp,$event_type,$from_interface,$to_interface,$reason" >> "$FAILOVER_HISTORY_FILE"
    log_info "FAILOVER EVENT: $event_type from $from_interface to $to_interface - $reason"
}

# === MWAN3 INTERFACE MANAGEMENT ===
get_mwan3_interface_status() {
    local interface="$1"
    
    if command -v mwan3 >/dev/null 2>&1; then
        mwan3 status | grep -E "interface $interface" | head -1 | awk '{print $4}' || echo "unknown"
    else
        log_error "mwan3 command not available"
        echo "unknown"
    fi
}

execute_mwan3_failover() {
    local from_interface="$1"
    local to_interface="$2"
    local reason="$3"
    
    log_info "Executing failover: $from_interface -> $to_interface"
    log_info "Reason: $reason"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY_RUN] Would execute:"
        log_info "[DRY_RUN]   mwan3 ifdown $from_interface"
        log_info "[DRY_RUN]   mwan3 ifup $to_interface"
        return 0
    fi
    
    # Execute actual failover
    if command -v mwan3 >/dev/null 2>&1; then
        log_step "Disabling interface: $from_interface"
        if mwan3 ifdown "$from_interface"; then
            log_success "Interface $from_interface disabled"
        else
            log_error "Failed to disable interface $from_interface"
            return 1
        fi
        
        log_step "Enabling interface: $to_interface"
        if mwan3 ifup "$to_interface"; then
            log_success "Interface $to_interface enabled"
        else
            log_error "Failed to enable interface $to_interface"
            # Try to re-enable original interface
            log_warning "Attempting to restore original interface: $from_interface"
            mwan3 ifup "$from_interface" || log_error "Failed to restore $from_interface"
            return 1
        fi
        
        # Update state
        save_current_primary "$to_interface"
        last_failover_time=$(date +%s)
        consecutive_stability_checks=0
        
        # Log the event
        log_failover_event "FAILOVER" "$from_interface" "$to_interface" "$reason"
        
        save_failover_state
        log_success "Failover completed successfully"
        return 0
    else
        log_error "mwan3 command not available - cannot execute failover"
        return 1
    fi
}

# === COOLDOWN MANAGEMENT ===
check_failover_cooldown() {
    local current_time=$(date +%s)
    local time_since_last=$((current_time - last_failover_time))
    
    if [ "$time_since_last" -lt "$FAILOVER_COOLDOWN" ]; then
        local remaining=$((FAILOVER_COOLDOWN - time_since_last))
        log_debug "Failover cooldown active: ${remaining}s remaining"
        return 1
    else
        log_debug "Failover cooldown expired: ${time_since_last}s since last failover"
        return 0
    fi
}

# === SCORE-BASED DECISION LOGIC ===
make_failover_decision() {
    log_step "Analyzing connection scores for failover decision"
    
    # Get connection scoring recommendations
    local scoring_script="$SCRIPTS_DIR/connection-scoring-system-rutos.sh"
    if [ ! -f "$scoring_script" ]; then
        log_error "Connection scoring script not found: $scoring_script"
        return 1
    fi
    
    # Get recommended best connection
    local recommended_interface
    if ! recommended_interface=$("$scoring_script" best "$current_primary" 2>/dev/null); then
        log_error "Failed to get connection scoring recommendation"
        return 1
    fi
    
    log_info "Current primary: $current_primary"
    log_info "Scoring recommendation: $recommended_interface"
    
    # Check if recommendation is different from current primary
    if [ "$recommended_interface" = "$current_primary" ]; then
        log_info "Score-based analysis recommends staying with current primary"
        consecutive_stability_checks=$((consecutive_stability_checks + 1))
        
        # Reset any pending failover
        if [ "$failover_pending" = "true" ]; then
            log_info "Canceling pending failover - current connection is now optimal"
            failover_pending=false
        fi
        
        save_failover_state
        return 0
    fi
    
    # Different interface recommended - check if we should failover
    log_info "Score-based analysis recommends failover to: $recommended_interface"
    
    # Check cooldown period
    if ! check_failover_cooldown; then
        log_info "Failover blocked by cooldown period"
        return 0
    fi
    
    # Check interface availability
    local target_status=$(get_mwan3_interface_status "$recommended_interface")
    if [ "$target_status" != "online" ] && [ "$target_status" != "tracking" ]; then
        log_warning "Recommended interface $recommended_interface is not available (status: $target_status)"
        return 0
    fi
    
    # Check stability requirements
    if [ "$failover_pending" = "true" ]; then
        consecutive_stability_checks=$((consecutive_stability_checks + 1))
        log_info "Failover pending - stability check $consecutive_stability_checks/$STABILITY_CHECKS"
        
        if [ "$consecutive_stability_checks" -ge "$STABILITY_CHECKS" ]; then
            # Execute the failover
            local reason="Connection scoring recommends $recommended_interface (${consecutive_stability_checks} consecutive checks)"
            
            if execute_mwan3_failover "$current_primary" "$recommended_interface" "$reason"; then
                failover_pending=false
                consecutive_stability_checks=0
                save_failover_state
                return 0
            else
                log_error "Failover execution failed"
                failover_pending=false
                save_failover_state
                return 1
            fi
        else
            save_failover_state
            return 0
        fi
    else
        # Start stability monitoring for potential failover
        log_info "Starting stability monitoring for potential failover to: $recommended_interface"
        failover_pending=true
        consecutive_stability_checks=1
        save_failover_state
        return 0
    fi
}

# === HEALTH MONITORING ===
check_system_health() {
    log_debug "Checking system health for failover manager"
    
    # Check if monitoring is active
    local monitoring_script="$SCRIPTS_DIR/starlink_monitor_unified-v3-rutos.sh"
    if [ ! -f "$monitoring_script" ]; then
        log_warning "Monitoring script not found - scores may be stale"
    fi
    
    # Check if connection scoring is working
    local scoring_script="$SCRIPTS_DIR/connection-scoring-system-rutos.sh"
    if [ ! -f "$scoring_script" ]; then
        log_error "Connection scoring script not found"
        return 1
    fi
    
    # Test scoring system
    if ! "$scoring_script" status >/dev/null 2>&1; then
        log_warning "Connection scoring system appears to have issues"
    fi
    
    return 0
}

# === MAIN MONITORING LOOP ===
run_monitoring_loop() {
    log_info "Starting intelligent failover monitoring loop"
    log_info "Check interval: ${CHECK_INTERVAL}s"
    log_info "Failover threshold: $FAILOVER_THRESHOLD points"
    log_info "Stability checks required: $STABILITY_CHECKS"
    
    while true; do
        log_debug "=== Failover Check Cycle ==="
        
        # Load current state
        load_failover_state
        
        # Check system health
        if ! check_system_health; then
            log_error "System health check failed - skipping this cycle"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Make failover decision based on connection scores
        make_failover_decision
        
        # Wait for next check
        log_debug "Sleeping for ${CHECK_INTERVAL}s until next check"
        sleep "$CHECK_INTERVAL"
    done
}

# === STATUS REPORTING ===
show_failover_status() {
    load_failover_state
    
    echo "=== Intelligent Failover Manager Status ==="
    echo "Current Primary Interface: $current_primary"
    echo "Failover Pending: $failover_pending"
    echo "Consecutive Stability Checks: $consecutive_stability_checks/$STABILITY_CHECKS"
    
    if [ "$last_failover_time" -gt 0 ]; then
        local time_since=$(($(date +%s) - last_failover_time))
        echo "Last Failover: $(date -d "@$last_failover_time" 2>/dev/null || echo "unknown") (${time_since}s ago)"
    else
        echo "Last Failover: Never"
    fi
    
    echo ""
    echo "=== Recent Failover History ==="
    if [ -f "$FAILOVER_HISTORY_FILE" ]; then
        echo "Timestamp,Event,From,To,Reason"
        tail -10 "$FAILOVER_HISTORY_FILE" 2>/dev/null || echo "No recent events"
    else
        echo "No failover history available"
    fi
    
    echo ""
    echo "=== Current Connection Scores ==="
    local scoring_script="$SCRIPTS_DIR/connection-scoring-system-rutos.sh"
    if [ -f "$scoring_script" ]; then
        "$scoring_script" status
    else
        echo "Connection scoring system not available"
    fi
}

# === MANUAL FAILOVER ===
execute_manual_failover() {
    local target_interface="$1"
    local reason="Manual failover requested"
    
    if [ -z "$target_interface" ]; then
        log_error "Target interface not specified for manual failover"
        return 1
    fi
    
    load_failover_state
    
    # Check if target is different from current
    if [ "$target_interface" = "$current_primary" ]; then
        log_info "Target interface $target_interface is already the primary"
        return 0
    fi
    
    # Check target interface availability
    local target_status=$(get_mwan3_interface_status "$target_interface")
    if [ "$target_status" != "online" ] && [ "$target_status" != "tracking" ]; then
        log_error "Target interface $target_interface is not available (status: $target_status)"
        return 1
    fi
    
    # Execute manual failover (bypass cooldown and stability checks)
    log_info "Executing manual failover to: $target_interface"
    
    if execute_mwan3_failover "$current_primary" "$target_interface" "$reason"; then
        # Reset stability monitoring
        failover_pending=false
        consecutive_stability_checks=0
        save_failover_state
        log_success "Manual failover completed"
        return 0
    else
        log_error "Manual failover failed"
        return 1
    fi
}

# === MAIN SCRIPT LOGIC ===
main() {
    local action="${1:-monitor}"
    local interface="$2"
    
    case "$action" in
        "monitor"|"run")
            # Start monitoring loop
            run_monitoring_loop
            ;;
        "check")
            # Single failover check
            load_failover_state
            check_system_health && make_failover_decision
            ;;
        "status")
            # Show current status
            show_failover_status
            ;;
        "failover")
            # Manual failover to specified interface
            if [ -z "$interface" ]; then
                log_error "Interface not specified for manual failover"
                echo "Usage: $0 failover <interface>"
                exit 1
            fi
            execute_manual_failover "$interface"
            ;;
        "set-primary")
            # Set primary interface without failover
            if [ -z "$interface" ]; then
                log_error "Interface not specified"
                echo "Usage: $0 set-primary <interface>"
                exit 1
            fi
            save_current_primary "$interface"
            log_info "Primary interface set to: $interface"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action] [interface]"
            echo ""
            echo "Actions:"
            echo "  monitor           - Start continuous monitoring loop (default)"
            echo "  check             - Perform single failover check"
            echo "  status            - Show current failover status and history"
            echo "  failover <iface>  - Manual failover to specified interface"
            echo "  set-primary <iface> - Set primary interface without failover"
            echo "  help              - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 monitor         - Start monitoring loop"
            echo "  $0 check           - Single check"
            echo "  $0 status          - Show status"
            echo "  $0 failover mob1s1a1 - Manual failover to cellular"
            echo ""
            echo "Environment Variables:"
            echo "  DRY_RUN=1         - Enable dry-run mode (no actual changes)"
            echo "  DEBUG=1           - Enable debug logging"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
