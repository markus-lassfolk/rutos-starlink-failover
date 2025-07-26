#!/bin/sh
# Script: add-gps-logging-to-starlink-monitor.sh
# Version: 2.4.6
# Description: Adds GPS data collection to existing Starlink monitoring using Victron approach
# Based on your rutos-victron-gps repository patterns

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Color variables may not all be used
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# GPS data collection functions based on Victron approach

# Collect GPS from RUTOS API (primary . - 2m accuracy)
get_rutos_gps() {
    rutos_ip="${1:-192.168.80.1}"
    auth_token="$2"

    if [ -z "$auth_token" ]; then
        log_warning "No RUTOS auth token provided, skipping RUTOS GPS"
        return 1
    fi

    # Make authenticated request to RUTOS GPS API
    if gps_data=$(curl -s -k -H "Authorization: Bearer $auth_token" \
        "https://$rutos_ip/api/gps/position/status" 2>/dev/null) && [ -n "$gps_data" ]; then
        # Parse GPS data similar to Victron Node-RED flow
        lat=$(echo "$gps_data" | grep -o '"latitude":[^,]*' | cut -d':' -f2 | tr -d '"')
        lon=$(echo "$gps_data" | grep -o '"longitude":[^,]*' | cut -d':' -f2 | tr -d '"')
        alt=$(echo "$gps_data" | grep -o '"altitude":[^,]*' | cut -d':' -f2 | tr -d '"')
        fix=$(echo "$gps_data" | grep -o '"fix_status":[^,]*' | cut -d':' -f2 | tr -d '"')
        acc=$(echo "$gps_data" | grep -o '"accuracy":[^,]*' | cut -d':' -f2 | tr -d '"')
        sats=$(echo "$gps_data" | grep -o '"satellites":[^,]*' | cut -d':' -f2 | tr -d '"')

        # Quality check: GPS fix > 0 and accuracy < 2m (Victron threshold)
        if [ -n "$lat" ] && [ -n "$lon" ] && [ "$fix" -gt 0 ] && [ "${acc%.*}" -lt 2 ] 2>/dev/null; then
            echo "rutos|$lat|$lon|$alt|$fix|$acc|$sats"
            return 0
        fi
    fi

    return 1
}

# Collect GPS from Starlink diagnostics (backup . - 10m accuracy)
get_starlink_gps() {
    starlink_ip="${1:-192.168.100.1}"

    # Use grpcurl like in Victron flow
    if command -v grpcurl >/dev/null 2>&1; then
        if diag_data=$(grpcurl -plaintext -emit-defaults -d '{"get_diagnostics":{}}' \
            "$starlink_ip:9200" SpaceX.API.Device.Device/Handle 2>/dev/null) && [ -n "$diag_data" ]; then
            # Extract location data from diagnostics
            lat=$(echo "$diag_data" | grep -o '"latitude":[^,]*' | head -1 | cut -d':' -f2)
            lon=$(echo "$diag_data" | grep -o '"longitude":[^,]*' | head -1 | cut -d':' -f2)
            alt=$(echo "$diag_data" | grep -o '"altitudeMeters":[^,]*' | cut -d':' -f2)
            unc=$(echo "$diag_data" | grep -o '"uncertaintyMeters":[^,]*' | cut -d':' -f2)
            valid=$(echo "$diag_data" | grep -o '"uncertaintyMetersValid":[^,]*' | cut -d':' -f2 | tr -d ' ')

            # Quality check: valid coordinates and accuracy < 10m (Victron threshold)
            if [ -n "$lat" ] && [ -n "$lon" ] && [ "$valid" = "true" ] && [ "${unc%.*}" -lt 10 ] 2>/dev/null; then
                fix=1 # Assume fix if data is valid
                echo "starlink|$lat|$lon|$alt|$fix|$unc|0"
                return 0
            fi
        fi
    else
        log_warning "grpcurl not found, cannot collect Starlink GPS data"
    fi

    return 1
}

# Select best GPS . using Victron logic
select_best_gps() {
    rutos_gps="$1"
    starlink_gps="$2"

    # Parse GPS data
    if [ -n "$rutos_gps" ]; then
        rutos_acc=$(echo "$rutos_gps" | cut -d'|' -f6)
        rutos_fix=$(echo "$rutos_gps" | cut -d'|' -f5)
        good_rutos=0
        if [ "$rutos_fix" -gt 0 ] && [ "${rutos_acc%.*}" -lt 2 ] 2>/dev/null; then
            good_rutos=1
        fi
    else
        good_rutos=0
    fi

    if [ -n "$starlink_gps" ]; then
        starlink_acc=$(echo "$starlink_gps" | cut -d'|' -f6)
        starlink_fix=$(echo "$starlink_gps" | cut -d'|' -f5)
        good_starlink=0
        if [ "$starlink_fix" -gt 0 ] && [ "${starlink_acc%.*}" -lt 10 ] 2>/dev/null; then
            good_starlink=1
        fi
    else
        good_starlink=0
    fi

    # Selection logic from Victron flow
    if [ "$good_rutos" -eq 1 ] && [ "$good_starlink" -eq 1 ]; then
        # Both good, select better accuracy
        if [ "${rutos_acc%.*}" -le "${starlink_acc%.*}" ] 2>/dev/null; then
            echo "$rutos_gps"
        else
            echo "$starlink_gps"
        fi
    elif [ "$good_rutos" -eq 1 ]; then
        echo "$rutos_gps"
    elif [ "$good_starlink" -eq 1 ]; then
        echo "$starlink_gps"
    else
        # Neither . good enough
        return 1
    fi
}

