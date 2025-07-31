#!/bin/sh
# ==============================================================================
# Fix STABILITY_CHECKS_REQUIRED Missing Configuration Issue
#
# Version: 2.8.0
# Description: Fixes the infinite failover loop caused by missing
#              STABILITY_CHECKS_REQUIRED configuration
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
DEBUG="${DEBUG:-0}"

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --test-mode)
                RUTOS_TEST_MODE=1
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat <<EOF
Starlink Failback Fix Script v$SCRIPT_VERSION

DESCRIPTION:
    Fixes the missing STABILITY_CHECKS_REQUIRED configuration that prevents
    automatic failback from cellular to Starlink after quality recovery.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run       Show what would be done without making changes
    --debug         Enable verbose debug logging
    --test-mode     Syntax check only, exit without execution
    --help, -h      Show this help message

EXAMPLES:
    # Test what would be fixed (safe)
    $0 --dry-run

    # Fix with verbose logging
    $0 --debug

    # Syntax check only
    $0 --test-mode

    # Normal fix (apply changes)
    $0

ENVIRONMENT VARIABLES:
    DRY_RUN=1           Enable dry-run mode
    DEBUG=1             Enable debug logging
    RUTOS_TEST_MODE=1   Enable test mode

EOF
}

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Function to safely execute commands with dry-run support
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ]; then
        printf "${YELLOW}[DRY-RUN]${NC} Would execute: %s\n" "$description" >&2
        printf "${YELLOW}[DRY-RUN]${NC} Command: %s\n" "$cmd" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "${CYAN}[DEBUG]${NC} Executing: %s\n" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# Function to safely write files with dry-run support
safe_write() {
    content="$1"
    file_path="$2"
    description="$3"

    if [ "$DRY_RUN" = "1" ]; then
        printf "${YELLOW}[DRY-RUN]${NC} Would write to: %s\n" "$file_path" >&2
        printf "${YELLOW}[DRY-RUN]${NC} Content: %s\n" "$description" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "${CYAN}[DEBUG]${NC} Writing to: %s\n" "$file_path" >&2
        fi
        printf "%s" "$content" >"$file_path"
    fi
}

