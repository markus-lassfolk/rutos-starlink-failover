#!/bin/sh
# starfailctl - CLI helper for starfail daemon
# Compatible with POSIX sh and busybox

set -e

PROG_NAME="starfailctl"
VERSION="1.0.0-dev"
SERVICE_NAME="starfail"

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${BLUE}[DEBUG]${NC} %s\n" "$1" >&2
    fi
}

# Check if ubus is available
check_ubus() {
    if ! command -v ubus >/dev/null 2>&1; then
        log_error "ubus command not found"
        return 1
    fi
    
    if ! ubus list | grep -q "^${SERVICE_NAME}$"; then
        log_error "starfail service not found in ubus"
        log_info "Is starfaild running? Try: /etc/init.d/starfail status"
        return 1
    fi
    
    return 0
}

# Execute ubus call with error handling
ubus_call() {
    local method="$1"
    shift
    local params="$*"
    
    log_debug "ubus call ${SERVICE_NAME} ${method} ${params}"
    
    if ! ubus call "${SERVICE_NAME}" "${method}" ${params} 2>/dev/null; then
        log_error "Failed to call ${method}"
        return 1
    fi
}

# Show daemon status
cmd_status() {
    log_info "Getting starfail daemon status..."
    
    if ! check_ubus; then
        return 1
    fi
    
    ubus_call status | jq -r '
        "Status: " + .status,
        "Uptime: " + (.uptime_seconds | tostring) + " seconds",
        "Version: " + .version,
        (if .current_member then "Current Primary: " + .current_member.name else "Current Primary: none" end),
        "Total Samples: " + (.stats.total_samples | tostring),
        "Total Events: " + (.stats.total_events | tostring)
    '
}

# List discovered members
cmd_members() {
    log_info "Listing discovered members..."
    
    if ! check_ubus; then
        return 1
    fi
    
    ubus_call members | jq -r '
        "Members (" + (.count | tostring) + "):",
        "",
        (.members[] | 
            "• " + .member.name + 
            " (" + .member.interface + ")" +
            " - " + .status +
            (if .last_score then " [score: " + (.last_score | tostring) + "]" else "" end)
        )
    '
}

# Show detailed metrics for a member
cmd_metrics() {
    local member="$1"
    local limit="${2:-10}"
    
    if [ -z "$member" ]; then
        log_error "Member name required"
        log_info "Usage: $PROG_NAME metrics <member_name> [limit]"
        return 1
    fi
    
    log_info "Getting metrics for member: $member"
    
    if ! check_ubus; then
        return 1
    fi
    
    ubus_call metrics "{\"member\":\"$member\",\"limit\":$limit}" | jq -r '
        "Metrics for " + .member + " (last " + (.count | tostring) + " samples):",
        "Time Range: " + .time_range,
        "",
        (.samples[] | 
            .timestamp + ": " +
            "score=" + (.final_score | tostring) +
            (if .metrics.latency_ms then ", lat=" + (.metrics.latency_ms | tostring) + "ms" else "" end) +
            (if .metrics.packet_loss_pct then ", loss=" + (.metrics.packet_loss_pct | tostring) + "%" else "" end) +
            (if .metrics.jitter_ms then ", jitter=" + (.metrics.jitter_ms | tostring) + "ms" else "" end)
        )
    '
}

# Execute failover action
cmd_failover() {
    local member="$1"
    local force="${2:-false}"
    
    if [ -z "$member" ]; then
        log_error "Member name required"
        log_info "Usage: $PROG_NAME failover <member_name> [force]"
        return 1
    fi
    
    log_info "Initiating failover to member: $member"
    
    if ! check_ubus; then
        return 1
    fi
    
    local force_param=""
    if [ "$force" = "force" ] || [ "$force" = "true" ]; then
        force_param=",\"force\":true"
    fi
    
    result=$(ubus_call action "{\"action\":\"failover\",\"member\":\"$member\"$force_param}")
    
    if echo "$result" | jq -e '.success' >/dev/null; then
        log_info "$(echo "$result" | jq -r '.message')"
    else
        log_error "$(echo "$result" | jq -r '.message')"
        return 1
    fi
}

