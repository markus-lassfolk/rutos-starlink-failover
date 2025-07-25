#!/bin/sh
# Quick comprehensive analysis for RUTOS monitoring logs
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

echo "Quick Comprehensive Analysis v$SCRIPT_VERSION"
echo "============================================="
echo ""

LOG_FILE="./temp/starlink_monitor_2025-07-24.log"
REPORT_FILE="quick_comprehensive_analysis.md"

echo "# RUTOS Comprehensive Data Analysis" >"$REPORT_FILE"
echo "" >>"$REPORT_FILE"

# System States
echo "## System State Analysis" >>"$REPORT_FILE"
STATE_UP=$(grep -c "Current state: up" "$LOG_FILE")
STATE_DOWN=$(grep -c "Current state: down" "$LOG_FILE")
{
    echo "- UP states: $STATE_UP"
    echo "- DOWN states: $STATE_DOWN"
    echo ""
} >>"$REPORT_FILE"

# Routing Metrics
echo "## Routing Analysis" >>"$REPORT_FILE"
METRIC_1=$(grep -c "Metric: 1" "$LOG_FILE")
METRIC_20=$(grep -c "Metric: 20" "$LOG_FILE")
{
    echo "- Good routing (Metric: 1): $METRIC_1"
    echo "- Failover routing (Metric: 20): $METRIC_20"
    echo ""
} >>"$REPORT_FILE"

# Stability Analysis
echo "## Stability Counter Analysis" >>"$REPORT_FILE"
grep "Stability:" "$LOG_FILE" | sed 's/.*Stability: \([0-9]*\).*/\1/' | sort -n | uniq -c | while read -r count stability; do
    echo "- Stability $stability: $count occurrences" >>"$REPORT_FILE"
done
echo "" >>"$REPORT_FILE"

# GPS Analysis
echo "## Enhanced GPS Analysis" >>"$REPORT_FILE"
GPS_VALID=$(grep -c "GPS: valid=true" "$LOG_FILE")
GPS_INVALID=$(grep -c "GPS: valid=false" "$LOG_FILE")
echo "- Valid GPS: $GPS_VALID" >>"$REPORT_FILE"
echo "- Invalid GPS: $GPS_INVALID" >>"$REPORT_FILE"

GPS_MIN=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | head -1)
GPS_MAX=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | tail -1)
GPS_UNIQUE=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | uniq | wc -l)
{
    echo "- GPS satellite range: $GPS_MIN to $GPS_MAX satellites"
    echo "- GPS unique values: $GPS_UNIQUE"
    echo ""
} >>"$REPORT_FILE"

# SNR Quality Analysis
echo "## Signal Quality (SNR) Analysis" >>"$REPORT_FILE"
SNR_POOR=$(grep -c "SNR:.*poor: [1-9]" "$LOG_FILE")
SNR_GOOD=$(grep -c "SNR:.*poor: 0" "$LOG_FILE")
SNR_ABOVE_NOISE_TRUE=$(grep -c "above_noise: true" "$LOG_FILE")
SNR_ABOVE_NOISE_FALSE=$(grep -c "above_noise: false" "$LOG_FILE")
SNR_PERSISTENTLY_LOW_TRUE=$(grep -c "persistently_low: true" "$LOG_FILE")
SNR_PERSISTENTLY_LOW_FALSE=$(grep -c "persistently_low: false" "$LOG_FILE")

{
    echo "- SNR Poor conditions: $SNR_POOR events"
    echo "- SNR Good conditions: $SNR_GOOD events"
    echo "- Above noise floor: $SNR_ABOVE_NOISE_TRUE times"
    echo "- Below noise floor: $SNR_ABOVE_NOISE_FALSE times"
    echo "- Persistently low SNR: $SNR_PERSISTENTLY_LOW_TRUE times"
    echo "- SNR not persistently low: $SNR_PERSISTENTLY_LOW_FALSE times"
    echo ""
} >>"$REPORT_FILE"

# Threshold Breach Analysis
echo "## Threshold Breach Analysis" >>"$REPORT_FILE"
HIGH_LOSS=$(grep -c "Loss:.*high: [1-9]" "$LOG_FILE")
HIGH_OBSTRUCTION=$(grep -c "Obstruction:.*high: [1-9]" "$LOG_FILE")
HIGH_LATENCY=$(grep -c "Latency:.*high: [1-9]" "$LOG_FILE")

{
    echo "- High packet loss flags: $HIGH_LOSS events"
    echo "- High obstruction flags: $HIGH_OBSTRUCTION events"
    echo "- High latency flags: $HIGH_LATENCY events"
    echo ""
} >>"$REPORT_FILE"

# Monitoring Frequency
echo "## Monitoring Frequency Analysis" >>"$REPORT_FILE"
MONITOR_STARTS=$(grep -c "Starting Starlink monitor check" "$LOG_FILE")
MONITOR_COMPLETED=$(grep -c "Monitor check completed" "$LOG_FILE")
MONITOR_STOPPED=$(grep -c "Monitor stopped" "$LOG_FILE")
API_ERRORS=$(grep -ic "error\|failed\|timeout" "$LOG_FILE")

{
    echo "- Monitor starts: $MONITOR_STARTS"
    echo "- Monitor completions: $MONITOR_COMPLETED"
    echo "- Monitor stops: $MONITOR_STOPPED"
    echo "- API errors/failures: $API_ERRORS"
    echo ""
} >>"$REPORT_FILE"

# Data Quality
echo "## Data Quality Summary" >>"$REPORT_FILE"
TOTAL_LINES=$(wc -l <"$LOG_FILE")
BASIC_METRICS=$(grep -c "Basic Metrics" "$LOG_FILE")
ENHANCED_METRICS=$(grep -c "Enhanced Metrics" "$LOG_FILE")

{
    echo "- Total log lines: $TOTAL_LINES"
    echo "- Basic metrics entries: $BASIC_METRICS"
    echo "- Enhanced metrics entries: $ENHANCED_METRICS"
    echo ""
} >>"$REPORT_FILE"

# Newly Discovered Metrics
{
    echo "## Additional Metrics Available"
    echo "### New data points discovered:"
    echo "1. **System state tracking** - Connection up/down status"
    echo "2. **Routing metrics** - Priority values (1=good, 20=failover)"
    echo "3. **Stability counters** - Progressive tracking for failback decisions"
    echo "4. **GPS validity status** - Beyond just satellite counts"
    echo "5. **SNR quality flags** - Multiple signal quality indicators"
    echo "6. **Threshold breach flags** - Real-time high flags for each metric"
    echo "7. **Monitoring health** - API success/failure tracking"
    echo ""
} >>"$REPORT_FILE"

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
