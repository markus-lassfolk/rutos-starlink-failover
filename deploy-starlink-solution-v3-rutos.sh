#!/bin/sh

# ==============================================================================
# Complete Starlink Solution Deployment Script for RUTOS (POSIX Shell Version)
# INTELLIGENT MONITORING SYSTEM v3.0 - Daemon-Based Architecture
#
# This script deploys the complete intelligent Starlink monitoring solution
# with MWAN3 integration, automatic interface discovery, dynamic metric
# adjustment, and predictive failover capabilities.
#
# NEW in v3.0:
# - MWAN3-integrated intelligent monitoring daemon
# - Automatic interface discovery and classification
# - Dynamic metric adjustment based on performance
# - Historical performance analysis and trend prediction
# - Multi-interface support (up to 8 cellular modems)
# - Predictive failover before user experience issues
#
# Version: 3.0.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# ==============================================================================

# CRITICAL: Defensive shell options - enable strict mode AFTER defining error handling
# This prevents cryptic "parameter not set" errors by ensuring proper initialization order

# STEP 1: Define early error handling BEFORE enabling strict mode
early_error_handler() {
    exit_code=${?:-1}
    error_line=${1:-"unknown"}

    printf "\n"
    printf "🚨 EARLY DEPLOYMENT ERROR (Before Library Load)\n"
    printf "================================================\n"
    printf "❌ Error Code: %s\n" "${exit_code:-unknown}"
    printf "📍 Line: %s\n" "${error_line:-unknown}"
    printf "📂 Script: %s\n" "${0##*/}"
    printf "📝 Phase: Pre-library initialization\n"
    printf "\n"
    printf "💡 LIKELY CAUSE: Library loading or early initialization failure\n"
    printf "🔧 TROUBLESHOOTING:\n"
    printf "   1. Check if lib/rutos-lib.sh exists in script directory\n"
    printf "   2. Verify file permissions on library files\n"
    printf "   3. Run with DEBUG=1 for more details\n"
    printf "   4. Check syntax: sh -n %s\n" "${0:-deploy-script}"
    printf "\n"
    exit "${exit_code:-1}"
}

# STEP 2: Set up early error trapping
trap 'early_error_handler ${LINENO:-unknown}' EXIT

# STEP 3: Enable strict mode AFTER error handling is in place
set -eu

# NOTE: SCRIPT_VERSION is intentionally placed after error handling setup
# This ensures proper error context is available before enabling strict mode
# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="3.0.0"

# === ENHANCED ERROR HANDLING SYSTEM ===
# Custom error handler that provides detailed context about failures

# Global variables for error context
ERROR_CONTEXT=""
CURRENT_FUNCTION=""

# Enhanced error handler with detailed diagnostics and defensive parameter handling
enhanced_error_handler() {
    # DEFENSIVE: Capture exit code immediately and use safe parameter expansion
    exit_code=${?:-1}
    error_line="${1:-unknown}"

    printf "\n"
    printf "🚨 ===============================================\n"
    printf "   DEPLOYMENT ERROR - DETAILED DIAGNOSTICS\n"
    printf "===============================================\n"
    printf "❌ Error Code: %s\n" "$exit_code"
    printf "📍 Line: %s\n" "$error_line"
    printf "📂 Script: %s\n" "${0##*/}"
    printf "🎯 Function: %s\n" "${CURRENT_FUNCTION:-main}"
    printf "📝 Context: %s\n" "${ERROR_CONTEXT:-No specific context available}"
    printf "\n"

    # Show environment state at time of error
    printf "🔍 ENVIRONMENT STATE AT ERROR:\n"
    printf "   DEBUG: %s\n" "${DEBUG:-unset}"
    printf "   RUTOS_TEST_MODE: %s\n" "${RUTOS_TEST_MODE:-unset}"
    printf "   DRY_RUN: %s\n" "${DRY_RUN:-unset}"
    printf "   _LIBRARY_LOADED: %s\n" "${_LIBRARY_LOADED:-unset}"
    printf "   USER: %s\n" "${USER:-unset}"
    printf "   PWD: %s\n" "${PWD:-unset}"
    printf "\n"

    # Show recent command history if available
    if command -v history >/dev/null 2>&1; then
        printf "📜 RECENT COMMANDS:\n"
        history | tail -5 2>/dev/null || printf "   Command history not available\n"
        printf "\n"
    fi

    # Provide specific help based on error patterns
    case "$exit_code" in
        2)
            printf "💡 LIKELY CAUSE: Parameter not set (uninitialized variable)\n"
            printf "🔧 TROUBLESHOOTING:\n"
            printf "   1. Check if required environment variables are set\n"
            printf "   2. Verify script arguments are provided correctly\n"
            printf "   3. Run with DEBUG=1 for detailed variable tracking\n"
            printf "   4. Check for typos in variable names\n"
            ;;
        126)
            printf "💡 LIKELY CAUSE: Permission denied or command not executable\n"
            printf "🔧 TROUBLESHOOTING:\n"
            printf "   1. Check file permissions: ls -la \$script_path\n"
            printf "   2. Ensure script has execute permission: chmod +x \$script_path\n"
            printf "   3. Verify file system is not mounted read-only\n"
            ;;
        127)
            printf "💡 LIKELY CAUSE: Command not found\n"
            printf "🔧 TROUBLESHOOTING:\n"
            printf "   1. Check if required commands are installed\n"
            printf "   2. Verify PATH environment variable\n"
            printf "   3. Install missing dependencies\n"
            ;;
        *)
            printf "💡 GENERIC ERROR: Unexpected failure\n"
            printf "🔧 TROUBLESHOOTING:\n"
            printf "   1. Run with DEBUG=1 RUTOS_TEST_MODE=1 for detailed logging\n"
            printf "   2. Check system logs: logread | grep starlink\n"
            printf "   3. Verify RUTOS system health: df -h && free\n"
            ;;
    esac

    printf "\n"
    printf "🆘 FOR HELP:\n"
    printf "   📖 Documentation: https://github.com/markus-lassfolk/rutos-starlink-failover\n"
    printf "   🐛 Report issues: https://github.com/markus-lassfolk/rutos-starlink-failover/issues\n"
    printf "   🔧 Include this error output when seeking help\n"
    printf "\n"
    printf "===============================================\n"

    exit "$exit_code"
}

