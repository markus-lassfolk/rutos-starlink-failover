#!/bin/sh
# === RUTOS COMMON FUNCTIONS LIBRARY ===
# Provides normalization and utility functions for the stability scoring system
# Used by collectors and scoring engine

# === METRIC NORMALIZATION FUNCTION ===
# Normalizes any metric to 0.0-1.0 scale where 1.0 = best, 0.0 = worst
# Args: value, best_threshold, worst_threshold, invert_flag
normalize_metric() {
    local value="$1"
    local best="$2" 
    local worst="$3"
    local invert="${4:-0}"  # 0 = higher is better, 1 = lower is better
    
    # Handle empty or invalid values
    if [ -z "$value" ] || [ "$value" = "0" ] || [ "$value" = "unknown" ]; then
        echo "0.0"
        return
    fi
    
    # Handle division by zero
    if [ "$best" = "$worst" ]; then
        echo "0.5"
        return
    fi
    
    local normalized
    if [ "$invert" = "1" ]; then
        # For metrics where lower is better (latency, packet loss, jitter)
        # normalized = 1 - ((value - best) / (worst - best))
        normalized=$(awk "BEGIN {
            val = $value
            best = $best
            worst = $worst
            if (val <= best) {
                print 1.0
            } else if (val >= worst) {
                print 0.0  
            } else {
                norm = 1.0 - ((val - best) / (worst - best))
                if (norm < 0) norm = 0.0
                if (norm > 1) norm = 1.0
                printf \"%.3f\", norm
            }
        }")
    else
        # For metrics where higher is better (SNR, signal strength, bandwidth)
        # normalized = (value - worst) / (best - worst)
        normalized=$(awk "BEGIN {
            val = $value
            best = $best  
            worst = $worst
            if (val >= best) {
                print 1.0
            } else if (val <= worst) {
                print 0.0
            } else {
                norm = (val - worst) / (best - worst)
                if (norm < 0) norm = 0.0
                if (norm > 1) norm = 1.0
                printf \"%.3f\", norm
            }
        }")
    fi
    
    echo "$normalized"
}

# === ENHANCED LOGGING FUNCTION ===
# Central logging with levels and timestamps
# Args: level, message
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "ERROR")
            printf "${RED}[ERROR]${NC} [%s] %s\n" "$timestamp" "$message" >&2
            ;;
        "WARN"|"WARNING")
            printf "${YELLOW}[WARN]${NC} [%s] %s\n" "$timestamp" "$message"
            ;;
        "INFO")
            printf "${GREEN}[INFO]${NC} [%s] %s\n" "$timestamp" "$message"
            ;;
        "DEBUG")
            if [ "${DEBUG:-0}" = "1" ]; then
                printf "${BLUE}[DEBUG]${NC} [%s] %s\n" "$timestamp" "$message"
            fi
            ;;
        "TRACE")
            if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
                printf "${CYAN}[TRACE]${NC} [%s] %s\n" "$timestamp" "$message"
            fi
            ;;
        *)
            printf "[%s] [%s] %s\n" "$level" "$timestamp" "$message"
            ;;
    esac
}

# === JSON UTILITY FUNCTIONS ===
# Simple JSON creation without external dependencies

# Create JSON field: "key": "value"
json_field() {
    local key="$1"
    local value="$2"
    local is_number="${3:-0}"
    
    if [ "$is_number" = "1" ]; then
        printf '"%s": %s' "$key" "$value"
    else
        printf '"%s": "%s"' "$key" "$value"
    fi
}

# Create JSON object from key-value pairs
json_object() {
    local first=1
    printf "{"
    
    while [ $# -gt 0 ]; do
        if [ "$first" = "0" ]; then
            printf ", "
        fi
        printf "%s" "$1"
        first=0
        shift
    done
    
    printf "}"
}

# === KILL SWITCH LOGIC ===
# Implements kill switch for critical metrics (e.g., high packet loss)
# Args: metric_name, value, threshold
check_kill_switch() {
    local metric="$1"
    local value="$2" 
    local threshold="$3"
    
    case "$metric" in
        "ping_loss"|"packet_loss")
            # Packet loss over threshold kills the connection score
            if awk "BEGIN {exit ($value > $threshold) ? 0 : 1}"; then
                log_message "WARN" "Kill switch activated for $metric: $value > $threshold"
                return 0  # Kill switch triggered
            fi
            ;;
        "latency"|"ping_latency")
            # Extreme latency kills connection score
            if awk "BEGIN {exit ($value > $threshold) ? 0 : 1}"; then
                log_message "WARN" "Kill switch activated for $metric: $value > $threshold"
                return 0  # Kill switch triggered
            fi
            ;;
    esac
    
    return 1  # No kill switch
}

