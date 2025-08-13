#!/usr/bin/env pwsh
# Script: create-github-labels.ps1
# Version: 1.0.0
# Description: Create comprehensive GitHub labels for RUTOS Starlink Failover project

param(
    [switch]$DryRun = $false,
    [switch]$Force = $false,
    [switch]$DebugMode = $false
)

# Color definitions
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$PURPLE = [ConsoleColor]::Magenta

function Write-StatusMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Comprehensive label definitions
$labels = @(
    # Critical Priority Labels
    @{ name = "critical-hardware-failure"; color = "b60205"; description = "Issues that will cause failures on RUTX50 hardware" },
    @{ name = "critical-busybox-incompatible"; color = "b60205"; description = "Code that won't work in busybox environment" },
    @{ name = "critical-posix-violation"; color = "b60205"; description = "Non-POSIX shell code that breaks RUTOS compatibility" },
    @{ name = "critical-local-keyword"; color = "b60205"; description = "Uses 'local' keyword (not supported in busybox)" },
    @{ name = "critical-bash-arrays"; color = "b60205"; description = "Uses bash arrays (not supported in busybox)" },

    # Issue Priority Labels
    @{ name = "priority-critical"; color = "d73a49"; description = "Must be fixed immediately (hardware compatibility)" },
    @{ name = "priority-major"; color = "fbca04"; description = "Should be fixed soon (may cause runtime issues)" },
    @{ name = "priority-minor"; color = "0075ca"; description = "Nice to have (best practices, portability)" },

    # Issue Category Labels
    @{ name = "rutos-compatibility"; color = "1d76db"; description = "General RUTOS compatibility issues" },
    @{ name = "shell-script"; color = "5319e7"; description = "Shell script related issues" },
    @{ name = "posix-compliance"; color = "0052cc"; description = "POSIX shell compliance issues" },
    @{ name = "busybox-compatibility"; color = "0e8a16"; description = "Busybox specific compatibility issues" },
    @{ name = "shellcheck-issues"; color = "f9d0c4"; description = "ShellCheck validation failures" },
    @{ name = "validation-failure"; color = "d93f0b"; description = "Failed pre-commit validation" },
    @{ name = "auto-fix-needed"; color = "7057ff"; description = "Issues that can be automatically fixed" },
    @{ name = "manual-fix-needed"; color = "e99695"; description = "Issues requiring manual intervention" },

    # Automation Labels
    @{ name = "copilot-fix"; color = "6f42c1"; description = "Issues assigned to GitHub Copilot" },
    @{ name = "automated"; color = "1f883d"; description = "Automatically generated issues/PRs" },
    @{ name = "autonomous-system"; color = "238636"; description = "Created by autonomous issue system" },
    @{ name = "monitoring-system"; color = "2ea043"; description = "Created by PR monitoring system" },
    @{ name = "self-healing"; color = "8b5cf6"; description = "Self-resolving automation issues" },

    # Issue Type Labels
    @{ name = "type-bash-shebang"; color = "fef2c0"; description = "Uses #!/bin/bash instead of #!/bin/sh" },
    @{ name = "type-local-variables"; color = "fef2c0"; description = "Uses 'local' keyword" },
    @{ name = "type-echo-dash-e"; color = "fef2c0"; description = "Uses 'echo -e' instead of printf" },
    @{ name = "type-double-brackets"; color = "fef2c0"; description = "Uses [[]] instead of []" },
    @{ name = "type-source-command"; color = "fef2c0"; description = "Uses 'source' instead of '.'" },
    @{ name = "type-pipefail"; color = "fef2c0"; description = "Uses 'set -o pipefail' (not POSIX)" },
    @{ name = "type-function-syntax"; color = "fef2c0"; description = "Uses 'function()' syntax" },
    @{ name = "type-printf-format"; color = "fef2c0"; description = "Printf format string issues (SC2059)" },
    @{ name = "type-color-definitions"; color = "fef2c0"; description = "Missing color variable definitions" },
    @{ name = "type-dynamic-source"; color = "fef2c0"; description = "ShellCheck can't follow dynamic sources" },

    # Workflow Labels
    @{ name = "workflow-pending"; color = "fbca04"; description = "Awaiting workflow approval" },
    @{ name = "workflow-failed"; color = "d73a49"; description = "Workflow execution failed" },
    @{ name = "workflow-approved"; color = "0e8a16"; description = "Workflow approved and running" },
    @{ name = "workflow-success"; color = "28a745"; description = "All workflows passed" },
    @{ name = "merge-conflict"; color = "d73a49"; description = "Has merge conflicts" },
    @{ name = "merge-ready"; color = "0e8a16"; description = "Ready for merge" },
    @{ name = "validation-pending"; color = "fbca04"; description = "Awaiting validation" },
    @{ name = "validation-passed"; color = "28a745"; description = "Validation successful" },

    # Fix Status Labels
    @{ name = "fix-in-progress"; color = "fbca04"; description = "Fix is being worked on" },
    @{ name = "fix-requested"; color = "0052cc"; description = "Fix has been requested from Copilot" },
    @{ name = "fix-verified"; color = "28a745"; description = "Fix has been verified to work" },
    @{ name = "fix-failed"; color = "d73a49"; description = "Fix attempt failed" },
    @{ name = "fix-retry"; color = "f9d0c4"; description = "Retry needed for fix" },
    @{ name = "fix-completed"; color = "0e8a16"; description = "Fix successfully completed" },

    # System Status Labels
    @{ name = "anti-loop-protection"; color = "5319e7"; description = "Has protection against infinite loops" },
    @{ name = "max-retries-reached"; color = "d73a49"; description = "Maximum retry attempts reached" },
    @{ name = "escalation-needed"; color = "b60205"; description = "Needs manual review/escalation" },
    @{ name = "rate-limited"; color = "fbca04"; description = "Rate limiting applied" },
    @{ name = "cost-optimized"; color = "0e8a16"; description = "Cost optimization measures applied" },

    # File/Component Labels
    @{ name = "starlink-core"; color = "1d76db"; description = "Core Starlink monitoring files" },
    @{ name = "pushover-notifications"; color = "f9d0c4"; description = "Pushover notification system" },
    @{ name = "azure-logging"; color = "0078d4"; description = "Azure logging integration" },
    @{ name = "config-templates"; color = "7057ff"; description = "Configuration template files" },
    @{ name = "installation-scripts"; color = "238636"; description = "Installation and setup scripts" },
    @{ name = "validation-scripts"; color = "d93f0b"; description = "Validation and testing scripts" },
    @{ name = "monitoring-scripts"; color = "2ea043"; description = "System monitoring scripts" },

    # Scope Control Labels
    @{ name = "scope-single-file"; color = "0052cc"; description = "Should only modify one file" },
    @{ name = "scope-validated"; color = "28a745"; description = "Scope has been validated" },
    @{ name = "scope-violation"; color = "d73a49"; description = "Scope has been exceeded" },
    @{ name = "scope-warning"; color = "fbca04"; description = "Potential scope issues detected" },

    # Progress Tracking Labels
    @{ name = "attempt-1"; color = "e1e4e8"; description = "First attempt" },
    @{ name = "attempt-2"; color = "d1d5da"; description = "Second attempt" },
    @{ name = "attempt-3"; color = "c6cbd1"; description = "Third attempt (final)" },
    @{ name = "created-today"; color = "0e8a16"; description = "Created in the last 24 hours" },
    @{ name = "stale"; color = "6a737d"; description = "No activity for extended period" },
    @{ name = "blocked"; color = "d73a49"; description = "Blocked by external dependency" },
    @{ name = "waiting-for-copilot"; color = "6f42c1"; description = "Waiting for Copilot response" },

    # Detection Method Labels
    @{ name = "detected-by-validation"; color = "2ea043"; description = "Found by validation system" },
    @{ name = "detected-by-shellcheck"; color = "f9d0c4"; description = "Found by ShellCheck" },
    @{ name = "detected-by-monitoring"; color = "238636"; description = "Found by monitoring system" },
    @{ name = "detected-by-manual"; color = "6a737d"; description = "Manually identified" },

    # Impact Assessment Labels
    @{ name = "impact-high"; color = "d73a49"; description = "High impact on system functionality" },
    @{ name = "impact-medium"; color = "fbca04"; description = "Medium impact on system functionality" },
    @{ name = "impact-low"; color = "0e8a16"; description = "Low impact on system functionality" },
    @{ name = "impact-cosmetic"; color = "e1e4e8"; description = "Cosmetic/style changes only" },

    # Documentation and Content Labels
    @{ name = "documentation"; color = "0075ca"; description = "Documentation improvements or additions" },
    @{ name = "markdown"; color = "1f77b4"; description = "Markdown file formatting and structure" },
    @{ name = "readme"; color = "17a2b8"; description = "README file updates" },
    @{ name = "guide"; color = "28a745"; description = "User guide and tutorial content" },
    @{ name = "api-docs"; color = "6c757d"; description = "API documentation and reference" },
    @{ name = "changelog"; color = "fd7e14"; description = "Changelog and release notes" },
    @{ name = "comments"; color = "6f42c1"; description = "Code comments and inline documentation" },
    
    # Feature Request and Enhancement Labels
    @{ name = "enhancement"; color = "a2eeef"; description = "Feature enhancement or improvement" },
    @{ name = "feature-request"; color = "00d4aa"; description = "New feature request" },
    @{ name = "suggestion"; color = "84d0ff"; description = "Suggestion for improvement" },
    @{ name = "recommendation"; color = "ffb84d"; description = "Recommended change or best practice" },
    @{ name = "user-story"; color = "c5def5"; description = "User story or use case" },
    @{ name = "epic"; color = "3e4b9e"; description = "Large feature or epic" },
    @{ name = "prototype"; color = "f9d71c"; description = "Prototype or proof of concept" },
    @{ name = "research"; color = "d4c5f9"; description = "Research and investigation needed" },
    
    # Content Type Labels
    @{ name = "content-typo"; color = "fef2c0"; description = "Typo or spelling correction" },
    @{ name = "content-grammar"; color = "fff2cc"; description = "Grammar and language improvements" },
    @{ name = "content-structure"; color = "e1d5e7"; description = "Content structure and organization" },
    @{ name = "content-accuracy"; color = "d1f2eb"; description = "Content accuracy and factual corrections" },
    @{ name = "content-outdated"; color = "fadbd8"; description = "Outdated content that needs updating" },
    
    # Special Labels
    @{ name = "good-first-issue"; color = "7057ff"; description = "Good for new contributors" },
    @{ name = "bug"; color = "d73a49"; description = "Bug fix" },
    @{ name = "dependency"; color = "0366d6"; description = "Dependency related" },
    @{ name = "security"; color = "b60205"; description = "Security related" }
)

