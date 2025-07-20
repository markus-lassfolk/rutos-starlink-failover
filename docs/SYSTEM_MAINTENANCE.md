# System Maintenance Script for RUTOS

## Overview

The `system-maintenance-rutos.sh` script is a generic system health checker and issue resolver for RUTOS systems. It automatically detects common problems and can fix them without manual intervention.

## Features

- **Automated Issue Detection**: Scans for common system problems
- **Automatic Fixes**: Can automatically resolve detected issues
- **Detailed Logging**: Comprehensive logging of all actions taken
- **Multiple Modes**: Check-only, fix, or report generation modes
- **Extensible**: Easy to add new checks and fixes

## Current Checks

1. **Missing /var/lock directory** - Fixes the "can't create /var/lock/qmimux.lock" error
2. **Missing /var/run directory** - Ensures critical runtime directory exists
3. **Missing critical system directories** - Creates essential system directories
4. **Large log files** - Rotates and truncates oversized log files
5. **Old temporary files** - Cleans up files older than 7 days
6. **High memory usage** - Clears caches when memory usage is high
7. **Network interface issues** - Reports interfaces that are down
8. **System service health** - Restarts critical services if they're down
9. **Disk space monitoring** - Cleans up when disk usage is high
10. **Permission issues** - Fixes incorrect permissions on critical files

## Usage

```bash
# Run automatic maintenance (check and fix issues)
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh

# Check for issues only (no fixes)
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh check

# Generate maintenance report
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh report

# Show help
/usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh help

# Run with debug output
DEBUG=1 /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh
```

## Cron Schedule

The script is automatically scheduled to run every 6 hours:
```
0 */6 * * * /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh auto
```

## Log Files

- **Maintenance Log**: `/var/log/system-maintenance.log` - Detailed action log
- **Report**: `/var/log/system-maintenance-report.txt` - Generated reports
- **Syslog**: Actions are also logged to system log with tag "SystemMaintenance"

## Adding New Checks

To add a new maintenance check, follow this pattern:

1. Create a new function in the script following the naming convention `check_*`:

```bash
# Check [N]: [Description]
check_new_issue() {
    log_debug "Checking for [describe what you're checking]"
    
    if [ condition_indicating_problem ]; then
        record_action "FOUND" "[Issue description]" "[Fix description]"
        
        if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
            if fix_command_here; then
                record_action "FIXED" "[Issue description]" "[Command used to fix]"
            else
                log_error "Failed to fix [issue]"
            fi
        fi
    else
        log_debug "[Normal state message]"
        record_action "CHECK" "[What was checked]" "No action needed"
    fi
}
```

2. Add your function to the `run_all_checks()` function:

```bash
run_all_checks() {
    # ... existing checks ...
    check_new_issue
    # Add more checks here in the future
}
```

## Example: The Original Issue

The script was created to fix this specific issue:

**Problem**: 
```
daemon.notice netifd: mob1s1a1 (10544): ./wwan.sh: eval: line 133: can't create /var/lock/qmimux.lock: nonexistent directory
```

**Solution Implemented**:
```bash
check_var_lock_directory() {
    if [ ! -d "/var/lock" ]; then
        # Issue found - directory missing
        if mkdir -p /var/lock 2>/dev/null; then
            chmod 755 /var/lock
            # Issue fixed
        fi
    fi
}
```

## Safety Features

- **Backup Strategy**: Critical files are backed up before modification
- **Conservative Fixes**: Only safe, well-tested fixes are applied automatically
- **Detailed Logging**: Every action is logged for auditing
- **Check Mode**: Can run in check-only mode for safety
- **Error Handling**: Comprehensive error handling prevents system damage

## Integration

- **Automatic Installation**: Installed automatically with `install-rutos.sh`
- **Cron Integration**: Scheduled automatically in system crontab
- **Starlink Integration**: Coordinates with other Starlink monitoring tools
- **RUTOS Compatible**: Designed specifically for RUTOS/OpenWrt environment

## Maintenance

The script is self-maintaining:
- Logs are automatically rotated when they become large
- Temporary files are cleaned up automatically
- Old maintenance logs are pruned to prevent disk space issues

## Future Enhancements

Planned additions:
- Network connectivity validation and repair
- Firewall rule verification and correction
- UCI configuration validation
- Package integrity checks
- Certificate and key validation
- Storage health monitoring

## Troubleshooting

If the maintenance script isn't working:

1. Check if it's installed:
   ```bash
   ls -la /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh
   ```

2. Check cron schedule:
   ```bash
   crontab -l | grep maintenance
   ```

3. Check recent logs:
   ```bash
   tail -50 /var/log/system-maintenance.log
   ```

4. Run manually with debug:
   ```bash
   DEBUG=1 /usr/local/starlink-monitor/scripts/system-maintenance-rutos.sh check
   ```

## Version History

- **v1.0.0**: Initial release with 10 basic system checks
  - Missing directory fixes
  - Log rotation
  - Memory and disk cleanup
  - Service health monitoring
  - Permission fixes
