#!/bin/sh
# Script: gps-location-analyzer-rutos.sh
# Version: 2.7.0
# Description: Location clustering and analysis for GPS data with motorhome-specific features
# Integrates with gps-collector-rutos.sh and existing configuration

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
# shellcheck disable=SC2034  # Used in some conditional contexts
PURPLE='\033[0;35m'
# shellcheck disable=SC2034  # Used in debug logging functions
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
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Configuration file path
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-monitor/config.sh}"

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_debug "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        log_debug "Configuration loaded successfully"
    else
        log_warning "Configuration file not found: $CONFIG_FILE"
        log_info "Using fallback defaults"
    fi

    # GPS Analysis Configuration with defaults
    GPS_CLUSTERING_DISTANCE="${GPS_CLUSTERING_DISTANCE:-50}" # meters
    GPS_SPEED_THRESHOLD="${GPS_SPEED_THRESHOLD:-5}"          # km/h
    GPS_NO_DATA_VALUE="${GPS_NO_DATA_VALUE:-N/A}"            # N/A or 0
    MIN_EVENTS_PER_LOCATION="${MIN_EVENTS_PER_LOCATION:-2}"  # Minimum events for problematic location
    MIN_TIME_AT_LOCATION="${MIN_TIME_AT_LOCATION:-3600}"     # Minimum seconds at location (1 hour default)
    PARKED_ONLY_CLUSTERING="${PARKED_ONLY_CLUSTERING:-true}" # Only cluster when parked
}

# Haversine distance calculation (precise geographic distance)
haversine_distance() {
    lat1="$1"
    lon1="$2"
    lat2="$3"
    lon2="$4"

    # Convert to awk for floating point math (busybox compatible)
    awk -v lat1="$lat1" -v lon1="$lon1" -v lat2="$lat2" -v lon2="$lon2" '
    BEGIN {
        R = 6371000  # Earth radius in meters
        rad = 3.14159265359 / 180
        
        dLat = (lat2 - lat1) * rad
        dLon = (lon2 - lon1) * rad
        lat1_rad = lat1 * rad
        lat2_rad = lat2 * rad
        
        a = sin(dLat/2) * sin(dLat/2) + cos(lat1_rad) * cos(lat2_rad) * sin(dLon/2) * sin(dLon/2)
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        distance = R * c
        
        print distance
    }'
}

