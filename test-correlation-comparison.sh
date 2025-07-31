#!/bin/sh
# Test to compare correlation logic between original and optimized versions
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.6.0"

# Display version if requested
if [ "${1:-}" = "--version" ]; then
    echo "test-correlation-comparison.sh v$SCRIPT_VERSION"
    exit 0
fi

echo "=== CORRELATION COMPARISON TEST ==="

# Extract just the 12:57 outage logic (the one that should have 2 correlations)
OUTAGE_TIME="12:57"
# shellcheck disable=SC2034  # Used later in the script
OUTAGE_DURATION="10"

# Original logic
echo "Original time_to_seconds calculation:"
outage_seconds=$(echo "$OUTAGE_TIME" | sed 's/:/ /' | while read -r hour minute; do
    hour=$(printf "%d" "$hour" 2>/dev/null || echo "0")
    minute=$(printf "%d" "$minute" 2>/dev/null || echo "0")
    echo $((hour * 3600 + minute * 60))
done)
echo "Outage seconds: $outage_seconds"

start_window=$((outage_seconds - 60))
end_window=$((outage_seconds + OUTAGE_DURATION + 60))
echo "Original window: $start_window - $end_window"

# Test with actual log data
echo ""
echo "=== Testing with actual log samples ==="
echo "Looking for events around 12:56-12:58..."

# Sample log entries from the actual log
cat >/tmp/test_events.txt <<'EOF'
2025-07-24 12:56:02 [info] Performing soft failover - setting metric to 20
2025-07-24 12:56:02 [warn] Quality degraded below threshold: [Obstructed: 0.005540166%]
2025-07-24 12:57:15 [debug] Some other event
2025-07-24 12:58:30 [info] Another event
EOF

echo "Test events:"
cat /tmp/test_events.txt

echo ""
echo "Checking which events fall in window $start_window - $end_window..."

while read -r event_line; do
    event_timestamp=$(echo "$event_line" | grep -o '2025-07-24 [0-9:]*' | awk '{print $2}')
    if [ -n "$event_timestamp" ]; then
        hour=$(echo "$event_timestamp" | cut -d: -f1)
        minute=$(echo "$event_timestamp" | cut -d: -f2)
        second=$(echo "$event_timestamp" | cut -d: -f3)

        hour=$(printf "%d" "$hour" 2>/dev/null || echo "0")
        minute=$(printf "%d" "$minute" 2>/dev/null || echo "0")
        second=$(printf "%d" "$second" 2>/dev/null || echo "0")

        event_seconds=$((hour * 3600 + minute * 60 + second))

        echo "Event at $event_timestamp = $event_seconds seconds"
        if [ "$event_seconds" -ge "$start_window" ] && [ "$event_seconds" -le "$end_window" ]; then
            echo "  ✓ CORRELATED: $event_line"
        else
            echo "  ✗ Outside window: $event_line"
        fi
    fi
done </tmp/test_events.txt

rm -f /tmp/test_events.txt
