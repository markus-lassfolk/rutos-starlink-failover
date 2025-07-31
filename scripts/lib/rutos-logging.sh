#!/bin/sh
# ==============================================================================
# RUTOS Logging Framework
#
# Provides 4-level standardized logging system for all RUTOS scripts:
# - NORMAL: Standard operation info
# - DRY_RUN: Shows what would be done without executing
# - DEBUG: Detailed debugging information with context
# - RUTOS_TEST_MODE: Full execution trace with command tracking
# ==============================================================================

# Prevent multiple sourcing

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
if [ "${_RUTOS_LOGGING_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_LOGGING_LOADED=1

# Source colors if not already loaded
if [ "${_RUTOS_COLORS_LOADED:-}" != "1" ]; then
    # Try to find colors module relative to this script
    _lib_dir="$(dirname "$0")/lib"
    if [ -f "$_lib_dir/rutos-colors.sh" ]; then
        . "$_lib_dir/rutos-colors.sh"
    elif [ -f "$(dirname "$0")/../scripts/lib/rutos-colors.sh" ]; then
        . "$(dirname "$0")/../scripts/lib/rutos-colors.sh"
    else
        # Fallback: define basic colors inline
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[1;35m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    fi
fi

# ============================================================================
# LOGGING LEVEL SETUP
# ============================================================================

# Initialize logging levels and modes
setup_logging_levels() {
    # Capture original values for debug display
    ORIGINAL_DRY_RUN="${DRY_RUN:-0}"
    ORIGINAL_DEBUG="${DEBUG:-0}"
    ORIGINAL_RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
    ORIGINAL_TEST_MODE="${TEST_MODE:-0}"

    # Set defaults for all logging variables
    DRY_RUN="${DRY_RUN:-0}"
    DEBUG="${DEBUG:-0}"
    RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
    TEST_MODE="${TEST_MODE:-0}"

    # Backward compatibility: TEST_MODE -> RUTOS_TEST_MODE
    if [ "$TEST_MODE" = "1" ] && [ "$RUTOS_TEST_MODE" = "0" ]; then
        RUTOS_TEST_MODE=1
    fi

    # Set global logging level based on active modes
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        LOG_LEVEL="TRACE"
    elif [ "$DEBUG" = "1" ]; then
        LOG_LEVEL="DEBUG"
    elif [ "$DRY_RUN" = "1" ]; then
        LOG_LEVEL="TRACE" # DRY_RUN should show TRACE for troubleshooting
    else
        LOG_LEVEL="NORMAL"
    fi

    # Export for child processes
    export DRY_RUN DEBUG RUTOS_TEST_MODE LOG_LEVEL
}

# ============================================================================
# CORE LOGGING FUNCTIONS (RUTOS Method 5 printf format)
# ============================================================================

# Get timestamp for logging
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Core logging function - all others use this
_log_message() {
    level="$1"
    color="$2"
    message="$3"
    destination="${4:-stdout}"
    syslog_priority="${5:-daemon.info}"

    timestamp=$(get_timestamp)

    # Output to console with colors
    if [ "$destination" = "stderr" ]; then
        printf "${color}[%s]${NC} [%s] %s\n" "$level" "$timestamp" "$message" >&2
    else
        printf "${color}[%s]${NC} [%s] %s\n" "$level" "$timestamp" "$message"
    fi

    # Also send to syslog (without colors) for human-readable system logs
    if command -v logger >/dev/null 2>&1; then
        # Use script name or default tag for syslog
        log_tag="${LOG_TAG:-${SCRIPT_NAME:-RutosScript}}"
        logger -t "$log_tag" -p "$syslog_priority" "[$level] $message"
    fi
}

# Standard logging functions
    # Version information for troubleshooting
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "Script: rutos-logging.sh v$SCRIPT_VERSION"
    fi
log_info() {
    _log_message "INFO" "$GREEN" "$1" "stdout" "daemon.info"
}

log_success() {
    _log_message "SUCCESS" "$GREEN" "$1" "stdout" "daemon.info"
}

log_warning() {
    _log_message "WARNING" "$YELLOW" "$1" "stderr" "daemon.warn"
}

log_error() {
    _log_message "ERROR" "$RED" "$1" "stderr" "daemon.err"
}

log_step() {
    _log_message "STEP" "$BLUE" "$1" "stdout" "daemon.info"
}

# Debug logging (only shown when DEBUG=1)
log_debug() {
    if [ "$DEBUG" = "1" ]; then
        _log_message "DEBUG" "$CYAN" "$1" "stderr" "daemon.debug"
    fi
}

# Trace logging (only shown when RUTOS_TEST_MODE=1)
log_trace() {
    if [ "$RUTOS_TEST_MODE" = "1" ] || [ "$LOG_LEVEL" = "TRACE" ]; then
        _log_message "TRACE" "$PURPLE" "$1" "stderr" "daemon.debug"
    fi
}

# ============================================================================
# ADVANCED LOGGING FUNCTIONS
# ============================================================================

# Log variable changes (for RUTOS_TEST_MODE)
log_variable_change() {
    var_name="$1"
    old_value="$2"
    new_value="$3"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "VARIABLE: $var_name changed from '$old_value' to '$new_value'"
    fi
}

# Log function entry (for DEBUG mode)
log_function_entry() {
    func_name="$1"
    func_args="$2"

    if [ "$DEBUG" = "1" ]; then
        log_debug "FUNCTION: Entering $func_name($func_args)"
    fi
}

# Log function exit (for DEBUG mode)
log_function_exit() {
    func_name="$1"
    exit_code="$2"

    if [ "$DEBUG" = "1" ]; then
        log_debug "FUNCTION: Exiting $func_name with code $exit_code"
    fi
}

# Log command execution (for TRACE mode)
log_command_execution() {
    command="$1"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "EXECUTING: $command"
    fi
}

# ============================================================================
# ERROR HANDLING AND STACK TRACES
# ============================================================================

# Enhanced error logging with context
log_error_with_context() {
    error_message="$1"
    script_name="${2:-$(basename "$0")}"
    line_number="${3:-unknown}"
    function_name="${4:-main}"

    log_error "$error_message"

    if [ "$DEBUG" = "1" ]; then
        log_debug "ERROR CONTEXT:"
        log_debug "  Script: $script_name"
        log_debug "  Line: $line_number"
        log_debug "  Function: $function_name"
        log_debug "  Working Directory: $(pwd)"
        log_debug "  Environment: DRY_RUN=$DRY_RUN DEBUG=$DEBUG RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
    fi
}

# Log script initialization (shows active logging modes)
log_script_init() {
    script_name="$1"
    script_version="$2"

    log_info "Starting $script_name v$script_version"

    if [ "$DEBUG" = "1" ]; then
        log_debug "ENVIRONMENT:"
        log_debug "  Working Directory: $(pwd)"
        log_debug "  Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo 'unknown')"
        log_debug "  LOGGING MODES:"
        log_debug "    DRY_RUN: $DRY_RUN (original: $ORIGINAL_DRY_RUN)"
        log_debug "    DEBUG: $DEBUG (original: $ORIGINAL_DEBUG)"
        log_debug "    RUTOS_TEST_MODE: $RUTOS_TEST_MODE (original: $ORIGINAL_RUTOS_TEST_MODE)"
        log_debug "    LOG_LEVEL: $LOG_LEVEL"
    fi
}

# ============================================================================
# DRY-RUN SAFE EXECUTION FRAMEWORK
# ============================================================================

# Safe command execution function
safe_execute() {
    command="$1"
    description="$2"

    # Enhanced tracing for RUTOS_TEST_MODE
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "=== COMMAND EXECUTION START ==="
        log_trace "Description: $description"
        log_trace "Command: $command"
        log_trace "Current Directory: $(pwd)"
        log_trace "Environment: DRY_RUN=$DRY_RUN DEBUG=$DEBUG"
        log_trace "Timestamp: $(date '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date)"
    fi

    # Log the command in trace mode
    log_command_execution "$command"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        if [ "$DEBUG" = "1" ]; then
            log_debug "Command: $command"
        fi
        if [ "$RUTOS_TEST_MODE" = "1" ]; then
            log_trace "DRY-RUN: Command would be executed but is being simulated"
            log_trace "Expected output: [simulated - actual command not run]"
            log_trace "=== COMMAND EXECUTION END (DRY-RUN) ==="
        fi
        return 0
    else
        log_step "Executing: $description"
        if [ "$DEBUG" = "1" ]; then
            log_debug "Command: $command"
        fi

        if [ "$RUTOS_TEST_MODE" = "1" ]; then
            log_trace "REAL EXECUTION: About to run actual command"
        fi

        # Execute the actual command
        if eval "$command"; then
            exit_code=0
            log_debug "Command succeeded: $description"
            if [ "$RUTOS_TEST_MODE" = "1" ]; then
                log_trace "EXECUTION RESULT: Success (exit code: 0)"
                log_trace "=== COMMAND EXECUTION END (SUCCESS) ==="
            fi
            return 0
        else
            exit_code=$?
            log_error "Command failed: $description (exit code: $exit_code)"
            if [ "$RUTOS_TEST_MODE" = "1" ]; then
                log_trace "EXECUTION RESULT: Failed (exit code: $exit_code)"
                log_trace "Error context: Command '$command' failed"
                log_trace "=== COMMAND EXECUTION END (FAILED) ==="
            fi
            return $exit_code
        fi
    fi
}

# Early exit for test modes (prevents real execution)
check_test_mode_exit() {
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ] && [ "${ALLOW_TEST_EXECUTION:-0}" != "1" ]; then
        # In RUTOS_TEST_MODE, show what we would normally exit for, but allow demo execution
        if [ "${DEMO_TRACING:-0}" = "1" ]; then
            log_info "RUTOS_TEST_MODE enabled with DEMO_TRACING - continuing execution for demonstration"
            return 0
        else
            log_info "RUTOS_TEST_MODE enabled - script syntax validated, exiting safely"
            exit 0
        fi
    fi
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Auto-setup when module is loaded (unless disabled)
if [ "${RUTOS_LOGGING_NO_AUTO_SETUP:-0}" != "1" ]; then
    setup_logging_levels
fi
