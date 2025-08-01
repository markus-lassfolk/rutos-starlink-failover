#!/bin/sh
# Script: post-install-check-rutos.sh
# Version: 2.4.12
# Description: Comprehensive post-installation health check with visual indicators
# Compatible with: RUTOS (busybox sh)

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)

# Standard colors for consistent output (compatible with busybox)
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='[0;35m'
CYAN='[0;36m'
NC='[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
log_info() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2317  # Function provided for consistency - may be unused in some scripts
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[WARNING]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    # shellcheck disable=SC2317  # Function provided for consistency - may be unused in some scripts
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    # shellcheck disable=SC2317  # Function provided for consistency - may be unused in some scripts
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[SUCCESS]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    # shellcheck disable=SC2317  # Function is called later in script
    cmd="$1"
    # shellcheck disable=SC2317  # Function is called later in script
    description="$2"

    # shellcheck disable=SC2317  # Function is called later in script
    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

log_step() {
    # shellcheck disable=SC2317  # Function provided for consistency - may be unused in some scripts
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Configuration paths
INSTALL_DIR="/usr/local/starlink-monitor"
CONFIG_FILE="/etc/starlink-config/config.sh"

# Status tracking counters
status_passed=0
status_failed=0
status_warnings=0
status_config=0
status_info=0

# Visual status check function
check_status() {
    status_type="$1"
    description="$2"
    details="$3"

    case "$status_type" in
        "pass")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${GREEN}✅ HEALTHY${NC}   | %-25s | %s
" "$description" "$details"
            status_passed=$((status_passed + 1))
            ;;
        "fail")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${RED}❌ FAILED${NC}    | %-25s | %s
" "$description" "$details"
            status_failed=$((status_failed + 1))
            ;;
        "config")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}⚙️  CONFIG${NC}   | %-25s | %s
" "$description" "$details"
            status_config=$((status_config + 1))
            ;;
        "warn")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${YELLOW}⚠️  WARN${NC}     | %-25s | %s
" "$description" "$details"
            status_warnings=$((status_warnings + 1))
            ;;
        "info")
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${BLUE}ℹ️  INFO${NC}     | %-25s | %s
" "$description" "$details"
            status_info=$((status_info + 1))
            ;;
    esac
}

# RUTOS_TEST_MODE enables trace logging (does NOT cause early exit)
# Script continues normal execution with enhanced debugging when RUTOS_TEST_MODE=1

# Show header
printf "
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}                  STARLINK POST-INSTALL HEALTH CHECK${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
printf "
"

log_info "Starting comprehensive health check v$SCRIPT_VERSION"

# Load configuration if available
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE" 2>/dev/null || {
        check_status "fail" "Configuration File" "Failed to load $CONFIG_FILE"
        exit 1
    }
    check_status "pass" "Configuration File" "Successfully loaded from $CONFIG_FILE"
    
    # Ensure Starlink connection variables have defaults
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    STARLINK_PORT="${STARLINK_PORT:-9200}"
    
    # Debug: Show loaded Starlink configuration
    log_debug "=== CONFIGURATION LOADED ==="
    log_debug "Configuration file: $CONFIG_FILE"
    log_debug "STARLINK_IP=${STARLINK_IP:-not_set}"
    log_debug "STARLINK_PORT=${STARLINK_PORT:-not_set}"
    log_debug "GRPCURL_CMD=${GRPCURL_CMD:-not_set}"
    log_debug "JQ_CMD=${JQ_CMD:-not_set}"
    log_debug "INSTALL_DIR=${INSTALL_DIR:-not_set}"
    
else
    check_status "fail" "Configuration File" "Missing: $CONFIG_FILE"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "
${RED}❌ Critical Error: Configuration file not found!${NC}
"
    printf "Run the installer first: curl -fL install-url | sh

"
    exit 1
fi

