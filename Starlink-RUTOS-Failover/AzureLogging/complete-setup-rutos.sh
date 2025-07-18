#!/bin/sh

# === Complete Azure Logging Setup and Verification ===
# This script performs end-to-end setup and testing of Azure logging integration

set -e

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="/overlay/messages"
SETUP_SCRIPT="$SCRIPT_DIR/setup-persistent-logging-rutos.sh"
SHIPPER_SCRIPT="$SCRIPT_DIR/log-shipper-rutos.sh"
# shellcheck disable=SC2034  # TEST_SCRIPT may be used for debugging
TEST_SCRIPT="$SCRIPT_DIR/test-azure-logging-rutos.sh"

echo "=== Azure Logging Complete Setup and Verification ==="
echo ""

# Function to check if running on RUTOS
check_rutos() {
	if [ ! -f "/etc/config/system" ]; then
		echo "❌ This script must be run on a RUTOS device with UCI configuration"
		exit 1
	fi

	if [ "$(id -u)" -ne 0 ]; then
		echo "❌ This script must be run as root"
		exit 1
	fi
}

# Function to setup persistent logging
setup_logging() {
	echo "Step 1: Setting up persistent logging..."

	if [ ! -f "$SETUP_SCRIPT" ]; then
		echo "❌ Setup script not found: $SETUP_SCRIPT"
		exit 1
	fi

	chmod +x "$SETUP_SCRIPT"
	"$SETUP_SCRIPT"

	echo "✅ Persistent logging setup completed"
}

# Function to verify logging is working
verify_logging() {
	echo ""
	echo "Step 2: Verifying persistent logging..."

	# Check if log file exists and is writable
	if [ ! -f "$LOG_FILE" ]; then
		echo "❌ Log file $LOG_FILE does not exist"
		return 1
	fi

	# Check log file size and permissions
	LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
	LOG_PERMS=$(stat -c%a "$LOG_FILE" 2>/dev/null || echo "000")

	echo "Log file: $LOG_FILE"
	echo "Size: $LOG_SIZE bytes"
	echo "Permissions: $LOG_PERMS"

	# Test writing to log
	logger -t "azure-setup-verify" "Setup verification test - $(date)"
	sleep 2

	if grep -q "azure-setup-verify" "$LOG_FILE"; then
		echo "✅ Logging verification successful"
		return 0
	else
		echo "❌ Failed to write test message to log file"
		return 1
	fi
}

# Function to setup log shipper
setup_shipper() {
	echo ""
	echo "Step 3: Installing log shipper..."

	if [ ! -f "$SHIPPER_SCRIPT" ]; then
		echo "❌ Log shipper script not found: $SHIPPER_SCRIPT"
		exit 1
	fi

	# Copy to overlay (persistent storage)
	cp "$SHIPPER_SCRIPT" "/overlay/log-shipper.sh"
	chmod 755 "/overlay/log-shipper.sh"

	echo "✅ Log shipper installed to /overlay/log-shipper.sh"

	# Check if Azure URL is configured
	if grep -q "PASTE_YOUR_AZURE_FUNCTION_URL_HERE" "/overlay/log-shipper.sh"; then
		echo ""
		echo "⚠️  IMPORTANT: You need to configure the Azure Function URL"
		echo "   Edit /overlay/log-shipper.sh and set AZURE_FUNCTION_URL"
		echo "   Get this URL after deploying your Azure Function App"
	fi
}

# Function to show next steps
show_next_steps() {
	echo ""
	echo "=== Next Steps ==="
	echo ""
	echo "1. Deploy Azure Infrastructure:"
	echo "   az deployment group create --resource-group YOUR_RG --template-file main.bicep"
	echo ""
	echo "2. Deploy Function Code:"
	echo "   (Zip HttpLogIngestor folder and deploy with Azure CLI)"
	echo ""
	echo "3. Get Function URL and configure log-shipper.sh:"
	echo "   vi /overlay/log-shipper.sh"
	echo "   # Set AZURE_FUNCTION_URL to your actual function URL"
	echo ""
	echo "4. Test the integration:"
	echo "   /overlay/log-shipper.sh"
	echo ""
	echo "5. Set up cron job (every 5 minutes):"
	echo "   crontab -e"
	echo "   # Add: */5 * * * * /overlay/log-shipper.sh"
	echo ""
	echo "6. Monitor logs:"
	echo "   tail -f $LOG_FILE"
	echo "   logread | grep azure-log-shipper"
}

# Function to show current status
show_status() {
	echo ""
	echo "=== Current System Status ==="

	# UCI configuration
	echo "Logging configuration:"
	uci show system.@system[0] | grep -E "(log_type|log_size|log_file)" || echo "No logging config found"

	# Storage space
	echo ""
	echo "Overlay storage:"
	df -h /overlay

	# Log file status
	if [ -f "$LOG_FILE" ]; then
		echo ""
		echo "Log file status:"
		ls -lh "$LOG_FILE"
		echo "Last 3 lines:"
		tail -3 "$LOG_FILE"
	fi

	# Cron status
	echo ""
	echo "Cron jobs for log shipping:"
	crontab -l 2>/dev/null | grep -E "(log-shipper|azure)" || echo "No cron jobs configured yet"
}

# Main execution
main() {
	check_rutos

	echo "This script will:"
	echo "1. Configure persistent logging (5MB file storage)"
	echo "2. Verify logging is working correctly"
	echo "3. Install the log shipper script"
	echo "4. Show next steps for Azure deployment"
	echo ""

	printf "Continue with setup? [y/N]: "
	read -r REPLY
	if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
		echo "Setup cancelled."
		exit 0
	fi

	setup_logging

	if verify_logging; then
		setup_shipper
		show_next_steps
	else
		echo ""
		echo "❌ Logging verification failed. Please check the system configuration."
		exit 1
	fi

	show_status

	echo ""
	echo "✅ RUTOS Azure logging setup completed successfully!"
	echo ""
	echo "Remember to:"
	echo "- Deploy Azure resources using main.bicep"
	echo "- Configure the Azure Function URL in /overlay/log-shipper.sh"
	echo "- Set up the cron job for automatic log shipping"
}

# Run main function
main "$@"
