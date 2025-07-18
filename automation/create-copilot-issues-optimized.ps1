#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Optimized Autonomous RUTOS Copilot Issue Creation System

.DESCRIPTION
    Optimized version that processes files individually for better performance:
    1. Scans repository for relevant files (shell scripts, PowerShell scripts, and markdown)
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

.PARAMETER DebugMode
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

.PARAMETER RecentlyClosedHours
    Hours to look back for recently closed issues to avoid conflicts (default: 8)

.EXAMPLE
    .\create-copilot-issues-optimized.ps1
    Run in safe dry run mode with max 3 issues

.EXAMPLE
    .\create-copilot-issues-optimized.ps1 -Production -MaxIssues 5
    Production mode with maximum 5 issues

.EXAMPLE
    .\create-copilot-issues-optimized.ps1 -PriorityFilter Critical -DebugMode
    Focus on critical issues with debug output
#>

[CmdletBinding()]
param(
    [switch]$Production = $false,
    [int]$MaxIssues = 3,
    [string]$PriorityFilter = "All", # All, Critical, Major, Minor
    [switch]$DebugMode = $false,
    [switch]$TestMode = $false,
    [switch]$SkipValidation = $false,
    [switch]$ForceReprocessing = $false,
    [string]$TargetFile = "",
    [int]$MinIssuesPerFile = 1,
    [switch]$SortByPriority = $false,
    [int]$RecentlyClosedHours = 8  # Hours to look back for recently closed issues
)

# Import the enhanced label management module
$labelModulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $labelModulePath) {
    Import-Module $labelModulePath -Force -ErrorAction SilentlyContinue
    Write-Information "[LABELS] GitHub Label Management Module Loaded" -InformationAction Continue
    Write-Information "[SUCCESS] Loaded enhanced label management system (100+ labels)" -InformationAction Continue
    $intelligentLabelingAvailable = $true
} else {
    Write-Warning "[WARNING] Enhanced label management module not found - using basic labels"
    $intelligentLabelingAvailable = $false
}

# Global configuration
$SCRIPT_VERSION = "1.0.0"
$VALIDATION_SCRIPT = "scripts/pre-commit-validation.sh"
$STATE_FILE = "automation/.copilot-issues-state.json"

# Script-scoped state variables to replace global variables
$script:CollectedErrors = @()
$script:ErrorCount = 0
$script:IssueState = @{}
$script:CreatedIssues = @()

# Color definitions for consistent output (kept for potential future use)
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
    if ($DebugMode) {
        Write-StatusMessage "[DEBUG] $Message" -Level "DEBUG"
    }
}

function Write-StepMessage {
    param([string]$Message)
    Write-StatusMessage "[STEP] $Message" -Level "STEP"
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-StatusMessage "[ERROR] $Message" -Level "ERROR"
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-StatusMessage "[SUCCESS] $Message" -Level "SUCCESS"
}

function Write-WarningMessage {
    param([string]$Message)
    Write-StatusMessage "[WARNING] $Message" -Level "WARNING"
}

function Write-InfoMessage {
    param([string]$Message)
    Write-StatusMessage "$Message" -Level "INFO"
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

    # Add to collection
    $script:CollectedErrors += $errorInfo

    # Display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$($script:ErrorCount) in $FunctionName`: $ErrorMessage" -Level "ERROR"

    if ($DebugMode) {
        Write-StatusMessage "   📍 Location: $Location" -Level "DEBUG"
        if ($Context) {
            Write-StatusMessage "   📝 Context: $Context" -Level "DEBUG"
        }
        if ($Exception) {
            Write-StatusMessage "   🔍 Exception: $($Exception.GetType().Name) - $($Exception.Message)" -Level "DEBUG"
        }
    }
}

# Display comprehensive error report
function Show-CollectedError {
    if ($script:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Level "SUCCESS"
        return
    }

    Write-Output -InputObject ("`n" + ("=" * 100))
    Write-Output -InputObject "🚨 COMPREHENSIVE ERROR REPORT - $($script:CollectedErrors.Count) Error(s) Found"
    Write-Output -InputObject ("=" * 100)

    foreach ($errorInfo in $script:CollectedErrors) {
        Write-Output -InputObject "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)"
        Write-Output -InputObject "   🎯 Function: $($errorInfo.FunctionName)"
        Write-Output -InputObject "   📍 Location: $($errorInfo.Location)"
        Write-Output -InputObject "   💬 Message: $($errorInfo.Message)"

        if ($errorInfo.Context) {
            Write-Output -InputObject "   📝 Context: $($errorInfo.Context)"
        }

        if ($errorInfo.ExceptionType -ne "N/A") {
            Write-Output -InputObject "   🔍 Exception: $($errorInfo.ExceptionType) - $($errorInfo.ExceptionMessage)"
        }

        if ($errorInfo.LastExitCode -ne 0) {
            Write-Output -InputObject "   🔢 Last Exit Code: $($errorInfo.LastExitCode)"
        }

        if ($errorInfo.AdditionalInfo.Count -gt 0) {
            Write-Output -InputObject "   📊 Additional Info:"
            foreach ($key in $errorInfo.AdditionalInfo.Keys) {
                Write-Output -InputObject "      $key`: $($errorInfo.AdditionalInfo[$key])"
            }
        }
    }

    Write-Output -InputObject "`n📊 ERROR SUMMARY:"
    Write-Output -InputObject "   Total Errors: $($script:CollectedErrors.Count)"
    Write-Output -InputObject "   Functions with Errors: $($script:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count"
}

