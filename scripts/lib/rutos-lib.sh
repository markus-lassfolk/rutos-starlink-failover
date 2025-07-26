#!/bin/sh
# ==============================================================================
# RUTOS Library Loader
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# Main entry point for loading all RUTOS library modules.
# Include this one file in scripts to get all standardized functionality.
#
# Usage in scripts:
#   . "$(dirname "$0")/lib/rutos-lib.sh"
#   rutos_init "script-name" "1.0.0"
# ==============================================================================

# Prevent multiple sourcing
if [ "${_RUTOS_LIB_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_LIB_LOADED=1

# Determine library directory
_rutos_lib_dir=""

# Try different possible locations for the lib directory
for _possible_dir in \
    "$(dirname "$0")/lib" \
    "$(dirname "$0")/../scripts/lib" \
    "/etc/starlink-config/lib" \
    "./scripts/lib" \
    "./lib"; do

    if [ -d "$_possible_dir" ] && [ -f "$_possible_dir/rutos-colors.sh" ]; then
        _rutos_lib_dir="$_possible_dir"
        break
    fi
done

# Verify we found the library directory
if [ -z "$_rutos_lib_dir" ]; then
    printf "ERROR: Could not locate RUTOS library directory\n" >&2
    printf "Expected to find rutos-colors.sh in one of these locations:\n" >&2
    printf "  - \$(dirname \$0)/lib/\n" >&2
    printf "  - \$(dirname \$0)/../scripts/lib/\n" >&2
    printf "  - /etc/starlink-config/lib/\n" >&2
    printf "  - ./scripts/lib/\n" >&2
    printf "  - ./lib/\n" >&2
    exit 1
fi

# Load all library modules in the correct order
. "$_rutos_lib_dir/rutos-colors.sh"
. "$_rutos_lib_dir/rutos-logging.sh"
. "$_rutos_lib_dir/rutos-common.sh"

# ============================================================================
# RUTOS INITIALIZATION FUNCTION
# ============================================================================

# Main initialization function for RUTOS scripts
rutos_init() {
    script_name="${1:-$(basename "$0")}"
    script_version="${2:-unknown}"

    # Set up logging levels
    setup_logging_levels

    # Set up cleanup handlers
    setup_cleanup_handlers

    # Log script initialization
    log_script_init "$script_name" "$script_version"

    # Validate RUTOS environment (unless in test mode)
    if [ "${SKIP_RUTOS_VALIDATION:-0}" != "1" ]; then
        validate_rutos_environment
    fi

    # Check for early test mode exit
    check_test_mode_exit

    # Export common variables for child processes
    export SCRIPT_NAME="$script_name"
    # Only export SCRIPT_VERSION if not already set (respect existing script versions)
    if [ -z "${SCRIPT_VERSION:-}" ]; then
        export SCRIPT_VERSION="$script_version"
    fi
    export _RUTOS_LIB_DIR="$_rutos_lib_dir"
}

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

# Quick setup for simple scripts (minimal initialization)
rutos_init_simple() {
    script_name="${1:-$(basename "$0")}"

    # Load minimal components
    setup_logging_levels
    log_info "Starting $script_name"
    check_test_mode_exit
}

# Setup for scripts that don't need RUTOS validation
rutos_init_portable() {
    script_name="${1:-$(basename "$0")}"
    script_version="${2:-unknown}"

    # Skip RUTOS environment validation
    SKIP_RUTOS_VALIDATION=1
    rutos_init "$script_name" "$script_version"
}

# ============================================================================
# LIBRARY INFORMATION
# ============================================================================

# Display loaded library information
rutos_lib_info() {
    printf "RUTOS Library System Information:\n"
    printf "  Library Directory: %s\n" "$_rutos_lib_dir"
    printf "  Colors Module: %s\n" "${_RUTOS_COLORS_LOADED:-not loaded}"
    printf "  Logging Module: %s\n" "${_RUTOS_LOGGING_LOADED:-not loaded}"
    printf "  Common Module: %s\n" "${_RUTOS_COMMON_LOADED:-not loaded}"
    printf "  Current Log Level: %s\n" "${LOG_LEVEL:-not set}"
    printf "  Environment Variables:\n"
    printf "    DRY_RUN: %s\n" "${DRY_RUN:-not set}"
    printf "    DEBUG: %s\n" "${DEBUG:-not set}"
    printf "    RUTOS_TEST_MODE: %s\n" "${RUTOS_TEST_MODE:-not set}"
}

# Check if all required modules are loaded
rutos_lib_check() {
    missing_modules=""

    if [ "${_RUTOS_COLORS_LOADED:-0}" != "1" ]; then
        missing_modules="$missing_modules colors"
    fi

    if [ "${_RUTOS_LOGGING_LOADED:-0}" != "1" ]; then
        missing_modules="$missing_modules logging"
    fi

    if [ "${_RUTOS_COMMON_LOADED:-0}" != "1" ]; then
        missing_modules="$missing_modules common"
    fi

    if [ -n "$missing_modules" ]; then
        printf "ERROR: Missing RUTOS modules:%s\n" "$missing_modules" >&2
        return 1
    else
        return 0
    fi
}
