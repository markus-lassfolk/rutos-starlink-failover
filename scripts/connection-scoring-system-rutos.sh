#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "connection-scoring-system-rutos.sh" "$SCRIPT_VERSION"

# === CONNECTION SCORING SYSTEM ===
# Calculates numerical scores for each connection based on multiple metrics
# Higher scores indicate better connections for intelligent failover decisions

readonly SCRIPT_NAME="connection-scoring-system-rutos.sh"

# === CONFIGURATION LOADING ===
CONFIG_FILE="${CONFIG_FILE:-/usr/local/starlink/config/config.sh}"
LOG_DIR="${LOG_DIR:-/usr/local/starlink/logs}"
STATE_DIR="${STATE_DIR:-/usr/local/starlink/state}"
METRICS_DIR="$LOG_DIR/metrics"
SCORES_DIR="$STATE_DIR/scores"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$STATE_DIR" "$METRICS_DIR" "$SCORES_DIR" 2>/dev/null || true

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    log_info "Configuration loaded from: $CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# === CONNECTION SCORING WEIGHTS ===
# These weights determine how much each metric contributes to the total score
# Values should add up to 100 for percentage-based scoring

# Performance metrics (40% of total score)
WEIGHT_LATENCY="${SCORE_WEIGHT_LATENCY:-15}"           # Lower latency = higher score
WEIGHT_PACKET_LOSS="${SCORE_WEIGHT_PACKET_LOSS:-15}"  # Lower packet loss = higher score  
WEIGHT_BANDWIDTH="${SCORE_WEIGHT_BANDWIDTH:-10}"      # Higher bandwidth = higher score

# Reliability metrics (35% of total score)
WEIGHT_UPTIME="${SCORE_WEIGHT_UPTIME:-15}"             # Higher uptime = higher score
WEIGHT_STABILITY="${SCORE_WEIGHT_STABILITY:-10}"      # Lower jitter = higher score
WEIGHT_CONNECTION_STATE="${SCORE_WEIGHT_CONNECTION_STATE:-10}" # Connected state bonus

# Connection-specific metrics (25% of total score)
WEIGHT_SIGNAL_STRENGTH="${SCORE_WEIGHT_SIGNAL_STRENGTH:-10}"   # Signal quality for wireless
WEIGHT_DATA_USAGE="${SCORE_WEIGHT_DATA_USAGE:-8}"             # Data cap considerations
WEIGHT_PRIORITY="${SCORE_WEIGHT_PRIORITY:-7}"                 # Manual priority settings

# === SCORING PARAMETERS ===
MAX_SCORE="${MAX_CONNECTION_SCORE:-100}"                      # Maximum possible score
MIN_SCORE="${MIN_CONNECTION_SCORE:-0}"                        # Minimum possible score

# Performance benchmarks for scoring calculations
EXCELLENT_LATENCY="${EXCELLENT_LATENCY_MS:-20}"               # 20ms = excellent latency
POOR_LATENCY="${POOR_LATENCY_MS:-500}"                        # 500ms = poor latency
EXCELLENT_PACKET_LOSS="${EXCELLENT_PACKET_LOSS_PCT:-0}"       # 0% = excellent packet loss
POOR_PACKET_LOSS="${POOR_PACKET_LOSS_PCT:-5}"                 # 5% = poor packet loss

# === SCORING ALGORITHMS ===

# Calculate latency score (0-100, higher is better)
calculate_latency_score() {
    local latency="$1"
    local score=0
    
    if [ -z "$latency" ] || [ "$latency" = "0" ]; then
        echo "0"
        return
    fi
    
    # Linear scoring between excellent and poor latency
    if [ "$latency" -le "$EXCELLENT_LATENCY" ]; then
        score=100
    elif [ "$latency" -ge "$POOR_LATENCY" ]; then
        score=0
    else
        # Linear interpolation: score = 100 - (latency - excellent) / (poor - excellent) * 100
        score=$(awk "BEGIN {
            excellent=$EXCELLENT_LATENCY
            poor=$POOR_LATENCY
            current=$latency
            score = 100 - ((current - excellent) / (poor - excellent)) * 100
            if (score < 0) score = 0
            if (score > 100) score = 100
            printf \"%.0f\", score
        }")
    fi
    
    echo "$score"
}

