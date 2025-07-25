#!/bin/sh
# Quick comprehensive data analysis

LOG_FILE="./temp/starlink_monitor_2025-07-24.log"
REPORT_FILE="quick_comprehensive_analysis.md"

echo "# RUTOS Comprehensive Data Analysis" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# System States
echo "## System State Analysis" >> "$REPORT_FILE"
STATE_UP=$(grep "Current state: up" "$LOG_FILE" | wc -l)
STATE_DOWN=$(grep "Current state: down" "$LOG_FILE" | wc -l)
echo "- UP states: $STATE_UP" >> "$REPORT_FILE"
echo "- DOWN states: $STATE_DOWN" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Routing Metrics  
echo "## Routing Analysis" >> "$REPORT_FILE"
METRIC_1=$(grep "Metric: 1" "$LOG_FILE" | wc -l)
METRIC_20=$(grep "Metric: 20" "$LOG_FILE" | wc -l)
echo "- Good routing (Metric: 1): $METRIC_1" >> "$REPORT_FILE"
echo "- Failover routing (Metric: 20): $METRIC_20" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Stability Analysis
echo "## Stability Counter Analysis" >> "$REPORT_FILE"
grep "Stability:" "$LOG_FILE" | sed 's/.*Stability: \([0-9]*\).*/\1/' | sort -n | uniq -c | while read count stability; do
    echo "- Stability $stability: $count occurrences" >> "$REPORT_FILE"
done
echo "" >> "$REPORT_FILE"

# GPS Analysis  
echo "## Enhanced GPS Analysis" >> "$REPORT_FILE"
GPS_VALID=$(grep "GPS: valid=true" "$LOG_FILE" | wc -l)
GPS_INVALID=$(grep "GPS: valid=false" "$LOG_FILE" | wc -l)
echo "- Valid GPS: $GPS_VALID" >> "$REPORT_FILE"
echo "- Invalid GPS: $GPS_INVALID" >> "$REPORT_FILE"

GPS_MIN=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | head -1)
GPS_MAX=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | tail -1)
GPS_UNIQUE=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | uniq | wc -l)
echo "- GPS satellite range: $GPS_MIN to $GPS_MAX satellites" >> "$REPORT_FILE"
echo "- GPS unique values: $GPS_UNIQUE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# SNR Quality Analysis
echo "## Signal Quality (SNR) Analysis" >> "$REPORT_FILE"
SNR_POOR=$(grep "SNR:.*poor: [1-9]" "$LOG_FILE" | wc -l)
SNR_GOOD=$(grep "SNR:.*poor: 0" "$LOG_FILE" | wc -l)
SNR_ABOVE_NOISE_TRUE=$(grep "above_noise: true" "$LOG_FILE" | wc -l)
SNR_ABOVE_NOISE_FALSE=$(grep "above_noise: false" "$LOG_FILE" | wc -l)
SNR_PERSISTENTLY_LOW_TRUE=$(grep "persistently_low: true" "$LOG_FILE" | wc -l)
SNR_PERSISTENTLY_LOW_FALSE=$(grep "persistently_low: false" "$LOG_FILE" | wc -l)

echo "- SNR Poor conditions: $SNR_POOR events" >> "$REPORT_FILE"
echo "- SNR Good conditions: $SNR_GOOD events" >> "$REPORT_FILE"
echo "- Above noise floor: $SNR_ABOVE_NOISE_TRUE times" >> "$REPORT_FILE"
echo "- Below noise floor: $SNR_ABOVE_NOISE_FALSE times" >> "$REPORT_FILE"
echo "- Persistently low SNR: $SNR_PERSISTENTLY_LOW_TRUE times" >> "$REPORT_FILE"
echo "- SNR not persistently low: $SNR_PERSISTENTLY_LOW_FALSE times" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Threshold Breach Analysis
echo "## Threshold Breach Analysis" >> "$REPORT_FILE"
HIGH_LOSS=$(grep "Loss:.*high: [1-9]" "$LOG_FILE" | wc -l)
HIGH_OBSTRUCTION=$(grep "Obstruction:.*high: [1-9]" "$LOG_FILE" | wc -l)
HIGH_LATENCY=$(grep "Latency:.*high: [1-9]" "$LOG_FILE" | wc -l)

echo "- High packet loss flags: $HIGH_LOSS events" >> "$REPORT_FILE"
echo "- High obstruction flags: $HIGH_OBSTRUCTION events" >> "$REPORT_FILE"
echo "- High latency flags: $HIGH_LATENCY events" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Monitoring Frequency
echo "## Monitoring Frequency Analysis" >> "$REPORT_FILE"
MONITOR_STARTS=$(grep "Starting Starlink monitor check" "$LOG_FILE" | wc -l)
MONITOR_COMPLETED=$(grep "Monitor check completed" "$LOG_FILE" | wc -l)
MONITOR_STOPPED=$(grep "Monitor stopped" "$LOG_FILE" | wc -l)
API_ERRORS=$(grep -i "error\|failed\|timeout" "$LOG_FILE" | wc -l)

echo "- Monitor starts: $MONITOR_STARTS" >> "$REPORT_FILE"
echo "- Monitor completions: $MONITOR_COMPLETED" >> "$REPORT_FILE"
echo "- Monitor stops: $MONITOR_STOPPED" >> "$REPORT_FILE"
echo "- API errors/failures: $API_ERRORS" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Data Quality
echo "## Data Quality Summary" >> "$REPORT_FILE"
TOTAL_LINES=$(wc -l < "$LOG_FILE")
BASIC_METRICS=$(grep "Basic Metrics" "$LOG_FILE" | wc -l)
ENHANCED_METRICS=$(grep "Enhanced Metrics" "$LOG_FILE" | wc -l)

echo "- Total log lines: $TOTAL_LINES" >> "$REPORT_FILE"
echo "- Basic metrics entries: $BASIC_METRICS" >> "$REPORT_FILE"
echo "- Enhanced metrics entries: $ENHANCED_METRICS" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Newly Discovered Metrics
echo "## Additional Metrics Available" >> "$REPORT_FILE"
echo "### New data points discovered:" >> "$REPORT_FILE"
echo "1. **System state tracking** - Connection up/down status" >> "$REPORT_FILE"
echo "2. **Routing metrics** - Priority values (1=good, 20=failover)" >> "$REPORT_FILE"
echo "3. **Stability counters** - Progressive tracking for failback decisions" >> "$REPORT_FILE"
echo "4. **GPS validity status** - Beyond just satellite counts" >> "$REPORT_FILE"
echo "5. **SNR quality flags** - Multiple signal quality indicators" >> "$REPORT_FILE"
echo "6. **Threshold breach flags** - Real-time high flags for each metric" >> "$REPORT_FILE"
echo "7. **Monitoring health** - API success/failure tracking" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Report generated: $REPORT_FILE"
echo "Analysis complete!"

# Summary to terminal
echo ""
echo "=== Quick Summary ==="
echo "System States: $STATE_UP up, $STATE_DOWN down"
echo "Routing: $METRIC_1 good, $METRIC_20 failover"
echo "GPS: $GPS_VALID valid, $GPS_INVALID invalid"
echo "SNR: $SNR_GOOD good, $SNR_POOR poor conditions"  
echo "Monitoring: $MONITOR_STARTS checks, $API_ERRORS errors"
echo "High flags: $HIGH_LOSS loss, $HIGH_OBSTRUCTION obstruction, $HIGH_LATENCY latency"