function Test-GitHubCLI {
    Write-StatusMessage "🔍 Checking GitHub CLI availability..." -Color $BLUE
    
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-StatusMessage "❌ GitHub CLI (gh) is not installed or not in PATH" -Color $RED
        Write-StatusMessage "📋 Install: https://cli.github.com/" -Color $CYAN
        return $false
    }
    
    # Verify GitHub CLI authentication
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "❌ GitHub CLI is not authenticated" -Color $RED
        Write-StatusMessage "🔐 Run: gh auth login" -Color $CYAN
        return $false
    }
    
    Write-StatusMessage "✅ GitHub CLI is available and authenticated" -Color $GREEN
    return $true
}

function Get-ExistingLabels {
    Write-StatusMessage "🔍 Fetching existing labels..." -Color $BLUE
    
    try {
        $existingLabels = gh label list --json name,color,description --limit 1000 | ConvertFrom-Json
        Write-StatusMessage "📋 Found $($existingLabels.Count) existing labels" -Color $CYAN
        return $existingLabels
    } catch {
        Write-StatusMessage "❌ Failed to fetch existing labels: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

function New-GitHubLabel {
    param(
        [hashtable]$Label,
        [switch]$DryRun
    )
    
    $name = $Label.name
    $color = $Label.color
    $description = $Label.description
    
    if ($DryRun) {
        Write-StatusMessage "🧪 [DRY RUN] Would create label: $name" -Color $YELLOW
        return @{ Success = $true; Action = "DryRun" }
    }
    
    try {
        gh label create $name --color $color --description $description 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Created label: $name" -Color $GREEN
            return @{ Success = $true; Action = "Created" }
        } else {
            Write-StatusMessage "❌ Failed to create label: $name" -Color $RED
            return @{ Success = $false; Action = "Failed" }
        }
    } catch {
        Write-StatusMessage "❌ Error creating label $name`: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; Action = "Error" }
    }
}

function Update-GitHubLabel {
    param(
        [hashtable]$Label,
        [switch]$DryRun
    )
    
    $name = $Label.name
    $color = $Label.color
    $description = $Label.description
    
    if ($DryRun) {
        Write-StatusMessage "🧪 [DRY RUN] Would update label: $name" -Color $YELLOW
        return @{ Success = $true; Action = "DryRun" }
    }
    
    try {
        gh label edit $name --color $color --description $description 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "🔄 Updated label: $name" -Color $BLUE
            return @{ Success = $true; Action = "Updated" }
        } else {
            Write-StatusMessage "❌ Failed to update label: $name" -Color $RED
            return @{ Success = $false; Action = "Failed" }
        }
    } catch {
        Write-StatusMessage "❌ Error updating label $name`: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; Action = "Error" }
    }
}

