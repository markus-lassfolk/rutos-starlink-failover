#!/bin/sh
# upgrade.sh: Safely upgrade scripts/configs without overwriting user changes
# Usage: ./scripts/upgrade.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BACKUP_DIR="/root/starlink-upgrade-backup-$(date +%Y%m%d_%H%M%S)"
INSTALL_DIR="/root/starlink-monitor"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

backup_file() {
  src="$1"
  dest="$BACKUP_DIR${src#$INSTALL_DIR}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

backup_configs() {
  echo "${YELLOW}Backing up user configs...${NC}"
  for f in "$INSTALL_DIR"/config/*.sh; do
    [ -f "$f" ] || continue
    backup_file "$f"
  done
}

backup_scripts() {
  echo "${YELLOW}Backing up user scripts...${NC}"
  for f in "$INSTALL_DIR"/scripts/*.sh; do
    [ -f "$f" ] || continue
    backup_file "$f"
  done
}

deploy_updates() {
  echo "${GREEN}Deploying updated scripts and configs...${NC}"
  # Only overwrite if file is unchanged or user confirms
  for src in "$REPO_DIR"/Starlink-RUTOS-Failover/*.sh "$REPO_DIR"/scripts/*.sh; do
    [ -f "$src" ] || continue
    fname="$(basename "$src")"
    dest="$INSTALL_DIR/scripts/$fname"
    if [ -f "$dest" ]; then
      if cmp -s "$src" "$dest"; then
        cp -a "$src" "$dest"
        echo "${GREEN}Updated: $fname${NC}"
      else
        echo "${YELLOW}User-modified: $fname. Skipping update. (See backup)${NC}"
      fi
    else
      cp -a "$src" "$dest"
      echo "${GREEN}Installed new: $fname${NC}"
    fi
  done
  # Config templates (never overwrite config.sh)
  for src in "$REPO_DIR"/config/*.template.sh; do
    [ -f "$src" ] || continue
    fname="$(basename "$src")"
    dest="$INSTALL_DIR/config/$fname"
    cp -a "$src" "$dest"
    echo "${GREEN}Updated template: $fname${NC}"
  done
}

main() {
  echo "${GREEN}=== Starlink System Upgrade ===${NC}"
  echo "Backup directory: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  backup_configs
  backup_scripts
  deploy_updates
  echo "${GREEN}Upgrade complete!${NC}"
  echo "${YELLOW}User configs and modified scripts are backed up in $BACKUP_DIR${NC}"
}

main "$@"
