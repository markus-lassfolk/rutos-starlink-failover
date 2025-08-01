#!/bin/sh
# ==============================================================================
# RUTOS Library Loader
#
# Main entry point for loading all RUTOS library modules.
# Include this one file in scripts to get all standardized functionality.
#
# Usage in scripts:
#   . "$(dirname "$0")/lib/rutos-lib.sh"
#   rutos_init "script-name" "1.0.0"
# ==============================================================================

# CRITICAL: Add immediate debug output for library loading
printf "[LIB_DEBUG] rutos-lib.sh starting at $(date '+%Y-%m-%d %H:%M:%S')\n" >&2
printf "[LIB_DEBUG] Called from script: $0\n" >&2
printf "[LIB_DEBUG] Current working directory: $(pwd)\n" >&2
printf "[LIB_DEBUG] Environment check:\n" >&2
printf "[LIB_DEBUG]   DEBUG=${DEBUG:-not_set}\n" >&2
printf "[LIB_DEBUG]   RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-not_set}\n" >&2
printf "[LIB_DEBUG]   _RUTOS_LIB_LOADED=${_RUTOS_LIB_LOADED:-not_set}\n" >&2

# Prevent multiple sourcing
if [ "${_RUTOS_LIB_LOADED:-}" = "1" ]; then
    printf "[LIB_DEBUG] Library already loaded, returning early\n" >&2
    return 0
fi

printf "[LIB_DEBUG] Setting _RUTOS_LIB_LOADED=1\n" >&2
_RUTOS_LIB_LOADED=1

printf "[LIB_DEBUG] Starting library directory detection...\n" >&2

# Determine library directory
_rutos_lib_dir=""

printf "[LIB_DEBUG] Testing possible library directories...\n" >&2

# Try different possible locations for the lib directory
for _possible_dir in \
    "$(dirname "$0")/lib" \
    "$(dirname "$0")/../scripts/lib" \
    "/etc/starlink-config/lib" \
    "./scripts/lib" \
    "./lib"; do

    printf "[LIB_DEBUG] Testing directory: %s\n" "$_possible_dir" >&2
    printf "[LIB_DEBUG]   Directory exists: $([ -d "$_possible_dir" ] && echo yes || echo no)\n" >&2
    printf "[LIB_DEBUG]   rutos-colors.sh exists: $([ -f "$_possible_dir/rutos-colors.sh" ] && echo yes || echo no)\n" >&2

    if [ -d "$_possible_dir" ] && [ -f "$_possible_dir/rutos-colors.sh" ]; then
        _rutos_lib_dir="$_possible_dir"
        printf "[LIB_DEBUG] ✓ Found library directory: %s\n" "$_possible_dir" >&2
        break
    else
        printf "[LIB_DEBUG] ✗ Directory not suitable: %s\n" "$_possible_dir" >&2
    fi
done

printf "[LIB_DEBUG] Library directory detection complete: %s\n" "${_rutos_lib_dir:-NOT_FOUND}" >&2

# Verify we found the library directory
if [ -z "$_rutos_lib_dir" ]; then
    printf "[LIB_DEBUG] ✗ FATAL: No suitable library directory found\n" >&2
    printf "ERROR: Could not locate RUTOS library directory\n" >&2
    printf "Expected to find rutos-colors.sh in one of these locations:\n" >&2
    printf "  - \$(dirname \$0)/lib/\n" >&2
    printf "  - \$(dirname \$0)/../scripts/lib/\n" >&2
    printf "  - /etc/starlink-config/lib/\n" >&2
    printf "  - ./scripts/lib/\n" >&2
    printf "  - ./lib/\n" >&2
    exit 1
fi

printf "[LIB_DEBUG] Starting to load library modules from: %s\n" "$_rutos_lib_dir" >&2

# Load all library modules in the correct order
printf "[LIB_DEBUG] Loading rutos-colors.sh...\n" >&2
if . "$_rutos_lib_dir/rutos-colors.sh"; then
    printf "[LIB_DEBUG] ✓ rutos-colors.sh loaded successfully\n" >&2
else
    printf "[LIB_DEBUG] ✗ FAILED to load rutos-colors.sh\n" >&2
    exit 1
fi

printf "[LIB_DEBUG] Loading rutos-logging.sh...\n" >&2
if . "$_rutos_lib_dir/rutos-logging.sh"; then
    printf "[LIB_DEBUG] ✓ rutos-logging.sh loaded successfully\n" >&2
