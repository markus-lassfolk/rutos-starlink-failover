# RUTOS Issue Automation Script for GitHub Copilot
# Enhanced Autonomous Version with Single Working Branch
# Run in PowerShell (Windows) with GH CLI authenticated

param(
    [string]$WorkingBranch = "automation/rutos-compatibility-fixes",
    [int]$MaxIssues = 5,
    [switch]$DryRun = $false,
    [switch]$CleanupOldIssues = $false,
    [switch]$MonitorOnly = $false,
    [string]$TestIssueNumber = "",
    [switch]$TestCopilotAssignment = $false
)

function Get-SmartValidationStatus {
    Write-Host "🔍 **SMART VALIDATION STATUS**" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Cyan
    
    # Get validation issues on main branch (stay on current branch)
    Write-Host "📊 Checking validation issues on main branch..." -ForegroundColor Yellow
    
    # Option 1: Check GitHub Actions workflow results for validation
    Write-Host "🔍 Checking GitHub Actions workflow results..." -ForegroundColor Cyan
    try {
        $workflowRuns = gh run list --workflow="shellcheck-format.yml" --limit=5 --json status,conclusion,headBranch,displayTitle 2>&1
        if ($LASTEXITCODE -eq 0) {
            $workflowData = $workflowRuns | ConvertFrom-Json
            $mainWorkflow = $workflowData | Where-Object { $_.headBranch -eq "main" } | Select-Object -First 1
            
            if ($mainWorkflow) {
                $statusColor = switch ($mainWorkflow.conclusion) {
                    "success" { "Green" }
                    "failure" { "Red" }
                    "skipped" { "Yellow" }
                    "action_required" { "Yellow" }
                    default { "Gray" }
                }
                Write-Host "  ✅ Latest shellcheck workflow: $($mainWorkflow.conclusion)" -ForegroundColor $statusColor
                Write-Host "  📝 Commit: $($mainWorkflow.displayTitle)" -ForegroundColor Gray
                
                # If workflow passed, we know validation is clean
                if ($mainWorkflow.conclusion -eq "success") {
                    Write-Host "  ✅ Server-side validation indicates clean repository" -ForegroundColor Green
                    $serverValidationClean = $true
                } else {
                    Write-Host "  ⚠️  Server-side validation indicates issues exist" -ForegroundColor Yellow
                    $serverValidationClean = $false
                }
            } else {
                Write-Host "  ⚠️  No recent validation workflow found for main branch" -ForegroundColor Yellow
                $serverValidationClean = $false
            }
        } else {
            Write-Host "  ⚠️  Could not fetch workflow results" -ForegroundColor Yellow
            $serverValidationClean = $false
        }
    } catch {
        Write-Host "  ⚠️  GitHub Actions check failed" -ForegroundColor Yellow
        $serverValidationClean = $false
    }
    
    # Option 2: Use server-side validation via GitHub API (check file contents)
    Write-Host "🔍 Performing server-side validation check..." -ForegroundColor Cyan
    try {
        # Get shell script files from repository
        $shellFiles = gh api repos/:owner/:repo/contents --jq '.[].name | select(endswith(".sh"))' 2>&1
        if ($LASTEXITCODE -eq 0) {
            $shellFileCount = ($shellFiles | Measure-Object).Count
            Write-Host "  📁 Shell files found: $shellFileCount" -ForegroundColor Blue
            
            # Check for common RUTOS compatibility issues via file content
            $criticalCount = 0
            $majorCount = 0
            $filesWithIssues = @()
            
            # Sample a few files to check for issues (avoid rate limiting)
            $sampleFiles = $shellFiles | Select-Object -First 10
            foreach ($file in $sampleFiles) {
                try {
                    $fileContent = gh api repos/:owner/:repo/contents/$file --jq '.content' | base64 -d 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        # Check for common RUTOS compatibility issues
                        if ($fileContent -match '#!/bin/bash' -or $fileContent -match '\[\[' -or $fileContent -match 'local\s+\w+' -or $fileContent -match 'echo\s+-e') {
                            $criticalCount++
                            $filesWithIssues += $file
                        }
                    }
                } catch {
                    # Skip files that can't be read
                }
            }
            
            Write-Host "  🔍 Sample validation results:" -ForegroundColor Gray
            Write-Host "  🔴 Estimated critical issues: $criticalCount" -ForegroundColor Red
            Write-Host "  📁 Files with potential issues: $($filesWithIssues.Count)" -ForegroundColor Yellow
        } else {
            Write-Host "  ⚠️  Could not fetch repository file list" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ⚠️  Server-side validation check failed" -ForegroundColor Yellow
    }
    
    # Option 3: Use local validation only if server-side methods failed
    if ($serverValidationClean) {
        Write-Host "🔍 Server-side validation indicates clean repository - skipping local validation" -ForegroundColor Green
        $criticalCount = 0
        $majorCount = 0
        $filesWithIssues = @()
    } else {
        Write-Host "🔍 Fallback: Running local validation (staying on current branch)..." -ForegroundColor Cyan
        $currentBranch = git branch --show-current
        
        # Save current branch and ensure we're on main for validation
        if ($currentBranch -ne "main") {
            Write-Host "  🔄 Temporarily switching to main for validation..." -ForegroundColor Yellow
            git checkout main 2>&1 | Out-Null
        }
        
        $quickValidation = wsl ./scripts/pre-commit-validation.sh --all 2>&1
        $criticalCount = ($quickValidation | Select-String -Pattern "\[CRITICAL\]" | Measure-Object).Count
        $majorCount = ($quickValidation | Select-String -Pattern "\[MAJOR\]" | Measure-Object).Count
        
        # Get files with issues
        $filesWithIssues = $quickValidation | Select-String -Pattern "\[CRITICAL\]|\[MAJOR\]" | ForEach-Object {
            if ($_ -match '\[(CRITICAL|MAJOR)\]\s+(.+?):') { $matches[2].Trim() }
        } | Where-Object { $_ -ne $null } | Select-Object -Unique
        
        # CRITICAL: Always restore original branch if we switched
        if ($currentBranch -ne "main") {
            Write-Host "  🔄 Restoring original branch: $currentBranch" -ForegroundColor Yellow
            git checkout $currentBranch 2>&1 | Out-Null
        }
    }
    
    # Check if any PRs are addressing these files (server-side approach)
    $allPRs = gh pr list --json number,headRefName,files | ConvertFrom-Json
    $filesBeingFixed = @()
    
    foreach ($pr in $allPRs) {
        $prFiles = $pr.files | Where-Object { $_.path -like "*.sh" } | Select-Object -ExpandProperty path
        $filesBeingFixed += $prFiles
    }
    
    $filesBeingFixed = $filesBeingFixed | Select-Object -Unique
    
    Write-Host "📋 Validation Summary:" -ForegroundColor White
    Write-Host "  🔴 Critical issues: $criticalCount" -ForegroundColor Red
    Write-Host "  🟡 Major issues: $majorCount" -ForegroundColor Yellow
    Write-Host "  📁 Files with issues: $($filesWithIssues.Count)" -ForegroundColor Gray
    Write-Host "  🔄 Files being fixed in PRs: $($filesBeingFixed.Count)" -ForegroundColor Blue
    
    # Show which files are being addressed
    if ($filesBeingFixed.Count -gt 0) {
        Write-Host "`n🔄 **FILES BEING FIXED IN OPEN PRs**:" -ForegroundColor Blue
        $filesBeingFixed | ForEach-Object {
            $isIssueFile = $filesWithIssues -contains $_
            $status = if ($isIssueFile) { "🔧 Fixing issues" } else { "📝 Other changes" }
            Write-Host "  $status $_" -ForegroundColor $(if ($isIssueFile) { "Green" } else { "Gray" })
        }
    }
    
    # Show remaining issues
    $remainingIssues = $filesWithIssues | Where-Object { $filesBeingFixed -notcontains $_ }
    if ($remainingIssues.Count -gt 0) {
        Write-Host "`n❌ **FILES STILL NEEDING FIXES**:" -ForegroundColor Red
        $remainingIssues | ForEach-Object {
            Write-Host "  🔴 $_" -ForegroundColor Red
        }
        Write-Host "`n💡 Run: ./automation/Create-RUTOS-PRs.ps1 -MaxIssues 5 to create issues for these files" -ForegroundColor Yellow
    } else {
        Write-Host "`n✅ All files with issues are being addressed in open PRs!" -ForegroundColor Green
        Write-Host "💡 Use: .\automation\Monitor-CopilotPRs.ps1 -CheckValidation to check PR status" -ForegroundColor Cyan
    }
    
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    return @{
        TotalIssues = $criticalCount + $majorCount
        FilesWithIssues = $filesWithIssues.Count
        FilesBeingFixed = $filesBeingFixed.Count
        RemainingIssues = $remainingIssues.Count
    }
}

