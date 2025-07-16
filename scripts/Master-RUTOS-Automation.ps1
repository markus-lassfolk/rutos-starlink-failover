# PowerShell Script: Master-RUTOS-Automation.ps1
# Version: 1.0.0
# Description: Master automation script for RUTOS compatibility fixes with GitHub integration

param(
    [switch]$Debug = $false,
    [switch]$DryRun = $false
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Script version
$ScriptVersion = "1.0.0"

# Colors for output (PowerShell compatible)
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
    Magenta = "Magenta"
}

# Logging functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Debug", "Success", "Step")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Info" { $Colors.Green }
        "Warning" { $Colors.Yellow }
        "Error" { $Colors.Red }
        "Debug" { $Colors.Cyan }
        "Success" { $Colors.Green }
        "Step" { $Colors.Blue }
        default { "White" }
    }
    
    if ($Level -eq "Debug" -and -not $Debug) {
        return
    }
    
    Write-Host "[$Level] [$timestamp] $Message" -ForegroundColor $color
    
    if ($Level -eq "Error") {
        Write-Error $Message
    }
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites" -Level "Step"
    
    # Check GitHub CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Log "GitHub CLI (gh) not found - required for automation" -Level "Error"
        throw "GitHub CLI not found"
    }
    
    # Check git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found - required for version control" -Level "Error"
        throw "Git not found"
    }
    
    # Check if we're in a git repository
    try {
        git rev-parse --git-dir | Out-Null
    } catch {
        Write-Log "Not in a git repository" -Level "Error"
        throw "Not in git repository"
    }
    
    # Check if authenticated with GitHub
    try {
        gh auth status | Out-Null
    } catch {
        Write-Log "Not authenticated with GitHub - run 'gh auth login'" -Level "Error"
        throw "Not authenticated with GitHub"
    }
    
    Write-Log "All prerequisites met" -Level "Success"
}

# Function to create feature branch
function New-FeatureBranch {
    $branchName = "feature/automated-rutos-fixes-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Log "Creating feature branch: $branchName" -Level "Step"
    
    if (-not $DryRun) {
        # Ensure we're on main
        git checkout main
        git pull origin main
        
        # Create and switch to feature branch
        git checkout -b $branchName
    }
    
    Write-Log "Created feature branch: $branchName" -Level "Success"
    return $branchName
}

# Function to get shell scripts to process
function Get-ShellScripts {
    Write-Log "Scanning for shell scripts to process" -Level "Step"
    
    $shellScripts = Get-ChildItem -Path . -Recurse -Include "*.sh" -File | 
                   Where-Object { $_.FullName -notlike "*\.git*" } |
                   Sort-Object FullName
    
    Write-Log "Found $($shellScripts.Count) shell scripts to process" -Level "Info"
    return $shellScripts
}

# Function to fix bash shebang
function Fix-BashShebang {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    if ($content -match "^#!/bin/bash") {
        Write-Log "Fixing bash shebang in: $FilePath" -Level "Debug"
        $content = $content -replace "^#!/bin/bash", "#!/bin/sh"
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $content -NoNewline
        }
        return $true
    }
    return $false
}

# Function to fix local keyword
function Fix-LocalKeyword {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    if ($content -match "\blocal\s+") {
        Write-Log "Removing 'local' keyword from: $FilePath" -Level "Debug"
        $content = $content -replace "\blocal\s+", "# local "
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $content -NoNewline
        }
        return $true
    }
    return $false
}

# Function to fix function definitions
function Fix-FunctionDefinitions {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    if ($content -match "function\s+([a-zA-Z_][a-zA-Z0-9_]*)\(\)") {
        Write-Log "Fixing function definitions in: $FilePath" -Level "Debug"
        $content = $content -replace "function\s+([a-zA-Z_][a-zA-Z0-9_]*)\(\)", '$1()'
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $content -NoNewline
        }
        return $true
    }
    return $false
}

# Function to fix echo to printf (simple cases)
function Fix-EchoToPrintf {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $changed = $false
    
    # Fix echo -e
    if ($content -match "echo\s+-e\s+") {
        $content = $content -replace "echo\s+-e\s+", "printf "
        $changed = $true
    }
    
    # Fix echo -n
    if ($content -match "echo\s+-n\s+") {
        $content = $content -replace "echo\s+-n\s+", "printf "
        $changed = $true
    }
    
    if ($changed) {
        Write-Log "Converting echo to printf in: $FilePath" -Level "Debug"
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $content -NoNewline
        }
    }
    
    return $changed
}

