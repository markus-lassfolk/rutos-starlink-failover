#!/bin/sh
# Analyze data variations in RUTOS monitoring logs

echo "=== STARLINK MONITORING DATA ANALYSIS ==="
echo "Analyzing data variations to validate monitoring accuracy"
echo ""

LOG_FILE="./temp/starlink_monitor_2025-07-24.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file not found: $LOG_FILE"
    exit 1
fi

echo "📊 BASIC METRICS ANALYSIS"
echo "========================="

# Extract and analyze Loss data
echo "📈 PACKET LOSS ANALYSIS:"
echo "------------------------"
grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Loss: \([0-9.]*\).*/\1/' | sort -n | {
    echo "Raw loss values (first 10):"
    head -10
    echo ""
    echo "Statistics:"
    awk '
    BEGIN { min=999; max=0; sum=0; count=0; zero_count=0 }
    {
        if (NF > 0 && $1 != "") {
            val = $1 + 0
            if (val < min) min = val
            if (val > max) max = val
            sum += val
            count++
            if (val == 0) zero_count++
        }
    }
    END {
        if (count > 0) {
            printf "  Minimum Loss: %.6f\n", min
            printf "  Maximum Loss: %.6f\n", max
            printf "  Average Loss: %.6f\n", sum/count
            printf "  Total samples: %d\n", count
            printf "  Zero values: %d (%.1f%%)\n", zero_count, (zero_count/count)*100
            printf "  Non-zero values: %d (%.1f%%)\n", count-zero_count, ((count-zero_count)/count)*100
        }
    }'
}

echo ""

# Extract and analyze Obstruction data
echo "🚧 OBSTRUCTION ANALYSIS:"
echo "------------------------"
grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Obstruction: \([0-9.]*\).*/\1/' | sort -n | {
    echo "Raw obstruction values (first 10):"
    head -10
    echo ""
    echo "Statistics:"
    awk '
    BEGIN { min=999; max=0; sum=0; count=0; zero_count=0 }
    {
        if (NF > 0 && $1 != "") {
            val = $1 + 0
            if (val < min) min = val
            if (val > max) max = val
            sum += val
            count++
            if (val == 0) zero_count++
        }
    }
    END {
        if (count > 0) {
            printf "  Minimum Obstruction: %.6f\n", min
            printf "  Maximum Obstruction: %.6f\n", max
            printf "  Average Obstruction: %.6f\n", sum/count
            printf "  Total samples: %d\n", count
            printf "  Zero values: %d (%.1f%%)\n", zero_count, (zero_count/count)*100
            printf "  Non-zero values: %d (%.1f%%)\n", count-zero_count, ((count-zero_count)/count)*100
        }
    }'
}

echo ""

# Extract and analyze Latency data
echo "⏱️  LATENCY ANALYSIS:"
echo "--------------------"
grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Latency: \([0-9]*\)ms.*/\1/' | sort -n | {
    echo "Raw latency values (first 10):"
    head -10
    echo ""
    echo "Statistics:"
    awk '
    BEGIN { min=9999; max=0; sum=0; count=0 }
    {
        if (NF > 0 && $1 != "") {
            val = $1 + 0
            if (val < min) min = val
            if (val > max) max = val
            sum += val
            count++
        }
    }
    END {
        if (count > 0) {
            printf "  Minimum Latency: %d ms\n", min
            printf "  Maximum Latency: %d ms\n", max
            printf "  Average Latency: %.1f ms\n", sum/count
            printf "  Total samples: %d\n", count
        }
    }'
}

echo ""
echo "🔍 ENHANCED METRICS ANALYSIS"
echo "============================"

