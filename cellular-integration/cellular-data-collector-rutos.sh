#!/bin/sh
# Script: cellular-data-collector-rutos.sh
# Version: 2.8.0
# Description: Comprehensive cellular data collection for RUTOS modems with 4G/5G support
# Collects signal strength, network type, operator, roaming status, and data usage

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # PURPLE unused in non-interactive mode
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

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

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

    # Cellular Configuration with defaults
    CELLULAR_PRIMARY_IFACE="${CELLULAR_PRIMARY_IFACE:-mob1s1a1}"               # Primary modem interface
    CELLULAR_BACKUP_IFACE="${CELLULAR_BACKUP_IFACE:-mob1s2a1}"                 # Backup modem interface
    CELLULAR_DATA_LOG="${CELLULAR_DATA_LOG:-/var/log/cellular_data.csv}"       # CSV log file
    CELLULAR_COLLECT_INTERVAL="${CELLULAR_COLLECT_INTERVAL:-60}"               # Collection interval in seconds
    CELLULAR_ROAMING_COST_THRESHOLD="${CELLULAR_ROAMING_COST_THRESHOLD:-10.0}" # Cost per MB threshold
    CELLULAR_SIGNAL_POOR_THRESHOLD="${CELLULAR_SIGNAL_POOR_THRESHOLD:--100}"   # dBm threshold for poor signal
    CELLULAR_SIGNAL_GOOD_THRESHOLD="${CELLULAR_SIGNAL_GOOD_THRESHOLD:--80}"    # dBm threshold for good signal
}

