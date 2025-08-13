````instructions
# RUTOS Starlink Failover Project Instructions

## Project Status: Go Rewrite in Progress

This project is transitioning from Bash scripts to a **Go-based daemon** (`starfaild`) for better performance, reliability, and maintainability on RutOS/OpenWrt routers.

## Current Architecture

### Core Components (Go)
- **Main daemon**: `cmd/starfaild/` - Single Go binary for all functionality  
- **Packages**: `pkg/` - Modular Go packages (collector, decision, controller, etc.)
- **Target platforms**: RutOS and OpenWrt (ARMv7, MIPS)
- **Integration**: UCI config, ubus API, mwan3, procd init system

### Supporting Scripts (Shell)
- **Init scripts**: `scripts/` - procd init, CLI helper, hotplug
- **Legacy archive**: `archive/` - Preserved Bash implementation for reference
- **Build/packaging**: `openwrt/`, `rutos/` - Cross-compilation and packaging

## Development Guidelines

### Go Code (Primary)
- **Go version**: 1.22+ with modules enabled
- **No CGO**: `CGO_ENABLED=0` for static binaries
- **No external deps**: Keep minimal for embedded systems
- **Structured logging**: JSON format via custom `pkg/logx`
- **Cross-compile targets**: `GOOS=linux GOARCH=arm GOARM=7` (RutOS), `GOARCH=mips` (OpenWrt)

### Shell Scripts (Supporting only)
- **POSIX sh only** - No bash syntax (BusyBox compatibility)
- **Minimal scripts**: Init, CLI wrapper, hotplug helpers only
- **Use RUTOS Library**: For any remaining shell scripts, use existing `lib/rutos-lib.sh`

### Integration Requirements
- **UCI configuration**: `/etc/config/starfail` 
- **ubus API**: Service name `starfail` with methods: status, members, metrics, action
- **mwan3 integration**: Drive existing mwan3 policies, don't replace
- **Resource constraints**: ≤12MB binary, ≤25MB RAM, minimal CPU on idle

## File Structure (New)

```
/cmd/starfaild/          # Main Go daemon
/pkg/                    # Go packages
  collector/             # Metric collection (Starlink, cellular, etc.)
  decision/              # Scoring and failover logic
  controller/            # mwan3/netifd integration
  telem/                 # Telemetry storage
  logx/                  # Structured logging
  uci/                   # UCI config management
  ubus/                  # ubus API server
/scripts/                # Shell support scripts (init, CLI, hotplug)
/configs/                # Example UCI configurations
/openwrt/                # OpenWrt Makefile
/rutos/                  # RutOS SDK packaging
/archive/                # Legacy Bash scripts (read-only)
```

## Build and Deployment

### Cross-compilation
```bash
# For RutOS (ARMv7)
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -ldflags "-s -w" -o starfaild ./cmd/starfaild

# For OpenWrt (MIPS)
CGO_ENABLED=0 GOOS=linux GOARCH=mips go build -ldflags "-s -w" -o starfaild ./cmd/starfaild
```

### Package Integration
- **OpenWrt**: Use `golang-package.mk` in feeds
- **RutOS**: Build with Teltonika SDK
- **Files**: Daemon binary, UCI config, init script, CLI helper

## Quality Requirements

- **Go**: Use `go fmt`, `go vet`, basic unit tests for core logic
- **Shell**: Continue using ShellCheck for remaining scripts
- **Testing**: Cross-platform testing on both RutOS and OpenWrt VMs
- **Documentation**: Update PROJECT_INSTRUCTION.md as implementation progresses

## Legacy Compatibility

- **Archive preserved**: All working Bash scripts moved to `archive/` for reference
- **Gradual migration**: Can run both systems during transition if needed
- **Same interfaces**: UCI config and functionality should be compatible
````
