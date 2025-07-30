#!/bin/sh
# Demonstration of predictive reboot failover functionality

set -e

# Test script location and library loading
SCRIPT_DIR="$(dirname "$0")"
echo "Testing predictive reboot failover from directory: $SCRIPT_DIR"

echo "🔄 PREDICTIVE REBOOT FAILOVER DEMONSTRATION"
echo "==========================================="

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

# Configuration for reboot warning window
export REBOOT_WARNING_SECONDS="300" # 5 minutes warning window

echo ""
echo "🕐 REBOOT WARNING CONFIGURATION"
echo "==============================="
echo "Reboot warning window: ${REBOOT_WARNING_SECONDS} seconds ($(echo "scale=1; $REBOOT_WARNING_SECONDS / 60" | bc 2>/dev/null || echo "~5") minutes)"
echo "This means failover will trigger when reboot is scheduled within this window."

echo ""
echo "📊 TESTING REBOOT STATUS MONITORING"
echo "==================================="

if command -v get_reboot_status >/dev/null 2>&1; then
    echo "✅ get_reboot_status() function available"

    # Test reboot status monitoring
    echo "Getting current reboot status:"
    reboot_status=$(get_reboot_status 2>/dev/null || echo "ERROR")

    if [ "$reboot_status" != "ERROR" ]; then
        echo "✅ Reboot status retrieved: $reboot_status"
        echo "   Format: update_state,requires_reboot,scheduled_utc,countdown,reboot_ready"

        # Parse and display components
        update_state=$(echo "$reboot_status" | cut -d',' -f1)
        requires_reboot=$(echo "$reboot_status" | cut -d',' -f2)
        scheduled_utc=$(echo "$reboot_status" | cut -d',' -f3)
        countdown=$(echo "$reboot_status" | cut -d',' -f4)
        reboot_ready=$(echo "$reboot_status" | cut -d',' -f5)

        echo ""
        echo "📈 REBOOT STATUS BREAKDOWN:"
        echo "   🔧 Software Update State: $update_state"
        echo "   🔄 Requires Reboot: $requires_reboot"
        echo "   📅 Scheduled UTC Time: $scheduled_utc"
        echo "   ⏱️  Countdown: ${countdown}s"
        echo "   ✅ Reboot Ready: $reboot_ready"

        # Convert scheduled time to human readable if available
        if [ "$scheduled_utc" != "0" ] && [ "$scheduled_utc" != "null" ]; then
            if command -v date >/dev/null 2>&1; then
                scheduled_readable=$(date -d "@$scheduled_utc" 2>/dev/null || date -r "$scheduled_utc" 2>/dev/null || echo "Unable to convert")
                echo "   📅 Scheduled Time (readable): $scheduled_readable"
            fi
        fi

        # Test failover decision for reboot
        echo ""
        echo "🚨 TESTING REBOOT FAILOVER DECISION:"
        if command -v should_failover_for_reboot >/dev/null 2>&1; then
            if should_failover_for_reboot "$reboot_status"; then
                echo "🚨 PREDICTIVE FAILOVER TRIGGERED: Reboot conditions warrant immediate failover"
                echo "   📋 Action: Switch to cellular backup immediately"
                echo "   🎯 Reason: Minimize service interruption from scheduled reboot"
            else
                echo "✅ NO FAILOVER NEEDED: No immediate reboot concerns detected"
            fi
        else
            echo "❌ should_failover_for_reboot() function not available"
        fi

    else
        echo "⚠️  Reboot status retrieval failed (may be expected if Starlink not available)"
    fi
else
    echo "❌ get_reboot_status() function not available"
fi

echo ""
echo "🏥 TESTING INTEGRATED HEALTH CHECK WITH REBOOT MONITORING"
echo "=========================================================="