# Show recent events
cmd_events() {
    local limit="${1:-20}"
    
    log_info "Getting recent events (last $limit)..."
    
    if ! check_ubus; then
        return 1
    fi
    
    ubus_call events "{\"limit\":$limit}" | jq -r '
        "Recent Events (" + (.count | tostring) + "):",
        "",
        (.events[] | 
            .timestamp + " [" + .level + "] " + .type + 
            (if .member then " (" + .member + ")" else "" end) +
            ": " + .message
        )
    '
}

# Refresh daemon configuration
cmd_refresh() {
    log_info "Refreshing daemon configuration..."
    
    if ! check_ubus; then
        return 1
    fi
    
    result=$(ubus_call action '{"action":"refresh"}')
    
    if echo "$result" | jq -e '.success' >/dev/null; then
        log_info "$(echo "$result" | jq -r '.message')"
    else
        log_error "$(echo "$result" | jq -r '.message')"
        return 1
    fi
}

# Service management functions
cmd_start() {
    log_info "Starting starfail service..."
    /etc/init.d/starfail start
}

cmd_stop() {
    log_info "Stopping starfail service..."
    /etc/init.d/starfail stop
}

cmd_restart() {
    log_info "Restarting starfail service..."
    /etc/init.d/starfail restart
}

cmd_reload() {
    log_info "Reloading starfail configuration..."
    killall -HUP starfaild 2>/dev/null || {
        log_warn "Could not send SIGHUP to starfaild, trying restart..."
        /etc/init.d/starfail restart
    }
}

# Show version
cmd_version() {
    echo "$PROG_NAME $VERSION"
    
    if check_ubus >/dev/null 2>&1; then
        daemon_info=$(ubus_call status 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
        echo "Daemon version: $daemon_info"
    fi
}

# Show help
cmd_help() {
    cat << EOF
$PROG_NAME - CLI for starfail daemon

USAGE:
    $PROG_NAME <command> [options]

COMMANDS:
    status              Show daemon status and current primary
    members             List all discovered members
    metrics <member>    Show detailed metrics for a member
    events [limit]      Show recent events (default: 20)
    failover <member>   Manually failover to specified member
    refresh             Refresh daemon configuration
    
    start               Start the starfail service
    stop                Stop the starfail service  
    restart             Restart the starfail service
    reload              Reload configuration (SIGHUP)
    
    version             Show version information
    help                Show this help message

EXAMPLES:
    $PROG_NAME status
    $PROG_NAME members
    $PROG_NAME metrics wan_starlink
    $PROG_NAME failover wan_cell
    $PROG_NAME events 50

ENVIRONMENT:
    DEBUG=1             Enable debug output

For more information, see the project documentation.
EOF
}

# Main command dispatcher
main() {
    # Parse global options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_help
                exit 0
                ;;
            -v|--version)
                cmd_version
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                break
                ;;
        esac
        shift
    done
    
    # Check for command
    if [ $# -eq 0 ]; then
        log_error "No command specified"
        cmd_help
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Dispatch to command function
    case "$command" in
        status)
            cmd_status "$@"
            ;;
        members)
            cmd_members "$@"
            ;;
        metrics)
            cmd_metrics "$@"
            ;;
        events)
            cmd_events "$@"
            ;;
        failover)
            cmd_failover "$@"
            ;;
        refresh)
            cmd_refresh "$@"
            ;;
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        reload)
            cmd_reload "$@"
            ;;
        version)
            cmd_version "$@"
            ;;
        help)
            cmd_help "$@"
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

# Check dependencies
check_deps() {
    local missing_deps=""
    
    for dep in jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps="$missing_deps $dep"
        fi
    done
    
    if [ -n "$missing_deps" ]; then
        log_error "Missing dependencies:$missing_deps"
        log_info "Please install: opkg install$missing_deps"
        exit 1
    fi
}

# Entry point
if [ "${0##*/}" = "starfailctl" ] || [ "${0##*/}" = "starfailctl.sh" ]; then
    check_deps
    main "$@"
fi
