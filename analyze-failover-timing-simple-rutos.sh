#!/bin/sh
# Script: analyze-failover-timing-simple-rutos.sh
# Version: 2.7.0
# Description: Simplified failover timing analysis for RUTOS Starlink monitoring

set -e

SCRIPT_VERSION="2.7.0"

# Standard colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

# Configuration
TEMP_DIR="temp"
ANALYSIS_OUTPUT="failover_timing_analysis_$(date '+%Y%m%d_%H%M%S').md"

main() {
    log_info "Starting simplified failover timing analysis v$SCRIPT_VERSION"

    if [ ! -d "$TEMP_DIR" ]; then
        log_error "Temp directory not found: $TEMP_DIR"
        exit 1
    fi

    # Create analysis report
    {
        echo "# Failover Timing Analysis Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## Log Files Analyzed"
        echo ""
    } >"$ANALYSIS_OUTPUT"

    # List log files
    log_step "Analyzing log files in $TEMP_DIR"
    find "$TEMP_DIR" -name "starlink_monitor_*.log" -type f | while read -r logfile; do
        echo "- $(basename "$logfile")" >>"$ANALYSIS_OUTPUT"
    done

    echo "" >>"$ANALYSIS_OUTPUT"

    # Extract state transitions for each file
    log_step "Extracting state transitions"
    {
        echo "## State Transition Analysis"
        echo ""
    } >>"$ANALYSIS_OUTPUT"

    find "$TEMP_DIR" -name "starlink_monitor_*.log" -type f | sort | while read -r logfile; do
        filename=$(basename "$logfile")
        log_info "Processing $filename"

        {
            echo "### $filename"
            echo ""
        } >>"$ANALYSIS_OUTPUT"

        # Find state transitions in this file
        temp_states="/tmp/states_${filename}_$$"
        grep "Current state:" "$logfile" >"$temp_states" || true

        if [ -s "$temp_states" ]; then
            # Look for state changes
            previous_state=""
            transition_count=0

            {
                echo "**State Transitions Found:**"
                echo ""
            } >>"$ANALYSIS_OUTPUT"

            while read -r line; do
                current_state=$(echo "$line" | sed 's/.*Current state: \([^,]*\).*/\1/')
                timestamp=$(echo "$line" | cut -d' ' -f1-2)
                stability=$(echo "$line" | sed 's/.*Stability: \([0-9]*\).*/\1/')
                metric=$(echo "$line" | sed 's/.*Metric: \([0-9]*\).*/\1/')

                if [ -n "$previous_state" ] && [ "$current_state" != "$previous_state" ]; then
                    transition_count=$((transition_count + 1))
                    {
                        echo "**Transition #$transition_count**: $timestamp"
                        echo "- **Change**: $previous_state → $current_state"
                        echo "- **Stability**: $stability"
                        echo "- **Metric**: $metric"
                        echo ""
                    } >>"$ANALYSIS_OUTPUT"

                    # Analyze metrics around this transition
                    analyze_transition_context "$logfile" "$timestamp" "$previous_state" "$current_state"
                fi

                previous_state="$current_state"
            done <"$temp_states"

            if [ "$transition_count" -eq 0 ]; then
                echo "No state transitions found in this file." >>"$ANALYSIS_OUTPUT"
                echo "" >>"$ANALYSIS_OUTPUT"
            fi
        else
            echo "No state information found in this file." >>"$ANALYSIS_OUTPUT"
            echo "" >>"$ANALYSIS_OUTPUT"
        fi

        rm -f "$temp_states"
    done

    # Generate summary
    generate_summary

    log_success "Analysis completed: $ANALYSIS_OUTPUT"
}

analyze_transition_context() {
    logfile="$1"
    timestamp="$2"
    from_state="$3"
    to_state="$4"

    {
        echo "**Metrics Context Analysis:**"
        echo ""
    } >>"$ANALYSIS_OUTPUT"

    # Get metrics before the transition
    temp_before="/tmp/before_$$"
    grep -B 10 "$timestamp" "$logfile" | grep "Metrics -" | tail -3 >"$temp_before"

    if [ -s "$temp_before" ]; then
        {
            echo "*Pre-transition metrics:*"
            echo '```'
            cat "$temp_before"
            echo '```'
            echo ""
        } >>"$ANALYSIS_OUTPUT"

        # Check for threshold violations
        violations=$(grep -c "high: 1" "$temp_before" || echo "0")
        {
            echo "- **Threshold violations before transition**: $violations"
        } >>"$ANALYSIS_OUTPUT"
    fi

    # Get metrics after the transition
    temp_after="/tmp/after_$$"
    grep -A 5 "$timestamp" "$logfile" | grep "Metrics -" | head -2 >"$temp_after"

    if [ -s "$temp_after" ]; then
        {
            echo ""
            echo "*Post-transition metrics:*"
            echo '```'
            cat "$temp_after"
            echo '```'
            echo ""
        } >>"$ANALYSIS_OUTPUT"
    fi

    # Assess the transition
    assess_transition "$from_state" "$to_state" "$violations"

    echo "---" >>"$ANALYSIS_OUTPUT"
    echo "" >>"$ANALYSIS_OUTPUT"

    rm -f "$temp_before" "$temp_after"
}

