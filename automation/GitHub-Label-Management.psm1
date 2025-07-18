#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Comprehensive GitHub Label Management for RUTOS Starlink Failover Project
    
.DESCRIPTION
    This utility provides comprehensive label management functions for the RUTOS
    Starlink Failover automation system. It includes intelligent label assignment,
    progress tracking, and workflow status management.
    
.NOTES
    This module is used by both create-copilot-issues.ps1 and Monitor-CopilotPRs-Advanced.ps1
    to ensure consistent label management across the entire automation system.
#>

# =============================================================================
# LABEL DEFINITIONS AND CATEGORIES
# =============================================================================

# Define all available labels with their categories and descriptions
$script:LabelDefinitions = @{
    # Critical Priority Labels
    "critical-hardware-failure" = @{ Category = "Critical"; Color = "#B60205"; Description = "Issues that could cause hardware damage or system failure" }
    "critical-busybox-incompatible" = @{ Category = "Critical"; Color = "#B60205"; Description = "Code that will not run on busybox shell" }
    "critical-posix-violation" = @{ Category = "Critical"; Color = "#B60205"; Description = "POSIX compliance violations" }
    "critical-local-keyword" = @{ Category = "Critical"; Color = "#B60205"; Description = "Use of 'local' keyword (not supported in busybox)" }
    "critical-bash-arrays" = @{ Category = "Critical"; Color = "#B60205"; Description = "Bash array syntax (not supported in busybox)" }
    
    # Priority Labels
    "priority-critical" = @{ Category = "Priority"; Color = "#B60205"; Description = "Critical priority - must fix immediately" }
    "priority-major" = @{ Category = "Priority"; Color = "#D93F0B"; Description = "Major priority - should fix soon" }
    "priority-minor" = @{ Category = "Priority"; Color = "#FBCA04"; Description = "Minor priority - fix when possible" }
    
    # Issue Category Labels
    "rutos-compatibility" = @{ Category = "Category"; Color = "#0E8A16"; Description = "RUTOS router compatibility issues" }
    "shell-script" = @{ Category = "Category"; Color = "#1D76DB"; Description = "Shell script related issues" }
    "posix-compliance" = @{ Category = "Category"; Color = "#0E8A16"; Description = "POSIX compliance issues" }
    "busybox-compatibility" = @{ Category = "Category"; Color = "#0E8A16"; Description = "Busybox shell compatibility" }
    "shellcheck-issues" = @{ Category = "Category"; Color = "#5319E7"; Description = "ShellCheck validation issues" }
    "validation-failure" = @{ Category = "Category"; Color = "#D93F0B"; Description = "Validation system failures" }
    
    # Fix Type Labels
    "auto-fix-needed" = @{ Category = "FixType"; Color = "#0075CA"; Description = "Can be automatically fixed" }
    "manual-fix-needed" = @{ Category = "FixType"; Color = "#F9D0C4"; Description = "Requires manual intervention" }
    "copilot-fix" = @{ Category = "FixType"; Color = "#0075CA"; Description = "Copilot can fix this issue" }
    
    # Automation Labels
    "automated" = @{ Category = "Automation"; Color = "#0075CA"; Description = "Automated process" }
    "autonomous-system" = @{ Category = "Automation"; Color = "#0075CA"; Description = "Autonomous system operation" }
    "monitoring-system" = @{ Category = "Automation"; Color = "#0075CA"; Description = "Monitoring system related" }
    "self-healing" = @{ Category = "Automation"; Color = "#0075CA"; Description = "Self-healing system capability" }
    
    # Specific Issue Type Labels
    "type-bash-shebang" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Bash shebang line issues" }
    "type-local-variables" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Local variable usage issues" }
    "type-echo-dash-e" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "echo -e usage issues" }
    "type-double-brackets" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Double bracket [[ ]] usage" }
    "type-source-command" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Source command usage issues" }
    "type-pipefail" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Pipefail option issues" }
    "type-function-syntax" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Function syntax issues" }
    "type-printf-format" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Printf format string issues" }
    "type-color-definitions" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Color definition issues" }
    "type-dynamic-source" = @{ Category = "IssueType"; Color = "#E4E669"; Description = "Dynamic source issues" }
    
    # Workflow Status Labels
    "workflow-pending" = @{ Category = "WorkflowStatus"; Color = "#FBCA04"; Description = "Workflow is pending" }
    "workflow-failed" = @{ Category = "WorkflowStatus"; Color = "#D93F0B"; Description = "Workflow has failed" }
    "workflow-approved" = @{ Category = "WorkflowStatus"; Color = "#0E8A16"; Description = "Workflow has been approved" }
    "workflow-success" = @{ Category = "WorkflowStatus"; Color = "#0E8A16"; Description = "Workflow completed successfully" }
    
    # Merge Status Labels
    "merge-conflict" = @{ Category = "MergeStatus"; Color = "#D93F0B"; Description = "Merge conflict detected" }
    "merge-ready" = @{ Category = "MergeStatus"; Color = "#0E8A16"; Description = "Ready for merge" }
    
    # Validation Status Labels
    "validation-pending" = @{ Category = "ValidationStatus"; Color = "#FBCA04"; Description = "Validation is pending" }
    "validation-passed" = @{ Category = "ValidationStatus"; Color = "#0E8A16"; Description = "Validation has passed" }
    
    # Fix Status Labels
    "fix-in-progress" = @{ Category = "FixStatus"; Color = "#0075CA"; Description = "Fix is in progress" }
    "fix-requested" = @{ Category = "FixStatus"; Color = "#FBCA04"; Description = "Fix has been requested" }
    "fix-verified" = @{ Category = "FixStatus"; Color = "#0E8A16"; Description = "Fix has been verified" }
    "fix-failed" = @{ Category = "FixStatus"; Color = "#D93F0B"; Description = "Fix attempt failed" }
    "fix-retry" = @{ Category = "FixStatus"; Color = "#FBCA04"; Description = "Fix retry needed" }
    "fix-completed" = @{ Category = "FixStatus"; Color = "#0E8A16"; Description = "Fix completed successfully" }
    
    # Safety and Control Labels
    "anti-loop-protection" = @{ Category = "Safety"; Color = "#5319E7"; Description = "Anti-loop protection active" }
    "max-retries-reached" = @{ Category = "Safety"; Color = "#B60205"; Description = "Maximum retries reached" }
    "escalation-needed" = @{ Category = "Safety"; Color = "#B60205"; Description = "Manual escalation needed" }
    "rate-limited" = @{ Category = "Safety"; Color = "#FBCA04"; Description = "Rate limiting active" }
    "cost-optimized" = @{ Category = "Safety"; Color = "#0E8A16"; Description = "Cost optimization active" }
    
    # Component Labels
    "starlink-core" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Starlink core functionality" }
    "pushover-notifications" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Pushover notification system" }
    "azure-logging" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Azure logging integration" }
    "config-templates" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Configuration template system" }
    "installation-scripts" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Installation script system" }
    "validation-scripts" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Validation script system" }
    "monitoring-scripts" = @{ Category = "Component"; Color = "#1D76DB"; Description = "Monitoring script system" }
    
    # Scope Control Labels
    "scope-single-file" = @{ Category = "Scope"; Color = "#0E8A16"; Description = "Changes limited to single file" }
    "scope-validated" = @{ Category = "Scope"; Color = "#0E8A16"; Description = "Scope has been validated" }
    "scope-violation" = @{ Category = "Scope"; Color = "#B60205"; Description = "Scope violation detected" }
    "scope-warning" = @{ Category = "Scope"; Color = "#FBCA04"; Description = "Scope compliance warning" }
    
    # Progress Tracking Labels
    "attempt-1" = @{ Category = "Progress"; Color = "#0075CA"; Description = "First attempt" }
    "attempt-2" = @{ Category = "Progress"; Color = "#FBCA04"; Description = "Second attempt" }
    "attempt-3" = @{ Category = "Progress"; Color = "#D93F0B"; Description = "Third attempt (final)" }
    "created-today" = @{ Category = "Progress"; Color = "#0075CA"; Description = "Created today" }
    "stale" = @{ Category = "Progress"; Color = "#7057FF"; Description = "Stale issue/PR" }
    "blocked" = @{ Category = "Progress"; Color = "#D93F0B"; Description = "Blocked progress" }
    "waiting-for-copilot" = @{ Category = "Progress"; Color = "#0075CA"; Description = "Waiting for Copilot response" }
    
    # Detection Method Labels
    "detected-by-validation" = @{ Category = "Detection"; Color = "#5319E7"; Description = "Detected by validation system" }
    "detected-by-shellcheck" = @{ Category = "Detection"; Color = "#5319E7"; Description = "Detected by ShellCheck" }
    "detected-by-monitoring" = @{ Category = "Detection"; Color = "#5319E7"; Description = "Detected by monitoring system" }
    "detected-by-manual" = @{ Category = "Detection"; Color = "#5319E7"; Description = "Detected by manual review" }
    
    # Impact Assessment Labels
    "impact-high" = @{ Category = "Impact"; Color = "#B60205"; Description = "High impact issue" }
    "impact-medium" = @{ Category = "Impact"; Color = "#D93F0B"; Description = "Medium impact issue" }
    "impact-low" = @{ Category = "Impact"; Color = "#FBCA04"; Description = "Low impact issue" }
    "impact-cosmetic" = @{ Category = "Impact"; Color = "#C5DEF5"; Description = "Cosmetic impact only" }
    
    # Standard GitHub Labels
    "good-first-issue" = @{ Category = "GitHub"; Color = "#7057FF"; Description = "Good for newcomers" }
    "bug" = @{ Category = "GitHub"; Color = "#D73A49"; Description = "Something isn't working" }
    "dependency" = @{ Category = "GitHub"; Color = "#0366D6"; Description = "Dependency related" }
    "security" = @{ Category = "GitHub"; Color = "#D73A49"; Description = "Security related issue" }
    
    # Documentation and Content Labels
    "documentation" = @{ Category = "Documentation"; Color = "#0075CA"; Description = "Documentation improvements or additions" }
    "markdown" = @{ Category = "Documentation"; Color = "#1F77B4"; Description = "Markdown file formatting and structure" }
    "readme" = @{ Category = "Documentation"; Color = "#17A2B8"; Description = "README file updates" }
    "guide" = @{ Category = "Documentation"; Color = "#28A745"; Description = "User guide and tutorial content" }
    "api-docs" = @{ Category = "Documentation"; Color = "#6C757D"; Description = "API documentation and reference" }
    "changelog" = @{ Category = "Documentation"; Color = "#FD7E14"; Description = "Changelog and release notes" }
    "comments" = @{ Category = "Documentation"; Color = "#6F42C1"; Description = "Code comments and inline documentation" }
    
    # Feature Request and Enhancement Labels
    "enhancement" = @{ Category = "Enhancement"; Color = "#A2EEEF"; Description = "Feature enhancement or improvement" }
    "feature-request" = @{ Category = "Enhancement"; Color = "#00D4AA"; Description = "New feature request" }
    "suggestion" = @{ Category = "Enhancement"; Color = "#84D0FF"; Description = "Suggestion for improvement" }
    "recommendation" = @{ Category = "Enhancement"; Color = "#FFB84D"; Description = "Recommended change or best practice" }
    "user-story" = @{ Category = "Enhancement"; Color = "#C5DEF5"; Description = "User story or use case" }
    "epic" = @{ Category = "Enhancement"; Color = "#3E4B9E"; Description = "Large feature or epic" }
    "prototype" = @{ Category = "Enhancement"; Color = "#F9D71C"; Description = "Prototype or proof of concept" }
    "research" = @{ Category = "Enhancement"; Color = "#D4C5F9"; Description = "Research and investigation needed" }
    
    # Content Type Labels
    "content-typo" = @{ Category = "Content"; Color = "#FEF2C0"; Description = "Typo or spelling correction" }
    "content-grammar" = @{ Category = "Content"; Color = "#FFF2CC"; Description = "Grammar and language improvements" }
    "content-structure" = @{ Category = "Content"; Color = "#E1D5E7"; Description = "Content structure and organization" }
    "content-accuracy" = @{ Category = "Content"; Color = "#D1F2EB"; Description = "Content accuracy and factual corrections" }
    "content-outdated" = @{ Category = "Content"; Color = "#FADBD8"; Description = "Outdated content that needs updating" }
}

