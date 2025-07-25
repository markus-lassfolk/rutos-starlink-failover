#!/bin/sh
# Script: integrate-gps-into-starlink-monitor-rutos.sh
# Version: 2.4.6
# Description: Integration instructions for adding GPS collection to existing Starlink monitoring
# Integrates gps-collector-rutos.sh into starlink_monitor.sh and configuration

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors (RUTOS Method 5 format)
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
DRY_RUN="${DRY_RUN:-1}" # Default to dry-run for safety

# Configuration paths - Updated for Logger Script Integration
MONITOR_SCRIPT="./Starlink-RUTOS-Failover/starlink_monitor-rutos.sh" # For reference only
LOGGER_SCRIPT="./Starlink-RUTOS-Failover/starlink_logger-rutos.sh"   # Primary integration target
CONFIG_FILE="./config/config.sh"
GPS_COLLECTOR_SCRIPT="./gps-integration/gps-collector-rutos.sh"
GPS_ANALYZER_SCRIPT="./gps-integration/gps-location-analyzer-rutos.sh"

# Show dry-run warning
show_dry_run_warning() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "\n${YELLOW}========================================${NC}\n"
        printf "${YELLOW}           DRY-RUN MODE ENABLED         ${NC}\n"
        printf "${YELLOW}========================================${NC}\n"
        printf "${YELLOW}This script will show what changes would be made${NC}\n"
        printf "${YELLOW}without actually modifying any files.${NC}\n"
        printf "${YELLOW}To execute real changes, run with: DRY_RUN=0${NC}\n"
        printf "${YELLOW}========================================${NC}\n\n"
    fi
}

# Safe execution wrapper
safe_execute() {
    operation="$1"
    command="$2"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "DRY-RUN: Would $operation"
        log_debug "Command: $command"
    else
        log_step "$operation"
        eval "$command"
        if [ $? -eq 0 ]; then
            log_success "Completed: $operation"
        else
            log_error "Failed: $operation"
            return 1
        fi
    fi
}

# Backup existing files
backup_files() {
    backup_dir="/etc/starlink-monitor/backup/gps-integration-$(date '+%Y%m%d_%H%M%S')"

    log_step "Creating backup of existing files"

    safe_execute "create backup directory" "mkdir -p '$backup_dir'"

    # Backup monitor script if it exists
    if [ -f "$MONITOR_SCRIPT" ]; then
        safe_execute "backup starlink_monitor.sh" "cp '$MONITOR_SCRIPT' '$backup_dir/'"
    fi

    # Backup config file if it exists
    if [ -f "$CONFIG_FILE" ]; then
        safe_execute "backup config.sh" "cp '$CONFIG_FILE' '$backup_dir/'"
    fi

    log_info "Backup location: $backup_dir"
}

# Copy GPS integration scripts
install_gps_scripts() {
    log_step "Installing GPS integration scripts"

    # Copy GPS collector script
    if [ -f "gps-integration/gps-collector-rutos.sh" ]; then
        safe_execute "install GPS collector script" "cp 'gps-integration/gps-collector-rutos.sh' '$GPS_COLLECTOR_SCRIPT'"
        safe_execute "make GPS collector executable" "chmod +x '$GPS_COLLECTOR_SCRIPT'"
    else
        log_error "GPS collector script not found: gps-integration/gps-collector-rutos.sh"
        return 1
    fi

    # Copy GPS analyzer script
    if [ -f "gps-integration/gps-location-analyzer-rutos.sh" ]; then
        safe_execute "install GPS analyzer script" "cp 'gps-integration/gps-location-analyzer-rutos.sh' '$GPS_ANALYZER_SCRIPT'"
        safe_execute "make GPS analyzer executable" "chmod +x '$GPS_ANALYZER_SCRIPT'"
    else
        log_error "GPS analyzer script not found: gps-integration/gps-location-analyzer-rutos.sh"
        return 1
    fi
}

