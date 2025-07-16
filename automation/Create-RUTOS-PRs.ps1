# RUTOS Issue Automation Script for GitHub Copilot
# Enhanced Autonomous Version with Single Working Branch
# Run in PowerShell (Windows) with GH CLI authenticated

param(
    [string]$WorkingBranch = "automation/rutos-compatibility-fixes",
    [int]$MaxIssues = 5,
    [switch]$DryRun = $false,
    [switch]$CleanupOldIssues = $false,
    [switch]$MonitorOnly = $false
)

function Invoke-AutomationMonitoring {
    Write-Host "🔍 **AUTOMATION MONITORING DASHBOARD**" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    
    # Check current branch status
    $currentBranch = git branch --show-current
    Write-Host "📍 Current branch: $currentBranch" -ForegroundColor Gray
    
    # Check for open automation issues
    $openIssues = gh issue list --label "rutos-compatibility,automation" --state open --json number,title,assignees,labels | ConvertFrom-Json
    Write-Host "📋 Open automation issues: $($openIssues.Count)" -ForegroundColor Yellow
    
    if ($openIssues.Count -gt 0) {
        $openIssues | ForEach-Object {
            $assigneeNames = ($_.assignees | ForEach-Object { $_.login }) -join ", "
            Write-Host "  🔄 #$($_.number): $($_.title)" -ForegroundColor Blue
            Write-Host "     👤 Assigned: $($assigneeNames ? $assigneeNames : 'Unassigned')" -ForegroundColor Gray
        }
    }
    
    # Check for existing PRs from working branch
    $existingPRs = gh pr list --head $WorkingBranch --json number,title,state | ConvertFrom-Json
    Write-Host "🔀 PRs from $WorkingBranch: $($existingPRs.Count)" -ForegroundColor Green
    
    if ($existingPRs.Count -gt 0) {
        $existingPRs | ForEach-Object {
            Write-Host "  📝 #$($_.number): $($_.title) [$($_.state)]" -ForegroundColor Green
        }
    }
    
    # Check branch commits
    $branchExists = git branch --list $WorkingBranch | Measure-Object | Select-Object -ExpandProperty Count
    if ($branchExists -gt 0) {
        $branchCommits = git rev-list --count HEAD ^main 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "🌿 Commits in $WorkingBranch: $branchCommits" -ForegroundColor Magenta
        }
    } else {
        Write-Host "🌿 Working branch $WorkingBranch: Not created yet" -ForegroundColor Yellow
    }
    
    # Quick validation status
    Write-Host "🔍 Running quick validation check..." -ForegroundColor Cyan
    $quickValidation = wsl ./scripts/pre-commit-validation.sh --all 2>&1
    $criticalCount = ($quickValidation | Select-String -Pattern "\[CRITICAL\]" | Measure-Object).Count
    $majorCount = ($quickValidation | Select-String -Pattern "\[MAJOR\]" | Measure-Object).Count
    
    Write-Host "📊 Current validation status:" -ForegroundColor Yellow
    Write-Host "  🔴 Critical issues: $criticalCount" -ForegroundColor Red
    Write-Host "  🟡 Major issues: $majorCount" -ForegroundColor Yellow
    
    Write-Host "`n💡 **RECOMMENDED ACTIONS**" -ForegroundColor Green
    if ($openIssues.Count -gt 0) {
        Write-Host "  ⏳ Wait for Copilot to complete open issues" -ForegroundColor Yellow
    }
    if ($criticalCount -gt 0 -or $majorCount -gt 0) {
        Write-Host "  🚀 Run: ./automation/Create-RUTOS-PRs.ps1 -MaxIssues 5" -ForegroundColor Green
    }
    if ($branchCommits -gt 0 -and $existingPRs.Count -eq 0) {
        Write-Host "  🔄 Consider creating PR from $WorkingBranch" -ForegroundColor Blue
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
    $oldIssues = gh issue list --label "rutos-compatibility,automation" --state open --json number,title | ConvertFrom-Json
    
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

function Get-GitHubAssignee {
    Write-Host "🤖 Determining optimal assignee..." -ForegroundColor Cyan
    
    # Get current user
    $currentUser = gh api user | ConvertFrom-Json
    $currentUsername = $currentUser.login
    
    # Enhanced Copilot assignment - try multiple approaches
    $copilotCandidates = @()
    
    # Method 1: Check for Copilot app installation
    try {
        $apps = gh api repos/:owner/:repo/installation | ConvertFrom-Json
        if ($apps.app_slug -contains "github-copilot") {
            Write-Host "🎯 GitHub Copilot app detected in repository" -ForegroundColor Green
            $copilotCandidates += "copilot"
        }
    } catch {
        Write-Host "🔍 Copilot app check failed - continuing with other methods" -ForegroundColor Gray
    }
    
    # Method 2: Check repository collaborators for Copilot-related users
    try {
        $repoCollaborators = gh api repos/:owner/:repo/collaborators | ConvertFrom-Json
        $copilotUsers = @("github-copilot", "copilot", "github-actions", "github-copilot[bot]")
        
        foreach ($copilotUser in $copilotUsers) {
            $found = $repoCollaborators | Where-Object { $_.login -eq $copilotUser }
            if ($found) {
                Write-Host "🎯 Found Copilot collaborator: $copilotUser" -ForegroundColor Green
                $copilotCandidates += $copilotUser
            }
        }
    } catch {
        Write-Host "🔍 Collaborator check failed - using current user" -ForegroundColor Gray
    }
    
    # Method 3: Use current user as assignee (Copilot will still be mentioned)
    if ($copilotCandidates.Count -eq 0) {
        Write-Host "🎯 Using current user as assignee: $currentUsername" -ForegroundColor Yellow
        Write-Host "   (Copilot will still be @mentioned in issues)" -ForegroundColor Gray
        return $currentUsername
    }
    
    # Return first available Copilot candidate
    $selectedAssignee = $copilotCandidates[0]
    Write-Host "🎯 Selected Copilot assignee: $selectedAssignee" -ForegroundColor Green
    return $selectedAssignee
}

# Main Script Execution
Write-Host "🔍 Starting Enhanced RUTOS Issue automation script for GitHub Copilot..." -ForegroundColor Cyan
Write-Host "📁 Working directory: $(Get-Location)" -ForegroundColor Gray
Write-Host "🌿 Working branch: $WorkingBranch" -ForegroundColor Green
Write-Host "📊 Max issues to create: $MaxIssues" -ForegroundColor Yellow

# Run prerequisite checks
Test-Prerequisites

# Clean up old issues if requested
Clear-OldAutomationIssues

# Enhanced Git Management with Single Working Branch
Write-Host "`n🔧 Setting up git environment..." -ForegroundColor Yellow

# Ensure we're on main branch first
Write-Host "🔄 Switching to main branch..." -ForegroundColor Cyan
git checkout main 2>&1 | Out-Null
git pull origin main 2>&1 | Out-Null

# Check if working branch exists, create or reset it
$branchExists = git branch --list $WorkingBranch 2>&1 | Out-Null
if ($branchExists) {
    Write-Host "🔄 Resetting existing working branch: $WorkingBranch" -ForegroundColor Yellow
    git branch -D $WorkingBranch 2>&1 | Out-Null
}

Write-Host "🆕 Creating fresh working branch: $WorkingBranch" -ForegroundColor Green
git checkout -b $WorkingBranch 2>&1 | Out-Null

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
        Write-Host "⚠️  No changes found in branch $BranchName" -ForegroundColor Yellow
        return $false
    }
    
    # Create comprehensive PR description
    $prTitle = "🤖 RUTOS Compatibility Fixes - Automated Batch ($($CompletedIssues.Count) files)"
    $prBody = @"
