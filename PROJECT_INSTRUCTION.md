# PROJECT_INSTRUCTION.md
**Starfail – Go Core (RutOS/OpenWrt) – Full Engineering Specification**

> This is the authoritative, version-controlled specification for the Go-based
> multi-interface failover daemon intended to replace the legacy Bash solution.
> It merges the complete initial plan and the multi-interface/scoring/telemetry
> addendum. Treat this document as the single source of truth for Codex/Copilot
> and human contributors. All major design decisions must be reflected here.

## IMPLEMENTATION STATUS


**Last Updated**: 2025-01-14 (Accurate Analysis)

### ✅ FULLY IMPLEMENTED (Production Ready)
- [x] **Project structure and Go module setup** - Complete with proper package organization
- [x] **Core types and interfaces** (`pkg/types.go`) - Comprehensive data structures for all features
- [x] **Structured logging package** (`pkg/logx/logger.go`) - Full implementation with multiple log levels
- [x] **Telemetry store with ring buffers** (`pkg/telem/store.go`) - Working RAM-based storage with cleanup
- [x] **Main daemon entry point** (`cmd/starfaild/main.go`) - Complete with signal handling and graceful shutdown
- [x] **Build script for cross-compilation** (`scripts/build.sh`) - Ready for ARM/MIPS targets
- [x] **Init script for procd** (`scripts/starfail.init`) - OpenWrt/RutOS service integration
- [x] **CLI implementation** (`scripts/starfailctl`) - Shell wrapper for ubus commands
- [x] **Sample configuration file** (`configs/starfail.example`) - Comprehensive UCI configuration


### ⚡ PARTIALLY IMPLEMENTED (Core Functions Work, Advanced Features Missing)
- [⚠️] **UCI configuration** (`pkg/uci/`) - Uses exec commands to call UCI CLI (not native library)
  - ✅ Reads/writes configuration via CLI
  - ❌ No native UCI library integration
  - ❌ Performance overhead from exec calls

- [⚠️] **Starlink collector** (`pkg/collector/starlink.go`) - Basic API integration only
  - ✅ HTTP API calls to 192.168.100.1
  - ✅ Obstruction and outage metrics collection
  - ❌ No enhanced diagnostics (hardware test, thermal, bandwidth restrictions)
  - ❌ No predictive reboot detection
  - ❌ No GPS data collection from Starlink

- [⚠️] **Cellular collector** (`pkg/collector/cellular.go`) - Basic metrics only
  - ✅ ubus command execution for basic metrics
  - ✅ Fallback to /sys/class/net readings
  - ❌ Limited radio metrics (RSRP/RSRQ/SINR may fail)
  - ❌ No roaming detection implementation
  - ❌ No multi-SIM support

- [⚠️] **WiFi collector** (`pkg/collector/wifi.go`) - Minimal implementation
  - ✅ Basic signal strength via iwinfo
  - ❌ No bitrate collection
  - ❌ No SNR calculation
  - ❌ No tethering detection

- [⚠️] **Decision engine** (`pkg/decision/engine.go`) - Basic scoring only
  - ✅ Instant/EWMA/Final score calculation
  - ✅ Basic hysteresis and cooldown
  - ❌ Predictive logic incomplete (TODO comments)
  - ❌ No trend analysis implementation
  - ❌ No pattern detection

- [⚠️] **Controller** (`pkg/controller/controller.go`) - Framework only
  - ✅ mwan3 status checking via CLI
  - ❌ mwan3 policy updates are TODO (logs only, no actual changes)
  - ❌ netifd route metric updates are TODO (logs only)
  - ❌ No actual failover execution

- [⚠️] **System Management** (`pkg/sysmgmt/`) - Real implementation but limited testing
  - ✅ Service monitoring with process checks
  - ✅ Overlay space cleanup implementation
  - ✅ Log rotation and flood detection
  - ⚠️ Untested on actual RutOS devices
  - ❌ No integration with main daemon


### 🔧 STUB/PLACEHOLDER IMPLEMENTATIONS (Not Functional)
- [❌] **ubus server/client** (`pkg/ubus/`) - Incomplete native integration
  - ⚠️ Socket connection attempt but falls back to CLI
  - ❌ Message protocol not fully implemented
  - ❌ Method registration incomplete
  - ❌ Listen loop not functional

- [❌] **Predictive engine** (`pkg/decision/predictive.go`) - Structure only
  - ❌ MLPredictor is empty stub
  - ❌ No actual model training or inference
  - ❌ Trend calculation returns placeholder values
  - ❌ Pattern detection not implemented

- [❌] **Performance profiler** (`pkg/performance/profiler.go`) - Likely placeholder
  - ❌ No actual profiling implementation visible
  - ❌ Automatic tuning not implemented

- [❌] **Security auditor** (`pkg/security/auditor.go`) - Basic framework only
  - ❌ File integrity checks not implemented
  - ❌ Network security checks incomplete
  - ❌ Threat detection is placeholder

- [❌] **MQTT client** (`pkg/mqtt/client.go`) - May be incomplete
  - ⚠️ Implementation not verified
  - ❌ No telemetry publishing logic

- [❌] **Metrics/Health servers** (`pkg/metrics/`, `pkg/health/`) - Framework only
  - ❌ No Prometheus metrics export
  - ❌ Health endpoint returns static data

- [❌] **LuCI/Vuci interface** (`luci/`) - Shell scripts only
  - ❌ No actual Lua implementation
  - ❌ Web UI not functional


### 🚫 NOT IMPLEMENTED (Data Structures Exist, No Logic)
- [ ] **Enhanced Starlink Diagnostics** - Types defined, no collection
- [ ] **GPS Integration** - Types defined, no data sources connected
- [ ] **Location Clustering** - Types defined, no clustering logic
- [ ] **Decision Audit Trail** - Types defined, no logging implementation
- [ ] **Advanced Notifications** - Config exists, only basic Pushover
- [ ] **Obstruction Prediction** - Types defined, no predictive logic
- [ ] **Adaptive Sampling** - Config exists, no rate adjustment
- [ ] **Discovery system** (`pkg/discovery/`) - Referenced but implementation unclear

### ⏳ PENDING (Enhanced Starlink Diagnostics Implementation)
- [ ] **Enhanced Starlink API Integration** - Pull hardware self-test, thermal, bandwidth restrictions from Starlink API
- [ ] **Predictive Reboot Monitoring** - Detect scheduled reboots and trigger preemptive failover
- [ ] **Hardware Health Monitoring** - Real-time hardware status tracking and alerts

### ⏳ PENDING (Location-Aware Intelligence Implementation)
- [ ] **GPS Data Collection** - Pull GPS data from Starlink and RUTOS sources
- [ ] **Movement Detection** - >500m triggers obstruction map reset
- [ ] **Location Clustering Logic** - Implement clustering algorithms for problematic areas
- [ ] **Location-based Threshold Adjustments** - Dynamic threshold adjustment based on location
- [ ] **Multi-source GPS Prioritization** - RUTOS > Starlink GPS priority logic

### ⏳ PENDING (Comprehensive Decision Audit Trail Implementation)
- [ ] **Decision Logging Implementation** - Log all failover decisions with detailed reasoning
- [ ] **Real-Time Decision Viewer** - Live monitoring of decision-making process
- [ ] **Historical Pattern Analysis** - Trend identification and automated recommendations
- [ ] **Root Cause Analysis** - Automated troubleshooting with pattern recognition
- [ ] **Decision Analysis Tools** - CLI and API endpoints for decision analysis

### ⏳ PENDING (Advanced Notification Systems Implementation)
- [ ] **Multi-Channel Notifications** - Email, Slack, Discord, Telegram integration
- [ ] **Smart Notification Management** - Advanced rate limiting and cooldown logic
- [ ] **Contextual Alerts** - Different notification types for fixes, failures, critical issues
- [ ] **Notification Intelligence** - Emergency priority with retry, acknowledgment requirements

### ⏳ PENDING (Predictive Obstruction Management Implementation)
- [ ] **Proactive Failover Logic** - Failover before complete signal loss
- [ ] **Obstruction Acceleration Detection** - Rapid increases in obstruction
- [ ] **SNR Trend Analysis** - Early warning based on SNR trends
- [ ] **Movement-triggered Obstruction Map Refresh** - Reset obstruction data on movement
- [ ] **Environmental Pattern Learning** - Machine learning for environmental patterns
- [ ] **Multi-Factor Obstruction Assessment** - Current + historical + prolonged duration analysis
- [ ] **False Positive Reduction** - Use timeObstructed and avgProlongedObstructionIntervalS
- [ ] **Data Quality Validation** - Check patchesValid and validS for measurement reliability