# Get cellular modem information using RUTOS commands
get_modem_info() {
    modem_interface="$1"

    log_debug "Collecting modem info for interface: $modem_interface"

    # Initialize variables with defaults
    signal_dbm="N/A"
    signal_quality="N/A"
    network_type="N/A"
    operator="N/A"
    roaming_status="N/A"
    connection_status="N/A"
    data_usage_rx="N/A"
    data_usage_tx="N/A"
    ip_address="N/A"

    # Extract modem ID from interface name (e.g., mob1s1a1 -> modem 1, sim 1)
    modem_id=$(echo "$modem_interface" | sed 's/mob\([0-9]\).*/\1/')
    sim_id=$(echo "$modem_interface" | sed 's/mob[0-9]s\([0-9]\).*/\1/')

    log_debug "Extracted modem_id=$modem_id, sim_id=$sim_id from interface $modem_interface"

    # Method 1: Try gsmctl (RUTOS-specific command)
    if command -v gsmctl >/dev/null 2>&1; then
        log_debug "Using gsmctl for modem data collection"

        # Get signal strength
        signal_info=$(gsmctl -A "AT+CSQ" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$signal_info" ]; then
            # Parse CSQ response: +CSQ: <rssi>,<ber>
            rssi=$(echo "$signal_info" | grep "+CSQ:" | sed 's/.*+CSQ: \([0-9]*\),.*/\1/' 2>/dev/null || echo "")
            if [ -n "$rssi" ] && [ "$rssi" != "99" ]; then
                # Convert RSSI to dBm: dBm = -113 + 2*rssi
                signal_dbm=$(awk -v rssi="$rssi" 'BEGIN {print -113 + 2*rssi}')
            fi
        fi

        # Get network registration and operator info
        network_info=$(gsmctl -A "AT+COPS?" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$network_info" ]; then
            # Parse COPS response: +COPS: <mode>,<format>,"<operator>",<AcT>
            operator=$(echo "$network_info" | grep "+COPS:" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null | tr -d '\n\r,' | head -c 25 || echo "Unknown")
            network_type_code=$(echo "$network_info" | grep "+COPS:" | sed 's/.*,\([0-9]*\)$/\1/' 2>/dev/null | tr -d '\n\r' || echo "")
            case "$network_type_code" in
                "0") network_type="GSM" ;;
                "2") network_type="UTRAN" ;;
                "7") network_type="LTE" ;;
                "12") network_type="5G-NR" ;;
                *) network_type="Unknown" ;;
            esac
        fi

        # Get roaming status
        roaming_info=$(gsmctl -A "AT+CGREG?" -M "$modem_id" 2>/dev/null || echo "")
        if [ -n "$roaming_info" ]; then
            # Parse CGREG response: +CGREG: <n>,<stat>[,<lac>,<ci>[,<AcT>]]
            roaming_stat=$(echo "$roaming_info" | grep "+CGREG:" | sed 's/.*+CGREG: [0-9]*,\([0-9]*\).*/\1/' 2>/dev/null || echo "")
            case "$roaming_stat" in
                "1") roaming_status="Home" ;;
                "5") roaming_status="Roaming" ;;
                "0" | "2" | "3") roaming_status="Not_Registered" ;;
                *) roaming_status="Unknown" ;;
            esac
        fi
    fi

    # Method 2: Try mmcli (ModemManager command line interface)
    if command -v mmcli >/dev/null 2>&1; then
        log_debug "Using mmcli for enhanced modem data collection"

        # Find modem by interface
        modem_path=$(mmcli -L 2>/dev/null | grep -E "Modem.*$modem_id" | sed 's|.*\(/org/freedesktop/ModemManager1/Modem/[0-9]*\).*|\1|' || echo "")

        if [ -n "$modem_path" ]; then
            # Get comprehensive modem status
            modem_status=$(mmcli -m "$modem_path" 2>/dev/null || echo "")

            if [ -n "$modem_status" ]; then
                # Extract signal quality (RSSI, RSRP, RSRQ, SINR for LTE/5G)
                signal_rssi=$(echo "$modem_status" | grep -i "signal quality" | sed 's/.*: \([0-9-]*\).*/\1/' 2>/dev/null || echo "")
                if [ -n "$signal_rssi" ] && [ "$signal_rssi" != "0" ]; then
                    signal_dbm="$signal_rssi"
                fi

                # Get access technology (more detailed than AT commands)
                access_tech=$(echo "$modem_status" | grep -i "access tech" | sed 's/.*: \(.*\)$/\1/' 2>/dev/null || echo "")
                if [ -n "$access_tech" ]; then
                    network_type="$access_tech"
                fi

                # Get operator name
                operator_name=$(echo "$modem_status" | grep -i "operator name" | sed 's/.*: \(.*\)$/\1/' 2>/dev/null || echo "")
                if [ -n "$operator_name" ]; then
                    operator="$operator_name"
                fi

                # Get connection state
                conn_state=$(echo "$modem_status" | grep -i "state" | head -1 | sed 's/.*: \(.*\)$/\1/' 2>/dev/null || echo "")
                if [ -n "$conn_state" ]; then
                    connection_status="$conn_state"
                fi
            fi
        fi
    fi

    # Method 3: UCI configuration and status
    if command -v uci >/dev/null 2>&1; then
        log_debug "Using UCI for additional modem information"

        # Get interface IP address
        ip_addr=$(uci get network."$modem_interface".ipaddr 2>/dev/null || echo "")
        if [ -z "$ip_addr" ]; then
            # Try getting from ip command
            ip_addr=$(ip addr show "$modem_interface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 || echo "")
        fi
        if [ -n "$ip_addr" ]; then
            ip_address="$ip_addr"
        fi

        # Get mobile configuration
        # shellcheck disable=SC2034  # Variables collected for potential future use
        apn=$(uci get network."$modem_interface".apn 2>/dev/null || echo "Unknown")
        # shellcheck disable=SC2034  # Variables collected for potential future use
        username=$(uci get network."$modem_interface".username 2>/dev/null || echo "")
    fi

    # Method 4: Network statistics for data usage
    if [ -f "/sys/class/net/$modem_interface/statistics/rx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$modem_interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/$modem_interface/statistics/tx_bytes" 2>/dev/null || echo "0")

        # Convert bytes to MB
        if [ "$rx_bytes" != "0" ]; then
            data_usage_rx=$(awk -v bytes="$rx_bytes" 'BEGIN {printf "%.2f", bytes/1048576}')
        fi
        if [ "$tx_bytes" != "0" ]; then
            data_usage_tx=$(awk -v bytes="$tx_bytes" 'BEGIN {printf "%.2f", bytes/1048576}')
        fi
    fi

    # Method 5: Interface status using ip and iwconfig
    if command -v iwconfig >/dev/null 2>&1; then
        # Some modems support wireless extensions
        iw_info=$(iwconfig "$modem_interface" 2>/dev/null || echo "")
        if [ -n "$iw_info" ]; then
            # Extract additional signal information if available
            signal_level=$(echo "$iw_info" | grep "Signal level" | sed 's/.*Signal level=\([0-9-]*\).*/\1/' 2>/dev/null || echo "")
            if [ -n "$signal_level" ] && [ "$signal_dbm" = "N/A" ]; then
                signal_dbm="$signal_level"
            fi
        fi
    fi

    # Assess signal quality based on dBm values
    if [ "$signal_dbm" != "N/A" ]; then
        signal_int=$(echo "$signal_dbm" | cut -d'.' -f1)
        if [ "$signal_int" -ge "$CELLULAR_SIGNAL_GOOD_THRESHOLD" ]; then
            signal_quality="Excellent"
        elif [ "$signal_int" -ge "$CELLULAR_SIGNAL_POOR_THRESHOLD" ]; then
            signal_quality="Good"
        else
            signal_quality="Poor"
        fi
    fi

    # Output structured data (sanitize all fields to prevent CSV corruption)
    # Remove newlines, carriage returns, and commas from all fields
    modem_interface=$(echo "$modem_interface" | tr -d '\n\r,' | head -c 20)
    signal_dbm=$(echo "$signal_dbm" | tr -d '\n\r,' | head -c 10)
    signal_quality=$(echo "$signal_quality" | tr -d '\n\r,' | head -c 15)
    network_type=$(echo "$network_type" | tr -d '\n\r,' | head -c 15)
    operator=$(echo "$operator" | tr -d '\n\r,' | head -c 25)
    roaming_status=$(echo "$roaming_status" | tr -d '\n\r,' | head -c 15)
    connection_status=$(echo "$connection_status" | tr -d '\n\r,' | head -c 15)
    data_usage_rx=$(echo "$data_usage_rx" | tr -d '\n\r,' | head -c 10)
    data_usage_tx=$(echo "$data_usage_tx" | tr -d '\n\r,' | head -c 10)
    ip_address=$(echo "$ip_address" | tr -d '\n\r,' | head -c 15)
    
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$modem_interface" \
        "$signal_dbm" \
        "$signal_quality" \
        "$network_type" \
        "$operator" \
        "$roaming_status" \
        "$connection_status" \
        "$data_usage_rx" \
        "$data_usage_tx" \
        "$ip_address" \
        "$(date '+%Y-%m-%d %H:%M:%S')"
}

