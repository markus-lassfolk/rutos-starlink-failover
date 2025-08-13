#!/bin/sh

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"

# Fix for missing STARLINK_IP and STARLINK_PORT variables in config

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

# Main function
main() {
    log_info "STARLINK Variable Fix Script v$SCRIPT_VERSION"
    echo ""

    CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    log_step "Checking for missing STARLINK_IP and STARLINK_PORT variables..."

    # Check if variables are missing
    missing_ip=false
    missing_port=false

    if ! grep -q "^export STARLINK_IP=" "$CONFIG_FILE"; then
        missing_ip=true
        log_warning "STARLINK_IP variable is missing"
    fi

    if ! grep -q "^export STARLINK_PORT=" "$CONFIG_FILE"; then
        missing_port=true
        log_warning "STARLINK_PORT variable is missing"
    fi

    if [ "$missing_ip" = "false" ] && [ "$missing_port" = "false" ]; then
        log_info "Both STARLINK_IP and STARLINK_PORT variables are already present"
        exit 0
    fi

    # Create backup
    backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    log_step "Creating backup: $backup_file"
    cp "$CONFIG_FILE" "$backup_file"

    # Add missing variables
    log_step "Adding missing STARLINK variables to configuration..."

    # Create temporary file with the fixes
    temp_file="/tmp/config_fix_$$"

    # Find a good place to insert the variables (after the basic settings section)
    if grep -q "# Basic required variables" "$CONFIG_FILE"; then
        # Insert after the basic variables section
        sed '/# Basic required variables/,/^$/s/^$/# --- Starlink Connection Settings ---\n# Starlink gRPC endpoint IP and port (separate variables for flexibility)\n# Default: IP=192.168.100.1, PORT=9200 (standard Starlink configuration)\n# Change only if your Starlink uses a different IP or port\nexport STARLINK_IP="192.168.100.1"\nexport STARLINK_PORT="9200"\n/' "$CONFIG_FILE" >"$temp_file"
    else
        # If we can't find the section, add at the end of the export section
        {
            cat "$CONFIG_FILE"
            echo ""
            echo "# --- Starlink Connection Settings ---"
            echo "# Starlink gRPC endpoint IP and port (separate variables for flexibility)"
            echo "# Default: IP=192.168.100.1, PORT=9200 (standard Starlink configuration)"
            echo "# Change only if your Starlink uses a different IP or port"
            if [ "$missing_ip" = "true" ]; then
                echo 'export STARLINK_IP="192.168.100.1"'
            fi
            if [ "$missing_port" = "true" ]; then
                echo 'export STARLINK_PORT="9200"'
            fi
        } >"$temp_file"
    fi

    # Validate the temp file
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "$CONFIG_FILE"
        log_info "✓ Configuration updated successfully"
        log_info "✓ Backup saved to: $backup_file"

        # Show what was added
        if [ "$missing_ip" = "true" ]; then
            log_info "✓ Added: export STARLINK_IP=\"192.168.100.1\""
        fi
        if [ "$missing_port" = "true" ]; then
            log_info "✓ Added: export STARLINK_PORT=\"9200\""
        fi

        echo ""
        log_info "Please verify the configuration and restart the monitoring services:"
        log_info "  1. Edit $CONFIG_FILE if needed"
        log_info "  2. Restart cron: /etc/init.d/cron restart"

    else
        log_error "Failed to create updated configuration"
        rm -f "$temp_file"
        exit 1
    fi
}

# Run main function
main "$@"
