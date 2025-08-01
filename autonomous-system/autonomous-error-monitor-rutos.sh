#!/bin/bash
# ==============================================================================
# Autonomous Error Monitor & GitHub Issue Creator
# 
# This script monitors error logs from autonomous deployments and creates
# GitHub issues for any errors found, with integration to existing PowerShell
# issue creation workflows.
#
# Features:
# - Continuous error log monitoring
# - Intelligent error parsing and categorization
# - GitHub issue creation with detailed context
# - Integration with PowerShell issue scripts
# - Duplicate issue detection and management
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="1.0.0"
CONFIG_FILE="${CONFIG_FILE:-./autonomous-config.conf}"
LOG_DIR="${LOG_DIR:-./logs}"
ERROR_LOG="$LOG_DIR/autonomous-errors.log"
MONITOR_LOG="$LOG_DIR/error-monitor.log"
PROCESSED_ERRORS="$LOG_DIR/processed-errors.db"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Try to load GitHub authentication from multiple sources
load_github_auth() {
    # Method 1: Environment variable already set
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        log_debug "Using GITHUB_TOKEN from environment"
        return 0
    fi
    
    # Method 2: Load from saved token file
    local saved_token="/etc/autonomous-system/github-token"
    if [ -f "$saved_token" ]; then
        log_debug "Loading GitHub token from $saved_token"
        . "$saved_token"
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            export GITHUB_TOKEN
            return 0
        fi
    fi
    
    # Method 3: Try GitHub CLI
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        log_debug "Extracting token from GitHub CLI"
        GITHUB_TOKEN=$(gh auth token 2>/dev/null)
        if [ -n "$GITHUB_TOKEN" ]; then
            export GITHUB_TOKEN
            return 0
        fi
    fi
    
    # Method 4: Check for auth loader script
    local auth_loader="/etc/autonomous-system/load-github-auth.sh"
    if [ -f "$auth_loader" ]; then
        log_debug "Using GitHub auth loader: $auth_loader"
        . "$auth_loader"
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            return 0
        fi
    fi
    
    return 1
}

# Load GitHub authentication
if ! load_github_auth; then
    echo "ERROR: GitHub authentication not available" >&2
    echo "Available setup methods:" >&2
    echo "1. Run: ./setup-github-token-rutos.sh" >&2
    echo "2. Set: export GITHUB_TOKEN='your_token'" >&2
    echo "3. Use: gh auth login" >&2
    exit 1
fi

# Required configuration (with defaults)
: "${REPO_OWNER:=${GITHUB_REPO_OWNER:-markus-lassfolk}}"
: "${REPO_NAME:=${GITHUB_REPO_NAME:-rutos-starlink-failover}}"

# Create necessary files
mkdir -p "$LOG_DIR"
touch "$PROCESSED_ERRORS"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR] [INFO] $*" | tee -a "$MONITOR_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR] [ERROR] $*" | tee -a "$MONITOR_LOG"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR] [DEBUG] $*" | tee -a "$MONITOR_LOG"
    fi
}

# Generate unique error hash for duplicate detection
generate_error_hash() {
    local error_msg="$1"
    local script_name="$2"
    local host="$3"
    
    # Create hash from error message and script (excluding timestamp and host)
    echo "${error_msg}|${script_name}" | sha256sum | cut -d' ' -f1
}

# Check if error was already processed
is_error_processed() {
    local error_hash="$1"
    grep -q "^$error_hash" "$PROCESSED_ERRORS" 2>/dev/null
}

# Mark error as processed
mark_error_processed() {
    local error_hash="$1"
    local timestamp="$2"
    echo "$error_hash|$timestamp" >> "$PROCESSED_ERRORS"
}

