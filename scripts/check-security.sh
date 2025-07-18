#!/bin/sh

set_permissions() {
    echo "Setting file permissions for scripts and config template..."
    chmod 600 config/config.template.sh config/config.advanced.template.sh 2>/dev/null || true
    chmod 755 scripts/*.sh Starlink-RUTOS-Failover/*.sh 2>/dev/null || true
}

check_secrets() {
    echo "Checking for hardcoded secrets..."
    # Look for likely secret patterns, ignore placeholders and comments
    if grep -r -n -i --exclude-dir=.git --exclude-dir=.github --exclude=*.md --exclude=*.json --exclude=*.yml --exclude=*.yaml --exclude=*.toml --exclude=*_test.sh --exclude=*test* \
        "password|secret|token|key" . |
        grep -v "scripts/check-security.sh" |
        grep -v "^[[:space:]]*#" | grep -v "^[[:space:]]*//" |
        grep -v "YOUR_PUSHOVER_API_TOKEN" | grep -v "YOUR_PUSHOVER_USER_KEY" |
        grep -v 'PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"' | grep -v 'PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"' |
        grep -v "YOUR_" | grep -v "PLACEHOLDER" | grep -v "example" |
        grep -vE '\$[A-Z_]+(TOKEN|USER|SECRET|KEY)' |
        grep -v "test_token" | grep -v "test_user" | grep -v "Application API Token" | grep -v "User Key" | grep -v "apiVersion" |
        grep -v "Replace this placeholder" | grep -v "actual token" | grep -v "actual key" |
        grep -vE "placeholder|dummy|not.*a.*real.*secret"; then
        printf "%bFAIL:%b Potential hardcoded secrets found above.\n" "$RED" "$NC"
        failures=$((failures + 1))
    else
        printf "%bOK:%b No hardcoded secrets detected.\n" "$GREEN" "$NC"
    fi
}

# check-security.sh: Checks file permissions, hardcoded secrets, and config values

set -e

# Check if terminal supports colors
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Fallback to no colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

failures=0

# 1. Check file permissions
check_permissions() {
    echo "Checking file permissions..."
    # Config files should be 600
    for f in config/*.sh; do
        [ -f "$f" ] || continue
        perms=$(stat -c "%a" "$f")
        if [ "$perms" != "600" ]; then
            echo "${RED}FAIL:${NC} $f has permissions $perms (expected 600)"
            failures=$((failures + 1))
        else
            echo "${GREEN}OK:${NC} $f permissions are 600"
        fi
    done
    # Scripts should be 755
    for f in scripts/*.sh Starlink-RUTOS-Failover/*.sh; do
        [ -f "$f" ] || continue
        perms=$(stat -c "%a" "$f")
        if [ "$perms" != "755" ]; then
            echo "${RED}FAIL:${NC} $f has permissions $perms (expected 755)"
            failures=$((failures + 1))
        else
            echo "${GREEN}OK:${NC} $f permissions are 755"
        fi
    done
}

# 3. Check config values for secure defaults
check_config_values() {
    echo "Checking config values for secure defaults..."
    for f in config/*.sh; do
        [ -f "$f" ] || continue
        if grep -q 'PUSHOVER_TOKEN="your_pushover_token"' "$f"; then
            echo "${YELLOW}WARN:${NC} $f has default pushover token."
        fi
        if grep -q 'PUSHOVER_USER="your_pushover_user_key"' "$f"; then
            echo "${YELLOW}WARN:${NC} $f has default pushover user key."
        fi
    done
}

# Call all checks at the very end
set_permissions
check_permissions
check_secrets
check_config_values

if [ $failures -eq 0 ]; then
    echo "${GREEN}Security checks passed!${NC}"
    exit 0
else
    echo "${RED}Security checks failed: $failures issue(s) found.${NC}"
    exit 1
fi
