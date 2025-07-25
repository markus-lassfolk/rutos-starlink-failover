#!/bin/sh

# ==============================================================================
# Test Version of Starlink Outage Correlation Analysis Script for RUTOS
# Modified to work with local temp logs for testing the infinite loop issue
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

# Configuration for testing
ANALYSIS_DATE="2025-07-24"
LOG_DIR="./temp" # Use local temp directory for testing
REPORT_FILE="./temp/test_outage_analysis_$(date '+%Y%m%d_%H%M%S').txt"
DEBUG="${DEBUG:-1}" # Enable debug by default for testing

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

# Convert time to seconds since midnight (simplified version for testing)
time_to_seconds() {
    time_str="$1"

    if [ -z "$time_str" ]; then
        echo "0"
        return 1
    fi

    hour=$(echo "$time_str" | cut -d: -f1)
    minute=$(echo "$time_str" | cut -d: -f2)

    # Basic validation
    if ! echo "$hour" | grep -q '^[0-9]\+$' || ! echo "$minute" | grep -q '^[0-9]\+$'; then
        echo "0"
        return 1
    fi

    # Remove leading zeros to prevent octal interpretation
    hour=$(printf "%d" "$hour" 2>/dev/null || echo "0")
    minute=$(printf "%d" "$minute" 2>/dev/null || echo "0")

    echo $((hour * 3600 + minute * 60))
}

# Convert seconds since midnight to HH:MM format
seconds_to_time() {
    seconds="$1"

    # Validate input
    if [ -z "$seconds" ] || ! echo "$seconds" | grep -q '^[0-9]\+$'; then
        printf "00:00"
        return 1
    fi

    hour=$((seconds / 3600))
    minute=$(((seconds % 3600) / 60))
    printf "%02d:%02d" "$hour" "$minute"
}

# Extract timestamp from log line (simplified)
extract_log_timestamp() {
    log_line="$1"
    echo "$log_line" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/p'
}

# Convert log timestamp to seconds since midnight
log_timestamp_to_seconds() {
    timestamp="$1"
    time_part=$(echo "$timestamp" | cut -d' ' -f2)
    time_to_seconds "$time_part"
}

# Validate environment
validate_environment() {
    log_step "Validating test environment"

    if [ ! -d "$LOG_DIR" ]; then
        log_error "Log directory not found: $LOG_DIR"
        return 1
    fi

    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    if [ ! -f "$log_file" ]; then
        log_error "No log file found for $ANALYSIS_DATE: $log_file"
        return 1
    fi

    log_debug "Using log file: $log_file"
    log_debug "Report will be written to: $REPORT_FILE"
    return 0
}

