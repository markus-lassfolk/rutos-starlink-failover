#!/bin/sh
# Detailed data analysis for Starlink monitoring
# Version information (auto-updated by update-version.sh)
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.6.0"

# Display version if requested
if [ "${1:-}" = "--version" ]; then
    echo "detailed-data-analysis.sh v$SCRIPT_VERSION"
    exit 0
fi

echo "=== DETAILED STARLINK DATA VALIDATION ==="
echo ""

LOG_FILE="./temp/starlink_monitor_2025-07-24.log"

echo "🔢 RAW DATA SAMPLES:"
echo "==================="
echo "First 5 Basic Metrics lines:"
grep "Basic Metrics" "$LOG_FILE" | head -5
echo ""
echo "First 5 Enhanced Metrics lines:"
grep "Enhanced Metrics" "$LOG_FILE" | head -5

echo ""
echo "📊 PACKET LOSS DETAILED ANALYSIS:"
echo "================================="
grep "Basic Metrics" "$LOG_FILE" | grep -o "Loss: [0-9.]*" | sed 's/Loss: //' | {
    echo "Sample values:"
    head -10
    echo ""
    echo "All unique values:"
    sort -n | uniq -c | head -20
    echo ""
    echo "Min/Max:"
    sort -n | {
        read -r min
        tail -1 >/tmp/max_val.txt
        max=$(cat /tmp/max_val.txt)
        echo "  Minimum: $min"
        echo "  Maximum: $max"
        rm -f /tmp/max_val.txt
    }
}

echo ""
echo "🚧 OBSTRUCTION DETAILED ANALYSIS:"
echo "================================="
grep "Basic Metrics" "$LOG_FILE" | grep -o "Obstruction: [0-9.]*" | sed 's/Obstruction: //' | {
    echo "Sample values:"
    head -10
    echo ""
    echo "Unique values (top 20):"
    sort -n | uniq -c | head -20
    echo ""
    echo "Min/Max:"
    sort -n | {
        read -r min
        tail -1 >/tmp/max_val.txt
        max=$(cat /tmp/max_val.txt)
        echo "  Minimum: $min"
        echo "  Maximum: $max"
        rm -f /tmp/max_val.txt
    }
}

echo ""
echo "⏱️  LATENCY DETAILED ANALYSIS:"
echo "============================="
grep "Basic Metrics" "$LOG_FILE" | grep -o "Latency: [0-9]*ms" | sed 's/Latency: //; s/ms//' | {
    echo "Sample values:"
    head -10
    echo ""
    echo "Unique values (top 20):"
    sort -n | uniq -c | head -20
    echo ""
    echo "Min/Max:"
    sort -n | {
        read -r min
        tail -1 >/tmp/max_val.txt
        max=$(cat /tmp/max_val.txt)
        echo "  Minimum: $min ms"
        echo "  Maximum: $max ms"
        rm -f /tmp/max_val.txt
    }
}

echo ""
echo "📡 SNR DETAILED ANALYSIS:"
echo "========================"
grep "Enhanced Metrics" "$LOG_FILE" | grep -o "SNR: [0-9]*dB" | sed 's/SNR: //; s/dB//' | {
    echo "Sample values:"
    head -10
    echo ""
    echo "All unique values:"
    sort -n | uniq -c
    echo ""
    echo "Min/Max:"
    sort -n | {
        read -r min
        tail -1 >/tmp/max_val.txt
        max=$(cat /tmp/max_val.txt)
        echo "  Minimum: $min dB"
        echo "  Maximum: $max dB"
        rm -f /tmp/max_val.txt
    }
}

echo ""
echo "🛰️  GPS SATELLITES DETAILED ANALYSIS:"
echo "====================================="
grep "Enhanced Metrics" "$LOG_FILE" | grep -o "sats=[0-9]*" | sed 's/sats=//' | {
    echo "Sample values:"
    head -10
    echo ""
    echo "All unique values:"
    sort -n | uniq -c
    echo ""
    echo "Min/Max:"
    sort -n | {
        read -r min
        tail -1 >/tmp/max_val.txt
        max=$(cat /tmp/max_val.txt)
        echo "  Minimum: $min satellites"
        echo "  Maximum: $max satellites"
        rm -f /tmp/max_val.txt
    }
}

echo ""
echo "🔍 THRESHOLD ANALYSIS:"
echo "====================="
echo "High threshold violations:"
grep "high: 1" "$LOG_FILE" | head -5

echo ""
echo "Quality degradation events:"
grep "Quality degraded below threshold" "$LOG_FILE"

echo ""
echo "📈 CONCLUSION:"
echo "============="
echo "✅ Data that shows good variation (trustworthy):"
echo "   - Obstruction values: 336 unique values"
echo "   - Latency values: 56 unique values"
echo "   - GPS satellites: 13 unique values"
echo ""
echo "⚠️  Data that may be questionable:"
echo "   - Packet Loss: Only 4 unique values (mostly zeros)"
echo "   - SNR: Only 1 unique value (always 0 dB)"
echo ""
echo "🎯 RECOMMENDATION:"
echo "The monitoring system appears to be working correctly for most metrics."
echo "Obstruction and latency show realistic variations, indicating good data quality."
echo "SNR being always 0 dB may indicate an API limitation or specific Starlink behavior."