# Calculate packet loss score (0-100, higher is better)
calculate_packet_loss_score() {
    local packet_loss="$1"
    local score=0
    
    if [ -z "$packet_loss" ] || [ "$packet_loss" = "0" ]; then
        echo "100"
        return
    fi
    
    # Convert percentage to decimal if needed
    if echo "$packet_loss" | grep -q '%'; then
        packet_loss=$(echo "$packet_loss" | sed 's/%//')
    fi
    
    # Linear scoring between excellent and poor packet loss
    if [ "$packet_loss" = "0" ]; then
        score=100
    elif awk "BEGIN {exit ($packet_loss >= $POOR_PACKET_LOSS) ? 0 : 1}"; then
        score=0
    else
        # Linear interpolation: score = 100 - (packet_loss / poor) * 100
        score=$(awk "BEGIN {
            poor=$POOR_PACKET_LOSS
            current=$packet_loss
            score = 100 - (current / poor) * 100
            if (score < 0) score = 0
            if (score > 100) score = 100
            printf \"%.0f\", score
        }")
    fi
    
    echo "$score"
}

# Calculate signal strength score for wireless connections
calculate_signal_score() {
    local interface="$1"
    local signal_strength="$2"
    local connection_type="$3"
    
    case "$connection_type" in
        cellular_*)
            # Cellular signal strength (percentage)
            if [ -n "$signal_strength" ] && [ "$signal_strength" != "0" ]; then
                echo "$signal_strength"
            else
                echo "0"
            fi
            ;;
        wifi_*)
            # WiFi signal strength (dBm to percentage)
            if [ -n "$signal_strength" ] && [ "$signal_strength" != "0" ]; then
                # Convert dBm to percentage (rough approximation)
                awk "BEGIN {
                    dbm = $signal_strength
                    if (dbm >= -30) score = 100
                    else if (dbm <= -90) score = 0
                    else score = 100 + (dbm + 30) * (100/60)
                    if (score < 0) score = 0
                    if (score > 100) score = 100
                    printf \"%.0f\", score
                }"
            else
                echo "0"
            fi
            ;;
        wireguard|vpn_*)
            # VPN connections - use uptime as proxy for signal quality
            echo "50"  # Neutral score for VPN
            ;;
        *)
            # Wired connections get full signal score
            echo "100"
            ;;
    esac
}

# Calculate uptime score based on connection history
calculate_uptime_score() {
    local interface="$1"
    local current_state="$2"
    
    # Base score from current state
    case "$current_state" in
        "connected"|"online")
            local base_score=100
            ;;
        "limited"|"degraded")
            local base_score=60
            ;;
        "connecting"|"unknown")
            local base_score=30
            ;;
        *)
            local base_score=0
            ;;
    esac
    
    # TODO: Enhance with historical uptime data
    # For now, return base score
    echo "$base_score"
}

# Calculate bandwidth score
calculate_bandwidth_score() {
    local interface="$1"
    local rx_bytes="$2"
    local tx_bytes="$3"
    local time_window="60"  # 60-second window
    
    # Calculate rough bandwidth in MB/s
    if [ -n "$rx_bytes" ] && [ "$rx_bytes" != "0" ]; then
        local bandwidth_mbps=$(awk "BEGIN {
            bytes = $rx_bytes
            mbps = (bytes * 8) / (1024 * 1024 * $time_window)
            printf \"%.2f\", mbps
        }")
        
        # Score based on bandwidth tiers
        if awk "BEGIN {exit ($bandwidth_mbps >= 100) ? 0 : 1}"; then
            echo "100"  # 100+ Mbps = excellent
        elif awk "BEGIN {exit ($bandwidth_mbps >= 25) ? 0 : 1}"; then
            echo "80"   # 25+ Mbps = good
        elif awk "BEGIN {exit ($bandwidth_mbps >= 10) ? 0 : 1}"; then
            echo "60"   # 10+ Mbps = fair
        elif awk "BEGIN {exit ($bandwidth_mbps >= 1) ? 0 : 1}"; then
            echo "40"   # 1+ Mbps = poor
        else
            echo "20"   # <1 Mbps = very poor
        fi
    else
        echo "0"
    fi
}

# Calculate data usage penalty for limited connections
calculate_data_usage_score() {
    local interface="$1"
    local connection_type="$2"
    local data_limit="$3"
    
    case "$connection_type" in
        cellular_*|satellite_*)
            # Apply data usage penalty for limited connections
            # TODO: Track actual data usage vs limits
            # For now, return reduced score for limited connections
            echo "70"
            ;;
        *)
            # Unlimited connections get full score
            echo "100"
            ;;
    esac
}

