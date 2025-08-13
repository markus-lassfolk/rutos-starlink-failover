# Migration Guide: Bash to Go Implementation

This guide explains the transition from the Bash-based RUTOS Starlink Failover system to the new Go-based daemon.

## Overview

The new Go implementation (`starfaild`) replaces the collection of Bash scripts with a single, efficient daemon while maintaining compatibility with existing configurations and workflows.

## Key Changes

### From Multiple Scripts to Single Daemon

**Before (Bash)**:
```
/usr/local/starlink/bin/
├── starlink_monitor_unified-rutos.sh    # Main monitoring
├── connection-scoring-system-rutos.sh   # Scoring logic
├── intelligent-failover-manager-rutos.sh # Decision engine
└── [various support scripts]
```

**After (Go)**:
```
/usr/sbin/starfaild                      # Single daemon binary
/usr/sbin/starfailctl                    # CLI helper (thin shell wrapper)
```

### Configuration Compatibility

The UCI configuration format remains the same:

```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    # ... same options as before
```

### API Evolution

**Before**: Direct script execution and file-based state
**After**: ubus API with structured JSON responses

```bash
# Old way
./starlink_monitor_unified-rutos.sh --status

# New way  
starfailctl status
# or directly:
ubus call starfail status
```

## Installation Process

### 1. Backup Current System

```bash
# Create backup of current installation
mkdir -p /tmp/starfail-backup
cp -r /usr/local/starlink /tmp/starfail-backup/
cp /etc/config/starfail /tmp/starfail-backup/ 2>/dev/null || true
```

### 2. Install Go Daemon

#### OpenWrt Package Installation
```bash
opkg update
opkg install starfail_1.0.0_arm_cortex-a7.ipk
```

#### Manual Installation
```bash
# Download binary for your platform
wget https://github.com/markus-lassfolk/rutos-starlink-failover/releases/latest/starfaild-rutos-armv7
chmod +x starfaild-rutos-armv7
mv starfaild-rutos-armv7 /usr/sbin/starfaild

# Install support scripts
wget https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfailctl
chmod +x starfailctl
mv starfailctl /usr/sbin/

# Install init script
wget https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfail.init
mv starfail.init /etc/init.d/starfail
chmod +x /etc/init.d/starfail
```

### 3. Configuration Migration

The Go daemon automatically migrates most configurations, but verify:

```bash
# Check current config
cat /etc/config/starfail

# Test configuration parsing
starfaild -config /etc/config/starfail -version
```

### 4. Service Transition

```bash
# Stop old services
/etc/init.d/starlink-monitor stop 2>/dev/null || true

# Enable and start new service
/etc/init.d/starfail enable
/etc/init.d/starfail start

# Verify operation
starfailctl status
```

## Functional Comparison

### Monitoring and Metrics

| Feature | Bash Implementation | Go Implementation |
|---------|-------------------|-------------------|
| Member Discovery | mwan3 config parsing | Native mwan3 integration + auto-discovery |
| Starlink API | grpcurl + jq | Native gRPC client |
| Cellular Metrics | ubus calls + parsing | Native ubus integration |
| WiFi Monitoring | iwinfo + parsing | Native iwinfo integration |
| Data Storage | Files in /tmp | RAM-backed ring buffers |
| Logging | Mixed formats | Structured JSON |

### Decision Making

| Feature | Bash Implementation | Go Implementation |
|---------|-------------------|-------------------|
| Scoring Algorithm | Shell arithmetic | Native floating-point |
| Hysteresis Logic | Time-file based | In-memory state tracking |
| Predictive Logic | Basic thresholds | Advanced slope detection |
| Rate Limiting | File locks | Native synchronization |
| Configuration | Shell variables | Type-safe UCI parsing |

### Performance Improvements

| Metric | Bash System | Go Daemon | Improvement |
|--------|-------------|-----------|-------------|
| Memory Usage | 15-30MB | <25MB | More predictable |
| CPU Usage | 5-15% (peaks) | <5% steady | More efficient |
| Startup Time | 10-15s | <2s | Faster boot |
| Response Time | 1-3s | <100ms | Real-time |

## Troubleshooting Migration

### Common Issues

#### 1. Config Not Found
```bash
# Symptom: starfaild fails to start
# Solution: Create default config
starfailctl status  # This triggers default config creation
```

#### 2. ubus Service Not Available
```bash
# Check if daemon is running
ps | grep starfaild

# Check ubus registration
ubus list | grep starfail

# Restart if needed
/etc/init.d/starfail restart
```

#### 3. Member Discovery Issues
```bash
# Check mwan3 configuration
cat /etc/config/mwan3

# Force discovery recheck
starfailctl recheck

# View discovery logs
logread | grep starfail
```

#### 4. Metric Collection Problems
```bash
# Check collector status per member
starfailctl members

# View detailed metrics
starfailctl metrics wan_starlink

# Enable debug logging
starfailctl setlog debug
```

### Rollback Procedure

If issues occur, rollback to Bash system:

```bash
# Stop Go daemon
/etc/init.d/starfail stop
/etc/init.d/starfail disable

# Restore backup
cp -r /tmp/starfail-backup/starlink /usr/local/
cp /tmp/starfail-backup/starfail /etc/config/

# Restart old system
/etc/init.d/starlink-monitor enable
/etc/init.d/starlink-monitor start
```

## Validation Checklist

After migration, verify these functions:

### Basic Operation
- [ ] Daemon starts without errors
- [ ] Members are discovered correctly
- [ ] Metrics are collected for all interfaces
- [ ] Scores are calculated properly

### Failover Behavior  
- [ ] Automatic failover on primary degradation
- [ ] Failback when primary recovers
- [ ] Manual failover/restore commands work
- [ ] Cooldown periods are respected

### Integration
- [ ] mwan3 policies update correctly
- [ ] UCI configuration reloads work
- [ ] ubus API responds to all methods
- [ ] Logging appears in syslog

### Performance
- [ ] Memory usage stays within limits
- [ ] CPU usage is reasonable
- [ ] No excessive log spam
- [ ] Response times are acceptable

## Getting Help

### Log Analysis
```bash
# View recent logs
logread | grep starfail | tail -50

# Enable debug mode
starfailctl setlog debug

# View live logs
logread -f | grep starfail
```

### Status Reporting
```bash
# Comprehensive status
starfailctl status
starfailctl members
starfailctl events 20

# System information
cat /proc/version
df -h
free -m
```

### Community Support

- **GitHub Issues**: https://github.com/markus-lassfolk/rutos-starlink-failover/issues
- **Documentation**: Check `/docs` directory for additional guides
- **Legacy Reference**: Bash scripts preserved in `/archive` for reference

## Future Updates

The Go daemon supports:

- **Hot configuration reloads**: `kill -HUP $(pidof starfaild)`
- **Remote updates**: Binary can be replaced without downtime
- **Feature flags**: UCI options for experimental features
- **Plugin architecture**: Future extension points for custom collectors
