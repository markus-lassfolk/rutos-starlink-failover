# 🔌 RUTOS Starlink Failover - API Reference

Complete reference for ubus API, CLI tools, and HTTP endpoints.

## ubus API Reference

The starfail daemon provides a comprehensive ubus API for monitoring and control.

### Authentication & Access

- **Service Name**: `starfail`
- **Access Level**: Local admin (root required)
- **Transport**: ubus JSON-RPC
- **Availability**: When daemon is running with `enable_ubus=1`

### Core Methods

#### `status` - System Status

Get overall daemon status and current primary interface.

**Usage:**

```bash
ubus call starfail status

```

**Response Schema:**

```json
{
  "daemon": {
    "version": "string",           // Daemon version
    "uptime": "number",            // Uptime in seconds
    "config_file": "string",       // Configuration file path
    "pid": "number",               // Process ID
    "build_time": "string",        // Build timestamp
    "go_version": "string"         // Go version used
  },
  "current_primary": "string",     // Current primary interface name
  "member_count": "number",        // Total discovered members
  "last_switch": "string",         // ISO timestamp of last switch
  "next_evaluation": "string",     // ISO timestamp of next evaluation
  "system": {
    "memory_usage": "string",      // Current memory usage
    "cpu_usage": "string",         // Current CPU usage percentage
    "goroutines": "number",        // Active goroutines
    "gc_runs": "number"            // Garbage collection runs
  },
  "configuration": {
    "poll_interval_ms": "number",  // Current polling interval
    "switch_margin": "number",     // Current switch margin
    "predictive": "boolean",       // Predictive logic enabled
    "dry_run": "boolean"          // Dry run mode status
  }
}

```

**Example Response:**

```json
{
  "daemon": {
    "version": "1.0.0",
    "uptime": 3600,
    "config_file": "/etc/config/starfail",
    "pid": 1234,
    "build_time": "2025-01-15T10:00:00Z",
    "go_version": "go1.22.0"
  },
  "current_primary": "starlink_any",
  "member_count": 4,
  "last_switch": "2025-01-15T10:30:45Z",
  "next_evaluation": "2025-01-15T10:35:17Z",
  "system": {
    "memory_usage": "12.3 MB",
    "cpu_usage": "2.1%",
    "goroutines": 15,
    "gc_runs": 42
  },
  "configuration": {
    "poll_interval_ms": 1500,
    "switch_margin": 10,
    "predictive": true,
    "dry_run": false
  }
}

```

#### `members` - Interface Discovery

List all discovered interfaces with current scores and states.

**Usage:**

```bash
ubus call starfail members

```

**Response Schema:**

```json
{
  "members": [
    {
      "name": "string",              // Interface name
      "class": "string",             // Interface class (starlink|cellular|wifi|lan)
      "state": "string",             // Current state (primary|backup|disabled|failed)
      "eligible": "boolean",         // Currently eligible for selection
      "detected": "boolean",         // Successfully detected/configured
      "score": {
        "instant": "number",         // Instant score (0-100)
        "ewma": "number",           // EWMA smoothed score (0-100)
        "window_avg": "number",     // Window average score (0-100)
        "final": "number"           // Final blended score (0-100)
      },
      "metrics": {
        "latency_ms": "number",     // Current latency in milliseconds
        "loss_pct": "number",       // Current packet loss percentage
        "jitter_ms": "number",      // Current jitter in milliseconds
        "signal_strength": "number", // Signal strength (dBm, if applicable)
        "timestamp": "string"       // ISO timestamp of measurement
      },
      "uptime": "number",           // Seconds since interface came up
      "last_seen": "string",        // ISO timestamp of last successful check
      "error_count": "number",      // Consecutive error count
      "cooldown_until": "string",   // ISO timestamp when cooldown expires
      "interface_specific": "object" // Class-specific additional data
    }
  ],
  "discovery": {
    "last_scan": "string",          // ISO timestamp of last discovery scan
    "scan_duration_ms": "number",   // Duration of last scan
    "interfaces_found": "number",   // Total interfaces found
    "interfaces_configured": "number" // Successfully configured interfaces
  }
}

```

**Class-Specific Data:**

**Starlink (`interface_specific`):**

```json
{
  "snr": "number",                  // Signal-to-noise ratio
  "obstruction_pct": "number",      // Current obstruction percentage
  "uptime": "number",               // Starlink reported uptime (0-1)
  "pop_ping_latency_ms": "number",  // POP ping latency
  "downlink_throughput_bps": "number", // Current downlink throughput
  "uplink_throughput_bps": "number",   // Current uplink throughput
  "outages_detected": "number"      // Number of outages detected
}

```

