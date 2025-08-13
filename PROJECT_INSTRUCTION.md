# PROJECT_INSTRUCTION.md
**Starfail – Go Core (RutOS/OpenWrt) – Full Engineering Specification**

> This is the authoritative, version-controlled specification for the Go-based
> multi-interface failover daemon intended to replace the legacy Bash solution.
> It merges the complete initial plan and the multi-interface/scoring/telemetry
> addendum. Treat this document as the single source of truth for Codex/Copilot
> and human contributors. All major design decisions must be reflected here.

## Implementation Progress Status
**Started**: 2025-01-17 - Moving from Bash to Go implementation
**Updated**: 2025-08-13 - Enhanced feature set and production requirements

### Core Foundation ✅ COMPLETE
- ✅ Repository restructure and Go project setup
- ✅ Basic project structure (`cmd/starfaild/`, `pkg/` packages, `scripts/`, etc.)
- ✅ Core interfaces and type definitions (collector.Collector, decision.Engine, etc.)
- ✅ Basic UCI config structures with validation framework
- ✅ Structured JSON logging with levels and cross-platform syslog integration
- ✅ UCI config loader with uci command integration and validation
- ✅ Enhanced logging with contextual fields and platform-specific syslog support
- ✅ Starlink collector implementation with JSON API support
- ✅ Cellular collector with ubus mobiled/GSM integration  
- ✅ WiFi collector with ubus iwinfo/iwconfig support
- ✅ LAN/Generic ping-based collector with interface binding

### Core Functionality 🔄 IN PROGRESS
- 🔄 Decision engine with EWMA scoring and hysteresis
- 🔄 mwan3 integration and controllers
- 🔄 ubus API server with complete method implementation
- 🔄 CLI implementation (starfailctl)
- 🔄 Telemetry store with RAM-backed ring buffers

### Advanced Features 📋 PLANNED
- 📋 **System Health Monitoring & Auto-Recovery** (starfail-sysmgmt)
  - Overlay space management and log cleanup
  - Service watchdog for hung processes
  - Log flood detection and prevention
  - NTP sync monitoring and time drift correction
  - Network interface stabilization
- 📋 **Enhanced Starlink Diagnostics**
  - Hardware self-test and thermal monitoring
  - Bandwidth restrictions and uptime tracking
  - Predictive reboot detection and preemptive failover
  - Pending update monitoring
- 📋 **Location-Aware Intelligence**
  - Multi-source GPS data collection (RUTOS > Starlink priority)
  - Movement detection (>500m triggers obstruction map reset)
  - Location clustering for pattern analysis
  - Location-based threshold adjustments
- 📋 **Comprehensive Decision Audit Trail**
  - Structured decision reasoning logs
  - Quality factor breakdown with scoring transparency
  - Real-time decision viewer and historical pattern analysis
  - Root cause analysis with automated recommendations
- 📋 **Advanced Notification Systems**
  - Smart notification management with rate limiting
  - Contextual alerts with priority levels and cooldown
  - Emergency notifications with retry and acknowledgment
- 📋 **Predictive Obstruction Management**
  - Obstruction acceleration detection for early warning
  - SNR trend analysis and movement-triggered map refresh
  - Multi-factor obstruction assessment with false positive reduction
  - Data quality validation using patchesValid and validS
- 📋 **Adaptive Sampling**
  - Dynamic sampling rates (1s unlimited, 60s metered)
  - Connection-type aware probing strategies
- 📋 **Backup and Recovery**
  - Automated recovery after firmware upgrades
  - Configuration preservation and restoration