function Start-LabelCreation {
    Write-StatusMessage "🚀 Starting GitHub Label Creation for RUTOS Starlink Failover..." -Color $GREEN
    Write-StatusMessage "📊 Total labels to process: $($labels.Count)" -Color $BLUE
    
    if ($DryRun) {
        Write-StatusMessage "🧪 DRY RUN MODE - No actual changes will be made" -Color $YELLOW
    }
    
    # Check GitHub CLI
    if (-not (Test-GitHubCLI)) {
        Write-StatusMessage "❌ GitHub CLI check failed - exiting" -Color $RED
        return $false
    }
    
    # Get existing labels
    $existingLabels = Get-ExistingLabels
    $existingLabelNames = $existingLabels | ForEach-Object { $_.name }
    
    # Process each label
    $created = 0
    $updated = 0
    $failed = 0
    $skipped = 0
    
    foreach ($label in $labels) {
        $labelName = $label.name
        
        Write-StatusMessage "🔍 Processing label: $labelName" -Color $CYAN
        
        if ($DebugMode) {
            Write-StatusMessage "   Color: #$($label.color)" -Color $PURPLE
            Write-StatusMessage "   Description: $($label.description)" -Color $PURPLE
        }
        
        if ($labelName -in $existingLabelNames) {
            $existingLabel = $existingLabels | Where-Object { $_.name -eq $labelName }
            
            # Check if update is needed
            $needsUpdate = $false
            if ($existingLabel.color -ne $label.color) {
                $needsUpdate = $true
                if ($DebugMode) {
                    Write-StatusMessage "   Color needs update: #$($existingLabel.color) -> #$($label.color)" -Color $PURPLE
                }
            }
            if ($existingLabel.description -ne $label.description) {
                $needsUpdate = $true
                if ($DebugMode) {
                    Write-StatusMessage "   Description needs update" -Color $PURPLE
                }
            }
            
            if ($needsUpdate -and $Force) {
                $result = Update-GitHubLabel -Label $label -DryRun:$DryRun
                if ($result.Success) {
                    $updated++
                } else {
                    $failed++
                }
            } else {
                Write-StatusMessage "⏭️  Label exists and matches (use -Force to update): $labelName" -Color $CYAN
                $skipped++
            }
        } else {
            $result = New-GitHubLabel -Label $label -DryRun:$DryRun
            if ($result.Success) {
                $created++
            } else {
                $failed++
            }
        }
        
        # Small delay to avoid rate limiting
        Start-Sleep -Milliseconds 100
    }
    
    # Summary
    Write-StatusMessage "`n" + ("=" * 60) -Color $GREEN
    Write-StatusMessage "🎉 Label Creation Summary:" -Color $GREEN
    Write-StatusMessage "   📊 Total labels processed: $($labels.Count)" -Color $BLUE
    Write-StatusMessage "   ✅ Created: $created" -Color $GREEN
    Write-StatusMessage "   🔄 Updated: $updated" -Color $BLUE
    Write-StatusMessage "   ⏭️  Skipped: $skipped" -Color $CYAN
    Write-StatusMessage "   ❌ Failed: $failed" -Color $RED
    
    if ($DryRun) {
        Write-StatusMessage "   🧪 DRY RUN - No actual changes made" -Color $YELLOW
    }
    
    Write-StatusMessage ("=" * 60) -Color $GREEN
    
    return $failed -eq 0
}

# Main execution
try {
    Write-StatusMessage "🏷️  RUTOS Starlink Failover - GitHub Label Creation System" -Color $GREEN
    Write-StatusMessage "📋 Configuration:" -Color $CYAN
    Write-StatusMessage "   DryRun: $DryRun" -Color $CYAN
    Write-StatusMessage "   Force: $Force" -Color $CYAN
    Write-StatusMessage "   DebugMode: $DebugMode" -Color $CYAN
    
    $success = Start-LabelCreation
    
    if ($success) {
        Write-StatusMessage "✅ Label creation completed successfully!" -Color $GREEN
        exit 0
    } else {
        Write-StatusMessage "❌ Label creation completed with errors" -Color $RED
        exit 1
    }
    
} catch {
    Write-StatusMessage "❌ Script failed: $($_.Exception.Message)" -Color $RED
    Write-StatusMessage "🔍 Stack trace: $($_.ScriptStackTrace)" -Color $PURPLE
    exit 1
}