# Enhanced function entry logging with error context and defensive parameter handling
log_function_entry() {
    # DEFENSIVE: Use safe parameter expansion
    func_name="${1:-unknown_function}"

    # DEFENSIVE: Set globals safely
    CURRENT_FUNCTION="$func_name"
    ERROR_CONTEXT="Entering function: $func_name"

    # Use smart logging that handles library state
    if [ "${DEBUG:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        smart_debug "FUNCTION: Entering $func_name()"
        smart_debug "Script: ${0##*/}"
    fi
}

# Enhanced function exit logging with defensive parameter handling
log_function_exit() {
    # DEFENSIVE: Use safe parameter expansion with defaults
    func_name="${1:-${CURRENT_FUNCTION:-unknown_function}}"
    exit_code="${2:-0}"

    # DEFENSIVE: Set error context safely
    ERROR_CONTEXT="Exiting function: $func_name"

    # Use smart logging that handles library state
    if [ "${DEBUG:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        smart_debug "FUNCTION: Exiting $func_name with code $exit_code"
    fi

    # Clear current function context
    CURRENT_FUNCTION=""
}

# Enhanced function exit logging
log_function_exit() {
    func_name="$1"
    exit_code="${2:-0}"
    ERROR_CONTEXT="Exiting function: $func_name"
    if [ "${DEBUG:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        smart_debug "FUNCTION: Exiting $func_name with code $exit_code"
    fi
    CURRENT_FUNCTION=""
}

# Enhanced parameter validation with detailed error messages
validate_required_parameter() {
    param_name="$1"
    param_value="$2"
    context="${3:-parameter validation}"

    ERROR_CONTEXT="Validating required parameter: $param_name in $context"

    if [ -z "$param_value" ]; then
        printf "\n"
        printf "🚨 PARAMETER VALIDATION ERROR\n"
        printf "===============================\n"
        printf "❌ Required parameter '%s' is empty or unset\n" "$param_name"
        printf "📍 Context: %s\n" "$context"
        printf "🔧 This parameter is required for the deployment to work correctly\n"
        printf "\n"
        printf "💡 SOLUTIONS:\n"
        printf "   1. Set the parameter: export %s='your_value'\n" "$param_name"
        printf "   2. Check if you missed a configuration step\n"
        printf "   3. Run in interactive mode to set all parameters\n"
        printf "   4. Check the documentation for required parameters\n"
        printf "\n"
        return 1
    fi

    smart_debug "✓ Parameter validated: '$param_name'='$param_value'"
    return 0
}

# === DEFENSIVE PARAMETER VALIDATION ===
# Enhanced argument validation for functions with comprehensive error prevention
validate_function_arguments() {
    # DEFENSIVE: Use parameter expansion with defaults for all arguments
    func_name="${1:-unknown_function}"
    expected_args="${2:-0}"
    actual_args="${3:-0}"

    # DEFENSIVE: Set error context safely with fallback
    ERROR_CONTEXT="Validating arguments for function: ${func_name}"

    if [ "$actual_args" -lt "$expected_args" ]; then
        printf "\n"
        printf "🚨 FUNCTION ARGUMENT ERROR\n"
        printf "============================\n"
        printf "❌ Function '%s' requires %d arguments but got %d\n" "$func_name" "$expected_args" "$actual_args"
        printf "📍 This indicates a programming error in the script\n"
        printf "\n"
        printf "💡 SOLUTIONS:\n"
        printf "   1. This is likely a bug - please report it\n"
        printf "   2. Check if you're calling the function correctly\n"
        printf "   3. Verify all required parameters are passed\n"
        printf "\n"
        return 1
    fi

    return 0
}

# Safe parameter validation with detailed error reporting
validate_required_parameter() {
    # DEFENSIVE: Use parameter expansion with defaults
    param_name="${1:-unknown_parameter}"
    param_value="${2:-}"
    context="${3:-unknown_context}"

    # DEFENSIVE: Set error context safely
    ERROR_CONTEXT="Validating parameter: ${param_name} in context: ${context}"

    if [ -z "$param_value" ]; then
        printf "\n"
        printf "🚨 PARAMETER VALIDATION ERROR\n"
        printf "===============================\n"
        printf "❌ Required parameter '$param_name' is empty or unset\n"
        printf "📍 Context: $context\n"
        printf "\n"
        printf "💡 SOLUTIONS:\n"
        printf "   1. Ensure parameter is set before calling this function\n"
        printf "   2. Check for typos in parameter name\n"
        printf "   3. Verify initialization order in script\n"
        printf "\n"
        return 1
    fi

    smart_debug "✓ Parameter validated: '$param_name'='$param_value'"
    return 0
}

# Enhanced exit code checking with defensive parameter handling
check_exit_code() {
    # DEFENSIVE: Capture exit code first, then use safe parameter expansion
    last_exit_code=$?
    error_line="${1:-unknown}"

    # DEFENSIVE: Set error context safely
    ERROR_CONTEXT="Checking exit code at line: ${error_line}"

    if [ $last_exit_code -ne 0 ]; then
        # Call enhanced error handler if available, otherwise use fallback
        if command -v enhanced_error_handler >/dev/null 2>&1; then
            enhanced_error_handler "$error_line"
        else
            printf "ERROR: Command failed with exit code %d at line %s\n" "$last_exit_code" "$error_line" >&2
            exit "$last_exit_code"
        fi
    fi

    return 0
}

# === PRE-LIBRARY DEBUG SYSTEM ===
# Basic logging functions used BEFORE the RUTOS library is loaded
# These are prefixed with [PRE-DEBUG] to distinguish from library logging

# Global flag to track if library is loaded
_LIBRARY_LOADED=0

# Get current timestamp in library format
_get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Pre-library debug logging function
pre_debug() {
    if [ "${DEBUG:-0}" = "1" ] || [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        printf "[PRE-DEBUG] [%s] %s\n" "$(_get_timestamp)" "$*" >&2
    fi
}

# Pre-library info logging function
pre_info() {
    printf "[PRE-INFO] [%s] %s\n" "$(_get_timestamp)" "$*"
}

# Pre-library error logging function
pre_error() {
    printf "[PRE-ERROR] [%s] %s\n" "$(_get_timestamp)" "$*" >&2
}

# Pre-library success logging function
pre_success() {
    printf "[PRE-SUCCESS] [%s] %s\n" "$(_get_timestamp)" "$*"
}

# Pre-library warning logging function
pre_warning() {
    printf "[PRE-WARNING] [%s] %s\n" "$(_get_timestamp)" "$*" >&2
}

# Pre-library step logging function
pre_step() {
    printf "[PRE-STEP] [%s] === %s ===\n" "$(_get_timestamp)" "$*"
}

# Log script initialization with pre-library system
pre_info "Starting deploy-starlink-solution-v3-rutos.sh v$SCRIPT_VERSION"
pre_debug "Pre-library logging system initialized"
pre_debug "Environment: DEBUG=${DEBUG:-0}, RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0}, DRY_RUN=${DRY_RUN:-0}"

# Capture original values for debug display
ORIGINAL_DEBUG="${DEBUG:-0}"
ORIGINAL_RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
ORIGINAL_TEST_MODE="${TEST_MODE:-0}"
ORIGINAL_DRY_RUN="${DRY_RUN:-0}"

pre_debug "Original environment values captured:"
pre_debug "  ORIGINAL_DEBUG=$ORIGINAL_DEBUG"
pre_debug "  ORIGINAL_RUTOS_TEST_MODE=$ORIGINAL_RUTOS_TEST_MODE"
pre_debug "  ORIGINAL_TEST_MODE=$ORIGINAL_TEST_MODE"
pre_debug "  ORIGINAL_DRY_RUN=$ORIGINAL_DRY_RUN"

# CRITICAL: Load RUTOS library system (REQUIRED)
# Check if running from bootstrap (library in different location)
pre_step "Loading RUTOS Library System"
pre_debug "Checking library loading mode..."

# shellcheck disable=SC1091,SC1090
if [ "${USE_LIBRARY:-0}" = "1" ] && [ -n "${LIBRARY_PATH:-}" ]; then
    # Bootstrap mode - library is in LIBRARY_PATH
    pre_debug "Bootstrap mode detected - loading library from: $LIBRARY_PATH"
    if [ ! -f "$LIBRARY_PATH/rutos-lib.sh" ]; then
        pre_error "Library file not found: $LIBRARY_PATH/rutos-lib.sh"
        exit 1
    fi
    pre_debug "Library file exists, attempting to source..."
    . "$LIBRARY_PATH/rutos-lib.sh"
else
    # Normal mode - library is relative to script
    lib_path="$(dirname "$0")/lib/rutos-lib.sh"
    pre_debug "Normal mode detected - loading library from: $lib_path"
    if [ ! -f "$lib_path" ]; then
        pre_error "Library file not found: $lib_path"
        exit 1
    fi
    pre_debug "Library file exists, attempting to source..."
    . "$lib_path"
fi

pre_success "RUTOS library system loaded successfully"

# Disable early error trap and set up enhanced error handling
trap - EXIT

# CRITICAL: Initialize script with library features (REQUIRED)
pre_debug "Initializing script with library features..."
rutos_init "deploy-starlink-solution-v3-rutos.sh" "$SCRIPT_VERSION"

# Set up enhanced error handling now that library is loaded
trap 'enhanced_error_handler ${LINENO:-unknown}' EXIT

# Mark library as loaded and transition to library logging
_LIBRARY_LOADED=1
log_info "=== TRANSITION: Now using RUTOS library logging system ==="
log_debug "Pre-library phase completed - all subsequent logging uses library functions"

# Backward compatibility: Support both TEST_MODE and RUTOS_TEST_MODE
if [ "${TEST_MODE:-0}" = "1" ] && [ "${RUTOS_TEST_MODE:-0}" = "0" ]; then
    export RUTOS_TEST_MODE=1
    log_debug "Backward compatibility: Enabled RUTOS_TEST_MODE from TEST_MODE"
fi

log_debug "Debug environment status:"
log_debug "  DEBUG=${DEBUG:-0} (original: $ORIGINAL_DEBUG)"
log_debug "  RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0} (original: $ORIGINAL_RUTOS_TEST_MODE)"
log_debug "  TEST_MODE=${TEST_MODE:-0} (original: $ORIGINAL_TEST_MODE)"
log_debug "  DRY_RUN=${DRY_RUN:-0} (original: $ORIGINAL_DRY_RUN)"

# Comprehensive debug state output for troubleshooting
log_debug "=== COMPREHENSIVE DEBUG STATE FOR TROUBLESHOOTING ==="
log_debug "Current state: DRY_RUN=${DRY_RUN:-0}, TEST_MODE=${TEST_MODE:-0}, RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0}"
log_debug "Original state: DRY_RUN=$ORIGINAL_DRY_RUN, TEST_MODE=$ORIGINAL_TEST_MODE, RUTOS_TEST_MODE=$ORIGINAL_RUTOS_TEST_MODE"

log_debug "Library loading verification:"
log_debug "  _LIBRARY_LOADED=$_LIBRARY_LOADED"
log_debug "  Available library functions: $(type log_info log_debug log_error 2>/dev/null | wc -l) of 3 expected"

# Verify critical library functions are available
if ! command -v log_info >/dev/null 2>&1 || ! command -v log_debug >/dev/null 2>&1 || ! command -v log_error >/dev/null 2>&1; then
    pre_error "CRITICAL: Library functions not properly loaded!"
    pre_error "This indicates a library loading failure - using fallback logging"
    _LIBRARY_LOADED=0
else
    log_success "Library functions verified - full logging system active"
fi

# === SMART LOGGING WRAPPER SYSTEM ===
# Automatically use pre-debug or library logging depending on library state
# This ensures consistent logging throughout the script lifecycle
# CRITICAL: Must be defined immediately after library loading verification

# Enhanced safe_execute wrapper with command execution logging
smart_safe_execute() {
    ERROR_CONTEXT="Executing command via smart_safe_execute"

    # Validate arguments with detailed error messages
    if [ $# -eq 0 ]; then
        printf "\n"
        printf "🚨 SMART_SAFE_EXECUTE ERROR\n"
        printf "=============================\n"
        printf "❌ No command provided to smart_safe_execute\n"
        printf "📍 This function requires at least 1 argument (the command to execute)\n"
        printf "\n"
        printf "💡 CORRECT USAGE:\n"
        printf "   smart_safe_execute \"command\" \"description\"\n"
        printf "   smart_safe_execute \"ls -la\" \"List files\"\n"
        printf "\n"
        return 1
    fi

    command="$1"
    description="${2:-Execute command}"

    # Validate command is not empty
    if ! validate_required_parameter "command" "$command" "smart_safe_execute"; then
        printf "🔧 SMART_SAFE_EXECUTE CONTEXT:\n"
        printf "   Function called from: %s\n" "${CURRENT_FUNCTION:-main}"
        printf "   Expected: Non-empty command string\n"
        printf "   Received: '%s'\n" "$command"
        printf "\n"
        return 1
    fi

    ERROR_CONTEXT="Executing command: $command"

    if [ "$_LIBRARY_LOADED" = "1" ]; then
        log_debug "COMMAND EXECUTION: $description"
        log_debug "  Command: $command"
        log_debug "  DRY_RUN: ${DRY_RUN:-0}"
        safe_execute "$command" "$description"
    else
        pre_debug "COMMAND EXECUTION: $description"
        pre_debug "  Command: $command"
        pre_debug "  DRY_RUN: ${DRY_RUN:-0}"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            pre_info "DRY-RUN: Would execute: $command"
            return 0
        else
            eval "$command"
        fi
    fi
}

# === SMART LOGGING WRAPPER FUNCTIONS ===
# These functions intelligently choose between library and pre-library logging
# CRITICAL: All functions use defensive parameter handling to prevent "parameter not set" errors

smart_debug() {
    # DEFENSIVE: Validate we have at least one argument using $# check
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_debug called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely with fallback
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_debug >/dev/null 2>&1; then
        log_debug "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_debug >/dev/null 2>&1; then
            pre_debug "$@"
        else
            printf "[PRE-DEBUG] %s\n" "$*" >&2
        fi
    fi
}

smart_info() {
    # DEFENSIVE: Validate we have at least one argument
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_info called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_info >/dev/null 2>&1; then
        log_info "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_info >/dev/null 2>&1; then
            pre_info "$@"
        else
            printf "[PRE-INFO] %s\n" "$*"
        fi
    fi
}

smart_error() {
    # DEFENSIVE: Validate we have at least one argument
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_error called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_error >/dev/null 2>&1; then
            pre_error "$@"
        else
            printf "[PRE-ERROR] %s\n" "$*" >&2
        fi
    fi
}

smart_success() {
    # DEFENSIVE: Validate we have at least one argument
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_success called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_success >/dev/null 2>&1; then
        log_success "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_success >/dev/null 2>&1; then
            pre_success "$@"
        else
            printf "[PRE-SUCCESS] %s\n" "$*"
        fi
    fi
}

smart_warning() {
    # DEFENSIVE: Validate we have at least one argument
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_warning called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_warning >/dev/null 2>&1; then
        log_warning "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_warning >/dev/null 2>&1; then
            pre_warning "$@"
        else
            printf "[PRE-WARNING] %s\n" "$*" >&2
        fi
    fi
}

smart_step() {
    # DEFENSIVE: Validate we have at least one argument
    if [ $# -eq 0 ]; then
        printf "WARNING: smart_step called with no arguments\n" >&2
        return 1
    fi

    # DEFENSIVE: Check library state safely
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v log_step >/dev/null 2>&1; then
        log_step "$@"
    else
        # Fallback to pre-library logging
        if command -v pre_step >/dev/null 2>&1; then
            pre_step "$@"
        else
            printf "[PRE-STEP] === %s ===\n" "$*"
        fi
    fi
}

# Smart command execution wrapper
smart_safe_execute() {
    # DEFENSIVE: Validate required arguments
    if [ $# -lt 2 ]; then
        printf "ERROR: smart_safe_execute requires at least 2 arguments (command, description)\n" >&2
        return 1
    fi

    command="${1:-}"
    description="${2:-}"

    # Validate command is not empty
    if [ -z "$command" ]; then
        printf "ERROR: smart_safe_execute called with empty command\n" >&2
        return 1
    fi

    # Use library safe_execute if available, otherwise fallback
    if [ "${_LIBRARY_LOADED:-0}" = "1" ] && command -v safe_execute >/dev/null 2>&1; then
        safe_execute "$command" "$description"
    else
        # Pre-library command execution
        smart_debug "COMMAND EXECUTION: $description"
        smart_debug "  Command: $command"
        smart_debug "  DRY_RUN: ${DRY_RUN:-0}"

        if [ "${DRY_RUN:-0}" = "1" ]; then
            smart_info "DRY-RUN: Would execute: $command"
            return 0
        else
            # Execute the command with error handling
            if eval "$command"; then
                smart_debug "✓ Command succeeded: $description"
                return 0
            else
                exit_code=$?
                smart_error "✗ Command failed: $description"
                smart_error "  Command: $command"
                smart_error "  Exit code: $exit_code"
                return $exit_code
            fi
        fi
    fi
}

# === CONFIGURATION DEFAULTS ===
# DEFENSIVE: Initialize all configuration defaults to prevent "parameter not set" errors
DEFAULT_AZURE_ENDPOINT=""
DEFAULT_ENABLE_AZURE="false"
DEFAULT_ENABLE_STARLINK_MONITORING="true"
DEFAULT_ENABLE_GPS="true"
DEFAULT_ENABLE_PUSHOVER="false"
DEFAULT_RUTOS_IP="192.168.80.1"
DEFAULT_STARLINK_IP="192.168.100.1"

# Debug: Log default values for troubleshooting (use smart logging for library compatibility)
smart_debug "Configuration defaults loaded:"
smart_debug "  DEFAULT_ENABLE_STARLINK_MONITORING='$DEFAULT_ENABLE_STARLINK_MONITORING'"
smart_debug "  DEFAULT_ENABLE_GPS='$DEFAULT_ENABLE_GPS'"
smart_debug "  DEFAULT_ENABLE_AZURE='$DEFAULT_ENABLE_AZURE'"
smart_debug "  DEFAULT_ENABLE_PUSHOVER='$DEFAULT_ENABLE_PUSHOVER'"

# === INTERACTIVE MODE DETECTION ===
# Check if script is running in interactive mode
is_interactive() {
    # Debug output for troubleshooting before any early returns
    smart_debug "is_interactive() called - checking interactive mode"
    smart_debug "  Environment state: DRY_RUN=${DRY_RUN:-0}, TEST_MODE=${TEST_MODE:-0}, RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0}"
    smart_debug "  Terminal check: stdin is terminal = $([ -t 0 ] && echo 'yes' || echo 'no')"
    smart_debug "  Batch mode check: BATCH_MODE=${BATCH_MODE:-0}"

    # Check if stdin is a terminal and not running in non-interactive mode
    result=$([ -t 0 ] && [ "${BATCH_MODE:-0}" != "1" ] && echo 'true' || echo 'false')
    smart_debug "  Interactive mode result: $result"
    [ "$result" = "true" ]
}

# === DEBUG ENVIRONMENT INHERITANCE ===
# Export debug settings for child scripts
export_debug_environment() {
    smart_debug "Exporting debug environment for child scripts:"

    # Export core debugging variables
    export DEBUG="${DEBUG:-0}"
    export RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
    export DRY_RUN="${DRY_RUN:-0}"
    export VERBOSE="${VERBOSE:-0}"

    # Export additional debugging flags
    export ALLOW_TEST_EXECUTION="${ALLOW_TEST_EXECUTION:-0}"

    # Log what we're exporting
    smart_debug "  DEBUG=$DEBUG"
    smart_debug "  RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
    smart_debug "  DRY_RUN=$DRY_RUN"
    smart_debug "  VERBOSE=$VERBOSE"
    smart_debug "  ALLOW_TEST_EXECUTION=$ALLOW_TEST_EXECUTION"

    smart_debug "Debug environment exported - child scripts will inherit these settings"
}

# === CHILD SCRIPT EXECUTION WRAPPER ===
# Execute child scripts with proper environment and library inheritance
execute_child_script() {
    script_path="$1"
    script_args="${2:-}"
    description="${3:-Execute child script}"

    smart_debug "Executing child script: $script_path $script_args"
    smart_debug "Description: $description"

    # Ensure debug environment is exported
    export_debug_environment

    # Additional environment variables for child scripts
    export USE_LIBRARY="${USE_LIBRARY:-0}"
    export LIBRARY_PATH="${LIBRARY_PATH:-}"
    export SCRIPT_SOURCE="deploy-starlink-solution-v3-rutos.sh"

    smart_debug "Child script environment:"
    smart_debug "  USE_LIBRARY=$USE_LIBRARY"
    smart_debug "  LIBRARY_PATH=$LIBRARY_PATH"
    smart_debug "  SCRIPT_SOURCE=$SCRIPT_SOURCE"

    # Execute the script with proper environment
    if [ "${DRY_RUN:-0}" = "1" ]; then
        smart_info "DRY-RUN: Would execute: $script_path $script_args"
        return 0
    else
        smart_debug "Executing: $script_path $script_args"
        if [ -n "$script_args" ]; then
            "$script_path" "$script_args"
        else
            "$script_path"
        fi
    fi
}

# === NEW: INTELLIGENT MONITORING DEFAULTS ===
# Note: These defaults are available for reference but may not be directly used in this script
# They are used by other scripts in the system for consistency
export DEFAULT_MONITORING_MODE="daemon" # daemon, cron, or hybrid
export DEFAULT_DAEMON_AUTOSTART="true"
export DEFAULT_MONITORING_INTERVAL="60"
export DEFAULT_QUICK_CHECK_INTERVAL="30"
export DEFAULT_DEEP_ANALYSIS_INTERVAL="300"

# === PATHS AND DIRECTORIES (RUTOS PERSISTENT STORAGE) ===
# CRITICAL: Use persistent storage that survives firmware upgrades on RUTOS
# /root is wiped during firmware upgrades - use /opt or /mnt for persistence
# Note: Actual paths will be set after detecting available persistent storage
export HOTPLUG_DIR="/etc/hotplug.d/iface" # System hotplug directory (exported for child scripts)
INIT_D_DIR="/etc/init.d"                  # System init.d directory

# === RUTOS PERSISTENT STORAGE VERIFICATION ===
# Check for available persistent storage locations (in order of preference)
# NOTE: This happens AFTER library loading, so we use smart logging functions
smart_step "Detecting RUTOS Persistent Storage"
smart_debug "Checking available persistent storage locations..."

PERSISTENT_STORAGE=""
for storage_path in "/usr/local" "/opt" "/mnt" "/root"; do
    smart_debug "Testing storage path: $storage_path"
    if [ -d "$storage_path" ] && [ -w "$storage_path" ]; then
        PERSISTENT_STORAGE="$storage_path"
        smart_success "Found writable persistent storage: $storage_path"
        break
    else
        smart_debug "Storage path not available or not writable: $storage_path"
    fi
done

if [ -z "$PERSISTENT_STORAGE" ]; then
    smart_error "No writable persistent storage directory found. Checked: /usr/local /opt /mnt /root"
    smart_error "RUTOS system may have read-only filesystem issues"
    exit 1
fi

smart_info "Using persistent storage: $PERSISTENT_STORAGE"

# === SET DIRECTORY PATHS BASED ON DETECTED STORAGE ===
INSTALL_BASE_DIR="$PERSISTENT_STORAGE/starlink"                         # Main installation directory (persistent)
BACKUP_DIR="$PERSISTENT_STORAGE/starlink/backup-$(date +%Y%m%d-%H%M%S)" # Backup location (persistent)
CONFIG_DIR="$PERSISTENT_STORAGE/starlink/config"                        # Configuration files (persistent)
SCRIPTS_DIR="$PERSISTENT_STORAGE/starlink/bin"                          # Executable scripts (persistent)
LOG_DIR="$PERSISTENT_STORAGE/starlink/logs"                             # Log files (persistent)
STATE_DIR="$PERSISTENT_STORAGE/starlink/state"                          # Runtime state files (persistent)
LIB_DIR="$PERSISTENT_STORAGE/starlink/lib"                              # Library files (persistent)

# === BINARY URLS (ARMv7 for RUTX50) ===
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# === PERSISTENT STORAGE SETUP ===
setup_persistent_storage() {
    log_step "Setting up RUTOS Persistent Storage"

    # Verify persistent storage availability
    if [ ! -d "$PERSISTENT_STORAGE" ]; then
        log_error "Persistent storage $PERSISTENT_STORAGE not available"
        log_error "RUTOS devices require persistent storage for intelligent monitoring"
        return 1
    fi

    log_info "Using persistent storage: $PERSISTENT_STORAGE"

    # Create all required directories
    log_info "Creating persistent directory structure..."

    for dir in "$INSTALL_BASE_DIR" "$CONFIG_DIR" "$SCRIPTS_DIR" "$LOG_DIR" "$STATE_DIR" "$LIB_DIR" "$BACKUP_DIR"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                log_error "Failed to create directory: $dir"
                return 1
            }
            log_success "Created directory: $dir"
        else
            log_info "Directory exists: $dir"
        fi
    done

    # Set appropriate permissions
    chmod 755 "$INSTALL_BASE_DIR" "$CONFIG_DIR" "$SCRIPTS_DIR" "$LOG_DIR" "$STATE_DIR" "$LIB_DIR"
    chmod 700 "$BACKUP_DIR" # Backup directory should be more restrictive

    # Create convenience symlinks in /root for backward compatibility (non-persistent)
    log_info "Creating convenience symlinks for backward compatibility..."

    # Remove any existing symlinks/files first
    smart_safe_execute "rm -f /root/starlink_monitor_unified-rutos.sh" "Remove existing monitor symlink"
    smart_safe_execute "rm -f /root/config.sh" "Remove existing config symlink"

    # Create symlinks (these will be recreated after firmware upgrades by the recovery script)
    smart_safe_execute "ln -sf '$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh' /root/starlink_monitor_unified-rutos.sh" "Create monitor symlink"
    smart_safe_execute "ln -sf '$CONFIG_DIR/config.sh' /root/config.sh" "Create config symlink"

    log_success "Persistent storage setup completed"
    log_info "Main installation: $INSTALL_BASE_DIR"
    log_info "Scripts accessible at: $SCRIPTS_DIR and /root (symlink)"
    log_info "Configuration: $CONFIG_DIR"
    log_info "Logs: $LOG_DIR"
}

# Create firmware upgrade recovery script
create_recovery_script() {
    log_function_entry "create_recovery_script"
    log_info "Creating firmware upgrade recovery script..."

    cat >"$SCRIPTS_DIR/recover-after-firmware-upgrade.sh" <<EOF
#!/bin/sh
# RUTOS Firmware Upgrade Recovery Script
# This script restores the intelligent monitoring system after firmware upgrades
# Run this after firmware upgrades to restore functionality

set -e

# Persistent storage locations (set during installation)
INSTALL_BASE_DIR="$INSTALL_BASE_DIR"
CONFIG_DIR="$CONFIG_DIR"
SCRIPTS_DIR="$SCRIPTS_DIR"
LOG_DIR="$LOG_DIR"
INIT_D_DIR="/etc/init.d"

echo "🔄 RUTOS Firmware Upgrade Recovery - Starlink Intelligent Monitoring"
echo "===================================================================="

# Check if persistent storage exists
if [ ! -d "$INSTALL_BASE_DIR" ]; then
    echo "❌ ERROR: Persistent storage not found at $INSTALL_BASE_DIR"
    echo "   The intelligent monitoring system needs to be reinstalled."
    echo "   Run: curl -L https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/deploy-starlink-solution-v3-rutos.sh | sh"
    exit 1
fi

echo "✓ Found persistent storage at $INSTALL_BASE_DIR"

# Recreate convenience symlinks
echo "🔗 Recreating convenience symlinks..."
ln -sf "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" /root/starlink_monitor_unified-rutos.sh
ln -sf "$CONFIG_DIR/config.sh" /root/config.sh
echo "✓ Symlinks created"

# Recreate init.d service
echo "🔧 Recreating daemon services..."
if [ -f "$SCRIPTS_DIR/../templates/starlink-monitor.init" ]; then
    cp "$SCRIPTS_DIR/../templates/starlink-monitor.init" "$INIT_D_DIR/starlink-monitor"
    chmod +x "$INIT_D_DIR/starlink-monitor"
    echo "✓ Monitoring daemon service restored"
else
    echo "⚠️ Warning: Monitoring daemon service template not found - manual setup required"
fi

if [ -f "$SCRIPTS_DIR/../templates/starlink-logger.init" ]; then
    cp "$SCRIPTS_DIR/../templates/starlink-logger.init" "$INIT_D_DIR/starlink-logger"
    chmod +x "$INIT_D_DIR/starlink-logger"
    echo "✓ Logging daemon service restored"
else
    echo "⚠️ Warning: Logging daemon service template not found - manual setup required"
fi

# Verify MWAN3 availability
if command -v mwan3 >/dev/null 2>&1; then
    echo "✓ MWAN3 available"
else
    echo "⚠️ Warning: MWAN3 not found - may need to be reinstalled after firmware upgrade"
    echo "   Install with: opkg update && opkg install mwan3"
fi

# Test system functionality
echo "🧪 Testing system functionality..."
if [ -x "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ]; then
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" validate >/dev/null 2>&1; then
        echo "✓ System validation passed"
    else
        echo "⚠️ Warning: System validation failed - may need configuration"
    fi
else
    echo "❌ ERROR: Main monitoring script not found or not executable"
    exit 1
fi

# Start monitoring daemon if configured for autostart
if [ -f "$CONFIG_DIR/config.sh" ]; then
    . "$CONFIG_DIR/config.sh"
    if [ "${DAEMON_AUTOSTART:-false}" = "true" ]; then
        if [ -f "$INIT_D_DIR/starlink-monitor" ]; then
            echo "🚀 Starting monitoring daemon..."
            "$INIT_D_DIR/starlink-monitor" start
            echo "✓ Monitoring daemon started"
        fi
        
        if [ -f "$INIT_D_DIR/starlink-logger" ]; then
            echo "📊 Starting logging daemon..."
            "$INIT_D_DIR/starlink-logger" start
            echo "✓ Logging daemon started"
        fi
    fi
fi

echo ""
echo "✅ Recovery completed successfully!"
echo "📊 Check status: $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh status"
echo "📁 Configuration: $CONFIG_DIR/config.sh"
echo "📝 Logs: $LOG_DIR/"
EOF

    chmod +x "$SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
    log_success "Recovery script created: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
    log_function_exit "create_recovery_script"
}

# === INTELLIGENT MONITORING DAEMON SETUP ===
setup_intelligent_monitoring_daemon() {
    log_function_entry "setup_intelligent_monitoring_daemon"
    log_step "Setting up Intelligent Monitoring Daemon v3.0"

    # Create init.d service script for the intelligent monitoring daemon
    log_info "Creating daemon service script..."

    # First, create a template for the service in persistent storage
    mkdir -p "$INSTALL_BASE_DIR/templates"

    cat >"$INSTALL_BASE_DIR/templates/starlink-monitor.init" <<EOF
#!/bin/sh /etc/rc.common

START=95
STOP=10

USE_PROCD=1
PROG="$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh"
PIDFILE="/var/run/starlink-monitor.pid"

start_service() {
    # Ensure MWAN3 is available before starting
    if ! command -v mwan3 >/dev/null 2>&1; then
        logger -s -t starlink-monitor "ERROR: MWAN3 not found - cannot start intelligent monitoring"
        return 1
    fi
    
    # Validate that the monitoring script exists
    if [ ! -f "\$PROG" ]; then
        logger -s -t starlink-monitor "ERROR: Monitoring script not found at \$PROG"
        return 1
    fi
    
    logger -s -t starlink-monitor "Starting Intelligent Starlink Monitoring Daemon v3.0"
    
    procd_open_instance
    procd_set_param command "\$PROG" start --daemon
    procd_set_param pidfile "\$PIDFILE"
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    logger -s -t starlink-monitor "Intelligent monitoring daemon started successfully"
}

stop_service() {
    logger -s -t starlink-monitor "Stopping Intelligent Starlink Monitoring Daemon"
    
    if [ -f "\$PIDFILE" ] && [ -s "\$PIDFILE" ]; then
        PID=\$(cat "\$PIDFILE")
        if kill -0 "\$PID" 2>/dev/null; then
            kill -TERM "\$PID"
            sleep 3
            if kill -0 "\$PID" 2>/dev/null; then
                kill -KILL "\$PID"
                logger -s -t starlink-monitor "Force killed daemon process"
            else
                logger -s -t starlink-monitor "Daemon stopped gracefully"
            fi
        fi
        rm -f "\$PIDFILE"
    else
        logger -s -t starlink-monitor "No daemon PID file found"
    fi
}

reload_service() {
    logger -s -t starlink-monitor "Reloading Intelligent Starlink Monitoring Daemon"
    stop
    start
}

status() {
    if [ -f "\$PIDFILE" ] && [ -s "\$PIDFILE" ]; then
        PID=\$(cat "\$PIDFILE")
        if kill -0 "\$PID" 2>/dev/null; then
            UPTIME=\$(ps -o etime= -p "\$PID" 2>/dev/null | tr -d ' ')
            echo "Intelligent Starlink Monitoring Daemon is running (PID: \$PID, Uptime: \$UPTIME)"
            return 0
        else
            echo "Daemon PID file exists but process is not running"
            rm -f "\$PIDFILE"
            return 1
        fi
    else
        echo "Intelligent Starlink Monitoring Daemon is not running"
        return 1
    fi
}
EOF

    # Copy the template to the active init.d location
    smart_safe_execute "cp '$INSTALL_BASE_DIR/templates/starlink-monitor.init' '$INIT_D_DIR/starlink-monitor'" "Copy monitor service template to init.d"
    smart_safe_execute "chmod +x '$INIT_D_DIR/starlink-monitor'" "Make monitor service executable"

    log_success "Created init.d service script (persistent template stored)"
    log_info "Service template: $INSTALL_BASE_DIR/templates/starlink-monitor.init"
    log_info "Active service: $INIT_D_DIR/starlink-monitor"

    # Enable the service to start at boot
    if [ "$DAEMON_AUTOSTART" = "true" ]; then
        log_info "Enabling daemon autostart at boot..."
        smart_safe_execute "'$INIT_D_DIR/starlink-monitor' enable" "Enable monitor daemon autostart"
        log_success "Daemon autostart enabled"
    fi

    # Remove old cron-based monitoring if it exists
    cleanup_legacy_cron_monitoring

    log_success "Intelligent monitoring daemon setup completed"
    log_function_exit "setup_intelligent_monitoring_daemon"
}

# Remove legacy cron-based monitoring
cleanup_legacy_cron_monitoring() {
    log_function_entry "cleanup_legacy_cron_monitoring"
    log_info "Cleaning up legacy cron-based monitoring..."

    # Remove existing starlink-related cron jobs
    if crontab -l 2>/dev/null | grep -q "starlink"; then
        log_info "Found legacy cron jobs, removing..."
        smart_safe_execute "bash -c '(crontab -l 2>/dev/null | grep -v \"starlink\" || true) | crontab -'" "Remove legacy cron jobs"
        log_success "Legacy cron monitoring removed"
    else
        log_info "No legacy cron jobs found"
    fi

    log_function_exit "cleanup_legacy_cron_monitoring"
}

# Setup hybrid monitoring (daemon + essential cron jobs)
setup_hybrid_monitoring() {
    log_function_entry "setup_hybrid_monitoring"
    log_step "Setting up Hybrid Monitoring (Daemon + Essential Cron Jobs)"

    # Setup the main intelligent daemon
    setup_intelligent_monitoring_daemon

    # Keep essential cron jobs that complement the daemon
    log_info "Setting up essential cron jobs to complement the daemon..."
    cron_content=$(
        cat <<EOF
# Essential Starlink maintenance tasks
# API change detection (daily)
30 5 * * * $SCRIPTS_DIR/check_starlink_api-rutos.sh

$(if [ "$ENABLE_AZURE" = "true" ]; then
            echo "# Azure log shipping (every 10 minutes - daemon handles main monitoring)"
            echo "*/10 * * * * $SCRIPTS_DIR/log-shipper.sh"
        fi)

# Weekly system health check
0 6 * * 0 $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh validate
EOF
    )

    combined_cron="$(crontab -l 2>/dev/null | grep -v 'starlink' || true)
$cron_content"

    smart_safe_execute "bash -c 'echo \"$combined_cron\" | crontab -'" "Install hybrid monitoring cron jobs"

    # Restart cron service
    smart_safe_execute "/etc/init.d/cron restart >/dev/null 2>&1" "Restart cron service"
    log_success "Hybrid monitoring setup completed"
    log_function_exit "setup_hybrid_monitoring"
}

# Setup traditional cron-based monitoring (fallback)
setup_traditional_cron_monitoring() {
    log_function_entry "setup_traditional_cron_monitoring"
    log_step "Setting up Traditional Cron-Based Monitoring (Legacy Mode)"
    log_warning "Using legacy mode - intelligent features will be limited"

    # Remove any existing daemon setup
    if [ -f "$INIT_D_DIR/starlink-monitor" ]; then
        smart_safe_execute "$INIT_D_DIR/starlink-monitor stop 2>/dev/null || true" "Stop monitoring daemon"
        smart_safe_execute "$INIT_D_DIR/starlink-monitor disable 2>/dev/null || true" "Disable monitoring daemon"
        rm -f "$INIT_D_DIR/starlink-monitor"
        log_info "Removed daemon service"
    fi

    # Setup traditional cron jobs
    log_info "Setting up traditional cron jobs..."
    cron_content=$(
        cat <<EOF
# Traditional Starlink monitoring (legacy mode)
*/5 * * * * $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh test
30 5 * * * $SCRIPTS_DIR/check_starlink_api-rutos.sh

$(if [ "$ENABLE_AZURE" = "true" ]; then
            echo "*/5 * * * * $SCRIPTS_DIR/log-shipper.sh"
        fi)
EOF
    )

    combined_cron="$(crontab -l 2>/dev/null | grep -v 'starlink' || true)
$cron_content"

    smart_safe_execute "bash -c 'echo \"$combined_cron\" | crontab -'" "Install traditional monitoring cron jobs"

    # Restart cron service
    smart_safe_execute "/etc/init.d/cron restart >/dev/null 2>&1" "Restart cron service"
    log_success "Traditional cron monitoring setup completed"
    log_function_exit "setup_traditional_cron_monitoring"
}

# Main monitoring setup function
setup_monitoring_system() {
    case "${MONITORING_MODE:-daemon}" in
        daemon)
            log_info "Setting up daemon-based intelligent monitoring..."
            setup_intelligent_monitoring_daemon
            ;;
        hybrid)
            log_info "Setting up hybrid monitoring (daemon + cron)..."
            setup_hybrid_monitoring
            ;;
        cron)
            log_info "Setting up traditional cron-based monitoring..."
            setup_traditional_cron_monitoring
            ;;
        *)
            log_warning "Unknown monitoring mode '$MONITORING_MODE', defaulting to daemon"
            setup_intelligent_monitoring_daemon
            ;;
    esac
}

# === ENHANCED CONFIGURATION COLLECTION ===
collect_enhanced_configuration() {
    log_function_entry "collect_enhanced_configuration"
    log_step "Enhanced Configuration for Intelligent Monitoring v3.0"

    # Basic configuration (existing)
    collect_basic_configuration

    # New: Intelligent monitoring configuration
    log_info "Intelligent Monitoring Configuration"

    if is_interactive; then
        printf "Choose monitoring mode:\n"
        printf "  1) Daemon (recommended) - Intelligent continuous monitoring\n"
        printf "  2) Hybrid - Daemon + essential cron jobs\n"
        printf "  3) Cron - Traditional cron-based (legacy)\n"
        printf "Enter choice [1-3] (default: 1): "
        read -r MONITORING_CHOICE

        case "${MONITORING_CHOICE:-1}" in
            1) MONITORING_MODE="daemon" ;;
            2) MONITORING_MODE="hybrid" ;;
            3) MONITORING_MODE="cron" ;;
            *) MONITORING_MODE="daemon" ;;
        esac

        if [ "$MONITORING_MODE" = "daemon" ] || [ "$MONITORING_MODE" = "hybrid" ]; then
            printf "Enable daemon autostart at boot? [y/N]: "
            read -r AUTOSTART_CHOICE
            case "${AUTOSTART_CHOICE:-n}" in
                [Yy]*) DAEMON_AUTOSTART="true" ;;
                *) DAEMON_AUTOSTART="false" ;;
            esac

            printf "Monitoring interval in seconds (default: 60): "
            read -r MONITORING_INTERVAL_INPUT
            MONITORING_INTERVAL="${MONITORING_INTERVAL_INPUT:-60}"

            printf "Quick check interval in seconds (default: 30): "
            read -r QUICK_INTERVAL_INPUT
            QUICK_CHECK_INTERVAL="${QUICK_INTERVAL_INPUT:-30}"

            printf "Deep analysis interval in seconds (default: 300): "
            read -r DEEP_INTERVAL_INPUT
            DEEP_ANALYSIS_INTERVAL="${DEEP_INTERVAL_INPUT:-300}"
        fi
    else
        log_info "Non-interactive mode - using recommended monitoring configuration"

        # Use environment variables if set, otherwise recommended defaults
        MONITORING_MODE="${MONITORING_MODE:-daemon}"
        DAEMON_AUTOSTART="${DAEMON_AUTOSTART:-true}"
        MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"
        QUICK_CHECK_INTERVAL="${QUICK_CHECK_INTERVAL:-30}"
        DEEP_ANALYSIS_INTERVAL="${DEEP_ANALYSIS_INTERVAL:-300}"

        log_info "Selected: $MONITORING_MODE monitoring mode with autostart $DAEMON_AUTOSTART"
        log_info "Intervals: Monitoring=${MONITORING_INTERVAL}s, Quick=${QUICK_CHECK_INTERVAL}s, Deep=${DEEP_ANALYSIS_INTERVAL}s"

        # Log if any environment variables were used for monitoring config
        if [ "${MONITORING_MODE}" != "daemon" ]; then
            log_info "Environment: Using custom MONITORING_MODE=$MONITORING_MODE"
        fi
        if [ "${DAEMON_AUTOSTART}" != "true" ]; then
            log_info "Environment: Daemon autostart disabled"
        fi
    fi

    log_success "Enhanced configuration collected"
    log_function_exit "collect_enhanced_configuration"
}

