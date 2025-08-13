# Starfail - Go Core

A reliable, autonomous, and resource-efficient multi-interface failover daemon for RutOS and OpenWrt routers.

## Overview

Starfail is a Go-based daemon that manages multi-interface failover (Starlink, cellular with multiple SIMs, Wi-Fi STA/tethering, LAN uplinks) with predictive behavior so users don't notice degradation/outages.

## Features

- **Auto-discovery** of mwan3 members and their underlying netifd interfaces
- **Multi-class support**: Starlink, Cellular, Wi-Fi, LAN with specialized metrics
- **Predictive failover** based on health scoring and trend analysis
- **Native integration** with UCI, ubus, procd, and mwan3
- **Resource-efficient**: minimal CPU wakeups, RAM caps, low traffic on metered links
- **Observability**: structured logs, metrics, event history for troubleshooting

## Quick Start

### Prerequisites

- RutOS or OpenWrt router
- mwan3 package installed
- Go 1.22+ (for building)

### Installation

```bash
# Build for ARM (RutOS/OpenWrt)
export CGO_ENABLED=0
GOOS=linux GOARCH=arm GOARM=7 go build -ldflags "-s -w" -o starfaild ./cmd/starfaild
strip starfaild

# Install
cp starfaild /usr/sbin/
chmod 755 /usr/sbin/starfaild
```

### Configuration

Create `/etc/config/starfail`:

```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    option poll_interval_ms '1500'
    option predictive '1'
    option switch_margin '10'
    option log_level 'info'
```

### Usage

```bash
# Start the daemon
/etc/init.d/starfail start

# Check status
starfailctl status

# View members
starfailctl members

# Manual failover
starfailctl failover
```

## Architecture

- **Collectors**: Per-class metric providers (Starlink/Cellular/Wi-Fi/LAN)
- **Decision Engine**: Scoring + hysteresis + predictive logic
- **Controllers**: mwan3 policy adjuster with netifd fallback
- **Telemetry**: RAM-backed ring buffers for samples and events
- **API**: ubus RPC interface and CLI wrapper

## Documentation

- [Architecture Guide](docs/ARCHITECTURE.md)
- [Configuration Reference](docs/CONFIGURATION.md)
- [API Reference](docs/API_REFERENCE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)

## Development

```bash
# Run tests
go test ./...

# Build for development
go build ./cmd/starfaild

# Run with debug logging
./starfaild -config /etc/config/starfail -log-level debug
```

## License

See [LICENSE](LICENSE) file for details.