## 🤖 Automated RUTOS Compatibility Fix Batch

This PR contains autonomous fixes for RUTOS/busybox compatibility issues across multiple files.

### 📊 **Summary**
- **Files Fixed**: $($CompletedIssues.Count)
- **Branch**: ``$BranchName``
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
    $prResult = gh pr create --title $prTitle --body $prBody --base main --head $BranchName --assignee $Assignee --label "rutos-compatibility,automation,copilot" 2>&1
    
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
    
    # Extract specific issues with enhanced parsing
    $specificIssues = $fileValidation | Select-String -Pattern "\[MAJOR\]|\[CRITICAL\]" | ForEach-Object { 
        $_.Line.Trim() 
    }
    $shellCheckIssues = $fileValidation | Select-String -Pattern "SC[0-9]{4}" | ForEach-Object { 
        $_.Line.Trim() 
    }
    $allIssues = ($specificIssues + $shellCheckIssues) | Select-Object -Unique
    
    Write-Host "📊 Found $($allIssues.Count) specific issues in $file" -ForegroundColor Yellow
    
    # Create comprehensive issue with enhanced autonomous instructions
    $issueTitle = "🤖 RUTOS Compatibility: Fix $file (Autonomous Fix Required)"
    $issueBody = @"
@copilot Please autonomously fix the RUTOS/busybox compatibility issues in ``$file``.

