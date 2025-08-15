# 📚 RUTOS Starlink Failover - Complete Features & Configuration Guide

## Production-Ready Go Daemon for Intelligent Multi-Interface Failover

---

## 🏗️ System Architecture

### Core Components

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Collectors    │───▶│ Decision Engine │───▶│   Controllers   │
│ • Starlink API  │    │ • EWMA Scoring  │    │ • mwan3 Policies│
│ • Cellular ubus │    │ • Hysteresis    │    │ • netifd Routes │
│ • WiFi iwinfo   │    │ • Predictive    │    │ • Route Metrics │
│ • LAN/Ping      │    │   Logic         │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│              Telemetry Store & ubus API                        │
│    • In-memory samples     • Event logging                     │
│    • JSON export           • Live monitoring                   │
└─────────────────────────────────────────────────────────────────┘
```

### Package Structure

| **Package** | **Purpose** | **Key Features** |
|-------------|-------------|------------------|
| `cmd/starfaild/` | Main daemon | Tick-based loop, signal handling, service lifecycle |
| `cmd/starfail-sysmgmt/` | System maintenance | Cleanup, monitoring, health checks |
| `pkg/collector/` | Metrics collection | Interface-specific data gathering |
| `pkg/decision/` | Scoring engine | EWMA, hysteresis, predictive logic |
| `pkg/controller/` | Network control | mwan3 integration, policy management |
| `pkg/notification/` | Alert system | Multi-channel notifications with rate limiting |
| `pkg/telem/` | Telemetry | In-memory storage, retention management |
| `pkg/ubus/` | API interface | Complete ubus API for monitoring and control |
| `pkg/uci/` | Configuration | UCI config parsing and validation |

---

## ⚙️ Complete Configuration Reference

### Main Configuration (`/etc/config/starfail`)

#### **Core System Settings**

```uci
config starfail 'main'
    # System Control
    option enable '1'                           # Enable/disable daemon (1|0)
    option use_mwan3 '1'                       # Use mwan3 for routing control (1|0)
    option dry_run '0'                         # Test mode without actual changes (1|0)
    option enable_ubus '1'                     # Enable ubus API (1|0)
    
    # Timing & Performance
    option poll_interval_ms '1500'            # Main loop interval (ms)
    option history_window_s '600'             # Metrics history window (seconds)
    option retention_hours '24'               # Data retention period (hours)
    option min_uptime_s '20'                  # Minimum interface uptime before eligibility (seconds)
    option cooldown_s '20'                    # Cooldown between switches (seconds)
    
    # Memory Management
    option max_ram_mb '16'                     # Maximum RAM usage (MB)
    option max_samples_per_member '1000'      # Max samples per interface
    option max_events '500'                    # Max stored events
    
    # Decision Logic
    option data_cap_mode 'balanced'            # Data usage mode (conservative|balanced|aggressive)
    option predictive '1'                      # Enable predictive switching (1|0)
    option switch_margin '10'                 # Minimum score difference for switch
    
    # Monitoring & Debugging
    option metrics_listener '0'               # Enable metrics HTTP endpoint (1|0)
    option health_listener '1'                # Enable health check endpoint (1|0)
    option log_level 'info'                   # Log level (trace|debug|info|warn|error)
    option log_file ''                        # Log file path (empty = stdout)
```

#### **Fail/Restore Thresholds**

```uci
    # Failure Detection
    option fail_threshold_loss '5'            # Packet loss % to trigger failure
    option fail_threshold_latency '1200'      # Latency ms to trigger failure
    option fail_min_duration_s '10'           # Minimum failure duration before switch
    
    # Recovery Detection
    option restore_threshold_loss '1'         # Packet loss % for recovery
    option restore_threshold_latency '800'    # Latency ms for recovery
    option restore_min_duration_s '30'        # Minimum recovery duration before restore
```

#### **Optional Features**

```uci
    # Notifications (Basic)
    option pushover_token ''                   # Pushover app token
    option pushover_user ''                    # Pushover user key
    
    # Telemetry Publishing
    option mqtt_broker ''                      # MQTT broker URL
    option mqtt_topic 'starfail/status'       # MQTT topic prefix
