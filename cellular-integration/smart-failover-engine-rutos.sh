#!/bin/sh
# Script: smart-failover-engine-rutos.sh
# Version: 2.7.0
# Description: Intelligent failover decision engine for Starlink + multiple cellular modems
# Makes smart decisions based on signal strength, roaming costs, network type, and location patterns

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='\033[0;35m'
# shellcheck disable=SC2034  # Used in debug logging functions
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors (RUTOS Method 5 format)
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Configuration file path
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-monitor/config.sh}"

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_debug "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        log_debug "Configuration loaded successfully"
    else
        log_warning "Configuration file not found: $CONFIG_FILE"
        log_info "Using fallback defaults"
    fi

    # Smart Failover Configuration with defaults
    STARLINK_PRIORITY_SCORE="${STARLINK_PRIORITY_SCORE:-100}"    # Base priority for Starlink
    CELLULAR_PRIMARY_PRIORITY="${CELLULAR_PRIMARY_PRIORITY:-80}" # Primary cellular priority
    CELLULAR_BACKUP_PRIORITY="${CELLULAR_BACKUP_PRIORITY:-60}"   # Backup cellular priority

    # Signal quality thresholds
    STARLINK_SNR_GOOD="${STARLINK_SNR_GOOD:-8.0}"                 # Good Starlink SNR (dB)
    STARLINK_SNR_POOR="${STARLINK_SNR_POOR:-3.0}"                 # Poor Starlink SNR (dB)
    CELLULAR_SIGNAL_EXCELLENT="${CELLULAR_SIGNAL_EXCELLENT:--70}" # Excellent cellular signal (dBm)
    CELLULAR_SIGNAL_GOOD="${CELLULAR_SIGNAL_GOOD:--85}"           # Good cellular signal (dBm)
    CELLULAR_SIGNAL_POOR="${CELLULAR_SIGNAL_POOR:--105}"          # Poor cellular signal (dBm)

    # Cost and roaming settings
    ROAMING_COST_PENALTY="${ROAMING_COST_PENALTY:-50}" # Score penalty for roaming
    NETWORK_5G_BONUS="${NETWORK_5G_BONUS:-20}"         # Score bonus for 5G
    NETWORK_LTE_BONUS="${NETWORK_LTE_BONUS:-10}"       # Score bonus for LTE

    # Failover decision thresholds
    FAILOVER_SCORE_THRESHOLD="${FAILOVER_SCORE_THRESHOLD:-30}"  # Minimum score difference for failover
    FAILOVER_HYSTERESIS_TIME="${FAILOVER_HYSTERESIS_TIME:-300}" # Seconds to wait before switching back

    # Interface names
    STARLINK_INTERFACE="${STARLINK_INTERFACE:-wlan0}"
    CELLULAR_PRIMARY_IFACE="${CELLULAR_PRIMARY_IFACE:-mob1s1a1}"
    CELLULAR_BACKUP_IFACE="${CELLULAR_BACKUP_IFACE:-mob1s2a1}"
}

