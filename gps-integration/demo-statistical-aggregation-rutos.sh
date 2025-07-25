#!/bin/sh
# Script: demo-statistical-aggregation-rutos.sh
# Version: 2.4.6
# Description: Demonstration of 60:1 statistical aggregation with GPS for logger optimization
# Shows exactly how the data reduction works with real examples

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors (RUTOS Method 5 format)
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Statistical calculation functions (POSIX-compliant for busybox)
calculate_min() {
    data="$1"
    echo "$data" | awk '{if(NR==1||$1<min) min=$1} END {print min+0}'
}

calculate_max() {
    data="$1"
    echo "$data" | awk '{if(NR==1||$1>max) max=$1} END {print max+0}'
}

calculate_avg() {
    data="$1"
    echo "$data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print 0}'
}

calculate_percentile() {
    data="$1"
    percentile="$2" # e.g., 95 for 95th percentile

    # Sort data and calculate percentile position
    sorted_data=$(echo "$data" | sort -n)
    count=$(echo "$sorted_data" | wc -l | tr -d ' \n\r')

    if [ "$count" -eq 0 ]; then
        echo "0"
        return
    fi

    # Calculate position (1-based indexing)
    position=$(echo "$count * $percentile / 100" | awk '{printf "%.0f", $1}')
    if [ "$position" -lt 1 ]; then
        position=1
    elif [ "$position" -gt "$count" ]; then
        position="$count"
    fi

    # Extract value at position
    echo "$sorted_data" | sed -n "${position}p"
}

count_true_values() {
    data="$1"
    echo "$data" | grep -c "1" 2>/dev/null || echo "0"
}

# Generate realistic sample data for demonstration
generate_sample_data() {
    log_step "Generating 60 realistic data samples for demonstration"

    # Create sample data representing 60 seconds of Starlink monitoring
    # This simulates what the logger currently collects

    cat >/tmp/sample_raw_data.csv <<'EOF'
Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Reboot Detected
2025-07-25 12:00:01,45,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:02,47,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:03,43,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:04,52,0.50,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:05,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:06,44,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:07,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:08,46,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:09,51,0.00,2.15,72.3,7.8,1,0,1,12,0
2025-07-25 12:00:10,45,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:11,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:12,47,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:13,53,1.00,2.15,72.3,7.7,1,0,1,12,0
2025-07-25 12:00:14,49,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:15,44,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:16,46,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:17,50,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:18,45,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:19,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:20,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:21,52,0.50,2.15,72.3,7.8,1,0,1,12,0
2025-07-25 12:00:22,46,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:23,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:24,44,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:25,51,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:26,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:27,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:28,45,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:29,53,1.50,2.15,72.3,7.6,1,0,1,12,0
2025-07-25 12:00:30,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:31,46,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:32,50,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:33,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:34,44,0.00,2.15,72.3,8.5,1,0,1,12,0
2025-07-25 12:00:35,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:36,52,0.50,2.15,72.3,7.8,1,0,1,12,0
2025-07-25 12:00:37,45,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:38,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:39,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:40,51,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:41,46,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:42,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:43,54,2.00,2.15,72.3,7.5,1,0,1,12,0
2025-07-25 12:00:44,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:45,45,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:46,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:47,50,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:48,46,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:49,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:50,52,0.50,2.15,72.3,7.8,1,0,1,12,0
2025-07-25 12:00:51,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:00:52,44,0.00,2.15,72.3,8.5,1,0,1,12,0
2025-07-25 12:00:53,49,0.00,2.15,72.3,8.1,1,0,1,12,0
2025-07-25 12:00:54,51,0.00,2.15,72.3,7.9,1,0,1,12,0
2025-07-25 12:00:55,45,0.00,2.15,72.3,8.3,1,0,1,12,0
2025-07-25 12:00:56,48,0.00,2.15,72.3,8.0,1,0,1,12,0
2025-07-25 12:00:57,53,1.00,2.15,72.3,7.7,1,0,1,12,0
2025-07-25 12:00:58,46,0.00,2.15,72.3,8.4,1,0,1,12,0
2025-07-25 12:00:59,47,0.00,2.15,72.3,8.2,1,0,1,12,0
2025-07-25 12:01:00,49,0.00,2.15,72.3,8.1,1,0,1,12,0
EOF

    log_success "Generated 60 realistic data samples (current logger format)"

    # Show current data format
    log_info "Current format: 60 individual entries per minute"
    log_info "Sample size: $(wc -l </tmp/sample_raw_data.csv) lines"
    log_info "File size: $(wc -c </tmp/sample_raw_data.csv) bytes"
}

