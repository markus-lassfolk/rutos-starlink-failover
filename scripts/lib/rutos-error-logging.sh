#!/bin/sh
# ==============================================================================
# RUTOS Centralized Error Logging System
#
# This module provides comprehensive error capture and logging for the
# autonomous system, ensuring ALL errors are captured regardless of execution
# mode (normal, debug, cron, daemon, manual).
#
# Features:
# - Centralized error log for autonomous monitoring
# - Stack trace capture where possible
# - Environment context capture
# - Error categorization and severity levels
# - Integration with existing logging framework
# ==============================================================================

# Prevent multiple sourcing
if [ "${_RUTOS_ERROR_LOGGING_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_ERROR_LOGGING_LOADED=1

# ============================================================================
# CENTRALIZED ERROR LOGGING CONFIGURATION
# ============================================================================

# Determine if centralized error logging should be enabled
# Priority: 1. Explicit ENABLE_CENTRALIZED_ERROR_LOGGING
#          2. Bootstrap mode (no config exists yet)
#          3. Config setting (after installation)
should_enable_centralized_logging() {
    # Explicit override always wins
    if [ -n "${ENABLE_CENTRALIZED_ERROR_LOGGING:-}" ]; then
        [ "$ENABLE_CENTRALIZED_ERROR_LOGGING" = "true" ]
        return $?
    fi
    
    # Check if we're in bootstrap/installation mode (no config exists)
    local config_path="${CONFIG_DIR:-/etc/starlink-failover}/config.sh"
    if [ ! -f "$config_path" ]; then
        # Bootstrap mode - always enable centralized logging
        return 0
    fi
    
    # Check config setting after installation
    if [ -f "$config_path" ]; then
        # Source config to check ENABLE_AUTONOMOUS_ERROR_LOGGING setting
        if grep -q "ENABLE_AUTONOMOUS_ERROR_LOGGING=.*true" "$config_path" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Default: disabled after installation unless explicitly enabled
    return 1
}

# Error log configuration
CENTRALIZED_ERROR_LOG="${CENTRALIZED_ERROR_LOG:-/tmp/rutos-autonomous-errors.log}"
ERROR_LOG_MAX_SIZE="${ERROR_LOG_MAX_SIZE:-10485760}"  # 10MB default
ERROR_LOG_BACKUP_COUNT="${ERROR_LOG_BACKUP_COUNT:-5}"

# Error categorization
ERROR_CATEGORY_CRITICAL="CRITICAL"
ERROR_CATEGORY_HIGH="HIGH"
ERROR_CATEGORY_MEDIUM="MEDIUM"
ERROR_CATEGORY_LOW="LOW"

# Initialize centralized error logging
init_centralized_error_logging() {
    # Create error log directory if it doesn't exist
    error_log_dir="$(dirname "$CENTRALIZED_ERROR_LOG")"
    if [ ! -d "$error_log_dir" ]; then
        mkdir -p "$error_log_dir" 2>/dev/null || true
    fi
    
    # Create error log if it doesn't exist
    if [ ! -f "$CENTRALIZED_ERROR_LOG" ]; then
        touch "$CENTRALIZED_ERROR_LOG" 2>/dev/null || true
    fi
    
    # Set up log rotation if log is too large
    if [ -f "$CENTRALIZED_ERROR_LOG" ]; then
        log_size=$(wc -c < "$CENTRALIZED_ERROR_LOG" 2>/dev/null || echo "0")
        if [ "$log_size" -gt "$ERROR_LOG_MAX_SIZE" ]; then
            rotate_error_log
        fi
    fi
}

# Rotate error log when it gets too large
rotate_error_log() {
    if [ ! -f "$CENTRALIZED_ERROR_LOG" ]; then
        return 0
    fi
    
    # Rotate backup logs
    i=$ERROR_LOG_BACKUP_COUNT
    while [ $i -gt 1 ]; do
        prev=$((i - 1))
        if [ -f "${CENTRALIZED_ERROR_LOG}.$prev" ]; then
            mv "${CENTRALIZED_ERROR_LOG}.$prev" "${CENTRALIZED_ERROR_LOG}.$i" 2>/dev/null || true
        fi
        i=$prev
    done
    
    # Move current log to .1
    if [ -f "$CENTRALIZED_ERROR_LOG" ]; then
        mv "$CENTRALIZED_ERROR_LOG" "${CENTRALIZED_ERROR_LOG}.1" 2>/dev/null || true
    fi
    
    # Create new log
    touch "$CENTRALIZED_ERROR_LOG" 2>/dev/null || true
}

# ============================================================================
# ENVIRONMENT CONTEXT CAPTURE
# ============================================================================

# Capture comprehensive environment context
capture_environment_context() {
    cat << EOF
=== ENVIRONMENT CONTEXT ===
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Script: ${SCRIPT_NAME:-$(basename "$0" 2>/dev/null || echo "unknown")}
Version: ${SCRIPT_VERSION:-unknown}
PID: $$
PPID: ${PPID:-unknown}
User: $(id -un 2>/dev/null || echo "unknown")
Working Directory: $(pwd 2>/dev/null || echo "unknown")
Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo "$0")
Execution Mode: $(get_execution_mode)
System: $(uname -a 2>/dev/null || echo "unknown")

=== LOGGING CONFIGURATION ===
DRY_RUN: ${DRY_RUN:-0}
DEBUG: ${DEBUG:-0}
RUTOS_TEST_MODE: ${RUTOS_TEST_MODE:-0}
LOG_LEVEL: ${LOG_LEVEL:-INFO}
Centralized Error Log: $CENTRALIZED_ERROR_LOG

=== SCRIPT VARIABLES ===
$(set | grep -E '^(RUTOS_|STARLINK_|MWAN_|ENABLE_|CONFIG_)' 2>/dev/null || echo "No RUTOS variables set")

=== SYSTEM STATE ===
Free Memory: $(free -h 2>/dev/null | grep "Mem:" | awk '{print $7}' || echo "unknown")
Free Disk: $(df -h . 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
Load Average: $(uptime 2>/dev/null | sed 's/.*load average: //' || echo "unknown")
EOF
}

# Detect execution mode (cron, daemon, manual, etc.)
get_execution_mode() {
    # Check if running under cron
    if [ -n "${CRON:-}" ] || [ -n "${CRONTAB:-}" ]; then
        echo "cron"
        return
    fi
    
    # Check if parent is cron
    if ps -p ${PPID:-0} -o comm= 2>/dev/null | grep -q cron; then
        echo "cron"
        return
    fi
    
    # Check if running as daemon (no controlling terminal)
    if [ ! -t 0 ] && [ ! -t 1 ] && [ ! -t 2 ]; then
        echo "daemon"
        return
    fi
    
    # Check if running under systemd/init
    if ps -p ${PPID:-0} -o comm= 2>/dev/null | grep -qE '^(systemd|init)$'; then
        echo "service"
        return
    fi
    
    # Check if running under SSH
    if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_CONNECTION:-}" ]; then
        echo "ssh"
        return
    fi
    
    # Default to manual
    echo "manual"
}

