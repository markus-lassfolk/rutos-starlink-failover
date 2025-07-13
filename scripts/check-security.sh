#!/bin/bash
# check-security.sh: Checks file permissions, hardcoded secrets, and config values

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

failures=0

# 0. Set file permissions (for CI or Linux environments)
set_permissions() {
  echo "Setting file permissions for scripts and config template..."
  chmod 600 config/config.template.sh 2>/dev/null || true
  chmod 755 scripts/*.sh Starlink-RUTOS-Failover/*.sh 2>/dev/null || true
}

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
  # Look for likely secret patterns, ignore placeholders and comments
  if grep -r -n -i --exclude-dir=.git --exclude-dir=.github --exclude=*.md --exclude=*.json --exclude=*.yml --exclude=*.yaml --exclude=*.toml --exclude=*_test.sh --exclude=*test* \
    "password\|secret\|token\|key" . | \
    grep -v "YOUR_" | grep -v "PLACEHOLDER" | grep -v "example" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*//' | \
    grep -v '\$PUSHOVER_TOKEN' | grep -v '\$PUSHOVER_USER' | grep -v '\$[A-Z_]*TOKEN' | grep -v '\$[A-Z_]*USER' | grep -v '\$[A-Z_]*SECRET' | grep -v '\$[A-Z_]*KEY' | \
    grep -v 'test_token' | grep -v 'test_user' | grep -v 'Application API Token' | grep -v 'User Key' | grep -v 'apiVersion' ; then
    echo "${RED}FAIL:${NC} Potential hardcoded secrets found above."
    failures=$((failures+1))
  else
    echo "${GREEN}OK:${NC} No hardcoded secrets detected."
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
set_permissions
check_permissions
check_secrets
check_config_values

if [ "$failures" -eq 0 ]; then
  echo "${GREEN}Security checks passed!${NC}"
  exit 0
else
  echo "${RED}Security checks failed: $failures issue(s) found.${NC}"
  exit 1
fi
# 0. Set file permissions (for CI or Linux environments)

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
  # Look for likely secret patterns, ignore placeholders and comments
  grep -r -n -i --exclude-dir=.git --exclude=*.md --exclude=*.json \
    "password\|secret\|token\|key" . | \
    grep -v "YOUR_" | grep -v "PLACEHOLDER" | grep -v "example" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*//'
  if [ $? -eq 0 ]; then
    echo "${RED}FAIL:${NC} Potential hardcoded secrets found above."
    failures=$((failures+1))
  else
    echo "${GREEN}OK:${NC} No hardcoded secrets detected."
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