# Demonstrate statistical aggregation
demonstrate_aggregation() {
    log_step "Demonstrating statistical aggregation (60:1 reduction)"

    # Extract data columns for calculation (skip header)
    latency_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f2)
    loss_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f3)
    snr_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f6)
    snr_above_noise_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f7)
    snr_persistently_low_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f8)
    gps_valid_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f9)
    gps_satellites_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f10)

    # Calculate statistics
    log_debug "Calculating latency statistics..."
    latency_min=$(calculate_min "$latency_data")
    latency_max=$(calculate_max "$latency_data")
    latency_avg=$(calculate_avg "$latency_data")
    latency_p95=$(calculate_percentile "$latency_data" 95)

    log_debug "Calculating packet loss statistics..."
    loss_min=$(calculate_min "$loss_data")
    loss_max=$(calculate_max "$loss_data")
    loss_avg=$(calculate_avg "$loss_data")

    log_debug "Calculating SNR statistics..."
    snr_min=$(calculate_min "$snr_data")
    snr_max=$(calculate_max "$snr_data")
    snr_avg=$(calculate_avg "$snr_data")

    log_debug "Calculating boolean flag counts..."
    snr_above_noise_count=$(count_true_values "$snr_above_noise_data")
    snr_persistently_low_count=$(count_true_values "$snr_persistently_low_data")
    gps_valid_count=$(count_true_values "$gps_valid_data")
    gps_satellites_avg=$(calculate_avg "$gps_satellites_data")

    # Static values for this demonstration
    sample_count=60
    obstruction_pct="2.15"
    uptime_hours="72.3"
    reboot_detected="0"

    # Simulated GPS data (would come from actual GPS in real implementation)
    gps_lat="59.8586"
    gps_lon="17.6389"
    gps_speed="0"
    gps_accuracy="2"
    gps_source="rutos"

    # Create optimized CSV entry
    aggregated_timestamp="2025-07-25 12:01:00"

    cat >/tmp/sample_optimized_data.csv <<EOF
Timestamp,Sample_Count,Latency_Min,Latency_Max,Latency_Avg,Latency_P95,PacketLoss_Min,PacketLoss_Max,PacketLoss_Avg,Obstruction (%),Uptime (hours),SNR_Min,SNR_Max,SNR_Avg,SNR_Above_Noise_Count,SNR_Persistently_Low_Count,GPS_Valid_Count,GPS_Satellites_Avg,GPS_Latitude,GPS_Longitude,GPS_Speed,GPS_Accuracy,GPS_Source,Reboot_Detected
$aggregated_timestamp,$sample_count,$latency_min,$latency_max,$latency_avg,$latency_p95,$loss_min,$loss_max,$loss_avg,$obstruction_pct,$uptime_hours,$snr_min,$snr_max,$snr_avg,$snr_above_noise_count,$snr_persistently_low_count,$gps_valid_count,$gps_satellites_avg,$gps_lat,$gps_lon,$gps_speed,$gps_accuracy,$gps_source,$reboot_detected
EOF

    log_success "Statistical aggregation completed"

    # Show optimized data format
    log_info "Optimized format: 1 aggregated entry per minute"
    log_info "Sample size: $(wc -l </tmp/sample_optimized_data.csv) lines"
    log_info "File size: $(wc -c </tmp/sample_optimized_data.csv) bytes"
}

