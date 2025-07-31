#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "analyze-decision-log-rutos.sh" "$SCRIPT_VERSION"

# =============================================================================
# STARLINK DECISION LOG ANALYZER
# =============================================================================
# Analyzes the failover decision log to provide insights into monitoring behavior
# Shows decision patterns, failover frequency, and quality trends

# Default configuration
DECISION_LOG_FILE="${1:-/etc/starlink-logs/failover_decisions.csv}"
HOURS_TO_ANALYZE="${2:-24}"  # Default to last 24 hours
SHOW_ALL="${3:-false}"       # Show all decisions or just summary

# Color formatting for better readability
        echo "analyze-decision-log-rutos.sh v$SCRIPT_VERSION"
        echo ""
show_usage() {
    printf "${BLUE}Usage: %s [decision_log_file] [hours_to_analyze] [show_all]${NC}\n" "$(basename "$0")"
    printf "\n"
    printf "Parameters:\n"
    printf "  decision_log_file   Path to decision log (default: /etc/starlink-logs/failover_decisions.csv)\n"
    printf "  hours_to_analyze    Hours of history to analyze (default: 24)\n"
    printf "  show_all           Show all decisions or summary only (default: false)\n"
    printf "\n"
    printf "Examples:\n"
    printf "  %s                                    # Analyze last 24 hours\n" "$(basename "$0")"
    printf "  %s /tmp/decisions.csv 12             # Analyze last 12 hours\n" "$(basename "$0")"
    printf "  %s /tmp/decisions.csv 48 true        # Show all decisions from last 48 hours\n" "$(basename "$0")"
}

# Check if log file exists
if [ ! -f "$DECISION_LOG_FILE" ]; then
    log_error "Decision log file not found: $DECISION_LOG_FILE"
        echo "analyze-decision-log-rutos.sh v$SCRIPT_VERSION"
        echo ""
    show_usage
    exit 1
fi

log_info "Analyzing Starlink decision log: $DECISION_LOG_FILE"
log_info "Time period: Last $HOURS_TO_ANALYZE hours"

# Calculate cutoff timestamp for analysis period
cutoff_time=$(date -d "$HOURS_TO_ANALYZE hours ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-"$HOURS_TO_ANALYZE"H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")

if [ -z "$cutoff_time" ]; then
    log_warning "Unable to calculate cutoff time, analyzing entire log"
    analysis_data=$(tail -n +2 "$DECISION_LOG_FILE")  # Skip header
else
    log_debug "Cutoff time: $cutoff_time"
    # Filter records newer than cutoff time
    analysis_data=$(awk -F',' -v cutoff="$cutoff_time" 'NR>1 && $1 >= cutoff' "$DECISION_LOG_FILE")
fi

# Count total decisions
total_decisions=$(echo "$analysis_data" | wc -l | tr -d ' ')
if [ "$total_decisions" -eq 0 ]; then
    log_warning "No decisions found in the specified time period"
    exit 0
fi

printf "\n${GREEN}=== STARLINK DECISION LOG ANALYSIS ===${NC}\n"
printf "${BLUE}Analysis Period:${NC} Last %s hours (%s total decisions)\n" "$HOURS_TO_ANALYZE" "$total_decisions"
printf "${BLUE}Log File:${NC} %s\n\n" "$DECISION_LOG_FILE"

# =============================================================================
# DECISION TYPE SUMMARY
# =============================================================================

printf "${YELLOW}📊 DECISION TYPE SUMMARY${NC}\n"
printf "%-20s %-8s %-12s\n" "Decision Type" "Count" "Percentage"
printf "%-20s %-8s %-12s\n" "-------------" "-----" "----------"

echo "$analysis_data" | cut -d',' -f2 | sort | uniq -c | while read count decision_type; do
    percentage=$(awk "BEGIN {printf \"%.1f\", ($count/$total_decisions)*100}")
    printf "%-20s %-8s %-12s%%\n" "$decision_type" "$count" "$percentage"
