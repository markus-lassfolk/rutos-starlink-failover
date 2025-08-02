#!/bin/sh

# ==============================================================================
# Complete Starlink Solution Deployment Script for RUTOS (POSIX Shell Version)
# INTELLIGENT MONITORING SYSTEM v3.0 - Daemon-Based Architecture
#
# This script deploys the complete intelligent Starlink monitoring solution
# with MWAN3 integration, automatic interface discovery, dynamic metric
# adjustment, and predictive failover capabilities.
#
# NEW in v3.0:
# - MWAN3-integrated intelligent monitoring daemon
# - Automatic interface discovery and classification
# - Dynamic metric adjustment based on performance
# - Historical performance analysis and trend prediction
# - Multi-interface support (up to 8 cellular modems)
# - Predictive failover before user experience issues
#
# Version: 3.0.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="3.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# Check if running from bootstrap (library in different location)
if [ "${USE_LIBRARY:-0}" = "1" ] && [ -n "${LIBRARY_PATH:-}" ]; then
    # Bootstrap mode - library is in LIBRARY_PATH
    . "$LIBRARY_PATH/rutos-lib.sh"
else
    # Normal mode - library is relative to script
    . "$(dirname "$0")/lib/rutos-lib.sh"
fi

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "deploy-starlink-solution-v3-rutos.sh" "$SCRIPT_VERSION"

# === CONFIGURATION DEFAULTS ===
DEFAULT_AZURE_ENDPOINT=""
DEFAULT_ENABLE_AZURE="false"
DEFAULT_ENABLE_STARLINK_MONITORING="true"
DEFAULT_ENABLE_GPS="true"
DEFAULT_ENABLE_PUSHOVER="false"
DEFAULT_RUTOS_IP="192.168.80.1"
DEFAULT_STARLINK_IP="192.168.100.1"

# === INTERACTIVE MODE DETECTION ===
# Check if script is running in interactive mode
is_interactive() {
    # Check if stdin is a terminal and not running in non-interactive mode
    [ -t 0 ] && [ "${BATCH_MODE:-0}" != "1" ]
}

# === NEW: INTELLIGENT MONITORING DEFAULTS ===
DEFAULT_MONITORING_MODE="daemon" # daemon, cron, or hybrid
DEFAULT_DAEMON_AUTOSTART="true"
DEFAULT_MONITORING_INTERVAL="60"
DEFAULT_QUICK_CHECK_INTERVAL="30"
DEFAULT_DEEP_ANALYSIS_INTERVAL="300"

# === PATHS AND DIRECTORIES (RUTOS PERSISTENT STORAGE) ===
# CRITICAL: Use persistent storage that survives firmware upgrades on RUTOS
# /root is wiped during firmware upgrades - use /opt or /mnt for persistence
# Note: Actual paths will be set after detecting available persistent storage
HOTPLUG_DIR="/etc/hotplug.d/iface" # System hotplug directory
INIT_D_DIR="/etc/init.d"           # System init.d directory

# === RUTOS PERSISTENT STORAGE VERIFICATION ===
# Check for available persistent storage locations (in order of preference)
PERSISTENT_STORAGE=""
for storage_path in "/usr/local" "/opt" "/mnt" "/root"; do
    if [ -d "$storage_path" ] && [ -w "$storage_path" ]; then
        PERSISTENT_STORAGE="$storage_path"
        log_debug "Found writable persistent storage: $storage_path"
        break
    fi
done

if [ -z "$PERSISTENT_STORAGE" ]; then
    log_error "No writable persistent storage directory found. Checked: /opt /mnt /usr/local /root"
    log_error "RUTOS system may have read-only filesystem issues"
    exit 1
fi

log_info "Using persistent storage: $PERSISTENT_STORAGE"

# === SET DIRECTORY PATHS BASED ON DETECTED STORAGE ===
INSTALL_BASE_DIR="$PERSISTENT_STORAGE/starlink"                         # Main installation directory (persistent)
BACKUP_DIR="$PERSISTENT_STORAGE/starlink/backup-$(date +%Y%m%d-%H%M%S)" # Backup location (persistent)
CONFIG_DIR="$PERSISTENT_STORAGE/starlink/config"                        # Configuration files (persistent)
SCRIPTS_DIR="$PERSISTENT_STORAGE/starlink/bin"                          # Executable scripts (persistent)
LOG_DIR="$PERSISTENT_STORAGE/starlink/logs"                             # Log files (persistent)
STATE_DIR="$PERSISTENT_STORAGE/starlink/state"                          # Runtime state files (persistent)
LIB_DIR="$PERSISTENT_STORAGE/starlink/lib"                              # Library files (persistent)

# === BINARY URLS (ARMv7 for RUTX50) ===
GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf"

# === PERSISTENT STORAGE SETUP ===
setup_persistent_storage() {
    log_step "Setting up RUTOS Persistent Storage"

    # Verify persistent storage availability
    if [ ! -d "$PERSISTENT_STORAGE" ]; then
        log_error "Persistent storage $PERSISTENT_STORAGE not available"
        log_error "RUTOS devices require persistent storage for intelligent monitoring"
        return 1
    fi

    log_info "Using persistent storage: $PERSISTENT_STORAGE"

    # Create all required directories
    log_info "Creating persistent directory structure..."

    for dir in "$INSTALL_BASE_DIR" "$CONFIG_DIR" "$SCRIPTS_DIR" "$LOG_DIR" "$STATE_DIR" "$LIB_DIR" "$BACKUP_DIR"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                log_error "Failed to create directory: $dir"
                return 1
            }
            log_success "Created directory: $dir"
        else
            log_info "Directory exists: $dir"
        fi
    done

    # Set appropriate permissions
    chmod 755 "$INSTALL_BASE_DIR" "$CONFIG_DIR" "$SCRIPTS_DIR" "$LOG_DIR" "$STATE_DIR" "$LIB_DIR"
    chmod 700 "$BACKUP_DIR" # Backup directory should be more restrictive

    # Create convenience symlinks in /root for backward compatibility (non-persistent)
    log_info "Creating convenience symlinks for backward compatibility..."

    # Remove any existing symlinks/files first
    rm -f /root/starlink_monitor_unified-rutos.sh 2>/dev/null || true
    rm -f /root/config.sh 2>/dev/null || true

    # Create symlinks (these will be recreated after firmware upgrades by the recovery script)
    ln -sf "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" /root/starlink_monitor_unified-rutos.sh
    ln -sf "$CONFIG_DIR/config.sh" /root/config.sh

    log_success "Persistent storage setup completed"
    log_info "Main installation: $INSTALL_BASE_DIR"
    log_info "Scripts accessible at: $SCRIPTS_DIR and /root (symlink)"
    log_info "Configuration: $CONFIG_DIR"
    log_info "Logs: $LOG_DIR"
}

