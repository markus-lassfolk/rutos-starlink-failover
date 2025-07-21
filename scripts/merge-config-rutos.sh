#!/bin/sh
# Configuration merging script for Starlink RUTOS Failover
# Version: 2.4.12

# Standard colors for consistent output

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Use version for logging
echo "merge-config-rutos.sh v$SCRIPT_VERSION started" >/dev/null 2>&1 || true
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # shellcheck disable=SC2034
    RED=""
    # shellcheck disable=SC2034
    GREEN=""
    # shellcheck disable=SC2034
    YELLOW=""
    # shellcheck disable=SC2034
    BLUE=""
    # shellcheck disable=SC2034
    CYAN=""
    # shellcheck disable=SC2034
    NC=""
fi

# Function to extract variable value from config file
extract_variable() {
    file="$1"
    var_name="$2"

    if [ -f "$file" ]; then
        grep "^[[:space:]]*export[[:space:]]*${var_name}=" "$file" |
            sed "s/^[[:space:]]*export[[:space:]]*${var_name}=[\"']\?//" |
            sed "s/[\"']\?[[:space:]]*$//" |
            head -n 1
    fi
}

# Function to check if variable exists in file
variable_exists() {
    file="$1"
    var_name="$2"

    if [ -f "$file" ]; then
        grep -q "^[[:space:]]*export[[:space:]]*${var_name}=" "$file"
    else
        return 1
    fi
}

# Function to get all variables from config file
get_all_variables() {
    file="$1"

    if [ -f "$file" ]; then
        grep "^[[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*=" "$file" |
            sed "s/^[[:space:]]*export[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/" |
            sort -u
    fi
}

echo "merge-config.sh loaded successfully"