```

---

### Scoring Algorithm Configuration

```uci
config starfail 'scoring'
    # Weight Distribution (must sum to ~100)
    option weight_latency '25'                # Latency importance %
    option weight_loss '30'                   # Packet loss importance %
    option weight_jitter '15'                 # Jitter importance %
    option weight_obstruction '20'            # Starlink obstruction importance %
    
    # Performance Thresholds
    option latency_ok_ms '50'                 # Good latency threshold
    option latency_bad_ms '1500'              # Bad latency threshold
    option loss_ok_pct '0'                    # Good packet loss threshold
    option loss_bad_pct '10'                  # Bad packet loss threshold
    option jitter_ok_ms '5'                   # Good jitter threshold
    option jitter_bad_ms '200'                # Bad jitter threshold
    option obstruction_ok_pct '0'             # Good obstruction threshold
    option obstruction_bad_pct '10'           # Bad obstruction threshold
```

---

### Starlink-Specific Configuration

```uci
config starfail 'starlink'
    option dish_ip '192.168.100.1'           # Starlink dish IP address
    option dish_port '9200'                  # Starlink gRPC API port
```

---

### Advanced Notification Configuration

```uci
config starfail 'notifications'
    # Core Settings
    option enable '1'                         # Enable notifications (1|0)
    option rate_limit_minutes '5'            # Minimum time between similar alerts
    option priority_threshold 'medium'        # Minimum priority (info|warning|critical|emergency)
    
    # Pushover Integration
    option pushover_enabled '1'              # Enable Pushover (1|0)
    option pushover_token 'your_app_token'   # Pushover application token
    option pushover_user 'your_user_key'     # Pushover user key
    
    # MQTT Integration
    option mqtt_enabled '1'                  # Enable MQTT (1|0)
    option mqtt_broker 'mqtt://broker:1883'  # MQTT broker URL
    option mqtt_topic 'starfail/alerts'      # MQTT topic for alerts
    
    # Webhook Integration
    option webhook_enabled '0'               # Enable webhook (1|0)
    option webhook_url ''                    # Webhook endpoint URL
    
    # Email Integration
    option email_enabled '0'                 # Enable email (1|0)
    option email_smtp_server ''              # SMTP server
    option email_from ''                     # From address
    option email_to ''                       # To address
```

---

### Recovery & Backup Configuration

```uci
config starfail 'recovery'
    option enable '1'                         # Enable backup/recovery (1|0)
    option backup_dir '/etc/starfail/backup' # Backup directory
    option max_versions '10'                 # Maximum backup versions
    option auto_backup_on_change '1'         # Auto-backup on config change (1|0)
    option backup_interval_hours '24'        # Backup interval
    option compress_backups '1'              # Compress backups (1|0)
```

---

### Adaptive Sampling Configuration

```uci
config starfail 'sampling'
    option enable '1'                         # Enable adaptive sampling (1|0)
    option base_interval_ms '1000'           # Base sampling interval
    option fast_interval_ms '500'            # Fast interval for problems
    option slow_interval_ms '5000'           # Slow interval for stable
    option performance_threshold '70.0'      # Score threshold for fast sampling
    option data_cap_aware '1'                # Reduce sampling on metered (1|0)
    option adaptation_factor '0.1'           # Rate of adaptation
```

---

### System Management Configuration

```uci
config starfail 'sysmgmt'
    option enable '1'                         # Enable system management (1|0)
    option overlay_cleanup_days '7'          # Clean old overlay files
    option log_cleanup_days '3'              # Clean old log files
    option service_check_interval '300'      # Service health check interval
    option time_drift_threshold '30'         # Time drift alert threshold
    option interface_flap_threshold '5'      # Interface flap detection
```

---

### Per-Member Configuration Overrides

```uci
# Starlink Configuration
config member 'starlink_any'
    option detect 'auto'                      # Detection mode (auto|disable|force)
    option class 'starlink'                   # Interface class
    option weight '100'                       # Base weight (0-100)
    option min_uptime_s '30'                  # Minimum uptime before use
    option cooldown_s '20'                    # Cooldown after switch
    option metered '0'                        # Is metered connection (1|0)

# Cellular Configuration
config member 'cellular_any'
    option detect 'auto'
    option class 'cellular'
    option weight '80'
    option prefer_roaming '0'                 # Prefer roaming SIM (1|0)
    option metered '1'                        # Cellular is typically metered
    option min_uptime_s '20'
    option cooldown_s '20'

