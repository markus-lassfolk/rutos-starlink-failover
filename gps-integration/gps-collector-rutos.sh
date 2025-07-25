#!/bin/sh
# Script: gps-collector-rutos.sh
# Version: 2.7.0
# Description: Unified GPS data collection from RUTOS and Starlink with intelligent . selection
# Based on Victron Node-RED approach with RUTOS config integration

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

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
    # shellcheck disable=SC2034  # Used in some conditional contexts
    PURPLE=""
    # shellcheck disable=SC2034  # Used in debug logging functions
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

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Configuration file path
CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-monitor/config.sh}"

# Load configuration with fallback defaults
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

    # GPS Configuration with defaults
    GPS_PRIMARY_SOURCE="${GPS_PRIMARY_SOURCE:-auto}"                         # auto, rutos, starlink
    GPS_BACKUP_SOURCE="${GPS_BACKUP_SOURCE:-auto}"                           # auto, rutos, starlink
    GPS_CLUSTERING_DISTANCE="${GPS_CLUSTERING_DISTANCE:-50}"                 # meters (0=disabled, 5, 10, 50, 500)
    GPS_RUTOS_ACCURACY_THRESHOLD="${GPS_RUTOS_ACCURACY_THRESHOLD:-2}"        # meters
    GPS_STARLINK_ACCURACY_THRESHOLD="${GPS_STARLINK_ACCURACY_THRESHOLD:-10}" # meters
    GPS_SPEED_THRESHOLD="${GPS_SPEED_THRESHOLD:-5}"                          # km/h - below this is considered "parked"
    GPS_NO_DATA_VALUE="${GPS_NO_DATA_VALUE:-N/A}"                            # N/A or 0 for missing data

    # Existing configuration (reuse from starlink-monitor)
    STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
    RUTOS_IP="${RUTOS_IP:-192.168.80.1}"
    RUTOS_USERNAME="${RUTOS_USERNAME:-admin}"
    RUTOS_PASSWORD="${RUTOS_PASSWORD:-}"

    log_debug "GPS Primary Source: $GPS_PRIMARY_SOURCE"
    log_debug "GPS Clustering Distance: ${GPS_CLUSTERING_DISTANCE}m"
    log_debug "GPS Speed Threshold: ${GPS_SPEED_THRESHOLD} km/h"
    log_debug "GPS No Data Value: $GPS_NO_DATA_VALUE"
}

# RUTOS authentication token management
get_rutos_auth_token() {
    rutos_ip="$1"
    username="$2"
    password="$3"

    if [ -z "$password" ]; then
        log_debug "No RUTOS password provided, skipping authentication"
        return 1
    fi

    log_debug "Attempting RUTOS authentication to $rutos_ip"

    # Create login payload
    login_data="{\"username\":\"$username\",\"password\":\"$password\"}"

    # Authenticate and extract token
    auth_response=$(curl -s -k -X POST \
        -H "Content-Type: application/json" \
        -d "$login_data" \
        "https://$rutos_ip/api/login" 2>/dev/null)

    if curl -s -k -X POST -H "Content-Type: application/json" -d "$login_data" "https://$rutos_ip/api/login" >/dev/null 2>&1 && [ -n "$auth_response" ]; then
        # Extract token using basic string manipulation (busybox compatible)
        token=$(echo "$auth_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$token" ]; then
            log_debug "RUTOS authentication successful"
            echo "$token"
            return 0
        fi
    fi

    log_debug "RUTOS authentication failed"
    return 1
}

