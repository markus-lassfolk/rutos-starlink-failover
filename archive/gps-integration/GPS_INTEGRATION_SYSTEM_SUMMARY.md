# GPS Integration System for RUTOS Starlink Failover

<!-- Version: 1.0.0 - GPS Integration Documentation -->

## Overview

This GPS integration system provides comprehensive location-based analytics for the RUTOS Starlink failover
solution, specifically optimized for motorhome and RV connectivity monitoring. The system addresses all four key
requirements identified for location-aware monitoring:

1. **Separate GPS Folder**: Independent GPS system with reusable configuration
2. **Starlink Integration**: Seamless integration with existing monitoring scripts
3. **No GPS Handling**: Graceful handling of missing GPS coordinates (ferry/covered dish scenarios)
4. **Clustering Accuracy**: Speed-aware location clustering for different movement states

## System Architecture

### Core Components

#### 1. GPS Collector (`gps-collector-rutos.sh`)

- **Purpose**: Unified GPS data collection from multiple sources
- **Sources**: RUTOS GPS (primary), Starlink GPS (backup), automatic selection
- **Features**: Quality assessment, source selection, authentication handling
- **Output**: Structured GPS data in log/json/csv formats

#### 2. Location Analyzer (`gps-location-analyzer-rutos.sh`)

- **Purpose**: Location clustering and connectivity pattern analysis
- **Algorithm**: Haversine distance calculations for precise geographic clustering
- **Features**: Speed-aware clustering, problematic location identification, comprehensive reporting
- **Output**: Detailed markdown reports with actionable insights

#### 3. Integration Script (`integrate-gps-into-starlink-monitor-rutos.sh`)

- **Purpose**: Automated integration with existing Starlink monitoring system
- **Safety**: Comprehensive dry-run mode with file backup
- **Features**: Configuration injection, script installation, verification system
- **Output**: Complete integration with manual instruction guide

### Technical Foundation

#### GPS Source Selection Logic

Based on proven Victron GPS Node-RED flow patterns:

```bash
# Primary: RUTOS GPS (high precision)
- Accuracy threshold: 2 meters
- API: Device-native GPS interface
- Reliability: High (dedicated GPS hardware)

# Backup: Starlink GPS (broad coverage)
- Accuracy threshold: 10 meters
- API: grpcurl to Starlink diagnostics
- Reliability: Medium (satellite-based)

# Selection: Best accuracy wins when both available
```

#### Location Clustering Algorithm

Optimized for motorhome parking analysis:

```bash
# Clustering Parameters
- Distance: 50m radius (configurable)
- Speed threshold: 5km/h (parked vs moving)
- Parked focus: Only clusters stationary periods
- Minimum events: 2+ for problematic location

# Haversine Distance Calculation
- Precise geographic distance measurement
- Accounts for Earth's curvature
- Meter-level accuracy for clustering decisions
```

## Configuration System

### GPS Integration Settings

All GPS settings integrate with existing `config.sh` configuration:

```bash
# ===== GPS INTEGRATION CONFIGURATION =====

# GPS Collection Settings
GPS_ENABLED="true"                          # Enable GPS data collection
GPS_PRIMARY_SOURCE="rutos"                   # Primary GPS source (rutos/starlink/auto)
GPS_FALLBACK_SOURCE="starlink"              # Fallback GPS source
GPS_COLLECTION_INTERVAL="60"                # Collection interval in seconds
GPS_ACCURACY_THRESHOLD_RUTOS="2"             # RUTOS GPS accuracy threshold (meters)
GPS_ACCURACY_THRESHOLD_STARLINK="10"         # Starlink GPS accuracy threshold (meters)

# GPS Location Analysis Settings
GPS_CLUSTERING_DISTANCE="50"                # Location clustering radius (meters)
GPS_SPEED_THRESHOLD="5"                     # Speed threshold for parked vs moving (km/h)
GPS_NO_DATA_VALUE="N/A"                     # Value for missing GPS data
PARKED_ONLY_CLUSTERING="true"               # Only cluster when vehicle is parked
MIN_EVENTS_PER_LOCATION="2"                 # Minimum events to flag problematic location

# GPS Output Settings
GPS_OUTPUT_FORMAT="log"                     # Output format (log/json/csv)
GPS_LOG_ENHANCED_METRICS="true"             # Include GPS in enhanced metrics
GPS_LOCATION_ANALYSIS_ENABLED="true"        # Enable automatic location analysis
```

