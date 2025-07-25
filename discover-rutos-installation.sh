#!/bin/sh
# RUTOS Installation Discovery Script
# This script finds what Starlink monitoring scripts are currently installed

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# Colors for output (RUTOS compatible)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    NC='\033[0m'
else
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_found() {
    printf "${GREEN}[FOUND]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_missing() {
    printf "${YELLOW}[MISSING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

printf "%s================================================%s\n" "$BLUE" "$NC"
printf "%s      RUTOS Starlink Installation Discovery%s\n" "$BLUE" "$NC"
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "\n"

log_info "Scanning for Starlink monitoring installation..."
log_info "Router: $(uname -a 2>/dev/null || echo 'Unknown')"
log_info "Current user: $(whoami 2>/dev/null || id -un 2>/dev/null || echo 'Unknown')"
printf "\n"

# Check common installation directories
INSTALL_DIRS="/usr/local/starlink-monitor /opt/starlink /root/starlink /tmp/starlink"
CONFIG_DIRS="/etc/starlink-config /root/.starlink /opt/starlink/config"

log_step "Checking installation directories"
for dir in $INSTALL_DIRS; do
    if [ -d "$dir" ]; then
        log_found "Directory exists: $dir"
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            log_info "  Contents: $(ls -la "$dir" 2>/dev/null | wc -l) items"
            ls -la "$dir" 2>/dev/null | head -10
        else
            log_missing "  Directory is empty"
        fi
    else
        log_missing "Directory not found: $dir"
    fi
done

printf "\n"
log_step "Checking configuration directories"
for dir in $CONFIG_DIRS; do
    if [ -d "$dir" ]; then
        log_found "Config directory exists: $dir"
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            log_info "  Contents:"
            ls -la "$dir" 2>/dev/null
        else
            log_missing "  Directory is empty"
        fi
    else
        log_missing "Config directory not found: $dir"
    fi
done

printf "\n"
log_step "Searching for Starlink scripts system-wide"
SCRIPT_NAMES="starlink_monitor starlink_logger check_starlink_api"

for script_name in $SCRIPT_NAMES; do
    log_info "Searching for: *${script_name}*"

    # Search in common locations
    found_files=""
    for search_dir in /usr/local /opt /root /tmp /etc /usr/bin /usr/sbin; do
        if [ -d "$search_dir" ]; then
            found=$(find "$search_dir" -name "*${script_name}*" -type f 2>/dev/null || true)
            if [ -n "$found" ]; then
                found_files="$found_files $found"
            fi
        fi
    done

    if [ -n "$found_files" ]; then
        for file in $found_files; do
            log_found "Found: $file"
            if [ -x "$file" ]; then
                log_info "  Executable: YES"
            else
                log_missing "  Executable: NO"
            fi
            log_info "  Size: $(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo 'Unknown')"
        done
    else
        log_missing "No files found for: $script_name"
    fi
done

printf "\n"
log_step "Checking crontab for Starlink jobs"
if crontab -l >/dev/null 2>&1; then
    starlink_crons=$(crontab -l 2>/dev/null | grep -i starlink || true)
    if [ -n "$starlink_crons" ]; then
        log_found "Starlink cron jobs found:"
        echo "$starlink_crons" | while read -r line; do
            log_info "  $line"
        done
    else
        log_missing "No Starlink cron jobs found"
    fi
else
    log_missing "No crontab found or cannot access"
fi

printf "\n"
log_step "Checking for running Starlink processes"
starlink_processes=$(ps aux 2>/dev/null | grep -i starlink | grep -v grep || true)
if [ -n "$starlink_processes" ]; then
    log_found "Starlink processes running:"
    echo "$starlink_processes" | while read -r line; do
        log_info "  $line"
    done
else
    log_missing "No Starlink processes currently running"
fi

printf "\n"
log_step "Checking system logs for Starlink entries"
starlink_logs=$(logread 2>/dev/null | grep -i starlink | tail -5 || true)
if [ -n "$starlink_logs" ]; then
    log_found "Recent Starlink log entries:"
    echo "$starlink_logs" | while read -r line; do
        log_info "  $line"
    done
else
    log_missing "No recent Starlink log entries found"
fi

printf "\n"
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "%s              DISCOVERY COMPLETE%s\n" "$BLUE" "$NC"
printf "%s================================================%s\n" "$BLUE" "$NC"
printf "\n"

log_info "Discovery completed!"
log_info "If no Starlink installation was found, you may need to run the installer first:"
log_info "curl -fsSL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/install-rutos.sh | sh"
printf "\n"