# Test the main analysis loop to find infinite loop issue
test_main_analysis() {
    log_file="$LOG_DIR/starlink_monitor_$ANALYSIS_DATE.log"
    temp_events="/tmp/monitor_events_test_$$.txt"
    temp_outages="/tmp/known_outages_test_$$.txt"

    log_step "Starting test analysis to identify infinite loop"

    # Extract relevant events
    log_debug "Extracting events from log file..."
    grep -E "(Quality degraded|Performing soft failover|Quality recovered|Soft failback|WARN|ERROR|state: down)" \
        "$log_file" 2>/dev/null >"$temp_events" || {
        log_warning "No monitoring events found in log file"
        touch "$temp_events"
    }

    event_count=$(wc -l <"$temp_events" | tr -d ' ')
    log_debug "Found $event_count monitoring events"

    # Write known outages to temp file
    echo "$KNOWN_OUTAGES" >"$temp_outages"

    # Initialize report
    {
        printf "\n=== TEST OUTAGE CORRELATION ANALYSIS ===\n"
        printf "Analysis Date: %s\n" "$ANALYSIS_DATE"
        printf "Log File: %s\n" "$log_file"
        printf "Generated: %s\n\n" "$(date)"
    } >"$REPORT_FILE"

    outage_count=0
    process_count=0

    log_debug "Starting outage processing loop..."

    # Process each known outage with progress tracking
    while read -r outage_line; do
        # Skip empty lines
        [ -z "$outage_line" ] && continue

        process_count=$((process_count + 1))
        log_debug "Processing line $process_count: '$outage_line'"

        outage_time=$(echo "$outage_line" | awk '{print $1}')
        outage_type=$(echo "$outage_line" | awk '{print $2}')
        outage_duration=$(echo "$outage_line" | awk '{print $3}')
        outage_desc=$(echo "$outage_line" | awk '{print $4}')

        # Skip if no time
        if [ -z "$outage_time" ]; then
            log_debug "Skipping line with no time: '$outage_line'"
            continue
        fi

        outage_count=$((outage_count + 1))
        log_debug "Processing outage #$outage_count: $outage_time ($outage_type)"

        outage_seconds=$(time_to_seconds "$outage_time")
        log_debug "Outage time in seconds: $outage_seconds"

        # Look for events within ±60 seconds of the outage
        start_window=$((outage_seconds - 60))
        end_window=$((outage_seconds + outage_duration + 60))

        {
            printf "\n--- OUTAGE #%d: %s (%s) ---\n" "$outage_count" "$outage_time" "$outage_type"
            printf "Duration: %ds, Type: %s, Description: %s\n" "$outage_duration" "$outage_type" "$outage_desc"
            printf "Analysis window: %s - %s\n" "$(seconds_to_time $start_window)" "$(seconds_to_time $end_window)"
        } >>"$REPORT_FILE"

        # Find correlated events (THIS MIGHT BE WHERE THE LOOP HAPPENS)
        correlated_events=""
        event_processing_count=0

        log_debug "Searching for correlated events in window $start_window - $end_window"

        while read -r event_line; do
            [ -z "$event_line" ] && continue

            event_processing_count=$((event_processing_count + 1))

            # Add safety counter to prevent infinite loop
            if [ "$event_processing_count" -gt 1000 ]; then
                log_error "INFINITE LOOP DETECTED: Processed $event_processing_count events for outage #$outage_count"
                log_error "Last event line: '$event_line'"
                echo "ERROR: Infinite loop detected in event processing" >>"$REPORT_FILE"
                break
            fi

            if [ $((event_processing_count % 100)) -eq 0 ]; then
                log_debug "Processed $event_processing_count events for outage #$outage_count"
            fi

            event_timestamp=$(extract_log_timestamp "$event_line")
            [ -z "$event_timestamp" ] && continue

            event_seconds=$(log_timestamp_to_seconds "$event_timestamp")

            if [ "$event_seconds" -ge "$start_window" ] && [ "$event_seconds" -le "$end_window" ]; then
                correlated_events="${correlated_events}${event_line}\n"
                log_debug "Found correlated event at $event_timestamp"
            fi
        done <"$temp_events"

        log_debug "Completed event correlation for outage #$outage_count (processed $event_processing_count events)"

        # Report findings
        {
            if [ -n "$correlated_events" ]; then
                printf "\n✓ CORRELATED EVENTS FOUND:\n"
                printf "%b" "$correlated_events"
            else
                printf "\n✗ NO CORRELATED EVENTS FOUND\n"
            fi
        } >>"$REPORT_FILE"

        # Safety check - if we've processed too many outages, something is wrong
        if [ "$outage_count" -gt 50 ]; then
            log_error "SAFETY BREAK: Processed $outage_count outages - possible infinite loop"
            break
        fi

    done <"$temp_outages"

    log_info "Test analysis completed"
    log_info "Processed $process_count lines, found $outage_count valid outages"

    # Clean up
    rm -f "$temp_events" "$temp_outages"

    # Generate summary
    {
        printf "\n=== TEST ANALYSIS SUMMARY ===\n"
        printf "Lines processed: %d\n" "$process_count"
        printf "Valid outages found: %d\n" "$outage_count"
        printf "Report location: %s\n" "$REPORT_FILE"
    } >>"$REPORT_FILE"

    log_info "Test analysis report saved to: $REPORT_FILE"
}

# Main execution
main() {
    log_info "Starting Test Outage Correlation Analysis v$SCRIPT_VERSION"

    if [ "$DEBUG" = "1" ]; then
        log_debug "==================== DEBUG MODE ENABLED ===================="
        log_debug "Analysis date: $ANALYSIS_DATE"
        log_debug "Log directory: $LOG_DIR"
        log_debug "Report file: $REPORT_FILE"
        log_debug "=============================================================="
    fi

    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi

    # Run test analysis
    test_main_analysis

    log_info "Test analysis completed successfully!"
}

# Execute main function
main "$@"