# =============================================================================
# LABEL MANAGEMENT FUNCTIONS
# =============================================================================

# Get intelligent labels based on issue analysis
function Get-IntelligentLabels {
    param(
        [string]$FilePath,
        [array]$Issues,
        [string]$Context = "issue",  # "issue", "pr", "workflow", "documentation", "enhancement", "content"
        [hashtable]$CustomLabels = @{},
        [string]$IssueTitle = "",
        [string]$IssueBody = ""
    )
    
    $labels = @()
    
    # Analyze title and body for content-related issues
    $combinedText = "$IssueTitle $IssueBody"
    
    # Content-related label detection
    if ($combinedText -match "typo|spelling|misspell" -or $FilePath -match "\.md$") {
        $labels += "content-typo"
    }
    if ($combinedText -match "grammar|sentence|language") {
        $labels += "content-grammar"
    }
    if ($combinedText -match "structure|organization|layout|format") {
        $labels += "content-structure"
    }
    if ($combinedText -match "outdated|old|deprecated|update.*content") {
        $labels += "content-outdated"
    }
    if ($combinedText -match "inaccurate|incorrect|wrong|fact") {
        $labels += "content-accuracy"
    }
    
    # Enhancement-related label detection
    if ($combinedText -match "suggest|recommendation|should|could|would be nice") {
        $labels += "suggestion"
    }
    if ($combinedText -match "recommend|best practice|guideline") {
        $labels += "recommendation"
    }
    if ($combinedText -match "feature request|new feature|add.*feature") {
        $labels += "feature-request"
    }
    if ($combinedText -match "user story|as a user|user needs") {
        $labels += "user-story"
    }
    if ($combinedText -match "epic|large feature|major.*feature") {
        $labels += "epic"
    }
    if ($combinedText -match "prototype|proof of concept|poc|experiment") {
        $labels += "prototype"
    }
    if ($combinedText -match "research|investigate|study|analyze") {
        $labels += "research"
    }
    
    # Documentation-related label detection
    if ($combinedText -match "documentation|docs|document") {
        $labels += "documentation"
    }
    if ($combinedText -match "api.*doc|document.*api") {
        $labels += "api-docs"
    }
    if ($combinedText -match "guide|tutorial|how.*to|walkthrough") {
        $labels += "guide"
    }
    if ($combinedText -match "changelog|release.*note|version.*history") {
        $labels += "changelog"
    }
    if ($combinedText -match "comment|inline.*doc|code.*comment") {
        $labels += "comments"
    }
    
    if ($Issues -and $Issues.Count -gt 0) {
        # Classify issues
        $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
        $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }
        
        # Priority labels based on highest severity present
        if ($criticalIssues.Count -gt 0) {
            $labels += "priority-critical"
        } elseif ($majorIssues.Count -gt 0) {
            $labels += "priority-major"
        } else {
            $labels += "priority-minor"
        }
        
        # Add specific critical issue type labels
        foreach ($issue in $criticalIssues) {
            $issueText = $issue.Line
            if ($issueText -match "local\s+\w+") {
                $labels += "critical-local-keyword"
            }
            if ($issueText -match "#!/bin/bash") {
                $labels += "type-bash-shebang"
            }
            if ($issueText -match "\[\[.*\]\]") {
                $labels += "critical-posix-violation"
            }
            if ($issueText -match "declare\s+-[aA]" -or $issueText -match "\w+\s*=\s*\(" -or $issueText -match "\[\d+\]") {
                $labels += "critical-bash-arrays"
            }
            if ($issueText -match "set\s+-o\s+pipefail" -or $issueText -match "busybox") {
                $labels += "critical-busybox-incompatible"
            }
        }
        
        # Add specific issue type labels
        $allIssuesText = ($Issues | ForEach-Object { $_.Line }) -join " "
        
        if ($allIssuesText -match "echo\s+-e") { $labels += "type-echo-dash-e" }
        if ($allIssuesText -match "source\s+") { $labels += "type-source-command" }
        if ($allIssuesText -match "function\s+\w+\s*\(\s*\)") { $labels += "type-function-syntax" }
        if ($allIssuesText -match "printf.*\$\{.*\}") { $labels += "type-printf-format" }
        if ($allIssuesText -match "tput\s+colors" -or $allIssuesText -match "command\s+-v\s+tput") { $labels += "type-color-definitions" }
        if ($allIssuesText -match "SC1090" -or $allIssuesText -match "SC1091") { $labels += "type-dynamic-source" }
        if ($allIssuesText -match "set\s+-o\s+pipefail") { $labels += "type-pipefail" }
        if ($allIssuesText -match "\[\[.*\]\]") { $labels += "type-double-brackets" }
        if ($allIssuesText -match "local\s+\w+") { $labels += "type-local-variables" }
        
        # Impact assessment
        if ($criticalIssues.Count -gt 0) {
            $labels += "impact-high"
        } elseif ($majorIssues.Count -gt 0) {
            $labels += "impact-medium"
        } else {
            $labels += "impact-low"
        }
        
        # Detection method
        $labels += "detected-by-validation"
        if ($minorIssues.Count -gt 0) {
            $labels += "detected-by-shellcheck"
        }
        
        # Fix type
        if ($criticalIssues.Count -gt 0) {
            $labels += "auto-fix-needed"
        } else {
            $labels += "manual-fix-needed"
        }
    }
    
    # Core system labels
    $labels += "rutos-compatibility"
    $labels += "copilot-fix"
    $labels += "automated"
    $labels += "autonomous-system"
    $labels += "monitoring-system"
    
    # File-based labels
    if ($FilePath) {
        if ($FilePath -match "\.sh$") { $labels += "shell-script" }
        if ($FilePath -match "\.md$") { $labels += "markdown" }
        if ($FilePath -match "README\.md$") { $labels += "readme" }
        if ($FilePath -match "CHANGELOG|HISTORY") { $labels += "changelog" }
        if ($FilePath -match "docs/.*\.md$") { $labels += "guide" }
        if ($FilePath -match "API|api") { $labels += "api-docs" }
        if ($FilePath -match "config/") { $labels += "config-templates" }
        if ($FilePath -match "scripts/install") { $labels += "installation-scripts" }
        if ($FilePath -match "scripts/.*validate") { $labels += "validation-scripts" }
        if ($FilePath -match "starlink.*monitor") { 
            $labels += "monitoring-scripts"
            $labels += "starlink-core"
        }
        if ($FilePath -match "azure") { $labels += "azure-logging" }
        if ($FilePath -match "pushover") { $labels += "pushover-notifications" }
    }
    
    # Context-specific labels
    switch ($Context) {
        "issue" {
            $labels += "posix-compliance"
            $labels += "busybox-compatibility"
            $labels += "shellcheck-issues"
            $labels += "scope-single-file"
            $labels += "scope-validated"
            $labels += "attempt-1"
            $labels += "created-today"
            $labels += "waiting-for-copilot"
            $labels += "workflow-pending"
            $labels += "validation-pending"
            $labels += "cost-optimized"
            $labels += "anti-loop-protection"
        }
        "pr" {
            $labels += "validation-pending"
            $labels += "workflow-pending"
            $labels += "fix-in-progress"
        }
        "workflow" {
            $labels += "workflow-pending"
            $labels += "monitoring-system"
        }
        "documentation" {
            $labels += "documentation"
            if ($FilePath -match "\.md$") { $labels += "markdown" }
            if ($FilePath -match "README") { $labels += "readme" }
            if ($FilePath -match "guide|tutorial") { $labels += "guide" }
        }
        "enhancement" {
            $labels += "enhancement"
            # Could add feature-request, suggestion, etc. based on other context
        }
        "content" {
            # Content-specific labels would be added based on the type of content issue
            $labels += "content-accuracy"  # Default for content issues
        }
    }
    
    # Add custom labels
    if ($CustomLabels.Count -gt 0) {
        $labels += $CustomLabels.Keys
    }
    
    # Remove duplicates and sort
    $labels = $labels | Sort-Object -Unique
    
    return $labels
}

