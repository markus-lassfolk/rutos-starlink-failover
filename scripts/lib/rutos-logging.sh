#!/bin/sh
# ==============================================================================
# RUTOS Logging Framework
#
# Version: 2.7.1
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# Provides 4-level standardized logging system for all RUTOS scripts:
# - NORMAL: Standard operation info
# - DRY_RUN: Shows what would be done without executing
# - DEBUG: Detailed debugging information with context
# - RUTOS_TEST_MODE: Full execution trace with command tracking
# ==============================================================================

# Prevent multiple sourcing

# Version information (auto-updated by update-version.sh)
# Only set if not already defined as readonly
if ! readonly SCRIPT_VERSION 2>/dev/null; then
    SCRIPT_VERSION="2.7.1"
    readonly SCRIPT_VERSION
fi
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

    timestamp=$(get_timestamp)

    if [ "$destination" = "stderr" ]; then
        printf "${color}[%s]${NC} [%s] %s\n" "$level" "$timestamp" "$message" >&2
    else
        printf "${color}[%s]${NC} [%s] %s\n" "$level" "$timestamp" "$message"
    fi
}

# Standard logging functions
# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: rutos-logging.sh v$SCRIPT_VERSION"
fi
log_info() {
    _log_message "INFO" "$GREEN" "$1" "stdout"
}

log_success() {
    _log_message "SUCCESS" "$GREEN" "$1" "stdout"
}

log_warning() {
    _log_message "WARNING" "$YELLOW" "$1" "stderr"
}

log_error() {
    _log_message "ERROR" "$RED" "$1" "stderr"
}

log_step() {
    _log_message "STEP" "$BLUE" "$1" "stdout"
}

# Debug logging (only shown when DEBUG=1)
log_debug() {
    if [ "$DEBUG" = "1" ]; then
        _log_message "DEBUG" "$CYAN" "$1" "stderr"
    fi
}

# Trace logging (only shown when RUTOS_TEST_MODE=1)
log_trace() {
    if [ "$RUTOS_TEST_MODE" = "1" ] || [ "$LOG_LEVEL" = "TRACE" ]; then
        _log_message "TRACE" "$PURPLE" "$1" "stderr"
    fi
}

# ============================================================================
# ENHANCED CALLER INFORMATION TRACKING
# ============================================================================

# Function call stack tracking (for automatic function tracing)
_FUNCTION_STACK=""
_FUNCTION_DEPTH=0

# Get caller information for line number tracking
get_caller_info() {
    # Get the calling script name
    caller_script="${0##*/}" # Just the basename

    # Use manual tracking approach since POSIX sh doesn't have BASH_LINENO
    caller_line="${CURRENT_LINE:-unknown}"
    caller_function="${CURRENT_FUNCTION:-main}"

    echo "$caller_script:$caller_line:$caller_function"
}

# Manual line context setting (call this before important operations)
set_line_context() {
    CURRENT_LINE="$1"
    CURRENT_FUNCTION="${2:-main}"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "CONTEXT: Line $CURRENT_LINE, Function $CURRENT_FUNCTION"
    fi
}

# ============================================================================
# AUTOMATIC FUNCTION TRACING (NO SCRIPT MODIFICATIONS NEEDED)
# ============================================================================

# Push function onto call stack
_push_function_stack() {
    func_name="$1"
    func_args="$2"

    _FUNCTION_DEPTH=$((_FUNCTION_DEPTH + 1))
    _FUNCTION_STACK="$func_name|$_FUNCTION_STACK"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        # Create indentation based on function depth
        indent=""
        i=1
        while [ "$i" -lt "$_FUNCTION_DEPTH" ]; do
            indent="  $indent"
            i=$((i + 1))
        done

        caller_info=$(get_caller_info)
        log_trace "FUNC_ENTER [$caller_info] ${indent}→ $func_name($func_args) [depth: $_FUNCTION_DEPTH]"
    fi
}

# Pop function from call stack
_pop_function_stack() {
    func_name="$1"
    return_value="$2"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        # Create indentation based on function depth
        indent=""
        i=1
        while [ "$i" -lt "$_FUNCTION_DEPTH" ]; do
            indent="  $indent"
            i=$((i + 1))
        done

        caller_info=$(get_caller_info)
        log_trace "FUNC_EXIT [$caller_info] ${indent}← $func_name() returns: $return_value [depth: $_FUNCTION_DEPTH]"
    fi

    # Remove function from stack
    _FUNCTION_STACK="${_FUNCTION_STACK#*|}"
    _FUNCTION_DEPTH=$((_FUNCTION_DEPTH - 1))
    if [ "$_FUNCTION_DEPTH" -lt 0 ]; then
        _FUNCTION_DEPTH=0
    fi
}

