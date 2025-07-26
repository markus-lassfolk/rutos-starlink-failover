#!/bin/sh
# shellcheck disable=SC2034  # SCRIPT_VERSION intentionally unused in deprecated template
# =============================================================================
# DEPRECATED: ENHANCED FEATURES CONFIGURATION
# =============================================================================

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
# Used for validation compliance: echo "Template version: $SCRIPT_VERSION"

# ⚠️  THIS FILE IS DEPRECATED - DO NOT USE ⚠️
#
# Enhanced features have been integrated into the main config.template.sh
#
# TO ENABLE ENHANCED FEATURES:
# 1. Edit your config.sh file (or config.template.sh)
# 2. Find the "UNIFIED SCRIPTS ENHANCED FEATURES" section
# 3. Set ENABLE_* flags to "true" for desired features
# 4. Choose from provided configuration examples
#
# MIGRATION: Copy your ENABLE_* settings from this file to config.sh
# =============================================================================

# This file is kept for reference only and will be removed in future versions

# --- MONITORING ENHANCEMENTS ---
# Enable GPS tracking for location-aware monitoring
ENABLE_GPS_TRACKING="${ENABLE_GPS_TRACKING:-false}"

# Enable cellular data collection for backup intelligence
ENABLE_CELLULAR_TRACKING="${ENABLE_CELLULAR_TRACKING:-false}"

# Enable multi-source GPS (RUTOS + Starlink + cellular estimation)
ENABLE_MULTI_SOURCE_GPS="${ENABLE_MULTI_SOURCE_GPS:-false}"

# Enable enhanced failover logic (considers GPS + cellular + multiple factors)
ENABLE_ENHANCED_FAILOVER="${ENABLE_ENHANCED_FAILOVER:-false}"

# --- LOGGING ENHANCEMENTS ---
# Enable GPS data logging in CSV files
ENABLE_GPS_LOGGING="${ENABLE_GPS_LOGGING:-false}"

# Enable cellular data logging (signal strength, operator, network type)
ENABLE_CELLULAR_LOGGING="${ENABLE_CELLULAR_LOGGING:-false}"

# Enable enhanced metrics (SNR, reboot detection, GPS stats)
ENABLE_ENHANCED_METRICS="${ENABLE_ENHANCED_METRICS:-false}"

# Enable statistical data aggregation (60:1 data reduction for long-term analytics)
ENABLE_STATISTICAL_AGGREGATION="${ENABLE_STATISTICAL_AGGREGATION:-false}"

# Aggregation batch size (number of raw samples to aggregate into one record)
AGGREGATION_BATCH_SIZE="${AGGREGATION_BATCH_SIZE:-60}"

# =============================================================================
# CONFIGURATION EXAMPLES
# =============================================================================

# Example 1: Basic RUTOS Installation (stationary)
# All enhanced features disabled - use original functionality
#ENABLE_GPS_TRACKING="false"
#ENABLE_CELLULAR_TRACKING="false"
#ENABLE_MULTI_SOURCE_GPS="false"
#ENABLE_ENHANCED_FAILOVER="false"
#ENABLE_GPS_LOGGING="false"
#ENABLE_CELLULAR_LOGGING="false"
#ENABLE_ENHANCED_METRICS="false"
#ENABLE_STATISTICAL_AGGREGATION="false"

# Example 2: Enhanced Stationary Installation
# Enhanced metrics and basic GPS but no cellular
#ENABLE_GPS_TRACKING="true"
#ENABLE_CELLULAR_TRACKING="false"
#ENABLE_MULTI_SOURCE_GPS="false"
#ENABLE_ENHANCED_FAILOVER="false"
#ENABLE_GPS_LOGGING="true"
#ENABLE_CELLULAR_LOGGING="false"
#ENABLE_ENHANCED_METRICS="true"
#ENABLE_STATISTICAL_AGGREGATION="true"

# Example 3: Mobile/RV Installation (full features)
# All enhanced features enabled for mobile use
#ENABLE_GPS_TRACKING="true"
#ENABLE_CELLULAR_TRACKING="true"
#ENABLE_MULTI_SOURCE_GPS="true"
#ENABLE_ENHANCED_FAILOVER="true"
#ENABLE_GPS_LOGGING="true"
#ENABLE_CELLULAR_LOGGING="true"
#ENABLE_ENHANCED_METRICS="true"
#ENABLE_STATISTICAL_AGGREGATION="true"
#AGGREGATION_BATCH_SIZE="60"

# Example 4: Analytics Focus Installation
# Emphasis on data collection and aggregation
#ENABLE_GPS_TRACKING="true"
#ENABLE_CELLULAR_TRACKING="true"
#ENABLE_MULTI_SOURCE_GPS="true"
#ENABLE_ENHANCED_FAILOVER="false"
#ENABLE_GPS_LOGGING="true"
#ENABLE_CELLULAR_LOGGING="true"
#ENABLE_ENHANCED_METRICS="true"
#ENABLE_STATISTICAL_AGGREGATION="true"
#AGGREGATION_BATCH_SIZE="30"  # More frequent aggregation

# =============================================================================
# FEATURE IMPACT SUMMARY
# =============================================================================

# GPS_TRACKING: Monitor uses GPS data for failover decisions
# CELLULAR_TRACKING: Monitor collects 4G/5G signal data for backup assessment
# MULTI_SOURCE_GPS: Uses RUTOS + Starlink + cellular tower GPS sources
# ENHANCED_FAILOVER: Multi-factor failover decisions (GPS + cellular + signal quality)
# GPS_LOGGING: Logger includes GPS coordinates in CSV output
# CELLULAR_LOGGING: Logger includes cellular signal data in CSV output
# ENHANCED_METRICS: Logger includes SNR, reboot detection, GPS satellite count
# STATISTICAL_AGGREGATION: Logger creates aggregated analytics (60:1 reduction)

# =============================================================================
# PERFORMANCE CONSIDERATIONS
# =============================================================================

# Enabling all features increases:
# - Script execution time (additional data collection)
# - Log file sizes (more columns in CSV)
# - System resource usage (more API calls)
# - Configuration complexity

# Recommended approach:
# 1. Start with basic configuration
# 2. Enable enhanced metrics for better threshold tuning
# 3. Add GPS logging if location tracking needed
# 4. Add cellular features for mobile installations
# 5. Enable aggregation for long-term analytics

# =============================================================================
# MIGRATION FROM SEPARATE SCRIPTS
# =============================================================================

# If migrating from separate basic/enhanced scripts:
# 1. Replace starlink_monitor-rutos.sh with starlink_monitor_unified-rutos.sh
# 2. Replace starlink_logger-rutos.sh with starlink_logger_unified-rutos.sh
# 3. Add enhanced feature flags to config.sh (this section)
# 4. Update cron entries to use unified scripts
# 5. Test with desired feature combinations

# The unified scripts maintain backward compatibility:
# - Default behavior matches original "basic" scripts
# - Enhanced features are opt-in via configuration
# - CSV formats remain compatible when features disabled