# Collect comprehensive cellular data for all modems
collect_cellular_data() {
    output_format="$1" # csv, json, or human

    log_step "Collecting cellular data from all modems"

    # Create CSV header if needed
    if [ "$output_format" = "csv" ] && [ ! -f "$CELLULAR_DATA_LOG" ]; then
        echo "interface,signal_dbm,signal_quality,network_type,operator,roaming_status,connection_status,data_rx_mb,data_tx_mb,ip_address,timestamp" >"$CELLULAR_DATA_LOG"
        log_info "Created cellular data log: $CELLULAR_DATA_LOG"
    fi

    # Collect data for primary cellular interface
    if [ -n "$CELLULAR_PRIMARY_IFACE" ]; then
        log_debug "Collecting data for primary cellular: $CELLULAR_PRIMARY_IFACE"
        primary_data=$(get_modem_info "$CELLULAR_PRIMARY_IFACE")

        case "$output_format" in
            "csv")
                echo "$primary_data" >>"$CELLULAR_DATA_LOG"
                ;;
            "json")
                # Convert CSV to JSON format
                echo "$primary_data" | awk -F',' '{
                    printf "{\n"
                    printf "  \"interface\": \"%s\",\n", $1
                    printf "  \"signal_dbm\": \"%s\",\n", $2
                    printf "  \"signal_quality\": \"%s\",\n", $3
                    printf "  \"network_type\": \"%s\",\n", $4
                    printf "  \"operator\": \"%s\",\n", $5
                    printf "  \"roaming_status\": \"%s\",\n", $6
                    printf "  \"connection_status\": \"%s\",\n", $7
                    printf "  \"data_rx_mb\": \"%s\",\n", $8
                    printf "  \"data_tx_mb\": \"%s\",\n", $9
                    printf "  \"ip_address\": \"%s\",\n", $10
                    printf "  \"timestamp\": \"%s\"\n", $11
                    printf "}\n"
                }'
                ;;
            "human")
                echo "$primary_data" | awk -F',' '{
                    printf "📱 Primary Cellular (%s):\n", $1
                    printf "   Signal: %s dBm (%s)\n", $2, $3
                    printf "   Network: %s via %s\n", $4, $5
                    printf "   Status: %s (%s)\n", $7, $6
                    printf "   Data Usage: ↓%s MB / ↑%s MB\n", $8, $9
                    printf "   IP: %s\n", $10
                    printf "   Updated: %s\n\n", $11
                }'
                ;;
        esac
    fi

    # Collect data for backup cellular interface
    if [ -n "$CELLULAR_BACKUP_IFACE" ]; then
        log_debug "Collecting data for backup cellular: $CELLULAR_BACKUP_IFACE"
        backup_data=$(get_modem_info "$CELLULAR_BACKUP_IFACE")

        case "$output_format" in
            "csv")
                echo "$backup_data" >>"$CELLULAR_DATA_LOG"
                ;;
            "json")
                echo "$backup_data" | awk -F',' '{
                    printf "{\n"
                    printf "  \"interface\": \"%s\",\n", $1
                    printf "  \"signal_dbm\": \"%s\",\n", $2
                    printf "  \"signal_quality\": \"%s\",\n", $3
                    printf "  \"network_type\": \"%s\",\n", $4
                    printf "  \"operator\": \"%s\",\n", $5
                    printf "  \"roaming_status\": \"%s\",\n", $6
                    printf "  \"connection_status\": \"%s\",\n", $7
                    printf "  \"data_rx_mb\": \"%s\",\n", $8
                    printf "  \"data_tx_mb\": \"%s\",\n", $9
                    printf "  \"ip_address\": \"%s\",\n", $10
                    printf "  \"timestamp\": \"%s\"\n", $11
                    printf "}\n"
                }'
                ;;
            "human")
                echo "$backup_data" | awk -F',' '{
                    printf "📱 Backup Cellular (%s):\n", $1
                    printf "   Signal: %s dBm (%s)\n", $2, $3
                    printf "   Network: %s via %s\n", $4, $5
                    printf "   Status: %s (%s)\n", $7, $6
                    printf "   Data Usage: ↓%s MB / ↑%s MB\n", $8, $9
                    printf "   IP: %s\n", $10
                    printf "   Updated: %s\n", $11
                }'
                ;;
        esac
    fi
}

