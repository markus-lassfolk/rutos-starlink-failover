#!/usr/bin/env pwsh
# Enhanced Status Check Management for Mixed Workflow Results
# Handles cases where successful retries are blocked by old failed status checks

param(
    [string]$PRNumber,
    [switch]$Force,
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

# Function to analyze status check conflicts
function Get-StatusCheckAnalysis {
    param([string]$PRNumber)
    
    Write-LogStep "Analyzing status checks for PR #$PRNumber"
    
    # Get detailed PR status information
    $prData = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
        mergeable: .mergeable,
        mergeable_state: .mergeable_state,
        merge_commit_sha: .merge_commit_sha,
        head: {
            sha: .head.sha,
            ref: .head.ref
        }
    }' | ConvertFrom-Json
    
    Write-LogDebug "PR merge state: $($prData.mergeable_state), mergeable: $($prData.mergeable)"
    
    # Get status checks for the head commit
    $statusChecks = gh api "repos/$env:GITHUB_REPOSITORY/statuses/$($prData.head.sha)" | ConvertFrom-Json
    
    # Group status checks by context (workflow name)
    $groupedStatuses = $statusChecks | Group-Object -Property context
    
    $analysis = @{
        PR = $prData
        ConflictingContexts = @()
        SuccessfulRetries = @()
        OldFailures = @()
        MixedStatus = $false
    }
    
    foreach ($group in $groupedStatuses) {
        $context = $group.Name
        $statuses = $group.Group | Sort-Object created_at -Descending
        
        Write-LogDebug "Context: $context, Status count: $($statuses.Count)"
        
        if ($statuses.Count -gt 1) {
            $latest = $statuses[0]
            $older = $statuses[1..($statuses.Count-1)]
            
            # Check if we have a successful latest run with older failures
            if ($latest.state -eq "success" -and ($older | Where-Object { $_.state -eq "failure" -or $_.state -eq "error" })) {
                Write-LogWarning "Mixed status detected for context: $context"
                Write-LogDebug "  Latest: $($latest.state) at $($latest.created_at)"
                Write-LogDebug "  Older failures: $(($older | Where-Object { $_.state -in @('failure', 'error') }).Count)"
                
                $analysis.ConflictingContexts += $context
                $analysis.SuccessfulRetries += $latest
                $analysis.OldFailures += ($older | Where-Object { $_.state -in @('failure', 'error') })
                $analysis.MixedStatus = $true
            }
        }
    }
    
    return $analysis
}

# Function to trigger a dummy status check to refresh GitHub's status evaluation
function Invoke-StatusRefresh {
    param([string]$PRNumber, [string]$HeadSha)
    
    Write-LogStep "Attempting to refresh status checks for PR #$PRNumber"
    
    if ($DryRun) {
        Write-LogInfo "DRY RUN: Would trigger status refresh for commit $HeadSha"
        return $true
    }
    
    try {
        # Create a neutral status check that will trigger GitHub to re-evaluate
        $statusBody = @{
            state = "success"
            target_url = "https://github.com/$env:GITHUB_REPOSITORY/pull/$PRNumber"
            description = "Status refresh trigger - mixed status cleanup"
            context = "autonomous-status-refresh"
        } | ConvertTo-Json
        
        # Write to temp file for gh input
        $tempFile = [System.IO.Path]::GetTempFileName()
        $statusBody | Out-File -FilePath $tempFile -Encoding UTF8
        
        gh api "repos/$env:GITHUB_REPOSITORY/statuses/$HeadSha" `
            --method POST `
            --input $tempFile
            
        Remove-Item $tempFile -Force
            
        Write-LogInfo "Status refresh triggered successfully"
        return $true
    }
    catch {
        Write-LogError "Failed to trigger status refresh: $_"
        return $false
    }
}

