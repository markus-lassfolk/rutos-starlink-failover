# 🚀 RUTOS Starlink Failover - Quick Reference

## Essential Commands

### System Status
```bash
starfailctl status                    # Overall daemon status
starfailctl members                   # All interfaces and scores
starfailctl metrics starlink_any      # Detailed metrics for interface
starfailctl events 20                 # Recent decision events
```

### Manual Control
```bash
starfailctl failover                  # Force failover to best backup
starfailctl restore                   # Restore to primary interface
starfailctl recheck                   # Re-scan for interfaces
starfailctl setlog debug              # Enable debug logging
```

### ubus API
```bash
ubus call starfail status             # JSON status output
ubus call starfail members            # All members with scores
ubus call starfail action '{"action":"failover"}'  # Manual failover
ubus call starfail config.get         # Show configuration
```

## Basic Configuration

### Essential UCI Settings (`/etc/config/starfail`)
```uci
config starfail 'main'
    option enable '1'                 # Enable daemon
    option use_mwan3 '1'             # Use mwan3 for routing
    option poll_interval_ms '1500'   # Main loop interval
    option log_level 'info'          # Logging level
    
    # Failure thresholds
    option fail_threshold_loss '5'            # 5% packet loss = failure
    option fail_threshold_latency '1200'      # 1200ms latency = failure
    option fail_min_duration_s '10'           # Fail for 10s before switch
    
    # Recovery thresholds  
    option restore_threshold_loss '1'         # 1% loss = good
    option restore_threshold_latency '800'    # 800ms = good
    option restore_min_duration_s '30'        # Good for 30s before restore

# Starlink API settings
config starfail 'starlink'
    option dish_ip '192.168.100.1'   # Starlink dish IP
    option dish_port '9200'          # gRPC API port
```

### Interface Priority Configuration
```uci
# Starlink (highest priority)
config member 'starlink_any'
    option detect 'auto'
    option class 'starlink'
    option weight '100'              # Highest weight

# Cellular backup
config member 'cellular_any'  
    option detect 'auto'
    option class 'cellular'
    option weight '80'               # Good backup
    option metered '1'               # Mark as metered

# WiFi backup
config member 'wifi_any'
    option detect 'auto'
    option class 'wifi' 
    option weight '60'               # Lower priority

# LAN backup
config member 'lan_any'
    option detect 'auto'
    option class 'lan'
    option weight '40'               # Lowest priority
```

## Quick Setup

### 1. Install
```bash
# For RUTX50/11/12 (ARMv7)
wget -O starfaild https://github.com/markus-lassfolk/rutos-starlink-failover/releases/latest/download/starfaild-rutx50
chmod +x starfaild && mv starfaild /usr/sbin/

# Install service files
wget -O /etc/init.d/starfail https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfail.init
chmod +x /etc/init.d/starfail

# Install CLI tool
wget -O /usr/bin/starfailctl https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfailctl
chmod +x /usr/bin/starfailctl
```

### 2. Configure
```bash
# Create basic configuration
wget -O /etc/config/starfail https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/configs/starfail.example

# Edit configuration
vi /etc/config/starfail

# Enable and start
/etc/init.d/starfail enable
/etc/init.d/starfail start
```

### 3. Verify
```bash
# Check status
starfailctl status

# Monitor for 30 seconds
starfaild --monitor --log-level debug
```

## Notifications Setup

### Pushover (Recommended)
```uci
config starfail 'notifications'
    option enable '1'
    option pushover_enabled '1'
    option pushover_token 'your_app_token'    # From pushover.net
    option pushover_user 'your_user_key'      # Your user key
    option rate_limit_minutes '5'             # Cooldown between alerts
```

### MQTT
```uci
config starfail 'notifications'  
    option mqtt_enabled '1'
    option mqtt_broker 'mqtt://broker:1883'
    option mqtt_topic 'starfail/alerts'
```

## Scoring System Quick Reference

### Score Components
- **Instant Score**: Real-time performance (0-100)
- **EWMA Score**: Smoothed average with exponential weighting  
- **Window Average**: Historical performance over time window
- **Final Score**: Blended: 30% instant + 50% EWMA + 20% window

### Default Weights
- **Latency**: 25% of score
- **Packet Loss**: 30% of score  
- **Jitter**: 15% of score
- **Obstruction** (Starlink): 20% of score
- **Signal Quality**: 10% of score

### Performance Thresholds
| Metric | Good | Bad | 
|--------|------|-----|
| Latency | <50ms | >1500ms |
| Loss | 0% | >10% |
| Jitter | <5ms | >200ms |
| Obstruction | 0% | >10% |

## Troubleshooting

### Common Issues
```bash
# Daemon won't start
/etc/init.d/starfail status
starfaild --config /etc/config/starfail --debug

# No interfaces detected  
starfailctl recheck
ip link show
mwan3 status

# Poor scoring
starfailctl metrics member_name
ping -c 10 8.8.8.8

# Notifications not working
ubus call starfail notify '{"message":"Test","priority":"info"}'
```

### Debug Commands
```bash
# Enable debug logging
starfailctl setlog debug

# Force interface rescan
starfailctl recheck

# Manual failover test
starfailctl failover

# Check health endpoint
curl http://127.0.0.1:9101/health

# View recent events
starfailctl events 50
```

## File Locations

| File | Purpose |
|------|---------|
| `/usr/sbin/starfaild` | Main daemon binary |
| `/usr/bin/starfailctl` | CLI management tool |
| `/etc/config/starfail` | UCI configuration |
| `/etc/init.d/starfail` | Service init script |
| `/var/run/starfail.pid` | Process ID file |
| `/var/log/messages` | System logs (contains starfail logs) |

## Performance Targets

- **Memory Usage**: <25MB RSS
- **CPU Usage**: <5% idle, <15% during failover
- **Response Time**: <5 seconds end-to-end failover
- **Decision Time**: <1 second calculation
- **Binary Size**: <12MB (stripped)

For complete documentation, see [FEATURES_AND_CONFIGURATION.md](FEATURES_AND_CONFIGURATION.md)