# Collect current Starlink status
get_starlink_status() {
    log_debug "Collecting Starlink status"

    # Initialize defaults
    starlink_status="Disconnected"
    snr_db="0"
    obstruction_percent="1.0"
    ping_ms="999"
    download_mbps="0"
    upload_mbps="0"

    # Try to get Starlink status via grpcurl
    if command -v grpcurl >/dev/null 2>&1; then
        starlink_data=$(timeout 10 grpcurl -plaintext -d '{"getStatus":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle 2>/dev/null || echo "")

        if [ -n "$starlink_data" ]; then
            # Parse Starlink data
            if echo "$starlink_data" | grep -q '"state":"CONNECTED"'; then
                starlink_status="Connected"
            fi

            # Extract SNR
            snr_value=$(echo "$starlink_data" | sed -n 's/.*"snr":\([0-9.-]*\).*/\1/p' 2>/dev/null || echo "0")
            if [ -n "$snr_value" ] && [ "$snr_value" != "null" ]; then
                snr_db="$snr_value"
            fi

            # Extract obstruction percentage
            obstruction_value=$(echo "$starlink_data" | sed -n 's/.*"fractionObstructed":\([0-9.]*\).*/\1/p' 2>/dev/null || echo "0")
            if [ -n "$obstruction_value" ]; then
                obstruction_percent="$obstruction_value"
            fi
        fi
    fi

    # Test connectivity with ping
    if ping -I "$STARLINK_INTERFACE" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        ping_result=$(ping -I "$STARLINK_INTERFACE" -c 3 -W 5 8.8.8.8 2>/dev/null | tail -1)
        if [ -n "$ping_result" ]; then
            ping_ms=$(echo "$ping_result" | sed -n 's/.*= \([0-9.]*\)\/.*/\1/p' 2>/dev/null || echo "999")
        fi
    fi

    # Simple speed test (optional - can be disabled for efficiency)
    if [ "${ENABLE_SPEED_TEST:-0}" = "1" ]; then
        # Simplified speed test using curl
        download_test=$(timeout 10 curl -s -w "%{speed_download}" -o /dev/null http://speedtest.telstra.com/1mb.txt 2>/dev/null || echo "0")
        if [ -n "$download_test" ] && [ "$download_test" != "0" ]; then
            download_mbps=$(echo "$download_test" | awk '{printf "%.1f", $1/125000}') # Convert bytes/sec to Mbps
        fi
    fi

    printf "%s,%s,%s,%s,%s,%s\n" "$starlink_status" "$snr_db" "$obstruction_percent" "$ping_ms" "$download_mbps" "$upload_mbps"
}

# Collect cellular modem status
get_cellular_status() {
    modem_interface="$1"

    log_debug "Collecting cellular status for: $modem_interface"

    # Initialize defaults
    signal_dbm="-999"
    signal_quality="Poor"
    network_type="Unknown"
    operator="Unknown"
    roaming_status="Unknown"
    connection_status="Disconnected"
    ping_ms="999"

    # Extract modem ID from interface name
    modem_id=$(echo "$modem_interface" | sed 's/mob\([0-9]\).*/\1/')

    # Get cellular data using gsmctl
    if command -v gsmctl >/dev/null 2>&1; then
        # Get signal strength
        signal_info=$(gsmctl -A "AT+CSQ" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$signal_info" ]; then
            rssi=$(echo "$signal_info" | grep "+CSQ:" | sed 's/.*+CSQ: \([0-9]*\),.*/\1/' 2>/dev/null || echo "")
            if [ -n "$rssi" ] && [ "$rssi" != "99" ]; then
                signal_dbm=$(awk -v rssi="$rssi" 'BEGIN {print -113 + 2*rssi}')

                # Determine signal quality
                signal_int=$(echo "$signal_dbm" | cut -d'.' -f1)
                if [ "$signal_int" -ge "$CELLULAR_SIGNAL_EXCELLENT" ]; then
                    signal_quality="Excellent"
                elif [ "$signal_int" -ge "$CELLULAR_SIGNAL_GOOD" ]; then
                    signal_quality="Good"
                elif [ "$signal_int" -ge "$CELLULAR_SIGNAL_POOR" ]; then
                    signal_quality="Fair"
                else
                    signal_quality="Poor"
                fi
            fi
        fi

        # Get operator and network type
        network_info=$(gsmctl -A "AT+COPS?" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$network_info" ]; then
            operator=$(echo "$network_info" | grep "+COPS:" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "Unknown")
            network_code=$(echo "$network_info" | grep "+COPS:" | sed 's/.*,\([0-9]*\)$/\1/' 2>/dev/null || echo "")
            case "$network_code" in
                "0") network_type="GSM" ;;
                "2") network_type="3G" ;;
                "7") network_type="LTE" ;;
                "12") network_type="5G" ;;
                *) network_type="Unknown" ;;
            esac
        fi

        # Get roaming status
        roaming_info=$(gsmctl -A "AT+CGREG?" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$roaming_info" ]; then
            roaming_stat=$(echo "$roaming_info" | grep "+CGREG:" | sed 's/.*+CGREG: [0-9]*,\([0-9]*\).*/\1/' 2>/dev/null || echo "")
            case "$roaming_stat" in
                "1") roaming_status="Home" ;;
                "5") roaming_status="Roaming" ;;
                *) roaming_status="Unknown" ;;
            esac
        fi
    fi

    # Test connectivity
    if ping -I "$modem_interface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        connection_status="Connected"
        ping_result=$(ping -I "$modem_interface" -c 3 -W 5 8.8.8.8 2>/dev/null | tail -1)
        if [ -n "$ping_result" ]; then
            ping_ms=$(echo "$ping_result" | sed -n 's/.*= \([0-9.]*\)\/.*/\1/p' 2>/dev/null || echo "999")
        fi
    fi

    printf "%s,%s,%s,%s,%s,%s,%s\n" "$signal_dbm" "$signal_quality" "$network_type" "$operator" "$roaming_status" "$connection_status" "$ping_ms"
}

