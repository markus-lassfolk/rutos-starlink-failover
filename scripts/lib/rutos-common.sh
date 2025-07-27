#!/bin/sh
# ==============================================================================
# RUTOS Common Utilities Library
#
# Common utility functions used across RUTOS scripts.
# POSIX sh compatible for busybox environments.
# ==============================================================================

# Prevent multiple sourcing
if [ "${_RUTOS_COMMON_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_COMMON_LOADED=1

# Source logging if not already loaded
if [ "${_RUTOS_LOGGING_LOADED:-}" != "1" ]; then
    # Try to find logging module relative to this script
    _lib_dir="$(dirname "$0")/lib"
    if [ -f "$_lib_dir/rutos-logging.sh" ]; then
        . "$_lib_dir/rutos-logging.sh"
    elif [ -f "$(dirname "$0")/../scripts/lib/rutos-logging.sh" ]; then
        . "$(dirname "$0")/../scripts/lib/rutos-logging.sh"
    fi
fi

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

# Check if running on RUTOS system
is_rutos_system() {
    if [ -f "/etc/openwrt_release" ]; then
        return 0
    else
        return 1
    fi
}

# Validate RUTOS environment
validate_rutos_environment() {
    log_function_entry "validate_rutos_environment" ""

    if ! is_rutos_system; then
        log_warning "Not running on RUTOS/OpenWrt system"
        if [ "$RUTOS_TEST_MODE" != "1" ] && [ "$DRY_RUN" != "1" ]; then
            log_error "This script is designed for RUTOS systems"
            return 1
        fi
    fi

    # Version information for troubleshooting
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "Script: rutos-common.sh"
    fi
    log_debug "RUTOS environment validated"
    log_function_exit "validate_rutos_environment" "0"
    return 0
}

# ============================================================================
# COMMAND AVAILABILITY
# ============================================================================

# Check if command exists
command_exists() {
    command="$1"
    log_trace "Checking if command exists: $command"

    if command -v "$command" >/dev/null 2>&1; then
        log_trace "Command available: $command"
        return 0
    else
        log_trace "Command not available: $command"
        return 1
    fi
}

# Require command to exist
require_command() {
    command="$1"
    package="${2:-$command}"

    log_function_entry "require_command" "$command"

    if ! command_exists "$command"; then
        log_error "Required command not found: $command"
        log_error "Please install package: $package"
        log_function_exit "require_command" "1"
        return 1
    fi

    log_debug "Required command available: $command"
    log_function_exit "require_command" "0"
    return 0
}

# ============================================================================
# FILE AND DIRECTORY OPERATIONS
# ============================================================================

# Safely create directory
safe_mkdir() {
    dir_path="$1"
    permissions="${2:-755}"

    log_function_entry "safe_mkdir" "$dir_path"

    if [ -d "$dir_path" ]; then
        log_debug "Directory already exists: $dir_path"
        log_function_exit "safe_mkdir" "0"
        return 0
    fi

    safe_execute "mkdir -p '$dir_path' && chmod $permissions '$dir_path'" \
        "Create directory: $dir_path"

    exit_code=$?
    log_function_exit "safe_mkdir" "$exit_code"
    return $exit_code
}

# Safely backup file
safe_backup() {
    source_file="$1"
    backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"

    log_function_entry "safe_backup" "$source_file"

    if [ ! -f "$source_file" ]; then
        log_debug "Source file does not exist, no backup needed: $source_file"
        log_function_exit "safe_backup" "0"
        return 0
    fi

    backup_file="${source_file}${backup_suffix}"
    safe_execute "cp '$source_file' '$backup_file'" \
        "Backup file: $source_file -> $backup_file"

    exit_code=$?
    log_function_exit "safe_backup" "$exit_code"
    return $exit_code
}

# Check if file is writable
is_file_writable() {
    file_path="$1"

    log_trace "Checking if file is writable: $file_path"

    if [ -w "$file_path" ]; then
        log_trace "File is writable: $file_path"
        return 0
    else
        log_trace "File is not writable: $file_path"
        return 1
    fi
}

# ============================================================================
# NETWORK UTILITIES
# ============================================================================

# Test network connectivity
test_connectivity() {
    host="$1"
    port="${2:-80}"
    timeout="${3:-5}"

    log_function_entry "test_connectivity" "$host:$port"

    # Use netcat if available, otherwise try ping
    if command_exists nc; then
        log_trace "Testing connectivity with netcat: $host:$port"
        if nc -z -w "$timeout" "$host" "$port" 2>/dev/null; then
            log_trace "Connectivity successful: $host:$port"
            log_function_exit "test_connectivity" "0"
            return 0
        fi
    elif command_exists ping; then
        log_trace "Testing connectivity with ping: $host"
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            log_trace "Ping successful: $host"
            log_function_exit "test_connectivity" "0"
            return 0
        fi
    else
        log_warning "No network testing tools available (nc or ping)"
        log_function_exit "test_connectivity" "1"
        return 1
    fi

    log_trace "Connectivity failed: $host:$port"
    log_function_exit "test_connectivity" "1"
    return 1
}

# ============================================================================
# PROCESS AND SERVICE MANAGEMENT
# ============================================================================

# Check if process is running
is_process_running() {
    process_name="$1"

    log_trace "Checking if process is running: $process_name"

    if pgrep "$process_name" >/dev/null 2>&1; then
        log_trace "Process is running: $process_name"
        return 0
    else
        log_trace "Process is not running: $process_name"
        return 1
    fi
}

# Safely restart service
safe_service_restart() {
    service_name="$1"

    log_function_entry "safe_service_restart" "$service_name"

    safe_execute "/etc/init.d/$service_name restart" \
        "Restart service: $service_name"

    exit_code=$?
    log_function_exit "safe_service_restart" "$exit_code"
    return $exit_code
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Load configuration file safely
load_config() {
    config_file="$1"

    log_function_entry "load_config" "$config_file"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        log_function_exit "load_config" "1"
        return 1
    fi

    if [ ! -r "$config_file" ]; then
        log_error "Configuration file not readable: $config_file"
        log_function_exit "load_config" "1"
        return 1
    fi

    log_debug "Loading configuration: $config_file"

    # Source the configuration file
    if . "$config_file"; then
        log_debug "Configuration loaded successfully: $config_file"
        log_function_exit "load_config" "0"
        return 0
    else
        log_error "Failed to load configuration: $config_file"
        log_function_exit "load_config" "1"
        return 1
    fi
}

# ============================================================================
# STRING AND DATA UTILITIES
# ============================================================================

# Trim whitespace from string
trim_whitespace() {
    string="$1"
    # Remove leading and trailing whitespace
    # shellcheck disable=SC2001 # sed is more reliable than parameter expansion for complex whitespace
    echo "$string" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Check if string is empty
is_empty() {
    string="$1"
    trimmed=$(trim_whitespace "$string")
    [ -z "$trimmed" ]
}

# Check if string contains substring
string_contains() {
    string="$1"
    substring="$2"

    case "$string" in
        *"$substring"*) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# CLEANUP AND ERROR HANDLING
# ============================================================================

# Cleanup function template
cleanup_on_exit() {
    log_debug "Cleanup function called"
    # Remove temporary files
    rm -f /tmp/*_$$* 2>/dev/null || true
}

# Set up signal handlers for cleanup
setup_cleanup_handlers() {
    trap 'cleanup_on_exit; exit 130' INT  # Ctrl+C
    trap 'cleanup_on_exit; exit 143' TERM # Termination
    trap 'cleanup_on_exit' EXIT           # Normal exit
}

# ============================================================================
# VERSION AND UPDATE UTILITIES
# ============================================================================

# Extract version from script
get_script_version() {
    script_file="$1"

    if [ -f "$script_file" ]; then
        grep '^SCRIPT_VERSION=' "$script_file" 2>/dev/null | head -1 | sed 's/.*="\(.*\)"/\1/'
    else
        echo "unknown"
    fi
}

# Compare version strings (basic semantic version comparison)
version_compare() {
    version1="$1"
    version2="$2"

    # Convert versions to comparable format
    # shellcheck disable=SC2001 # sed is more reliable for complex character removal in busybox
    v1=$(echo "$version1" | sed 's/[^0-9.]//g')
    # shellcheck disable=SC2001 # sed is more reliable for complex character removal in busybox
    v2=$(echo "$version2" | sed 's/[^0-9.]//g')

    if [ "$v1" = "$v2" ]; then
        return 0 # Equal
    elif [ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ]; then
        return 1 # v1 < v2
    else
        return 2 # v1 > v2
    fi
}

# ============================================================================
# BACKWARDS COMPATIBILITY FUNCTIONS
# ============================================================================

# DEPRECATED: log_message compatibility function
# This function provides backwards compatibility for scripts using the old log_message format
# New scripts should use the standard RUTOS logging functions directly
log_message() {
    level="$1"
    message="$2"
    
    # Show deprecation warning in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_trace "DEPRECATED: log_message() called with level '$level' - use log_info(), log_error(), etc. instead"
    fi
    
    # Map old log levels to new RUTOS library functions
    case "$level" in
        "INFO"|"info")
            log_info "$message"
            ;;
        "ERROR"|"error")
            log_error "$message"
            ;;
        "WARNING"|"warning"|"WARN"|"warn")
            log_warning "$message"
            ;;
        "DEBUG"|"debug")
            log_debug "$message"
            ;;
        "SUCCESS"|"success")
            log_success "$message"
            ;;
        "CONFIG_DEBUG"|"config_debug")
            log_debug "CONFIG: $message"
            ;;
        "DEBUG_EXEC"|"debug_exec")
            log_debug "EXEC: $message"
            ;;
        *)
            # Unknown level - default to info but show warning
            log_warning "Unknown log level '$level' in deprecated log_message() call"
            log_info "$message"
            ;;
    esac
}