**Cellular (`interface_specific`):**

```json
{
  "technology": "string",           // Technology (4G, 5G, etc.)
  "operator": "string",             // Network operator name
  "rsrp": "number",                // Reference Signal Received Power
  "rsrq": "number",                // Reference Signal Received Quality
  "sinr": "number",                // Signal-to-Interference-plus-Noise Ratio
  "band": "string",                // Current frequency band
  "roaming": "boolean"             // Currently roaming
}

```

#### `metrics` - Detailed Metrics

Get detailed metrics and history for a specific interface.

**Usage:**

```bash
ubus call starfail metrics '{"member": "interface_name", "limit": 100}'

```

**Parameters:**

- `member` (string, required): Interface name
- `limit` (number, optional): Maximum number of historical samples (default: 50)

**Response Schema:**

```json
{
  "member": "string",               // Interface name
  "class": "string",               // Interface class
  "current": {
    "timestamp": "string",          // ISO timestamp
    "latency_ms": "number",        // Current latency
    "loss_pct": "number",          // Current packet loss
    "jitter_ms": "number",         // Current jitter
    "signal_strength": "number",    // Signal strength (if applicable)
    "score": {
      "instant": "number",
      "ewma": "number",
      "window_avg": "number",
      "final": "number"
    },
    "class_specific": "object"      // Class-specific current metrics
  },
  "history": [
    {
      "timestamp": "string",
      "latency_ms": "number",
      "loss_pct": "number",
      "jitter_ms": "number",
      "score": "number"
    }
  ],
  "statistics": {
    "sample_count": "number",       // Total samples collected
    "avg_latency_ms": "number",    // Average latency
    "p95_latency_ms": "number",    // 95th percentile latency
    "p99_latency_ms": "number",    // 99th percentile latency
    "avg_loss_pct": "number",      // Average packet loss
    "max_loss_pct": "number",      // Maximum packet loss
    "avg_jitter_ms": "number",     // Average jitter
    "availability": "number",       // Availability (0-1)
    "uptime_pct": "number"         // Uptime percentage
  }
}

```

#### `events` - Decision History

Get recent decision events and failover history.

**Usage:**

```bash
ubus call starfail events '{"limit": 50}'

```

**Parameters:**

- `limit` (number, optional): Maximum number of events (default: 20)

**Response Schema:**

```json
{
  "events": [
    {
      "id": "string",               // Unique decision ID (UUID)
      "timestamp": "string",        // ISO timestamp
      "type": "string",            // Event type (switch|member_discovered|member_failed|config_changed)
      "from": "string",            // Previous primary (for switch events)
      "to": "string",              // New primary (for switch events)
      "reason": "string",          // Human-readable reason
      "trigger": "string",         // Trigger type (manual|automatic|threshold|predictive)
      "duration_ms": "number",     // Decision calculation time
      "score_delta": "number",     // Score difference that triggered switch
      "member_scores": "object",   // All member scores at decision time
      "metrics_context": "object", // Relevant metrics context
      "successful": "boolean",     // Whether action completed successfully
      "error": "string"           // Error message if unsuccessful
    }
  ],
  "summary": {
    "total_events": "number",       // Total events in history
    "switch_count": "number",       // Total failover switches
    "avg_decision_time_ms": "number", // Average decision calculation time
    "last_24h_switches": "number"   // Switches in last 24 hours
  }
}

```

#### `action` - Manual Actions

Execute manual actions like failover, restore, or member discovery.

**Usage:**

```bash
ubus call starfail action '{"action": "failover"}'
ubus call starfail action '{"action": "switch", "member": "cellular_sim1", "force": true}'

```

**Parameters:**

- `action` (string, required): Action to perform
- `member` (string, optional): Target member for switch actions
- `force` (boolean, optional): Force action even if checks fail

**Supported Actions:**

| Action | Description | Additional Parameters |
|--------|-------------|---------------------|
| `failover` | Switch to best available backup | None |
| `restore` | Restore to primary member | None |
| `switch` | Switch to specific member | `member` (required) |
| `recheck` | Force member discovery | None |
| `reload` | Reload configuration | None |
| `test` | Test notification system | `message`, `priority` |

**Response Schema:**

```json
{
  "action": "string",               // Action performed
  "successful": "boolean",          // Whether action succeeded
  "message": "string",             // Result message
  "previous_primary": "string",     // Primary before action
  "new_primary": "string",         // Primary after action (if changed)
  "execution_time_ms": "number",   // Action execution time
  "decision_id": "string"          // Decision ID (for switch actions)
}

```

#### `config.get` - Configuration Retrieval

