#!/bin/bash
# self-update.sh: Checks for new version and updates scripts if needed
# Usage: ./scripts/self-update.sh

set -euo pipefail

REPO_URL="https://github.com/markus-lassfolk/rutos-starlink-victron"
RAW_URL="https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-victron/main"
INSTALL_DIR="/root/starlink-monitor"
VERSION_FILE="$INSTALL_DIR/VERSION"
TMP_VERSION="/tmp/starlink-latest-version.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_local_version() {
  [ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "0.0.0"
}

get_remote_version() {
  curl -fsSL "$RAW_URL/VERSION" -o "$TMP_VERSION" && cat "$TMP_VERSION" || echo "0.0.0"
}

version_gt() {
  # Returns 0 if $1 > $2
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

main() {
  echo "Checking for updates..."
  local_version=$(get_local_version)
  remote_version=$(get_remote_version)
  echo "Local version: $local_version"
  echo "Remote version: $remote_version"
  if version_gt "$remote_version" "$local_version"; then
    echo "${YELLOW}Update available!${NC}"
    echo "Run: $INSTALL_DIR/scripts/upgrade.sh to update."
    exit 2
  else
    echo "${GREEN}You are up to date.${NC}"
    exit 0
  fi
}

main "$@"