# Load and save state for preventing infinite loops
function Get-IssueState {
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
            Add-CollectedError -ErrorMessage "Failed to load state file: $($_.Exception.Message)" -FunctionName "Get-IssueState" -Exception $_.Exception -Context "Loading issue state from $STATE_FILE" -AdditionalInfo @{StateFile = $STATE_FILE}
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
    param(
        [ScriptState]
        [string]$FilePath
    )

    Write-DebugMessage "Running validation on file: $FilePath"

    try {
        # Use Start-Process instead of Invoke-Expression for security
        $arguments = @(
            'bash'
            '-c'
            "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'"
        )

        Write-DebugMessage "Executing: wsl $($arguments -join ' ')"

        $process = Start-Process -FilePath 'wsl' -ArgumentList $arguments -Wait -NoNewWindow -PassThru -RedirectStandardOutput -RedirectStandardError
        $validationOutput = Get-Content $process.StandardOutput -Raw
        $errorOutput = Get-Content $process.StandardError -Raw
        $exitCode = $process.ExitCode

        # Combine output and error streams
        $combinedOutput = @($validationOutput, $errorOutput) | Where-Object { $_ } | ForEach-Object { $_.Split("`n") }

        Write-DebugMessage "Validation exit code: $exitCode"

        # Parse the validation output to extract issues
        $issues = ConvertFrom-ValidationOutput -Output $combinedOutput -FilePath $FilePath

        return @{
            Success = $exitCode -eq 0
            ExitCode = $exitCode
            Issues = $issues
            Output = $combinedOutput
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
function ConvertFrom-ValidationOutput {
    param(
        [string[]]$Output,
        [string]$FilePath
    )

    Write-DebugMessage "Parsing validation output for: $FilePath"

    $issues = @()
    $lineCount = 0

    foreach ($line in $Output) {
        $line = $line.Trim()
        $lineCount++

        # Skip empty lines and obvious summary lines
        if (-not $line -or $line -match "^(Files processed|Files failed|Total|Summary|===|---|\[SUCCESS\]|\[INFO\])") {
            continue
        }

        Write-DebugMessage "Processing line $lineCount`: $line"

        # Handle the specific format: [SEVERITY] filepath:line description
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]\s+(.+?):(\d+)\s+(.+)$") {
            $severity = $Matches[1]
            $filepath = $Matches[2] -replace "^\.\/", ""
            $lineNumber = $Matches[3]
            $description = $Matches[4]

            Write-DebugMessage "Found formatted issue: [$severity] $filepath`:$lineNumber $description"

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
                Write-DebugMessage "Added issue: Type=$issueType, Line=$lineNumber"
            } else {
                Write-DebugMessage "Skipped issue for different file: $filepath"
            }
        }
        # Handle ShellCheck format: filepath:line:column: note/warning/error: description
        elseif ($line -match "^(.+?):(\d+):(\d+):\s+(note|warning|error):\s+(.+)$") {
            $filepath = $Matches[1] -replace "^\.\/", ""
            $lineNumber = $Matches[2]
            $issueLevel = $Matches[4]
            $description = $Matches[5]

            Write-DebugMessage "Found ShellCheck issue: $filepath`:$lineNumber $issueLevel`: $description"

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
                Write-DebugMessage "Added ShellCheck issue: Type=$issueType, Line=$lineNumber"
            } else {
                Write-DebugMessage "Skipped ShellCheck issue for different file: $filepath"
            }
        }
        # Handle PSScriptAnalyzer format: RuleName: Line number severity message
        elseif ($line -match "^([A-Za-z0-9_]+):\s+Line\s+(\d+)\s+(Error|Warning|Information)\s+(.+)$") {
            $ruleName = $Matches[1]
            $lineNumber = $Matches[2]
            $severity = $Matches[3]
            $message = $Matches[4]

            Write-DebugMessage "Found PSScriptAnalyzer issue: Line $lineNumber $severity`: $ruleName - $message"

            $issueType = switch ($severity) {
                "Error" { "Critical" }
                "Warning" { "Major" }
                "Information" { "Minor" }
                default { "Minor" }
            }

            $issues += @{
                Line = [int]$lineNumber
                Description = "$ruleName - $message"
                Type = $issueType
                Severity = $severity
            }
            Write-DebugMessage "Added PSScriptAnalyzer issue: Type=$issueType, Line=$lineNumber"
        }
        # Generic error patterns - be more specific to avoid false positives
        elseif ($line -match "^\s*(CRITICAL|ERROR):\s*(.+)" -and $line -notmatch "SUCCESS|PASSED|Files failed|Total|Summary") {
            $description = $Matches[2].Trim()
            Write-DebugMessage "Found generic error pattern: $description"
            # Only add if it looks like a real issue description, not a summary line
            if ($description -and $description.Length -gt 10 -and $description -notmatch "^\d+$") {
                $issues += @{
                    Line = "Unknown"
                    Description = $description
                    Type = "Critical"
                    Severity = "High"
                }
                Write-DebugMessage "Added generic critical issue: $description"
            } else {
                Write-DebugMessage "Rejected generic pattern as summary line: $description"
            }
        }
        else {
            Write-DebugMessage "Line didn't match any pattern: $line"
        }
    }

    # Categorize issues for debugging
    $criticalCount = ($issues | Where-Object { $_.Type -eq "Critical" }).Count
    $majorCount = ($issues | Where-Object { $_.Type -eq "Major" }).Count
    $minorCount = ($issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "Warning" }).Count

    Write-DebugMessage "Parsing complete for $FilePath`:"
    Write-DebugMessage "  Total issues found: $($issues.Count)"
    Write-DebugMessage "  Critical: $criticalCount, Major: $majorCount, Minor: $minorCount"
    Write-DebugMessage "  Lines processed: $lineCount"

    return $issues
}