# WiFi Configuration
config member 'wifi_any'
    option detect 'auto'
    option class 'wifi'
    option weight '60'
    option metered '0'

# LAN Configuration
config member 'lan_any'
    option detect 'auto'
    option class 'lan'
    option weight '40'
    option metered '0'
```

---

## 🚀 Core Features

### 1. **Intelligent Multi-Interface Failover**

#### **Supported Interface Types**

| **Type** | **Detection Method** | **Key Metrics** | **Special Features** |
|----------|---------------------|------------------|---------------------|
| **Starlink** | Local API (192.168.100.1:9200) | SNR, obstruction, outages | Predictive obstruction detection |
| **Cellular** | ubus mobiled/gsm | RSRP, RSRQ, SINR | Multi-SIM support, roaming preference |
| **WiFi** | iwinfo + ping | Signal strength, bitrate | Station mode and tethering |
| **LAN/Ethernet** | Ping probing | Latency, loss, jitter | Generic interface support |

#### **Automatic Discovery**
- **Interface scanning**: Automatically detects available interfaces
- **Class identification**: Determines interface type and capabilities
- **Configuration inheritance**: Applies defaults with per-member overrides
- **Dynamic updates**: Handles interface hotplug events

### 2. **Advanced Scoring System**

#### **Multi-Layer Scoring Algorithm**

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Instant Score  │    │   EWMA Score    │    │ Window Average  │
│   (0-100)       │───▶│   (smoothed)    │───▶│   (historical)  │
│                 │    │                 │    │                 │
│ Base - Penalties│    │ α×new + (1-α)×old│    │ Mean of samples │
│ + Bonuses       │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
         ┌─────────────────────────────────────────────────┐
         │            Final Blended Score                  │
         │    30% × Instant + 50% × EWMA + 20% × Window   │
         └─────────────────────────────────────────────────┘
```

#### **Scoring Components**

**Instant Score Calculation:**
```go
instant_score = base_weight 
    - latency_penalty 
    - loss_penalty 
    - jitter_penalty 
    - obstruction_penalty 
    + signal_bonus 
    + reliability_bonus
```

**Penalty Examples:**
- **Latency**: 0 penalty for <50ms, linear increase to max at >1500ms
- **Loss**: 0 penalty for 0%, exponential increase beyond 1%
- **Jitter**: 0 penalty for <5ms, sharp increase beyond 200ms
- **Obstruction**: Starlink-specific, 0% = no penalty, >10% = major penalty

### 3. **Hysteresis & Predictive Logic**

#### **Hysteresis Prevention**
- **Duration-based windows**: Must maintain state for minimum duration
- **Switch margin**: Requires minimum score difference (default 10 points)
- **Cooldown periods**: Prevents rapid switching between interfaces
- **Member uptime**: Ensures interface stability before eligibility

#### **Predictive Switching**
- **Trend analysis**: Detects rising loss/latency slopes
- **Jitter spikes**: Identifies connection quality degradation
- **Starlink obstruction**: Predicts outages from obstruction data
- **Pattern learning**: Adapts to location-specific behavior

### 4. **Comprehensive Decision Audit Trail**

#### **Decision Context Tracking**
```json
{
  "decision_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2025-01-15T10:30:45Z",
  "trigger": "primary_degradation",
  "current_primary": "starlink_any",
  "new_primary": "cellular_sim1",
  "reason": "Rising packet loss (8.2%)",
  "member_scores": {
    "starlink_any": {"instant": 15.2, "ewma": 22.1, "final": 18.8},
    "cellular_sim1": {"instant": 78.4, "ewma": 76.2, "final": 77.1}
  },
  "metrics_context": {
    "starlink_any": {
      "latency_ms": 1250.5,
      "loss_pct": 8.2,
      "jitter_ms": 45.8,
      "obstruction_pct": 0.0
    }
  },
  "decision_duration_ms": 1.2,
  "switch_executed": true
}
```

---

## 🔌 ubus API Reference

### **Core API Endpoints**

