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

[CmdletBinding(SupportsShouldProcess)]
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
    Write-Information "🏷️  GitHub Label Management Module Loaded"
    Write-Information "✅ Loaded enhanced label management system (100+ labels)"
    $intelligentLabelingAvailable = $true
} else {
    Write-Information "⚠️  Enhanced label management module not found - using basic labels"
    $intelligentLabelingAvailable = $false
}

# Global configuration
$SCRIPT_VERSION = "1.0.0"
$VALIDATION_SCRIPT = "scripts/pre-commit-validation.sh"
$STATE_FILE = "automation/.copilot-issues-state.json"

# Script-scoped error collection for comprehensive reporting
$script:CollectedErrors = @()
$script:ErrorCount = 0

# State tracking
$script:IssueState = @{}
$script:CreatedIssues = @()

# Color definitions for consistent output
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$GRAY = [ConsoleColor]::Gray

# Enhanced logging functions
function Write-StatusMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$Level] [$timestamp] $Message"
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

    $script:ErrorCount++

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
        ErrorNumber = $script:ErrorCount
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

    # Add to script collection
    $script:CollectedErrors += $errorInfo

    # Display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$script:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED -Level "ERROR"

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
function Show-CollectedError {
    if ($script:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }

    Write-Information "`n" + ("=" * 100)
    Write-Information "🚨 COMPREHENSIVE ERROR REPORT - $($script:CollectedErrors.Count) Error(s) Found"
    Write-Information ("=" * 100)

    foreach ($errorInfo in $script:CollectedErrors) {
        Write-Information "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)"
        Write-Information "   🎯 Function: $($errorInfo.FunctionName)"
        Write-Information "   📍 Location: $($errorInfo.Location)"
        Write-Information "   💬 Message: $($errorInfo.Message)"

        if ($errorInfo.Context) {
            Write-Information "   📝 Context: $($errorInfo.Context)"
        }

        if ($errorInfo.ExceptionType -ne "N/A") {
            Write-Information "   🔍 Exception: $($errorInfo.ExceptionType) - $($errorInfo.ExceptionMessage)"
        }

        if ($errorInfo.LastExitCode -ne 0) {
            Write-Information "   🔢 Last Exit Code: $($errorInfo.LastExitCode)"
        }

        if ($errorInfo.AdditionalInfo.Count -gt 0) {
            Write-Information "   📊 Additional Info:"
            foreach ($key in $errorInfo.AdditionalInfo.Keys) {
                Write-Information "      $key`: $($errorInfo.AdditionalInfo[$key])"
            }
        }
    }

    Write-Information "`n📊 ERROR SUMMARY:"
    Write-Information "   Total Errors: $($script:CollectedErrors.Count)"
    Write-Information "   Functions with Errors: $($script:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count"
}