# Calculate connection score for smart failover decisions
calculate_connection_score() {
    connection_type="$1"
    connection_data="$2"

    log_debug "Calculating score for $connection_type: $connection_data"

    base_score=0

    case "$connection_type" in
        "starlink")
            # Parse Starlink data: status,snr_db,obstruction_percent,ping_ms,download_mbps,upload_mbps
            status=$(echo "$connection_data" | cut -d',' -f1)
            snr_db=$(echo "$connection_data" | cut -d',' -f2)
            obstruction_percent=$(echo "$connection_data" | cut -d',' -f3)
            ping_ms=$(echo "$connection_data" | cut -d',' -f4)

            base_score="$STARLINK_PRIORITY_SCORE"

            # SNR scoring
            snr_int=$(echo "$snr_db" | cut -d'.' -f1)
            if [ "$snr_int" -ge "$(echo "$STARLINK_SNR_GOOD" | cut -d'.' -f1)" ]; then
                base_score=$((base_score + 30)) # Excellent SNR
            elif [ "$snr_int" -ge "$(echo "$STARLINK_SNR_POOR" | cut -d'.' -f1)" ]; then
                base_score=$((base_score + 10)) # Acceptable SNR
            else
                base_score=$((base_score - 20)) # Poor SNR
            fi

            # Obstruction penalty
            obstruction_int=$(echo "$obstruction_percent * 100" | awk '{printf "%.0f", $1}')
            if [ "$obstruction_int" -gt 5 ]; then
                penalty=$((obstruction_int * 2))
                base_score=$((base_score - penalty))
            fi

            # Connectivity bonus
            if [ "$status" = "Connected" ]; then
                base_score=$((base_score + 20))
            else
                base_score=$((base_score - 50))
            fi

            # Ping penalty
            ping_int=$(echo "$ping_ms" | cut -d'.' -f1)
            if [ "$ping_int" -gt 100 ]; then
                base_score=$((base_score - 10))
            fi
            ;;

        "cellular_primary" | "cellular_backup")
            # Parse cellular data: signal_dbm,signal_quality,network_type,operator,roaming_status,connection_status,ping_ms
            signal_dbm=$(echo "$connection_data" | cut -d',' -f1)
            signal_quality=$(echo "$connection_data" | cut -d',' -f2)
            network_type=$(echo "$connection_data" | cut -d',' -f3)
            operator=$(echo "$connection_data" | cut -d',' -f4)
            roaming_status=$(echo "$connection_data" | cut -d',' -f5)
            connection_status=$(echo "$connection_data" | cut -d',' -f6)
            ping_ms=$(echo "$connection_data" | cut -d',' -f7)

            if [ "$connection_type" = "cellular_primary" ]; then
                base_score="$CELLULAR_PRIMARY_PRIORITY"
            else
                base_score="$CELLULAR_BACKUP_PRIORITY"
            fi

            # Signal strength scoring
            signal_int=$(echo "$signal_dbm" | cut -d'.' -f1)
            if [ "$signal_int" != "-999" ]; then
                if [ "$signal_int" -ge "$CELLULAR_SIGNAL_EXCELLENT" ]; then
                    base_score=$((base_score + 30))
                elif [ "$signal_int" -ge "$CELLULAR_SIGNAL_GOOD" ]; then
                    base_score=$((base_score + 20))
                elif [ "$signal_int" -ge "$CELLULAR_SIGNAL_POOR" ]; then
                    base_score=$((base_score + 5))
                else
                    base_score=$((base_score - 20))
                fi
            else
                base_score=$((base_score - 50)) # No signal data
            fi

            # Network type bonus
            case "$network_type" in
                "5G") base_score=$((base_score + NETWORK_5G_BONUS)) ;;
                "LTE") base_score=$((base_score + NETWORK_LTE_BONUS)) ;;
                "3G") base_score=$((base_score - 10)) ;;
                "GSM") base_score=$((base_score - 20)) ;;
            esac

            # Roaming penalty
            if [ "$roaming_status" = "Roaming" ]; then
                base_score=$((base_score - ROAMING_COST_PENALTY))
            fi

            # Connectivity bonus
            if [ "$connection_status" = "Connected" ]; then
                base_score=$((base_score + 15))
            else
                base_score=$((base_score - 30))
            fi

            # Ping penalty
            ping_int=$(echo "$ping_ms" | cut -d'.' -f1)
            if [ "$ping_int" -gt 150 ]; then
                base_score=$((base_score - 15))
            fi
            ;;
    esac

    # Ensure minimum score of 0
    if [ "$base_score" -lt 0 ]; then
        base_score=0
    fi

    echo "$base_score"
}

