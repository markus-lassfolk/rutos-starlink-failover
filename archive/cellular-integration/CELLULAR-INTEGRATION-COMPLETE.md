# Cellular Integration Complete Solution

<!-- Version: 2.7.0 - Auto-updated documentation -->

## Overview

This solution extends our GPS-enhanced Starlink monitoring system with comprehensive cellular data integration,
enabling intelligent multi-connectivity management for RUTX50 routers. The system supports both **dual-modem
configurations** (no Starlink) and **triple-connectivity setups** (Starlink + 2 cellular modems) with smart
failover decisions based on signal strength, network type, roaming status, and cost considerations.

## Key Features

### 🔄 Smart Failover Capabilities

- **Multi-connectivity analysis**: Starlink + Primary Cellular + Backup Cellular
- **Signal strength-based decisions**: Automatic switching to strongest signal
- **Roaming cost awareness**: Avoids expensive roaming when alternatives available
- **Network type preferences**: 5G > LTE > 3G > GSM prioritization
- **Hysteresis protection**: Prevents excessive switching between connections

### 📱 Comprehensive Cellular Monitoring

- **Real-time signal strength**: dBm readings with quality assessment
- **Network type detection**: 5G, LTE, 3G, GSM identification
- **Operator identification**: Current network provider tracking
- **Roaming status monitoring**: Home vs Roaming detection
- **Connection quality assessment**: Ping tests and connectivity validation

### 📊 Enhanced Data Collection

- **Statistical aggregation**: 60:1 data reduction with cellular metrics
- **Multi-source GPS**: RUTOS GPS (primary) + Starlink GPS (backup)
- **Comprehensive CSV format**: 42 columns including cellular data
- **Location-based intelligence**: Connectivity patterns by geographic location
- **Cost optimization**: Roaming expense tracking and avoidance

## Architecture

### System Components

```text
┌─────────────────────────────────────────────────────────────────┐
│                    RUTOS Cellular Integration                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │    Starlink     │  │ Primary Modem   │  │ Backup Modem    │ │
│  │   (wlan0)       │  │   (mob1s1a1)    │  │   (mob1s2a1)    │ │
│  │                 │  │                 │  │                 │ │
│  │ • SNR: 8.5dB    │  │ • Signal: -80dBm│  │ • Signal: -85dBm│ │
│  │ • Obstruction   │  │ • Network: LTE  │  │ • Network: LTE  │ │
│  │ • Speed test    │  │ • Operator: Telia│  │ • Operator: Three│ │
│  │ • GPS backup    │  │ • Roaming: Home │  │ • Roaming: Home │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│           │                     │                     │         │
│           └─────────────────────┼─────────────────────┘         │
│                                 │                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │           Smart Failover Decision Engine                    │ │
│  │                                                             │ │
│  │  • Signal strength scoring                                  │ │
│  │  • Roaming cost penalties                                   │ │
│  │  • Network type bonuses                                     │ │
│  │  • Connection quality assessment                            │ │
│  │  • Hysteresis and stability                                 │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                 │                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │             Enhanced Data Logger                            │ │
│  │                                                             │ │
│  │  • Cellular metrics collection                              │ │
│  │  • GPS data with source priority                            │ │
│  │  • Statistical aggregation (60:1)                           │ │
│  │  • Location-based analysis                                  │ │
│  │  • Cost optimization insights                               │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Collection Phase**:

   - Starlink metrics via grpcurl (SNR, obstruction, speed)
   - Cellular data via gsmctl/mmcli (signal, network, roaming)
   - GPS coordinates via RUTOS GPS (primary) or Starlink GPS (backup)

2. **Analysis Phase**:

   - Connection scoring based on multiple factors
   - Roaming cost assessment
   - Signal quality evaluation
   - Network type preferences

3. **Decision Phase**:

   - Compare all available connections
   - Apply hysteresis rules
   - Generate failover recommendations
   - Execute switching (with dry-run safety)

4. **Logging Phase**:
   - Statistical aggregation (60:1 reduction)
   - Enhanced CSV with cellular metrics
   - Location pattern analysis
   - Cost optimization tracking

## File Structure

```text
cellular-integration/
├── cellular-data-collector-rutos.sh     # Core cellular data collection
├── optimize-logger-with-cellular-rutos.sh # Enhanced logger with aggregation
├── smart-failover-engine-rutos.sh       # Intelligent failover decisions
└── demo-cellular-integration-rutos.sh   # Comprehensive demonstration
```

## Configuration

### Basic Setup

Add these settings to your existing configuration file (`/etc/starlink-monitor/config.sh`):

```bash
# Cellular Interface Configuration
CELLULAR_PRIMARY_IFACE="mob1s1a1"              # Primary modem interface
CELLULAR_BACKUP_IFACE="mob1s2a1"               # Backup modem interface

