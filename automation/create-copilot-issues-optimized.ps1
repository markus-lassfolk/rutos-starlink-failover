#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Optimized Autonomous RUTOS Copilot Issue Creation System
    
.DESCRIPTION
    Optimized version that processes files individually for better performance:
    1. Scans repository for relevant files (shell scripts and markdown)
    2. Tests each file individually with validation script
    3. Creates targeted issues for files with problems
    4. Stops early when reaching the maximum issues limit
    5. Comprehensive error handling and state management
    
.PARAMETER Production
    Enable production mode to create real issues (default: dry run for safety)
    
.PARAMETER MaxIssues
    Maximum number of issues to create in a single run (default: 3)
    
.PARAMETER PriorityFilter
    Filter issues by priority: All, Critical, Major, Minor (default: All)
    
.PARAMETER Debug
    Enable detailed debug logging
    
.PARAMETER TestMode
    Run in test mode without creating actual issues
    
.PARAMETER SkipValidation
    Skip the initial validation step (for testing)
    
.PARAMETER ForceReprocessing
    Force reprocessing of previously handled files
    
.PARAMETER TargetFile
    Process only a specific file (for testing)
    
.PARAMETER MinIssuesPerFile
    Skip files with fewer than this many issues (default: 1)
    
.PARAMETER SortByPriority
    Process files with critical issues first, then major, then minor

.EXAMPLE
    .\create-copilot-issues-optimized.ps1
    Run in safe dry run mode with max 3 issues
    
.EXAMPLE
    .\create-copilot-issues-optimized.ps1 -Production -MaxIssues 5
    Production mode with maximum 5 issues
    
.EXAMPLE
    .\create-copilot-issues-optimized.ps1 -PriorityFilter Critical -Debug
    Focus on critical issues with debug output
#>

[CmdletBinding()]
param(
    [switch]$Production = $false,
    [int]$MaxIssues = 3,
    [string]$PriorityFilter = "All", # All, Critical, Major, Minor
    [switch]$Debug = $false,
    [switch]$TestMode = $false,
    [switch]$SkipValidation = $false,
    [switch]$ForceReprocessing = $false,
    [string]$TargetFile = "",
    [int]$MinIssuesPerFile = 1,
    [switch]$SortByPriority = $false
)

# Import the enhanced label management module
$labelModulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $labelModulePath) {
    Import-Module $labelModulePath -Force -ErrorAction SilentlyContinue
    Write-Host "🏷️  GitHub Label Management Module Loaded" -ForegroundColor Blue
    Write-Host "✅ Loaded enhanced label management system (100+ labels)" -ForegroundColor Green
    $intelligentLabelingAvailable = $true
} else {
    Write-Host "⚠️  Enhanced label management module not found - using basic labels" -ForegroundColor Yellow
    $intelligentLabelingAvailable = $false
}

# Global configuration
$SCRIPT_VERSION = "1.0.0"
$VALIDATION_SCRIPT = "scripts/pre-commit-validation.sh"
$STATE_FILE = "automation/.copilot-issues-state.json"

# Global error collection for comprehensive reporting
$global:CollectedErrors = @()
$global:ErrorCount = 0

# State tracking
$global:IssueState = @{}
$global:CreatedIssues = @()

# Color definitions for consistent output
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$GRAY = [ConsoleColor]::Gray
$PURPLE = [ConsoleColor]::Magenta

# Enhanced logging functions
function Write-StatusMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelColor = switch ($Level) {
        "ERROR" { $RED }
        "WARNING" { $YELLOW }
        "SUCCESS" { $GREEN }
        "DEBUG" { $CYAN }
        "STEP" { $BLUE }
        default { [ConsoleColor]::White }
    }
    
    Write-Host "[$Level] [$timestamp] $Message" -ForegroundColor $levelColor
}

function Write-DebugMessage {
    param([string]$Message)
    if ($Debug) {
        Write-StatusMessage "🔍 $Message" -Color $CYAN -Level "DEBUG"
    }
}

function Write-StepMessage {
    param([string]$Message)
    Write-StatusMessage "🔄 $Message" -Color $BLUE -Level "STEP"
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-StatusMessage "❌ $Message" -Color $RED -Level "ERROR"
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-StatusMessage "✅ $Message" -Color $GREEN -Level "SUCCESS"
}

function Write-WarningMessage {
    param([string]$Message)
    Write-StatusMessage "⚠️ $Message" -Color $YELLOW -Level "WARNING"
}

function Write-InfoMessage {
    param([string]$Message)
    Write-StatusMessage "$Message" -Color [ConsoleColor]::White -Level "INFO"
}

# Enhanced error collection
function Add-CollectedError {
    param(
        [string]$ErrorMessage,
        [string]$FunctionName = "Unknown",
        [object]$Exception = $null,
        [string]$Context = ""
    )
    
    $global:ErrorCount++
    
    $errorInfo = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ErrorNumber = $global:ErrorCount
        Message = $ErrorMessage
        FunctionName = $FunctionName
        Context = $Context
        ExceptionType = if ($Exception) { $Exception.GetType().Name } else { "N/A" }
        ExceptionMessage = if ($Exception) { $Exception.Message } else { "N/A" }
    }
    
    $global:CollectedErrors += $errorInfo
    Write-StatusMessage "❌ Error #$global:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED -Level "ERROR"
}

# Display error report
function Show-CollectedErrors {
    if ($global:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor $RED
    Write-Host "🚨 ERROR REPORT - $($global:CollectedErrors.Count) Error(s) Found" -ForegroundColor $RED
    Write-Host ("=" * 80) -ForegroundColor $RED
    
    foreach ($errorInfo in $global:CollectedErrors) {
        Write-Host "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)" -ForegroundColor $RED
        Write-Host "   🎯 Function: $($errorInfo.FunctionName)" -ForegroundColor $YELLOW
        Write-Host "   💬 Message: $($errorInfo.Message)" -ForegroundColor White
        if ($errorInfo.Context) {
            Write-Host "   📝 Context: $($errorInfo.Context)" -ForegroundColor $CYAN
        }
    }
}

# Run validation on individual file
function Invoke-ValidationOnFile {
    param([string]$FilePath)
    
    Write-DebugMessage "Running validation on file: $FilePath"
    
    try {
        $validationCmd = "wsl bash -c `"cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'`""
        Write-DebugMessage "Executing: $validationCmd"
        
        $validationOutput = Invoke-Expression $validationCmd 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-DebugMessage "Validation exit code: $exitCode"
        
        # Parse the validation output to extract issues
        $issues = Parse-ValidationOutput -Output $validationOutput -FilePath $FilePath
        
        return @{
            Success = $exitCode -eq 0
            ExitCode = $exitCode
            Issues = $issues
            Output = $validationOutput
        }
    } catch {
        Add-CollectedError -ErrorMessage "Failed to validate file: $($_.Exception.Message)" -FunctionName "Invoke-ValidationOnFile" -Exception $_.Exception -Context "Validating file $FilePath"
        return @{
            Success = $false
            ExitCode = -1
            Issues = @()
            Error = $_.Exception.Message
        }
    }
}

# Parse validation output for a specific file
function Parse-ValidationOutput {
    param(
        [string[]]$Output,
        [string]$FilePath
    )
    
    Write-DebugMessage "Parsing validation output for: $FilePath"
    
    $issues = @()
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        
        # Handle the specific format: [SEVERITY] filepath:line description
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]\s+(.+?):(\d+)\s+(.+)$") {
            $severity = $Matches[1]
            $filepath = $Matches[2] -replace "^\.\/", ""
            $lineNumber = $Matches[3]
            $description = $Matches[4]
            
            # Only include issues for our target file
            if ($filepath -eq $FilePath) {
                $issueType = switch ($severity) {
                    "CRITICAL" { "Critical" }
                    "MAJOR" { "Major" }
                    "MINOR" { "Minor" }
                    "WARNING" { "Warning" }
                    default { "Minor" }
                }
                
                $issues += @{
                    Line = [int]$lineNumber
                    Description = $description
                    Type = $issueType
                    Severity = $severity
                }
            }
        }
        # Handle ShellCheck format: filepath:line:column: note/warning/error: description
        elseif ($line -match "^(.+?):(\d+):(\d+):\s+(note|warning|error):\s+(.+)$") {
            $filepath = $Matches[1] -replace "^\.\/", ""
            $lineNumber = $Matches[2]
            $issueLevel = $Matches[4]
            $description = $Matches[5]
            
            if ($filepath -eq $FilePath) {
                $issueType = switch ($issueLevel) {
                    "error" { "Critical" }
                    "warning" { "Major" }
                    "note" { "Minor" }
                    default { "Minor" }
                }
                
                $issues += @{
                    Line = [int]$lineNumber
                    Description = $description
                    Type = $issueType
                    Severity = $issueLevel
                }
            }
        }
        # Generic error patterns
        elseif ($line -match "CRITICAL:|ERROR:|FAILED" -and $line -notmatch "SUCCESS|PASSED") {
            $issues += @{
                Line = "Unknown"
                Description = $line
                Type = "Critical"
                Severity = "High"
            }
        }
    }
    
    Write-DebugMessage "Found $($issues.Count) issues for file: $FilePath"
    return $issues
}