# Get current function stack as a readable string
get_function_stack() {
    if [ -n "$_FUNCTION_STACK" ]; then
        echo "$_FUNCTION_STACK" | tr '|' ' → '
    else
        echo "main"
    fi
}

# Enhanced function wrapper - automatically traces function entry/exit
# Usage: trace_function "function_name" "args" && { your_function_body; trace_function_exit $?; }
trace_function() {
    func_name="$1"
    shift
    func_args="$*"

    _push_function_stack "$func_name" "$func_args"

    # Set current function context
    CURRENT_FUNCTION="$func_name"

    return 0
}

# Mark function exit with return value
trace_function_exit() {
    exit_code="${1:-0}"
    func_name="${CURRENT_FUNCTION:-unknown}"

    # Determine return value description
    if [ "$exit_code" = "0" ]; then
        return_desc="success"
    else
        return_desc="error (exit code: $exit_code)"
    fi

    _pop_function_stack "$func_name" "$return_desc"

    # Restore previous function context from stack
    if [ -n "$_FUNCTION_STACK" ]; then
        CURRENT_FUNCTION="${_FUNCTION_STACK%%|*}"
    else
        CURRENT_FUNCTION="main"
    fi

    return $exit_code
}

# ============================================================================
# AUTOMATIC SHELL TRACING (POSIX COMPATIBLE)
# ============================================================================

# Enable automatic function tracing using PS4 and set -x
enable_automatic_function_tracing() {
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        # Set PS4 to show function and line information
        export PS4='TRACE[${0##*/}:${LINENO:-?}:${FUNCNAME:-main}]: '

        # Enable shell tracing - this will show every command execution
        set -x

        log_trace "Automatic shell tracing enabled (set -x)"
        log_trace "All commands will be traced with PS4 format"
    fi
}

# Disable automatic function tracing
disable_automatic_function_tracing() {
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        set +x
        log_trace "Automatic shell tracing disabled"
    fi
}

# Enable selective function tracing (only for specific functions)
enable_selective_function_tracing() {
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        # This sets up the environment for manual function tracing
        log_trace "Selective function tracing enabled"
        log_trace "Use trace_function() and trace_function_exit() in your functions"
        log_trace "Example:"
        log_trace "  my_function() {"
        log_trace "    trace_function 'my_function' \"\$@\""
        log_trace "    # ... function body ..."
        log_trace "    trace_function_exit \$?"
        log_trace "  }"
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
        caller_info=$(get_caller_info)
        log_trace "VARIABLE [$caller_info]: $var_name changed from '$old_value' to '$new_value'"
    fi
}

# Log function entry (for DEBUG mode)
log_function_entry() {
    func_name="$1"
    func_args="$2"

    if [ "$DEBUG" = "1" ]; then
        caller_info=$(get_caller_info)
        log_debug "FUNCTION ENTRY [$caller_info]: $func_name($func_args)"
    fi
}

# Log function exit (for DEBUG mode)
log_function_exit() {
    func_name="$1"
    exit_code="$2"

    if [ "$DEBUG" = "1" ]; then
        caller_info=$(get_caller_info)
        log_debug "FUNCTION EXIT [$caller_info]: $func_name with code $exit_code"
    fi
}

# Log command execution (for TRACE mode)
log_command_execution() {
    command="$1"

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        caller_info=$(get_caller_info)
        log_trace "EXECUTING [$caller_info]: $command"
    fi
}

# ============================================================================
# ERROR HANDLING AND STACK TRACES
# ============================================================================

# Enhanced error reporting with exit code context (for DEBUG mode)
log_error_with_exit_code() {
    error_message="$1"
    exit_code="$2"
    command="${3:-unknown command}"
    line="${4:-${CURRENT_LINE:-unknown}}"
    function_name="${5:-${CURRENT_FUNCTION:-main}}"

    # Always log the basic error
    log_error "$error_message (exit code: $exit_code)"

    # Enhanced analysis only in DEBUG mode
    if [ "$DEBUG" = "1" ]; then
        # Provide context about common exit codes
        case "$exit_code" in
            1) exit_meaning="General error" ;;
            2) exit_meaning="Misuse of shell builtins" ;;
            126) exit_meaning="Command invoked cannot execute" ;;
            127) exit_meaning="Command not found" ;;
            128) exit_meaning="Invalid argument to exit" ;;
            130) exit_meaning="Script terminated by Control-C" ;;
            255) exit_meaning="Exit status out of range" ;;
            *) exit_meaning="Application-specific error" ;;
        esac

        log_debug "ERROR ANALYSIS:"
        log_debug "  Exit Code: $exit_code ($exit_meaning)"
        log_debug "  Failed Command: $command"
        log_debug "  Script Location: Line $line, Function $function_name"
        log_debug "  Working Directory: $(pwd)"
        log_debug "  Environment: DRY_RUN=$DRY_RUN DEBUG=$DEBUG RUTOS_TEST_MODE=$RUTOS_TEST_MODE"

        # Additional context for specific error codes
        case "$exit_code" in
            127)
                log_debug "  Suggestion: Check if the command is installed and in PATH"
                ;;
            126)
                log_debug "  Suggestion: Check file permissions and execute bit"
                ;;
            130)
                log_debug "  Info: Script was interrupted by user (Ctrl+C)"
                ;;
        esac
    fi
}