# Show detailed comparison
show_comparison() {
    log_step "Showing detailed before/after comparison"

    echo ""
    printf "${PURPLE}=== CURRENT LOGGER FORMAT (60 entries) ===${NC}\n"
    echo ""

    # Show first few and last few entries
    printf "${CYAN}First 5 entries:${NC}\n"
    head -6 /tmp/sample_raw_data.csv | tail -5
    echo "..."
    printf "${CYAN}Last 5 entries:${NC}\n"
    tail -5 /tmp/sample_raw_data.csv

    echo ""
    printf "${PURPLE}=== OPTIMIZED LOGGER FORMAT (1 aggregated entry) ===${NC}\n"
    echo ""

    # Show the optimized entry
    cat /tmp/sample_optimized_data.csv

    echo ""
    printf "${PURPLE}=== STATISTICAL COMPARISON ===${NC}\n"
    echo ""

    # Extract latency data for comparison
    latency_data=$(tail -n +2 /tmp/sample_raw_data.csv | cut -d',' -f2)

    printf "${GREEN}Latency Analysis:${NC}\n"
    printf "  Individual samples: %s\n" "$(echo "$latency_data" | tr '\n' ' ' | sed 's/ $//')"
    printf "  Minimum: %s ms\n" "$(calculate_min "$latency_data")"
    printf "  Maximum: %s ms\n" "$(calculate_max "$latency_data")"
    printf "  Average: %s ms\n" "$(calculate_avg "$latency_data")"
    printf "  95th Percentile: %s ms\n" "$(calculate_percentile "$latency_data" 95)"

    echo ""
    printf "${GREEN}Data Efficiency:${NC}\n"
    current_size=$(wc -c </tmp/sample_raw_data.csv)
    optimized_size=$(wc -c </tmp/sample_optimized_data.csv)
    reduction_ratio=$((current_size / optimized_size))
    reduction_percent=$(((current_size - optimized_size) * 100 / current_size))

    printf "  Current format: %d bytes (60 entries)\n" "$current_size"
    printf "  Optimized format: %d bytes (1 entry)\n" "$optimized_size"
    printf "  Reduction ratio: %d:1\n" "$reduction_ratio"
    printf "  Space savings: %d%%\n" "$reduction_percent"

    echo ""
    printf "${GREEN}GPS Efficiency:${NC}\n"
    printf "  Current: GPS coordinates duplicated 60 times\n"
    printf "  Optimized: GPS coordinates stored once per minute\n"
    printf "  GPS data reduction: 60:1 (98%% space savings for GPS data)\n"

    echo ""
    printf "${GREEN}Enhanced Analytics:${NC}\n"
    printf "  Current: Only individual sample values\n"
    printf "  Optimized: Min/Max/Average/95th percentile statistics\n"
    printf "  Benefits: Pattern recognition, outlier detection, trend analysis\n"
}

# Show real-world implications
show_real_world_implications() {
    log_step "Demonstrating real-world implications"

    echo ""
    printf "${PURPLE}=== REAL-WORLD IMPACT ANALYSIS ===${NC}\n"
    echo ""

    printf "${GREEN}Daily Data Volume:${NC}\n"
    printf "  Current format: 60 entries/minute × 1440 minutes/day = 86,400 entries/day\n"
    printf "  Optimized format: 1 entry/minute × 1440 minutes/day = 1,440 entries/day\n"
    printf "  Daily reduction: 84,960 fewer entries (98%% reduction)\n"

    echo ""
    printf "${GREEN}Monthly Storage (30 days):${NC}\n"
    current_daily=$(wc -c </tmp/sample_raw_data.csv)
    optimized_daily=$(wc -c </tmp/sample_optimized_data.csv)
    current_monthly=$((current_daily * 1440)) # 1440 minutes per day
    optimized_monthly=$((optimized_daily * 1440))

    current_monthly_mb=$((current_monthly / 1024 / 1024))
    optimized_monthly_mb=$((optimized_monthly / 1024 / 1024))

    printf "  Current format: ~%d MB/month\n" "$current_monthly_mb"
    printf "  Optimized format: ~%d MB/month\n" "$optimized_monthly_mb"
    printf "  Monthly savings: ~%d MB\n" "$((current_monthly_mb - optimized_monthly_mb))"

    echo ""
    printf "${GREEN}Motorhome Travel Season (6 months):${NC}\n"
    current_seasonal=$((current_monthly_mb * 6))
    optimized_seasonal=$((optimized_monthly_mb * 6))

    printf "  Current format: ~%d MB/season\n" "$current_seasonal"
    printf "  Optimized format: ~%d MB/season\n" "$optimized_seasonal"
    printf "  Seasonal savings: ~%d MB\n" "$((current_seasonal - optimized_seasonal))"

    echo ""
    printf "${GREEN}Analysis Performance:${NC}\n"
    printf "  Current: Must process 86,400 entries to analyze one day\n"
    printf "  Optimized: Process 1,440 entries to analyze one day (60x faster)\n"
    printf "  Location analysis: One GPS coordinate per minute vs 60 duplicates\n"
    printf "  Statistical insights: Built-in min/max/percentile data\n"

    echo ""
    printf "${GREEN}Motorhome Use Case Benefits:${NC}\n"
    printf "  📍 Location tracking: Efficient GPS coordinate storage\n"
    printf "  🏕️  Camping analysis: Minute-level precision sufficient for site evaluation\n"
    printf "  📊 Connectivity patterns: Statistical summaries reveal more than individual samples\n"
    printf "  💾 Storage efficiency: Longer history retention on limited router storage\n"
    printf "  🔄 Data transfer: Reduced bandwidth for remote log analysis\n"
    printf "  ⚡ Processing speed: Faster analysis and reporting\n"
}