# Add GPS configuration to config.sh
add_gps_configuration() {
    log_step "Adding GPS configuration to config.sh"

    gps_config="
# ===== GPS INTEGRATION CONFIGURATION =====
# GPS data collection and location analysis settings
# Added by gps-integration system

# GPS Collection Settings
GPS_ENABLED=\"true\"                          # Enable GPS data collection (true/false)
GPS_PRIMARY_SOURCE=\"rutos\"                   # Primary GPS . (rutos/starlink/auto)
GPS_FALLBACK_SOURCE=\"starlink\"              # Fallback GPS . (rutos/starlink/none)
GPS_COLLECTION_INTERVAL=\"60\"                # GPS collection interval in seconds
GPS_ACCURACY_THRESHOLD_RUTOS=\"2\"             # RUTOS GPS accuracy threshold in meters
GPS_ACCURACY_THRESHOLD_STARLINK=\"10\"         # Starlink GPS accuracy threshold in meters

# GPS Location Analysis Settings  
GPS_CLUSTERING_DISTANCE=\"50\"                # Location clustering radius in meters
GPS_SPEED_THRESHOLD=\"5\"                     # Speed threshold for parked vs moving (km/h)
GPS_NO_DATA_VALUE=\"N/A\"                     # Value for missing GPS data (N/A or 0)
PARKED_ONLY_CLUSTERING=\"true\"               # Only cluster when vehicle is parked
MIN_EVENTS_PER_LOCATION=\"2\"                 # Minimum events to flag problematic location
MIN_TIME_AT_LOCATION=\"3600\"                 # Minimum seconds at location (1 hour)

# GPS Output Settings
GPS_OUTPUT_FORMAT=\"log\"                     # Output format (log/json/csv)
GPS_LOG_ENHANCED_METRICS=\"true\"             # Include GPS in enhanced metrics logging
GPS_LOCATION_ANALYSIS_ENABLED=\"true\"        # Enable automatic location analysis

# GPS Integration Paths
GPS_COLLECTOR_SCRIPT=\"$GPS_COLLECTOR_SCRIPT\"
GPS_ANALYZER_SCRIPT=\"$GPS_ANALYZER_SCRIPT\"
GPS_DATA_DIR=\"\$LOG_DIR/gps\"                 # GPS data storage directory
"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "DRY-RUN: Would add GPS configuration to $CONFIG_FILE"
        printf "\n${CYAN}Configuration to be added:${NC}\n"
        echo "$gps_config"
    else
        # Check if GPS configuration already exists
        if grep -q "GPS_ENABLED" "$CONFIG_FILE" 2>/dev/null; then
            log_warning "GPS configuration already exists in config.sh"
            log_info "Skipping GPS configuration addition"
        else
            echo "$gps_config" >>"$CONFIG_FILE"
            log_success "GPS configuration added to config.sh"
        fi
    fi
}

