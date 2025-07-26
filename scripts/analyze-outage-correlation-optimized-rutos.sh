#!/bin/sh
# Script: analyze-outage-correlation-optimized-rutos.sh
# Version: 2.7.0
# Description: Optimized outage correlation analysis for RUTOS monitoring logs

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Color definitions (busybox compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# RUTOS test mode support (for testing framework)
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Standard logging functions
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
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Default configuration
ANALYSIS_DATE="$(date '+%Y-%m-%d')"
LOG_DIR="/etc/starlink-logs"
REPORT_FILE="/tmp/outage_analysis_optimized_$(date '+%Y%m%d_%H%M%S').txt"
DEBUG="${DEBUG:-0}"

# Known outages from Starlink app (July 24, 2025)
# Format: "HH:MM TYPE DURATION_SECONDS DESCRIPTION"
KNOWN_OUTAGES="
13:43 Obstructed 12 Obstructed+1
13:42 NoSignal 6 No_signal_received
13:33 Obstructed 6 Obstructed+1
13:23 Obstructed 14 Obstructed+1
13:22 Obstructed 9 Obstructed+1
13:18 Obstructed 7 Obstructed
13:17 Obstructed 13 Obstructed
13:11 Obstructed 7 Obstructed
13:10 Obstructed 10 Obstructed+1
13:03 Obstructed 6 Obstructed+1
13:02 Obstructed 8 Obstructed+1
13:02 Obstructed 18 Obstructed+1
13:02 Obstructed 7 Obstructed
13:01 Obstructed 7 Obstructed
12:58 Searching 22 Searching+2
12:57 Obstructed 10 Obstructed
"

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --date)
                ANALYSIS_DATE="$2"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --report-file)
                REPORT_FILE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    printf "${GREEN}Starlink Outage Correlation Analysis (Optimized) v%s${NC}\n\n" "$SCRIPT_VERSION"
    printf "Analyzes RUTOS monitoring logs and correlates with known outages.\n\n"
    printf "Usage: %s [options]\n\n" "$(basename "$0")"
    printf "Options:\n"
    printf "  --date YYYY-MM-DD     Analyze specific date (default: today)\n"
    printf "  --log-dir PATH        Custom log directory (default: /etc/starlink-logs)\n"
    printf "  --report-file PATH    Output report file\n"
    printf "  --debug               Enable debug output\n"
    printf "  --help                Show this help\n\n"
    printf "Examples:\n"
    printf "  %s --date 2025-07-24\n" "$(basename "$0")"
    printf "  %s --debug --report-file /tmp/analysis.txt\n" "$(basename "$0")"
}

# Convert time to seconds since midnight (with octal fix)
time_to_seconds() {
    time_str="$1"

    if [ -z "$time_str" ]; then
        log_debug "time_to_seconds: empty input"
        echo "0"
        return 1
    fi

    # Extract hour, minute, and seconds with proper field separation
    hour=$(echo "$time_str" | cut -d: -f1)
    minute=$(echo "$time_str" | cut -d: -f2)
    seconds=$(echo "$time_str" | cut -d: -f3)

    # Default seconds to 0 if not provided
    seconds="${seconds:-0}"

    # Convert to decimal to avoid octal interpretation
    hour=$(printf "%d" "$hour" 2>/dev/null || echo "0")
    minute=$(printf "%d" "$minute" 2>/dev/null || echo "0")
    seconds=$(printf "%d" "$seconds" 2>/dev/null || echo "0")

    log_debug "time_to_seconds: converting '$time_str' (hour='$hour', minute='$minute', seconds='$seconds')"

    # Calculate total seconds
    total_seconds=$((hour * 3600 + minute * 60 + seconds))
    echo "$total_seconds"
}

# Extract timestamp from log line
extract_log_timestamp() {
    log_line="$1"

    if [ -z "$log_line" ]; then
        echo ""
        return 1
    fi

    # Extract timestamp in format: 2025-07-24 13:43:12
    timestamp=$(echo "$log_line" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/p' 2>/dev/null)

    if [ -z "$timestamp" ]; then
        timestamp=$(echo "$log_line" | sed -n 's/^\([0-9-]* [0-9:]*\).*/\1/p' 2>/dev/null)
    fi

    echo "$timestamp"
}

# Convert log timestamp to seconds since midnight
log_timestamp_to_seconds() {
    timestamp="$1"

    if [ -z "$timestamp" ]; then
        echo "0"
        return 1
    fi

    # Extract time part from "YYYY-MM-DD HH:MM:SS"
    time_part=$(echo "$timestamp" | awk '{print $2}')
    time_to_seconds "$time_part"
}

# Validate environment
validate_environment() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"

    if [ ! -f "$log_file" ]; then
        log_error "Log file not found: $log_file"
        return 1
    fi

    log_debug "Using log file: $log_file"
    log_debug "Report will be written to: $REPORT_FILE"
    return 0
}

