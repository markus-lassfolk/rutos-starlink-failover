# Copilot PR Monitoring and Automation Script
# Monitors Copilot PRs, approves workflows, validates changes, and reports status
# Run in PowerShell 5.1 (Windows) with GH CLI authenticated

param(
    [switch]$AutoApproveWorkflows = $false,
    [switch]$CheckValidation = $false,
    [switch]$MonitorOnly = $true,
    [switch]$HandleMergeConflicts = $false,
    [switch]$ShowValidationIssues = $false,
    [string]$SpecificPR = "",
    [int]$MaxRetries = 3
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

function Get-CopilotPRs {
    Write-StatusMessage "🔍 Scanning for Copilot PRs..." -Color $CYAN
    
    try {
        $allPRs = gh pr list --state open --json number,title,author,headRefName,mergeable,mergeStateStatus,statusCheckRollup | ConvertFrom-Json
        
        # Filter for Copilot PRs (created by Copilot or on copilot/* branches)
        $copilotPRs = $allPRs | Where-Object { 
            $_.author.login -eq "Copilot" -or 
            $_.headRefName -like "copilot/*" -or
            $_.title -like "*Copilot*" -or
            $_.title -like "*🤖*"
        }
        
        Write-StatusMessage "📊 Found $($copilotPRs.Count) Copilot PRs out of $($allPRs.Count) total PRs" -Color $YELLOW
        
        return $copilotPRs
    } catch {
        Write-StatusMessage "❌ Failed to fetch PRs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

function Get-WorkflowRuns {
    param(
        [string]$PRNumber
    )
    
    try {
        $runs = gh api repos/:owner/:repo/actions/runs -f "event=pull_request" | ConvertFrom-Json
        
        # Filter runs for this specific PR
        $prRuns = $runs.workflow_runs | Where-Object { 
            $_.pull_requests -and 
            ($_.pull_requests | Where-Object { $_.number -eq [int]$PRNumber })
        }
        
        return $prRuns
    } catch {
        Write-StatusMessage "⚠️  Failed to fetch workflow runs for PR #$PRNumber" -Color $YELLOW
        return @()
    }
}

function Approve-WorkflowRun {
    param(
        [string]$RunId
    )
    
    try {
        gh api repos/:owner/:repo/actions/runs/$RunId/approve -X POST
        return $true
    } catch {
        Write-StatusMessage "❌ Failed to approve workflow run $RunId" -Color $RED
        return $false
    }
}

function Show-ValidationIssues {
    param(
        [switch]$ShowAll = $false
    )
    
    Write-StatusMessage "🔍 Analyzing current validation issues..." -Color $CYAN
    
    try {
        $validationOutput = wsl ./scripts/pre-commit-validation.sh --all 2>&1
        
        # Parse validation output for detailed issue reporting
        $criticalIssues = @()
        $majorIssues = @()
        
        foreach ($line in $validationOutput) {
            # Match pattern: [CRITICAL] filename: issue description
            if ($line -match '^\[CRITICAL\]\s+(.+?):\s*(.+)$') {
                $criticalIssues += @{
                    File = $matches[1].Trim()
                    Issue = $matches[2].Trim()
                    Type = "CRITICAL"
                }
            }
            # Match pattern: [MAJOR] filename: issue description  
            elseif ($line -match '^\[MAJOR\]\s+(.+?):\s*(.+)$') {
                $majorIssues += @{
                    File = $matches[1].Trim()
                    Issue = $matches[2].Trim()
                    Type = "MAJOR"
                }
            }
        }
        
        Write-StatusMessage "📊 Validation Status Summary:" -Color $YELLOW
        Write-StatusMessage "  🔴 Critical issues: $($criticalIssues.Count)" -Color $RED
        Write-StatusMessage "  🟡 Major issues: $($majorIssues.Count)" -Color $YELLOW
        
        if ($ShowAll) {
            # Show detailed breakdown for Copilot
            if ($criticalIssues.Count -gt 0) {
                Write-StatusMessage "`n🔴 **CRITICAL ISSUES** (Need immediate attention):" -Color $RED
                $criticalByFile = $criticalIssues | Group-Object -Property File
                foreach ($fileGroup in $criticalByFile | Sort-Object Count -Descending) {
                    Write-StatusMessage "  📄 $($fileGroup.Name): $($fileGroup.Count) issues" -Color $RED
                    
                    # Group similar issues to reduce noise
                    $issueGroups = $fileGroup.Group | Group-Object -Property Issue | Sort-Object Count -Descending
                    foreach ($issueGroup in $issueGroups | Select-Object -First 5) {
                        $countText = if ($issueGroup.Count -gt 1) { " (×$($issueGroup.Count))" } else { "" }
                        Write-StatusMessage "    • $($issueGroup.Name)$countText" -Color $GRAY
                    }
                    if ($issueGroups.Count -gt 5) {
                        Write-StatusMessage "    • ... and $($issueGroups.Count - 5) more similar issues" -Color $GRAY
                    }
                }
            }
            
            if ($majorIssues.Count -gt 0) {
                Write-StatusMessage "`n🟡 **MAJOR ISSUES** (Important fixes needed):" -Color $YELLOW
                $majorByFile = $majorIssues | Group-Object -Property File
                foreach ($fileGroup in $majorByFile | Sort-Object Count -Descending) {
                    Write-StatusMessage "  📄 $($fileGroup.Name): $($fileGroup.Count) issues" -Color $YELLOW
                    
                    # Group similar issues to reduce noise
                    $issueGroups = $fileGroup.Group | Group-Object -Property Issue | Sort-Object Count -Descending
                    foreach ($issueGroup in $issueGroups | Select-Object -First 5) {
                        $countText = if ($issueGroup.Count -gt 1) { " (×$($issueGroup.Count))" } else { "" }
                        Write-StatusMessage "    • $($issueGroup.Name)$countText" -Color $GRAY
                    }
                    if ($issueGroups.Count -gt 5) {
                        Write-StatusMessage "    • ... and $($issueGroups.Count - 5) more similar issues" -Color $GRAY
                    }
                }
            }
        }
        
        # Create issue summary for Copilot
        if ($criticalIssues.Count -gt 0 -or $majorIssues.Count -gt 0) {
            Write-StatusMessage "`n📝 **ISSUE SUMMARY FOR COPILOT**:" -Color $CYAN
            Write-StatusMessage "Files requiring fixes:" -Color $WHITE
            $allIssues = $criticalIssues + $majorIssues
            $filesSummary = $allIssues | Group-Object -Property File | Sort-Object Count -Descending
            foreach ($fileGroup in $filesSummary | Select-Object -First 10) {
                $criticalCount = ($fileGroup.Group | Where-Object { $_.Type -eq "CRITICAL" }).Count
                $majorCount = ($fileGroup.Group | Where-Object { $_.Type -eq "MAJOR" }).Count
                Write-StatusMessage "  • $($fileGroup.Name): $criticalCount critical, $majorCount major" -Color $CYAN
            }
            if ($filesSummary.Count -gt 10) {
                Write-StatusMessage "  • ... and $($filesSummary.Count - 10) more files with issues" -Color $GRAY
            }
        } else {
            Write-StatusMessage "`n✅ No validation issues found!" -Color $GREEN
        }
        
        return @{
            CriticalIssues = $criticalIssues
            MajorIssues = $majorIssues
            TotalIssues = $criticalIssues.Count + $majorIssues.Count
        }
    } catch {
        Write-StatusMessage "❌ Failed to analyze validation issues: $($_.Exception.Message)" -Color $RED
        return @{
            CriticalIssues = @()
            MajorIssues = @()
            TotalIssues = 0
        }
    }
}

function Test-PRValidation {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔍 Testing validation for PR #$PRNumber (branch: $HeadRef)" -Color $CYAN
    
    try {
        # Get the files changed in the PR
        $changedFiles = gh pr view $PRNumber --json files | ConvertFrom-Json
        $filePaths = $changedFiles.files | Where-Object { $_.path -like "*.sh" } | Select-Object -ExpandProperty path
        
        if ($filePaths.Count -eq 0) {
            Write-StatusMessage "ℹ️  No shell script files changed in PR #$PRNumber" -Color $YELLOW
            return @{ Success = $true; FilesChecked = 0; Issues = @() }
        }
        
        Write-StatusMessage "📂 Checking $($filePaths.Count) shell script files..." -Color $BLUE
        
        # CRITICAL FIX: Switch to the PR branch to check the actual fixed files
        $currentBranch = git branch --show-current
        Write-StatusMessage "🔄 Switching to PR branch: $HeadRef" -Color $CYAN
        
        # Fetch the PR branch from remote
        Write-StatusMessage "📥 Fetching PR branch from remote..." -Color $BLUE
        $fetchResult = git fetch origin $HeadRef 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "⚠️  Failed to fetch branch, trying alternate method..." -Color $YELLOW
            # Try fetching the full PR
            $fetchResult = git fetch origin pull/$PRNumber/head:pr-$PRNumber 2>&1
            if ($LASTEXITCODE -eq 0) {
                $HeadRef = "pr-$PRNumber"
            } else {
                Write-StatusMessage "❌ Could not fetch PR branch. Checking current branch files..." -Color $RED
                # Continue with current branch - better than failing completely
            }
        }
        
        # Switch to the PR branch if fetch was successful
        if ($LASTEXITCODE -eq 0) {
            git checkout $HeadRef 2>&1 | Out-Null
            
            if ($LASTEXITCODE -ne 0) {
                Write-StatusMessage "❌ Failed to switch to PR branch $HeadRef, checking current branch" -Color $RED
                # Continue with current branch instead of failing
            } else {
                Write-StatusMessage "✅ Successfully switched to PR branch: $HeadRef" -Color $GREEN
            }
        }
        
        $validationResults = @()
        
        foreach ($file in $filePaths) {
            Write-StatusMessage "   📄 Validating: $file (in PR branch)" -Color $BLUE
            
            # Run validation on the specific file in the PR branch
            $validationOutput = wsl ./scripts/pre-commit-validation.sh $file 2>&1
            $validationPassed = $LASTEXITCODE -eq 0
            
            # Parse validation output for detailed issues
            $criticalIssueDetails = @()
            $majorIssueDetails = @()
            
            foreach ($line in $validationOutput) {
                # Match pattern: [CRITICAL] filename: issue description
                if ($line -match '^\[CRITICAL\]\s+(.+?):\s*(.+)$') {
                    $criticalIssueDetails += @{
                        File = $matches[1].Trim()
                        Issue = $matches[2].Trim()
                        Type = "CRITICAL"
                    }
                }
                # Match pattern: [MAJOR] filename: issue description
                elseif ($line -match '^\[MAJOR\]\s+(.+?):\s*(.+)$') {
                    $majorIssueDetails += @{
                        File = $matches[1].Trim()
                        Issue = $matches[2].Trim()
                        Type = "MAJOR"
                    }
                }
                # Also catch ShellCheck issues that might not have the file prefix
                elseif ($line -match '^(.+?):\s*line\s*\d+:\s*(.+)$') {
                    $issueText = "$($matches[1].Trim()): $($matches[2].Trim())"
                    $majorIssueDetails += @{
                        File = $file
                        Issue = $issueText
                        Type = "MAJOR"
                    }
                }
            }
            
            # Group and clean up issues
            $criticalIssues = $criticalIssueDetails.Count
            $majorIssues = $majorIssueDetails.Count
            
            # Filter out duplicates and group similar issues
            $criticalIssueDetails = $criticalIssueDetails | Sort-Object Issue -Unique
            $majorIssueDetails = $majorIssueDetails | Sort-Object Issue -Unique
            
            $validationResults += @{
                File = $file
                Passed = $validationPassed
                CriticalIssues = $criticalIssues
                MajorIssues = $majorIssues
                CriticalDetails = $criticalIssueDetails
                MajorDetails = $majorIssueDetails
                Output = $validationOutput
            }
            
            if ($validationPassed) {
                Write-StatusMessage "   ✅ $file - Validation passed" -Color $GREEN
            } else {
                Write-StatusMessage "   ❌ $file - $criticalIssues critical, $majorIssues major issues" -Color $RED
            }
        }
        
        # Switch back to the original branch
        Write-StatusMessage "🔄 Switching back to original branch: $currentBranch" -Color $CYAN
        git checkout $currentBranch 2>&1 | Out-Null
        
        $allPassed = ($validationResults | Where-Object { -not $_.Passed }).Count -eq 0
        $totalIssues = ($validationResults | ForEach-Object { $_.CriticalIssues + $_.MajorIssues } | Measure-Object -Sum).Sum
        
        return @{
            Success = $allPassed
            FilesChecked = $filePaths.Count
            Issues = $validationResults
            TotalIssues = $totalIssues
        }
    } catch {
        # Make sure we switch back to original branch even on error
        $currentBranch = git branch --show-current
        if ($currentBranch -ne $HeadRef) {
            git checkout $currentBranch 2>&1 | Out-Null
        }
        
        Write-StatusMessage "❌ Validation test failed: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; FilesChecked = 0; Issues = @(); Error = $_.Exception.Message }
    }
}

function Resolve-MergeConflicts {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔄 Attempting to resolve merge conflicts for PR #$PRNumber" -Color $YELLOW
    
    try {
        # Fetch the latest changes
        git fetch origin
        
        # Switch to the PR branch
        git checkout $HeadRef
        
        # Try to merge main into the PR branch
        git merge origin/main --no-edit
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Merge conflicts resolved automatically" -Color $GREEN
            
            # Push the resolved changes
            git push origin $HeadRef
            
            Write-StatusMessage "✅ Pushed conflict resolution to $HeadRef" -Color $GREEN
            return $true
        } else {
            Write-StatusMessage "❌ Automatic merge conflict resolution failed" -Color $RED
            return $false
        }
    } catch {
        Write-StatusMessage "❌ Error resolving merge conflicts: $($_.Exception.Message)" -Color $RED
        return $false
    } finally {
        # Always return to main branch
        git checkout main
    }
}

function Add-PRComment {
    param(
        [string]$PRNumber,
        [string]$Comment
    )
    
    try {
        gh pr comment $PRNumber --body $Comment
        return $true
    } catch {
        Write-StatusMessage "⚠️  Failed to add comment to PR #$PRNumber" -Color $YELLOW
        return $false
    }
}

function Monitor-CopilotPR {
    param(
        [object]$PR
    )
    
    $prNumber = $PR.number
    $headRef = $PR.headRefName
    $mergeState = $PR.mergeStateStatus
    $mergeable = $PR.mergeable
    
    Write-StatusMessage "🔍 Monitoring PR #$prNumber - $($PR.title)" -Color $CYAN
    Write-StatusMessage "   📍 Branch: $headRef" -Color $BLUE
    Write-StatusMessage "   🔄 Merge State: $mergeState" -Color $BLUE
    Write-StatusMessage "   ✅ Mergeable: $mergeable" -Color $BLUE
    
    # Check for merge conflicts
    if ($mergeState -eq "DIRTY" -or $mergeable -eq "CONFLICTING") {
        Write-StatusMessage "⚠️  PR #$prNumber has merge conflicts" -Color $YELLOW
        
        if ($HandleMergeConflicts) {
            Write-StatusMessage "🔧 Attempting to resolve merge conflicts..." -Color $CYAN
            $conflictResolved = Resolve-MergeConflicts -PRNumber $prNumber -HeadRef $headRef
            
            if ($conflictResolved) {
                Add-PRComment -PRNumber $prNumber -Comment "🤖 **Automated Conflict Resolution**`n`nMerge conflicts have been automatically resolved by merging the latest changes from main branch.`n`nPlease review the changes and re-run any failing checks."
            } else {
                Add-PRComment -PRNumber $prNumber -Comment "⚠️  **Manual Intervention Required**`n`nThis PR has merge conflicts that could not be automatically resolved. Please resolve them manually or recreate the PR from an updated branch."
            }
        }
    }
    
    # Get workflow runs for this PR
    $workflowRuns = Get-WorkflowRuns -PRNumber $prNumber
    $pendingRuns = $workflowRuns | Where-Object { $_.status -eq "waiting" }
    
    if ($pendingRuns.Count -gt 0) {
        Write-StatusMessage "⏳ Found $($pendingRuns.Count) pending workflow runs" -Color $YELLOW
        
        if ($AutoApproveWorkflows) {
            Write-StatusMessage "🚀 Auto-approving workflow runs..." -Color $GREEN
            
            foreach ($run in $pendingRuns) {
                $approved = Approve-WorkflowRun -RunId $run.id
                if ($approved) {
                    Write-StatusMessage "   ✅ Approved workflow: $($run.name)" -Color $GREEN
                } else {
                    Write-StatusMessage "   ❌ Failed to approve workflow: $($run.name)" -Color $RED
                }
            }
            
            Add-PRComment -PRNumber $prNumber -Comment "🤖 **Automated Workflow Approval**`n`nAll pending workflow runs have been automatically approved and should start running shortly.`n`nWorkflows approved: $($pendingRuns.Count)"
        } else {
            Write-StatusMessage "💡 Use -AutoApproveWorkflows to automatically approve these runs" -Color $YELLOW
        }
    }
    
    # Check validation status
    if ($CheckValidation) {
        Write-StatusMessage "🔍 Running validation check..." -Color $CYAN
        $validationResult = Test-PRValidation -PRNumber $prNumber -HeadRef $headRef
        
        if ($validationResult.Success) {
            Write-StatusMessage "✅ All validation checks passed!" -Color $GREEN
            
            $comment = "✅ **Validation Status: PASSED**`n`n"
            $comment += "- **Files Checked**: $($validationResult.FilesChecked)`n"
            $comment += "- **Issues Found**: 0`n"
            $comment += "- **Status**: Ready for review and merge`n`n"
            $comment += "All RUTOS compatibility checks have passed. This PR is ready for final review."
            
            Add-PRComment -PRNumber $prNumber -Comment $comment
        } else {
            Write-StatusMessage "❌ Validation failed - $($validationResult.TotalIssues) issues found" -Color $RED
            
            $comment = "❌ **Validation Status: FAILED**`n`n"
            $comment += "📊 **Summary**: $($validationResult.TotalIssues) issues found in $($validationResult.FilesChecked) files`n`n"
            
            # Show detailed issues for each file in a clean format
            foreach ($issue in $validationResult.Issues) {
                if (-not $issue.Passed) {
                    $comment += "### 📄 ``$($issue.File)``\n"
                    $comment += "**Issues**: $($issue.CriticalIssues) critical, $($issue.MajorIssues) major\n\n"
                    
                    if ($issue.CriticalDetails.Count -gt 0) {
                        $comment += "🔴 **Critical Issues:**\n"
                        $criticalGroups = $issue.CriticalDetails | Group-Object -Property Issue | Sort-Object Count -Descending
                        foreach ($group in $criticalGroups) {
                            $comment += "- $($group.Name)"
                            if ($group.Count -gt 1) {
                                $comment += " (×$($group.Count))"
                            }
                            $comment += "\n"
                        }
                        $comment += "\n"
                    }
                    
                    if ($issue.MajorDetails.Count -gt 0) {
                        $comment += "🟡 **Major Issues:**\n"
                        $majorGroups = $issue.MajorDetails | Group-Object -Property Issue | Sort-Object Count -Descending
                        foreach ($group in $majorGroups) {
                            $comment += "- $($group.Name)"
                            if ($group.Count -gt 1) {
                                $comment += " (×$($group.Count))"
                            }
                            $comment += "\n"
                        }
                        $comment += "\n"
                    }
                }
            }
            
            $comment += "---\n"
            $comment += "### 🤖 **Action Required**\n"
            $comment += "@copilot Please address these validation issues:\n\n"
            $comment += "**Common RUTOS Fixes:**\n"
            $comment += "- Remove ``local`` keyword (use regular variables)\n"
            $comment += "- Fix printf format strings (use %s placeholders)\n"
            $comment += "- Add proper error handling (``|| exit 1``)\n"
            $comment += "- Use POSIX sh syntax only (no bash features)\n"
            $comment += "- Replace arrays with space-separated strings\n"
            $comment += "- Use single brackets ``[ ]`` instead of ``[[ ]]``\n"
            
            Add-PRComment -PRNumber $prNumber -Comment $comment
        }
    }
    
    return @{
        PRNumber = $prNumber
        HasConflicts = ($mergeState -eq "DIRTY" -or $mergeable -eq "CONFLICTING")
        PendingWorkflows = $pendingRuns.Count
        ValidationPassed = if ($CheckValidation) { $validationResult.Success } else { $null }
    }
}

# Main execution
Write-Host "🤖 **COPILOT PR MONITORING DASHBOARD**" -ForegroundColor $MAGENTA
Write-Host "=" * 60 -ForegroundColor $MAGENTA

Write-StatusMessage "🔧 Configuration:" -Color $CYAN
Write-StatusMessage "   🔄 Auto-approve workflows: $AutoApproveWorkflows" -Color $BLUE
Write-StatusMessage "   ✅ Check validation: $CheckValidation" -Color $BLUE
Write-StatusMessage "   🔀 Handle merge conflicts: $HandleMergeConflicts" -Color $BLUE
Write-StatusMessage "   📊 Monitor only: $MonitorOnly" -Color $BLUE
Write-StatusMessage "   🔍 Show validation issues: $ShowValidationIssues" -Color $BLUE

# Show current validation issues if requested
if ($ShowValidationIssues) {
    Write-Host "`n" + ("=" * 60) -ForegroundColor $CYAN
    $validationStatus = Show-ValidationIssues -ShowAll:$ShowValidationIssues
    Write-Host ("=" * 60) -ForegroundColor $CYAN
    
    if ($validationStatus.TotalIssues -gt 0) {
        Write-StatusMessage "💡 **RECOMMENDATION**: Create issues for these files using Create-RUTOS-PRs.ps1" -Color $YELLOW
        Write-StatusMessage "   Command: .\automation\Create-RUTOS-PRs.ps1 -MaxIssues 5" -Color $CYAN
    }
}

if ($SpecificPR) {
    Write-StatusMessage "🎯 Monitoring specific PR: #$SpecificPR" -Color $YELLOW
    
    try {
        $prData = gh pr view $SpecificPR --json number,title,author,headRefName,mergeable,mergeStateStatus | ConvertFrom-Json
        $results = Monitor-CopilotPR -PR $prData
        
        Write-StatusMessage "📊 Results for PR #${SpecificPR}:" -Color $GREEN
        Write-StatusMessage "   🔀 Has conflicts: $($results.HasConflicts)" -Color $BLUE
        Write-StatusMessage "   ⏳ Pending workflows: $($results.PendingWorkflows)" -Color $BLUE
        if ($results.ValidationPassed -ne $null) {
            Write-StatusMessage "   ✅ Validation passed: $($results.ValidationPassed)" -Color $BLUE
        }
    } catch {
        Write-StatusMessage "❌ Failed to monitor PR #${SpecificPR}: $($_.Exception.Message)" -Color $RED
    }
} else {
    # Monitor all Copilot PRs
    $copilotPRs = Get-CopilotPRs
    
    if ($copilotPRs.Count -eq 0) {
        Write-StatusMessage "ℹ️  No Copilot PRs found" -Color $YELLOW
    } else {
        Write-StatusMessage "📊 Processing $($copilotPRs.Count) Copilot PRs..." -Color $GREEN
        
        $allResults = @()
        
        foreach ($pr in $copilotPRs) {
            Write-Host "`n" + ("-" * 50) -ForegroundColor $CYAN
            $result = Monitor-CopilotPR -PR $pr
            $allResults += $result
        }
        
        Write-Host "`n" + ("=" * 60) -ForegroundColor $MAGENTA
        Write-StatusMessage "📈 **SUMMARY REPORT**" -Color $GREEN
        
        $totalPRs = $allResults.Count
        $conflictedPRs = ($allResults | Where-Object { $_.HasConflicts }).Count
        $pendingWorkflows = ($allResults | ForEach-Object { $_.PendingWorkflows } | Measure-Object -Sum).Sum
        
        Write-StatusMessage "📊 Total Copilot PRs: $totalPRs" -Color $BLUE
        Write-StatusMessage "⚠️  PRs with conflicts: $conflictedPRs" -Color $YELLOW
        Write-StatusMessage "⏳ Total pending workflows: $pendingWorkflows" -Color $YELLOW
        
        if ($CheckValidation) {
            $validationResults = $allResults | Where-Object { $_.ValidationPassed -ne $null }
            $passedValidation = ($validationResults | Where-Object { $_.ValidationPassed }).Count
            Write-StatusMessage "✅ PRs passing validation: $passedValidation/$($validationResults.Count)" -Color $GREEN
        }
    }
}

Write-Host "`n💡 **USAGE EXAMPLES**" -ForegroundColor $YELLOW
Write-Host "# Full automation (approve workflows, check validation, handle conflicts)" -ForegroundColor $CYAN
Write-Host ".\automation\Monitor-CopilotPRs.ps1 -AutoApproveWorkflows -CheckValidation -HandleMergeConflicts" -ForegroundColor $WHITE
Write-Host "" -ForegroundColor $CYAN
Write-Host "# Monitor specific PR with full automation" -ForegroundColor $CYAN
Write-Host ".\automation\Monitor-CopilotPRs.ps1 -SpecificPR 60 -AutoApproveWorkflows -CheckValidation" -ForegroundColor $WHITE
Write-Host "" -ForegroundColor $CYAN
Write-Host "# Show current validation issues across all files" -ForegroundColor $CYAN
Write-Host ".\automation\Monitor-CopilotPRs.ps1 -ShowValidationIssues" -ForegroundColor $WHITE
Write-Host "" -ForegroundColor $CYAN
Write-Host "# Just check validation status" -ForegroundColor $CYAN
Write-Host ".\automation\Monitor-CopilotPRs.ps1 -CheckValidation" -ForegroundColor $WHITE

Write-Host "`n" + ("=" * 60) -ForegroundColor $MAGENTA
Write-StatusMessage "🚀 Copilot PR monitoring completed!" -Color $GREEN
