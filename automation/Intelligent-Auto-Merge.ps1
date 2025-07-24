#!/usr/bin/env pwsh
# Intelligent Auto-Merge System for Resolved Copilot PRs
# Automatically merges PRs that pass all checks and meet safety criteria

param(
    [string]$PRNumber,
    [switch]$DryRun,
    [switch]$Debug,
    [string]$MergeMethod = "squash", # squash, merge, rebase
    [switch]$RequireApprovals = $true
)

# Configuration
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Enhanced logging
function Write-LogInfo { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-LogWarning { param($Message) Write-Host "⚠️ $Message" -ForegroundColor Yellow }
function Write-LogError { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-LogDebug { param($Message) if ($Debug) { Write-Host "🔍 $Message" -ForegroundColor Cyan } }
function Write-LogStep { param($Message) Write-Host "🔄 $Message" -ForegroundColor Blue }

# Function to check if PR is safe to auto-merge
function Test-AutoMergeSafety {
    param([string]$PRNumber)
    
    Write-LogStep "Evaluating auto-merge safety for PR #$PRNumber..."
    
    try {
        # Get comprehensive PR data
        $prData = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
            user: .user.login,
            title: .title,
            body: .body,
            draft: .draft,
            state: .state,
            mergeable: .mergeable,
            mergeable_state: .mergeable_state,
            base: .base.ref,
            head: .head.ref,
            changed_files: .changed_files,
            additions: .additions,
            deletions: .deletions,
            commits: .commits
        }' | ConvertFrom-Json
        
        # Safety checks
        $safetyChecks = @{
            IsTrustedAuthor = $false
            IsNonDraft = $false
            IsMergeable = $false
            HasReasonableSize = $false
            IsTrustedBranch = $false
            HasSafeTitle = $false
            HasNoRiskyChanges = $false
            PassesAllChecks = $false
            HasRequiredApprovals = $false
        }
        
        # Check 1: Trusted author
        $trustedAuthors = @(
            "app/copilot-swe-agent",
            "copilot-swe-agent", 
            "github-copilot[bot]",
            "app/github-copilot"
        )
        $safetyChecks.IsTrustedAuthor = $trustedAuthors -contains $prData.user
        Write-LogDebug "Trusted author check: $($safetyChecks.IsTrustedAuthor) (Author: $($prData.user))"
        
        # Check 2: Not a draft
        $safetyChecks.IsNonDraft = -not $prData.draft
        Write-LogDebug "Non-draft check: $($safetyChecks.IsNonDraft)"
        
        # Check 3: Mergeable state
        $safetyChecks.IsMergeable = $prData.mergeable -eq $true -and $prData.mergeable_state -eq "clean"
        Write-LogDebug "Mergeable check: $($safetyChecks.IsMergeable) (State: $($prData.mergeable_state))"
        
        # Check 4: Reasonable size (not massive changes)
        $totalChanges = $prData.additions + $prData.deletions
        $safetyChecks.HasReasonableSize = $totalChanges -le 1000 -and $prData.changed_files -le 20
        Write-LogDebug "Size check: $($safetyChecks.HasReasonableSize) ($totalChanges changes, $($prData.changed_files) files)"
        
        # Check 5: Trusted branch (typically main or develop)
        $trustedTargetBranches = @("main", "master", "develop", "dev")
        $safetyChecks.IsTrustedBranch = $trustedTargetBranches -contains $prData.base
        Write-LogDebug "Branch check: $($safetyChecks.IsTrustedBranch) (Target: $($prData.base))"
        
        # Check 6: Safe title patterns
        $safeTitlePatterns = @(
            "Fix.*RUTOS.*compatibility",
            "Fix:.*version.*information", 
            "Add.*version.*information",
            "\[MINOR\].*version.*information",
            "Update.*version.*to.*",
            "Fix.*shell.*compatibility",
            "Add.*missing.*dry-run.*support"
        )
        $safetyChecks.HasSafeTitle = $false
        foreach ($pattern in $safeTitlePatterns) {
            if ($prData.title -match $pattern) {
                $safetyChecks.HasSafeTitle = $true
                break
            }
        }
        Write-LogDebug "Safe title check: $($safetyChecks.HasSafeTitle) (Title: $($prData.title))"
        
        # Check 7: No risky changes in body/description
        $riskyKeywords = @("delete", "remove", "DROP", "rm -rf", "sudo", "password", "secret", "token", "DROP TABLE", "DELETE FROM")
        $safetyChecks.HasNoRiskyChanges = $true
        foreach ($keyword in $riskyKeywords) {
            if ($prData.body -match $keyword) {
                $safetyChecks.HasNoRiskyChanges = $false
                Write-LogDebug "Risky keyword found: $keyword"
                break
            }
        }
        Write-LogDebug "No risky changes check: $($safetyChecks.HasNoRiskyChanges)"
        
        # Check 8: All status checks pass
        $statusChecks = gh api "repos/$env:GITHUB_REPOSITORY/commits/$($prData.head.sha)/status" --jq '.state' 2>/dev/null
        $safetyChecks.PassesAllChecks = $statusChecks -eq "success"
        Write-LogDebug "Status checks: $($safetyChecks.PassesAllChecks) (State: $statusChecks)"
        
        # Check 9: Required approvals (if enabled)
        if ($RequireApprovals) {
            $reviews = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber/reviews" --jq '[.[] | select(.state == "APPROVED")] | length' 2>/dev/null
            $safetyChecks.HasRequiredApprovals = [int]$reviews -ge 1
            Write-LogDebug "Approvals check: $($safetyChecks.HasRequiredApprovals) ($reviews approvals)"
        } else {
            $safetyChecks.HasRequiredApprovals = $true
            Write-LogDebug "Approvals check: Skipped (not required)"
        }
        
        # Overall safety assessment
        $allChecksPassed = $safetyChecks.Values | ForEach-Object { $_ } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
        $isSafe = $allChecksPassed -eq 0
        
        Write-LogDebug "Safety assessment complete: $isSafe"
        
        return @{
            IsSafe = $isSafe
            Checks = $safetyChecks
            PRData = $prData
            FailedChecks = ($safetyChecks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
        }
    }
    catch {
        Write-LogError "Failed to evaluate PR safety: $_"
        return @{
            IsSafe = $false
            Error = $_.Exception.Message
        }
    }
}

# Function to perform auto-merge
function Invoke-AutoMerge {
    param(
        [string]$PRNumber,
        [string]$MergeMethod = "squash"
    )
    
    Write-LogStep "Attempting auto-merge for PR #$PRNumber using $MergeMethod method..."
    
    try {
        if ($DryRun) {
            Write-LogInfo "DRY RUN: Would merge PR #$PRNumber using $MergeMethod method"
            return @{ Success = $true; Method = "dry-run" }
        }
        
        # Attempt the merge
        $mergeResult = gh pr merge $PRNumber --$MergeMethod --auto --delete-branch 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "✅ Successfully auto-merged PR #$PRNumber"
            return @{ 
                Success = $true
                Method = $MergeMethod
                Result = $mergeResult
            }
        } else {
            Write-LogError "Failed to merge PR #$PRNumber: $mergeResult"
            return @{
                Success = $false
                Error = $mergeResult
            }
        }
    }
    catch {
        Write-LogError "Exception during merge: $_"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Function to process multiple PRs for auto-merge
function Start-AutoMergeProcessing {
    param([string[]]$PRNumbers = @())
    
    Write-LogInfo "🤖 Starting intelligent auto-merge processing..."
    
    if ($PRNumbers.Count -eq 0) {
        # Get all ready Copilot PRs
        $readyPRs = gh pr list --author "app/copilot-swe-agent" --state "open" --limit 50 --json number,title | ConvertFrom-Json
        $PRNumbers = $readyPRs | ForEach-Object { $_.number.ToString() }
    }
    
    Write-LogInfo "Evaluating $($PRNumbers.Count) PR(s) for auto-merge eligibility"
    
    $processedResults = @()
    $mergedCount = 0
    
    foreach ($pr in $PRNumbers) {
        Write-LogStep "Evaluating PR #$pr..."
        
        $safetyAssessment = Test-AutoMergeSafety -PRNumber $pr
        
        if ($safetyAssessment.IsSafe) {
            Write-LogInfo "✅ PR #$pr passed all safety checks - proceeding with merge"
            
            $mergeResult = Invoke-AutoMerge -PRNumber $pr -MergeMethod $MergeMethod
            
            if ($mergeResult.Success) {
                $mergedCount++
                Write-LogInfo "🎉 Successfully merged PR #$pr"
            } else {
                Write-LogWarning "⚠️ PR #$pr was safe but merge failed: $($mergeResult.Error)"
            }
            
            $processedResults += @{
                PR = $pr
                Title = $safetyAssessment.PRData.title
                SafetyPassed = $true
                MergeAttempted = $true
                MergeSuccessful = $mergeResult.Success
                MergeError = $mergeResult.Error
            }
        } else {
            Write-LogWarning "⚠️ PR #$pr failed safety checks: $($safetyAssessment.FailedChecks -join ', ')"
            
            $processedResults += @{
                PR = $pr
                Title = if ($safetyAssessment.PRData) { $safetyAssessment.PRData.title } else { "Unknown" }
                SafetyPassed = $false
                FailedChecks = $safetyAssessment.FailedChecks
                MergeAttempted = $false
                MergeSuccessful = $false
            }
        }
        
        # Small delay between PRs
        Start-Sleep -Seconds 2
    }
    
    # Summary report
    Write-LogInfo "🏁 Auto-merge processing completed"
    Write-LogInfo "📊 Summary:"
    Write-LogInfo "   PRs evaluated: $($processedResults.Count)"
    Write-LogInfo "   PRs merged: $mergedCount"
    Write-LogInfo "   Success rate: $([math]::Round($mergedCount / [math]::Max($processedResults.Count, 1) * 100, 1))%"
    
    if ($Debug) {
        Write-LogDebug "Detailed results:"
        foreach ($result in $processedResults) {
            if ($result.MergeSuccessful) {
                Write-LogDebug "  ✅ PR #$($result.PR): MERGED"
            } elseif ($result.SafetyPassed) {
                Write-LogDebug "  ⚠️ PR #$($result.PR): SAFE but merge failed - $($result.MergeError)"
            } else {
                Write-LogDebug "  ❌ PR #$($result.PR): Failed safety - $($result.FailedChecks -join ', ')"
            }
        }
    }
    
    return @{
        ProcessedResults = $processedResults
        MergedCount = $mergedCount
        TotalEvaluated = $processedResults.Count
    }
}

# Main execution
function Main {
    Write-LogInfo "🎯 Intelligent Auto-Merge System for Copilot PRs"
    Write-LogInfo "================================================"
    
    if ($DryRun) {
        Write-LogWarning "DRY RUN MODE - No actual merges will be performed"
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
    
    Write-LogInfo "Merge method: $MergeMethod"
    Write-LogInfo "Require approvals: $RequireApprovals"
    
    if ($PRNumber) {
        # Process specific PR
        Write-LogInfo "Processing specific PR #$PRNumber"
        
        $safetyAssessment = Test-AutoMergeSafety -PRNumber $PRNumber
        
        if ($safetyAssessment.IsSafe) {
            $mergeResult = Invoke-AutoMerge -PRNumber $PRNumber -MergeMethod $MergeMethod
            if ($mergeResult.Success) {
                Write-LogInfo "✅ PR #$PRNumber successfully merged"
            } else {
                Write-LogError "❌ PR #$PRNumber merge failed: $($mergeResult.Error)"
                exit 1
            }
        } else {
            Write-LogWarning "⚠️ PR #$PRNumber not eligible for auto-merge"
            Write-LogWarning "Failed checks: $($safetyAssessment.FailedChecks -join ', ')"
            exit 1
        }
    } else {
        # Process all eligible PRs
        $result = Start-AutoMergeProcessing
        Write-LogInfo "✅ Processed $($result.TotalEvaluated) PRs, merged $($result.MergedCount)"
    }
}

# Execute main function
Main