# Import and save state for preventing infinite loops
function Import-IssueState {
    Write-DebugMessage "Loading issue state from: $STATE_FILE"

    if (Test-Path $STATE_FILE) {
        try {
            $stateContent = Get-Content $STATE_FILE -Raw | ConvertFrom-Json
            $script:IssueState = @{}

            foreach ($property in $stateContent.PSObject.Properties) {
                $script:IssueState[$property.Name] = $property.Value
            }

            Write-DebugMessage "Loaded state for $($script:IssueState.Count) files"
            return $true
        } catch {
            Add-CollectedError -ErrorMessage "Failed to load state file: $($_.Exception.Message)" -FunctionName "Import-IssueState" -Exception $_.Exception -Context "Loading issue state from $STATE_FILE" -AdditionalInfo @{StateFile = $STATE_FILE}
            $script:IssueState = @{}
            return $false
        }
    } else {
        Write-DebugMessage "No existing state file found - starting fresh"
        $script:IssueState = @{}
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
        $script:IssueState | ConvertTo-Json -Depth 10 | Out-File $STATE_FILE -Encoding UTF8
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
        Write-DebugMessage "Running validation on file: $FilePath"

        # Use Start-Process instead of Invoke-Expression for security
        $processArgs = @{
            FilePath = "wsl"
            ArgumentList = @("bash", "-c", "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'")
            Wait = $true
            PassThru = $true
            RedirectStandardOutput = $true
            RedirectStandardError = $true
        }

        $process = Start-Process @processArgs
        $validationOutput = Get-Content $process.StandardOutput -ErrorAction SilentlyContinue
        $errorOutput = Get-Content $process.StandardError -ErrorAction SilentlyContinue
        $exitCode = $process.ExitCode

        # Combine output and error streams like 2>&1
        $allOutput = @()
        if ($validationOutput) { $allOutput += $validationOutput }
        if ($errorOutput) { $allOutput += $errorOutput }

        Write-DebugMessage "Validation exit code: $exitCode"

        # Parse the validation output to extract issues
        $issues = ConvertFrom-ValidationOutput -Output $allOutput -FilePath $FilePath

        return @{
            Success = $exitCode -eq 0
            ExitCode = $exitCode
            Issues = $issues
            Output = $allOutput
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

# Convert validation output for a specific file
function ConvertFrom-ValidationOutput {
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

# Get list of relevant file to process
function Get-RelevantFile {
    Write-DebugMessage "Getting relevant files to process"

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

    Write-DebugMessage "Found $($filesToProcess.Count) relevant files"
    return $filesToProcess
}

# Test if file has validation issue
function Test-FileHasValidationIssue {
    param([string]$FilePath)

    Write-DebugMessage "Testing if file has validation issues: $FilePath"

    $validationResult = Invoke-ValidationOnFile -FilePath $FilePath
    return @{
        HasIssues = -not $validationResult.Success
        IssuesCount = $validationResult.Issues.Count
        ValidationResult = $validationResult
    }
}

# Get detailed validation information for a file
function Get-FileValidationDetail {
    param([string]$FilePath)

    Write-DebugMessage "Getting validation details for: $FilePath"

    $validationResult = Invoke-ValidationOnFile -FilePath $FilePath

    if ($validationResult.Success) {
        return @{
            HasIssues = $false
            IssuesCount = 0
            Issues = @()
            Details = "File passed validation"
        }
    }

    $criticalIssues = $validationResult.Issues | Where-Object { $_.Type -eq "Critical" }
    $majorIssues = $validationResult.Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $validationResult.Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }

    return @{
        HasIssues = $true
        IssuesCount = $validationResult.Issues.Count
        Issues = $validationResult.Issues
        CriticalCount = $criticalIssues.Count
        MajorCount = $majorIssues.Count
        MinorCount = $minorIssues.Count
        Details = "Found $($validationResult.Issues.Count) issues: $($criticalIssues.Count) critical, $($majorIssues.Count) major, $($minorIssues.Count) minor"
    }
}

# Test if an issue already exists for a file
function Test-IssueExist {
    param([string]$FilePath)

    Write-DebugMessage "Checking if issue exists for: $FilePath"

    try {
        # Search for existing issues related to this file
        $searchResult = gh issue list --search "$FilePath" --state "open" --json "number,title" 2>&1

        if ($LASTEXITCODE -eq 0) {
            $issues = $searchResult | ConvertFrom-Json
            $existingIssue = $issues | Where-Object { $_.title -match [regex]::Escape($FilePath) }

            if ($existingIssue) {
                Write-DebugMessage "Found existing issue #$($existingIssue.number) for file"
                return @{
                    Exists = $true
                    IssueNumber = $existingIssue.number
                    Title = $existingIssue.title
                }
            }
        }

        return @{ Exists = $false }
    } catch {
        Add-CollectedError -ErrorMessage "Failed to check for existing issues: $($_.Exception.Message)" -FunctionName "Test-IssueExist" -Exception $_.Exception -Context "Checking for existing issue for $FilePath"
        return @{ Exists = $false }
    }
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
    if ($script:IssueState.ContainsKey($FilePath) -and -not $ForceReprocessing) {
        $fileState = $script:IssueState[$FilePath]
        if ($fileState.Status -eq "Completed") {
            Write-DebugMessage "File already completed - skipping"
            return $false
        }
    }

    # Check if issue already exists
    $existingIssue = Test-IssueExist -FilePath $FilePath
    if ($existingIssue.Exists -and -not $ForceReprocessing) {
        Write-DebugMessage "Issue already exists (#$($existingIssue.IssueNumber)) - skipping"
        return $false
    }

    Write-DebugMessage "File should be processed"
    return $true
}

# Create GitHub issue with comprehensive content and intelligent labeling
function New-CopilotIssue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FilePath,
        [array]$Issues
    )

    Write-StepMessage "Creating Copilot issue for: $FilePath"

    if ($TestMode) {
        Write-SuccessMessage "[TEST MODE] Would create issue for: $FilePath"
        return @{ Success = $true; IssueNumber = "TEST-MODE"; TestMode = $true }
    }

    if (-not $PSCmdlet.ShouldProcess($FilePath, "Create GitHub Issue")) {
        return @{ Success = $false; Skipped = $true }
    }

    try {
        # Categorize issues by severity
        $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }

        # Convert Issues to format for intelligent labeling
        $issuesArray = @()
        foreach ($issue in $Issues) {
            $issuesArray += @{
                Line = $issue.Line
                Description = $issue.Description
                Type = $issue.Type
            }
        }

        # Get intelligent labels using the enhanced module system (if available)
        if ($intelligentLabelingAvailable -and (Get-Command Get-IntelligentLabels -ErrorAction SilentlyContinue)) {
            $intelligentLabels = Get-IntelligentLabels -FilePath $FilePath -Issues $issuesArray -Context "issue"
        } else {
            # Fallback to basic labels if module not available
            $intelligentLabels = @("rutos-compatibility", "posix-compliance", "busybox-compatibility", "shellcheck-issues")

            if ($criticalIssues.Count -gt 0) {
                $intelligentLabels += @("priority-critical", "critical-busybox-incompatible", "auto-fix-needed")
            } elseif ($majorIssues.Count -gt 0) {
                $intelligentLabels += @("priority-major", "manual-fix-needed")
            } else {
                $intelligentLabels += @("priority-minor", "manual-fix-needed")
            }

            if ($Issues | Where-Object { $_.Description -match "busybox" }) { $intelligentLabels += "busybox-fix" }
            if ($Issues | Where-Object { $_.Description -match "local" }) { $intelligentLabels += "critical-local-keyword" }
            if ($Issues | Where-Object { $_.Description -match "bash" }) { $intelligentLabels += "type-bash-shebang" }
        }

        # Add copilot assignment label
        $intelligentLabels += "copilot-assigned"

        # Debug output for intelligent labeling
        if ($Debug) {
            Write-DebugMessage "🏷️  Intelligent Labeling System Results:"
            Write-DebugMessage "   Module Available: $intelligentLabelingAvailable"
            Write-DebugMessage "   Total Labels: $($intelligentLabels.Count)"
            Write-DebugMessage "   Priority Labels: $(($intelligentLabels | Where-Object { $_ -match '^priority-' }) -join ', ')"
            Write-DebugMessage "   Critical Labels: $(($intelligentLabels | Where-Object { $_ -match '^critical-' }) -join ', ')"
            Write-DebugMessage "   Type Labels: $(($intelligentLabels | Where-Object { $_ -match '^type-' }) -join ', ')"
            Write-DebugMessage "   All Labels: $($intelligentLabels -join ', ')"
        }

        # Priority emoji based on highest severity
        $priorityEmoji = if ($criticalIssues.Count -gt 0) { "🔴" }
                         elseif ($majorIssues.Count -gt 0) { "🟡" }
                         else { "🔵" }

        # Generate enhanced issue title
        $issueTitle = "$priorityEmoji RUTOS Compatibility Fix: $(Split-Path $FilePath -Leaf)"

        # Generate enhanced issue body with intelligent labeling
        $issueBody = @"
# $priorityEmoji RUTOS Compatibility Issues Detected

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

        # Add fix guidelines and intelligent labeling section
        $issueBody += @"

## 🏷️ Intelligent Labels Applied

**Labeling System Status:** $(if ($intelligentLabelingAvailable) { "Enhanced (GitHub-Label-Management.psm1)" } else { "Basic" })

**Applied Labels:**
$(($intelligentLabels | ForEach-Object { "- ``$_``" }) -join "`n")

**Total Labels:** $($intelligentLabels.Count) labels applied

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

*Generated by create-copilot-issues-optimized.ps1 v$SCRIPT_VERSION with enhanced intelligent labeling*
*Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

        # Use intelligent labels instead of basic labels
        $labels = $intelligentLabels

        # Create temporary file for issue body
        $tempFile = [System.IO.Path]::GetTempFileName()
        $issueBody | Out-File -FilePath $tempFile -Encoding UTF8

        # Build GitHub CLI command arguments
        $ghArgs = @("issue", "create", "-t", $issueTitle, "-F", $tempFile)
        foreach ($label in $labels) {
            $ghArgs += @("-l", $label)
        }

        Write-DebugMessage "Executing: gh $($ghArgs -join ' ')"

        # Execute GitHub CLI command using Start-Process for security
        $processArgs = @{
            FilePath = "gh"
            ArgumentList = $ghArgs
            Wait = $true
            PassThru = $true
            RedirectStandardOutput = $true
            RedirectStandardError = $true
        }

        $process = Start-Process @processArgs
        $result = if ($process.StandardOutput) { Get-Content $process.StandardOutput } else { "" }
        $errorResult = if ($process.StandardError) { Get-Content $process.StandardError } else { "" }
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        if ($process.ExitCode -eq 0) {
            # Extract issue number from result
            $issueNumber = ""
            if ($result -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                $issueNumber = $Matches[1]
            }

            Write-SuccessMessage "Created issue #$issueNumber for: $FilePath"

            # Update state tracking
            $script:IssueState[$FilePath] = @{
                Status = "Created"
                IssueNumber = $issueNumber
                CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                IssueCount = $Issues.Count
            }

            # Assign Copilot to the issue
            Start-Sleep -Seconds 2
            $assignResult = Set-CopilotAssignment -IssueNumber $issueNumber

            if ($assignResult.Success) {
                Write-SuccessMessage "Assigned Copilot to issue #$issueNumber"
                $script:IssueState[$FilePath].Status = "Assigned"
            }

            return @{
                Success = $true
                IssueNumber = $issueNumber
                FilePath = $FilePath
            }
        } else {
            Add-CollectedError -ErrorMessage "Failed to create issue: $result $errorResult" -FunctionName "New-CopilotIssue" -Context "GitHub CLI command failed for $FilePath"
            return @{
                Success = $false
                Error = "GitHub CLI command failed: $result $errorResult"
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
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$IssueNumber)

    Write-DebugMessage "Assigning Copilot to issue #$IssueNumber"

    if (-not $PSCmdlet.ShouldProcess("Issue #$IssueNumber", "Assign Copilot")) {
        return @{ Success = $false; Skipped = $true }
    }

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
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-InfoMessage "🚀 Starting Optimized RUTOS Copilot Issue Creation System v$SCRIPT_VERSION"

    if (-not $PSCmdlet.ShouldProcess("Repository", "Start Issue Creation Process")) {
        Write-InfoMessage "Issue creation process cancelled by user"
        return
    }

    # Load state
    Import-IssueState | Out-Null

    # Get target files to process
    if ($TargetFile) {
        Write-InfoMessage "🎯 Processing single target file: $TargetFile"
        $filesToProcess = @($TargetFile)
    } else {
        Write-StepMessage "📂 Scanning repository for shell scripts and markdown files..."
        $filesToProcess = Get-RelevantFile
    }

    Write-InfoMessage "📊 Found $($filesToProcess.Count) potential files to process"

    if ($filesToProcess.Count -eq 0) {
        Write-WarningMessage "❌ No files found to process"
        return
    }

    # Sort files by priority if requested
    if ($SortByPriority) {
        Write-StepMessage "📋 Sorting files by issue priority..."
        $prioritizedFiles = @()

        foreach ($file in $filesToProcess) {
            $validationDetails = Get-FileValidationDetail -FilePath $file
            if ($validationDetails.HasIssues) {
                $priority = if ($validationDetails.CriticalCount -gt 0) { 1 }
                           elseif ($validationDetails.MajorCount -gt 0) { 2 }
                           else { 3 }

                $prioritizedFiles += @{
                    File = $file
                    Priority = $priority
                    Details = $validationDetails
                }
            }
        }

        $filesToProcess = ($prioritizedFiles | Sort-Object Priority | ForEach-Object { $_.File })
        Write-InfoMessage "📊 Prioritized $($filesToProcess.Count) files with issues"
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
                $script:CreatedIssues += @{
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

    # Save state
    Save-IssueState | Out-Null

    # Display final summary
    Write-Information "`n" + ("=" * 80)
    Write-Information "📊 PROCESSING SUMMARY"
    Write-Information ("=" * 80)

    Write-InfoMessage "📁 Files Processed: $filesProcessed"
    Write-InfoMessage "⏭️  Files Skipped: $filesSkipped"
    Write-InfoMessage "📝 Issues Created: $issuesCreated"
    Write-InfoMessage "🎯 Maximum Issues: $MaxIssues"

    if ($script:CreatedIssues.Count -gt 0) {
        Write-Information "`n📋 Created Issues:"
        foreach ($issue in $script:CreatedIssues) {
            Write-Information "   #$($issue.IssueNumber) - $($issue.FilePath) ($($issue.IssueCount) issues)"
        }
    }

    # Show any collected errors
    if ($script:CollectedErrors.Count -gt 0) {
        Show-CollectedError
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
        Write-DebugMessage "Intelligent labeling available: $intelligentLabelingAvailable"
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
        gh auth status 2>&1 | Out-Null
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
        Write-Information "Press Ctrl+C to cancel or wait 5 seconds to continue..."
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
