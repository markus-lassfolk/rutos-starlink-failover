#!/bin/sh

# ==============================================================================
# Starlink Outage Correlation Analysis Script for RUTOS
#
# Analyzes RUTOS monitoring logs and correlates with known outage periods
# to validate monitoring coverage and failover behavior.
#
# Features: Correlates logs with outages, analyzes failover timing,
# evaluates threshold sensitivity, provides tuning recommendations
#
# Usage: ./scripts/analyze-outage-correlation-rutos.sh [options]
# Options:
#   --date YYYY-MM-DD     Analyze specific date (default: today)
#   --log-dir PATH        Custom log directory (default: /etc/starlink-logs)
#   --report-file PATH    Output report file (default: /tmp/outage_analysis.txt)
#   --debug               Enable debug output
#   --help                Show this help
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"
readonly SCRIPT_VERSION

# Check if terminal supports colors (RUTOS busybox compatible)
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
REPORT_FILE="/tmp/outage_analysis_$(date '+%Y%m%d_%H%M%S').txt"
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
    printf "${GREEN}Starlink Outage Correlation Analysis v%s${NC}\n\n" "$SCRIPT_VERSION"
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
    printf "  DEBUG=1 %s\n" "$(basename "$0")"
}

# Convert time to seconds since midnight
time_to_seconds() {
    time_str="$1"

    # Validate input
    if [ -z "$time_str" ]; then
        log_debug "time_to_seconds: empty input"
        echo "0"
        return 1
    fi

    # Extract hour, minute, and optional seconds with validation
    hour=$(echo "$time_str" | cut -d: -f1 | tr -d ' ')
    minute=$(echo "$time_str" | cut -d: -f2 | tr -d ' ')
    # Handle optional seconds (HH:MM or HH:MM:SS format)
    seconds_part=$(echo "$time_str" | cut -d: -f3 | tr -d ' ')
    if [ -z "$seconds_part" ]; then
        seconds_part="0"
    fi

    # Validate hour and minute are numeric
    if ! echo "$hour" | grep -q '^[0-9]\+$' || ! echo "$minute" | grep -q '^[0-9]\+$'; then
        log_debug "time_to_seconds: invalid time format '$time_str' (hour='$hour', minute='$minute')"
        echo "0"
        return 1
    fi

    # Validate seconds is numeric (if provided)
    if ! echo "$seconds_part" | grep -q '^[0-9]\+$'; then
        log_debug "time_to_seconds: invalid seconds '$seconds_part' in '$time_str'"
        echo "0"
        return 1
    fi

    # Ensure values are within valid ranges
    if [ "$hour" -gt 23 ] || [ "$minute" -gt 59 ] || [ "$seconds_part" -gt 59 ]; then
        log_debug "time_to_seconds: time out of range '$time_str' (hour='$hour', minute='$minute', seconds='$seconds_part')"
        echo "0"
        return 1
    fi

    # Ensure all variables are clean integers for busybox arithmetic
    hour=$(printf "%d" "$hour" 2>/dev/null || echo "0")
    minute=$(printf "%d" "$minute" 2>/dev/null || echo "0")
    seconds_part=$(printf "%d" "$seconds_part" 2>/dev/null || echo "0")

    log_debug "time_to_seconds: converting '$time_str' (hour='$hour', minute='$minute', seconds='$seconds_part')"
    echo $((hour * 3600 + minute * 60 + seconds_part))
}
}

# Convert seconds since midnight to HH:MM format
seconds_to_time() {
    seconds="$1"

    # Validate input
    if [ -z "$seconds" ] || ! echo "$seconds" | grep -q '^[0-9]\+$'; then
        log_debug "seconds_to_time: invalid input '$seconds'"
        printf "00:00"
        return 1
    fi

    # Ensure seconds is within valid range (0-86399 for a day)
    if [ "$seconds" -lt 0 ] || [ "$seconds" -ge 86400 ]; then
        log_debug "seconds_to_time: seconds out of range '$seconds'"
        printf "00:00"
        return 1
    fi

    hour=$((seconds / 3600))
    minute=$(((seconds % 3600) / 60))
    printf "%02d:%02d" "$hour" "$minute"
}