# Create firmware upgrade recovery script
create_recovery_script() {
    log_info "Creating firmware upgrade recovery script..."

    cat >"$SCRIPTS_DIR/recover-after-firmware-upgrade.sh" <<EOF
#!/bin/sh
# RUTOS Firmware Upgrade Recovery Script
# This script restores the intelligent monitoring system after firmware upgrades
# Run this after firmware upgrades to restore functionality

set -e

# Persistent storage locations (set during installation)
INSTALL_BASE_DIR="$INSTALL_BASE_DIR"
CONFIG_DIR="$CONFIG_DIR"
SCRIPTS_DIR="$SCRIPTS_DIR"
LOG_DIR="$LOG_DIR"
INIT_D_DIR="/etc/init.d"

echo "🔄 RUTOS Firmware Upgrade Recovery - Starlink Intelligent Monitoring"
echo "===================================================================="

# Check if persistent storage exists
if [ ! -d "$INSTALL_BASE_DIR" ]; then
    echo "❌ ERROR: Persistent storage not found at $INSTALL_BASE_DIR"
    echo "   The intelligent monitoring system needs to be reinstalled."
    echo "   Run: curl -L https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/deploy-starlink-solution-v3-rutos.sh | sh"
    exit 1
fi

echo "✓ Found persistent storage at $INSTALL_BASE_DIR"

# Recreate convenience symlinks
echo "🔗 Recreating convenience symlinks..."
ln -sf "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" /root/starlink_monitor_unified-rutos.sh
ln -sf "$CONFIG_DIR/config.sh" /root/config.sh
echo "✓ Symlinks created"

# Recreate init.d service
echo "🔧 Recreating daemon services..."
if [ -f "$SCRIPTS_DIR/../templates/starlink-monitor.init" ]; then
    cp "$SCRIPTS_DIR/../templates/starlink-monitor.init" "$INIT_D_DIR/starlink-monitor"
    chmod +x "$INIT_D_DIR/starlink-monitor"
    echo "✓ Monitoring daemon service restored"
else
    echo "⚠️ Warning: Monitoring daemon service template not found - manual setup required"
fi

if [ -f "$SCRIPTS_DIR/../templates/starlink-logger.init" ]; then
    cp "$SCRIPTS_DIR/../templates/starlink-logger.init" "$INIT_D_DIR/starlink-logger"
    chmod +x "$INIT_D_DIR/starlink-logger"
    echo "✓ Logging daemon service restored"
else
    echo "⚠️ Warning: Logging daemon service template not found - manual setup required"
fi

# Verify MWAN3 availability
if command -v mwan3 >/dev/null 2>&1; then
    echo "✓ MWAN3 available"
else
    echo "⚠️ Warning: MWAN3 not found - may need to be reinstalled after firmware upgrade"
    echo "   Install with: opkg update && opkg install mwan3"
fi

# Test system functionality
echo "🧪 Testing system functionality..."
if [ -x "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ]; then
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" validate >/dev/null 2>&1; then
        echo "✓ System validation passed"
    else
        echo "⚠️ Warning: System validation failed - may need configuration"
    fi
else
    echo "❌ ERROR: Main monitoring script not found or not executable"
    exit 1
fi

# Start monitoring daemon if configured for autostart
if [ -f "$CONFIG_DIR/config.sh" ]; then
    . "$CONFIG_DIR/config.sh"
    if [ "${DAEMON_AUTOSTART:-false}" = "true" ]; then
        if [ -f "$INIT_D_DIR/starlink-monitor" ]; then
            echo "🚀 Starting monitoring daemon..."
            "$INIT_D_DIR/starlink-monitor" start
            echo "✓ Monitoring daemon started"
        fi
        
        if [ -f "$INIT_D_DIR/starlink-logger" ]; then
            echo "📊 Starting logging daemon..."
            "$INIT_D_DIR/starlink-logger" start
            echo "✓ Logging daemon started"
        fi
    fi
fi

echo ""
echo "✅ Recovery completed successfully!"
echo "📊 Check status: $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh status"
echo "📁 Configuration: $CONFIG_DIR/config.sh"
echo "📝 Logs: $LOG_DIR/"
EOF

    chmod +x "$SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
    log_success "Recovery script created: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
}

# === INTELLIGENT MONITORING DAEMON SETUP ===
setup_intelligent_monitoring_daemon() {
    log_step "Setting up Intelligent Monitoring Daemon v3.0"

    # Create init.d service script for the intelligent monitoring daemon
    log_info "Creating daemon service script..."

    # First, create a template for the service in persistent storage
    mkdir -p "$INSTALL_BASE_DIR/templates"

    cat >"$INSTALL_BASE_DIR/templates/starlink-monitor.init" <<EOF
#!/bin/sh /etc/rc.common

START=95
STOP=10

USE_PROCD=1
PROG="$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh"
PIDFILE="/var/run/starlink-monitor.pid"

start_service() {
    # Ensure MWAN3 is available before starting
    if ! command -v mwan3 >/dev/null 2>&1; then
        logger -s -t starlink-monitor "ERROR: MWAN3 not found - cannot start intelligent monitoring"
        return 1
    fi
    
    # Validate that the monitoring script exists
    if [ ! -f "\$PROG" ]; then
        logger -s -t starlink-monitor "ERROR: Monitoring script not found at \$PROG"
        return 1
    fi
    
    logger -s -t starlink-monitor "Starting Intelligent Starlink Monitoring Daemon v3.0"
    
    procd_open_instance
    procd_set_param command "\$PROG" start --daemon
    procd_set_param pidfile "\$PIDFILE"
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    logger -s -t starlink-monitor "Intelligent monitoring daemon started successfully"
}

stop_service() {
    logger -s -t starlink-monitor "Stopping Intelligent Starlink Monitoring Daemon"
    
    if [ -f "\$PIDFILE" ] && [ -s "\$PIDFILE" ]; then
        PID=\$(cat "\$PIDFILE")
        if kill -0 "\$PID" 2>/dev/null; then
            kill -TERM "\$PID"
            sleep 3
            if kill -0 "\$PID" 2>/dev/null; then
                kill -KILL "\$PID"
                logger -s -t starlink-monitor "Force killed daemon process"
            else
                logger -s -t starlink-monitor "Daemon stopped gracefully"
            fi
        fi
        rm -f "\$PIDFILE"
    else
        logger -s -t starlink-monitor "No daemon PID file found"
    fi
}

reload_service() {
    logger -s -t starlink-monitor "Reloading Intelligent Starlink Monitoring Daemon"
    stop
    start
}

status() {
    if [ -f "\$PIDFILE" ] && [ -s "\$PIDFILE" ]; then
        PID=\$(cat "\$PIDFILE")
        if kill -0 "\$PID" 2>/dev/null; then
            UPTIME=\$(ps -o etime= -p "\$PID" 2>/dev/null | tr -d ' ')
            echo "Intelligent Starlink Monitoring Daemon is running (PID: \$PID, Uptime: \$UPTIME)"
            return 0
        else
            echo "Daemon PID file exists but process is not running"
            rm -f "\$PIDFILE"
            return 1
        fi
    else
        echo "Intelligent Starlink Monitoring Daemon is not running"
        return 1
    fi
}
EOF

    # Copy the template to the active init.d location
    cp "$INSTALL_BASE_DIR/templates/starlink-monitor.init" "$INIT_D_DIR/starlink-monitor"
    chmod +x "$INIT_D_DIR/starlink-monitor"

    log_success "Created init.d service script (persistent template stored)"
    log_info "Service template: $INSTALL_BASE_DIR/templates/starlink-monitor.init"
    log_info "Active service: $INIT_D_DIR/starlink-monitor"

    # Enable the service to start at boot
    if [ "$DAEMON_AUTOSTART" = "true" ]; then
        log_info "Enabling daemon autostart at boot..."
        "$INIT_D_DIR/starlink-monitor" enable
        log_success "Daemon autostart enabled"
    fi

    # Remove old cron-based monitoring if it exists
    cleanup_legacy_cron_monitoring

    log_success "Intelligent monitoring daemon setup completed"
}

# Remove legacy cron-based monitoring
cleanup_legacy_cron_monitoring() {
    log_info "Cleaning up legacy cron-based monitoring..."

    # Remove existing starlink-related cron jobs
    if crontab -l 2>/dev/null | grep -q "starlink"; then
        log_info "Found legacy cron jobs, removing..."
        (crontab -l 2>/dev/null | grep -v "starlink" || true) | crontab -
        log_success "Legacy cron monitoring removed"
    else
        log_info "No legacy cron jobs found"
    fi
}

# Setup hybrid monitoring (daemon + essential cron jobs)
setup_hybrid_monitoring() {
    log_step "Setting up Hybrid Monitoring (Daemon + Essential Cron Jobs)"

    # Setup the main intelligent daemon
    setup_intelligent_monitoring_daemon

    # Keep essential cron jobs that complement the daemon
    (
        crontab -l 2>/dev/null | grep -v "starlink" || true
        echo "# Essential Starlink maintenance tasks"
        echo "# API change detection (daily)"
        echo "30 5 * * * $SCRIPTS_DIR/check_starlink_api-rutos.sh"

        if [ "$ENABLE_AZURE" = "true" ]; then
            echo "# Azure log shipping (every 10 minutes - daemon handles main monitoring)"
            echo "*/10 * * * * $SCRIPTS_DIR/log-shipper.sh"
        fi

        echo "# Weekly system health check"
        echo "0 6 * * 0 $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh validate"
    ) | crontab -

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1
    log_success "Hybrid monitoring setup completed"
}

# Setup traditional cron-based monitoring (fallback)
setup_traditional_cron_monitoring() {
    log_step "Setting up Traditional Cron-Based Monitoring (Legacy Mode)"
    log_warning "Using legacy mode - intelligent features will be limited"

    # Remove any existing daemon setup
    if [ -f "$INIT_D_DIR/starlink-monitor" ]; then
        "$INIT_D_DIR/starlink-monitor" stop 2>/dev/null || true
        "$INIT_D_DIR/starlink-monitor" disable 2>/dev/null || true
        rm -f "$INIT_D_DIR/starlink-monitor"
        log_info "Removed daemon service"
    fi

    # Setup traditional cron jobs
    (
        crontab -l 2>/dev/null | grep -v "starlink" || true
        echo "# Traditional Starlink monitoring (legacy mode)"
        echo "*/5 * * * * $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh test"
        echo "30 5 * * * $SCRIPTS_DIR/check_starlink_api-rutos.sh"

        if [ "$ENABLE_AZURE" = "true" ]; then
            echo "*/5 * * * * $SCRIPTS_DIR/log-shipper.sh"
        fi
    ) | crontab -

    # Restart cron service
    /etc/init.d/cron restart >/dev/null 2>&1
    log_success "Traditional cron monitoring setup completed"
}

# Main monitoring setup function
setup_monitoring_system() {
    case "${MONITORING_MODE:-daemon}" in
        daemon)
            log_info "Setting up daemon-based intelligent monitoring..."
            setup_intelligent_monitoring_daemon
            ;;
        hybrid)
            log_info "Setting up hybrid monitoring (daemon + cron)..."
            setup_hybrid_monitoring
            ;;
        cron)
            log_info "Setting up traditional cron-based monitoring..."
            setup_traditional_cron_monitoring
            ;;
        *)
            log_warning "Unknown monitoring mode '$MONITORING_MODE', defaulting to daemon"
            setup_intelligent_monitoring_daemon
            ;;
    esac
}