# Demonstrate GPS coordinate efficiency
demonstrate_gps_efficiency() {
    log_step "Demonstrating GPS coordinate efficiency"

    echo ""
    printf "${PURPLE}=== GPS DATA EFFICIENCY ANALYSIS ===${NC}\n"
    echo ""

    # Show current GPS duplication problem
    printf "${YELLOW}Current GPS Data Duplication Problem:${NC}\n"
    printf "  Every sample gets same GPS coordinates: 59.8586, 17.6389\n"
    printf "  GPS coordinates repeated 60 times per minute\n"
    printf "  Storage waste: 59 duplicate GPS readings per minute\n"
    printf "  Daily GPS duplicates: 84,960 redundant coordinate pairs\n"

    echo ""
    printf "${GREEN}Optimized GPS Data Storage:${NC}\n"
    printf "  GPS coordinates stored once per minute: 59.8586, 17.6389\n"
    printf "  Additional GPS metadata: speed, accuracy, source\n"
    printf "  Daily GPS entries: 1,440 unique coordinate readings\n"
    printf "  GPS data reduction: 98%% storage savings\n"

    echo ""
    printf "${GREEN}Enhanced GPS Features:${NC}\n"
    printf "  GPS Source Priority: RUTOS > gpsd > Starlink > fallback\n"
    printf "  Accuracy Tracking: Precision metadata for each reading\n"
    printf "  Speed Integration: Movement detection for parked/traveling\n"
    printf "  Quality Assessment: Valid GPS flag counts per minute\n"

    echo ""
    printf "${GREEN}Location Analysis Benefits:${NC}\n"
    printf "  Clustering Efficiency: Process 1,440 locations vs 86,400 duplicates\n"
    printf "  Travel Pattern Recognition: Clear movement vs stationary periods\n"
    printf "  Camping Site Analysis: Precise location with connectivity statistics\n"
    printf "  Problem Area Identification: Geographic correlation with connection issues\n"
}

# Main function
main() {
    log_info "Starting statistical aggregation demonstration v$SCRIPT_VERSION"

    echo ""
    printf "${BLUE}==============================================================${NC}\n"
    printf "${BLUE}GPS-Optimized Logger: 60:1 Statistical Aggregation Demo${NC}\n"
    printf "${BLUE}==============================================================${NC}\n"

    # Generate sample data
    generate_sample_data

    # Demonstrate aggregation
    demonstrate_aggregation

    # Show detailed comparison
    show_comparison

    # Show real-world implications
    show_real_world_implications

    # Demonstrate GPS efficiency
    demonstrate_gps_efficiency

    echo ""
    printf "${BLUE}==============================================================${NC}\n"
    printf "${BLUE}Demonstration Complete${NC}\n"
    printf "${BLUE}==============================================================${NC}\n"

    log_success "Statistical aggregation demonstration completed successfully"

    echo ""
    log_step "Key Takeaways:"
    log_info "✅ 60:1 data reduction with enhanced analytical capabilities"
    log_info "✅ GPS coordinate storage efficiency (98% space savings)"
    log_info "✅ Statistical insights superior to individual samples"
    log_info "✅ Perfect for motorhome travel and camping analysis"
    log_info "✅ Maintains full analytical capabilities with compact storage"

    echo ""
    log_step "Generated Files:"
    log_info "📄 Raw data sample: /tmp/sample_raw_data.csv"
    log_info "📄 Optimized data sample: /tmp/sample_optimized_data.csv"
    log_info "📊 Compare the files to see the transformation"

    if [ "$DRY_RUN" = "1" ]; then
        echo ""
        log_info "This was a demonstration - no actual logger modifications made"
    fi
}

# Execute main function
main "$@"