# Get list of relevant files to process
function Get-RelevantFile {
    Write-DebugMessage "Getting relevant files to process"

    $filesToProcess = Get-ChildItem -Path "." -Recurse -Include "*.sh", "*.ps1", "*.md" -File |
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

# Test if file has validation issues
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

# Test if an issue already exists for a file (open or recently closed)
function Test-IssueExist {
    param([string]$FilePath)

    Write-DebugMessage "Checking if issue exists for: $FilePath"

    try {
        # Calculate cutoff time for "recent" closed issues (configurable hours ago)
        $cutoffTime = (Get-Date).AddHours(-$RecentlyClosedHours).ToString("yyyy-MM-ddTHH:mm:ssZ")
        Write-DebugMessage "Checking for issues closed after: $cutoffTime ($RecentlyClosedHours hours ago)"

        # First check for open issues
        $openResult = & gh issue list --search "$FilePath" --state "open" --json "number,title,state,updatedAt" 2>$null

        if ($LASTEXITCODE -eq 0 -and $openResult -and $openResult.Trim()) {
            try {
                $openIssues = $openResult | ConvertFrom-Json
                # Smart matching: check for any of the possible title patterns for this file
                $fileName = Split-Path $FilePath -Leaf
                $expectedTitlePatterns = @(
                    "[CRITICAL] RUTOS Compatibility Fix: $fileName",
                    "[MAJOR] RUTOS Compatibility Fix: $fileName",
                    "[MINOR] RUTOS Compatibility Fix: $fileName"
                )

                $existingOpenIssue = $openIssues | Where-Object {
                    $currentTitle = $_.title
                    $expectedTitlePatterns | Where-Object { $currentTitle -eq $_ }
                } | Select-Object -First 1

                if ($existingOpenIssue) {
                    Write-DebugMessage "Found existing OPEN issue #$($existingOpenIssue.number) for file with exact title match: '$($existingOpenIssue.title)'"
                    return @{
                        Exists = $true
                        IssueNumber = $existingOpenIssue.number
                        Title = $existingOpenIssue.title
                        State = "open"
                        Reason = "Open issue already exists"
                    }
                }
            } catch {
                Write-DebugMessage "JSON parsing failed for open issues. Raw output: $openResult"
            }
        }

        # Then check for recently closed issues
        $closedResult = & gh issue list --search "$FilePath" --state "closed" --json "number,title,state,closedAt" 2>$null

        if ($LASTEXITCODE -eq 0 -and $closedResult -and $closedResult.Trim()) {
            try {
                $closedIssues = $closedResult | ConvertFrom-Json
                # Smart matching: check for any of the possible title patterns for this file
                $fileName = Split-Path $FilePath -Leaf
                $expectedTitlePatterns = @(
                    "[CRITICAL] RUTOS Compatibility Fix: $fileName",
                    "[MAJOR] RUTOS Compatibility Fix: $fileName",
                    "[MINOR] RUTOS Compatibility Fix: $fileName"
                )

                $recentlyClosedIssue = $closedIssues | Where-Object {
                    $currentTitle = $_.title
                    $matchesTitle = $expectedTitlePatterns | Where-Object { $currentTitle -eq $_ }
                    $withinTimeWindow = $_.closedAt -and ([DateTime]::Parse($_.closedAt) -gt [DateTime]::Parse($cutoffTime))

                    $matchesTitle -and $withinTimeWindow
                } | Select-Object -First 1

                if ($recentlyClosedIssue) {
                    $timeSinceClosed = [DateTime]::Now - [DateTime]::Parse($recentlyClosedIssue.closedAt)
                    $hoursAgo = [Math]::Round($timeSinceClosed.TotalHours, 1)
                    Write-DebugMessage "Found recently CLOSED issue #$($recentlyClosedIssue.number) for file (closed $hoursAgo hours ago, exact title match: '$($recentlyClosedIssue.title)')"
                    return @{
                        Exists = $true
                        IssueNumber = $recentlyClosedIssue.number
                        Title = $recentlyClosedIssue.title
                        State = "closed"
                        ClosedAt = $recentlyClosedIssue.closedAt
                        HoursAgo = $hoursAgo
                        Reason = "Recently closed issue (within $RecentlyClosedHours hours)"
                    }
                }
            } catch {
                Write-DebugMessage "JSON parsing failed for closed issues. Raw output: $closedResult"
            }
        }

        Write-DebugMessage "No existing or recently closed issues found for file"
        return @{ Exists = $false; Reason = "No conflicts found" }

    } catch {
        Add-CollectedError -ErrorMessage "Failed to check for existing issues: $($_.Exception.Message)" -FunctionName "Test-IssueExist" -Exception $_.Exception -Context "Checking for existing issue for $FilePath"
        return @{ Exists = $false; Reason = "Error during check" }
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
        return @{ ShouldProcess = $false; SkipReason = "LowPriority" }
    }

    # Apply minimum issues filter
    if ($Issues.Count -lt $MinIssuesPerFile) {
        Write-DebugMessage "File has only $($Issues.Count) issues, minimum is $MinIssuesPerFile - skipping"
        return @{ ShouldProcess = $false; SkipReason = "InsufficientIssues" }
    }

    # Check if already processed (unless forcing reprocessing)
    if ($global:IssueState.ContainsKey($FilePath) -and -not $ForceReprocessing) {
        $fileState = $global:IssueState[$FilePath]
        if ($fileState.Status -eq "Completed") {
            Write-DebugMessage "File already completed - skipping"
            return @{ ShouldProcess = $false; SkipReason = "AlreadyCompleted" }
        }
    }

    # Check if issue already exists (open or recently closed)
    $existingIssue = Test-IssueExist -FilePath $FilePath
    if ($existingIssue.Exists -and -not $ForceReprocessing) {
        if ($existingIssue.State -eq "open") {
            Write-DebugMessage "SKIPPING: Open issue #$($existingIssue.IssueNumber) already exists for this file"
            Write-Warning "   ⚠️  CONFLICT: Open issue #$($existingIssue.IssueNumber) already exists - $($existingIssue.Reason)"
            return @{ ShouldProcess = $false; SkipReason = "OpenIssue"; IssueNumber = $existingIssue.IssueNumber }
        } elseif ($existingIssue.State -eq "closed") {
            Write-DebugMessage "SKIPPING: Recently closed issue #$($existingIssue.IssueNumber) for this file (closed $($existingIssue.HoursAgo) hours ago)"
            Write-Information "   ⏰ RECENT: Issue #$($existingIssue.IssueNumber) was closed $($existingIssue.HoursAgo) hours ago - avoiding conflict" -InformationAction Continue
            return @{ ShouldProcess = $false; SkipReason = "RecentlyClosed"; IssueNumber = $existingIssue.IssueNumber; HoursAgo = $existingIssue.HoursAgo }
        }
    }

    Write-DebugMessage "File should be processed"
    return @{ ShouldProcess = $true; SkipReason = $null }
}

# Create GitHub issue with comprehensive content and intelligent labeling
function New-CopilotIssue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ScriptState]
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
            # Determine file type for appropriate labeling
            $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
            $isShellScript = $fileExtension -eq ".sh"
            $isPowerShellScript = $fileExtension -eq ".ps1"
            $isMarkdownFile = $fileExtension -eq ".md"

            # Base labels based on file type
            if ($isShellScript) {
                $intelligentLabels = @("rutos-compatibility", "posix-compliance", "busybox-compatibility", "shellcheck-issues")
            } elseif ($isPowerShellScript) {
                $intelligentLabels = @("powershell-quality", "psscriptanalyzer", "automation-enhancement", "powershell-best-practices")
            } elseif ($isMarkdownFile) {
                $intelligentLabels = @("documentation", "markdown-quality", "formatting")
            } else {
                $intelligentLabels = @("code-quality")
            }

            if ($criticalIssues.Count -gt 0) {
                $intelligentLabels += @("priority-critical", "auto-fix-needed")
                if ($isShellScript) { $intelligentLabels += "critical-busybox-incompatible" }
                if ($isPowerShellScript) { $intelligentLabels += "critical-powershell-issues" }
            } elseif ($majorIssues.Count -gt 0) {
                $intelligentLabels += @("priority-major", "manual-fix-needed")
            } else {
                $intelligentLabels += @("priority-minor", "manual-fix-needed")
            }

            # Add specific issue type labels
            if ($isShellScript) {
                if ($Issues | Where-Object { $_.Description -match "busybox" }) { $intelligentLabels += "busybox-fix" }
                if ($Issues | Where-Object { $_.Description -match "local" }) { $intelligentLabels += "critical-local-keyword" }
                if ($Issues | Where-Object { $_.Description -match "bash" }) { $intelligentLabels += "type-bash-shebang" }
            } elseif ($isPowerShellScript) {
                if ($Issues | Where-Object { $_.Description -match "PSAvoidUsingWriteHost" }) { $intelligentLabels += "output-handling" }
                if ($Issues | Where-Object { $_.Description -match "PSAvoidUsingInvokeExpression" }) { $intelligentLabels += "security-issue" }
                if ($Issues | Where-Object { $_.Description -match "PSUseApprovedVerbs" }) { $intelligentLabels += "naming-convention" }
            }
        }

        # Add copilot assignment label
        $intelligentLabels += "copilot-assigned"

        # Debug output for intelligent labeling
        if ($DebugMode) {
            Write-DebugMessage "🏷️  Intelligent Labeling System Results:"
            Write-DebugMessage "   Module Available: $intelligentLabelingAvailable"
            Write-DebugMessage "   Total Labels: $($intelligentLabels.Count)"
            Write-DebugMessage "   Priority Labels: $(($intelligentLabels | Where-Object { $_ -match '^priority-' }) -join ', ')"
            Write-DebugMessage "   Critical Labels: $(($intelligentLabels | Where-Object { $_ -match '^critical-' }) -join ', ')"
            Write-DebugMessage "   Type Labels: $(($intelligentLabels | Where-Object { $_ -match '^type-' }) -join ', ')"
            Write-DebugMessage "   All Labels: $($intelligentLabels -join ', ')"
        }

        # Priority emoji based on highest severity
        $priorityEmoji = if ($criticalIssues.Count -gt 0) { "[CRITICAL]" }
                         elseif ($majorIssues.Count -gt 0) { "[MAJOR]" }
                         else { "[MINOR]" }

        # Generate file type-specific issue title and objective
        $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        if ($fileExtension -eq ".sh") {
            $issueTitle = "$priorityEmoji RUTOS Compatibility Fix: $(Split-Path $FilePath -Leaf)"
            $objective = "Fix all RUTOS compatibility issues in this file to ensure it works correctly on RUTX50 hardware with busybox shell environment."
            $fileTypeDescription = "Shell Script - RUTOS Compatibility"
            $scopeRestriction = @"
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**DO NOT commit or alter any other files including:**
- ❌ Other shell scripts or configuration files
- ❌ Validation scripts or testing tools
- ❌ Documentation or README files
- ❌ GitHub workflow files
- ❌ Any files not explicitly identified in this issue

**✅ Focus exclusively on fixing the issues in the single target file listed above.**
"@
        } elseif ($fileExtension -eq ".ps1") {
            $issueTitle = "$priorityEmoji PowerShell Quality Enhancement: $(Split-Path $FilePath -Leaf)"
            $objective = "Fix all PowerShell quality issues in this file to ensure it follows best practices, security guidelines, and automation standards."
            $fileTypeDescription = "PowerShell Script - Automation Quality"
            $scopeRestriction = @"
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**DO NOT commit or alter any other files including:**
- ❌ Other PowerShell scripts or configuration files
- ❌ Validation scripts or testing tools
- ❌ Documentation or README files
- ❌ GitHub workflow files
- ❌ Any files not explicitly identified in this issue

**✅ Focus exclusively on fixing the PowerShell quality issues in the single target file listed above.**
"@
        } elseif ($fileExtension -eq ".md") {
            $issueTitle = "$priorityEmoji Documentation Quality Fix: $(Split-Path $FilePath -Leaf)"
            $objective = "Fix all documentation quality issues in this file to ensure proper formatting and clarity."
            $fileTypeDescription = "Markdown Documentation - Quality Enhancement"
            $scopeRestriction = @"
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**DO NOT commit or alter any other files including:**
- ❌ Other documentation or markdown files
- ❌ Code files or scripts
- ❌ Configuration files
- ❌ GitHub workflow files
- ❌ Any files not explicitly identified in this issue

**✅ Focus exclusively on fixing the documentation issues in the single target file listed above.**
"@
        } else {
            $issueTitle = "$priorityEmoji Code Quality Fix: $(Split-Path $FilePath -Leaf)"
            $objective = "Fix all code quality issues in this file."
            $fileTypeDescription = "Code File - Quality Enhancement"
            $scopeRestriction = @"
**🎯 ONLY MODIFY THE FILE SPECIFIED ABOVE: `$FilePath`**

**✅ Focus exclusively on fixing the issues in the single target file listed above.**
"@
        }

        # Generate enhanced issue body with file type-specific content
        $issueBody = @"
