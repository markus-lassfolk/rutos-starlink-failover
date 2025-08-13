#!/bin/sh
# ==============================================================================
# GitHub Authentication Integration for Autonomous System
#
# This script provides seamless integration between:
# - Shell-based autonomous system (autonomous-error-monitor-rutos.sh)
# - PowerShell-based issue creation (create-copilot-issues-optimized.ps1)
# - GitHub CLI authentication
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck disable=SC1091 # Library path is dynamic based on deployment location
. "$(dirname "$0")/scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "github-auth-integration-rutos.sh" "$SCRIPT_VERSION"

# Integration with PowerShell issue creation
use_powershell_integration() {
    error_log="$1"
    issues_created="${2:-1}"

    log_step "Using PowerShell integration for GitHub issue creation"

    # Check if PowerShell script exists
    ps_script="automation/create-copilot-issues-optimized.ps1"
    if [ ! -f "$ps_script" ]; then
        log_error "PowerShell script not found: $ps_script"
        return 1
    fi

    # Create a temporary analysis file from error log
    temp_analysis="/tmp/autonomous-error-analysis.txt"
    create_error_analysis_for_powershell "$error_log" >"$temp_analysis"

    log_info "Created error analysis for PowerShell: $temp_analysis"
    log_info "Running PowerShell issue creation..."

    # Run PowerShell script with production mode
    if command -v pwsh >/dev/null 2>&1; then
        pwsh -File "$ps_script" -Production -MaxIssues "$issues_created" -PriorityFilter "Critical" -DebugMode
    elif command -v powershell >/dev/null 2>&1; then
        powershell -File "$ps_script" -Production -MaxIssues "$issues_created" -PriorityFilter "Critical" -DebugMode
    else
        log_error "PowerShell not available for issue creation"
        return 1
    fi

    # Clean up
    rm -f "$temp_analysis"

    log_success "PowerShell integration completed"
}

# Create error analysis in format expected by PowerShell script
create_error_analysis_for_powershell() {
    error_log="$1"

    cat <<EOF
# Autonomous Error Analysis
# Generated: $(date)
# Source: $error_log

## Critical Errors Detected

The autonomous monitoring system has detected critical errors that require immediate attention:

EOF

    # Extract recent critical errors
    if [ -f "$error_log" ]; then
        grep -A 20 "Category: CRITICAL" "$error_log" | head -50 || true
    fi

    cat <<EOF

## Recommended Actions

1. Review error details above
2. Check deployment logs for context
3. Test fixes in development environment
4. Deploy fixes via autonomous system

## Autonomous System Context

- Detection Method: Centralized error logging
- Error Source: $error_log
- Integration: PowerShell issue creation
- Priority: Critical (requires immediate attention)

EOF
}

# Direct GitHub API integration (alternative to PowerShell)
create_github_issue_direct() {
    title="$1"
    body="$2"
    labels="$3"

    log_step "Creating GitHub issue via API..."

    api_url="https://api.github.com/repos/${REPO_OWNER:-markus-lassfolk}/${REPO_NAME:-rutos-starlink-failover}/issues"

    # Create issue JSON
    issue_json=$(
        cat <<EOF
{
  "title": "$title",
  "body": $(echo "$body" | jq -R -s .),
  "labels": $(echo "$labels" | jq -R 'split(",") | map(select(length > 0))')
}
EOF
    )

    # Create the issue
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$issue_json" \
        "$api_url")

    # Check for success
    if echo "$response" | jq -e '.html_url' >/dev/null 2>&1; then
        issue_url=$(echo "$response" | jq -r '.html_url')
        log_success "Issue created: $issue_url"
        return 0
    else
        log_error "Failed to create issue. Response: $response"
        return 1
    fi
}

# Hybrid approach: Use both direct API and PowerShell
create_github_issue_hybrid() {
    error_context="$1"

    log_info "=== Hybrid GitHub Issue Creation ==="

    # Extract error details
    timestamp=$(date)
    host=$(hostname 2>/dev/null || echo "unknown")
    error_msg="Autonomous system detected critical errors"

    # Try direct API first (faster)
    log_step "Attempting direct GitHub API creation..."
    title="🤖 Autonomous Error Alert: $host - $timestamp"
    body="## 🤖 Autonomous Error Report

**Detection Time:** $timestamp  
**Host:** $host  
**Error Context:** $error_context  
**Summary:** $error_msg

### 🚨 Critical Error Detected

The autonomous monitoring system has detected critical errors requiring immediate attention.

### 🔧 Recommended Actions

1. ✅ Review the centralized error log
2. ✅ Check deployment status on affected systems
3. ✅ Investigate root cause
4. ✅ Deploy fixes via autonomous system

### 🤖 System Information

- **Autonomous System:** RUTOS Starlink Failover
- **Detection Method:** Centralized error logging
- **Priority:** Critical
- **Auto-Assignment:** GitHub Copilot

---
*This issue was created automatically by the autonomous monitoring system.*"

    labels="autonomous,critical,error,rutos"

    if create_github_issue_direct "$title" "$body" "$labels"; then
        log_success "Direct API issue creation successful"
        return 0
    else
        log_warning "Direct API failed, falling back to PowerShell integration"
        use_powershell_integration "/tmp/rutos-autonomous-errors.log" 1
    fi
}

