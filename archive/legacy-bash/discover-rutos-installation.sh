#!/bin/sh
# RUTOS Installation Discovery Script
# This script finds what Starlink monitoring scripts are currently installed

set -e

# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="2.7.1"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "discover-rutos-installation.sh" "$SCRIPT_VERSION"

# === DEBUG AND TESTING VARIABLES ===
# Support standard variables
DEBUG="${DEBUG:-0}"
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Early exit for test mode
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    log_info "TEST_MODE enabled - exiting early"
    exit 0
fi

log_info "Scanning for Starlink monitoring installation..."
log_info "Router: $(uname -a 2>/dev/null || echo 'Unknown')"
log_info "Current user: $(whoami 2>/dev/null || id -un 2>/dev/null || echo 'Unknown')"
printf "\n"

# Check common installation directories
INSTALL_DIRS="/usr/local/starlink-monitor /usr/local/starlink /root/starlink /tmp/starlink"
CONFIG_DIRS="/etc/starlink-config /root/.starlink /usr/local/starlink/config"

log_step "Checking installation directories"
for dir in $INSTALL_DIRS; do
    if [ -d "$dir" ]; then
        log_success "Directory exists: $dir"
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            # Count items in directory using find instead of ls | wc -l
            item_count=$(find "$dir" -maxdepth 1 -type f -o -type d | grep -vc "^$dir$")
            log_info "  Contents: $item_count items"
            # Use find to list directory contents instead of ls
            find "$dir" -maxdepth 1 -type f -o -type d | grep -v "^$dir$" | head -10 | while read -r item; do
                log_info "    $(basename "$item")"
            done
        else
            log_warning "  Directory is empty"
        fi
    else
        log_missing "Directory not found: $dir"
    fi
done

printf "\n"
log_step "Checking configuration directories"
for dir in $CONFIG_DIRS; do
    if [ -d "$dir" ]; then
        log_success "Config directory exists: $dir"
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            log_info "  Contents:"
            ls -la "$dir" 2>/dev/null
        else
            log_warning "  Directory is empty"
        fi
    else
        log_warning "Config directory not found: $dir"
    fi
done

printf "\n"
log_step "Searching for Starlink scripts system-wide"
SCRIPT_NAMES="starlink_monitor starlink_logger check_starlink_api"

for script_name in $SCRIPT_NAMES; do
    log_info "Searching for: *${script_name:-unknown}*"

    # Search in common locations
    found_files=""
    for search_dir in /usr/local /opt /root /tmp /etc /usr/bin /usr/sbin; do
        if [ -d "$search_dir" ]; then
            found=$(find "$search_dir" -name "*${script_name:-unknown}*" -type f 2>/dev/null || true)
            if [ -n "$found" ]; then
                found_files="$found_files $found"
            fi
        fi
    done

    if [ -n "$found_files" ]; then
        for file in $found_files; do
            log_success "Found: $file"
            if [ -x "$file" ]; then
                log_info "  Executable: YES"
            else
                log_warning "  Executable: NO"
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
        log_warning "No files found for: ${script_name:-unknown}"
    fi
done

printf "\n"
log_step "Checking crontab for Starlink jobs"
if smart_safe_execute "crontab -l >/dev/null 2>&1"; then
    starlink_crons=$(smart_safe_execute "crontab -l 2>/dev/null | grep -i starlink || true")
    if [ -n "$starlink_crons" ]; then
        log_success "Starlink cron jobs found:"
        echo "$starlink_crons" | while read -r line; do
            log_info "  $line"
        done
    else
        log_warning "No Starlink cron jobs found"
    fi
else
    log_warning "No crontab found or cannot access"
fi

printf "\n"
log_step "Checking for running Starlink processes"
# Use pgrep instead of ps aux | grep for better process detection
if starlink_pids=$(pgrep -f "starlink" 2>/dev/null); then
    log_success "Starlink processes running:"
    for pid in $starlink_pids; do
        # Get process details for each PID
        if ps_line=$(ps -p "$pid" -o pid,user,command 2>/dev/null | tail -n +2); then
            log_info "  $ps_line"
        fi
    done
else
    log_warning "No Starlink processes currently running"
fi

printf "\n"
log_step "Checking system logs for Starlink entries"
starlink_logs=$(logread 2>/dev/null | grep -i starlink | tail -5 || true)
if [ -n "$starlink_logs" ]; then
    log_success "Recent Starlink log entries:"
    echo "$starlink_logs" | while read -r line; do
        log_info "  $line"
    done
else
    log_warning "No recent Starlink log entries found"
fi

printf "\n"
log_success "DISCOVERY COMPLETE"
printf "\n"

log_info "Discovery completed!"
log_info "If no Starlink installation was found, you may need to run the installer first:"
log_info "smart_safe_execute 'curl -fsSL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/install-rutos.sh | sh'"
printf "\n"
