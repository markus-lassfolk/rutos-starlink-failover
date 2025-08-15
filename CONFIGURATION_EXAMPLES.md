# 📋 RUTOS Starlink Failover - Configuration Examples

This document provides real-world configuration examples for different deployment scenarios.

## 🚗 Mobile/Vehicle Deployment

### Use Case
- Vehicle with Starlink dish
- Cellular backup (multiple SIMs)
- Frequent movement with obstructions
- Data cost consciousness

### Configuration
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    
    # Faster polling for mobile environment
    option poll_interval_ms '1000'
    
    # Higher switch margin for stability
    option switch_margin '15'
    
    # Enable predictive logic for obstructions
    option predictive '1'
    
    # Conservative data usage
    option data_cap_mode 'conservative'
    
    # Tighter failure detection
    option fail_threshold_loss '3'
    option fail_threshold_latency '1000'
    option fail_min_duration_s '8'
    
    # Slower restoration (avoid ping-pong)
    option restore_threshold_loss '0.5'
    option restore_threshold_latency '600'
    option restore_min_duration_s '45'
    
    # Notifications
    option pushover_token 'your_mobile_token'
    option pushover_user 'your_user_key'

config starfail 'scoring'
    # Adjust weights for mobile environment
    option weight_latency '20'           # Reduce latency importance
    option weight_loss '35'              # Increase loss importance
    option weight_jitter '15'            # Moderate jitter weight
    option weight_obstruction '25'       # High obstruction weight
    
    # Mobile-friendly thresholds
    option latency_ok_ms '80'            # Higher acceptable latency
    option latency_bad_ms '2000'         # Very high bad threshold
    option loss_ok_pct '0'               # Zero loss still ideal
    option loss_bad_pct '8'              # Higher loss tolerance

config starfail 'starlink'
    option dish_ip '192.168.100.1'
    option dish_port '9200'

# Member priorities for mobile
config member 'starlink_dish'
    option detect 'auto'
    option class 'starlink'
    option weight '100'                  # Prefer when available
    option min_uptime_s '45'             # Longer stabilization
    option cooldown_s '30'               # Longer cooldown

config member 'cellular_primary'
    option detect 'auto'
    option class 'cellular'
    option weight '75'                   # Good backup
    option metered '1'                   # Mark as metered
    option min_uptime_s '15'             # Faster activation
    option cooldown_s '15'

config member 'cellular_roaming'
    option detect 'auto'
    option class 'cellular'
    option weight '65'                   # Lower priority (expensive)
    option prefer_roaming '1'            # Use for roaming
    option metered '1'
    option min_uptime_s '20'
    option cooldown_s '20'
```

## 🏠 Fixed Residential Installation

### Use Case
- Fixed Starlink installation
- Fiber/cable backup available
- Stable environment with predictable patterns
- Cost-effective operation

### Configuration
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    
    # Slower polling for fixed installation
    option poll_interval_ms '2000'
    
    # Lower margin for responsiveness
    option switch_margin '8'
    
    # Balanced data usage
    option data_cap_mode 'balanced'
    
    # Standard failure detection
    option fail_threshold_loss '5'
    option fail_threshold_latency '1200'
    option fail_min_duration_s '10'
    
    # Quick restoration
    option restore_threshold_loss '1'
    option restore_threshold_latency '800'
    option restore_min_duration_s '25'
    
    # Home automation integration
    option mqtt_broker 'mqtt://homeassistant.local:1883'
    option mqtt_topic 'starfail/status'

config starfail 'scoring'
    # Optimize for fixed installation
    option weight_latency '30'           # Higher latency importance
    option weight_loss '25'              # Standard loss weight
    option weight_jitter '20'            # Higher jitter sensitivity
    option weight_obstruction '15'       # Lower obstruction weight
    
    # Tighter thresholds for quality
    option latency_ok_ms '40'            # Low latency expectation
    option latency_bad_ms '1200'         # Standard bad threshold
    option jitter_ok_ms '3'              # Low jitter tolerance
    option jitter_bad_ms '150'           # Moderate jitter limit

config starfail 'starlink'
    option dish_ip '192.168.100.1'
    option dish_port '9200'

# Member configuration for residential
config member 'starlink_dish'
    option detect 'auto'
    option class 'starlink'
    option weight '90'                   # High but not absolute priority
    option min_uptime_s '20'             # Quick activation
    option cooldown_s '15'

config member 'fiber_backup'
    option detect 'auto'
    option class 'lan'                   # Treat as LAN connection
    option weight '85'                   # High-quality backup
    option min_uptime_s '10'             # Very quick activation
    option cooldown_s '10'

config member 'cellular_emergency'
    option detect 'auto'
    option class 'cellular'
    option weight '60'                   # Emergency only
    option metered '1'
    option min_uptime_s '30'             # Slow to activate
    option cooldown_s '60'               # Long cooldown
```