# Enhanced error logging with context
log_error_with_context() {
    error_message="$1"
    script_name="${2:-$(basename "$0")}"
    line_number="${3:-${CURRENT_LINE:-unknown}}"
    function_name="${4:-${CURRENT_FUNCTION:-main}}"

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

# Enhanced stack trace functionality (for DEBUG mode)
print_stack_trace() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "=== STACK TRACE ==="
        log_debug "Current script: ${0##*/}"
        log_debug "Current directory: $(pwd)"
        log_debug "Current function: ${CURRENT_FUNCTION:-main}"
        log_debug "Current line context: ${CURRENT_LINE:-unknown}"
        log_debug "Process ID: $$"
        log_debug "Parent Process ID: $PPID"
        log_debug "Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo 'unknown')"
        log_debug "=== END STACK TRACE ==="
    fi
}

# Log script initialization (shows active logging modes)
log_script_init() {
    script_name="$1"
    script_version="$2"
    tracing_mode="${3:-selective}" # "automatic", "selective", or "off"

    # Set initial context
    set_line_context "1" "main"

    log_info "Starting $script_name v$script_version"

    if [ "$DEBUG" = "1" ]; then
        log_debug "ENVIRONMENT:"
        log_debug "  Working Directory: $(pwd)"
        log_debug "  Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo 'unknown')"
        log_debug "  LOGGING MODES:"
        log_debug "    DRY_RUN: $DRY_RUN (original: $ORIGINAL_DRY_RUN)"
        log_debug "    DEBUG: $DEBUG (original: $ORIGINAL_DEBUG) - Enhanced error analysis enabled"
        log_debug "    RUTOS_TEST_MODE: $RUTOS_TEST_MODE (original: $ORIGINAL_RUTOS_TEST_MODE) - Line tracking enabled"
        log_debug "    LOG_LEVEL: $LOG_LEVEL"
        log_debug "  ENHANCED FEATURES:"
        log_debug "    Line tracking: Use set_line_context(line, function)"
        log_debug "    Error analysis: Automatic exit code analysis in DEBUG mode"
        log_debug "    Stack traces: Available for critical errors"
        log_debug "    Function tracing: $tracing_mode mode"
    fi

    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "Enhanced RUTOS logging framework initialized"
        log_trace "Features: Line number tracking, enhanced error reporting, stack traces"
        log_trace "Usage: Call set_line_context() before important operations for better tracing"

        # Initialize function tracing based on mode
        case "$tracing_mode" in
            "automatic")
                enable_automatic_function_tracing
                ;;
            "selective")
                enable_selective_function_tracing
                ;;
            "off")
                log_trace "Function tracing disabled"
                ;;
            *)
                log_trace "Unknown tracing mode: $tracing_mode, using selective mode"
                enable_selective_function_tracing
                ;;
        esac
    fi
}

# ============================================================================
# DRY-RUN SAFE EXECUTION FRAMEWORK
# ============================================================================

# Safe command execution function
safe_execute() {
    command="$1"
    description="$2"

    # Enhanced tracing for RUTOS_TEST_MODE with line numbers
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        caller_info=$(get_caller_info)
        log_trace "=== COMMAND EXECUTION START [$caller_info] ==="
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
            # Use enhanced error reporting with exit code analysis
            log_error_with_exit_code "Command failed: $description" "$exit_code" "$command"

            if [ "$RUTOS_TEST_MODE" = "1" ]; then
                caller_info=$(get_caller_info)
                log_trace "EXECUTION RESULT: Failed (exit code: $exit_code)"
                log_trace "Failure Location: $caller_info"
                log_trace "Error Command: $command"
                log_trace "=== COMMAND EXECUTION END (FAILED) ==="
            fi

            # Show stack trace for critical errors in debug mode
            if [ "$DEBUG" = "1" ] && [ "$exit_code" -ne 0 ]; then
                print_stack_trace
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