#### **1. System Status**
```bash
ubus call starfail status
```
**Returns:**
```json
{
  "daemon": {
    "version": "1.0.0",
    "uptime": 3600,
    "config_file": "/etc/config/starfail",
    "pid": 1234
  },
  "current_primary": "starlink_any",
  "member_count": 4,
  "last_switch": "2025-01-15T10:30:45Z",
  "system": {
    "memory_usage": "12.3 MB",
    "cpu_usage": "2.1%",
    "goroutines": 15
  }
}
```

#### **2. Member Discovery & Scores**
```bash
ubus call starfail members
```
**Returns:**
```json
{
  "members": [
    {
      "name": "starlink_any",
      "class": "starlink",
      "state": "primary",
      "eligible": true,
      "score": {
        "instant": 85.2,
        "ewma": 87.1,
        "window_avg": 86.5,
        "final": 86.4
      },
      "uptime": 1800,
      "last_seen": "2025-01-15T10:35:12Z"
    },
    {
      "name": "cellular_sim1",
      "class": "cellular",
      "state": "backup",
      "eligible": true,
      "score": {
        "instant": 76.8,
        "ewma": 78.2,
        "window_avg": 75.9,
        "final": 77.1
      },
      "uptime": 900,
      "last_seen": "2025-01-15T10:35:10Z"
    }
  ]
}
```

#### **3. Detailed Metrics**
```bash
ubus call starfail metrics '{"member": "starlink_any", "limit": 100}'
```
**Returns:**
```json
{
  "member": "starlink_any",
  "class": "starlink",
  "current": {
    "timestamp": "2025-01-15T10:35:15Z",
    "latency_ms": 45.2,
    "loss_pct": 0.1,
    "jitter_ms": 8.5,
    "signal_strength": -65,
    "starlink_specific": {
      "snr": 8.2,
      "obstruction_pct": 0.0,
      "uptime": 0.99,
      "pop_ping_latency_ms": 28.5
    }
  },
  "history": [
    // Last 100 samples...
  ],
  "statistics": {
    "avg_latency_ms": 47.8,
    "p95_latency_ms": 65.2,
    "avg_loss_pct": 0.15,
    "availability": 0.995
  }
}
```

#### **4. Event History**
```bash
ubus call starfail events '{"limit": 50}'
```
**Returns:**
```json
{
  "events": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "timestamp": "2025-01-15T10:30:45Z",
      "type": "switch",
      "from": "starlink_any",
      "to": "cellular_sim1",
      "reason": "Rising packet loss (8.2%)",
      "duration_ms": 1.2
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "timestamp": "2025-01-15T10:25:30Z",
      "type": "member_discovered",
      "member": "wifi_sta",
      "class": "wifi"
    }
  ]
}
```

#### **5. Manual Actions**
```bash
# Force failover to best backup
ubus call starfail action '{"action": "failover"}'

# Force specific member
ubus call starfail action '{"action": "switch", "member": "cellular_sim1", "force": true}'

# Restore to primary
ubus call starfail action '{"action": "restore"}'

# Trigger member discovery
ubus call starfail action '{"action": "recheck"}'
```

#### **6. Configuration Management**
```bash
# Get current configuration
ubus call starfail config.get

# Update configuration
ubus call starfail config.set '{
  "main.log_level": "debug",
  "main.switch_margin": "15",
  "notifications.pushover_enabled": "1"
}'
```

---

## 🛠️ Command-Line Tools

### **starfailctl - Main CLI Tool**

#### **System Status & Monitoring**
```bash
starfailctl status                    # Show daemon status and current member
starfailctl members                   # List all discovered members with scores
starfailctl metrics wan_starlink      # Show detailed metrics for a member
starfailctl history wan_cell 300      # Show 5-minute history for cellular
starfailctl events 50                 # Show last 50 decision events
```

#### **Manual Control**
```bash
starfailctl failover                  # Manually trigger failover to best backup
starfailctl restore                   # Manually restore to primary member
starfailctl recheck                   # Force member discovery and recheck
```

#### **Configuration & Debugging**
```bash
starfailctl setlog debug              # Set log level to debug
starfailctl config get                # Show current configuration
starfailctl config set main.log_level=info  # Update configuration
```

### **Direct Daemon Options**

```bash
# Start with specific configuration
starfaild --config /etc/config/starfail --log-level debug

# Monitor mode with real-time output
starfaild --monitor --verbose

# Test mode without making changes
starfaild --dry-run --log-level trace
```

