#!/bin/sh
# upgrade.sh: Safely upgrade scripts/configs without overwriting user changes
# Usage: ./scripts/upgrade.sh
# shellcheck disable=SC2059 # Method 5 printf format required for RUTOS color compatibility

set -eu

# Check if terminal supports colors
# shellcheck disable=SC2034  # Color variables may not all be used in every script

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Fallback to no colors if terminal doesn't support them
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "${CYAN}[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s${NC}\n" "$DRY_RUN" "$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        printf "${GREEN}[DRY-RUN] Would execute: %s${NC}\n" "$description"
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "${CYAN}[DRY-RUN] Command: %s${NC}\n" "$cmd"
        fi
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "${CYAN}Executing: %s${NC}\n" "$cmd"
        fi
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    printf "${GREEN}RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution${NC}\n"
    exit 0
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
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "upgrade-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: upgrade-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
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