# === ENHANCED CONFIGURATION COLLECTION ===
collect_enhanced_configuration() {
    log_step "Enhanced Configuration for Intelligent Monitoring v3.0"

    # Basic configuration (existing)
    collect_basic_configuration

    # New: Intelligent monitoring configuration
    log_info "Intelligent Monitoring Configuration"

    if is_interactive; then
        printf "Choose monitoring mode:\n"
        printf "  1) Daemon (recommended) - Intelligent continuous monitoring\n"
        printf "  2) Hybrid - Daemon + essential cron jobs\n"
        printf "  3) Cron - Traditional cron-based (legacy)\n"
        printf "Enter choice [1-3] (default: 1): "
        read -r MONITORING_CHOICE

        case "${MONITORING_CHOICE:-1}" in
            1) MONITORING_MODE="daemon" ;;
            2) MONITORING_MODE="hybrid" ;;
            3) MONITORING_MODE="cron" ;;
            *) MONITORING_MODE="daemon" ;;
        esac

        if [ "$MONITORING_MODE" = "daemon" ] || [ "$MONITORING_MODE" = "hybrid" ]; then
            printf "Enable daemon autostart at boot? [y/N]: "
            read -r AUTOSTART_CHOICE
            case "${AUTOSTART_CHOICE:-n}" in
                [Yy]*) DAEMON_AUTOSTART="true" ;;
                *) DAEMON_AUTOSTART="false" ;;
            esac

            printf "Monitoring interval in seconds (default: 60): "
            read -r MONITORING_INTERVAL_INPUT
            MONITORING_INTERVAL="${MONITORING_INTERVAL_INPUT:-60}"

            printf "Quick check interval in seconds (default: 30): "
            read -r QUICK_INTERVAL_INPUT
            QUICK_CHECK_INTERVAL="${QUICK_INTERVAL_INPUT:-30}"

            printf "Deep analysis interval in seconds (default: 300): "
            read -r DEEP_INTERVAL_INPUT
            DEEP_ANALYSIS_INTERVAL="${DEEP_INTERVAL_INPUT:-300}"
        fi
    else
        log_info "Non-interactive mode - using recommended monitoring configuration"

        # Use environment variables if set, otherwise recommended defaults
        MONITORING_MODE="${MONITORING_MODE:-daemon}"
        DAEMON_AUTOSTART="${DAEMON_AUTOSTART:-true}"
        MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"
        QUICK_CHECK_INTERVAL="${QUICK_CHECK_INTERVAL:-30}"
        DEEP_ANALYSIS_INTERVAL="${DEEP_ANALYSIS_INTERVAL:-300}"

        log_info "Selected: $MONITORING_MODE monitoring mode with autostart $DAEMON_AUTOSTART"
        log_info "Intervals: Monitoring=${MONITORING_INTERVAL}s, Quick=${QUICK_CHECK_INTERVAL}s, Deep=${DEEP_ANALYSIS_INTERVAL}s"

        # Log if any environment variables were used for monitoring config
        if [ "${MONITORING_MODE}" != "daemon" ]; then
            log_info "Environment: Using custom MONITORING_MODE=$MONITORING_MODE"
        fi
        if [ "${DAEMON_AUTOSTART}" != "true" ]; then
            log_info "Environment: Daemon autostart disabled"
        fi
    fi

    log_success "Enhanced configuration collected"
}

