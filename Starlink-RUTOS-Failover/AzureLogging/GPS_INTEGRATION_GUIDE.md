# GPS and Mobility Integration Guide

## Overview

The Azure logging solution integrates with the existing repository GPS infrastructure to provide location-aware network performance analysis. This enhancement leverages GPS patterns for consistent and reliable location tracking.

## GPS Data Sources

### Primary: RUTOS GPS
The system uses GPS collection methods for reliable positioning:

- **RUTOS API**: `/api/gps/position/status` endpoint
- **Authentication**: Bearer token authentication
- **Data Structure**: Standard GPS field mapping:
  - `latitude`, `longitude`, `altitude`
  - `fix_status`, `satellites`, `accuracy`
  - `speed` (in km/h)
- **Fallback Methods**: 
  - gpsd/gpspipe interface
  - UCI GPS configuration
  - Direct NMEA device access

### Fallback: Starlink GPS (Using get_diagnostics)
Following the repository's API patterns:

- **API Call**: `get_diagnostics`
- **Location Structure**: `dishGetDiagnostics.location`
  - `latitude`, `longitude`, `altitudeMeters`
  - `uncertaintyMeters`, `uncertaintyMetersValid`
- **GPS Stats**: `dishGetDiagnostics.gpsStats.gpsSats`
- **Quality Thresholds**: Standard accuracy requirements

## Configuration (Using Repository Standards)

### GPS Settings
Configure GPS integration using the same variables as the main repository:

```bash
# In your config.sh or environment
RUTOS_IP="192.168.80.1"                    # RUTOS device IP (standard)
RUTOS_USERNAME="your_username"             # RUTOS login credentials
RUTOS_PASSWORD="your_password"             
GPS_ACCURACY_THRESHOLD=100                 # Accuracy threshold in meters
```

### Quality Thresholds
The system uses GPS quality checks for reliable positioning:

- **RUTOS GPS Good**: `fix_status > 0` AND `accuracy < 2m`
- **Starlink GPS Good**: `uncertaintyMetersValid = true` AND `uncertaintyMeters < 10m`
- **Selection Logic**: Standard GPS selection - prefer RUTOS if both good, otherwise use best available

## Enhanced Analysis Capabilities

### Location-Based Performance Analysis

**Coverage Mapping**
- Visual maps showing where you've been
- Performance overlays (latency, throughput, packet loss)
- Identification of problem areas
- Best/worst performing locations

**Geographic Patterns**
- Performance correlation with latitude/longitude
- Regional performance variations
- Coverage area calculation
- Unique location tracking

### Mobility Analysis

**Speed vs Performance Correlation**
- How velocity affects network quality
- Optimal speed ranges for connectivity
- Performance degradation at high speeds
- Handoff behavior during movement

**Movement Pattern Analysis**
- Total distance traveled
- Average movement per measurement
- Route optimization opportunities
- Stationary vs mobile performance comparison

### Enhanced Failover Intelligence

**Location-Aware Thresholds**
- Different thresholds for stationary vs mobile use
- Speed-dependent performance expectations
- Geographic area-specific adjustments
- Movement-predictive failover triggering

**Mobility State Considerations**
- Faster failover for high-speed scenarios
- More tolerant thresholds when stationary
- Predictive switching based on movement patterns
- Location-based backup connection preferences

## Practical Applications

### Mobile Deployments
- **RVs and Motorhomes**: Track performance across travel routes
- **Marine Applications**: Monitor connectivity while cruising
- **Construction/Mining**: Performance mapping for work sites
- **Emergency Response**: Coverage analysis for remote deployments

### Fixed Installations with Mobility
- **Backup Location Analysis**: Performance comparison between primary and backup sites
- **Temporary Deployments**: Quick assessment of new locations
- **Site Survey Data**: Historical performance for location decisions

### Route Optimization
- **Travel Planning**: Identify routes with best connectivity
- **Performance Prediction**: Expected quality based on planned travel
- **Backup Planning**: Locations where failover is more likely needed

## Configuration Examples

### For Mobile Use (RV/Marine)
```bash
# More aggressive failover for mobile scenarios
LATENCY_THRESHOLD_MOBILE=100ms
PACKET_LOSS_THRESHOLD_MOBILE=2%
SPEED_THRESHOLD_FOR_MOBILE=5kmh  # Switch to mobile mode above this speed
```

### For Fixed Installation with Movement Capability
```bash
# Conservative when stationary, faster when mobile
LATENCY_THRESHOLD_STATIONARY=200ms
LATENCY_THRESHOLD_MOBILE=120ms
MOBILITY_DETECTION_ENABLED=true
```

### For Site Survey/Analysis
```bash
# Collect maximum GPS data for analysis
GPS_COLLECTION_INTERVAL=30s  # More frequent for detailed mapping
DETAILED_LOCATION_LOGGING=true
MOVEMENT_TRACKING_ENABLED=true
```

## Analysis Insights

### Performance Reports Include

**Geographic Analysis**
- Coverage area in km²
- Unique locations visited
- Best/worst performing coordinates
- Regional performance variations

**Movement Analysis**
- Average travel speed
- Maximum recorded speed
- Time spent in each mobility state
- Speed vs performance correlations

**Location-Based Recommendations**
- Optimal positioning suggestions
- Problem area identification
- Route recommendations for best connectivity
- Site-specific threshold adjustments

### Visualization Outputs

**Coverage Maps**
- GPS track overlaid with performance data
- Color-coded performance regions
- Problem area highlighting
- Coverage density analysis

**Mobility Charts**
- Speed over time
- Performance vs velocity correlations
- Mobility state distributions
- Movement pattern analysis

**Location Performance**
- Latitude/longitude vs latency scatter plots
- Geographic performance gradients
- Regional comparison charts
- Best/worst location identification

## Setup Requirements

### GPS Hardware
- RUTOS device with GPS capability OR
- Starlink connection (GPS fallback)
- GPS antenna properly positioned
- Clear sky view for optimal accuracy

### Software Dependencies
- `gpsd` and `gpspipe` (for RUTOS GPS)
- `jq` for JSON parsing
- `bc` for calculations (optional)
- Standard RUTOS UCI configuration

### Python Analysis Requirements
```bash
pip install pandas matplotlib seaborn folium  # Add folium for mapping
```

## Troubleshooting GPS Issues

### RUTOS GPS Not Working
1. Check GPS hardware connection
2. Verify GPS is enabled in UCI: `uci get gps.gps.enabled`
3. Test GPS daemon: `gpspipe -r -n 5`
4. Check device permissions: `ls -la /dev/ttyUSB* /dev/ttyACM*`

### Starlink GPS Fallback
1. Verify Starlink API access: `grpcurl -plaintext -d '{"get_location":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle`
2. Check for location API support in your Starlink firmware
3. Ensure Starlink has GPS lock (may take time after power-on)

### Accuracy Issues
- GPS accuracy degrades indoors or with obstructed sky view
- Starlink GPS typically more accurate than basic RUTOS GPS modules
- Cold starts may take several minutes for accurate positioning
- Movement improves GPS accuracy through Doppler calculations

## Privacy and Security Considerations

### Data Protection
- GPS coordinates are precise location data - handle with care
- Consider data retention policies for location information
- Implement access controls for GPS-enabled analysis reports
- Option to anonymize or round coordinates for privacy

### Analysis Scope
- GPS data helps with technical optimization
- Location patterns can reveal usage behaviors
- Consider geographic data sovereignty requirements
- Implement secure transmission and storage practices

This GPS integration transforms the logging solution from performance monitoring into comprehensive location-intelligent network optimization!