# Get connection priority from configuration
get_connection_priority() {
    local interface="$1"
    
    # Check for interface-specific priority in config
    case "$interface" in
        wan*)
            echo "${PRIORITY_WAN:-90}"
            ;;
        mob*)
            echo "${PRIORITY_CELLULAR:-70}"
            ;;
        wg_*)
            echo "${PRIORITY_VPN:-60}"
            ;;
        wifi*)
            echo "${PRIORITY_WIFI:-80}"
            ;;
        *)
            echo "${PRIORITY_DEFAULT:-50}"
            ;;
    esac
}

# === MAIN SCORING FUNCTION ===
calculate_connection_score() {
    local interface="$1"
    local latency="$2"
    local packet_loss="$3"
    local signal_strength="$4"
    local connection_state="$5"
    local connection_type="$6"
    local rx_bytes="$7"
    local tx_bytes="$8"
    
    log_debug "Calculating score for $interface: latency=$latency, loss=$packet_loss, signal=$signal_strength, state=$connection_state"
    
    # Calculate individual component scores
    local latency_score=$(calculate_latency_score "$latency")
    local packet_loss_score=$(calculate_packet_loss_score "$packet_loss")
    local signal_score=$(calculate_signal_score "$interface" "$signal_strength" "$connection_type")
    local uptime_score=$(calculate_uptime_score "$interface" "$connection_state")
    local bandwidth_score=$(calculate_bandwidth_score "$interface" "$rx_bytes" "$tx_bytes")
    local data_usage_score=$(calculate_data_usage_score "$interface" "$connection_type" "")
    local priority_score=$(get_connection_priority "$interface")
    
    log_trace "Score components for $interface:"
    log_trace "  Latency: $latency_score (weight: $WEIGHT_LATENCY)"
    log_trace "  Packet Loss: $packet_loss_score (weight: $WEIGHT_PACKET_LOSS)"
    log_trace "  Signal: $signal_score (weight: $WEIGHT_SIGNAL_STRENGTH)"
    log_trace "  Uptime: $uptime_score (weight: $WEIGHT_UPTIME)"
    log_trace "  Bandwidth: $bandwidth_score (weight: $WEIGHT_BANDWIDTH)"
    log_trace "  Data Usage: $data_usage_score (weight: $WEIGHT_DATA_USAGE)"
    log_trace "  Priority: $priority_score (weight: $WEIGHT_PRIORITY)"
    
    # Calculate weighted total score
    local total_score=$(awk "BEGIN {
        score = 0
        score += ($latency_score * $WEIGHT_LATENCY / 100)
        score += ($packet_loss_score * $WEIGHT_PACKET_LOSS / 100)
        score += ($signal_score * $WEIGHT_SIGNAL_STRENGTH / 100)
        score += ($uptime_score * $WEIGHT_UPTIME / 100)
        score += ($bandwidth_score * $WEIGHT_BANDWIDTH / 100)
        score += ($data_usage_score * $WEIGHT_DATA_USAGE / 100)
        score += ($priority_score * $WEIGHT_PRIORITY / 100)
        
        # Normalize to max score
        final_score = (score / 100) * $MAX_SCORE
        if (final_score < $MIN_SCORE) final_score = $MIN_SCORE
        if (final_score > $MAX_SCORE) final_score = $MAX_SCORE
        printf \"%.1f\", final_score
    }")
    
    log_debug "Total score for $interface: $total_score/$MAX_SCORE"
    echo "$total_score"
}

# === SCORE PERSISTENCE ===
save_connection_score() {
    local interface="$1"
    local score="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local score_file="$SCORES_DIR/${interface}_scores.csv"
    
    # Create header if file doesn't exist
    if [ ! -f "$score_file" ]; then
        echo "timestamp,interface,score" > "$score_file"
    fi
    
    # Append score with timestamp
    echo "$timestamp,$interface,$score" >> "$score_file"
    
    # Keep only last 1000 entries per interface
    tail -1000 "$score_file" > "$score_file.tmp" && mv "$score_file.tmp" "$score_file"
}