# OPTIMIZED: Pre-process and sort all log entries by timestamp
prepare_sorted_data() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    temp_sorted_events="/tmp/sorted_events_$$.txt"
    temp_sorted_metrics="/tmp/sorted_metrics_$$.txt"

    # NO LOGGING in this function - logging contaminates command substitution output

    # Extract and sort events with timestamps
    grep -E "(Quality degraded|Performing soft failover|Quality recovered|Soft failback|WARN|ERROR)" \
        "$log_file" 2>/dev/null | while read -r line; do
        timestamp=$(extract_log_timestamp "$line")
        if [ -n "$timestamp" ]; then
            seconds=$(log_timestamp_to_seconds "$timestamp")
            printf "%06d|%s\n" "$seconds" "$line"
        fi
    done | sort -n >"$temp_sorted_events"

    # Extract and sort metrics with timestamps
    grep -E "(Basic Metrics|Enhanced Metrics)" \
        "$log_file" 2>/dev/null | while read -r line; do
        timestamp=$(extract_log_timestamp "$line")
        if [ -n "$timestamp" ]; then
            seconds=$(log_timestamp_to_seconds "$timestamp")
            printf "%06d|%s\n" "$seconds" "$line"
        fi
    done | sort -n >"$temp_sorted_metrics"

    # Return only the file paths - NO LOGGING HERE
    echo "$temp_sorted_events|$temp_sorted_metrics"
}

# OPTIMIZED: Use binary search approach for time window matching
find_correlations_optimized() {
    outage_time="$1"
    outage_duration="$2"
    temp_sorted_events="$3"
    temp_sorted_metrics="$4"

    outage_seconds=$(time_to_seconds "$outage_time")
    start_window=$((outage_seconds - 60))
    end_window=$((outage_seconds + outage_duration + 60))

    log_debug "Searching for correlations in window: $start_window - $end_window seconds"

    # Find events in time window (much faster with sorted data)
    correlated_events=$(awk -F'|' -v start="$start_window" -v end="$end_window" \
        '$1 >= start && $1 <= end { print $2 }' "$temp_sorted_events")

    # Find metrics in time window
    correlated_metrics=$(awk -F'|' -v start="$start_window" -v end="$end_window" \
        '$1 >= start && $1 <= end { print $2 }' "$temp_sorted_metrics")

    # Count correlations (clean whitespace to avoid arithmetic errors)
    event_count=$(echo "$correlated_events" | grep -c . 2>/dev/null | tr -d ' \n\r' || echo "0")
    metric_count=$(echo "$correlated_metrics" | grep -c . 2>/dev/null | tr -d ' \n\r' || echo "0")

    # Check for failovers (clean whitespace)
    failover_count=$(echo "$correlated_events" | grep -c "Performing soft failover" 2>/dev/null | tr -d ' \n\r' || echo "0")

    log_debug "Found $event_count events, $metric_count metrics, $failover_count failovers in window"

    # Write detailed results to temp files for retrieval
    echo "$correlated_events" >"/tmp/temp_events_$$"
    echo "$correlated_metrics" >"/tmp/temp_metrics_$$"

    # Return only counts in simple format
    echo "$event_count~$failover_count"
}

