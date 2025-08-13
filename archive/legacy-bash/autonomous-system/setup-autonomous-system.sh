#!/bin/sh
# ==============================================================================
# Autonomous System Setup Script for RUTOS Deployment
# ==============================================================================
# This script sets up the autonomous deployment and monitoring system for
# RUTOS devices. It creates the necessary directory structure, installs
# scripts, configures SSH keys, generates configuration files, sets up
# cron jobs, and prepares the system for autonomous operation.
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck disable=SC1091 # Library path is dynamic based on deployment location
. "$(dirname "$0")/../scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "setup-autonomous-system.sh" "$SCRIPT_VERSION"

INSTALL_DIR="${INSTALL_DIR:-$HOME/autonomous-rutos}"

# Check prerequisites
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."

    missing_deps=""

    # Check for required commands
    for cmd in git curl ssh jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if [ -z "$missing_deps" ]; then
                missing_deps="$cmd"
            else
                missing_deps="$missing_deps $cmd"
            fi
        fi
    done

    # Check for GitHub CLI (recommended)
    if ! command -v gh >/dev/null 2>&1; then
        log_warn "GitHub CLI (gh) not found - will use PowerShell fallback if available"
    fi

    # Check for PowerShell (fallback)
    if ! command -v pwsh >/dev/null 2>&1; then
        log_warn "PowerShell (pwsh) not found - GitHub CLI is required"
    fi

    if [ -n "$missing_deps" ]; then
        log_error "Missing required dependencies: $missing_deps"
        log_info "Please install missing dependencies and run this script again."
        exit 1
    fi

    log_info "✅ All prerequisites satisfied"
}

# Create directory structure
create_directory_structure() {
    log_info "📁 Creating directory structure at $INSTALL_DIR..."

    mkdir -p "$INSTALL_DIR"/{logs,config,scripts,keys,models}

    # Set appropriate permissions
    chmod 700 "$INSTALL_DIR/keys"
    chmod 755 "$INSTALL_DIR"/{logs,config,scripts,models}

    log_info "✅ Directory structure created"
}

# Copy autonomous system files
copy_system_files() {
    log_info "📋 Copying autonomous system files..."

    # Copy main scripts
    cp autonomous-system/autonomous-deployer-rutos.sh "$INSTALL_DIR/scripts/"
    cp autonomous-system/autonomous-error-monitor-rutos.sh "$INSTALL_DIR/scripts/"

    # Copy configuration template
    cp autonomous-system/autonomous-config.template.conf "$INSTALL_DIR/config/"

    # Make scripts executable
    chmod +x "$INSTALL_DIR/scripts"/*.sh

    log_info "✅ System files copied"
}

# Configure SSH keys
configure_ssh() {
    log_info "🔑 SSH key configuration..."

    ssh_key_path="$INSTALL_DIR/keys/rutos_key"

    if [ ! -f "$ssh_key_path" ]; then
        log_info "Generating SSH key pair for RUTOS access..."
        ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "" -C "autonomous-rutos-$(date +%Y%m%d)"

        log_info "📋 SSH public key generated:"
        log_info "$(cat "$ssh_key_path.pub")"
        log_warn "⚠️  Please copy this public key to your RUTOS devices:"
        log_warn "   SSH to each RUTOS device and add the key to /root/.ssh/authorized_keys"
    else
        log_info "✅ SSH key already exists at $ssh_key_path"
    fi
}

# Create configuration file
create_configuration() {
    log_info "⚙️ Creating configuration file..."

    config_file="$INSTALL_DIR/config/autonomous-config.conf"

    if [ ! -f "$config_file" ]; then
        cp "$INSTALL_DIR/config/autonomous-config.template.conf" "$config_file"

        # Interactive configuration
        log_info "📝 Please configure the following settings:"

        printf "Enter RUTOS device IPs (space-separated): "
        read -r rutos_hosts
        printf "Enter GitHub repository owner [%s]: " "$USER"
        read -r repo_owner
        repo_owner="${repo_owner:-$USER}"
        printf "Enter GitHub repository name [rutos-starlink-failover]: "
        read -r repo_name
        repo_name="${repo_name:-rutos-starlink-failover}"
        printf "Enter GitHub token: "
        read -r github_token
        echo

        # Update configuration file
        sed -i "s|^# RUTOS_HOSTS=.*|RUTOS_HOSTS=\"$rutos_hosts\"|" "$config_file"
        sed -i "s|^# SSH_KEY=.*|SSH_KEY=\"$INSTALL_DIR/keys/rutos_key\"|" "$config_file"
        sed -i "s|^# REPO_OWNER=.*|REPO_OWNER=\"$repo_owner\"|" "$config_file"
        sed -i "s|^# REPO_NAME=.*|REPO_NAME=\"$repo_name\"|" "$config_file"
        sed -i "s|^# GITHUB_TOKEN=.*|GITHUB_TOKEN=\"$github_token\"|" "$config_file"
        sed -i "s|^# DEBUG=.*|DEBUG=\"1\"|" "$config_file"

        log_info "✅ Configuration file created: $config_file"
    else
        log_info "✅ Configuration file already exists"
    fi
}

# Setup cron jobs
setup_cron_jobs() {
    log_info "⏰ Setting up cron jobs..."

    deployer_script="$INSTALL_DIR/scripts/autonomous-deployer-rutos.sh"
    monitor_script="$INSTALL_DIR/scripts/autonomous-error-monitor-rutos.sh"
    config_file="$INSTALL_DIR/config/autonomous-config.conf"

    # Create cron entries
    cron_entries=$(
        cat <<EOF
# Autonomous RUTOS System - Generated $(date)
# Deployment every 6 hours
0 */6 * * * cd "$INSTALL_DIR" && CONFIG_FILE="$config_file" "$deployer_script" >> "$INSTALL_DIR/logs/cron.log" 2>&1

# Error monitoring every 5 minutes
*/5 * * * * cd "$INSTALL_DIR" && CONFIG_FILE="$config_file" "$monitor_script" >> "$INSTALL_DIR/logs/cron.log" 2>&1

# Log cleanup daily at 2 AM
0 2 * * * find "$INSTALL_DIR/logs" -name "*.log" -mtime +7 -delete
EOF
    )

    # Add to user's crontab
    (crontab -l 2>/dev/null || echo "") | grep -v "Autonomous RUTOS System" >/tmp/current_cron
    echo "$cron_entries" >>/tmp/current_cron
    crontab /tmp/current_cron
    rm /tmp/current_cron

    log_info "✅ Cron jobs configured"
    log_info "📅 Deployment schedule: Every 6 hours"
    log_info "🔍 Error monitoring: Every 5 minutes"
}

