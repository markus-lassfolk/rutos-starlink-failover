#!/usr/bin/env pwsh
# Auto-Approve Workflows for Copilot PRs
# Automatically approves workflow runs for trusted Copilot PRs to enable fully autonomous operation

param(
    [string]$PRNumber,
    [switch]$DryRun,
    [switch]$Debug
)

# Configuration
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Enhanced logging with colors
function Write-LogInfo { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-LogWarning { param($Message) Write-Host "⚠️ $Message" -ForegroundColor Yellow }
function Write-LogError { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-LogDebug { param($Message) if ($Debug) { Write-Host "🔍 $Message" -ForegroundColor Cyan } }
function Write-LogStep { param($Message) Write-Host "🔄 $Message" -ForegroundColor Blue }

# Function to check if PR is from trusted Copilot
function Test-TrustedCopilotPR {
    param([string]$PRNumber)
    
    Write-LogStep "Checking if PR #$PRNumber is from trusted Copilot..."
    
    $prData = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
        user: .user.login,
        title: .title,
        body: .body,
        draft: .draft
    }' | ConvertFrom-Json
    
    $trustedAuthors = @(
        "app/copilot-swe-agent",
        "copilot-swe-agent",
        "github-copilot[bot]",
        "app/github-copilot"
    )
    
    $trustedTitlePatterns = @(
        "Fix.*RUTOS.*compatibility",
        "Fix:.*version.*information",
        "Add.*version.*information",
        "\[MINOR\].*version.*information"
    )
    
    # Check if author is trusted
    $isTrustedAuthor = $trustedAuthors -contains $prData.user
    
    # Check if title matches trusted patterns
    $isTrustedTitle = $false
    foreach ($pattern in $trustedTitlePatterns) {
        if ($prData.title -match $pattern) {
            $isTrustedTitle = $true
            break
        }
    }
    
    # Additional safety checks
    $isDraft = $prData.draft
    $hasRiskyKeywords = $prData.body -match "(delete|remove|DROP|rm -rf|sudo|password|secret|token)"
    
    $isTrusted = $isTrustedAuthor -and $isTrustedTitle -and -not $isDraft -and -not $hasRiskyKeywords
    
    Write-LogDebug "Author: $($prData.user) (Trusted: $isTrustedAuthor)"
    Write-LogDebug "Title: $($prData.title) (Trusted: $isTrustedTitle)"
    Write-LogDebug "Draft: $isDraft"
    Write-LogDebug "Risky keywords: $hasRiskyKeywords"
    Write-LogDebug "Overall trusted: $isTrusted"
    
    return @{
        IsTrusted = $isTrusted
        Author = $prData.user
        Title = $prData.title
        Reason = if ($isTrusted) { "Trusted Copilot PR" } else { "Failed trust checks" }
    }
}

# Function to auto-approve workflow runs
function Approve-WorkflowRuns {
    param([string]$PRNumber)
    
    Write-LogStep "Finding workflow runs requiring approval for PR #$PRNumber..."
    
    # Get workflow runs that need approval
    $workflowRuns = gh run list --limit 50 --json databaseId,status,workflowName,headBranch,conclusion | ConvertFrom-Json
    
    $needingApproval = $workflowRuns | Where-Object { 
        $_.status -eq "action_required" -and 
        $_.headBranch -like "*$PRNumber*" 
    }
    
    if (-not $needingApproval) {
        Write-LogInfo "No workflow runs requiring approval found for PR #$PRNumber"
        return @{ ApprovedCount = 0; Workflows = @() }
    }
    
    Write-LogInfo "Found $($needingApproval.Count) workflow run(s) requiring approval"
    
    $approvedCount = 0
    $approvedWorkflows = @()
    
    foreach ($run in $needingApproval) {
        Write-LogStep "Approving workflow: $($run.workflowName) (ID: $($run.databaseId))"
        
        if ($DryRun) {
            Write-LogInfo "DRY RUN: Would approve workflow run $($run.databaseId)"
            $approvedCount++
            $approvedWorkflows += $run.workflowName
        } else {
            try {
                # Use GitHub CLI to approve the workflow run
                $result = gh api "repos/$env:GITHUB_REPOSITORY/actions/runs/$($run.databaseId)/approve" --method POST
                
                Write-LogInfo "✅ Approved workflow: $($run.workflowName)"
                $approvedCount++
                $approvedWorkflows += $run.workflowName
                
                # Small delay between approvals to avoid rate limiting
                Start-Sleep -Seconds 2
            }
            catch {
                Write-LogError "Failed to approve workflow $($run.workflowName): $_"
            }
        }
    }
    
    return @{
        ApprovedCount = $approvedCount
        Workflows = $approvedWorkflows
        TotalFound = $needingApproval.Count
    }
}

# Function to monitor and auto-approve for multiple PRs
function Start-AutoApprovalMonitoring {
    param([string[]]$PRNumbers = @())
    
    Write-LogInfo "🤖 Starting autonomous workflow approval monitoring..."
    
    if ($PRNumbers.Count -eq 0) {
        # Get all open Copilot PRs
        $prList = gh pr list --author "app/copilot-swe-agent" --limit 50 --json number | ConvertFrom-Json
        $PRNumbers = $prList | ForEach-Object { $_.number.ToString() }
    }
    
    Write-LogInfo "Monitoring $($PRNumbers.Count) PR(s) for auto-approval opportunities"
    
    $totalApproved = 0
    $processedPRs = @()
    
    foreach ($pr in $PRNumbers) {
        Write-LogStep "Processing PR #$pr..."
        
        # Check if PR is trusted
        $trustCheck = Test-TrustedCopilotPR -PRNumber $pr
        
        if ($trustCheck.IsTrusted) {
            Write-LogInfo "✅ PR #$pr is trusted: $($trustCheck.Reason)"
            
            # Auto-approve workflows
            $approvalResult = Approve-WorkflowRuns -PRNumber $pr
            
            $processedPRs += @{
                PR = $pr
                Author = $trustCheck.Author
                Title = $trustCheck.Title
                ApprovedCount = $approvalResult.ApprovedCount
                Workflows = $approvalResult.Workflows
            }
            
            $totalApproved += $approvalResult.ApprovedCount
        } else {
            Write-LogWarning "⚠️ PR #$pr not trusted: $($trustCheck.Reason)"
            $processedPRs += @{
                PR = $pr
                Author = $trustCheck.Author
                Title = $trustCheck.Title
                ApprovedCount = 0
                Workflows = @()
                Reason = $trustCheck.Reason
            }
        }
        
        # Small delay between PRs
        Start-Sleep -Seconds 1
    }
    
    # Summary report
    Write-LogInfo "🏁 Auto-approval monitoring completed"
    Write-LogInfo "📊 Summary:"
    Write-LogInfo "   PRs processed: $($processedPRs.Count)"
    Write-LogInfo "   Total workflows approved: $totalApproved"
    
    if ($Debug) {
        Write-LogDebug "Detailed results:"
        foreach ($result in $processedPRs) {
            Write-LogDebug "  PR #$($result.PR): $($result.ApprovedCount) approvals"
            if ($result.Workflows.Count -gt 0) {
                Write-LogDebug "    Workflows: $($result.Workflows -join ', ')"
            }
        }
    }
    
    return @{
        ProcessedPRs = $processedPRs
        TotalApproved = $totalApproved
    }
}

# Main execution
function Main {
    Write-LogInfo "🚀 Autonomous Workflow Approval System"
    Write-LogInfo "======================================"
    
    if ($DryRun) {
        Write-LogWarning "DRY RUN MODE - No actual approvals will be made"
    }
    
    # Validate environment
    try {
        $repo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $env:GITHUB_REPOSITORY = $repo.nameWithOwner
        Write-LogInfo "Repository: $env:GITHUB_REPOSITORY"
    }
    catch {
        Write-LogError "Failed to get repository information. Ensure you're in a git repository with gh CLI authenticated."
        exit 1
    }
    
    if ($PRNumber) {
        # Process specific PR
        Write-LogInfo "Processing specific PR #$PRNumber"
        
        $trustCheck = Test-TrustedCopilotPR -PRNumber $PRNumber
        
        if ($trustCheck.IsTrusted) {
            $result = Approve-WorkflowRuns -PRNumber $PRNumber
            Write-LogInfo "✅ Auto-approved $($result.ApprovedCount) workflow(s) for PR #$PRNumber"
        } else {
            Write-LogWarning "⚠️ PR #$PRNumber not eligible for auto-approval: $($trustCheck.Reason)"
        }
    } else {
        # Monitor all Copilot PRs
        $result = Start-AutoApprovalMonitoring
        Write-LogInfo "✅ Processed $($result.ProcessedPRs.Count) PRs, approved $($result.TotalApproved) workflows"
    }
}

# Execute main function
Main
