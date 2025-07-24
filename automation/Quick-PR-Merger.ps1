# Quick PR Merger - Simple script to merge ready Copilot PRs
# Addresses the immediate backlog issue

param(
    [switch]$DryRun,          # Default behavior is dry-run
    [switch]$Force,           # Force actual execution
    [int]$MaxPRs = 10,        # Limit number of PRs to process
    [switch]$Verbose
)

# Default to dry-run unless Force is specified
if (-not $Force) {
    $DryRun = $true
}

# Show help and safety warning
if ($DryRun) {
    Write-Host "🚨 SAFETY MODE: Dry-run enabled by default" -ForegroundColor Red
    Write-Host "   Use -Force to actually merge PRs" -ForegroundColor Yellow
    Write-Host ""
}

# Color functions
function Write-Info { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }

Write-Info "Quick PR Merger - Processing Copilot PRs with 'ready-for-merge' label"
Write-Info "Dry Run: $DryRun | Force: $Force | Max PRs: $MaxPRs"

try {
    # Check GitHub CLI
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    }

    # Get ready-to-merge Copilot PRs
    Write-Info "Fetching ready-to-merge Copilot PRs..."
    $prsJson = gh pr list --state open --label "ready-for-merge" --label "validation-passed" --json number,title,author,mergeable,mergeStateStatus,labels --limit $MaxPRs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch PRs"
        exit 1
    }

    $prs = $prsJson | ConvertFrom-Json

    if ($prs.Count -eq 0) {
        Write-Info "No ready-to-merge Copilot PRs found"
        exit 0
    }

    Write-Success "Found $($prs.Count) ready-to-merge Copilot PRs"

    $processedCount = 0
    $mergedCount = 0
    $skippedCount = 0
    $failedCount = 0

    foreach ($pr in $prs) {
        $processedCount++
        Write-Host ""
        Write-Info "Processing PR #$($pr.number): $($pr.title)"
        
        # Filter to only Copilot authors
        if ($pr.author.login -notmatch "(copilot|app/copilot)") {
            Write-Warning "Skipping PR #$($pr.number): Not from Copilot author ($($pr.author.login))"
            $skippedCount++
            continue
        }
        
        if ($Verbose) {
            Write-Host "   Author: $($pr.author.login)" -ForegroundColor Gray
            Write-Host "   Mergeable: $($pr.mergeable)" -ForegroundColor Gray
            Write-Host "   Merge State: $($pr.mergeStateStatus)" -ForegroundColor Gray
            Write-Host "   Labels: $($pr.labels.name -join ', ')" -ForegroundColor Gray
        }

        # Basic safety checks
        $canMerge = $true
        $reasons = @()

        # Check if actually mergeable (accept MERGEABLE or UNKNOWN)
        if ($pr.mergeable -eq "CONFLICTING") {
            $canMerge = $false
            $reasons += "Has merge conflicts"
        }

        # Check for validation-passed label
        $hasValidation = $pr.labels | Where-Object { $_.name -eq "validation-passed" }
        if (-not $hasValidation) {
            $canMerge = $false
            $reasons += "Missing validation-passed label"
        }

        # Check title safety
        $safeTitle = $pr.title -match "(Fix.*RUTOS.*compatibility|Fix:.*version.*information|Add.*version.*information|\[MINOR\].*version)"
        if (-not $safeTitle) {
            Write-Warning "Title doesn't match safe patterns, but proceeding (has ready-for-merge label)"
        }

        if (-not $canMerge) {
            Write-Warning "Skipping PR #$($pr.number): $($reasons -join ', ')"
            $skippedCount++
            continue
        }

        # Attempt merge
        if ($DryRun) {
            Write-Success "DRY RUN: Would merge PR #$($pr.number)"
            $mergedCount++
        } else {
            Write-Info "Attempting to merge PR #$($pr.number)..."
            
            $mergeResult = gh pr merge $pr.number --squash --delete-branch 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Successfully merged PR #$($pr.number)"
                $mergedCount++
                
                # Add success comment
                $comment = "🤖 **Quick Merge Successful**`n`nThis PR was merged using the quick merger script after validation.`n`nMerge method: Squash merge with branch deletion"
                gh pr comment $pr.number --body $comment | Out-Null
                
                # Brief pause to avoid rate limiting
                Start-Sleep -Seconds 2
            } else {
                Write-Error "Failed to merge PR #$($pr.number): $mergeResult"
                $failedCount++
                
                # Add failure comment
                $comment = "🤖 **Quick Merge Failed**`n`nThis PR failed to merge automatically. Error: $mergeResult`n`nPlease check the merge status and retry manually."
                gh pr comment $pr.number --body $comment | Out-Null
            }
        }
    }

    # Summary
    Write-Host ""
    Write-Host "=" * 50 -ForegroundColor Blue
    Write-Success "Quick PR Merger Summary"
    Write-Host "=" * 50 -ForegroundColor Blue
    Write-Info "PRs Processed: $processedCount"
    Write-Success "Successfully Merged: $mergedCount"
    Write-Warning "Skipped: $skippedCount"
    Write-Error "Failed: $failedCount"
    
    if ($DryRun) {
        Write-Host ""
        Write-Warning "This was a DRY RUN - no actual merges performed"
        Write-Info "To execute actual merges: .\automation\Quick-PR-Merger.ps1 -Force"
    }

} catch {
    Write-Error "Script error: $($_.Exception.Message)"
    exit 1
}