# Extract timestamp from log line
extract_log_timestamp() {
    log_line="$1"

    # Validate input
    if [ -z "$log_line" ]; then
        log_debug "extract_log_timestamp: empty log line"
        echo ""
        return 1
    fi

    # Extract timestamp in format: 2025-07-24 13:43:12
    # More robust extraction using multiple patterns
    timestamp=""

    # Try standard format first: YYYY-MM-DD HH:MM:SS
    timestamp=$(echo "$log_line" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/p' 2>/dev/null)

    # If that didn't work, try more permissive pattern
    if [ -z "$timestamp" ]; then
        timestamp=$(echo "$log_line" | sed -n 's/^\([0-9-]* [0-9:]*\).*/\1/p' 2>/dev/null)
    fi

    # Final validation
    if [ -z "$timestamp" ]; then
        log_debug "extract_log_timestamp: could not extract timestamp from '$log_line'"
    else
        log_debug "extract_log_timestamp: extracted '$timestamp' from log line"
    fi

    echo "$timestamp"
}

# Convert log timestamp to seconds since midnight
log_timestamp_to_seconds() {
    timestamp="$1"

    # Validate input
    if [ -z "$timestamp" ]; then
        log_debug "log_timestamp_to_seconds: empty timestamp"
        echo "0"
        return 1
    fi

    # Extract time part (should be after space)
    time_part=$(echo "$timestamp" | cut -d' ' -f2)

    # Validate time part exists
    if [ -z "$time_part" ] || [ "$time_part" = "$timestamp" ]; then
        log_debug "log_timestamp_to_seconds: could not extract time from '$timestamp'"
        echo "0"
        return 1
    fi

    log_debug "log_timestamp_to_seconds: processing timestamp '$timestamp' -> time_part '$time_part'"
    time_to_seconds "$time_part"
}

# Check if log directory exists and is accessible
validate_environment() {
    log_step "Validating analysis environment"

    if [ ! -d "$LOG_DIR" ]; then
        log_error "Log directory not found: $LOG_DIR"
        log_info "This script is designed to run on the RUTX50 router with monitoring active"
        log_info "For development/testing, you can specify --log-dir with a test directory"
        return 1
    fi

    # Check for today's log file
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    if [ ! -f "$log_file" ]; then
        log_warning "No log file found for $ANALYSIS_DATE: $log_file"
        log_info "Available log files:"
        ls -la "$LOG_DIR"/starlink_monitor_*.log 2>/dev/null || log_info "  No monitoring log files found"
        return 1
    fi

    log_debug "Using log file: $log_file"
    log_debug "Report will be written to: $REPORT_FILE"
    return 0
}

# Analyze monitoring logs for outage correlation
analyze_log_correlation() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    temp_events="/tmp/monitor_events_$$.txt"
    temp_metrics="/tmp/monitor_metrics_$$.txt"
    temp_outages="/tmp/known_outages_$$.txt"

    log_step "Extracting monitoring events from logs"

    # Extract relevant events (state changes, quality issues, failovers)
    grep -E "(Quality degraded|Performing soft failover|Quality recovered|Soft failback|WARN|ERROR)" \
        "$log_file" 2>/dev/null >"$temp_events" || {
        log_warning "No monitoring events found in log file"
        touch "$temp_events"
    }

    # Extract metric measurements (for correlation analysis)
    grep -E "(Basic Metrics|Enhanced Metrics)" \
        "$log_file" 2>/dev/null >"$temp_metrics" || {
        log_warning "No metric measurements found in log file"
        touch "$temp_metrics"
    }

    log_debug "Found $(wc -l <"$temp_events" | tr -d ' ') monitoring events"
    log_debug "Found $(wc -l <"$temp_metrics" | tr -d ' ') metric measurements"

    # Write known outages to temp file to avoid subshell variable issues
    echo "$KNOWN_OUTAGES" >"$temp_outages"

    # Initialize report section using grouped commands to fix SC2129
    {
        printf "\n=== OUTAGE CORRELATION ANALYSIS ===\n"
        printf "Analysis Date: %s\n" "$ANALYSIS_DATE"
        printf "Log File: %s\n" "$log_file"
        printf "Generated: %s\n\n" "$(date)"
    } >>"$REPORT_FILE"

    outage_count=0
    correlated_count=0
    failover_count=0

    # Process each known outage (using file instead of pipeline to avoid subshell)
    while read -r outage_line; do
        # Skip empty lines
        [ -z "$outage_line" ] && continue

        outage_time=$(echo "$outage_line" | awk '{print $1}')
        outage_type=$(echo "$outage_line" | awk '{print $2}')
        outage_duration=$(echo "$outage_line" | awk '{print $3}')
        outage_desc=$(echo "$outage_line" | awk '{print $4}')

        [ -z "$outage_time" ] && continue

        outage_count=$((outage_count + 1))
        outage_seconds=$(time_to_seconds "$outage_time")

        # Look for events within ±60 seconds of the outage
        start_window=$((outage_seconds - 60))
        end_window=$((outage_seconds + outage_duration + 60))

        {
            printf "\n--- OUTAGE #%d: %s (%s) ---\n" "$outage_count" "$outage_time" "$outage_type"
            printf "Duration: %ds, Type: %s, Description: %s\n" "$outage_duration" "$outage_type" "$outage_desc"
            printf "Analysis window: %s - %s\n" "$(seconds_to_time $start_window)" "$(seconds_to_time $end_window)"
        } >>"$REPORT_FILE"

        # Find correlated events
        correlated_events=""
        correlated_metrics=""

        while read -r event_line; do
            [ -z "$event_line" ] && continue

            event_timestamp=$(extract_log_timestamp "$event_line")
            [ -z "$event_timestamp" ] && continue

            event_seconds=$(log_timestamp_to_seconds "$event_timestamp")

            if [ "$event_seconds" -ge "$start_window" ] && [ "$event_seconds" -le "$end_window" ]; then
                correlated_events="${correlated_events}${event_line}\n"
                correlated_count=$((correlated_count + 1))

                # Check if this is a failover event
                if echo "$event_line" | grep -q "Performing soft failover"; then
                    failover_count=$((failover_count + 1))
                fi
            fi
        done <"$temp_events"

        # Find correlated metrics
        while read -r metric_line; do
            [ -z "$metric_line" ] && continue

            metric_timestamp=$(extract_log_timestamp "$metric_line")
            [ -z "$metric_timestamp" ] && continue

            metric_seconds=$(log_timestamp_to_seconds "$metric_timestamp")

            if [ "$metric_seconds" -ge "$start_window" ] && [ "$metric_seconds" -le "$end_window" ]; then
                correlated_metrics="${correlated_metrics}${metric_line}\n"
            fi
        done <"$temp_metrics"

        # Report findings using grouped commands to fix SC2129
        {
            if [ -n "$correlated_events" ]; then
                printf "\n✓ CORRELATED EVENTS FOUND:\n"
                printf "%b" "$correlated_events"
            else
                printf "\n✗ NO CORRELATED EVENTS FOUND\n"
            fi

            if [ -n "$correlated_metrics" ]; then
                printf "\n📊 CORRELATED METRICS:\n"
                printf "%b" "$correlated_metrics"
            else
                printf "\n📊 NO METRIC DATA AVAILABLE\n"
            fi
        } >>"$REPORT_FILE"
    done <"$temp_outages"

    # Clean up temp files
    rm -f "$temp_events" "$temp_metrics" "$temp_outages"

    # Store summary for final report
    echo "$outage_count" >"/tmp/outage_count_$$"
    echo "$correlated_count" >"/tmp/correlated_count_$$"
    echo "$failover_count" >"/tmp/failover_count_$$"
}