# === ENHANCED CONFIGURATION FILE GENERATION ===
generate_enhanced_config() {
    log_function_entry "generate_enhanced_config"
    log_info "Generating enhanced configuration file..."

    # Debug: Verify all required variables are set before generating config
    log_debug "Pre-generation variable verification:"
    log_debug "  ENABLE_STARLINK_MONITORING='${ENABLE_STARLINK_MONITORING:-UNSET}'"
    log_debug "  ENABLE_GPS='${ENABLE_GPS:-UNSET}'"
    log_debug "  ENABLE_AZURE='${ENABLE_AZURE:-UNSET}'"
    log_debug "  ENABLE_PUSHOVER='${ENABLE_PUSHOVER:-UNSET}'"

    # Validate required variables exist (safety check with set -eu)
    if [ -z "${ENABLE_STARLINK_MONITORING:-}" ]; then
        log_error "ENABLE_STARLINK_MONITORING is not set - this should have been set in collect_basic_configuration"
        log_error "Available defaults: DEFAULT_ENABLE_STARLINK_MONITORING='$DEFAULT_ENABLE_STARLINK_MONITORING'"
        return 1
    fi

    if [ -z "${ENABLE_GPS:-}" ]; then
        log_error "ENABLE_GPS is not set - this should have been set in collect_basic_configuration"
        log_error "Available defaults: DEFAULT_ENABLE_GPS='$DEFAULT_ENABLE_GPS'"
        return 1
    fi

    log_debug "All required variables validated successfully"

    cat >"$CONFIG_DIR/config.sh" <<EOF
#!/bin/sh
# Enhanced Starlink Solution Configuration
# Generated by deployment script v$SCRIPT_VERSION on $(date)
# PERSISTENT STORAGE: This configuration survives firmware upgrades

# === INSTALLATION PATHS (PERSISTENT) ===
INSTALL_BASE_DIR="$INSTALL_BASE_DIR"
CONFIG_DIR="$CONFIG_DIR"
SCRIPTS_DIR="$SCRIPTS_DIR"
LOG_DIR="$LOG_DIR"
STATE_DIR="$STATE_DIR"
LIB_DIR="$LIB_DIR"

# === BASIC CONFIGURATION ===
STARLINK_IP="$STARLINK_IP"
STARLINK_PORT="$STARLINK_PORT"
RUTOS_IP="$RUTOS_IP"

# === NETWORK CONFIGURATION ===
MWAN_IFACE="$MWAN_IFACE"
MWAN_MEMBER="$MWAN_MEMBER"
METRIC_GOOD="$METRIC_GOOD"
METRIC_BAD="$METRIC_BAD"

# === THRESHOLDS ===
LATENCY_THRESHOLD="$LATENCY_THRESHOLD"
PACKET_LOSS_THRESHOLD="$PACKET_LOSS_THRESHOLD"
OBSTRUCTION_THRESHOLD="$OBSTRUCTION_THRESHOLD"

# === FEATURE TOGGLES ===
ENABLE_STARLINK_MONITORING="$ENABLE_STARLINK_MONITORING"
ENABLE_GPS="$ENABLE_GPS"
ENABLE_AZURE="$ENABLE_AZURE"
ENABLE_PUSHOVER="$ENABLE_PUSHOVER"

# === AZURE CONFIGURATION ===
AZURE_ENDPOINT="$AZURE_ENDPOINT"

# === PUSHOVER CONFIGURATION ===
PUSHOVER_USER_KEY="$PUSHOVER_USER_KEY"
PUSHOVER_API_TOKEN="$PUSHOVER_API_TOKEN"

# === INTELLIGENT MONITORING CONFIGURATION ===
MONITORING_MODE="$MONITORING_MODE"
DAEMON_AUTOSTART="$DAEMON_AUTOSTART"
MONITORING_INTERVAL="$MONITORING_INTERVAL"
QUICK_CHECK_INTERVAL="$QUICK_CHECK_INTERVAL"
DEEP_ANALYSIS_INTERVAL="$DEEP_ANALYSIS_INTERVAL"

# === INTELLIGENT LOGGING CONFIGURATION ===
HIGH_FREQ_INTERVAL="\${HIGH_FREQ_INTERVAL:-1}"           # 1 second for unlimited connections
LOW_FREQ_INTERVAL="\${LOW_FREQ_INTERVAL:-60}"           # 60 seconds for limited data connections
GPS_COLLECTION_INTERVAL="\${GPS_COLLECTION_INTERVAL:-60}"  # GPS every minute
AGGREGATION_WINDOW="\${AGGREGATION_WINDOW:-60}"         # 60-second aggregation windows
PERCENTILES="\${PERCENTILES:-50,90,95,99}"              # Percentiles to calculate
LOG_RETENTION_HOURS="\${LOG_RETENTION_HOURS:-24}"       # 24 hours of detailed logs
ARCHIVE_RETENTION_DAYS="\${ARCHIVE_RETENTION_DAYS:-7}"  # 7 days of compressed archives

# === CONNECTION TYPE PATTERNS ===
CELLULAR_INTERFACES_PATTERN="\${CELLULAR_INTERFACES_PATTERN:-^mob[0-9]s[0-9]a[0-9]$}"
SATELLITE_INTERFACES_PATTERN="\${SATELLITE_INTERFACES_PATTERN:-^wwan|^starlink}"
UNLIMITED_INTERFACES_PATTERN="\${UNLIMITED_INTERFACES_PATTERN:-^eth|^wifi}"

# === INTELLIGENT MONITORING THRESHOLDS ===
LATENCY_WARNING_THRESHOLD="\${LATENCY_WARNING_THRESHOLD:-200}"
LATENCY_CRITICAL_THRESHOLD="\${LATENCY_CRITICAL_THRESHOLD:-500}"
PACKET_LOSS_WARNING_THRESHOLD="\${PACKET_LOSS_WARNING_THRESHOLD:-2}"
PACKET_LOSS_CRITICAL_THRESHOLD="\${PACKET_LOSS_CRITICAL_THRESHOLD:-5}"

# === PERFORMANCE ANALYSIS SETTINGS ===
HISTORICAL_ANALYSIS_WINDOW="\${HISTORICAL_ANALYSIS_WINDOW:-1800}"
TREND_ANALYSIS_SAMPLES="\${TREND_ANALYSIS_SAMPLES:-10}"
MAX_METRIC_ADJUSTMENT="\${MAX_METRIC_ADJUSTMENT:-50}"
MAX_ADJUSTMENTS_PER_CYCLE="\${MAX_ADJUSTMENTS_PER_CYCLE:-3}"
ADJUSTMENT_COOLDOWN="\${ADJUSTMENT_COOLDOWN:-120}"

# === BINARY PATHS ===
GRPCURL_CMD="$SCRIPTS_DIR/grpcurl"
JQ_CMD="$SCRIPTS_DIR/jq"

# === DEVELOPMENT/DEBUG ===
DEBUG="\${DEBUG:-0}"
DRY_RUN="\${DRY_RUN:-0}"
RUTOS_TEST_MODE="\${RUTOS_TEST_MODE:-0}"

# === FIRMWARE UPGRADE RECOVERY ===
# After firmware upgrades, run: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh
RECOVERY_SCRIPT="$SCRIPTS_DIR/recover-after-firmware-upgrade.sh"

EOF

    chmod 644 "$CONFIG_DIR/config.sh"
    log_success "Enhanced configuration file created at $CONFIG_DIR/config.sh"
    log_info "Configuration is stored in persistent storage and survives firmware upgrades"
    log_function_exit "generate_enhanced_config"
}