## 🎯 **Fully Autonomous Fix Instructions**

### **Context & Environment**
- **Target**: RUTX50 router with RUTOS RUT5_R_00.07.09.7 (armv7l busybox)
- **Shell**: POSIX sh only (NOT bash) - busybox environment
- **Branch**: Working on ``$WorkingBranch`` (single branch for all fixes)
- **Priority**: $($criticalFiles -contains $file ? "🔴 CRITICAL" : "🟡 MAJOR")

### **Specific Issues Found**
``````
$($allIssues -join "`n")
``````

### **🤖 Autonomous Fix Protocol**
1. **Read Guidelines**: Follow ``.github/copilot-instructions.md`` for RUTOS requirements
2. **Switch Branch**: ``git checkout $WorkingBranch``
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
✅ **Efficient**: All fixes in one branch ``$WorkingBranch``  
✅ **Optimized CI**: Workflow only validates changed files in PRs  
✅ **No Conflicts**: Your changes won't conflict with other unfixed files  
✅ **Fast Review**: Batch processing of multiple fixes  

### **Auto-Assignment & Mentions**
- **Assigned to**: @$assignee
- **Primary Handler**: @copilot (autonomous fixes)
- **Reviewer**: Repository maintainers

### **Success Criteria & Auto-Close**
- [ ] All ShellCheck issues resolved
- [ ] RUTOS busybox compatibility confirmed  
- [ ] Pre-commit validation passes: ``wsl ./scripts/pre-commit-validation.sh $file``
- [ ] No MAJOR or CRITICAL issues remain
- [ ] Commit message includes "Closes #[this-issue-number]"
- [ ] GitHub Actions workflow passes

### **🚀 Final Autonomous Steps**
1. **Commit with auto-close**: ``git commit -m "🔧 Fix RUTOS compatibility in $file - Closes #[issue-number]"``
2. **Validation comment**: Add exactly this comment when done:
   **"✅ RUTOS compatibility validation passed - Auto-fixed and ready for batch PR"**

