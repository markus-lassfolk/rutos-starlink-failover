#!/bin/sh
# Test script for enhanced GPS and health monitoring functions

set -e

# Test script location and library loading

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
SCRIPT_DIR="$(dirname "$0")"
echo "Testing enhanced data collection from directory: $SCRIPT_DIR"

echo "🔬 TESTING ENHANCED RUTOS DATA COLLECTION"
echo "=========================================="

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

# Mock Starlink configuration for testing (adjust as needed)
export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl"
export JQ_CMD="/usr/bin/jq"
export STARLINK_IP="192.168.100.1"
export STARLINK_PORT="9200"

echo ""
echo "🛰️ TESTING ENHANCED GPS COLLECTION"
echo "==================================="

# Test enhanced GPS data collection
ENABLE_GPS_LOGGING="true"
export ENABLE_GPS_LOGGING

echo "Testing enhanced GPS data collection with diagnostics:"
if command -v collect_gps_data_enhanced >/dev/null 2>&1; then
    echo "✅ collect_gps_data_enhanced() function available"

    # Test the function (will show debug output if DEBUG=1)
    gps_enhanced_result=$(collect_gps_data_enhanced 2>/dev/null || echo "ERROR")
    if [ "$gps_enhanced_result" != "ERROR" ]; then
        echo "✅ Enhanced GPS collection successful:"
        echo "   Result: $gps_enhanced_result"
        echo "   Format: lat,lon,alt,accuracy,source,uncertainty_meters,gps_time_s,utc_offset_s"

        # Parse and display components
        lat=$(echo "$gps_enhanced_result" | cut -d',' -f1)
        lon=$(echo "$gps_enhanced_result" | cut -d',' -f2)
        alt=$(echo "$gps_enhanced_result" | cut -d',' -f3)
        accuracy=$(echo "$gps_enhanced_result" | cut -d',' -f4)
        source=$(echo "$gps_enhanced_result" | cut -d',' -f5)
        uncertainty=$(echo "$gps_enhanced_result" | cut -d',' -f6)
        gps_time=$(echo "$gps_enhanced_result" | cut -d',' -f7)
        utc_offset=$(echo "$gps_enhanced_result" | cut -d',' -f8)

        echo "   📍 Coordinates: $lat, $lon (altitude: ${alt}m)"
        echo "   🎯 Accuracy: $accuracy (source: $source)"
        echo "   📏 Uncertainty: ${uncertainty}m"
        echo "   ⏰ GPS Time: $gps_time, UTC Offset: ${utc_offset}s"
    else
        echo "⚠️  Enhanced GPS collection failed (may be expected if Starlink not available)"
    fi
else
    echo "❌ collect_gps_data_enhanced() function not available"
fi

echo ""
echo "🏥 TESTING STARLINK HEALTH MONITORING"
echo "====================================="

# Test Starlink health monitoring
echo "Testing Starlink health assessment:"
if command -v check_starlink_health >/dev/null 2>&1; then
    echo "✅ check_starlink_health() function available"

    # Test the function
    health_result=$(check_starlink_health 2>/dev/null || echo "ERROR")
    if [ "$health_result" != "ERROR" ]; then
        echo "✅ Health monitoring successful:"
        echo "   Result: $health_result"
        echo "   Format: overall,hardware_test,dl_bw_reason,ul_bw_reason,thermal_throttle,thermal_shutdown,roaming"

        # Parse and display components
        overall=$(echo "$health_result" | cut -d',' -f1)
        hardware_test=$(echo "$health_result" | cut -d',' -f2)
        dl_bw_reason=$(echo "$health_result" | cut -d',' -f3)
        ul_bw_reason=$(echo "$health_result" | cut -d',' -f4)
        thermal_throttle=$(echo "$health_result" | cut -d',' -f5)
        thermal_shutdown=$(echo "$health_result" | cut -d',' -f6)
        roaming=$(echo "$health_result" | cut -d',' -f7)

        echo "   🏥 Overall Status: $overall"
        echo "   🔧 Hardware Self-Test: $hardware_test"
        echo "   📶 Bandwidth Restrictions: DL=$dl_bw_reason, UL=$ul_bw_reason"
        echo "   🌡️  Thermal Status: Throttle=$thermal_throttle, Shutdown=$thermal_shutdown"
        echo "   🌍 Roaming Alert: $roaming"

        # Test failover decision
        echo ""
        echo "Testing failover decision logic:"
        if command -v should_trigger_failover >/dev/null 2>&1; then
            if should_trigger_failover "$health_result"; then
                echo "🚨 FAILOVER RECOMMENDED: Health status indicates failover should be triggered"
            else
                echo "✅ FAILOVER NOT NEEDED: System health is acceptable"
            fi
        else
            echo "❌ should_trigger_failover() function not available"
        fi
    else
        echo "⚠️  Health monitoring failed (may be expected if Starlink not available)"
    fi
else
    echo "❌ check_starlink_health() function not available"
fi

echo ""
echo "📊 TESTING COMPARATIVE DATA COLLECTION"
echo "======================================"

echo "Comparing standard vs enhanced GPS collection:"

# Standard GPS
echo "Standard GPS collection:"
standard_gps=$(collect_gps_data 2>/dev/null || echo "ERROR")
echo "   Standard: $standard_gps"
echo "   Format: lat,lon,alt,accuracy,source"

# Enhanced GPS
echo "Enhanced GPS collection:"
enhanced_gps=$(collect_gps_data_enhanced 2>/dev/null || echo "ERROR")
echo "   Enhanced: $enhanced_gps"
echo "   Format: lat,lon,alt,accuracy,source,uncertainty_meters,gps_time_s,utc_offset_s"

echo ""
echo "🎯 INTEGRATION TEST SUMMARY"
echo "=========================="
echo "Enhanced data collection library provides:"
echo "✨ Enhanced GPS collection with uncertainty and timing data"
echo "🏥 Comprehensive health monitoring for failover decisions"
echo "🚨 Automated failover trigger detection"
echo "📡 Support for multiple Starlink API endpoints (get_location, get_diagnostics)"
echo "⚡ Backwards compatibility with existing functions"
echo ""
echo "Key improvements over basic collection:"
echo "• GPS uncertainty measurements for accuracy assessment"
echo "• Hardware self-test monitoring for device health"
echo "• Bandwidth restriction detection for performance issues"
echo "• Thermal status monitoring for environmental concerns"
echo "• Automated failover decision logic"
echo ""
echo "🎉 Enhanced integration test complete!"
