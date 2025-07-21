#!/bin/sh
# Script: repair-system-rutos.sh
# Version: 2.4.12
# Description: Automatic system repair for common Starlink monitoring issues
# Compatible with: RUTOS (busybox sh)

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Version information (used for logging and debugging)
# shellcheck disable=SC2034  # SCRIPT_VERSION used for version tracking
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
# shellcheck disable=SC2034  # CYAN may be used in future enhancements
# shellcheck disable=SC2034  # CYAN is available for future use if needed
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    # shellcheck disable=SC2034  # CYAN is available for future use if needed
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Constants
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"
CRON_FILE="/etc/crontabs/root"

# Print header
print_header() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${PURPLE}                    STARLINK SYSTEM REPAIR${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

# Show usage
show_usage() {
    printf "Usage: %s [OPTION]\n\n" "$(basename "$0")"
    printf "Options:\n"
    printf "  --cron          Repair cron job issues\n"
    printf "  --config        Repair configuration issues\n"
    printf "  --permissions   Fix file permissions\n"
    printf "  --logs          Clean and rotate logs\n"
    printf "  --database      Fix database issues\n"
    printf "  --all           Run all repair operations\n"
    printf "  --help          Show this help message\n\n"
    printf "Examples:\n"
    printf "  %s --all          # Run all repairs\n" "$(basename "$0")"
    printf "  %s --cron         # Fix cron issues only\n" "$(basename "$0")"
    printf "  %s --config       # Fix config issues only\n" "$(basename "$0")"
}

# Repair cron jobs
repair_cron() {
    log_step "Repairing cron job configuration"

    # Check if cron file exists
    if [ ! -f "$CRON_FILE" ]; then
        log_warning "Cron file doesn't exist, creating it"
        touch "$CRON_FILE"
    fi

    # Check for required cron entries
    monitor_entries=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
    logger_entries=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

    repairs_made=0

    if [ "$monitor_entries" -eq 0 ]; then
        log_warning "Missing monitor cron job, adding it"
        echo "* * * * * CONFIG_FILE=$CONFIG_FILE $INSTALL_DIR/scripts/starlink_monitor-rutos.sh" >>"$CRON_FILE"
        repairs_made=$((repairs_made + 1))
    fi

    if [ "$logger_entries" -eq 0 ]; then
        log_warning "Missing logger cron job, adding it"
        echo "* * * * * CONFIG_FILE=$CONFIG_FILE $INSTALL_DIR/scripts/starlink_logger-rutos.sh" >>"$CRON_FILE"
        repairs_made=$((repairs_made + 1))
    fi

    # Restart cron service
    if [ $repairs_made -gt 0 ]; then
        if /etc/init.d/cron restart >/dev/null 2>&1; then
            log_success "Cron service restarted successfully"
        else
            log_warning "Could not restart cron service, changes will take effect on next boot"
        fi
        log_success "Added $repairs_made missing cron job(s)"
    else
        log_info "Cron jobs are properly configured"
    fi
}

# Repair configuration
repair_config() {
    log_step "Repairing configuration issues"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Please run the installation script to create the configuration"
        return 1
    fi

    # Run configuration validation with repair
    if [ -f "$INSTALL_DIR/scripts/validate-config-rutos.sh" ]; then
        log_info "Running configuration validation and repair"
        if "$INSTALL_DIR/scripts/validate-config-rutos.sh" "$CONFIG_FILE" --repair; then
            log_success "Configuration validation and repair completed"
        else
            log_warning "Configuration validation completed with warnings"
        fi
    else
        log_warning "Configuration validator not found"
    fi

    # Check configuration permissions
    if [ ! -r "$CONFIG_FILE" ]; then
        log_warning "Configuration file is not readable, fixing permissions"
        chmod 644 "$CONFIG_FILE" 2>/dev/null || log_error "Could not fix config file permissions"
    fi
}

# Fix file permissions
repair_permissions() {
    log_step "Fixing file permissions"

    fixes_made=0

    # Fix script permissions
    if [ -d "$INSTALL_DIR/scripts" ]; then
        for script in "$INSTALL_DIR/scripts"/*.sh; do
            if [ -f "$script" ] && [ ! -x "$script" ]; then
                chmod +x "$script" 2>/dev/null && fixes_made=$((fixes_made + 1))
            fi
        done
    fi

    # Fix binary permissions
    for binary in "$INSTALL_DIR/grpcurl" "$INSTALL_DIR/jq"; do
        if [ -f "$binary" ] && [ ! -x "$binary" ]; then
            chmod +x "$binary" 2>/dev/null && fixes_made=$((fixes_made + 1))
        fi
    done

    # Fix log directory permissions
    if [ -d "$INSTALL_DIR/logs" ]; then
        chmod 755 "$INSTALL_DIR/logs" 2>/dev/null || log_warning "Could not fix log directory permissions"
        for log_file in "$INSTALL_DIR/logs"/*.log; do
            if [ -f "$log_file" ]; then
                chmod 644 "$log_file" 2>/dev/null || true
            fi
        done
    fi

    if [ $fixes_made -gt 0 ]; then
        log_success "Fixed permissions on $fixes_made file(s)"
    else
        log_info "File permissions are correct"
    fi
}

# Clean and rotate logs
repair_logs() {
    log_step "Cleaning and rotating logs"

    log_dir="$INSTALL_DIR/logs"
    if [ ! -d "$log_dir" ]; then
        log_warning "Log directory doesn't exist, creating it"
        mkdir -p "$log_dir" || log_error "Could not create log directory"
        return
    fi

    cleaned=0

    # Find and rotate large log files (>10MB)
    for log_file in "$log_dir"/*.log; do
        if [ -f "$log_file" ]; then
            size=$(wc -c <"$log_file" 2>/dev/null || echo "0")
            if [ "$size" -gt 10485760 ]; then # 10MB
                log_warning "Rotating large log file: $(basename "$log_file") (${size} bytes)"
                mv "$log_file" "${log_file}.old"
                touch "$log_file"
                cleaned=$((cleaned + 1))
            fi
        fi
    done

    # Clean old rotated logs (keep last 3)
    for old_log in "$log_dir"/*.log.old; do
        if [ -f "$old_log" ]; then
            rm -f "$old_log" && cleaned=$((cleaned + 1))
        fi
    done

    if [ $cleaned -gt 0 ]; then
        log_success "Cleaned/rotated $cleaned log file(s)"
    else
        log_info "Log files are within normal size limits"
    fi
}

# Fix database issues
repair_database() {
    log_step "Fixing database-related issues"

    if [ -f "$INSTALL_DIR/scripts/fix-database-spam-rutos.sh" ]; then
        log_info "Running database spam fix"
        "$INSTALL_DIR/scripts/fix-database-spam-rutos.sh"
    else
        log_warning "Database spam fix script not found"
    fi

    if [ -f "$INSTALL_DIR/scripts/fix-database-loop-rutos.sh" ]; then
        log_info "Running database loop fix"
        "$INSTALL_DIR/scripts/fix-database-loop-rutos.sh"
    else
        log_warning "Database loop fix script not found"
    fi
}

# Run all repairs
repair_all() {
    log_info "Running comprehensive system repair"

    repair_cron
    repair_config
    repair_permissions
    repair_logs
    repair_database

    log_success "All repair operations completed"
    log_info "Run the post-install check to verify repairs: $INSTALL_DIR/scripts/post-install-check-rutos.sh"
}

# Main function
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "repair-system-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: repair-system-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    print_header

    case "${1:-}" in
        --cron)
            repair_cron
            ;;
        --config)
            repair_config
            ;;
        --permissions)
            repair_permissions
            ;;
        --logs)
            repair_logs
            ;;
        --database)
            repair_database
            ;;
        --all)
            repair_all
            ;;
        --help)
            show_usage
            ;;
        "")
            # Default: run all repairs
            repair_all
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