# Extract GPS coordinates from various log formats
extract_gps_from_logs() {
    log_dir="$1"
    output_file="$2"
    include_moving="${3:-false}" # Include moving vehicle data

    log_step "Extracting GPS coordinates from logs in: $log_dir"

    >"$output_file" # Clear output file

    # Process all log files
    find "$log_dir" -name "*.log" -type f | while read -r logfile; do
        log_debug "Processing log file: $logfile"

        # Extract GPS data in various formats
        # Format 1: GPS: source=rutos, lat=59.8586, lon=17.6389, alt=45m, fix=1, acc=1.2m, sats=12, speed=0km/h
        grep "GPS:" "$logfile" | while read -r line; do
            # Extract coordinates using pattern matching
            lat=$(echo "$line" | sed -n 's/.*lat=\([0-9\.-]*\).*/\1/p')
            lon=$(echo "$line" | sed -n 's/.*lon=\([0-9\.-]*\).*/\1/p')
            speed=$(echo "$line" | sed -n 's/.*speed=\([0-9\.-]*\)km\/h.*/\1/p')
            timestamp=$(echo "$line" | sed -n 's/^\[\([0-9: -]*\)\].*/\1/p')

            # Skip if coordinates are missing or invalid
            if [ -z "$lat" ] || [ -z "$lon" ] || [ "$lat" = "$GPS_NO_DATA_VALUE" ] || [ "$lon" = "$GPS_NO_DATA_VALUE" ]; then
                continue
            fi

            # Skip moving vehicles if parked-only clustering is enabled
            if [ "$include_moving" = "false" ] && [ "$PARKED_ONLY_CLUSTERING" = "true" ]; then
                speed_int=$(echo "$speed" | cut -d'.' -f1 2>/dev/null || echo "999")
                if [ "$speed_int" -gt "$GPS_SPEED_THRESHOLD" ] 2>/dev/null; then
                    log_debug "Skipping moving vehicle data: speed=${speed}km/h > ${GPS_SPEED_THRESHOLD}km/h"
                    continue
                fi
            fi

            echo "$timestamp,$lat,$lon,$speed" >>"$output_file"
        done

        # Format 2: Enhanced metrics with GPS data
        grep "ENHANCED METRICS:" "$logfile" | grep "GPS:" | while read -r line; do
            lat=$(echo "$line" | sed -n 's/.*lat=\([0-9\.-]*\).*/\1/p')
            lon=$(echo "$line" | sed -n 's/.*lon=\([0-9\.-]*\).*/\1/p')
            speed=$(echo "$line" | sed -n 's/.*speed=\([0-9\.-]*\).*/\1/p')
            timestamp=$(echo "$line" | sed -n 's/^\[\([0-9: -]*\)\].*/\1/p')

            if [ -z "$lat" ] || [ -z "$lon" ] || [ "$lat" = "$GPS_NO_DATA_VALUE" ] || [ "$lon" = "$GPS_NO_DATA_VALUE" ]; then
                continue
            fi

            if [ "$include_moving" = "false" ] && [ "$PARKED_ONLY_CLUSTERING" = "true" ]; then
                speed_int=$(echo "$speed" | cut -d'.' -f1 2>/dev/null || echo "999")
                if [ "$speed_int" -gt "$GPS_SPEED_THRESHOLD" ] 2>/dev/null; then
                    continue
                fi
            fi

            echo "$timestamp,$lat,$lon,$speed" >>"$output_file"
        done
    done

    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        coord_count=$(wc -l <"$output_file" | tr -d ' \n\r')
        log_info "Extracted $coord_count GPS coordinate entries"

        if [ "$PARKED_ONLY_CLUSTERING" = "true" ]; then
            log_info "Filtering: Parked vehicles only (speed ≤ ${GPS_SPEED_THRESHOLD}km/h)"
        else
            log_info "Filtering: All vehicle states included"
        fi
    else
        log_warning "No GPS coordinates found in logs"
        # Create demo data for testing
        echo "2025-07-25 12:00:00,59.8586,17.6389,0" >"$output_file"
        echo "2025-07-25 12:05:00,59.8586,17.6389,1" >>"$output_file"
        echo "2025-07-25 13:00:00,59.9586,17.7389,0" >>"$output_file"
        log_info "Created demo GPS data for testing"
    fi
}

# Calculate time duration at location in seconds
calculate_time_duration() {
    first_time="$1"
    last_time="$2"

    # Convert timestamps to epoch seconds for calculation
    # Format: "2025-07-25 12:34:56"
    first_epoch=$(date -d "$first_time" +%s 2>/dev/null || echo "0")
    last_epoch=$(date -d "$last_time" +%s 2>/dev/null || echo "0")

    if [ "$first_epoch" -gt 0 ] && [ "$last_epoch" -gt 0 ]; then
        duration=$((last_epoch - first_epoch))
        echo "$duration"
    else
        echo "0"
    fi
}

