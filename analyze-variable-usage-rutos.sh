#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# Simple logging for standalone analysis
log_info() { printf "[INFO] %s\n" "$1"; }
log_step() { printf "[STEP] %s\n" "$1"; }
log_warning() { printf "[WARN] %s\n" "$1"; }
log_error() { printf "[ERROR] %s\n" "$1"; }
log_success() { printf "[SUCCESS] %s\n" "$1"; }

log_info "=== Variable Usage Analysis ===" 

# Variables that scripts expect but config defines differently
log_step "1. Checking variable naming mismatches between scripts and config"

# Check main cron scripts
MONITOR_SCRIPT="Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
LOGGER_SCRIPT="Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh"
CONFIG_TEMPLATE="config/config.unified.template.sh"

if [ ! -f "$MONITOR_SCRIPT" ]; then
    log_error "Monitor script not found: $MONITOR_SCRIPT"
    exit 1
fi

if [ ! -f "$LOGGER_SCRIPT" ]; then
    log_error "Logger script not found: $LOGGER_SCRIPT"
    exit 1
fi

if [ ! -f "$CONFIG_TEMPLATE" ]; then
    log_error "Config template not found: $CONFIG_TEMPLATE"
    exit 1
fi

log_info "Analyzing main cron scripts:"
log_info "  Monitor: $MONITOR_SCRIPT"
log_info "  Logger:  $LOGGER_SCRIPT"
log_info "  Config:  $CONFIG_TEMPLATE"

# Extract variables used by scripts
log_step "2. Extracting variables used by scripts"

# Monitor script variables
MONITOR_VARS=$(grep -o 'ENABLE_[A-Z_]*\|GPS_[A-Z_]*\|CELLULAR_[A-Z_]*\|PUSHOVER_[A-Z_]*' "$MONITOR_SCRIPT" 2>/dev/null | sort -u || echo "")
LOGGER_VARS=$(grep -o 'ENABLE_[A-Z_]*\|GPS_[A-Z_]*\|CELLULAR_[A-Z_]*\|PUSHOVER_[A-Z_]*' "$LOGGER_SCRIPT" 2>/dev/null | sort -u || echo "")

# Config template variables
CONFIG_VARS=$(grep -o '^export [A-Z_]*=' "$CONFIG_TEMPLATE" 2>/dev/null | sed 's/^export //' | sed 's/=.*$//' | sort -u || echo "")

log_info "Monitor script uses these variables:"
for var in $MONITOR_VARS; do
    printf "  %s\n" "$var"
done

log_info ""
log_info "Logger script uses these variables:"
for var in $LOGGER_VARS; do
    printf "  %s\n" "$var"
done

log_info ""
log_info "Config template defines these variables:"
for var in $CONFIG_VARS; do
    printf "  %s\n" "$var"
done

# Check for mismatches
log_step "3. Identifying variable naming mismatches"

# Combine all script variables
ALL_SCRIPT_VARS="$MONITOR_VARS $LOGGER_VARS"
UNIQUE_SCRIPT_VARS=$(printf "%s\n" $ALL_SCRIPT_VARS | sort -u)

MISMATCHES=""
MISSING_IN_CONFIG=""

for script_var in $UNIQUE_SCRIPT_VARS; do
    found=0
    for config_var in $CONFIG_VARS; do
        if [ "$script_var" = "$config_var" ]; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        # Check for similar variables (naming pattern mismatches)
        case "$script_var" in
            "ENABLE_PUSHOVER")
                # Script uses ENABLE_PUSHOVER, config defines PUSHOVER_ENABLED
                found_pushover=0
                for config_var in $CONFIG_VARS; do
                    if [ "$config_var" = "PUSHOVER_ENABLED" ]; then
                        found_pushover=1
                        break
                    fi
                done
                if [ $found_pushover -eq 1 ]; then
                    MISMATCHES="$MISMATCHES
  Script uses: $script_var
  Config has:  PUSHOVER_ENABLED"
                else
                    MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                fi
                ;;
            "ENABLE_GPS_TRACKING")
                # Script uses ENABLE_GPS_TRACKING, config may have GPS_ENABLED
                found_gps=0
                for config_var in $CONFIG_VARS; do
                    if [ "$config_var" = "GPS_ENABLED" ]; then
                        found_gps=1
                        break
                    fi
                done
                if [ $found_gps -eq 1 ]; then
                    MISMATCHES="$MISMATCHES
  Script uses: $script_var
  Config has:  GPS_ENABLED"
                else
                    MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                fi
                ;;
            "ENABLE_CELLULAR_TRACKING")
                # Script uses ENABLE_CELLULAR_TRACKING, config may have CELLULAR_ENABLED
                found_cellular=0
                for config_var in $CONFIG_VARS; do
                    if [ "$config_var" = "CELLULAR_ENABLED" ]; then
                        found_cellular=1
                        break
                    fi
                done
                if [ $found_cellular -eq 1 ]; then
                    MISMATCHES="$MISMATCHES
  Script uses: $script_var
  Config has:  CELLULAR_ENABLED"
                else
                    MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                fi
                ;;
            "ENABLE_GPS_LOGGING")
                # Script uses ENABLE_GPS_LOGGING, config may have GPS_ENABLED
                found_gps_log=0
                for config_var in $CONFIG_VARS; do
                    if [ "$config_var" = "GPS_ENABLED" ]; then
                        found_gps_log=1
                        break
                    fi
                done
                if [ $found_gps_log -eq 1 ]; then
                    MISMATCHES="$MISMATCHES
  Script uses: $script_var
  Config has:  GPS_ENABLED"
                else
                    MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                fi
                ;;
            "ENABLE_CELLULAR_LOGGING")
                # Script uses ENABLE_CELLULAR_LOGGING, config may have CELLULAR_ENABLED
                found_cellular_log=0
                for config_var in $CONFIG_VARS; do
                    if [ "$config_var" = "CELLULAR_ENABLED" ]; then
                        found_cellular_log=1
                        break
                    fi
                done
                if [ $found_cellular_log -eq 1 ]; then
                    MISMATCHES="$MISMATCHES
  Script uses: $script_var
  Config has:  CELLULAR_ENABLED"
                else
                    MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                fi
                ;;
            *)
                MISSING_IN_CONFIG="$MISSING_IN_CONFIG $script_var"
                ;;
        esac
    fi