Get current configuration in JSON format.

**Usage:**

```bash
ubus call starfail config.get

```

**Response:** Complete UCI configuration as JSON object with all sections and values.

#### `config.set` - Configuration Updates

Update configuration values dynamically.

**Usage:**

```bash
ubus call starfail config.set '{
  "main.log_level": "debug",
  "main.switch_margin": "15",
  "notifications.pushover_enabled": "1"
}'

```

**Parameters:**

- Object with key-value pairs where keys use dot notation (section.option)

**Response Schema:**

```json
{
  "successful": "boolean",          // Whether update succeeded
  "changes_applied": "number",      // Number of changes applied
  "changes": [
    {
      "key": "string",             // Configuration key
      "old_value": "string",       // Previous value
      "new_value": "string",       // New value
      "applied": "boolean"         // Whether change was applied
    }
  ],
  "reload_required": "boolean",     // Whether daemon restart needed
  "message": "string"              // Result message
}

```

### Extended Methods

#### `export` - Data Export

Export telemetry data in JSON format.

**Usage:**

```bash
ubus call starfail export
ubus call starfail export '{"member": "starlink_any", "hours": 6}'

```

**Parameters:**

- `member` (string, optional): Specific member to export
- `hours` (number, optional): Number of hours to export (default: all)
- `format` (string, optional): Export format (json|csv) (default: json)

#### `notify` - Test Notifications

Send test notification to verify notification system.

**Usage:**

```bash
ubus call starfail notify '{"message": "Test notification", "priority": "info"}'

```

**Parameters:**

- `message` (string, required): Notification message
- `priority` (string, optional): Priority level (info|warning|critical|emergency)

## CLI Tool Reference

### starfailctl Commands

#### System Information

```bash
starfailctl status                    # Show daemon status
starfailctl version                   # Show version information
starfailctl health                    # Check system health

```

#### Interface Management

```bash
starfailctl members                   # List all interfaces
starfailctl metrics <member>          # Show metrics for interface
starfailctl history <member> [seconds] # Show historical data
starfailctl recheck                   # Re-discover interfaces

```

#### Manual Control

```bash
starfailctl failover                  # Force failover to best backup
starfailctl restore                   # Restore to primary
starfailctl switch <member>           # Switch to specific interface
starfailctl enable <member>           # Enable interface
starfailctl disable <member>          # Disable interface

```

#### Monitoring & Debugging

```bash
starfailctl events [limit]            # Show recent events
starfailctl logs [lines]              # Show recent log entries
starfailctl setlog <level>            # Set log level
starfailctl monitor                   # Real-time monitoring mode

```

#### Configuration

```bash
starfailctl config get                # Show current configuration
starfailctl config set <key>=<value>  # Update configuration
starfailctl config reload             # Reload configuration
starfailctl config backup             # Backup configuration

```

#### Testing & Diagnostics

```bash
starfailctl test notifications        # Test notification system
starfailctl test ping <member>        # Test connectivity to member
starfailctl test starlink             # Test Starlink API connectivity
starfailctl diagnose                  # Run diagnostic checks

```

### Direct Daemon Options

#### Command Line Flags

```bash
starfaild [options]

```

| Flag | Description | Default |
|------|-------------|---------|
| `--config PATH` | Configuration file path | `/etc/config/starfail` |
| `--log-level LEVEL` | Set log level | `info` |
| `--log-file PATH` | Log file path | stdout |
| `--monitor` | Enable real-time monitoring | disabled |
| `--dry-run` | Test mode without changes | disabled |
| `--verbose` | Enable verbose logging | disabled |
| `--debug` | Enable debug logging | disabled |
| `--trace` | Enable trace logging | disabled |
| `--json` | JSON log format | disabled |
| `--no-color` | Disable colored output | disabled |
| `--metrics-addr ADDR` | Metrics server address | `127.0.0.1:9101` |
| `--health-addr ADDR` | Health server address | `127.0.0.1:9101` |
| `--version` | Show version and exit | - |
| `--help` | Show help and exit | - |

#### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STARFAIL_CONFIG` | Configuration file path | `/etc/config/starfail` |
| `STARFAIL_LOG_LEVEL` | Log level override | - |
| `STARFAIL_DRY_RUN` | Enable dry run mode | `false` |
| `STARFAIL_METRICS_ADDR` | Metrics endpoint address | `127.0.0.1:9101` |

## HTTP Endpoints

### Health Check Endpoint

**URL:** `http://127.0.0.1:9101/health`
**Method:** GET
**Description:** System health status

**Response:**

