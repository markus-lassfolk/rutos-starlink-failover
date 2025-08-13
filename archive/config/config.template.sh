#!/bin/sh
# Enhanced Starlink Solution Configuration Template
# This file contains default settings and will be intelligently merged with existing user settings
# PERSISTENT STORAGE: This configuration survives firmware upgrades
#
# USAGE: Simply edit the values below to customize your installation
# Format: VARIABLE_NAME="your_value"

# === INSTALLATION PATHS (PERSISTENT) ===
# Note: These will be dynamically set during deployment based on detected persistent storage
export INSTALL_BASE_DIR="/usr/local/starlink"
export CONFIG_DIR="/usr/local/starlink/config"
export SCRIPTS_DIR="/usr/local/starlink/bin"
export LOG_DIR="/usr/local/starlink/logs"
export STATE_DIR="/usr/local/starlink/state"
export LIB_DIR="/usr/local/starlink/lib"

# === BASIC CONFIGURATION ===
export STARLINK_IP="192.168.100.1"          # Starlink dish IP address
export STARLINK_PORT="9200"                 # Starlink gRPC API port
export RUTOS_IP="192.168.80.1"             # RUTOS router IP address

# === NETWORK CONFIGURATION ===
export MWAN_IFACE="wan"                     # MWAN3 interface name for Starlink
export MWAN_MEMBER="member1"                # MWAN3 member name
export METRIC_GOOD="1"                      # Route metric when connection is good
export METRIC_BAD="10"                      # Route metric when connection is poor

# === MONITORING THRESHOLDS ===
export LATENCY_THRESHOLD="600"              # Latency threshold in milliseconds
export PACKET_LOSS_THRESHOLD="10"          # Packet loss threshold in percentage
export OBSTRUCTION_THRESHOLD="10"          # Obstruction threshold in percentage

# === FEATURE TOGGLES ===
export ENABLE_STARLINK_MONITORING="true"   # Enable Starlink quality monitoring
export ENABLE_GPS="true"                   # Enable GPS location tracking
export ENABLE_AZURE="false"                # Enable Azure integration
export ENABLE_PUSHOVER="false"             # Enable Pushover notifications

# === AZURE CONFIGURATION ===
export AZURE_ENDPOINT=""                   # Azure Log Analytics endpoint (if enabled)

# === PUSHOVER CONFIGURATION ===
export PUSHOVER_USER_KEY=""                # Pushover user key (if enabled)
export PUSHOVER_API_TOKEN=""               # Pushover API token (if enabled)

# === INTELLIGENT MONITORING CONFIGURATION ===
export MONITORING_MODE="daemon"            # Monitoring mode: daemon, hybrid, or cron
export DAEMON_AUTOSTART="true"             # Start monitoring daemon at boot
export MONITORING_INTERVAL="60"            # Main monitoring interval in seconds
export QUICK_CHECK_INTERVAL="30"           # Quick check interval in seconds
export DEEP_ANALYSIS_INTERVAL="300"        # Deep analysis interval in seconds

# === INTELLIGENT LOGGING CONFIGURATION ===
export HIGH_FREQ_INTERVAL="1"              # 1 second for unlimited connections
export LOW_FREQ_INTERVAL="60"             # 60 seconds for limited data connections
export GPS_COLLECTION_INTERVAL="60"       # GPS collection interval in seconds
export AGGREGATION_WINDOW="60"            # Statistical aggregation window in seconds
export PERCENTILES="50,90,95,99"          # Percentiles to calculate for statistics
export LOG_RETENTION_HOURS="24"           # Hours to keep detailed logs
export ARCHIVE_RETENTION_DAYS="7"         # Days to keep compressed archives

# === LOGGING DIRECTORIES (PERSISTENT) ===
export LOG_BASE_DIR=""                    # Base log directory (set automatically)
export METRICS_LOG_DIR=""                 # Metrics log directory (set automatically)
export GPS_LOG_DIR=""                     # GPS log directory (set automatically)
export AGGREGATED_LOG_DIR=""              # Aggregated data directory (set automatically)
export ARCHIVE_LOG_DIR=""                 # Archive directory (set automatically)

# === CONNECTION TYPE PATTERNS ===
export CELLULAR_INTERFACES_PATTERN="^mob[0-9]s[0-9]a[0-9]$|^wwan[0-9]*$"    # Cellular interface patterns
export SATELLITE_INTERFACES_PATTERN="^starlink$"                             # Satellite interface patterns
export UNLIMITED_INTERFACES_PATTERN="^eth[0-9]*$|^wifi[0-9]*$"              # Unlimited connection patterns
export VPN_INTERFACES_PATTERN="^tun[0-9]*$|^tap[0-9]*$|^vpn[0-9]*$"        # VPN interface patterns