# Format GPS data for logging
format_gps_log() {
    gps_data="$1"

    if [ -n "$gps_data" ]; then
        source=$(echo "$gps_data" | cut -d'|' -f1)
        lat=$(echo "$gps_data" | cut -d'|' -f2)
        lon=$(echo "$gps_data" | cut -d'|' -f3)
        alt=$(echo "$gps_data" | cut -d'|' -f4)
        fix=$(echo "$gps_data" | cut -d'|' -f5)
        acc=$(echo "$gps_data" | cut -d'|' -f6)
        sats=$(echo "$gps_data" | cut -d'|' -f7)

        echo "GPS: source=$source, lat=$lat, lon=$lon, alt=${alt}m, fix=$fix, acc=${acc}m, sats=$sats"
    else
        echo "GPS: no_valid_data"
    fi
}

# Main GPS collection function for integration
collect_gps_data() {
    rutos_ip="${1:-192.168.80.1}"
    starlink_ip="${2:-192.168.100.1}"
    auth_token="$3"

    # Collect from both sources
    rutos_gps=$(get_rutos_gps "$rutos_ip" "$auth_token")
    starlink_gps=$(get_starlink_gps "$starlink_ip")

    # Select best source
    best_gps=$(select_best_gps "$rutos_gps" "$starlink_gps")

    if [ -n "$best_gps" ]; then
        format_gps_log "$best_gps"
        return 0
    else
        echo "GPS: no_valid_sources"
        return 1
    fi
}

# Integration instructions
show_integration_instructions() {
    cat <<'EOF'

# GPS Integration Instructions for Starlink Monitor

## 1. Add GPS Collection to starlink_monitor_unified-rutos.sh

Add this function after the existing API data collection:

```bash
# GPS data collection using Victron approach
collect_and_log_gps() {
    # Get RUTOS auth token (if available)
    auth_token=$(get_rutos_auth_token 2>/dev/null || echo "")
    
    # Collect GPS data from both sources
    gps_status=$(collect_gps_data "192.168.80.1" "192.168.100.1" "$auth_token")
    
    # Log GPS data
    enhanced_log "ENHANCED METRICS: ${existing_metrics}, ${gps_status}"
}
```

## 2. Add to Main Monitoring Loop

In the main monitoring loop, after existing data collection:

```bash
# Existing Starlink API calls
# ... existing code ...

# Add GPS collection
collect_and_log_gps

# Continue with failover logic
# ... existing code ...
```

## 3. Location-Based Failover Enhancement

Add location tracking for intelligent failover:

```bash
# Track location changes for mobile applications
track_location_changes() {
    current_gps="$1"
    last_position_file="/tmp/last_gps_position"
    
    if [ -n "$current_gps" ] && [ -f "$last_position_file" ]; then
        # Calculate movement using haversine distance
        # If moved > 500m, reset Starlink obstruction map
        # (Implementation details in location analysis script)
    fi
    
    # Save current position
    echo "$current_gps" > "$last_position_file"
}
```

## 4. Enhanced Logging Format

Update logging to include location context:

```bash
LOCATION: lat=59.8586, lon=17.6389, alt=45m, source=rutos, acc=1.2m
FAILOVER: obstruction=0.55%, location_id=cluster_1, previous_events=2
```

## 5. Location-Based Alerting

Add location-aware threshold adjustments:

```bash
# Adjust thresholds based on location history
adjust_thresholds_for_location() {
    current_location="$1"
    
    # Check if current location has history of issues
    # Implement more aggressive thresholds for problematic locations
    # Use standard thresholds for new/good locations
}
```

EOF
}

# Main function
main() {
    log_info "GPS Integration Setup for Starlink Monitor v$SCRIPT_VERSION"

    if [ "$1" = "--demo" ]; then
        log_step "Running GPS collection demo"

        # Demo GPS collection
        log_info "Collecting GPS from RUTOS and Starlink sources..."
        if gps_result=$(collect_gps_data "192.168.80.1" "192.168.100.1" ""); then
            log_info "GPS Result: $gps_result"
        else
            log_warning "No valid GPS sources available in demo mode"
        fi

        echo ""
    fi

    log_step "Displaying integration instructions"
    show_integration_instructions

    log_info "GPS integration setup completed"
    log_info "Next steps:"
    log_info "1. Review integration instructions above"
    log_info "2. Add GPS collection to starlink_monitor_unified-rutos.sh"
    log_info "3. Test with real RUTOS and Starlink hardware"
    log_info "4. Enable location-based failover analysis"
}

# Execute main function
main "$@"