assess_transition() {
    from_state="$1"
    to_state="$2"
    violations="$3"

    {
        echo "**Assessment:**"
        echo ""
    } >>"$ANALYSIS_OUTPUT"

    case "${from_state}_to_${to_state}" in
        "up_to_down")
            if [ "$violations" -gt 0 ]; then
                {
                    echo "✅ **JUSTIFIED FAILOVER** - Switched to cellular backup"
                    echo "- Found $violations threshold violations before failover"
                    echo "- System correctly detected quality degradation"
                    echo "- **Timing**: Appropriate"
                } >>"$ANALYSIS_OUTPUT"
            else
                {
                    echo "⚠️ **QUESTIONABLE FAILOVER** - Switched to cellular backup"
                    echo "- No clear threshold violations detected"
                    echo "- May have been triggered by transient issues"
                    echo "- **Recommendation**: Review threshold sensitivity"
                } >>"$ANALYSIS_OUTPUT"
            fi
            ;;
        "down_to_up")
            {
                echo "✅ **FAILBACK TO STARLINK** - Restored primary connection"
                echo "- System detected improved Starlink quality"
                echo "- Cellular backup successfully maintained connectivity"
                echo "- **Timing**: Normal failback procedure"
            } >>"$ANALYSIS_OUTPUT"
            ;;
        *)
            {
                echo "ℹ️ **UNKNOWN TRANSITION** - $from_state to $to_state"
            } >>"$ANALYSIS_OUTPUT"
            ;;
    esac

    echo "" >>"$ANALYSIS_OUTPUT"
}

generate_summary() {
    log_step "Generating analysis summary"

    # Count different types of transitions
    justified=$(grep -c "JUSTIFIED FAILOVER" "$ANALYSIS_OUTPUT" || echo "0")
    questionable=$(grep -c "QUESTIONABLE FAILOVER" "$ANALYSIS_OUTPUT" || echo "0")
    failbacks=$(grep -c "FAILBACK TO STARLINK" "$ANALYSIS_OUTPUT" || echo "0")

    {
        echo ""
        echo "## Executive Summary"
        echo ""
        echo "### Transition Analysis Results"
        echo ""
        echo "| Transition Type | Count | Assessment |"
        echo "|----------------|-------|------------|"
        echo "| Justified Failovers | $justified | ✅ Appropriate |"
        echo "| Questionable Failovers | $questionable | ⚠️ Review needed |"
        echo "| Failbacks to Starlink | $failbacks | ✅ Normal operation |"
        echo ""

        total_failovers=$((justified + questionable))

        if [ "$total_failovers" -gt 0 ]; then
            success_rate=$((justified * 100 / total_failovers))
            {
                echo "### Overall Assessment"
                echo ""
                echo "**Failover Decision Quality**: $success_rate% ($justified/$total_failovers justified)"
                echo ""
            }

            if [ "$success_rate" -ge 80 ]; then
                echo "✅ **EXCELLENT** - Your failover system is making good decisions"
            elif [ "$success_rate" -ge 60 ]; then
                echo "⚠️ **GOOD** - Minor tuning may improve performance"
            else
                echo "❌ **NEEDS IMPROVEMENT** - Review threshold configuration"
            fi
            echo ""
        fi

        echo "### Key Findings"
        echo ""

        if [ "$questionable" -gt 0 ]; then
            echo "- **$questionable questionable failovers detected** - Consider reviewing threshold sensitivity"
        fi

        if [ "$failbacks" -gt 0 ]; then
            echo "- **$failbacks successful failbacks** - System is properly restoring primary connectivity"
        fi

        if [ "$justified" -gt 0 ]; then
            echo "- **$justified justified failovers** - System correctly detected quality issues"
        fi

        echo ""
        echo "### Recommendations"
        echo ""

        if [ "$questionable" -gt 0 ]; then
            {
                echo "1. **Review Threshold Sensitivity**:"
                echo "   - Consider slightly increasing thresholds to reduce false positives"
                echo "   - Implement hysteresis (different thresholds for failover vs recovery)"
                echo ""
            }
        fi

        {
            echo "2. **Monitoring Recommendations**:"
            echo "   - Continue monitoring for patterns in questionable failovers"
            echo "   - Track correlation between environmental factors and false triggers"
            echo "   - Consider implementing predictive failover based on trend analysis"
            echo ""
            echo "3. **System Health**:"
            echo "   - Current failover system is functioning as designed"
            echo "   - Backup connectivity is working effectively"
            echo "   - Consider fine-tuning thresholds based on usage patterns"
        }

    } >>"$ANALYSIS_OUTPUT"
}

# Execute main function
main "$@"
