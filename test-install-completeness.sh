#!/bin/sh
# Test script to verify all RUTOS scripts are included in install-rutos.sh
# shellcheck disable=SC2034  # Colors may appear unused but are used in printf

set -e

# Colors for output (RUTOS-compatible detection)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Enable colors if in a terminal and colors are supported
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

printf "%b=== RUTOS SCRIPTS INSTALLATION VERIFICATION TEST ===%b\n" "$BLUE" "$NC"

# Get list of all RUTOS scripts in the scripts directory
printf "%b[INFO]%b Scanning scripts directory for RUTOS scripts...\n" "$BLUE" "$NC"
available_scripts=$(find scripts -name "*-rutos.sh" -type f | grep -v "install-rutos.sh" | sort)
available_count=$(echo "$available_scripts" | wc -l)

printf "%b[FOUND]%b %s RUTOS scripts available:\n" "$GREEN" "$NC" "$available_count"
echo "$available_scripts" | while read -r script; do
    echo "  - $(basename "$script")"
done

# Extract scripts listed in install-rutos.sh
echo ""
echo "${BLUE}[INFO]${NC} Extracting script lists from install-rutos.sh..."

# Get utility scripts list
utility_scripts=$(grep -A 20 "# Core utility scripts" scripts/install-rutos.sh | grep "\.sh" | sed 's/.*\(.*-rutos\.sh\).*/\1/' | grep -v "placeholder-utils.sh" | sort)
utility_count=$(echo "$utility_scripts" | wc -l)

# Get test scripts list
test_scripts=$(grep -A 15 "# Install test and debug scripts" scripts/install-rutos.sh | grep "\.sh" | sed 's/.*\(.*-rutos\.sh\).*/\1/' | sort)
test_count=$(echo "$test_scripts" | wc -l)

echo "${GREEN}[INSTALL LIST]${NC} Scripts configured for installation:"
echo "${BLUE}Utility scripts ($utility_count):${NC}"
echo "$utility_scripts" | while read -r script; do
    echo "  + $script"
done

echo "${BLUE}Test scripts ($test_count):${NC}"
echo "$test_scripts" | while read -r script; do
    echo "  + $script"
done

# Check for missing scripts
printf "\n"
printf "%b[ANALYSIS]%b Checking for missing scripts...\n" "$BLUE" "$NC"

missing_scripts=""
missing_count=0

# Use a temporary file to avoid subshell issues
temp_missing="/tmp/missing_scripts.$$"
temp_count="/tmp/missing_count.$$"
echo "0" >"$temp_count"
touch "$temp_missing"

# Check each available script against install lists
for script_path in $available_scripts; do
    script_name=$(basename "$script_path")

    # Skip certain scripts that shouldn't be installed
    case "$script_name" in
        "install-rutos.sh" | "test-intelligent-merge-rutos.sh" | "placeholder-utils.sh")
            continue
            ;;
    esac

    # Check if script is in either utility or test list
    if echo "$utility_scripts" | grep -q "^${script_name}$"; then
        printf "%b[✓]%b %s - Found in utility scripts\n" "$GREEN" "$NC" "$script_name"
    elif echo "$test_scripts" | grep -q "^${script_name}$"; then
        printf "%b[✓]%b %s - Found in test scripts\n" "$GREEN" "$NC" "$script_name"
    else
        printf "%b[?]%b %s - NOT FOUND in install lists\n" "$YELLOW" "$NC" "$script_name"
        echo "$script_name" >>"$temp_missing"
        current_count=$(cat "$temp_count")
        echo "$((current_count + 1))" >"$temp_count"
    fi
done

# Read results from temporary files
missing_scripts=$(tr '\n' ' ' <"$temp_missing")
missing_count=$(cat "$temp_count")

# Cleanup temporary files
rm -f "$temp_missing" "$temp_count"

# Summary
echo ""
echo "${BLUE}=== VERIFICATION SUMMARY ===${NC}"
total_in_install=$((utility_count + test_count))
echo "Available RUTOS scripts: $available_count"
echo "Scripts in install lists: $total_in_install"
echo "Missing from install: $missing_count"

if [ "$missing_count" -eq 0 ]; then
    echo "${GREEN}[SUCCESS]${NC} All RUTOS scripts are properly included in install-rutos.sh!"
    exit 0
else
    echo "${YELLOW}[WARNING]${NC} Some scripts may be missing from installation:"
    for script in $missing_scripts; do
        echo "  - $script"
    done
    echo ""
    echo "${BLUE}[RECOMMENDATION]${NC} Review these scripts and add them to install-rutos.sh if needed."
    exit 1
    # Debug version display
    if [ "$DEBUG" = "1" ]; then
        printf "Script version: %s\n" "$SCRIPT_VERSION"
    fi

fi