# Cluster locations based on proximity, parked status, and time duration
cluster_locations() {
    coords_file="$1"
    clusters_file="$2"

    log_step "Clustering locations within ${GPS_CLUSTERING_DISTANCE}m radius"
    log_info "Minimum time at location: ${MIN_TIME_AT_LOCATION}s ($(echo "$MIN_TIME_AT_LOCATION / 3600" | awk '{printf "%.1f", $1}')h)"

    if [ "$GPS_CLUSTERING_DISTANCE" -eq 0 ] 2>/dev/null; then
        log_info "Clustering disabled (distance = 0m)"
        # Create individual clusters for each coordinate with time validation
        cluster_id=1
        >"$clusters_file"
        temp_location_file="/tmp/location_tracking_$$"
        >"$temp_location_file"

        # Group by exact coordinates to calculate time duration
        while IFS=',' read -r timestamp lat lon speed; do
            if [ -n "$lat" ] && [ -n "$lon" ]; then
                echo "$timestamp,$lat,$lon,$speed" >>"$temp_location_file"
            fi
        done <"$coords_file"

        # Process grouped locations
        sort -t',' -k2,3 "$temp_location_file" | awk -F',' '
        {
            key = $2 "," $3
            if (key != prev_key) {
                if (prev_key != "" && count >= 1) {
                    print prev_first_time "," prev_key "," count "," prev_first_time "," prev_last_time
                }
                prev_key = key
                prev_first_time = $1
                prev_last_time = $1
                count = 1
            } else {
                prev_last_time = $1
                count++
            }
        }
        END {
            if (prev_key != "" && count >= 1) {
                print prev_first_time "," prev_key "," count "," prev_first_time "," prev_last_time
            }
        }' | while IFS=',' read -r timestamp lat lon count first_time last_time; do
            # Calculate time duration at this location
            duration=$(calculate_time_duration "$first_time" "$last_time")

            if [ "$duration" -ge "$MIN_TIME_AT_LOCATION" ]; then
                echo "$lat,$lon,$cluster_id,$count,$first_time,$last_time,${duration}s" >>"$clusters_file"
                cluster_id=$((cluster_id + 1))
                log_debug "Added location cluster: $lat,$lon (${duration}s duration, $count readings)"
            else
                log_debug "Skipped short-duration location: $lat,$lon (${duration}s < ${MIN_TIME_AT_LOCATION}s)"
            fi
        done

        rm -f "$temp_location_file"
        return 0
    fi

    cluster_id=1
    >"$clusters_file" # Clear clusters file
    temp_clusters="/tmp/temp_clusters_$$"
    >"$temp_clusters"

    # First pass: Group coordinates into potential clusters
    while IFS=',' read -r timestamp lat lon speed; do
        # Skip invalid coordinates
        if [ -z "$lat" ] || [ -z "$lon" ]; then
            continue
        fi

        # Check if this coordinate belongs to an existing cluster
        found_cluster=""
        if [ -f "$temp_clusters" ] && [ -s "$temp_clusters" ]; then
            while IFS=',' read -r cluster_lat cluster_lon cluster_id_existing readings_data; do
                distance=$(haversine_distance "$lat" "$lon" "$cluster_lat" "$cluster_lon")
                distance_int=$(echo "$distance" | cut -d'.' -f1)

                if [ "$distance_int" -lt "$GPS_CLUSTERING_DISTANCE" ]; then
                    found_cluster="$cluster_id_existing"
                    # Add this reading to the cluster
                    new_readings="$readings_data|$timestamp"
                    # Update the cluster entry
                    temp_file="/tmp/clusters_update_$$"
                    grep -v "^$cluster_lat,$cluster_lon,$cluster_id_existing," "$temp_clusters" >"$temp_file" || true
                    echo "$cluster_lat,$cluster_lon,$cluster_id_existing,$new_readings" >>"$temp_file"
                    mv "$temp_file" "$temp_clusters"
                    break
                fi
            done <"$temp_clusters"
        fi

        # If no cluster found, create new one
        if [ -z "$found_cluster" ]; then
            echo "$lat,$lon,$cluster_id,$timestamp" >>"$temp_clusters"
            cluster_id=$((cluster_id + 1))
        fi
    done <"$coords_file"

    # Second pass: Validate clusters against time duration requirement
    if [ -f "$temp_clusters" ] && [ -s "$temp_clusters" ]; then
        while IFS=',' read -r lat lon cluster_id readings_data; do
            # Extract first and last timestamps from readings
            first_time=$(echo "$readings_data" | cut -d'|' -f1)
            last_time=$(echo "$readings_data" | rev | cut -d'|' -f1 | rev)
            reading_count=$(echo "$readings_data" | tr '|' '\n' | wc -l | tr -d ' \n\r')

            # Calculate time duration at this location
            duration=$(calculate_time_duration "$first_time" "$last_time")

            if [ "$duration" -ge "$MIN_TIME_AT_LOCATION" ]; then
                echo "$lat,$lon,$cluster_id,$reading_count,$first_time,$last_time,${duration}s" >>"$clusters_file"
                log_debug "Validated cluster $cluster_id: $lat,$lon (${duration}s duration, $reading_count readings)"
            else
                log_debug "Rejected cluster $cluster_id: $lat,$lon (${duration}s < ${MIN_TIME_AT_LOCATION}s required)"
            fi
        done <"$temp_clusters"
    fi

    # Cleanup temp files
    rm -f "$temp_clusters"

    if [ -f "$clusters_file" ] && [ -s "$clusters_file" ]; then
        cluster_count=$(wc -l <"$clusters_file" | tr -d ' \n\r')
        log_info "Created $cluster_count valid location clusters (≥${MIN_TIME_AT_LOCATION}s duration)"

        # Show summary of rejected short-duration locations
        total_potential=$(wc -l <"/tmp/temp_clusters_rejected_$$" 2>/dev/null | tr -d ' \n\r' || echo "0")
        if [ "$total_potential" -gt 0 ]; then
            rejected_count=$((total_potential - cluster_count))
            log_info "Rejected $rejected_count short-duration locations (< $(echo "$MIN_TIME_AT_LOCATION / 3600" | awk '{printf "%.1f", $1}')h)"
        fi
    else
        log_warning "No location clusters met minimum time requirement"
        log_info "Consider reducing MIN_TIME_AT_LOCATION from ${MIN_TIME_AT_LOCATION}s if no results"
    fi
}