#### **Command-Line Options**

| **Option** | **Description** | **Example** |
|------------|-----------------|-------------|
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
| `--dry-run` | Test mode without making changes | `--dry-run` |

---

## 📊 Monitoring & Observability

### **Structured Logging**

#### **Log Levels & Content**
- **TRACE**: Detailed function entry/exit, raw data
- **DEBUG**: Decision logic, score calculations, state changes
- **INFO**: Failover events, member discovery, configuration changes
- **WARN**: Degraded performance, timeout issues, recoverable errors
- **ERROR**: Configuration errors, system failures, critical issues

#### **JSON Log Format**
```json
{
  "timestamp": "2025-01-15T10:35:15.123Z",
  "level": "info",
  "component": "decision",
  "message": "member switch executed",
  "fields": {
    "decision_id": "550e8400-e29b-41d4-a716-446655440000",
    "from": "starlink_any",
    "to": "cellular_sim1",
    "reason": "primary_degradation",
    "score_delta": 15.3,
    "duration_ms": 1.2
  }
}
```

### **Health Monitoring Endpoints**

#### **Health Check (Default: 127.0.0.1:9101/health)**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime": 3600,
  "checks": {
    "uci_config": "ok",
    "ubus_connectivity": "ok",
    "mwan3_integration": "ok",
    "memory_usage": "ok"
  }
}
```

#### **Metrics Endpoint (Optional: 127.0.0.1:9101/metrics)**
```text
starfail_member_score{member="starlink_any"} 86.4
starfail_member_latency_ms{member="starlink_any"} 45.2
starfail_switch_total{from="starlink",to="cellular"} 3
starfail_uptime_seconds 3600
```

### **Telemetry Storage**

#### **In-Memory Ring Buffers**
- **Configurable retention**: Default 24 hours, 1000 samples per member
- **Automatic downsampling**: When memory limits exceeded
- **Event storage**: Last 500 decisions with full context
- **Memory caps**: Enforced with graceful degradation

#### **Data Export**
```bash
# Export all telemetry as JSON
ubus call starfail export

# Export specific member history
ubus call starfail export '{"member": "starlink_any", "hours": 6}'
```

---

## 📢 Notification System

### **Smart Notification Features**

#### **Priority-Based Rate Limiting**
| **Priority** | **Cooldown** | **Use Cases** |
|--------------|--------------|---------------|
| **Emergency** | 0 seconds | Complete connectivity loss |
| **Critical** | 5 minutes | Primary interface failure |
| **Warning** | 1 hour | Interface degradation |
| **Info** | 6 hours | Routine status updates |

#### **Context-Aware Notifications**
- **Rich details**: Interface metrics, decision context, location data
- **Acknowledgment tracking**: Reduces duplicate alerts
- **Channel failover**: Falls back to system logs if primary fails
- **Template customization**: Configurable message formats

### **Supported Notification Channels**

#### **1. Pushover Integration**
```uci
option pushover_enabled '1'
option pushover_token 'your_app_token'
option pushover_user 'your_user_key'
```

**Features:**
- **Priority mapping**: Automatic priority assignment based on event type
- **Rich notifications**: Device info, metrics, decision context
- **Acknowledgment support**: Reduces notification spam
- **Retry logic**: Exponential backoff on failures

#### **2. MQTT Publishing**

```uci
option mqtt_enabled '1'
option mqtt_broker 'mqtt://broker:1883'
option mqtt_topic 'starfail/alerts'
```

**Topics:**

- `starfail/alerts/switch` - Failover events
- `starfail/alerts/member` - Member state changes
- `starfail/alerts/system` - System events

#### **3. Webhook Integration**

```uci
option webhook_enabled '1'
option webhook_url 'https://your-webhook.com/starfail'
```

**Payload Example:**
```json
{
  "event": "switch",
  "timestamp": "2025-01-15T10:30:45Z",
  "from": "starlink_any",
  "to": "cellular_sim1",
  "reason": "primary_degradation",
  "metrics": { /* detailed metrics */ }
}
```

#### **4. Email Notifications** (Optional)
```uci
option email_enabled '1'
option email_smtp_server 'smtp.gmail.com:587'
option email_from 'router@example.com'
option email_to 'admin@example.com'
```

---

## 🔄 System Integration

### **mwan3 Integration**

#### **Policy Management**
- **Non-destructive**: Works with existing mwan3 configurations
- **Policy updates**: Changes member priorities without full reload
- **Verification**: Validates changes before and after execution
- **Rollback**: Automatic rollback on failures

#### **Member Synchronization**
```bash
# starfail automatically discovers and maps mwan3 members
# Maps network interfaces to mwan3 member names
# Respects existing mwan3 configuration
```

### **netifd Fallback**
- **Route metrics**: Direct route table manipulation when mwan3 unavailable
- **Interface monitoring**: Integration with netifd interface events
- **Graceful degradation**: Continues operation without mwan3

### **procd Service Integration**

#### **Service Definition** (`/etc/init.d/starfail`)
```bash
# Automatic respawn on crashes
procd_set_param respawn 3600 5 3