# Add GPS integration to starlink_logger-rutos.sh (primary target)
integrate_gps_logging() {
    log_step "Integrating GPS collection into starlink_logger-rutos.sh"

    if [ ! -f "$LOGGER_SCRIPT" ]; then
        log_error "Starlink logger script not found: $LOGGER_SCRIPT"
        return 1
    fi

    # Integration strategy for logger script
    integration_code='
# GPS data collection for logging
collect_gps_coordinates() {
    if [ "$GPS_ENABLED" = "true" ]; then
        debug_log "Collecting GPS coordinates for logging"
        
        # Get current GPS coordinates using our collector
        if [ -x "$GPS_COLLECTOR_SCRIPT" ]; then
            gps_output=$("$GPS_COLLECTOR_SCRIPT" --single-reading --format=compact --config="$CONFIG_FILE" 2>/dev/null || echo "")
            
            if [ -n "$gps_output" ]; then
                # Extract coordinates from GPS output
                # Expected format: GPS: source=rutos, lat=59.8586, lon=17.6389, alt=45m, fix=1, acc=1.2m, sats=12, speed=0km/h
                gps_lat=$(echo "$gps_output" | sed -n '\''s/.*lat=\([0-9\.-]*\).*/\1/p'\'')
                gps_lon=$(echo "$gps_output" | sed -n '\''s/.*lon=\([0-9\.-]*\).*/\1/p'\'')
                gps_speed=$(echo "$gps_output" | sed -n '\''s/.*speed=\([0-9\.-]*\)km\/h.*/\1/p'\'')
                gps_accuracy=$(echo "$gps_output" | sed -n '\''s/.*acc=\([0-9\.-]*\)m.*/\1/p'\'')
                gps_source=$(echo "$gps_output" | sed -n '\''s/.*source=\([a-z]*\).*/\1/p'\'')
                
                debug_log "GPS COORDINATES: lat=$gps_lat, lon=$gps_lon, speed=$gps_speed, accuracy=$gps_accuracy, source=$gps_source"
                
                # Set GPS coordinates for CSV logging (fallback to N/A if missing)
                GPS_LATITUDE="${gps_lat:-N/A}"
                GPS_LONGITUDE="${gps_lon:-N/A}" 
                GPS_SPEED="${gps_speed:-N/A}"
                GPS_ACCURACY="${gps_accuracy:-N/A}"
                GPS_SOURCE="${gps_source:-N/A}"
            else
                debug_log "GPS COORDINATES: No GPS data available"
                GPS_LATITUDE="N/A"
                GPS_LONGITUDE="N/A"
                GPS_SPEED="N/A" 
                GPS_ACCURACY="N/A"
                GPS_SOURCE="N/A"
            fi
        else
            debug_log "GPS COORDINATES: GPS collector not available: $GPS_COLLECTOR_SCRIPT"
            GPS_LATITUDE="N/A"
            GPS_LONGITUDE="N/A"
            GPS_SPEED="N/A"
            GPS_ACCURACY="N/A" 
            GPS_SOURCE="N/A"
        fi
    else
        debug_log "GPS COORDINATES: GPS collection disabled"
        GPS_LATITUDE="N/A"
        GPS_LONGITUDE="N/A"
        GPS_SPEED="N/A"
        GPS_ACCURACY="N/A"
        GPS_SOURCE="N/A"
    fi
}'

    if [ "$DRY_RUN" = "1" ]; then
        log_info "DRY-RUN: Would integrate GPS functions into starlink_logger-rutos.sh"
        printf "\n${CYAN}Logger Integration code to be added:${NC}\n"
        echo "$integration_code"

        printf "\n${CYAN}Integration points for Logger Script:${NC}\n"
        echo "1. Add GPS collection function after enhanced metrics extraction"
        echo "2. Modify CSV header to include GPS coordinates"
        echo "3. Modify CSV data output to include GPS coordinates"
        echo "4. Call collect_gps_coordinates() before CSV logging"
        echo ""
        echo "Enhanced CSV format will be:"
        echo "Timestamp,Latency (ms),Packet Loss (%),Obstruction (%),Uptime (hours),SNR (dB),SNR Above Noise,SNR Persistently Low,GPS Valid,GPS Satellites,Reboot Detected,GPS Latitude,GPS Longitude,GPS Speed (km/h),GPS Accuracy (m),GPS Source"
    else
        # Check if GPS integration already exists
        if grep -q "collect_gps_coordinates" "$LOGGER_SCRIPT" 2>/dev/null; then
            log_warning "GPS integration already exists in starlink_logger-rutos.sh"
            log_info "Skipping GPS integration"
        else
            # Add GPS functions after enhanced metrics extraction (around line 240)
            temp_file="/tmp/logger_integration_$$"

            # Find insertion point (after enhanced metrics extraction)
            awk '
                /Enhanced Metrics Extraction/ { 
                    print
                    print ""
                    print "'"$integration_code"'"
                    print ""
                    next
                }
                { print }
            ' "$LOGGER_SCRIPT" >"$temp_file"

            # Replace original file
            mv "$temp_file" "$LOGGER_SCRIPT"

            log_success "GPS integration functions added to starlink_logger-rutos.sh"
            log_warning "Manual CSV header and data output modifications required"
        fi
    fi
}

# Create GPS data directory
create_gps_data_directory() {
    log_step "Creating GPS data directory"

    gps_data_dir="/var/log/starlink/gps"
    safe_execute "create GPS data directory" "mkdir -p '$gps_data_dir'"
    safe_execute "set GPS data directory permissions" "chmod 755 '$gps_data_dir'"
}

