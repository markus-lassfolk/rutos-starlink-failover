#!/bin/bash

# === RUTOS Persistent Logging Setup for Azure Integration ===
# This script configures RUTOS to write logs to persistent storage
# and increases the log size for better Azure log collection.

set -e  # Exit on any error

LOG_FILE="/overlay/messages"
UCI_SYSTEM_CONFIG="/etc/config/system"
BACKUP_DIR="/overlay/backup-configs"
CURRENT_DATE=$(date +%Y%m%d_%H%M%S)

echo "=== RUTOS Persistent Logging Setup ==="
echo "Configuring logging for Azure integration..."

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to backup current configuration
backup_config() {
    echo "Creating backup of current system configuration..."
    cp "$UCI_SYSTEM_CONFIG" "$BACKUP_DIR/system.backup.$CURRENT_DATE"
    echo "Backup saved to: $BACKUP_DIR/system.backup.$CURRENT_DATE"
}

# Function to check current logging configuration
check_current_config() {
    echo ""
    echo "=== Current Logging Configuration ==="
    
    # Check if system section exists
    if ! uci show system.@system[0] >/dev/null 2>&1; then
        echo "ERROR: System configuration section not found!"
        exit 1
    fi
    
    # Get current values
    LOG_TYPE=$(uci get system.@system[0].log_type 2>/dev/null || echo "circular")
    LOG_SIZE=$(uci get system.@system[0].log_size 2>/dev/null || echo "200")
    LOG_FILE_UCI=$(uci get system.@system[0].log_file 2>/dev/null || echo "not set")
    LOG_BUFFER_SIZE=$(uci get system.@system[0].log_buffer_size 2>/dev/null || echo "128")
    
    echo "Current log_type: $LOG_TYPE"
    echo "Current log_size: ${LOG_SIZE}KB"
    echo "Current log_file: $LOG_FILE_UCI"
    echo "Current log_buffer_size: ${LOG_BUFFER_SIZE}KB"
    
    # Check if configuration needs updating
    NEEDS_UPDATE=0
    
    if [ "$LOG_TYPE" != "file" ]; then
        echo "⚠️  Log type needs to be changed from '$LOG_TYPE' to 'file'"
        NEEDS_UPDATE=1
    fi
    
    if [ "$LOG_SIZE" -lt 5120 ]; then
        echo "⚠️  Log size needs to be increased from '${LOG_SIZE}KB' to '5120KB' (5MB)"
        NEEDS_UPDATE=1
    fi
    
    if [ "$LOG_FILE_UCI" != "$LOG_FILE" ]; then
        echo "⚠️  Log file needs to be set to '$LOG_FILE'"
        NEEDS_UPDATE=1
    fi
    
    if [ "$NEEDS_UPDATE" -eq 0 ]; then
        echo "✅ Logging configuration is already optimal!"
        return 0
    else
        echo ""
        echo "Configuration update required."
        return 1
    fi
}

# Function to apply the new configuration
apply_config() {
    echo ""
    echo "=== Applying New Logging Configuration ==="
    
    # Set logging to file mode
    uci set system.@system[0].log_type='file'
    echo "✅ Set log_type to 'file'"
    
    # Set log file path
    uci set system.@system[0].log_file="$LOG_FILE"
    echo "✅ Set log_file to '$LOG_FILE'"
    
    # Increase log size to 5MB
    uci set system.@system[0].log_size='5120'
    echo "✅ Set log_size to '5120' (5MB)"
    
    # Optionally increase buffer size for better performance
    uci set system.@system[0].log_buffer_size='256'
    echo "✅ Set log_buffer_size to '256KB'"
    
    # Commit the changes
    uci commit system
    echo "✅ Configuration committed"
}

# Function to restart logging service
restart_logging() {
    echo ""
    echo "=== Restarting Logging Service ==="
    
    # Restart the system logging service
    /etc/init.d/log restart
    echo "✅ Logging service restarted"
    
    # Wait a moment for the service to start
    sleep 2
    
    # Verify the log file exists and is writable
    if [ -f "$LOG_FILE" ]; then
        echo "✅ Log file '$LOG_FILE' exists and is ready"
        
        # Show current log file size
        LOG_SIZE_BYTES=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        echo "Current log file size: $LOG_SIZE_BYTES bytes"
    else
        echo "⚠️  Log file '$LOG_FILE' not found. It will be created when logging starts."
    fi
}

# Function to test logging
test_logging() {
    echo ""
    echo "=== Testing Logging Configuration ==="
    
    # Send a test message to syslog
    logger -t "azure-logging-setup" "Test message: Persistent logging configured at $(date)"
    
    # Wait a moment for the message to be written
    sleep 1
    
    # Check if the message appears in the log file
    if [ -f "$LOG_FILE" ] && grep -q "azure-logging-setup" "$LOG_FILE"; then
        echo "✅ Test logging successful - message written to $LOG_FILE"
    else
        echo "❌ Test logging failed - message not found in $LOG_FILE"
        echo "You may need to wait a few moments or check the system configuration."
    fi
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=== Final Configuration Status ==="
    uci show system.@system[0] | grep -E "(log_type|log_size|log_file|log_buffer_size)"
    
    echo ""
    echo "=== Storage Information ==="
    df -h /overlay
    
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "=== Current Log File Status ==="
        ls -lh "$LOG_FILE"
    fi
}

# Main execution
main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root (use sudo or run directly as root)"
        exit 1
    fi
    
    # Create backup
    backup_config
    
    # Check current configuration
    if check_current_config; then
        # Configuration is already good
        test_logging
        show_final_status
    else
        # Need to update configuration
        echo ""
        read -p "Do you want to apply the new logging configuration? [y/N]: " -r
        if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
            apply_config
            restart_logging
            test_logging
            show_final_status
            
            echo ""
            echo "✅ Persistent logging setup complete!"
            echo ""
            echo "Next steps:"
            echo "1. Deploy the Azure Function App using main.bicep"
            echo "2. Configure the Azure Function URL in log-shipper.sh"
            echo "3. Set up the cron job to run log-shipper.sh every 5 minutes"
            echo ""
            echo "To restore the previous configuration if needed:"
            echo "  cp $BACKUP_DIR/system.backup.$CURRENT_DATE /etc/config/system"
            echo "  uci commit system && /etc/init.d/log restart"
        else
            echo "Configuration not changed. Exiting."
            exit 0
        fi
    fi
}

# Run main function
main "$@"