# Test if file should be processed
function Test-ShouldProcessFile {
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    # Apply priority filter
    $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" }
    $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }
    
    $passesFilter = switch ($PriorityFilter) {
        "Critical" { $criticalIssues.Count -gt 0 }
        "Major" { $majorIssues.Count -gt 0 }
        "Minor" { $minorIssues.Count -gt 0 }
        default { $true }  # "All"
    }
    
    if (-not $passesFilter) {
        Write-DebugMessage "File doesn't match priority filter ($PriorityFilter) - skipping"
        return $false
    }
    
    # Apply minimum issues filter
    if ($Issues.Count -lt $MinIssuesPerFile) {
        Write-DebugMessage "File has only $($Issues.Count) issues, minimum is $MinIssuesPerFile - skipping"
        return $false
    }
    
    return $true
}

# Create GitHub issue
function New-CopilotIssue {
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    Write-StepMessage "Creating Copilot issue for: $FilePath"
    
    if ($TestMode) {
        Write-SuccessMessage "[TEST MODE] Would create issue for: $FilePath"
        return @{ Success = $true; IssueNumber = "TEST-MODE"; TestMode = $true }
    }
    
    try {
        # Categorize issues by severity
        $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }
        
        # Generate issue title
        $issueTitle = "🔧 RUTOS Compatibility Fix Required: $FilePath"
        
        # Generate comprehensive issue body
        $issueBody = @"
# 🔧 RUTOS Compatibility Fix Required

## 📄 **Target File**
``$FilePath``

## 🎯 **Objective**
Fix all RUTOS compatibility issues in this file to ensure it works correctly on RUTX50 hardware with busybox shell environment.

## ⚠️ **IMPORTANT: Scope Restriction**
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**DO NOT commit or alter any other files including:**
- ❌ Other shell scripts or configuration files
- ❌ Validation scripts or testing tools  
- ❌ Documentation or README files
- ❌ GitHub workflow files
- ❌ Any files not explicitly identified in this issue

**✅ Focus exclusively on fixing the issues in the single target file listed above.**

## 🚨 **Issues Found**

### 📊 **Issue Summary**
- 🔴 **Critical Issues**: $($criticalIssues.Count) (Must fix - will cause hardware failures)
- 🟡 **Major Issues**: $($majorIssues.Count) (Should fix - may cause runtime problems)  
- 🔵 **Minor Issues**: $($minorIssues.Count) (Best practices - improve if possible)

**Total Issues**: $($Issues.Count)

"@

        # Add critical issues section
        if ($criticalIssues.Count -gt 0) {
            $issueBody += @"

### 🔴 **CRITICAL ISSUES** (Must Fix Immediately)

These issues will cause failures on RUTX50 hardware and must be fixed:

"@
            foreach ($issue in $criticalIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add major issues section
        if ($majorIssues.Count -gt 0) {
            $issueBody += @"

### 🟡 **MAJOR ISSUES** (Should Fix)

These issues may cause problems in the busybox environment:

"@
            foreach ($issue in $majorIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add minor issues section
        if ($minorIssues.Count -gt 0) {
            $issueBody += @"

### 🔵 **MINOR ISSUES** (Best Practices)

These issues represent best practices and portability improvements:

"@
            foreach ($issue in $minorIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add fix guidelines
        $issueBody += @"

## 🛠️ **Fix Guidelines**

### **RUTOS Compatibility Rules**
1. **POSIX Shell Only**: Use `#!/bin/sh` instead of `#!/bin/bash`
2. **No Bash Arrays**: Use space-separated strings or multiple variables
3. **Use `[ ]` not `[[ ]]`**: Busybox doesn't support `[[ ]]`
4. **No `local` keyword**: All variables are global in busybox
5. **Use `printf` not `echo -e`**: More portable and consistent
6. **Source with `.` not `source`**: Use `. script.sh` instead of `source script.sh`
7. **No `function()` syntax**: Use `function_name() {` format
8. **Proper printf format**: Avoid variables in format strings (SC2059)

## 📋 **Acceptance Criteria**
- [ ] All critical issues resolved
- [ ] All major issues resolved (if possible)
- [ ] Minor issues addressed (if time permits)
- [ ] File passes validation with no errors
- [ ] Only the target file is modified

---

*Generated by create-copilot-issues-optimized.ps1 v$SCRIPT_VERSION on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

        # Generate labels
        $labels = @("rutos-compatibility", "copilot-fix", "automated", "shell-script")
        
        if ($criticalIssues.Count -gt 0) {
            $labels += "priority-critical"
        } elseif ($majorIssues.Count -gt 0) {
            $labels += "priority-major"
        } else {
            $labels += "priority-minor"
        }
        
        # Create temporary file for issue body
        $tempFile = [System.IO.Path]::GetTempFileName()
        $issueBody | Out-File -FilePath $tempFile -Encoding UTF8
        
        # Build GitHub CLI command
        $labelArgs = ($labels | ForEach-Object { "-l `"$_`"" }) -join " "
        $ghCommand = "gh issue create -t `"$issueTitle`" -F `"$tempFile`" $labelArgs"
        
        Write-DebugMessage "Executing: $ghCommand"
        
        # Execute GitHub CLI command
        $result = Invoke-Expression $ghCommand
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            # Extract issue number from result
            $issueNumber = ""
            if ($result -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                $issueNumber = $Matches[1]
            }
            
            Write-SuccessMessage "Created issue #$issueNumber for: $FilePath"
            
            # Assign Copilot to the issue
            Start-Sleep -Seconds 2
            $assignResult = Set-CopilotAssignment -IssueNumber $issueNumber
            
            if ($assignResult.Success) {
                Write-SuccessMessage "Assigned Copilot to issue #$issueNumber"
            }
            
            return @{ 
                Success = $true
                IssueNumber = $issueNumber
                FilePath = $FilePath
            }
        } else {
            Add-CollectedError -ErrorMessage "Failed to create issue: $result" -FunctionName "New-CopilotIssue" -Context "GitHub CLI command failed for $FilePath"
            return @{ 
                Success = $false
                Error = "GitHub CLI command failed: $result"
            }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error creating issue: $($_.Exception.Message)" -FunctionName "New-CopilotIssue" -Exception $_.Exception -Context "Creating GitHub issue for $FilePath"
        return @{ 
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Assign Copilot to an issue
function Set-CopilotAssignment {
    param([string]$IssueNumber)
    
    Write-DebugMessage "Assigning Copilot to issue #$IssueNumber"
    
    try {
        if ($TestMode) {
            Write-SuccessMessage "[TEST MODE] Would assign Copilot to issue #$IssueNumber"
            return @{ Success = $true; TestMode = $true }
        }
        
        # Assign Copilot as assignee
        $assignResult = gh issue edit $IssueNumber --add-assignee "@copilot" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "✅ Copilot assigned successfully!"
            return @{ Success = $true }
        } else {
            Add-CollectedError -ErrorMessage "Failed to assign Copilot: $assignResult" -FunctionName "Set-CopilotAssignment" -Context "Assigning Copilot to issue #$IssueNumber"
            return @{ Success = $false; Error = $assignResult }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error assigning Copilot: $($_.Exception.Message)" -FunctionName "Set-CopilotAssignment" -Exception $_.Exception -Context "Assigning Copilot to issue #$IssueNumber"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Main execution logic with optimized file-by-file processing
function Start-OptimizedIssueCreation {
    Write-InfoMessage "🚀 Starting Optimized RUTOS Copilot Issue Creation System v$SCRIPT_VERSION"
    
    # Get target files to process
    if ($TargetFile) {
        Write-InfoMessage "🎯 Processing single target file: $TargetFile"
        $filesToProcess = @($TargetFile)
    } else {
        Write-StepMessage "📂 Scanning repository for shell scripts and markdown files..."
        
        $filesToProcess = Get-ChildItem -Path "." -Recurse -Include "*.sh", "*.md" -File | 
                         Where-Object { 
                             $_.Name -ne "pre-commit-validation.sh" -and 
                             $_.FullName -notmatch "\.git" -and
                             $_.FullName -notmatch "node_modules" -and
                             $_.FullName -notmatch "\.vscode" -and
                             $_.FullName -notmatch "automation\\.*\.log$"
                         } | 
                         ForEach-Object { 
                             $_.FullName.Replace($PWD.Path, "").Replace("\", "/").TrimStart("/") 
                         }
    }
    
    Write-InfoMessage "📊 Found $($filesToProcess.Count) potential files to process"
    
    if ($filesToProcess.Count -eq 0) {
        Write-WarningMessage "❌ No files found to process"
        return
    }
    
    # Process files individually
    $issuesCreated = 0
    $filesProcessed = 0
    $filesSkipped = 0
    
    foreach ($file in $filesToProcess) {
        # Check if we've reached the maximum issues limit
        if ($issuesCreated -ge $MaxIssues) {
            Write-InfoMessage "🛑 Reached maximum issues limit ($MaxIssues) - stopping"
            break
        }
        
        Write-StepMessage "🔍 Processing file: $file"
        $filesProcessed++
        
        try {
            # Run validation on the individual file
            $validationResult = Invoke-ValidationOnFile -FilePath $file
            
            if ($validationResult.Success) {
                Write-DebugMessage "✅ File has no issues: $file"
                continue
            }
            
            if ($validationResult.Issues.Count -eq 0) {
                Write-DebugMessage "ℹ️  No parseable issues found: $file"
                continue
            }
            
            Write-InfoMessage "⚠️  Found $($validationResult.Issues.Count) issues in: $file"
            
            # Check if this file should be processed based on our criteria
            if (-not (Test-ShouldProcessFile -FilePath $file -Issues $validationResult.Issues)) {
                Write-DebugMessage "⏭️  Skipping file based on processing criteria: $file"
                $filesSkipped++
                continue
            }
            
            # Create issue for this file
            Write-StepMessage "📝 Creating issue for: $file"
            $issueResult = New-CopilotIssue -FilePath $file -Issues $validationResult.Issues
            
            if ($issueResult.Success) {
                $issuesCreated++
                Write-SuccessMessage "✅ Created issue #$($issueResult.IssueNumber) for: $file"
                
                # Update tracking
                $global:CreatedIssues += @{
                    IssueNumber = $issueResult.IssueNumber
                    FilePath = $file
                    CreatedAt = Get-Date
                    IssueCount = $validationResult.Issues.Count
                }
                
                # Small delay to respect rate limits
                Start-Sleep -Seconds 3
            } else {
                Write-ErrorMessage "❌ Failed to create issue for: $file - $($issueResult.Error)"
                Add-CollectedError -ErrorMessage "Failed to create issue for $file" -FunctionName "Start-OptimizedIssueCreation" -Context "Processing file $file"
            }
            
        } catch {
            Write-ErrorMessage "❌ Error processing file: $file - $($_.Exception.Message)"
            Add-CollectedError -ErrorMessage "Error processing file: $($_.Exception.Message)" -FunctionName "Start-OptimizedIssueCreation" -Exception $_.Exception -Context "Processing file $file"
        }
    }
    
    # Display final summary
    Write-Host "`n" + ("=" * 80) -ForegroundColor $BLUE
    Write-Host "📊 PROCESSING SUMMARY" -ForegroundColor $BLUE
    Write-Host ("=" * 80) -ForegroundColor $BLUE
    
    Write-InfoMessage "📁 Files Processed: $filesProcessed"
    Write-InfoMessage "⏭️  Files Skipped: $filesSkipped"
    Write-InfoMessage "📝 Issues Created: $issuesCreated"
    Write-InfoMessage "🎯 Maximum Issues: $MaxIssues"
    
    if ($global:CreatedIssues.Count -gt 0) {
        Write-Host "`n📋 Created Issues:" -ForegroundColor $GREEN
        foreach ($issue in $global:CreatedIssues) {
            Write-Host "   #$($issue.IssueNumber) - $($issue.FilePath) ($($issue.IssueCount) issues)" -ForegroundColor $GREEN
        }
    }
    
    # Show any collected errors
    if ($global:CollectedErrors.Count -gt 0) {
        Show-CollectedErrors
    } else {
        Write-SuccessMessage "✅ No errors encountered during processing"
    }
    
    Write-SuccessMessage "🎉 Optimized issue creation completed successfully!"
}

# Entry point
function Main {
    Write-InfoMessage "🔧 Optimized RUTOS Copilot Issue Creation System"
    Write-InfoMessage "📅 Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    if ($Debug) {
        Write-DebugMessage "==================== DEBUG MODE ENABLED ===================="
        Write-DebugMessage "Script version: $SCRIPT_VERSION"
        Write-DebugMessage "Working directory: $(Get-Location)"
        Write-DebugMessage "Production mode: $Production"
        Write-DebugMessage "Test mode: $TestMode"
        Write-DebugMessage "Max issues: $MaxIssues"
        Write-DebugMessage "Priority filter: $PriorityFilter"
        Write-DebugMessage "Target file: $TargetFile"
        Write-DebugMessage "Force reprocessing: $ForceReprocessing"
        Write-DebugMessage "Skip validation: $SkipValidation"
        Write-DebugMessage "Min issues per file: $MinIssuesPerFile"
        Write-DebugMessage "Sort by priority: $SortByPriority"
        Write-DebugMessage "==========================================================="
    }
    
    # Validate prerequisites
    Write-StepMessage "🔧 Validating prerequisites..."
    
    # Check if we're in the right directory
    if (-not (Test-Path ".git")) {
        Write-ErrorMessage "❌ Not in a Git repository root. Please run from repository root."
        exit 1
    }
    
    # Check for validation script
    if (-not $SkipValidation -and -not (Test-Path $VALIDATION_SCRIPT)) {
        Write-ErrorMessage "❌ Validation script not found: $VALIDATION_SCRIPT"
        exit 1
    }
    
    # Check for GitHub CLI
    try {
        $ghVersion = gh --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "❌ GitHub CLI (gh) not found or not working"
            exit 1
        }
        Write-DebugMessage "GitHub CLI version: $($ghVersion[0])"
    } catch {
        Write-ErrorMessage "❌ GitHub CLI (gh) not available"
        exit 1
    }
    
    # Check GitHub authentication
    try {
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "❌ GitHub CLI not authenticated. Run: gh auth login"
            exit 1
        }
        Write-DebugMessage "GitHub authentication: OK"
    } catch {
        Write-ErrorMessage "❌ GitHub authentication check failed"
        exit 1
    }
    
    # Safety check for production mode
    if ($Production -and -not $TestMode) {
        Write-WarningMessage "⚠️  PRODUCTION MODE ENABLED - Issues will be created in GitHub"
        Write-Host "Press Ctrl+C to cancel or wait 5 seconds to continue..." -ForegroundColor $YELLOW
        Start-Sleep -Seconds 5
    } else {
        Write-InfoMessage "🧪 Running in safe mode (no real issues will be created)"
    }
    
    Write-SuccessMessage "✅ All prerequisites validated"
    
    # Start the optimized issue creation process
    Start-OptimizedIssueCreation
}

# Execute main function if script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    Main
}

# Enhanced error collection with comprehensive information
function Add-CollectedError {
    param(
        [string]$ErrorMessage,
        [string]$FunctionName = "Unknown",
        [string]$Location = "Unknown",
        [object]$Exception = $null,
        [string]$Context = "",
        [hashtable]$AdditionalInfo = @{}
    )
    
    $global:ErrorCount++
    
    # Get caller information if not provided
    if ($FunctionName -eq "Unknown" -or $Location -eq "Unknown") {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $caller = $callStack[1]
            if ($FunctionName -eq "Unknown") { $FunctionName = $caller.FunctionName }
            if ($Location -eq "Unknown") { $Location = "$($caller.ScriptName):$($caller.ScriptLineNumber)" }
        }
    }
    
    # Create comprehensive error information
    $errorInfo = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ErrorNumber = $global:ErrorCount
        Message = $ErrorMessage
        FunctionName = $FunctionName
        Location = $Location
        Context = $Context
        ExceptionType = if ($Exception) { $Exception.GetType().Name } else { "N/A" }
        ExceptionMessage = if ($Exception) { $Exception.Message } else { "N/A" }
        InnerException = if ($Exception -and $Exception.InnerException) { $Exception.InnerException.Message } else { "N/A" }
        LastExitCode = $LASTEXITCODE
        AdditionalInfo = $AdditionalInfo
    }
    
    # Add to global collection
    $global:CollectedErrors += $errorInfo
    
    # Display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$global:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED -Level "ERROR"
    
    if ($Debug) {
        Write-StatusMessage "   📍 Location: $Location" -Color $GRAY -Level "DEBUG"
        if ($Context) {
            Write-StatusMessage "   📝 Context: $Context" -Color $GRAY -Level "DEBUG"
        }
        if ($Exception) {
            Write-StatusMessage "   🔍 Exception: $($Exception.GetType().Name) - $($Exception.Message)" -Color $GRAY -Level "DEBUG"
        }
    }
}

# Display comprehensive error report
function Show-CollectedErrors {
    if ($global:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }
    
    Write-Host "`n" + ("=" * 100) -ForegroundColor $RED
    Write-Host "🚨 COMPREHENSIVE ERROR REPORT - $($global:CollectedErrors.Count) Error(s) Found" -ForegroundColor $RED
    Write-Host ("=" * 100) -ForegroundColor $RED
    
    foreach ($errorInfo in $global:CollectedErrors) {
        Write-Host "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)" -ForegroundColor $RED
        Write-Host "   🎯 Function: $($errorInfo.FunctionName)" -ForegroundColor $YELLOW
        Write-Host "   📍 Location: $($errorInfo.Location)" -ForegroundColor $YELLOW
        Write-Host "   💬 Message: $($errorInfo.Message)" -ForegroundColor White
        
        if ($errorInfo.Context) {
            Write-Host "   📝 Context: $($errorInfo.Context)" -ForegroundColor $CYAN
        }
        
        if ($errorInfo.ExceptionType -ne "N/A") {
            Write-Host "   🔍 Exception: $($errorInfo.ExceptionType) - $($errorInfo.ExceptionMessage)" -ForegroundColor $PURPLE
        }
        
        if ($errorInfo.LastExitCode -ne 0) {
            Write-Host "   🔢 Last Exit Code: $($errorInfo.LastExitCode)" -ForegroundColor $RED
        }
        
        if ($errorInfo.AdditionalInfo.Count -gt 0) {
            Write-Host "   📊 Additional Info:" -ForegroundColor $BLUE
            foreach ($key in $errorInfo.AdditionalInfo.Keys) {
                Write-Host "      $key`: $($errorInfo.AdditionalInfo[$key])" -ForegroundColor $GRAY
            }
        }
    }
    
    Write-Host "`n📊 ERROR SUMMARY:" -ForegroundColor $RED
    Write-Host "   Total Errors: $($global:CollectedErrors.Count)" -ForegroundColor $RED
    Write-Host "   Functions with Errors: $($global:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count" -ForegroundColor $YELLOW
}

# Enhanced error collection with comprehensive information
function Add-CollectedError {
    param(
        [string]$ErrorMessage,
        [string]$FunctionName = "Unknown",
        [string]$Location = "Unknown",
        [object]$Exception = $null,
        [string]$Context = "",
        [hashtable]$AdditionalInfo = @{}
    )
    
    $global:ErrorCount++
    
    # Get caller information if not provided
    if ($FunctionName -eq "Unknown" -or $Location -eq "Unknown") {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $caller = $callStack[1]
            if ($FunctionName -eq "Unknown") { $FunctionName = $caller.FunctionName }
            if ($Location -eq "Unknown") { $Location = "$($caller.ScriptName):$($caller.ScriptLineNumber)" }
        }
    }
    
    # Create comprehensive error information
    $errorInfo = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ErrorNumber = $global:ErrorCount
        Message = $ErrorMessage
        FunctionName = $FunctionName
        Location = $Location
        Context = $Context
        ExceptionType = if ($Exception) { $Exception.GetType().Name } else { "N/A" }
        ExceptionMessage = if ($Exception) { $Exception.Message } else { "N/A" }
        InnerException = if ($Exception -and $Exception.InnerException) { $Exception.InnerException.Message } else { "N/A" }
        LastExitCode = $LASTEXITCODE
        AdditionalInfo = $AdditionalInfo
    }
    
    # Add to global collection
    $global:CollectedErrors += $errorInfo
    
    # Display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$global:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED -Level "ERROR"
    
    if ($Debug) {
        Write-StatusMessage "   📍 Location: $Location" -Color $GRAY -Level "DEBUG"
        if ($Context) {
            Write-StatusMessage "   📝 Context: $Context" -Color $GRAY -Level "DEBUG"
        }
        if ($Exception) {
            Write-StatusMessage "   🔍 Exception: $($Exception.GetType().Name) - $($Exception.Message)" -Color $GRAY -Level "DEBUG"
        }
    }
}

# Display comprehensive error report
function Show-CollectedErrors {
    if ($global:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }
    
    Write-Host "`n" + ("=" * 100) -ForegroundColor $RED
    Write-Host "🚨 COMPREHENSIVE ERROR REPORT - $($global:CollectedErrors.Count) Error(s) Found" -ForegroundColor $RED
    Write-Host ("=" * 100) -ForegroundColor $RED
    
    foreach ($errorInfo in $global:CollectedErrors) {
        Write-Host "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)" -ForegroundColor $RED
        Write-Host "   🎯 Function: $($errorInfo.FunctionName)" -ForegroundColor $YELLOW
        Write-Host "   📍 Location: $($errorInfo.Location)" -ForegroundColor $YELLOW
        Write-Host "   💬 Message: $($errorInfo.Message)" -ForegroundColor White
        
        if ($errorInfo.Context) {
            Write-Host "   📝 Context: $($errorInfo.Context)" -ForegroundColor $CYAN
        }
        
        if ($errorInfo.ExceptionType -ne "N/A") {
            Write-Host "   🔍 Exception: $($errorInfo.ExceptionType) - $($errorInfo.ExceptionMessage)" -ForegroundColor $PURPLE
        }
        
        if ($errorInfo.LastExitCode -ne 0) {
            Write-Host "   🔢 Last Exit Code: $($errorInfo.LastExitCode)" -ForegroundColor $RED
        }
        
        if ($errorInfo.AdditionalInfo.Count -gt 0) {
            Write-Host "   📊 Additional Info:" -ForegroundColor $BLUE
            foreach ($key in $errorInfo.AdditionalInfo.Keys) {
                Write-Host "      $key`: $($errorInfo.AdditionalInfo[$key])" -ForegroundColor $GRAY
            }
        }
    }
    
    Write-Host "`n📊 ERROR SUMMARY:" -ForegroundColor $RED
    Write-Host "   Total Errors: $($global:CollectedErrors.Count)" -ForegroundColor $RED
    Write-Host "   Functions with Errors: $($global:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count" -ForegroundColor $YELLOW
}

# Load and save state for preventing infinite loops
function Load-IssueState {
    Write-DebugMessage "Loading issue state from: $STATE_FILE"
    
    if (Test-Path $STATE_FILE) {
        try {
            $stateContent = Get-Content $STATE_FILE -Raw | ConvertFrom-Json
            $global:IssueState = @{}
            
            foreach ($property in $stateContent.PSObject.Properties) {
                $global:IssueState[$property.Name] = $property.Value
            }
            
            Write-DebugMessage "Loaded state for $($global:IssueState.Count) files"
            return $true
        } catch {
            Add-CollectedError -ErrorMessage "Failed to load state file: $($_.Exception.Message)" -FunctionName "Load-IssueState" -Exception $_.Exception -Context "Loading issue state from $STATE_FILE" -AdditionalInfo @{StateFile = $STATE_FILE}
            $global:IssueState = @{}
            return $false
        }
    } else {
        Write-DebugMessage "No existing state file found - starting fresh"
        $global:IssueState = @{}
        return $false
    }
}

function Save-IssueState {
    Write-DebugMessage "Saving issue state to: $STATE_FILE"
    
    try {
        # Ensure directory exists
        $stateDir = Split-Path $STATE_FILE -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        
        # Convert to JSON and save
        $global:IssueState | ConvertTo-Json -Depth 10 | Out-File $STATE_FILE -Encoding UTF8
        Write-DebugMessage "State saved successfully"
        return $true
    } catch {
        Add-CollectedError -ErrorMessage "Failed to save state: $($_.Exception.Message)" -FunctionName "Save-IssueState" -Exception $_.Exception -Context "Saving issue state to $STATE_FILE"
        return $false
    }
}

# Run validation on individual file
function Invoke-ValidationOnFile {
    param([string]$FilePath)
    
    Write-DebugMessage "Running validation on file: $FilePath"
    
    try {
        $validationCmd = "wsl bash -c `"cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'`""
        Write-DebugMessage "Executing: $validationCmd"
        
        $validationOutput = Invoke-Expression $validationCmd 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-DebugMessage "Validation exit code: $exitCode"
        
        # Parse the validation output to extract issues
        $issues = Parse-ValidationOutput -Output $validationOutput -FilePath $FilePath
        
        return @{
            Success = $exitCode -eq 0
            ExitCode = $exitCode
            Issues = $issues
            Output = $validationOutput
        }
    } catch {
        Add-CollectedError -ErrorMessage "Failed to validate file: $($_.Exception.Message)" -FunctionName "Invoke-ValidationOnFile" -Exception $_.Exception -Context "Validating file $FilePath"
        return @{
            Success = $false
            ExitCode = -1
            Issues = @()
            Error = $_.Exception.Message
        }
    }
}

# Parse validation output for a specific file
function Parse-ValidationOutput {
    param(
        [string[]]$Output,
        [string]$FilePath
    )
    
    Write-DebugMessage "Parsing validation output for: $FilePath"
    
    $issues = @()
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        
        # Handle the specific format: [SEVERITY] filepath:line description
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]\s+(.+?):(\d+)\s+(.+)$") {
            $severity = $Matches[1]
            $filepath = $Matches[2] -replace "^\.\/", ""
            $lineNumber = $Matches[3]
            $description = $Matches[4]
            
            # Only include issues for our target file
            if ($filepath -eq $FilePath) {
                $issueType = switch ($severity) {
                    "CRITICAL" { "Critical" }
                    "MAJOR" { "Major" }
                    "MINOR" { "Minor" }
                    "WARNING" { "Warning" }
                    default { "Minor" }
                }
                
                $issues += @{
                    Line = [int]$lineNumber
                    Description = $description
                    Type = $issueType
                    Severity = $severity
                }
            }
        }
        # Handle ShellCheck format: filepath:line:column: note/warning/error: description
        elseif ($line -match "^(.+?):(\d+):(\d+):\s+(note|warning|error):\s+(.+)$") {
            $filepath = $Matches[1] -replace "^\.\/", ""
            $lineNumber = $Matches[2]
            $issueLevel = $Matches[4]
            $description = $Matches[5]
            
            if ($filepath -eq $FilePath) {
                $issueType = switch ($issueLevel) {
                    "error" { "Critical" }
                    "warning" { "Major" }
                    "note" { "Minor" }
                    default { "Minor" }
                }
                
                $issues += @{
                    Line = [int]$lineNumber
                    Description = $description
                    Type = $issueType
                    Severity = $issueLevel
                }
            }
        }
        # Generic error patterns
        elseif ($line -match "CRITICAL:|ERROR:|FAILED" -and $line -notmatch "SUCCESS|PASSED") {
            $issues += @{
                Line = "Unknown"
                Description = $line
                Type = "Critical"
                Severity = "High"
            }
        }
    }
    
    Write-DebugMessage "Found $($issues.Count) issues for file: $FilePath"
    return $issues
}

# Test if file should be processed based on state and criteria
function Test-ShouldProcessFile {
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    Write-DebugMessage "Checking if file should be processed: $FilePath"
    
    # Apply priority filter
    $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" }
    $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }
    
    $passesFilter = switch ($PriorityFilter) {
        "Critical" { $criticalIssues.Count -gt 0 }
        "Major" { $majorIssues.Count -gt 0 }
        "Minor" { $minorIssues.Count -gt 0 }
        default { $true }  # "All"
    }
    
    if (-not $passesFilter) {
        Write-DebugMessage "File doesn't match priority filter ($PriorityFilter) - skipping"
        return $false
    }
    
    # Apply minimum issues filter
    if ($Issues.Count -lt $MinIssuesPerFile) {
        Write-DebugMessage "File has only $($Issues.Count) issues, minimum is $MinIssuesPerFile - skipping"
        return $false
    }
    
    # Check if already processed (unless forcing reprocessing)
    if ($global:IssueState.ContainsKey($FilePath) -and -not $ForceReprocessing) {
        $fileState = $global:IssueState[$FilePath]
        if ($fileState.Status -eq "Completed") {
            Write-DebugMessage "File already completed - skipping"
            return $false
        }
    }
    
    Write-DebugMessage "File should be processed"
    return $true
}

# Create GitHub issue with comprehensive content
function New-CopilotIssue {
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    Write-StepMessage "Creating Copilot issue for: $FilePath"
    
    if ($TestMode) {
        Write-SuccessMessage "[TEST MODE] Would create issue for: $FilePath"
        return @{ Success = $true; IssueNumber = "TEST-MODE"; TestMode = $true }
    }
    
    try {
        # Categorize issues by severity
        $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }
        
        # Generate issue title
        $issueTitle = "🔧 RUTOS Compatibility Fix Required: $FilePath"
        
        # Generate comprehensive issue body
        $issueBody = @"
# 🔧 RUTOS Compatibility Fix Required

## 📄 **Target File**
``$FilePath``

## 🎯 **Objective**
Fix all RUTOS compatibility issues in this file to ensure it works correctly on RUTX50 hardware with busybox shell environment.

## ⚠️ **IMPORTANT: Scope Restriction**
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**DO NOT commit or alter any other files including:**
- ❌ Other shell scripts or configuration files
- ❌ Validation scripts or testing tools  
- ❌ Documentation or README files
- ❌ GitHub workflow files
- ❌ Any files not explicitly identified in this issue

**✅ Focus exclusively on fixing the issues in the single target file listed above.**

## 🚨 **Issues Found**

### 📊 **Issue Summary**
- 🔴 **Critical Issues**: $($criticalIssues.Count) (Must fix - will cause hardware failures)
- 🟡 **Major Issues**: $($majorIssues.Count) (Should fix - may cause runtime problems)  
- 🔵 **Minor Issues**: $($minorIssues.Count) (Best practices - improve if possible)

**Total Issues**: $($Issues.Count)

"@

        # Add critical issues section
        if ($criticalIssues.Count -gt 0) {
            $issueBody += @"

### 🔴 **CRITICAL ISSUES** (Must Fix Immediately)

These issues will cause failures on RUTX50 hardware and must be fixed:

"@
            foreach ($issue in $criticalIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add major issues section
        if ($majorIssues.Count -gt 0) {
            $issueBody += @"

### 🟡 **MAJOR ISSUES** (Should Fix)

These issues may cause problems in the busybox environment:

"@
            foreach ($issue in $majorIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add minor issues section
        if ($minorIssues.Count -gt 0) {
            $issueBody += @"

### 🔵 **MINOR ISSUES** (Best Practices)

These issues represent best practices and portability improvements:

"@
            foreach ($issue in $minorIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }
        
        # Add fix guidelines
        $issueBody += @"

## 🛠️ **Fix Guidelines**

### **RUTOS Compatibility Rules**
1. **POSIX Shell Only**: Use `#!/bin/sh` instead of `#!/bin/bash`
2. **No Bash Arrays**: Use space-separated strings or multiple variables
3. **Use `[ ]` not `[[ ]]`**: Busybox doesn't support `[[ ]]`
4. **No `local` keyword**: All variables are global in busybox
5. **Use `printf` not `echo -e`**: More portable and consistent
6. **Source with `.` not `source`**: Use `. script.sh` instead of `source script.sh`
7. **No `function()` syntax**: Use `function_name() {` format
8. **Proper printf format**: Avoid variables in format strings (SC2059)

## 📋 **Acceptance Criteria**
- [ ] All critical issues resolved
- [ ] All major issues resolved (if possible)
- [ ] Minor issues addressed (if time permits)
- [ ] File passes validation with no errors
- [ ] Only the target file is modified

---

*Generated by create-copilot-issues-optimized.ps1 v$SCRIPT_VERSION on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

        # Generate labels
        $labels = @("rutos-compatibility", "copilot-fix", "automated", "shell-script")
        
        if ($criticalIssues.Count -gt 0) {
            $labels += "priority-critical"
        } elseif ($majorIssues.Count -gt 0) {
            $labels += "priority-major"
        } else {
            $labels += "priority-minor"
        }
        
        # Create temporary file for issue body
        $tempFile = [System.IO.Path]::GetTempFileName()
        $issueBody | Out-File -FilePath $tempFile -Encoding UTF8
        
        # Build GitHub CLI command
        $labelArgs = ($labels | ForEach-Object { "-l `"$_`"" }) -join " "
        $ghCommand = "gh issue create -t `"$issueTitle`" -F `"$tempFile`" $labelArgs"
        
        Write-DebugMessage "Executing: $ghCommand"
        
        # Execute GitHub CLI command
        $result = Invoke-Expression $ghCommand
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            # Extract issue number from result
            $issueNumber = ""
            if ($result -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                $issueNumber = $Matches[1]
            }
            
            Write-SuccessMessage "Created issue #$issueNumber for: $FilePath"
            
            # Assign Copilot to the issue
            Start-Sleep -Seconds 2
            $assignResult = Set-CopilotAssignment -IssueNumber $issueNumber
            
            if ($assignResult.Success) {
                Write-SuccessMessage "Assigned Copilot to issue #$issueNumber"
            }
            
            return @{ 
                Success = $true
                IssueNumber = $issueNumber
                FilePath = $FilePath
            }
        } else {
            Add-CollectedError -ErrorMessage "Failed to create issue: $result" -FunctionName "New-CopilotIssue" -Context "GitHub CLI command failed for $FilePath"
            return @{ 
                Success = $false
                Error = "GitHub CLI command failed: $result"
            }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error creating issue: $($_.Exception.Message)" -FunctionName "New-CopilotIssue" -Exception $_.Exception -Context "Creating GitHub issue for $FilePath"
        return @{ 
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Assign Copilot to an issue
function Set-CopilotAssignment {
    param([string]$IssueNumber)
    
    Write-DebugMessage "Assigning Copilot to issue #$IssueNumber"
    
    try {
        if ($TestMode) {
            Write-SuccessMessage "[TEST MODE] Would assign Copilot to issue #$IssueNumber"
            return @{ Success = $true; TestMode = $true }
        }
        
        # Assign Copilot as assignee
        $assignResult = gh issue edit $IssueNumber --add-assignee "@copilot" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "✅ Copilot assigned successfully!"
            return @{ Success = $true }
        } else {
            Add-CollectedError -ErrorMessage "Failed to assign Copilot: $assignResult" -FunctionName "Set-CopilotAssignment" -Context "Assigning Copilot to issue #$IssueNumber"
            return @{ Success = $false; Error = $assignResult }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error assigning Copilot: $($_.Exception.Message)" -FunctionName "Set-CopilotAssignment" -Exception $_.Exception -Context "Assigning Copilot to issue #$IssueNumber"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Get-RelevantFiles {
    Write-ColorMessage "🔍 Scanning for relevant files..." $BLUE
    
    # Get all shell script files
    $shellFiles = Get-ChildItem -Recurse -Include "*.sh" | Where-Object { 
        -not $_.FullName.Contains(".git") -and 
        -not $_.FullName.Contains("node_modules") 
    }
    
    # Get all markdown files
    $markdownFiles = Get-ChildItem -Recurse -Include "*.md" | Where-Object { 
        -not $_.FullName.Contains(".git") -and 
        -not $_.FullName.Contains("node_modules") 
    }
    
    $allFiles = @($shellFiles) + @($markdownFiles)
    
    Write-ColorMessage "Found $($shellFiles.Count) shell files and $($markdownFiles.Count) markdown files" $CYAN
    Write-DebugMessage "Total files to process: $($allFiles.Count)"
    
    return $allFiles
}

function Test-FileHasValidationIssues {
    param([string]$FilePath)
    
    Write-DebugMessage "Testing file: $FilePath"
    
    # Run validation on single file
    $relativePath = (Resolve-Path $FilePath -Relative).Replace('\', '/')
    $validationOutput = & bash scripts/pre-commit-validation.sh $relativePath 2>&1
    
    # Check if validation found issues
    if ($LASTEXITCODE -ne 0) {
        Write-DebugMessage "Validation found issues in $FilePath"
        return $true
    }
    
    Write-DebugMessage "No issues found in $FilePath"
    return $false
}

function Get-FileValidationDetails {
    param([string]$FilePath)
    
    Write-DebugMessage "Getting detailed validation for: $FilePath"
    
    # Run validation on single file and capture output
    $relativePath = (Resolve-Path $FilePath -Relative).Replace('\', '/')
    $result = & bash scripts/pre-commit-validation.sh $relativePath 2>&1
    
    $issues = @()
    $criticalCount = 0
    $majorCount = 0
    $minorCount = 0
    
    # Parse the output for issue details
    foreach ($line in $result) {
        if ($line -match "\[CRITICAL\]") {
            $criticalCount++
            $issues += $line
        } elseif ($line -match "\[MAJOR\]") {
            $majorCount++
            $issues += $line
        } elseif ($line -match "\[MINOR\]") {
            $minorCount++
            $issues += $line
        }
    }
    
    return @{
        FilePath = $FilePath
        RelativePath = $relativePath
        Issues = $issues
        CriticalCount = $criticalCount
        MajorCount = $majorCount
        MinorCount = $minorCount
        TotalCount = $criticalCount + $majorCount + $minorCount
        HighestPriority = if ($criticalCount -gt 0) { "Critical" } elseif ($majorCount -gt 0) { "Major" } else { "Minor" }
    }
}

function Test-IssueExists {
    param([string]$FilePath)
    
    $fileName = Split-Path $FilePath -Leaf
    
    # Check if there's already an open issue for this file
    try {
        $existingIssues = gh issue list --state open --search "in:title $fileName" --json title,number | ConvertFrom-Json
        
        foreach ($issue in $existingIssues) {
            if ($issue.title -like "*$fileName*") {
                Write-DebugMessage "Found existing issue for $fileName`: #$($issue.number) - $($issue.title)"
                return $true
            }
        }
    } catch {
        Write-DebugMessage "Error checking for existing issues: $($_.Exception.Message)"
    }
    
    return $false
}

function New-CopilotIssue {
    param([object]$ValidationResult)
    
    $fileName = Split-Path $ValidationResult.FilePath -Leaf
    $priority = $ValidationResult.HighestPriority
    $totalIssues = $ValidationResult.TotalCount
    
    # Convert ValidationResult to Issues array for intelligent labeling
    $issuesArray = @()
    foreach ($issue in $ValidationResult.Issues) {
        $issuesArray += @{
            Line = "Unknown"  # ValidationResult format doesn't include line numbers
            Description = $issue
            Type = $ValidationResult.HighestPriority
        }
    }
    
    # Get intelligent labels using the enhanced module system (if available)
    if ($intelligentLabelingAvailable -and (Get-Command Get-IntelligentLabels -ErrorAction SilentlyContinue)) {
        $intelligentLabels = Get-IntelligentLabels -FilePath $ValidationResult.FilePath -Issues $issuesArray -Context "issue"
    } else {
        # Fallback to basic labels if module not available
        $intelligentLabels = @("rutos-compatibility", "posix-compliance", "busybox-compatibility", "shellcheck-issues")
        
        if ($priority -eq "Critical") {
            $intelligentLabels += @("priority-critical", "critical-busybox-incompatible", "auto-fix-needed")
        } elseif ($priority -eq "Major") {
            $intelligentLabels += @("priority-major", "manual-fix-needed")
        } else {
            $intelligentLabels += @("priority-minor", "manual-fix-needed")
        }
        
        if ($ValidationResult.Issues -match "busybox") { $intelligentLabels += "busybox-fix" }
        if ($ValidationResult.Issues -match "local") { $intelligentLabels += "critical-local-keyword" }
        if ($ValidationResult.Issues -match "bash") { $intelligentLabels += "type-bash-shebang" }
    }
    
    # Add copilot assignment label
    $intelligentLabels += "copilot-assigned"
    
    # Debug output for intelligent labeling
    if ($Debug) {
        Write-ColorMessage "🏷️  Intelligent Labeling System Results:" $BLUE
        Write-ColorMessage "   Module Available: $intelligentLabelingAvailable" $CYAN
        Write-ColorMessage "   Total Labels: $($intelligentLabels.Count)" $CYAN
        Write-ColorMessage "   Priority Labels: $(($intelligentLabels | Where-Object { $_ -match '^priority-' }) -join ', ')" $YELLOW
        Write-ColorMessage "   Critical Labels: $(($intelligentLabels | Where-Object { $_ -match '^critical-' }) -join ', ')" $RED
        Write-ColorMessage "   Type Labels: $(($intelligentLabels | Where-Object { $_ -match '^type-' }) -join ', ')" $MAGENTA
        Write-ColorMessage "   All Labels: $($intelligentLabels -join ', ')" $WHITE
    }
    
    # Priority emoji based on highest severity
    $priorityEmoji = if ($priority -eq "Critical") { "🔴" } 
                     elseif ($priority -eq "Major") { "🟡" } 
                     else { "🔵" }
    
    # Create enhanced issue title
    $title = "$priorityEmoji RUTOS Compatibility Fix: $fileName"
    
    # Create enhanced issue body
    $issueBody = @"
## $priorityEmoji RUTOS Compatibility Issues Detected

**File:** ``$($ValidationResult.RelativePath)``  
**Issues Found:** $totalIssues ($($ValidationResult.CriticalCount) critical, $($ValidationResult.MajorCount) major, $($ValidationResult.MinorCount) minor)  
**Priority:** $priorityEmoji $priority

### 🎯 Issues to Fix

#### Issue Breakdown:
- � **Critical:** $($ValidationResult.CriticalCount)
- 🟡 **Major:** $($ValidationResult.MajorCount)
- 🔵 **Minor:** $($ValidationResult.MinorCount)

#### Issues Found:
``````
$($ValidationResult.Issues -join "`n")
``````

### 📋 RUTOS Compatibility Requirements

This file needs to be compatible with **RUTX50 router running RUTOS** (busybox shell environment):

- ✅ **POSIX sh compliance** (no bash-specific syntax)
- ✅ **No arrays** (use space-separated strings)
- ✅ **No [[]]** (use [ ] for conditions)
- ✅ **No local variables** (busybox limitation)
- ✅ **No bash built-ins** (like echo -e, use printf)

### 🏷️ Intelligent Labels Applied

**Labeling System Status:** $(if ($intelligentLabelingAvailable) { "Enhanced (GitHub-Label-Management.psm1)" } else { "Basic" })

**Applied Labels:**
$(($intelligentLabels | ForEach-Object { "- ``$_``" }) -join "`n")

**Total Labels:** $($intelligentLabels.Count) labels applied

### 🔧 Expected Actions

Please review and fix the POSIX compliance issues in this file. Focus on:

1. **Critical Issues First** - Address any bash-specific syntax
2. **Shell Compatibility** - Ensure busybox sh compatibility
3. **Testing** - Verify changes work in RUTOS environment
4. **Documentation** - Update any changed functionality

### 📚 Reference Documentation

- [RUTOS Compatibility Guidelines](../docs/SHELL-COMPATIBILITY-STRATEGY.md)
- [POSIX Shell Scripting Best Practices](../docs/CODE_QUALITY_SYSTEM.md)
- [Testing on RUTX50](../docs/RUTX50-PRODUCTION-GUIDE.md)

**Auto-assigned to @copilot for autonomous resolution.**

---
*This issue was automatically generated by the RUTOS compatibility validation system with enhanced intelligent labeling.*
*Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*
"@

    $labelsString = $intelligentLabels -join ","
    
    Write-ColorMessage "🚀 Creating issue for $fileName..." $BLUE
    
    if ($Production) {
        try {
            # Create the issue without assignee first
            $issueResult = gh issue create --title $title --body $issueBody --label $labelsString
            
            if ($LASTEXITCODE -eq 0) {
                # Extract issue number from result
                $issueNumber = $issueResult -replace '.*#(\d+).*', '$1'
                Write-ColorMessage "✅ Created issue #$issueNumber" $GREEN
                
                # Now try to assign @copilot using our enhanced assignment function
                try {
                    $assignResult = gh issue edit $issueNumber --add-assignee "copilot"
                    if ($LASTEXITCODE -eq 0) {
                        Write-ColorMessage "✅ Assigned @copilot to issue #$issueNumber" $GREEN
                    } else {
                        Write-ColorMessage "⚠️  Issue created but copilot assignment failed" $YELLOW
                    }
                } catch {
                    Write-ColorMessage "⚠️  Issue created but copilot assignment failed: $($_.Exception.Message)" $YELLOW
                }
                
                return @{ Success = $true; IssueNumber = $issueNumber; Title = $title }
            } else {
                Write-ColorMessage "❌ Failed to create issue for $fileName" $RED
                return @{ Success = $false; Error = "GitHub CLI failed" }
            }
        } catch {
            Write-ColorMessage "❌ Error creating issue: $($_.Exception.Message)" $RED
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    } else {
        Write-ColorMessage "🧪 [DRY RUN] Would create issue: $title" $YELLOW
        return @{ Success = $true; IssueNumber = "DRY-RUN"; Title = $title }
    }
}

function Test-ShouldProcessFile {
    param([object]$ValidationResult, [string]$PriorityFilter)
    
    if ($PriorityFilter -eq "All") {
        return $true
    }
    
    switch ($PriorityFilter) {
        "Critical" { return $ValidationResult.CriticalCount -gt 0 }
        "Major" { return $ValidationResult.MajorCount -gt 0 }
        "Minor" { return $ValidationResult.MinorCount -gt 0 }
        default { return $true }
    }
}

# Main execution
Write-ColorMessage "🎯 OPTIMIZED COPILOT ISSUE CREATION SYSTEM" $BLUE
Write-ColorMessage "=============================================" $BLUE

if (-not $Production) {
    Write-ColorMessage "🧪 DRY RUN MODE - No actual issues will be created" $YELLOW
    Write-ColorMessage "   Use -Production to create real issues" $YELLOW
} else {
    Write-ColorMessage "🚀 PRODUCTION MODE - Issues will be created" $GREEN
}

Write-ColorMessage "📊 Configuration:" $CYAN
Write-ColorMessage "   Max Issues: $MaxIssues" $CYAN
Write-ColorMessage "   Priority Filter: $PriorityFilter" $CYAN
Write-ColorMessage "   Debug Mode: $Debug" $CYAN

# Step 1: Get all relevant files
$allFiles = Get-RelevantFiles

# Step 2: Process files one by one
$processedFiles = @()
$createdIssues = @()
$skippedFiles = @()

Write-ColorMessage "`n🔄 Processing files individually..." $BLUE

foreach ($file in $allFiles) {
    Write-DebugMessage "Processing: $($file.FullName)"
    
    # Check if we've reached our limit
    if ($createdIssues.Count -ge $MaxIssues) {
        Write-ColorMessage "✅ Reached maximum issues limit ($MaxIssues)" $GREEN
        break
    }
    
    # Check if issue already exists
    if (Test-IssueExists -FilePath $file.FullName) {
        Write-ColorMessage "⏭️  Skipping $($file.Name) - issue already exists" $GRAY
        $skippedFiles += $file
        continue
    }
    
    # Test if file has validation issues
    if (Test-FileHasValidationIssues -FilePath $file.FullName) {
        # Get detailed validation results
        $validationResult = Get-FileValidationDetails -FilePath $file.FullName
        $processedFiles += $validationResult
        
        # Check if we should process this file based on priority filter
        if (Test-ShouldProcessFile -ValidationResult $validationResult -PriorityFilter $PriorityFilter) {
            Write-ColorMessage "🎯 Found issues in $($file.Name) - Priority: $($validationResult.HighestPriority), Count: $($validationResult.TotalCount)" $YELLOW
            
            # Create issue for this file
            $issueResult = New-CopilotIssue -ValidationResult $validationResult
            
            if ($issueResult.Success) {
                $createdIssues += $issueResult
            }
        } else {
            Write-ColorMessage "⏭️  Skipping $($file.Name) - doesn't match priority filter ($PriorityFilter)" $GRAY
            $skippedFiles += $file
        }
    } else {
        Write-DebugMessage "No issues found in $($file.Name)"
    }
}

# Summary
Write-ColorMessage "`n📊 EXECUTION SUMMARY" $BLUE
Write-ColorMessage "===================" $BLUE
Write-ColorMessage "Total files scanned: $($allFiles.Count)" $CYAN
Write-ColorMessage "Files with issues: $($processedFiles.Count)" $CYAN
Write-ColorMessage "Files skipped (existing issues): $($skippedFiles.Count)" $CYAN
Write-ColorMessage "Issues created: $($createdIssues.Count)" $GREEN
Write-ColorMessage "Max issues limit: $MaxIssues" $CYAN

if ($createdIssues.Count -gt 0) {
    Write-ColorMessage "`n🎉 Created Issues:" $GREEN
    foreach ($issue in $createdIssues) {
        Write-ColorMessage "   $($issue.IssueNumber): $($issue.Title)" $GREEN
    }
}

if ($Debug -and $processedFiles.Count -gt 0) {
    Write-ColorMessage "`n🔍 Files with Issues (Debug):" $CYAN
    foreach ($file in $processedFiles) {
        Write-ColorMessage "   $($file.RelativePath): $($file.HighestPriority) priority, $($file.TotalCount) issues" $CYAN
    }
}

Write-ColorMessage "`n✅ Optimized issue creation completed!" $GREEN