# Test system
test_system() {
    log_info "🧪 Testing autonomous system..."

    config_file="$INSTALL_DIR/config/autonomous-config.conf"

    # Test configuration loading
    # shellcheck source=/dev/null
    if . "$config_file" 2>/dev/null; then
        log_info "✅ Configuration loads successfully"
    else
        log_error "❌ Configuration file has errors"
        return 1
    fi

    # Test deployer script
    cd "$INSTALL_DIR"
    if CONFIG_FILE="$config_file" TEST_MODE="true" "$INSTALL_DIR/scripts/autonomous-deployer-rutos.sh" >/dev/null 2>&1; then
        log_info "✅ Deployer script test passed"
    else
        log_warn "⚠️ Deployer script test failed (may need RUTOS host access)"
    fi

    # Test error monitor
    if CONFIG_FILE="$config_file" "$INSTALL_DIR/scripts/autonomous-error-monitor-rutos.sh" >/dev/null 2>&1; then
        log_info "✅ Error monitor script test passed"
    else
        log_warn "⚠️ Error monitor script test failed (may need GitHub access)"
    fi

    log_info "✅ System testing completed"
}

# Display setup summary
display_summary() {
    log_info "🎉 Autonomous RUTOS System Setup Complete!"
    echo
    log_info "📁 Installation Directory: $INSTALL_DIR"
    log_info "⚙️ Configuration: $INSTALL_DIR/config/autonomous-config.conf"
    log_info "📝 Logs: $INSTALL_DIR/logs/"
    log_info "🔑 SSH Key: $INSTALL_DIR/keys/rutos_key"
    echo
    log_info "📅 Scheduled Operations:"
    log_info "   • Deployment: Every 6 hours"
    log_info "   • Error Monitoring: Every 5 minutes"
    log_info "   • Log Cleanup: Daily at 2 AM"
    echo
    log_info "🚀 Next Steps:"
    log_info "1. Ensure SSH public key is installed on all RUTOS devices"
    log_info "2. Test manual deployment: cd $INSTALL_DIR && ./scripts/autonomous-deployer-rutos.sh"
    log_info "3. Monitor logs: tail -f $INSTALL_DIR/logs/cron.log"
    log_info "4. Check GitHub for autonomous issues and PRs"
    echo
    log_info "🤖 The autonomous system is now active and will:"
    log_info "   • Deploy latest code to RUTOS devices every 6 hours"
    log_info "   • Monitor for errors and create GitHub issues"
    log_info "   • Auto-assign issues to GitHub Copilot"
    log_info "   • Test and merge fixes automatically"
    log_info "   • Use fixed code in next deployment cycle"
}

# Main setup function
main() {
    log_info "🚀 Starting Autonomous RUTOS System Setup v$SCRIPT_VERSION"
    echo

    check_prerequisites
    create_directory_structure
    copy_system_files
    configure_ssh
    create_configuration
    setup_cron_jobs
    test_system
    display_summary

    log_info "✅ Setup completed successfully!"
}

# Execute main function
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