done

if [ -n "$MISMATCHES" ]; then
    log_warning "Found variable naming mismatches:"
    printf "%s\n" "$MISMATCHES"
else
    log_success "No variable naming mismatches found"
fi

if [ -n "$MISSING_IN_CONFIG" ]; then
    log_warning "Variables used by scripts but not defined in config:"
    for var in $MISSING_IN_CONFIG; do
        printf "  %s\n" "$var"
    done
else
    log_success "All script variables are defined in config"
fi

# Check for unused config variables
log_step "4. Checking for unused config variables"

UNUSED_VARS=""
for config_var in $CONFIG_VARS; do
    found=0
    for script_var in $UNIQUE_SCRIPT_VARS; do
        if [ "$config_var" = "$script_var" ]; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        # Check special cases that might be used indirectly
        case "$config_var" in
            "PUSHOVER_ENABLED"|"GPS_ENABLED"|"CELLULAR_ENABLED")
                # These are main enable flags, may be mapped to ENABLE_ variants
                continue
                ;;
            "PUSHOVER_TOKEN"|"PUSHOVER_USER"|"PUSHOVER_TIMEOUT")
                # These are used when PUSHOVER is enabled
                continue
                ;;
            "MAINTENANCE_PUSHOVER_ENABLED"|"MAINTENANCE_PUSHOVER_TOKEN"|"MAINTENANCE_PUSHOVER_USER")
                # These are for maintenance notifications
                continue
                ;;
            *)
                # Check if variable appears in any script
                if grep -q "$config_var" "$MONITOR_SCRIPT" "$LOGGER_SCRIPT" 2>/dev/null; then
                    continue
                fi
                UNUSED_VARS="$UNUSED_VARS $config_var"
                ;;
        esac
    fi
done

if [ -n "$UNUSED_VARS" ]; then
    log_info "Config variables not directly used by main scripts:"
    for var in $UNUSED_VARS; do
        printf "  %s\n" "$var"
    done
    log_info "(Note: Some may be used by other scripts or features)"
else
    log_success "All config variables appear to be used"
fi

# Recommendations
log_step "5. Recommendations"

if [ -n "$MISMATCHES" ]; then
    log_info "Variable Naming Standardization Options:"
    log_info ""
    log_info "Option A: Update scripts to use config variable names"
    log_info "  - Change ENABLE_PUSHOVER to PUSHOVER_ENABLED in scripts"
    log_info "  - Change ENABLE_GPS_TRACKING to GPS_ENABLED in scripts"
    log_info "  - Change ENABLE_CELLULAR_TRACKING to CELLULAR_ENABLED in scripts"
    log_info "  - Pros: Simpler config, less confusion"
    log_info "  - Cons: Need to update multiple script files"
    log_info ""
    log_info "Option B: Update config to use script variable names"
    log_info "  - Change PUSHOVER_ENABLED to ENABLE_PUSHOVER in config"
    log_info "  - Change GPS_ENABLED to ENABLE_GPS_TRACKING in config"
    log_info "  - Change CELLULAR_ENABLED to ENABLE_CELLULAR_TRACKING in config"
    log_info "  - Pros: Scripts don't need changes"
    log_info "  - Cons: Config variable names become less intuitive"
    log_info ""
    log_info "Option C: Keep compatibility mapping in config (current approach)"
    log_info "  - Keep both variable sets with export ENABLE_VAR=\"\${VAR_ENABLED}\""
    log_info "  - Pros: Both naming conventions work"
    log_info "  - Cons: More complex config, potential confusion"
    log_info ""
    log_info "RECOMMENDATION: Option A (update scripts) for long-term maintainability"
else
    log_success "No variable naming issues found!"
fi

        echo "analyze-variable-usage-rutos.sh v$SCRIPT_VERSION"
        echo ""
log_success "Variable usage analysis complete"
