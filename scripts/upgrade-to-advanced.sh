#!/bin/sh

# ==============================================================================
# Upgrade to Advanced Configuration Script
#
# This script upgrades from basic configuration to advanced configuration
# while preserving all existing settings and adding new advanced features.
#
# Usage: ./upgrade-to-advanced.sh
# ==============================================================================

set -eu

# Script version information
SCRIPT_VERSION="1.0.2"
SCRIPT_NAME="upgrade-to-advanced.sh"
COMPATIBLE_INSTALL_VERSION="1.0.0"

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
# shellcheck disable=SC2034
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[1;35m' # Bright magenta instead of dark blue for better readability
	CYAN='\033[0;36m'
	NC='\033[0m' # No Color
else
	# Fallback to no colors if terminal doesn't support them
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	CYAN=""
	NC=""
fi

# Configuration paths
INSTALL_DIR="/root/starlink-monitor"
CONFIG_DIR="$INSTALL_DIR/config"
BASIC_CONFIG="$CONFIG_DIR/config.sh"
ADVANCED_TEMPLATE="$CONFIG_DIR/config.advanced.template.sh"
BACKUP_CONFIG="$CONFIG_DIR/config.sh.backup.$(date +%Y%m%d_%H%M%S)"

# Function to print colored output
print_status() {
	color="$1"
	message="$2"
	printf "%s%s%s\n" "$color" "$message" "$NC"
}

print_error() {
	print_status "$RED" "❌ $1"
}

print_success() {
	print_status "$GREEN" "✅ $1"
}

print_info() {
	print_status "$BLUE" "ℹ $1"
}

print_warning() {
	print_status "$YELLOW" "⚠ $1"
}

# Function to extract value from config file
get_config_value() {
	file="$1"
	key="$2"
	if [ -f "$file" ]; then
		grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*#.*$//;s/^"//;s/"$//'
	fi
}

# Function to check if advanced template exists
check_advanced_template() {
	if [ ! -f "$ADVANCED_TEMPLATE" ]; then
		print_error "Advanced template not found: $ADVANCED_TEMPLATE"
		print_info "Downloading advanced template..."

		# Try to download from GitHub
		if command -v wget >/dev/null 2>&1; then
			if wget -q -O "$ADVANCED_TEMPLATE" "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/feature/testing-improvements/config/config.advanced.template.sh"; then
				print_success "Advanced template downloaded successfully"
			else
				print_error "Failed to download advanced template"
				return 1
			fi
		elif command -v curl >/dev/null 2>&1; then
			if curl -s -o "$ADVANCED_TEMPLATE" "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/feature/testing-improvements/config/config.advanced.template.sh"; then
				print_success "Advanced template downloaded successfully"
			else
				print_error "Failed to download advanced template"
				return 1
			fi
		else
			print_error "Neither wget nor curl available for download"
			return 1
		fi
	fi
	return 0
}

# Function to migrate configuration
migrate_config() {
	basic_config="$1"
	advanced_template="$2"
	output_file="$3"

	print_info "Migrating configuration from basic to advanced..."

	# Start with the advanced template
	cp "$advanced_template" "$output_file"

	# List of settings to migrate from basic to advanced
	settings="
    STARLINK_IP
    MWAN_IFACE
    MWAN_MEMBER
    PUSHOVER_TOKEN
    PUSHOVER_USER
    NOTIFY_ON_CRITICAL
    NOTIFY_ON_SOFT_FAIL
    NOTIFY_ON_HARD_FAIL
    NOTIFY_ON_RECOVERY
    NOTIFY_ON_INFO
    PACKET_LOSS_THRESHOLD
    OBSTRUCTION_THRESHOLD
    LATENCY_THRESHOLD_MS
    STABILITY_CHECKS_REQUIRED
    METRIC_GOOD
    METRIC_BAD
    STATE_DIR
    LOG_DIR
    DATA_DIR
    GRPCURL_CMD
    JQ_CMD
    RUTOS_IP
    RUTOS_USERNAME
    RUTOS_PASSWORD
    LOG_TAG
    LOG_RETENTION_DAYS
    API_TIMEOUT
    HTTP_TIMEOUT
    GPS_ACCURACY_THRESHOLD
    MOVEMENT_THRESHOLD
    "

	# Migrate each setting
	for setting in $settings; do
		value=$(get_config_value "$basic_config" "$setting")

		if [ -n "$value" ]; then
			# Replace the setting in the advanced config
			if grep -q "^${setting}=" "$output_file"; then
				# Setting exists in advanced template, update it
				sed -i "s|^${setting}=.*|${setting}=\"${value}\"|" "$output_file"
				print_success "Migrated $setting: $value"
			else
				print_warning "Setting $setting not found in advanced template (skipping)"
			fi
		else
			print_info "Setting $setting not found in basic config (using default)"
		fi
	done
}

# Function to show differences
show_new_features() {
	print_info "New features available in advanced configuration:"

	cat <<'EOF'

🚀 Advanced Features Now Available:

📱 Enhanced Notifications:
   - NOTIFY_ON_SIGNAL_RESET=1    # Cellular signal reset notifications
   - NOTIFY_ON_SIM_SWITCH=1      # SIM card switch notifications  
   - NOTIFY_ON_GPS_STATUS=0      # GPS status change notifications
   - NOTIFICATION_COOLDOWN=300   # Rate limiting (5 minutes)
   - MAX_NOTIFICATIONS_PER_HOUR=12 # Prevent spam

🔄 Dual Cellular Configuration:
   - CELLULAR_PRIMARY_IFACE="mob1s1a1"   # Primary SIM interface
   - CELLULAR_PRIMARY_MEMBER="member3"   # Primary SIM member
   - CELLULAR_BACKUP_IFACE="mob1s2a1"    # Backup SIM interface
   - CELLULAR_BACKUP_MEMBER="member4"    # Backup SIM member

🎯 Mobile-Optimized Thresholds:
   - PACKET_LOSS_CRITICAL=0.15    # 15% for immediate failover
   - OBSTRUCTION_CRITICAL=0.005   # 0.5% for immediate failover
   - LATENCY_CRITICAL_MS=500      # 500ms for immediate failover

🌐 GPS & Movement Detection:
   - MOVEMENT_DETECTION_DISTANCE=50      # 50m movement threshold
   - STARLINK_OBSTRUCTION_RESET_DISTANCE=500 # Reset obstruction map

🔗 Integration Options:
   - MQTT integration settings
   - RMS (Remote Management System) integration
   - Enhanced logging and debugging options

📊 Cellular Optimization:
   - Auto SIM switching based on signal strength
   - Data limit awareness and management
   - Signal strength monitoring

EOF

	print_info "Edit your config to enable these features: vi $CONFIG_DIR/config.sh"
}

# Main execution
main() {
	print_status "$BLUE" "=== Upgrade to Advanced Configuration ==="
	print_status "$BLUE" "Script: $SCRIPT_NAME"
	print_status "$BLUE" "Version: $SCRIPT_VERSION"
	print_status "$BLUE" "Compatible with install.sh: $COMPATIBLE_INSTALL_VERSION"
	echo

	# Check if basic configuration exists
	if [ ! -f "$BASIC_CONFIG" ]; then
		print_error "Basic configuration not found: $BASIC_CONFIG"
		print_info "Please run the installation script first"
		exit 1
	fi

	# Check if advanced template exists
	if ! check_advanced_template; then
		exit 1
	fi

	# Create backup of current config
	print_info "Creating backup of current configuration..."
	cp "$BASIC_CONFIG" "$BACKUP_CONFIG"
	print_success "Backup created: $BACKUP_CONFIG"

	# Migrate configuration
	migrate_config "$BASIC_CONFIG" "$ADVANCED_TEMPLATE" "$BASIC_CONFIG"

	print_success "Configuration successfully upgraded to advanced!"
	print_info "Backup of original config: $BACKUP_CONFIG"

	# Show new features
	show_new_features

	# Final instructions
	echo
	print_status "$GREEN" "🎉 Upgrade Complete!"
	print_info "Next steps:"
	print_info "1. Edit configuration: vi $CONFIG_DIR/config.sh"
	print_info "2. Validate configuration: $INSTALL_DIR/scripts/validate-config.sh"
	print_info "3. Restart monitoring: systemctl restart starlink-monitor (if running)"
	print_info "4. Test the system manually"

	echo
	print_info "To revert to basic config: cp $BACKUP_CONFIG $BASIC_CONFIG"
}

# Run main function
main "$@"
