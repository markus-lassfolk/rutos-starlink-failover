#!/bin/sh
# shellcheck disable=SC1091 # Dynamic source files
# upgrade.sh: Safely upgrade scripts/configs without overwriting user changes
# Usage: ./scripts/upgrade.sh

set -eu

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

# shellcheck disable=SC2034
BACKUP_DIR="/root/starlink-upgrade-backup-$(date +%Y%m%d_%H%M%S)"
# shellcheck disable=SC2034
INSTALL_DIR="/root/starlink-monitor"
# shellcheck disable=SC2034
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

backup_file() {
	src="$1"
	dest="$BACKUP_DIR${src#"$INSTALL_DIR"}"
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