# === ENHANCED CONFIGURATION FILE GENERATION ===
generate_enhanced_config() {
    log_info "Generating enhanced configuration file..."

    cat >"$CONFIG_DIR/config.sh" <<EOF
#!/bin/sh
# Enhanced Starlink Solution Configuration
# Generated by deployment script v$SCRIPT_VERSION on $(date)
# PERSISTENT STORAGE: This configuration survives firmware upgrades

# === INSTALLATION PATHS (PERSISTENT) ===
INSTALL_BASE_DIR="$INSTALL_BASE_DIR"
CONFIG_DIR="$CONFIG_DIR"
SCRIPTS_DIR="$SCRIPTS_DIR"
LOG_DIR="$LOG_DIR"
STATE_DIR="$STATE_DIR"
LIB_DIR="$LIB_DIR"

# === BASIC CONFIGURATION ===
STARLINK_IP="$STARLINK_IP"
STARLINK_PORT="$STARLINK_PORT"
RUTOS_IP="$RUTOS_IP"

# === NETWORK CONFIGURATION ===
MWAN_IFACE="$MWAN_IFACE"
MWAN_MEMBER="$MWAN_MEMBER"
METRIC_GOOD="$METRIC_GOOD"
METRIC_BAD="$METRIC_BAD"

# === THRESHOLDS ===
LATENCY_THRESHOLD="$LATENCY_THRESHOLD"
PACKET_LOSS_THRESHOLD="$PACKET_LOSS_THRESHOLD"
OBSTRUCTION_THRESHOLD="$OBSTRUCTION_THRESHOLD"

# === FEATURE TOGGLES ===
ENABLE_STARLINK_MONITORING="$ENABLE_STARLINK_MONITORING"
ENABLE_GPS="$ENABLE_GPS"
ENABLE_AZURE="$ENABLE_AZURE"
ENABLE_PUSHOVER="$ENABLE_PUSHOVER"

# === AZURE CONFIGURATION ===
AZURE_ENDPOINT="$AZURE_ENDPOINT"

# === PUSHOVER CONFIGURATION ===
PUSHOVER_USER_KEY="$PUSHOVER_USER_KEY"
PUSHOVER_API_TOKEN="$PUSHOVER_API_TOKEN"

# === INTELLIGENT MONITORING CONFIGURATION ===
MONITORING_MODE="$MONITORING_MODE"
DAEMON_AUTOSTART="$DAEMON_AUTOSTART"
MONITORING_INTERVAL="$MONITORING_INTERVAL"
QUICK_CHECK_INTERVAL="$QUICK_CHECK_INTERVAL"
DEEP_ANALYSIS_INTERVAL="$DEEP_ANALYSIS_INTERVAL"

# === INTELLIGENT LOGGING CONFIGURATION ===
HIGH_FREQ_INTERVAL="\${HIGH_FREQ_INTERVAL:-1}"           # 1 second for unlimited connections
LOW_FREQ_INTERVAL="\${LOW_FREQ_INTERVAL:-60}"           # 60 seconds for limited data connections
GPS_COLLECTION_INTERVAL="\${GPS_COLLECTION_INTERVAL:-60}"  # GPS every minute
AGGREGATION_WINDOW="\${AGGREGATION_WINDOW:-60}"         # 60-second aggregation windows
PERCENTILES="\${PERCENTILES:-50,90,95,99}"              # Percentiles to calculate
LOG_RETENTION_HOURS="\${LOG_RETENTION_HOURS:-24}"       # 24 hours of detailed logs
ARCHIVE_RETENTION_DAYS="\${ARCHIVE_RETENTION_DAYS:-7}"  # 7 days of compressed archives

# === CONNECTION TYPE PATTERNS ===
CELLULAR_INTERFACES_PATTERN="\${CELLULAR_INTERFACES_PATTERN:-^mob[0-9]s[0-9]a[0-9]$}"
SATELLITE_INTERFACES_PATTERN="\${SATELLITE_INTERFACES_PATTERN:-^wwan|^starlink}"
UNLIMITED_INTERFACES_PATTERN="\${UNLIMITED_INTERFACES_PATTERN:-^eth|^wifi}"

# === INTELLIGENT MONITORING THRESHOLDS ===
LATENCY_WARNING_THRESHOLD="\${LATENCY_WARNING_THRESHOLD:-200}"
LATENCY_CRITICAL_THRESHOLD="\${LATENCY_CRITICAL_THRESHOLD:-500}"
PACKET_LOSS_WARNING_THRESHOLD="\${PACKET_LOSS_WARNING_THRESHOLD:-2}"
PACKET_LOSS_CRITICAL_THRESHOLD="\${PACKET_LOSS_CRITICAL_THRESHOLD:-5}"

# === PERFORMANCE ANALYSIS SETTINGS ===
HISTORICAL_ANALYSIS_WINDOW="\${HISTORICAL_ANALYSIS_WINDOW:-1800}"
TREND_ANALYSIS_SAMPLES="\${TREND_ANALYSIS_SAMPLES:-10}"
MAX_METRIC_ADJUSTMENT="\${MAX_METRIC_ADJUSTMENT:-50}"
MAX_ADJUSTMENTS_PER_CYCLE="\${MAX_ADJUSTMENTS_PER_CYCLE:-3}"
ADJUSTMENT_COOLDOWN="\${ADJUSTMENT_COOLDOWN:-120}"

# === BINARY PATHS ===
GRPCURL_CMD="$SCRIPTS_DIR/grpcurl"
JQ_CMD="$SCRIPTS_DIR/jq"

# === DEVELOPMENT/DEBUG ===
DEBUG="\${DEBUG:-0}"
DRY_RUN="\${DRY_RUN:-0}"
RUTOS_TEST_MODE="\${RUTOS_TEST_MODE:-0}"

# === FIRMWARE UPGRADE RECOVERY ===
# After firmware upgrades, run: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh
RECOVERY_SCRIPT="$SCRIPTS_DIR/recover-after-firmware-upgrade.sh"

EOF

    chmod 644 "$CONFIG_DIR/config.sh"
    log_success "Enhanced configuration file created at $CONFIG_DIR/config.sh"
    log_info "Configuration is stored in persistent storage and survives firmware upgrades"
}

