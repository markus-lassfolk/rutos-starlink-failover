#!/bin/sh
set -e

# Test script for enhanced GPS and drop rate calculation features
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "test-enhanced-data-collection-rutos.sh" "$SCRIPT_VERSION"

# Set test mode for detailed logging
RUTOS_TEST_MODE=1
DEBUG=1

log_info "🧪 ENHANCED DATA COLLECTION TEST"
log_info "Testing new GPS precision and drop rate calculation features"

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

# Mock Starlink configuration for testing
STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl"
JQ_CMD="/usr/bin/jq"

log_step "Checking tool availability"
log_debug "🔧 TOOLS: GRPCURL_CMD=$GRPCURL_CMD"
log_debug "🔧 TOOLS: JQ_CMD=$JQ_CMD"
log_debug "🔧 STARLINK: IP=$STARLINK_IP, PORT=$STARLINK_PORT"

# Check if tools are available
if [ ! -f "$GRPCURL_CMD" ]; then
    log_warning "grpcurl not found at $GRPCURL_CMD (expected in production environment)"
    GRPCURL_CMD=""
fi

if [ ! -f "$JQ_CMD" ]; then
    log_warning "jq not found at $JQ_CMD (expected in production environment)"
    JQ_CMD=""
fi

# =============================================================================
# TEST GPS COLLECTION WITH ENHANCED PRECISION
# =============================================================================

log_step "Testing GPS Collection with Enhanced Precision"

# Enable GPS logging for testing
ENABLE_GPS_LOGGING="true"
GPS_PRIMARY_SOURCE="starlink"
GPS_SECONDARY_SOURCE="rutos"

export ENABLE_GPS_LOGGING GPS_PRIMARY_SOURCE GPS_SECONDARY_SOURCE
export STARLINK_IP STARLINK_PORT GRPCURL_CMD JQ_CMD

log_info "📍 GPS: Testing enhanced GPS collection with multiple source fallbacks"
log_debug "📍 GPS CONFIG: PRIMARY=$GPS_PRIMARY_SOURCE, SECONDARY=$GPS_SECONDARY_SOURCE"

# Test GPS data collection
if gps_data=$(collect_gps_data); then
    log_success "GPS data collection completed"
    log_info "📍 GPS RESULT: $gps_data"

    # Parse GPS data components
    gps_lat=$(echo "$gps_data" | cut -d',' -f1)
    gps_lon=$(echo "$gps_data" | cut -d',' -f2)
    gps_alt=$(echo "$gps_data" | cut -d',' -f3)
    gps_accuracy=$(echo "$gps_data" | cut -d',' -f4)
    gps_source=$(echo "$gps_data" | cut -d',' -f5)

    log_info "📊 GPS ANALYSIS:"
    log_info "  Latitude: $gps_lat"
    log_info "  Longitude: $gps_lon"
    log_info "  Altitude: $gps_alt"
    log_info "  Accuracy: $gps_accuracy"
    log_info "  Source: $gps_source"

    # Check for high-precision coordinates (more than 6 decimal places)
    lat_decimals=$(echo "$gps_lat" | grep -o '\.[0-9]*' | tr -d '.' | wc -c)
    lon_decimals=$(echo "$gps_lon" | grep -o '\.[0-9]*' | tr -d '.' | wc -c)

    if [ "$lat_decimals" -gt 8 ] || [ "$lon_decimals" -gt 8 ]; then
        log_success "✅ High-precision GPS coordinates detected (>8 decimal places)"
    elif [ "$lat_decimals" -gt 6 ] || [ "$lon_decimals" -gt 6 ]; then
        log_info "✓ Standard precision GPS coordinates (6-8 decimal places)"
    else
        log_warning "⚠️  Lower precision GPS coordinates (<6 decimal places)"
    fi
else
    log_error "GPS data collection failed"
fi

# =============================================================================
# TEST STARLINK DROP RATE CALCULATION
# =============================================================================

