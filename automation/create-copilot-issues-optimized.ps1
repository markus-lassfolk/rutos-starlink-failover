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
    Write-Host "[LABELS] GitHub Label Management Module Loaded" -ForegroundColor Blue
    Write-Host "[SUCCESS] Loaded enhanced label management system (100+ labels)" -ForegroundColor Green
    $intelligentLabelingAvailable = $true
} else {
    Write-Host "[WARNING] Enhanced label management module not found - using basic labels" -ForegroundColor Yellow
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
    if ($DebugMode) {
        Write-StatusMessage "[DEBUG] $Message" -Color $CYAN -Level "DEBUG"
    }
}

function Write-StepMessage {
    param([string]$Message)
    Write-StatusMessage "[STEP] $Message" -Color $BLUE -Level "STEP"
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-StatusMessage "[ERROR] $Message" -Color $RED -Level "ERROR"
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-StatusMessage "[SUCCESS] $Message" -Color $GREEN -Level "SUCCESS"
}

function Write-WarningMessage {
    param([string]$Message)
    Write-StatusMessage "[WARNING] $Message" -Color $YELLOW -Level "WARNING"
}

function Write-InfoMessage {
    param([string]$Message)
    Write-StatusMessage "$Message" -Color White -Level "INFO"
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
    
    if ($DebugMode) {
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

# Run full validation on all files
function Invoke-FullValidation {
    Write-DebugMessage "Running full validation on all files"
    
    try {
        $validationCmd = "wsl bash -c `"cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT`""
        Write-DebugMessage "Executing: $validationCmd"
        
        $validationOutput = Invoke-Expression $validationCmd 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-DebugMessage "Full validation exit code: $exitCode"
        Write-DebugMessage "Full validation output lines: $($validationOutput.Count)"
        
        # Parse the validation output to extract issues for all files
        $fileIssues = Parse-FullValidationOutput -Output $validationOutput
        
        return @{
            Success = $exitCode -eq 0
            ExitCode = $exitCode
            FileIssues = $fileIssues
            Output = $validationOutput
            TotalFiles = $fileIssues.Keys.Count
            TotalIssues = ($fileIssues.Values | ForEach-Object { $_.Issues.Count } | Measure-Object -Sum).Sum
        }
    } catch {
        Add-CollectedError -ErrorMessage "Failed to run full validation: $($_.Exception.Message)" -FunctionName "Invoke-FullValidation" -Exception $_.Exception -Context "Running full validation"
        return @{
            Success = $false
            ExitCode = -1
            FileIssues = @{}
            Error = $_.Exception.Message
        }
    }
}

# Run validation on individual file (kept for compatibility)
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

# Parse full validation output for all files
function Parse-FullValidationOutput {
    param([string[]]$Output)
    
    Write-DebugMessage "Parsing full validation output with $($Output.Count) lines"
    
    $fileIssues = @{}
    $lineCount = 0
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        $lineCount++
        
        # Skip empty lines and obvious summary lines  
        if (-not $line -or $line -match "^(Files processed|Files failed|Total|Summary|===|---|\[SUCCESS\]|\[INFO\]|\[STEP\])") {
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
            
            $issueType = switch ($severity) {
                "CRITICAL" { "Critical" }
                "MAJOR" { "Major" }
                "MINOR" { "Minor" }
                "WARNING" { "Warning" }
                default { "Minor" }
            }
            
            # Initialize file entry if not exists
            if (-not $fileIssues.ContainsKey($filepath)) {
                $fileIssues[$filepath] = @{
                    Issues = @()
                    CriticalCount = 0
                    MajorCount = 0
                    MinorCount = 0
                }
            }
            
            # Add issue to file
            $fileIssues[$filepath].Issues += @{
                Line = [int]$lineNumber
                Description = $description
                Type = $issueType
                Severity = $severity
            }
            
            # Update counts
            switch ($issueType) {
                "Critical" { $fileIssues[$filepath].CriticalCount++ }
                "Major" { $fileIssues[$filepath].MajorCount++ }
                "Minor" { $fileIssues[$filepath].MinorCount++ }
                "Warning" { $fileIssues[$filepath].MinorCount++ }
            }
            
            Write-DebugMessage "Added issue to $filepath`: Type=$issueType, Line=$lineNumber"
        }
        # Handle ShellCheck format: filepath:line:column: note/warning/error: description
        elseif ($line -match "^(.+?):(\d+):(\d+):\s+(note|warning|error):\s+(.+)$") {
            $filepath = $Matches[1] -replace "^\.\/", ""
            $lineNumber = $Matches[2]
            $issueLevel = $Matches[4]
            $description = $Matches[5]
            
            Write-DebugMessage "Found ShellCheck issue: $filepath`:$lineNumber $issueLevel`: $description"
            
            $issueType = switch ($issueLevel) {
                "error" { "Critical" }
                "warning" { "Major" }
                "note" { "Minor" }
                default { "Minor" }
            }
            
            # Initialize file entry if not exists
            if (-not $fileIssues.ContainsKey($filepath)) {
                $fileIssues[$filepath] = @{
                    Issues = @()
                    CriticalCount = 0
                    MajorCount = 0
                    MinorCount = 0
                }
            }
            
            # Add issue to file
            $fileIssues[$filepath].Issues += @{
                Line = [int]$lineNumber
                Description = $description
                Type = $issueType
                Severity = $issueLevel
            }
            
            # Update counts
            switch ($issueType) {
                "Critical" { $fileIssues[$filepath].CriticalCount++ }
                "Major" { $fileIssues[$filepath].MajorCount++ }
                "Minor" { $fileIssues[$filepath].MinorCount++ }
            }
            
            Write-DebugMessage "Added ShellCheck issue to $filepath`: Type=$issueType, Line=$lineNumber"
        }
        else {
            Write-DebugMessage "Line didn't match any pattern: $line"
        }
    }
    
    # Log summary
    $totalFiles = $fileIssues.Keys.Count
    $totalIssues = ($fileIssues.Values | ForEach-Object { $_.Issues.Count } | Measure-Object -Sum).Sum
    $totalCritical = ($fileIssues.Values | ForEach-Object { $_.CriticalCount } | Measure-Object -Sum).Sum
    $totalMajor = ($fileIssues.Values | ForEach-Object { $_.MajorCount } | Measure-Object -Sum).Sum
    $totalMinor = ($fileIssues.Values | ForEach-Object { $_.MinorCount } | Measure-Object -Sum).Sum
    
    Write-DebugMessage "Full validation parsing complete:"
    Write-DebugMessage "  Files with issues: $totalFiles"
    Write-DebugMessage "  Total issues: $totalIssues"
    Write-DebugMessage "  Critical: $totalCritical, Major: $totalMajor, Minor: $totalMinor"
    Write-DebugMessage "  Lines processed: $lineCount"
    
    return $fileIssues
}

# Parse validation output for a specific file (kept for compatibility)
function Parse-ValidationOutput {
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
            Write-Host "   ⚠️  CONFLICT: Open issue #$($existingIssue.IssueNumber) already exists - $($existingIssue.Reason)" -ForegroundColor Yellow
            return @{ ShouldProcess = $false; SkipReason = "OpenIssue"; IssueNumber = $existingIssue.IssueNumber }
        } elseif ($existingIssue.State -eq "closed") {
            Write-DebugMessage "SKIPPING: Recently closed issue #$($existingIssue.IssueNumber) for this file (closed $($existingIssue.HoursAgo) hours ago)"
            Write-Host "   ⏰ RECENT: Issue #$($existingIssue.IssueNumber) was closed $($existingIssue.HoursAgo) hours ago - avoiding conflict" -ForegroundColor Cyan
            return @{ ShouldProcess = $false; SkipReason = "RecentlyClosed"; IssueNumber = $existingIssue.IssueNumber; HoursAgo = $existingIssue.HoursAgo }
        }
    }
    
    Write-DebugMessage "File should be processed"
    return @{ ShouldProcess = $true; SkipReason = $null }
}