# Extract detailed error context
extract_error_context() {
    local error_entry="$1"
    
    # Parse the structured error entry
    local timestamp=$(echo "$error_entry" | grep "^Timestamp:" | cut -d' ' -f2-)
    local host=$(echo "$error_entry" | grep "^Host:" | cut -d' ' -f2-)
    local script=$(echo "$error_entry" | grep "^Script:" | cut -d' ' -f2-)
    local error_msg=$(echo "$error_entry" | grep "^Error:" | cut -d' ' -f2-)
    local full_line=$(echo "$error_entry" | grep "^Full Line:" | cut -d' ' -f3-)
    local deployment_log=$(echo "$error_entry" | grep "^Deployment Log:" | cut -d' ' -f3-)
    
    # Create JSON structure for issue creation
    cat << EOF
{
    "timestamp": "$timestamp",
    "host": "$host",
    "script": "$script",
    "error_message": "$error_msg",
    "full_line": "$full_line",
    "deployment_log": "$deployment_log",
    "severity": "high"
}
EOF
}

# Create GitHub issue using PowerShell integration
create_github_issue() {
    local error_context="$1"
    
    # Extract key fields for issue creation
    local timestamp=$(echo "$error_context" | jq -r '.timestamp')
    local host=$(echo "$error_context" | jq -r '.host')
    local script=$(echo "$error_context" | jq -r '.script')
    local error_msg=$(echo "$error_context" | jq -r '.error_message')
    local full_line=$(echo "$error_context" | jq -r '.full_line')
    
    # Create issue title and body
    local issue_title="🤖 Autonomous Deployment Error: $script on $host"
    local issue_body=$(cat << EOF
## 🤖 Autonomous Error Report

**Detected by:** Autonomous Monitoring System  
**Timestamp:** $timestamp  
**Host:** $host  
**Script:** $script  

### 🚨 Error Details

\`\`\`
$error_msg
\`\`\`

### 📋 Full Error Line

\`\`\`
$full_line
\`\`\`

### 🔍 Analysis Required

This error was automatically detected during autonomous deployment. Please:

1. ✅ Review the error context above
2. ✅ Check the deployment log for additional details
3. ✅ Identify the root cause
4. ✅ Implement a fix
5. ✅ Test the fix on the affected host: $host

### 🤖 Autonomous System Information

- **Detection Time:** $timestamp
- **Affected Host:** $host
- **Script Path:** $script
- **Deployment Mode:** Autonomous
- **Next Deployment:** Will use fixed code automatically

### 🔧 Quick Fix Commands

\`\`\`bash
# Test the fix locally
./scripts/$script --debug --dry-run

# Deploy fix to affected host
ssh root@$host "curl -fsSL https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/scripts/bootstrap-deploy-v3-rutos.sh | DEBUG=1 sh"
\`\`\`

**Auto-assigned to:** @github-copilot  
**Priority:** High  
**Type:** Autonomous Bug Report  
EOF
)

    log_info "🎫 Creating GitHub issue for error: $script on $host"
    
    # Use GitHub CLI to create issue
    if command -v gh >/dev/null 2>&1; then
        local issue_url=$(gh issue create \
            --repo "$REPO_OWNER/$REPO_NAME" \
            --title "$issue_title" \
            --body "$issue_body" \
            --label "autonomous,bug,deployment-error" \
            --assignee "github-copilot" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            log_info "✅ GitHub issue created: $issue_url"
            return 0
        else
            log_error "❌ Failed to create GitHub issue: $issue_url"
            return 1
        fi
    else
        # Fallback to PowerShell script if available
        if [[ -f "./scripts/create-issue.ps1" ]]; then
            log_info "📜 Using PowerShell fallback for issue creation"
            pwsh -File "./scripts/create-issue.ps1" \
                -Title "$issue_title" \
                -Body "$issue_body" \
                -Label "autonomous,bug,deployment-error" \
                -Assignee "github-copilot"
            return $?
        else
            log_error "❌ No GitHub issue creation method available (gh CLI or PowerShell script)"
            return 1
        fi
    fi
}

# Process new errors from log
process_new_errors() {
    local processed_count=0
    local new_errors=0
    
    if [[ ! -f "$ERROR_LOG" ]]; then
        log_debug "🔍 No error log found: $ERROR_LOG"
        return 0
    fi
    
    log_info "🔍 Scanning for new errors in $ERROR_LOG"
    
    # Read error log and process each error entry
    local current_entry=""
    local in_entry=false
    
    while IFS= read -r line; do
        if [[ "$line" == "===== AUTONOMOUS ERROR ENTRY =====" ]]; then
            in_entry=true
            current_entry=""
        elif [[ "$line" == "=====================================" ]] && [[ "$in_entry" == true ]]; then
            in_entry=false
            
            if [[ -n "$current_entry" ]]; then
                # Extract error details for hash generation
                local error_msg=$(echo "$current_entry" | grep "^Error:" | cut -d' ' -f2-)
                local script_name=$(echo "$current_entry" | grep "^Script:" | cut -d' ' -f2-)
                local host=$(echo "$current_entry" | grep "^Host:" | cut -d' ' -f2-)
                
                # Generate hash for duplicate detection
                local error_hash=$(generate_error_hash "$error_msg" "$script_name" "$host")
                
                processed_count=$((processed_count + 1))
                
                if ! is_error_processed "$error_hash"; then
                    log_info "🆕 New error detected: $script_name on $host"
                    log_debug "🔍 Error hash: $error_hash"
                    
                    # Extract context and create issue
                    local error_context=$(extract_error_context "$current_entry")
                    
                    if create_github_issue "$error_context"; then
                        mark_error_processed "$error_hash" "$(date '+%Y-%m-%d %H:%M:%S')"
                        new_errors=$((new_errors + 1))
                        log_info "✅ Issue created and error marked as processed"
                    else
                        log_error "❌ Failed to create issue for error"
                    fi
                else
                    log_debug "🔄 Error already processed (hash: $error_hash)"
                fi
            fi
        elif [[ "$in_entry" == true ]]; then
            current_entry+="$line"$'\n'
        fi
    done < "$ERROR_LOG"
    
    log_info "📊 Error processing summary:"
    log_info "   - Total entries processed: $processed_count"
    log_info "   - New issues created: $new_errors"
    
    return 0
}

# Cleanup old processed errors (keep last 30 days)
cleanup_processed_errors() {
    local cutoff_date=$(date -d '30 days ago' '+%Y-%m-%d')
    local temp_file=$(mktemp)
    
    if [[ -f "$PROCESSED_ERRORS" ]]; then
        # Keep only recent entries
        while IFS='|' read -r hash timestamp; do
            if [[ "$timestamp" > "$cutoff_date" ]]; then
                echo "$hash|$timestamp" >> "$temp_file"
            fi
        done < "$PROCESSED_ERRORS"
        
        mv "$temp_file" "$PROCESSED_ERRORS"
        log_debug "🧹 Cleaned up old processed errors"
    fi
}

# Main monitoring loop
main_monitor() {
    log_info "🎯 Starting autonomous error monitoring"
    log_info "📊 Configuration:"
    log_info "   - Error Log: $ERROR_LOG"
    log_info "   - Monitor Log: $MONITOR_LOG"
    log_info "   - Processed DB: $PROCESSED_ERRORS"
    log_info "   - GitHub Repo: $REPO_OWNER/$REPO_NAME"
    
    # Single run mode (for cron) vs continuous mode
    if [[ "${CONTINUOUS_MODE:-false}" == "true" ]]; then
        log_info "🔄 Running in continuous monitoring mode"
        local check_interval="${CHECK_INTERVAL:-300}" # 5 minutes default
        
        while true; do
            process_new_errors
            cleanup_processed_errors
            log_debug "😴 Sleeping for $check_interval seconds"
            sleep "$check_interval"
        done
    else
        log_info "🔄 Running in single-check mode (cron-friendly)"
        process_new_errors
        cleanup_processed_errors
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_monitor "$@"
fi
