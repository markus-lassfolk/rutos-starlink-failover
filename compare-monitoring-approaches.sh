#!/bin/sh
set -e

# Comparison tool for monitoring approaches
echo "🔄 RUTOS Starlink Monitoring: Cron vs Daemon Comparison"
echo "======================================================="

# Function to check current setup
check_current_setup() {
    echo ""
    echo "📊 Current System Analysis:"
    echo "----------------------------"

    # Check for cron-based monitoring
    if crontab -l 2>/dev/null | grep -q starlink; then
        echo "✓ Found cron-based monitoring:"
        crontab -l 2>/dev/null | grep starlink | sed 's/^/  /'
        CURRENT_MODE="cron"
    else
        echo "ℹ️ No cron-based monitoring found"
        CURRENT_MODE="none"
    fi

    # Check for daemon-based monitoring
    if [ -f "/etc/init.d/starlink-monitor" ]; then
        echo "✓ Found daemon service setup"
        if /etc/init.d/starlink-monitor status >/dev/null 2>&1; then
            echo "✓ Daemon is currently running"
            CURRENT_MODE="daemon"
        else
            echo "⚠️ Daemon service exists but not running"
        fi
    else
        echo "ℹ️ No daemon service found"
    fi

    # Check for intelligent monitoring script
    if [ -f "/root/starlink_monitor_unified-rutos.sh" ]; then
        echo "✓ Intelligent monitoring script found"

        # Test if it has new v3.0 features
        if grep -q "run_intelligent_monitoring" /root/starlink_monitor_unified-rutos.sh 2>/dev/null; then
            echo "✓ Script has v3.0 intelligent features"
            SCRIPT_VERSION="v3.0"
        else
            echo "ℹ️ Script is legacy version"
            SCRIPT_VERSION="legacy"
        fi
    else
        echo "❌ No monitoring script found"
        SCRIPT_VERSION="none"
    fi

    # Check MWAN3 availability
    if command -v mwan3 >/dev/null 2>&1; then
        echo "✓ MWAN3 available"
        interface_count=$(uci show mwan3 2>/dev/null | grep "interface=" | wc -l)
        echo "ℹ️ MWAN3 interfaces configured: $interface_count"
        MWAN3_AVAILABLE="yes"
    else
        echo "❌ MWAN3 not available"
        MWAN3_AVAILABLE="no"
    fi
}

# Function to show feature comparison
show_feature_comparison() {
    echo ""
    echo "🆚 Feature Comparison: Cron vs Daemon"
    echo "======================================"

    printf "%-30s | %-15s | %-15s\n" "Feature" "Cron Mode" "Daemon Mode"
    printf "%-30s-+-%-15s-+-%-15s\n" "------------------------------" "---------------" "---------------"
    printf "%-30s | %-15s | %-15s\n" "Historical Analysis" "❌ None" "✅ Complete"
    printf "%-30s | %-15s | %-15s\n" "Predictive Failover" "❌ Reactive" "✅ Proactive"
    printf "%-30s | %-15s | %-15s\n" "State Persistence" "❌ None" "✅ Full"
    printf "%-30s | %-15s | %-15s\n" "Adaptive Timing" "❌ Fixed" "✅ Dynamic"
    printf "%-30s | %-15s | %-15s\n" "Multi-Interface Support" "🟡 Limited" "✅ Full"
    printf "%-30s | %-15s | %-15s\n" "Resource Efficiency" "🟡 Medium" "✅ High"
    printf "%-30s | %-15s | %-15s\n" "Trend Analysis" "❌ None" "✅ Complete"
    printf "%-30s | %-15s | %-15s\n" "Intelligent Metrics" "❌ None" "✅ Dynamic"
    printf "%-30s | %-15s | %-15s\n" "Performance Correlation" "❌ None" "✅ Advanced"
    printf "%-30s | %-15s | %-15s\n" "Startup Overhead" "❌ High" "✅ None"
}