### Configurable Parameters

#### Clustering Distance Options

- **5m**: Precise parking spot analysis
- **50m**: Campground/parking area analysis (recommended)
- **500m**: Regional area analysis
- **0**: Disable clustering (individual coordinates)

#### Speed Threshold Considerations

- **5km/h**: Distinguishes parked vs creeping movement (recommended)
- **1km/h**: Very sensitive to any movement
- **10km/h**: More tolerant of parking lot movement

#### No GPS Data Handling

- **"N/A"**: Clear indication of missing data (recommended)
- **"0"**: Numeric zero (may cause false coordinate plotting)

## Installation and Setup

### Automatic Installation

```bash
# Run integration script with dry-run preview
./gps-integration/integrate-gps-into-starlink-monitor-rutos.sh

# Execute real installation
./gps-integration/integrate-gps-into-starlink-monitor-rutos.sh --execute
```

### Manual Installation Steps

1. **Copy Scripts**:

   ```bash
   cp gps-integration/gps-collector-rutos.sh /etc/starlink-monitor/
   cp gps-integration/gps-location-analyzer-rutos.sh /etc/starlink-monitor/
   chmod +x /etc/starlink-monitor/gps-*.sh
   ```

2. **Add Configuration**:

   ```bash
   # Append GPS configuration to /etc/starlink-monitor/config.sh
   cat gps-integration/gps-config-template.sh >> /etc/starlink-monitor/config.sh
   ```

3. **Integrate with Monitor**:

   ```bash
   # Add GPS collection call to starlink_monitor.sh main loop
   collect_gps_data  # Add this call in monitoring loop
   ```

### Verification

```bash
# Run comprehensive verification
/etc/starlink-monitor/verify-gps-integration.sh

# Test GPS collector
/etc/starlink-monitor/gps-collector-rutos.sh --test-only

# Test location analyzer
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

## Usage Examples

### Basic GPS Collection

```bash
# Single GPS reading in log format
/etc/starlink-monitor/gps-collector-rutos.sh --single-reading

# Continuous collection with enhanced logging
/etc/starlink-monitor/gps-collector-rutos.sh --continuous --format=log

# JSON output for API integration
/etc/starlink-monitor/gps-collector-rutos.sh --format=json
```

### Location Analysis

```bash
# Analyze all log data for location patterns
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Include moving vehicle data in analysis
/etc/starlink-monitor/gps-location-analyzer-rutos.sh --include-moving /var/log/starlink

# Custom clustering distance
GPS_CLUSTERING_DISTANCE=100 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

### Configuration Testing

```bash
# Test different speed thresholds
GPS_SPEED_THRESHOLD=1 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Disable clustering for individual coordinate analysis
GPS_CLUSTERING_DISTANCE=0 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Test no-data handling
GPS_NO_DATA_VALUE="0" /etc/starlink-monitor/gps-collector-rutos.sh --test-only
```

## Real-World Applications

### Motorhome Travel Optimization

#### Problem Location Identification

```bash
# Daily location analysis
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Extract problematic locations for GPS navigation
grep "PROBLEMATIC LOCATION" /var/log/starlink/gps_location_analysis_*.md
```

#### Travel Planning Integration

```bash
# Weekly summary for route planning
find /var/log/starlink -name "gps_location_analysis_*.md" -mtime -7

# Export coordinates for mapping software
/etc/starlink-monitor/gps-collector-rutos.sh --format=csv --single-reading
```

### Connectivity Pattern Analysis

#### Campground Assessment

```bash
# Focus on parked locations only
PARKED_ONLY_CLUSTERING=true /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Include movement patterns
PARKED_ONLY_CLUSTERING=false /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

#### Equipment Optimization

```bash
# Fine-grained parking spot analysis
GPS_CLUSTERING_DISTANCE=5 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Regional connectivity assessment
GPS_CLUSTERING_DISTANCE=500 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

## Output Formats and Reports

### GPS Collection Output

#### Log Format (Default)

```text
[2025-07-25 12:34:56] GPS: source=rutos, lat=59.8586, lon=17.6389, alt=45m, fix=1, acc=1.2m, sats=12, speed=0km/h
```

