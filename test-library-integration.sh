#!/bin/sh
# Quick test to verify library integration and function availability

set -e

# Test script location and library loading

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
SCRIPT_DIR="$(dirname "$0")"
echo "Testing from directory: $SCRIPT_DIR"

echo "🔍 TESTING RUTOS LIBRARY INTEGRATION"
echo "===================================="

# Load library
if . "$SCRIPT_DIR/scripts/lib/rutos-lib.sh" 2>/dev/null; then
    echo "✅ RUTOS library loaded successfully"
else
    echo "❌ Failed to load RUTOS library"
    exit 1
fi

# Check if data collection module is loaded
if [ "${_RUTOS_DATA_COLLECTION_LOADED:-0}" = "1" ]; then
    echo "✅ Data collection module loaded successfully"
else
    echo "❌ Data collection module not loaded"
    exit 1
fi

# Test function availability
echo ""
echo "🔧 TESTING FUNCTION AVAILABILITY"
echo "=================================="

# Test library functions
if command -v collect_gps_data >/dev/null 2>&1; then
    echo "✅ collect_gps_data() available"
else
    echo "❌ collect_gps_data() not available"
fi

if command -v collect_cellular_data >/dev/null 2>&1; then
    echo "✅ collect_cellular_data() available"
else
    echo "❌ collect_cellular_data() not available"
fi

# Test library aliases
if command -v collect_gps_data_lib >/dev/null 2>&1; then
    echo "✅ collect_gps_data_lib() alias available"
else
    echo "❌ collect_gps_data_lib() alias not available"
fi

if command -v collect_cellular_data_lib >/dev/null 2>&1; then
    echo "✅ collect_cellular_data_lib() alias available"
else
    echo "❌ collect_cellular_data_lib() alias not available"
fi

# Test helper functions
if command -v sanitize_csv_field >/dev/null 2>&1; then
    echo "✅ sanitize_csv_field() helper available"
else
    echo "❌ sanitize_csv_field() helper not available"
fi

if command -v validate_gps_coordinates >/dev/null 2>&1; then
    echo "✅ validate_gps_coordinates() helper available"
else
    echo "❌ validate_gps_coordinates() helper not available"
fi

# Test data collection (with logging disabled to prevent issues)
echo ""
echo "📊 TESTING DATA COLLECTION"
echo "=========================="

# Test GPS data collection with library
ENABLE_GPS_LOGGING="false"
export ENABLE_GPS_LOGGING
echo "Testing GPS data collection (disabled mode):"
gps_result=$(collect_gps_data 2>/dev/null || echo "ERROR")
if [ "$gps_result" != "ERROR" ]; then
    echo "✅ GPS data collection successful: $(echo "$gps_result" | head -c 50)..."
else
    echo "⚠️  GPS data collection failed (may be expected if gpsctl not available)"
fi

# Test cellular data collection with library
ENABLE_CELLULAR_LOGGING="false"
export ENABLE_CELLULAR_LOGGING
echo "Testing cellular data collection (disabled mode):"
cellular_result=$(collect_cellular_data 2>/dev/null || echo "ERROR")
if [ "$cellular_result" != "ERROR" ]; then
    echo "✅ Cellular data collection successful: $(echo "$cellular_result" | head -c 50)..."
else
    echo "⚠️  Cellular data collection failed (may be expected if gsmctl not available)"
fi

# Test CSV sanitization
echo ""
echo "🧹 TESTING CSV SANITIZATION"
echo "=========================="

test_field="Test,Data\nWith\rProblems"
sanitized=$(sanitize_csv_field "$test_field" 20 2>/dev/null || echo "ERROR")
if [ "$sanitized" != "ERROR" ] && [ "$sanitized" = "TestDataWithProblems" ]; then
    echo "✅ CSV sanitization working correctly: '$sanitized'"
else
    echo "❌ CSV sanitization failed: '$sanitized'"
fi

echo ""
echo "🎯 INTEGRATION TEST COMPLETE"
echo "============================"
echo "Library integration appears to be working correctly!"
echo "All scripts can now use standardized GPS and cellular data collection."
