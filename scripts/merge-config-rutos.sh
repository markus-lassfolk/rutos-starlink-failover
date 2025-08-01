#!/bin/sh
# Configuration merging script for Starlink RUTOS Failover
# Version: 2.7.1
# Description: Unified template configuration merging functions

# Version information (auto-updated by update-version.sh)
# Use version for logging
echo "merge-config-rutos.sh v$SCRIPT_VERSION (unified template support) started" >/dev/null 2>&1 || true
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='[0;31m'
    GREEN='[0;32m'
    YELLOW='[1;33m'
    BLUE='[1;35m'
    CYAN='[0;36m'
    NC='[0m'
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

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    echo "[DEBUG] DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE" >&2
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        echo "[DRY-RUN] Would execute: $description" >&2
        echo "[DRY-RUN] Command: $cmd" >&2
        return 0
    else
        if [ "$DEBUG" = "1" ]; then
            echo "[DEBUG] Executing: $cmd" >&2
        fi
        eval "$cmd"
    fi
}

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
            sed "s/^[[:space:]]*export[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*//" |
            sort -u
    fi
}

echo "merge-config.sh loaded successfully"

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
