#!/bin/sh
# Enhanced Starlink Solution Configuration Template
# This file contains default settings and will be intelligently merged with existing user settings
# PERSISTENT STORAGE: This configuration survives firmware upgrades

# === INSTALLATION PATHS (PERSISTENT) ===
# Note: These will be dynamically set during deployment based on detected persistent storage
export INSTALL_BASE_DIR="${INSTALL_BASE_DIR:-/usr/local/starlink}"
export CONFIG_DIR="${CONFIG_DIR:-/usr/local/starlink/config}"
export SCRIPTS_DIR="${SCRIPTS_DIR:-/usr/local/starlink/bin}"
export LOG_DIR="${LOG_DIR:-/usr/local/starlink/logs}"
export STATE_DIR="${STATE_DIR:-/usr/local/starlink/state}"
export LIB_DIR="${LIB_DIR:-/usr/local/starlink/lib}"

# === BASIC CONFIGURATION ===
export STARLINK_IP="${STARLINK_IP:-192.168.100.1}"
export STARLINK_PORT="${STARLINK_PORT:-9200}"
export RUTOS_IP="${RUTOS_IP:-192.168.80.1}"

# === NETWORK CONFIGURATION ===
export MWAN_IFACE="${MWAN_IFACE:-starlink}"
export MWAN_MEMBER="${MWAN_MEMBER:-starlink_member}"
export METRIC_GOOD="${METRIC_GOOD:-1}"
export METRIC_BAD="${METRIC_BAD:-10}"

# === MONITORING THRESHOLDS ===
export LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-600}"
export PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD:-10}"
export OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD:-10}"

# === FEATURE TOGGLES ===
export ENABLE_STARLINK_MONITORING="${ENABLE_STARLINK_MONITORING:-true}"
export ENABLE_GPS="${ENABLE_GPS:-true}"
export ENABLE_AZURE="${ENABLE_AZURE:-false}"
export ENABLE_PUSHOVER="${ENABLE_PUSHOVER:-false}"

# === AZURE CONFIGURATION ===
export AZURE_ENDPOINT="${AZURE_ENDPOINT:-}"

# === PUSHOVER CONFIGURATION ===
export PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-}"
export PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-}"

# === INTELLIGENT MONITORING CONFIGURATION ===
export MONITORING_MODE="${MONITORING_MODE:-daemon}"
export DAEMON_AUTOSTART="${DAEMON_AUTOSTART:-true}"
export MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"
export QUICK_CHECK_INTERVAL="${QUICK_CHECK_INTERVAL:-30}"
export DEEP_ANALYSIS_INTERVAL="${DEEP_ANALYSIS_INTERVAL:-300}"

# === INTELLIGENT LOGGING CONFIGURATION ===
export HIGH_FREQ_INTERVAL="${HIGH_FREQ_INTERVAL:-1}"           # 1 second for unlimited connections
export LOW_FREQ_INTERVAL="${LOW_FREQ_INTERVAL:-60}"          # 60 seconds for limited data connections
export GPS_COLLECTION_INTERVAL="${GPS_COLLECTION_INTERVAL:-60}"    # GPS every minute
export AGGREGATION_WINDOW="${AGGREGATION_WINDOW:-60}"         # 60-second aggregation windows
export PERCENTILES="${PERCENTILES:-50,90,95,99}"       # Percentiles to calculate
export LOG_RETENTION_HOURS="${LOG_RETENTION_HOURS:-24}"        # 24 hours of detailed logs
export ARCHIVE_RETENTION_DAYS="${ARCHIVE_RETENTION_DAYS:-7}"      # 7 days of compressed archives

# === LOGGING DIRECTORIES (PERSISTENT) ===
export LOG_BASE_DIR="${LOG_BASE_DIR:-${LOG_DIR}}"
export METRICS_LOG_DIR="${METRICS_LOG_DIR:-${LOG_DIR}/metrics}"
export GPS_LOG_DIR="${GPS_LOG_DIR:-${LOG_DIR}/gps}"
export AGGREGATED_LOG_DIR="${AGGREGATED_LOG_DIR:-${LOG_DIR}/aggregated}"
export ARCHIVE_LOG_DIR="${ARCHIVE_LOG_DIR:-${LOG_DIR}/archive}"

# === CONNECTION TYPE PATTERNS ===
export CELLULAR_INTERFACES_PATTERN="${CELLULAR_INTERFACES_PATTERN:-^mob[0-9]s[0-9]a[0-9]$|^wwan[0-9]*$}"
export SATELLITE_INTERFACES_PATTERN="${SATELLITE_INTERFACES_PATTERN:-^starlink$}"
export UNLIMITED_INTERFACES_PATTERN="${UNLIMITED_INTERFACES_PATTERN:-^eth[0-9]*$|^wifi[0-9]*$}"
export VPN_INTERFACES_PATTERN="${VPN_INTERFACES_PATTERN:-^tun[0-9]*$|^tap[0-9]*$|^vpn[0-9]*$}"

# === INTELLIGENT MONITORING THRESHOLDS ===
export LATENCY_WARNING_THRESHOLD="${LATENCY_WARNING_THRESHOLD:-200}"
export LATENCY_CRITICAL_THRESHOLD="${LATENCY_CRITICAL_THRESHOLD:-500}"
export PACKET_LOSS_WARNING_THRESHOLD="${PACKET_LOSS_WARNING_THRESHOLD:-2}"
export PACKET_LOSS_CRITICAL_THRESHOLD="${PACKET_LOSS_CRITICAL_THRESHOLD:-5}"

# === PERFORMANCE ANALYSIS SETTINGS ===
export HISTORICAL_ANALYSIS_WINDOW="${HISTORICAL_ANALYSIS_WINDOW:-1800}"
export TREND_ANALYSIS_SAMPLES="${TREND_ANALYSIS_SAMPLES:-10}"
export MAX_METRIC_ADJUSTMENT="${MAX_METRIC_ADJUSTMENT:-50}"
export MAX_ADJUSTMENTS_PER_CYCLE="${MAX_ADJUSTMENTS_PER_CYCLE:-3}"
export ADJUSTMENT_COOLDOWN="${ADJUSTMENT_COOLDOWN:-120}"

# === BINARY PATHS ===
# Note: These will be dynamically set during deployment
export GRPCURL_CMD="${GRPCURL_CMD:-${SCRIPTS_DIR}/grpcurl}"
export JQ_CMD="${JQ_CMD:-${SCRIPTS_DIR}/jq}"

# === DEVELOPMENT/DEBUG ===
export DEBUG="${DEBUG:-0}"
export DRY_RUN="${DRY_RUN:-0}"
export RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# === FIRMWARE UPGRADE RECOVERY ===
# After firmware upgrades, run the recovery script to restore functionality
export RECOVERY_SCRIPT="${RECOVERY_SCRIPT:-${SCRIPTS_DIR}/recover-after-firmware-upgrade.sh}"

# === SYSTEM INFORMATION ===
# These will be set automatically during deployment
export CONFIG_VERSION="${CONFIG_VERSION:-3.0.0}"
export TEMPLATE_VERSION="${TEMPLATE_VERSION:-3.0.0}"
export INSTALLATION_DATE="${INSTALLATION_DATE:-}"
export LAST_UPDATE_DATE="${LAST_UPDATE_DATE:-}"