# Generate integration verification script
generate_verification_script() {
    log_step "Generating GPS integration verification script"

    verification_script="/etc/starlink-monitor/verify-gps-integration.sh"

    cat >"/tmp/verify_gps_$$" <<'EOF'
#!/bin/sh
# GPS Integration Verification Script
# Verifies that GPS integration is properly installed and configured

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
NC='\033[0m'

log_check() {
    printf "${BLUE}[CHECK]${NC} %s: " "$1"
}

log_pass() {
    printf "${GREEN}PASS${NC}\n"
}

log_fail() {
    printf "${RED}FAIL${NC}\n"
    echo "  Error: $1"
}

log_warn() {
    printf "${YELLOW}WARN${NC}\n"
    echo "  Warning: $1"
}

echo "Verifying GPS Integration Installation..."
echo ""

# Check GPS collector script
log_check "GPS collector script exists"
if [ -f "/etc/starlink-monitor/gps-collector-rutos.sh" ] && [ -x "/etc/starlink-monitor/gps-collector-rutos.sh" ]; then
    log_pass
else
    log_fail "GPS collector script missing or not executable"
fi

# Check GPS analyzer script  
log_check "GPS analyzer script exists"
if [ -f "/etc/starlink-monitor/gps-location-analyzer-rutos.sh" ] && [ -x "/etc/starlink-monitor/gps-location-analyzer-rutos.sh" ]; then
    log_pass
else
    log_fail "GPS analyzer script missing or not executable"
fi

# Check configuration
log_check "GPS configuration in config.sh"
if [ -f "/etc/starlink-monitor/config.sh" ] && grep -q "GPS_ENABLED" "/etc/starlink-monitor/config.sh"; then
    log_pass
else
    log_fail "GPS configuration missing from config.sh"
fi

# Check GPS data directory
log_check "GPS data directory exists"
if [ -d "/var/log/starlink/gps" ]; then
    log_pass
else
    log_fail "GPS data directory missing"
fi

# Test GPS collector functionality
log_check "GPS collector functionality"
if [ -x "/etc/starlink-monitor/gps-collector-rutos.sh" ]; then
    # Test with dry run
    if /etc/starlink-monitor/gps-collector-rutos.sh --test-only --config="/etc/starlink-monitor/config.sh" >/dev/null 2>&1; then
        log_pass
    else
        log_warn "GPS collector test failed - may need RUTOS environment"
    fi
else
    log_fail "GPS collector not executable"
fi

# Test GPS analyzer functionality
log_check "GPS analyzer functionality"
if [ -x "/etc/starlink-monitor/gps-location-analyzer-rutos.sh" ]; then
    # Test with help option
    if /etc/starlink-monitor/gps-location-analyzer-rutos.sh --help >/dev/null 2>&1; then
        log_pass
    else
        log_warn "GPS analyzer test failed"
    fi
else
    log_fail "GPS analyzer not executable"
fi

# Check integration in monitor script
log_check "GPS integration in monitor script"
if [ -f "/etc/starlink-monitor/starlink_monitor.sh" ] && grep -q "collect_gps_data" "/etc/starlink-monitor/starlink_monitor.sh"; then
    log_pass
else
    log_warn "GPS integration not found in monitor script - manual integration required"
fi

echo ""
echo "GPS Integration Verification Complete"
echo ""
echo "Next Steps:"
echo "1. Review and customize GPS configuration in /etc/starlink-monitor/config.sh"
echo "2. Complete manual integration in starlink_monitor.sh main loop"
echo "3. Test GPS collection: /etc/starlink-monitor/gps-collector-rutos.sh --test-only"
echo "4. Run location analysis: /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink"
EOF

    safe_execute "install verification script" "cp '/tmp/verify_gps_$$' '$verification_script'"
    safe_execute "make verification script executable" "chmod +x '$verification_script'"

    # Cleanup temp file
    rm -f "/tmp/verify_gps_$$"

    log_info "Verification script installed: $verification_script"
}