## 🏢 Business/Office Installation

### Use Case
- Critical uptime requirements
- Multiple backup options
- Cost management
- SLA compliance

### Configuration
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    
    # Moderate polling for business use
    option poll_interval_ms '1500'
    
    # Conservative switching
    option switch_margin '12'
    
    # Aggressive monitoring for uptime
    option data_cap_mode 'aggressive'
    option predictive '1'
    
    # Strict failure detection
    option fail_threshold_loss '3'
    option fail_threshold_latency '800'
    option fail_min_duration_s '5'
    
    # Quick restoration
    option restore_threshold_loss '0.5'
    option restore_threshold_latency '400'
    option restore_min_duration_s '15'
    
    # Business notifications
    option pushover_token 'business_app_token'
    option pushover_user 'it_team_user'

config starfail 'notifications'
    option enable '1'
    option rate_limit_minutes '3'        # More frequent alerts
    option priority_threshold 'warning'  # Lower threshold
    
    # Multiple notification channels
    option pushover_enabled '1'
    option pushover_token 'business_token'
    option pushover_user 'it_team_key'
    
    option email_enabled '1'
    option email_smtp_server 'smtp.company.com:587'
    option email_from 'network@company.com'
    option email_to 'it-alerts@company.com'
    
    option webhook_enabled '1'
    option webhook_url 'https://monitoring.company.com/webhook/starfail'

config starfail 'scoring'
    # Business-optimized weights
    option weight_latency '35'           # Latency critical for VoIP/video
    option weight_loss '30'              # Loss affects quality
    option weight_jitter '20'            # Jitter critical for real-time
    option weight_obstruction '10'       # Less critical
    
    # Strict business thresholds
    option latency_ok_ms '30'            # Very low latency requirement
    option latency_bad_ms '600'          # Strict limit
    option loss_ok_pct '0'               # Zero tolerance
    option loss_bad_pct '2'              # Very low tolerance
    option jitter_ok_ms '2'              # Very low jitter
    option jitter_bad_ms '50'            # Strict jitter limit

# Business member priorities
config member 'starlink_primary'
    option detect 'auto'
    option class 'starlink'
    option weight '95'                   # High priority
    option min_uptime_s '15'
    option cooldown_s '10'

config member 'fiber_primary'
    option detect 'auto'
    option class 'lan'
    option weight '90'                   # Alternative primary
    option min_uptime_s '10'
    option cooldown_s '10'

config member 'cellular_backup'
    option detect 'auto'
    option class 'cellular'
    option weight '70'                   # Reliable backup
    option metered '1'
    option min_uptime_s '20'
    option cooldown_s '15'

config member 'backup_fiber'
    option detect 'auto'
    option class 'lan'
    option weight '65'                   # Secondary backup
    option min_uptime_s '15'
    option cooldown_s '15'
```

## 🧪 Development/Testing Environment

### Use Case
- Development and testing
- Frequent configuration changes
- Debug monitoring
- Non-production use

### Configuration
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    
    # Test mode - no actual changes
    option dry_run '1'
    
    # Verbose logging
    option log_level 'debug'
    
    # Fast polling for testing
    option poll_interval_ms '500'
    
    # Low margin for frequent switches
    option switch_margin '5'
    
    # Aggressive testing
    option data_cap_mode 'aggressive'
    option predictive '1'
    
    # Quick failure detection for testing
    option fail_threshold_loss '2'
    option fail_threshold_latency '500'
    option fail_min_duration_s '3'
    
    # Quick restoration for testing
    option restore_threshold_loss '0.5'
    option restore_threshold_latency '300'
    option restore_min_duration_s '5'
    
    # Enable all monitoring
    option metrics_listener '1'
    option health_listener '1'

config starfail 'notifications'
    option enable '1'
    option rate_limit_minutes '1'        # Allow frequent test alerts
    option priority_threshold 'info'     # All events
    
    option pushover_enabled '1'
    option pushover_token 'test_token'
    option pushover_user 'dev_user'

config starfail 'scoring'
    # Testing-optimized weights
    option weight_latency '25'
    option weight_loss '25'
    option weight_jitter '25'
    option weight_obstruction '25'       # Equal weights for testing
    
    # Loose thresholds for testing
    option latency_ok_ms '100'
    option latency_bad_ms '3000'
    option loss_ok_pct '0'
    option loss_bad_pct '15'

# Test members with fast switching
config member 'test_starlink'
    option detect 'auto'
    option class 'starlink'
    option weight '80'                   # Not absolute priority
    option min_uptime_s '5'              # Very fast activation
    option cooldown_s '5'                # Very fast cooldown

config member 'test_cellular'
    option detect 'auto'
    option class 'cellular'
    option weight '75'
    option metered '1'
    option min_uptime_s '5'
    option cooldown_s '5'

config member 'test_wifi'
    option detect 'auto'
    option class 'wifi'
    option weight '70'
    option min_uptime_s '5'
    option cooldown_s '5'
```