# Make smart failover decision
make_failover_decision() {
    log_step "Analyzing all connections for smart failover decision"

    # Collect status for all connections
    starlink_data=$(get_starlink_status)
    cellular_primary_data=$(get_cellular_status "$CELLULAR_PRIMARY_IFACE")
    cellular_backup_data=$(get_cellular_status "$CELLULAR_BACKUP_IFACE")

    log_debug "Starlink data: $starlink_data"
    log_debug "Cellular primary data: $cellular_primary_data"
    log_debug "Cellular backup data: $cellular_backup_data"

    # Calculate scores
    starlink_score=$(calculate_connection_score "starlink" "$starlink_data")
    cellular_primary_score=$(calculate_connection_score "cellular_primary" "$cellular_primary_data")
    cellular_backup_score=$(calculate_connection_score "cellular_backup" "$cellular_backup_data")

    log_debug "Starlink score: $starlink_score"
    log_debug "Cellular primary score: $cellular_primary_score"
    log_debug "Cellular backup score: $cellular_backup_score"

    # Determine current active connection
    current_route=$(ip route | grep "^default" | head -1 || echo "")
    current_interface=$(echo "$current_route" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')

    current_connection="unknown"
    current_score=0

    case "$current_interface" in
        "$STARLINK_INTERFACE" | wlan*)
            current_connection="starlink"
            current_score="$starlink_score"
            ;;
        "$CELLULAR_PRIMARY_IFACE")
            current_connection="cellular_primary"
            current_score="$cellular_primary_score"
            ;;
        "$CELLULAR_BACKUP_IFACE")
            current_connection="cellular_backup"
            current_score="$cellular_backup_score"
            ;;
    esac

    # Find the best connection
    best_connection="starlink"
    best_score="$starlink_score"

    if [ "$cellular_primary_score" -gt "$best_score" ]; then
        best_connection="cellular_primary"
        best_score="$cellular_primary_score"
    fi

    if [ "$cellular_backup_score" -gt "$best_score" ]; then
        best_connection="cellular_backup"
        best_score="$cellular_backup_score"
    fi

    # Display analysis
    printf "\n🔍 SMART FAILOVER ANALYSIS:\n\n"

    printf "📊 CONNECTION SCORES:\n"
    printf "  🛰️  Starlink:         %3d points\n" "$starlink_score"
    printf "  📱 Cellular Primary:  %3d points\n" "$cellular_primary_score"
    printf "  📱 Cellular Backup:   %3d points\n" "$cellular_backup_score"
    printf "\n"

    printf "📍 CURRENT STATUS:\n"
    printf "  Active Connection: %s (Score: %d)\n" "$current_connection" "$current_score"
    printf "  Best Available:   %s (Score: %d)\n" "$best_connection" "$best_score"
    printf "\n"

    # Detailed status for each connection
    printf "🛰️  STARLINK STATUS:\n"
    echo "$starlink_data" | awk -F',' '{
        printf "   Status: %s | SNR: %s dB | Obstruction: %s%% | Ping: %s ms\n", $1, $2, $3*100, $4
    }'

    printf "\n📱 CELLULAR PRIMARY (%s):\n" "$CELLULAR_PRIMARY_IFACE"
    echo "$cellular_primary_data" | awk -F',' '{
        printf "   Signal: %s dBm (%s) | Network: %s | %s | %s | Ping: %s ms\n", $1, $2, $3, $5, $6, $7
    }'

    printf "\n📱 CELLULAR BACKUP (%s):\n" "$CELLULAR_BACKUP_IFACE"
    echo "$cellular_backup_data" | awk -F',' '{
        printf "   Signal: %s dBm (%s) | Network: %s | %s | %s | Ping: %s ms\n", $1, $2, $3, $5, $6, $7
    }'
    printf "\n"

    # Make recommendation
    score_difference=$((best_score - current_score))

    printf "💡 RECOMMENDATION:\n"

    if [ "$current_connection" = "$best_connection" ]; then
        printf "  ✅ Current connection is optimal - no change needed\n"
        printf "  📈 Score advantage: Current connection is the best available\n"
    elif [ "$score_difference" -ge "$FAILOVER_SCORE_THRESHOLD" ]; then
        printf "  🔄 RECOMMEND FAILOVER to %s\n" "$best_connection"
        printf "  📈 Score improvement: +%d points\n" "$score_difference"
        printf "  ⚡ Reason: Significant improvement justifies switch\n"

        # Show the command to execute failover
        case "$best_connection" in
            "starlink")
                printf "  🛠️  Command: ip route replace default via <starlink_gateway> dev %s\n" "$STARLINK_INTERFACE"
                ;;
            "cellular_primary")
                printf "  🛠️  Command: ip route replace default via <cellular_gateway> dev %s\n" "$CELLULAR_PRIMARY_IFACE"
                ;;
            "cellular_backup")
                printf "  🛠️  Command: ip route replace default via <cellular_gateway> dev %s\n" "$CELLULAR_BACKUP_IFACE"
                ;;
        esac
    else
        printf "  ⏸️  Maintain current connection\n"
        printf "  📈 Score difference: +%d points (below threshold of %d)\n" "$score_difference" "$FAILOVER_SCORE_THRESHOLD"
        printf "  🔒 Reason: Improvement not significant enough to justify switch\n"
    fi

    printf "\n"

    # Additional insights
    printf "🎯 SMART INSIGHTS:\n"

    # Roaming analysis
    primary_roaming=$(echo "$cellular_primary_data" | cut -d',' -f5)
    backup_roaming=$(echo "$cellular_backup_data" | cut -d',' -f5)

    if [ "$primary_roaming" = "Roaming" ] || [ "$backup_roaming" = "Roaming" ]; then
        printf "  💰 Cost Alert: Cellular roaming detected - consider Starlink preference\n"
    fi

    # Network type analysis
    primary_network=$(echo "$cellular_primary_data" | cut -d',' -f3)
    backup_network=$(echo "$cellular_backup_data" | cut -d',' -f3)

    if [ "$primary_network" = "5G" ] || [ "$backup_network" = "5G" ]; then
        printf "  🚀 5G Available: High-speed cellular option detected\n"
    fi

    # Signal quality warnings
    primary_signal=$(echo "$cellular_primary_data" | cut -d',' -f1)
    backup_signal=$(echo "$cellular_backup_data" | cut -d',' -f1)
    starlink_snr=$(echo "$starlink_data" | cut -d',' -f2)

    if [ "$(echo "$starlink_snr" | cut -d'.' -f1)" -lt 3 ]; then
        printf "  ⚠️  Starlink SNR Poor: Consider cellular backup\n"
    fi

    if [ "$(echo "$primary_signal" | cut -d'.' -f1)" -lt -100 ] && [ "$(echo "$backup_signal" | cut -d'.' -f1)" -lt -100 ]; then
        printf "  📶 Weak Cellular: Both modems have poor signal strength\n"
    fi

    printf "\n"

    # Return the decision for scripting
    if [ "$current_connection" = "$best_connection" ]; then
        echo "DECISION:MAINTAIN,$current_connection,$current_score"
    elif [ "$score_difference" -ge "$FAILOVER_SCORE_THRESHOLD" ]; then
        echo "DECISION:FAILOVER,$best_connection,$best_score"
    else
        echo "DECISION:MAINTAIN,$current_connection,$current_score"
    fi
}

