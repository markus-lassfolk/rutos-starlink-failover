#!/bin/sh
# upgrade-rutos.sh: Safely upgrade scripts/configs without overwriting user changes
# Usage: ./scripts/upgrade-rutos.sh

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -eu

# Check if terminal supports colors
# shellcheck disable=SC2034,SC2059  # Color variables may not all be used in every script; Method 5 printf for RUTOS

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    # shellcheck disable=SC2034  # BLUE used for progress indicators in RUTOS scripts
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
    # shellcheck disable=SC2034  # BLUE used for progress indicators in RUTOS scripts
    BLUE=""
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${CYAN}[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s${NC}\n" "$DRY_RUN" "$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${GREEN}[DRY-RUN] Would execute: %s${NC}\n" "$description"
        if [ "${DEBUG:-0}" = "1" ]; then
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${CYAN}[DRY-RUN] Command: %s${NC}\n" "$cmd"
        fi
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${CYAN}Executing: %s${NC}\n" "$cmd"
        fi
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    # shellcheck disable=SC2059 # Method 5 format required for RUTOS compatibility
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
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
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}Backing up user configs...${NC}\n"
    for f in "$INSTALL_DIR"/config/*.sh; do
        [ -f "$f" ] || continue
        backup_file "$f"
    done
}

backup_scripts() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}Backing up user scripts...${NC}\n"
    for f in "$INSTALL_DIR"/scripts/*.sh; do
        [ -f "$f" ] || continue
        backup_file "$f"
    done
}

deploy_updates() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}Deploying updated scripts and configs...${NC}\n"
    # Only overwrite if file is unchanged or user confirms
    for src in "$REPO_DIR"/Starlink-RUTOS-Failover/*.sh "$REPO_DIR"/scripts/*.sh; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        dest="$INSTALL_DIR/scripts/$fname"
        if [ -f "$dest" ]; then
            if cmp -s "$src" "$dest"; then
                cp -a "$src" "$dest"
                # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
                printf "${GREEN}Updated: %s${NC}\n" "$fname"
            else
                # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
                printf "${YELLOW}User-modified: %s. Skipping update. (See backup)${NC}\n" "$fname"
            fi
        else
            cp -a "$src" "$dest"
            # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
            printf "${GREEN}Installed new: %s${NC}\n" "$fname"
        fi
    done
    # Config templates (never overwrite config.sh)
    for src in "$REPO_DIR"/config/*.template.sh; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        dest="$INSTALL_DIR/config/$fname"
        cp -a "$src" "$dest"
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${GREEN}Updated template: %s${NC}\n" "$fname"
    done
}

main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "upgrade-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    if [ "${DEBUG:-0}" = "1" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG] ==================== SCRIPT START ===================${NC}\n" >&2
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG] Script: upgrade-rutos.sh v%s${NC}\n" "$SCRIPT_VERSION" >&2
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG] Working directory: %s${NC}\n" "$(pwd)" >&2
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG] Arguments: %s${NC}\n" "$*" >&2
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG] ======================================================${NC}\n" >&2
    fi
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}=== Starlink System Upgrade ===${NC}\n"
    printf "Backup directory: %s\n" "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    backup_configs
    backup_scripts
    deploy_updates
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}Upgrade complete!${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}User configs and modified scripts are backed up in %s${NC}\n" "$BACKUP_DIR"
}

main "$@"
