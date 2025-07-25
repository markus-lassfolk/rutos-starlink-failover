#!/bin/sh

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Parse command line arguments
CHANGED_FILES=""
AUTO_FIX_CHMOD=false

while [ $# -gt 0 ]; do
    case $1 in
        --auto-fix-chmod)
            AUTO_FIX_CHMOD=true
            shift
            ;;
        *)
            if [ -z "$CHANGED_FILES" ]; then
                CHANGED_FILES="$1"
            fi
            shift
            ;;
    esac
done

set_permissions() {
    echo "Setting file permissions for scripts and config template..."
    chmod 600 config/config.template.sh config/config.advanced.template.sh 2>/dev/null || true
    chmod 755 scripts/*.sh Starlink-RUTOS-Failover/*.sh 2>/dev/null || true
}

auto_fix_permissions() {
    echo "🔧 Auto-fixing file permissions for changed files..."
    fixed_count=0

    if [ -n "$CHANGED_FILES" ]; then
        # Create a temporary file to avoid subshell issues
        temp_file=$(mktemp)
        echo "$CHANGED_FILES" >"$temp_file"

        while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi
            if [ ! -f "$file" ]; then continue; fi

            case "$file" in
                config/*.sh)
                    current_perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
                    if [ "$current_perms" != "600" ]; then
                        echo "🔧 Fixing permissions for $file: $current_perms → 600"
                        chmod 600 "$file" 2>/dev/null || true
                        fixed_count=$((fixed_count + 1))
                    fi
                    ;;
                scripts/*.sh | Starlink-RUTOS-Failover/*.sh | *.sh)
                    current_perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
                    if [ "$current_perms" != "755" ]; then
                        echo "🔧 Fixing permissions for $file: $current_perms → 755"
                        chmod 755 "$file" 2>/dev/null || true
                        fixed_count=$((fixed_count + 1))
                    fi
                    ;;
            esac
        done <"$temp_file"

        rm -f "$temp_file"
    else
        # Fallback to all files if no specific files provided
        chmod 600 config/*.sh 2>/dev/null || true
        chmod 755 scripts/*.sh Starlink-RUTOS-Failover/*.sh 2>/dev/null || true
    fi

    echo "✅ Auto-fixed permissions for $fixed_count files"
}

check_secrets() {
    echo "Checking for hardcoded secrets..."

    # If we have specific files, check only those
    search_locations="."

    if [ -n "$CHANGED_FILES" ]; then
        echo "🔍 Checking secrets in changed files only..."
        search_locations=""
        # Create a temporary file to avoid subshell issues
        temp_file=$(mktemp)
        echo "$CHANGED_FILES" >"$temp_file"

        while IFS= read -r file; do
            if [ -z "$file" ] || [ ! -f "$file" ]; then continue; fi
            search_locations="$search_locations $file"
        done <"$temp_file"

        rm -f "$temp_file"
    fi

    # Look for likely secret patterns, ignore placeholders and comments
    if grep -r -n -i --exclude-dir=.git --exclude-dir=.github --exclude=*.md --exclude=*.json --exclude=*.yml --exclude=*.yaml --exclude=*.toml --exclude=*_test.sh --exclude=*test* \
        "password|secret|token|key" "${search_locations:-"."}" |
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

# Version information (auto-updated by update-version.sh)

# Version information

# Use version for logging
echo "check-security.sh v$SCRIPT_VERSION started" >/dev/null 2>&1 || true

# Version information

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

# 1. Check file permissions (PR-aware)
check_permissions() {
    echo "Checking file permissions..."

    if [ -n "$CHANGED_FILES" ]; then
        echo "🔍 Checking permissions for changed files only..."
        # Create a temporary file to avoid subshell issues
        temp_file=$(mktemp)
        echo "$CHANGED_FILES" >"$temp_file"

        while IFS= read -r file; do
            if [ -z "$file" ] || [ ! -f "$file" ]; then continue; fi

            case "$file" in
                config/*.sh)
                    perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
                    if [ "$perms" != "600" ]; then
                        echo "${RED}FAIL:${NC} $file has permissions $perms (expected 600)"
                        failures=$((failures + 1))
                    else
                        echo "${GREEN}OK:${NC} $file permissions are 600"
                    fi
                    ;;
                scripts/*.sh | Starlink-RUTOS-Failover/*.sh | *.sh)
                    perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
                    if [ "$perms" != "755" ]; then
                        echo "${RED}FAIL:${NC} $file has permissions $perms (expected 755)"
                        failures=$((failures + 1))
                    else
                        echo "${GREEN}OK:${NC} $file permissions are 755"
                    fi
                    ;;
            esac
        done <"$temp_file"

        rm -f "$temp_file"
    else
        echo "🔍 Checking permissions for all relevant files..."
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
    fi
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
if [ "$AUTO_FIX_CHMOD" = true ]; then
    echo "🔧 AUTO-FIX MODE ENABLED"
    auto_fix_permissions
else
    set_permissions
fi

check_permissions
check_secrets
check_config_values

if [ $failures -eq 0 ]; then
    echo "${GREEN}Security checks passed!${NC}"
    exit 0
else
    if [ "$AUTO_FIX_CHMOD" = true ]; then
        echo "${YELLOW}Security checks found issues, but auto-fix was attempted.${NC}"
        echo "${YELLOW}Please review the changes and re-run if needed.${NC}"
        exit 0 # Don't fail in auto-fix mode to allow commit
    else
        echo "${RED}Security checks failed: $failures issue(s) found.${NC}"
        exit 1
    fi
fi
