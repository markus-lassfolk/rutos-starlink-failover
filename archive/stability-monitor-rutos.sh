#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "stability-monitor-rutos.sh" "$SCRIPT_VERSION"

# === PREDICTIVE MULTI-WAN STABILITY & ROUTING ENGINE ===
# Main controller implementing the architecture from scoring.md
# Orchestrates collectors, scoring, and MWAN3 decision making

readonly SCRIPT_NAME="stability-monitor-rutos.sh"

# Load common functions
. "$(dirname "$0")/lib/common_functions.sh"

# === CONFIGURATION ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"
DATA_DIR="${DATA_DIR:-/usr/local/starlink/data}"
COLLECTORS_DIR="$(dirname "$0")/collectors"
SCORING_DIR="$(dirname "$0")/scoring"

# File paths
METRICS_FILE="$DATA_DIR/latest_metrics.json"
HISTORY_FILE="$DATA_DIR/history_log.csv"
STATE_FILE="$DATA_DIR/monitor_state.dat"
LAST_RUN_FILE="$DATA_DIR/last_collector_runs.dat"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === INTERFACE CONFIGURATION ===
# Define interfaces to monitor with their types and polling intervals
INTERFACES="
wan:starlink:2
mob1s1a1:cellular:60
mob1s2a1:cellular:60
wg_klara:vpn:30
"

# === MONITORING STATE ===
monitor_running=0
total_cycles=0
last_score_calculation=0

# === STATE PERSISTENCE ===
load_monitor_state() {
    if [ -f "$STATE_FILE" ]; then
        . "$STATE_FILE"
        log_debug "Loaded monitor state: running=$monitor_running, cycles=$total_cycles"
    fi
}

save_monitor_state() {
    cat > "$STATE_FILE" << EOF
monitor_running=$monitor_running
total_cycles=$total_cycles
last_score_calculation=$last_score_calculation
EOF
}

load_last_runs() {
    if [ -f "$LAST_RUN_FILE" ]; then
        . "$LAST_RUN_FILE"
        log_debug "Loaded last collector run times"
    fi
}

save_last_run() {
    local interface="$1"
    local timestamp="$2"
    local var_name="LAST_RUN_$(echo "$interface" | sed 's/[^a-zA-Z0-9]/_/g')"
    
    # Update the variable
    eval "$var_name=$timestamp"
    
    # Save to file
    echo "$var_name=$timestamp" >> "$LAST_RUN_FILE.tmp"
    
    # Keep only the variables we're tracking and remove duplicates
    if [ -f "$LAST_RUN_FILE" ]; then
        grep -v "^$var_name=" "$LAST_RUN_FILE" >> "$LAST_RUN_FILE.tmp" 2>/dev/null || true
    fi
    
    mv "$LAST_RUN_FILE.tmp" "$LAST_RUN_FILE"
}

get_last_run() {
    local interface="$1"
    local var_name="LAST_RUN_$(echo "$interface" | sed 's/[^a-zA-Z0-9]/_/g')"
    
    eval "echo \$$var_name"
}

# === COLLECTOR MANAGEMENT ===
should_run_collector() {
    local interface="$1"
    local interval="$2"
    local current_time=$(get_unix_timestamp)
    local last_run=$(get_last_run "$interface")
    
    # Run if never run before
    if [ -z "$last_run" ] || [ "$last_run" = "0" ]; then
        log_debug "Collector for $interface should run: never run before"
        return 0
    fi
    
    # Check if enough time has passed
    local elapsed=$((current_time - last_run))
    if [ "$elapsed" -ge "$interval" ]; then
        log_debug "Collector for $interface should run: ${elapsed}s >= ${interval}s"
        return 0
    else
        log_trace "Collector for $interface should wait: ${elapsed}s < ${interval}s"
        return 1
    fi
}

run_collector() {
    local interface="$1"
    local connection_type="$2"
    local collector_script="$COLLECTORS_DIR/collect_${connection_type}-rutos.sh"
    
    log_debug "Running collector for $interface ($connection_type)"
    
    # Check if collector script exists
    if [ ! -f "$collector_script" ]; then
        log_error "Collector script not found: $collector_script"
        return 1
    fi
    
    # Check if interface exists
    if ! check_interface_exists "$interface"; then
        log_warning "Interface $interface does not exist or is down, skipping collection"
        return 1
    fi
    
    # Run collector and capture JSON output
    local json_output
    if json_output=$("$collector_script" "$interface" 2>/dev/null); then
        log_debug "Collector for $interface succeeded"
        log_trace "Collector output: $json_output"
        
        # Update last run time
        save_last_run "$interface" "$(get_unix_timestamp)"
        
        # Update metrics file
        update_metrics_file "$interface" "$json_output"
        
        # Append to history
        append_to_history "$json_output"
        
        return 0
    else
        log_error "Collector for $interface failed"
        return 1
    fi
}