# Generate comprehensive location analysis report
generate_location_analysis() {
    coords_file="$1"
    clusters_file="$2"
    output_file="$3"

    log_step "Generating comprehensive location analysis report"

    # Create detailed analysis report
    cat >"$output_file" <<'EOF'
# GPS-Based Location Analysis Report

## Overview

This analysis clusters GPS coordinates by geographical location to identify patterns in connectivity and failover events, with specific optimizations for motorhome and RV use cases.

## Methodology

### Clustering Configuration
EOF

    # Add current configuration to report
    echo "- **Clustering Distance**: ${GPS_CLUSTERING_DISTANCE}m radius" >>"$output_file"
    echo "- **Speed Threshold**: ${GPS_SPEED_THRESHOLD}km/h (parked vs moving)" >>"$output_file"
    echo "- **Minimum Location Duration**: ${MIN_TIME_AT_LOCATION}s ($(echo "$MIN_TIME_AT_LOCATION / 3600" | awk '{printf "%.1f", $1}')h)" >>"$output_file"
    echo "- **Parked-Only Analysis**: $PARKED_ONLY_CLUSTERING" >>"$output_file"
    echo "- **Minimum Events for Problematic Location**: $MIN_EVENTS_PER_LOCATION" >>"$output_file"
    echo "- **No Data Handling**: $GPS_NO_DATA_VALUE" >>"$output_file"
    echo "" >>"$output_file"

    cat >>"$output_file" <<'EOF'
### GPS Source Selection
- **Primary**: RUTOS GPS (2m accuracy threshold) for high precision
- **Backup**: Starlink GPS (10m accuracy threshold) for coverage
- **Selection Logic**: Best accuracy wins when both available

### Motorhome-Specific Features
- **Parked Vehicle Focus**: Only analyzes stationary periods for camping/parking patterns
- **Movement Detection**: Filters out driving data to focus on destination analysis
- **Clustering Radius**: Optimized for motorhome parking area sizes

## Location Clusters and Analysis

EOF

    cluster_num=1
    total_locations=0
    problematic_locations=0
    total_events=0

    if [ -f "$clusters_file" ] && [ -s "$clusters_file" ]; then
        while IFS=',' read -r lat lon cluster_id count first_seen last_seen duration; do
            total_locations=$((total_locations + 1))
            total_events=$((total_events + count))

            # Calculate duration in hours for display
            duration_seconds=$(echo "$duration" | sed 's/s$//')
            duration_hours=$(echo "$duration_seconds / 3600" | awk '{printf "%.1f", $1}')
            duration_minutes=$(echo "$duration_seconds / 60" | awk '{printf "%.0f", $1}')

            echo "### Location Cluster $cluster_num" >>"$output_file"
            echo "" >>"$output_file"
            echo "- **Coordinates**: $lat, $lon" >>"$output_file"
            echo "- **Cluster ID**: $cluster_id" >>"$output_file"
            echo "- **GPS Readings**: $count readings" >>"$output_file"
            echo "- **Duration at Location**: ${duration_hours}h (${duration_minutes}m)" >>"$output_file"
            echo "- **First Seen**: $first_seen" >>"$output_file"
            echo "- **Last Seen**: $last_seen" >>"$output_file"

            # Determine if this is a problematic location
            if [ "$count" -ge "$MIN_EVENTS_PER_LOCATION" ]; then
                problematic_locations=$((problematic_locations + 1))
                echo "- **Status**: ⚠️ **PROBLEMATIC LOCATION** - Multiple connectivity issues" >>"$output_file"
                echo "- **Risk Level**: HIGH - Requires investigation" >>"$output_file"
                echo "- **Analysis**: Extended stay (${duration_hours}h) with connectivity problems" >>"$output_file"
                echo "- **Recommendations**:" >>"$output_file"
                echo "  - Survey local environment for permanent obstructions" >>"$output_file"
                echo "  - Test different parking orientations for optimal Starlink view" >>"$output_file"
                echo "  - Consider alternative parking areas within same location" >>"$output_file"
                echo "  - Document interference sources (buildings, trees, terrain)" >>"$output_file"
                echo "  - **Priority**: High - Avoid this specific location for extended stays" >>"$output_file"
            else
                echo "- **Status**: ✅ **NORMAL LOCATION** - Reliable connectivity" >>"$output_file"
                echo "- **Risk Level**: LOW - Good camping location" >>"$output_file"
                echo "- **Analysis**: Extended stay (${duration_hours}h) with stable connectivity" >>"$output_file"
                echo "- **Assessment**: Suitable for future camping at this location" >>"$output_file"
            fi

            echo "" >>"$output_file"
            cluster_num=$((cluster_num + 1))
        done <"$clusters_file"
    else
        echo "No location clusters found in analysis." >>"$output_file"
        echo "" >>"$output_file"
    fi

    # Add comprehensive summary statistics
    cat >>"$output_file" <<EOF

## Summary Statistics

### Location Analysis
- **Total Location Clusters**: $total_locations
- **Total Events Analyzed**: $total_events
- **Problematic Locations**: $problematic_locations (≥$MIN_EVENTS_PER_LOCATION events)
- **Normal Locations**: $((total_locations - problematic_locations))
- **Clustering Distance**: ${GPS_CLUSTERING_DISTANCE}m radius

### Risk Assessment
EOF

    if [ "$total_locations" -gt 0 ]; then
        risk_percentage=$((problematic_locations * 100 / total_locations))
        echo "- **Risk Percentage**: ${risk_percentage}% of locations show connectivity issues" >>"$output_file"

        if [ "$risk_percentage" -lt 20 ]; then
            echo "- **Overall Assessment**: ✅ **LOW RISK** - Excellent connectivity pattern" >>"$output_file"
        elif [ "$risk_percentage" -lt 50 ]; then
            echo "- **Overall Assessment**: ⚠️ **MODERATE RISK** - Some problem areas identified" >>"$output_file"
        else
            echo "- **Overall Assessment**: 🚨 **HIGH RISK** - Multiple problematic locations" >>"$output_file"
        fi
    else
        echo "- **Overall Assessment**: ❓ **INSUFFICIENT DATA** - Need more GPS data" >>"$output_file"
    fi

    cat >>"$output_file" <<EOF

## Motorhome Travel Insights

### Parking Optimization Strategy
EOF

    if [ "$problematic_locations" -gt 0 ]; then
        cat >>"$output_file" <<EOF
- **Avoid Problematic Locations**: $problematic_locations locations identified for alternative parking
- **Orientation Testing**: Test different parking angles at problem locations
- **Site Selection**: Choose open areas away from tall obstacles
- **Elevation Advantage**: Seek higher ground for better satellite visibility
EOF
    else
        cat >>"$output_file" <<EOF
- **Excellent Track Record**: No problematic locations identified
- **Current Strategy Working**: Continue with current site selection approach
- **Maintain Vigilance**: Monitor new locations for potential issues
EOF
    fi

    cat >>"$output_file" <<EOF

### Speed-Based Analysis
- **Parked Threshold**: ≤${GPS_SPEED_THRESHOLD}km/h considered stationary
- **Analysis Focus**: Camping/parking locations only
- **Moving Data**: Excluded from clustering (driving conditions differ)

### Future Travel Planning
- **Route Optimization**: Avoid known problematic areas when possible
- **Backup Planning**: Identify alternative parking near problem locations
- **Equipment Checks**: Schedule antenna/equipment maintenance for problem areas
- **Documentation**: Maintain log of successful vs. problematic camping locations

## Technical Implementation

### Configuration Integration
All settings are managed through the existing Starlink monitor configuration:
\`\`\`bash
# GPS Analysis Settings in $CONFIG_FILE
GPS_CLUSTERING_DISTANCE="$GPS_CLUSTERING_DISTANCE"        # Cluster radius in meters
GPS_SPEED_THRESHOLD="$GPS_SPEED_THRESHOLD"                # Parked vs moving threshold
PARKED_ONLY_CLUSTERING="$PARKED_ONLY_CLUSTERING"         # Focus on stationary analysis
MIN_EVENTS_PER_LOCATION="$MIN_EVENTS_PER_LOCATION"       # Problematic location threshold
\`\`\`

### Data Sources
- **Primary GPS**: RUTOS device (high accuracy)
- **Backup GPS**: Starlink diagnostics (coverage)
- **Log Integration**: Existing Starlink monitor logs
- **Real-time Collection**: Integrated with monitoring system

### Analysis Features
- **Haversine Distance**: Precise geographic calculations
- **Speed Filtering**: Focuses on relevant stationary periods
- **Quality Assessment**: Multi-. GPS reliability
- **Configurable Clustering**: Adaptable to different use cases

## Recommendations

### For Current Configuration
EOF

    if [ "$GPS_CLUSTERING_DISTANCE" -eq 0 ]; then
        echo "- **Enable Clustering**: Set GPS_CLUSTERING_DISTANCE to 50m for motorhome analysis" >>"$output_file"
    elif [ "$GPS_CLUSTERING_DISTANCE" -gt 100 ]; then
        echo "- **Reduce Cluster Size**: Consider smaller radius (50m) for precise parking analysis" >>"$output_file"
    else
        echo "- **Clustering Optimal**: Current ${GPS_CLUSTERING_DISTANCE}m radius appropriate for motorhome use" >>"$output_file"
    fi

    if [ "$PARKED_ONLY_CLUSTERING" = "false" ]; then
        echo "- **Enable Parked Focus**: Set PARKED_ONLY_CLUSTERING=true for camping analysis" >>"$output_file"
    else
        echo "- **Parked Focus Enabled**: Correctly focusing on stationary periods" >>"$output_file"
    fi

    cat >>"$output_file" <<EOF

### For Enhanced Analysis
- **Regular Review**: Analyze location patterns monthly during travel season
- **Seasonal Patterns**: Compare connectivity across different travel periods
- **Equipment Correlation**: Track antenna positioning effectiveness
- **Weather Integration**: Correlate connectivity with weather patterns

### Integration Opportunities
- **Navigation Systems**: Import problematic locations to GPS/mapping software
- **Travel Planning**: Use data for campground selection and route planning
- **Community Sharing**: Share successful locations with other motorhome travelers
- **Predictive Alerts**: Implement warnings when approaching known problem areas

EOF

    log_success "Location analysis report generated: $output_file"

    # Display summary to user
    echo ""
    log_step "Analysis Summary:"
    log_info "📍 Total location clusters: $total_locations"
    log_info "📊 Total events analyzed: $total_events"

    if [ "$problematic_locations" -gt 0 ]; then
        log_warning "⚠️  Problematic locations: $problematic_locations"
        echo ""
        log_warning "Problematic locations requiring attention:"
        cluster_num=1
        while IFS=',' read -r lat lon cluster_id count first_seen; do
            if [ "$count" -ge "$MIN_EVENTS_PER_LOCATION" ]; then
                printf "  🚨 Cluster %s: %.6f, %.6f (%d events)\n" "$cluster_id" "$lat" "$lon" "$count"
            fi
            cluster_num=$((cluster_num + 1))
        done <"$clusters_file"
    else
        log_success "✅ No problematic locations identified"
    fi
}

# Usage information
show_usage() {
    cat <<EOF

Usage: $0 [options] <log_directory>

Options:
    --include-moving        Include moving vehicle data in analysis
    --config <file>         Use specific configuration file
    --output <file>         Specify output report filename
    --help                  Show this help message

Arguments:
    <log_directory>         Directory containing log files to analyze

Configuration:
    Edit $CONFIG_FILE to configure analysis settings:
    
    GPS_CLUSTERING_DISTANCE="50"           # meters (0=disabled, 5, 10, 50, 500)
    GPS_SPEED_THRESHOLD="5"                # km/h (below = parked)
    PARKED_ONLY_CLUSTERING="true"          # Focus on stationary periods
    MIN_EVENTS_PER_LOCATION="2"            # Events for problematic classification
    MIN_TIME_AT_LOCATION="3600"            # Minimum seconds at location (1 hour)
    GPS_NO_DATA_VALUE="N/A"                # How to handle missing GPS data

Examples:
    $0 /var/log/starlink                   # Analyze logs in directory
    $0 --include-moving /tmp/logs          # Include moving vehicle data
    $0 --output custom_report.md /logs     # Custom output filename
    
EOF
}

# Main function
main() {
    # Load configuration
    load_config

    # Parse command line arguments
    include_moving="false"
    output_file=""
    log_directory=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --include-moving)
                include_moving="true"
                ;;
            --config)
                shift
                CONFIG_FILE="$1"
                load_config # Reload with new config
                ;;
            --output)
                shift
                output_file="$1"
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$log_directory" ]; then
                    log_directory="$1"
                else
                    log_error "Multiple directories specified. Use only one."
                    show_usage
                    exit 1
                fi
                ;;
        esac
        shift
    done

    # Validate arguments
    if [ -z "$log_directory" ]; then
        log_error "Log directory not specified"
        show_usage
        exit 1
    fi

    if [ ! -d "$log_directory" ]; then
        log_error "Log directory not found: $log_directory"
        exit 1
    fi

    # Set default output file if not specified
    if [ -z "$output_file" ]; then
        output_file="$log_directory/gps_location_analysis_$(date '+%Y%m%d_%H%M%S').md"
    fi

    log_info "Starting GPS Location Analysis v$SCRIPT_VERSION"
    log_info "Log Directory: $log_directory"
    log_info "Output Report: $output_file"
    log_info "Clustering Distance: ${GPS_CLUSTERING_DISTANCE}m"
    log_info "Include Moving Data: $include_moving"

    # Create temporary files
    coords_file="/tmp/gps_coordinates_$$"
    clusters_file="/tmp/location_clusters_$$"

    # Extract GPS coordinates from logs
    extract_gps_from_logs "$log_directory" "$coords_file" "$include_moving"

    # Cluster locations by proximity
    cluster_locations "$coords_file" "$clusters_file"

    # Generate comprehensive analysis report
    generate_location_analysis "$coords_file" "$clusters_file" "$output_file"

    # Cleanup temporary files
    rm -f "$coords_file" "$clusters_file"

    log_success "GPS location analysis completed successfully"
    log_info "Full report available at: $output_file"
}

# Execute main function
main "$@"