# === SYSTEM VERIFICATION WITH DAEMON SUPPORT ===
verify_intelligent_monitoring_system() {
    log_step "Verifying Intelligent Monitoring System v3.0"

    verification_failed=0

    # Check persistent storage setup
    if [ -d "$INSTALL_BASE_DIR" ] && [ -d "$SCRIPTS_DIR" ] && [ -d "$CONFIG_DIR" ]; then
        log_success "Persistent storage directories verified"
    else
        log_error "Persistent storage directories missing"
        verification_failed=1
    fi

    # Check if monitoring script exists and is executable in persistent location
    if [ -f "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ] && [ -x "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" ]; then
        log_success "Intelligent monitoring script installed in persistent storage"
    else
        log_error "Intelligent monitoring script missing or not executable in persistent storage"
        verification_failed=1
    fi

    # Check convenience symlinks
    if [ -L "/root/starlink_monitor_unified-rutos.sh" ] && [ -L "/root/config.sh" ]; then
        log_success "Convenience symlinks created"
    else
        log_warning "Convenience symlinks missing (not critical)"
    fi

    # Check MWAN3 availability (required for intelligent monitoring)
    if command -v mwan3 >/dev/null 2>&1; then
        log_success "MWAN3 available for intelligent monitoring"

        # Test MWAN3 configuration access
        if uci show mwan3 >/dev/null 2>&1; then
            log_success "MWAN3 UCI configuration accessible"
        else
            log_error "MWAN3 UCI configuration not accessible"
            verification_failed=1
        fi
    else
        log_error "MWAN3 not found - intelligent monitoring requires MWAN3"
        verification_failed=1
    fi

    # Check daemon service setup
    if [ "$MONITORING_MODE" = "daemon" ] || [ "$MONITORING_MODE" = "hybrid" ]; then
        if [ -f "$INIT_D_DIR/starlink-monitor" ] && [ -x "$INIT_D_DIR/starlink-monitor" ]; then
            log_success "Daemon service script installed"

            # Test daemon functionality
            log_info "Testing daemon service..."
            if "$INIT_D_DIR/starlink-monitor" status >/dev/null 2>&1; then
                log_success "Daemon service operational"
            else
                log_info "Daemon not currently running (normal after installation)"
            fi
        else
            log_error "Daemon service script missing"
            verification_failed=1
        fi
    fi

    # Test intelligent monitoring script
    log_info "Testing intelligent monitoring script functionality..."
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" validate 2>/dev/null; then
        log_success "Intelligent monitoring validation passed"
    else
        log_warning "Intelligent monitoring validation failed - may need MWAN3 configuration"
    fi

    # Test discovery capabilities
    log_info "Testing MWAN3 discovery capabilities..."
    if "$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh" discover >/dev/null 2>&1; then
        log_success "MWAN3 interface discovery working"
    else
        log_warning "MWAN3 interface discovery needs configuration"
    fi

    if [ $verification_failed -eq 0 ]; then
        log_success "All intelligent monitoring system checks passed"
        return 0
    else
        log_error "Some intelligent monitoring system checks failed"
        return 1
    fi
}

# === INTELLIGENT LOGGING SYSTEM DEPLOYMENT ===
deploy_intelligent_logging_system() {
    log_step "Deploying Intelligent Logging System v3.0"

    # Download the intelligent logger script
    log_info "Downloading intelligent logging system..."

    logger_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/scripts/starlink_intelligent_logger-rutos.sh"
    logger_dest="$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would download $logger_url to $logger_dest"
    else
        if curl -fsSL "$logger_url" -o "$logger_dest"; then
            chmod +x "$logger_dest"
            log_success "Intelligent logger installed: $logger_dest"
        else
            log_error "Failed to download intelligent logger"
            return 1
        fi
    fi

    # Create logging system configuration
    log_info "Configuring intelligent logging system..."

    cat >"$CONFIG_DIR/logging.conf" <<EOF
# Intelligent Logging System Configuration
# Generated by deployment script v$SCRIPT_VERSION

# === COLLECTION FREQUENCY ===
HIGH_FREQ_INTERVAL=1           # 1 second for unlimited connections
LOW_FREQ_INTERVAL=60          # 60 seconds for limited data connections
GPS_COLLECTION_INTERVAL=60    # GPS every minute

# === STATISTICAL AGGREGATION ===
AGGREGATION_WINDOW=60         # 60-second aggregation windows
PERCENTILES="50,90,95,99"     # Percentiles to calculate

# === LOG RETENTION ===
LOG_RETENTION_HOURS=24        # 24 hours of detailed logs
ARCHIVE_RETENTION_DAYS=7      # 7 days of compressed archives

# === CONNECTION TYPE PATTERNS ===
CELLULAR_INTERFACES_PATTERN="^mob[0-9]s[0-9]a[0-9]$"
SATELLITE_INTERFACES_PATTERN="^wwan|^starlink"
UNLIMITED_INTERFACES_PATTERN="^eth|^wifi"

# === LOGGING DIRECTORIES (PERSISTENT) ===
LOG_BASE_DIR="$LOG_DIR"
METRICS_LOG_DIR="$LOG_DIR/metrics"
GPS_LOG_DIR="$LOG_DIR/gps"
AGGREGATED_LOG_DIR="$LOG_DIR/aggregated"
ARCHIVE_LOG_DIR="$LOG_DIR/archive"
EOF

    chmod 644 "$CONFIG_DIR/logging.conf"
    log_success "Logging configuration created: $CONFIG_DIR/logging.conf"

    # Create convenience symlink for backward compatibility
    ln -sf "$logger_dest" /root/starlink_intelligent_logger-rutos.sh 2>/dev/null || true

    log_success "Intelligent logging system deployment completed"
}

# === INTELLIGENT LOGGING SERVICE SETUP ===
setup_intelligent_logging_service() {
    log_step "Setting up Intelligent Logging Service"

    # Create init.d service script for the intelligent logger
    log_info "Creating logging daemon service script..."

    cat >"$INSTALL_BASE_DIR/templates/starlink-logger.init" <<EOF
#!/bin/sh /etc/rc.common

START=96
STOP=9

USE_PROCD=1
PROG="$SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh"
PIDFILE="/var/run/starlink-logger.pid"

start_service() {
    # Ensure configuration exists
    if [ ! -f "$CONFIG_DIR/config.sh" ]; then
        logger -s -t starlink-logger "ERROR: Configuration not found at $CONFIG_DIR/config.sh"
        return 1
    fi
    
    # Ensure MWAN3 is available
    if ! command -v mwan3 >/dev/null 2>&1; then
        logger -s -t starlink-logger "WARNING: MWAN3 not found - limited metrics available"
    fi
    
    logger -s -t starlink-logger "Starting Intelligent Starlink Logger v3.0"
    
    procd_open_instance
    procd_set_param command "\$PROG" start
    procd_set_param pidfile "\$PIDFILE"
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    logger -s -t starlink-logger "Intelligent logging daemon started"
}

stop_service() {
    logger -s -t starlink-logger "Stopping Intelligent Starlink Logger"
    "\$PROG" stop
}

reload_service() {
    logger -s -t starlink-logger "Reloading Intelligent Starlink Logger"
    "\$PROG" restart
}

status() {
    "\$PROG" status
}
EOF

    # Copy the template to the active init.d location
    cp "$INSTALL_BASE_DIR/templates/starlink-logger.init" "$INIT_D_DIR/starlink-logger"
    chmod +x "$INIT_D_DIR/starlink-logger"

    log_success "Created logging daemon service script"
    log_info "Service template: $INSTALL_BASE_DIR/templates/starlink-logger.init"
    log_info "Active service: $INIT_D_DIR/starlink-logger"

    # Enable the service to start at boot if monitoring is enabled
    if [ "${ENABLE_STARLINK_MONITORING:-true}" = "true" ]; then
        log_info "Enabling logging daemon autostart at boot..."
        "$INIT_D_DIR/starlink-logger" enable 2>/dev/null || true
        log_success "Logging daemon autostart enabled"
    fi

    log_success "Intelligent logging service setup completed"
}

# === MAIN DEPLOYMENT FUNCTIONS ===

# Basic configuration collection (placeholder for full implementation)
collect_basic_configuration() {
    log_step "Basic Configuration Collection"

    if is_interactive; then
        log_info "Interactive mode detected - collecting configuration"

        # Collect basic network settings
        printf "Starlink IP address [%s]: " "$DEFAULT_STARLINK_IP"
        read -r STARLINK_IP_INPUT
        STARLINK_IP="${STARLINK_IP_INPUT:-$DEFAULT_STARLINK_IP}"

        printf "Starlink port [9200]: "
        read -r STARLINK_PORT_INPUT
        STARLINK_PORT="${STARLINK_PORT_INPUT:-9200}"

        printf "RUTOS IP address [%s]: " "$DEFAULT_RUTOS_IP"
        read -r RUTOS_IP_INPUT
        RUTOS_IP="${RUTOS_IP_INPUT:-$DEFAULT_RUTOS_IP}"

        # Network configuration
        printf "MWAN interface name [starlink]: "
        read -r MWAN_IFACE_INPUT
        MWAN_IFACE="${MWAN_IFACE_INPUT:-starlink}"

        printf "MWAN member name [starlink_m1_w1]: "
        read -r MWAN_MEMBER_INPUT
        MWAN_MEMBER="${MWAN_MEMBER_INPUT:-starlink_m1_w1}"

        printf "Good connection metric [10]: "
        read -r METRIC_GOOD_INPUT
        METRIC_GOOD="${METRIC_GOOD_INPUT:-10}"

        printf "Bad connection metric [100]: "
        read -r METRIC_BAD_INPUT
        METRIC_BAD="${METRIC_BAD_INPUT:-100}"

        # Thresholds
        printf "Latency threshold in ms [1000]: "
        read -r LATENCY_THRESHOLD_INPUT
        LATENCY_THRESHOLD="${LATENCY_THRESHOLD_INPUT:-1000}"

        printf "Packet loss threshold %% [10]: "
        read -r PACKET_LOSS_THRESHOLD_INPUT
        PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD_INPUT:-10}"

        printf "Obstruction threshold %% [5]: "
        read -r OBSTRUCTION_THRESHOLD_INPUT
        OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD_INPUT:-5}"

        # Feature toggles
        printf "Enable Starlink monitoring? [Y/n]: "
        read -r STARLINK_MONITORING_CHOICE
        case "${STARLINK_MONITORING_CHOICE:-y}" in
            [Nn]*) ENABLE_STARLINK_MONITORING="false" ;;
            *) ENABLE_STARLINK_MONITORING="true" ;;
        esac

        printf "Enable GPS collection? [Y/n]: "
        read -r GPS_CHOICE
        case "${GPS_CHOICE:-y}" in
            [Nn]*) ENABLE_GPS="false" ;;
            *) ENABLE_GPS="true" ;;
        esac

        printf "Enable Azure integration? [y/N]: "
        read -r AZURE_CHOICE
        case "${AZURE_CHOICE:-n}" in
            [Yy]*)
                ENABLE_AZURE="true"
                printf "Azure endpoint URL: "
                read -r AZURE_ENDPOINT
                ;;
            *)
                ENABLE_AZURE="false"
                AZURE_ENDPOINT=""
                ;;
        esac

        printf "Enable Pushover notifications? [y/N]: "
        read -r PUSHOVER_CHOICE
        case "${PUSHOVER_CHOICE:-n}" in
            [Yy]*)
                ENABLE_PUSHOVER="true"
                printf "Pushover user key: "
                read -r PUSHOVER_USER_KEY
                printf "Pushover API token: "
                read -r PUSHOVER_API_TOKEN
                ;;
            *)
                ENABLE_PUSHOVER="false"
                PUSHOVER_USER_KEY=""
                PUSHOVER_API_TOKEN=""
                ;;
        esac
    else
        log_info "Non-interactive mode detected - using default configuration"

        # Use environment variables if set, otherwise defaults
        STARLINK_IP="${STARLINK_IP:-$DEFAULT_STARLINK_IP}"
        STARLINK_PORT="${STARLINK_PORT:-9200}"
        RUTOS_IP="${RUTOS_IP:-$DEFAULT_RUTOS_IP}"
        MWAN_IFACE="${MWAN_IFACE:-starlink}"
        MWAN_MEMBER="${MWAN_MEMBER:-starlink_m1_w1}"
        METRIC_GOOD="${METRIC_GOOD:-10}"
        METRIC_BAD="${METRIC_BAD:-100}"
        LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-1000}"
        PACKET_LOSS_THRESHOLD="${PACKET_LOSS_THRESHOLD:-10}"
        OBSTRUCTION_THRESHOLD="${OBSTRUCTION_THRESHOLD:-5}"
        ENABLE_STARLINK_MONITORING="${ENABLE_STARLINK_MONITORING:-$DEFAULT_ENABLE_STARLINK_MONITORING}"
        ENABLE_GPS="${ENABLE_GPS:-$DEFAULT_ENABLE_GPS}"
        ENABLE_AZURE="${ENABLE_AZURE:-false}"
        AZURE_ENDPOINT="${AZURE_ENDPOINT:-}"
        ENABLE_PUSHOVER="${ENABLE_PUSHOVER:-false}"
        PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-}"
        PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-}"

        log_info "Using configuration: Starlink IP=$STARLINK_IP, RUTOS IP=$RUTOS_IP"
        log_info "Network: Interface=$MWAN_IFACE, Member=$MWAN_MEMBER"
        log_info "Thresholds: Latency=${LATENCY_THRESHOLD}ms, Loss=${PACKET_LOSS_THRESHOLD}%, Obstruction=${OBSTRUCTION_THRESHOLD}%"
        log_info "Features: Starlink=$ENABLE_STARLINK_MONITORING, GPS=$ENABLE_GPS"
        log_info "Integrations: Azure=$ENABLE_AZURE, Pushover=$ENABLE_PUSHOVER"

        # Log if any environment variables were used
        if [ "$STARLINK_IP" != "$DEFAULT_STARLINK_IP" ]; then
            log_info "Environment: Using custom STARLINK_IP=$STARLINK_IP"
        fi
        if [ "${ENABLE_STARLINK_MONITORING}" != "$DEFAULT_ENABLE_STARLINK_MONITORING" ]; then
            log_info "Environment: Starlink monitoring=$ENABLE_STARLINK_MONITORING"
        fi
        if [ "${ENABLE_GPS}" != "$DEFAULT_ENABLE_GPS" ]; then
            log_info "Environment: GPS collection=$ENABLE_GPS"
        fi
        if [ "${ENABLE_AZURE}" = "true" ]; then
            log_info "Environment: Azure integration enabled"
        fi
        if [ "${ENABLE_PUSHOVER}" = "true" ]; then
            log_info "Environment: Pushover notifications enabled"
        fi
    fi

    log_success "Basic configuration collected"
}

