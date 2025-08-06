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
export MWAN_IFACE="starlink"                # MWAN3 interface name for Starlink
export MWAN_MEMBER="starlink_member"        # MWAN3 member name
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

# === FIRMWARE UPGRADE RECOVERY ===
# After firmware upgrades, run the recovery script to restore functionality
export RECOVERY_SCRIPT=""                 # Recovery script path (set automatically)

# === SYSTEM INFORMATION ===
# These will be set automatically during deployment
export CONFIG_VERSION="3.0.0"            # Configuration file version
export TEMPLATE_VERSION="3.0.0"          # Template version
export INSTALLATION_DATE=""               # Installation timestamp (set automatically)
export LAST_UPDATE_DATE=""                # Last update timestamp (set automatically)
