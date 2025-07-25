#!/bin/sh
# Script: analyze-failover-timing-rutos.sh
# Version: 1.0.0
# Description: Advanced failover timing analysis for RUTOS Starlink monitoring
# Analyzes failover decisions, timing optimization, and threshold effectiveness

set -e # Exit on error

# Version information
SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='\033[0;35m'
# shellcheck disable=SC2034  # Used in debug logging functions
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

# Standard logging functions with consistent colors
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

# Configuration
TEMP_DIR="temp"
ANALYSIS_OUTPUT="failover_timing_analysis_$(date '+%Y%m%d_%H%M%S').md"
PRE_FAILOVER_WINDOW=300  # 5 minutes before failover
POST_FAILOVER_WINDOW=180 # 3 minutes after failover

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Find all state transitions
extract_state_transitions() {
    log_step "Extracting state transitions from all log files"

    temp_transitions="/tmp/state_transitions_$$"

    # Extract all state information with timestamps
    find "$TEMP_DIR" -name "starlink_monitor_*.log" -type f | while read -r logfile; do
        grep "Current state:" "$logfile" | sed "s|^|$(basename "$logfile"): |"
    done | sort >"$temp_transitions"

    log_info "Found $(wc -l <"$temp_transitions") state records across all log files"
    echo "$temp_transitions"
}

# Identify failover events (state changes)
identify_failover_events() {
    transitions_file="$1"
    log_step "Identifying failover events (state transitions)"

    temp_failovers="/tmp/failovers_$$"

    # Process transitions to find state changes
    previous_state=""
    previous_time=""
    previous_file=""

    while IFS=': ' read -r filename timestamp rest; do
        # Extract state and other info
        if echo "$rest" | grep -q "Current state:"; then
            current_state=$(echo "$rest" | sed 's/.*Current state: \([^,]*\).*/\1/')
            stability=$(echo "$rest" | sed 's/.*Stability: \([0-9]*\).*/\1/')
            metric=$(echo "$rest" | sed 's/.*Metric: \([0-9]*\).*/\1/')

            if [ -n "$previous_state" ] && [ "$current_state" != "$previous_state" ]; then
                # Found a state change - this is a failover event
                printf "%s %s: %s->%s (Stability: %s, Metric: %s)\n" \
                    "$filename" "$timestamp" "$previous_state" "$current_state" "$stability" "$metric" >>"$temp_failovers"

                log_debug "Failover detected: $previous_state->$current_state at $timestamp"
            fi

            previous_state="$current_state"
            previous_time="$timestamp"
            previous_file="$filename"
        fi
    done <"$transitions_file"

    failover_count=$(wc -l <"$temp_failovers" 2>/dev/null || echo "0")
    log_info "Identified $failover_count failover events"

    echo "$temp_failovers"
}

# Analyze metrics around failover events
analyze_failover_context() {
    failovers_file="$1"
    log_step "Analyzing metrics context around each failover event"

    analysis_output="/tmp/failover_analysis_$$"

    # Header for analysis
    {
        echo "# Failover Timing Analysis Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## Executive Summary"
        echo ""
        echo "This analysis examines each failover event to determine:"
        echo "- Whether the failover was necessary (legitimate quality degradation)"
        echo "- If we could have detected the issue earlier"
        echo "- If the failover timing was optimal"
        echo "- Whether short glitches caused unnecessary failovers"
        echo ""
        echo "## Detailed Failover Analysis"
        echo ""
    } >"$analysis_output"

    event_num=1

    while read -r failover_line; do
        log_step "Analyzing failover event $event_num"

        # Parse failover event
        filename=$(echo "$failover_line" | cut -d':' -f1)
        timestamp=$(echo "$failover_line" | cut -d':' -f2-3 | sed 's/ [A-Z].*$//')
        transition=$(echo "$failover_line" | grep -o '[a-z]*->[a-z]*')

        {
            echo "### Failover Event #$event_num"
            echo "**Time**: $timestamp"
            echo "**File**: $filename"
            echo "**Transition**: $transition"
            echo ""
        } >>"$analysis_output"

        # Analyze metrics before failover
        analyze_pre_failover_metrics "$filename" "$timestamp" "$analysis_output"

        # Analyze metrics after failover
        analyze_post_failover_metrics "$filename" "$timestamp" "$analysis_output"

        # Provide timing assessment
        assess_failover_timing "$filename" "$timestamp" "$transition" "$analysis_output"

        echo "" >>"$analysis_output"

        event_num=$((event_num + 1))

    done <"$failovers_file"

    # Generate summary and recommendations
    generate_failover_summary "$analysis_output"

    echo "$analysis_output"
}