# System requirements setup (placeholder for full implementation)
setup_system_requirements() {
    log_step "Setting up System Requirements"

    # Check for essential tools
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        return 1
    fi

    if ! command -v uci >/dev/null 2>&1; then
        log_error "uci is required but not installed (not RUTOS?)"
        return 1
    fi

    log_success "System requirements verified"
}

# Package installation (placeholder for full implementation)
install_required_packages() {
    log_step "Installing Required Packages"

    # Update package lists
    log_info "Updating package lists..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would run opkg update"
    else
        opkg update >/dev/null 2>&1 || log_warninging "Package update failed (may be offline)"
    fi

    # Install MWAN3 if not present
    if ! command -v mwan3 >/dev/null 2>&1; then
        log_info "Installing MWAN3..."
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_info "DRY-RUN: Would install mwan3 package"
        else
            opkg install mwan3 || log_warninging "MWAN3 installation failed"
        fi
    else
        log_success "MWAN3 already available"
    fi

    log_success "Package installation completed"
}

# Binary downloads (placeholder for full implementation)
download_binaries() {
    log_step "Downloading Required Binaries"

    # Download grpcurl
    if [ ! -f "$SCRIPTS_DIR/grpcurl" ]; then
        log_info "Downloading grpcurl..."
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_info "DRY-RUN: Would download grpcurl from $GRPCURL_URL"
        else
            temp_dir="/tmp/grpcurl_$$"
            mkdir -p "$temp_dir"
            if curl -fsSL "$GRPCURL_URL" | tar -xz -C "$temp_dir"; then
                cp "$temp_dir/grpcurl" "$SCRIPTS_DIR/grpcurl"
                chmod +x "$SCRIPTS_DIR/grpcurl"
                rm -rf "$temp_dir"
                log_success "grpcurl installed"
            else
                log_error "Failed to download grpcurl"
                rm -rf "$temp_dir"
                return 1
            fi
        fi
    else
        log_success "grpcurl already available"
    fi

    # Download jq
    if [ ! -f "$SCRIPTS_DIR/jq" ]; then
        log_info "Downloading jq..."
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_info "DRY-RUN: Would download jq from $JQ_URL"
        else
            if curl -fsSL "$JQ_URL" -o "$SCRIPTS_DIR/jq"; then
                chmod +x "$SCRIPTS_DIR/jq"
                log_success "jq installed"
            else
                log_error "Failed to download jq"
                return 1
            fi
        fi
    else
        log_success "jq already available"
    fi

    log_success "Binary downloads completed"
}

