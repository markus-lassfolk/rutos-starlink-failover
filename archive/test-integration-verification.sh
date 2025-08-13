#!/bin/sh
# Test script to verify integration installation process
# This simulates what happens during a real installation

set -e

# Test directories
TEST_DIR="/tmp/starlink-test-$(date +%s)"
echo "Creating test installation in: $TEST_DIR"

# Create test structure
mkdir -p "$TEST_DIR/gps-integration"
mkdir -p "$TEST_DIR/cellular-integration"
mkdir -p "$TEST_DIR/scripts"

# Copy integration scripts
echo "Copying GPS integration scripts..."
cp gps-integration/*.sh "$TEST_DIR/gps-integration/"

echo "Copying cellular integration scripts..."
cp cellular-integration/*.sh "$TEST_DIR/cellular-integration/"

echo "Copying unified scripts..."
cp Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh "$TEST_DIR/scripts/"
cp Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh "$TEST_DIR/scripts/"

# Check if GPS collector exists
if [ -f "$TEST_DIR/gps-integration/gps-collector-rutos.sh" ]; then
    echo "✅ GPS collector found"
else
    echo "❌ GPS collector missing"
fi

# Check if cellular collector exists
if [ -f "$TEST_DIR/cellular-integration/cellular-data-collector-rutos.sh" ]; then
    echo "✅ Cellular collector found"
else
    echo "❌ Cellular collector missing"
fi

# Check if unified scripts exist
if [ -f "$TEST_DIR/scripts/starlink_monitor_unified-rutos.sh" ]; then
    echo "✅ Unified monitor script found"
else
    echo "❌ Unified monitor script missing"
fi

if [ -f "$TEST_DIR/scripts/starlink_logger_unified-rutos.sh" ]; then
    echo "✅ Unified logger script found"
else
    echo "❌ Unified logger script missing"
fi

echo ""
echo "Test directory: $TEST_DIR"
echo "To clean up: rm -rf $TEST_DIR"