# Test GitHub authentication methods
test_all_auth_methods() {
    log_info "=== Testing All GitHub Authentication Methods ==="

    success_count=0
    total_methods=4

    # Test 1: Environment variable
    log_step "Testing GITHUB_TOKEN environment variable..."
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        if test_github_token_validity "$GITHUB_TOKEN"; then
            log_success "✓ Environment GITHUB_TOKEN is valid"
            success_count=$((success_count + 1))
        else
            log_error "✗ Environment GITHUB_TOKEN is invalid"
        fi
    else
        log_warning "✗ GITHUB_TOKEN not set in environment"
    fi

    # Test 2: Saved token file
    log_step "Testing saved token file..."
    saved_token="/etc/autonomous-system/github-token"
    if [ -f "$saved_token" ]; then
        # Source the file and test token
        # shellcheck source=/dev/null
        (. "$saved_token" && test_github_token_validity "$GITHUB_TOKEN")
        token_test_result=$?
        if [ $token_test_result -eq 0 ]; then
            log_success "✓ Saved token file is valid"
            success_count=$((success_count + 1))
        else
            log_error "✗ Saved token file is invalid"
        fi
    else
        log_warning "✗ No saved token file found"
    fi

    # Test 3: GitHub CLI
    log_step "Testing GitHub CLI authentication..."
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            cli_token=$(gh auth token 2>/dev/null)
            if [ -n "$cli_token" ] && test_github_token_validity "$cli_token"; then
                log_success "✓ GitHub CLI authentication is valid"
                success_count=$((success_count + 1))
            else
                log_error "✗ GitHub CLI token is invalid"
            fi
        else
            log_warning "✗ GitHub CLI is not authenticated"
        fi
    else
        log_warning "✗ GitHub CLI not installed"
    fi

    # Test 4: PowerShell integration
    log_step "Testing PowerShell integration..."
    if command -v pwsh >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1; then
        if [ -f "automation/create-copilot-issues-optimized.ps1" ]; then
            log_success "✓ PowerShell and issue creation script available"
            success_count=$((success_count + 1))
        else
            log_warning "✗ PowerShell script not found"
        fi
    else
        log_warning "✗ PowerShell not available"
    fi

    # Summary
    log_info ""
    log_info "=== Authentication Test Summary ==="
    log_info "Methods available: $success_count/$total_methods"

    if [ $success_count -eq 0 ]; then
        log_error "❌ No GitHub authentication methods available"
        log_info "Run: ./setup-github-token-rutos.sh to configure authentication"
        return 1
    elif [ $success_count -ge 2 ]; then
        log_success "✅ Multiple authentication methods available (redundancy: good)"
        return 0
    else
        log_warning "⚠️  Only one authentication method available (consider setting up backup)"
        return 0
    fi
}

# Test token validity
test_github_token_validity() {
    token="$1"

    if [ -z "$token" ]; then
        return 1
    fi

    # Test API access
    response=$(curl -s -H "Authorization: Bearer $token" \
        "https://api.github.com/repos/${REPO_OWNER:-markus-lassfolk}/${REPO_NAME:-rutos-starlink-failover}")

    echo "$response" | grep -q '"name"'
}

# Main function
main() {
    case "${1:-test}" in
        "test")
            test_all_auth_methods
            ;;
        "setup")
            exec "./setup-github-token-rutos.sh"
            ;;
        "create-issue")
            create_github_issue_hybrid "${2:-Test error context}"
            ;;
        "powershell")
            use_powershell_integration "${2:-/tmp/rutos-autonomous-errors.log}" "${3:-1}"
            ;;
        *)
            log_info "Usage: $0 [test|setup|create-issue|powershell]"
            log_info "  test         - Test all authentication methods"
            log_info "  setup        - Run GitHub token setup"
            log_info "  create-issue - Create test issue (hybrid method)"
            log_info "  powershell   - Use PowerShell integration"
            exit 1
            ;;
    esac
}

# Default configuration
REPO_OWNER="${REPO_OWNER:-markus-lassfolk}"
REPO_NAME="${REPO_NAME:-rutos-starlink-failover}"

# Execute main function
main "$@"