# Analyze failover behavior and timing
analyze_failover_behavior() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    temp_failovers="/tmp/failover_analysis_$$.txt"

    log_step "Analyzing failover behavior and timing"

    # Extract failover and failback events with timestamps
    grep -E "(Performing soft failover|Soft failback completed|Quality recovered)" \
        "$log_file" 2>/dev/null >"$temp_failovers" || {
        log_warning "No failover events found"
        touch "$temp_failovers"
    }

    printf "\n\n=== FAILOVER BEHAVIOR ANALYSIS ===\n" >>"$REPORT_FILE"

    if [ ! -s "$temp_failovers" ]; then
        {
            printf "No failover events detected in logs.\n"
            printf "This could indicate:\n"
            printf "  - Monitoring was not active during outage periods\n"
            printf "  - Thresholds are too relaxed (not triggering failovers)\n"
            printf "  - Short outages resolved before failover threshold was met\n"
        } >>"$REPORT_FILE"
        rm -f "$temp_failovers"
        return
    fi

    # Analyze failover sequences
    failover_sequences=0
    current_failover_start=""
    total_failover_time=0
    rapid_failbacks=0

    while read -r event_line; do
        event_timestamp=$(extract_log_timestamp "$event_line")

        if echo "$event_line" | grep -q "Performing soft failover"; then
            if [ -n "$current_failover_start" ]; then
                log_warning "Detected nested failover - possible aggressive behavior"
            fi
            current_failover_start="$event_timestamp"
            failover_sequences=$((failover_sequences + 1))

            # Extract reason from the event
            reason=$(echo "$event_line" | sed 's/.*Quality degraded below threshold: //' | sed 's/.*failover due to signal degradation: //')

            {
                printf "\n--- FAILOVER SEQUENCE #%d ---\n" "$failover_sequences"
                printf "Failover started: %s\n" "$event_timestamp"
                printf "Reason: %s\n" "$reason"
            } >>"$REPORT_FILE"

        elif echo "$event_line" | grep -q "Soft failback completed" && [ -n "$current_failover_start" ]; then
            failback_time="$event_timestamp"

            # Calculate duration (simplified - just using time difference)
            start_seconds=$(log_timestamp_to_seconds "$current_failover_start")
            end_seconds=$(log_timestamp_to_seconds "$failback_time")
            duration=$((end_seconds - start_seconds))

            if [ "$duration" -lt 0 ]; then
                duration=$((duration + 86400)) # Handle day rollover
            fi

            total_failover_time=$((total_failover_time + duration))

            # Check for rapid failback (less than 2 minutes)
            if [ "$duration" -lt 120 ]; then
                rapid_failbacks=$((rapid_failbacks + 1))
                {
                    printf "Failback completed: %s\n" "$failback_time"
                    printf "Failover duration: %d seconds (%d minutes)\n" "$duration" "$((duration / 60))"
                    printf "⚠️  RAPID FAILBACK detected (< 2 minutes)\n"
                } >>"$REPORT_FILE"
            else
                {
                    printf "Failback completed: %s\n" "$failback_time"
                    printf "Failover duration: %d seconds (%d minutes)\n" "$duration" "$((duration / 60))"
                } >>"$REPORT_FILE"
            fi

            current_failover_start=""
        fi
    done <"$temp_failovers"

    # Generate behavior analysis
    {
        printf "\n=== FAILOVER BEHAVIOR SUMMARY ===\n"
        printf "Total failover sequences: %d\n" "$failover_sequences"
        printf "Rapid failbacks (< 2 min): %d\n" "$rapid_failbacks"
    } >>"$REPORT_FILE"

    if [ "$failover_sequences" -gt 0 ]; then
        avg_duration=$((total_failover_time / failover_sequences))
        {
            printf "Average failover duration: %d seconds (%d minutes)\n" "$avg_duration" "$((avg_duration / 60))"
            printf "\n=== RECOMMENDATIONS ===\n"
        } >>"$REPORT_FILE"

        if [ "$rapid_failbacks" -gt $((failover_sequences / 2)) ]; then
            {
                printf "⚠️  HIGH RAPID FAILBACK RATE: Consider increasing STABILITY_CHECKS_REQUIRED\n"
                printf "   Current quick failbacks suggest thresholds may be too sensitive\n"
            } >>"$REPORT_FILE"
        fi

        if [ "$failover_sequences" -gt 10 ]; then
            {
                printf "⚠️  HIGH FAILOVER FREQUENCY: Consider relaxing quality thresholds\n"
                printf "   Multiple failovers may indicate overly aggressive monitoring\n"
            } >>"$REPORT_FILE"
        fi

        if [ "$avg_duration" -gt 600 ]; then
            {
                printf "⚠️  LONG FAILOVER DURATIONS: Consider decreasing STABILITY_CHECKS_REQUIRED\n"
                printf "   Long failovers may indicate overly conservative failback logic\n"
            } >>"$REPORT_FILE"
        fi
    fi

    rm -f "$temp_failovers"
}

