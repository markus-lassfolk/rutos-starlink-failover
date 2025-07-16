# Fix Copilot PR Script - Handles merge conflicts and workflow approvals
# Specifically designed for PowerShell 5.1 compatibility
# Run in PowerShell (Windows) with GH CLI authenticated

param(
    [Parameter(Mandatory = $true)]
    [string]$PRNumber,
    [switch]$AutoApproveWorkflows = $false,
    [switch]$FixMergeConflicts = $false,
    [switch]$CheckValidation = $false,
    [switch]$DryRun = $false
)

# Color definitions for consistent output (PowerShell 5.1 compatible)
$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"
$CYAN = "Cyan"
$BLUE = "Blue"
$MAGENTA = "Magenta"
$WHITE = "White"

function Write-StatusMessage {
    param(
        [string]$Message,
        [string]$Color = "White",
        [string]$Prefix = "ℹ️"
    )
    Write-Host "$Prefix $Message" -ForegroundColor $Color
}

function Get-PRDetails {
    param([string]$PRNumber)
    
    Write-StatusMessage "🔍 Getting PR #$PRNumber details..." -Color $CYAN
    
    try {
        $prData = gh pr view $PRNumber --json number,title,headRefName,baseRefName,mergeable,mergeStateStatus,author,state | ConvertFrom-Json
        return $prData
    } catch {
        Write-StatusMessage "❌ Failed to get PR details: $($_.Exception.Message)" -Color $RED
        return $null
    }
}

function Get-PendingWorkflows {
    param([string]$PRNumber)
    
    Write-StatusMessage "🔍 Checking for pending workflows..." -Color $CYAN
    
    try {
        # Get workflow runs for this PR
        $runs = gh api repos/:owner/:repo/actions/runs --paginate | ConvertFrom-Json
        
        # Filter for runs related to this PR that are waiting for approval
        $pendingRuns = $runs.workflow_runs | Where-Object { 
            $_.status -eq "waiting" -and 
            $_.pull_requests -and 
            ($_.pull_requests | Where-Object { $_.number -eq [int]$PRNumber })
        }
        
        Write-StatusMessage "⏳ Found $($pendingRuns.Count) pending workflow runs" -Color $YELLOW
        return $pendingRuns
    } catch {
        Write-StatusMessage "⚠️  Failed to check workflows: $($_.Exception.Message)" -Color $YELLOW
        return @()
    }
}

function Approve-WorkflowRuns {
    param(
        [array]$PendingRuns,
        [string]$PRNumber
    )
    
    if ($PendingRuns.Count -eq 0) {
        Write-StatusMessage "✅ No pending workflows to approve" -Color $GREEN
        return $true
    }
    
    Write-StatusMessage "🚀 Approving $($PendingRuns.Count) workflow runs..." -Color $GREEN
    
    $successCount = 0
    foreach ($run in $PendingRuns) {
        try {
            if (-not $DryRun) {
                gh api repos/:owner/:repo/actions/runs/$($run.id)/approve -X POST | Out-Null
            }
            
            Write-StatusMessage "   ✅ Approved: $($run.name)" -Color $GREEN
            $successCount++
        } catch {
            Write-StatusMessage "   ❌ Failed to approve: $($run.name)" -Color $RED
        }
    }
    
    if ($successCount -eq $PendingRuns.Count) {
        Write-StatusMessage "✅ All workflows approved successfully!" -Color $GREEN
        
        # Add comment to PR
        $comment = "🤖 **Automated Workflow Approval**`n`n"
        $comment += "All pending workflow runs have been automatically approved:`n`n"
        $PendingRuns | ForEach-Object { $comment += "- ✅ $($_.name)`n" }
        $comment += "`nWorkflows should start running shortly."
        
        if (-not $DryRun) {
            gh pr comment $PRNumber --body $comment | Out-Null
        }
        
        return $true
    } else {
        Write-StatusMessage "⚠️  Only $successCount/$($PendingRuns.Count) workflows approved" -Color $YELLOW
        return $false
    }
}