# Function to show recommendations
show_recommendations() {
    echo ""
    echo "🎯 Recommendations Based on Your System:"
    echo "========================================"

    if [ "$MWAN3_AVAILABLE" = "no" ]; then
        echo "❌ MWAN3 Required: Install MWAN3 first for intelligent monitoring"
        echo "   Command: opkg update && opkg install mwan3"
        echo ""
        return
    fi

    case "$CURRENT_MODE" in
        "cron")
            echo "🔄 UPGRADE RECOMMENDED: You're using legacy cron-based monitoring"
            echo ""
            echo "Benefits of upgrading to daemon mode:"
            echo "  ✅ Intelligent predictive failover"
            echo "  ✅ Historical performance analysis"
            echo "  ✅ Dynamic metric adjustment"
            echo "  ✅ Better resource efficiency"
            echo ""
            echo "Upgrade command:"
            echo "  ./deploy-starlink-solution-v3-rutos.sh"
            ;;
        "daemon")
            echo "✅ OPTIMAL SETUP: You're using intelligent daemon-based monitoring"
            echo ""
            echo "Current benefits:"
            echo "  ✅ Predictive failover active"
            echo "  ✅ Historical analysis running"
            echo "  ✅ Resource efficient operation"
            echo ""
            echo "Verify system health:"
            echo "  /root/starlink_monitor_unified-rutos.sh status"
            ;;
        "none")
            echo "🚀 FRESH INSTALLATION: No monitoring detected"
            echo ""
            echo "Recommended: Start with intelligent daemon-based monitoring"
            echo "  ./deploy-starlink-solution-v3-rutos.sh"
            echo ""
            echo "This will provide:"
            echo "  ✅ Best-in-class intelligent monitoring"
            echo "  ✅ Automatic MWAN3 integration"
            echo "  ✅ Predictive failover capabilities"
            ;;
    esac
}

# Function to show migration path
show_migration_path() {
    echo ""
    echo "🔄 Migration Path:"
    echo "=================="

    if [ "$CURRENT_MODE" = "cron" ]; then
        echo "Your migration options:"
        echo ""
        echo "1. 🚀 CLEAN MIGRATION (Recommended)"
        echo "   - Removes legacy cron jobs"
        echo "   - Installs intelligent daemon"
        echo "   - Full v3.0 features"
        echo "   Command: ./deploy-starlink-solution-v3-rutos.sh"
        echo ""
        echo "2. 🔄 HYBRID MIGRATION (Conservative)"
        echo "   - Keeps some cron jobs for compatibility"
        echo "   - Adds intelligent daemon"
        echo "   - Gradual transition"
        echo "   Command: ./deploy-starlink-solution-v3-rutos.sh (choose hybrid mode)"
        echo ""
        echo "3. 🧪 MANUAL TESTING"
        echo "   - Test new system alongside old"
        echo "   - Manual migration control"
        echo "   Commands:"
        echo "     ./test-intelligent-system.sh"
        echo "     /root/starlink_monitor_unified-rutos.sh test --debug"
    fi
}

# Function to show quick actions
show_quick_actions() {
    echo ""
    echo "⚡ Quick Actions:"
    echo "================"

    echo "Test current system:"
    echo "  crontab -l | grep starlink"
    echo ""

    if [ -f "/root/starlink_monitor_unified-rutos.sh" ]; then
        echo "Test intelligent monitoring:"
        echo "  /root/starlink_monitor_unified-rutos.sh validate"
        echo "  /root/starlink_monitor_unified-rutos.sh discover"
        echo "  /root/starlink_monitor_unified-rutos.sh test --debug"
        echo ""
    fi

    if [ "$CURRENT_MODE" = "daemon" ]; then
        echo "Check daemon status:"
        echo "  /root/starlink_monitor_unified-rutos.sh status"
        echo "  tail -f /root/logs/rutos-lib.log"
        echo ""
    fi

    echo "Install/upgrade to v3.0:"
    echo "  curl -L https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/deploy-starlink-solution-v3-rutos.sh | sh"
}

# Main execution
main() {
    check_current_setup
    show_feature_comparison
    show_recommendations
    show_migration_path
    show_quick_actions

    echo ""
    echo "📖 For detailed migration guide, see: MIGRATION-GUIDE.md"
    echo "🧠 For intelligent system documentation, see: README-INTELLIGENT.md"
    echo ""
}

# Run the comparison
main
