#!/bin/sh

# ==============================================================================
# Variable Consistency Checker for RUTOS Starlink Scripts
#
# Version: 2.7.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# This script checks for configuration variable consistency across all scripts,
# particularly focusing on common mismatches that cause runtime errors.
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Count and report variables
check_variable_usage() {
    var_name="$1"
    description="$2"

    printf "%b\n" "${BLUE}Checking %s usage...${NC}" "$description"

    total_count=0
    # Use command substitution instead of pipe to avoid subshell
    for script in $(find . -name "*.sh" -type f 2>/dev/null); do
        count=$(grep -c "$var_name" "$script" 2>/dev/null || echo 0)
        if [ "$count" -gt 0 ]; then
            printf "  %s: %d occurrences\n" "$script" "$count"
            total_count=$((total_count + count))
        fi
    done

    printf "%b\n" "${GREEN}Total %s occurrences: %d${NC}\n" "$description" "$total_count"
    echo "$total_count"
}

# Check for specific inconsistencies
check_grpcurl_consistency() {
    printf "%b\n" "${YELLOW}=== GRPCURL Variable Consistency Check ===${NC}\n"

    # Count usage of each variant
    grpcurl_cmd_count=$(check_variable_usage "GRPCURL_CMD" "GRPCURL_CMD")
    grpcurl_path_count=$(check_variable_usage "GRPCURL_PATH" "GRPCURL_PATH")

    # Analyze results
    if [ "$grpcurl_path_count" -gt 0 ] && [ "$grpcurl_cmd_count" -gt 0 ]; then
        printf "%b\n" "${RED}CRITICAL: Mixed usage of GRPCURL_CMD and GRPCURL_PATH detected!${NC}"
        printf "%b\n" "${YELLOW}Configuration files should export one consistent variable.${NC}"
        printf "%b\n" "${YELLOW}Recommendation: Use GRPCURL_CMD (used %d times vs GRPCURL_PATH %d times)${NC}\n" "$grpcurl_cmd_count" "$grpcurl_path_count"
        return 1
    elif [ "$grpcurl_cmd_count" -gt 0 ]; then
        printf "%b\n" "${GREEN}✓ Consistent usage of GRPCURL_CMD found${NC}\n"
        return 0
    elif [ "$grpcurl_path_count" -gt 0 ]; then
        printf "%b\n" "${YELLOW}Found only GRPCURL_PATH usage - ensure config exports this variable${NC}\n"
        return 0
    else
        printf "%b\n" "${YELLOW}No GRPCURL variables found${NC}\n"
        return 0
    fi
}

# Check for DRY_RUN variable handling
check_dry_run_consistency() {
    printf "%b\n" "${YELLOW}=== DRY_RUN Variable Handling Check ===${NC}\n"

    # Look for scripts that capture DRY_RUN before assignment
    scripts_with_capture=0
    scripts_with_dry_run=0

    # Use command substitution instead of pipe to avoid subshell
    for script in $(find . -name "*unified*.sh" -type f 2>/dev/null); do
        if grep -q "DRY_RUN" "$script" 2>/dev/null; then
            scripts_with_dry_run=$((scripts_with_dry_run + 1))
            printf "  Found DRY_RUN usage in: %s\n" "$script"

            if grep -q "ORIGINAL_DRY_RUN" "$script" 2>/dev/null; then
                scripts_with_capture=$((scripts_with_capture + 1))
                printf "    ✓ Captures original value for debug output\n"
            else
                printf "    ⚠ May have debug display issues\n"
            fi
        fi
    done

    if [ "$scripts_with_dry_run" -gt 0 ]; then
        printf "\n%b\n" "${GREEN}Found %d scripts with DRY_RUN support${NC}" "$scripts_with_dry_run"
        if [ "$scripts_with_capture" -lt "$scripts_with_dry_run" ]; then
            printf "%b\n" "${YELLOW}%d scripts may have DRY_RUN debug display issues${NC}\n" "$((scripts_with_dry_run - scripts_with_capture))"
        else
            printf "%b\n" "${GREEN}All scripts properly handle DRY_RUN debug output${NC}\n"
        fi
    else
        printf "%b\n" "${BLUE}No unified scripts with DRY_RUN found${NC}\n"
    fi
}

# Check for common variable mismatches
check_common_mismatches() {
    printf "%b\n" "${YELLOW}=== Common Variable Mismatch Check ===${NC}\n"

    # Common variable pairs that should be consistent
    common_vars="JQ_CMD STARLINK_IP STARLINK_PORT LOG_DIR STATE_DIR"

    for var in $common_vars; do
        count=$(find . -name "*.sh" -type f -exec grep -l "$var" {} \; 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            printf "  %s: used in %d scripts\n" "$var" "$count"
        fi
    done

    printf "\n%b\n" "${GREEN}✓ Common variable usage analysis complete${NC}\n"
}

# Main execution
main() {
    printf "%b\n" "${BLUE}RUTOS Starlink Variable Consistency Checker v%s${NC}\n" "$SCRIPT_VERSION"
    printf "%b\n" "${BLUE}======================================================${NC}\n\n"

    # Change to script directory for relative path searches
    cd "$(dirname "$0")/.." || exit 1

    issues_found=0

    # Run all checks
    if ! check_grpcurl_consistency; then
        issues_found=$((issues_found + 1))
    fi

    check_dry_run_consistency
    check_common_mismatches

    # Summary
    printf "%b\n" "${BLUE}=== SUMMARY ===${NC}"
    if [ "$issues_found" -eq 0 ]; then
        printf "%b\n" "${GREEN}✓ No critical variable consistency issues found${NC}"
        exit 0
    else
        printf "%b\n" "${RED}✗ Found %d critical variable consistency issues${NC}" "$issues_found"
        printf "%b\n" "${YELLOW}Please review and fix the issues above${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