else
    printf "[LIB_DEBUG] ✗ FAILED to load rutos-logging.sh\n" >&2
    exit 1
fi

printf "[LIB_DEBUG] Loading rutos-common.sh...\n" >&2
if . "$_rutos_lib_dir/rutos-common.sh"; then
    printf "[LIB_DEBUG] ✓ rutos-common.sh loaded successfully\n" >&2
else
    printf "[LIB_DEBUG] ✗ FAILED to load rutos-common.sh\n" >&2
    exit 1
fi

# Load optional modules with graceful handling
printf "[LIB_DEBUG] Loading optional modules...\n" >&2

# Load centralized error logging module (conditional - bootstrap mode or config-enabled)
printf "[LIB_DEBUG] Checking if centralized error logging should be enabled...\n" >&2

# Check if we should load error logging (bootstrap mode or config setting)
_should_load_error_logging=0

# Check for explicit override
if [ -n "${ENABLE_CENTRALIZED_ERROR_LOGGING:-}" ]; then
    if [ "$ENABLE_CENTRALIZED_ERROR_LOGGING" = "true" ]; then
        _should_load_error_logging=1
        printf "[LIB_DEBUG] Centralized error logging: ENABLED (explicit override)\n" >&2
    else
        printf "[LIB_DEBUG] Centralized error logging: DISABLED (explicit override)\n" >&2
    fi
# Check for bootstrap mode (no config exists)
elif [ ! -f "${CONFIG_DIR:-/etc/starlink-failover}/config.sh" ]; then
    _should_load_error_logging=1
    printf "[LIB_DEBUG] Centralized error logging: ENABLED (bootstrap mode - no config found)\n" >&2
# Check config setting
elif [ -f "${CONFIG_DIR:-/etc/starlink-failover}/config.sh" ] && grep -q "ENABLE_AUTONOMOUS_ERROR_LOGGING=.*true" "${CONFIG_DIR:-/etc/starlink-failover}/config.sh" 2>/dev/null; then
    _should_load_error_logging=1
    printf "[LIB_DEBUG] Centralized error logging: ENABLED (config setting)\n" >&2
else
    printf "[LIB_DEBUG] Centralized error logging: DISABLED (not enabled in config)\n" >&2
fi

# Load error logging if should be enabled
if [ "$_should_load_error_logging" = "1" ] && [ -f "$_rutos_lib_dir/rutos-error-logging.sh" ]; then
    printf "[LIB_DEBUG] Loading rutos-error-logging.sh...\n" >&2
    if . "$_rutos_lib_dir/rutos-error-logging.sh"; then
        printf "[LIB_DEBUG] ✓ rutos-error-logging.sh loaded successfully\n" >&2
        _RUTOS_ERROR_LOGGING_LOADED=1
    else
        printf "[LIB_DEBUG] ✗ FAILED to load rutos-error-logging.sh\n" >&2
        _RUTOS_ERROR_LOGGING_LOADED=0
    fi
elif [ "$_should_load_error_logging" = "1" ]; then
    printf "[LIB_DEBUG] rutos-error-logging.sh not found (will use basic error logging)\n" >&2
    _RUTOS_ERROR_LOGGING_LOADED=0
else
    printf "[LIB_DEBUG] Centralized error logging disabled, using basic logging only\n" >&2
    _RUTOS_ERROR_LOGGING_LOADED=0
fi

# Load optional compatibility module (for legacy script support)
if [ -f "$_rutos_lib_dir/rutos-compatibility.sh" ]; then
    printf "[LIB_DEBUG] Loading rutos-compatibility.sh...\n" >&2
    if . "$_rutos_lib_dir/rutos-compatibility.sh"; then
        printf "[LIB_DEBUG] ✓ rutos-compatibility.sh loaded successfully\n" >&2
        _RUTOS_COMPATIBILITY_LOADED=1
    else
        printf "[LIB_DEBUG] ✗ FAILED to load rutos-compatibility.sh\n" >&2
        _RUTOS_COMPATIBILITY_LOADED=0
    fi
else
    printf "[LIB_DEBUG] rutos-compatibility.sh not found (optional)\n" >&2
    _RUTOS_COMPATIBILITY_LOADED=0
fi