**Note**: Development machine (Windows) has antivirus blocking Go compilation, but code structure is designed for target RutOS/OpenWrt Linux platform with proper cross-platform support.

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
17. [System Health Monitoring & Auto-Recovery](#system-health-monitoring--auto-recovery)
18. [Enhanced Starlink Diagnostics](#enhanced-starlink-diagnostics)
19. [Location-Aware Intelligence](#location-aware-intelligence)
20. [Comprehensive Decision Audit Trail](#comprehensive-decision-audit-trail)
21. [Advanced Notification Systems](#advanced-notification-systems)
22. [Predictive Obstruction Management](#predictive-obstruction-management)
23. [Adaptive Sampling](#adaptive-sampling)
24. [Backup and Recovery](#backup-and-recovery)
25. [Build, Packaging & Deployment](#build-packaging--deployment)
26. [Init, Hotplug & Service Control](#init-hotplug--service-control)
27. [Testing Strategy & Acceptance](#testing-strategy--acceptance)
28. [Performance Targets](#performance-targets)
29. [Security & Privacy](#security--privacy)
30. [Failure Modes & Safe Behavior](#failure-modes--safe-behavior)
31. [Future UI (LuCI/Vuci) – for later](#future-ui-lucivuci--for-later)
32. [Coding Style & Quality](#coding-style--quality)
33. [Appendix: Examples & Snippets](#appendix-examples--snippets)

---

## Overview & Problem Statement
We need a reliable, autonomous, and resource-efficient system on **RutOS** and **OpenWrt**
routers to manage **multi-interface failover** (e.g., Starlink, cellular with multiple SIMs,
Wi‑Fi STA/tethering, LAN uplinks), with **predictive** behavior so users _don’t notice_
degradation/outages. The legacy Bash approach created too much process churn, had BusyBox
limitations, and was harder to maintain and extend.

**Solution**: a **single Go daemon** (`starfaild`) that:
- Discovers all **mwan3** members and their underlying netifd interfaces
- Collects **metrics** per member (Starlink API, radio quality, latency/loss, etc.)
- Computes **health scores** (instant + rolling) and performs **predictive failover/failback**
- Integrates natively with **UCI**, **ubus**, **procd**, and **mwan3**
- Exposes a small **CLI** for operational control and deep **DEBUG** logging
- Stores short-term telemetry in **RAM** (no flash wear by default)

No Web UI is required in this phase; we’ll add LuCI/Vuci later to the same ubus/UCI API.

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
- Replacing mwan3 entirely (we **drive** it; we don’t reinvent it).
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
  - Change only what’s necessary; avoid reload storms.
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
- `fail_min_duration_s`: sustained “bad” before **failover**.
- `restore_min_duration_s`: sustained “good” before **failback**.

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

## System Health Monitoring & Auto-Recovery
**Separate Go application**: `cmd/starfail-sysmgmt/` for cron-based system maintenance.

### Core Functionality
- **Overlay Space Management**: Monitor and cleanup `/overlay`, `/tmp`, `/var/log`
  - Remove stale files older than configurable thresholds
  - Compress/rotate large log files automatically
  - Emergency cleanup when storage <10% free
- **Service Watchdog**: Monitor critical services and restart if hung
  - `nlbwmon`, `mdcollectd`, `mobiled`, `hostapd`, `mwan3`
  - Process health checks via PID monitoring and responsiveness tests
  - Graceful restart with backoff on repeated failures
- **Log Flood Detection**: Prevent services from filling storage
  - Monitor log growth rates and implement flood protection
  - Rate limit `hostapd` and `kernel` message floods
  - Automatic logrotate acceleration during floods
- **Time Drift Correction**: NTP sync monitoring and correction
  - Detect time drift >30s and force NTP sync
  - Monitor NTP daemon health and restart if needed
  - GPS time fallback for offline environments
- **Network Interface Stabilization**: Detect and fix flapping interfaces
  - Monitor interface up/down cycles and implement dampening
  - Reset stuck interfaces with proper state restoration
  - Coordinate with starfaild to prevent conflicts

### Configuration
```uci
config starfail-sysmgmt 'main'
    option enable '1'
    option overlay_cleanup_days '7'
    option log_cleanup_days '3'
    option service_check_interval '300'
    option time_drift_threshold '30'
    option interface_flap_threshold '5'
```

### Cron Integration
```bash
# /etc/crontabs/root
*/5 * * * * /usr/sbin/starfail-sysmgmt --quick-check
0 */6 * * * /usr/sbin/starfail-sysmgmt --full-maintenance
```

---

## Enhanced Starlink Diagnostics
**Extended Starlink API integration** for comprehensive hardware monitoring.

### Hardware Health Monitoring
- **Self-test Results**: Monitor hardware self-test status and results
- **Thermal Management**: Track dish and power supply temperatures
  - Thermal throttling detection and preemptive failover
  - Overheat warnings with automatic protective measures
- **Power Supply Health**: Monitor power consumption and voltage stability
- **Dish Alignment**: Track pointing accuracy and motor health

### Bandwidth and Performance
- **Bandwidth Restrictions**: Detect Fair Access Policy limitations
- **Service Degradation**: Monitor plan limits and throttling
- **Uptime Tracking**: Detailed uptime/downtime statistics
- **Performance Trending**: Historical throughput and latency analysis

### Predictive Maintenance
- **Pending Updates**: Detect scheduled firmware updates
  - Trigger preemptive failover before automatic reboots
  - Monitor update progress and estimate completion time
- **Scheduled Reboots**: API-reported maintenance windows
  - Automatic failover 5 minutes before scheduled reboot
  - Post-reboot connectivity validation and failback

### Extended API Fields
```go
type StarlinkExtended struct {
    // Hardware
    ThermalThrottled    bool    `json:"thermal_throttled"`
    DishTempC          float64 `json:"dish_temp_c"`
    PSUTempC           float64 `json:"psu_temp_c"`
    PowerDrawW         float64 `json:"power_draw_w"`
    
    // Performance
    FairUsageExceeded  bool    `json:"fair_usage_exceeded"`
    PlanDataLimitPct   float64 `json:"plan_data_limit_pct"`
    ExpectedBandwidthMbps float64 `json:"expected_bandwidth_mbps"`
    
    // Maintenance
    PendingUpdate      bool    `json:"pending_update"`
    ScheduledRebootAt  *time.Time `json:"scheduled_reboot_at"`
    LastUpdateAt       time.Time `json:"last_update_at"`
}
```

---

## Location-Aware Intelligence
**Multi-source GPS integration** for location-aware decision making.

### GPS Data Sources (Priority Order)
1. **RUTOS GPS**: Primary source via ubus `gps.info`
2. **Starlink GPS**: Secondary source from dish API
3. **Manual Configuration**: Fallback static coordinates

### Movement Detection
- **Distance Threshold**: Movement >500m triggers obstruction map reset
- **Speed Calculation**: Detect stationary vs mobile deployment
- **Location Clustering**: Identify problematic vs equipment-related issues
  - Poor performance at specific coordinates = environmental
  - Poor performance across locations = equipment issue

### Location-Based Adaptations
- **Threshold Adjustments**: Modify scoring based on known difficult areas
- **Historical Performance**: Location-specific performance baselines
- **Environmental Factors**: Terrain, weather, and obstruction correlation
- **Obstruction Map Management**: Auto-refresh when location changes

### Implementation
```go
type LocationManager struct {
    Current    GPSCoordinate
    Previous   GPSCoordinate
    Movement   MovementState
    Clusters   []LocationCluster
}

type LocationCluster struct {
    Center       GPSCoordinate
    Radius       float64
    Observations []PerformanceObservation
    QualityScore float64
}
```

---

## Comprehensive Decision Audit Trail
**Structured decision reasoning** for troubleshooting and transparency.

### Decision Context Logging
- **Quality Factor Breakdown**: Detailed scoring components
  ```json
  {
    "decision_id": "d_2025081312345",
    "timestamp": "2025-08-13T12:34:56Z",
    "action": "failover",
    "from": "wan_starlink", 
    "to": "wan_cell",
    "reason": "predictive_obstruction",
    "quality_factors": {
      "wan_starlink": {"latency": 1, "loss": 0, "obstruction": 1, "snr": 0, "final": 45.2},
      "wan_cell": {"latency": 0, "loss": 0, "rsrp": 1, "rsrq": 1, "final": 78.3}
    },
    "thresholds": {"switch_margin": 10, "min_duration": 10},
    "windows": {"bad_duration_s": 15, "good_duration_s": 0}
  }
  ```

### Real-Time Decision Viewer
- **Live Decision Stream**: ubus method for real-time decision monitoring
- **Decision Replay**: Historical decision reconstruction with full context
- **What-If Analysis**: Simulate decisions with different thresholds

### Pattern Analysis
- **Trend Identification**: Automated pattern recognition in decision history
- **Recommendation Engine**: Suggest threshold adjustments based on patterns
- **Root Cause Analysis**: Automated troubleshooting with pattern matching
  - Frequent failovers = threshold too sensitive
  - Delayed failovers = thresholds too conservative
  - Location-specific patterns = environmental issues

### Audit Storage
```go
type DecisionAudit struct {
    ID              string                 `json:"decision_id"`
    Timestamp       time.Time              `json:"timestamp"`
    Action          string                 `json:"action"`
    From            string                 `json:"from"`
    To              string                 `json:"to"`
    Reason          string                 `json:"reason"`
    QualityFactors  map[string]ScoreBreakdown `json:"quality_factors"`
    Context         DecisionContext        `json:"context"`
    Outcome         DecisionOutcome        `json:"outcome"`
}
```

---

## Advanced Notification Systems
**Intelligent notification management** with context-aware alerting.

### Smart Rate Limiting
- **Priority Levels**: Emergency > Critical > Warning > Info
- **Cooldown Periods**: Prevent notification spam
  - Emergency: No cooldown (immediate retry)
  - Critical: 5-minute cooldown
  - Warning: 1-hour cooldown
  - Info: 6-hour cooldown
- **Acknowledgment System**: Mark notifications as acknowledged to reduce noise

### Contextual Alerts
- **Notification Types**:
  - **Fix Notifications**: Problem automatically resolved
  - **Failure Notifications**: Require human intervention
  - **Critical Notifications**: Emergency situations (all links down)
  - **Status Notifications**: Regular health updates
- **Rich Context**: Include current status, attempted fixes, and next steps

### Emergency Priority System
- **Escalation**: Retry critical notifications with increasing urgency
- **Multiple Channels**: Pushover, MQTT, email, webhook
- **Fallback Methods**: If primary channel fails, try alternatives
- **Time-Based Escalation**: Increase priority if not acknowledged

### Implementation
```go
type NotificationManager struct {
    Channels    []NotificationChannel
    RateLimiter map[string]time.Time
    Priorities  map[string]Priority
}

type Notification struct {
    ID       string    `json:"id"`
    Priority Priority  `json:"priority"`
    Type     string    `json:"type"`
    Message  string    `json:"message"`
    Context  Context   `json:"context"`
    Retry    RetryPolicy `json:"retry"`
}
```

---

## Predictive Obstruction Management
**Proactive failover** before signal loss impacts users.

### Advanced Obstruction Detection
- **Acceleration Detection**: Rapid obstruction percentage increases
  - Rate of change >2%/minute triggers early warning
  - Sustained acceleration >5%/minute triggers preemptive failover
- **SNR Trend Analysis**: Signal-to-noise ratio degradation patterns
  - SNR dropping >3dB/minute indicates incoming obstruction
  - Combined with obstruction percentage for accurate prediction

### Multi-Factor Assessment
- **Current Obstruction**: Real-time obstruction percentage
- **Historical Impact**: `timeObstructed` and `avgProlongedObstructionIntervalS`
- **Duration Analysis**: Distinguish temporary vs persistent obstructions
- **Environmental Correlation**: Weather, time of day, seasonal patterns

### False Positive Reduction
- **Data Quality Validation**: Use `patchesValid` and `validS` fields
- **Minimum Thresholds**: Require sustained trends, not single data points
- **Confidence Scoring**: Multi-factor confidence before triggering actions
- **Learning Algorithm**: Improve predictions based on outcome feedback

### Implementation
```go
type ObstructionPredictor struct {
    History         []ObstructionSample
    TrendAnalyzer   TrendAnalyzer
    Confidence      float64
    LastPrediction  time.Time
}

type ObstructionSample struct {
    Timestamp           time.Time `json:"timestamp"`
    ObstructionPct      float64   `json:"obstruction_pct"`
    SNR                 float64   `json:"snr"`
    TimeObstructed      float64   `json:"time_obstructed"`
    ProlongedInterval   float64   `json:"prolonged_interval"`
    PatchesValid        bool      `json:"patches_valid"`
    ValidS              float64   `json:"valid_s"`
}
```

---

## Adaptive Sampling
**Dynamic sampling rates** based on connection characteristics and data usage.

### Connection-Type Aware Sampling
- **Unlimited Connections**: 1-second sampling for maximum responsiveness
  - Starlink, unlimited cellular plans, fiber/cable
  - High-frequency monitoring for optimal performance
- **Metered Connections**: 60-second sampling to conserve data
  - Pay-per-MB cellular, satellite with data caps
  - Reduced probe frequency while maintaining reliability

### Intelligent Rate Adjustment
- **Performance-Based**: Increase sampling during degraded performance
- **Stability-Based**: Reduce sampling when connection is stable
- **Event-Driven**: Temporary high-frequency sampling during failovers
- **Time-Based**: Different rates for business hours vs off-hours

### Data Conservation
- **Probe Size Optimization**: Minimal ICMP packets for reachability tests
- **Batch Operations**: Combine multiple tests into single sessions
- **Smart Targeting**: Use closest/fastest targets for minimal latency
- **Background vs Foreground**: Lower rates when no user activity detected

### Configuration
```go
type SamplingConfig struct {
    UnlimitedIntervalMs   int `uci:"unlimited_interval_ms" default:"1000"`
    MeteredIntervalMs     int `uci:"metered_interval_ms" default:"60000"`
    DegradedIntervalMs    int `uci:"degraded_interval_ms" default:"5000"`
    StableIntervalMs      int `uci:"stable_interval_ms" default:"10000"`
    MaxProbeSize          int `uci:"max_probe_size" default:"32"`
}
```

---

## Backup and Recovery
**Automated recovery** and configuration preservation.

### System Recovery
- **Post-Firmware Recovery**: Detect firmware upgrades and restore configuration
- **Service Recovery**: Restart starfaild after system maintenance
- **Configuration Validation**: Verify UCI config integrity after upgrades
- **Dependency Checking**: Ensure mwan3, ubus, and other deps are available

### Configuration Preservation
- **Backup on Change**: Automatic backup before configuration changes
- **Version Control**: Keep multiple configuration versions
- **Rollback Capability**: Revert to previous working configuration
- **Migration Support**: Update configuration format during upgrades

### Disaster Recovery
- **Factory Reset Recovery**: Restore minimal working configuration
- **Network Recovery**: Rebuild mwan3 configuration from starfail config
- **Emergency Mode**: Basic connectivity when full system unavailable
- **Remote Recovery**: Restore configuration via management interfaces

### Implementation
```go
type RecoveryManager struct {
    BackupPath      string
    ConfigVersions  []ConfigVersion
    RecoveryState   RecoveryState
    LastBackup      time.Time
}

type ConfigVersion struct {
    Version     int       `json:"version"`
    Timestamp   time.Time `json:"timestamp"`
    Config      Config    `json:"config"`
    Hash        string    `json:"hash"`
}
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
**Unit tests**
- Scoring math (norm, EWMA, window, blend)
- Predictive slope detection & thresholds
- Hysteresis windows & cooldown logic
- UCI parsing, defaulting, validation

**Integration tests**
- Mock Starlink, cellular, wifi providers
- Mock mwan3/netifd controllers
- Config reload and live update

**Device E2E (RutOS + OpenWrt)**
- 8–16 members discovered from synthetic mwan3 configuration
- Starlink obstruction/outage → predictive switch to cellular
- Cellular roaming penalty → prefer Wi‑Fi/LAN when better
- Wi‑Fi signal drop → switch to cellular
- LAN jitter spike → switch to cellular
- Cooldowns prevent ping-pong
- Data-cap **conservative** mode reduces probe volume measurably
- Reboot persistence; interface flaps; SIM switch; absence of mwan3

**Acceptance Criteria**
- Auto-discovers & classifies members reliably
- Makes correct (and stable) predictive failovers/failbacks
- Exposes ubus API and CLI works as specified
- Telemetry retained within RAM caps and time window
- Meets CPU/RAM targets; no busy loops
- Degrades gracefully when providers are missing

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
- **Starlink API down**: mark API fields null; rely on reachability; WARN, don’t crash.
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