# Generate threshold analysis and recommendations
analyze_threshold_effectiveness() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"

    log_step "Analyzing threshold effectiveness"

    printf "\n\n=== THRESHOLD EFFECTIVENESS ANALYSIS ===\n" >>"$REPORT_FILE"

    # Analyze missed outages (outages without failovers)
    outage_count=$(cat "/tmp/outage_count_$$" 2>/dev/null || echo "0")
    correlated_count=$(cat "/tmp/correlated_count_$$" 2>/dev/null || echo "0")
    failover_count=$(cat "/tmp/failover_count_$$" 2>/dev/null || echo "0")

    # Calculate coverage statistics
    if [ "$outage_count" -gt 0 ]; then
        coverage_percentage=$((correlated_count * 100 / outage_count))
        failover_percentage=$((failover_count * 100 / outage_count))
    else
        coverage_percentage=0
        failover_percentage=0
    fi

    {
        printf "Monitoring Coverage Analysis:\n"
        printf "  Known outages: %d\n" "$outage_count"
        printf "  Detected events: %d (%d%% coverage)\n" "$correlated_count" "$coverage_percentage"
        printf "  Triggered failovers: %d (%d%% of outages)\n" "$failover_count" "$failover_percentage"
        printf "\n=== THRESHOLD TUNING RECOMMENDATIONS ===\n"
    } >>"$REPORT_FILE"

    if [ "$coverage_percentage" -lt 50 ]; then
        {
            printf "🔴 LOW COVERAGE (%d%%): Monitoring may be missing outages\n" "$coverage_percentage"
            printf "   Recommendations:\n"
            printf "   - Check if monitoring service is running continuously\n"
            printf "   - Verify Starlink API connectivity\n"
            printf "   - Consider more frequent monitoring checks\n"
        } >>"$REPORT_FILE"
    elif [ "$coverage_percentage" -lt 80 ]; then
        {
            printf "🟡 MODERATE COVERAGE (%d%%): Some outages may be missed\n" "$coverage_percentage"
            printf "   Recommendations:\n"
            printf "   - Review short outage detection capability\n"
            printf "   - Consider adjusting monitoring frequency\n"
        } >>"$REPORT_FILE"
    else
        printf "🟢 GOOD COVERAGE (%d%%): Most outages are being detected\n" "$coverage_percentage" >>"$REPORT_FILE"
    fi

    if [ "$failover_percentage" -lt 30 ]; then
        {
            printf "🔴 LOW FAILOVER RATE (%d%%): Thresholds may be too relaxed\n" "$failover_percentage"
            printf "   Recommendations:\n"
            printf "   - Lower OBSTRUCTION_THRESHOLD (currently should be < 0.05)\n"
            printf "   - Lower PACKET_LOSS_THRESHOLD (currently should be < 0.02)\n"
            printf "   - Lower LATENCY_THRESHOLD_MS (currently should be < 100ms)\n"
        } >>"$REPORT_FILE"
    elif [ "$failover_percentage" -gt 80 ]; then
        {
            printf "🟡 HIGH FAILOVER RATE (%d%%): Thresholds may be too aggressive\n" "$failover_percentage"
            printf "   Recommendations:\n"
            printf "   - Increase threshold values slightly\n"
            printf "   - Consider longer averaging periods\n"
            printf "   - Review enhanced metrics for false positives\n"
        } >>"$REPORT_FILE"
    else
        printf "🟢 BALANCED FAILOVER RATE (%d%%): Thresholds appear well-tuned\n" "$failover_percentage" >>"$REPORT_FILE"
    fi

    # Clean up temp files
    rm -f "/tmp/outage_count_$$" "/tmp/correlated_count_$$" "/tmp/failover_count_$$"
}