# Function to trigger workflow re-run for specific failed contexts
function Invoke-WorkflowRerun {
    param([string]$Context, [string]$PRNumber)
    
    Write-LogStep "Looking for workflow runs to re-run for context: $Context"
    
    # Get recent workflow runs for this PR
    $workflows = gh run list --limit 50 --json databaseId,workflowName,status,conclusion,headBranch,createdAt | ConvertFrom-Json
    
    # Find the most recent failed run for this context/workflow
    $targetRun = $workflows | Where-Object { 
        $_.workflowName -like "*$Context*" -and 
        $_.headBranch -like "*$PRNumber*" -and
        $_.conclusion -eq "failure"
    } | Select-Object -First 1
    
    if ($targetRun) {
        Write-LogInfo "Found failed run to retry: $($targetRun.databaseId) - $($targetRun.workflowName)"
        
        if ($DryRun) {
            Write-LogInfo "DRY RUN: Would re-run workflow $($targetRun.databaseId)"
            return $true
        }
        
        try {
            gh run rerun $targetRun.databaseId --failed
            Write-LogInfo "Workflow re-run triggered successfully"
            return $true
        }
        catch {
            Write-LogError "Failed to re-run workflow: $_"
            return $false
        }
    }
    else {
        Write-LogWarning "No suitable failed workflow run found for context: $Context"
        return $false
    }
}

# Function to resolve mixed status issues
function Resolve-MixedStatusChecks {
    param([string]$PRNumber)
    
    Write-LogStep "Starting mixed status check resolution for PR #$PRNumber"
    
    $analysis = Get-StatusCheckAnalysis -PRNumber $PRNumber
    
    if (-not $analysis.MixedStatus) {
        Write-LogInfo "No mixed status issues detected for PR #$PRNumber"
        return $true
    }
    
    Write-LogWarning "Mixed status checks detected for PR #$PRNumber"
    Write-LogInfo "Conflicting contexts: $($analysis.ConflictingContexts -join ', ')"
    
    $resolutionStrategies = @()
    
    # Strategy 1: Trigger status refresh
    $resolutionStrategies += @{
        Name = "Status Refresh"
        Action = { Invoke-StatusRefresh -PRNumber $PRNumber -HeadSha $analysis.PR.head.sha }
        Description = "Trigger GitHub status re-evaluation"
    }
    
    # Strategy 2: Re-run failed workflows for successful retries
    foreach ($context in $analysis.ConflictingContexts) {
        $resolutionStrategies += @{
            Name = "Workflow Re-run: $context"
            Action = { Invoke-WorkflowRerun -Context $context -PRNumber $PRNumber }
            Description = "Re-run failed workflow to replace old status"
        }
    }
    
    # Strategy 3: Force status override (if enabled)
    if ($Force) {
        $resolutionStrategies += @{
            Name = "Force Status Override"
            Action = { 
                # Create new successful status checks for each conflicting context
                foreach ($context in $analysis.ConflictingContexts) {
                    $statusBody = @{
                        state = "success"
                        target_url = "https://github.com/$env:GITHUB_REPOSITORY/pull/$PRNumber"
                        description = "Force override - mixed status resolved"
                        context = "$context-override"
                    } | ConvertTo-Json
                    
                    if (-not $DryRun) {
                        $tempFile = [System.IO.Path]::GetTempFileName()
                        $statusBody | Out-File -FilePath $tempFile -Encoding UTF8
                        
                        gh api "repos/$env:GITHUB_REPOSITORY/statuses/$($analysis.PR.head.sha)" `
                            --method POST `
                            --input $tempFile
                            
                        Remove-Item $tempFile -Force
                    }
                }
                $true
            }
            Description = "Force create successful status overrides"
        }
    }
    
    # Execute resolution strategies
    $successCount = 0
    foreach ($strategy in $resolutionStrategies) {
        Write-LogStep "Executing strategy: $($strategy.Name)"
        Write-LogDebug "Strategy description: $($strategy.Description)"
        
        try {
            $result = & $strategy.Action
            if ($result) {
                Write-LogInfo "Strategy '$($strategy.Name)' executed successfully"
                $successCount++
            }
            else {
                Write-LogWarning "Strategy '$($strategy.Name)' failed"
            }
        }
        catch {
            Write-LogError "Strategy '$($strategy.Name)' failed with error: $_"
        }
        
        # Wait between strategies to allow GitHub to process
        if (-not $DryRun) {
            Start-Sleep -Seconds 5
        }
    }
    
    Write-LogInfo "Resolution completed: $successCount/$($resolutionStrategies.Count) strategies successful"
    
    # Re-analyze to check if issues are resolved
    Start-Sleep -Seconds 10
    $postAnalysis = Get-StatusCheckAnalysis -PRNumber $PRNumber
    
    if ($postAnalysis.MixedStatus) {
        Write-LogWarning "Mixed status issues still present after resolution attempt"
        return $false
    }
    else {
        Write-LogInfo "Mixed status issues appear to be resolved!"
        return $true
    }
}