load_latest_scores() {
    local scores_summary="$SCORES_DIR/latest_scores.csv"
    echo "interface,score,timestamp" > "$scores_summary"
    
    for score_file in "$SCORES_DIR"/*_scores.csv; do
        if [ -f "$score_file" ]; then
            local interface=$(basename "$score_file" | sed 's/_scores\.csv$//')
            local latest_line=$(tail -1 "$score_file" 2>/dev/null)
            if [ -n "$latest_line" ] && [ "$latest_line" != "timestamp,interface,score" ]; then
                local timestamp=$(echo "$latest_line" | cut -d',' -f1)
                local score=$(echo "$latest_line" | cut -d',' -f3)
                echo "$interface,$score,$timestamp" >> "$scores_summary"
            fi
        fi
    done
    
    echo "$scores_summary"
}

# === METRICS INTEGRATION ===
process_metrics_for_scoring() {
    local metrics_file="$1"
    
    if [ ! -f "$metrics_file" ]; then
        log_error "Metrics file not found: $metrics_file"
        return 1
    fi
    
    log_info "Processing metrics for connection scoring: $metrics_file"
    
    # Process each line in metrics file (skip header)
    tail -n +2 "$metrics_file" | while IFS=',' read -r timestamp interface state latency packet_loss jitter \
        signal_strength signal_quality rx_bytes tx_bytes rx_packets environment connection_type data_limit; do
        
        # Skip empty lines
        [ -z "$interface" ] && continue
        
        # Calculate score for this connection
        local score=$(calculate_connection_score "$interface" "$latency" "$packet_loss" \
            "$signal_strength" "$state" "$connection_type" "$rx_bytes" "$tx_bytes")
        
        # Save score
        save_connection_score "$interface" "$score"
        
        log_info "Connection $interface score: $score/$MAX_SCORE (state: $state, latency: ${latency}ms, loss: ${packet_loss}%)"
    done
}

# === FAILOVER DECISION LOGIC ===
get_best_connection() {
    local current_primary="$1"
    local scores_file="$(load_latest_scores)"
    local best_interface=""
    local best_score=0
    local current_score=0
    
    log_info "Evaluating connections for failover decision"
    
    # Read scores and find the best connection
    while IFS=',' read -r interface score timestamp; do
        # Skip header
        [ "$interface" = "interface" ] && continue
        
        log_debug "Evaluating $interface: score=$score"
        
        # Track current primary score
        if [ "$interface" = "$current_primary" ]; then
            current_score="$score"
        fi
        
        # Find highest scoring available connection
        if awk "BEGIN {exit ($score > $best_score) ? 0 : 1}"; then
            best_interface="$interface"
            best_score="$score"
        fi
    done < "$scores_file"
    
    # Decision logic with hysteresis
    local score_difference=$(awk "BEGIN {printf \"%.1f\", $best_score - $current_score}")
    local failover_threshold="${SCORE_FAILOVER_THRESHOLD:-10}"
    
    log_info "Current primary: $current_primary (score: $current_score)"
    log_info "Best alternative: $best_interface (score: $best_score)"
    log_info "Score difference: $score_difference (threshold: $failover_threshold)"
    
    if [ "$best_interface" != "$current_primary" ] && \
       awk "BEGIN {exit ($score_difference >= $failover_threshold) ? 0 : 1}"; then
        log_info "RECOMMENDATION: Failover to $best_interface (score improvement: $score_difference)"
        echo "$best_interface"
    else
        log_info "RECOMMENDATION: Stay with $current_primary"
        echo "$current_primary"
    fi
    
    # Clean up temp file
    rm -f "$scores_file"
}

# === MAIN SCRIPT LOGIC ===
main() {
    local action="${1:-score}"
    local interface="$2"
    
    case "$action" in
        "score")
            if [ -n "$interface" ]; then
                # Score specific interface (for testing)
                log_info "Scoring interface: $interface"
                # TODO: Get current metrics for interface
                echo "Feature not yet implemented for single interface"
            else
                # Score all interfaces from latest metrics
                local today=$(date '+%Y%m%d')
                local metrics_file="$METRICS_DIR/metrics_$today.csv"
                process_metrics_for_scoring "$metrics_file"
            fi
            ;;
        "best")
            # Find best connection for failover
            local current_primary="${interface:-wan}"
            get_best_connection "$current_primary"
            ;;
        "status")
            # Show current scores for all connections
            local scores_file="$(load_latest_scores)"
            log_info "Current connection scores:"
            printf "%-15s %-8s %-20s\n" "Interface" "Score" "Last Updated"
            printf "%-15s %-8s %-20s\n" "---------" "-----" "------------"
            while IFS=',' read -r interface score timestamp; do
                [ "$interface" = "interface" ] && continue
                printf "%-15s %-8s %-20s\n" "$interface" "$score" "$timestamp"
            done < "$scores_file"
            rm -f "$scores_file"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action] [interface]"
            echo ""
            echo "Actions:"
            echo "  score [interface]  - Calculate scores for all interfaces (or specific interface)"
            echo "  best [primary]     - Find best connection for failover (default primary: wan)"
            echo "  status            - Show current scores for all connections"
            echo "  help              - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 score           - Score all interfaces from today's metrics"
            echo "  $0 best wan        - Find best alternative to 'wan' interface"
            echo "  $0 status          - Show current connection scores"
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