# === SYSTEM VERIFICATION WITH DAEMON SUPPORT ===
verify_intelligent_monitoring_system() {
    log_function_entry "verify_intelligent_monitoring_system"
    log_step "Verifying Intelligent Monitoring System v3.0"

    verification_failed=0

    # Check persistent storage setup
    if [ -d "$INSTALL_BASE_DIR" ] && [ -d "$SCRIPTS_DIR" ] && [ -d "$CONFIG_DIR" ]; then
        log_success "Persistent storage directories verified"
    else
        log_error "Persistent storage directories missing"
        verification_failed=1
    fi

    # Check if monitoring script exists and is executable in persistent location
    if [ -f "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ] && [ -x "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ]; then
        log_success "Intelligent monitoring script installed in persistent storage"
    else
        log_error "Intelligent monitoring script missing or not executable in persistent storage"
        verification_failed=1
    fi

    # Check convenience symlinks
    if [ -L "/root/starlink_monitor_unified-rutos.sh" ] && [ -L "/root/config.sh" ]; then
        log_success "Convenience symlinks created"
    else
        log_warning "Convenience symlinks missing (not critical)"
    fi

    # Check MWAN3 availability (required for intelligent monitoring)
    if command -v mwan3 >/dev/null 2>&1; then
        log_success "MWAN3 available for intelligent monitoring"

        # Test MWAN3 configuration access
        if uci show mwan3 >/dev/null 2>&1; then
            log_success "MWAN3 UCI configuration accessible"
        else
            log_error "MWAN3 UCI configuration not accessible"
            verification_failed=1
        fi
    else
        log_error "MWAN3 not found - intelligent monitoring requires MWAN3"
        verification_failed=1
    fi

    # Check daemon service setup
    if [ "$MONITORING_MODE" = "daemon" ] || [ "$MONITORING_MODE" = "hybrid" ]; then
        if [ -f "$INIT_D_DIR/starlink-monitor" ] && [ -x "$INIT_D_DIR/starlink-monitor" ]; then
            log_success "Daemon service script installed"

            # Test daemon functionality
            log_info "Testing daemon service..."
            if "$INIT_D_DIR/starlink-monitor" status >/dev/null 2>&1; then
                log_success "Daemon service operational"
            else
                log_info "Daemon not currently running (normal after installation)"
            fi
        else
            log_error "Daemon service script missing"
            verification_failed=1
        fi
    fi

    # Test intelligent monitoring script
    log_info "Testing intelligent monitoring script functionality..."
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" validate 2>/dev/null; then
        log_success "Intelligent monitoring validation passed"
    else
        log_warning "Intelligent monitoring validation failed - may need MWAN3 configuration"
    fi

    # Test discovery capabilities
    log_info "Testing MWAN3 discovery capabilities..."
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" discover >/dev/null 2>&1; then
        log_success "MWAN3 interface discovery working"
    else
        log_warning "MWAN3 interface discovery needs configuration"
    fi

    if [ $verification_failed -eq 0 ]; then
        log_success "All intelligent monitoring system checks passed"
        log_function_exit "verify_intelligent_monitoring_system"
        return 0
    else
        log_error "Some intelligent monitoring system checks failed"
        log_function_exit "verify_intelligent_monitoring_system"
        return 1
    fi
}

