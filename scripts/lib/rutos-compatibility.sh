#!/bin/sh
# ==============================================================================
# RUTOS Library - Legacy Compatibility Module
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# Provides compatibility functions for legacy logging patterns found in older scripts.
# This allows gradual migration to RUTOS library standards without breaking existing code.
#
# Legacy patterns mapped to RUTOS library functions:
# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: rutos-compatibility.sh v$SCRIPT_VERSION"
fi
# - debug_log() -> log_debug()
# - debug_msg() -> log_debug()
# - print_status() -> printf with colors
# - debug_exec() -> safe_execute()
# - log_message() -> appropriate log_* function
# ==============================================================================

# Only load if RUTOS library is present

# Version information (auto-updated by update-version.sh)
# Only set if not already defined as readonly
if ! readonly SCRIPT_VERSION 2>/dev/null; then
    SCRIPT_VERSION="2.8.0"
    readonly SCRIPT_VERSION
fi
if [ "${_RUTOS_LIB_LOADED:-}" != "1" ]; then
    printf "ERROR: RUTOS compatibility module requires RUTOS library to be loaded first\n" >&2
    exit 1
fi

# Prevent multiple loading
if [ "${_RUTOS_COMPATIBILITY_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_COMPATIBILITY_LOADED=1

# ==============================================================================
# LEGACY COMPATIBILITY FUNCTIONS
# ==============================================================================

# Legacy debug_log() -> log_debug()
debug_log() {
    log_debug "$1"
}

# Legacy debug_msg() -> log_debug()
debug_msg() {
    log_debug "$1"
}

# Legacy print_status() -> printf with colors
print_status() {
    color="$1"
    message="$2"
    printf "%s%s%s\n" "$color" "$message" "$NC"
}

# Legacy debug_exec() -> safe_execute()
debug_exec() {
    safe_execute "$*" "Execute command: $*"
}

# Legacy log_message() -> appropriate log_* function based on level
log_message() {
    level="$1"
    message="$2"

    case "$level" in
        "INFO" | "info") log_info "$message" ;;
        "SUCCESS" | "success") log_success "$message" ;;
        "WARNING" | "warning" | "WARN" | "warn") log_warning "$message" ;;
        "ERROR" | "error") log_error "$message" ;;
        "STEP" | "step") log_step "$message" ;;
        "DEBUG" | "debug") log_debug "$message" ;;
        *) log_info "[$level] $message" ;;
    esac
}

# Legacy config_debug() -> log_debug()
config_debug() {
    log_debug "$1"
}

# Additional legacy patterns can be added here as discovered
# For example:
# legacy_function_name() {
#     modern_rutos_function "$@"
# }

# ==============================================================================
# COMPATIBILITY INFORMATION
# ==============================================================================

# Export compatibility information for debugging
export _RUTOS_COMPATIBILITY_FUNCTIONS="debug_log debug_msg print_status debug_exec log_message config_debug"

# Log compatibility loading if debug mode is enabled
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "RUTOS compatibility layer loaded with functions: $_RUTOS_COMPATIBILITY_FUNCTIONS"
fi
