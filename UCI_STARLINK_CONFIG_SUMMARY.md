# UCI Starlink IP and Port Configuration - Implementation Summary

## Problem Identified

**Original Issues:**
❌ **No UCI configuration entries** for Starlink IP and Port
❌ **Hardcoded values** in the code:
- IP: `192.168.100.1` (hardcoded default)
- Port: `9200` (hardcoded in gRPC calls)
❌ **Inconsistent initialization** - Starlink collector initialized with empty string

## ✅ Solution Implemented

### 1. Added UCI Configuration Structure

**New StarlinkConfig in `pkg/uci/config.go`:**
```go
// StarlinkConfig represents Starlink-specific configuration
type StarlinkConfig struct {
    DishIP   string `uci:"dish_ip" default:"192.168.100.1"`
    DishPort int    `uci:"dish_port" default:"9200"`
}
```

**Added to main Config struct:**
```go
type Config struct {
    Main          MainConfig         `uci:"starfail.main"`
    Scoring       ScoringConfig      `uci:"starfail.scoring"`
    Starlink      StarlinkConfig     `uci:"starfail.starlink"`  // ← NEW
    // ... other sections
}
```

### 2. Updated UCI Configuration Example

**Enhanced `configs/starfail.example`:**
```uci
# Starlink-specific configuration
config starfail 'starlink'
    option dish_ip '192.168.100.1'
    option dish_port '9200'
```

### 3. Enhanced Starlink Collector

**Updated `pkg/collector/starlink.go`:**

**Before:**
```go
type StarlinkCollector struct {
    dishIP     string           // Only IP
    httpClient *http.Client
    runner     *retry.Runner
}

func NewStarlinkCollector(dishIP string) *StarlinkCollector
```

**After:**
```go
type StarlinkCollector struct {
    dishIP     string           // IP address
    dishPort   int              // ← NEW: Port number
    httpClient *http.Client
    runner     *retry.Runner
}

func NewStarlinkCollector(dishIP string, dishPort int) *StarlinkCollector
```

**Port Validation Added:**
```go
// Validate port range
if dishPort < 1 || dishPort > 65535 {
    dishPort = 9200 // Fallback to safe default
}
```

### 4. Fixed Hardcoded gRPC Port References

**Before:**
```go
fmt.Sprintf("%s:9200", s.dishIP),  // Hardcoded port
```

**After:**
```go
fmt.Sprintf("%s:%d", s.dishIP, s.dishPort),  // Configurable port
```

**All gRPC calls now use configurable port:**
- `getGRPCData()` - get_diagnostics call
- `getGRPCStatus()` - get_status call

### 5. Updated Main Daemon Initialization

**Enhanced `cmd/starfaild/main.go`:**

**Before:**
```go
registry.Register("starlink", collector.NewStarlinkCollector(""))  // Empty string
```

**After:**
```go
registry.Register("starlink", collector.NewStarlinkCollector(config.Starlink.DishIP, config.Starlink.DishPort))
```

### 6. Enhanced ubus config.set Support

**Added Starlink configuration to ubus API:**

**New configuration keys supported:**
- `starlink.dish_ip` - Starlink dish IP address
- `starlink.dish_port` - Starlink dish gRPC port

**Implementation in `pkg/ubus/server.go`:**
```go
// Support starlink configuration updates
if starlinkIface, ok := changes["starlink"]; ok {
    if starlinkMap, ok := starlinkIface.(map[string]interface{}); ok {
        if err := s.applyStarlinkConfigChanges(ctx, starlinkMap, applied); err != nil {
            return nil, fmt.Errorf("failed to apply starlink config changes: %w", err)
        }
        needsUCICommit = true
    }
}
```

**Validation Logic:**
```go
func (s *Server) applyStarlinkConfigChanges(ctx context.Context, changes map[string]interface{}, applied map[string]interface{}) error {
    // IP validation
    if v, ok := changes["dish_ip"]; ok {
        if dishIP, ok := v.(string); ok {
            if net.ParseIP(dishIP) == nil {
                return fmt.Errorf("dish_ip must be valid IP address")
            }
            applied["starlink.dish_ip"] = dishIP
        }
    }
    
    // Port validation
    if v, ok := changes["dish_port"]; ok {
        if port, ok := v.(float64); ok {
            portInt := int(port)
            if portInt < 1 || portInt > 65535 {
                return fmt.Errorf("dish_port must be between 1-65535")
            }
            applied["starlink.dish_port"] = portInt
        }
    }
}
```

## 🚀 Benefits Achieved

### ✅ Configurable Starlink Connection
- **UCI-managed** IP and port settings
- **Runtime configuration** via ubus API
- **Persistent storage** with UCI commit
- **Validation** for IP format and port ranges

### ✅ Production Flexibility
- **Non-standard networks** - Support for different Starlink dish IPs
- **Custom ports** - Support for modified gRPC ports
- **Remote management** - Configuration changes via ubus without reboot
- **Graceful defaults** - Safe fallbacks when invalid values provided

### ✅ Consistency Across All gRPC Calls
- **All gRPC operations** now use configurable port
- **No hardcoded values** remaining in the codebase
- **Centralized configuration** through UCI system

## Usage Examples

### Via UCI Configuration File
```uci
config starfail 'starlink'
    option dish_ip '192.168.100.5'    # Custom Starlink IP
    option dish_port '9201'            # Custom gRPC port
```

### Via ubus API
```bash
# Change Starlink dish IP
ubus call starfail config.set '{
    "starlink": {
        "dish_ip": "192.168.100.10"
    }
}'

# Change Starlink dish port
ubus call starfail config.set '{
    "starlink": {
        "dish_port": 9201
    }
}'
```

### Verification
```bash
# Check current configuration
ubus call starfail status

# Test connection with new settings
starfailctl test starlink
```

## Test Results

**All tests pass:**
```
✅ Build successful: go build ./cmd/starfaild
✅ Enhanced features test: TestEnhancedUbusConfigSet
✅ Full test suite: go test ./...
✅ Starlink collector graceful degradation: Working with configurable IP/port
```

**Verified functionality:**
- ✅ UCI configuration loading with Starlink section
- ✅ ubus config.set support for starlink.dish_ip and starlink.dish_port
- ✅ Starlink collector initialization with configuration values
- ✅ All gRPC calls use configurable port
- ✅ Input validation for IP addresses and port ranges
- ✅ Graceful fallbacks to safe defaults

The system now provides complete UCI configuration management for Starlink dish connectivity, eliminating hardcoded values and enabling flexible deployment scenarios!