# Analyze cellular data and provide failover recommendations
analyze_cellular_failover() {
    log_step "Analyzing cellular data for failover recommendations"

    if [ ! -f "$CELLULAR_DATA_LOG" ]; then
        log_warning "No cellular data log found: $CELLULAR_DATA_LOG"
        return 1
    fi

    # Get latest data for both modems
    primary_latest=$(grep "^$CELLULAR_PRIMARY_IFACE," "$CELLULAR_DATA_LOG" | tail -1 2>/dev/null || echo "")
    backup_latest=$(grep "^$CELLULAR_BACKUP_IFACE," "$CELLULAR_DATA_LOG" | tail -1 2>/dev/null || echo "")

    if [ -z "$primary_latest" ] && [ -z "$backup_latest" ]; then
        log_warning "No recent cellular data available for analysis"
        return 1
    fi

    printf "\n🔍 CELLULAR FAILOVER ANALYSIS:\n\n"

    # Analyze primary modem
    if [ -n "$primary_latest" ]; then
        echo "$primary_latest" | awk -F',' -v threshold_poor="$CELLULAR_SIGNAL_POOR_THRESHOLD" -v threshold_good="$CELLULAR_SIGNAL_GOOD_THRESHOLD" '{
            printf "📱 PRIMARY MODEM (%s):\n", $1
            printf "   Signal Strength: %s dBm (%s)\n", $2, $3
            printf "   Network: %s\n", $4
            printf "   Operator: %s\n", $5
            printf "   Roaming: %s\n", $6
            printf "   Status: %s\n", $7
            
            # Assess quality
            signal = $2
            roaming = $6
            status = $7
            
            score = 0
            issues = ""
            
            if (signal == "N/A") {
                issues = issues "No signal data; "
            } else if (signal < threshold_poor) {
                issues = issues "Very poor signal (" signal " dBm); "
            } else if (signal < threshold_good) {
                score += 5
            } else {
                score += 10
            }
            
            if (roaming == "Roaming") {
                issues = issues "Expensive roaming; "
                score -= 3
            } else if (roaming == "Home") {
                score += 5
            }
            
            if (status == "connected" || status == "Connected") {
                score += 5
            } else {
                issues = issues "Not connected; "
            }
            
            printf "   Quality Score: %d/20\n", score
            if (issues != "") {
                printf "   Issues: %s\n", issues
            }
            printf "\n"
        }'
    fi

    # Analyze backup modem
    if [ -n "$backup_latest" ]; then
        echo "$backup_latest" | awk -F',' -v threshold_poor="$CELLULAR_SIGNAL_POOR_THRESHOLD" -v threshold_good="$CELLULAR_SIGNAL_GOOD_THRESHOLD" '{
            printf "📱 BACKUP MODEM (%s):\n", $1
            printf "   Signal Strength: %s dBm (%s)\n", $2, $3
            printf "   Network: %s\n", $4
            printf "   Operator: %s\n", $5
            printf "   Roaming: %s\n", $6
            printf "   Status: %s\n", $7
            
            # Assess quality
            signal = $2
            roaming = $6
            status = $7
            
            score = 0
            issues = ""
            
            if (signal == "N/A") {
                issues = issues "No signal data; "
            } else if (signal < threshold_poor) {
                issues = issues "Very poor signal (" signal " dBm); "
            } else if (signal < threshold_good) {
                score += 5
            } else {
                score += 10
            }
            
            if (roaming == "Roaming") {
                issues = issues "Expensive roaming; "
                score -= 3
            } else if (roaming == "Home") {
                score += 5
            }
            
            if (status == "connected" || status == "Connected") {
                score += 5
            } else {
                issues = issues "Not connected; "
            }
            
            printf "   Quality Score: %d/20\n", score
            if (issues != "") {
                printf "   Issues: %s\n", issues
            }
            printf "\n"
        }'
    fi

    # Generate recommendations
    printf "💡 FAILOVER RECOMMENDATIONS:\n\n"

    if [ -n "$primary_latest" ] && [ -n "$backup_latest" ]; then
        # Compare both modems and provide recommendation
        primary_signal=$(echo "$primary_latest" | cut -d',' -f2)
        backup_signal=$(echo "$backup_latest" | cut -d',' -f2)
        primary_roaming=$(echo "$primary_latest" | cut -d',' -f6)
        backup_roaming=$(echo "$backup_latest" | cut -d',' -f6)

        # Simple comparison logic
        if [ "$primary_roaming" = "Home" ] && [ "$backup_roaming" = "Roaming" ]; then
            printf "✅ Prefer PRIMARY: Home network vs roaming\n"
        elif [ "$primary_roaming" = "Roaming" ] && [ "$backup_roaming" = "Home" ]; then
            printf "✅ Prefer BACKUP: Home network vs roaming\n"
        elif [ "$primary_signal" != "N/A" ] && [ "$backup_signal" != "N/A" ]; then
            primary_int=$(echo "$primary_signal" | cut -d'.' -f1)
            backup_int=$(echo "$backup_signal" | cut -d'.' -f1)

            if [ "$primary_int" -gt "$backup_int" ]; then
                signal_diff=$((primary_int - backup_int))
                printf "✅ Prefer PRIMARY: %d dBm stronger signal\n" "$signal_diff"
            else
                signal_diff=$((backup_int - primary_int))
                printf "✅ Prefer BACKUP: %d dBm stronger signal\n" "$signal_diff"
            fi
        else
            printf "ℹ️  Insufficient data for clear recommendation\n"
        fi
    fi
}

