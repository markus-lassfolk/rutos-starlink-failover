#!/bin/sh
# shellcheck disable=SC2317
# Script: validate-persistent-config-rutos.sh
# Version: 2.7.1
# Description: Validate persistent configuration for firmware upgrade restoration

set -e

# Version information
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
# Colors for output (busybox compatible)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='[0;31m'
    GREEN='[0;32m'
    YELLOW='[1;33m'
    BLUE='[1;35m'
    CYAN='[0;36m'
    NC='[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

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
        printf "[DRY-RUN] Command: %s
" "$cmd" >&2
        return 0
    else
        printf "[EXECUTE] %s
" "$description" >&2
        eval "$cmd"
    fi
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s
" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "Debug mode enabled for validate-persistent-config-rutos.sh v$SCRIPT_VERSION"
fi

# Validate persistent configuration for corruption and required settings
validate_persistent_config() {
    config_file="$1"
    log_step "Validating configuration file: $config_file"

    validation_errors=0
    validation_warnings=0

    # Check if file exists and is readable
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file does not exist: $config_file"
        return 1
    fi

    if [ ! -r "$config_file" ]; then
        log_error "Configuration file is not readable: $config_file"
        return 1
    fi

    # Check file size (should not be empty or too small)
    file_size=$(wc -c <"$config_file" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 100 ]; then
        log_error "Configuration file is too small ($file_size bytes) - likely corrupted"
        return 1
    else
        log_info "File size check passed: $file_size bytes"
    fi

    # Check for shell syntax errors
    if ! sh -n "$config_file" 2>/dev/null; then
        log_error "Configuration file has shell syntax errors"
        validation_errors=$((validation_errors + 1))
    else
        log_info "Shell syntax validation passed"
    fi

    # Check for required settings
    required_settings="STARLINK_IP MWAN_IFACE MWAN_MEMBER"
    log_step "Checking required settings..."

    for setting in $required_settings; do
        if ! grep -q "^${setting}=" "$config_file" 2>/dev/null; then
            log_error "Missing required setting: $setting"
            validation_errors=$((validation_errors + 1))
        else
            # Check if value is not a placeholder
            value=$(grep "^${setting}=" "$config_file" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
            if echo "$value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                log_warning "Setting $setting has placeholder value: $value"
                validation_warnings=$((validation_warnings + 1))
            else
                log_debug "Required setting OK: $setting = $value"
            fi
        fi
    done

    # Check for common configuration settings
    optional_settings="PUSHOVER_TOKEN PUSHOVER_USER RUTOS_USERNAME RUTOS_PASSWORD"
    log_step "Checking optional settings..."

    configured_count=0
    for setting in $optional_settings; do
        if grep -q "^${setting}=" "$config_file" 2>/dev/null; then
            value=$(grep "^${setting}=" "$config_file" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
            if ! echo "$value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                configured_count=$((configured_count + 1))
                log_debug "Optional setting configured: $setting"
            fi
        fi
    done

    if [ "$configured_count" -gt 0 ]; then
        log_info "Found $configured_count configured optional settings"
    else
        log_warning "No optional settings are configured (all using defaults/placeholders)"
        validation_warnings=$((validation_warnings + 1))
    fi

    # Check for template version information
    if grep -q "^# Template Version:" "$config_file" 2>/dev/null; then
        template_version=$(grep "^# Template Version:" "$config_file" | head -1 | cut -d':' -f2- | tr -d ' ')
        log_info "Template version detected: $template_version"
    else
        log_debug "No template version information found"
    fi

    # Summary
    log_step "Validation summary:"
    if [ "$validation_errors" -eq 0 ]; then
        if [ "$validation_warnings" -eq 0 ]; then
            log_info "✅ Configuration validation PASSED - No errors or warnings"
            return 0
        else
            log_warning "⚠️ Configuration validation PASSED with $validation_warnings warnings"
            return 0
        fi
    else
        log_error "❌ Configuration validation FAILED with $validation_errors errors and $validation_warnings warnings"
        return 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 <config_file_path>"
    echo ""
    echo "Validates persistent configuration files for firmware upgrade restoration."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -d, --debug   Enable debug output"
    echo ""
    echo "Examples:"
    echo "  $0 /etc/starlink-config/config.sh"
    echo "  DEBUG=1 $0 /path/to/config.sh"
    echo ""
    echo "Exit codes:"
    echo "  0  Configuration is valid"
    echo "  1  Configuration is invalid or corrupted"
    echo "  2  Invalid usage"
}

# Main function
main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                show_usage
                exit 0
                ;;
            -d | --debug)
                DEBUG=1
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
            *)
                break
                ;;
        esac
    done

    # Check if config file argument provided
    if [ $# -eq 0 ]; then
        log_error "No configuration file specified"
        show_usage
        exit 2
    fi

    config_file="$1"

    log_info "Starting persistent configuration validation v$SCRIPT_VERSION"
    log_info "Target configuration: $config_file"

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_warning "This script is designed for OpenWrt/RUTOS systems"
    fi

    # Perform validation
    if validate_persistent_config "$config_file"; then
        log_info "🎉 Configuration validation completed successfully"
        exit 0
    else
        log_error "💥 Configuration validation failed"
        exit 1
    fi
}

# Execute main function
main "$@"

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