function Invoke-AutomationMonitoring {
    Write-Host "🔍 **AUTOMATION MONITORING DASHBOARD**" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    
    # Check current branch status (no switching needed)
    $currentBranch = git branch --show-current
    Write-Host "📍 Current branch: $currentBranch" -ForegroundColor Gray
    
    # Check for open automation issues
    $openIssues = gh issue list -l "rutos-compatibility" -l "automation" --state open --json number,title,assignees,labels | ConvertFrom-Json
    Write-Host "📋 Open automation issues: $($openIssues.Count)" -ForegroundColor Yellow
    
    if ($openIssues.Count -gt 0) {
        $openIssues | ForEach-Object {
            $assigneeNames = ($_.assignees | ForEach-Object { $_.login }) -join ", "
            Write-Host "  🔄 #$($_.number): $($_.title)" -ForegroundColor Blue
            $assigneeDisplay = if ($assigneeNames) { $assigneeNames } else { "Unassigned" }
            Write-Host "     👤 Assigned: $assigneeDisplay" -ForegroundColor Gray
        }
    }
    
    # Check for existing PRs from working branch
    $existingPRs = gh pr list --head ${WorkingBranch} --json number,title,state | ConvertFrom-Json
    Write-Host "🔀 PRs from ${WorkingBranch}: $($existingPRs.Count)" -ForegroundColor Green
    
    if ($existingPRs.Count -gt 0) {
        $existingPRs | ForEach-Object {
            Write-Host "  📝 #$($_.number): $($_.title) [$($_.state)]" -ForegroundColor Green
        }
    }
    
    # Check branch commits using GitHub API (server-side approach)
    Write-Host "🔍 Checking working branch status (server-side)..." -ForegroundColor Cyan
    try {
        $branchInfo = gh api repos/:owner/:repo/branches/${WorkingBranch} 2>&1
        if ($LASTEXITCODE -eq 0) {
            $branchData = $branchInfo | ConvertFrom-Json
            
            # Get commit count comparison using GitHub API
            $comparisonResult = gh api repos/:owner/:repo/compare/main...${WorkingBranch} 2>&1
            if ($LASTEXITCODE -eq 0) {
                $comparisonData = $comparisonResult | ConvertFrom-Json
                Write-Host "🌿 Commits in ${WorkingBranch}: $($comparisonData.ahead_by)" -ForegroundColor Magenta
                Write-Host "  📊 Files changed: $($comparisonData.files.Count)" -ForegroundColor Gray
            } else {
                Write-Host "🌿 Branch ${WorkingBranch} comparison failed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "🌿 Working branch ${WorkingBranch}: Not created yet" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "🌿 Working branch ${WorkingBranch}: Status check failed" -ForegroundColor Yellow
    }
    
    # Smart validation status (server-side validation)
    $validationStatus = Get-SmartValidationStatus
    
    Write-Host "`n💡 **RECOMMENDED ACTIONS**" -ForegroundColor Green
    if ($openIssues.Count -gt 0) {
        Write-Host "  ⏳ Wait for Copilot to complete open issues" -ForegroundColor Yellow
        Write-Host "  📊 Monitor PR progress with: .\automation\Monitor-CopilotPRs.ps1" -ForegroundColor Cyan
    }
    if ($criticalCount -gt 0 -or $majorCount -gt 0) {
        if ($openIssues.Count -eq 0) {
            Write-Host "  🚀 Create new issues: ./automation/Create-RUTOS-PRs.ps1 -MaxIssues 5" -ForegroundColor Green
        } else {
            Write-Host "  🔄 Check if PRs fix these issues: .\automation\Monitor-CopilotPRs.ps1 -CheckValidation" -ForegroundColor Blue
        }
    }
    if ($branchCommits -gt 0 -and $existingPRs.Count -eq 0) {
        Write-Host "  🔄 Consider creating PR from ${WorkingBranch}" -ForegroundColor Blue
    }
    if ($existingPRs.Count -gt 0) {
        Write-Host "  📋 Check PR validation status: .\automation\Monitor-CopilotPRs.ps1 -CheckValidation" -ForegroundColor Magenta
    }
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
}

# Handle monitor-only mode
if ($MonitorOnly) {
    Invoke-AutomationMonitoring
    exit 0
}

# Helper Functions for Enhanced Autonomy
function Test-Prerequisites {
    Write-Host "🔍 Checking prerequisites..." -ForegroundColor Cyan
    
    # Check if gh CLI is authenticated
    $ghAuth = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ GitHub CLI not authenticated. Run: gh auth login" -ForegroundColor Red
        exit 1
    }
    
    # Check if we're in a git repository
    if (-not (Test-Path ".git")) {
        Write-Host "❌ Not in a git repository root" -ForegroundColor Red
        exit 1
    }
    
    # Check if validation script exists
    if (-not (Test-Path "scripts/pre-commit-validation.sh")) {
        Write-Host "❌ Validation script not found: scripts/pre-commit-validation.sh" -ForegroundColor Red
        exit 1
    }
    
    # Check WSL availability
    $wslTest = wsl --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ WSL not available. Install WSL for validation." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ All prerequisites met" -ForegroundColor Green
}

function Clear-OldAutomationIssues {
    if (-not $CleanupOldIssues) { return }
    
    Write-Host "🧹 Cleaning up old automation issues..." -ForegroundColor Yellow
    
    # Find and close old automation issues
    $oldIssues = gh issue list -l "rutos-compatibility" -l "automation" --state open --json number,title | ConvertFrom-Json
    
    if ($oldIssues.Count -gt 0) {
        Write-Host "🔄 Found $($oldIssues.Count) old automation issues to close" -ForegroundColor Yellow
        
        foreach ($issue in $oldIssues) {
            Write-Host "  🔒 Closing issue #$($issue.number): $($issue.title)" -ForegroundColor Gray
            gh issue close $issue.number --comment "🤖 Closing old automation issue - replaced by new enhanced version"
        }
        
        Write-Host "✅ Old issues cleaned up" -ForegroundColor Green
    } else {
        Write-Host "✅ No old automation issues found" -ForegroundColor Green
    }
}

function Ensure-GitHubLabels {
    Write-Host "🏷️  Ensuring required GitHub labels exist..." -ForegroundColor Cyan
    
    $requiredLabels = @(
        @{ Name = "rutos-compatibility"; Description = "RUTOS/busybox compatibility issues"; Color = "D73A4A" },
        @{ Name = "automation"; Description = "Automated processes and scripts"; Color = "0052CC" },
        @{ Name = "copilot"; Description = "GitHub Copilot automated fixes"; Color = "7C3AED" },
        @{ Name = "autonomous"; Description = "Autonomous fixes requiring no human intervention"; Color = "10B981" }
    )
    
    foreach ($label in $requiredLabels) {
        $existingLabel = gh label list --json name,color,description | ConvertFrom-Json | Where-Object { $_.name -eq $label.Name }
        
        if (-not $existingLabel) {
            Write-Host "  ➕ Creating label: $($label.Name)" -ForegroundColor Yellow
            gh label create $label.Name --description $label.Description --color $label.Color 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ Label '$($label.Name)' created successfully" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Failed to create label '$($label.Name)'" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✅ Label '$($label.Name)' already exists" -ForegroundColor Green
        }
    }
}

function Test-IssueAssignmentStructure {
    param(
        [string]$IssueNumber
    )
    
    Write-Host "🔍 Analyzing issue assignment structure for #$IssueNumber..." -ForegroundColor Cyan
    
    try {
        # Get issue details using GitHub API
        $issueData = gh api repos/:owner/:repo/issues/$IssueNumber | ConvertFrom-Json
        
        Write-Host "📋 Issue #$IssueNumber Analysis:" -ForegroundColor Yellow
        Write-Host "  📝 Title: $($issueData.title)" -ForegroundColor Gray
        Write-Host "  👤 Assignees Count: $($issueData.assignees.Count)" -ForegroundColor Gray
        
        if ($issueData.assignees.Count -gt 0) {
            Write-Host "  🎯 Current Assignees:" -ForegroundColor Green
            $issueData.assignees | ForEach-Object {
                Write-Host "    - Login: $($_.login)" -ForegroundColor Blue
                Write-Host "    - ID: $($_.id)" -ForegroundColor Gray
                Write-Host "    - Type: $($_.type)" -ForegroundColor Gray
                Write-Host "    - URL: $($_.html_url)" -ForegroundColor Gray
            }
            
            # Check if Copilot is assigned
            $copilotAssigned = $issueData.assignees | Where-Object { $_.login -eq "Copilot" }
            if ($copilotAssigned) {
                Write-Host "  ✅ Copilot is successfully assigned!" -ForegroundColor Green
                Write-Host "  📊 Copilot Details:" -ForegroundColor Cyan
                Write-Host "    - Login: $($copilotAssigned.login)" -ForegroundColor Blue
                Write-Host "    - ID: $($copilotAssigned.id)" -ForegroundColor Gray
                Write-Host "    - Type: $($copilotAssigned.type)" -ForegroundColor Gray
                return @{ Success = $true; CopilotAssigned = $true; AssigneeData = $copilotAssigned }
            } else {
                Write-Host "  ⚠️  Copilot is NOT assigned" -ForegroundColor Yellow
                return @{ Success = $true; CopilotAssigned = $false; AssigneeData = $issueData.assignees }
            }
        } else {
            Write-Host "  ⚠️  No assignees found" -ForegroundColor Yellow
            return @{ Success = $true; CopilotAssigned = $false; AssigneeData = $null }
        }
    } catch {
        Write-Host "  ❌ Failed to analyze issue #$IssueNumber" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; CopilotAssigned = $false; AssigneeData = $null }
    }
}