done
printf "\n"

# =============================================================================
# ACTION RESULTS SUMMARY
# =============================================================================

printf "${YELLOW}⚡ ACTION RESULTS SUMMARY${NC}\n"
printf "%-20s %-8s %-12s\n" "Action Result" "Count" "Percentage"
printf "%-20s %-8s %-12s\n" "-------------" "-----" "----------"

echo "$analysis_data" | cut -d',' -f12 | sort | uniq -c | while read count result; do
    percentage=$(awk "BEGIN {printf \"%.1f\", ($count/$total_decisions)*100}")
    case "$result" in
        "success") color="$GREEN" ;;
        "failed") color="$RED" ;;
        *) color="$NC" ;;
    esac
    printf "${color}%-20s %-8s %-12s%%${NC}\n" "$result" "$count" "$percentage"
done
printf "\n"

# =============================================================================
# TRIGGER REASON ANALYSIS
# =============================================================================

printf "${YELLOW}🔍 TRIGGER REASON ANALYSIS${NC}\n"
printf "%-30s %-8s %-12s\n" "Trigger Reason" "Count" "Percentage"
printf "%-30s %-8s %-12s\n" "--------------" "-----" "----------"

echo "$analysis_data" | cut -d',' -f3 | sort | uniq -c | while read count reason; do
    percentage=$(awk "BEGIN {printf \"%.1f\", ($count/$total_decisions)*100}")
    printf "%-30s %-8s %-12s%%\n" "$reason" "$count" "$percentage"
done
printf "\n"

# =============================================================================
# QUALITY METRICS TRENDS
# =============================================================================

printf "${YELLOW}📈 QUALITY METRICS TRENDS${NC}\n"

# Extract numeric values for analysis (handle unknown/non-numeric values)
latencies=$(echo "$analysis_data" | cut -d',' -f5 | grep -E '^[0-9]+$' || echo "")
packet_losses=$(echo "$analysis_data" | cut -d',' -f6 | grep -E '^[0-9.]+$' || echo "")
obstructions=$(echo "$analysis_data" | cut -d',' -f7 | grep -E '^[0-9.]+$' || echo "")

if [ -n "$latencies" ]; then
    latency_count=$(echo "$latencies" | wc -l | tr -d ' ')
    latency_avg=$(echo "$latencies" | awk '{sum+=$1} END {if(NR>0) printf "%.1f", sum/NR; else print "N/A"}')
    latency_max=$(echo "$latencies" | sort -n | tail -1)
    printf "Latency (ms):      Avg: %s, Max: %s, Samples: %s\n" "$latency_avg" "$latency_max" "$latency_count"
fi

if [ -n "$packet_losses" ]; then
    loss_count=$(echo "$packet_losses" | wc -l | tr -d ' ')
    loss_avg=$(echo "$packet_losses" | awk '{sum+=$1} END {if(NR>0) printf "%.2f", sum/NR; else print "N/A"}')
    loss_max=$(echo "$packet_losses" | sort -n | tail -1)
    printf "Packet Loss (%%):   Avg: %s, Max: %s, Samples: %s\n" "$loss_avg" "$loss_max" "$loss_count"
fi

if [ -n "$obstructions" ]; then
    obst_count=$(echo "$obstructions" | wc -l | tr -d ' ')
    obst_avg=$(echo "$obstructions" | awk '{sum+=$1} END {if(NR>0) printf "%.3f", sum/NR; else print "N/A"}')
    obst_max=$(echo "$obstructions" | sort -n | tail -1)
    printf "Obstruction (%%):   Avg: %s, Max: %s, Samples: %s\n" "$obst_avg" "$obst_max" "$obst_count"
fi
printf "\n"

# =============================================================================
# METRIC CHANGES TRACKING
# =============================================================================

printf "${YELLOW}🔄 METRIC CHANGES TRACKING${NC}\n"