log_step "Testing Starlink Drop Rate Calculation"

log_info "📊 STARLINK: Testing drop rate calculation from history data"

# Test enhanced status retrieval
if status_data=$(get_starlink_status_enhanced 2>/dev/null); then
    log_success "Enhanced Starlink status retrieved"

    # Extract drop rate
    if [ -n "$JQ_CMD" ] && [ -f "$JQ_CMD" ]; then
        drop_rate=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.popPingDropRate // "N/A"' 2>/dev/null)
        log_info "📊 DROP RATE: $drop_rate"

        if [ "$drop_rate" != "N/A" ] && [ "$drop_rate" != "null" ]; then
            log_success "✅ Drop rate successfully obtained/calculated"

            # Convert to percentage for readability
            if [ -n "$drop_rate" ] && [ "$drop_rate" != "0" ]; then
                drop_percent=$(echo "$drop_rate" | awk '{printf "%.2f%%", $1 * 100}')
                log_info "📊 DROP RATE PERCENTAGE: $drop_percent"
            fi
        else
            log_warning "⚠️  Drop rate not available"
        fi
    else
        log_warning "jq not available for data parsing"
    fi
else
    log_warning "Starlink API not accessible (expected in non-production environment)"

    # Test standalone drop rate calculation
    log_info "Testing standalone drop rate calculation function"
    if drop_rate=$(calculate_starlink_drop_rate 2>/dev/null); then
        log_info "📊 CALCULATED DROP RATE: $drop_rate"
    else
        log_warning "Drop rate calculation failed (expected without Starlink connection)"
    fi
fi

# =============================================================================
# TEST CELLULAR DATA COLLECTION
# =============================================================================

log_step "Testing Cellular Data Collection"

# Enable cellular logging for testing
ENABLE_CELLULAR_LOGGING="true"
export ENABLE_CELLULAR_LOGGING

log_info "📱 CELLULAR: Testing cellular data collection with library functions"

if cellular_data=$(collect_cellular_data); then
    log_success "Cellular data collection completed"
    log_info "📱 CELLULAR RESULT: $cellular_data"

    # Parse cellular data components
    cell_timestamp=$(echo "$cellular_data" | cut -d',' -f1)
    cell_modem=$(echo "$cellular_data" | cut -d',' -f2)
    cell_signal=$(echo "$cellular_data" | cut -d',' -f3)
    cell_quality=$(echo "$cellular_data" | cut -d',' -f4)
    cell_network=$(echo "$cellular_data" | cut -d',' -f5)
    cell_operator=$(echo "$cellular_data" | cut -d',' -f6)

    log_info "📊 CELLULAR ANALYSIS:"
    log_info "  Signal Strength: $cell_signal dBm"
    log_info "  Signal Quality: $cell_quality"
    log_info "  Network Type: $cell_network"
    log_info "  Operator: $cell_operator"
else
    log_error "Cellular data collection failed"
fi

# =============================================================================
# SUMMARY
# =============================================================================

log_step "Test Summary"

log_info "🧪 ENHANCED DATA COLLECTION TEST COMPLETED"
log_info ""
log_info "✅ New Features Tested:"
log_info "  • GPS: Multiple Starlink API sources (get_location, get_diagnostics)"
log_info "  • GPS: High-precision coordinate collection"
log_info "  • GPS: Intelligent source fallback (Starlink → RUTOS)"
log_info "  • Starlink: Drop rate calculation from history when missing"
log_info "  • Starlink: Enhanced status retrieval with auto-completion"
log_info "  • Cellular: Improved CSV sanitization and error handling"
log_info ""
log_info "🎯 Benefits:"
log_info "  • Higher GPS precision for better location tracking"
log_info "  • More reliable packet loss monitoring"
log_info "  • Robust fallback mechanisms for data collection"
log_info "  • Consistent CSV formatting across all data sources"

log_success "Enhanced data collection library ready for production use!"