#### JSON Format

```json
{
  "timestamp": "2025-07-25T12:34:56Z",
  "source": "rutos",
  "latitude": 59.8586,
  "longitude": 17.6389,
  "altitude": 45,
  "fix_type": 1,
  "accuracy": 1.2,
  "satellites": 12,
  "speed_kmh": 0
}
```

#### CSV Format

```csv
timestamp,source,latitude,longitude,altitude,fix_type,accuracy,satellites,speed_kmh
2025-07-25 12:34:56,rutos,59.8586,17.6389,45,1,1.2,12,0
```

### Location Analysis Reports

#### Comprehensive Markdown Reports

- **Overview**: Methodology and configuration summary
- **Location Clusters**: Detailed analysis of each identified location
- **Risk Assessment**: Problematic location identification and recommendations
- **Travel Insights**: Motorhome-specific recommendations and optimization strategies
- **Technical Documentation**: Configuration details and integration information

#### Key Report Sections

1. **Clustering Configuration**: Current analysis parameters
2. **Problematic Locations**: Locations requiring attention (≥2 events)
3. **Normal Locations**: Single-event locations (likely temporary issues)
4. **Summary Statistics**: Overall connectivity health assessment
5. **Motorhome Recommendations**: Travel planning and site selection guidance

## Advanced Features

### Speed-Aware Analysis

The system distinguishes between different vehicle states for contextually relevant analysis:

```bash
# Parked Analysis (≤5km/h)
- Focus: Camping and parking locations
- Use case: Connectivity assessment for stationary periods
- Clustering: Relevant for site selection

# Moving Analysis (>5km/h)
- Focus: Transit connectivity patterns
- Use case: Route optimization and coverage assessment
- Clustering: Less relevant due to continuous movement
```

### Multi-Source GPS Integration

Sophisticated source selection based on Victron GPS Node-RED patterns:

```bash
# Quality Assessment Logic
1. Check RUTOS GPS accuracy vs 2m threshold
2. Check Starlink GPS accuracy vs 10m threshold
3. Select best available source
4. Fall back gracefully when sources unavailable
5. Handle authentication for Starlink API access
```

### No GPS Data Scenarios

Comprehensive handling of GPS-unavailable situations:

```bash
# Ferry Crossing: No GPS signal
- GPS_NO_DATA_VALUE="N/A"
- Prevents false coordinate plotting
- Maintains log continuity

# Covered Dish: Starlink blocked, RUTOS available
- Automatic fallback to RUTOS GPS
- Quality assessment continues
- Seamless source switching
```

## Integration with Existing System

### Starlink Monitor Integration

The GPS system integrates seamlessly with existing monitoring:

```bash
# Enhanced Metrics with GPS
ENHANCED METRICS: satellites=12, uptime=3600, reboot_count=0 | GPS: source=rutos, lat=59.8586, lon=17.6389, speed=0km/h

# Failover Events with Location
FAILOVER EVENT: starlink_down at location lat=59.8586, lon=17.6389 (cluster_id=3, event_count=2)
```

### Configuration Reuse

All GPS features leverage existing configuration infrastructure:

```bash
# Uses existing LOG_DIR for GPS data storage
GPS_DATA_DIR="$LOG_DIR/gps"

# Integrates with existing authentication
# Uses existing DEBUG mode support
# Follows existing logging patterns
```

### Backward Compatibility

GPS integration maintains full backward compatibility:

```bash
# GPS disabled by default in fresh installations
GPS_ENABLED="false"  # Safe default

# No impact on existing functionality when disabled
# Graceful degradation when GPS unavailable
# Maintains existing log formats when GPS disabled
```

## Troubleshooting

### Common Issues and Solutions

#### GPS Collector Issues

**Problem**: GPS collector returns "No GPS data available"

```bash
# Solution: Check GPS source availability
# Test RUTOS GPS API
curl -X GET "http://192.168.1.1/api/gps"

# Test Starlink GPS via grpcurl
grpcurl -plaintext 192.168.100.1:9200 SpaceX.API.Device.Device/GetStatus
```

**Problem**: Authentication failures for Starlink GPS

```bash
# Solution: Verify Starlink API access
# Check network connectivity to Starlink device
ping 192.168.100.1

# Verify grpcurl installation and permissions
which grpcurl && grpcurl --help
```