# Main fix function
main() {
    log_info "Starlink Failback Fix Script v$SCRIPT_VERSION"
    log_info "This script fixes the missing STABILITY_CHECKS_REQUIRED configuration"

    # Show mode information
    if [ "$DRY_RUN" = "1" ]; then
        log_warn "DRY-RUN MODE: No changes will be made"
    fi
    if [ "$DEBUG" = "1" ]; then
        log_debug "DEBUG MODE enabled - verbose logging active"
        log_debug "Script arguments: $*"
        log_debug "Working directory: $(pwd)"
        log_debug "User: $(whoami 2>/dev/null || echo 'unknown')"
    fi
    echo ""

    # Check if we're on a RUTOS system
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Step 1: Check current state
    log_step "Checking current Starlink failover state"

    log_debug "Reading state files and UCI configuration"
    current_state=$(cat /tmp/run/starlink_monitor.state 2>/dev/null || echo "unknown")
    stability_count=$(cat /tmp/run/starlink_monitor.stability 2>/dev/null || echo "0")
    current_metric=$(uci -q get mwan3.member1.metric 2>/dev/null || echo "unknown")

    log_debug "State file contents:"
    log_debug "  /tmp/run/starlink_monitor.state: $current_state"
    log_debug "  /tmp/run/starlink_monitor.stability: $stability_count"
    log_debug "  mwan3.member1.metric: $current_metric"

    log_info "Current state: $current_state"
    log_info "Stability count: $stability_count"
    log_info "Current metric: $current_metric"

    if [ "$current_state" = "down" ] && [ "$current_metric" = "20" ]; then
        log_warn "Starlink is currently in failover mode (stuck!)"
    fi
    echo ""

    # Step 2: Check configuration file
    log_step "Checking configuration file"

    config_file="/etc/starlink-config/config.sh"
    log_debug "Configuration file path: $config_file"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        if [ "$DRY_RUN" = "1" ]; then
            log_warn "DRY-RUN: Would exit here due to missing config file"
            return 1
        else
            exit 1
        fi
    fi

    log_debug "Configuration file exists, checking for STABILITY_CHECKS_REQUIRED"
    # Check if STABILITY_CHECKS_REQUIRED is defined
    if grep -q "STABILITY_CHECKS_REQUIRED" "$config_file"; then
        log_info "STABILITY_CHECKS_REQUIRED found in config"
        current_value=$(grep "STABILITY_CHECKS_REQUIRED" "$config_file" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        log_info "Current value: $current_value"
        log_debug "Extracted value from config: '$current_value'"
    else
        log_warn "STABILITY_CHECKS_REQUIRED missing from configuration!"

        # Step 3: Add missing configuration
        log_step "Adding STABILITY_CHECKS_REQUIRED to configuration"

        log_debug "Preparing to add STABILITY_CHECKS_REQUIRED to config file"
        # Add the missing configuration
        config_addition="

# Stability checks required before failback (consecutive good checks)
# Added by fix-stability-checks-rutos.sh on $(date)
export STABILITY_CHECKS_REQUIRED=\"5\""

        if [ "$DRY_RUN" = "1" ]; then
            log_warn "DRY-RUN: Would append to $config_file:"
            printf "${YELLOW}%s${NC}\n" "$config_addition"
        else
            printf "%s" "$config_addition" >>"$config_file"
            log_success "Added STABILITY_CHECKS_REQUIRED=5 to configuration"
        fi
    fi
    echo ""

    # Step 4: Immediate fix - restore Starlink priority
    log_step "Performing immediate failback to restore Starlink priority"

    if [ "$current_metric" = "20" ]; then
        log_info "Restoring Starlink to primary priority (metric=1)"
        log_debug "Current metric is 20 (failover), changing to 1 (primary)"

        if safe_execute "uci set mwan3.member1.metric='1' && uci commit mwan3" "Set Starlink metric to 1 and commit UCI changes"; then
            log_success "UCI configuration updated"

            if safe_execute "mwan3 restart" "Restart mwan3 service"; then
                log_success "mwan3 service restarted"

                # Reset state files
                log_debug "Resetting state files to 'up' and stability count to 0"
                safe_write "up" "/tmp/run/starlink_monitor.state" "Set monitor state to 'up'"
                safe_write "0" "/tmp/run/starlink_monitor.stability" "Reset stability count to 0"

                log_success "State files reset"
                log_success "Starlink is now back to primary internet!"
            else
                log_error "Failed to restart mwan3 service"
                if [ "$DRY_RUN" = "1" ]; then
                    log_warn "DRY-RUN: Would exit here due to mwan3 restart failure"
                else
                    exit 1
                fi
            fi
        else
            log_error "Failed to update UCI configuration"
            if [ "$DRY_RUN" = "1" ]; then
                log_warn "DRY-RUN: Would exit here due to UCI update failure"
            else
                exit 1
            fi
        fi
    else
        log_info "Starlink metric is already correct ($current_metric)"
        log_debug "No metric change needed, current metric: $current_metric"
    fi
    echo ""

    # Step 5: Verify fix
    log_step "Verifying the fix"

    log_debug "Reading final state after changes"
    if [ "$DRY_RUN" = "1" ]; then
        # In dry-run mode, simulate the expected results
        new_metric="1"
        new_state="up"
        new_stability="0"
        log_debug "DRY-RUN: Simulating expected final state"
    else
        new_metric=$(uci -q get mwan3.member1.metric 2>/dev/null || echo "unknown")
        new_state=$(cat /tmp/run/starlink_monitor.state 2>/dev/null || echo "unknown")
        new_stability=$(cat /tmp/run/starlink_monitor.stability 2>/dev/null || echo "unknown")
    fi

    log_debug "Final state verification:"
    log_debug "  mwan3.member1.metric: $new_metric"
    log_debug "  starlink_monitor.state: $new_state"
    log_debug "  starlink_monitor.stability: $new_stability"

    log_info "New metric: $new_metric"
    log_info "New state: $new_state"
    log_info "New stability count: $new_stability"

    if [ "$new_metric" = "1" ] && [ "$new_state" = "up" ]; then
        if [ "$DRY_RUN" = "1" ]; then
            log_success "DRY-RUN: Fix would complete successfully!"
            log_success "DRY-RUN: Starlink would be primary internet connection"
        else
            log_success "Fix completed successfully!"
            log_success "Starlink is now primary internet connection"
        fi
        echo ""
        log_info "Future failovers will now automatically failback after 5 consecutive good checks"
        log_info "Monitor with: logread | grep StarlinkMonitor"

        if [ "$DEBUG" = "1" ]; then
            log_debug "Fix summary:"
            log_debug "  Configuration updated: STABILITY_CHECKS_REQUIRED=5"
            log_debug "  mwan3 metric restored: member1.metric=1"
            log_debug "  State files reset: state=up, stability=0"
            log_debug "  Service restarted: mwan3"
        fi
    else
        if [ "$DRY_RUN" = "1" ]; then
            log_error "DRY-RUN: Fix simulation shows unexpected results"
        else
            log_error "Fix may not have completed successfully"
            log_error "Please check the system manually"
        fi
        log_debug "Expected: metric=1, state=up"
        log_debug "Actual: metric=$new_metric, state=$new_state"

        if [ "$DRY_RUN" = "1" ]; then
            return 1
        else
            exit 1
        fi
    fi
}

# Execute main function
parse_arguments "$@"
main "$@"