# Signal Quality Thresholds
CELLULAR_SIGNAL_EXCELLENT="-70"                # Excellent signal (dBm)
CELLULAR_SIGNAL_GOOD="-85"                     # Good signal (dBm)
CELLULAR_SIGNAL_POOR="-105"                    # Poor signal (dBm)

# Smart Failover Settings
STARLINK_PRIORITY_SCORE="100"                  # Base Starlink priority
CELLULAR_PRIMARY_PRIORITY="80"                 # Primary cellular priority
CELLULAR_BACKUP_PRIORITY="60"                  # Backup cellular priority
FAILOVER_SCORE_THRESHOLD="30"                  # Min score difference for failover
ROAMING_COST_PENALTY="50"                      # Score penalty for roaming

# Network Type Bonuses
NETWORK_5G_BONUS="20"                          # Score bonus for 5G
NETWORK_LTE_BONUS="10"                         # Score bonus for LTE

# Data Collection
CELLULAR_DATA_LOG="/var/log/cellular_data.csv" # Cellular data log file
CELLULAR_COLLECT_INTERVAL="60"                 # Collection interval (seconds)
```

### Advanced Configuration

```bash
# Cost Management
CELLULAR_ROAMING_COST_THRESHOLD="10.0"         # Cost per MB threshold
ROAMING_DATA_LIMIT_MB="1000"                   # Daily roaming data limit

# Quality Assessment
STARLINK_SNR_GOOD="8.0"                        # Good Starlink SNR (dB)
STARLINK_SNR_POOR="3.0"                        # Poor Starlink SNR (dB)

# Failover Behavior
FAILOVER_HYSTERESIS_TIME="300"                 # Seconds before switching back
AUTO_EXECUTE_FAILOVER="0"                      # Auto-execute (0=manual, 1=auto)

# Monitoring
ENABLE_SPEED_TEST="0"                          # Enable speed testing (resource intensive)
DEBUG="0"                                      # Debug mode
```

## Usage Examples

### 1. Test Cellular Data Collection

```bash
# Test data collection from both modems
./cellular-integration/cellular-data-collector-rutos.sh collect human

# Output cellular data in CSV format
./cellular-integration/cellular-data-collector-rutos.sh collect csv

# Analyze cellular data for failover recommendations
./cellular-integration/cellular-data-collector-rutos.sh analyze
```

### 2. Enhance Existing Logs with Cellular Data

```bash
# Enhance existing Starlink logs with cellular metrics
./cellular-integration/optimize-logger-with-cellular-rutos.sh enhance \
    /var/log/starlink.csv \
    /var/log/enhanced_with_cellular.csv

# Generate statistical aggregation with cellular data
./cellular-integration/optimize-logger-with-cellular-rutos.sh aggregate \
    /var/log/enhanced_with_cellular.csv \
    /var/log/aggregated_cellular.csv
```

### 3. Smart Failover Decision Making

```bash
# Analyze current connections and get recommendations
./cellular-integration/smart-failover-engine-rutos.sh analyze

# Test failover to specific connection (dry-run)
./cellular-integration/smart-failover-engine-rutos.sh execute cellular_primary --dry-run

# Execute real failover (use with caution)
./cellular-integration/smart-failover-engine-rutos.sh execute starlink --force

# Start continuous monitoring
./cellular-integration/smart-failover-engine-rutos.sh monitor 300
```

### 4. Comprehensive Demonstration

```bash
# Show all cellular integration features
./cellular-integration/demo-cellular-integration-rutos.sh all