#### Location Analyzer Issues

**Problem**: No location clusters generated

```bash
# Solution: Check GPS data in logs
grep "GPS:" /var/log/starlink/*.log | head -5

# Verify clustering distance setting
echo "Current clustering distance: $GPS_CLUSTERING_DISTANCE"

# Test with larger clustering distance
GPS_CLUSTERING_DISTANCE=500 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

**Problem**: All locations marked as problematic

```bash
# Solution: Adjust minimum events threshold
MIN_EVENTS_PER_LOCATION=5 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink

# Or reduce clustering distance for more granular analysis
GPS_CLUSTERING_DISTANCE=25 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

#### Integration Issues

**Problem**: GPS functions not found in monitor script

```bash
# Solution: Verify integration completed
grep "collect_gps_data" /etc/starlink-monitor/starlink_monitor.sh

# Re-run integration if missing
./gps-integration/integrate-gps-into-starlink-monitor-rutos.sh --execute
```

**Problem**: Configuration not loaded

```bash
# Solution: Check configuration syntax
sh -n /etc/starlink-monitor/config.sh

# Verify GPS configuration present
grep "GPS_ENABLED" /etc/starlink-monitor/config.sh
```

### Debugging Tools

#### Debug Mode

```bash
# Enable comprehensive debug output
DEBUG=1 /etc/starlink-monitor/gps-collector-rutos.sh --test-only

# Debug location analysis
DEBUG=1 /etc/starlink-monitor/gps-location-analyzer-rutos.sh /var/log/starlink
```

#### Component Testing

```bash
# Test individual components
/etc/starlink-monitor/verify-gps-integration.sh

# Test GPS collector in isolation
/etc/starlink-monitor/gps-collector-rutos.sh --single-reading --format=json

# Test analyzer with minimal data
echo "2025-07-25 12:00:00,59.8586,17.6389,0" > /tmp/test_gps.csv
/etc/starlink-monitor/gps-location-analyzer-rutos.sh /tmp/
```

#### Log Analysis

```bash
# Check for GPS-related errors
grep -i "gps\|error" /var/log/starlink/*.log | tail -20

# Monitor GPS collection in real-time
tail -f /var/log/starlink/starlink_monitor.log | grep "GPS:"

# Review location analysis results
find /var/log/starlink -name "gps_location_analysis_*.md" -exec tail {} \;
```

## Future Enhancements

### Planned Features

1. **Predictive Analytics**: ML-based connectivity prediction based on location patterns
2. **Weather Integration**: Correlate connectivity issues with weather conditions
3. **Community Data**: Shared database of problematic locations for RV community
4. **Real-Time Alerts**: Notifications when approaching known problem areas
5. **Route Optimization**: Integration with navigation systems for connectivity-aware routing

### Extensibility

The modular design supports future enhancements:

```bash
# Plugin Architecture: Additional GPS sources
# Data Export: Integration with external mapping systems
# API Integration: RESTful API for real-time GPS data
# Mobile Apps: Companion apps for RV travelers
# Cloud Sync: Synchronized location database across devices
```

### Configuration Evolution

Future configuration enhancements:

```bash
# Adaptive Clustering: Dynamic distance based on location type
# Seasonal Patterns: Different analysis for summer/winter travel
# Equipment Profiles: Different settings for different antenna types
# Travel Modes: Highway vs camping vs urban configurations
```

## Summary

The GPS Integration System provides comprehensive location-based analytics for RUTOS Starlink failover monitoring,
specifically optimized for motorhome and RV connectivity patterns. Key achievements:

✅ **Separate GPS System**: Independent folder with reusable configuration
✅ **Starlink Integration**: Seamless integration with existing monitoring scripts  
✅ **No GPS Data Handling**: Graceful handling of missing coordinates (N/A values)
✅ **Speed-Aware Clustering**: 5km/h threshold for parked vs moving analysis
✅ **Production Ready**: Comprehensive testing, verification, and documentation
✅ **Motorhome Optimized**: 50m clustering for camping/parking area analysis

The system leverages proven Victron GPS normalization patterns, implements sophisticated Haversine distance
calculations, and provides actionable insights for travel optimization and connectivity planning.