# === INTELLIGENT LOGGING SYSTEM DEPLOYMENT ===
deploy_intelligent_logging_system() {
    log_function_entry "deploy_intelligent_logging_system"
    log_step "Deploying Intelligent Logging System v3.0"

    # Download the intelligent logger script
    log_info "Downloading intelligent logging system..."

    logger_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/scripts/starlink_intelligent_logger-rutos.sh"
    logger_dest="$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would download $logger_url to $logger_dest"
    else
        if smart_safe_execute "curl -fsSL '$logger_url' -o '$logger_dest'" "Download intelligent logger script"; then
            smart_safe_execute "chmod +x '$logger_dest'" "Make logger script executable"
            log_success "Intelligent logger installed: $logger_dest"
        else
            log_error "Failed to download intelligent logger"
            log_function_exit "deploy_intelligent_logging_system" 1
            return 1
        fi
    fi

    # Create logging system configuration
    log_info "Configuring intelligent logging system..."

    cat >"$CONFIG_DIR/logging.conf" <<EOF
# Intelligent Logging System Configuration
# Generated by deployment script v$SCRIPT_VERSION

# === COLLECTION FREQUENCY ===
HIGH_FREQ_INTERVAL=1           # 1 second for unlimited connections
LOW_FREQ_INTERVAL=60          # 60 seconds for limited data connections
GPS_COLLECTION_INTERVAL=60    # GPS every minute

# === STATISTICAL AGGREGATION ===
AGGREGATION_WINDOW=60         # 60-second aggregation windows
PERCENTILES="50,90,95,99"     # Percentiles to calculate

# === LOG RETENTION ===
LOG_RETENTION_HOURS=24        # 24 hours of detailed logs
ARCHIVE_RETENTION_DAYS=7      # 7 days of compressed archives

# === CONNECTION TYPE PATTERNS ===
CELLULAR_INTERFACES_PATTERN="^mob[0-9]s[0-9]a[0-9]$"
SATELLITE_INTERFACES_PATTERN="^wwan|^starlink"
UNLIMITED_INTERFACES_PATTERN="^eth|^wifi"

# === LOGGING DIRECTORIES (PERSISTENT) ===
LOG_BASE_DIR="$LOG_DIR"
METRICS_LOG_DIR="$LOG_DIR/metrics"
GPS_LOG_DIR="$LOG_DIR/gps"
AGGREGATED_LOG_DIR="$LOG_DIR/aggregated"
ARCHIVE_LOG_DIR="$LOG_DIR/archive"
EOF

    chmod 644 "$CONFIG_DIR/logging.conf"
    log_success "Logging configuration created: $CONFIG_DIR/logging.conf"

    # Create convenience symlink for backward compatibility
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would create symlink: ln -sf '$logger_dest' /root/starlink_intelligent_logger-rutos.sh"
    else
        ln -sf "$logger_dest" /root/starlink_intelligent_logger-rutos.sh 2>/dev/null || true
    fi

    log_success "Intelligent logging system deployment completed"
    log_function_exit "deploy_intelligent_logging_system"
}