# Execute automatic failover (dry-run mode by default for safety)
execute_failover() {
    target_connection="$1"
    dry_run="${2:-1}" # Default to dry-run for safety

    log_step "Executing failover to: $target_connection"

    if [ "$dry_run" = "1" ]; then
        log_warning "DRY RUN MODE - No actual changes will be made"
    fi

    case "$target_connection" in
        "starlink")
            target_interface="$STARLINK_INTERFACE"
            log_info "Target: Starlink via $target_interface"
            ;;
        "cellular_primary")
            target_interface="$CELLULAR_PRIMARY_IFACE"
            log_info "Target: Primary Cellular via $target_interface"
            ;;
        "cellular_backup")
            target_interface="$CELLULAR_BACKUP_IFACE"
            log_info "Target: Backup Cellular via $target_interface"
            ;;
        *)
            log_error "Unknown target connection: $target_connection"
            return 1
            ;;
    esac

    # Get current gateway for the target interface
    gateway=$(ip route | grep "$target_interface" | grep -v "default" | head -1 | awk '{print $1}' || echo "")

    if [ -z "$gateway" ]; then
        log_error "Cannot determine gateway for interface: $target_interface"
        return 1
    fi

    # Construct the failover command
    failover_cmd="ip route replace default via $gateway dev $target_interface"

    if [ "$dry_run" = "1" ]; then
        log_info "Would execute: $failover_cmd"
    else
        log_warning "Executing failover command..."
        if eval "$failover_cmd"; then
            log_success "Failover completed successfully"

            # Verify the change
            sleep 2
            new_route=$(ip route | grep "^default" | head -1)
            log_info "New default route: $new_route"
        else
            log_error "Failover command failed"
            return 1
        fi
    fi
}

