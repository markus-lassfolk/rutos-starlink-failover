#!/bin/sh
# RUTOS Installation Discovery Script
# This script finds what Starlink monitoring scripts are currently installed

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Colors for output (RUTOS compatible)
# shellcheck disable=SC2034  # Colors are defined as a standard set for project consistency
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
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
printf "%s                   v%s%s\n" "$BLUE" "$SCRIPT_VERSION" "$NC"
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
            # Count items in directory using find instead of ls | wc -l
            item_count=$(find "$dir" -maxdepth 1 -type f -o -type d | grep -vc "^$dir$")
            log_info "  Contents: $item_count items"
            # Use find to list directory contents instead of ls
            find "$dir" -maxdepth 1 -type f -o -type d | grep -v "^$dir$" | head -10 | while read -r item; do
                log_info "    $(basename "$item")"
            done
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
            # Use stat instead of ls to get file size
            file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            # Convert to human readable format
            if [ "$file_size" -ge 1048576 ]; then
                size_display="$((file_size / 1048576))M"
            elif [ "$file_size" -ge 1024 ]; then
                size_display="$((file_size / 1024))K"
            else
                size_display="${file_size}B"
            fi
            log_info "  Size: $size_display"
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
# Use pgrep instead of ps aux | grep for better process detection
if starlink_pids=$(pgrep -f "starlink" 2>/dev/null); then
    log_found "Starlink processes running:"
    for pid in $starlink_pids; do
        # Get process details for each PID
        if ps_line=$(ps -p "$pid" -o pid,user,command 2>/dev/null | tail -n +2); then
            log_info "  $ps_line"
        fi
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
