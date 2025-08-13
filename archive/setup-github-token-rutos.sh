#!/bin/sh
# ==============================================================================
# GitHub Token Setup Helper for Autonomous System
#
# This script helps set up GitHub authentication for the autonomous system
# by extracting tokens from various sources (GitHub CLI, manual setup, etc.)
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck disable=SC1091 # Library path is dynamic based on deployment location
. "$(dirname "$0")/scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "setup-github-token-rutos.sh" "$SCRIPT_VERSION"

# Check if GitHub CLI is available and authenticated
check_github_cli_auth() {
    if ! command -v gh >/dev/null 2>&1; then
        log_warning "GitHub CLI (gh) not found"
        return 1
    fi

    if gh auth status >/dev/null 2>&1; then
        log_success "GitHub CLI is authenticated"
        return 0
    else
        log_warning "GitHub CLI is not authenticated"
        return 1
    fi
}

# Extract token from GitHub CLI
get_github_cli_token() {
    if check_github_cli_auth; then
        token=$(gh auth token 2>/dev/null)
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi
    return 1
}

# Setup GitHub token for autonomous system
setup_github_token() {
    log_info "=== GitHub Token Setup for Autonomous System ==="

    # Method 1: Try to get token from GitHub CLI
    log_step "Checking GitHub CLI authentication..."
    if token=$(get_github_cli_token); then
        log_success "✓ GitHub CLI token retrieved successfully"

        # Test the token
        if test_github_token "$token"; then
            log_success "✓ Token validated successfully"

            # Save token to environment file
            save_github_token "$token"

            log_success "GitHub token setup completed!"
            log_info "You can now run the autonomous system with GitHub integration"
            return 0
        else
            log_error "✗ Token validation failed"
        fi
    else
        log_warning "✗ Could not retrieve token from GitHub CLI"
    fi

    # Method 2: Prompt for manual token setup
    log_info ""
    log_info "=== Manual Token Setup ==="
    log_info "To set up GitHub authentication manually:"
    log_info "1. Go to: https://github.com/settings/personal-access-tokens/tokens"
    log_info "2. Create a Fine-grained Personal Access Token with these permissions:"
    log_info "   Repository: ${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
    log_info "   Permissions needed:"
    log_info "   - Issues: Read and write"
    log_info "   - Metadata: Read"
    log_info "   - Pull requests: Read and write (for autonomous fixes)"
    log_info "3. Copy the token and run:"
    log_info "   export GITHUB_TOKEN='your_token_here'"
    log_info "   echo 'export GITHUB_TOKEN=\"your_token_here\"' >> ~/.bashrc"

    # Method 3: Try GitHub CLI login
    log_info ""
    log_info "=== GitHub CLI Setup ==="
    log_info "Alternatively, authenticate with GitHub CLI:"
    log_info "1. gh auth login"
    log_info "2. Re-run this script to extract the token automatically"

    return 1
}

# Test GitHub token validity
test_github_token() {
    token="$1"

    log_step "Testing GitHub token..."

    # Test API access
    response=$(curl -s -H "Authorization: Bearer $token" \
        "https://api.github.com/repos/${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}")

    if echo "$response" | grep -q '"name"'; then
        log_debug "Token test successful"
        return 0
    else
        log_error "Token test failed. Response: $response"
        return 1
    fi
}

# Save GitHub token to persistent location
save_github_token() {
    token="$1"

    log_step "Saving GitHub token..."

    # Create autonomous system config directory
    config_dir="/etc/autonomous-system"
    if [ ! -d "$config_dir" ]; then
        safe_execute "mkdir -p $config_dir" "Create autonomous system config directory"
    fi

    # Create token file with restricted permissions
    token_file="$config_dir/github-token"
    cat >"$token_file" <<EOF
# GitHub token for autonomous system
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL
export GITHUB_TOKEN="$token"
EOF

    # Secure the token file
    safe_execute "chmod 600 $token_file" "Secure token file permissions"
    safe_execute "chown root:root $token_file" "Set token file ownership" || true

    log_success "Token saved to: $token_file"

    # Also create sourcing script for easy loading
    loader_script="$config_dir/load-github-auth.sh"
    cat >"$loader_script" <<EOF
#!/bin/sh
# Load GitHub authentication for autonomous system
if [ -f "$token_file" ]; then
    . "$token_file"
    export GITHUB_TOKEN
else
    echo "ERROR: GitHub token not found at $token_file" >&2
    echo "Run setup-github-token-rutos.sh to configure authentication" >&2
    exit 1
fi
EOF

    safe_execute "chmod +x $loader_script" "Make loader script executable"

    log_info "Authentication loader created: $loader_script"
    log_info "Use: . $loader_script  (to load in current shell)"
}

# Show current authentication status
show_auth_status() {
    log_info "=== GitHub Authentication Status ==="

    # Check environment variable
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        log_success "✓ GITHUB_TOKEN environment variable is set"
        if test_github_token "$GITHUB_TOKEN"; then
            log_success "✓ Token is valid"
        else
            log_error "✗ Token is invalid"
        fi
    else
        log_warning "✗ GITHUB_TOKEN environment variable not set"
    fi

    # Check GitHub CLI
    if check_github_cli_auth; then
        log_success "✓ GitHub CLI is authenticated"
    else
        log_warning "✗ GitHub CLI is not authenticated"
    fi

    # Check saved token
    saved_token="/etc/autonomous-system/github-token"
    if [ -f "$saved_token" ]; then
        log_success "✓ Saved token file exists: $saved_token"
    else
        log_warning "✗ No saved token file found"
    fi
}

# Main function
main() {
    case "${1:-setup}" in
        "setup")
            setup_github_token
            ;;
        "status")
            show_auth_status
            ;;
        "test")
            if [ -n "${GITHUB_TOKEN:-}" ]; then
                test_github_token "$GITHUB_TOKEN"
            else
                log_error "GITHUB_TOKEN not set"
                exit 1
            fi
            ;;
        *)
            log_info "Usage: $0 [setup|status|test]"
            log_info "  setup  - Set up GitHub authentication (default)"
            log_info "  status - Show current authentication status"
            log_info "  test   - Test current GITHUB_TOKEN"
            exit 1
            ;;
    esac
}

# Default configuration
GITHUB_REPO="${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"

# Execute main function
main "$@"