# === INTELLIGENT MONITORING THRESHOLDS ===
export LATENCY_WARNING_THRESHOLD="200"     # Latency warning threshold in milliseconds
export LATENCY_CRITICAL_THRESHOLD="500"    # Latency critical threshold in milliseconds
export PACKET_LOSS_WARNING_THRESHOLD="2"   # Packet loss warning threshold in percentage
export PACKET_LOSS_CRITICAL_THRESHOLD="5"  # Packet loss critical threshold in percentage

# === PERFORMANCE ANALYSIS SETTINGS ===
export HISTORICAL_ANALYSIS_WINDOW="1800"  # Historical analysis window in seconds
export TREND_ANALYSIS_SAMPLES="10"        # Number of samples for trend analysis
export MAX_METRIC_ADJUSTMENT="50"         # Maximum metric adjustment allowed
export MAX_ADJUSTMENTS_PER_CYCLE="3"      # Maximum adjustments per monitoring cycle
export ADJUSTMENT_COOLDOWN="120"          # Cooldown period between adjustments in seconds

# === BINARY PATHS ===
# Note: These will be dynamically set during deployment
export GRPCURL_CMD=""                     # Path to grpcurl binary (set automatically)
export JQ_CMD=""                          # Path to jq binary (set automatically)

# === DEVELOPMENT/DEBUG ===
export DEBUG="0"                          # Enable debug logging (0=off, 1=on)
export DRY_RUN="0"                        # Dry-run mode (0=off, 1=on)
export RUTOS_TEST_MODE="0"                # Test mode (0=off, 1=on)

# === CONNECTION-SPECIFIC MONITORING SETTINGS ===

# === STARLINK ENHANCED MONITORING ===
export STARLINK_API_ENDPOINTS="192.168.100.1:9200 192.168.1.1:9200 dishy.starlink.com:9200"  # Starlink API endpoints to try
export STARLINK_API_TIMEOUT="8"                    # Starlink API timeout in seconds
export STARLINK_COLLECT_ADVANCED="1"               # Collect advanced metrics (dish heating, obstructions, etc.) (0=off, 1=on)
export STARLINK_COLLECT_SIGNAL_QUALITY="1"         # Collect SNR, RSSI, and signal quality metrics (0=off, 1=on)
export STARLINK_COLLECT_THROUGHPUT="1"             # Collect downlink/uplink throughput metrics (0=off, 1=on)
export STARLINK_OBSTRUCTION_CHECK="1"              # Monitor for obstructions and dish alignment (0=off, 1=on)

# === STARLINK PREDICTIVE FAILOVER SETTINGS ===
export STARLINK_ENABLE_PREDICTIVE_FAILOVER="1"     # Enable intelligent predictive failover (0=off, 1=on)
export STARLINK_SNR_DROP_THRESHOLD="0.5"           # SNR drop threshold for predictive failover
export STARLINK_LATENCY_SPIKE_THRESHOLD="100"      # Latency spike threshold (ms) for immediate failover
export STARLINK_PACKET_LOSS_SPIKE_THRESHOLD="0.02" # Packet loss spike threshold (2%) for immediate failover
export STARLINK_COLLECT_HISTORY="1"                # Collect historical performance data (0=off, 1=on)
export STARLINK_HISTORY_SAMPLES="3"                # Number of history samples to analyze for trends
export STARLINK_FAILBACK_STABILITY_CHECKS="120"    # Stability checks required before failback (120 * 2s = 4min)
export STARLINK_SATELLITE_HANDOFF_THRESHOLD="0.5"  # Seconds to next satellite for proactive failover
export STARLINK_TREND_ANALYSIS_WINDOW="10"         # Number of samples for SNR trend analysis
export STARLINK_OBSTRUCTION_HISTORY_CHECK="1"      # Check obstruction history for failback decisions (0=off, 1=on)