### ⏳ PENDING (Adaptive Sampling Implementation)
- [ ] **Dynamic Sampling Rates** - 1s for unlimited, 60s for metered connections
- [ ] **Connection Type Detection** - Automatic detection of connection types
- [ ] **Sampling Rate Adjustment** - Real-time adjustment based on connection status

### ⏳ PENDING (Backup and Recovery Implementation)
- [ ] **System Recovery** - Automated recovery after firmware upgrades
- [ ] **Configuration Backup** - Automatic backup of critical configurations
- [ ] **Recovery Procedures** - Automated recovery procedures for common issues

### ⏳ PENDING (Additional Features)
- [ ] Container deployment support (Docker)
- [ ] Cloud integration (AWS, Azure, GCP)
- [ ] Advanced analytics and reporting dashboard
- [ ] Multi-site failover coordination
- [ ] Advanced machine learning model training and deployment
- [ ] Real-time threat intelligence integration
- [ ] Advanced network topology discovery and mapping
- [ ] Integration with external monitoring systems (Prometheus, Grafana, etc.)

### 🐛 CRITICAL ISSUES (Blocking Production)
1. **Controller doesn't actually perform failover** - mwan3/netifd updates are TODO placeholders
2. **ubus server not functional** - Can't receive commands from CLI
3. **Discovery system unclear** - pkg/discovery referenced but implementation missing
4. **No actual network switching** - Decision engine makes decisions but controller doesn't act
5. **Main loop collectors not initialized** - No collector factory setup in main.go
6. **Predictive engine not connected** - Created but never used in decision flow

### ⚠️ KNOWN ISSUES
- UCI integration uses exec calls (performance overhead, error-prone)
- Cellular metrics collection unreliable (ubus mobiled may not exist)
- WiFi collector missing critical metrics (SNR, bitrate)
- System management runs separately (not integrated with main daemon)
- MQTT client implementation unverified
- No integration tests with actual hardware
- Performance profiler and security auditor are mostly placeholders
- LuCI/Vuci interface non-functional

### 🎯 ACTUAL ACHIEVEMENTS
- **Basic Go structure** established with proper package organization
- **Comprehensive data types** defined for all planned features
- **Basic collectors** with some real system integration
- **Logging framework** functional
- **Telemetry storage** working in RAM
- **System management** has real implementation (but separate daemon)
- **Build and deployment** scripts ready

### 📊 REALISTIC IMPLEMENTATION SUMMARY

**✅ ACTUALLY WORKING (Can Run)**
- Basic daemon startup and signal handling
- Configuration loading from UCI (via CLI)
- Logging to syslog/file
- RAM-based telemetry storage
- Basic HTTP API calls to Starlink
- Process monitoring for services

**⚠️ PARTIALLY WORKING (Major Gaps)**
- Collectors gather some metrics but miss critical data
- Decision engine calculates scores but can't trigger failover
- System management works but isn't integrated

**❌ NOT WORKING (Critical for Production)**
- No actual network failover capability
- No predictive failover
- No ubus RPC interface
- No web UI
- No MQTT telemetry publishing
- No GPS integration
- No advanced Starlink diagnostics