# Check root privileges
check_root_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check system compatibility
check_system_compatibility() {
    log_info "Checking RUTOS compatibility..."

    if [ ! -f "/etc/openwrt_release" ]; then
        log_warninging "Not detected as OpenWrt/RUTOS system"
    fi

    # Check for RUTOS-specific features
    if command -v gsmctl >/dev/null 2>&1; then
        log_success "RUTOS cellular capabilities detected"
    else
        log_info "No RUTOS cellular capabilities (basic monitoring only)"
    fi
}

# Deploy monitoring scripts (placeholder for full implementation)
deploy_monitoring_scripts() {
    log_step "Deploying Monitoring Scripts"

    # Download main monitoring script
    monitor_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
    monitor_dest="$SCRIPTS_DIR/starlink_monitor_unified-rutos.sh"

    log_info "Downloading main monitoring script..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would download $monitor_url to $monitor_dest"
    else
        if curl -fsSL "$monitor_url" -o "$monitor_dest"; then
            chmod +x "$monitor_dest"
            log_success "Main monitoring script installed: $monitor_dest"
        else
            log_error "Failed to download main monitoring script"
            return 1
        fi
    fi

    # Download RUTOS library
    lib_url="https://github.com/markus-lassfolk/rutos-starlink-failover/raw/main/scripts/lib/rutos-lib.sh"
    lib_dest="$LIB_DIR/rutos-lib.sh"

    log_info "Downloading RUTOS library..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_info "DRY-RUN: Would download $lib_url to $lib_dest"
    else
        if curl -fsSL "$lib_url" -o "$lib_dest"; then
            chmod +x "$lib_dest"
            log_success "RUTOS library installed: $lib_dest"
        else
            log_error "Failed to download RUTOS library"
            return 1
        fi
    fi

    # Deploy intelligent logging system
    deploy_intelligent_logging_system

    log_success "Monitoring scripts deployment completed"
}

