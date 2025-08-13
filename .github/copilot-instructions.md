# RUTOS Starlink Failover Project Instructions

## Architecture Overview: Production Go Daemon

This project implements **starfaild**, a production-ready Go daemon for intelligent multi-interface failover on RutOS/OpenWrt routers. The system uses a **collector → decision → controller** pipeline with comprehensive telemetry.

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Collectors    │───▶│ Decision Engine │───▶│   Controllers   │
│ (Starlink API,  │    │ (EWMA Scoring,  │    │ (mwan3 policies,│
│  cellular ubus, │    │  hysteresis,    │    │  route metrics) │
│  ping tests)    │    │  predictive)    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
         ┌─────────────────────────────────────────────────┐
         │       Telemetry Store & ubus API               │
         └─────────────────────────────────────────────────┘
```

## Core Development Patterns

### Go Module Structure (Zero Dependencies)
- **No external dependencies** - Pure stdlib for embedded targets
- **Internal packages**: All functionality in `pkg/` with clear boundaries
- **Structured data flow**: `collector.Metrics → decision.Score → controller.Action`
- **Embed resources**: Use `//go:embed` for static configs/templates

### Cross-Platform Build System
Use `Makefile` targets for device-specific builds:
```bash
make rutx50    # ARMv7 for RUTX50/11/12
make rut901    # MIPS for older RUT series  
make check     # fmt + vet + test
```

### Embedded Integration Points
- **UCI config**: Use `pkg/uci` for `/etc/config/starfail` parsing with struct tags
- **ubus API**: `pkg/ubus` provides JSON-RPC interface matching OpenWrt conventions
- **procd integration**: `scripts/starfail.init` with respawn and file watching
- **mwan3 control**: `pkg/controller` drives existing policies, never replaces them

### Resource-Constrained Design
- **Memory limits**: ≤25MB RAM, with configurable sample retention in `pkg/telem`
- **CPU efficiency**: Polling intervals configurable (default 1.5s), background collection
- **Binary size**: Static linking with `-ldflags "-s -w"` targeting ≤12MB
- **Graceful shutdown**: Signal handling with cleanup in main daemon

## Key Configuration Patterns

### UCI Configuration Structure (configs/starfail.example)
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    option poll_interval_ms '1500'
    
config member 'starlink_any'
    option detect 'auto'
    option class 'starlink'
```

### Metrics Collection Contract (pkg/collector/collector.go)
- **Interface uniformity**: All collectors implement `Collector` interface
- **Typed metrics**: Use `*float64` for optional values (Starlink obstruction, cellular RSSI)
- **Class-specific data**: Starlink (SNR, outages), cellular (RSRP, RSRQ), WiFi (signal, bitrate)
- **Timestamp consistency**: All metrics use `time.Time` for correlation

### Decision Engine Scoring (pkg/decision/engine.go)
- **Multi-layer scoring**: Instant, EWMA, WindowAvg → Final blended score (0-100)
- **Hysteresis prevention**: Cooldown periods and switch margin thresholds
- **Audit trail**: Every decision logged with `pkg/audit` for debugging

## Development Workflows

### Local Development
```bash
go run ./cmd/starfaild -config configs/starfail.example -log-level debug
```

### Testing Strategy
- **Unit tests**: Focus on scoring algorithms and UCI parsing
- **Integration tests**: Use actual ubus/mwan3 commands in test environment
- **Cross-compilation**: Test binary size and startup on target architectures

### Shell Script Constraints (scripts/)
- **POSIX sh only**: No bash syntax - target BusyBox on routers
- **Use instruction files**: Follow patterns in `.github/instructions/*.instructions.md`
- **Minimal scripts**: Only init, CLI wrapper, hotplug handlers

### OpenWrt Packaging (openwrt/Makefile)
- **golang-package.mk**: Standard OpenWrt Go build system
- **Dependencies**: +mwan3 +ca-bundle for HTTPS Starlink API
- **Install files**: Binary, UCI config, init script, CLI helper

## Debugging and Monitoring

### Structured Logging (pkg/logx)
```go
logger.Info("interface score calculated", 
    "member", member.Name,
    "score", score.Final,
    "metrics", metrics)
```

### ubus API for Live Monitoring
```bash
ubus call starfail status    # Current state and scores
ubus call starfail metrics   # Historical telemetry  
ubus call starfail members   # Interface discovery
```

### Telemetry Retention (pkg/telem)
- **In-memory store**: Configurable sample limits per interface
- **Event logging**: Failover decisions with full context
- **JSON export**: Structured data for external analysis

## Legacy and Migration

- **Archive reference**: Complete bash implementation preserved in `archive/`
- **UCI compatibility**: Same configuration interface as legacy version
- **Gradual rollout**: Can run alongside bash version during transition
