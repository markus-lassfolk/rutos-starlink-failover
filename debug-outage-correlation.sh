#!/bin/sh
# Debug specific outage correlation
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.6.0"

# Display version if requested
if [ "${1:-}" = "--version" ]; then
    echo "debug-outage-correlation.sh v$SCRIPT_VERSION"
    exit 0
fi

echo "=== DEBUGGING 12:57 OUTAGE CORRELATION ==="

# Extract events from the actual log file that should correlate
echo "Events around 12:56-12:58 from actual log:"
grep -E "2025-07-24 12:5[6-8]:" ./temp/starlink_monitor_2025-07-24.log | grep -E "(info|warn|error)"

echo ""
echo "Checking for the specific events mentioned in optimized results:"
grep -E "Performing soft failover|Quality degraded below threshold" ./temp/starlink_monitor_2025-07-24.log

echo ""
echo "Full context around 12:56:02:"
grep -B 2 -A 2 "2025-07-24 12:56:02" ./temp/starlink_monitor_2025-07-24.log