## 🛥️ Marine/Remote Installation

### Use Case
- Remote location with limited connectivity
- High latency tolerance
- Cost-sensitive data usage
- Reliability over speed

### Configuration
```uci
config starfail 'main'
    option enable '1'
    option use_mwan3 '1'
    
    # Slower polling for remote/battery
    option poll_interval_ms '3000'
    
    # High margin for stability
    option switch_margin '20'
    
    # Very conservative data usage
    option data_cap_mode 'conservative'
    option predictive '1'
    
    # Relaxed failure detection
    option fail_threshold_loss '10'
    option fail_threshold_latency '3000'
    option fail_min_duration_s '30'
    
    # Slow restoration (avoid costs)
    option restore_threshold_loss '2'
    option restore_threshold_latency '2000'
    option restore_min_duration_s '120'
    
    # Emergency notifications only
    option pushover_token 'marine_token'
    option pushover_user 'boat_user'

config starfail 'notifications'
    option enable '1'
    option rate_limit_minutes '30'       # Very infrequent alerts
    option priority_threshold 'critical' # Only critical events
    
    option pushover_enabled '1'
    option pushover_token 'marine_token'
    option pushover_user 'emergency_key'

config starfail 'scoring'
    # Marine-optimized weights
    option weight_latency '15'           # Latency less important
    option weight_loss '40'              # Loss most important
    option weight_jitter '10'            # Jitter less critical
    option weight_obstruction '30'       # Weather affects Starlink
    
    # Marine-friendly thresholds
    option latency_ok_ms '200'           # High latency acceptable
    option latency_bad_ms '5000'         # Very high tolerance
    option loss_ok_pct '1'               # Some loss acceptable
    option loss_bad_pct '20'             # High loss tolerance

config starfail 'sampling'
    option enable '1'
    option base_interval_ms '5000'       # Very slow sampling
    option fast_interval_ms '2000'       # Slow fast sampling
    option slow_interval_ms '10000'      # Very slow stable sampling
    option data_cap_aware '1'
    option adaptation_factor '0.05'      # Slow adaptation

# Marine member configuration
config member 'starlink_marine'
    option detect 'auto'
    option class 'starlink'
    option weight '100'                  # Primary when available
    option min_uptime_s '120'            # Long stabilization
    option cooldown_s '180'              # Long cooldown

config member 'cellular_satellite'
    option detect 'auto'
    option class 'cellular'
    option weight '60'                   # Expensive backup
    option metered '1'
    option min_uptime_s '60'
    option cooldown_s '300'              # Very long cooldown

config member 'wifi_marina'
    option detect 'disable'             # Manual enable only
    option class 'wifi'
    option weight '80'                   # Good when available
    option min_uptime_s '30'
    option cooldown_s '60'
```

## 🎯 Configuration Guidelines

### Choosing Poll Intervals

| Environment | poll_interval_ms | Reasoning |
|-------------|------------------|-----------|
| Mobile/Vehicle | 1000 | Fast response to changing conditions |
| Fixed Residential | 2000 | Balance responsiveness and resources |
| Business | 1500 | Quick response for uptime SLA |
| Development | 500 | Fast testing and validation |
| Marine/Remote | 3000+ | Conserve power and data |

### Tuning Switch Margin

| Use Case | switch_margin | Effect |
|----------|---------------|--------|
| Stable environment | 5-8 | Responsive switching |
| Mobile/unstable | 15-20 | Prevent ping-pong |
| Business critical | 10-12 | Balance stability/responsiveness |
| Testing | 5 | Frequent switches for testing |

### Weight Distribution Guidelines

| Priority | Starlink | Fiber/Cable | Cellular | WiFi | LAN |
|----------|----------|-------------|----------|------|-----|
| Speed-focused | 100 | 95 | 70 | 60 | 40 |
| Reliability-focused | 90 | 100 | 80 | 60 | 50 |
| Cost-conscious | 95 | 85 | 60 | 70 | 75 |
| Balanced | 90 | 85 | 75 | 65 | 50 |

### Data Cap Mode Effects

| Mode | Cellular Sampling | Ping Frequency | Starlink Polling |
|------|------------------|----------------|------------------|
| conservative | Minimal | Reduced | Standard |
| balanced | Moderate | Standard | Standard |
| aggressive | Full | Full | Frequent |

For complete configuration reference, see [FEATURES_AND_CONFIGURATION.md](FEATURES_AND_CONFIGURATION.md)
