#!/bin/sh
# Script: debug-config.sh
# Version: 2.4.12
# Description: Debug script to analyze config format issues

set -e # Exit on error

# Version information
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled (keep current values)
    :
else
    # Colors disabled
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
    printf "%s[INFO]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "%s[WARNING]%s [%s] %s\n" "$YELLOW" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "%s[ERROR]%s [%s] %s\n" "$RED" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "%s[DEBUG]%s [%s] %s\n" "$CYAN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "%s[SUCCESS]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "%s[STEP]%s [%s] %s\n" "$BLUE" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Main analysis function
analyze_config() {
    CONFIG_FILE="${1:-./config.sh}"

    log_info "Starting config analysis v$SCRIPT_VERSION"
    log_step "Analyzing config file: $CONFIG_FILE"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi

    printf "\n%s=== CONFIG FILE ANALYSIS ===%s\n" "$PURPLE" "$NC"
    printf "File: %s\n\n" "$CONFIG_FILE"

    log_step "Checking export variables"
    grep -n "^export [A-Z_]*=" "$CONFIG_FILE" | head -10

    printf "\n"
    log_step "Checking non-export variables"
    grep -n "^[A-Z_]*=" "$CONFIG_FILE" | head -10

    printf "\n"
    log_step "Counting variables"
    export_count=$(grep -c "^export [A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || printf "0")
    nonexport_count=$(grep -c "^[A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || printf "0")
    printf "Export format: %s\n" "$export_count"
    printf "Non-export format: %s\n" "$nonexport_count"
    printf "Total: %s\n" "$((export_count + nonexport_count))"

    printf "\n"
    log_step "Checking critical variables"
    for var in STARLINK_IP MWAN_IFACE MWAN_MEMBER CHECK_INTERVAL; do
        # Try both formats
        value=$(grep "^export $var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -z "$value" ]; then
            value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        fi

        if [ -n "$value" ]; then
            printf "%s✓ %s = '%s'%s\n" "$GREEN" "$var" "$value" "$NC"
        else
            printf "%s✗ %s = NOT FOUND%s\n" "$RED" "$var" "$NC"
        fi
    done

    printf "\n"
    log_step "Checking template comparison"
    template_file="/root/starlink-monitor/config/config.template.sh"
    if [ -f "$template_file" ]; then
        log_info "Template file exists: $template_file"
        template_vars=$(grep -E '^export [A-Z_]+=.*' "$template_file" | sed 's/^export //' | cut -d'=' -f1 | sort)
        config_vars=$(grep -E '^[A-Z_]+=.*' "$CONFIG_FILE" | cut -d'=' -f1 | sort)

        echo "Template variables:"
        echo "$template_vars"
        echo
        echo "Config variables:"
        echo "$config_vars"
        echo
        echo "Missing from config:"
        echo "$template_vars" | while read -r var; do
            if ! echo "$config_vars" | grep -q "^$var$"; then
                echo "  - $var"
            fi
        done
    else
        log_warning "Template file not found: $template_file"
    fi

    log_success "Config analysis completed"
}

# Main execution
main() {
    # Debug mode support
    DEBUG="${DEBUG:-0}"
    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode enabled"
        log_debug "Script version: $SCRIPT_VERSION"
        log_debug "Arguments: $*"
    fi

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_warning "Not running on OpenWrt/RUTOS system"
    fi

    analyze_config "$@"
}

# Execute main function
main "$@"