# Configuration file watching
procd_set_param file /etc/config/starfail

# Interface change triggers
procd_add_interface_trigger "interface" "*" /etc/init.d/starfail reload
```

#### **Signal Handling**
- **SIGHUP**: Reload configuration without restart
- **SIGTERM/SIGINT**: Graceful shutdown with cleanup
- **SIGUSR1**: Dump internal state to logs

---

## 🚀 Performance Characteristics

### **Resource Usage**

#### **Memory Management**
- **Static allocation**: Minimal garbage collection pressure
- **Ring buffers**: Fixed-size circular buffers for metrics
- **Memory caps**: Configurable limits with automatic downsampling
- **Target usage**: <25MB RSS in steady state

#### **CPU Efficiency**
- **Tick-based loop**: Configurable intervals (default 1.5s)
- **Non-blocking collectors**: Parallel metric collection
- **Efficient algorithms**: O(1) scoring, O(log n) decision tree
- **Target usage**: <5% CPU on idle, <15% during failover

#### **Network Usage**
- **Conservative probing**: Minimal bandwidth usage
- **Data cap awareness**: Reduced probing on metered connections
- **Efficient APIs**: Single requests for multiple metrics
- **Target usage**: <1MB/hour network overhead

### **Timing Characteristics**

#### **Response Times**
- **Decision calculation**: <1 second typical
- **Failover execution**: <5 seconds end-to-end
- **Member discovery**: <10 seconds initial scan
- **Configuration reload**: <2 seconds without restart

#### **Reliability Targets**
- **Uptime**: >99.9% availability
- **Failover success**: >99.5% successful switches
- **False positives**: <0.1% incorrect decisions
- **Memory stability**: No memory leaks over 30-day runs

---

## 🛡️ Security & Privacy

### **Security Model**
- **Root privileges**: Required for network control (standard OpenWrt pattern)
- **Local access**: API endpoints bound to localhost only
- **No external dependencies**: Self-contained binary reduces attack surface
- **Credential handling**: UCI-only storage, never logged

### **Privacy Protection**
- **Local processing**: All decisions made on-device
- **Optional telemetry**: MQTT/webhook publishing is opt-in
- **No cloud dependencies**: Fully functional without internet
- **Data retention**: Configurable with automatic cleanup

---

## 📚 Advanced Configuration Examples

### **Mobile/Vehicle Deployment**
```uci
config starfail 'main'
    option enable '1'
    option poll_interval_ms '1000'        # Faster polling for mobile
    option switch_margin '15'             # Higher margin for stability
    option predictive '1'                 # Enable obstruction prediction
    option data_cap_mode 'conservative'   # Minimize cellular usage

config starfail 'scoring'
    option weight_latency '20'            # Reduce latency weight
    option weight_loss '35'               # Increase loss weight
    option weight_obstruction '25'        # High obstruction weight

config member 'starlink_dish'
    option weight '100'                   # Prefer Starlink when available
    option min_uptime_s '45'              # Longer stabilization

config member 'cellular_primary'
    option weight '75'                    # Good backup option
    option metered '1'                    # Mark as metered
```

### **Fixed Installation**
```uci
config starfail 'main'
    option enable '1'
    option poll_interval_ms '2000'        # Slower polling for fixed install
    option switch_margin '8'              # Lower margin for responsiveness
    option data_cap_mode 'balanced'       # Balanced usage

