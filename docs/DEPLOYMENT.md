# Starfail Deployment Guide

This guide explains how to build, install, and configure the starfail multi-interface failover daemon on RutOS and OpenWrt systems.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Building from Source](#building-from-source)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Service Management](#service-management)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [Upgrading](#upgrading)

## Prerequisites

### Development Environment

- **Go 1.22+** - Required for building from source
- **Git** - For cloning the repository
- **Make** - For build automation (optional)
- **Cross-compilation tools** - For building for different architectures

### Target System

- **RutOS** (Teltonika) or **OpenWrt** (modern releases)
- **mwan3** package installed (recommended)
- **ubus** available (required)
- **procd** init system (required)

### System Requirements

- **RAM**: Minimum 32MB, recommended 64MB+
- **Flash**: Minimum 8MB, recommended 16MB+
- **CPU**: Any ARM or x86 processor supported by OpenWrt

## Building from Source

### 1. Clone the Repository

```bash
git clone https://github.com/starfail/starfail.git
cd starfail
```

### 2. Build for Target Architecture

#### Using the Build Script (Recommended)

```bash
# Build for all supported architectures
./scripts/build.sh --all

# Build for specific architecture (e.g., ARM)
./scripts/build.sh --target linux/arm --strip --package

# Build with custom version
./scripts/build.sh --version 1.0.1 --target linux/arm64
```

#### Manual Build

```bash
# For ARM (RutOS/OpenWrt)
export CGO_ENABLED=0
export GOOS=linux
export GOARCH=arm
export GOARM=7
go build -ldflags "-s -w" -o starfaild ./cmd/starfaild

# For ARM64
export GOOS=linux
export GOARCH=arm64
go build -ldflags "-s -w" -o starfaild ./cmd/starfaild

# For x86_64
export GOOS=linux
export GOARCH=amd64
go build -ldflags "-s -w" -o starfaild ./cmd/starfaild
```

### 3. Build Output

The build script creates:
- Binary files in `build/` directory
- Package files (`.tar.gz`) if `--package` is used
- Stripped binaries if `--strip` is used

## Installation

### Method 1: Manual Installation

1. **Copy the binary**:
   ```bash
   scp build/starfaild-linux-armv7 root@192.168.1.1:/usr/sbin/starfaild
   ```

2. **Make it executable**:
   ```bash
   ssh root@192.168.1.1 "chmod 755 /usr/sbin/starfaild"
   ```

3. **Copy the CLI**:
   ```bash
   scp scripts/starfailctl root@192.168.1.1:/usr/sbin/starfailctl
   ssh root@192.168.1.1 "chmod 755 /usr/sbin/starfailctl"
   ```

4. **Copy the init script**:
   ```bash
   scp scripts/starfail.init root@192.168.1.1:/etc/init.d/starfail
   ssh root@192.168.1.1 "chmod 755 /etc/init.d/starfail"
   ```

### Method 2: Using Package

1. **Extract the package**:
   ```bash
   tar -xzf build/starfail-1.0.0-linux-arm.tar.gz -C /
   ```

2. **Set permissions**:
   ```bash
   chmod 755 /usr/sbin/starfaild
   chmod 755 /usr/sbin/starfailctl
   chmod 755 /etc/init.d/starfail
   ```

### Method 3: OpenWrt Package

For OpenWrt systems, you can create an `.ipk` package:

```bash
# Create package structure
mkdir -p starfail_1.0.0/usr/sbin
mkdir -p starfail_1.0.0/etc/init.d
mkdir -p starfail_1.0.0/etc/config

# Copy files
cp build/starfaild-linux-armv7 starfail_1.0.0/usr/sbin/starfaild
cp scripts/starfailctl starfail_1.0.0/usr/sbin/
cp scripts/starfail.init starfail_1.0.0/etc/init.d/starfail
cp configs/starfail.example starfail_1.0.0/etc/config/starfail

# Create control file
cat > starfail_1.0.0/CONTROL/control << EOF
Package: starfail
Version: 1.0.0
Depends: mwan3
Architecture: arm_cortex-a7
Installed-Size: 1024
Description: Multi-interface failover daemon
EOF

# Build package
tar -czf data.tar.gz -C starfail_1.0.0 .
tar -czf control.tar.gz -C starfail_1.0.0/CONTROL .
echo "2.0" > debian-binary
ar -r starfail_1.0.0_arm_cortex-a7.ipk debian-binary control.tar.gz data.tar.gz
```

## Configuration

### 1. Create Configuration File

```bash
# Copy sample configuration
cp configs/starfail.example /etc/config/starfail
```

### 2. Edit Configuration

Edit `/etc/config/starfail` to match your setup:

```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    option poll_interval_ms '1500'
    option predictive '1'
    option ml_enabled '1'
    option ml_model_path '/etc/starfail/models.json'
    option switch_margin '10'
    option log_level 'info'

# Configure your interfaces
config member 'starlink_any'
    option detect 'auto'
    option class 'starlink'
    option weight '100'

config member 'cellular_any'
    option detect 'auto'
    option class 'cellular'
    option weight '80'
    option metered '1'
```

The `ml_model_path` option must point to a writable location containing
JSON-formatted model definitions. If the file exists, models are loaded
at startup; otherwise, new models will be trained and saved to this path.

### 3. Configure mwan3 (Recommended)

Ensure mwan3 is properly configured:

```bash
# Install mwan3 if not already installed
opkg update
opkg install mwan3

# Configure mwan3 interfaces
uci set mwan3.wan_starlink=interface
uci set mwan3.wan_starlink.enabled=1
uci set mwan3.wan_starlink.track_method=ping
uci set mwan3.wan_starlink.track_ip=8.8.8.8

uci set mwan3.wan_cell=interface
uci set mwan3.wan_cell.enabled=1
uci set mwan3.wan_cell.track_method=ping
uci set mwan3.wan_cell.track_ip=8.8.8.8

# Commit changes
uci commit mwan3
```

## Service Management

### 1. Start the Service

```bash
# Start starfail
/etc/init.d/starfail start

# Enable at boot
/etc/init.d/starfail enable
```

### 2. Check Status

```bash
# Check service status
/etc/init.d/starfail status

# Check daemon status
starfailctl status

# Check members
starfailctl members
```

### 3. Service Commands

```bash
# Start/stop/restart
/etc/init.d/starfail start
/etc/init.d/starfail stop
/etc/init.d/starfail restart

# Reload configuration
/etc/init.d/starfail reload

# Health check
/etc/init.d/starfail health

# Show information
/etc/init.d/starfail info
```

## Testing

### 1. Basic Functionality

```bash
# Check if daemon is running
ps aux | grep starfaild

# Check ubus service
ubus list | grep starfail

# Test ubus calls
ubus call starfail status
ubus call starfail members
```

### 2. Interface Testing

```bash
# Test specific member
starfailctl metrics wan_starlink

# Check events
starfailctl events 10

# Manual failover test
starfailctl failover
```

### 3. Log Monitoring

```bash
# Monitor logs
logread -f | grep starfail

# Check daemon logs
tail -f /var/log/starfaild.log
```

### 4. Performance Testing

```bash
# Check memory usage
ps aux | grep starfaild

# Check CPU usage
top -p $(pgrep starfaild)

# Check telemetry storage
starfailctl info
```

## Troubleshooting

### Common Issues

#### 1. Daemon Won't Start

**Symptoms**: Service fails to start
**Solutions**:
```bash
# Check binary permissions
ls -la /usr/sbin/starfaild

# Check configuration
/etc/init.d/starfail test

# Check logs
logread | grep starfail

# Run manually for debugging
/usr/sbin/starfaild -config /etc/config/starfail -log-level debug
```

#### 2. No Members Discovered

**Symptoms**: `starfailctl members` returns empty
**Solutions**:
```bash
# Check mwan3 configuration
ubus call mwan3 status

# Check network interfaces
ip link show

# Check UCI configuration
uci show mwan3
```

#### 3. ubus Service Not Available

**Symptoms**: `ubus list` doesn't show starfail
**Solutions**:
```bash
# Check if daemon is running
ps aux | grep starfaild

# Check ubus socket
ls -la /var/run/ubus.sock

# Restart ubus if needed
/etc/init.d/ubus restart
```

#### 4. High Memory Usage

**Symptoms**: Daemon using too much RAM
**Solutions**:
```bash
# Reduce telemetry retention
uci set starfail.main.retention_hours=12
uci set starfail.main.max_ram_mb=8
uci commit starfail

# Restart service
/etc/init.d/starfail restart
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug level
starfailctl setlog debug

# Monitor logs
logread -f | grep starfail

# Check debug output
starfailctl info
```

### Log Analysis

```bash
# Show recent events
starfailctl events 50

# Check member history
starfailctl history wan_starlink 3600

# Analyze metrics
starfailctl metrics wan_starlink
```

## Upgrading

### 1. Backup Configuration

```bash
# Backup current configuration
cp /etc/config/starfail /etc/config/starfail.backup

# Backup telemetry data (if needed)
cp -r /tmp/starfail /tmp/starfail.backup
```

### 2. Stop Service

```bash
/etc/init.d/starfail stop
```

### 3. Install New Version

```bash
# Copy new binary
cp starfaild-new /usr/sbin/starfaild
chmod 755 /usr/sbin/starfaild

# Update scripts if needed
cp starfailctl-new /usr/sbin/starfailctl
cp starfail.init-new /etc/init.d/starfail
```

### 4. Start Service

```bash
/etc/init.d/starfail start
/etc/init.d/starfail status
```

### 5. Verify Upgrade

```bash
# Check version
starfailctl status

# Test functionality
starfailctl members
starfailctl events 10
```

## Performance Tuning

### Memory Optimization

```uci
config starfail 'main'
    # Reduce telemetry retention
    option retention_hours '12'
    option max_ram_mb '8'
    
    # Increase polling interval
    option poll_interval_ms '2000'
```

### Network Optimization

```uci
config starfail 'main'
    # Use conservative data cap mode
    option data_cap_mode 'conservative'
    
    # Reduce switch margin for faster failover
    option switch_margin '5'
```

### CPU Optimization

```uci
config starfail 'main'
    # Increase polling interval
    option poll_interval_ms '3000'
    
    # Disable predictive mode if not needed
    option predictive '0'
```

## Security Considerations

### 1. File Permissions

```bash
# Set correct permissions
chmod 755 /usr/sbin/starfaild
chmod 755 /usr/sbin/starfailctl
chmod 755 /etc/init.d/starfail
chmod 644 /etc/config/starfail
```

### 2. Network Security

- The daemon binds to localhost only for metrics/health endpoints
- ubus calls are restricted to local system
- No external network access required

### 3. Configuration Security

- Keep configuration files secure
- Don't expose sensitive information in logs
- Use appropriate log levels in production

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review logs with debug level enabled
3. Check the project documentation
4. Open an issue on GitHub with detailed information

### Useful Commands

```bash
# System information
starfailctl info

# Service health
/etc/init.d/starfail health

# Configuration validation
/etc/init.d/starfail test

# Performance monitoring
ps aux | grep starfaild
top -p $(pgrep starfaild)
```
