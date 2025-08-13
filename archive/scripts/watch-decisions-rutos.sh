#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/../lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "watch-decisions-rutos.sh" "$SCRIPT_VERSION"

# =============================================================================
# STARLINK DECISION LOG REAL-TIME VIEWER
# =============================================================================
# Real-time monitoring of failover decisions with formatted output

# Default configuration
DECISION_LOG_FILE="${1:-/etc/starlink-logs/failover_decisions.csv}"
REFRESH_INTERVAL="${2:-5}" # Default refresh every 5 seconds

show_usage() {
    printf "${BLUE}Usage: %s [decision_log_file] [refresh_interval]${NC}\n" "$(basename "$0")"
    printf "\n"
    printf "Parameters:\n"
    printf "  decision_log_file   Path to decision log (default: /etc/starlink-logs/failover_decisions.csv)\n"
    printf "  refresh_interval    Seconds between updates (default: 5)\n"
    printf "\n"
    printf "Controls:\n"
    printf "  Ctrl+C             Exit viewer\n"
    printf "\n"
    printf "Examples:\n"
    printf "  %s                                    # Watch with 5 second refresh\n" "$(basename "$0")"
    printf "  %s /tmp/decisions.csv 2             # Watch with 2 second refresh\n" "$(basename "$0")"
}

# Check if log file exists
if [ ! -f "$DECISION_LOG_FILE" ]; then
    log_error "Decision log file not found: $DECISION_LOG_FILE"
    show_usage
    exit 1
fi

log_info "Watching Starlink decision log: $DECISION_LOG_FILE"
log_info "Refresh interval: $REFRESH_INTERVAL seconds"
log_info "Press Ctrl+C to exit"

# Function to format and display recent decisions
show_recent_decisions() {
    clear
    printf "${GREEN}=== STARLINK DECISION LOG VIEWER ===${NC}\n"
    printf "${BLUE}File:${NC} %s\n" "$DECISION_LOG_FILE"
    printf "${BLUE}Updated:${NC} %s\n" "$(date)"
    printf "${BLUE}Refresh:${NC} Every %s seconds\n\n" "$REFRESH_INTERVAL"

    # Check if file has content
    if [ ! -s "$DECISION_LOG_FILE" ]; then
        printf "${YELLOW}No decisions logged yet...${NC}\n"
        return
    fi

    # Show last 15 decisions with formatting
    printf "${YELLOW}📋 RECENT DECISIONS (Last 15)${NC}\n"
    printf "%-19s %-12s %-20s %-7s %-8s %-6s %-6s %-30s\n" "Timestamp" "Type" "Reason" "Result" "Latency" "Loss%" "Obst%" "Notes"
    printf "%-19s %-12s %-20s %-7s %-8s %-6s %-6s %-30s\n" "---------" "----" "------" "------" "-------" "-----" "-----" "-----"

    tail -n +2 "$DECISION_LOG_FILE" | tail -15 | while IFS=',' read timestamp decision_type trigger_reason quality_factors latency packet_loss obstruction snr current_metric new_metric action_taken action_result gps_context cellular_context additional_notes; do
        # Format timestamp
        short_timestamp=$(echo "$timestamp" | cut -c12-19) # Show only time part

        # Truncate and format fields
        short_type=$(echo "$decision_type" | cut -c1-12)
        short_reason=$(echo "$trigger_reason" | cut -c1-20)
        short_result=$(echo "$action_result" | cut -c1-7)
        short_latency=$(echo "$latency" | cut -c1-8)
        short_loss=$(echo "$packet_loss" | cut -c1-6)
        short_obst=$(echo "$obstruction" | cut -c1-6)
        short_notes=$(echo "$additional_notes" | cut -c1-30)

        # Color code based on decision type and result
        case "$decision_type" in
            "evaluation")
                if [ "$action_result" = "completed" ]; then
                    color="$NC"
                else
                    color="$BLUE"
                fi
                ;;
            "soft_failover") color="$YELLOW" ;;
            "hard_failover") color="$RED" ;;
            "restore") color="$GREEN" ;;
            "maintenance") color="$CYAN" ;;
            *) color="$NC" ;;
        esac

        # Add result color overlay
        case "$action_result" in
            "failed") color="$RED" ;;
        esac

        printf "${color}%-19s %-12s %-20s %-7s %-8s %-6s %-6s %-30s${NC}\n" "$short_timestamp" "$short_type" "$short_reason" "$short_result" "$short_latency" "$short_loss" "$short_obst" "$short_notes"
    done

    printf "\n"

    # Show current system status
    printf "${YELLOW}📊 CURRENT STATUS${NC}\n"

    # Get current MWAN3 metric if possible
    if command -v uci >/dev/null 2>&1; then
        current_metric=$(uci get mwan3.starlink.metric 2>/dev/null || echo "unknown")
        printf "Current Starlink Metric: %s\n" "$current_metric"

        # Interpret metric status
        if [ "$current_metric" != "unknown" ]; then
            if [ "$current_metric" -eq 1 ] 2>/dev/null; then
                printf "Status: ${GREEN}PRIMARY (Active)${NC}\n"
            elif [ "$current_metric" -gt 1 ] 2>/dev/null; then
                printf "Status: ${YELLOW}BACKUP (Failover Active)${NC}\n"
            else
                printf "Status: ${BLUE}Unknown metric value${NC}\n"
            fi
        fi
    fi

    # Show decision statistics
    if [ -s "$DECISION_LOG_FILE" ]; then
        total_decisions=$(tail -n +2 "$DECISION_LOG_FILE" | wc -l | tr -d ' ')
        last_hour_decisions=$(tail -n +2 "$DECISION_LOG_FILE" | awk -v cutoff="$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '')" '$1 > cutoff' | wc -l | tr -d ' ')

        printf "Total Decisions: %s\n" "$total_decisions"
        if [ -n "$last_hour_decisions" ]; then
            printf "Last Hour: %s decisions\n" "$last_hour_decisions"
        fi
    fi

    printf "\n${BLUE}Press Ctrl+C to exit...${NC}\n"
}

# Set up signal handler for clean exit
trap 'printf "\n${GREEN}Decision log viewer stopped.${NC}\n"; exit 0' INT TERM

# Main monitoring loop
while true; do
    show_recent_decisions
    sleep "$REFRESH_INTERVAL"
done