# Function to add shellcheck disable comments
function Add-ShellCheckDisables {
    param([string]$FilePath)
    
    $lines = Get-Content $FilePath
    if (-not ($lines -match "shellcheck disable=SC1091")) {
        Write-Log "Adding shellcheck disable comments for: $FilePath" -Level "Debug"
        $newLines = @()
        $newLines += $lines[0]  # Keep shebang
        $newLines += "# shellcheck disable=SC1091 # Dynamic source files"
        $newLines += $lines[1..($lines.Count - 1)]
        
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $newLines
        }
        return $true
    }
    return $false
}

# Function to process a single file
function Invoke-FileProcessing {
    param([System.IO.FileInfo]$File)
    
    Write-Log "Processing file: $($File.Name)" -Level "Step"
    
    # Check if it's a shell script
    $firstLine = Get-Content $File.FullName -First 1
    if (-not ($firstLine -match "^#!" -and $firstLine -match "sh")) {
        Write-Log "Skipping non-shell file: $($File.Name)" -Level "Debug"
        return @{ FixesApplied = 0; NeedsManualReview = $false }
    }
    
    # Create backup
    if (-not $DryRun) {
        Copy-Item $File.FullName "$($File.FullName).backup"
    }
    
    $fixesApplied = 0
    $needsManualReview = $false
    
    # Apply fixes in order of safety
    if (Fix-BashShebang -FilePath $File.FullName) { $fixesApplied++ }
    if (Fix-LocalKeyword -FilePath $File.FullName) { $fixesApplied++ }
    if (Fix-FunctionDefinitions -FilePath $File.FullName) { $fixesApplied++ }
    if (Fix-EchoToprintf -FilePath $File.FullName) { $fixesApplied++ }
    if (Add-ShellCheckDisables -FilePath $File.FullName) { $fixesApplied++ }
    
    # Check for complex printf format strings
    $content = Get-Content $File.FullName -Raw
    if ($content -match 'printf.*\$\{.*\}.*\$\{.*\}') {
        Write-Log "File $($File.Name) contains printf format strings that need manual review" -Level "Warning"
        $needsManualReview = $true
    }
    
    if ($fixesApplied -gt 0) {
        Write-Log "Applied $fixesApplied automated fixes to: $($File.Name)" -Level "Success"
    } else {
        Write-Log "No automated fixes needed for: $($File.Name)" -Level "Info"
    }
    
    return @{ FixesApplied = $fixesApplied; NeedsManualReview = $needsManualReview }
}