# === CELLULAR ENHANCED MONITORING ===
export CELLULAR_COLLECT_LTE="1"                    # Collect LTE-specific metrics (RSRP, RSRQ) (0=off, 1=on)
export CELLULAR_COLLECT_THERMAL="1"                # Monitor modem temperature for thermal throttling (0=off, 1=on)
export CELLULAR_COLLECT_OPERATOR="1"               # Collect carrier and network technology info (0=off, 1=on)
export CELLULAR_COLLECT_REGISTRATION="1"           # Monitor network registration status (0=off, 1=on)
export CELLULAR_COLLECT_DATA_SESSION="1"           # Monitor PDP context and data session status (0=off, 1=on)
export CELLULAR_SIGNAL_THRESHOLD="20"              # Minimum acceptable signal strength percentage
export CELLULAR_THERMAL_THRESHOLD="70"             # Temperature threshold for thermal warnings (°C)
export CELLULAR_AT_TIMEOUT="5"                     # AT command timeout in seconds

# === WIREGUARD ENHANCED MONITORING ===
export WIREGUARD_HANDSHAKE_TIMEOUT="300"           # Seconds before considering handshake stale
export WIREGUARD_COLLECT_TRANSFER="1"              # Collect transfer statistics (received/sent data) (0=off, 1=on)
export WIREGUARD_COLLECT_PEERS="1"                 # Monitor peer connection status (0=off, 1=on)
export WIREGUARD_KEEPALIVE_CHECK="1"               # Monitor persistent keepalive status (0=off, 1=on)
export WIREGUARD_ENDPOINT_CHECK="1"                # Verify endpoint connectivity (0=off, 1=on)

# === WIRELESS ENHANCED MONITORING ===
export WIRELESS_COLLECT_SIGNAL="1"                 # Collect wireless signal strength and quality (0=off, 1=on)
export WIRELESS_COLLECT_CHANNEL="1"                # Monitor channel information and interference (0=off, 1=on)
export WIRELESS_SIGNAL_THRESHOLD="-70"             # Minimum acceptable wireless signal strength (dBm)

# === ETHERNET ENHANCED MONITORING ===
export ETHERNET_COLLECT_SPEED="1"                  # Monitor link speed and duplex mode (0=off, 1=on)
export ETHERNET_COLLECT_ERRORS="1"                 # Collect interface error statistics (0=off, 1=on)

# === CONNECTION TYPE MONITORING FREQUENCY ===
export MONITOR_FREQ_UNLIMITED="3"                  # Ping count for unlimited connections (wan, ethernet, wifi)
export MONITOR_FREQ_LIMITED="1"                    # Ping count for limited connections (cellular)
export MONITOR_FREQ_VPN="2"                        # Ping count for VPN connections
export MONITOR_FREQ_SATELLITE="2"                  # Ping count for satellite connections

# === PING TARGET CONFIGURATION ===
export PING_TARGET_PRIMARY="8.8.8.8"               # Primary connectivity test target
export PING_TARGET_SECONDARY="1.1.1.1"             # Secondary connectivity test target (fallback)
export PING_TARGET_STARLINK="192.168.100.1"        # Starlink-specific ping target
export PING_TIMEOUT="3"                            # Ping timeout in seconds

# === NETWORK STATISTICS COLLECTION ===
export COLLECT_INTERFACE_STATS="1"                 # Collect /proc/net/dev statistics (0=off, 1=on)
export COLLECT_MWAN_STATUS="1"                     # Collect MWAN3 status information (0=off, 1=on)
export COLLECT_ROUTE_METRICS="1"                   # Monitor route metrics and changes (0=off, 1=on)
export STATS_AGGREGATION_INTERVAL="60"             # Statistics aggregation interval in seconds

# === PREDICTIVE MULTI-WAN STABILITY SYSTEM ===
# Unified scoring system for intelligent failover decisions based on stability scores

# === STABILITY SCORING CONFIGURATION ===
export SCORE_CALCULATION_INTERVAL="60"             # How often to calculate stability scores (seconds)
export ENABLE_STABILITY_SCORING="1"                # Enable unified stability scoring system (0=off, 1=on)
export STABILITY_HISTORY_SAMPLES="10"              # Number of historical samples for trend analysis

# === POLLING INTERVALS BY CONNECTION TYPE ===
export STARLINK_POLL_INTERVAL="2"                  # Starlink polling interval (seconds) - frequent for real-time
export CELLULAR_POLL_INTERVAL="60"                 # Cellular polling interval (seconds) - less frequent for data usage
export WIFI_POLL_INTERVAL="15"                     # WiFi polling interval (seconds)
export ETHERNET_POLL_INTERVAL="5"                  # Ethernet polling interval (seconds) 
export VPN_POLL_INTERVAL="30"                      # VPN polling interval (seconds)
export DEFAULT_POLL_INTERVAL="30"                  # Default polling interval for unknown connection types

