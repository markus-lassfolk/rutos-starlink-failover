#!/bin/sh
# Script: comprehensive-stats-analysis.sh
# Comprehensive statistical analysis of all available RUTOS monitoring data
# Version: 1.0.0

set -e

# Version information
SCRIPT_VERSION="1.0.0"

# Standard colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Configuration
LOG_FILE="${1:-./temp/starlink_monitor_2025-07-24.log}"
REPORT_FILE="comprehensive_data_analysis_$(date '+%Y%m%d_%H%M%S').md"

# Validate input
if [ ! -f "$LOG_FILE" ]; then
    printf "${RED}Error: Log file not found: %s${NC}\n" "$LOG_FILE"
    exit 1
fi

log_info "Starting comprehensive data analysis on: $LOG_FILE"
log_info "Report will be saved to: $REPORT_FILE"

# Initialize report
cat > "$REPORT_FILE" << 'EOF'
# Comprehensive RUTOS Monitoring Data Analysis

## Analysis Overview
This report provides detailed statistical analysis of ALL available metrics from your RUTOS Starlink monitoring system.

EOF

printf "**Analysis Date**: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
printf "**Log File**: %s\n" "$LOG_FILE" >> "$REPORT_FILE"
printf "**Total Log Size**: %s\n\n" "$(wc -c < "$LOG_FILE" | tr -d ' \n\r') bytes" >> "$REPORT_FILE"

# 1. SYSTEM STATE ANALYSIS
log_step "Analyzing system states and stability"

cat >> "$REPORT_FILE" << 'EOF'
## 1. System State Analysis

### Connection States
EOF

# State distribution
STATE_UP=$(grep "Current state: up" "$LOG_FILE" | wc -l | tr -d ' \n\r')
STATE_DOWN=$(grep "Current state: down" "$LOG_FILE" | wc -l | tr -d ' \n\r')
TOTAL_STATES=$((STATE_UP + STATE_DOWN))

if [ "$TOTAL_STATES" -gt 0 ]; then
    UP_PERCENT=$(( (STATE_UP * 100) / TOTAL_STATES ))
    DOWN_PERCENT=$(( (STATE_DOWN * 100) / TOTAL_STATES ))
    echo "- **UP states**: $STATE_UP ($UP_PERCENT%)" >> "$REPORT_FILE"
    echo "- **DOWN states**: $STATE_DOWN ($DOWN_PERCENT%)" >> "$REPORT_FILE"
else
    echo "- **UP states**: $STATE_UP" >> "$REPORT_FILE"
    echo "- **DOWN states**: $STATE_DOWN" >> "$REPORT_FILE"
fi

# Metric values (routing priorities)
METRIC_1=$(grep "Metric: 1" "$LOG_FILE" | wc -l | tr -d ' \n\r')
METRIC_20=$(grep "Metric: 20" "$LOG_FILE" | wc -l | tr -d ' \n\r')

cat >> "$REPORT_FILE" << EOF

### Routing Metrics
- **Good routing (Metric: 1)**: $METRIC_1 entries
- **Failover routing (Metric: 20)**: $METRIC_20 entries

EOF

# 2. STABILITY TRACKING
log_step "Analyzing stability patterns"

cat >> "$REPORT_FILE" << 'EOF'
## 2. Stability Analysis

### Stability Counter Distribution
EOF

# Extract unique stability values
STABILITY_VALUES=$(grep "Stability:" "$LOG_FILE" | sed 's/.*Stability: \([0-9]*\).*/\1/' | sort -n | uniq)
for stability in $STABILITY_VALUES; do
    count=$(grep "Stability: $stability" "$LOG_FILE" | wc -l | tr -d ' \n\r')
    echo "- **Stability $stability**: $count occurrences" >> "$REPORT_FILE"
done

# 3. ENHANCED GPS ANALYSIS  
log_step "Performing enhanced GPS analysis"

cat >> "$REPORT_FILE" << 'EOF'

## 3. Enhanced GPS Analysis

### GPS Validity Status
EOF

# GPS validity analysis
GPS_VALID=$(grep "GPS: valid=true" "$LOG_FILE" | wc -l | tr -d ' \n\r')
GPS_INVALID=$(grep "GPS: valid=false" "$LOG_FILE" | wc -l | tr -d ' \n\r')
GPS_TOTAL=$((GPS_VALID + GPS_INVALID))

if [ "$GPS_TOTAL" -gt 0 ]; then
    GPS_VALID_PERCENT=$(( (GPS_VALID * 100) / GPS_TOTAL ))
    GPS_INVALID_PERCENT=$(( (GPS_INVALID * 100) / GPS_TOTAL ))
    echo "- **Valid GPS**: $GPS_VALID ($GPS_VALID_PERCENT%)" >> "$REPORT_FILE"
    echo "- **Invalid GPS**: $GPS_INVALID ($GPS_INVALID_PERCENT%)" >> "$REPORT_FILE"
fi

# GPS satellite statistics
GPS_MIN=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | head -1)
GPS_MAX=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | tail -1)
GPS_UNIQUE=$(grep -o 'sats=[0-9]*' "$LOG_FILE" | sed 's/sats=//' | sort -n | uniq | wc -l | tr -d ' \n\r')