# Collect GPS from RUTOS API (high accuracy source)
get_rutos_gps() {
    rutos_ip="$1"
    auth_token="$2"

    if [ -z "$auth_token" ]; then
        log_debug "No RUTOS auth token provided, skipping RUTOS GPS"
        return 1
    fi

    log_debug "Collecting GPS data from RUTOS: $rutos_ip"

    # Make authenticated request to RUTOS GPS API
    gps_data=$(curl -s -k -H "Authorization: Bearer $auth_token" \
        "https://$rutos_ip/api/gps/position/status" 2>/dev/null)

    if [ -n "$gps_data" ] && echo "$gps_data" | grep -q '"latitude"'; then
        # Parse GPS data (busybox-compatible parsing)
        lat=$(echo "$gps_data" | grep -o '"latitude":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        lon=$(echo "$gps_data" | grep -o '"longitude":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        alt=$(echo "$gps_data" | grep -o '"altitude":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        fix=$(echo "$gps_data" | grep -o '"fix_status":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        acc=$(echo "$gps_data" | grep -o '"accuracy":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        sats=$(echo "$gps_data" | grep -o '"satellites":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')
        speed=$(echo "$gps_data" | grep -o '"speed":[^,}]*' | cut -d':' -f2 | tr -d '"' | tr -d ' ')

        log_debug "RUTOS GPS raw: lat=$lat, lon=$lon, fix=$fix, acc=$acc"

        # Quality check: GPS fix > 0 and accuracy within threshold
        if [ -n "$lat" ] && [ -n "$lon" ] && [ -n "$fix" ] && [ "$fix" -gt 0 ] 2>/dev/null; then
            # Check accuracy threshold
            acc_int=$(echo "$acc" | cut -d'.' -f1)
            if [ -n "$acc_int" ] && [ "$acc_int" -le "$GPS_RUTOS_ACCURACY_THRESHOLD" ] 2>/dev/null; then
                # Convert speed from km/h to ensure consistency
                speed_kmh="$speed"
                if [ -z "$speed_kmh" ]; then
                    speed_kmh="0"
                fi

                echo "rutos|$lat|$lon|$alt|$fix|$acc|$sats|$speed_kmh"
                log_debug "RUTOS GPS: VALID (accuracy: ${acc}m, threshold: ${GPS_RUTOS_ACCURACY_THRESHOLD}m)"
                return 0
            else
                log_debug "RUTOS GPS: REJECTED (accuracy: ${acc}m > threshold: ${GPS_RUTOS_ACCURACY_THRESHOLD}m)"
            fi
        else
            log_debug "RUTOS GPS: INVALID (no fix or missing coordinates)"
        fi
    else
        log_debug "RUTOS GPS: API request failed"
    fi

    return 1
}

# Collect GPS from Starlink diagnostics (backup source)
get_starlink_gps() {
    starlink_ip="$1"

    log_debug "Collecting GPS data from Starlink: $starlink_ip"

    # Check for grpcurl availability
    if ! command -v grpcurl >/dev/null 2>&1; then
        log_debug "grpcurl not found, cannot collect Starlink GPS data"
        return 1
    fi

    # Use grpcurl like in Victron flow
    diag_data=$(grpcurl -plaintext -emit-defaults -d '{"get_diagnostics":{}}' \
        "$starlink_ip:9200" SpaceX.API.Device.Device/Handle 2>/dev/null)

    if [ -n "$diag_data" ] && echo "$diag_data" | grep -q '"latitude"'; then
        # Extract location data from diagnostics (busybox-compatible)
        lat=$(echo "$diag_data" | grep -o '"latitude":[^,}]*' | head -1 | cut -d':' -f2 | tr -d ' ')
        lon=$(echo "$diag_data" | grep -o '"longitude":[^,}]*' | head -1 | cut -d':' -f2 | tr -d ' ')
        alt=$(echo "$diag_data" | grep -o '"altitudeMeters":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        unc=$(echo "$diag_data" | grep -o '"uncertaintyMeters":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        valid=$(echo "$diag_data" | grep -o '"uncertaintyMetersValid":[^,}]*' | cut -d':' -f2 | tr -d ' ' | tr -d 'true' | tr -d 'false')

        log_debug "Starlink GPS raw: lat=$lat, lon=$lon, valid=$valid, unc=$unc"

        # Quality check: valid coordinates and accuracy within threshold
        if [ -n "$lat" ] && [ -n "$lon" ] && [ "$valid" = "true" ]; then
            unc_int=$(echo "$unc" | cut -d'.' -f1)
            if [ -n "$unc_int" ] && [ "$unc_int" -le "$GPS_STARLINK_ACCURACY_THRESHOLD" ] 2>/dev/null; then
                fix=1   # Assume fix if data is valid
                sats=0  # Starlink doesn't provide satellite count in diagnostics
                speed=0 # Starlink doesn't provide speed in diagnostics

                echo "starlink|$lat|$lon|$alt|$fix|$unc|$sats|$speed"
                log_debug "Starlink GPS: VALID (uncertainty: ${unc}m, threshold: ${GPS_STARLINK_ACCURACY_THRESHOLD}m)"
                return 0
            else
                log_debug "Starlink GPS: REJECTED (uncertainty: ${unc}m > threshold: ${GPS_STARLINK_ACCURACY_THRESHOLD}m)"
            fi
        else
            log_debug "Starlink GPS: INVALID (not valid or missing coordinates)"
        fi
    else
        log_debug "Starlink GPS: grpcurl request failed"
    fi

    return 1
}

# Select best GPS . using Victron intelligent selection logic
select_best_gps() {
    rutos_gps="$1"
    starlink_gps="$2"
    primary_source="$3"

    # Parse GPS data quality
    if [ -n "$rutos_gps" ]; then
        rutos_acc=$(echo "$rutos_gps" | cut -d'|' -f6)
        rutos_fix=$(echo "$rutos_gps" | cut -d'|' -f5)
        good_rutos=0
        if [ "$rutos_fix" -gt 0 ] 2>/dev/null; then
            rutos_acc_int=$(echo "$rutos_acc" | cut -d'.' -f1)
            if [ "$rutos_acc_int" -le "$GPS_RUTOS_ACCURACY_THRESHOLD" ] 2>/dev/null; then
                good_rutos=1
            fi
        fi
    else
        good_rutos=0
    fi

    if [ -n "$starlink_gps" ]; then
        starlink_acc=$(echo "$starlink_gps" | cut -d'|' -f6)
        starlink_fix=$(echo "$starlink_gps" | cut -d'|' -f5)
        good_starlink=0
        if [ "$starlink_fix" -gt 0 ] 2>/dev/null; then
            starlink_acc_int=$(echo "$starlink_acc" | cut -d'.' -f1)
            if [ "$starlink_acc_int" -le "$GPS_STARLINK_ACCURACY_THRESHOLD" ] 2>/dev/null; then
                good_starlink=1
            fi
        fi
    else
        good_starlink=0
    fi

    log_debug "GPS quality assessment: RUTOS=$good_rutos, Starlink=$good_starlink, Primary=$primary_source"

    # Selection logic based on configuration
    case "$primary_source" in
        "rutos")
            if [ "$good_rutos" -eq 1 ]; then
                echo "$rutos_gps"
                log_debug "GPS selection: RUTOS (forced primary)"
                return 0
            elif [ "$good_starlink" -eq 1 ]; then
                echo "$starlink_gps"
                log_debug "GPS selection: Starlink (RUTOS primary failed, backup)"
                return 0
            fi
            ;;
        "starlink")
            if [ "$good_starlink" -eq 1 ]; then
                echo "$starlink_gps"
                log_debug "GPS selection: Starlink (forced primary)"
                return 0
            elif [ "$good_rutos" -eq 1 ]; then
                echo "$rutos_gps"
                log_debug "GPS selection: RUTOS (Starlink primary failed, backup)"
                return 0
            fi
            ;;
        "auto" | *)
            # Victron intelligent selection: both good = best accuracy, otherwise prefer RUTOS
            if [ "$good_rutos" -eq 1 ] && [ "$good_starlink" -eq 1 ]; then
                # Both good, select better accuracy
                rutos_acc_int=$(echo "$rutos_acc" | cut -d'.' -f1)
                starlink_acc_int=$(echo "$starlink_acc" | cut -d'.' -f1)
                if [ "$rutos_acc_int" -le "$starlink_acc_int" ] 2>/dev/null; then
                    echo "$rutos_gps"
                    log_debug "GPS selection: RUTOS (auto, better accuracy: ${rutos_acc}m vs ${starlink_acc}m)"
                else
                    echo "$starlink_gps"
                    log_debug "GPS selection: Starlink (auto, better accuracy: ${starlink_acc}m vs ${rutos_acc}m)"
                fi
                return 0
            elif [ "$good_rutos" -eq 1 ]; then
                echo "$rutos_gps"
                log_debug "GPS selection: RUTOS (auto, only good source)"
                return 0
            elif [ "$good_starlink" -eq 1 ]; then
                echo "$starlink_gps"
                log_debug "GPS selection: Starlink (auto, only good source)"
                return 0
            fi
            ;;
    esac

    # No valid sources
    log_debug "GPS selection: NONE (no valid sources available)"
    return 1
}

# Format GPS data for output/logging
format_gps_output() {
    gps_data="$1"
    output_format="$2" # "log", "json", "csv"

    if [ -n "$gps_data" ]; then
        source=$(echo "$gps_data" | cut -d'|' -f1)
        lat=$(echo "$gps_data" | cut -d'|' -f2)
        lon=$(echo "$gps_data" | cut -d'|' -f3)
        alt=$(echo "$gps_data" | cut -d'|' -f4)
        fix=$(echo "$gps_data" | cut -d'|' -f5)
        acc=$(echo "$gps_data" | cut -d'|' -f6)
        sats=$(echo "$gps_data" | cut -d'|' -f7)
        speed=$(echo "$gps_data" | cut -d'|' -f8)

        case "$output_format" in
            "json")
                echo "{\"source\":\"$source\",\"lat\":$lat,\"lon\":$lon,\"alt\":$alt,\"fix\":$fix,\"acc\":$acc,\"sats\":$sats,\"speed\":$speed}"
                ;;
            "csv")
                echo "$source,$lat,$lon,$alt,$fix,$acc,$sats,$speed"
                ;;
            "log" | *)
                echo "GPS: source=$source, lat=$lat, lon=$lon, alt=${alt}m, fix=$fix, acc=${acc}m, sats=$sats, speed=${speed}km/h"
                ;;
        esac
    else
        case "$output_format" in
            "json")
                echo "{\"source\":\"none\",\"lat\":\"$GPS_NO_DATA_VALUE\",\"lon\":\"$GPS_NO_DATA_VALUE\",\"alt\":\"$GPS_NO_DATA_VALUE\",\"fix\":0,\"acc\":\"$GPS_NO_DATA_VALUE\",\"sats\":0,\"speed\":\"$GPS_NO_DATA_VALUE\"}"
                ;;
            "csv")
                echo "none,$GPS_NO_DATA_VALUE,$GPS_NO_DATA_VALUE,$GPS_NO_DATA_VALUE,0,$GPS_NO_DATA_VALUE,0,$GPS_NO_DATA_VALUE"
                ;;
            "log" | *)
                echo "GPS: source=none, status=no_valid_data, value=$GPS_NO_DATA_VALUE"
                ;;
        esac
    fi
}

