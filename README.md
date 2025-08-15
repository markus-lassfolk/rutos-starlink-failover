# 🚀 Starfail - Go Multi-Interface Failover Daemon

**Experimental Go Implementation (Work in Progress)** | **For RutOS/OpenWrt**

![GitHub Stars](https://img.shields.io/github/stars/markus-lassfolk/rutos-starlink-failover)
![License](https://img.shields.io/github/license/markus-lassfolk/rutos-starlink-failover)
![Last Commit](https://img.shields.io/github/last-commit/markus-lassfolk/rutos-starlink-failover)

An experimental Go daemon for intelligent multi-interface failover on OpenWrt/RutOS routers. Automatically manages connections between **Starlink**, **Cellular (4G/5G)**, **Wi-Fi**, and **Ethernet** interfaces with **predictive switching** and **comprehensive monitoring**.

## 🎯 Architecture Overview

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Collectors    │    │ Decision Engine │    │   Controllers   │
│                 │    │                 │    │                 │
│ • Starlink API  │───▶│ • EWMA Scoring  │───▶│ • mwan3 Policies│
│ • Cellular ubus │    │ • Hysteresis    │    │ • netifd Routes │
│ • WiFi iwinfo   │    │ • Predictive    │    │ • Route Metrics │
│ • LAN/Ping      │    │   Logic         │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Telemetry Store & ubus API                    │
│         • In-memory samples    • Event logging                 │
│         • JSON export          • Live monitoring               │
└─────────────────────────────────────────────────────────────────┘

```

## ✨ Key Features

- **🔄 Intelligent Failover**: Score-based decision engine with EWMA and hysteresis
- **📊 Multi-Interface Support**: Starlink, Cellular, WiFi, and LAN monitoring
- **🎛️ mwan3 Integration**: Native policy management and seamless control
- **📈 Real-time Metrics**: In-memory telemetry with structured JSON logging
- **🔌 ubus API**: Complete management interface for automation
- **⚡ High Performance**: Zero-dependency Go binary (~4MB, <10MB RAM)
- **🚧 Experimental Status**: Core daemon loop and ubus integration are still under development
- **🔍 Observability**: Structured logging, event tracking, and live monitoring

## � Quick Start

### Installation (RutOS/RUTX Series)


```bash

# Download pre-built binary for ARMv7 (RUTX50/11/12)

wget -O starfaild https://github.com/markus-lassfolk/rutos-starlink-failover/releases/latest/download/starfaild-rutx50
chmod +x starfaild && sudo mv starfaild /usr/sbin/

# Install CLI and service files

wget -O /usr/sbin/starfailctl https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfailctl.sh
wget -O /etc/init.d/starfail https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/starfail.init
chmod +x /usr/sbin/starfailctl /etc/init.d/starfail

# Start the service

/etc/init.d/starfail enable
/etc/init.d/starfail start

# Verify operation

starfailctl status

```

### Basic Usage


```bash

# Check daemon status and current primary interface

starfailctl status

# List all discovered members with scores

starfailctl members

# View detailed metrics for an interface

starfailctl metrics wan_starlink

# Manual failover to specific interface

starfailctl failover wan_cell

# View recent system events

starfailctl events

# Service management

/etc/init.d/starfail {start|stop|restart|reload|status}

```

## 🔧 Manual Operation & Debugging

The starfail daemon can be run manually for testing, debugging, and real-time monitoring. This is especially useful during development, troubleshooting, or when you want to observe the daemon's behavior in detail.

### Running the Daemon Manually

#### Basic Manual Execution


```bash

# Run with default configuration

starfaild --config /etc/config/starfail

# Run with custom configuration file

starfaild --config /tmp/test-starfail.conf

```

#### Real-Time Monitoring Mode


```bash

# Full monitoring with live console output

starfaild --monitor --verbose --trace

# Clean monitoring without colors (for log files)

starfaild --monitor --no-color --verbose

# JSON structured output for analysis

starfaild --monitor --json --verbose

#### Debug and Development

```bash
# Debug configuration issues
starfaild --monitor --debug --config ./configs/starfail.example

# Trace all API calls and decision logic

starfaild --monitor --trace --verbose

# Test configuration without making changes

starfaild --monitor --trace --config /tmp/test-config --log-level trace

```

### Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--config PATH` | UCI configuration file path | `--config /etc/config/starfail` |
| `--monitor` | Enable real-time console monitoring | `--monitor` |
| `--verbose` | Enable verbose logging (debug level) | `--verbose` |
| `--trace` | Enable trace logging (most detailed) | `--trace` |
| `--debug` | Alias for verbose mode | `--debug` |
| `--log-level LEVEL` | Set specific log level | `--log-level debug` |
| `--log-file PATH` | Write logs to file | `--log-file /var/log/starfail.log` |
| `--json` | Output logs in JSON format | `--json` |
| `--no-color` | Disable colored output | `--no-color` |
| `--version` | Show version and exit | `--version` |
| `--help` | Show help with examples | `--help` |

### Monitoring Output Example

When running with `--monitor`, you'll see real-time output like this:

```text
[15:04:05.123] INFO  Starting starfail daemon version=v2.0.0 config=/etc/config/starfail
[15:04:05.234] DEBUG Loading UCI configuration members=3 interfaces_detected=2  
[15:04:05.345] TRACE Starlink API request endpoint=192.168.100.1/SpaceX/get_status
[15:04:05.456] INFO  Starlink metrics collected snr=8.2 outages=3 obstruction=2.1%
[15:04:05.567] TRACE Cellular metrics ubus_call=network.interface.cellular_wan
[15:04:05.678] INFO  Cellular metrics collected rsrp=-85 rsrq=-12 technology=LTE
[15:04:05.789] DEBUG Decision engine processing members=2 scores=[85.2, 72.1]
[15:04:05.890] WARN  Interface score below threshold interface=starlink score=65.2 threshold=70
[15:04:05.991] INFO  Failover triggered from=starlink to=cellular reason=low_score

```

### Log Levels Explained

- **TRACE**: Most detailed logging - shows internal operations, API calls, data flow
- **DEBUG**: Development debugging - configuration parsing, metric collection details  
- **INFO**: General operational information - startup, failovers, status changes
- **WARN**: Warning conditions - score drops, API failures that don't stop operation
- **ERROR**: Error conditions - configuration errors, critical failures

### Common Debug Scenarios

#### Testing Configuration Changes


```bash

# Test new configuration without affecting running daemon

cp /etc/config/starfail /tmp/test-config

# Edit /tmp/test-config

starfaild --monitor --config /tmp/test-config --trace

```

#### Troubleshooting API Issues


```bash

# See all Starlink API calls and responses

starfaild --monitor --trace | grep -i starlink

# Monitor cellular connectivity issues

starfaild --monitor --trace | grep -i cellular

```

#### Analyzing Failover Decisions


```bash

# Watch decision engine scoring in real-time

starfaild --monitor --debug | grep -E "(score|decision|failover)"

# Export decisions to file for analysis

starfaild --monitor --json --verbose > /var/log/starfail-debug.json

```

#### Performance Monitoring


```bash

# Monitor resource usage and timing

starfaild --monitor --trace | grep -E "(timing|memory|cpu)"

# Check polling intervals and response times

starfaild --monitor --debug | grep -E "(poll|interval|latency)"

```

### Integration with System Tools

#### Using with systemctl (systemd systems)


```bash

# Stop service daemon

systemctl stop starfail

# Run manually for debugging

starfaild --monitor --debug --config /etc/config/starfail

# Restart service when done

systemctl start starfail

```

#### Using with procd (OpenWrt/RutOS)


```bash

# Stop service daemon

/etc/init.d/starfail stop

# Run manually for debugging

starfaild --monitor --debug --config /etc/config/starfail

# Restart service when done

/etc/init.d/starfail start

```

#### Log File Analysis


```bash

# Capture structured logs for analysis

starfaild --json --verbose --log-file /var/log/starfail-debug.json

# Parse logs with jq

cat /var/log/starfail-debug.json | jq '.fields | select(.score != null)'

# Monitor failover events

tail -f /var/log/starfail-debug.json | jq 'select(.message | contains("failover"))'

```

### Safety Notes

⚠️ **Important**: When running the daemon manually, ensure the system service is stopped to prevent conflicts:

```bash

# Always stop the service first

/etc/init.d/starfail stop

# Run your manual testing

starfaild --monitor --debug

# Remember to restart the service

/etc/init.d/starfail start

```

💡 **Tip**: Use `screen` or `tmux` for long-running manual sessions:

```bash
screen -S starfail-debug
starfaild --monitor --trace --config /etc/config/starfail

# Ctrl+A, D to detach

# screen -r starfail-debug to reattach


```

> **📍 Victron GPS Integration Moved!**  
> The Victron GPS failover functionality has been split into its own repository for better maintainability.  
> **New location:** [rutos-victron-gps](https://github.com/markus-lassfolk/rutos-victron-gps)

[![Shell Script Quality](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/shellcheck-format.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/shellcheck-format.yml)
[![Security Scan](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/security-scan.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/security-scan.yml)
[![Python Code Quality](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/python-quality.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/python-quality.yml)
[![PowerShell Validation](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/powershell-validation.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/powershell-validation.yml)

[![Documentation Check](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/docs-check.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/docs-check.yml)
[![Configuration Validation](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/config-validation.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/config-validation.yml)
[![Infrastructure Tests](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/infrastructure-validation.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/infrastructure-validation.yml)
[![Integration Tests](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/workflows/integration-tests.yml)

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Azure](https://img.shields.io/badge/Azure-Ready-0078d4.svg)](Starlink-RUTOS-Failover/AzureLogging/)
[![RUTOS](https://img.shields.io/badge/RUTOS-Compatible-orange.svg)](https://teltonika-networks.com/)
[![Starlink](https://img.shields.io/badge/Starlink-Integrated-brightgreen.svg)](https://starlink.com/)

A comprehensive solution for **RV and boat owners** seeking robust internet connectivity. This repository provides
intelligent failover systems for Starlink connections on RUTOS routers.

## 📚 Complete Documentation

### 📖 Essential Reading

| Document | Description | Use Case |
|----------|-------------|-----------|
| **[🚀 Quick Reference](QUICK_REFERENCE.md)** | Essential commands and basic setup | Getting started quickly |
| **[📚 Complete Features Guide](FEATURES_AND_CONFIGURATION.md)** | Comprehensive features and configuration | Understanding all capabilities |
| **[🔌 API Reference](API_REFERENCE.md)** | Complete ubus API and CLI documentation | Integration and automation |
| **[📋 Configuration Examples](CONFIGURATION_EXAMPLES.md)** | Real-world configuration scenarios | Deployment-specific setups |

### 🎯 Quick Navigation

**For New Users:**

1. Start with [Quick Reference](QUICK_REFERENCE.md) for essential commands
2. Read [Configuration Examples](CONFIGURATION_EXAMPLES.md) for your deployment type
3. Use [Features Guide](FEATURES_AND_CONFIGURATION.md) for detailed configuration

**For Developers:**

1. Review [API Reference](API_REFERENCE.md) for integration details
2. Check [Features Guide](FEATURES_AND_CONFIGURATION.md) for technical architecture
3. See [Configuration Examples](CONFIGURATION_EXAMPLES.md) for testing setups

**For System Administrators:**

1. Read [Features Guide](FEATURES_AND_CONFIGURATION.md) for complete system understanding
2. Use [Configuration Examples](CONFIGURATION_EXAMPLES.md) for production deployments
3. Reference [API Reference](API_REFERENCE.md) for monitoring and automation

## 🌟 Features

### 🔄 Proactive Starlink Failover

- **Real-time quality monitoring** using Starlink's internal API
- **Soft failover** preserving existing connections
- **Intelligent recovery** with stability checks
- **Comprehensive notifications** via Pushover
- **Data logging** for threshold optimization

## 🚀 Quick Start

### Option 1: Automated Installation (Recommended)

```bash

# Download and run the installer

curl -fL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/install-rutos.sh | sh

# Configure the system

nano /root/starlink-monitor/config/config.sh

# Validate configuration

/root/starlink-monitor/scripts/validate-config.sh

# Configure mwan3 (see documentation)


```

### Option 2: Manual Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/markus-lassfolk/rutos-starlink-failover.git
   cd rutos-starlink-failover
   ```

2. **Install dependencies**

   ```bash
   # Install grpcurl (ARMv7)
   curl -fL https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz -o /tmp/grpcurl.tar.gz
   tar -zxf /tmp/grpcurl.tar.gz -C /root/ grpcurl
   chmod +x /root/grpcurl

   # Install jq (ARMv7)
   curl -fL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf -o /root/jq
   chmod +x /root/jq
   ```

3. **Configure the system**

   ```bash
   cp config/config.template.sh config/config.sh
   nano config/config.sh
   ```

4. **Deploy scripts**

   ```bash
   cp Starlink-RUTOS-Failover/starlink_monitor.sh /root/
   cp Starlink-RUTOS-Failover/99-pushover_notify /etc/hotplug.d/iface/99-pushover_notify
   chmod +x /root/starlink_monitor.sh /etc/hotplug.d/iface/99-pushover_notify
   ```

## 📋 Prerequisites

### Hardware Requirements

- **Teltonika RUTX50** or similar OpenWrt/RUTOS router
- **Starlink dish** in Bypass Mode
- **Cellular backup** connection

### Software Requirements

- **RUTOS firmware** (latest stable)
- **mwan3 package** configured
- **Pushover account** for notifications

## 🛠️ Configuration

### 1. Basic Configuration

For standard setups, edit `/root/starlink-monitor/config/config.sh`:

```bash

# Network settings

STARLINK_IP="192.168.100.1"
STARLINK_PORT="9200"
MWAN_IFACE="wan"
MWAN_MEMBER="member1"

# Pushover notifications

PUSHOVER_TOKEN="your_pushover_token"
PUSHOVER_USER="your_pushover_user_key"

# Failover thresholds

PACKET_LOSS_THRESHOLD=5       # 5%
OBSTRUCTION_THRESHOLD=3       # 3%
LATENCY_THRESHOLD=150         # 150ms

```

### 1.1 Advanced Configuration (RUTX50 Production)

For RUTX50 routers with dual SIM and GPS, use the advanced template:

```bash

# Use advanced configuration template

cp config/config.advanced.template.sh config/config.sh
nano config/config.sh

# Run UCI optimizer for your existing setup

scripts/uci-optimizer.sh analyze           # Analyze current config
scripts/uci-optimizer.sh optimize          # Apply optimizations

```

**Advanced features include:**

- **GPS-enhanced failover** with movement detection
- **Dual SIM integration** with automatic switching
- **MQTT logging** for integration with existing systems
- **Intelligent reboot scheduling** based on system health
- **Enhanced cellular optimization** for mobile environments

📖 **See [RUTX50 Production Guide](docs/RUTX50-PRODUCTION-GUIDE.md) for detailed setup**

### 2. mwan3 Configuration

```bash

# Set interface priorities

uci set mwan3.member1.metric='1'     # Starlink (highest priority)
uci set mwan3.member3.metric='2'     # Primary SIM
uci set mwan3.member4.metric='4'     # Backup SIM

# Configure health checks

uci set mwan3.wan.track_ip='1.0.0.1' '8.8.8.8'
uci set mwan3.wan.reliability='1'
uci set mwan3.wan.timeout='1'
uci set mwan3.wan.interval='1'
uci set mwan3.wan.down='2'
uci set mwan3.wan.up='3'

# Commit changes

uci commit mwan3
mwan3 restart

```

### 3. Static Route for Starlink

```bash

# Add static route to Starlink management interface

uci add network route
uci set network.@route[-1].interface='wan'
uci set network.@route[-1].target='192.168.100.1'
uci set network.@route[-1].netmask='255.255.255.255'
uci commit network
/etc/init.d/network reload

```

## 🚨 Starlink API Change Response

If you receive a daily notification about a Starlink API schema change:

1. Run `scripts/check_starlink_api_change.sh` to confirm and view the new schema.
2. Compare `/root/starlink_api_schema_last.json` and `/tmp/starlink_api_schema_current.json` for differences.
3. Update `starlink_monitor.sh` and related scripts to match any new/renamed fields.
4. Validate with `scripts/validate-config.sh` and `tests/test-suite.sh`.
5. See `docs/API_CHANGE_RESPONSE.md` for a full step-by-step process.

## 🔧 Advanced Features

### Enhanced Monitoring

The enhanced monitoring system includes:

- **Centralized configuration** management
- **Rate limiting** for notifications
- **Health checks** and diagnostics
- **Graceful error handling**
- **Comprehensive logging**


### Security Features

- **No hardcoded credentials**
- **Configuration validation**
- **Secure defaults**
- **Rate limiting** protection

### Observability

- **Structured logging** with rotation
- **Health status** tracking
- **Performance metrics** collection
- **Notification history**

## 📊 Monitoring and Troubleshooting

### View System Status

```bash

# Check monitor status

logread | grep StarlinkMonitor

# View health status

cat /tmp/run/starlink_monitor.health

# Check recent notifications

tail -f /var/log/notifications.log

```

### Test Notifications

```bash

# Test notification system

/etc/hotplug.d/iface/99-pushover_notify test

# Test Starlink API

grpcurl -plaintext -d '{"get_status":{}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle

```

### Performance Analysis

```bash

# View performance data

cat /root/starlink_performance_log.csv

# Generate API documentation

/root/starlink-monitor/scripts/generate_api_docs.sh

```

## 🔒 Security Considerations

- **Never commit** real credentials to version control
- **Use secure connections** where possible
- **Regularly update** dependencies
- **Monitor logs** for security events
- **Limit API access** to necessary services

## 📚 Documentation

### Project Structure

```text
├── .github/workflows/          # CI/CD workflows
├── config/                     # Configuration templates
│   ├── config.template.sh      # Basic configuration template
│   └── config.advanced.template.sh  # Advanced RUTX50 template
├── scripts/                    # Installation and utility scripts
│   ├── install.sh             # Automated installation
│   ├── validate-config.sh     # Configuration validation
│   └── uci-optimizer.sh       # UCI configuration optimizer
├── docs/                       # Documentation
│   ├── RUTX50-PRODUCTION-GUIDE.md  # RUTX50 specific guide
│   ├── TROUBLESHOOTING.md      # Troubleshooting guide
│   └── API_REFERENCE.md        # API documentation
└── Starlink-RUTOS-Failover/    # Failover system
    ├── starlink_monitor.sh     # Main monitoring script
    ├── 99-pushover_notify      # Notification system
    └── AzureLogging/           # Azure integration

```

### Key Scripts

| Script                | Purpose                                            |
| --------------------- | -------------------------------------------------- |
| `starlink_monitor.sh` | Advanced monitoring with centralized configuration |
| `99-pushover_notify`  | Intelligent notification system                    |
| `starlink_logger.sh`  | Data collection for threshold optimization         |
| `install.sh`          | Automated installation script                      |
| `validate-config.sh`  | Configuration validation                           |

## 🤝 Contributing

1. **Fork** the repository
2. **Create** a feature branch
3. **Test** your changes thoroughly
4. **Submit** a pull request

### Development Guidelines

- **Follow shell script best practices**
- **Add comprehensive error handling**
- **Include documentation** for new features
- **Test on actual hardware** when possible

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided "as-is" without warranty. Test thoroughly in your environment before production use. The
author is not responsible for any damage or service interruption.

## 🙏 Acknowledgments

- **Starlink** for the unofficial API
- **Teltonika** for excellent hardware
- **Community contributors** for testing and feedback

---

**Need help?** Check the [documentation](docs/) or open an
[issue](https://github.com/markus-lassfolk/rutos-starlink-failover/issues).
