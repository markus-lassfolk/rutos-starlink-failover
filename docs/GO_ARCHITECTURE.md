# Go Implementation Architecture

This document outlines the Go-based rewrite of the RUTOS Starlink Failover system as specified in PROJECT_INSTRUCTION.md.

## Core Architecture

### Single Binary Design
- **Daemon**: `starfaild` - Single statically linked Go binary
- **Size target**: ≤12MB stripped binary
- **Memory target**: ≤25MB RSS in steady state
- **CPU target**: ≤5% on low-end ARM when healthy

### Package Structure

```
pkg/
├── collector/       # Metric collection interfaces and implementations
│   ├── starlink.go  # Starlink gRPC/JSON API collector
│   ├── cellular.go  # Cellular ubus collector (RutOS mobiled)
│   ├── wifi.go      # WiFi signal quality collector
│   ├── lan.go       # Generic LAN ping-based collector
│   └── registry.go  # Collector registry and factory
├── decision/        # Scoring and decision engine
│   ├── engine.go    # Main decision logic
│   ├── scoring.go   # Metric normalization and scoring
│   └── hysteresis.go # Failover/failback timing logic
├── controller/      # System integration controllers
│   ├── mwan3.go     # mwan3 policy controller (preferred)
│   └── netifd.go    # netifd/route fallback controller
├── telem/          # Telemetry and event storage
│   ├── store.go     # RAM-backed ring buffer storage
│   └── events.go    # Event logging and history
├── logx/           # Structured logging
│   └── logger.go    # JSON structured logger
├── uci/            # UCI configuration management
│   └── config.go    # UCI parser and validator
└── ubus/           # ubus API server
    └── server.go    # ubus method handlers
```

## Core Loop Design

The daemon runs a main loop at ~1.5s intervals:

```go
for {
    select {
    case <-ticker.C:
        // 1. Discover/refresh members
        members := discovery.Scan()
        
        // 2. Collect metrics per member
        for _, member := range members {
            metrics := collectors.Collect(member)
            engine.UpdateMetrics(member, metrics)
        }
        
        // 3. Evaluate decision
        if event := engine.Evaluate(); event != nil {
            controller.Apply(event)
            telemetry.Record(event)
        }
        
    case <-reload:
        config.Reload()
    case <-shutdown:
        return
    }
}
```

## Interface Classification

Member interfaces are classified automatically:

- **Starlink**: Can reach 192.168.100.1 Starlink API
- **Cellular**: ubus mobiled providers or QMI/MBIM/NCM proto
- **WiFi STA**: Wireless STA mode bound to WAN
- **LAN**: DHCP/static ethernet WAN (non-Starlink)
- **Other**: Generic fallback (ping-based only)

## Metric Collection

### Common Metrics (All Classes)
- Latency (ICMP ping or TCP connect timing)
- Packet loss percentage
- Jitter (computed from latency variance)

### Class-Specific Metrics

**Starlink**:
- Obstruction percentage (from API)
- SNR/signal quality
- Outage count
- PoP ping latency

**Cellular**:
- RSSI, RSRP, RSRQ, SINR
- Network type (4G/5G)
- Roaming status
- Cell ID and operator

**WiFi**:
- Signal strength
- Noise floor
- Bitrate
- SNR

## Scoring Algorithm

Instant score (0-100):
```
score = base_weight
      - w_lat * normalize(latency, good_threshold, bad_threshold)
      - w_loss * normalize(loss_pct, 0%, 10%)
      - w_jitter * normalize(jitter, 5ms, 200ms)
      - class_specific_penalties()
      + class_specific_bonuses()
```

Final score blend:
```
final = 0.30 * instant + 0.50 * ewma + 0.20 * window_average
```

## Decision Logic

### Switch Conditions
1. **Score margin**: `new_score - current_score >= switch_margin`
2. **Duration windows**: Sustained good/bad for minimum time
3. **Cooldown respect**: No switches during cooldown period
4. **Eligibility**: Member must be up for minimum time

### Predictive Triggers
- Rising loss/latency slope
- Jitter spikes above threshold
- Starlink obstruction acceleration
- API-reported outages

## Integration Points

### UCI Configuration
- File: `/etc/config/starfail`
- Automatic defaults with validation
- Hot-reload via SIGHUP

### ubus API
- Service: `starfail`
- Methods: `status`, `members`, `metrics`, `history`, `events`, `action`
- JSON responses for all methods

### mwan3 Integration
- Read member configuration from `/etc/config/mwan3`
- Modify weights/metrics without full reloads
- Fallback to netifd if mwan3 unavailable

### Telemetry Storage
- RAM-backed ring buffers
- Configurable retention (default 24h)
- Memory usage capped (default 16MB)
- Optional Prometheus metrics endpoint

## Build and Deployment

### Cross-Compilation
```bash
# RutOS (ARMv7)
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
  go build -ldflags "-s -w" -o starfaild ./cmd/starfaild

# OpenWrt (MIPS)
CGO_ENABLED=0 GOOS=linux GOARCH=mips \
  go build -ldflags "-s -w" -o starfaild ./cmd/starfaild
```

### Package Contents
- `/usr/sbin/starfaild` - Main daemon binary
- `/usr/sbin/starfailctl` - CLI helper script (shell)
- `/etc/init.d/starfail` - procd init script
- `/etc/config/starfail` - Default UCI configuration
- `/etc/hotplug.d/iface/99-starfail` - Interface change handler

## Testing Strategy

### Unit Tests
- Scoring algorithm correctness
- Configuration parsing and validation
- Metric normalization functions

### Integration Tests  
- Mock collectors and controllers
- Configuration reload behavior
- Decision engine logic with synthetic data

### Device Testing
- Cross-platform testing on RutOS and OpenWrt
- Performance benchmarking (CPU/RAM usage)
- Real-world failover scenarios
- Interface flapping and recovery

## Migration from Bash

### Preserved Features
- Same UCI configuration interface
- Compatible member discovery logic
- Equivalent scoring methodology
- Same notification integrations

### Improvements
- Single binary deployment (no script dependencies)
- Structured JSON logging
- Built-in telemetry storage
- Native ubus integration
- Predictive failover capabilities
- Better resource management

### Migration Path
1. Archive existing Bash scripts in `/archive`
2. Deploy Go daemon alongside legacy system
3. Validate equivalent behavior
4. Switch init system to Go daemon
5. Remove legacy scripts when confident