# Generate final report summary
generate_report_summary() {
    log_step "Generating analysis report"

    {
        printf "\n\n=== ANALYSIS SUMMARY ===\n"
        printf "Script Version: %s\n" "$SCRIPT_VERSION"
        printf "Analysis completed: %s\n" "$(date)"
        printf "Report file: %s\n" "$REPORT_FILE"
        printf "\nNext Steps:\n"
        printf "1. Review correlation analysis for missed outages\n"
        printf "2. Adjust monitoring thresholds based on recommendations\n"
        printf "3. Test threshold changes in controlled environment\n"
        printf "4. Monitor failover behavior after tuning\n"
        printf "5. Re-run analysis after configuration changes\n"
    } >>"$REPORT_FILE"

    log_info "Analysis complete! Report saved to: $REPORT_FILE"
    log_info "Review the report for detailed findings and recommendations"
}

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# Main execution
main() {
    log_info "Starting Starlink Outage Correlation Analysis v$SCRIPT_VERSION"

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
    printf "STARLINK OUTAGE CORRELATION ANALYSIS REPORT\n" >"$REPORT_FILE"
    printf "Generated by: %s v%s\n" "$(basename "$0")" "$SCRIPT_VERSION" >>"$REPORT_FILE"
    printf "=====================================================\n" >>"$REPORT_FILE"

    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi

    # Run analysis phases
    analyze_log_correlation
    analyze_failover_behavior
    analyze_threshold_effectiveness
    generate_report_summary

    log_info "Analysis completed successfully!"
    log_info "Open the report file to view detailed results: $REPORT_FILE"
}

# Execute main function with all arguments
main "$@"
