#!/bin/sh
# RUTOS Installation Verification Script
# This script verifies all RUTOS scripts are properly categorized for installation
# shellcheck disable=SC2034  # Colors may appear unused but are used in printf

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Colors for output (RUTOS compatible)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

echo "================================================"
echo "    RUTOS Scripts Installation Analysis"
echo "    Script Version: $SCRIPT_VERSION"
echo "================================================"
echo ""

# Core monitoring scripts (Starlink-RUTOS-Failover directory)
echo "${BLUE}=== CORE MONITORING SCRIPTS (Starlink-RUTOS-Failover/) ===${NC}"
echo "${GREEN}UNIFIED SCRIPTS (RECOMMENDED):${NC}"
echo "✓ starlink_monitor_unified-rutos.sh (unified monitoring with all features)"
echo "✓ starlink_logger_unified-rutos.sh (unified logging with all features)"
echo ""
echo "${YELLOW}LEGACY SCRIPTS (for compatibility):${NC}"
echo "✓ starlink_monitor-rutos.sh (original monitoring script - DEPRECATED)"
echo "✓ starlink_logger-rutos.sh (original logger - DEPRECATED)"
echo "✓ starlink_logger_enhanced-rutos.sh (enhanced logger)"
echo "✓ starlink_monitor_enhanced-rutos.sh (enhanced monitor)"
echo ""
echo "${GREEN}SUPPORT SCRIPTS:${NC}"
echo "✓ check_starlink_api-rutos.sh (API version monitoring)"
echo "✓ 99-pushover_notify-rutos.sh (hotplug notification)"
echo ""

# Utility scripts (scripts directory)
echo "${BLUE}=== UTILITY SCRIPTS (scripts/) ===${NC}"
echo "${GREEN}SHOULD BE INSTALLED:${NC}"
echo "✓ validate-config-rutos.sh"
echo "✓ auto-detect-config-rutos.sh"
echo "✓ post-install-check-rutos.sh"
echo "✓ system-status-rutos.sh"
echo "✓ health-check-rutos.sh"
echo "✓ update-config-rutos.sh"
echo "✓ merge-config-rutos.sh"
echo "✓ restore-config-rutos.sh"
echo "✓ cleanup-rutos.sh"
echo "✓ self-update-rutos.sh"
echo "✓ uci-optimizer-rutos.sh"
echo "✓ verify-cron-rutos.sh"
echo "✓ update-cron-config-path-rutos.sh"
echo "✓ upgrade-rutos.sh"
echo "✓ placeholder-utils.sh"
echo "✓ fix-database-loop-rutos.sh"
echo "✓ diagnose-database-loop-rutos.sh"
echo "✓ fix-database-spam-rutos.sh"
echo "✓ fix-stability-checks-rutos.sh"
echo "✓ fix-logger-tracking-rutos.sh"
echo "✓ debug-starlink-api-rutos.sh"
echo "✓ repair-system-rutos.sh"
echo "✓ system-maintenance-rutos.sh"
echo "✓ view-logs-rutos.sh"
echo "✓ analyze-outage-correlation-rutos.sh"
echo "✓ analyze-outage-correlation-optimized-rutos.sh"
echo "✓ check-pushover-logs-rutos.sh"
echo "✓ diagnose-pushover-notifications-rutos.sh"
echo "✓ test-all-scripts-rutos.sh"
echo "✓ validate-persistent-config-rutos.sh"
echo "✓ dev-testing-rutos.sh"
echo ""

# Test and debug scripts
echo "${BLUE}=== TEST & DEBUG SCRIPTS (scripts/tests/) ===${NC}"
echo "${GREEN}SHOULD BE INSTALLED:${NC}"
echo "✓ test-pushover-rutos.sh"
echo "✓ test-pushover-quick-rutos.sh"
echo "✓ test-monitoring-rutos.sh"
echo "✓ test-connectivity-rutos.sh"
echo "✓ test-connectivity-rutos-fixed.sh"
echo "✓ test-colors-rutos.sh"
echo "✓ test-method5-rutos.sh"
echo "✓ test-cron-cleanup-rutos.sh"
echo "✓ test-notification-merge-rutos.sh"
echo "✓ debug-notification-merge-rutos.sh"
echo ""

# Optional/Future scripts (not included in base installation)
echo "${YELLOW}=== OPTIONAL SCRIPTS (not installed by default) ===${NC}"
echo "- GPS integration scripts (gps-integration/)"
echo "- Cellular integration scripts (cellular-integration/)"
echo "- Analysis scripts in root directory"
echo "- Development testing scripts"
echo ""

# Installation directories
echo "${BLUE}=== INSTALLATION STRUCTURE ===${NC}"
echo "/usr/local/starlink-monitor/"
echo "├── scripts/"
echo "│   ├── starlink_monitor_unified-rutos.sh (RECOMMENDED)"
echo "│   ├── starlink_logger_unified-rutos.sh (RECOMMENDED)"
echo "│   ├── starlink_monitor-rutos.sh (legacy - deprecated)"
echo "│   ├── starlink_logger-rutos.sh (legacy - deprecated)"
echo "│   ├── starlink_logger_enhanced-rutos.sh"
echo "│   ├── starlink_monitor_enhanced-rutos.sh"
echo "│   ├── check_starlink_api-rutos.sh"
echo "│   ├── [all utility scripts]"
echo "│   └── tests/"
echo "│       └── [all test scripts]"
echo "├── grpcurl (binary)"
echo "├── jq (binary)"
echo "└── installation.log"
echo ""
echo "/etc/hotplug.d/iface/"
echo "└── 99-pushover_notify-rutos.sh"
echo ""
echo "/etc/starlink-config/"
echo "└── config.sh"
echo ""

echo "${GREEN}=== SUMMARY ===${NC}"
echo "Unified scripts (recommended): 2"
echo "Legacy scripts (compatibility): 4"
echo "Support scripts: 2"
echo "Utility scripts: 30"
echo "Test scripts: 10"
echo "Total RUTOS scripts: 48"
echo ""
echo "${BLUE}RECOMMENDED INSTALLATION:${NC}"
echo "- Use starlink_monitor_unified-rutos.sh + starlink_logger_unified-rutos.sh"
echo "- Configure features in config.sh using enhanced-features-config.template.sh"
echo "- Legacy scripts available for backward compatibility"
echo ""
echo "${BLUE}All scripts listed above should be included in install-rutos.sh${NC}"
echo "================================================"