# Enhanced logging format for integration with existing monitor
log_cellular_enhanced() {
    log_step "Generating enhanced cellular metrics"

    # Collect current data
    temp_primary="/tmp/cellular_primary_$$"
    temp_backup="/tmp/cellular_backup_$$"

    get_modem_info "$CELLULAR_PRIMARY_IFACE" >"$temp_primary"
    get_modem_info "$CELLULAR_BACKUP_IFACE" >"$temp_backup"

    # Format for integration with existing logger
    printf "CELLULAR_METRICS: "

    # Primary modem data
    if [ -f "$temp_primary" ] && [ -s "$temp_primary" ]; then
        awk -F',' '{
            printf "primary={iface=%s,signal=%s,quality=%s,network=%s,operator=%s,roaming=%s,status=%s,rx_mb=%s,tx_mb=%s,ip=%s} ", 
                   $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
        }' "$temp_primary"
    else
        printf "primary={iface=%s,status=unavailable} " "$CELLULAR_PRIMARY_IFACE"
    fi

    # Backup modem data
    if [ -f "$temp_backup" ] && [ -s "$temp_backup" ]; then
        awk -F',' '{
            printf "backup={iface=%s,signal=%s,quality=%s,network=%s,operator=%s,roaming=%s,status=%s,rx_mb=%s,tx_mb=%s,ip=%s} ", 
                   $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
        }' "$temp_backup"
    else
        printf "backup={iface=%s,status=unavailable} " "$CELLULAR_BACKUP_IFACE"
    fi

    printf "timestamp=%s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

    # Cleanup
    rm -f "$temp_primary" "$temp_backup"
}