# $priorityEmoji $fileTypeDescription Issues Detected

## 📄 **Target File**
``$FilePath``

## 🎯 **Objective**
$objective

## ⚠️ **IMPORTANT: Scope Restriction**
$scopeRestriction

## 🚨 **Issues Found**

### 📊 **Issue Summary**
- 🔴 **Critical Issues**: $($criticalIssues.Count) (Must fix - will cause failures)
- 🟡 **Major Issues**: $($majorIssues.Count) (Should fix - may cause problems)
- 🔵 **Minor Issues**: $($minorIssues.Count) (Best practices - improve if possible)

**Total Issues**: $($Issues.Count)

"@

        # Add critical issues section
        if ($criticalIssues.Count -gt 0) {
            $criticalDescription = if ($fileExtension -eq ".sh") {
                "These issues will cause failures on RUTX50 hardware and must be fixed:"
            } elseif ($fileExtension -eq ".ps1") {
                "These issues represent critical PowerShell problems that must be fixed:"
            } else {
                "These are critical issues that must be fixed:"
            }

            $issueBody += @"

### 🔴 **CRITICAL ISSUES** (Must Fix Immediately)

$criticalDescription

"@
            foreach ($issue in $criticalIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }

        # Add major issues section
        if ($majorIssues.Count -gt 0) {
            $majorDescription = if ($fileExtension -eq ".sh") {
                "These issues may cause problems in the busybox environment:"
            } elseif ($fileExtension -eq ".ps1") {
                "These issues may cause PowerShell runtime problems:"
            } else {
                "These issues should be fixed:"
            }

            $issueBody += @"

### 🟡 **MAJOR ISSUES** (Should Fix)

$majorDescription

"@
            foreach ($issue in $majorIssues) {
                $issueBody += "- **Line $($issue.Line)**: $($issue.Description)`n"
            }
        }

        # Add minor issues section
        if ($minorIssues.Count -gt 0) {
            $minorDescription = if ($fileExtension -eq ".sh") {
                "These issues represent best practices and portability improvements:"
            } elseif ($fileExtension -eq ".ps1") {
                "These issues represent PowerShell best practices:"
            } else {
                "These issues represent best practices:"
            }

            $issueBody += @"

### 🔵 **MINOR ISSUES** (Best Practices)

$minorDescription

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

"@

        # Add file type-specific fix guidelines
        if ($fileExtension -eq ".sh") {
            $issueBody += @"
### **RUTOS Compatibility Rules**
1. **POSIX Shell Only**: Use `#!/bin/sh` instead of `#!/bin/bash`
2. **No Bash Arrays**: Use space-separated strings or multiple variables
3. **Use `[ ]` not `[[ ]]`**: Busybox doesn't support `[[ ]]`
4. **No `local` keyword**: All variables are global in busybox
5. **Use `printf` not `echo -e`**: More portable and consistent
6. **Source with `.` not `source`**: Use `. script.sh` instead of `source script.sh`
7. **No `function()` syntax**: Use `function_name() {` format
8. **Proper printf format**: Avoid variables in format strings (SC2059)
"@
        } elseif ($fileExtension -eq ".ps1") {
            $issueBody += @"
### **PowerShell Best Practices**
1. **Use Write-Output**: Prefer `Write-Output` over `Write-Host` for pipeline compatibility
2. **Avoid Invoke-Expression**: Use direct calls instead of `Invoke-Expression` for security
3. **Use Approved Verbs**: Follow PowerShell verb naming conventions (Get-, Set-, New-, etc.)
4. **Parameter Validation**: Use proper parameter attributes for input validation
5. **Error Handling**: Implement proper try-catch blocks and error handling
6. **Security**: Avoid hardcoded credentials and sensitive information
7. **PSScriptAnalyzer**: Follow all PSScriptAnalyzer recommendations
8. **Help Documentation**: Include proper comment-based help for functions
"@
        } elseif ($fileExtension -eq ".md") {
            $issueBody += @"
### **Markdown Quality Guidelines**
1. **Consistent Formatting**: Use consistent heading levels and formatting
2. **Link Validation**: Ensure all links are valid and properly formatted
3. **Table Formatting**: Use proper table syntax with aligned columns
4. **Code Blocks**: Use appropriate language tags for syntax highlighting
5. **Accessibility**: Include alt text for images and descriptive link text
6. **Structure**: Maintain logical document structure and flow
"@
        } else {
            $issueBody += @"
### **General Code Quality Guidelines**
1. **Consistency**: Maintain consistent formatting and style
2. **Readability**: Write clear, maintainable code
3. **Best Practices**: Follow language-specific best practices
4. **Documentation**: Include appropriate comments and documentation
"@
        }

        $issueBody += @"

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

        # Try to create the issue with automatic label creation retry
        $issueResult = New-GitHubIssueWithLabelHandling -Title $issueTitle -Body $issueBody -Labels $labels -FilePath $FilePath

        if ($issueResult.Success) {
            # Update state tracking
            $global:IssueState[$FilePath] = @{
                Status = "Created"
                IssueNumber = $issueResult.IssueNumber
                CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                IssueCount = $Issues.Count
            }

            # Assign Copilot to the issue
            Start-Sleep -Seconds 2
            $assignResult = Set-CopilotAssignment -IssueNumber $issueResult.IssueNumber

            if ($assignResult.Success) {
                Write-SuccessMessage "Assigned Copilot to issue #$($issueResult.IssueNumber)"
                $global:IssueState[$FilePath].Status = "Assigned"
            }

            return @{
                Success = $true
                IssueNumber = $issueResult.IssueNumber
                FilePath = $FilePath
            }
        } else {
            return @{
                Success = $false
                Error = $issueResult.Error
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

# Create GitHub issue with automatic label creation and retry capability
function New-GitHubIssueWithLabelHandling {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ScriptState]
        [string]$Title,
        [string]$Body,
        [array]$Labels,
        [string]$FilePath
    )

    Write-DebugMessage "Creating GitHub issue with automatic label handling"

    try {
        # Create temporary file for issue body
        $tempFile = [System.IO.Path]::GetTempFileName()
        $Body | Out-File -FilePath $tempFile -Encoding UTF8

        # Build GitHub CLI arguments
        $arguments = @('issue', 'create', '-t', $Title, '-F', $tempFile)
        foreach ($label in $Labels) {
            $arguments += @('-l', $label)
        }

        Write-DebugMessage "Executing: gh $($arguments -join ' ')"

        if ($PSCmdlet.ShouldProcess("GitHub", "Create issue '$Title'")) {
            # Execute GitHub CLI command
            $result = & gh $arguments 2>&1
            $exitCode = $LASTEXITCODE

            # Clean up temp file
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

            if ($exitCode -eq 0) {
                # Extract issue number from result
                $issueNumber = ""
                if ($result -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                    $issueNumber = $Matches[1]
            }

            Write-SuccessMessage "Created issue #$issueNumber for: $FilePath"
            return @{ Success = $true; IssueNumber = $issueNumber }
        } else {
            # Check if the error is due to missing labels
            $errorText = $result -join " "
            if ($errorText -match "could not add label: '([^']+)' not found") {
                $missingLabels = @()

                # Extract all missing labels from error message
                $errorLines = $result | Where-Object { $_ -match "could not add label: '([^']+)' not found" }
                foreach ($errorLine in $errorLines) {
                    if ($errorLine -match "could not add label: '([^']+)' not found") {
                        $missingLabels += $Matches[1]
                    }
                }

                Write-WarningMessage "Found $($missingLabels.Count) missing labels: $($missingLabels -join ', ')"

                # Create missing labels automatically
                $createdLabels = @()
                foreach ($missingLabel in $missingLabels) {
                    $labelResult = New-MissingGitHubLabel -LabelName $missingLabel
                    if ($labelResult.Success) {
                        $createdLabels += $missingLabel
                        Write-SuccessMessage "Created missing label: $missingLabel"
                    } else {
                        Write-ErrorMessage "Failed to create label '$missingLabel': $($labelResult.Error)"
                    }
                }

                # Retry issue creation if we successfully created any labels
                if ($createdLabels.Count -gt 0) {
                    Write-InfoMessage "Retrying issue creation with newly created labels..."
                    Start-Sleep -Seconds 2

                    # Retry with the same arguments
                    $tempFile2 = [System.IO.Path]::GetTempFileName()
                    $Body | Out-File -FilePath $tempFile2 -Encoding UTF8

                    # Update the temp file argument
                    $retryArguments = $arguments.Clone()
                    $retryArguments[5] = $tempFile2  # Replace the temp file path

                    $retryResult = & gh $retryArguments 2>&1
                    $retryExitCode = $LASTEXITCODE

                    Remove-Item $tempFile2 -Force -ErrorAction SilentlyContinue

                    if ($retryExitCode -eq 0) {
                        # Extract issue number from retry result
                        $issueNumber = ""
                        if ($retryResult -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                            $issueNumber = $Matches[1]
                        }

                        Write-SuccessMessage "✅ Retry successful! Created issue #$issueNumber for: $FilePath (with $($createdLabels.Count) auto-created labels)"
                        return @{ Success = $true; IssueNumber = $issueNumber; CreatedLabels = $createdLabels }
                    } else {
                        Write-ErrorMessage "Retry failed even after creating labels: $retryResult"
                        return @{ Success = $false; Error = "Retry failed: $retryResult" }
                    }
                } else {
                    Write-ErrorMessage "Could not create any missing labels"
                    return @{ Success = $false; Error = "Could not create missing labels: $errorText" }
                }
            } else {
                # Different error, not related to missing labels
                Write-ErrorMessage "GitHub CLI command failed: $errorText"
                return @{ Success = $false; Error = "GitHub CLI failed: $errorText" }
            }
        }

    } catch {
        # Clean up temp file on exception
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }

        Add-CollectedError -ErrorMessage "Error in label handling: $($_.Exception.Message)" -FunctionName "New-GitHubIssueWithLabelHandling" -Exception $_.Exception -Context "Creating issue with label handling for $FilePath"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Create a missing GitHub label with intelligent color and description assignment
function New-MissingGitHubLabel {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LabelName)

    Write-DebugMessage "Creating missing GitHub label: $LabelName"

    try {
        # Assign intelligent colors and descriptions based on label patterns
        $labelColor = "6c757d"  # Default gray
        $labelDescription = "Auto-generated label"

        # Priority labels
        if ($LabelName -match "^priority-critical") {
            $labelColor = "b60205"  # Red
            $labelDescription = "Critical priority issues requiring immediate attention"
        } elseif ($LabelName -match "^priority-major|^priority-high") {
            $labelColor = "d93f0b"  # Orange-red
            $labelDescription = "High priority issues that should be addressed soon"
        } elseif ($LabelName -match "^priority-medium") {
            $labelColor = "fbca04"  # Yellow
            $labelDescription = "Medium priority issues"
        } elseif ($LabelName -match "^priority-minor|^priority-low") {
            $labelColor = "0e8a16"  # Green
            $labelDescription = "Low priority issues"
        }

        # Critical system labels
        elseif ($LabelName -match "^critical-") {
            $labelColor = "b60205"  # Red
            $labelDescription = "Critical system compatibility issues"
        }

        # Type-specific labels
        elseif ($LabelName -match "^type-") {
            $labelColor = "fef2c0"  # Light yellow
            $labelDescription = "Specific code pattern or syntax issues"
        }

        # Content-related labels
        elseif ($LabelName -match "^content-") {
            $labelColor = "1f77b4"  # Blue
            $labelDescription = "Content quality and accuracy issues"
        }

        # Enhancement and suggestion labels
        elseif ($LabelName -match "suggestion|recommendation|feature-request") {
            $labelColor = "a2eeef"  # Light blue
            $labelDescription = "Enhancement suggestions and feature requests"
        }

        # Automation and workflow labels
        elseif ($LabelName -match "automated|autonomous|monitoring|workflow") {
            $labelColor = "1f883d"  # Green
            $labelDescription = "Automated processes and workflow management"
        }

        # Fix-related labels
        elseif ($LabelName -match "fix-|auto-fix|manual-fix") {
            $labelColor = "7057ff"  # Purple
            $labelDescription = "Issue resolution and fix management"
        }

        # Scope and validation labels
        elseif ($LabelName -match "scope-|validation-") {
            $labelColor = "0052cc"  # Blue
            $labelDescription = "Scope management and validation processes"
        }

        # Copilot-related labels
        elseif ($LabelName -match "copilot") {
            $labelColor = "6f42c1"  # Purple
            $labelDescription = "GitHub Copilot automated fixes and assignments"
        }

        # Create the label using GitHub CLI
        if ($PSCmdlet.ShouldProcess("GitHub", "Create label '$LabelName'")) {
            $createResult = & gh label create $LabelName --description $labelDescription --color $labelColor 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-DebugMessage "Successfully created label '$LabelName' with color #$labelColor"
                return @{ Success = $true; LabelName = $LabelName; Color = $labelColor; Description = $labelDescription }
            } else {
                Write-DebugMessage "Failed to create label '$LabelName': $createResult"
                return @{ Success = $false; Error = $createResult }
            }
        } else {
            return @{ Success = $false; Error = "Operation cancelled by user" }
        }

    } catch {
        Add-CollectedError -ErrorMessage "Error creating label '$LabelName': $($_.Exception.Message)" -FunctionName "New-MissingGitHubLabel" -Exception $_.Exception -Context "Creating missing GitHub label"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Assign Copilot to an issue
function Set-CopilotAssignment {
    [CmdletBinding(SupportsShouldProcess)]
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
    [CmdletBinding(SupportsShouldProcess)]
    
    Write-InfoMessage "🚀 Starting Optimized RUTOS Copilot Issue Creation System v$SCRIPT_VERSION"

    # Load state
    Load-IssueState | Out-Null

    # Get target files to process
    if ($TargetFile) {
        Write-InfoMessage "🎯 Processing single target file: $TargetFile"
        $filesToProcess = @($TargetFile)
    } else {
        Write-StepMessage "📂 Scanning repository for shell scripts, PowerShell scripts, and markdown files..."
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
    $filesSkippedOpenIssue = 0
    $filesSkippedRecentlyClosed = 0
    $filesSkippedLowPriority = 0
    $filesSkippedOther = 0

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
            $shouldProcessResult = Test-ShouldProcessFile -FilePath $file -Issues $validationResult.Issues
            if (-not $shouldProcessResult.ShouldProcess) {
                Write-DebugMessage "⏭️  Skipping file based on processing criteria: $file (Reason: $($shouldProcessResult.SkipReason))"
                $filesSkipped++

                # Track specific skip reasons
                switch ($shouldProcessResult.SkipReason) {
                    "OpenIssue" {
                        $filesSkippedOpenIssue++
                        Write-Information "   📋 Skipped: Open issue #$($shouldProcessResult.IssueNumber) exists" -InformationAction Continue
                    }
                    "RecentlyClosed" {
                        $filesSkippedRecentlyClosed++
                        Write-Information "   ⏰ Skipped: Recently closed issue #$($shouldProcessResult.IssueNumber) ($($shouldProcessResult.HoursAgo)h ago)" -InformationAction Continue
                    }
                    "LowPriority" {
                        $filesSkippedLowPriority++
                        Write-Information "   🎯 Skipped: Priority filter ($PriorityFilter)" -InformationAction Continue
                    }
                    default {
                        $filesSkippedOther++
                        Write-Information "   ℹ️  Skipped: $($shouldProcessResult.SkipReason)" -InformationAction Continue
                    }
                }
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
    Write-Output -InputObject ("`n" + ("=" * 80))
    Write-Output -InputObject "📊 PROCESSING SUMMARY"
    Write-Output -InputObject ("=" * 80)

    Write-InfoMessage "📁 Files Processed: $filesProcessed"
    Write-InfoMessage "⏭️  Files Skipped: $filesSkipped"
    Write-InfoMessage "📝 Issues Created: $issuesCreated"
    Write-InfoMessage "🎯 Maximum Issues: $MaxIssues"

    # Show detailed skip breakdown if any files were skipped
    if ($filesSkipped -gt 0) {
        Write-Output "`n📊 Skip Breakdown:"
        if ($filesSkippedOpenIssue -gt 0) {
            Write-Output "   ⚠️  Open Issues: $filesSkippedOpenIssue files (avoiding conflicts)"
        }
        if ($filesSkippedRecentlyClosed -gt 0) {
            Write-Output "   ⏰ Recently Closed: $filesSkippedRecentlyClosed files (within $RecentlyClosedHours hours)"
        }
        if ($filesSkippedLowPriority -gt 0) {
            Write-Output "   🎯 Low Priority: $filesSkippedLowPriority files (filter: $PriorityFilter)"
        }
        if ($filesSkippedOther -gt 0) {
            Write-Output "   ℹ️  Other: $filesSkippedOther files (various reasons)"
        }
    }

    if ($script:CreatedIssues.Count -gt 0) {
        Write-Output "`n📋 Created Issues:"
        foreach ($issue in $script:CreatedIssues) {
            Write-Output "   #$($issue.IssueNumber) - $($issue.FilePath) ($($issue.IssueCount) issues)"
        }
    }

    # Show any collected errors
    if ($global:CollectedErrors.Count -gt 0) {
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

    if ($DebugMode) {
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
        $null = gh auth status 2>&1
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
        Write-Warning "Press Ctrl+C to cancel or wait 5 seconds to continue..."
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