# Extract and analyze SNR data
echo "📡 SIGNAL-TO-NOISE RATIO (SNR) ANALYSIS:"
echo "----------------------------------------"
grep "Enhanced Metrics" "$LOG_FILE" | sed 's/.*SNR: \([0-9]*\)dB.*/\1/' | sort -n | {
    echo "Raw SNR values (first 10):"
    head -10
    echo ""
    echo "Statistics:"
    awk '
    BEGIN { min=999; max=-999; sum=0; count=0; zero_count=0 }
    {
        if (NF > 0 && $1 != "") {
            val = $1 + 0
            if (val < min) min = val
            if (val > max) max = val
            sum += val
            count++
            if (val == 0) zero_count++
        }
    }
    END {
        if (count > 0) {
            printf "  Minimum SNR: %d dB\n", min
            printf "  Maximum SNR: %d dB\n", max
            printf "  Average SNR: %.1f dB\n", sum/count
            printf "  Total samples: %d\n", count
            printf "  Zero values: %d (%.1f%%)\n", zero_count, (zero_count/count)*100
            printf "  Non-zero values: %d (%.1f%%)\n", count-zero_count, ((count-zero_count)/count)*100
        }
    }'
}

echo ""

# Extract and analyze GPS satellite count
echo "🛰️  GPS SATELLITE COUNT ANALYSIS:"
echo "---------------------------------"
grep "Enhanced Metrics" "$LOG_FILE" | sed 's/.*sats=\([0-9]*\).*/\1/' | sort -n | {
    echo "Raw satellite count values (first 10):"
    head -10
    echo ""
    echo "Statistics:"
    awk '
    BEGIN { min=999; max=0; sum=0; count=0 }
    {
        if (NF > 0 && $1 != "") {
            val = $1 + 0
            if (val < min) min = val
            if (val > max) max = val
            sum += val
            count++
        }
    }
    END {
        if (count > 0) {
            printf "  Minimum Satellites: %d\n", min
            printf "  Maximum Satellites: %d\n", max
            printf "  Average Satellites: %.1f\n", sum/count
            printf "  Total samples: %d\n", count
        }
    }'
}

echo ""
echo "🔍 DATA QUALITY ASSESSMENT"
echo "=========================="

# Count total metrics samples
TOTAL_BASIC=$(grep -c "Basic Metrics" "$LOG_FILE")
TOTAL_ENHANCED=$(grep -c "Enhanced Metrics" "$LOG_FILE")

echo "📈 Sample Counts:"
echo "  Basic Metrics samples: $TOTAL_BASIC"
echo "  Enhanced Metrics samples: $TOTAL_ENHANCED"

echo ""
echo "🎯 REALISTIC VALUE RANGES:"
echo "  Packet Loss: Should be 0-100% (0-1.0)"
echo "  Obstruction: Should be 0-100% (0-1.0)"
echo "  Latency: Should be 20-2000ms for satellite"
echo "  SNR: Should be 0-30dB for Starlink"
echo "  GPS Satellites: Should be 4-20 typically"

echo ""
echo "✅ DATA VALIDATION SUMMARY:"

# Check for realistic variations
HAS_LOSS_VARIATION=$(grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Loss: \([0-9.]*\).*/\1/' | sort -u | wc -l)
HAS_OBSTRUCTION_VARIATION=$(grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Obstruction: \([0-9.]*\).*/\1/' | sort -u | wc -l)
HAS_LATENCY_VARIATION=$(grep "Basic Metrics" "$LOG_FILE" | sed 's/.*Latency: \([0-9]*\)ms.*/\1/' | sort -u | wc -l)
HAS_SNR_VARIATION=$(grep "Enhanced Metrics" "$LOG_FILE" | sed 's/.*SNR: \([0-9]*\)dB.*/\1/' | sort -u | wc -l)
HAS_GPS_VARIATION=$(grep "Enhanced Metrics" "$LOG_FILE" | sed 's/.*sats=\([0-9]*\).*/\1/' | sort -u | wc -l)

echo "  Unique Loss values: $HAS_LOSS_VARIATION"
echo "  Unique Obstruction values: $HAS_OBSTRUCTION_VARIATION"
echo "  Unique Latency values: $HAS_LATENCY_VARIATION"
echo "  Unique SNR values: $HAS_SNR_VARIATION"
echo "  Unique GPS satellite counts: $HAS_GPS_VARIATION"

echo ""
if [ "$HAS_LOSS_VARIATION" -gt 5 ] && [ "$HAS_LATENCY_VARIATION" -gt 5 ]; then
    echo "✅ DATA APPEARS TRUSTWORTHY: Multiple unique values detected"
else
    echo "⚠️  DATA MAY BE QUESTIONABLE: Limited variation detected"
fi
