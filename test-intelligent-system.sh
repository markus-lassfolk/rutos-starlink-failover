#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="3.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "test-intelligent-system.sh" "$SCRIPT_VERSION"

# Test script for the new intelligent monitoring system
log_info "🧪 Testing Intelligent Starlink Monitoring System"
log_step "=================================================="

# Move to the correct directory
cd "$(dirname "$0")/Starlink-RUTOS-Failover"

# Make the script executable
chmod +x starlink_monitor_unified-rutos.sh

echo ""
log_info " Testing help system..."
./starlink_monitor_unified-rutos.sh help

echo ""
log_info " Testing system validation..."
./starlink_monitor_unified-rutos.sh validate

echo ""
log_info " Testing MWAN3 discovery..."
./starlink_monitor_unified-rutos.sh discover

echo ""
echo "🧪 Testing single monitoring cycle..."
./starlink_monitor_unified-rutos.sh test --debug

echo ""
echo "📊 Testing status check..."
./starlink_monitor_unified-rutos.sh status

echo ""
log_success " All tests completed!"
echo ""
echo "Next steps:"
echo "  1. Review the test output above"
echo "  2. Start the daemon: ./starlink_monitor_unified-rutos.sh start --daemon"
echo "  3. Monitor status: ./starlink_monitor_unified-rutos.sh status"
echo "  4. Stop when needed: ./starlink_monitor_unified-rutos.sh stop"