# Continuous monitoring mode
monitor_and_decide() {
    monitor_interval="${1:-300}" # Default 5 minutes

    log_info "Starting continuous monitoring mode"
    log_info "Monitoring interval: $monitor_interval seconds"
    log_info "Press Ctrl+C to stop monitoring"

    while true; do
        printf "\n"
        log_step "Smart Failover Decision Check - $(date)"

        decision_output=$(make_failover_decision | tail -1)
        decision_action=$(echo "$decision_output" | cut -d',' -f1 | cut -d':' -f2)
        decision_target=$(echo "$decision_output" | cut -d',' -f2)
        decision_score=$(echo "$decision_output" | cut -d',' -f3)

        case "$decision_action" in
            "FAILOVER")
                log_warning "Failover recommended to: $decision_target (Score: $decision_score)"
                if [ "${AUTO_EXECUTE_FAILOVER:-0}" = "1" ]; then
                    execute_failover "$decision_target" 0 # Real execution
                else
                    log_info "Automatic execution disabled - use AUTO_EXECUTE_FAILOVER=1 to enable"
                fi
                ;;
            "MAINTAIN")
                log_info "Current connection optimal: $decision_target (Score: $decision_score)"
                ;;
        esac

        log_info "Sleeping for $monitor_interval seconds..."
        sleep "$monitor_interval"
    done
}