# === METRIC VALIDATION ===
# Validates that metric values are reasonable
validate_metric() {
    local metric="$1"
    local value="$2"
    
    # Check for empty/null values
    if [ -z "$value" ] || [ "$value" = "null" ] || [ "$value" = "unknown" ]; then
        return 1
    fi
    
    # Check for reasonable ranges based on metric type
    case "$metric" in
        "ping_loss"|"packet_loss")
            # Packet loss should be 0-100%
            if ! awk "BEGIN {exit ($value >= 0 && $value <= 100) ? 0 : 1}"; then
                log_message "DEBUG" "Invalid $metric value: $value (expected 0-100%)"
                return 1
            fi
            ;;
        "latency"|"ping_latency"|"jitter")
            # Latency/jitter should be positive and under 10 seconds
            if ! awk "BEGIN {exit ($value >= 0 && $value <= 10000) ? 0 : 1}"; then
                log_message "DEBUG" "Invalid $metric value: $value (expected 0-10000ms)" 
                return 1
            fi
            ;;
        "rsrp"|"rsrq"|"rssi")
            # Cellular signal values should be negative dBm
            if ! awk "BEGIN {exit ($value >= -150 && $value <= 0) ? 0 : 1}"; then
                log_message "DEBUG" "Invalid $metric value: $value (expected -150 to 0 dBm)"
                return 1
            fi
            ;;
        "snr"|"sinr")
            # SNR values typically -10 to 30 dB
            if ! awk "BEGIN {exit ($value >= -10 && $value <= 50) ? 0 : 1}"; then
                log_message "DEBUG" "Invalid $metric value: $value (expected -10 to 50 dB)"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# === TIMESTAMP UTILITIES ===
get_unix_timestamp() {
    date +%s
}

get_iso_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# === FILE UTILITIES ===
ensure_directory() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" 2>/dev/null || {
            log_message "ERROR" "Failed to create directory: $dir_path"
            return 1
        }
    fi
    return 0
}

# === INTERFACE UTILITIES ===
# Get interface type from name pattern
get_interface_type() {
    local interface="$1"
    
    case "$interface" in
        wan*)
            echo "wan"
            ;;
        mob*|wwan*|cellular*)
            echo "cellular"
            ;;
        wg_*|tun*|tap*)
            echo "vpn"
            ;;
        wifi*|wlan*)
            echo "wifi"
            ;;
        eth*)
            echo "ethernet"
            ;;
        br-*)
            echo "bridge"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if interface exists and is up
check_interface_exists() {
    local interface="$1"
    
    if [ -d "/sys/class/net/$interface" ]; then
        local state=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null)
        case "$state" in
            "up"|"unknown")
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    else
        return 1
    fi
}

# === CONFIGURATION HELPERS ===
# Get polling interval for interface type
get_polling_interval() {
    local interface_type="$1"
    
    case "$interface_type" in
        "starlink"|"wan")
            echo "${STARLINK_POLL_INTERVAL:-2}"
            ;;
        "cellular")
            echo "${CELLULAR_POLL_INTERVAL:-60}"
            ;;
        "wifi")
            echo "${WIFI_POLL_INTERVAL:-15}"
            ;;
        "ethernet"|"bridge")
            echo "${ETHERNET_POLL_INTERVAL:-5}"
            ;;
        "vpn")
            echo "${VPN_POLL_INTERVAL:-30}"
            ;;
        *)
            echo "${DEFAULT_POLL_INTERVAL:-30}"
            ;;
    esac
}

# === ERROR HANDLING ===
# Safe command execution with error handling
safe_command() {
    local description="$1"
    shift
    local command="$*"
    
    log_message "TRACE" "Executing: $description"
    log_message "TRACE" "Command: $command"
    
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_message "INFO" "[DRY_RUN] Would execute: $command"
        return 0
    fi
    
    local output
    local exit_code
    
    output=$(eval "$command" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_message "TRACE" "Command succeeded: $description"
        if [ -n "$output" ]; then
            echo "$output"
        fi
        return 0
    else
        log_message "ERROR" "Command failed: $description (exit code: $exit_code)"
        if [ -n "$output" ]; then
            log_message "ERROR" "Command output: $output"
        fi
        return $exit_code
    fi
}

# === SYSTEM UTILITIES ===
# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system uptime in seconds
get_system_uptime() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0"
}

# Get load average
get_load_average() {
    awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0"
}

# === EXPORT FUNCTIONS ===
# Make functions available to scripts that source this library
export -f normalize_metric
export -f log_message
export -f json_field
export -f json_object
export -f check_kill_switch
export -f validate_metric
export -f get_unix_timestamp
export -f get_iso_timestamp
export -f ensure_directory
export -f get_interface_type
export -f check_interface_exists
export -f get_polling_interval
export -f safe_command
export -f command_exists
export -f get_system_uptime
export -f get_load_average