# Analyze metrics before failover
analyze_pre_failover_metrics() {
    filename="$1"
    failover_time="$2"
    output_file="$3"

    log_debug "Analyzing pre-failover metrics for $failover_time"

    {
        echo "#### Pre-Failover Analysis (5 minutes before)"
        echo ""
    } >>"$output_file"

    # Extract metrics from 5 minutes before failover
    temp_metrics="/tmp/pre_metrics_$$"

    # Get metrics leading up to failover
    grep -B 20 "$failover_time" "$TEMP_DIR/$filename" | grep "Metrics -" | tail -5 >"$temp_metrics"

    if [ -s "$temp_metrics" ]; then
        echo "**Recent metrics before failover:**" >>"$output_file"
        echo '```' >>"$output_file"
        cat "$temp_metrics" >>"$output_file"
        echo '```' >>"$output_file"
        echo "" >>"$output_file"

        # Analyze trends
        analyze_metric_trends "$temp_metrics" "$output_file" "pre-failover"
    else
        echo "**No pre-failover metrics found**" >>"$output_file"
        echo "" >>"$output_file"
    fi

    rm -f "$temp_metrics"
}

# Analyze metrics after failover
analyze_post_failover_metrics() {
    filename="$1"
    failover_time="$2"
    output_file="$3"

    log_debug "Analyzing post-failover metrics for $failover_time"

    {
        echo "#### Post-Failover Analysis (3 minutes after)"
        echo ""
    } >>"$output_file"

    # Extract metrics from 3 minutes after failover
    temp_metrics="/tmp/post_metrics_$$"

    # Get metrics after failover
    grep -A 15 "$failover_time" "$TEMP_DIR/$filename" | grep "Metrics -" | head -3 >"$temp_metrics"

    if [ -s "$temp_metrics" ]; then
        echo "**Metrics after failover:**" >>"$output_file"
        echo '```' >>"$output_file"
        cat "$temp_metrics" >>"$output_file"
        echo '```' >>"$output_file"
        echo "" >>"$output_file"

        # Analyze recovery
        analyze_metric_trends "$temp_metrics" "$output_file" "post-failover"
    else
        echo "**No post-failover metrics found**" >>"$output_file"
        echo "" >>"$output_file"
    fi

    rm -f "$temp_metrics"
}

# Analyze metric trends for threshold violations
analyze_metric_trends() {
    metrics_file="$1"
    output_file="$2"
    context="$3"

    # Extract key metrics and check for threshold violations
    obstruction_violations=0
    loss_violations=0
    latency_violations=0

    while read -r line; do
        # Extract threshold violation flags
        if echo "$line" | grep -q "high: 1"; then
            if echo "$line" | grep -q "Obstruction:"; then
                obstruction_violations=$((obstruction_violations + 1))
            elif echo "$line" | grep -q "Loss:"; then
                loss_violations=$((loss_violations + 1))
            elif echo "$line" | grep -q "Latency:"; then
                latency_violations=$((latency_violations + 1))
            fi
        fi
    done <"$metrics_file"

    {
        echo "**Threshold violations in $context period:**"
        echo "- Obstruction violations: $obstruction_violations"
        echo "- Packet loss violations: $loss_violations"
        echo "- Latency violations: $latency_violations"
        echo ""
    } >>"$output_file"
}