# Function to check if a value is a placeholder
is_placeholder() {
    value="$1"
    case "$value" in
        "YOUR_"* | "REPLACE_"* | "SET_"* | "EDIT_"* | "CHANGEME"* | "PLACEHOLDER"* | "TODO"* | "<"*">"* | "***"* | "XXX"* | "")
            return 0 # Is placeholder
            ;;
        *)
            return 1 # Is real value
            ;;
    esac
}

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}1. CORE SYSTEM COMPONENTS${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check installation directory
if [ -d "$INSTALL_DIR" ]; then
    script_count=$(find "$INSTALL_DIR/scripts" -name "*-rutos.sh" -type f 2>/dev/null | wc -l)
    check_status "pass" "Installation Directory" "$script_count scripts installed in $INSTALL_DIR"
else
    check_status "fail" "Installation Directory" "Missing: $INSTALL_DIR"
fi

# Check required binaries
if [ -f "$INSTALL_DIR/grpcurl" ] && [ -x "$INSTALL_DIR/grpcurl" ]; then
    # Extract grpcurl version properly - it outputs "grpcurl v1.x.x"
    version=$("$INSTALL_DIR/grpcurl" --version 2>/dev/null | head -1 | sed 's/^grpcurl //' || echo "unknown")
    check_status "pass" "gRPC Client (grpcurl)" "Installed: v$version"
else
    check_status "fail" "gRPC Client (grpcurl)" "Missing or not executable"
fi

if [ -f "$INSTALL_DIR/jq" ] && [ -x "$INSTALL_DIR/jq" ]; then
    version=$("$INSTALL_DIR/jq" --version 2>/dev/null || echo "unknown")
    check_status "pass" "JSON Processor (jq)" "Installed: $version"
else
    check_status "fail" "JSON Processor (jq)" "Missing or not executable"
fi

# Check hotplug notification script
if [ -f "/etc/hotplug.d/iface/99-pushover_notify-rutos.sh" ]; then
    check_status "pass" "Hotplug Notification" "Installed and active"
else
    check_status "fail" "Hotplug Notification" "Missing notification script"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}2. CRON SCHEDULING${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check cron entries (only count ACTIVE non-commented entries)
CRON_FILE="/etc/crontabs/root"
if [ -f "$CRON_FILE" ]; then
    # Only count lines that are NOT commented out (don't start with #)
    monitor_entries=$(grep -c "^[^#]*starlink_monitor_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "^[^#]*starlink_logger_unified-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    api_entries=$(grep -c "^[^#]*check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
    maintenance_entries=$(grep -c "^[^#]*system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    autoupdate_entries=$(grep -c "^[^#]*self-update-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    # Clean any whitespace/newlines from the counts (fix for RUTOS busybox grep -c behavior)
    monitor_entries=$(echo "$monitor_entries" | tr -d '
' | sed 's/[^0-9]//g')
    logger_entries=$(echo "$logger_entries" | tr -d '
' | sed 's/[^0-9]//g')
    api_entries=$(echo "$api_entries" | tr -d '
' | sed 's/[^0-9]//g')
    maintenance_entries=$(echo "$maintenance_entries" | tr -d '
' | sed 's/[^0-9]//g')
    autoupdate_entries=$(echo "$autoupdate_entries" | tr -d '
' | sed 's/[^0-9]//g')

    # Ensure we have valid numbers (default to 0 if empty)
    monitor_entries=${monitor_entries:-0}
    logger_entries=${logger_entries:-0}
    api_entries=${api_entries:-0}
    maintenance_entries=${maintenance_entries:-0}
    autoupdate_entries=${autoupdate_entries:-0}

    if [ "$monitor_entries" -gt 0 ]; then
        check_status "pass" "Monitor Cron Job" "$monitor_entries active entry(s) configured"
    else
        check_status "fail" "Monitor Cron Job" "No active cron entries found"
    fi

    if [ "$logger_entries" -gt 0 ]; then
        check_status "pass" "Logger Cron Job" "$logger_entries active entry(s) configured"
    else
        check_status "fail" "Logger Cron Job" "No active cron entries found"
    fi

    if [ "$api_entries" -gt 0 ]; then
        check_status "pass" "API Check Cron Job" "$api_entries active entry(s) configured"
    else
        check_status "warn" "API Check Cron Job" "No active cron entries (optional)"
    fi

    if [ "$maintenance_entries" -gt 0 ]; then
        check_status "pass" "Maintenance Cron Job" "$maintenance_entries active entry(s) configured"
    else
        check_status "warn" "Maintenance Cron Job" "No active cron entries (optional)"
    fi

    if [ "$autoupdate_entries" -gt 0 ]; then
        check_status "pass" "Auto-Update Cron Job" "$autoupdate_entries active entry(s) configured"
    else
        check_status "warn" "Auto-Update Cron Job" "No active cron entries (optional)"
    fi
else
    check_status "fail" "Cron Configuration" "Crontab file missing: $CRON_FILE"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}3. STARLINK CONFIGURATION${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check Starlink IP configuration
if [ -n "${STARLINK_IP:-}" ]; then
    if is_placeholder "$STARLINK_IP"; then
        check_status "config" "Starlink IP Address" "Needs configuration: $STARLINK_IP"
    else
        # Use separate IP and PORT variables (standardized format)
        grpc_host="$STARLINK_IP"
        grpc_port="${STARLINK_PORT:-9200}"
        
        log_debug "=== STARLINK CONNECTIVITY TEST ==="
        log_debug "Testing Starlink gRPC endpoint: $grpc_host:$grpc_port"
        log_debug "STARLINK_IP=$STARLINK_IP"
        log_debug "STARLINK_PORT=$grpc_port"

        # Use netcat for basic connectivity test first
        if command -v nc >/dev/null 2>&1; then
            log_debug "Testing basic TCP connectivity with netcat..."
            if echo | timeout 5 nc "$grpc_host" "$grpc_port" 2>/dev/null; then
                log_debug "✓ TCP port $grpc_port is reachable on $grpc_host"
                
                # Try grpcurl test if basic connectivity works
                if [ -f "$INSTALL_DIR/grpcurl" ] && [ -x "$INSTALL_DIR/grpcurl" ]; then
                    grpc_cmd="$INSTALL_DIR/grpcurl -plaintext -d '{\"get_device_info\":{}}' $grpc_host:$grpc_port SpaceX.API.Device.Device/Handle"
                    log_debug "Testing gRPC API with command:"
                    log_debug "  $grpc_cmd"
                    
                    if timeout 10 "$INSTALL_DIR/grpcurl" -plaintext -d '{"get_device_info":{}}' "$grpc_host:$grpc_port" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
                        log_debug "✓ gRPC API responding successfully"
                        check_status "pass" "Starlink IP Address" "gRPC API responding: $grpc_host:$grpc_port"
                    else
                        log_debug "✗ gRPC API not responding"
                        check_status "warn" "Starlink IP Address" "Port open but gRPC API not responding: $grpc_host:$grpc_port"
                    fi
                else
                    log_debug "⚠ grpcurl not available for full gRPC test"
                    check_status "pass" "Starlink IP Address" "TCP port reachable: $grpc_host:$grpc_port (grpcurl not available for full test)"
                fi
            else
                log_debug "✗ TCP port $grpc_port not reachable on $grpc_host"
                check_status "fail" "Starlink IP Address" "Not reachable: $grpc_host:$grpc_port"
            fi
        else
            log_debug "netcat not available, trying TCP test..."
            # Fallback to basic TCP test
            if timeout 5 sh -c "echo >/dev/tcp/$grpc_host/$grpc_port" 2>/dev/null; then
                log_debug "✓ TCP connection successful via /dev/tcp"
                check_status "pass" "Starlink IP Address" "TCP port reachable: $grpc_host:$grpc_port"
            else
                log_debug "✗ TCP connection failed via /dev/tcp"
                check_status "fail" "Starlink IP Address" "Not reachable: $grpc_host:$grpc_port"
            fi
        fi
    fi
else
    check_status "config" "Starlink IP Address" "Not configured (using defaults: IP=${STARLINK_IP:-192.168.100.1}, PORT=${STARLINK_PORT:-9200})"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}4. NETWORK CONFIGURATION${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check MWAN interface configuration
if [ -n "${MWAN_IFACE:-}" ]; then
    if is_placeholder "$MWAN_IFACE"; then
        check_status "config" "MWAN Interface" "Needs configuration: $MWAN_IFACE"
    else
        # Check if interface exists in UCI
        if uci get network."$MWAN_IFACE" >/dev/null 2>&1; then
            check_status "pass" "MWAN Interface" "Configured: $MWAN_IFACE"
        else
            check_status "fail" "MWAN Interface" "Interface not found in UCI: $MWAN_IFACE"
        fi
    fi
else
    check_status "config" "MWAN Interface" "Not configured"
fi

# Check MWAN member configuration
if [ -n "${MWAN_MEMBER:-}" ]; then
    if is_placeholder "$MWAN_MEMBER"; then
        check_status "config" "MWAN Member" "Needs configuration: $MWAN_MEMBER"
    else
        # Check if member exists in MWAN3 using correct UCI path
        if uci get "mwan3.$MWAN_MEMBER" >/dev/null 2>&1; then
            member_interface=$(uci get "mwan3.$MWAN_MEMBER.interface" 2>/dev/null || echo "unknown")
            check_status "pass" "MWAN Member" "Configured: $MWAN_MEMBER (interface: $member_interface)"
        else
            # Provide helpful feedback about available members
            available_members=$(uci show mwan3 2>/dev/null | grep "=member$" | cut -d'.' -f2 | cut -d'=' -f1 | head -5)
            if [ -n "$available_members" ]; then
                members_list=$(echo "$available_members" | tr '
' ',' | sed 's/,$//' | sed 's/,/, /g')
                check_status "warn" "MWAN Member" "Member '$MWAN_MEMBER' not found. Available: $members_list"
            else
                check_status "warn" "MWAN Member" "Member '$MWAN_MEMBER' not found in MWAN3 config"
            fi
        fi
    fi
else
    check_status "config" "MWAN Member" "Not configured"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}5. NOTIFICATION SYSTEM${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check Pushover configuration
if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then
    if is_placeholder "$PUSHOVER_TOKEN" || is_placeholder "$PUSHOVER_USER"; then
        check_status "config" "Pushover Notifications" "Needs configuration: TOKEN and USER required"
    else
        # Test Pushover API
        if command -v curl >/dev/null 2>&1; then
            test_response=$(curl -s --max-time 10 \
                -d "token=$PUSHOVER_TOKEN" \
                -d "user=$PUSHOVER_USER" \
                -d "message=Starlink Monitor Test" \
                https://api.pushover.net/1/messages.json 2>/dev/null || echo '{"status":0}')

            if echo "$test_response" | grep -q '"status":1'; then
                check_status "pass" "Pushover Notifications" "API test successful"
            else
                check_status "fail" "Pushover Notifications" "API test failed - check credentials"
            fi
        else
            check_status "warn" "Pushover Notifications" "Configured but curl not available for testing"
        fi
    fi
else
    check_status "info" "Pushover Notifications" "Not configured (optional feature)"
fi

# Check Slack configuration (if implemented)
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    if is_placeholder "$SLACK_WEBHOOK_URL"; then
        check_status "config" "Slack Notifications" "Needs configuration: WEBHOOK_URL required"
    else
        check_status "pass" "Slack Notifications" "Configured"
    fi
else
    check_status "info" "Slack Notifications" "Not configured (optional feature)"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}6. MONITORING THRESHOLDS${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check critical monitoring values
if [ -n "${CHECK_INTERVAL:-}" ]; then
    if is_placeholder "$CHECK_INTERVAL"; then
        check_status "config" "Check Interval" "Needs configuration: $CHECK_INTERVAL"
    else
        # Validate interval is reasonable (30-600 seconds)
        if [ "$CHECK_INTERVAL" -ge 30 ] && [ "$CHECK_INTERVAL" -le 600 ]; then
            check_status "pass" "Check Interval" "Set to ${CHECK_INTERVAL}s (recommended: 30-600s)"
        else
            check_status "warn" "Check Interval" "Set to ${CHECK_INTERVAL}s (recommended: 30-600s)"
        fi
    fi
else
    check_status "config" "Check Interval" "Not configured (using default 60s)"
fi

# Check failure threshold for Starlink connectivity monitoring
if [ -n "${FAILURE_THRESHOLD:-}" ]; then
    if is_placeholder "$FAILURE_THRESHOLD"; then
        check_status "config" "Connectivity Failure Threshold" "Needs configuration: $FAILURE_THRESHOLD"
    else
        check_status "pass" "Connectivity Failure Threshold" "Set to $FAILURE_THRESHOLD failures before failover"
    fi
else
    check_status "config" "Connectivity Failure Threshold" "Not configured (using default 3 failures before failover)"
fi

# Check recovery threshold for Starlink connectivity monitoring
if [ -n "${RECOVERY_THRESHOLD:-}" ]; then
    if is_placeholder "$RECOVERY_THRESHOLD"; then
        check_status "config" "Connectivity Recovery Threshold" "Needs configuration: $RECOVERY_THRESHOLD"
    else
        check_status "pass" "Connectivity Recovery Threshold" "Set to $RECOVERY_THRESHOLD successes before failback"
    fi
else
    check_status "config" "Connectivity Recovery Threshold" "Not configured (using default 3 successes before failback)"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}7. SYSTEM HEALTH${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Check log directory and space
log_dir="${LOG_DIR:-/etc/starlink-logs}"
if [ -d "$log_dir" ]; then
    if [ -w "$log_dir" ]; then
        log_count=$(find "$log_dir" -name "*.log" 2>/dev/null | wc -l)
        check_status "pass" "Log Directory" "Writable with $log_count log files"
    else
        check_status "fail" "Log Directory" "Exists but not writable: $log_dir"
    fi
else
    check_status "fail" "Log Directory" "Missing: $log_dir"
fi

# Check disk space - focus on relevant partitions for RUTOS
if command -v df >/dev/null 2>&1; then
    # Check root filesystem but be less strict since RUTOS manages this
    root_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "100")
    if [ "$root_usage" -eq 100 ]; then
        # Check if this is a RUTOS system where 100% is normal for root
        if df | grep -q "overlay\|tmpfs"; then
            check_status "pass" "Root Filesystem" "RUTOS overlay filesystem (100% normal for embedded systems)"
        else
            check_status "fail" "Root Filesystem" "Root filesystem ${root_usage}% used (critical)"
        fi
    elif [ "$root_usage" -lt 90 ]; then
        check_status "pass" "Root Filesystem" "Root filesystem ${root_usage}% used (healthy)"
    else
        check_status "warn" "Root Filesystem" "Root filesystem ${root_usage}% used (monitor closely)"
    fi

    # Check if we have a separate data partition that we care about more
    data_partition=""
    for partition in "/mnt/data" "/opt" "/var" "/tmp"; do
        if df "$partition" >/dev/null 2>&1 && df "$partition" 2>/dev/null | tail -1 | awk '{print $6}' | grep -q "^$partition$"; then
            data_partition="$partition"
            break
        fi
    done

    if [ -n "$data_partition" ]; then
        data_usage=$(df "$data_partition" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
        if [ "$data_usage" -lt 80 ]; then
            check_status "pass" "Data Partition ($data_partition)" "${data_usage}% used (healthy)"
        elif [ "$data_usage" -lt 90 ]; then
            check_status "warn" "Data Partition ($data_partition)" "${data_usage}% used (monitor closely)"
        else
            check_status "fail" "Data Partition ($data_partition)" "${data_usage}% used (critical)"
        fi
    fi
else
    check_status "warn" "Disk Space" "Cannot check - df command unavailable"
fi

# Check memory usage
if [ -f "/proc/meminfo" ]; then
    mem_total=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
    mem_available=$(grep "MemAvailable:" /proc/meminfo | awk '{print $2}' || grep "MemFree:" /proc/meminfo | awk '{print $2}')
    if [ -n "$mem_total" ] && [ -n "$mem_available" ] && [ "$mem_total" -gt 0 ]; then
        mem_used_percent=$(((mem_total - mem_available) * 100 / mem_total))
        if [ "$mem_used_percent" -lt 80 ]; then
            check_status "pass" "Memory Usage" "${mem_used_percent}% used (healthy)"
        elif [ "$mem_used_percent" -lt 90 ]; then
            check_status "warn" "Memory Usage" "${mem_used_percent}% used (monitor closely)"
        else
            check_status "fail" "Memory Usage" "${mem_used_percent}% used (critical)"
        fi
    else
        check_status "warn" "Memory Usage" "Cannot calculate usage"
    fi
else
    check_status "warn" "Memory Usage" "Cannot check - /proc/meminfo unavailable"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}8. CONNECTIVITY TESTS${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

# Test internet connectivity
if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    check_status "pass" "Internet Connectivity" "External connectivity working"
else
    check_status "fail" "Internet Connectivity" "Cannot reach external hosts"
fi

# Test DNS resolution
if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1; then
    check_status "pass" "DNS Resolution" "DNS queries working"
else
    check_status "fail" "DNS Resolution" "Cannot resolve domain names"
fi

# Additional connectivity tests can be added here if needed

# Calculate totals and display summary
printf "
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}                               SUMMARY${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"

printf "
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${BLUE}Results Overview:${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${GREEN}✅ Passed:${NC}      %d
" "$status_passed"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${RED}❌ Failed:${NC}      %d
" "$status_failed"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${YELLOW}⚠️  Warnings:${NC}    %d
" "$status_warnings"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${CYAN}⚙️  Config Needed:${NC} %d
" "$status_config"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "  ${BLUE}ℹ️  Info:${NC}        %d
" "$status_info"
printf "
"

# Determine overall system status
overall_status="unknown"
if [ "$status_failed" -eq 0 ] && [ "$status_config" -eq 0 ]; then
    overall_status="excellent"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}🎉 SYSTEM STATUS: EXCELLENT${NC}
"
    printf "Your Starlink monitoring system is fully operational and properly configured.
"
    printf "All components are working correctly.
"
elif [ "$status_failed" -eq 0 ] && [ "$status_config" -gt 0 ]; then
    overall_status="good"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}⚙️ SYSTEM STATUS: NEEDS CONFIGURATION${NC}
"
    printf "Your system is installed correctly but needs configuration to be fully functional.
"
    printf "Please address the configuration items marked above.
"
elif [ "$status_failed" -le 2 ] && [ "$status_warnings" -le 3 ]; then
    overall_status="needs_attention"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}⚠️ SYSTEM STATUS: NEEDS ATTENTION${NC}
"
    printf "Your system has some issues that should be addressed for optimal operation.
"
    printf "Most functionality should work, but reliability may be affected.
"
else
    overall_status="critical"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}❌ SYSTEM STATUS: CRITICAL ISSUES${NC}
"
    printf "Your system has significant problems that prevent proper operation.
"
    printf "Please resolve the failed checks before relying on the monitoring system.
"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}Quick Actions:${NC}
"

# Configuration guidance
if [ "$status_config" -gt 0 ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Configure system:  ${CYAN}vi $CONFIG_FILE${NC}
"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Re-run validation: ${CYAN}$INSTALL_DIR/scripts/validate-config-rutos.sh${NC}
"
fi

# Standard management commands
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Test monitoring:   ${CYAN}$INSTALL_DIR/scripts/tests/test-monitoring-rutos.sh${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Check system:      ${CYAN}$INSTALL_DIR/scripts/system-status-rutos.sh${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• View logs:         ${CYAN}$INSTALL_DIR/scripts/view-logs-rutos.sh${NC}
"

if [ "$status_failed" -gt 0 ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "• Repair issues:     ${CYAN}$INSTALL_DIR/scripts/repair-system-rutos.sh${NC}
"
fi

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}Configuration File Location:${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "${CYAN}$CONFIG_FILE${NC}
"

# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "
${BLUE}Documentation:${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Installation Guide: ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/INSTALLATION.md${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Configuration Help: ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/CONFIGURATION.md${NC}
"
# shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
printf "• Troubleshooting:    ${CYAN}https://github.com/your-repo/rutos-starlink-failover/blob/main/docs/TROUBLESHOOTING.md${NC}
"

printf "
"

# Exit with appropriate code based on status
# In dry-run or test mode, always exit with 0 for successful completion
if [ "${DRY_RUN:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "${GREEN}[SUCCESS]${NC} [%s] Post-installation check completed in test mode
" "$(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
fi

case "$overall_status" in
    "excellent")
        exit 0
        ;;
    "good")
        exit 10 # Configuration needed
        ;;
    "needs_attention")
        exit 20 # Warnings present
        ;;
    "critical")
        exit 30 # Critical failures
        ;;
    *)
        exit 1 # Unknown status
        ;;
esac

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