config starfail 'scoring'
    option weight_latency '30'            # Higher latency weight
    option weight_jitter '20'             # Higher jitter weight
    option weight_obstruction '15'        # Lower obstruction weight

config member 'starlink_dish'
    option weight '90'                    # Still prefer Starlink
    option min_uptime_s '20'              # Faster switches

config member 'fiber_backup'
    option weight '85'                    # High-quality backup
    option class 'lan'                    # Treat as LAN connection
```

### **Development/Testing Configuration**
```uci
config starfail 'main'
    option enable '1'
    option dry_run '1'                    # Test mode - no actual changes
    option log_level 'debug'              # Verbose logging
    option poll_interval_ms '500'         # Fast polling for testing
    option switch_margin '5'              # Low margin for frequent switches

config starfail 'notifications'
    option enable '1'
    option pushover_enabled '1'           # Test notifications
    option rate_limit_minutes '1'         # Allow frequent test alerts
```

---

## 🔧 Troubleshooting Guide

### **Common Issues & Solutions**

#### **1. Daemon Won't Start**
```bash
# Check configuration syntax
uci show starfail

# Verify binary permissions
ls -la /usr/sbin/starfaild

# Check init script
/etc/init.d/starfail status

# Manual start with debug
starfaild --config /etc/config/starfail --debug
```

#### **2. No Interfaces Detected**
```bash
# Check network configuration
ip link show

# Verify mwan3 status
mwan3 status

# Force member discovery
starfailctl recheck

# Check detection logs
logread | grep starfail | grep detect
```

#### **3. Scores Always Zero**
```bash
# Check collector status
starfailctl members

# Verify ping connectivity
ping -c 3 8.8.8.8

# Check Starlink API
curl http://192.168.100.1:9200/JSONData

# Review scoring configuration
uci show starfail.scoring
```

#### **4. Notifications Not Working**
```bash
# Test notification system
ubus call starfail notify '{"message":"Test","priority":"info"}'

# Check Pushover credentials
uci show starfail.notifications

# Verify rate limiting
grep "rate limited" /var/log/messages
```

### **Debug Commands**

```bash
# Full system status
starfailctl status

# Detailed member information
starfailctl members

# Recent decision events
starfailctl events 20

# Configuration dump
ubus call starfail config.get

# Enable debug logging
starfailctl setlog debug

# Force failover test
starfailctl failover

# Check service health
curl http://127.0.0.1:9101/health
```

---

## 📈 Deployment Best Practices

### **Pre-Deployment Checklist**

#### **1. Network Infrastructure**
- ✅ Verify all interfaces are configured in mwan3
- ✅ Test basic connectivity on each interface
- ✅ Configure appropriate ping targets
- ✅ Set reasonable mwan3 tracking parameters

#### **2. starfail Configuration**
- ✅ Create `/etc/config/starfail` with appropriate settings
- ✅ Tune scoring weights for your environment
- ✅ Set realistic thresholds for fail/restore
- ✅ Configure notification channels

#### **3. Testing & Validation**
- ✅ Run in dry-run mode initially
- ✅ Test manual failover operations
- ✅ Verify notification delivery
- ✅ Monitor resource usage

#### **4. Production Deployment**
- ✅ Start with conservative settings
- ✅ Monitor logs during initial operation
- ✅ Gradually tune parameters based on observed behavior
- ✅ Set up regular configuration backups

### **Monitoring & Maintenance**

#### **Regular Checks**
```bash
# Weekly health check
starfailctl status
curl http://127.0.0.1:9101/health

# Monthly configuration backup
cp /etc/config/starfail /etc/starfail/backup/starfail.$(date +%Y%m%d)

# Review decision history
starfailctl events 100 | grep switch

# Check resource usage
ps aux | grep starfail
cat /proc/$(pgrep starfaild)/status | grep VmRSS
```

#### **Performance Tuning**
- **Monitor switch frequency**: Adjust `switch_margin` if too frequent
- **Optimize polling intervals**: Balance responsiveness vs. resource usage
- **Tune scoring weights**: Based on observed interface behavior
- **Adjust thresholds**: Based on actual network conditions

---

*This documentation covers all features and configuration options for the RUTOS Starlink Failover system. For implementation-specific details, refer to the source code and inline documentation.*