# Show specific demonstrations
./cellular-integration/demo-cellular-integration-rutos.sh scenarios
./cellular-integration/demo-cellular-integration-rutos.sh decisions
./cellular-integration/demo-cellular-integration-rutos.sh efficiency
```

## Enhanced CSV Format

### Original Format (15 columns)

```csv
timestamp,starlink_status,ping_ms,download_mbps,upload_mbps,ping_drop_rate,snr_db,obstruction_percent,uptime_seconds,gps_lat,gps_lon,gps_alt,gps_speed,gps_accuracy,gps_source
```

### Enhanced Format (26 columns)

```csv
timestamp,starlink_status,ping_ms,download_mbps,upload_mbps,ping_drop_rate,snr_db,obstruction_percent,uptime_seconds,gps_lat,gps_lon,gps_alt,gps_speed,gps_accuracy,gps_source,cellular_primary_signal,cellular_primary_quality,cellular_primary_network,cellular_primary_operator,cellular_primary_roaming,cellular_backup_signal,cellular_backup_quality,cellular_backup_network,cellular_backup_operator,cellular_backup_roaming,active_connection
```

### Statistical Aggregation Format (42+ columns)

```csv
timestamp_start,timestamp_end,duration_minutes,samples_count,starlink_status_summary,ping_ms_min,ping_ms_max,ping_ms_avg,ping_ms_95th,download_mbps_min,download_mbps_max,download_mbps_avg,download_mbps_95th,upload_mbps_min,upload_mbps_max,upload_mbps_avg,upload_mbps_95th,ping_drop_rate_min,ping_drop_rate_max,ping_drop_rate_avg,snr_db_min,snr_db_max,snr_db_avg,obstruction_percent_min,obstruction_percent_max,obstruction_percent_avg,uptime_seconds_total,gps_lat_avg,gps_lon_avg,gps_alt_avg,gps_speed_max,gps_accuracy_avg,gps_source_primary,cellular_primary_signal_avg,cellular_primary_quality_summary,cellular_primary_network_summary,cellular_primary_operator,cellular_backup_signal_avg,cellular_backup_quality_summary,cellular_backup_network_summary,cellular_backup_operator,active_connection_summary
```

## Deployment Scenarios

### 1. Triple Connectivity (Starlink + 2 Cellular)

**Use Case**: Motorhome with maximum connectivity redundancy

**Configuration**:

- Starlink as primary (highest priority score: 100)
- Primary cellular SIM with home network (priority: 80)
- Backup cellular SIM for roaming areas (priority: 60)

**Benefits**:

- Automatic failover based on signal quality
- Roaming cost avoidance
- 5G/LTE speed optimization
- Location-based connectivity learning

### 2. Dual Cellular Only (No Starlink)

**Use Case**: Urban/suburban areas with good cellular coverage

**Configuration**:

- Primary cellular as main connection (priority: 100)
- Backup cellular for redundancy (priority: 80)
- No Starlink component

**Benefits**:

- Smart switching between carriers
- Roaming cost management
- Network type optimization (5G preferred)
- Cost-effective connectivity

### 3. Motorhome Travel Optimization

**Use Case**: Long-distance travel with varying connectivity

**Features**:

- Location-based connectivity patterns
- Automatic roaming detection and avoidance
- Signal strength optimization by location
- Travel route planning assistance

**Intelligence**:

- Learn best connections at frequent stops
- Identify problematic locations
- Optimize parking for best connectivity
- Cost tracking across different regions

## Smart Failover Scoring System

### Connection Scoring Formula

Each connection receives a score based on multiple factors:

```text
Total Score = Base Priority + Signal Bonus + Network Bonus + Status Bonus - Penalties
```

#### Base Priorities

- **Starlink**: 100 points
- **Primary Cellular**: 80 points
- **Backup Cellular**: 60 points

#### Signal Quality Bonuses

- **Starlink SNR**:

  - ≥8.0 dB: +30 points
  - ≥3.0 dB: +10 points
  - <3.0 dB: -20 points

- **Cellular Signal**:
  - ≥-70 dBm: +30 points (Excellent)
  - ≥-85 dBm: +20 points (Good)
  - ≥-105 dBm: +5 points (Fair)
  - <-105 dBm: -20 points (Poor)

#### Network Type Bonuses

- **5G**: +20 points
- **LTE**: +10 points
- **3G**: -10 points
- **GSM**: -20 points

#### Status Bonuses

- **Connected**: +15-20 points
- **Disconnected**: -30 to -50 points

#### Penalties

- **Roaming**: -50 points
- **High Obstruction**: -2 points per % obstruction
- **High Ping**: -10 to -15 points for >100ms

### Decision Threshold

Failover occurs when:

```text
Best Available Score - Current Score ≥ FAILOVER_SCORE_THRESHOLD (default: 30)
```

This prevents excessive switching for minor improvements.

## Integration with Existing System

### Backward Compatibility

The cellular integration is designed to be fully backward compatible:

- **Existing GPS system**: Enhanced but unchanged
- **Current configuration**: New settings are optional
- **Log formats**: Original format still supported
- **Scripts**: Existing scripts continue to work

### Enhanced Components

- **GPS collection**: Multi-source with priority (RUTOS → Starlink)
- **Statistical aggregation**: Extended with cellular metrics
- **Location analysis**: Enhanced with connectivity intelligence
- **Configuration**: Extended with cellular settings

### Migration Path

1. **Phase 1**: Install cellular collection scripts
2. **Phase 2**: Test cellular data collection
3. **Phase 3**: Enhance existing logs with cellular data
4. **Phase 4**: Configure smart failover rules
5. **Phase 5**: Enable automatic failover monitoring

## Performance and Efficiency

### Data Reduction

- **Original**: 21,600 entries/day (60 per hour × 24 hours)
- **Enhanced**: 360 entries/day (15 aggregated chunks × 24 hours)
- **Reduction**: 60:1 compression ratio
- **Storage**: 98.3% reduction in log size

### Resource Usage

- **CPU Impact**: Minimal (cellular checks every 60 seconds)
- **Memory Usage**: Low (streaming processing)
- **Network Overhead**: Negligible (local data collection)
- **Storage Efficiency**: Significant improvement with aggregation

### Real-time Responsiveness

- **Decision Speed**: <5 seconds for analysis
- **Failover Time**: <10 seconds for execution
- **Monitoring Frequency**: Configurable (60-300 seconds)
- **Hysteresis Protection**: Prevents rapid switching

## Monitoring and Maintenance

### Health Checks

```bash
# Check cellular modem status
./cellular-integration/cellular-data-collector-rutos.sh test mob1s1a1
./cellular-integration/cellular-data-collector-rutos.sh test mob1s2a1