function Resolve-MergeConflicts {
    param(
        [string]$PRNumber,
        [string]$HeadBranch,
        [string]$BaseBranch = "main"
    )
    
    Write-StatusMessage "🔧 Attempting to resolve merge conflicts..." -Color $CYAN
    Write-StatusMessage "   📍 PR Branch: $HeadBranch" -Color $BLUE
    Write-StatusMessage "   📍 Base Branch: $BaseBranch" -Color $BLUE
    
    $currentBranch = git branch --show-current
    
    try {
        # Fetch latest changes
        Write-StatusMessage "🔄 Fetching latest changes..." -Color $CYAN
        if (-not $DryRun) {
            git fetch origin | Out-Null
        }
        
        # Switch to the PR branch
        Write-StatusMessage "🔄 Switching to PR branch: $HeadBranch" -Color $CYAN
        if (-not $DryRun) {
            git checkout $HeadBranch | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-StatusMessage "❌ Failed to checkout branch $HeadBranch" -Color $RED
                return $false
            }
        }
        
        # Try to merge the base branch
        Write-StatusMessage "🔄 Attempting to merge $BaseBranch into $HeadBranch..." -Color $CYAN
        if (-not $DryRun) {
            $mergeResult = git merge origin/$BaseBranch --no-edit 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Merge successful - no conflicts!" -Color $GREEN
                
                # Push the resolved changes
                Write-StatusMessage "🚀 Pushing resolved changes..." -Color $CYAN
                git push origin $HeadBranch | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "✅ Changes pushed successfully" -Color $GREEN
                    
                    # Add comment to PR
                    $comment = "🤖 **Automated Merge Conflict Resolution**`n`n"
                    $comment += "Merge conflicts have been automatically resolved by merging the latest changes from ``$BaseBranch`` branch.`n`n"
                    $comment += "**Changes made:**`n"
                    $comment += "- Merged latest ``$BaseBranch`` into ``$HeadBranch```n"
                    $comment += "- Resolved conflicts automatically`n"
                    $comment += "- Pushed updated branch`n`n"
                    $comment += "Please review the changes and re-run any failing checks."
                    
                    gh pr comment $PRNumber --body $comment | Out-Null
                    
                    return $true
                } else {
                    Write-StatusMessage "❌ Failed to push changes" -Color $RED
                    return $false
                }
            } else {
                Write-StatusMessage "❌ Merge conflicts detected - manual resolution required" -Color $RED
                Write-StatusMessage "   Conflict details:" -Color $YELLOW
                Write-Host "$mergeResult" -ForegroundColor $WHITE
                
                # Add comment to PR about manual intervention needed
                $comment = "⚠️  **Manual Intervention Required**`n`n"
                $comment += "This PR has merge conflicts that could not be automatically resolved.`n`n"
                $comment += "**Conflict Details:**`n"
                $comment += "``````text`n$mergeResult`n``````"
                $comment += "`n**Resolution Steps:**`n"
                $comment += "1. Checkout the branch: ``git checkout $HeadBranch```n"
                $comment += "2. Merge main: ``git merge origin/$BaseBranch```n"
                $comment += "3. Resolve conflicts manually`n"
                $comment += "4. Commit resolved changes`n"
                $comment += "5. Push: ``git push origin $HeadBranch```n"
                $comment += "`nAlternatively, recreate the PR from an updated branch."
                
                gh pr comment $PRNumber --body $comment | Out-Null
                
                return $false
            }
        } else {
            Write-StatusMessage "🔍 DRY RUN: Would attempt to merge $BaseBranch into $HeadBranch" -Color $CYAN
            return $true
        }
    } catch {
        Write-StatusMessage "❌ Error during merge conflict resolution: $($_.Exception.Message)" -Color $RED
        return $false
    } finally {
        # Always return to the original branch
        if (-not $DryRun -and $currentBranch -ne $HeadBranch) {
            Write-StatusMessage "🔄 Returning to original branch: $currentBranch" -Color $CYAN
            git checkout $currentBranch | Out-Null
        }
    }
}