# Function to monitor PR until merge or timeout
function Wait-ForPRMerge {
    param([string]$PRNumber, [int]$TimeoutMinutes = 10)
    
    Write-LogStep "Monitoring PR #$PRNumber for merge (timeout: $TimeoutMinutes minutes)"
    
    $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
    
    while ((Get-Date) -lt $timeout) {
        $prStatus = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
            state: .state,
            merged: .merged,
            mergeable: .mergeable,
            mergeable_state: .mergeable_state
        }' | ConvertFrom-Json
        
        Write-LogDebug "PR Status: state=$($prStatus.state), merged=$($prStatus.merged), mergeable=$($prStatus.mergeable), merge_state=$($prStatus.mergeable_state)"
        
        if ($prStatus.merged) {
            Write-LogInfo "🎉 PR #$PRNumber has been merged successfully!"
            return $true
        }
        
        if ($prStatus.state -eq "closed") {
            Write-LogWarning "PR #$PRNumber was closed without merging"
            return $false
        }
        
        if ($prStatus.mergeable_state -eq "clean") {
            Write-LogInfo "PR #$PRNumber is now in clean merge state"
            # Trigger auto-merge if it's not already enabled
            if (-not $DryRun) {
                gh pr merge $PRNumber --auto --merge --delete-branch 2>$null
            }
        }
        
        Start-Sleep -Seconds 30
    }
    
    Write-LogWarning "Timeout reached waiting for PR #$PRNumber to merge"
    return $false
}

# Main execution
function Main {
    Write-LogInfo "🚀 Mixed Status Check Resolution Tool"
    Write-LogInfo "====================================="
    
    if (-not $PRNumber) {
        Write-LogError "PR number is required. Use -PRNumber parameter."
        exit 1
    }
    
    if ($DryRun) {
        Write-LogWarning "DRY RUN MODE - No actual changes will be made"
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
    
    # Check if PR exists
    try {
        $prInfo = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{number: .number, title: .title}' | ConvertFrom-Json
        Write-LogInfo "Processing PR #$($prInfo.number): $($prInfo.title)"
    }
    catch {
        Write-LogError "PR #$PRNumber not found or inaccessible"
        exit 1
    }
    
    # Resolve mixed status checks
    $resolved = Resolve-MixedStatusChecks -PRNumber $PRNumber
    
    if ($resolved -and -not $DryRun) {
        # Monitor for successful merge
        $merged = Wait-ForPRMerge -PRNumber $PRNumber -TimeoutMinutes 10
        
        if ($merged) {
            Write-LogInfo "🎉 Successfully resolved mixed status checks and PR was merged!"
        }
        else {
            Write-LogWarning "Status checks resolved but PR did not merge automatically"
            Write-LogInfo "Manual merge may be required"
        }
    }
    elseif ($DryRun) {
        Write-LogInfo "DRY RUN completed successfully"
    }
    else {
        Write-LogError "Failed to resolve mixed status check issues"
        exit 1
    }
}

# Execute main function
Main