# Determine if vehicle is parked (for clustering analysis)
is_vehicle_parked() {
    gps_data="$1"
    speed_threshold="$2"

    if [ -n "$gps_data" ]; then
        speed=$(echo "$gps_data" | cut -d'|' -f8)
        speed_int=$(echo "$speed" | cut -d'.' -f1)

        if [ -n "$speed_int" ] && [ "$speed_int" -le "$speed_threshold" ] 2>/dev/null; then
            return 0 # Parked
        else
            return 1 # Moving
        fi
    else
        return 1 # Unknown, assume moving
    fi
}

# Main GPS collection function
collect_gps_data() {
    output_format="${1:-log}" # log, json, csv

    log_step "Collecting GPS data from configured sources"

    # Get RUTOS authentication token if needed
    auth_token=""
    if [ "$GPS_PRIMARY_SOURCE" = "rutos" ] || [ "$GPS_PRIMARY_SOURCE" = "auto" ] || [ "$GPS_BACKUP_SOURCE" = "rutos" ]; then
        if [ -n "$RUTOS_PASSWORD" ]; then
            auth_token=$(get_rutos_auth_token "$RUTOS_IP" "$RUTOS_USERNAME" "$RUTOS_PASSWORD")
        fi
    fi

    # Collect from both sources
    rutos_gps=""
    starlink_gps=""

    if [ "$GPS_PRIMARY_SOURCE" = "rutos" ] || [ "$GPS_PRIMARY_SOURCE" = "auto" ] || [ "$GPS_BACKUP_SOURCE" = "rutos" ]; then
        rutos_gps=$(get_rutos_gps "$RUTOS_IP" "$auth_token")
    fi

    if [ "$GPS_PRIMARY_SOURCE" = "starlink" ] || [ "$GPS_PRIMARY_SOURCE" = "auto" ] || [ "$GPS_BACKUP_SOURCE" = "starlink" ]; then
        starlink_gps=$(get_starlink_gps "$STARLINK_IP")
    fi

    # Select best source
    best_gps=$(select_best_gps "$rutos_gps" "$starlink_gps" "$GPS_PRIMARY_SOURCE")

    if [ -n "$best_gps" ]; then
        # Check if vehicle is parked for clustering relevance
        if is_vehicle_parked "$best_gps" "$GPS_SPEED_THRESHOLD"; then
            parking_status="parked"
        else
            parking_status="moving"
        fi

        # Output GPS data in requested format
        gps_output=$(format_gps_output "$best_gps" "$output_format")
        echo "$gps_output"

        if [ "$output_format" = "log" ]; then
            log_info "Vehicle status: $parking_status (speed threshold: ${GPS_SPEED_THRESHOLD}km/h)"
            if [ "$GPS_CLUSTERING_DISTANCE" -gt 0 ] 2>/dev/null; then
                if [ "$parking_status" = "parked" ]; then
                    log_info "Clustering: ENABLED for parked vehicle (radius: ${GPS_CLUSTERING_DISTANCE}m)"
                else
                    log_info "Clustering: DISABLED for moving vehicle"
                fi
            else
                log_info "Clustering: DISABLED (distance = 0)"
            fi
        fi

        return 0
    else
        # No valid GPS sources
        no_data_output=$(format_gps_output "" "$output_format")
        echo "$no_data_output"

        if [ "$output_format" = "log" ]; then
            log_warning "No valid GPS sources available (ferry/covered scenario)"
        fi

        return 1
    fi
}