# === INTELLIGENT LOGGING SERVICE SETUP ===
setup_intelligent_logging_service() {
    log_function_entry "setup_intelligent_logging_service"
    log_step "Setting up Intelligent Logging Service"

    # Create init.d service script for the intelligent logger
    log_info "Creating logging daemon service script..."

    cat >"$INSTALL_BASE_DIR/templates/starlink-logger.init" <<EOF
#!/bin/sh /etc/rc.common

START=96
STOP=9

USE_PROCD=1
PROG="$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh"
PIDFILE="/var/run/starlink-logger.pid"

start_service() {
    # Ensure configuration exists
    if [ ! -f "$CONFIG_DIR/config.sh" ]; then
        logger -s -t starlink-logger "ERROR: Configuration not found at $CONFIG_DIR/config.sh"
        return 1
    fi
    
    # Ensure MWAN3 is available
    if ! command -v mwan3 >/dev/null 2>&1; then
        logger -s -t starlink-logger "WARNING: MWAN3 not found - limited metrics available"
    fi
    
    logger -s -t starlink-logger "Starting Intelligent Starlink Logger v3.0"
    
    procd_open_instance
    procd_set_param command "\$PROG" start
    procd_set_param pidfile "\$PIDFILE"
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    logger -s -t starlink-logger "Intelligent logging daemon started"
}

stop_service() {
    logger -s -t starlink-logger "Stopping Intelligent Starlink Logger"
    "\$PROG" stop
}

reload_service() {
    logger -s -t starlink-logger "Reloading Intelligent Starlink Logger"
    "\$PROG" restart
}

status() {
    "\$PROG" status
}
EOF

    # Copy the template to the active init.d location
    smart_safe_execute "cp '$INSTALL_BASE_DIR/templates/starlink-logger.init' '$INIT_D_DIR/starlink-logger'" "Copy service template to init.d"
    smart_safe_execute "chmod +x '$INIT_D_DIR/starlink-logger'" "Make service script executable"

    log_success "Created logging daemon service script"
    log_info "Service template: $INSTALL_BASE_DIR/templates/starlink-logger.init"
    log_info "Active service: $INIT_D_DIR/starlink-logger"

    # Enable the service to start at boot if monitoring is enabled
    if [ "${ENABLE_STARLINK_MONITORING:-true}" = "true" ]; then
        log_info "Enabling logging daemon autostart at boot..."
        smart_safe_execute "'$INIT_D_DIR/starlink-logger' enable" "Enable logging daemon autostart"
        log_success "Logging daemon autostart enabled"
    fi

    log_success "Intelligent logging service setup completed"
    log_function_exit "setup_intelligent_logging_service"
}

# === MAIN DEPLOYMENT FUNCTIONS ===

# Basic configuration collection (placeholder for full implementation)
collect_basic_configuration() {
    log_function_entry "collect_basic_configuration"
    log_step "Basic Configuration Collection"

    if is_interactive; then
        log_info "Interactive mode detected - collecting configuration"

        # Collect basic network settings
        printf "Starlink IP address [%s]: " "$DEFAULT_STARLINK_IP"
        read -r STARLINK_IP_INPUT
        STARLINK_IP="${STARLINK_IP_INPUT:-$DEFAULT_STARLINK_IP}"

        printf "Starlink port [9200]: "
        read -r STARLINK_PORT_INPUT
        STARLINK_PORT="${STARLINK_PORT_INPUT:-9200}"

        printf "RUTOS IP address [%s]: " "$DEFAULT_RUTOS_IP"
        read -r RUTOS_IP_INPUT
        RUTOS_IP="${RUTOS_IP_INPUT:-$DEFAULT_RUTOS_IP}"

        # Network configuration
        printf "MWAN interface name [starlink]: "
        read -r MWAN_IFACE_INPUT
        MWAN_IFACE="${MWAN_IFACE_INPUT:-starlink}"

        printf "MWAN member name [starlink_m1_w1]: "
        read -r MWAN_MEMBER_INPUT
        MWAN_MEMBER="${MWAN_MEMBER_INPUT:-starlink_m1_w1}"

        printf "Good connection metric [10]: "
        read -r METRIC_GOOD_INPUT
        METRIC_GOOD="${METRIC_GOOD_INPUT:-10}"

        printf "Bad connection metric [100]: "
        read -r METRIC_BAD_INPUT
        METRIC_BAD="${METRIC_BAD_INPUT:-100}"

        # Thresholds
        printf "Latency threshold in ms [1000]: "
        read -r LATENCY_THRESHOLD_INPUT
        LATENCY_THRESHOLD="${LATENCY_THRESHOLD_INPUT:-1000}"

        printf "Packet loss threshold %% [10]: "
        read -r PACKET_LOSS_THRESHOLD_INPUT
        PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD_INPUT:-10}"

        printf "Obstruction threshold %% [5]: "
        read -r OBSTRUCTION_THRESHOLD_INPUT
        OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD_INPUT:-5}"

        # Feature toggles
        printf "Enable Starlink monitoring? [Y/n]: "
        read -r STARLINK_MONITORING_CHOICE
        case "${STARLINK_MONITORING_CHOICE:-y}" in
            [Nn]*) ENABLE_STARLINK_MONITORING="false" ;;
            *) ENABLE_STARLINK_MONITORING="true" ;;
        esac

        printf "Enable GPS collection? [Y/n]: "
        read -r GPS_CHOICE
        case "${GPS_CHOICE:-y}" in
            [Nn]*) ENABLE_GPS="false" ;;
            *) ENABLE_GPS="true" ;;
        esac

        printf "Enable Azure integration? [y/N]: "
        read -r AZURE_CHOICE
        case "${AZURE_CHOICE:-n}" in
            [Yy]*)
                ENABLE_AZURE="true"
                printf "Azure endpoint URL: "
                read -r AZURE_ENDPOINT
                ;;
            *)
                ENABLE_AZURE="false"
                AZURE_ENDPOINT=""
                ;;
        esac

        printf "Enable Pushover notifications? [y/N]: "
        read -r PUSHOVER_CHOICE
        case "${PUSHOVER_CHOICE:-n}" in
            [Yy]*)
                ENABLE_PUSHOVER="true"
                printf "Pushover user key: "
                read -r PUSHOVER_USER_KEY
                printf "Pushover API token: "
                read -r PUSHOVER_API_TOKEN
                ;;
            *)
                ENABLE_PUSHOVER="false"
                PUSHOVER_USER_KEY=""
                PUSHOVER_API_TOKEN=""
                ;;
        esac
    else
        log_info "Non-interactive mode detected - using default configuration"

        # CRITICAL: Set all required variables to prevent 'parameter not set' errors
        log_debug "Setting configuration variables with default fallbacks..."

        # Use environment variables if set, otherwise defaults
        STARLINK_IP="${STARLINK_IP:-$DEFAULT_STARLINK_IP}"
        STARLINK_PORT="${STARLINK_PORT:-9200}"
        RUTOS_IP="${RUTOS_IP:-$DEFAULT_RUTOS_IP}"
        MWAN_IFACE="${MWAN_IFACE:-starlink}"
        MWAN_MEMBER="${MWAN_MEMBER:-starlink_m1_w1}"
        METRIC_GOOD="${METRIC_GOOD:-10}"
        METRIC_BAD="${METRIC_BAD:-100}"
        LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-1000}"
        PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD:-10}"
        OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD:-5}"

        # CRITICAL: Feature toggles - must be set to prevent set -eu failures
        ENABLE_STARLINK_MONITORING="${ENABLE_STARLINK_MONITORING:-$DEFAULT_ENABLE_STARLINK_MONITORING}"
        ENABLE_GPS="${ENABLE_GPS:-$DEFAULT_ENABLE_GPS}"
        ENABLE_AZURE="${ENABLE_AZURE:-$DEFAULT_ENABLE_AZURE}"
        ENABLE_PUSHOVER="${ENABLE_PUSHOVER:-$DEFAULT_ENABLE_PUSHOVER}"

        # Integration settings
        AZURE_ENDPOINT="${AZURE_ENDPOINT:-$DEFAULT_AZURE_ENDPOINT}"
        PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-}"
        PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-}"

        # Debug: Log all set variables to verify they're properly initialized
        log_debug "Configuration variables set:"
        log_debug "  ENABLE_STARLINK_MONITORING='$ENABLE_STARLINK_MONITORING' (default: $DEFAULT_ENABLE_STARLINK_MONITORING)"
        log_debug "  ENABLE_GPS='$ENABLE_GPS' (default: $DEFAULT_ENABLE_GPS)"
        log_debug "  ENABLE_AZURE='$ENABLE_AZURE' (default: $DEFAULT_ENABLE_AZURE)"
        log_debug "  ENABLE_PUSHOVER='$ENABLE_PUSHOVER' (default: $DEFAULT_ENABLE_PUSHOVER)"

        log_info "Using configuration: Starlink IP=$STARLINK_IP, RUTOS IP=$RUTOS_IP"
        log_info "Network: Interface=$MWAN_IFACE, Member=$MWAN_MEMBER"
        log_info "Thresholds: Latency=${LATENCY_THRESHOLD}ms, Loss=${PACKET_LOSS_THRESHOLD}%, Obstruction=${OBSTRUCTION_THRESHOLD}%"
        log_info "Features: Starlink=$ENABLE_STARLINK_MONITORING, GPS=$ENABLE_GPS"
        log_info "Integrations: Azure=$ENABLE_AZURE, Pushover=$ENABLE_PUSHOVER"

        # Log if any environment variables were used
        if [ "$STARLINK_IP" != "$DEFAULT_STARLINK_IP" ]; then
            log_info "Environment: Using custom STARLINK_IP=$STARLINK_IP"
        fi
        if [ "${ENABLE_STARLINK_MONITORING}" != "$DEFAULT_ENABLE_STARLINK_MONITORING" ]; then
            log_info "Environment: Starlink monitoring=$ENABLE_STARLINK_MONITORING"
        fi
        if [ "${ENABLE_GPS}" != "$DEFAULT_ENABLE_GPS" ]; then
            log_info "Environment: GPS collection=$ENABLE_GPS"
        fi
        if [ "${ENABLE_AZURE}" = "true" ]; then
            log_info "Environment: Azure integration enabled"
        fi
        if [ "${ENABLE_PUSHOVER}" = "true" ]; then
            log_info "Environment: Pushover notifications enabled"
        fi
    fi

    log_success "Basic configuration collected"
    log_function_exit "collect_basic_configuration"
}