# Assess failover timing and provide recommendations
assess_failover_timing() {
    filename="$1"
    failover_time="$2"
    transition="$3"
    output_file="$4"

    log_debug "Assessing failover timing for $transition at $failover_time"

    {
        echo "#### Timing Assessment"
        echo ""
    } >>"$output_file"

    # Analyze transition type
    case "$transition" in
        "up->down")
            assess_failto_cellular "$filename" "$failover_time" "$output_file"
            ;;
        "down->up")
            assess_failback_to_starlink "$filename" "$failover_time" "$output_file"
            ;;
        *)
            echo "**Unknown transition type: $transition**" >>"$output_file"
            ;;
    esac

    echo "" >>"$output_file"
}

# Assess failover to cellular (up->down transition)
assess_failto_cellular() {
    filename="$1"
    failover_time="$2"
    output_file="$3"

    {
        echo "**Failover to Cellular Analysis:**"
        echo ""
        echo "This represents switching FROM Starlink TO cellular backup."
        echo ""
    } >>"$output_file"

    # Look for leading indicators
    temp_leading="/tmp/leading_$$"
    grep -B 10 "$failover_time" "$TEMP_DIR/$filename" | grep "high: 1" >"$temp_leading"

    leading_violations=$(wc -l <"$temp_leading")

    if [ "$leading_violations" -gt 0 ]; then
        {
            echo "✅ **JUSTIFIED FAILOVER** - Found $leading_violations threshold violations before failover"
            echo ""
            echo "Leading indicators:"
            echo '```'
            cat "$temp_leading"
            echo '```'
            echo ""
            echo "**Assessment**: Failover was appropriate based on threshold violations."
        } >>"$output_file"
    else
        {
            echo "⚠️ **QUESTIONABLE FAILOVER** - No clear threshold violations found before failover"
            echo ""
            echo "**Assessment**: This failover may have been premature or triggered by transient issues."
            echo "**Recommendation**: Review threshold sensitivity and stability requirements."
        } >>"$output_file"
    fi

    rm -f "$temp_leading"
}

# Assess failback to Starlink (down->up transition)
assess_failback_to_starlink() {
    filename="$1"
    failover_time="$2"
    output_file="$3"

    {
        echo "**Failback to Starlink Analysis:**"
        echo ""
        echo "This represents switching FROM cellular backup TO Starlink."
        echo ""
    } >>"$output_file"

    # Look for stability buildup
    temp_stability="/tmp/stability_$$"
    grep -B 5 "$failover_time" "$TEMP_DIR/$filename" | grep "Stability:" >"$temp_stability"

    if [ -s "$temp_stability" ]; then
        max_stability=$(cat "$temp_stability" | sed 's/.*Stability: \([0-9]*\).*/\1/' | sort -n | tail -1)

        {
            echo "**Stability progression before failback:**"
            echo '```'
            cat "$temp_stability"
            echo '```'
            echo ""
        } >>"$output_file"

        if [ "$max_stability" -ge 5 ]; then
            echo "✅ **APPROPRIATE FAILBACK** - Achieved sufficient stability ($max_stability checks)" >>"$output_file"
        else
            echo "⚠️ **PREMATURE FAILBACK** - Insufficient stability ($max_stability checks)" >>"$output_file"
            echo "**Recommendation**: Increase stability requirements before failback." >>"$output_file"
        fi
    else
        echo "**No stability information found**" >>"$output_file"
    fi

    rm -f "$temp_stability"
}