# Show configuration and test
show_config_and_test() {
    log_step "GPS Configuration Summary"
    echo ""
    printf "${BLUE}GPS Configuration:${NC}\n"
    printf "  Primary Source: %s\n" "$GPS_PRIMARY_SOURCE"
    printf "  Backup Source: %s\n" "$GPS_BACKUP_SOURCE"
    printf "  Clustering Distance: %sm\n" "$GPS_CLUSTERING_DISTANCE"
    printf "  RUTOS Accuracy Threshold: %sm\n" "$GPS_RUTOS_ACCURACY_THRESHOLD"
    printf "  Starlink Accuracy Threshold: %sm\n" "$GPS_STARLINK_ACCURACY_THRESHOLD"
    printf "  Speed Threshold (parked): %s km/h\n" "$GPS_SPEED_THRESHOLD"
    printf "  No Data Value: %s\n" "$GPS_NO_DATA_VALUE"
    echo ""
    printf "${BLUE}Connection Settings:${NC}\n"
    printf "  Starlink IP: %s\n" "$STARLINK_IP"
    printf "  RUTOS IP: %s\n" "$RUTOS_IP"
    printf "  RUTOS Username: %s\n" "$RUTOS_USERNAME"
    printf "  RUTOS Password: %s\n" "$([ -n "$RUTOS_PASSWORD" ] && echo "configured" || echo "not configured")"
    echo ""

    log_step "Testing GPS Collection"
    collect_gps_data "log"
}