function Test-PRValidation {
    param(
        [string]$PRNumber,
        [string]$HeadBranch
    )
    
    Write-StatusMessage "🔍 Testing validation for PR #$PRNumber..." -Color $CYAN
    
    try {
        # Get the files changed in this PR
        $changedFiles = gh pr view $PRNumber --json files | ConvertFrom-Json
        $shellFiles = $changedFiles.files | Where-Object { $_.path -like "*.sh" }
        
        if ($shellFiles.Count -eq 0) {
            Write-StatusMessage "ℹ️  No shell script files changed in this PR" -Color $YELLOW
            return @{ Success = $true; FilesChecked = 0; Issues = @() }
        }
        
        Write-StatusMessage "📂 Checking $($shellFiles.Count) shell script files..." -Color $BLUE
        
        $validationResults = @()
        $allPassed = $true
        
        foreach ($file in $shellFiles) {
            Write-StatusMessage "   📄 Validating: $($file.path)" -Color $BLUE
            
            # Run validation on the specific file
            $validationOutput = wsl ./scripts/pre-commit-validation.sh $file.path 2>&1
            $validationPassed = $LASTEXITCODE -eq 0
            
            if (-not $validationPassed) {
                $allPassed = $false
            }
            
            # Parse validation output for issues
            $criticalIssues = if ($validationOutput) { 
                ($validationOutput | Select-String -Pattern "\[CRITICAL\]" | Measure-Object).Count 
            } else { 0 }
            
            $majorIssues = if ($validationOutput) { 
                ($validationOutput | Select-String -Pattern "\[MAJOR\]" | Measure-Object).Count 
            } else { 0 }
            
            $validationResults += @{
                File = $file.path
                Passed = $validationPassed
                CriticalIssues = $criticalIssues
                MajorIssues = $majorIssues
                Output = $validationOutput
            }
            
            if ($validationPassed) {
                Write-StatusMessage "   ✅ $($file.path) - Validation passed" -Color $GREEN
            } else {
                Write-StatusMessage "   ❌ $($file.path) - $criticalIssues critical, $majorIssues major issues" -Color $RED
            }
        }
        
        # Add comment to PR with validation results
        $comment = if ($allPassed) { "✅ **Validation Status: PASSED**" } else { "❌ **Validation Status: FAILED**" }
        $comment += "`n`n**Files Checked:** $($shellFiles.Count)`n"
        $comment += "**Issues Found:** $(($validationResults | ForEach-Object { $_.CriticalIssues + $_.MajorIssues } | Measure-Object -Sum).Sum)`n`n"
        
        if (-not $allPassed) {
            $comment += "**Issues by File:**`n"
            $validationResults | Where-Object { -not $_.Passed } | ForEach-Object {
                $comment += "- ``$($_.File)`` - $($_.CriticalIssues) critical, $($_.MajorIssues) major issues`n"
            }
            $comment += "`n@copilot Please address the remaining validation issues before this PR can be merged."
        } else {
            $comment += "All RUTOS compatibility checks have passed. This PR is ready for final review."
        }
        
        if (-not $DryRun) {
            gh pr comment $PRNumber --body $comment | Out-Null
        }
        
        return @{
            Success = $allPassed
            FilesChecked = $shellFiles.Count
            Issues = $validationResults
            TotalIssues = ($validationResults | ForEach-Object { $_.CriticalIssues + $_.MajorIssues } | Measure-Object -Sum).Sum
        }
    } catch {
        Write-StatusMessage "❌ Validation test failed: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; FilesChecked = 0; Issues = @(); Error = $_.Exception.Message }
    }
}

# Main execution
Write-Host "🚀 **COPILOT PR FIX AUTOMATION**" -ForegroundColor $MAGENTA
Write-Host "=" * 60 -ForegroundColor $MAGENTA

Write-StatusMessage "🔧 Configuration:" -Color $CYAN
Write-StatusMessage "   📍 PR Number: #$PRNumber" -Color $BLUE
Write-StatusMessage "   🔄 Auto-approve workflows: $AutoApproveWorkflows" -Color $BLUE
Write-StatusMessage "   🔧 Fix merge conflicts: $FixMergeConflicts" -Color $BLUE
Write-StatusMessage "   ✅ Check validation: $CheckValidation" -Color $BLUE
Write-StatusMessage "   🔍 Dry run: $DryRun" -Color $BLUE

# Get PR details
$prDetails = Get-PRDetails -PRNumber $PRNumber
if (-not $prDetails) {
    Write-StatusMessage "❌ Cannot proceed without PR details" -Color $RED
    exit 1
}

Write-StatusMessage "📊 PR Details:" -Color $CYAN
Write-StatusMessage "   📝 Title: $($prDetails.title)" -Color $BLUE
Write-StatusMessage "   🌿 Head Branch: $($prDetails.headRefName)" -Color $BLUE
Write-StatusMessage "   🔄 Merge State: $($prDetails.mergeStateStatus)" -Color $BLUE
Write-StatusMessage "   ✅ Mergeable: $($prDetails.mergeable)" -Color $BLUE

$hasConflicts = $prDetails.mergeStateStatus -eq "DIRTY" -or $prDetails.mergeable -eq "CONFLICTING"

# Handle merge conflicts first
if ($hasConflicts -and $FixMergeConflicts) {
    Write-StatusMessage "🔧 Resolving merge conflicts..." -Color $YELLOW
    $conflictResolved = Resolve-MergeConflicts -PRNumber $PRNumber -HeadBranch $prDetails.headRefName
    
    if ($conflictResolved) {
        Write-StatusMessage "✅ Merge conflicts resolved successfully!" -Color $GREEN
        
        # Refresh PR details after conflict resolution
        Start-Sleep -Seconds 3
        $prDetails = Get-PRDetails -PRNumber $PRNumber
        $hasConflicts = $prDetails.mergeStateStatus -eq "DIRTY" -or $prDetails.mergeable -eq "CONFLICTING"
    } else {
        Write-StatusMessage "❌ Failed to resolve merge conflicts" -Color $RED
    }
} elseif ($hasConflicts) {
    Write-StatusMessage "⚠️  PR has merge conflicts but auto-fix is disabled" -Color $YELLOW
    Write-StatusMessage "   💡 Use -FixMergeConflicts to automatically resolve" -Color $YELLOW
}