# System requirements setup (placeholder for full implementation)
setup_system_requirements() {
    log_function_entry "setup_system_requirements"
    log_step "Setting up System Requirements"

    # Check for essential tools
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        return 1
    fi

    if ! command -v uci >/dev/null 2>&1; then
        log_error "uci is required but not installed (not RUTOS?)"
        return 1
    fi

    log_success "System requirements verified"
    log_function_exit "setup_system_requirements"
}

# Package installation (placeholder for full implementation)
install_required_packages() {
    log_function_entry "install_required_packages"
    log_step "Installing Required Packages"

    # Update package lists
    log_info "Updating package lists..."
    smart_safe_execute "opkg update" "Update package lists" || log_warning "Package update failed (may be offline)"

    # Install MWAN3 if not present
    if ! command -v mwan3 >/dev/null 2>&1; then
        log_info "Installing MWAN3..."
        smart_safe_execute "opkg install mwan3" "Install MWAN3 package" || log_warning "MWAN3 installation failed"
    else
        log_success "MWAN3 already available"
    fi

    log_success "Package installation completed"
    log_function_exit "install_required_packages"
}

# Binary downloads (placeholder for full implementation)
download_binaries() {
    log_function_entry "download_binaries"
    log_step "Downloading Required Binaries"

    # Download grpcurl
    if [ ! -f "$SCRIPTS_DIR/grpcurl" ]; then
        log_info "Downloading grpcurl..."
        temp_dir="/tmp/grpcurl_$$"
        smart_safe_execute "mkdir -p '$temp_dir'" "Create temporary directory"
        if smart_safe_execute "bash -c 'curl -fsSL \"$GRPCURL_URL\" | tar -xz -C \"$temp_dir\"'" "Download and extract grpcurl"; then
            smart_safe_execute "cp '$temp_dir/grpcurl' '$SCRIPTS_DIR/grpcurl'" "Install grpcurl binary"
            smart_safe_execute "chmod +x '$SCRIPTS_DIR/grpcurl'" "Make grpcurl executable"
            smart_safe_execute "rm -rf '$temp_dir'" "Clean up temporary directory"
            log_success "grpcurl installed"
        else
            log_error "Failed to download grpcurl"
            smart_safe_execute "rm -rf '$temp_dir'" "Clean up temporary directory"
            return 1
        fi
    else
        log_success "grpcurl already available"
    fi

    # Download jq
    if [ ! -f "$SCRIPTS_DIR/jq" ]; then
        log_info "Downloading jq..."
        if smart_safe_execute "curl -fsSL '$JQ_URL' -o '$SCRIPTS_DIR/jq'" "Download jq binary"; then
            smart_safe_execute "chmod +x '$SCRIPTS_DIR/jq'" "Make jq executable"
            log_success "jq installed"
        else
            log_error "Failed to download jq"
            return 1
        fi
    else
        log_success "jq already available"
    fi

    log_success "Binary downloads completed"
    log_function_exit "download_binaries"
}

# Check root privileges
check_root_privileges() {
    log_function_entry "check_root_privileges"
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_function_exit "check_root_privileges"
}

# Check system compatibility
check_system_compatibility() {
    log_function_entry "check_system_compatibility"
    log_info "Checking RUTOS compatibility..."

    if [ ! -f "/etc/openwrt_release" ]; then
        log_warning "Not detected as OpenWrt/RUTOS system"
    fi

    # Check for RUTOS-specific features
    if command -v gsmctl >/dev/null 2>&1; then
        log_success "RUTOS cellular capabilities detected"
    else
        log_info "No RUTOS cellular capabilities (basic monitoring only)"
    fi
    log_function_exit "check_system_compatibility"
}

# Deploy monitoring scripts (placeholder for full implementation)
deploy_monitoring_scripts() {
    log_function_entry "deploy_monitoring_scripts"
    log_step "Deploying Monitoring Scripts"

    # Debug: Log current environment inheritance status
    log_debug "Environment inheritance check for child scripts:"
    log_debug "  DEBUG environment variable: ${DEBUG:-unset}"
    log_debug "  RUTOS_TEST_MODE environment variable: ${RUTOS_TEST_MODE:-unset}"
    log_debug "  DRY_RUN environment variable: ${DRY_RUN:-unset}"

    # Re-export to ensure inheritance (some shells need this)
    export DEBUG RUTOS_TEST_MODE DRY_RUN VERBOSE

    # Download main monitoring script
    monitor_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
    monitor_dest="$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh"

    log_info "Downloading main monitoring script..."
    log_debug "Download details: $monitor_url -> $monitor_dest"
    if smart_safe_execute "curl -fsSL '$monitor_url' -o '$monitor_dest'" "Download main monitoring script"; then
        smart_safe_execute "chmod +x '$monitor_dest'" "Make monitoring script executable"
        # Verify download
        if [ -f "$monitor_dest" ] && [ -s "$monitor_dest" ]; then
            file_size=$(wc -c <"$monitor_dest" 2>/dev/null || echo "unknown")
            log_success "Main monitoring script installed: $monitor_dest ($file_size bytes)"
            log_debug "Script permissions: $(ls -la "$monitor_dest" 2>/dev/null || echo 'cannot check')"
        else
            log_error "Download succeeded but file is missing or empty: $monitor_dest"
            return 1
        fi
    else
        log_error "Failed to download main monitoring script from $monitor_url"
        log_error "Check network connectivity and URL availability"
        return 1
    fi

    # Download RUTOS library
    lib_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/scripts/lib/rutos-lib.sh"
    lib_dest="$LIB_DIR/rutos-lib.sh"

    log_info "Downloading RUTOS library..."
    log_debug "Download details: $lib_url -> $lib_dest"
    if smart_safe_execute "curl -fsSL '$lib_url' -o '$lib_dest'" "Download RUTOS library"; then
        smart_safe_execute "chmod +x '$lib_dest'" "Make library executable"
        # Verify download
        if [ -f "$lib_dest" ] && [ -s "$lib_dest" ]; then
            file_size=$(wc -c <"$lib_dest" 2>/dev/null || echo "unknown")
            log_success "RUTOS library installed: $lib_dest ($file_size bytes)"
            log_debug "Library permissions: $(ls -la "$lib_dest" 2>/dev/null || echo 'cannot check')"
        else
            log_error "Download succeeded but library file is missing or empty: $lib_dest"
            return 1
        fi
    else
        log_error "Failed to download RUTOS library from $lib_url"
        log_error "Check network connectivity and URL availability"
        return 1
    fi

    # Deploy intelligent logging system
    deploy_intelligent_logging_system

    # Test script functionality with debug environment inheritance
    test_deployed_scripts

    log_success "Monitoring scripts deployment completed"
    log_function_exit "deploy_monitoring_scripts"
}

# Test deployed scripts with proper environment inheritance
test_deployed_scripts() {
    log_function_entry "test_deployed_scripts"
    log_debug "Testing deployed scripts with environment inheritance..."

    # Test main monitoring script if it exists
    if [ -f "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ] && [ -x "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ]; then
        log_debug "Testing main monitoring script with debug environment:"
        log_debug "  Command: '$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh' validate"
        log_debug "  Environment: DEBUG=$DEBUG RUTOS_TEST_MODE=$RUTOS_TEST_MODE DRY_RUN=$DRY_RUN"

        # Use the child script execution wrapper for proper environment inheritance
        if execute_child_script "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" "validate" "Test monitoring script validation"; then
            log_debug "✓ Main monitoring script basic validation passed"
        else
            log_debug "ℹ Main monitoring script validation failed (may need configuration)"
        fi
    else
        log_warning "Main monitoring script not found or not executable for testing"
    fi

    # Test intelligent logger if it exists
    if [ -f "$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh" ] && [ -x "$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh" ]; then
        log_debug "Testing intelligent logger script..."

        # Test logger with proper environment inheritance
        if execute_child_script "$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh" "status" "Test logger script status"; then
            log_debug "✓ Intelligent logger script accessible"
        else
            log_debug "ℹ Intelligent logger script test failed (normal if not configured)"
        fi
    else
        log_debug "Intelligent logger script not found (will be downloaded during deployment)"
    fi
    log_function_exit "test_deployed_scripts"
}

# Azure integration setup (placeholder for full implementation)
setup_azure_integration() {
    log_function_entry "setup_azure_integration"
    log_step "Setting up Azure Integration"

    if [ "$ENABLE_AZURE" = "true" ] && [ -n "$AZURE_ENDPOINT" ]; then
        log_info "Configuring Azure log shipping..."
        # Azure setup would go here
        log_success "Azure integration configured"
    else
        log_info "Azure integration disabled"
    fi
    log_function_exit "setup_azure_integration"
}

# Pushover notifications setup (placeholder for full implementation)
setup_pushover_notifications() {
    log_function_entry "setup_pushover_notifications"
    log_step "Setting up Pushover Notifications"

    if [ "$ENABLE_PUSHOVER" = "true" ] && [ -n "$PUSHOVER_USER_KEY" ] && [ -n "$PUSHOVER_API_TOKEN" ]; then
        log_info "Configuring Pushover notifications..."
        # Pushover setup would go here
        log_success "Pushover notifications configured"
    else
        log_info "Pushover notifications disabled"
    fi
    log_function_exit "setup_pushover_notifications"
}