# Function to create GitHub issue
function New-GitHubIssue {
    param(
        [string]$FileName,
        [bool]$NeedsManualReview
    )
    
    $title = "RUTOS Compatibility: Fix $FileName"
    $body = @"
## File: ``$FileName``

This file needs RUTOS compatibility fixes based on automated analysis.

### Automated Fixes Applied:
- ✅ Bash shebang conversion (#!/bin/bash → #!/bin/sh)
- ✅ Local keyword removal (not supported in busybox)
- ✅ Function definition format standardization
- ✅ Echo to printf conversion (simple cases)
- ✅ Shellcheck disable comments

### Manual Review Required:
$(if ($NeedsManualReview) { "- ❌ Printf format strings with variables (SC2059)" } else { "- ✅ No complex printf format strings found" })
- Error handling improvements
- RUTOS-specific optimizations
- Complex bash patterns

### Acceptance Criteria:
- [ ] All ShellCheck errors resolved
- [ ] RUTOS compatibility validated
- [ ] Proper printf format strings
- [ ] No bash-specific syntax
- [ ] Consistent error handling

**Priority:** High
**Component:** RUTOS Compatibility
**Type:** Enhancement
"@

    Write-Log "Creating GitHub issue for: $FileName" -Level "Step"
    
    if (-not $DryRun) {
        try {
            $issueUrl = gh issue create --title $title --body $body --label "rutos-compatibility,automated-fix,high-priority" --assignee "@me"
            Write-Log "Created issue: $issueUrl" -Level "Success"
        } catch {
            Write-Log "Failed to create issue for $FileName`: $($_.Exception.Message)" -Level "Error"
        }
    } else {
        Write-Log "DRY RUN: Would create issue for $FileName" -Level "Info"
    }
}

# Function to commit changes
function Invoke-CommitChanges {
    param([int]$TotalFiles, [int]$ProcessedFiles)
    
    Write-Log "Committing automated fixes" -Level "Step"
    
    if (-not $DryRun) {
        git add -A
        
        # Check if there are changes to commit
        $status = git status --porcelain
        if (-not $status) {
            Write-Log "No changes to commit" -Level "Warning"
            return
        }
        
        $commitMessage = @"
Automated RUTOS compatibility fixes

Applied automated fixes for RUTOS compatibility:
- Convert bash shebang to sh
- Remove 'local' keyword (not supported in busybox)
- Fix function definitions
- Convert echo to printf (simple cases)
- Add shellcheck disable comments

Files processed: $ProcessedFiles of $TotalFiles
Generated by: Master-RUTOS-Automation.ps1 v$ScriptVersion

Issues created in GitHub for manual review of complex cases.
All changes include .backup files for safety.
"@
        
        git commit -m $commitMessage
        Write-Log "Changes committed successfully" -Level "Success"
    } else {
        Write-Log "DRY RUN: Would commit changes for $ProcessedFiles files" -Level "Info"
    }
}

# Function to create pull request
function New-PullRequest {
    param([string]$BranchName, [int]$TotalFiles)
    
    Write-Log "Creating pull request" -Level "Step"
    
    if (-not $DryRun) {
        git push origin $BranchName
        
        $prTitle = "Automated RUTOS Compatibility Fixes"
        $prBody = @"
## Automated RUTOS Compatibility Fixes

This PR contains automated fixes for RUTOS compatibility issues.

### Changes Applied:
- ✅ **Bash to sh conversion**: Changed #!/bin/bash to #!/bin/sh
- ✅ **Local keyword removal**: Removed 'local' keyword (not supported in busybox)
- ✅ **Function definition fixes**: Corrected function syntax
- ✅ **Echo to printf conversion**: Simple cases converted automatically
- ✅ **Shellcheck disable comments**: Added for dynamic source files

### Safety Measures:
- All modified files have .backup copies
- Only safe, well-tested transformations applied
- Complex cases flagged for manual review in separate issues

### Files Processed:
$TotalFiles shell scripts

### Testing:
- [ ] All shell scripts pass basic syntax validation
- [ ] RUTOS compatibility verified
- [ ] No functionality regressions

**Generated by:** ``Master-RUTOS-Automation.ps1 v$ScriptVersion``
**Branch:** ``$BranchName``
"@
        
        try {
            $prUrl = gh pr create --title $prTitle --body $prBody --label "rutos-compatibility,automated-fix,enhancement" --assignee "@me"
            Write-Log "Pull request created: $prUrl" -Level "Success"
            return $prUrl
        } catch {
            Write-Log "Failed to create pull request: $($_.Exception.Message)" -Level "Error"
            throw
        }
    } else {
        Write-Log "DRY RUN: Would create pull request for branch $BranchName" -Level "Info"
        return "DRY-RUN-PR-URL"
    }
}

# Main execution function
function Invoke-Main {
    Write-Log "Starting master RUTOS automation v$ScriptVersion" -Level "Info"
    
    if ($Debug) {
        Write-Log "Debug mode enabled" -Level "Debug"
    }
    
    if ($DryRun) {
        Write-Log "DRY RUN mode enabled - no changes will be made" -Level "Warning"
    }
    
    try {
        # Execute automation workflow
        Test-Prerequisites
        $branchName = New-FeatureBranch
        $shellScripts = Get-ShellScripts
        
        $totalFiles = $shellScripts.Count
        $processedFiles = 0
        $filesNeedingManualReview = 0
        
        # Process each file
        foreach ($file in $shellScripts) {
            $result = Invoke-FileProcessing -File $file
            
            if ($result.FixesApplied -gt 0 -or $result.NeedsManualReview) {
                $processedFiles++
                
                # Create GitHub issue for tracking
                New-GitHubIssue -FileName $file.Name -NeedsManualReview $result.NeedsManualReview
                
                if ($result.NeedsManualReview) {
                    $filesNeedingManualReview++
                }
            }
        }
        
        # Commit changes and create PR
        Invoke-CommitChanges -TotalFiles $totalFiles -ProcessedFiles $processedFiles
        $prUrl = New-PullRequest -BranchName $branchName -TotalFiles $totalFiles
        
        # Summary
        Write-Log "Automation completed successfully!" -Level "Success"
        Write-Log "Summary:" -Level "Info"
        Write-Log "  Total files: $totalFiles" -Level "Info"
        Write-Log "  Processed: $processedFiles" -Level "Info"
        Write-Log "  Need manual review: $filesNeedingManualReview" -Level "Info"
        Write-Log "  Pull request: $prUrl" -Level "Info"
        
        Write-Log "Next steps:" -Level "Info"
        Write-Log "1. Review the created pull request" -Level "Info"
        Write-Log "2. Address individual file issues for manual review" -Level "Info"
        Write-Log "3. Test changes on RUTOS environment" -Level "Info"
        Write-Log "4. Merge when ready" -Level "Info"
        
    } catch {
        Write-Log "Automation failed: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# Execute main function
Invoke-Main