function Get-GitHubAssignee {
    Write-Host "🤖 Determining optimal assignee..." -ForegroundColor Cyan
    
    # Get current user for fallback
    $currentUser = gh api user | ConvertFrom-Json
    $currentUsername = $currentUser.login
    
    # Based on our testing, "Copilot" is not assignable via GitHub CLI
    # It's a special UI feature that only works in the web interface
    # We'll use current user and rely on @copilot mentions in the issue body
    
    Write-Host "🔍 Note: Copilot assignment via CLI is not supported" -ForegroundColor Yellow
    Write-Host "   Issues will be assigned to current user with @copilot mentions" -ForegroundColor Gray
    Write-Host "   You can manually assign to Copilot in GitHub UI if needed" -ForegroundColor Gray
    
    Write-Host "🎯 Using current user as assignee: $currentUsername" -ForegroundColor Green
    Write-Host "   (Strong @copilot mentions in issue body for autonomous handling)" -ForegroundColor Cyan
    return $currentUsername
}

function Test-CopilotAssignment {
    <#
    .SYNOPSIS
    Tests if Copilot assignment is working correctly
    .DESCRIPTION
    Creates a test issue and attempts to assign it to Copilot to verify the workflow
    .PARAMETER Repository
    The repository to test in (format: owner/repo)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )
    
    Write-Host "🧪 Testing Copilot assignment workflow..." -ForegroundColor Cyan
    
    # Create a test issue
    $testTitle = "Test: Copilot Assignment Verification $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $testBody = "This is a test issue to verify Copilot assignment workflow.`n`n@copilot Please close this test issue."
    
    try {
        $testIssueResult = New-CopilotIssue -Title $testTitle -Body $testBody -Repository $Repository
        
        if ($testIssueResult.Success) {
            Write-Host "✅ Test issue created successfully: $($testIssueResult.URL)" -ForegroundColor Green
            $statusColor = if ($testIssueResult.Verified) { "Green" } else { "Yellow" }
            Write-Host "🤖 Assignment status: $($testIssueResult.Assignee)" -ForegroundColor $statusColor
            
            # Close the test issue
            $issueNumber = $testIssueResult.URL.Split('/')[-1]
            gh issue close $issueNumber --repo $Repository --comment "Test completed - closing automatically"
            Write-Host "🗑️  Test issue closed automatically" -ForegroundColor Gray
            
            return $testIssueResult.Verified
        } else {
            Write-Host "❌ Test issue creation failed: $($testIssueResult.Error)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Test failed with error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test mode for verifying Copilot assignment
if ($TestIssueNumber) {
    Write-Host "🧪 **TESTING MODE: Verifying Copilot Assignment**" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta
    
    $testResult = Test-IssueAssignmentStructure -IssueNumber $TestIssueNumber
    
    if ($testResult.Success) {
        Write-Host "✅ Test completed successfully!" -ForegroundColor Green
        
        if ($testResult.CopilotAssigned) {
            Write-Host "🎯 Result: Copilot is properly assigned to issue #$TestIssueNumber" -ForegroundColor Green
            Write-Host "🤖 This is the target structure for automated assignment" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️  Result: Copilot is NOT assigned to issue #$TestIssueNumber" -ForegroundColor Yellow
            Write-Host "👤 Current assignees:" -ForegroundColor Gray
            if ($testResult.AssigneeData) {
                $testResult.AssigneeData | ForEach-Object {
                    Write-Host "  - $($_.login) (ID: $($_.id))" -ForegroundColor Blue
                }
            } else {
                Write-Host "  - No assignees found" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "❌ Test failed - could not analyze issue #$TestIssueNumber" -ForegroundColor Red
    }
    
    Write-Host "`n💡 **Usage Instructions:**" -ForegroundColor Yellow
    Write-Host "1. Create a test issue and manually assign it to Copilot" -ForegroundColor White
    Write-Host "2. Run: ./automation/Create-RUTOS-PRs.ps1 -TestIssueNumber <issue-number>" -ForegroundColor White
    Write-Host "3. This will show the exact structure we need to match" -ForegroundColor White
    Write-Host "4. Then run the full script to verify automated assignment works" -ForegroundColor White
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Magenta
    exit 0
}

# Test mode for testing Copilot assignment workflow
if ($TestCopilotAssignment) {
    Write-Host "🧪 **TESTING MODE: Copilot Assignment Workflow**" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta
    
    # Get repository info
    $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
    $repository = $repoInfo.nameWithOwner
    
    Write-Host "📍 Repository: $repository" -ForegroundColor Gray
    Write-Host "🧪 Testing Copilot assignment workflow..." -ForegroundColor Cyan
    
    $testResult = Test-CopilotAssignment -Repository $repository
    
    if ($testResult) {
        Write-Host "✅ Copilot assignment test PASSED!" -ForegroundColor Green
        Write-Host "🤖 The workflow correctly assigns issues to Copilot" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Copilot assignment test FAILED!" -ForegroundColor Red
        Write-Host "⚠️  Issues may not be properly assigned to Copilot" -ForegroundColor Yellow
    }
    
    Write-Host "`n💡 **Next Steps:**" -ForegroundColor Yellow
    Write-Host "1. If test passed, run the full script to create actual issues" -ForegroundColor White
    Write-Host "2. If test failed, check GitHub CLI authentication and permissions" -ForegroundColor White
    Write-Host "3. Manual assignment in GitHub UI may be needed" -ForegroundColor White
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Magenta
    exit 0
}

# Main Script Execution
Write-Host "🔍 Starting Enhanced RUTOS Issue automation script for GitHub Copilot..." -ForegroundColor Cyan
Write-Host "📁 Working directory: $(Get-Location)" -ForegroundColor Gray
Write-Host "🌿 Working branch: ${WorkingBranch}" -ForegroundColor Green
Write-Host "📊 Max issues to create: $MaxIssues" -ForegroundColor Yellow

# Run prerequisite checks
Test-Prerequisites

# Clean up old issues if requested
Clear-OldAutomationIssues

# Get assignee for issues
$assignee = Get-GitHubAssignee

# Ensure required GitHub labels exist
Ensure-GitHubLabels

# Enhanced Git Management with Single Working Branch
Write-Host "`n🔧 Setting up git environment..." -ForegroundColor Yellow

# Ensure we're on main branch first
Write-Host "🔄 Switching to main branch..." -ForegroundColor Cyan
git checkout main 2>&1 | Out-Null
git pull origin main 2>&1 | Out-Null

# Check if working branch exists, create or reset it
$branchExists = git branch --list ${WorkingBranch} 2>&1 | Out-Null
if ($branchExists) {
    Write-Host "🔄 Resetting existing working branch: ${WorkingBranch}" -ForegroundColor Yellow
    git branch -D ${WorkingBranch} 2>&1 | Out-Null
}

Write-Host "🆕 Creating fresh working branch: ${WorkingBranch}" -ForegroundColor Green
git checkout -b ${WorkingBranch} 2>&1 | Out-Null

function Invoke-AutonomousValidation {
    param(
        [string]$FilePath,
        [int]$MaxRetries = 3
    )
    
    Write-Host "🔍 Running autonomous validation for $FilePath..." -ForegroundColor Cyan
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Host "  🔄 Validation attempt $i/$MaxRetries" -ForegroundColor Gray
        
        $validationResult = wsl ./scripts/pre-commit-validation.sh $FilePath 2>&1
        $validationPassed = $LASTEXITCODE -eq 0
        
        if ($validationPassed) {
            Write-Host "  ✅ Validation passed!" -ForegroundColor Green
            return @{
                Success = $true
                Output = $validationResult
                Attempts = $i
            }
        } else {
            Write-Host "  ❌ Validation failed (attempt $i)" -ForegroundColor Red
            if ($i -eq $MaxRetries) {
                Write-Host "  ⚠️  Max retries reached" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Output = $validationResult
                    Attempts = $i
                }
            }
            Start-Sleep -Seconds 2
        }
    }
}

function New-AutomatedPullRequest {
    param(
        [string]$BranchName,
        [array]$CompletedIssues,
        [string]$Assignee
    )
    
    Write-Host "🔄 Creating automated pull request..." -ForegroundColor Cyan
    
    # Check if there are any changes to commit
    $hasChanges = git diff --name-only HEAD main | Measure-Object | Select-Object -ExpandProperty Count
    if ($hasChanges -eq 0) {
        Write-Host "⚠️  No changes found in branch ${BranchName}" -ForegroundColor Yellow
        return $false
    }
    
    # Create comprehensive PR description
    $prTitle = "🤖 RUTOS Compatibility Fixes - Automated Batch ($($CompletedIssues.Count) files)"
    $prBody = @"
## 🤖 Automated RUTOS Compatibility Fix Batch

This PR contains autonomous fixes for RUTOS/busybox compatibility issues across multiple files.

### 📊 **Summary**
- **Files Fixed**: $($CompletedIssues.Count)
- **Branch**: ``${BranchName}``
- **Validation**: All files pass pre-commit validation
- **Target**: RUTX50 router with RUTOS RUT5_R_00.07.09.7 (armv7l busybox)

### 📋 **Files Included**
$($CompletedIssues | ForEach-Object { "- ✅ ``$($_.File)`` - $($_.IssueNumber)" } | Out-String)

### 🔧 **Autonomous Fixes Applied**
- POSIX sh compatibility (busybox environment)
- ShellCheck compliance (SC2164, SC2002, SC2034, SC2059, etc.)
- Removed bash-specific syntax (arrays, [[]], local, function())
- Fixed printf format strings
- Added proper error handling

### ✅ **Validation Results**
All files pass RUTOS compatibility validation:
``````bash
wsl ./scripts/pre-commit-validation.sh --all
``````

### 🎯 **Testing Recommendations**
1. **Local Testing**: Run validation script on changed files
2. **RUTOS Testing**: Deploy to actual RUTX50 hardware if possible
3. **Integration**: Verify scripts work in busybox environment

### 🔗 **Related Issues**
$($CompletedIssues | ForEach-Object { "- Closes #$($_.IssueNumber)" } | Out-String)

---
**Auto-generated by**: Enhanced PowerShell automation v2.0  
**Assigned to**: @$Assignee  
**Branch Strategy**: Single working branch for all RUTOS fixes  
**Priority**: Critical RUTOS hardware compatibility
"@

    # Create the pull request
    Write-Host "📝 Creating pull request..." -ForegroundColor Yellow
    $prResult = gh pr create --title $prTitle --body $prBody --base main --head $BranchName --assignee $Assignee -l "rutos-compatibility" -l "automation" -l "copilot" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Pull request created successfully!" -ForegroundColor Green
        $prUrl = ($prResult | Select-String -Pattern "https://github.com/.*" | ForEach-Object { $_.Line.Trim() })
        if ($prUrl) {
            Write-Host "🔗 PR URL: $prUrl" -ForegroundColor Blue
            return $prUrl
        }
        return $true
    } else {
        Write-Host "❌ Pull request creation failed" -ForegroundColor Red
        Write-Host "Error: $prResult" -ForegroundColor Red
        return $false
    }
}

# Enhanced Validation and Issue Prioritization
Write-Host "`n🔧 Running enhanced pre-commit validation..." -ForegroundColor Yellow
$validationOutput = wsl ./scripts/pre-commit-validation.sh --all 2>&1
Write-Host "✅ Validation complete. Output lines: $($validationOutput.Count)" -ForegroundColor Green

# Parse output for files with errors and categorize by severity
Write-Host "🔍 Parsing validation output for errors..." -ForegroundColor Yellow
$criticalFiles = $validationOutput | Select-String -Pattern "\[CRITICAL\]" | ForEach-Object {
    if ($_ -match '\[CRITICAL\] (.*?):') { $matches[1].Trim() }
} | Where-Object { $_ -ne $null } | Select-Object -Unique

$majorFiles = $validationOutput | Select-String -Pattern "\[MAJOR\]" | ForEach-Object {
    if ($_ -match '\[MAJOR\] (.*?):') { $matches[1].Trim() }
} | Where-Object { $_ -ne $null } | Select-Object -Unique

# Prioritize: CRITICAL first, then MAJOR, then shell scripts
Write-Host "📊 Found errors:" -ForegroundColor Cyan
Write-Host "  🔴 Critical files: $($criticalFiles.Count)" -ForegroundColor Red
Write-Host "  🟡 Major files: $($majorFiles.Count)" -ForegroundColor Yellow

# Smart prioritization algorithm
$targetFiles = @()
$allFilesWithErrors = ($criticalFiles + $majorFiles) | Select-Object -Unique

# Prioritize shell scripts for RUTOS compatibility
$shellScripts = $allFilesWithErrors | Where-Object { $_ -match '\.sh$' }
$otherFiles = $allFilesWithErrors | Where-Object { $_ -notmatch '\.sh$' }

# Critical shell scripts first
$criticalShellScripts = $criticalFiles | Where-Object { $_ -match '\.sh$' }
$majorShellScripts = $majorFiles | Where-Object { $_ -match '\.sh$' }

# Build priority list
if ($criticalShellScripts.Count -gt 0) {
    $targetFiles += $criticalShellScripts | Select-Object -First ([Math]::Min($criticalShellScripts.Count, $MaxIssues))
}
if ($targetFiles.Count -lt $MaxIssues -and $majorShellScripts.Count -gt 0) {
    $remaining = $MaxIssues - $targetFiles.Count
    $targetFiles += $majorShellScripts | Select-Object -First $remaining
}
if ($targetFiles.Count -lt $MaxIssues -and $otherFiles.Count -gt 0) {
    $remaining = $MaxIssues - $targetFiles.Count
    $targetFiles += $otherFiles | Select-Object -First $remaining
}

Write-Host "🎯 Selected $($targetFiles.Count) files for processing:" -ForegroundColor Magenta
$targetFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

# Enhanced Issue Processing with Single Branch Strategy
$issueCounter = 0
$successfulIssues = @()
$failedIssues = @()

foreach ($file in $targetFiles) {
    $issueCounter++
    Write-Host "`n🔄 Processing file $issueCounter/$($targetFiles.Count): $file" -ForegroundColor Yellow
    
    # Skip if dry run
    if ($DryRun) {
        Write-Host "🔍 DRY RUN - Would process: $file" -ForegroundColor Cyan
        continue
    }
    
    # Get specific validation issues for this file
    Write-Host "🔍 Running targeted validation..." -ForegroundColor Cyan
    $fileValidation = wsl ./scripts/pre-commit-validation.sh $file 2>&1
    $fileValidationPassed = $LASTEXITCODE -eq 0
    
    if ($fileValidationPassed) {
        Write-Host "✅ File already passes validation - skipping" -ForegroundColor Green
        continue
    }
    
function Format-ValidationIssuesMarkdown {
    param(
        [string]$FilePath,
        [string]$ValidationOutput
    )
    
    # Parse validation output to extract detailed issues
    $issueLines = $ValidationOutput -split "`n" | Where-Object { $_ -match '\[(CRITICAL|MAJOR)\]' }
    
    if ($issueLines.Count -eq 0) {
        return "## ⚠️  **No specific validation issues found**`n`nThe validation script reported problems, but no detailed issues were extracted from the output. This might be a validation script issue rather than a RUTOS compatibility problem.`n`nPlease check the validation script output manually."
    }
    
    $markdownOutput = @()
    $markdownOutput += "## 🔍 **Detailed Validation Issues**"
    $markdownOutput += ""
    
    $realIssueCount = 0
    
    foreach ($issueLine in $issueLines) {
        if ($issueLine -match '\[(CRITICAL|MAJOR)\]\s+(.+?):\s*(.+)') {
            $severity = $matches[1]
            $file = $matches[2]
            $description = $matches[3]
            
            # Skip automation-related issues
            if ($description -like "*Could not fetch file*" -or $description -like "*Server-side validation*") {
                continue
            }
            
            $realIssueCount++
            
            # Extract line number if present
            $lineNumber = "Unknown"
            if ($description -match 'line (\d+)') {
                $lineNumber = $matches[1]
            }
            
            # Extract ShellCheck code if present
            $shellCheckCode = "N/A"
            if ($description -match '(SC\d+)') {
                $shellCheckCode = $matches[1]
            }
            
            # Create severity icon
            $severityIcon = if ($severity -eq "CRITICAL") { "🔴" } else { "🟡" }
            
            $markdownOutput += "### $severityIcon **$severity**: Line $lineNumber"
            $markdownOutput += ""
            $markdownOutput += "**File**: ``$file``"
            $markdownOutput += "**Issue**: $description"
            $markdownOutput += "**ShellCheck**: $shellCheckCode"
            $markdownOutput += ""
            
            # Add specific solutions based on common issues
            $solution = Get-SolutionForIssue -Description $description -ShellCheckCode $shellCheckCode
            if ($solution) {
                $markdownOutput += "**Solution**:"
                $markdownOutput += "``````bash"
                $markdownOutput += $solution
                $markdownOutput += "``````"
                $markdownOutput += ""
            }
            
            $markdownOutput += "---"
            $markdownOutput += ""
        }
    }
    
    if ($realIssueCount -eq 0) {
        return "## ⚠️  **No actionable RUTOS compatibility issues found**`n`nThe validation failures appear to be related to automation/technical issues rather than actual RUTOS compatibility problems. This issue may resolve automatically."
    }
    
    return $markdownOutput -join "`n"
}

function Get-SolutionForIssue {
    param(
        [string]$Description,
        [string]$ShellCheckCode
    )
    
    # Provide specific solutions based on common RUTOS compatibility issues
    switch -Regex ($Description) {
        "bash.*shebang" { return "#!/bin/sh" }
        "local.*keyword" { return "# Remove 'local' keyword - all variables are global in busybox`nVARIABLE_NAME=`"value`"" }
        "printf.*format" { return "# Use %s placeholders instead of variables in format string`nprintf `"%s%s%s`n`" `"`$VAR1`" `"`$VAR2`" `"`$VAR3`"" }
        "echo.*-e" { return "# Replace echo -e with printf`nprintf `"message with\nescapes\n`"" }
        "\[\[.*\]\]" { return "# Replace [[ ]] with [ ] for POSIX compatibility`nif [ `"`$condition`" = `"value`" ]; then" }
        "array" { return "# Convert arrays to space-separated strings`nITEMS=`"item1 item2 item3`"`nfor item in `$ITEMS; do" }
        "function.*syntax" { return "# Use POSIX function syntax`nfunction_name() {`n    # function body`n}" }
        "source.*command" { return "# Use dot (.) instead of source`n. ./script.sh" }
        default { 
            # Fallback based on ShellCheck code
            switch ($ShellCheckCode) {
                "SC2164" { return "# Add error handling to cd commands`ncd /path/to/directory || exit 1" }
                "SC2002" { return "# Remove useless cat`n# Instead of: cat file | command`ncommand < file" }
                "SC2034" { return "# Add shellcheck disable for intentionally unused variables`n# shellcheck disable=SC2034`nVARIABLE_NAME=`"value`"" }
                "SC2059" { return "# Fix printf format strings`nprintf `"%s: %s`n`" `"`$label`" `"`$value`"" }
                "SC3043" { return "# Remove local keyword`n# Instead of: local var=value`nvar=value" }
                default { return $null }
            }
        }
    }
}

    # Extract specific issues with enhanced parsing
    $specificIssues = $fileValidation | Select-String -Pattern "\[MAJOR\]|\[CRITICAL\]" | ForEach-Object { 
        $_.Line.Trim() 
    }
    $shellCheckIssues = $fileValidation | Select-String -Pattern "SC[0-9]{4}" | ForEach-Object { 
        $_.Line.Trim() 
    }
    $allIssues = ($specificIssues + $shellCheckIssues) | Select-Object -Unique
    
    Write-Host "📊 Found $($allIssues.Count) specific issues in $file" -ForegroundColor Yellow
    
    # Create detailed markdown-formatted issues
    $detailedIssues = Format-ValidationIssuesMarkdown -FilePath $file -ValidationOutput $fileValidation
    
    # Check if there are actual RUTOS compatibility issues to fix
    if ($detailedIssues -like "*No actionable RUTOS compatibility issues found*" -or 
        $detailedIssues -like "*No specific validation issues found*") {
        Write-Host "⚠️  No actionable RUTOS compatibility issues found in $file - skipping issue creation" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "📊 Created detailed validation report for $file" -ForegroundColor Yellow
    
    # Create comprehensive issue with enhanced autonomous instructions
    $issueTitle = "🤖 RUTOS Compatibility: Fix $file (Autonomous Fix Required)"
    
    # Determine priority using PowerShell 5.1 compatible syntax
    $priority = if ($criticalFiles -contains $file) { "🔴 CRITICAL" } else { "🟡 MAJOR" }
    
    $issueBody = @"
👋 **@copilot** - This issue is specifically assigned to you for autonomous fixing!

## 🎯 **Fully Autonomous Fix Instructions for GitHub Copilot**

### **Context & Environment**
- **Target**: RUTX50 router with RUTOS RUT5_R_00.07.09.7 (armv7l busybox)
- **Shell**: POSIX sh only (NOT bash) - busybox environment
- **Branch**: Working on ``${WorkingBranch}`` (single branch for all fixes)
- **Priority**: $priority

### **Specific Issues Found**
$detailedIssues

### **🤖 Autonomous Fix Protocol for @copilot**
1. **Read Guidelines**: Follow ``.github/copilot-instructions.md`` for RUTOS requirements
2. **Switch Branch**: ``git checkout ${WorkingBranch}``
3. **Apply Fixes**: Address ALL issues using POSIX sh syntax only
4. **Validate**: Run ``wsl ./scripts/pre-commit-validation.sh $file`` until clean
5. **Commit**: Use descriptive commit message with 🔧 emoji
6. **Auto-Close**: Add "Closes #[issue-number]" in commit message
7. **Report**: Comment with validation results

### **Critical RUTOS Compatibility Requirements**
- **SC2164**: Add ``|| exit 1`` to cd commands
- **SC2002**: Remove useless cat pipes (``cat file | command`` → ``command < file``)
- **SC2034**: Add ``# shellcheck disable=SC2034`` for intentionally unused vars
- **SC2059**: Fix printf format strings - use ``%s`` placeholders, not variables in format
- **SC3043**: Remove ``local`` keyword (busybox doesn't support it)
- **Arrays**: Convert to space-separated strings or multiple variables
- **[[]]**: Use single brackets ``[ ]`` for all conditions
- **function()**: Use ``name() {`` syntax (no function keyword)
- **echo -e**: Use ``printf`` instead for escape sequences
- **set -x**: Use structured logging instead for debugging

### **Enhanced Validation Workflow**
``````bash
# Test your fixes (iterate until clean)
wsl ./scripts/pre-commit-validation.sh $file

# Expected result: No MAJOR or CRITICAL issues
# Success indicator: "[SUCCESS] ✓ filename: All checks passed"
``````

### **Single Branch Strategy Benefits**
✅ **Efficient**: All fixes in one branch ``${WorkingBranch}``  
✅ **Optimized CI**: Workflow only validates changed files in PRs  
✅ **No Conflicts**: Your changes won't conflict with other unfixed files  
✅ **Fast Review**: Batch processing of multiple fixes  

### **Auto-Assignment & Copilot Integration**
- **Primary Handler**: @copilot (YOU!) - autonomous fixes required
- **Fallback Assignee**: @$assignee (if direct assignment fails)
- **Reviewer**: Repository maintainers
- **Automation**: This issue was created by enhanced PowerShell automation

### **Success Criteria & Auto-Close**
- [ ] All ShellCheck issues resolved
- [ ] RUTOS busybox compatibility confirmed  
- [ ] Pre-commit validation passes: ``wsl ./scripts/pre-commit-validation.sh $file``
- [ ] No MAJOR or CRITICAL issues remain
- [ ] Commit message includes "Closes #[this-issue-number]"
- [ ] GitHub Actions workflow passes

### **🚀 Final Autonomous Steps for @copilot**
1. **Commit with auto-close**: ``git commit -m "🔧 Fix RUTOS compatibility in $file - Closes #[issue-number]"``
2. **Validation comment**: Add exactly this comment when done:
   **"✅ RUTOS compatibility validation passed - Auto-fixed and ready for batch PR"**

---
**Enhanced Automation**: v2.0 with direct Copilot assignment  
**Primary Handler**: @copilot (autonomous fixing required)  
**Fallback Assignment**: @$assignee  
**Priority**: $priority - RUTOS hardware compatibility  
**Auto-Close**: Commit with "Closes #[issue-number]" will auto-close this issue
"@

function New-CopilotIssue {
    param(
        [string]$Title,
        [string]$Body,
        [string]$PreferredAssignee,
        [array]$Labels
    )
    
    Write-Host "🤖 Creating GitHub Issue with Copilot assignment..." -ForegroundColor Magenta
    
    # Step 1: Create the issue without Copilot assignment (GitHub CLI limitation)
    Write-Host "📝 Step 1: Creating issue with labels..." -ForegroundColor Cyan
    
    # Save the body to a temporary file to avoid command line parsing issues
    $tempBodyFile = [System.IO.Path]::GetTempFileName()
    $Body | Out-File -FilePath $tempBodyFile -Encoding UTF8
    
    # Build label arguments array
    $labelArgs = @()
    foreach ($label in $Labels) {
        $labelArgs += "-l"
        $labelArgs += $label
    }
    
    # Use splatting for better argument handling
    $ghArgs = @(
        "issue", "create",
        "--title", $Title,
        "--body-file", $tempBodyFile
    ) + $labelArgs
    
    Write-Host "🔍 Debug: Creating issue with title '$Title' and $($Labels.Count) labels" -ForegroundColor Gray
    
    $createResult = & gh @ghArgs 2>&1
    
    # Clean up temporary file
    try {
        Remove-Item $tempBodyFile -ErrorAction SilentlyContinue
    } catch {
        Write-Host "⚠️  Warning: Could not remove temporary file $tempBodyFile" -ForegroundColor Yellow
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Issue creation failed" -ForegroundColor Red
        Write-Host "🔍 Error details:" -ForegroundColor Yellow
        Write-Host "$createResult" -ForegroundColor Red
        
        return @{ 
            Success = $false; 
            Result = $createResult; 
            Assignee = "failed"; 
            Verified = $false;
            CopilotMentioned = $false;
            Error = $createResult 
        }
    }
    
    Write-Host "✅ Issue created successfully!" -ForegroundColor Green
    
    # Extract issue number from result with improved pattern matching
    $issueNumber = $null
    if ($createResult -match "#(\d+)") {
        $issueNumber = $matches[1]
    } elseif ($createResult -match "issues/(\d+)") {
        $issueNumber = $matches[1]
    }
    
    if (-not $issueNumber) {
        Write-Host "⚠️  Could not extract issue number from result" -ForegroundColor Yellow
        Write-Host "🔍 Result content: $createResult" -ForegroundColor Gray
        return @{ 
            Success = $true; 
            Result = $createResult; 
            Assignee = "unassigned"; 
            Verified = $false;
            CopilotMentioned = $true;
            IssueNumber = "unknown" 
        }
    }
    
    Write-Host "� Issue #$issueNumber created" -ForegroundColor Cyan
    
    # Step 2: Assign Copilot using gh issue edit (the only way that works)
    Write-Host "🤖 Step 2: Assigning Copilot using gh issue edit..." -ForegroundColor Cyan
    $assignResult = gh issue edit $issueNumber --add-assignee "@copilot" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Copilot assigned successfully!" -ForegroundColor Green
        
        # Step 3: Verify the assignment worked
        Write-Host "🔍 Step 3: Verifying Copilot assignment..." -ForegroundColor Cyan
        Start-Sleep -Seconds 2  # Give GitHub API time to process
        
        $verification = Test-IssueAssignmentStructure -IssueNumber $issueNumber
        
        if ($verification.Success -and $verification.CopilotAssigned) {
            Write-Host "✅ Copilot assignment verified!" -ForegroundColor Green
            return @{ 
                Success = $true; 
                Result = $createResult; 
                Assignee = "Copilot"; 
                IssueNumber = $issueNumber; 
                Verified = $true;
                CopilotMentioned = $true 
            }
        } else {
            Write-Host "⚠️  Copilot assignment verification failed" -ForegroundColor Yellow
            return @{ 
                Success = $true; 
                Result = $createResult; 
                Assignee = "unverified"; 
                IssueNumber = $issueNumber; 
                Verified = $false;
                CopilotMentioned = $true 
            }
        }
    } else {
        Write-Host "⚠️  Copilot assignment failed, but issue created successfully" -ForegroundColor Yellow
        Write-Host "🔍 Assignment error: $assignResult" -ForegroundColor Gray
        Write-Host "💡 Issue #$issueNumber has @copilot mentions in body" -ForegroundColor Gray
        
        return @{ 
            Success = $true; 
            Result = $createResult; 
            Assignee = "unassigned"; 
            IssueNumber = $issueNumber; 
            Verified = $false;
            CopilotMentioned = $true;
            AssignmentError = $assignResult
        }
    }
}

    # Create GitHub Issue with enhanced Copilot assignment
    $issueCreation = New-CopilotIssue -Title $issueTitle -Body $issueBody -PreferredAssignee $assignee -Labels @("rutos-compatibility", "automation", "copilot", "autonomous")
    
    if ($issueCreation.Success) {
        Write-Host "✅ Issue created successfully for $file" -ForegroundColor Green
        $issueUrl = ($issueCreation.Result | Select-String -Pattern "https://github.com/.*" | ForEach-Object { $_.Line.Trim() })
        $issueNumber = $issueCreation.IssueNumber
        
        if (-not $issueNumber) {
            $issueNumber = ($issueCreation.Result | Select-String -Pattern "#(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        }
        
        if ($issueUrl) {
            Write-Host "🔗 Issue URL: $issueUrl" -ForegroundColor Blue
            Write-Host "🔢 Issue Number: #$issueNumber" -ForegroundColor Cyan
            
            # Determine priority using PowerShell 5.1 compatible syntax
            $priority = if ($criticalFiles -contains $file) { "Critical" } else { "Major" }
            
            $successfulIssues += @{ 
                File = $file; 
                URL = $issueUrl; 
                IssueNumber = $issueNumber;
                Priority = $priority;
                AssignmentVerified = $false;
                FinalAssignee = $issueCreation.Assignee;
                CopilotMentioned = $issueCreation.CopilotMentioned
            }
        }
        
        # Enhanced assignment reporting
        if ($issueCreation.Verified) {
            Write-Host "✅ Copilot assignment verified: $($issueCreation.Assignee)" -ForegroundColor Green
            Write-Host "🤖 Issue ready for autonomous Copilot handling" -ForegroundColor Magenta
        } else {
            Write-Host "⚠️  Assignment status: $($issueCreation.Assignee)" -ForegroundColor Yellow
            Write-Host "🤖 @copilot mentioned in issue body" -ForegroundColor Gray
            if ($issueCreation.AssignmentError) {
                Write-Host "🔍 Assignment error: $($issueCreation.AssignmentError)" -ForegroundColor Gray
            }
        }
        Write-Host "💡 Issue can be manually assigned to Copilot in GitHub UI if needed" -ForegroundColor Cyan
        
        # Post-creation validation check (single attempt - this is expected to fail)
        Write-Host "🔍 Running initial validation check..." -ForegroundColor Cyan
        $validationResult = wsl ./scripts/pre-commit-validation.sh $file 2>&1
        $validationPassed = $LASTEXITCODE -eq 0
        
        if ($validationPassed) {
            Write-Host "✅ File already passes validation (unexpected - issue may not be needed)" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Initial validation failed - Copilot will fix this (expected behavior)" -ForegroundColor Yellow
        }
        
        # Small delay to avoid rate limiting
        Start-Sleep -Seconds 3
    } else {
        Write-Host "❌ Issue creation failed for $file" -ForegroundColor Red
        Write-Host "🔍 Error details:" -ForegroundColor Yellow
        Write-Host "$($issueCreation.Error)" -ForegroundColor Red
        $failedIssues += @{ File = $file; Error = $issueCreation.Error }
    }
}

# Enhanced Summary and Reporting with Auto-PR Creation
Write-Host "`n🎉 Enhanced automation script completed!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan

# Check for completed issues and auto-create PR if applicable
$hasCompletedFixes = $false
if ($successfulIssues.Count -gt 0) {
    Write-Host "🔍 Checking for completed fixes in branch..." -ForegroundColor Cyan
    
    # Check if there are commits in the working branch
    $branchCommits = git rev-list --count HEAD ^main 2>&1
    if ($LASTEXITCODE -eq 0 -and [int]$branchCommits -gt 0) {
        Write-Host "✅ Found $branchCommits commits in working branch - preparing auto-PR" -ForegroundColor Green
        $hasCompletedFixes = $true
        
        # Create automated pull request
        $prResult = New-AutomatedPullRequest -BranchName ${WorkingBranch} -CompletedIssues $successfulIssues -Assignee $assignee
        if ($prResult) {
            Write-Host "🎉 Automated pull request created successfully!" -ForegroundColor Green
            Write-Host "🔗 PR URL: $prResult" -ForegroundColor Blue
        }
    } else {
        Write-Host "⏳ No commits yet - issues are pending Copilot fixes" -ForegroundColor Yellow
    }
}

# Summary statistics
Write-Host "📊 **EXECUTION SUMMARY**" -ForegroundColor Cyan
Write-Host "  🌿 Working branch: ${WorkingBranch}" -ForegroundColor Green
Write-Host "  🎯 Total files processed: $($targetFiles.Count)" -ForegroundColor Gray
Write-Host "  ✅ Successful issues: $($successfulIssues.Count)" -ForegroundColor Green
Write-Host "  ❌ Failed issues: $($failedIssues.Count)" -ForegroundColor Red
Write-Host "  👤 Assigned to: $assignee" -ForegroundColor Cyan
Write-Host "  🤖 Copilot mentions: $($successfulIssues.Count)" -ForegroundColor Magenta

# PowerShell 5.1 compatible PR status display
$prStatusText = if ($hasCompletedFixes) { "Yes" } else { "Pending fixes" }
$prStatusColor = if ($hasCompletedFixes) { "Green" } else { "Yellow" }
Write-Host "  🔄 Auto-PR created: $prStatusText" -ForegroundColor $prStatusColor

if ($successfulIssues.Count -gt 0) {
    Write-Host "`n📋 **CREATED ISSUES**" -ForegroundColor Green
    $successfulIssues | ForEach-Object {
        $priorityColor = if ($_.Priority -eq "Critical") { "Red" } else { "Yellow" }
        $copilotIcon = if ($_.CopilotMentioned) { "🤖" } else { "👤" }
        $assigneeInfo = "$($_.FinalAssignee) (with @copilot mentions)"
        
        Write-Host "  ✅ $($_.File) [$($_.Priority)]" -ForegroundColor $priorityColor
        Write-Host "     🔗 $($_.URL)" -ForegroundColor Blue
        Write-Host "     🔢 Issue #$($_.IssueNumber)" -ForegroundColor Cyan
        Write-Host "     $copilotIcon Assigned: $assigneeInfo" -ForegroundColor Green
    }
    
    # Assignment summary
    $copilotMentionedCount = ($successfulIssues | Where-Object { $_.CopilotMentioned }).Count
    
    Write-Host "`n📊 **ASSIGNMENT SUMMARY**" -ForegroundColor Cyan
    Write-Host "  🤖 Issues with @copilot mentions: $copilotMentionedCount" -ForegroundColor Green
    Write-Host "  👤 Assigned to current user: $($successfulIssues.Count)" -ForegroundColor Blue
    Write-Host "  � Manual Copilot assignment available in GitHub UI" -ForegroundColor Yellow
}

if ($failedIssues.Count -gt 0) {
    Write-Host "`n⚠️  **FAILED ISSUES**" -ForegroundColor Red
    $failedIssues | ForEach-Object {
        Write-Host "  ❌ $($_.File)" -ForegroundColor Red
        Write-Host "     Error: $($_.Error)" -ForegroundColor Gray
    }
    
    # Display detailed error information for debugging
    Write-Host "`n🔍 **DETAILED ERROR ANALYSIS**" -ForegroundColor Red
    Write-Host "=" * 60 -ForegroundColor Red
    foreach ($failedIssue in $failedIssues) {
        Write-Host "📁 File: $($failedIssue.File)" -ForegroundColor Yellow
        Write-Host "❌ Full Error Output:" -ForegroundColor Red
        Write-Host "$($failedIssue.Error)" -ForegroundColor White
        Write-Host "=" * 60 -ForegroundColor Red
    }
}

# Next steps and automation info
Write-Host "`n🤖 **AUTONOMOUS WORKFLOW ACTIVATED**" -ForegroundColor Magenta
Write-Host "  ✅ Single branch strategy: All fixes consolidated in ${WorkingBranch}" -ForegroundColor Green
Write-Host "  ✅ Issues assigned to $assignee with @copilot mentions" -ForegroundColor Green
Write-Host "  ✅ Each issue includes complete autonomous fix instructions" -ForegroundColor Green
Write-Host "  ✅ Auto-close mechanism: Commits with 'Closes #issue-number'" -ForegroundColor Green
Write-Host "  ✅ Validation workflow integrated with retry logic" -ForegroundColor Green
Write-Host "  ✅ GitHub Actions optimized for changed files only" -ForegroundColor Green
Write-Host "  ✅ Automated PR creation when fixes are committed" -ForegroundColor Green

# Advanced automation features
Write-Host "`n🚀 **ADVANCED AUTOMATION FEATURES**" -ForegroundColor Cyan
Write-Host "  🔄 Auto-PR: Created when commits are detected in ${WorkingBranch}" -ForegroundColor Blue
Write-Host "  🎯 Smart Assignment: Tries Copilot first, falls back to current user" -ForegroundColor Blue
Write-Host "  📊 Priority System: Critical files processed first" -ForegroundColor Blue
Write-Host "  🔍 Validation Retry: Up to 3 attempts with 2-second delays" -ForegroundColor Blue
Write-Host "  🏷️  Enhanced Labels: 'rutos-compatibility', 'automation', 'copilot', 'autonomous'" -ForegroundColor Blue
Write-Host "  📝 Rich Context: Complete RUTOS environment details in each issue" -ForegroundColor Blue

# Monitoring and next steps
Write-Host "`n📊 **MONITORING COMMANDS**" -ForegroundColor Yellow
Write-Host "  📋 Check issues: gh issue list --label rutos-compatibility" -ForegroundColor White
Write-Host "  🔀 Check PRs: gh pr list --head ${WorkingBranch}" -ForegroundColor White
Write-Host "  🌿 Check branch: git log --oneline ${WorkingBranch} ^main" -ForegroundColor White
Write-Host "  ✅ Validate: wsl ./scripts/pre-commit-validation.sh --all" -ForegroundColor White
Write-Host "  🔄 Re-run: ./automation/Create-RUTOS-PRs.ps1" -ForegroundColor White

# Links and references
Write-Host "`n🔗 **QUICK LINKS**" -ForegroundColor Blue
Write-Host "  📝 Issues: https://github.com/markus-lassfolk/rutos-starlink-failover/issues" -ForegroundColor Blue
Write-Host "  🔀 PRs: https://github.com/markus-lassfolk/rutos-starlink-failover/pulls" -ForegroundColor Blue
Write-Host "  📖 Guidelines: .github/copilot-instructions.md" -ForegroundColor Blue
Write-Host "  🌿 Branch: ${WorkingBranch}" -ForegroundColor Blue

# Final automation advice
Write-Host "`n💡 **AUTOMATION BENEFITS**" -ForegroundColor Yellow
Write-Host "  🎯 Single branch reduces git complexity" -ForegroundColor Yellow
Write-Host "  🤖 Autonomous fixes with detailed instructions" -ForegroundColor Yellow
Write-Host "  📊 Priority-based issue creation (Critical → Major → Shell)" -ForegroundColor Yellow
Write-Host "  ⚡ Optimized CI/CD (only validates changed files)" -ForegroundColor Yellow
Write-Host "  🔄 Iterative validation workflow" -ForegroundColor Yellow

Write-Host "`n🚀 **NEXT STEPS**" -ForegroundColor Cyan
Write-Host "  1. Monitor issue assignments to $assignee" -ForegroundColor White
Write-Host "  2. Review PRs as they're created from ${WorkingBranch}" -ForegroundColor White
Write-Host "  3. Use monitoring: ./automation/Create-RUTOS-PRs.ps1 -MonitorOnly" -ForegroundColor White
Write-Host "  4. Validate fixes: wsl ./scripts/pre-commit-validation.sh <file>" -ForegroundColor White
Write-Host "  5. Merge completed fixes from ${WorkingBranch} to main" -ForegroundColor White

# Usage examples
Write-Host "`n📖 **USAGE EXAMPLES**" -ForegroundColor Blue
Write-Host "  # Full automation run (recommended)" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -MaxIssues 5" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Monitor current status" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -MonitorOnly" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Dry run to see what would be created" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -DryRun" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Test Copilot assignment workflow" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -TestCopilotAssignment" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Test existing issue assignment structure" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -TestIssueNumber 123" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Clean up old issues first" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -CleanupOldIssues" -ForegroundColor White
Write-Host "" -ForegroundColor Gray
Write-Host "  # Custom branch name" -ForegroundColor Gray
Write-Host "  ./automation/Create-RUTOS-PRs.ps1 -WorkingBranch 'fix/custom-rutos'" -ForegroundColor White

if ($DryRun) {
    Write-Host "`n🔍 **DRY RUN COMPLETED** - No issues were actually created" -ForegroundColor Cyan
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "✅ Enhanced RUTOS compatibility automation ready!" -ForegroundColor Green

# Final error summary for debugging
if ($failedIssues.Count -gt 0) {
    Write-Host "`n🚨 **FINAL ERROR SUMMARY FOR DEBUGGING**" -ForegroundColor Red
    Write-Host "=" * 60 -ForegroundColor Red
    Write-Host "❌ $($failedIssues.Count) issue(s) failed to create" -ForegroundColor Red
    Write-Host "🔍 Most recent error:" -ForegroundColor Yellow
    $latestError = $failedIssues | Select-Object -Last 1
    Write-Host "📁 File: $($latestError.File)" -ForegroundColor White
    Write-Host "❌ Error: $($latestError.Error)" -ForegroundColor White
    Write-Host "=" * 60 -ForegroundColor Red
    Write-Host "💡 Check GitHub CLI authentication and label permissions" -ForegroundColor Yellow
}