# Handle workflow approvals
if ($AutoApproveWorkflows) {
    $pendingWorkflows = Get-PendingWorkflows -PRNumber $PRNumber
    $workflowsApproved = Approve-WorkflowRuns -PendingRuns $pendingWorkflows -PRNumber $PRNumber
    
    if ($workflowsApproved) {
        Write-StatusMessage "✅ All workflows approved successfully!" -Color $GREEN
    } else {
        Write-StatusMessage "⚠️  Some workflows failed to approve" -Color $YELLOW
    }
} else {
    $pendingWorkflows = Get-PendingWorkflows -PRNumber $PRNumber
    if ($pendingWorkflows.Count -gt 0) {
        Write-StatusMessage "⚠️  $($pendingWorkflows.Count) workflows pending approval" -Color $YELLOW
        Write-StatusMessage "   💡 Use -AutoApproveWorkflows to automatically approve" -Color $YELLOW
    }
}

# Check validation status
if ($CheckValidation) {
    if ($hasConflicts) {
        Write-StatusMessage "⚠️  Cannot validate while merge conflicts exist" -Color $YELLOW
    } else {
        $validationResult = Test-PRValidation -PRNumber $PRNumber -HeadBranch $prDetails.headRefName
        
        if ($validationResult.Success) {
            Write-StatusMessage "✅ All validation checks passed!" -Color $GREEN
        } else {
            Write-StatusMessage "❌ Validation failed - $($validationResult.TotalIssues) issues found" -Color $RED
        }
    }
}

# Final summary
Write-Host "`n📊 **SUMMARY**" -ForegroundColor $MAGENTA
Write-Host "=" * 60 -ForegroundColor $MAGENTA

Write-StatusMessage "📍 PR #$PRNumber Status:" -Color $CYAN
Write-StatusMessage "   🔀 Has merge conflicts: $hasConflicts" -Color $(if ($hasConflicts) { $RED } else { $GREEN })
Write-StatusMessage "   🔄 Workflows approved: $(if ($AutoApproveWorkflows) { 'Yes' } else { 'Not requested' })" -Color $BLUE
Write-StatusMessage "   ✅ Validation checked: $(if ($CheckValidation) { 'Yes' } else { 'Not requested' })" -Color $BLUE

Write-Host "`n💡 **RECOMMENDED NEXT STEPS**" -ForegroundColor $YELLOW
if ($hasConflicts) {
    Write-Host "1. 🔧 Run with -FixMergeConflicts to resolve conflicts" -ForegroundColor $WHITE
}
if (-not $AutoApproveWorkflows) {
    Write-Host "2. 🚀 Run with -AutoApproveWorkflows to approve pending workflows" -ForegroundColor $WHITE
}
if (-not $CheckValidation) {
    Write-Host "3. ✅ Run with -CheckValidation to verify fixes" -ForegroundColor $WHITE
}

Write-Host "`n📖 **USAGE EXAMPLES**" -ForegroundColor $BLUE
Write-Host "# Full automation for PR #60:" -ForegroundColor $CYAN
Write-Host ".\automation\Fix-CopilotPR.ps1 -PRNumber 60 -FixMergeConflicts -AutoApproveWorkflows -CheckValidation" -ForegroundColor $WHITE
Write-Host "" -ForegroundColor $CYAN
Write-Host "# Just approve workflows:" -ForegroundColor $CYAN
Write-Host ".\automation\Fix-CopilotPR.ps1 -PRNumber 60 -AutoApproveWorkflows" -ForegroundColor $WHITE
Write-Host "" -ForegroundColor $CYAN
Write-Host "# Test run (no changes):" -ForegroundColor $CYAN
Write-Host ".\automation\Fix-CopilotPR.ps1 -PRNumber 60 -DryRun -FixMergeConflicts -AutoApproveWorkflows" -ForegroundColor $WHITE

if ($DryRun) {
    Write-Host "`n🔍 **DRY RUN COMPLETED** - No actual changes were made" -ForegroundColor $CYAN
}

Write-Host "`n" + ("=" * 60) -ForegroundColor $MAGENTA
Write-StatusMessage "🎉 PR fix automation completed!" -Color $GREEN