# Generate manual integration instructions
generate_manual_instructions() {
    log_step "Generating manual integration instructions"

    instructions_file="/tmp/gps_integration_instructions.md"

    cat >"$instructions_file" <<'EOF'
# Manual GPS Integration Instructions

## Overview

The GPS integration system has been installed but requires some manual steps to complete the integration with your existing Starlink monitoring system.

## Completed Automatically

✅ GPS collector script installed: `/etc/starlink-monitor/gps-collector-rutos.sh`
✅ GPS analyzer script installed: `/etc/starlink-monitor/gps-location-analyzer-rutos.sh`  
✅ GPS configuration added to: `/etc/starlink-monitor/config.sh`
✅ GPS functions added to: `/etc/starlink-monitor/starlink_monitor.sh`
✅ GPS data directory created: `/var/log/starlink/gps`

## Manual Steps Required

### 1. Complete Monitor Script Integration

Add GPS collection to the main monitoring loop in `starlink_monitor.sh`:

```bash
# Find the main monitoring loop and add GPS collection
# Look for the main loop that runs every monitoring interval

# Add this call in the main loop:
collect_gps_data

# Or add GPS collection with timing control:
if [ $((loop_counter % gps_interval_loops)) -eq 0 ]; then
    collect_gps_data
fi
```

### 2. Modify Enhanced Metrics Logging

Replace existing enhanced metrics logging with the GPS-enabled version:

```bash
# Replace existing log_enhanced_metrics call with:
log_enhanced_metrics_with_gps
```

### 3. Configuration Customization

Review and customize GPS settings in `/etc/starlink-monitor/config.sh`:

```bash
# Key settings to review:
GPS_ENABLED="true"                    # Enable/disable GPS collection
GPS_PRIMARY_SOURCE="rutos"           # rutos/starlink/auto
GPS_CLUSTERING_DISTANCE="50"         # Location clustering radius (meters)
GPS_SPEED_THRESHOLD="5"              # Parked vs moving threshold (km/h)
```

### 4. Test GPS Integration

Run verification and testing:

```bash
# Verify installation
/etc/starlink-monitor/verify-gps-integration.sh

# Test GPS collector
/etc/starlink-monitor/gps-collector-rutos.sh --test-only

# Test GPS analyzer (requires log data)
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

## Usage Examples

### Collect Single GPS Reading
```bash
/etc/starlink-monitor/gps-collector-rutos.sh --single-reading --format=json
```

### Analyze Location Patterns  
```bash
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

### Test Different Clustering Settings
```bash
GPS_CLUSTERING_DISTANCE=100 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

## Integration Points in starlink_monitor.sh

### Location 1: After Function Definitions
```bash
# Add GPS functions after existing function definitions
collect_gps_data() {
    # GPS collection function already added
}

log_enhanced_metrics_with_gps() {
    # Enhanced metrics with GPS already added  
}
```

### Location 2: Main Monitoring Loop
```bash
# In the main monitoring loop, add:
while true; do
    # ... existing monitoring code ...
    
    # Add GPS collection
    collect_gps_data
    
    # Use GPS-enabled enhanced metrics
    log_enhanced_metrics_with_gps
    
    # ... rest of loop ...
    sleep "$CHECK_INTERVAL"
done
```

### Location 3: Configuration Loading
```bash
# Ensure GPS configuration is loaded
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    # GPS configuration automatically loaded
fi
```

## Troubleshooting

### GPS Collector Issues
- Check RUTOS device connectivity
- Verify grpcurl installation
- Test Starlink API accessibility
- Review authentication settings

### Location Analysis Issues  
- Ensure sufficient GPS data in logs
- Check clustering distance settings
- Verify log file format compatibility
- Test with different speed thresholds

### Integration Issues
- Verify all scripts are executable
- Check configuration file syntax
- Test individual components separately
- Review log files for error messages

## Advanced Features

### Custom Location Analysis
```bash
# Analyze only parked locations
PARKED_ONLY_CLUSTERING=true /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Include moving vehicle data
/etc/starlink-monitor/gps-location-analyzer-rutos.sh --include-moving /var/log/starlink

# Use custom clustering distance
GPS_CLUSTERING_DISTANCE=25 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

### Automated Location Reports
```bash
# Add to cron for daily location analysis
0 6 * * * /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

### Integration with Travel Planning
```bash
# Export problematic locations for GPS navigation
grep "PROBLEMATIC LOCATION" /var/log/starlink/gps_location_analysis_*.md
```

EOF

    log_info "Manual integration instructions: $instructions_file"

    if [ "$DRY_RUN" = "1" ]; then
        printf "\n${CYAN}Manual integration instructions preview:${NC}\n"
        head -30 "$instructions_file"
        printf "\n${CYAN}... (full instructions in file) ...${NC}\n"
    else
        # Copy to permanent location
        cp "$instructions_file" "/etc/starlink-monitor/GPS_INTEGRATION_INSTRUCTIONS.md"
        log_info "Instructions also copied to: /etc/starlink-monitor/GPS_INTEGRATION_INSTRUCTIONS.md"
    fi
}

# Usage information
show_usage() {
    cat <<EOF

Usage: $0 [options]

Options:
    --execute               Execute real changes (default: dry-run only)
    --config <file>         Use specific configuration file
    --help                  Show this help message

Safety:
    By default, this script runs in DRY-RUN mode to show what changes
    would be made without actually modifying files.
    
    To execute real changes: $0 --execute
    Or set environment: DRY_RUN=0 $0

Examples:
    $0                      # Dry-run mode (safe preview)
    $0 --execute            # Execute real integration
    DRY_RUN=0 $0           # Execute real integration

EOF
}

# Main function
main() {
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --execute)
                DRY_RUN=0
                ;;
            --config)
                shift
                CONFIG_FILE="$1"
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done

    # Show dry-run warning and configuration
    show_dry_run_warning

    log_info "Starting GPS Integration v$SCRIPT_VERSION"
    log_info "Primary Target: $LOGGER_SCRIPT (starlink_logger-rutos.sh)"
    log_info "Configuration: $CONFIG_FILE"
    log_info "Execution Mode: $([ "$DRY_RUN" = "1" ] && echo "DRY-RUN" || echo "LIVE")"

    # Validate . files exist
    if [ ! -f "gps-integration/gps-collector-rutos.sh" ]; then
        log_error "GPS collector script not found: gps-integration/gps-collector-rutos.sh"
        log_error "Run this script from the project root directory"
        exit 1
    fi

    if [ ! -f "gps-integration/gps-location-analyzer-rutos.sh" ]; then
        log_error "GPS analyzer script not found: gps-integration/gps-location-analyzer-rutos.sh"
        log_error "Run this script from the project root directory"
        exit 1
    fi

    if [ ! -f "$LOGGER_SCRIPT" ]; then
        log_error "Target logger script not found: $LOGGER_SCRIPT"
        log_error "Run this script from the project root directory"
        exit 1
    fi

    # Execute integration steps
    backup_files
    install_gps_scripts
    add_gps_configuration
    integrate_gps_logging # Changed from integrate_gps_monitoring
    create_gps_data_directory
    generate_verification_script
    generate_manual_instructions

    # Final summary
    echo ""
    log_success "GPS integration completed successfully"

    if [ "$DRY_RUN" = "1" ]; then
        printf "\n${YELLOW}This was a DRY-RUN. No files were modified.${NC}\n"
        printf "${YELLOW}To execute real changes, run: $0 --execute${NC}\n\n"
    else
        printf "\n${GREEN}GPS integration installed successfully!${NC}\n\n"
        printf "${BLUE}Next Steps:${NC}\n"
        printf "1. Run verification: %s\n" "/etc/starlink-monitor/verify-gps-integration.sh"
        printf "2. Review instructions: %s\n" "/etc/starlink-monitor/GPS_INTEGRATION_INSTRUCTIONS.md"
        printf "3. Complete manual integration in starlink_monitor.sh\n"
        printf "4. Test GPS collection: %s --test-only\n" "$GPS_COLLECTOR_SCRIPT"
        printf "5. Run location analysis: %s /var/log/starlink\n" "$GPS_ANALYZER_SCRIPT"
        printf "\n"
    fi
}

# Execute main function
main "$@"