# Update PR labels based on status
function Update-PRLabels {
    param(
        [int]$PRNumber,
        [string]$Status,
        [array]$ValidationResults = @(),
        [bool]$DryRun = $false
    )
    
    $labelsToAdd = @()
    $labelsToRemove = @()
    
    switch ($Status) {
        "ValidationPassed" {
            $labelsToAdd += "validation-passed"
            $labelsToRemove += "validation-pending", "validation-failure"
        }
        "ValidationFailed" {
            $labelsToAdd += "validation-failure"
            $labelsToRemove += "validation-passed", "validation-pending"
        }
        "WorkflowSuccess" {
            $labelsToAdd += "workflow-success"
            $labelsToRemove += "workflow-pending", "workflow-failed"
        }
        "WorkflowFailed" {
            $labelsToAdd += "workflow-failed"
            $labelsToRemove += "workflow-pending", "workflow-success"
        }
        "MergeReady" {
            $labelsToAdd += "merge-ready"
            $labelsToRemove += "merge-conflict", "workflow-pending", "validation-pending"
        }
        "MergeConflict" {
            $labelsToAdd += "merge-conflict"
            $labelsToRemove += "merge-ready"
        }
        "FixCompleted" {
            $labelsToAdd += "fix-completed"
            $labelsToRemove += "fix-in-progress", "fix-requested", "fix-failed"
        }
        "FixFailed" {
            $labelsToAdd += "fix-failed"
            $labelsToRemove += "fix-in-progress", "fix-requested"
        }
        "ScopeViolation" {
            $labelsToAdd += "scope-violation"
            $labelsToRemove += "scope-validated"
        }
        "ScopeValidated" {
            $labelsToAdd += "scope-validated"
            $labelsToRemove += "scope-violation", "scope-warning"
        }
    }
    
    # Add intelligence based on validation results
    if ($ValidationResults.Count -gt 0) {
        $criticalIssues = $ValidationResults | Where-Object { $_.Type -eq "Critical" }
        if ($criticalIssues.Count -gt 0) {
            $labelsToAdd += "priority-critical"
            $labelsToRemove += "priority-major", "priority-minor"
        }
    }
    
    # Apply labels if not in dry run mode
    if (-not $DryRun) {
        foreach ($label in $labelsToAdd) {
            if ($script:LabelDefinitions.ContainsKey($label)) {
                try {
                    gh pr edit $PRNumber --add-label $label
                    Write-Host "✅ Added label: $label to PR #$PRNumber" -ForegroundColor Green
                } catch {
                    Write-Host "❌ Failed to add label: $label to PR #$PRNumber" -ForegroundColor Red
                }
            }
        }
        
        foreach ($label in $labelsToRemove) {
            try {
                gh pr edit $PRNumber --remove-label $label
                Write-Host "🗑️  Removed label: $label from PR #$PRNumber" -ForegroundColor Yellow
            } catch {
                # Label might not exist, which is fine
                Write-Host "ℹ️  Label $label was not present on PR #$PRNumber" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "🏷️  [DRY RUN] Would update PR #$PRNumber labels:" -ForegroundColor Cyan
        if ($labelsToAdd.Count -gt 0) {
            Write-Host "   Add: $($labelsToAdd -join ', ')" -ForegroundColor Green
        }
        if ($labelsToRemove.Count -gt 0) {
            Write-Host "   Remove: $($labelsToRemove -join ', ')" -ForegroundColor Yellow
        }
    }
    
    return @{
        Added = $labelsToAdd
        Removed = $labelsToRemove
    }
}

# Update issue labels based on progress
function Update-IssueLabels {
    param(
        [int]$IssueNumber,
        [string]$Status,
        [int]$AttemptNumber = 1,
        [bool]$DryRun = $false
    )
    
    $labelsToAdd = @()
    $labelsToRemove = @()
    
    # Update attempt labels
    switch ($AttemptNumber) {
        1 { 
            $labelsToAdd += "attempt-1"
            $labelsToRemove += "attempt-2", "attempt-3"
        }
        2 { 
            $labelsToAdd += "attempt-2"
            $labelsToRemove += "attempt-1", "attempt-3"
        }
        3 { 
            $labelsToAdd += "attempt-3"
            $labelsToRemove += "attempt-1", "attempt-2"
        }
    }
    
    # Update status labels
    switch ($Status) {
        "InProgress" {
            $labelsToAdd += "fix-in-progress"
            $labelsToRemove += "waiting-for-copilot", "fix-requested"
        }
        "Completed" {
            $labelsToAdd += "fix-completed"
            $labelsToRemove += "fix-in-progress", "fix-requested", "fix-failed"
        }
        "Failed" {
            $labelsToAdd += "fix-failed"
            $labelsToRemove += "fix-in-progress", "fix-requested"
        }
        "Escalated" {
            $labelsToAdd += "escalation-needed"
            $labelsToRemove += "waiting-for-copilot"
        }
        "MaxRetries" {
            $labelsToAdd += "max-retries-reached"
            $labelsToAdd += "escalation-needed"
        }
    }
    
    # Apply labels if not in dry run mode
    if (-not $DryRun) {
        foreach ($label in $labelsToAdd) {
            if ($script:LabelDefinitions.ContainsKey($label)) {
                try {
                    gh issue edit $IssueNumber --add-label $label
                    Write-Host "✅ Added label: $label to issue #$IssueNumber" -ForegroundColor Green
                } catch {
                    Write-Host "❌ Failed to add label: $label to issue #$IssueNumber" -ForegroundColor Red
                }
            }
        }
        
        foreach ($label in $labelsToRemove) {
            try {
                gh issue edit $IssueNumber --remove-label $label
                Write-Host "🗑️  Removed label: $label from issue #$IssueNumber" -ForegroundColor Yellow
            } catch {
                # Label might not exist, which is fine
                Write-Host "ℹ️  Label $label was not present on issue #$IssueNumber" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "🏷️  [DRY RUN] Would update issue #$IssueNumber labels:" -ForegroundColor Cyan
        if ($labelsToAdd.Count -gt 0) {
            Write-Host "   Add: $($labelsToAdd -join ', ')" -ForegroundColor Green
        }
        if ($labelsToRemove.Count -gt 0) {
            Write-Host "   Remove: $($labelsToRemove -join ', ')" -ForegroundColor Yellow
        }
    }
    
    return @{
        Added = $labelsToAdd
        Removed = $labelsToRemove
    }
}

# Get label information
function Get-LabelInfo {
    param(
        [string]$LabelName
    )
    
    if ($script:LabelDefinitions.ContainsKey($LabelName)) {
        return $script:LabelDefinitions[$LabelName]
    }
    
    return $null
}

# Get labels by category
function Get-LabelsByCategory {
    param(
        [string]$Category
    )
    
    return $script:LabelDefinitions.Keys | Where-Object { 
        $script:LabelDefinitions[$_].Category -eq $Category 
    }
}

# Display label statistics
function Show-LabelStatistics {
    param(
        [array]$Labels
    )
    
    Write-Host "🏷️  Label Statistics:" -ForegroundColor Cyan
    
    $categoryStats = @{}
    foreach ($label in $Labels) {
        $labelInfo = Get-LabelInfo -LabelName $label
        if ($labelInfo) {
            $category = $labelInfo.Category
            if (-not $categoryStats.ContainsKey($category)) {
                $categoryStats[$category] = 0
            }
            $categoryStats[$category]++
        }
    }
    
    foreach ($category in $categoryStats.Keys | Sort-Object) {
        Write-Host "   $category`: $($categoryStats[$category]) labels" -ForegroundColor White
    }
    
    Write-Host "   Total: $($Labels.Count) labels" -ForegroundColor Green
}

# Export functions for use in other scripts
Export-ModuleMember -Function @(
    'Get-IntelligentLabels',
    'Update-PRLabels',
    'Update-IssueLabels',
    'Get-LabelInfo',
    'Get-LabelsByCategory',
    'Show-LabelStatistics'
)

# Module initialization
Write-Host "🏷️  GitHub Label Management Module Loaded" -ForegroundColor Green
Write-Host "   Available Labels: $($script:LabelDefinitions.Count)" -ForegroundColor Cyan
Write-Host "   Categories: $($script:LabelDefinitions.Values.Category | Sort-Object -Unique | Measure-Object).Count" -ForegroundColor Yellow