# Validate smart failover decisions
./cellular-integration/smart-failover-engine-rutos.sh analyze

# Monitor continuous operation
tail -f /var/log/cellular_data.csv
```

### Troubleshooting

**No Cellular Data**:

- Check modem interfaces: `ip link show`
- Verify gsmctl availability: `which gsmctl`
- Test AT commands: `gsmctl -A "AT+CSQ" -M 1`

**Poor Signal Quality**:

- Check antenna connections
- Verify SIM card status
- Test different orientations/locations

**Failover Not Working**:

- Check scoring thresholds in configuration
- Verify interface names match actual setup
- Test routing table: `ip route`

### Logs and Debugging

Enable debug mode for detailed troubleshooting:

```bash
DEBUG=1 ./cellular-integration/smart-failover-engine-rutos.sh analyze
```

Key log files:

- `/var/log/cellular_data.csv` - Raw cellular data
- `/var/log/enhanced_with_cellular.csv` - Enhanced logs
- `/var/log/aggregated_cellular.csv` - Statistical summaries

## Future Enhancements

### Planned Features

1. **Machine Learning**: Predictive failover based on location patterns
2. **Cost Analytics**: Detailed roaming expense tracking
3. **Performance Benchmarking**: Automatic speed testing
4. **Weather Integration**: Correlation with weather conditions
5. **Community Data**: Shared connectivity insights

### API Integration

- **OpenWrt UCI**: Native configuration management
- **RUTOS APIs**: Deep integration with router features
- **External Services**: Weather, traffic, route planning

### Advanced Analytics

- **Travel Route Optimization**: Best connectivity paths
- **Cost Forecasting**: Roaming expense predictions
- **Performance Trends**: Connection quality over time
- **Location Intelligence**: Crowd-sourced connectivity data

## Conclusion

This cellular integration transforms our GPS-enhanced Starlink monitoring into a comprehensive multi-connectivity
intelligence system. It provides:

- **Smart failover decisions** based on signal quality, cost, and performance
- **Roaming cost awareness** to avoid expensive data charges
- **Location-based intelligence** for travel route optimization
- **Efficient data collection** with 60:1 statistical aggregation
- **Backward compatibility** with existing systems

The solution is particularly valuable for motorhome travelers who need reliable, cost-effective connectivity
across diverse geographic and network environments. It enables intelligent connection management that adapts to
changing conditions while maintaining comprehensive logging for analysis and optimization.

**Ready for deployment** on RUTX50 routers with RUTOS firmware, providing immediate benefits for both dual-modem
and triple-connectivity configurations.
