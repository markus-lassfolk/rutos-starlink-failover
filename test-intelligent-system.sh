#!/bin/sh
set -e

# Test script for the new intelligent monitoring system
echo "🧪 Testing Intelligent Starlink Monitoring System"
echo "=================================================="

# Move to the correct directory
cd "$(dirname "$0")/Starlink-RUTOS-Failover"

# Make the script executable
chmod +x starlink_monitor_unified-rutos.sh

echo ""
echo "📋 Testing help system..."
./starlink_monitor_unified-rutos.sh help

echo ""
echo "🔍 Testing system validation..."
./starlink_monitor_unified-rutos.sh validate

echo ""
echo "🔍 Testing MWAN3 discovery..."
./starlink_monitor_unified-rutos.sh discover

echo ""
echo "🧪 Testing single monitoring cycle..."
./starlink_monitor_unified-rutos.sh test --debug

echo ""
echo "📊 Testing status check..."
./starlink_monitor_unified-rutos.sh status

echo ""
echo "✅ All tests completed!"
echo ""
echo "Next steps:"
echo "  1. Review the test output above"
echo "  2. Start the daemon: ./starlink_monitor_unified-rutos.sh start --daemon"
echo "  3. Monitor status: ./starlink_monitor_unified-rutos.sh status"
echo "  4. Stop when needed: ./starlink_monitor_unified-rutos.sh stop"