cat >> "$REPORT_FILE" << EOF

### GPS Satellite Statistics
- **Range**: $GPS_MIN to $GPS_MAX satellites
- **Unique values**: $GPS_UNIQUE different counts

EOF

# 4. SNR DETAILED ANALYSIS
log_step "Analyzing SNR and signal quality indicators"

cat >> "$REPORT_FILE" << 'EOF'
## 4. Signal Quality Analysis

### SNR (Signal-to-Noise Ratio)
EOF

# SNR analysis with quality indicators
SNR_POOR=$(grep "SNR:.*poor: [1-9]" "$LOG_FILE" | wc -l | tr -d ' \n\r')
SNR_GOOD=$(grep "SNR:.*poor: 0" "$LOG_FILE" | wc -l | tr -d ' \n\r')
SNR_ABOVE_NOISE_TRUE=$(grep "above_noise: true" "$LOG_FILE" | wc -l | tr -d ' \n\r')
SNR_ABOVE_NOISE_FALSE=$(grep "above_noise: false" "$LOG_FILE" | wc -l | tr -d ' \n\r')
SNR_PERSISTENTLY_LOW_TRUE=$(grep "persistently_low: true" "$LOG_FILE" | wc -l | tr -d ' \n\r')
SNR_PERSISTENTLY_LOW_FALSE=$(grep "persistently_low: false" "$LOG_FILE" | wc -l | tr -d ' \n\r')

printf "- **SNR Poor conditions**: %s events\n" "$SNR_POOR" >> "$REPORT_FILE"
printf "- **SNR Good conditions**: %s events\n" "$SNR_GOOD" >> "$REPORT_FILE"
printf "- **Above noise floor**: %s times\n" "$SNR_ABOVE_NOISE_TRUE" >> "$REPORT_FILE"
printf "- **Below noise floor**: %s times\n" "$SNR_ABOVE_NOISE_FALSE" >> "$REPORT_FILE"  
printf "- **Persistently low SNR**: %s times\n" "$SNR_PERSISTENTLY_LOW_TRUE" >> "$REPORT_FILE"
printf "- **SNR not persistently low**: %s times\n" "$SNR_PERSISTENTLY_LOW_FALSE" >> "$REPORT_FILE"

# 5. THRESHOLD BREACH ANALYSIS
log_step "Analyzing threshold breach patterns"

cat >> "$REPORT_FILE" << 'EOF'

## 5. Threshold Breach Analysis

### High Flag Occurrences
EOF

# Count threshold breaches
HIGH_LOSS=$(grep "Loss:.*high: [1-9]" "$LOG_FILE" | wc -l | tr -d ' \n\r')
HIGH_OBSTRUCTION=$(grep "Obstruction:.*high: [1-9]" "$LOG_FILE" | wc -l | tr -d ' \n\r')
HIGH_LATENCY=$(grep "Latency:.*high: [1-9]" "$LOG_FILE" | wc -l | tr -d ' \n\r')

printf "- **High packet loss flags**: %s events\n" "$HIGH_LOSS" >> "$REPORT_FILE"
printf "- **High obstruction flags**: %s events\n" "$HIGH_OBSTRUCTION" >> "$REPORT_FILE"
printf "- **High latency flags**: %s events\n" "$HIGH_LATENCY" >> "$REPORT_FILE"

# 6. MONITORING FREQUENCY ANALYSIS
log_step "Analyzing monitoring frequency and gaps"

cat >> "$REPORT_FILE" << 'EOF'

## 6. Monitoring Frequency Analysis

### Check Frequency
EOF

# Monitoring frequency
MONITOR_STARTS=$(grep "Starting Starlink monitor check" "$LOG_FILE" | wc -l | tr -d ' \n\r')
MONITOR_COMPLETED=$(grep "Monitor check completed" "$LOG_FILE" | wc -l | tr -d ' \n\r')
MONITOR_STOPPED=$(grep "Monitor stopped" "$LOG_FILE" | wc -l | tr -d ' \n\r')

printf "- **Monitor starts**: %s\n" "$MONITOR_STARTS" >> "$REPORT_FILE"
printf "- **Monitor completions**: %s\n" "$MONITOR_COMPLETED" >> "$REPORT_FILE"
printf "- **Monitor stops**: %s\n" "$MONITOR_STOPPED" >> "$REPORT_FILE"

# Calculate average interval
FIRST_TIME=$(head -1 "$LOG_FILE" | cut -d' ' -f1-2)
LAST_TIME=$(tail -1 "$LOG_FILE" | cut -d' ' -f1-2)

cat >> "$REPORT_FILE" << EOF
- **First entry**: $FIRST_TIME
- **Last entry**: $LAST_TIME
- **Average check interval**: ~$(( 1440 / MONITOR_STARTS )) minutes

EOF

# 7. QUALITY INDICATORS SUMMARY
log_step "Generating quality indicators summary"

cat >> "$REPORT_FILE" << 'EOF'
## 7. Quality Assessment Summary

### Data Completeness
EOF