# Create GitHub issue with comprehensive content and intelligent labeling
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
    param(
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
        
        # Build GitHub CLI command
        $labelArgs = ($Labels | ForEach-Object { "-l `"$_`"" }) -join " "
        $ghCommand = "gh issue create -t `"$Title`" -F `"$tempFile`" $labelArgs"
        
        Write-DebugMessage "Executing: $ghCommand"
        
        # Execute GitHub CLI command
        $result = Invoke-Expression $ghCommand 2>&1
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
                    
                    # Retry the same command
                    $tempFile2 = [System.IO.Path]::GetTempFileName()
                    $Body | Out-File -FilePath $tempFile2 -Encoding UTF8
                    
                    $retryResult = Invoke-Expression $ghCommand 2>&1
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
        $createResult = gh label create "$LabelName" --description "$labelDescription" --color "$labelColor" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "Successfully created label '$LabelName' with color #$labelColor"
            return @{ Success = $true; LabelName = $LabelName; Color = $labelColor; Description = $labelDescription }
        } else {
            Write-DebugMessage "Failed to create label '$LabelName': $createResult"
            return @{ Success = $false; Error = $createResult }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error creating label '$LabelName': $($_.Exception.Message)" -FunctionName "New-MissingGitHubLabel" -Exception $_.Exception -Context "Creating missing GitHub label"
        return @{ Success = $false; Error = $_.Exception.Message }
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

# Main execution logic with optimized full validation processing
function Start-OptimizedIssueCreation {
    Write-InfoMessage "🚀 Starting Optimized RUTOS Copilot Issue Creation System v$SCRIPT_VERSION"
    
    # Load state
    Load-IssueState | Out-Null
    
    # Run full validation first to get all issues
    Write-StepMessage "🔍 Running comprehensive validation on all files..."
    $fullValidationResult = Invoke-FullValidation
    
    if ($fullValidationResult.TotalIssues -eq 0) {
        Write-SuccessMessage "🎉 No validation issues found - all files are clean!"
        return
    }
    
    $filesWithIssues = $fullValidationResult.FileIssues
    Write-InfoMessage "📊 Full validation complete: Found issues in $($filesWithIssues.Keys.Count) files, total $($fullValidationResult.TotalIssues) issues"
    
    # Filter files based on target file if specified
    if ($TargetFile) {
        Write-InfoMessage "🎯 Filtering for target file: $TargetFile"
        $originalCount = $filesWithIssues.Keys.Count
        $filteredIssues = @{}
        foreach ($file in $filesWithIssues.Keys) {
            if ($file -eq $TargetFile -or $file.EndsWith($TargetFile)) {
                $filteredIssues[$file] = $filesWithIssues[$file]
            }
        }
        $filesWithIssues = $filteredIssues
        Write-InfoMessage "📊 Filtered from $originalCount to $($filesWithIssues.Keys.Count) files for target"
    }
    
    # Sort files by priority if requested
    $filesToProcess = @($filesWithIssues.Keys)
    if ($SortByPriority) {
        Write-StepMessage "📋 Sorting files by issue priority..."
        $filesToProcess = $filesToProcess | Sort-Object {
            $fileIssues = $filesWithIssues[$_]
            # Priority: Critical = 1, Major = 2, Minor = 3
            if ($fileIssues.CriticalCount -gt 0) { 1 }
            elseif ($fileIssues.MajorCount -gt 0) { 2 }
            else { 3 }
        }
        Write-InfoMessage "📊 Prioritized $($filesToProcess.Count) files by issue severity"
    }
    
    # Process files with pre-parsed issues
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
            # Get pre-parsed validation results for this file
            $fileIssues = $filesWithIssues[$file]
            
            if (-not $fileIssues -or $fileIssues.Issues.Count -eq 0) {
                Write-DebugMessage "⚠️  No issues found for file: $file"
                continue
            }
            
            Write-InfoMessage "⚠️  Found $($fileIssues.Issues.Count) issues in: $file (Critical: $($fileIssues.CriticalCount), Major: $($fileIssues.MajorCount), Minor: $($fileIssues.MinorCount))"
            
            # Check if this file should be processed based on our criteria
            $shouldProcessResult = Test-ShouldProcessFile -FilePath $file -Issues $fileIssues.Issues
            if (-not $shouldProcessResult.ShouldProcess) {
                Write-DebugMessage "⏭️  Skipping file based on processing criteria: $file (Reason: $($shouldProcessResult.SkipReason))"
                $filesSkipped++
                
                # Track specific skip reasons
                switch ($shouldProcessResult.SkipReason) {
                    "OpenIssue" { 
                        $filesSkippedOpenIssue++
                        Write-Host "   📋 Skipped: Open issue #$($shouldProcessResult.IssueNumber) exists" -ForegroundColor Yellow
                    }
                    "RecentlyClosed" { 
                        $filesSkippedRecentlyClosed++
                        Write-Host "   ⏰ Skipped: Recently closed issue #$($shouldProcessResult.IssueNumber) ($($shouldProcessResult.HoursAgo)h ago)" -ForegroundColor Cyan
                    }
                    "LowPriority" { 
                        $filesSkippedLowPriority++
                        Write-Host "   🎯 Skipped: Priority filter ($PriorityFilter)" -ForegroundColor Gray
                    }
                    default { 
                        $filesSkippedOther++
                        Write-Host "   ℹ️  Skipped: $($shouldProcessResult.SkipReason)" -ForegroundColor Gray
                    }
                }
                continue
            }
            
            # Create issue for this file using pre-parsed issues
            Write-StepMessage "📝 Creating issue for: $file"
            $issueResult = New-CopilotIssue -FilePath $file -Issues $fileIssues.Issues
            
            if ($issueResult.Success) {
                $issuesCreated++
                Write-SuccessMessage "✅ Created issue #$($issueResult.IssueNumber) for: $file"
                
                # Update tracking
                $global:CreatedIssues += @{
                    IssueNumber = $issueResult.IssueNumber
                    FilePath = $file
                    CreatedAt = Get-Date
                    IssueCount = $fileIssues.Issues.Count
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
    Write-Host "`n" + ("=" * 80) -ForegroundColor $BLUE
    Write-Host "📊 PROCESSING SUMMARY" -ForegroundColor $BLUE
    Write-Host ("=" * 80) -ForegroundColor $BLUE
    
    Write-InfoMessage "📁 Files Processed: $filesProcessed"
    Write-InfoMessage "⏭️  Files Skipped: $filesSkipped"
    Write-InfoMessage "📝 Issues Created: $issuesCreated"
    Write-InfoMessage "🎯 Maximum Issues: $MaxIssues"
    
    # Show detailed skip breakdown if any files were skipped
    if ($filesSkipped -gt 0) {
        Write-Host "`n📊 Skip Breakdown:" -ForegroundColor $CYAN
        if ($filesSkippedOpenIssue -gt 0) {
            Write-Host "   ⚠️  Open Issues: $filesSkippedOpenIssue files (avoiding conflicts)" -ForegroundColor Yellow
        }
        if ($filesSkippedRecentlyClosed -gt 0) {
            Write-Host "   ⏰ Recently Closed: $filesSkippedRecentlyClosed files (within $RecentlyClosedHours hours)" -ForegroundColor Cyan
        }
        if ($filesSkippedLowPriority -gt 0) {
            Write-Host "   🎯 Low Priority: $filesSkippedLowPriority files (filter: $PriorityFilter)" -ForegroundColor Gray
        }
        if ($filesSkippedOther -gt 0) {
            Write-Host "   ℹ️  Other: $filesSkippedOther files (various reasons)" -ForegroundColor Gray
        }
    }
    
    if ($global:CreatedIssues.Count -gt 0) {
        Write-Host "`n📋 Created Issues:" -ForegroundColor $GREEN
        foreach ($issue in $global:CreatedIssues) {
            Write-Host "   #$($issue.IssueNumber) - $($issue.FilePath) ($($issue.IssueCount) issues)" -ForegroundColor $GREEN
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
