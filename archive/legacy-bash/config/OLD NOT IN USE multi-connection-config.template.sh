#!/bin/sh
# =============================================================================
# MULTI-CONNECTION MONITORING CONFIGURATION TEMPLATE
# Configuration for monitoring multiple cellular modems, WiFi, and Ethernet connections
# =============================================================================

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="3.0.0"

# =============================================================================
# MULTI-CONNECTION MONITORING SETTINGS
# =============================================================================

# Enable comprehensive multi-connection monitoring
ENABLE_MULTI_CONNECTION_MONITORING=true

# Performance comparison threshold (% improvement needed to trigger failover)
PERFORMANCE_COMPARISON_THRESHOLD=20

# Test configuration
CONNECTION_TEST_HOST="8.8.8.8" # Host to test all connections
CONNECTION_TEST_TIMEOUT=15     # Timeout in seconds for connection tests

# =============================================================================
# MULTI-CELLULAR MODEM CONFIGURATION
# Support for up to 8 cellular modems (RUTX50 can support 8 modems)
# =============================================================================

# Enable multi-cellular support
ENABLE_MULTI_CELLULAR=true

# Cellular modem interfaces (comma-separated list)
# Default RUTOS interfaces: mob1s1a1, mob2s1a1, mob3s1a1, mob4s1a1, etc.
CELLULAR_MODEMS="mob1s1a1,mob2s1a1,mob3s1a1,mob4s1a1"

# Cellular priority factors for ranking (affects scoring)
# Options: signal, latency, operator, network_type
CELLULAR_PRIORITY_ORDER="signal,latency,operator"

# =============================================================================
# GENERIC INTERNET CONNECTION CONFIGURATION
# Support for WiFi bridges, Ethernet connections, etc.
# =============================================================================

# Enable generic connection monitoring
ENABLE_GENERIC_CONNECTIONS=true

# Generic connection interfaces and their types
# Format: interface1,interface2,interface3
GENERIC_CONNECTIONS="wlan0,eth2,br-guest"

# Connection types corresponding to interfaces above
# Options: wifi, ethernet, bridge, vpn, etc.
GENERIC_CONNECTION_TYPES="wifi,ethernet,bridge"

# =============================================================================
# CONNECTION PRIORITY AND FAILOVER CONFIGURATION
# =============================================================================

# Global connection priority order (determines failover preference)
# Options: starlink, ethernet, wifi, cellular
CONNECTION_PRIORITY_ORDER="starlink,ethernet,wifi,cellular"

# Enable intelligent health scoring
ENABLE_CONNECTION_HEALTH_SCORING=true

# Health score weights (must total 100)
# Format: factor:weight,factor:weight
HEALTH_SCORE_WEIGHTS="latency:40,loss:30,signal:20,type:10"

# =============================================================================
# EXAMPLE CONFIGURATIONS FOR DIFFERENT SCENARIOS
# =============================================================================

# Example 1: Camping with WiFi bridge + multiple cellular modems
# GENERIC_CONNECTIONS="wlan0-campsite"
# GENERIC_CONNECTION_TYPES="wifi"
# CELLULAR_MODEMS="mob1s1a1,mob2s1a1"
# CONNECTION_PRIORITY_ORDER="starlink,wifi,cellular"

# Example 2: Marine/RV with Ethernet uplink + cellular array
# GENERIC_CONNECTIONS="eth2-marina"
# GENERIC_CONNECTION_TYPES="ethernet"
# CELLULAR_MODEMS="mob1s1a1,mob2s1a1,mob3s1a1,mob4s1a1"
# CONNECTION_PRIORITY_ORDER="starlink,ethernet,cellular"

# Example 3: Maximum redundancy with all connection types
# GENERIC_CONNECTIONS="wlan0,eth2,br-guest,tun0"
# GENERIC_CONNECTION_TYPES="wifi,ethernet,bridge,vpn"
# CELLULAR_MODEMS="mob1s1a1,mob2s1a1,mob3s1a1,mob4s1a1,mob5s1a1,mob6s1a1"
# CONNECTION_PRIORITY_ORDER="starlink,ethernet,vpn,wifi,cellular"

# =============================================================================
# BACKWARD COMPATIBILITY SETTINGS
# =============================================================================

# Legacy dual-connection settings (maintained for compatibility)
ENABLE_DUAL_CONNECTION_MONITORING=true      # Enable for legacy configs
SECONDARY_CONNECTION_TYPE="cellular"        # Used by legacy functions
SECONDARY_INTERFACE="mob1s1a1"              # Primary cellular interface
SECONDARY_TEST_HOST="$CONNECTION_TEST_HOST" # Redirect to unified setting

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

# Connection quality thresholds
LATENCY_THRESHOLD=150   # milliseconds
PACKET_LOSS_THRESHOLD=2 # percentage
JITTER_THRESHOLD=20     # milliseconds

# Signal strength thresholds for cellular connections
CELLULAR_SIGNAL_EXCELLENT=-70 # dBm
CELLULAR_SIGNAL_GOOD=-80      # dBm
CELLULAR_SIGNAL_FAIR=-90      # dBm
CELLULAR_SIGNAL_POOR=-100     # dBm

# WiFi connection quality expectations
WIFI_LATENCY_GOOD=30  # milliseconds (local network)
WIFI_LATENCY_FAIR=100 # milliseconds (congested)

# Ethernet connection quality expectations
ETHERNET_LATENCY_EXCELLENT=10 # milliseconds (direct connection)
ETHERNET_LATENCY_GOOD=50      # milliseconds (switched network)

# =============================================================================
# LOGGING AND MONITORING
# =============================================================================

# Enable detailed connection logging
ENABLE_CONNECTION_PERFORMANCE_LOGGING=true

# Connection log files
CONNECTION_PERFORMANCE_LOG="${LOG_DIR}/connection_performance.csv"
MULTI_CONNECTION_DECISIONS_LOG="${LOG_DIR}/multi_connection_decisions.csv"

# Performance monitoring interval
CONNECTION_MONITORING_INTERVAL=60 # seconds between comprehensive tests

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Notify on connection changes
NOTIFY_ON_CONNECTION_CHANGE=true

# Notify on new connections discovered
NOTIFY_ON_CONNECTION_DISCOVERY=true

# Notification message templates
CONNECTION_CHANGE_MESSAGE="Failover: %primary% → %secondary% (Score: %old_score% → %new_score%)"
CONNECTION_DISCOVERY_MESSAGE="New connection discovered: %interface% (%type%) - Score: %score%"