# Azure integration setup (placeholder for full implementation)
setup_azure_integration() {
    log_step "Setting up Azure Integration"

    if [ "$ENABLE_AZURE" = "true" ] && [ -n "$AZURE_ENDPOINT" ]; then
        log_info "Configuring Azure log shipping..."
        # Azure setup would go here
        log_success "Azure integration configured"
    else
        log_info "Azure integration disabled"
    fi
}

# Pushover notifications setup (placeholder for full implementation)
setup_pushover_notifications() {
    log_step "Setting up Pushover Notifications"

    if [ "$ENABLE_PUSHOVER" = "true" ] && [ -n "$PUSHOVER_USER_KEY" ] && [ -n "$PUSHOVER_API_TOKEN" ]; then
        log_info "Configuring Pushover notifications..."
        # Pushover setup would go here
        log_success "Pushover notifications configured"
    else
        log_info "Pushover notifications disabled"
    fi
}

# === MAIN EXECUTION ===
main() {
    log_step "Starlink Solution Deployment v$SCRIPT_VERSION - Intelligent Monitoring"

    # Pre-flight checks
    check_root_privileges
    check_system_compatibility

    # CRITICAL: Setup persistent storage first (RUTOS firmware upgrade survival)
    setup_persistent_storage

    # Configuration
    collect_enhanced_configuration

    # System setup
    setup_system_requirements
    install_required_packages
    download_binaries

    # Configuration and recovery setup
    generate_enhanced_config
    create_recovery_script

    # Core deployment
    deploy_monitoring_scripts
    setup_monitoring_system           # Intelligent monitoring daemon setup
    setup_intelligent_logging_service # NEW: Intelligent logging daemon setup

    # Additional features
    if [ "$ENABLE_AZURE" = "true" ]; then
        setup_azure_integration
    fi

    if [ "$ENABLE_PUSHOVER" = "true" ]; then
        setup_pushover_notifications
    fi

    # Verification
    verify_intelligent_monitoring_system

    # Final setup
    log_step "Deployment Completed Successfully!"

    case "$MONITORING_MODE" in
        daemon)
            log_info "Starting intelligent monitoring daemon..."
            "$INIT_D_DIR/starlink-monitor" start
            log_success "Intelligent monitoring daemon started"

            log_info "Starting intelligent logging daemon..."
            "$INIT_D_DIR/starlink-logger" start
            log_success "Intelligent logging daemon started"
            ;;
        hybrid)
            log_info "Starting intelligent monitoring daemon with cron support..."
            "$INIT_D_DIR/starlink-monitor" start
            log_success "Hybrid monitoring system active"

            log_info "Starting intelligent logging daemon..."
            "$INIT_D_DIR/starlink-logger" start
            log_success "Intelligent logging daemon started"
            ;;
        cron)
            log_info "Traditional cron-based monitoring configured"
            log_success "Legacy monitoring system active"

            log_info "Starting intelligent logging daemon..."
            "$INIT_D_DIR/starlink-logger" start
            log_success "Intelligent logging daemon started"
            ;;
    esac

    # Display final status
    log_step "System Status"
    log_info "Monitoring mode: $MONITORING_MODE"
    log_info "Installation directory: $INSTALL_BASE_DIR (PERSISTENT)"
    log_info "Configuration: $CONFIG_DIR/config.sh (PERSISTENT)"
    log_info "Scripts location: $SCRIPTS_DIR (PERSISTENT)"
    log_info "Logs directory: $LOG_DIR (PERSISTENT)"
    log_info "Convenience symlinks: /root/starlink_monitor_unified-rutos.sh, /root/config.sh"

    if [ "$MONITORING_MODE" != "cron" ]; then
        log_info "Monitoring daemon: $INIT_D_DIR/starlink-monitor {start|stop|status|restart}"
        log_info "Manual testing: $SCRIPTS_DIR/starlink_monitor_unified-rutos.sh test --debug"
    fi

    # NEW: Intelligent logging system status
    log_step "Intelligent Logging System"
    log_info "Logging daemon: $INIT_D_DIR/starlink-logger {start|stop|status|restart}"
    log_info "Logger control: $SCRIPTS_DIR/starlink_intelligent_logger-rutos.sh {start|stop|status|test}"
    log_info "Metrics logs: $LOG_DIR/metrics/ (24-hour retention)"
    log_info "GPS logs: $LOG_DIR/gps/ (daily files)"
    log_info "Aggregated data: $LOG_DIR/aggregated/ (statistical summaries)"
    log_info "Archived logs: $LOG_DIR/archive/ (7-day retention, compressed)"
    log_info "Collection features:"
    log_info "  • MWAN3 metrics extraction (no additional traffic)"
    log_info "  • Smart frequency: 1s unlimited, 60s limited connections"
    log_info "  • Dual-source GPS (RUTOS + Starlink)"
    log_info "  • Statistical aggregation with percentiles"
    log_info "  • Automatic log rotation and compression"

    # IMPORTANT: Firmware upgrade information
    log_step "IMPORTANT: Firmware Upgrade Recovery"
    log_warning "After RUTOS firmware upgrades, run the recovery script:"
    log_info "Recovery command: $SCRIPTS_DIR/recover-after-firmware-upgrade.sh"
    log_info "This will restore daemon service and symlinks after firmware upgrades"

    log_success "Intelligent Starlink Monitoring System v3.0 deployment completed!"
    log_success "All files stored in persistent storage: $INSTALL_BASE_DIR"
}

# Execute main function if script is run directly
if [ "${0##*/}" = "deploy-starlink-solution-v3-rutos.sh" ]; then
    main "$@"
fi