# Calculate data quality metrics
TOTAL_LINES=$(wc -l < "$LOG_FILE" | tr -d ' \n\r')
BASIC_METRICS=$(grep "Basic Metrics" "$LOG_FILE" | wc -l | tr -d ' \n\r')
ENHANCED_METRICS=$(grep "Enhanced Metrics" "$LOG_FILE" | wc -l | tr -d ' \n\r')
API_ERRORS=$(grep -i "error\|failed\|timeout" "$LOG_FILE" | wc -l | tr -d ' \n\r')

printf "- **Total log lines**: %s\n" "$TOTAL_LINES" >> "$REPORT_FILE"
printf "- **Basic metrics entries**: %s\n" "$BASIC_METRICS" >> "$REPORT_FILE"
printf "- **Enhanced metrics entries**: %s\n" "$ENHANCED_METRICS" >> "$REPORT_FILE"
printf "- **API errors/failures**: %s\n" "$API_ERRORS" >> "$REPORT_FILE"

# Data coverage percentage
if [ "$MONITOR_STARTS" -gt 0 ]; then
    BASIC_COVERAGE=$(( (BASIC_METRICS * 100) / MONITOR_STARTS ))
    ENHANCED_COVERAGE=$(( (ENHANCED_METRICS * 100) / MONITOR_STARTS ))
    
    printf "- **Basic metrics coverage**: %s%%%%\n" "$BASIC_COVERAGE" >> "$REPORT_FILE"
    printf "- **Enhanced metrics coverage**: %s%%%%\n" "$ENHANCED_COVERAGE" >> "$REPORT_FILE"
fi

# 8. OPERATIONAL INSIGHTS
log_step "Generating operational insights"

cat >> "$REPORT_FILE" << 'EOF'

## 8. Operational Insights

### System Reliability
EOF

# Calculate uptime percentage
if [ "$TOTAL_STATES" -gt 0 ]; then
    UPTIME_PERCENT=$(( (STATE_UP * 100) / TOTAL_STATES ))
    printf "- **System uptime**: %s%%%% (%s up / %s total states)\n" "$UPTIME_PERCENT" "$STATE_UP" "$TOTAL_STATES" >> "$REPORT_FILE"
else
    UPTIME_PERCENT=0
fi

# Calculate failure rate
if [ "$MONITOR_STARTS" -gt 0 ]; then
    FAILURE_RATE=$(( (API_ERRORS * 100) / MONITOR_STARTS ))
    printf "- **API failure rate**: %s%%%% (%s errors / %s checks)\n" "$FAILURE_RATE" "$API_ERRORS" "$MONITOR_STARTS" >> "$REPORT_FILE"
else
    FAILURE_RATE=0
fi

# 9. ADDITIONAL METRICS DISCOVERED
log_step "Searching for additional undocumented metrics"

cat >> "$REPORT_FILE" << 'EOF'

## 9. Additional Metrics Available

### Newly Discovered Data Points
EOF

# Search for other potential metrics
UNKNOWN_METRICS=$(grep -E 'debug|info' "$LOG_FILE" | grep -E '[A-Za-z]+:.*[0-9]' | sed 's/.*\[\(debug\|info\)\] //' | sort | uniq -c | sort -nr | head -10)

printf "Top metric patterns found:\n\`\`\`\n%s\n\`\`\`\n\n" "$UNKNOWN_METRICS" >> "$REPORT_FILE"

# Conclusion
cat >> "$REPORT_FILE" << 'EOF'
## Conclusion

### Available Data Summary
This analysis reveals significantly more data points than initially assessed:

1. **System State Tracking**: Connection up/down status with routing metrics
2. **Stability Counters**: Progressive stability tracking for failback decisions  
3. **Enhanced GPS Data**: Validity status beyond just satellite counts
4. **Signal Quality Flags**: Multiple SNR quality indicators (poor, above_noise, persistently_low)
5. **Threshold Breach Flags**: Real-time high flags for each metric
6. **Monitoring Health**: API success/failure tracking and frequency analysis

### Recommendations for Enhanced Analytics
1. **Trend Analysis**: Use stability counters to predict connection quality trends
2. **Failure Prediction**: Correlate SNR flags with upcoming connection issues
3. **Performance Optimization**: Analyze monitoring frequency vs. detection accuracy
4. **Quality Scoring**: Combine multiple quality indicators for comprehensive scoring
5. **Predictive Maintenance**: Use GPS validity and SNR trends for proactive alerts

EOF

log_success "Comprehensive analysis completed"
log_info "Report saved to: $REPORT_FILE"

printf "\n${GREEN}📊 ANALYSIS SUMMARY${NC}\n"
printf "System States: %s up, %s down (%s%%%% uptime)\n" "$STATE_UP" "$STATE_DOWN" "$UPTIME_PERCENT"
printf "GPS Status: %s valid, %s invalid readings\n" "$GPS_VALID" "$GPS_INVALID"
printf "Monitoring: %s checks with %s API errors (%s%%%% failure rate)\n" "$MONITOR_STARTS" "$API_ERRORS" "$FAILURE_RATE"
printf "Report: %s\n" "$REPORT_FILE"