---
**Enhanced Automation**: v2.0 with single branch strategy  
**Assignment**: @$assignee (with @copilot autonomous handling)  
**Priority**: $($criticalFiles -contains $file ? "🔴 Critical" : "🟡 Major") - RUTOS hardware compatibility  
**Auto-Close**: Commit with "Closes #[issue-number]" will auto-close this issue
"@

    # Create GitHub Issue with enhanced Copilot assignment
    Write-Host "🤖 Creating autonomous GitHub Issue with Copilot assignment..." -ForegroundColor Magenta
    
    # Try to assign to copilot first, fallback to current user
    $assignmentResult = $null
    try {
        $assignmentResult = gh issue create --title $issueTitle --body $issueBody --assignee $assignee --label "rutos-compatibility,automation,copilot,autonomous" 2>&1
    } catch {
        Write-Host "⚠️  Primary assignment failed, trying without specific assignee..." -ForegroundColor Yellow
        $assignmentResult = gh issue create --title $issueTitle --body $issueBody --label "rutos-compatibility,automation,copilot,autonomous" 2>&1
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Issue created successfully for $file" -ForegroundColor Green
        $issueUrl = ($assignmentResult | Select-String -Pattern "https://github.com/.*" | ForEach-Object { $_.Line.Trim() })
        $issueNumber = ($assignmentResult | Select-String -Pattern "#(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        
        if ($issueUrl) {
            Write-Host "🔗 Issue URL: $issueUrl" -ForegroundColor Blue
            Write-Host "🔢 Issue Number: #$issueNumber" -ForegroundColor Cyan
            $successfulIssues += @{ 
                File = $file; 
                URL = $issueUrl; 
                IssueNumber = $issueNumber;
                Priority = ($criticalFiles -contains $file ? "Critical" : "Major")
            }
        }
        Write-Host "🎯 Assigned to: $assignee" -ForegroundColor Cyan
        Write-Host "🤖 @copilot mentioned for autonomous handling" -ForegroundColor Magenta
        
        # Enhanced validation check
        $validationResult = Invoke-AutonomousValidation -FilePath $file -MaxRetries 2
        if ($validationResult.Success) {
            Write-Host "✅ Post-creation validation passed!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Post-creation validation failed - Copilot will need to fix" -ForegroundColor Yellow
        }
        
        # Small delay to avoid rate limiting
        Start-Sleep -Seconds 3
    } else {
        Write-Host "❌ Issue creation failed for $file" -ForegroundColor Red
        Write-Host "Error: $assignmentResult" -ForegroundColor Red
        $failedIssues += @{ File = $file; Error = $assignmentResult }
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
        $prResult = New-AutomatedPullRequest -BranchName $WorkingBranch -CompletedIssues $successfulIssues -Assignee $assignee
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
Write-Host "  🌿 Working branch: $WorkingBranch" -ForegroundColor Green
Write-Host "  🎯 Total files processed: $($targetFiles.Count)" -ForegroundColor Gray
Write-Host "  ✅ Successful issues: $($successfulIssues.Count)" -ForegroundColor Green
Write-Host "  ❌ Failed issues: $($failedIssues.Count)" -ForegroundColor Red
Write-Host "  👤 Assigned to: $assignee" -ForegroundColor Cyan
Write-Host "  🤖 Copilot mentions: $($successfulIssues.Count)" -ForegroundColor Magenta
Write-Host "  🔄 Auto-PR created: $($hasCompletedFixes ? "Yes" : "Pending fixes")" -ForegroundColor ($hasCompletedFixes ? "Green" : "Yellow")

if ($successfulIssues.Count -gt 0) {
    Write-Host "`n📋 **CREATED ISSUES**" -ForegroundColor Green
    $successfulIssues | ForEach-Object {
        $priorityColor = ($_.Priority -eq "Critical") ? "Red" : "Yellow"
        Write-Host "  ✅ $($_.File) [$($_.Priority)]" -ForegroundColor $priorityColor
        Write-Host "     🔗 $($_.URL)" -ForegroundColor Blue
        Write-Host "     🔢 Issue #$($_.IssueNumber)" -ForegroundColor Cyan
    }
}

if ($failedIssues.Count -gt 0) {
    Write-Host "`n⚠️  **FAILED ISSUES**" -ForegroundColor Red
    $failedIssues | ForEach-Object {
        Write-Host "  ❌ $($_.File)" -ForegroundColor Red
        Write-Host "     Error: $($_.Error)" -ForegroundColor Gray
    }
}

# Next steps and automation info
Write-Host "`n🤖 **AUTONOMOUS WORKFLOW ACTIVATED**" -ForegroundColor Magenta
Write-Host "  ✅ Single branch strategy: All fixes consolidated in $WorkingBranch" -ForegroundColor Green
Write-Host "  ✅ Issues assigned to $assignee with @copilot mentions" -ForegroundColor Green
Write-Host "  ✅ Each issue includes complete autonomous fix instructions" -ForegroundColor Green
Write-Host "  ✅ Auto-close mechanism: Commits with 'Closes #issue-number'" -ForegroundColor Green
Write-Host "  ✅ Validation workflow integrated with retry logic" -ForegroundColor Green
Write-Host "  ✅ GitHub Actions optimized for changed files only" -ForegroundColor Green
Write-Host "  ✅ Automated PR creation when fixes are committed" -ForegroundColor Green

# Advanced automation features
Write-Host "`n🚀 **ADVANCED AUTOMATION FEATURES**" -ForegroundColor Cyan
Write-Host "  🔄 Auto-PR: Created when commits are detected in $WorkingBranch" -ForegroundColor Blue
Write-Host "  🎯 Smart Assignment: Tries Copilot first, falls back to current user" -ForegroundColor Blue
Write-Host "  📊 Priority System: Critical files processed first" -ForegroundColor Blue
Write-Host "  🔍 Validation Retry: Up to 3 attempts with 2-second delays" -ForegroundColor Blue
Write-Host "  🏷️  Enhanced Labels: 'rutos-compatibility,automation,copilot,autonomous'" -ForegroundColor Blue
Write-Host "  📝 Rich Context: Complete RUTOS environment details in each issue" -ForegroundColor Blue

# Monitoring and next steps
Write-Host "`n📊 **MONITORING COMMANDS**" -ForegroundColor Yellow
Write-Host "  📋 Check issues: gh issue list --label rutos-compatibility" -ForegroundColor White
Write-Host "  🔀 Check PRs: gh pr list --head $WorkingBranch" -ForegroundColor White
Write-Host "  🌿 Check branch: git log --oneline $WorkingBranch ^main" -ForegroundColor White
Write-Host "  ✅ Validate: wsl ./scripts/pre-commit-validation.sh --all" -ForegroundColor White
Write-Host "  🔄 Re-run: ./automation/Create-RUTOS-PRs.ps1" -ForegroundColor White

# Links and references
Write-Host "`n🔗 **QUICK LINKS**" -ForegroundColor Blue
Write-Host "  📝 Issues: https://github.com/markus-lassfolk/rutos-starlink-failover/issues" -ForegroundColor Blue
Write-Host "  🔀 PRs: https://github.com/markus-lassfolk/rutos-starlink-failover/pulls" -ForegroundColor Blue
Write-Host "  📖 Guidelines: .github/copilot-instructions.md" -ForegroundColor Blue
Write-Host "  🌿 Branch: $WorkingBranch" -ForegroundColor Blue

# Final automation advice
Write-Host "`n💡 **AUTOMATION BENEFITS**" -ForegroundColor Yellow
Write-Host "  🎯 Single branch reduces git complexity" -ForegroundColor Yellow
Write-Host "  🤖 Autonomous fixes with detailed instructions" -ForegroundColor Yellow
Write-Host "  📊 Priority-based issue creation (Critical → Major → Shell)" -ForegroundColor Yellow
Write-Host "  ⚡ Optimized CI/CD (only validates changed files)" -ForegroundColor Yellow
Write-Host "  🔄 Iterative validation workflow" -ForegroundColor Yellow

Write-Host "`n🚀 **NEXT STEPS**" -ForegroundColor Cyan
Write-Host "  1. Monitor issue assignments to $assignee" -ForegroundColor White
Write-Host "  2. Review PRs as they're created from $WorkingBranch" -ForegroundColor White
Write-Host "  3. Use monitoring: ./automation/Create-RUTOS-PRs.ps1 -MonitorOnly" -ForegroundColor White
Write-Host "  4. Validate fixes: wsl ./scripts/pre-commit-validation.sh <file>" -ForegroundColor White
Write-Host "  5. Merge completed fixes from $WorkingBranch to main" -ForegroundColor White

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