**📈 REALISTIC PROGRESS METRICS**
- **Core Framework**: 70% Complete (structure exists, integration missing)
- **Data Collection**: 30% Complete (basic metrics only)
- **Decision Logic**: 40% Complete (scoring works, execution doesn't)
- **System Integration**: 20% Complete (no mwan3/netifd control)
- **Advanced Features**: 5% Complete (types only, no implementation)
- **Overall Production Readiness**: 25% Complete

**🚀 CRITICAL PATH TO PRODUCTION**
1. **Fix Controller** - Implement actual mwan3 policy updates
2. **Connect Discovery** - Implement member discovery from mwan3
3. **Initialize Collectors** - Create collector factory in main loop
4. **Fix ubus Server** - Complete socket protocol or use CLI wrapper
5. **Integration Testing** - Test on actual RutOS/OpenWrt hardware
6. **Complete Basic Failover** - Ensure decisions trigger network changes

## 📝 DETAILED TODO LIST FOR PRODUCTION READINESS

### Phase 1: Core Functionality (CRITICAL - 2 weeks)
```
[ ] Fix pkg/controller/controller.go
    [ ] Implement updateMWAN3Policy() to actually modify mwan3 configs
    [ ] Implement updateRouteMetrics() for netifd fallback
    [ ] Add proper mwan3 member weight adjustments
    [ ] Test failover execution on real hardware

[ ] Implement pkg/discovery/discovery.go
    [ ] Parse /etc/config/mwan3 for interfaces
    [ ] Map mwan3 members to netifd interfaces
    [ ] Classify members by type (Starlink/Cellular/WiFi/LAN)
    [ ] Periodic refresh of member list

[ ] Fix main loop initialization (cmd/starfaild/main.go)
    [ ] Create collector factory
    [ ] Initialize collectors for each discovered member
    [ ] Connect collectors to decision engine
    [ ] Verify telemetry storage of metrics

[ ] Complete ubus integration
    [ ] Either fix native socket protocol in pkg/ubus/
    [ ] OR create reliable CLI wrapper fallback
    [ ] Test all RPC methods work
    [ ] Ensure starfailctl commands function
```

### Phase 2: Reliable Metrics (1 week)
```
[ ] Enhance Starlink collector
    [ ] Parse full API response (not just obstruction)
    [ ] Add SNR, pop ping latency extraction
    [ ] Add hardware status checks
    [ ] Implement connection testing

[ ] Fix Cellular collector
    [ ] Add multi-SIM support detection
    [ ] Improve RSRP/RSRQ/SINR parsing
    [ ] Add roaming detection
    [ ] Handle different modem types (qmi/mbim/ncm)

[ ] Complete WiFi collector
    [ ] Add bitrate collection
    [ ] Calculate proper SNR
    [ ] Add link quality metrics
    [ ] Detect tethering vs STA mode
```

### Phase 3: Decision & Predictive (1 week)
```
[ ] Connect predictive engine
    [ ] Wire PredictiveEngine to Decision.Tick()
    [ ] Implement basic trend detection
    [ ] Add obstruction acceleration detection
    [ ] Test predictive triggers

[ ] Implement decision logging
    [ ] Create CSV logger for decisions
    [ ] Log all evaluations with reasoning
    [ ] Add quality factor breakdowns
    [ ] Include GPS/location context when available

[ ] Add hysteresis tuning
    [ ] Test and tune fail/restore windows
    [ ] Implement proper cooldown tracking
    [ ] Add per-member warmup periods
```

### Phase 4: Testing & Hardening (1 week)
```
[ ] Hardware testing
    [ ] Test on RUTX50 with real Starlink
    [ ] Test on RUTX11 with cellular
    [ ] Verify mwan3 policy changes work
    [ ] Measure actual failover times

[ ] Performance optimization
    [ ] Profile memory usage
    [ ] Reduce exec() calls
    [ ] Optimize telemetry storage
    [ ] Test with 10+ members

[ ] Error handling
    [ ] Handle Starlink API timeouts
    [ ] Handle missing ubus providers
    [ ] Graceful degradation scenarios
    [ ] Recovery from crashes
```

### Phase 5: Advanced Features (2 weeks)
```
[ ] GPS Integration
    [ ] Connect to RUTOS GPS source
    [ ] Pull GPS from Starlink API
    [ ] Implement location clustering
    [ ] Add movement detection

[ ] Enhanced Starlink monitoring
    [ ] Hardware self-test integration
    [ ] Thermal monitoring
    [ ] Bandwidth restriction detection
    [ ] Predictive reboot detection

[ ] Advanced notifications
    [ ] Implement rate limiting
    [ ] Add email/Slack/Discord channels
    [ ] Context-aware alerts
    [ ] Emergency priority handling

[ ] System integration
    [ ] Merge system management into main daemon
    [ ] Add database health checks
    [ ] Implement log flood prevention
    [ ] Add overlay space management
```

## 💡 VERSION 2.0 IDEAS (From Archive Analysis)

### Advanced Features from Legacy System
1. **GPS-Based Intelligence (from archive/GPS-INTEGRATION-COMPLETE-SOLUTION.md)**
   - 60:1 data compression for GPS-stamped metrics
   - Statistical aggregation (min/max/avg/P95) per minute
   - Location clustering for problematic areas
   - Movement detection (>500m triggers obstruction reset)
   - Multi-source GPS prioritization (RUTOS > Starlink)

2. **Enhanced Obstruction Monitoring (from archive/ENHANCED_OBSTRUCTION_MONITORING.md)**
   - Multi-factor obstruction assessment
   - Use timeObstructed vs fractionObstructed for accuracy
   - avgProlongedObstructionIntervalS for disruption detection
   - validS and patchesValid for data quality validation
   - False positive reduction algorithms

3. **Comprehensive Decision Logging (from archive/ENHANCED_DECISION_LOGGING_SUMMARY.md)**
   - 15-column CSV with complete context
   - Real-time decision viewer with color coding
   - Automated pattern analysis and recommendations
   - Quality factor breakdown visualization
   - Historical trend analysis tools

4. **Smart Error Logging (from archive/SMART_ERROR_LOGGING_SYSTEM.md)**
   - Contextual error aggregation
   - Automatic root cause analysis
   - Self-healing suggestions
   - Error pattern recognition

5. **Autonomous System Features**
   - Self-configuration based on network topology
   - Automatic threshold tuning based on location
   - Predictive maintenance alerts
   - Adaptive sampling based on connection type

### Performance Optimizations
1. **Data Optimization**
   - Ring buffer telemetry with automatic downsampling
   - Compressed storage for historical data
   - Efficient binary protocols for IPC
   - Lazy loading of diagnostic data

2. **Resource Management**
   - CPU governor integration
   - Memory pressure handling
   - I/O throttling during high load
   - Automatic garbage collection tuning

### Enterprise Features
1. **Multi-Site Coordination**
   - Centralized management dashboard
   - Cross-site failover orchestration
   - Global policy management
   - Fleet-wide analytics

2. **Cloud Integration**
   - Azure/AWS IoT Hub integration
   - Cloud-based ML model training
   - Remote configuration management
   - Centralized logging and analytics

3. **Advanced Analytics**
   - Machine learning for pattern recognition
   - Predictive failure analysis
   - Capacity planning recommendations
   - Cost optimization insights

---

## Table of Contents
1. [Overview & Problem Statement](#overview--problem-statement)
2. [Design Principles](#design-principles)
3. [Non-Goals](#non-goals)
4. [Target Platforms & Constraints](#target-platforms--constraints)
5. [Repository & Branching](#repository--branching)
6. [High-Level Architecture](#high-level-architecture)
7. [Configuration (UCI)](#configuration-uci)
8. [Daemon Public API (ubus)](#daemon-public-api-ubus)
9. [CLI](#cli)
10. [Integration: mwan3 & netifd](#integration-mwan3--netifd)
11. [Member Discovery & Classification](#member-discovery--classification)
12. [Metric Collection (per class)](#metric-collection-per-class)
13. [Scoring & Predictive Logic](#scoring--predictive-logic)
14. [Decision Engine & Hysteresis](#decision-engine--hysteresis)
15. [Telemetry Store (Short-Term DB)](#telemetry-store-short-term-db)
16. [Logging & Observability](#logging--observability)
17. [Build, Packaging & Deployment](#build-packaging--deployment)
18. [Init, Hotplug & Service Control](#init-hotplug--service-control)
19. [Testing Strategy & Acceptance](#testing-strategy--acceptance)
20. [Performance Targets](#performance-targets)
21. [Security & Privacy](#security--privacy)
22. [Failure Modes & Safe Behavior](#failure-modes--safe-behavior)
23. [Future UI (LuCI/Vuci) – for later](#future-ui-lucivuci--for-later)
24. [Coding Style & Quality](#coding-style--quality)
25. [Appendix: Examples & Snippets](#appendix-examples--snippets)

---

## Overview & Problem Statement
We need a reliable, autonomous, and resource-efficient system on **RutOS** and **OpenWrt**
routers to manage **multi-interface failover** (e.g., Starlink, cellular with multiple SIMs,
Wi‑Fi STA/tethering, LAN uplinks), with **predictive** behavior so users _don't notice_
degradation/outages. The legacy Bash approach created too much process churn, had BusyBox
limitations, and was harder to maintain and extend.

**Solution**: a **single Go daemon** (`starfaild`) that:
- Discovers all **mwan3** members and their underlying netifd interfaces
- Collects **metrics** per member (Starlink API, radio quality, latency/loss, etc.)
- Computes **health scores** (instant + rolling) and performs **predictive failover/failback**
- Integrates natively with **UCI**, **ubus**, **procd**, and **mwan3**
- Exposes a small **CLI** for operational control and deep **DEBUG** logging
- Stores short-term telemetry in **RAM** (no flash wear by default)

No Web UI is required in this phase; we'll add LuCI/Vuci later to the same ubus/UCI API.

---

## Design Principles
- **Single binary** (static, CGO disabled). No external runtimes or heavy deps.
- **OS-native integration**: UCI for config; ubus for control/status; procd for lifecycle.
- **Abstraction first**: collectors and controllers behind interfaces; easy to mock/test.
- **Autonomous by default**: auto-discovery, self-healing, predictive switching.
- **Deterministic & stable**: hysteresis, rate limiting, cooldowns; no flapping.
- **Resource-friendly**: minimal CPU wakeups, RAM caps, low traffic on metered links.
- **Observability**: structured logs (JSON), metrics, event history for troubleshooting.
- **Graceful degradation**: sensible behavior if Starlink API/ubus/mwan3 are unavailable.

---

## Non-Goals
- Shipping any Web UI now (LuCI/Vuci comes later).
- Replacing mwan3 entirely (we **drive** it; we don't reinvent it).
- Long-term persistent database on flash by default (telemetry is in RAM by default).

---

## Target Platforms & Constraints
- **RutOS** (Teltonika, BusyBox `ash`, procd, ubus, UCI, often with `mobiled`/cellular ubus)
- **OpenWrt** (modern releases; BusyBox `ash`, procd, ubus, UCI, mwan3 available)
- **Constraints**: limited flash & RAM; potential ICMP restrictions; variant firmware baselines.
- **Binary size target** ≤ 12 MB stripped; **RSS** ≤ 25 MB steady; **low CPU** on idle.

---

## Repository & Branching
- Create a new branch for this rewrite: `go-core`
- Move legacy Bash & docs to `archive/` (read-only inspiration).
- Proposed layout:
```
/cmd/starfaild/            # main daemon
/pkg/                      # internal packages
  collector/               # starlink, cellular, wifi, lan providers
  decision/                # scoring, hysteresis, predictive logic
  controller/              # mwan3, netifd/ubus integrations
  telem/                   # telemetry ring store & events
  logx/                    # structured logging helpers
  uci/                     # UCI read/validate/default/commit helpers
  ubus/                    # ubus server & method handlers
/scripts/                  # init.d, CLI, hotplug
/openwrt/                  # Makefiles for OpenWrt ipk
/rutos/                    # Teltonika SDK packaging
/configs/                  # example UCI configs
/docs/                     # architecture & operator guides
/archive/                  # legacy code
```

---

## High-Level Architecture
**Core loop** (tick ~1.0–1.5s):
1. Discover/refresh members periodically and on config reload.
2. Collect metrics per member via provider interfaces.
3. Update per-member instant & rolling scores.
4. Rank eligible members; evaluate switch conditions (hysteresis/predictive).
5. Apply decision via the active controller (mwan3 preferred; netifd fallback).
6. Emit logs, events, telemetry; expose state via ubus.

**Key components**
- **Collectors**: per-class metric providers (Starlink/Cellular/Wi‑Fi/LAN/Other).
- **Decision engine**: scoring + hysteresis + predictive, rate-limited.
- **Controllers**: `mwan3` policy adjuster; `netifd`/route metric fallback.
- **Interfaces**: UCI config; ubus RPC; CLI wrapper; procd lifecycle.
- **Telemetry**: RAM-backed ring buffers (samples + events).

---

## Configuration (UCI)
File: `/etc/config/starfail`

> All options must validate and default safely; never crash on missing/invalid config.
> Log a **WARN** for defaulted values. UCI is the **only** config source.

```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'                    # 1=drive mwan3; 0=netifd/route fallback
    option poll_interval_ms '1500'          # base tick
    option history_window_s '600'           # window for rolling score (X minutes)
    option retention_hours '24'             # telemetry retention in RAM
    option max_ram_mb '16'                  # RAM cap for telemetry
    option data_cap_mode 'balanced'         # balanced|conservative|aggressive
    option predictive '1'                   # enable predictive preempt
    option switch_margin '10'               # min score delta to switch
    option min_uptime_s '20'                # global minimum before member eligible
    option cooldown_s '20'                  # global cooldown after switch
    option metrics_listener '0'             # 1=enable :9101/metrics
    option health_listener '1'              # 1=enable :9101/healthz
    option log_level 'info'                 # debug|info|warn|error
    option log_file ''                      # empty=syslog only

    # Fail/restore thresholds (global defaults; per-class overrides allowed)
    option fail_threshold_loss '5'          # %
    option fail_threshold_latency '1200'    # ms
    option fail_min_duration_s '10'         # sustained bad before failover
    option restore_threshold_loss '1'       # %
    option restore_threshold_latency '800'  # ms
    option restore_min_duration_s '30'      # sustained good before failback

    # Notifications (optional)
    option pushover_token ''
    option pushover_user ''

    # Telemetry publish (optional)
    option mqtt_broker ''                   # e.g., tcp://127.0.0.1:1883
    option mqtt_topic 'starfail/status'

# Optional policy overrides (repeatable)
config member 'starlink_any'
    option detect 'auto'                    # auto|disable|force
    option class 'starlink'
    option weight '100'                     # class preference
    option min_uptime_s '30'
    option cooldown_s '20'

config member 'cellular_any'
    option detect 'auto'
    option class 'cellular'
    option weight '80'
    option prefer_roaming '0'               # 0=penalize roaming
    option metered '1'                      # reduce sampling
    option min_uptime_s '20'
    option cooldown_s '20'

config member 'wifi_any'
    option detect 'auto'
    option class 'wifi'
    option weight '60'

config member 'lan_any'
    option detect 'auto'
    option class 'lan'
    option weight '40'
```

**Validation rules**
- Numeric options must parse and be within sane ranges; otherwise default & WARN.
- Strings normalized (lowercase), unknown values → default & WARN.
- Member sections are optional; discovery works without them.

---

## Daemon Public API (ubus)
Service name: `starfail`

### Methods & Schemas
- `starfail.status` → current state and summary
```json
{
  "state":"primary|backup|degraded",
  "current":"wan_starlink",
  "rank":[
    {"name":"wan_starlink","class":"starlink","final":88.4,"eligible":true},
    {"name":"wan_cell","class":"cellular","final":76.2,"eligible":true}
  ],
  "last_event":{"ts":"2025-08-13T12:34:56Z","type":"failover","reason":"predictive","from":"wan_starlink","to":"wan_cell"},
  "config":{"predictive":true,"use_mwan3":true,"switch_margin":10},
  "mwan3":{"enabled":true,"policy":"auto","details":"..."}
}
```

- `starfail.members` → discovered members, metrics, scores
```json
[{
  "name":"wan_starlink",
  "class":"starlink",
  "iface":"wan_starlink",
  "eligible":true,
  "score":{"instant":87.2,"ewma":89.1,"final":88.5},
  "metrics":{"lat_ms":53,"loss_pct":0.3,"jitter_ms":7,"obstruction_pct":1.4,"outages":0},
  "last_update":"2025-08-13T12:34:56Z"
}]
```

- `starfail.metrics` → recent ring buffer (downsampled if large)
```json
{"name":"wan_cell","samples":[
  {"ts":"2025-08-13T12:33:12Z","lat_ms":73,"loss_pct":1.5,"jitter_ms":8,"rsrp":-95,"rsrq":-9,"sinr":14,"instant":78.2},
  {"ts":"2025-08-13T12:33:14Z","lat_ms":69,"loss_pct":0.8,"jitter_ms":7,"rsrp":-93,"rsrq":-8,"sinr":15,"instant":80.0}
]}
```

- `starfail.history` `{ "name":"wan_starlink", "since_s":600 }` → downsampled series

- `starfail.events` `{ "limit":100 }` → recent decision/events JSON objects

- `starfail.action` → manual operations
```json
{"cmd":"failover|restore|recheck|set_level|promote","name":"optional","level":"debug|info|warn|error"}
```
**Rules**: All actions idempotent; rate-limited; log WARN on throttle.

- `starfail.config.get` → effective config (post-defaults)
- `starfail.config.set` → (optional) write via UCI + commit + hot-reload

---

## CLI
File: `/usr/sbin/starfailctl` (BusyBox `ash`)

```
starfailctl status
starfailctl members
starfailctl metrics <name>
starfailctl history <name> [since_s]
starfailctl events [limit]
starfailctl failover|restore|recheck
starfailctl setlog <debug|info|warn|error>
```

---

## Integration: mwan3 & netifd
- **Preferred**: Drive **mwan3** membership/weights/metrics for the active policy.
  - Change only what's necessary; avoid reload storms.
  - Log when no change is needed (`mwan3 unchanged` @INFO).
- **Fallback**: If `use_mwan3=0` or mwan3 missing:
  - Use `netifd`/ubus or route metrics to prefer the target member.
  - Keep existing sessions where possible; no reckless down/up.

**Constraints**
- Respect per-member `min_uptime_s` and global `cooldown_s`.
- Apply **switch_margin** (score gap) and duration windows before switching.

---

## Member Discovery & Classification
1) Parse `/etc/config/mwan3` (UCI) for interfaces, members, policies.
2) Map members → netifd iface names.
3) Classify heuristically (+ optional hints from UCI member sections):
   - **Starlink**: reaches `192.168.100.1` Starlink local API.
   - **Cellular**: netifd proto in `{qmi,mbim,ncm,ppp,cdc_ether}` or ubus mobiled.
   - **Wi‑Fi STA**: `wireless` mode `sta` bound to WAN (use ubus `iwinfo` if present).
   - **LAN uplink**: DHCP/static ethernet WAN (non-Starlink).
   - **Other**: treat generically (lat/loss only).
4) Log discovery at startup and when changed (INFO table).

Target scale: **≥ 10 members** (mwan3 supports many; plan for 16).

---

## Metric Collection (per class)
All collectors implement:
```
Collect(ctx, member) (Metrics, error)   # non-blocking, rate-controlled
```

**Common metrics (all classes)**
- **Latency/Loss** probing to targets (ICMP preferred; TCP/UDP connect timing as fallback).
- Jitter computed (e.g., MAD or stddev over last N samples).
- Probe cadence obeys `data_cap_mode` and per-class defaults.

**Starlink**
- Local API (gRPC/JSON) — **in-process**, no grpcurl/jq.
- Fields (as available): `latency_ms`, `packet_loss_pct`, `obstruction_pct`, `outages`, `pop_ping_ms`.
- Keep a **sanity ICMP** to one target at low rate.

**Cellular**
- Prefer ubus (RutOS `mobiled`/`gsm` providers) to obtain: `RSSI`, `RSRP`, `RSRQ`, `SINR`, `network_type`, `roaming`, `operator`, `band`, `cell_id`.
- If ubus unavailable, fall back to generic reachability (lat/loss), mark radio metrics `null`.
- **Metered**: lower probing rate; coalesce pings.

**Wi‑Fi (STA/tether)**
- From ubus `iwinfo` (or `/proc/net/wireless`): `signal`, `noise`, `snr`, `bitrate`.
- Latency/loss probing like common.

**LAN**
- Latency/loss probing only.

**Provider selection**
- At startup, log provider chosen per member (INFO): `provider: member=wan_cell using=rutos.mobiled`.

---

## Scoring & Predictive Logic
**Instant score** (0..100):
```
score = clamp(0,100,
    base_weight
  - w_lat * norm(lat_ms,  L_ok, L_bad)
  - w_loss* norm(loss_%,  P_ok, P_bad)
  - w_jit * norm(jitter,  J_ok, J_bad)
  - w_obs * norm(obstruct, O_ok, O_bad)        # starlink only
  - penalties(class, roaming, weak_signal, ...)
  + bonuses(class, strong_radio, ...))
)
```
- `norm(x, ok, bad)` → 0..1 mapping from good..bad thresholds.
- Defaults (tuneable via UCI):  
  - `L_ok=50ms`, `L_bad=1500ms`; `P_ok=0%`, `P_bad=10%`; `J_ok=5ms`, `J_bad=200ms`; `O_ok=0%`, `O_bad=10%`.
- **Cellular roaming** penalty when `prefer_roaming=0`.
- **Wi‑Fi weak signal** penalty below RSSI threshold.

**Rolling score**:
- **EWMA** with α≈0.2.
- **Window average** over `history_window_s` (downsampled).

**Final score**:
```
final = 0.30*instant + 0.50*ewma + 0.20*window_avg
```

**Predictive triggers** (primary only):
- Rising **loss/latency slope** over last N samples,
- **Jitter spike** above threshold,
- **Starlink**: high/accelerating obstruction or API-reported outage,
- Backup member has **final score** higher by ≥ `switch_margin` and **eligible**.

Rate-limit predictive decisions (e.g., once per `5 * fail_min_duration_s`).

---

## Decision Engine & Hysteresis
State per member: `eligible`, `cooldown`, `last_change`, `warmup`.
Global windows:
- `fail_min_duration_s`: sustained "bad" before **failover**.
- `restore_min_duration_s`: sustained "good" before **failback**.

At each tick:
1) Rank **eligible** members by **final score**; tiebreak by `weight` then class.
2) If top ≠ current:
   - Ensure `top.final - current.final ≥ switch_margin`.
   - Ensure **duration** criteria (bad/good windows) OR predictive rule satisfied.
   - Respect `cooldown_s` and `min_uptime_s`.
3) Apply change via controller (mwan3 or netifd).
4) Emit an **event** with full context.

**Idempotency**: No-ops when already in desired state.

---

## Telemetry Store (Short-Term DB)
Two RAM-backed rings under `/tmp/starfail/`:
1) **Per-member samples**: timestamp + metrics + scores (bounded N).
2) **Event log**: state changes, provider errors, throttles (JSON objects).

**Retention**
- Drop samples older than `retention_hours`.
- Cap memory usage to `max_ram_mb`; if exceeded, **downsample** old data (keep every Nth sample).

**Persistence**
- By default, nothing is written to flash.
- Provide **manual** snapshot export (compressed) via a future CLI command (not required now).

**Publish**
- Optional Prometheus **/metrics** on `127.0.0.1:9101` (guarded by UCI).
- **/healthz** (OK with build/version/uptime).

---

## Logging & Observability
- **Structured JSON** lines to syslog (stdout/stderr via procd). Optional file path if configured.
- Levels: `DEBUG`, `INFO`, `WARN`, `ERROR`.
- Include contextual fields everywhere: `member`, `iface`, `class`, `state`, `reason`, `lat_ms`, `loss_pct`, `jitter_ms`, `obstruction_pct`, `rsrp`, `rsrq`, `sinr`, `decision_id`, `bad_window_s`, `good_window_s`, `switch_margin`, `mwan3_policy`.

**Examples**
- Discovery (INFO):
```
{"ts":"...","level":"info","msg":"discovery","member":"wan_starlink","class":"starlink","iface":"wan_starlink","policy":"wan_starlink_m1","tracking":"8.8.8.8"}
```
- Sample (DEBUG):
```
{"ts":"...","level":"debug","msg":"sample","member":"wan_cell","lat_ms":73,"loss_pct":1.5,"jitter_ms":8,"rsrp":-95,"rsrq":-9,"sinr":14,"instant":78.2,"ewma":80.5,"final":79.3}
```
- Decision (INFO):
```
{"ts":"...","level":"info","msg":"switch","from":"wan_starlink","to":"wan_cell","reason":"predictive","delta":12.4,"fail_window_s":11,"cooldown_s":0}
```
- Throttle (WARN):
```
{"ts":"...","level":"warn","msg":"throttle","what":"predictive","cooldown_s":20,"remaining_s":13}
```

---

## Build, Packaging & Deployment
**Go build (example for ARMv7/RUTX)**
```bash
export CGO_ENABLED=0
GOOS=linux GOARCH=arm GOARM=7 go build -ldflags "-s -w" -o starfaild ./cmd/starfaild
strip starfaild || true
```

**OpenWrt packaging**
- Packages:
  - `starfaild` (daemon + init + UCI defaults + hotplug + ubus service file if needed)
  - `starfail-cli` (the tiny `ash` CLI)
- Provide `/openwrt/Makefile` and install scripts; depend on `ca-bundle` if HTTPS notifications are used.

**RutOS packaging**
- Build via Teltonika SDK for the target device series/firmware.
- Produce `.ipk` matching the same file layout as OpenWrt packages.
- Optionally produce **offline install** bundles.

**Runtime files**
- `/usr/sbin/starfaild` (0755) – daemon
- `/etc/init.d/starfail` (0755) – procd script
- `/usr/sbin/starfailctl` (0755) – CLI
- `/etc/config/starfail` – UCI defaults
- `/etc/hotplug.d/iface/99-starfail` – optional hotplug (poke `recheck`)

---

## Init, Hotplug & Service Control
**procd init** must set respawn and log to stdout/stderr.
```
#!/bin/sh /etc/rc.common
START=90
USE_PROCD=1
NAME=starfail
start_service() {
  procd_open_instance
  procd_set_param command /usr/sbin/starfaild -config /etc/config/starfail
  procd_set_param respawn 5000 3 0
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
```

**hotplug (optional)**
```
# /etc/hotplug.d/iface/99-starfail
[ "$ACTION" = ifup ] || [ "$ACTION" = ifdown ] || exit 0
ubus call starfail action '{"cmd":"recheck"}' >/dev/null 2>&1
```

---

## Testing Strategy & Acceptance

### **COMPREHENSIVE TESTING FRAMEWORK**

#### **Unit Tests (Required for Every Component)**
```go
// Example: Controller unit tests
func TestController_UpdateMWAN3Policy(t *testing.T) {
    tests := []struct {
        name        string
        target      *Member
        config      *MWAN3Config
        wantErr     bool
        wantWeights map[string]int
    }{
        {
            name: "successful policy update",
            target: &Member{Name: "starlink", Weight: 100},
            config: &MWAN3Config{
                Members: []*MWAN3Member{
                    {Name: "starlink", Weight: 50},
                    {Name: "cellular", Weight: 50},
                },
            },
            wantErr: false,
            wantWeights: map[string]int{
                "starlink": 100,
                "cellular": 10,
            },
        },
        {
            name: "target member not found",
            target: &Member{Name: "nonexistent", Weight: 100},
            config: &MWAN3Config{Members: []*MWAN3Member{}},
            wantErr: true,
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            ctrl := NewController(testConfig, testLogger)
            
            // Test the actual implementation
            err := ctrl.updateMWAN3Policy(tt.target)
            
            if (err != nil) != tt.wantErr {
                t.Errorf("updateMWAN3Policy() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            
            if !tt.wantErr {
                // Verify weights were actually updated
                for name, wantWeight := range tt.wantWeights {
                    if got := ctrl.getMemberWeight(name); got != wantWeight {
                        t.Errorf("member %s weight = %d, want %d", name, got, wantWeight)
                    }
                }
            }
        })
    }
}
```

#### **Integration Tests (System Component Interaction)**
```go
// Example: End-to-end failover test
func TestFailover_StarlinkToCellular(t *testing.T) {
    // Setup test environment
    testEnv := setupTestEnvironment(t)
    defer testEnv.Cleanup()
    
    // Create test members
    starlink := &Member{Name: "starlink", Class: "starlink", Iface: "wan"}
    cellular := &Member{Name: "cellular", Class: "cellular", Iface: "wwan0"}
    
    // Initialize components
    ctrl := NewController(testConfig, testLogger)
    engine := NewEngine(testConfig, testLogger, testTelemetry)
    collector := NewStarlinkCollector(testConfig)
    
    // Test data flow
    t.Run("collector to engine", func(t *testing.T) {
        metrics, err := collector.Collect(context.Background(), starlink)
        require.NoError(t, err)
        require.NotNil(t, metrics)
        
        // Verify metrics are stored in telemetry
        samples := testTelemetry.GetSamples(starlink.Name, time.Now().Add(-time.Minute))
        require.Len(t, samples, 1)
        require.Equal(t, metrics.LatencyMS, samples[0].Metrics.LatencyMS)
    })
    
    t.Run("engine decision triggers controller", func(t *testing.T) {
        // Simulate Starlink degradation
        testEnv.SimulateStarlinkDegradation()
        
        // Run decision engine
        err := engine.Tick(ctrl)
        require.NoError(t, err)
        
        // Verify controller was called with correct parameters
        require.True(t, ctrl.SwitchCalled)
        require.Equal(t, cellular.Name, ctrl.LastSwitchTarget.Name)
    })
    
    t.Run("controller actually updates mwan3", func(t *testing.T) {
        // Verify mwan3 configuration was modified
        config := testEnv.GetMWAN3Config()
        require.Equal(t, 100, config.GetMemberWeight("cellular"))
        require.Equal(t, 10, config.GetMemberWeight("starlink"))
        
        // Verify mwan3 was reloaded
        require.True(t, testEnv.MWAN3Reloaded)
    })
}
```

#### **System Integration Tests (Real Hardware)**
```bash
#!/bin/bash
# test/integration/test-failover-rutx50.sh

set -e

echo "🧪 Testing failover on RUTX50 with real Starlink..."

# Test 1: Basic failover functionality
echo "Test 1: Starlink → Cellular failover"
# Simulate Starlink obstruction
curl -s "http://192.168.100.1/api/v1/status" > /dev/null || {
    echo "❌ Starlink API not accessible"
    exit 1
}

# Monitor failover
timeout 30s bash -c '
    while true; do
        if ubus call starfail status | grep -q "cellular"; then
            echo "✅ Failover to cellular successful"
            break
        fi
        sleep 1
    done
' || {
    echo "❌ Failover did not occur within 30 seconds"
    exit 1
}

# Test 2: Failback functionality
echo "Test 2: Cellular → Starlink failback"
# Restore Starlink
# ... restore logic ...

timeout 30s bash -c '
    while true; do
        if ubus call starfail status | grep -q "starlink"; then
            echo "✅ Failback to Starlink successful"
            break
        fi
        sleep 1
    done
' || {
    echo "❌ Failback did not occur within 30 seconds"
    exit 1
}

echo "✅ All integration tests passed"
```

### **COMPREHENSIVE TEST CASES BY COMPONENT**

#### **Controller Test Cases**
```yaml
Controller Tests:
  MWAN3 Integration:
    - test_mwan3_policy_update_success
    - test_mwan3_policy_update_invalid_member
    - test_mwan3_reload_success
    - test_mwan3_reload_failure
    - test_mwan3_config_validation
    - test_mwan3_member_weight_adjustment
    - test_mwan3_policy_verification
  
  Netifd Fallback:
    - test_route_metrics_update
    - test_route_metrics_verification
    - test_netifd_interface_control
    - test_netifd_fallback_when_mwan3_unavailable
  
  Error Handling:
    - test_controller_timeout_handling
    - test_controller_retry_logic
    - test_controller_graceful_degradation
    - test_controller_error_recovery
```

#### **Collector Test Cases**
```yaml
Starlink Collector Tests:
  API Integration:
    - test_starlink_api_connection
    - test_starlink_api_timeout
    - test_starlink_api_parse_obstruction
    - test_starlink_api_parse_snr
    - test_starlink_api_parse_hardware_status
    - test_starlink_api_connection_failure
    - test_starlink_api_invalid_response
  
  Data Validation:
    - test_obstruction_data_validation
    - test_snr_data_validation
    - test_hardware_status_validation
    - test_data_quality_assessment

Cellular Collector Tests:
  Ubus Integration:
    - test_ubus_mobiled_status
    - test_ubus_gsm_status
    - test_ubus_fallback_strategies
    - test_rsrp_rsrq_sinr_parsing
    - test_roaming_detection
  
  Sysfs Fallback:
    - test_sysfs_signal_reading
    - test_sysfs_carrier_detection
    - test_signal_to_rsrp_conversion

WiFi Collector Tests:
  Iwinfo Integration:
    - test_iwinfo_signal_strength
    - test_iwinfo_snr_calculation
    - test_iwinfo_bitrate_reading
    - test_iwinfo_ssid_detection
  
  Proc Fallback:
    - test_proc_wireless_parsing
    - test_proc_wireless_interface_mapping
```

#### **Decision Engine Test Cases**
```yaml
Scoring Tests:
  - test_instant_score_calculation
  - test_ewma_score_calculation
  - test_final_score_blending
  - test_score_normalization
  - test_class_specific_scoring
  - test_penalty_bonus_application

Hysteresis Tests:
  - test_fail_window_tracking
  - test_restore_window_tracking
  - test_cooldown_enforcement
  - test_warmup_periods
  - test_switch_margin_validation

Predictive Tests:
  - test_trend_detection
  - test_obstruction_acceleration
  - test_failure_prediction
  - test_predictive_trigger_conditions
  - test_confidence_calculation
```

#### **Discovery Test Cases**
```yaml
MWAN3 Parsing:
  - test_mwan3_config_parsing
  - test_mwan3_member_mapping
  - test_mwan3_interface_classification
  - test_mwan3_policy_detection
  - test_mwan3_config_changes

Interface Classification:
  - test_starlink_detection
  - test_cellular_detection
  - test_wifi_detection
  - test_lan_detection
  - test_unknown_interface_handling
```

#### **ubus Server Test Cases**
```yaml
Protocol Tests:
  - test_socket_connection
  - test_message_serialization
  - test_method_registration
  - test_rpc_call_handling
  - test_error_response_formatting

CLI Fallback Tests:
  - test_cli_wrapper_functionality
  - test_cli_error_handling
  - test_cli_timeout_handling
  - test_cli_response_parsing

Method Tests:
  - test_status_method
  - test_members_method
  - test_telemetry_method
  - test_failover_method
  - test_restore_method
  - test_recheck_method
```

### **PERFORMANCE TEST CASES**
```yaml
Load Tests:
  - test_10_members_concurrent_collection
  - test_high_frequency_decision_cycles
  - test_memory_usage_under_load
  - test_cpu_usage_under_load
  - test_network_io_under_load

Stress Tests:
  - test_rapid_interface_flapping
  - test_concurrent_failover_requests
  - test_system_under_memory_pressure
  - test_system_under_cpu_pressure
  - test_network_partition_scenarios
```

### **FAILURE MODE TEST CASES**
```yaml
System Failures:
  - test_starlink_api_unavailable
  - test_ubus_daemon_unavailable
  - test_mwan3_not_installed
  - test_disk_space_exhaustion
  - test_memory_exhaustion

Network Failures:
  - test_interface_down_scenarios
  - test_route_table_corruption
  - test_dns_resolution_failure
  - test_gateway_unreachable
  - test_partial_connectivity

Recovery Tests:
  - test_automatic_recovery_from_failures
  - test_manual_intervention_scenarios
  - test_configuration_restoration
  - test_service_restart_capability
```

### **ACCEPTANCE CRITERIA**

#### **Functional Requirements**
- [ ] Auto-discovers & classifies members reliably (100% accuracy)
- [ ] Makes correct (and stable) predictive failovers/failbacks
- [ ] Exposes ubus API and CLI works as specified
- [ ] Telemetry retained within RAM caps and time window
- [ ] Meets CPU/RAM targets; no busy loops
- [ ] Degrades gracefully when providers are missing

#### **Performance Requirements**
- [ ] Complete failover in <5 seconds
- [ ] Respond to ubus calls in <1 second
- [ ] Collect metrics in <2 seconds
- [ ] Make decisions in <1 second
- [ ] Handle 10+ concurrent members
- [ ] Memory usage <25MB steady state

#### **Reliability Requirements**
- [ ] 99.9% uptime (8.76 hours downtime/year)
- [ ] Zero data loss during failover
- [ ] Automatic recovery from all failure modes
- [ ] No memory leaks over 30-day period
- [ ] Graceful handling of all error conditions

### **TEST EXECUTION FRAMEWORK**

#### **Automated Test Suite**
```bash
#!/bin/bash
# scripts/run-tests.sh

echo "🧪 Running comprehensive test suite..."

# Unit tests
echo "Running unit tests..."
go test ./pkg/... -v -race -cover

# Integration tests
echo "Running integration tests..."
go test ./test/integration/... -v

# System tests (if hardware available)
if [ -f "/etc/config/mwan3" ]; then
    echo "Running system tests..."
    ./test/integration/test-failover-rutx50.sh
else
    echo "⚠️  Skipping system tests (no hardware available)"
fi

# Performance tests
echo "Running performance tests..."
go test ./test/performance/... -v

echo "✅ All tests completed"
```

#### **Continuous Integration**
```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.22'
      
      - name: Run unit tests
        run: go test ./pkg/... -v -race -cover
      
      - name: Run integration tests
        run: go test ./test/integration/... -v
      
      - name: Generate coverage report
        run: go test ./pkg/... -coverprofile=coverage.out
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.out
```

### **TEST DATA MANAGEMENT**

#### **Mock Data Sets**
```go
// test/data/mock_starlink_response.json
{
  "status": {
    "obstructionStats": {
      "currentlyObstructed": false,
      "fractionObstructed": 0.004166088,
      "last24hObstructedS": 0,
      "wedgeFractionObstructed": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    },
    "outage": {
      "lastOutageS": 0
    },
    "popPingLatencyMs": 53.2
  }
}

// test/data/mock_ubus_mobiled.json
{
  "rsrp": -95,
  "rsrq": -9,
  "sinr": 14,
  "network_type": "LTE",
  "roaming": false,
  "operator": "Test Operator",
  "band": "B3",
  "cell_id": "12345"
}
```

#### **Test Environment Setup**
```go
// test/setup/environment.go
type TestEnvironment struct {
    MWAN3Config     *MWAN3Config
    UbusResponses   map[string]interface{}
    StarlinkAPI     *MockStarlinkAPI
    NetworkState    *MockNetworkState
    FileSystem      *MockFileSystem
}

func SetupTestEnvironment(t *testing.T) *TestEnvironment {
    env := &TestEnvironment{
        MWAN3Config:   createTestMWAN3Config(),
        UbusResponses: loadMockUbusResponses(),
        StarlinkAPI:   NewMockStarlinkAPI(),
        NetworkState:  NewMockNetworkState(),
        FileSystem:    NewMockFileSystem(),
    }
    
    // Setup test data
    env.setupTestData()
    
    return env
}
```

### **TEST REPORTING**

#### **Test Results Format**
```json
{
  "test_suite": "starfail_integration",
  "timestamp": "2025-01-14T12:00:00Z",
  "duration": "45.2s",
  "results": {
    "total_tests": 156,
    "passed": 152,
    "failed": 4,
    "skipped": 0,
    "coverage": 87.3
  },
  "performance": {
    "avg_failover_time": "3.2s",
    "avg_decision_time": "0.8s",
    "memory_usage": "18.5MB",
    "cpu_usage": "2.3%"
  },
  "failures": [
    {
      "test": "TestFailover_RapidFlapping",
      "error": "failover occurred too quickly (1.2s < 2s minimum)",
      "component": "decision_engine"
    }
  ]
}
```

**This comprehensive testing framework ensures every component is thoroughly validated before being marked as complete.**

---

## Performance Targets
- Binary ≤ 12 MB stripped
- RSS ≤ 25 MB steady
- Tick ≤ 5% CPU on low-end ARM when healthy
- Probing minimal on metered links; measurable reduction in **conservative** mode

---

## Security & Privacy
- Daemon runs as root (network control) – minimize exposed surfaces.
- Bind metrics/health endpoints to **127.0.0.1** only.
- Store secrets (Pushover, MQTT creds) only in UCI; never log them.
- CLI and ubus methods are local-admin only (default OpenWrt/RutOS model).

---

## Failure Modes & Safe Behavior
- **Starlink API down**: mark API fields null; rely on reachability; WARN, don't crash.
- **ubus/mwan3 missing**: fall back to netifd (or no-op decisions) with clear WARN.
- **ICMP blocked**: use TCP/UDP connect timing as fallback.
- **Config missing/invalid**: default and WARN; keep operating.
- **Provider errors**: exponential backoff; surface in events; do not block main loop.
- **Memory pressure**: downsample telemetry; trim rings; WARN.

---

## Future UI (LuCI/Vuci) – for later
- UI talks to the same **ubus** methods and reads/writes **UCI**.
- Two thin UIs: `luci-app-starfail` (OpenWrt) and a Vuci module (RutOS).
- No daemon changes required to add UI later.

---

## Coding Style & Quality

### **CRITICAL: NO PLACEHOLDERS ALLOWED**
This is **production-critical network infrastructure** - users depend on it for internet connectivity. Every component must be fully functional with no room for placeholders or incomplete implementations.

### **IMPLEMENTATION REQUIREMENTS**

#### **1. COMPLETE FUNCTIONALITY MANDATE**
- **NEVER** use TODO comments as implementation
- **NEVER** return placeholder values or empty stubs  
- **NEVER** log "would do X" without actually doing X
- **ALWAYS** implement the complete feature as specified
- **ALWAYS** test your implementation logic thoroughly

#### **2. SYSTEM INTEGRATION REQUIREMENTS**
- **ALWAYS** connect components properly (no orphaned code)
- **ALWAYS** implement error handling for all failure modes
- **ALWAYS** ensure components can communicate with each other
- **ALWAYS** verify that data flows through the entire system

#### **3. REAL SYSTEM INTERACTION**
- **ALWAYS** implement actual system calls (not just logging)
- **ALWAYS** handle real file I/O, network calls, and process execution
- **ALWAYS** implement proper timeout and retry logic
- **ALWAYS** validate system responses and handle errors

### **SPECIFIC CODING STANDARDS**

#### **For Go Code:**
```go
// ❌ WRONG - Placeholder implementation
func updateMWAN3Policy(target *Member) error {
    logger.Info("Would update mwan3 policy", "target", target.Name)
    return nil // TODO: implement actual policy update
}

// ✅ CORRECT - Complete implementation
func updateMWAN3Policy(target *Member) error {
    // Read current mwan3 config
    config, err := readMWAN3Config()
    if err != nil {
        return fmt.Errorf("failed to read mwan3 config: %w", err)
    }
    
    // Update member weights to prefer target
    for _, member := range config.Members {
        if member.Name == target.Name {
            member.Weight = 100
        } else {
            member.Weight = 10
        }
    }
    
    // Write updated config
    if err := writeMWAN3Config(config); err != nil {
        return fmt.Errorf("failed to write mwan3 config: %w", err)
    }
    
    // Reload mwan3
    if err := reloadMWAN3(); err != nil {
        return fmt.Errorf("failed to reload mwan3: %w", err)
    }
    
    logger.Info("Successfully updated mwan3 policy", "target", target.Name)
    return nil
}
```

#### **For System Integration:**
```go
// ❌ WRONG - CLI fallback only
func getCellularMetrics(member *Member) (*Metrics, error) {
    // Try ubus, fall back to CLI
    if data, err := ubusCall("mobiled", "status"); err == nil {
        return parseCellularData(data)
    }
    return nil, fmt.Errorf("cellular metrics unavailable")
}

// ✅ CORRECT - Multiple fallback strategies
func getCellularMetrics(member *Member) (*Metrics, error) {
    // Strategy 1: Native ubus socket
    if data, err := ubusSocketCall("mobiled", "status"); err == nil {
        return parseCellularData(data)
    }
    
    // Strategy 2: ubus CLI
    if data, err := ubusCLICall("mobiled", "status"); err == nil {
        return parseCellularData(data)
    }
    
    // Strategy 3: Direct sysfs reading
    if metrics, err := readCellularSysfs(member.Iface); err == nil {
        return metrics, nil
    }
    
    // Strategy 4: Generic interface metrics
    return getGenericInterfaceMetrics(member)
}
```

### **TASK COMPLETION CHECKLIST**

Before marking any task as complete, verify:

#### **✅ IMPLEMENTATION COMPLETE**
- [ ] All functions have actual implementation (no TODO comments)
- [ ] All error conditions are handled
- [ ] All return values are meaningful
- [ ] All logging shows actual actions taken
- [ ] All system calls are implemented

#### **✅ INTEGRATION COMPLETE**
- [ ] Component is properly initialized in main()
- [ ] Component receives required dependencies
- [ ] Component can communicate with other components
- [ ] Data flows through the entire system
- [ ] No orphaned or unused code

#### **✅ TESTING COMPLETE**
- [ ] Logic handles all expected inputs
- [ ] Error conditions are properly handled
- [ ] Timeouts and retries are implemented
- [ ] System integration points work
- [ ] Performance is acceptable

### **SPECIFIC COMPONENT REQUIREMENTS**

#### **Controller (pkg/controller/controller.go)**
- **MUST** actually modify mwan3 configuration files
- **MUST** execute mwan3 reload commands
- **MUST** update route metrics for netifd fallback
- **MUST** verify changes were applied successfully
- **MUST** handle all error conditions

#### **Discovery (pkg/discovery/discovery.go)**
- **MUST** parse /etc/config/mwan3 completely
- **MUST** map mwan3 members to netifd interfaces
- **MUST** classify members by type (Starlink/Cellular/WiFi/LAN)
- **MUST** detect interface status changes
- **MUST** handle configuration reloads

#### **Collectors (pkg/collector/)**
- **MUST** implement multiple fallback strategies
- **MUST** handle all error conditions gracefully
- **MUST** parse all available metrics
- **MUST** validate data quality
- **MUST** implement proper timeouts

#### **Decision Engine (pkg/decision/)**
- **MUST** connect to predictive engine
- **MUST** implement actual trend detection
- **MUST** trigger real failover actions
- **MUST** log complete decision reasoning
- **MUST** handle all edge cases

#### **ubus Server (pkg/ubus/)**
- **MUST** implement complete socket protocol OR reliable CLI wrapper
- **MUST** handle all RPC methods
- **MUST** validate all inputs
- **MUST** return meaningful responses
- **MUST** handle connection errors

### **QUALITY ASSURANCE REQUIREMENTS**

#### **Code Review Checklist:**
- [ ] No TODO comments remain
- [ ] No placeholder return values
- [ ] No "would do X" logging without actual implementation
- [ ] All error paths are handled
- [ ] All system calls are implemented
- [ ] Components are properly connected
- [ ] Data flows through the system
- [ ] Performance is acceptable

#### **Testing Requirements:**
- [ ] Test with real hardware (RUTX50/RUTX11)
- [ ] Test all error conditions
- [ ] Test system integration points
- [ ] Test performance under load
- [ ] Test recovery from failures

### **PERFORMANCE REQUIREMENTS**

#### **Resource Usage:**
- **MUST** use minimal CPU and memory
- **MUST** avoid blocking operations
- **MUST** implement proper timeouts
- **MUST** handle high-frequency operations
- **MUST** scale to 10+ network interfaces

#### **Response Times:**
- **MUST** complete failover in <5 seconds
- **MUST** respond to ubus calls in <1 second
- **MUST** collect metrics in <2 seconds
- **MUST** make decisions in <1 second
- **MUST** handle concurrent operations

### **FAILURE MODE HANDLING**

#### **System Failures:**
- **ALWAYS** implement graceful degradation
- **ALWAYS** provide fallback mechanisms
- **ALWAYS** log detailed error information
- **ALWAYS** attempt recovery when possible
- **NEVER** crash or leave system in bad state

#### **Integration Failures:**
- **ALWAYS** handle missing dependencies
- **ALWAYS** provide alternative data sources
- **ALWAYS** maintain system functionality
- **ALWAYS** log integration issues clearly
- **NEVER** assume components will always be available

### **COMMUNICATION REQUIREMENTS**

#### **When Reporting Progress:**
- **ALWAYS** specify exactly what was implemented
- **ALWAYS** mention any limitations or assumptions
- **ALWAYS** describe how components are connected
- **ALWAYS** mention testing performed
- **NEVER** say "implemented" if only structure exists

#### **Example Progress Report:**
```
✅ COMPLETED: Starlink collector with full API integration
- Implemented HTTP client with timeout and retry logic
- Parses complete API response (obstruction, SNR, pop ping, hardware status)
- Handles API timeouts and connection errors
- Validates data quality before returning metrics
- Connected to main loop via collector factory
- Tested with real Starlink dish (API calls successful)
```

### **FINAL VERIFICATION**

Before considering any task complete:

1. **Read the code** - Does it actually do what it claims?
2. **Trace the execution** - Does data flow through the system?
3. **Check integration** - Are components properly connected?
4. **Verify error handling** - Are all failure modes covered?
5. **Test the logic** - Does it work with real inputs?
6. **Check performance** - Is it efficient enough?
7. **Verify completeness** - Is anything missing?

### **REMEMBER:**
- **This is production-critical infrastructure**
- **Users depend on this for internet connectivity**
- **There is no room for incomplete implementations**
- **Every component must work reliably**
- **Quality and completeness are non-negotiable**

**If you cannot implement a feature completely, say so clearly and explain what is missing. Do not pretend it is complete when it is not.**

### **Basic Go Standards:**
- Go 1.22+, modules enabled; CGO disabled.
- No panics on bad input; always validate/default and log at WARN.
- Interfaces for collectors/controllers; small test doubles.
- Config reload via `SIGHUP` or ubus `config.set` → atomic apply and diff log.
- No busy waits; timers via `time.Ticker`; contexts with deadlines everywhere.
- Avoid third-party deps unless absolutely necessary (MQTT may require a small client).

---

## Appendix: Examples & Snippets

### Example: Default UCI
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    option poll_interval_ms '1500'
    option history_window_s '600'
    option retention_hours '24'
    option max_ram_mb '16'
    option data_cap_mode 'balanced'
    option predictive '1'
    option switch_margin '10'
    option min_uptime_s '20'
    option cooldown_s '20'
    option metrics_listener '0'
    option health_listener '1'
    option log_level 'info'
    option log_file ''

    option fail_threshold_loss '5'
    option fail_threshold_latency '1200'
    option fail_min_duration_s '10'
    option restore_threshold_loss '1'
    option restore_threshold_latency '800'
    option restore_min_duration_s '30'
```

### Example: Member overrides (SIMs, Wi‑Fi, LAN)
```uci
config member 'starlink_any'
    option detect 'auto'
    option class 'starlink'
    option weight '100'
    option min_uptime_s '30'
    option cooldown_s '20'

config member 'sim_pool'
    option detect 'auto'
    option class 'cellular'
    option weight '80'
    option prefer_roaming '0'
    option metered '1'

config member 'wifi_any'
    option detect 'auto'
    option class 'wifi'
    option weight '60'

config member 'lan_any'
    option detect 'auto'
    option class 'lan'
    option weight '40'
```

### Example: CLI helper (`/usr/sbin/starfailctl`)
```sh
#!/bin/sh
case "$1" in
  status)   ubus call starfail status ;;
  members)  ubus call starfail members ;;
  metrics)  ubus call starfail metrics "{"name":"$2"}" ;;
  history)  ubus call starfail history "{"name":"$2","since_s":${3:-600}}" ;;
  events)   ubus call starfail events "{"limit":${2:-100}}" ;;
  failover) ubus call starfail action '{"cmd":"failover"}' ;;
  restore)  ubus call starfail action '{"cmd":"restore"}' ;;
  recheck)  ubus call starfail action '{"cmd":"recheck"}' ;;
  setlog)   ubus call starfail action "{"cmd":"set_level","level":"$2"}" ;;
  *) echo "Usage: starfailctl {status|members|metrics <name>|history <name> [since_s]|events [limit]|failover|restore|recheck|setlog <level>}"; exit 1 ;;
esac
```

### Example: procd init (`/etc/init.d/starfail`)
```sh
#!/bin/sh /etc/rc.common
START=90
USE_PROCD=1
NAME=starfail

start_service() {
  procd_open_instance
  procd_set_param command /usr/sbin/starfaild -config /etc/config/starfail
  procd_set_param respawn 5000 3 0
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
```

### Example: hotplug (`/etc/hotplug.d/iface/99-starfail`)
```sh
[ "$ACTION" = ifup ] || [ "$ACTION" = ifdown ] || exit 0
ubus call starfail action '{"cmd":"recheck"}' >/dev/null 2>&1
```

### Example: Decision Engine Pseudocode
```go
tick := time.NewTicker(cfg.PollInterval)
for {
  select {
  case <-tick.C:
    members := discover()
    for m := range members {
      metrics[m] = collectors[m.class].Collect(ctx, m)
      score[m] = scorer.Update(m, metrics[m])
    }
    top := rank(scores, eligible(members))
    if shouldSwitch(current, top, scores, windows, cfg) {
      controller.Switch(current, top)
      events.Add(SwitchEvent{...})
      current = top
    }
  case <-reload:
    cfg = loadConfig()
  }
}
```

---

**End of Specification**

### **PROJECT INSTRUCTION.md MAINTENANCE REQUIREMENTS**

#### **MANDATORY PROGRESS TRACKING**
This PROJECT_INSTRUCTION.md file **MUST** be kept up-to-date with accurate progress information. It serves as the single source of truth for all development work.

#### **UPDATE REQUIREMENTS**
- **ALWAYS** update implementation status when completing tasks
- **ALWAYS** move items between status categories (✅ COMPLETED, ⚡ PARTIALLY IMPLEMENTED, 🔧 STUB/PLACEHOLDER, 🚫 NOT IMPLEMENTED)
- **ALWAYS** update progress metrics with realistic percentages
- **ALWAYS** add new critical issues as they are discovered
- **ALWAYS** update the detailed TODO list as tasks are completed
- **ALWAYS** document any deviations from the original specification

#### **PROGRESS UPDATE FORMAT**
When updating progress, use this format:

```markdown
### ✅ COMPLETED (Component Name)
- [x] **Feature Name** - Brief description of what was actually implemented
  - ✅ Specific functionality that works
  - ✅ Integration points that are connected
  - ✅ Testing that was performed
  - ⚠️ Any limitations or assumptions made

### ⚡ PARTIALLY IMPLEMENTED (Component Name)
- [⚠️] **Feature Name** - What works vs what's missing
  - ✅ Working functionality
  - ❌ Missing functionality
  - 🔄 In-progress work
  - ⚠️ Known limitations
```

#### **ACCURACY REQUIREMENTS**
- **NEVER** mark something as complete unless it's fully functional
- **NEVER** use placeholder percentages (must be based on actual work)
- **ALWAYS** verify functionality before updating status
- **ALWAYS** include testing status in progress updates
- **ALWAYS** note any dependencies or blockers

#### **REVIEW REQUIREMENTS**
- **Weekly reviews** of implementation status accuracy
- **Before each release** - verify all completed items are actually functional
- **After major changes** - update affected sections immediately
- **When discovering issues** - update critical issues section
- **When adding features** - update version 2.0 ideas section

#### **DOCUMENTATION STANDARDS**
- **ALWAYS** use consistent formatting and terminology
- **ALWAYS** include specific file paths and function names
- **ALWAYS** reference actual code implementations
- **ALWAYS** include testing evidence for completed items
- **ALWAYS** note any deviations from original specification

#### **VERSION CONTROL**
- **ALWAYS** commit PROJECT_INSTRUCTION.md changes with implementation
- **ALWAYS** include progress updates in commit messages
- **ALWAYS** review changes before merging to main branch
- **ALWAYS** maintain change history for major updates

**This file is the authoritative reference for all development work. Keep it accurate and up-to-date at all times.**