# Usage information
show_usage() {
    cat <<EOF

Usage: $0 [options] [command]

Commands:
    analyze                 Perform smart failover analysis (default)
    execute <target>        Execute failover to target connection
    monitor [interval]      Start continuous monitoring mode
    
Targets for execute command:
    starlink               Failover to Starlink
    cellular_primary       Failover to primary cellular modem
    cellular_backup        Failover to backup cellular modem

Options:
    --config <file>        Use specific configuration file
    --dry-run              Execute in dry-run mode (default for execute)
    --force                Execute real changes (for execute command)
    --help                 Show this help message

Configuration:
    Edit $CONFIG_FILE to configure smart failover:
    
    # Priority scores (higher = preferred)
    STARLINK_PRIORITY_SCORE="100"                    # Base Starlink priority
    CELLULAR_PRIMARY_PRIORITY="80"                   # Primary cellular priority
    CELLULAR_BACKUP_PRIORITY="60"                    # Backup cellular priority
    
    # Signal quality thresholds
    STARLINK_SNR_GOOD="8.0"                          # Good Starlink SNR (dB)
    CELLULAR_SIGNAL_EXCELLENT="-70"                  # Excellent cellular signal (dBm)
    CELLULAR_SIGNAL_GOOD="-85"                       # Good cellular signal (dBm)
    
    # Decision thresholds
    FAILOVER_SCORE_THRESHOLD="30"                    # Min score difference for failover
    ROAMING_COST_PENALTY="50"                        # Score penalty for roaming
    
    # Interface names
    STARLINK_INTERFACE="wlan0"
    CELLULAR_PRIMARY_IFACE="mob1s1a1"
    CELLULAR_BACKUP_IFACE="mob1s2a1"

Examples:
    $0                                               # Analyze and recommend
    $0 analyze                                       # Same as above
    $0 execute cellular_primary --dry-run           # Test failover command
    $0 execute starlink --force                     # Execute real failover
    $0 monitor 300                                   # Monitor every 5 minutes
    AUTO_EXECUTE_FAILOVER=1 $0 monitor              # Auto-execute decisions
    
EOF
}

# Main function
main() {
    # Load configuration
    load_config

    # Parse command line arguments
    command="analyze"
    target_connection=""
    monitor_interval="300"
    dry_run="1"

    while [ $# -gt 0 ]; do
        case "$1" in
            --config)
                shift
                CONFIG_FILE="$1"
                load_config # Reload with new config
                ;;
            --dry-run)
                dry_run="1"
                ;;
            --force)
                dry_run="0"
                ;;
            --help)
                show_usage
                exit 0
                ;;
            analyze | execute | monitor)
                command="$1"
                ;;
            starlink | cellular_primary | cellular_backup)
                target_connection="$1"
                ;;
            [0-9]*)
                monitor_interval="$1"
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                log_warning "Unknown argument: $1"
                ;;
        esac
        shift
    done

    log_info "Starting Smart Failover Engine v$SCRIPT_VERSION"
    log_info "Command: $command"

    case "$command" in
        "analyze")
            make_failover_decision >/dev/null # Suppress the decision line for clean output
            ;;
        "execute")
            if [ -z "$target_connection" ]; then
                log_error "Target connection not specified for execute command"
                show_usage
                exit 1
            fi
            execute_failover "$target_connection" "$dry_run"
            ;;
        "monitor")
            monitor_and_decide "$monitor_interval"
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac

    log_success "Smart failover engine completed successfully"
}

# Execute main function
main "$@"