# === METRICS FILE MANAGEMENT ===
initialize_metrics_file() {
    if [ ! -f "$METRICS_FILE" ]; then
        echo "{}" > "$METRICS_FILE"
        log_info "Initialized empty metrics file"
    fi
}

update_metrics_file() {
    local interface="$1"
    local json_data="$2"
    
    log_debug "Updating metrics file for $interface"
    
    # Read current metrics
    local current_metrics
    if ! current_metrics=$(cat "$METRICS_FILE" 2>/dev/null); then
        current_metrics="{}"
    fi
    
    # Create temporary file for updated metrics
    local temp_file="$METRICS_FILE.tmp"
    
    # Simple JSON merge (without external dependencies)
    # Extract the metrics portion from the collector output
    local timestamp=$(echo "$json_data" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)
    local type=$(echo "$json_data" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
    local metrics=$(echo "$json_data" | grep -o '"metrics":{[^}]*}' | cut -d':' -f2-)
    
    # Build the interface entry
    local interface_entry=$(json_object \
        "$(json_field "timestamp" "$timestamp" 1)" \
        "$(json_field "type" "$type")" \
        "\"metrics\": $metrics" \
    )
    
    # Update the metrics file
    {
        echo "{"
        
        # Add existing interfaces (excluding the one we're updating)
        local first=1
        echo "$current_metrics" | grep -o '"[^"]*":{[^}]*}' | while IFS=: read -r iface_part entry_part; do
            local existing_interface=$(echo "$iface_part" | sed 's/"//g')
            
            if [ "$existing_interface" != "$interface" ]; then
                if [ "$first" = "0" ]; then
                    echo ","
                fi
                echo "  \"$existing_interface\": $entry_part"
                first=0
            fi
        done > "$temp_file.interfaces"
        
        # Add the updated interface entry
        if [ -s "$temp_file.interfaces" ]; then
            cat "$temp_file.interfaces"
            echo ","
        fi
        echo "  \"$interface\": $interface_entry"
        
        echo "}"
        
        # Clean up
        rm -f "$temp_file.interfaces"
    } > "$temp_file"
    
    # Replace original file
    if mv "$temp_file" "$METRICS_FILE"; then
        log_trace "Metrics file updated for $interface"
        return 0
    else
        log_error "Failed to update metrics file for $interface"
        return 1
    fi
}

append_to_history() {
    local json_data="$1"
    
    # Create CSV header if file doesn't exist
    if [ ! -f "$HISTORY_FILE" ]; then
        echo "timestamp,interface,type,ping_latency,ping_loss,jitter,specific_metric1,specific_metric2,specific_metric3" > "$HISTORY_FILE"
    fi
    
    # Extract data and append to CSV
    local timestamp=$(echo "$json_data" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)
    local interface=$(echo "$json_data" | grep -o '"iface":"[^"]*"' | cut -d'"' -f4)
    local type=$(echo "$json_data" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
    local metrics=$(echo "$json_data" | grep -o '"metrics":{[^}]*}' | cut -d':' -f2-)
    
    # Extract common metrics
    local ping_latency=$(echo "$metrics" | grep -o '"ping_latency_ms":[^,}]*' | cut -d':' -f2)
    local ping_loss=$(echo "$metrics" | grep -o '"ping_loss_percent":[^,}]*' | cut -d':' -f2)
    local jitter=$(echo "$metrics" | grep -o '"jitter_ms":[^,}]*' | cut -d':' -f2)
    
    # Set defaults
    ping_latency="${ping_latency:-0}"
    ping_loss="${ping_loss:-100}"
    jitter="${jitter:-0}"
    
    # Append to history (simplified format)
    echo "$timestamp,$interface,$type,$ping_latency,$ping_loss,$jitter,,,," >> "$HISTORY_FILE"
    
    # Keep history file reasonable size (last 10000 lines)
    tail -10000 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# === SCORING INTEGRATION ===
should_calculate_scores() {
    local current_time=$(get_unix_timestamp)
    local score_interval="${SCORE_CALCULATION_INTERVAL:-60}"
    local elapsed=$((current_time - last_score_calculation))
    
    if [ "$last_score_calculation" = "0" ] || [ "$elapsed" -ge "$score_interval" ]; then
        return 0
    else
        return 1
    fi
}

calculate_stability_scores() {
    log_step "Calculating stability scores for all interfaces"
    
    local scoring_script="$SCORING_DIR/calculate_score-rutos.sh"
    
    if [ ! -f "$scoring_script" ]; then
        log_error "Scoring script not found: $scoring_script"
        return 1
    fi
    
    if "$scoring_script" calculate; then
        last_score_calculation=$(get_unix_timestamp)
        log_success "Stability scores calculated successfully"
        return 0
    else
        log_error "Failed to calculate stability scores"
        return 1
    fi
}

# === MWAN3 INTEGRATION ===
analyze_scores_for_decisions() {
    log_debug "Analyzing stability scores for routing decisions"
    
    if [ ! -f "$METRICS_FILE" ]; then
        log_warning "No metrics file available for analysis"
        return 1
    fi
    
    # Extract current scores
    local best_interface=""
    local best_score=0
    local current_primary=""
    
    # Read scores from metrics file
    local interfaces_with_scores=$(grep -o '"[^"]*":{"timestamp":[^}]*"stability_score":[0-9.]*' "$METRICS_FILE" 2>/dev/null)
    
    echo "$interfaces_with_scores" | while read -r score_line; do
        local interface=$(echo "$score_line" | cut -d'"' -f2)
        local score=$(echo "$score_line" | grep -o '"stability_score":[0-9.]*' | cut -d':' -f2)
        
        log_info "Interface $interface: stability score = $score/100"
        
        # Track best scoring interface
        if awk "BEGIN {exit ($score > $best_score) ? 0 : 1}"; then
            best_interface="$interface"
            best_score="$score"
        fi
    done
    
    if [ -n "$best_interface" ]; then
        log_info "Best performing interface: $best_interface (score: $best_score/100)"
        
        # TODO: Integrate with MWAN3 priority adjustments
        # This would call the intelligent failover manager we created earlier
    else
        log_warning "No interfaces with valid scores found"
    fi
}

# === MAIN MONITORING LOOP ===
monitoring_cycle() {
    local cycle_start=$(get_unix_timestamp)
    total_cycles=$((total_cycles + 1))
    
    log_debug "=== Monitoring Cycle $total_cycles ==="
    
    # Load last run times
    load_last_runs
    
    local collectors_run=0
    
    # Process each configured interface
    echo "$INTERFACES" | while read -r interface_config; do
        # Skip empty lines
        [ -z "$interface_config" ] && continue
        
        # Parse interface configuration (format: interface:type:interval)
        local interface=$(echo "$interface_config" | cut -d':' -f1)
        local connection_type=$(echo "$interface_config" | cut -d':' -f2)
        local interval=$(echo "$interface_config" | cut -d':' -f3)
        
        # Skip if interface not properly configured
        if [ -z "$interface" ] || [ -z "$connection_type" ] || [ -z "$interval" ]; then
            log_debug "Skipping malformed interface config: $interface_config"
            continue
        fi
        
        log_trace "Checking interface: $interface ($connection_type, ${interval}s interval)"
        
        # Check if collector should run
        if should_run_collector "$interface" "$interval"; then
            log_info "Running collector for $interface ($connection_type)"
            
            if run_collector "$interface" "$connection_type"; then
                collectors_run=$((collectors_run + 1))
                log_success "Collector for $interface completed successfully"
            else
                log_warning "Collector for $interface failed"
            fi
        fi
    done
    
    # Calculate scores if needed and collectors were run
    if [ "$collectors_run" -gt 0 ] && should_calculate_scores; then
        calculate_stability_scores
        analyze_scores_for_decisions
    fi
    
    # Update state
    save_monitor_state
    
    local cycle_duration=$(($(get_unix_timestamp) - cycle_start))
    log_debug "Monitoring cycle $total_cycles completed in ${cycle_duration}s (collectors run: $collectors_run)"
}

run_monitoring_loop() {
    log_info "Starting Predictive Multi-WAN Stability & Routing Engine"
    log_info "Monitoring interfaces: $(echo "$INTERFACES" | grep -v '^$' | wc -l)"
    log_info "Data directory: $DATA_DIR"
    
    # Initialize
    ensure_directory "$DATA_DIR"
    initialize_metrics_file
    
    monitor_running=1
    save_monitor_state
    
    # Set up signal handlers
    trap 'monitor_running=0; log_info "Received shutdown signal"; save_monitor_state' INT TERM
    
    # Main monitoring loop
    while [ "$monitor_running" = "1" ]; do
        monitoring_cycle
        
        # Sleep for main loop interval (adjust based on shortest collector interval)
        log_trace "Sleeping for 10 seconds until next monitoring cycle"
        sleep 10
    done
    
    log_info "Monitoring loop stopped after $total_cycles cycles"
}

# === STATUS AND CONTROL ===
show_monitor_status() {
    load_monitor_state
    load_last_runs
    
    echo "=== Predictive Multi-WAN Stability Monitor Status ==="
    echo "Monitor Running: $monitor_running"
    echo "Total Cycles: $total_cycles"
    echo "Data Directory: $DATA_DIR"
    
    if [ "$last_score_calculation" -gt 0 ]; then
        local score_age=$(($(get_unix_timestamp) - last_score_calculation))
        echo "Last Score Calculation: $(date -d "@$last_score_calculation" 2>/dev/null || echo "unknown") (${score_age}s ago)"
    else
        echo "Last Score Calculation: Never"
    fi
    
    echo ""
    echo "=== Interface Status ==="
    printf "%-15s %-10s %-8s %-20s %-10s\n" "Interface" "Type" "Interval" "Last Collection" "Score"
    printf "%-15s %-10s %-8s %-20s %-10s\n" "---------" "----" "--------" "---------------" "-----"
    
    echo "$INTERFACES" | while read -r interface_config; do
        [ -z "$interface_config" ] && continue
        
        local interface=$(echo "$interface_config" | cut -d':' -f1)
        local connection_type=$(echo "$interface_config" | cut -d':' -f2) 
        local interval=$(echo "$interface_config" | cut -d':' -f3)
        local last_run=$(get_last_run "$interface")
        
        local last_run_str="Never"
        if [ -n "$last_run" ] && [ "$last_run" != "0" ]; then
            local age=$(($(get_unix_timestamp) - last_run))
            last_run_str="${age}s ago"
        fi
        
        local score="N/A"
        if [ -f "$METRICS_FILE" ]; then
            score=$(grep -o "\"$interface\":{[^}]*\"stability_score\":[0-9.]*" "$METRICS_FILE" 2>/dev/null | \
                   grep -o '"stability_score":[0-9.]*' | cut -d':' -f2 || echo "N/A")
        fi
        
        printf "%-15s %-10s %-8s %-20s %-10s\n" "$interface" "$connection_type" "${interval}s" "$last_run_str" "$score"
    done
    
    echo ""
    if [ -f "$METRICS_FILE" ]; then
        echo "=== Latest Metrics File ==="
        echo "File: $METRICS_FILE"
        echo "Size: $(wc -c < "$METRICS_FILE") bytes"
        echo "Last Modified: $(date -r "$METRICS_FILE" 2>/dev/null || echo "unknown")"
    fi
}

stop_monitor() {
    if [ -f "$STATE_FILE" ]; then
        load_monitor_state
        if [ "$monitor_running" = "1" ]; then
            log_info "Stopping monitor"
            monitor_running=0
            save_monitor_state
            log_success "Monitor stopped"
        else
            log_info "Monitor is not running"
        fi
    else
        log_info "No monitor state file found"
    fi
}

# === MAIN SCRIPT LOGIC ===
main() {
    local action="${1:-run}"
    
    case "$action" in
        "run"|"start"|"monitor")
            run_monitoring_loop
            ;;
        "status"|"info")
            show_monitor_status
            ;;
        "stop")
            stop_monitor
            ;;
        "cycle"|"once")
            # Run single monitoring cycle
            ensure_directory "$DATA_DIR"
            initialize_metrics_file
            monitoring_cycle
            ;;
        "test")
            # Test collectors individually
            local interface="${2:-wan}"
            local connection_type="${3:-starlink}"
            log_info "Testing collector for $interface ($connection_type)"
            run_collector "$interface" "$connection_type"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action]"
            echo ""
            echo "Actions:"
            echo "  run/start     - Start continuous monitoring loop (default)"
            echo "  status        - Show current monitor status"
            echo "  stop          - Stop running monitor"
            echo "  cycle         - Run single monitoring cycle"
            echo "  test <iface> <type> - Test specific collector"
            echo "  help          - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 run                      - Start monitoring"
            echo "  $0 status                   - Check status"  
            echo "  $0 test wan starlink        - Test Starlink collector"
            echo ""
            echo "Environment Variables:"
            echo "  DRY_RUN=1     - Enable dry-run mode"
            echo "  DEBUG=1       - Enable debug logging"
            echo "  RUTOS_TEST_MODE=1 - Enable trace logging"
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