# ============================================================================
# STACK TRACE CAPTURE (POSIX-compatible)
# ============================================================================

# Capture call stack (limited in POSIX sh but we do what we can)
capture_call_stack() {
    echo "=== CALL STACK ==="
    
    # Try to get some stack information
    if [ -n "${BASH_SOURCE:-}" ]; then
        # Bash-specific stack trace
        local i=0
        while [ $i -lt ${#BASH_SOURCE[@]} ]; do
            echo "  [$i] ${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$i]:-?} in ${FUNCNAME[$i+1]:-main}()"
            i=$((i + 1))
        done
    else
        # POSIX fallback - very limited
        echo "  [0] $(basename "$0" 2>/dev/null || echo "unknown"):? in main()"
        echo "  [1] Called from: ${CALLING_SCRIPT:-unknown}"
    fi
    
    echo "=== END CALL STACK ==="
}

# ============================================================================
# CENTRALIZED ERROR LOGGING FUNCTIONS
# ============================================================================

# Log error to centralized log with full context
log_error_centralized() {
    local error_message="$1"
    local error_category="${2:-$ERROR_CATEGORY_MEDIUM}"
    local script_context="${3:-}"
    local line_number="${4:-unknown}"
    local function_name="${5:-main}"
    
    # Check if centralized logging should be enabled
    if ! should_enable_centralized_logging; then
        # Centralized logging disabled - use regular logging only
        if command -v log_error >/dev/null 2>&1; then
            log_error "[$error_category] $error_message"
        else
            printf "${RED}[ERROR]${NC} [$error_category] %s\n" "$error_message" >&2
        fi
        return 0
    fi
    
    # Always initialize error logging when enabled
    init_centralized_error_logging
    
    # Generate unique error ID
    local error_id="ERR_$(date +%s)_$$_$(head -c 8 /dev/urandom 2>/dev/null | base64 | tr -d '+/=' | head -c 8 2>/dev/null || echo "$(date +%N)")"
    
    # Create comprehensive error entry
    {
        echo "===== AUTONOMOUS ERROR ENTRY ====="
        echo "Error ID: $error_id"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Category: $error_category"
        echo "Host: $(hostname 2>/dev/null || echo "unknown")"
        echo "Script: $(basename "$0" 2>/dev/null || echo "unknown")"
        echo "Line: $line_number"
        echo "Function: $function_name"
        echo "Error: $error_message"
        
        if [ -n "$script_context" ]; then
            echo "Context: $script_context"
        fi
        
        echo ""
        capture_environment_context
        echo ""
        capture_call_stack
        echo ""
        echo "===== END ERROR ENTRY ====="
        echo ""
    } >> "$CENTRALIZED_ERROR_LOG" 2>/dev/null || true
    
    # Also log to regular error logging
    log_error "[$error_category] $error_message (Error ID: $error_id)"
    
    # Log to syslog for immediate system monitoring
    if command -v logger >/dev/null 2>&1; then
        logger -t "rutos-autonomous" -p daemon.err "ERROR [$error_category] $error_message (ID: $error_id)"
    fi
    
    return 0
}

# Enhanced error logging functions for different severity levels
log_critical_error() {
    log_error_centralized "$1" "$ERROR_CATEGORY_CRITICAL" "$2" "$3" "$4"
}

log_high_error() {
    log_error_centralized "$1" "$ERROR_CATEGORY_HIGH" "$2" "$3" "$4"
}

log_medium_error() {
    log_error_centralized "$1" "$ERROR_CATEGORY_MEDIUM" "$2" "$3" "$4"
}

log_low_error() {
    log_error_centralized "$1" "$ERROR_CATEGORY_LOW" "$2" "$3" "$4"
}

# ============================================================================
# COMMAND EXECUTION WITH ERROR CAPTURE
# ============================================================================

# Enhanced safe_execute with comprehensive error logging
safe_execute_with_error_capture() {
    local command="$1"
    local description="$2"
    local error_category="${3:-$ERROR_CATEGORY_MEDIUM}"
    
    # Log command execution in trace mode
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_trace "EXECUTING: $description - $command"
    fi
    
    # Execute command and capture output and exit code
    local output
    local exit_code
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "DRY-RUN: $description"
        log_debug "Would execute: $command"
        return 0
    else
        # Capture both stdout and stderr
        if output=$(eval "$command" 2>&1); then
            exit_code=0
            if [ "$DEBUG" = "1" ]; then
                log_debug "Command succeeded: $description"
                if [ -n "$output" ]; then
                    log_debug "Output: $output"
                fi
            fi
        else
            exit_code=$?
            
            # Log detailed error information to centralized log
            local error_context="Command: $command | Description: $description | Exit Code: $exit_code"
            if [ -n "$output" ]; then
                error_context="$error_context | Output: $output"
            fi
            
            log_error_centralized "Command execution failed: $description" "$error_category" "$error_context" "$(caller 2>/dev/null | cut -d' ' -f1 || echo 'unknown')" "safe_execute_with_error_capture"
            
            # Also log to regular error logging
            log_error "Command failed: $description (exit code: $exit_code)"
            if [ -n "$output" ]; then
                log_error "Command output: $output"
            fi
        fi
    fi
    
    return $exit_code
}

# ============================================================================
# ERROR TRAP HANDLING
# ============================================================================

# Set up error trap for automatic error capture
setup_error_trap() {
    # Only set up trap if we're in a supported shell
    if [ -n "${BASH_VERSION:-}" ]; then
        # Bash-specific error trap
        set -E  # Enable error trap inheritance
        trap 'handle_trapped_error $? $LINENO $BASH_COMMAND' ERR
    elif [ -n "${ZSH_VERSION:-}" ]; then
        # Zsh-specific error trap
        trap 'handle_trapped_error $? $LINENO' ERR
    else
        # POSIX fallback - limited functionality
        trap 'handle_trapped_error $? "unknown"' EXIT
    fi
}

# Handle trapped errors
handle_trapped_error() {
    local exit_code="$1"
    local line_number="${2:-unknown}"
    local command="${3:-unknown}"
    
    # Don't handle successful exits
    if [ "$exit_code" -eq 0 ]; then
        return 0
    fi
    
    # Log the trapped error
    local error_context="Exit Code: $exit_code | Line: $line_number"
    if [ "$command" != "unknown" ]; then
        error_context="$error_context | Command: $command"
    fi
    
    log_error_centralized "Script execution error (trapped)" "$ERROR_CATEGORY_HIGH" "$error_context" "$line_number" "error_trap"
}

# ============================================================================
# INTEGRATION FUNCTIONS
# ============================================================================

# Enhanced version of log_error that always logs to centralized system
log_error_enhanced() {
    local error_message="$1"
    local error_category="${2:-$ERROR_CATEGORY_MEDIUM}"
    
    # Always log to centralized system
    log_error_centralized "$error_message" "$error_category" "" "$(caller 2>/dev/null | cut -d' ' -f1 || echo 'unknown')" "$(caller 2>/dev/null | cut -d' ' -f2 || echo 'unknown')"
    
    # Also call original log_error if available
    if command -v log_error >/dev/null 2>&1; then
        log_error "$error_message"
    fi
}

# Override the original log_error function to include centralized logging
if should_enable_centralized_logging; then
    # Save original log_error if it exists
    if command -v log_error >/dev/null 2>&1; then
        eval "log_error_original() { $(declare -f log_error | sed '1d'); }"
    fi
    
    # Replace log_error with enhanced version
    log_error() {
        log_error_enhanced "$@"
    }
    
    _CENTRALIZED_LOGGING_ACTIVE=1
else
    _CENTRALIZED_LOGGING_ACTIVE=0
fi

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize centralized error logging system
initialize_centralized_error_logging() {
    # Check if centralized logging should be enabled
    if ! should_enable_centralized_logging; then
        if [ "$DEBUG" = "1" ]; then
            log_debug "Centralized error logging disabled (not in bootstrap mode and not enabled in config)"
        fi
        return 0
    fi
    
    # Set up error logging
    init_centralized_error_logging
    
    # Set up error trap if enabled
    if [ "${ENABLE_ERROR_TRAP:-true}" = "true" ]; then
        setup_error_trap
    fi
    
    # Log initialization
    if [ "$DEBUG" = "1" ]; then
        log_debug "Centralized error logging initialized"
        log_debug "Error log: $CENTRALIZED_ERROR_LOG"
        log_debug "Execution mode: $(get_execution_mode)"
        if [ ! -f "${CONFIG_DIR:-/etc/starlink-failover}/config.sh" ]; then
            log_debug "Bootstrap mode: Config not found, centralized logging auto-enabled"
        else
            log_debug "Config mode: Centralized logging enabled via configuration"
        fi
    fi
}

# Auto-initialize when sourced
initialize_centralized_error_logging

log_debug "RUTOS Centralized Error Logging System loaded successfully"