if command -v check_starlink_health >/dev/null 2>&1; then
    echo "✅ check_starlink_health() function available"

    # Test integrated health check
    echo "Getting comprehensive health status with reboot monitoring:"
    health_status=$(check_starlink_health 2>/dev/null || echo "ERROR")

    if [ "$health_status" != "ERROR" ]; then
        echo "✅ Health status retrieved: $health_status"
        echo "   Format: overall,hardware_test,dl_bw_reason,ul_bw_reason,thermal_throttle,thermal_shutdown,roaming,reboot_imminent,reboot_countdown"

        # Parse enhanced health status
        overall=$(echo "$health_status" | cut -d',' -f1)
        hardware_test=$(echo "$health_status" | cut -d',' -f2)
        dl_bw_reason=$(echo "$health_status" | cut -d',' -f3)
        ul_bw_reason=$(echo "$health_status" | cut -d',' -f4)
        thermal_throttle=$(echo "$health_status" | cut -d',' -f5)
        thermal_shutdown=$(echo "$health_status" | cut -d',' -f6)
        roaming=$(echo "$health_status" | cut -d',' -f7)
        reboot_imminent=$(echo "$health_status" | cut -d',' -f8)
        reboot_countdown=$(echo "$health_status" | cut -d',' -f9)

        echo ""
        echo "📊 ENHANCED HEALTH STATUS BREAKDOWN:"
        echo "   🏥 Overall Status: $overall"
        echo "   🔧 Hardware Self-Test: $hardware_test"
        echo "   📶 Bandwidth Restrictions: DL=$dl_bw_reason, UL=$ul_bw_reason"
        echo "   🌡️  Thermal Status: Throttle=$thermal_throttle, Shutdown=$thermal_shutdown"
        echo "   🌍 Roaming Alert: $roaming"
        echo "   🔄 Reboot Imminent: $reboot_imminent"
        echo "   ⏱️  Reboot Countdown: ${reboot_countdown}s"

        # Highlight reboot status
        if [ "$reboot_imminent" = "true" ]; then
            echo ""
            echo "🚨 PREDICTIVE FAILOVER ALERT:"
            echo "   ⚠️  Reboot is imminent!"
            if [ "$reboot_countdown" != "0" ] && [ "$reboot_countdown" -gt 0 ]; then
                echo "   ⏰ Time remaining: ${reboot_countdown} seconds"
                echo "   📋 Recommendation: Execute failover immediately to minimize downtime"
            else
                echo "   📋 Recommendation: Execute failover immediately - reboot required or overdue"
            fi
        fi

        # Test overall failover decision
        echo ""
        echo "🚨 TESTING INTEGRATED FAILOVER DECISION:"
        if command -v should_trigger_failover >/dev/null 2>&1; then
            if should_trigger_failover "$health_status"; then
                echo "🚨 FAILOVER TRIGGERED: System conditions warrant immediate failover"
                case "$overall" in
                    reboot_imminent)
                        echo "   🔄 Primary Reason: Predictive failover for scheduled reboot"
                        ;;
                    critical)
                        echo "   💥 Primary Reason: Critical system health issue"
                        ;;
                    unknown)
                        echo "   ❓ Primary Reason: Health status unknown - precautionary failover"
                        ;;
                esac
            else
                echo "✅ NO FAILOVER NEEDED: System status acceptable"
            fi
        else
            echo "❌ should_trigger_failover() function not available"
        fi

    else
        echo "⚠️  Health status retrieval failed (may be expected if Starlink not available)"
    fi
else
    echo "❌ check_starlink_health() function not available"
fi

echo ""
echo "⚙️ CONFIGURATION EXAMPLES"
echo "========================="
echo "Environment variables for controlling predictive failover:"
echo ""
echo "# Reboot warning window (seconds before reboot to trigger failover)"
echo "export REBOOT_WARNING_SECONDS=300  # 5 minutes (default)"
echo "export REBOOT_WARNING_SECONDS=600  # 10 minutes (more conservative)"
echo "export REBOOT_WARNING_SECONDS=60   # 1 minute (last-minute failover)"
echo ""
echo "# Health monitoring control"
echo "export ENABLE_HEALTH_MONITORING=true   # Enable health checks (default)"
echo "export ENABLE_HEALTH_MONITORING=false  # Disable health monitoring"

echo ""
echo "🎯 PREDICTIVE FAILOVER BENEFITS"
echo "==============================="
echo "✨ Proactive Service Continuity:"
echo "   • Detects scheduled reboots before they happen"
echo "   • Calculates precise countdown to reboot"
echo "   • Triggers failover within configurable warning window"
echo "   • Minimizes service interruption duration"
echo ""
echo "🔍 Multiple Detection Methods:"
echo "   • Software update state monitoring (REBOOT_REQUIRED)"
echo "   • Scheduled reboot time tracking (rebootScheduledUtcTime)"
echo "   • Reboot readiness detection (swupdateRebootReady)"
echo "   • Update progress monitoring (softwareUpdateProgress)"
echo ""
echo "⚡ Intelligent Decision Making:"
echo "   • Time-based failover (configurable warning window)"
echo "   • State-based failover (immediate when reboot ready)"
echo "   • Integration with overall health assessment"
echo "   • Backwards compatible with existing monitoring"

echo ""
echo "🎉 PREDICTIVE REBOOT FAILOVER TESTING COMPLETE!"
echo "=============================================="
echo "The system now provides intelligent predictive failover capabilities"
echo "that can detect and respond to scheduled Starlink reboots before"
echo "they occur, minimizing service disruption and ensuring seamless"
echo "transition to backup connectivity."