# Generate summary and recommendations
generate_failover_summary() {
    analysis_file="$1"

    log_step "Generating failover summary and recommendations"

    {
        echo ""
        echo "## Summary and Recommendations"
        echo ""
        echo "### Key Findings"
        echo ""

        # Count different types of assessments
        justified_count=$(grep -c "JUSTIFIED FAILOVER" "$analysis_file" || echo "0")
        questionable_count=$(grep -c "QUESTIONABLE FAILOVER" "$analysis_file" || echo "0")
        appropriate_count=$(grep -c "APPROPRIATE FAILBACK" "$analysis_file" || echo "0")
        premature_count=$(grep -c "PREMATURE FAILBACK" "$analysis_file" || echo "0")

        echo "- **Justified failovers**: $justified_count"
        echo "- **Questionable failovers**: $questionable_count"
        echo "- **Appropriate failbacks**: $appropriate_count"
        echo "- **Premature failbacks**: $premature_count"
        echo ""

        echo "### Overall Assessment"
        echo ""

        total_events=$((justified_count + questionable_count + appropriate_count + premature_count))

        if [ "$total_events" -gt 0 ]; then
            good_decisions=$((justified_count + appropriate_count))
            success_rate=$((good_decisions * 100 / total_events))

            echo "**Failover Success Rate**: $success_rate% ($good_decisions/$total_events)"
            echo ""

            if [ "$success_rate" -ge 80 ]; then
                echo "✅ **EXCELLENT** - Your failover system is making good decisions"
            elif [ "$success_rate" -ge 60 ]; then
                echo "⚠️ **GOOD** - Minor tuning may improve performance"
            else
                echo "❌ **NEEDS IMPROVEMENT** - Significant threshold tuning recommended"
            fi
        else
            echo "No failover events analyzed."
        fi

        echo ""
        echo "### Recommendations"
        echo ""

        if [ "$questionable_count" -gt 0 ]; then
            echo "1. **Review Threshold Sensitivity**: $questionable_count questionable failovers suggest thresholds may be too aggressive"
            echo "   - Consider increasing threshold values slightly"
            echo "   - Implement hysteresis (different thresholds for failover vs recovery)"
        fi

        if [ "$premature_count" -gt 0 ]; then
            echo "2. **Increase Stability Requirements**: $premature_count premature failbacks detected"
            echo "   - Increase stability check count before failback"
            echo "   - Consider longer observation periods for quality verification"
        fi

        echo ""
        echo "### Proposed Threshold Optimizations"
        echo ""
        echo "Based on this analysis, consider these adjustments:"
        echo ""
        echo '```bash'
        echo "# Current vs Recommended Thresholds"
        echo "OBSTRUCTION_THRESHOLD=0.001      # Current: 0.1%"
        echo "OBSTRUCTION_HYSTERESIS=0.0005    # New: 0.05% for recovery"
        echo ""
        echo "PACKET_LOSS_THRESHOLD=0.03       # Current: 3%"
        echo "PACKET_LOSS_HYSTERESIS=0.01      # New: 1% for recovery"
        echo ""
        echo "LATENCY_THRESHOLD_MS=150         # Current: 150ms"
        echo "LATENCY_HYSTERESIS_MS=100        # New: 100ms for recovery"
        echo ""
        echo "STABILITY_CHECKS_REQUIRED=6      # Increase from current 5"
        echo '```'

    } >>"$analysis_file"
}

# Main analysis function
main() {
    log_info "Starting comprehensive failover timing analysis v$SCRIPT_VERSION"

    # Validate environment
    if [ ! -d "$TEMP_DIR" ]; then
        log_error "Temp directory not found: $TEMP_DIR"
        exit 1
    fi

    # Check for log files
    log_count=$(find "$TEMP_DIR" -name "starlink_monitor_*.log" -type f | wc -l)
    if [ "$log_count" -eq 0 ]; then
        log_error "No Starlink monitor log files found in $TEMP_DIR"
        exit 1
    fi

    log_info "Found $log_count log files for analysis"

    # Step 1: Extract all state transitions
    log_step "Phase 1: Extracting state transitions"
    transitions_file=$(extract_state_transitions)

    # Step 2: Identify failover events
    log_step "Phase 2: Identifying failover events"
    failovers_file=$(identify_failover_events "$transitions_file")

    # Step 3: Analyze each failover event
    log_step "Phase 3: Analyzing failover context and timing"
    analysis_file=$(analyze_failover_context "$failovers_file")

    # Step 4: Copy final report
    cp "$analysis_file" "$ANALYSIS_OUTPUT"

    # Cleanup
    rm -f "$transitions_file" "$failovers_file" "$analysis_file"

    log_success "Failover timing analysis completed"
    log_info "Report saved to: $ANALYSIS_OUTPUT"

    # Display summary
    if [ -f "$ANALYSIS_OUTPUT" ]; then
        log_step "Analysis Summary"
        grep -A 20 "## Summary and Recommendations" "$ANALYSIS_OUTPUT" | head -15
    fi
}

# Execute main function
main "$@"
