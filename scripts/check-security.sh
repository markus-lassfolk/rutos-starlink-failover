#!/bin/bash
# check-security.sh: Checks file permissions, hardcoded secrets, and config values
# Usage: ./scripts/check-security.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
      failures=$((failures+1))
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
      failures=$((failures+1))
    else
      echo "${GREEN}OK:${NC} $f permissions are 755"
    fi
  done
}

# 2. Check for hardcoded secrets
check_secrets() {
  echo "Checking for hardcoded secrets..."
  # Look for likely secret patterns, ignore placeholders
  grep -r -n -i --exclude-dir=.git --exclude=*.md --exclude=*.json \
    "password\|secret\|token\|key" . | \
    grep -v "YOUR_" | grep -v "PLACEHOLDER" | grep -v "example" && {
      echo "${RED}FAIL:${NC} Potential hardcoded secrets found above."
      failures=$((failures+1))
    } || {
      echo "${GREEN}OK:${NC} No hardcoded secrets detected."
    }
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