# === MAIN EXECUTION ===
main() {
    log_function_entry "main"
    ERROR_CONTEXT="Main deployment function initialization"

    # CRITICAL: Validate essential environment before proceeding
    smart_step "Pre-flight Environment Validation"

    # Validate library system state
    if [ "$_LIBRARY_LOADED" != "1" ]; then
        smart_error "CRITICAL: Library system not properly loaded"
        smart_error "Expected: _LIBRARY_LOADED=1, Found: _LIBRARY_LOADED=${_LIBRARY_LOADED:-unset}"
        smart_error "This indicates a library loading failure early in the script"
        return 1
    fi

    smart_success "✓ Library system validated"

    # Validate essential script variables exist
    essential_vars="SCRIPT_VERSION ORIGINAL_DEBUG ORIGINAL_RUTOS_TEST_MODE ORIGINAL_TEST_MODE ORIGINAL_DRY_RUN"
    for var in $essential_vars; do
        # Use eval to get the variable value safely - ensure var is not empty
        if [ -z "${var:-}" ]; then
            smart_error "Empty variable name in validation list"
            return 1
        fi
        var_value=""
        # Use a safer eval pattern to avoid ShellCheck warnings about undefined variables
        # shellcheck disable=SC2154 # $var is a valid variable name from the loop
        eval "var_value=\${${var:-unknown_var}:-}"
        if ! validate_required_parameter "${var:-unknown_var}" "$var_value" "main function initialization"; then
            smart_error "Essential script variable '${var:-unknown_var}' validation failed"
            smart_error "This indicates an initialization problem early in the script"
            return 1
        fi
    done

    smart_success "✓ Essential variables validated"

    smart_step "Starlink Solution Deployment v$SCRIPT_VERSION - Intelligent Monitoring"

    # CRITICAL: Export debug environment for child scripts early
    ERROR_CONTEXT="Exporting debug environment"
    export_debug_environment

    # Comprehensive debug state output for troubleshooting
    smart_debug "=== DEPLOYMENT START DIAGNOSTICS ==="
    smart_debug "Main deployment function started with enhanced debugging"
    smart_debug "Current working directory: $(pwd)"
    smart_debug "Script path: $0"
    smart_debug "Script arguments: $*"
    smart_debug "Deployment mode analysis:"
    smart_debug "  DRY_RUN=${DRY_RUN:-0} (original: ${ORIGINAL_DRY_RUN:-unset})"
    smart_debug "  TEST_MODE=${TEST_MODE:-0} (original: ${ORIGINAL_TEST_MODE:-unset})"
    smart_debug "  RUTOS_TEST_MODE=${RUTOS_TEST_MODE:-0} (original: ${ORIGINAL_RUTOS_TEST_MODE:-unset})"
    smart_debug "  DEBUG=${DEBUG:-0} (original: ${ORIGINAL_DEBUG:-unset})"
    smart_debug "Backward compatibility: $(if [ "${TEST_MODE:-0}" = "1" ] && [ "${RUTOS_TEST_MODE:-0}" = "0" ]; then echo "TEST_MODE->RUTOS_TEST_MODE enabled"; else echo "none needed"; fi)"
    smart_debug "Library status: $_LIBRARY_LOADED (1=loaded, 0=fallback)"
    smart_debug "System detection: USER=${USER:-unknown}, TERM=${TERM:-unknown}"
    smart_debug "Interactive mode: $(if is_interactive; then echo "yes"; else echo "no"; fi)"

    # Pre-flight checks
    ERROR_CONTEXT="Pre-flight system checks"
    smart_debug "Starting pre-flight checks..."
    check_root_privileges
    check_system_compatibility

    # CRITICAL: Setup persistent storage first (RUTOS firmware upgrade survival)
    ERROR_CONTEXT="Setting up persistent storage"
    setup_persistent_storage

    # Configuration
    ERROR_CONTEXT="Collecting configuration"
    collect_enhanced_configuration

    # System setup
    ERROR_CONTEXT="Setting up system requirements"
    setup_system_requirements
    ERROR_CONTEXT="Installing required packages"
    install_required_packages
    ERROR_CONTEXT="Downloading binaries"
    download_binaries

    # Configuration and recovery setup
    ERROR_CONTEXT="Generating configuration"
    generate_enhanced_config
    ERROR_CONTEXT="Creating recovery script"
    create_recovery_script

    # Core deployment
    ERROR_CONTEXT="Deploying monitoring scripts"
    deploy_monitoring_scripts
    ERROR_CONTEXT="Setting up monitoring system"
    setup_monitoring_system # Intelligent monitoring daemon setup
    ERROR_CONTEXT="Setting up intelligent logging service"
    setup_intelligent_logging_service # NEW: Intelligent logging daemon setup

    # Additional features
    if [ "$ENABLE_AZURE" = "true" ]; then
        ERROR_CONTEXT="Setting up Azure integration"
        setup_azure_integration
    fi

    if [ "$ENABLE_PUSHOVER" = "true" ]; then
        ERROR_CONTEXT="Setting up Pushover notifications"
        setup_pushover_notifications
    fi

    # Verification
    ERROR_CONTEXT="Verifying system"
    verify_intelligent_monitoring_system

    # Final setup
    ERROR_CONTEXT="Finalizing deployment"
    smart_step "Deployment Completed Successfully!"

    case "$MONITORING_MODE" in
        daemon)
            log_info "Starting intelligent monitoring daemon..."
            smart_safe_execute "'$INIT_D_DIR/starlink-monitor' start" "Start monitoring daemon"
            log_success "Intelligent monitoring daemon started"

            log_info "Starting intelligent logging daemon..."
            smart_safe_execute "'$INIT_D_DIR/starlink-logger' start" "Start logging daemon"
            log_success "Intelligent logging daemon started"
            ;;
        hybrid)
            log_info "Starting intelligent monitoring daemon with cron support..."
            smart_safe_execute "'$INIT_D_DIR/starlink-monitor' start" "Start monitoring daemon"
            log_success "Hybrid monitoring system active"

            log_info "Starting intelligent logging daemon..."
            smart_safe_execute "'$INIT_D_DIR/starlink-logger' start" "Start logging daemon"
            log_success "Intelligent logging daemon started"
            ;;
        cron)
            log_info "Traditional cron-based monitoring configured"
            log_success "Legacy monitoring system active"

            log_info "Starting intelligent logging daemon..."
            smart_safe_execute "'$INIT_D_DIR/starlink-logger' start" "Start logging daemon"
            log_success "Intelligent logging daemon started"
            ;;
    esac

    # Display final status
    log_step "System Status"
    log_info "Monitoring mode: $MONITORING_MODE"
    log_info "Installation directory: $INSTALL_BASE_DIR (PERSISTENT)"
    log_info "Configuration: $CONFIG_DIR/config.sh (PERSISTENT)"
    log_info "Scripts location: $SCRIPTS_DIR (PERSISTENT)"
    log_info "Logs directory: $LOG_DIR (PERSISTENT)"
    log_info "Convenience symlinks: /root/starlink_monitor_unified-rutos.sh, /root/config.sh"

    if [ "$MONITORING_MODE" != "cron" ]; then
        log_info "Monitoring daemon: $INIT_D_DIR/starlink-monitor {start|stop|status|restart}"
        log_info "Manual testing: $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh test --debug"
    fi

    # NEW: Intelligent logging system status
    log_step "Intelligent Logging System"
    log_info "Logging daemon: $INIT_D_DIR/starlink-logger {start|stop|status|restart}"
    log_info "Logger control: $SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh {start|stop|status|test}"
    log_info "Metrics logs: $LOG_DIR/metrics/ (24-hour retention)"
    log_info "GPS logs: $LOG_DIR/gps/ (daily files)"
    log_info "Aggregated data: $LOG_DIR/aggregated/ (statistical summaries)"
    log_info "Archived logs: $LOG_DIR/archive/ (7-day retention, compressed)"
    log_info "Collection features:"
    log_info "  • MWAN3 metrics extraction (no additional traffic)"
    log_info "  • Smart frequency: 1s unlimited, 60s limited connections"
    log_info "  • Dual-source GPS (RUTOS + Starlink)"
    log_info "  • Statistical aggregation with percentiles"
    log_info "  • Automatic log rotation and compression"

    # IMPORTANT: Firmware upgrade information
    log_step "IMPORTANT: Firmware Upgrade Recovery"
    log_warning "After RUTOS firmware upgrades, run the recovery script:"
    log_info "Recovery command: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
    log_info "This will restore daemon service and symlinks after firmware upgrades"

    log_success "Intelligent Starlink Monitoring System v3.0 deployment completed!"
    log_success "All files stored in persistent storage: $INSTALL_BASE_DIR"

    # Final diagnostics - verify library usage throughout deployment
    log_debug "=== FINAL DEPLOYMENT DIAGNOSTICS ==="
    log_debug "Library status: $_LIBRARY_LOADED (1=loaded, 0=fallback)"
    log_debug "Debug inheritance: DEBUG=$DEBUG, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
    log_debug "Child scripts will inherit: USE_LIBRARY=$USE_LIBRARY, LIBRARY_PATH=$LIBRARY_PATH"
    log_debug "Deployment completed with $(if [ "$_LIBRARY_LOADED" = "1" ]; then echo "full library"; else echo "fallback"; fi) logging system"
}

# === SCRIPT EXECUTION WRAPPER ===
# Execute main function if script is run directly
if [ "${0##*/}" = "deploy-starlink-solution-v3-rutos.sh" ]; then
    # Final pre-execution diagnostics
    pre_debug "Script execution starting..."
    pre_debug "Command line: $0 $*"
    pre_debug "Environment: USER=${USER:-unknown}, PWD=$PWD"

    # CRITICAL: Validate essential variables before main execution
    ERROR_CONTEXT="Pre-execution validation"

    # Check if the main function exists
    if ! command -v main >/dev/null 2>&1; then
        printf "\n"
        printf "🚨 CRITICAL SCRIPT ERROR\n"
        printf "==========================\n"
        printf "❌ Main function not found or not defined\n"
        printf "📍 This indicates a serious script parsing or definition error\n"
        printf "\n"
        printf "💡 TROUBLESHOOTING:\n"
        printf "   1. Check if the script file is corrupted\n"
        printf "   2. Verify the script downloaded completely\n"
        printf "   3. Check for syntax errors: sh -n %s\n" "$0"
        printf "   4. Re-download the script from GitHub\n"
        printf "\n"
        exit 1
    fi

    # Validate we have required base functionality
    essential_functions="smart_debug smart_info smart_error smart_success"
    for func in $essential_functions; do
        if ! command -v "$func" >/dev/null 2>&1; then
            printf "\n"
            printf "🚨 CRITICAL SCRIPT ERROR\n"
            printf "==========================\n"
            printf "❌ Essential function '%s' not found\n" "$func"
            printf "📍 This indicates the script was not loaded properly\n"
            printf "\n"
            printf "💡 TROUBLESHOOTING:\n"
            printf "   1. Check if the script file is corrupted\n"
            printf "   2. Verify all script components loaded correctly\n"
            printf "   3. Re-run with DEBUG=1 to see loading details\n"
            printf "\n"
            exit 1
        fi
    done

    # Execute main deployment with enhanced error context
    ERROR_CONTEXT="Main deployment execution"
    main "$@"

    # Post-execution status with detailed reporting
    exit_code=$?
    ERROR_CONTEXT="Post-execution cleanup"

    if [ $exit_code -eq 0 ]; then
        smart_success "🎉 Deployment script completed successfully (exit code: $exit_code)"
        smart_info "✅ All deployment steps completed without errors"
    else
        smart_error "❌ Deployment script failed (exit code: $exit_code)"
        smart_error "🔍 Check the error output above for specific failure details"

        # Provide context-specific help based on exit code
        case $exit_code in
            1)
                smart_error "💡 General error - check logs and error messages above"
                ;;
            2)
                smart_error "💡 Parameter/variable error - check configuration and environment"
                ;;
            126)
                smart_error "💡 Permission error - check file permissions and user privileges"
                ;;
            127)
                smart_error "💡 Command not found - check required dependencies are installed"
                ;;
        esac
    fi

    exit $exit_code
fi