# Analyze metric changes
echo "$analysis_data" | awk -F',' '
    $2 ~ /failover/ && $12 == "success" { 
        printf "FAILOVER:  %s | Metric: %s → %s | Reason: %s\n", $1, $9, $10, $3 
    }
    $2 == "restore" && $12 == "success" { 
        printf "RESTORE:   %s | Metric: %s → %s | Reason: %s\n", $1, $9, $10, $3 
    }
    $2 ~ /failover/ && $12 == "failed" { 
        printf "FAILED:    %s | Metric: %s → %s | Reason: %s\n", $1, $9, $10, $3 
    }
' | tail -10  # Show last 10 metric changes

printf "\n"

# =============================================================================
# RECENT DECISIONS (if show_all is true)
# =============================================================================

if [ "$SHOW_ALL" = "true" ]; then
    printf "${YELLOW}📋 RECENT DECISIONS (Last 20)${NC}\n"
    printf "%-19s %-15s %-25s %-10s %-30s\n" "Timestamp" "Type" "Reason" "Result" "Notes"
    printf "%-19s %-15s %-25s %-10s %-30s\n" "---------" "----" "------" "------" "-----"
    
    echo "$analysis_data" | tail -20 | while IFS=',' read timestamp decision_type trigger_reason quality_factors latency packet_loss obstruction snr current_metric new_metric action_taken action_result gps_context cellular_context additional_notes; do
        # Truncate long fields for display
        short_timestamp=$(echo "$timestamp" | cut -c1-19)
        short_type=$(echo "$decision_type" | cut -c1-15)
        short_reason=$(echo "$trigger_reason" | cut -c1-25)
        short_result=$(echo "$action_result" | cut -c1-10)
        short_notes=$(echo "$additional_notes" | cut -c1-30)
        
        # Color code based on result
        case "$action_result" in
            "success") color="$GREEN" ;;
            "failed") color="$RED" ;;
            *) color="$NC" ;;
        esac
        
        printf "${color}%-19s %-15s %-25s %-10s %-30s${NC}\n" "$short_timestamp" "$short_type" "$short_reason" "$short_result" "$short_notes"
    done
    printf "\n"
fi

# =============================================================================
# RECOMMENDATIONS
# =============================================================================

printf "${YELLOW}💡 MONITORING RECOMMENDATIONS${NC}\n"

# Analyze patterns and provide recommendations
failover_count=$(echo "$analysis_data" | grep -c "failover" || echo "0")
restore_count=$(echo "$analysis_data" | grep -c "restore" || echo "0")
failed_count=$(echo "$analysis_data" | grep -c "failed" || echo "0")

if [ "$failover_count" -gt 5 ]; then
    printf "${RED}⚠️  High failover frequency (%s in %s hours) - consider adjusting thresholds${NC}\n" "$failover_count" "$HOURS_TO_ANALYZE"
fi

if [ "$failed_count" -gt 0 ]; then
    printf "${RED}⚠️  %s failed operations detected - check system configuration${NC}\n" "$failed_count"
fi

if [ "$restore_count" -lt "$failover_count" ] && [ "$failover_count" -gt 2 ]; then
    printf "${YELLOW}⚠️  Fewer restores (%s) than failovers (%s) - check restore criteria${NC}\n" "$restore_count" "$failover_count"
fi

# Check for quality patterns
if [ -n "$latencies" ]; then
    high_latency_count=$(echo "$latencies" | awk '$1 > 150 {count++} END {print count+0}')
    if [ "$high_latency_count" -gt 0 ]; then
        printf "${YELLOW}📊 %s high latency events detected - consider network optimization${NC}\n" "$high_latency_count"
    fi
fi

printf "\n${GREEN}Analysis completed. Log file: %s${NC}\n" "$DECISION_LOG_FILE"
printf "${BLUE}💡 Tip: Run with 'show_all=true' to see detailed decision history${NC}\n"