# Usage information
show_usage() {
    cat <<EOF

Usage: $0 [options]

Options:
    --test              Test GPS collection and show configuration
    --json              Output GPS data in JSON format
    --csv               Output GPS data in CSV format
    --log               Output GPS data in log format (default)
    --config <file>     Use specific configuration file
    --help              Show this help message

Configuration:
    Edit $CONFIG_FILE to configure GPS settings:
    
    GPS_PRIMARY_SOURCE="auto"           # auto, rutos, starlink
    GPS_BACKUP_SOURCE="auto"            # auto, rutos, starlink
    GPS_CLUSTERING_DISTANCE="50"        # meters (0=disabled, 5, 10, 50, 500)
    GPS_RUTOS_ACCURACY_THRESHOLD="2"    # meters
    GPS_STARLINK_ACCURACY_THRESHOLD="10" # meters
    GPS_SPEED_THRESHOLD="5"             # km/h (below = parked)
    GPS_NO_DATA_VALUE="N/A"             # N/A or 0 for missing data

Examples:
    $0 --test                    # Test and show configuration
    $0 --json                    # Get GPS data as JSON
    $0 --csv                     # Get GPS data as CSV
    
EOF
}

# Main function
main() {
    # Load configuration first
    load_config

    # Parse command line arguments
    output_format="log"
    test_mode=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --test)
                test_mode=1
                ;;
            --json)
                output_format="json"
                ;;
            --csv)
                output_format="csv"
                ;;
            --log)
                output_format="log"
                ;;
            --config)
                shift
                CONFIG_FILE="$1"
                load_config # Reload with new config
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

    if [ "$test_mode" -eq 1 ]; then
        log_info "Starting GPS Collector v$SCRIPT_VERSION - Test Mode"
        show_config_and_test
    else
        # Just collect and output GPS data
        collect_gps_data "$output_format"
    fi
}

# Execute main function
main "$@"
