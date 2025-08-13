# Starfaild API Reference

This document provides a comprehensive reference for all APIs and interfaces provided by the starfaild daemon.

## Table of Contents

1. [ubus RPC Interface](#ubus-rpc-interface)
2. [HTTP Endpoints](#http-endpoints)
3. [Configuration](#configuration)
4. [Data Structures](#data-structures)
5. [Error Handling](#error-handling)
6. [Examples](#examples)

## ubus RPC Interface

The starfaild daemon exposes a ubus RPC interface for control and monitoring. All ubus calls use the `starfail` namespace.

### Authentication

ubus calls require appropriate permissions. The daemon runs with system privileges and can be accessed by:
- Root user
- Users in the `ubus` group
- Users with explicit ubus permissions

### Available Methods

#### `status`

Returns the current status of the daemon and all members.

**Parameters:** None

**Returns:**
```json
{
  "status": "running",
  "uptime": 3600,
  "version": "1.0.0",
  "active_member": "starlink",
  "members": [
    {
      "name": "starlink",
      "class": "starlink",
      "interface": "wan",
      "status": "active",
      "score": 85.5,
      "uptime": 3600
    }
  ]
}
```

**Example:**
```bash
ubus call starfail status
```

#### `members`

Returns detailed information about all discovered members.

**Parameters:** None

**Returns:**
```json
{
  "members": [
    {
      "name": "starlink",
      "class": "starlink",
      "interface": "wan",
      "enabled": true,
      "priority": 100,
      "created": "2024-01-01T00:00:00Z",
      "state": "eligible",
      "score": 85.5,
      "metrics": {
        "latency": 50.0,
        "loss": 0.1,
        "signal": -70.0,
        "obstruction": 5.0
      }
    }
  ]
}
```

**Example:**
```bash
ubus call starfail members
```

#### `metrics`

Returns metrics for a specific member or all members.

**Parameters:**
- `member` (optional): Member name to get metrics for

**Returns:**
```json
{
  "metrics": {
    "starlink": {
      "timestamp": "2024-01-01T00:00:00Z",
      "latency": 50.0,
      "loss": 0.1,
      "jitter": 5.0,
      "bandwidth": 100.0,
      "signal": -70.0,
      "obstruction": 5.0,
      "outages": 0,
      "network_type": "4G",
      "operator": "Test Operator",
      "roaming": false,
      "connected": true
    }
  }
}
```

**Example:**
```bash
# Get metrics for all members
ubus call starfail metrics

# Get metrics for specific member
ubus call starfail metrics '{"member": "starlink"}'
```

#### `history`

Returns historical data for a member.

**Parameters:**
- `member`: Member name
- `limit` (optional): Number of samples to return (default: 100)
- `hours` (optional): Hours of history to return (default: 24)

**Returns:**
```json
{
  "member": "starlink",
  "samples": [
    {
      "timestamp": "2024-01-01T00:00:00Z",
      "metrics": {
        "latency": 50.0,
        "loss": 0.1,
        "signal": -70.0
      },
      "score": {
        "instant": 85.0,
        "ewma": 82.0,
        "window_average": 80.0,
        "final": 83.0,
        "trend": "stable",
        "confidence": 0.9
      }
    }
  ]
}
```

**Example:**
```bash
ubus call starfail history '{"member": "starlink", "limit": 50, "hours": 12}'
```

#### `events`

Returns system events.

**Parameters:**
- `limit` (optional): Number of events to return (default: 100)
- `hours` (optional): Hours of history to return (default: 24)
- `type` (optional): Filter by event type

**Returns:**
```json
{
  "events": [
    {
      "timestamp": "2024-01-01T00:00:00Z",
      "type": "switch",
      "member": "starlink",
      "message": "Switched to starlink",
      "data": {
        "reason": "score_improvement",
        "previous_member": "cellular"
      }
    }
  ]
}
```

**Example:**
```bash
# Get all events
ubus call starfail events

# Get switch events only
ubus call starfail events '{"type": "switch", "limit": 10}'
```

#### `failover`

Manually triggers a failover to a specific member.

**Parameters:**
- `member`: Member name to switch to
- `reason` (optional): Reason for the switch

**Returns:**
```json
{
  "success": true,
  "message": "Switched to starlink",
  "previous_member": "cellular"
}
```

**Example:**
```bash
ubus call starfail failover '{"member": "starlink", "reason": "manual"}'
```

#### `restore`

Restores automatic failover mode.

**Parameters:** None

**Returns:**
```json
{
  "success": true,
  "message": "Automatic failover restored"
}
```

**Example:**
```bash
ubus call starfail restore
```

#### `recheck`

Forces a recheck of all members.

**Parameters:** None

**Returns:**
```json
{
  "success": true,
  "message": "Recheck completed",
  "members_checked": 3
}
```

**Example:**
```bash
ubus call starfail recheck
```

#### `setlog`

Sets the log level.

**Parameters:**
- `level`: Log level (debug, info, warn, error)

**Returns:**
```json
{
  "success": true,
  "message": "Log level set to debug",
  "previous_level": "info"
}
```

**Example:**
```bash
ubus call starfail setlog '{"level": "debug"}'
```

#### `config`

Returns the current configuration.

**Parameters:** None

**Returns:**
```json
{
  "config": {
    "log_level": "info",
    "poll_interval_ms": 1000,
    "decision_interval_ms": 5000,
    "retention_hours": 24,
    "max_ram_mb": 50,
    "predictive": false,
    "use_mwan3": true,
    "members": {
      "starlink": {
        "class": "starlink",
        "interface": "wan",
        "enabled": true,
        "priority": 100
      }
    }
  }
}
```

**Example:**
```bash
ubus call starfail config
```

#### `info`

Returns detailed system information.

**Parameters:** None

**Returns:**
```json
{
  "info": {
    "version": "1.0.0",
    "go_version": "1.22",
    "uptime": 3600,
    "start_time": "2024-01-01T00:00:00Z",
    "memory_usage": {
      "alloc_bytes": 1048576,
      "sys_bytes": 2097152,
      "heap_alloc_bytes": 524288
    },
    "statistics": {
      "total_switches": 5,
      "decision_cycles": 1000,
      "collection_errors": 2
    }
  }
}
```

**Example:**
```bash
ubus call starfail info
```

## HTTP Endpoints

The daemon provides HTTP endpoints for metrics and health monitoring.

### Metrics Endpoint

**URL:** `http://localhost:9090/metrics`

**Method:** GET

**Description:** Returns Prometheus-formatted metrics

**Example:**
```bash
curl http://localhost:9090/metrics
```

**Sample Output:**
```
# HELP starfail_member_score Current health score for each member
# TYPE starfail_member_score gauge
starfail_member_score{member="starlink",class="starlink",interface="wan"} 85.5

# HELP starfail_member_latency_ms Current latency for each member in milliseconds
# TYPE starfail_member_latency_ms gauge
starfail_member_latency_ms{member="starlink",class="starlink",interface="wan"} 50.0
```

### Health Endpoints

#### Basic Health Check

**URL:** `http://localhost:8080/health`

**Method:** GET

**Description:** Returns basic health status

**Example:**
```bash
curl http://localhost:8080/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00Z",
  "uptime": 3600,
  "version": "1.0.0"
}
```

#### Detailed Health Check

**URL:** `http://localhost:8080/health/detailed`

**Method:** GET

**Description:** Returns detailed health information

**Example:**
```bash
curl http://localhost:8080/health/detailed
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00Z",
  "uptime": 3600,
  "version": "1.0.0",
  "components": {
    "controller": {
      "status": "healthy",
      "message": "Controller is operational",
      "last_check": "2024-01-01T00:00:00Z",
      "uptime": 3600
    }
  },
  "members": [
    {
      "name": "starlink",
      "class": "starlink",
      "interface": "wan",
      "status": "excellent",
      "state": "eligible",
      "score": 85.5,
      "active": true,
      "last_seen": "2024-01-01T00:00:00Z",
      "uptime": 3600
    }
  ],
  "statistics": {
    "total_members": 3,
    "active_members": 1,
    "total_switches": 5,
    "total_samples": 1000,
    "total_events": 50
  },
  "memory": {
    "alloc_bytes": 1048576,
    "sys_bytes": 2097152,
    "heap_alloc_bytes": 524288
  }
}
```

#### Readiness Check

**URL:** `http://localhost:8080/health/ready`

**Method:** GET

**Description:** Returns readiness status for load balancers

**Example:**
```bash
curl http://localhost:8080/health/ready
```

**Response:**
```json
{"status":"ready"}
```

#### Liveness Check

**URL:** `http://localhost:8080/health/live`

**Method:** GET

**Description:** Returns liveness status for container orchestration

**Example:**
```bash
curl http://localhost:8080/health/live
```

**Response:**
```json
{"status":"alive"}
```

## Configuration

### UCI Configuration

The daemon uses UCI for configuration management. The configuration is stored in `/etc/config/starfail`.

#### Main Configuration

```bash
# Set log level
uci set starfail.main.log_level=debug

# Set poll interval
uci set starfail.main.poll_interval_ms=1000

# Set decision interval
uci set starfail.main.decision_interval_ms=5000

# Set retention period
uci set starfail.main.retention_hours=24

# Set memory limit
uci set starfail.main.max_ram_mb=50

# Enable predictive failover
uci set starfail.main.predictive=1

# Use mwan3 for interface control
uci set starfail.main.use_mwan3=1

# Enable metrics server
uci set starfail.main.metrics_listener=1
uci set starfail.main.metrics_port=9090

# Enable health server
uci set starfail.main.health_listener=1
uci set starfail.main.health_port=8080

# Commit changes
uci commit starfail
```

#### Member Configuration

```bash
# Configure Starlink member
uci set starfail.starlink=member
uci set starfail.starlink.class=starlink
uci set starfail.starlink.interface=wan
uci set starfail.starlink.enabled=1
uci set starfail.starlink.priority=100

# Configure cellular member
uci set starfail.cellular=member
uci set starfail.cellular.class=cellular
uci set starfail.cellular.interface=wwan0
uci set starfail.cellular.enabled=1
uci set starfail.cellular.priority=80

# Configure WiFi member
uci set starfail.wifi=member
uci set starfail.wifi.class=wifi
uci set starfail.wifi.interface=wlan0
uci set starfail.wifi.enabled=1
uci set starfail.wifi.priority=60

# Commit changes
uci commit starfail
```

### MQTT Configuration

```bash
# Enable MQTT
uci set starfail.mqtt.enabled=1

# Set broker
uci set starfail.mqtt.broker=localhost
uci set starfail.mqtt.port=1883

# Set credentials
uci set starfail.mqtt.username=starfail
uci set starfail.mqtt.password=password

# Set topic prefix
uci set starfail.mqtt.topic_prefix=starfail

# Set QoS
uci set starfail.mqtt.qos=1

# Commit changes
uci commit starfail
```

## Data Structures

### Member

```go
type Member struct {
    Name      string    `json:"name"`
    Interface string    `json:"interface"`
    Class     string    `json:"class"`
    Enabled   bool      `json:"enabled"`
    Priority  int       `json:"priority"`
    Created   time.Time `json:"created"`
}
```

### Metrics

```go
type Metrics struct {
    Timestamp     time.Time `json:"timestamp"`
    Latency       float64   `json:"latency"`
    Loss          float64   `json:"loss"`
    Jitter        float64   `json:"jitter"`
    Bandwidth     float64   `json:"bandwidth"`
    Signal        float64   `json:"signal"`
    Obstruction   float64   `json:"obstruction"`
    Outages       int       `json:"outages"`
    NetworkType   string    `json:"network_type"`
    Operator      string    `json:"operator"`
    Roaming       bool      `json:"roaming"`
    Connected     bool      `json:"connected"`
    LastSeen      time.Time `json:"last_seen"`
}
```

### Score

```go
type Score struct {
    Timestamp     time.Time `json:"timestamp"`
    Instant       float64   `json:"instant"`
    EWMA          float64   `json:"ewma"`
    WindowAverage float64   `json:"window_average"`
    Final         float64   `json:"final"`
    Trend         string    `json:"trend"`
    Confidence    float64   `json:"confidence"`
}
```

### Event

```go
type Event struct {
    Timestamp time.Time              `json:"timestamp"`
    Type      string                 `json:"type"`
    Member    string                 `json:"member"`
    Message   string                 `json:"message"`
    Data      map[string]interface{} `json:"data"`
}
```

## Error Handling

### ubus Error Responses

When a ubus call fails, it returns an error response:

```json
{
  "error": "Invalid member name",
  "code": 400
}
```

Common error codes:
- `400`: Bad Request - Invalid parameters
- `404`: Not Found - Member or resource not found
- `500`: Internal Server Error - Daemon error
- `503`: Service Unavailable - Daemon not ready

### HTTP Error Responses

HTTP endpoints return standard HTTP status codes:

- `200`: Success
- `400`: Bad Request
- `404`: Not Found
- `500`: Internal Server Error
- `503`: Service Unavailable

Error responses include a JSON body:

```json
{
  "error": "Service temporarily unavailable",
  "code": 503,
  "timestamp": "2024-01-01T00:00:00Z"
}
```

## Examples

### Complete Monitoring Script

```bash
#!/bin/bash

# Check daemon status
status=$(ubus call starfail status)
echo "Daemon Status: $status"

# Get active member
active_member=$(echo "$status" | jq -r '.active_member')
echo "Active Member: $active_member"

# Get metrics for active member
metrics=$(ubus call starfail metrics "{\"member\": \"$active_member\"}")
echo "Metrics: $metrics"

# Check health endpoint
health=$(curl -s http://localhost:8080/health)
echo "Health: $health"

# Get Prometheus metrics
prometheus_metrics=$(curl -s http://localhost:9090/metrics)
echo "Prometheus Metrics: $prometheus_metrics"
```

### Automated Failover Script

```bash
#!/bin/bash

# Check if current member is healthy
current_metrics=$(ubus call starfail metrics)
current_score=$(echo "$current_metrics" | jq -r '.metrics.starlink.score.final')

if (( $(echo "$current_score < 50" | bc -l) )); then
    echo "Current member score is low ($current_score), checking alternatives..."
    
    # Get all members
    members=$(ubus call starfail members)
    
    # Find best alternative
    best_member=$(echo "$members" | jq -r '.members[] | select(.enabled and .score > 70) | .name' | head -1)
    
    if [ -n "$best_member" ]; then
        echo "Switching to $best_member"
        ubus call starfail failover "{\"member\": \"$best_member\", \"reason\": \"low_score\"}"
    else
        echo "No suitable alternative found"
    fi
fi
```

### MQTT Integration Example

```python
import paho.mqtt.client as mqtt
import json

def on_connect(client, userdata, flags, rc):
    print("Connected to MQTT broker")
    client.subscribe("starfail/+/sample")
    client.subscribe("starfail/events/+")

def on_message(client, userdata, msg):
    data = json.loads(msg.payload.decode())
    print(f"Received {msg.topic}: {data}")

client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

client.connect("localhost", 1883, 60)
client.loop_forever()
```

### Prometheus Alerting Rules

```yaml
groups:
  - name: starfail
    rules:
      - alert: StarfailMemberDown
        expr: starfail_member_status == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Member {{ $labels.member }} is down"
          description: "Member {{ $labels.member }} has been down for more than 5 minutes"

      - alert: StarfailLowScore
        expr: starfail_member_score < 50
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Member {{ $labels.member }} has low score"
          description: "Member {{ $labels.member }} score is {{ $value }}"

      - alert: StarfailHighLatency
        expr: starfail_member_latency_ms > 200
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Member {{ $labels.member }} has high latency"
          description: "Member {{ $labels.member }} latency is {{ $value }}ms"
```

This API reference provides comprehensive documentation for integrating with the starfaild daemon. For additional examples and use cases, refer to the deployment guide and troubleshooting documentation.