# OPTIMIZED: Main analysis function
analyze_outage_correlation_optimized() {
    log_step "Running optimized outage correlation analysis"

    # Prepare sorted data once
    log_step "Pre-processing and sorting log data for efficient analysis"
    sorted_data=$(prepare_sorted_data)
    temp_sorted_events=$(echo "$sorted_data" | cut -d'|' -f1)
    temp_sorted_metrics=$(echo "$sorted_data" | cut -d'|' -f2)

    # Log the data preparation results
    event_count=$(wc -l <"$temp_sorted_events" | tr -d ' ')
    metric_count=$(wc -l <"$temp_sorted_metrics" | tr -d ' ')
    log_debug "Sorted $event_count events and $metric_count metrics by timestamp"

    temp_outages="/tmp/known_outages_$$.txt"
    echo "$KNOWN_OUTAGES" >"$temp_outages"

    # Initialize report
    {
        printf "\n=== OPTIMIZED OUTAGE CORRELATION ANALYSIS ===\n"
        printf "Analysis Date: %s\n" "$ANALYSIS_DATE"
        printf "Generated: %s\n\n" "$(date)"
    } >>"$REPORT_FILE"

    total_outages=0
    total_correlated=0
    total_failovers=0

    log_step "Processing known outages efficiently"

    # Process each outage efficiently
    while read -r outage_line; do
        [ -z "$outage_line" ] && continue

        outage_time=$(echo "$outage_line" | awk '{print $1}')
        outage_type=$(echo "$outage_line" | awk '{print $2}')
        outage_duration=$(echo "$outage_line" | awk '{print $3}')
        outage_desc=$(echo "$outage_line" | awk '{print $4}')

        [ -z "$outage_time" ] && continue

        total_outages=$((total_outages + 1))

        log_debug "Processing outage #$total_outages: $outage_time ($outage_type)"

        # Find correlations efficiently
        results=$(find_correlations_optimized "$outage_time" "$outage_duration" "$temp_sorted_events" "$temp_sorted_metrics")

        # Parse results (now just counts)
        event_count=$(echo "$results" | cut -d'~' -f1 | tr -d ' \n\r')
        failover_count=$(echo "$results" | cut -d'~' -f2 | tr -d ' \n\r')

        log_debug "Parsed event_count: '$event_count'"
        log_debug "Parsed failover_count: '$failover_count'"

        # Read detailed results from temp files
        if [ -f "/tmp/temp_events_$$" ]; then
            correlated_events=$(cat "/tmp/temp_events_$$")
            rm -f "/tmp/temp_events_$$"
        else
            correlated_events=""
        fi

        if [ -f "/tmp/temp_metrics_$$" ]; then
            correlated_metrics=$(cat "/tmp/temp_metrics_$$")
            rm -f "/tmp/temp_metrics_$$"
        else
            correlated_metrics=""
        fi

        # Ensure numeric values are valid (set to 0 if empty or invalid)
        [ -z "$event_count" ] && event_count=0
        [ -z "$failover_count" ] && failover_count=0

        total_correlated=$((total_correlated + event_count))
        total_failovers=$((total_failovers + failover_count))

        # Write results to report
        {
            printf "\n--- OUTAGE #%d: %s (%s) ---\n" "$total_outages" "$outage_time" "$outage_type"
            printf "Duration: %ds, Type: %s, Description: %s\n" "$outage_duration" "$outage_type" "$outage_desc"

            if [ "$event_count" -gt 0 ]; then
                printf "\n✓ FOUND %d CORRELATED EVENTS:\n" "$event_count"
                echo "$correlated_events"
            else
                printf "\n✗ NO CORRELATED EVENTS FOUND\n"
            fi

            if echo "$correlated_metrics" | grep -q .; then
                printf "\n📊 CORRELATED METRICS FOUND\n"
            else
                printf "\n📊 NO METRIC DATA AVAILABLE\n"
            fi
        } >>"$REPORT_FILE"

    done <"$temp_outages"

    # Generate summary
    {
        printf "\n\n=== ANALYSIS SUMMARY ===\n"
        printf "Total Known Outages: %d\n" "$total_outages"
        printf "Total Correlated Events: %d\n" "$total_correlated"
        printf "Total Failover Events: %d\n" "$total_failovers"
        printf "Correlation Rate: %.1f%%\n" "$((total_outages > 0 ? (total_correlated * 100) / total_outages : 0))"
    } >>"$REPORT_FILE"

    # Cleanup
    rm -f "$temp_sorted_events" "$temp_sorted_metrics" "$temp_outages"

    log_debug "Analysis completed: $total_outages outages, $total_correlated correlations, $total_failovers failovers"
}

# Main execution
main() {
    log_info "Starting Optimized Starlink Outage Correlation Analysis v$SCRIPT_VERSION"

    # Parse command line arguments
    parse_arguments "$@"

    if [ "$DEBUG" = "1" ]; then
        log_debug "==================== DEBUG MODE ENABLED ===================="
        log_debug "Analysis date: $ANALYSIS_DATE"
        log_debug "Log directory: $LOG_DIR"
        log_debug "Report file: $REPORT_FILE"
        log_debug "=============================================================="
    fi

    # Initialize report file
    printf "OPTIMIZED STARLINK OUTAGE CORRELATION ANALYSIS REPORT\n" >"$REPORT_FILE"
    printf "Generated by: %s v%s\n" "$(basename "$0")" "$SCRIPT_VERSION" >>"$REPORT_FILE"
    printf "=====================================================\n" >>"$REPORT_FILE"

    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi

    # Run optimized analysis
    analyze_outage_correlation_optimized

    log_info "Optimized analysis completed successfully!"
    log_info "Report file: $REPORT_FILE"
}

# Execute main function
main "$@"