# Load optional data collection module (graceful degradation if missing)
if [ -f "$_rutos_lib_dir/rutos-data-collection.sh" ]; then
    printf "[LIB_DEBUG] Loading rutos-data-collection.sh...\n" >&2
    if . "$_rutos_lib_dir/rutos-data-collection.sh"; then
        printf "[LIB_DEBUG] ✓ rutos-data-collection.sh loaded successfully\n" >&2
        _RUTOS_DATA_COLLECTION_LOADED=1
    else
        printf "[LIB_DEBUG] ✗ FAILED to load rutos-data-collection.sh\n" >&2
        _RUTOS_DATA_COLLECTION_LOADED=0
    fi
else
    printf "[LIB_DEBUG] rutos-data-collection.sh not found (optional)\n" >&2
    # Stub functions if data collection module is not available
    collect_system_info() { printf "Data collection not available\n"; }
    collect_network_info() { printf "Network collection not available\n"; }
    collect_gps_info() { printf "GPS collection not available\n"; }
    collect_cellular_info() { printf "Cellular collection not available\n"; }
    _RUTOS_DATA_COLLECTION_LOADED=0
fi

printf "[LIB_DEBUG] All library modules loaded successfully\n" >&2

# ============================================================================
# RUTOS INITIALIZATION FUNCTION
# ============================================================================

# Main initialization function for RUTOS scripts
rutos_init() {
    script_name="${1:-$(basename "$0")}"
    script_version="${2:-unknown}"

    printf "[LIB_DEBUG] rutos_init called with script_name='%s', script_version='%s'\n" "$script_name" "$script_version" >&2

    printf "[LIB_DEBUG] Setting up logging levels...\n" >&2
    # Set up logging levels
    if command -v setup_logging_levels >/dev/null 2>&1; then
        setup_logging_levels
        printf "[LIB_DEBUG] ✓ Logging levels set up\n" >&2
    else
        printf "[LIB_DEBUG] ✗ setup_logging_levels function not found\n" >&2
    fi

    printf "[LIB_DEBUG] Setting up cleanup handlers...\n" >&2
    # Set up cleanup handlers
    if command -v setup_cleanup_handlers >/dev/null 2>&1; then
        setup_cleanup_handlers
        printf "[LIB_DEBUG] ✓ Cleanup handlers set up\n" >&2
    else
        printf "[LIB_DEBUG] ✗ setup_cleanup_handlers function not found\n" >&2
    fi

    printf "[LIB_DEBUG] Logging script initialization...\n" >&2
    # Log script initialization
    if command -v log_script_init >/dev/null 2>&1; then
        log_script_init "$script_name" "$script_version"
        printf "[LIB_DEBUG] ✓ Script initialization logged\n" >&2
    else
        printf "[LIB_DEBUG] ✗ log_script_init function not found\n" >&2
    fi

    # Validate RUTOS environment (unless in test mode)
    if [ "${SKIP_RUTOS_VALIDATION:-0}" != "1" ]; then
        validate_rutos_environment
    fi

    # Check for early test mode exit
    check_test_mode_exit

    # Export common variables for child processes
    export SCRIPT_NAME="$script_name"
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

    printf "[LIB_DEBUG] rutos_init_portable called with script_name='%s', script_version='%s'\n" "$script_name" "$script_version" >&2

    printf "[LIB_DEBUG] Setting SKIP_RUTOS_VALIDATION=1\n" >&2
    # Skip RUTOS environment validation
    SKIP_RUTOS_VALIDATION=1

    printf "[LIB_DEBUG] Calling rutos_init...\n" >&2
    if rutos_init "$script_name" "$script_version"; then
        printf "[LIB_DEBUG] ✓ rutos_init_portable completed successfully\n" >&2
        return 0
    else
        printf "[LIB_DEBUG] ✗ rutos_init_portable FAILED\n" >&2
        return 1
    fi
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
    printf "  Data Collection Module: %s\n" "${_RUTOS_DATA_COLLECTION_LOADED:-not loaded}"
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

    if [ "${_RUTOS_DATA_COLLECTION_LOADED:-0}" != "1" ]; then
        missing_modules="$missing_modules data-collection"
    fi

    if [ -n "$missing_modules" ]; then
        printf "ERROR: Missing RUTOS modules:%s\n" "$missing_modules" >&2
        return 1
    else
        return 0
    fi
}