# === KILL SWITCH THRESHOLDS ===
# Values that immediately set stability score to 0 regardless of other metrics
export KILL_SWITCH_PING_LOSS="20"                  # Packet loss % that kills connection score
export KILL_SWITCH_LATENCY="2000"                  # Latency (ms) that kills connection score
export KILL_SWITCH_FRACTION_OBSTRUCTED="80"        # Starlink obstruction % that kills score

# === DATA STORAGE CONFIGURATION ===
export DATA_DIR="/usr/local/starlink/data"         # Directory for metrics and state files
export METRICS_RETENTION_HOURS="48"                # Hours to keep detailed metrics
export HISTORY_RETENTION_DAYS="7"                  # Days to keep historical data
export ENABLE_METRICS_COMPRESSION="1"              # Compress old metrics files (0=off, 1=on)

# === CONNECTION SCORING SYSTEM (Legacy - kept for compatibility) ===
# Intelligent connection scoring for failover decisions based on multiple weighted metrics

# === SCORING WEIGHTS (must add up to 100) ===
export SCORE_WEIGHT_LATENCY="15"                   # Weight for latency metric (lower latency = higher score)
export SCORE_WEIGHT_PACKET_LOSS="15"               # Weight for packet loss metric (lower loss = higher score)
export SCORE_WEIGHT_BANDWIDTH="10"                 # Weight for bandwidth metric (higher bandwidth = higher score)
export SCORE_WEIGHT_UPTIME="15"                    # Weight for uptime/reliability metric
export SCORE_WEIGHT_STABILITY="10"                 # Weight for connection stability (low jitter)
export SCORE_WEIGHT_CONNECTION_STATE="10"          # Weight for connection state (connected vs degraded)
export SCORE_WEIGHT_SIGNAL_STRENGTH="10"           # Weight for signal strength (wireless connections)
export SCORE_WEIGHT_DATA_USAGE="8"                 # Weight for data usage considerations (unlimited vs limited)
export SCORE_WEIGHT_PRIORITY="7"                   # Weight for manual priority settings

# === SCORING PARAMETERS ===
export MAX_CONNECTION_SCORE="100"                  # Maximum possible connection score
export MIN_CONNECTION_SCORE="0"                    # Minimum possible connection score
export SCORE_FAILOVER_THRESHOLD="10"               # Minimum score difference required for failover
export SCORE_FAILBACK_THRESHOLD="15"               # Minimum score difference required for failback
export SCORE_CALCULATION_INTERVAL="60"             # How often to calculate connection scores (seconds)

# === PERFORMANCE BENCHMARKS FOR SCORING ===
export EXCELLENT_LATENCY_MS="20"                   # Latency considered excellent (20ms)
export POOR_LATENCY_MS="500"                       # Latency considered poor (500ms)
export EXCELLENT_PACKET_LOSS_PCT="0"               # Packet loss considered excellent (0%)
export POOR_PACKET_LOSS_PCT="5"                    # Packet loss considered poor (5%)

# === CONNECTION PRIORITY SETTINGS ===
export PRIORITY_WAN="90"                           # Priority score for WAN connections
export PRIORITY_CELLULAR="70"                      # Priority score for cellular connections
export PRIORITY_VPN="60"                           # Priority score for VPN connections
export PRIORITY_WIFI="80"                          # Priority score for WiFi connections
export PRIORITY_DEFAULT="50"                       # Default priority for unknown connection types

# === CONNECTION QUALITY THRESHOLDS (Legacy) ===
export QUALITY_EXCELLENT_LATENCY="50"              # Latency threshold for excellent quality (ms)
export QUALITY_GOOD_LATENCY="150"                  # Latency threshold for good quality (ms)
export QUALITY_POOR_LATENCY="300"                  # Latency threshold for poor quality (ms)
export QUALITY_EXCELLENT_SIGNAL="80"               # Signal strength threshold for excellent quality (%)
export QUALITY_GOOD_SIGNAL="60"                    # Signal strength threshold for good quality (%)
export QUALITY_POOR_SIGNAL="30"                    # Signal strength threshold for poor quality (%)

# === FIRMWARE UPGRADE RECOVERY ===
# After firmware upgrades, run the recovery script to restore functionality
export RECOVERY_SCRIPT=""                 # Recovery script path (set automatically)

# === SYSTEM INFORMATION ===
# These will be set automatically during deployment
export CONFIG_VERSION="3.0.0"            # Configuration file version
export TEMPLATE_VERSION="3.0.0"          # Template version
export INSTALLATION_DATE=""               # Installation timestamp (set automatically)
export LAST_UPDATE_DATE=""                # Last update timestamp (set automatically)