```json
{
  "status": "healthy|degraded|unhealthy",
  "version": "string",
  "uptime": "number",
  "timestamp": "string",
  "checks": {
    "uci_config": "ok|error",
    "ubus_connectivity": "ok|error",
    "mwan3_integration": "ok|error",
    "memory_usage": "ok|warning|error",
    "collector_status": "ok|warning|error"
  },
  "details": {
    "memory_mb": "number",
    "goroutines": "number",
    "last_decision": "string",
    "active_members": "number"
  }
}

```

### Metrics Endpoint (Prometheus Format)

**URL:** `http://127.0.0.1:9101/metrics`
**Method:** GET
**Description:** Prometheus-compatible metrics

**Sample Metrics:**

```text

# HELP starfail_member_score Current member score (0-100)

# TYPE starfail_member_score gauge

starfail_member_score{member="starlink_any",class="starlink"} 86.4

# HELP starfail_member_latency_ms Current member latency in milliseconds

# TYPE starfail_member_latency_ms gauge

starfail_member_latency_ms{member="starlink_any"} 45.2

# HELP starfail_switch_total Total number of switches

# TYPE starfail_switch_total counter

starfail_switch_total{from="starlink",to="cellular"} 3

# HELP starfail_uptime_seconds Daemon uptime in seconds

# TYPE starfail_uptime_seconds gauge

starfail_uptime_seconds 3600

# HELP starfail_memory_bytes Current memory usage in bytes

# TYPE starfail_memory_bytes gauge

starfail_memory_bytes 12582912

# HELP starfail_decision_duration_seconds Time spent on last decision

# TYPE starfail_decision_duration_seconds gauge

starfail_decision_duration_seconds 0.0012

```

## Error Codes

### ubus Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | `UBUS_STATUS_OK` | Success |
| 1 | `UBUS_STATUS_INVALID_COMMAND` | Invalid method name |
| 2 | `UBUS_STATUS_INVALID_ARGUMENT` | Invalid parameters |
| 3 | `UBUS_STATUS_METHOD_NOT_FOUND` | Method not available |
| 4 | `UBUS_STATUS_NOT_FOUND` | Resource not found |
| 5 | `UBUS_STATUS_NO_DATA` | No data available |
| 6 | `UBUS_STATUS_PERMISSION_DENIED` | Access denied |
| 7 | `UBUS_STATUS_TIMEOUT` | Operation timeout |
| 8 | `UBUS_STATUS_NOT_SUPPORTED` | Operation not supported |
| 9 | `UBUS_STATUS_UNKNOWN_ERROR` | Unknown error |

### Application Error Codes

| Code | Description | Typical Causes |
|------|-------------|----------------|
| 1000 | Configuration Error | Invalid UCI configuration |
| 1001 | Member Not Found | Interface name not recognized |
| 1002 | Action Not Allowed | Action blocked by policy |
| 1003 | Collector Failed | Interface monitoring failed |
| 1004 | Controller Failed | mwan3/netifd operation failed |
| 1005 | Notification Failed | Alert delivery failed |
| 1006 | Resource Exhausted | Memory/connection limits |
| 1007 | External Dependency | ubus/UCI/mwan3 unavailable |

## Rate Limits

### ubus API Rate Limits

| Method | Limit | Window |
|--------|-------|---------|
| `status` | 60/min | Per client |
| `members` | 30/min | Per client |
| `metrics` | 20/min | Per client |
| `events` | 10/min | Per client |
| `action` | 5/min | Per client |
| `config.set` | 2/min | Per client |

### HTTP Endpoint Rate Limits

| Endpoint | Limit | Window |
|----------|-------|---------|
| `/health` | 120/min | Per IP |
| `/metrics` | 60/min | Per IP |

## Best Practices

### API Usage

1. **Polling Frequency**: Don't poll status more than once per 5 seconds
2. **Batch Operations**: Use single calls rather than rapid succession
3. **Error Handling**: Always check response status before using data
4. **Resource Cleanup**: Close connections properly in scripts

### CLI Usage

1. **Automation**: Use `--json` flag for script consumption
2. **Monitoring**: Use `monitor` command for real-time observation
3. **Testing**: Use `dry-run` mode before configuration changes
4. **Logging**: Increase log level temporarily for troubleshooting

### Performance Considerations

1. **Memory Impact**: Limit historical data requests to necessary timeframes
2. **Network Usage**: Avoid frequent metrics polling on metered connections
3. **CPU Impact**: Use appropriate polling intervals for your hardware
4. **Storage**: Regular cleanup of old events and logs

For implementation examples, see [CONFIGURATION_EXAMPLES.md](CONFIGURATION_EXAMPLES.md)