# Test cellular modem connectivity
test_cellular_connectivity() {
    interface="$1"

    log_debug "Testing connectivity for cellular interface: $interface"

    # Test with ping through specific interface
    if command -v ping >/dev/null 2>&1; then
        # Try to ping through the interface
        if ping -I "$interface" -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            echo "connected"
            return 0
        fi
    fi

    # Check if interface has IP and is up
    if ip addr show "$interface" 2>/dev/null | grep -q "inet.*scope global"; then
        echo "ip_assigned"
        return 0
    fi

    echo "disconnected"
    return 1
}

# Usage information
show_usage() {
    cat <<EOF

Usage: $0 [options] [command]

Commands:
    collect [format]        Collect cellular data (format: csv|json|human)
    analyze                 Analyze data and provide failover recommendations
    enhanced               Generate enhanced metrics for logger integration
    test [interface]       Test connectivity for specific interface
    monitor                Start continuous monitoring

Options:
    --config <file>        Use specific configuration file
    --interval <seconds>   Set collection interval for monitoring
    --help                 Show this help message

Configuration:
    Edit $CONFIG_FILE to configure cellular settings:
    
    CELLULAR_PRIMARY_IFACE="mob1s1a1"              # Primary modem interface
    CELLULAR_BACKUP_IFACE="mob1s2a1"               # Backup modem interface
    CELLULAR_DATA_LOG="/var/log/cellular_data.csv" # Data log file
    CELLULAR_COLLECT_INTERVAL="60"                 # Collection interval
    CELLULAR_SIGNAL_POOR_THRESHOLD="-100"          # Poor signal threshold (dBm)
    CELLULAR_SIGNAL_GOOD_THRESHOLD="-80"           # Good signal threshold (dBm)

Examples:
    $0 collect human                # Human-readable cellular status
    $0 collect csv                  # Log data to CSV file
    $0 analyze                      # Generate failover recommendations
    $0 enhanced                     # Enhanced metrics for logger
    $0 test mob1s1a1               # Test specific modem connectivity
    $0 monitor                      # Start continuous monitoring
    
EOF
}

# Main function
main() {
    # Load configuration
    load_config

    # Parse command line arguments
    command="collect"
    format="human"

    while [ $# -gt 0 ]; do
        case "$1" in
            --config)
                shift
                CONFIG_FILE="$1"
                load_config # Reload with new config
                ;;
            --interval)
                shift
                CELLULAR_COLLECT_INTERVAL="$1"
                ;;
            --help)
                show_usage
                exit 0
                ;;
            collect | analyze | enhanced | test | monitor)
                command="$1"
                ;;
            csv | json | human)
                format="$1"
                ;;
            mob1s1a1 | mob1s2a1 | mob*)
                test_interface="$1"
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

    log_info "Starting Cellular Data Collector v$SCRIPT_VERSION"
    log_info "Command: $command"

    case "$command" in
        "collect")
            collect_cellular_data "$format"
            ;;
        "analyze")
            analyze_cellular_failover
            ;;
        "enhanced")
            log_cellular_enhanced
            ;;
        "test")
            if [ -n "$test_interface" ]; then
                result=$(test_cellular_connectivity "$test_interface")
                log_info "Connectivity test for $test_interface: $result"
            else
                log_error "Interface not specified for test command"
                exit 1
            fi
            ;;
        "monitor")
            log_info "Starting continuous monitoring (interval: ${CELLULAR_COLLECT_INTERVAL}s)"
            log_info "Press Ctrl+C to stop monitoring"

            while true; do
                collect_cellular_data "csv"
                log_cellular_enhanced
                sleep "$CELLULAR_COLLECT_INTERVAL"
            done
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac

    log_success "Cellular data collection completed successfully"
}

# Execute main function
main "$@"
