#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Autonomous RUTOS Copilot Issue Creation and Management System
    
.DESCRIPTION
    This script implements a fully autonomous system that:
    1. Validates all files in the repository using pre-commit-validation.ps1
    2. Creates targeted issues for files with validation problems
    3. Assigns Copilot to automatically fix the issues
    4. Monitors progress and handles edge cases
    5. Manages the complete workflow from validation to merge
    
.PARAMETER TestMode
    Run in test mode without creating actual issues
    
.PARAMETER DryRun
    Show what would be done without making changes (DEFAULT: enabled for safety)
    
.PARAMETER MaxIssuesPerRun
    Maximum number of issues to create in a single run (DEFAULT: 3 for safety)
    
.PARAMETER Production
    Enable production mode (disables DryRun safety default)
    
.PARAMETER SkipValidation
    Skip the initial validation step (for testing)
    
.PARAMETER DebugMode
    Enable detailed debug logging
    
.PARAMETER ForceReprocessing
    Force reprocessing of previously handled files
    
.PARAMETER TargetFile
    Process only a specific file (for testing)
    
.PARAMETER PriorityFilter
    Filter issues by priority: All, Critical, Major, Minor (default: All)
    
.PARAMETER MinIssuesPerFile
    Skip files with fewer than this many issues (default: 1)
    
.PARAMETER SortByPriority
    Process files with critical issues first, then major, then minor
    
.EXAMPLE
    .\create-copilot-issues.ps1
    Run in safe mode (DryRun enabled by default, max 3 issues)
    
.EXAMPLE
    .\create-copilot-issues.ps1 -Production
    Run in production mode with actual issue creation
    
.EXAMPLE
    .\create-copilot-issues.ps1 -TestMode
    Run in test mode to see what issues would be created
    
.EXAMPLE
    .\create-copilot-issues.ps1 -DryRun -DebugMode
    Show detailed information about what would be done (explicit dry run)
    
.EXAMPLE
    .\create-copilot-issues.ps1 -Production -MaxIssuesPerRun 5
    Production mode with maximum 5 issues per run
    
.EXAMPLE
    .\create-copilot-issues.ps1 -PriorityFilter Critical -MaxIssuesPerRun 2
    Create maximum 2 issues, only for files with critical issues (dry run by default)
    
.EXAMPLE
    .\create-copilot-issues.ps1 -SortByPriority -MinIssuesPerFile 3
    Process files with 3+ issues, prioritizing critical issues first (dry run by default)
    
.EXAMPLE
    .\create-copilot-issues.ps1 -TargetFile "scripts/validate-config.sh"
    Process only the specified file (dry run by default)
#>

[CmdletBinding()]
param(
    [switch]$TestMode,
    [switch]$DryRun,                   # Dry run mode for safety (enabled by default unless -Production specified)
    [int]$MaxIssuesPerRun = 3,         # DEFAULT: Maximum 3 issues for testing
    [switch]$SkipValidation,
    [switch]$DebugMode,
    [switch]$ForceReprocessing,
    [string]$TargetFile = "",
    [string]$PriorityFilter = "All",  # All, Critical, Major, Minor
    [int]$MinIssuesPerFile = 1,       # Skip files with fewer issues
    [switch]$SortByPriority,          # Process critical issues first
    [switch]$Production               # Enable production mode (disables DryRun)
)

# Set DryRun default behavior - enabled by default for safety unless Production mode is specified
if ($Production) {
    $DryRun = $false
    Write-Information "🚀 Production mode enabled - DryRun disabled" -InformationAction Continue
} elseif (-not $PSBoundParameters.ContainsKey('DryRun')) {
    # DryRun not explicitly specified, enable by default for safety
    $DryRun = $true
    Write-Information "🧪 Safety mode - DryRun enabled by default" -InformationAction Continue
    Write-Information "   To run in production mode, use: -Production" -InformationAction Continue
} else {
    # DryRun was explicitly specified by user
    if ($DryRun) {
        Write-Information "🧪 Dry run mode explicitly enabled" -InformationAction Continue
    } else {
        Write-Information "🚀 Live mode explicitly enabled" -InformationAction Continue
    }
}

# Import the enhanced label management module
$labelModulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $labelModulePath) {
    Import-Module $labelModulePath -Force -ErrorAction SilentlyContinue
    Write-Information "✅ Loaded enhanced label management system (100 labels)" -InformationAction Continue
} else {
    Write-Warning "⚠️  Enhanced label management module not found - using basic labels"
}

# Additional safety checks
if (-not $DryRun -and $MaxIssuesPerRun -gt 5) {
    Write-Warning "⚠️  WARNING: MaxIssuesPerRun is set to $MaxIssuesPerRun"
    Write-Warning "   Consider using a smaller number for initial testing"
}

# Color definitions for consistent output
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$PURPLE = "`e[35m"
$CYAN = "`e[36m"
$GRAY = "`e[37m"
$NC = "`e[0m"

# Global configuration
$SCRIPT_VERSION = "1.0.0"
$VALIDATION_SCRIPT = "scripts/pre-commit-validation.sh"
$STATE_FILE = "automation/.copilot-issues-state.json"
$MAX_RETRIES = 3
$RETRY_DELAY_SECONDS = 30
$RATE_LIMIT_DELAY = 10

# Script-scoped error collection for comprehensive reporting
$script:CollectedErrors = @()
$script:ErrorCount = 0

# State tracking for preventing infinite loops
$script:ProcessedFiles = @{}
$script:IssueState = @{}
$script:CreatedIssues = @()

# Enhanced logging with debug support
function Write-StatusMessage {
    param(
        [string]$Message,
        [string]$Color = $NC,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelColor = switch ($Level) {
        "ERROR" { $RED }
        "WARNING" { $YELLOW }
        "SUCCESS" { $GREEN }
        "DEBUG" { $CYAN }
        "STEP" { $BLUE }
        default { $NC }
    }
    
    $output = "${levelColor}[${Level}]${NC} ${Color}[${timestamp}] ${Message}${NC}"
    Write-Host $output
    
    # Also log to file for debugging
    $logFile = "automation/create-copilot-issues.log"
    $logEntry = "[$Level] [$timestamp] $Message"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
}

function Write-DebugMessage {
    param([string]$Message)
    
    if ($DebugMode) {
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
        StackTrace = if ($Exception) { $Exception.StackTrace } else { "N/A" }
        PowerShellStackTrace = if ($Exception) { $Exception.ScriptStackTrace } else { "N/A" }
        LastExitCode = $LASTEXITCODE
        ErrorActionPreference = $ErrorActionPreference
        AdditionalInfo = $AdditionalInfo
    }
    
    # Add to global collection
    $script:CollectedErrors += $errorInfo
    
    # Still display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$script:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED -Level "ERROR"
    
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

# Display comprehensive error report at the end
function Show-CollectedError {
    if ($script:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }
    
    Write-StatusMessage "`n" + ("=" * 100) -Color $RED
    Write-StatusMessage "🚨 COMPREHENSIVE ERROR REPORT - $($script:CollectedErrors.Count) Error(s) Found" -Color $RED
    Write-StatusMessage ("=" * 100) -Color $RED
    
    foreach ($errorInfo in $script:CollectedErrors) {
        Write-StatusMessage "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)" -Color $RED
        Write-StatusMessage "   🎯 Function: $($errorInfo.FunctionName)" -Color $YELLOW
        Write-StatusMessage "   📍 Location: $($errorInfo.Location)" -Color $YELLOW
        Write-StatusMessage "   💬 Message: $($errorInfo.Message)" -Color $WHITE
        
        if ($errorInfo.Context) {
            Write-StatusMessage "   📝 Context: $($errorInfo.Context)" -Color $CYAN
        }
        
        if ($errorInfo.ExceptionType -ne "N/A") {
            Write-StatusMessage "   🔍 Exception Type: $($errorInfo.ExceptionType)" -Color $PURPLE
            Write-StatusMessage "   🔍 Exception Message: $($errorInfo.ExceptionMessage)" -Color $PURPLE
        }
        
        if ($errorInfo.InnerException -ne "N/A") {
            Write-StatusMessage "   🔍 Inner Exception: $($errorInfo.InnerException)" -Color $PURPLE
        }
        
        if ($errorInfo.LastExitCode -ne 0) {
            Write-StatusMessage "   🔢 Last Exit Code: $($errorInfo.LastExitCode)" -Color $RED
        }
        
        if ($errorInfo.AdditionalInfo.Count -gt 0) {
            Write-StatusMessage "   📊 Additional Info:" -Color $BLUE
            foreach ($key in $errorInfo.AdditionalInfo.Keys) {
                Write-StatusMessage "      $key`: $($errorInfo.AdditionalInfo[$key])" -Color $GRAY
            }
        }
        
        # Show stack trace in debug mode or for critical errors
        if ($DebugMode -or $errorInfo.ExceptionType -ne "N/A") {
            if ($errorInfo.PowerShellStackTrace -ne "N/A") {
                Write-StatusMessage "   📚 PowerShell Stack Trace:" -Color $GRAY
                $errorInfo.PowerShellStackTrace -split "`n" | ForEach-Object {
                    if ($_.Trim()) {
                        Write-StatusMessage "      $($_.Trim())" -Color $GRAY
                    }
                }
            }
        }
        
        Write-StatusMessage "   " + ("-" * 80) -Color $GRAY
    }
    
    Write-StatusMessage "`n📊 ERROR SUMMARY:" -Color $RED
    Write-StatusMessage "   Total Errors: $($script:CollectedErrors.Count)" -Color $RED
    Write-StatusMessage "   Functions with Errors: $($script:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count" -Color $YELLOW
    Write-StatusMessage "   Exception Types: $($script:CollectedErrors | Where-Object { $_.ExceptionType -ne 'N/A' } | Select-Object -Unique ExceptionType | Measure-Object).Count" -Color $PURPLE
    
    # Most common error types
    $errorTypes = $script:CollectedErrors | Group-Object -Property ExceptionType | Sort-Object Count -Descending
    if ($errorTypes.Count -gt 0) {
        Write-StatusMessage "   Most Common Error Types:" -Color $BLUE
        foreach ($type in $errorTypes | Select-Object -First 3) {
            Write-StatusMessage "      $($type.Name): $($type.Count) occurrence(s)" -Color $GRAY
        }
    }
    
    Write-StatusMessage "`n💡 DEBUGGING TIPS:" -Color $CYAN
    Write-StatusMessage "   • Run with -DebugMode for more detailed information" -Color $GRAY
    Write-StatusMessage "   • Use -TestMode to avoid creating actual issues while debugging" -Color $GRAY
    Write-StatusMessage "   • Check the Location field for exact line numbers" -Color $GRAY
    Write-StatusMessage "   • Review the Context field for operation details" -Color $GRAY
    Write-StatusMessage "   • Exception details provide root cause information" -Color $GRAY
    
    Write-StatusMessage "`n" + ("=" * 100) -Color $RED
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
            Write-WarningMessage "Failed to load state file: $($_.Exception.Message)"
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
        Write-ErrorMessage "Failed to save state: $($_.Exception.Message)"
        return $false
    }
}

# Enhanced validation runner with detailed parsing
function Invoke-ValidationScript {
    param(
        [string]$FilePath = "",
        [switch]$ParseOutput
    )
    
    Write-StepMessage "Running validation script..."
    
    try {
        # Build validation command for shell script
        if ($FilePath) {
            $wslArgs = @('bash', '-c', "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'")
        } else {
            $wslArgs = @('bash', '-c', "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT")
        }
        
        Write-DebugMessage "Executing: wsl $($wslArgs -join ' ')"
        
        # Execute validation
        $validationOutput = & wsl @wslArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-DebugMessage "Validation exit code: $exitCode"
        Write-DebugMessage "Validation output length: $($validationOutput.Length) characters"
        
        if ($ParseOutput) {
            return ConvertFrom-ValidationOutput -Output $validationOutput -ExitCode $exitCode
        } else {
            return @{
                Success = $exitCode -eq 0
                Output = $validationOutput
                ExitCode = $exitCode
            }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Validation script execution failed: $($_.Exception.Message)" -FunctionName "Invoke-ValidationScript" -Exception $_.Exception -Context "Executing validation script $VALIDATION_SCRIPT" -AdditionalInfo @{ValidationScript = $VALIDATION_SCRIPT; TargetFile = $TargetFile}
        Write-ErrorMessage "Validation script execution failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Output = $_.Exception.Message
            ExitCode = -1
            Error = $_.Exception.Message
        }
    }
}

# Parse validation output to extract specific file issues
function ConvertFrom-ValidationOutput {
    param(
        [string[]]$Output,
        [int]$ExitCode
    )
    
    Write-DebugMessage "Parsing validation output..."
    
    $fileIssues = @{}
    $currentFile = ""
    $currentIssues = @()
    
    # Check if this is summary output (aggregated) or detailed output (per-file)
    $isSummaryOutput = $false
    foreach ($line in $Output) {
        if ($line -match "^\d+x / \d+ files:" -or $line -match "=== VALIDATION SUMMARY ===" -or $line -match "Files failed: \d+") {
            $isSummaryOutput = $true
            break
        }
    }
    
    if ($isSummaryOutput) {
        Write-DebugMessage "Detected summary output format - extracting file patterns"
        return ConvertFrom-SummaryOutput -Output $Output -ExitCode $ExitCode
    }
    
    # Parse detailed output (per-file)
    # First, join any wrapped lines back together
    $joinedOutput = @()
    $currentLine = ""
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        
        # If line starts with [SEVERITY], it's a new issue line
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]") {
            # Save previous line if it exists
            if ($currentLine -ne "") {
                $joinedOutput += $currentLine
            }
            $currentLine = $line
        } else {
            # This might be a continuation of the previous line (PowerShell wrapping)
            if ($currentLine -ne "") {
                $currentLine += " " + $line
            } else {
                $joinedOutput += $line
            }
        }
    }
    
    # Don't forget the last line
    if ($currentLine -ne "") {
        $joinedOutput += $currentLine
    }
    
    Write-DebugMessage "Joined $($Output.Count) lines into $($joinedOutput.Count) lines"
    
    foreach ($line in $joinedOutput) {
        $line = $line.Trim()
        Write-DebugMessage "Processing line: $line"
        
        # Handle the specific format: [SEVERITY] filepath:line description [optional context]
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]\s+(.+?):(\d+)\s+(.+)$") {
            $severity = $Matches[1]
            $filepath = $Matches[2]
            $lineNumber = $Matches[3]
            $description = $Matches[4]
            
            # Clean up filepath (remove ./ prefix if present)
            $filepath = $filepath -replace "^\.\/", ""
            
            # Initialize file if not exists
            if (-not $fileIssues.ContainsKey($filepath)) {
                $fileIssues[$filepath] = @()
            }
            
            # Determine issue type and severity level
            $issueType = switch ($severity) {
                "CRITICAL" { "Critical" }
                "MAJOR" { "Major" }
                "MINOR" { "Minor" }
                "WARNING" { "Warning" }
                default { "Minor" }
            }
            
            $severityLevel = switch ($severity) {
                "CRITICAL" { "High" }
                "MAJOR" { "Medium" }
                "MINOR" { "Low" }
                "WARNING" { "Medium" }
                default { "Low" }
            }
            
            $issueInfo = @{
                Line = [int]$lineNumber
                Description = $description
                Type = $issueType
                Severity = $severityLevel
            }
            
            $fileIssues[$filepath] += $issueInfo
            Write-DebugMessage "Added $issueType issue for $filepath line ${lineNumber}: $description"
        }
        # Look for file headers (various formats) - legacy support
        elseif ($line -match "^=== (.+\.sh) ===" -or $line -match "^Validating: (.+\.sh)" -or $line -match "^File: (.+\.sh)" -or $line -match "^\[.*\] Validating (.+\.sh)") {
            # Save previous file if it had issues
            if ($currentFile -and $currentIssues.Count -gt 0) {
                $fileIssues[$currentFile] = $currentIssues
            }
            
            # Start new file
            $currentFile = $Matches[1]
            $currentIssues = @()
            Write-DebugMessage "Found file: $currentFile"
        }
        # Look for critical/error issues with line numbers
        elseif ($line -match "Line (\d+):" -or $line -match "\[Line (\d+)\]" -or $line -match "^(\d+):") {
            $lineNumber = $Matches[1]
            $issueType = "Minor"
            $severity = "Low"
            
            if ($line -match "CRITICAL:|ERROR:") {
                $issueType = "Critical"
                $severity = "High"
            } elseif ($line -match "MAJOR:") {
                $issueType = "Major"
                $severity = "Medium"
            } elseif ($line -match "SC\d+:") {
                $issueType = "ShellCheck"
                $severity = "Medium"
            }
            
            $issueInfo = @{
                Line = $lineNumber
                Description = $line
                Type = $issueType
                Severity = $severity
            }
            
            $currentIssues += $issueInfo
            Write-DebugMessage "Found issue: $($issueInfo.Type) at line $lineNumber - $($issueInfo.Description)"
        }
        # Look for critical/error issues without line numbers
        elseif ($line -match "CRITICAL:|ERROR:|MAJOR:|MINOR:" -or $line -match "SC\d+:") {
            $issueType = "Minor"
            $severity = "Low"
            
            if ($line -match "CRITICAL:") {
                $issueType = "Critical"
                $severity = "High"
            } elseif ($line -match "ERROR:") {
                $issueType = "Error"
                $severity = "High"
            } elseif ($line -match "MAJOR:") {
                $issueType = "Major"
                $severity = "Medium"
            } elseif ($line -match "SC\d+:") {
                $issueType = "ShellCheck"
                $severity = "Medium"
            }
            
            $issueInfo = @{
                Line = "Unknown"
                Description = $line
                Type = $issueType
                Severity = $severity
            }
            
            $currentIssues += $issueInfo
            Write-DebugMessage "Found issue: $($issueInfo.Type) - $($issueInfo.Description)"
        }
        # Look for generic failure indicators
        elseif ($line -match "FAILED|ERROR|FAIL" -and $line -notmatch "SUCCESS|PASSED") {
            $issueInfo = @{
                Line = "Unknown"
                Description = $line
                Type = "Error"
                Severity = "High"
            }
            
            $currentIssues += $issueInfo
            Write-DebugMessage "Found generic error: $line"
        }
    }
    
    # Don't forget the last file
    if ($currentFile -and $currentIssues.Count -gt 0) {
        $fileIssues[$currentFile] = $currentIssues
    }
    
    Write-DebugMessage "Parsed issues for $($fileIssues.Count) files"
    
    return @{
        Success = $ExitCode -eq 0
        FileIssues = $fileIssues
        ExitCode = $ExitCode
        TotalFiles = $fileIssues.Count
        TotalIssues = if ($fileIssues.Values) { ($fileIssues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }
    }
}

# Parse summary output to extract files that have issues
function ConvertFrom-SummaryOutput {
    param(
        [string[]]$Output,
        [int]$ExitCode
    )
    
    Write-DebugMessage "Parsing summary output to extract files with issues..."
    
    $filesWithIssues = @{}
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        Write-DebugMessage "Processing line: $line"
        
        # Look for issue patterns that indicate files with problems
        if ($line -match "^\d+x / (\d+) files:" -and $line -match "SC\d+|CRITICAL|MAJOR|MINOR|bash shebang|local.*keyword") {
            $fileCount = [int]$Matches[1]
            Write-DebugMessage "Found issue: $line affecting $fileCount files"
            
            # Create a synthetic issue to represent this type of problem
            $issueType = "ShellCheck"
            $severity = "Medium"
            
            if ($line -match "CRITICAL") {
                $issueType = "Critical"
                $severity = "High"
            } elseif ($line -match "MAJOR") {
                $issueType = "Major"
                $severity = "Medium"
            } elseif ($line -match "bash shebang|local.*keyword") {
                $issueType = "Critical"
                $severity = "High"
            }
            
            # We'll need to identify which files have these issues
            # For now, create a placeholder that will trigger individual file validation
            for ($i = 1; $i -le $fileCount; $i++) {
                $placeholderFile = "unknown_file_$i.sh"
                if (-not $filesWithIssues.ContainsKey($placeholderFile)) {
                    $filesWithIssues[$placeholderFile] = @()
                }
                
                $filesWithIssues[$placeholderFile] += @{
                    Line = "Unknown"
                    Description = $line
                    Type = $issueType
                    Severity = $severity
                }
            }
        }
    }
    
    Write-DebugMessage "Summary parsing found $($filesWithIssues.Count) placeholder files with issues"
    
    return @{
        Success = $ExitCode -eq 0
        FileIssues = $filesWithIssues
        ExitCode = $ExitCode
        TotalFiles = $filesWithIssues.Count
        TotalIssues = if ($filesWithIssues.Values) { ($filesWithIssues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }
        IsSummary = $true
    }
}

# Get list of files that need validation
function Get-FilesForValidation {
    param(
        [string]$FilePattern = "*.sh",
        [int]$MaxFiles = 50
    )
    
    Write-DebugMessage "Getting files for validation with pattern: $FilePattern"
    
    try {
        # Get all shell files (excluding validation script itself)
        $allFiles = Get-ChildItem -Path "." -Recurse -Include $FilePattern -File | 
                    Where-Object { 
                        $_.Name -ne "pre-commit-validation.sh" -and 
                        $_.FullName -notmatch "\.git" -and
                        $_.FullName -notmatch "node_modules" -and
                        $_.FullName -notmatch "\.vscode"
                    } | 
                    Select-Object -First $MaxFiles |
                    ForEach-Object { 
                        $_.FullName.Replace($PWD.Path, "").Replace("\", "/").TrimStart("/") 
                    }
        
        Write-DebugMessage "Found $($allFiles.Count) files for validation"
        return $allFiles
    }
    catch {
        Add-CollectedError -ErrorMessage "Error getting files for validation: $($_.Exception.Message)" -FunctionName "Get-FilesForValidation" -Exception $_.Exception -Context "Getting files for validation" -AdditionalInfo @{TargetFile = $TargetFile}
        Write-ErrorMessage "Error getting files for validation: $($_.Exception.Message)"
        return @()
    }
}

# Run validation on individual files to get detailed results
function Get-DetailedValidationResult {
    param(
        [string[]]$Files,
        [int]$MaxFiles = 20
    )
    
    Write-DebugMessage "Getting detailed validation results for $($Files.Count) files"
    
    $allFileIssues = @{}
    $filesProcessed = 0
    
    foreach ($file in $Files) {
        if ($filesProcessed -ge $MaxFiles) {
            Write-DebugMessage "Reached max files limit ($MaxFiles) - stopping detailed validation"
            break
        }
        
        Write-DebugMessage "Running detailed validation for: $file"
        
        try {
            # Run validation on individual file
            $wslArgs = @('bash', '-c', "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$file'")
            Write-DebugMessage "Executing: wsl $($wslArgs -join ' ')"
            
            $validationOutput = & wsl @wslArgs 2>&1
            $exitCode = $LASTEXITCODE
            
            Write-DebugMessage "Individual validation exit code: $exitCode"
            
            # Parse the detailed output
            $parseResult = ConvertFrom-ValidationOutput -Output $validationOutput -ExitCode $exitCode
            
            # Add results to collection
            if ($parseResult.FileIssues.Count -gt 0) {
                foreach ($fileKey in $parseResult.FileIssues.Keys) {
                    $allFileIssues[$fileKey] = $parseResult.FileIssues[$fileKey]
                }
                Write-DebugMessage "File $file has $($parseResult.TotalIssues) issues"
            } else {
                Write-DebugMessage "File $file has no issues"
            }
            
            $filesProcessed++
        }
        catch {
            Add-CollectedError -ErrorMessage "Error validating file ${file}: $($_.Exception.Message)" -FunctionName "Get-DetailedValidationResult" -Exception $_.Exception -Context "Validating individual file $file" -AdditionalInfo @{File = $file; ProcessedFiles = $filesProcessed}
            Write-ErrorMessage "Error validating file ${file}: $($_.Exception.Message)"
        }
        
        # Small delay to avoid overwhelming the system
        Start-Sleep -Milliseconds 100
    }
    
    Write-DebugMessage "Detailed validation completed: $($allFileIssues.Count) files with issues"
    
    return @{
        Success = $true
        FileIssues = $allFileIssues
        TotalFiles = $allFileIssues.Count
        TotalIssues = if ($allFileIssues.Values) { ($allFileIssues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }
        FilesProcessed = $filesProcessed
    }
}
function Test-ShouldProcessFile {
    param(
        [string]$FilePath,
        [hashtable]$Issues
    )
    
    Write-DebugMessage "Checking if file should be processed: $FilePath"
    
    # Check if we have state for this file
    if ($script:IssueState.ContainsKey($FilePath)) {
        $fileState = $script:IssueState[$FilePath]
        
        Write-DebugMessage "File state: Status=$($fileState.Status), Attempts=$($fileState.Attempts), LastProcessed=$($fileState.LastProcessed)"
        
        # Skip if already successfully processed
        if ($fileState.Status -eq "Completed") {
            Write-DebugMessage "File already completed - skipping"
            return $false
        }
        
        # Skip if max attempts reached
        if ($fileState.Attempts -ge $MAX_RETRIES) {
            Write-WarningMessage "File has reached max attempts ($MAX_RETRIES) - skipping"
            return $false
        }
        
        # Check if we should wait before retry
        if ($fileState.LastProcessed) {
            $lastProcessed = [DateTime]::Parse($fileState.LastProcessed)
            $timeSinceLastProcess = (Get-Date) - $lastProcessed
            
            if ($timeSinceLastProcess.TotalSeconds -lt $RETRY_DELAY_SECONDS) {
                Write-DebugMessage "File processed recently - waiting for retry delay"
                return $false
            }
        }
        
        # Check if forcing reprocessing
        if (-not $ForceReprocessing -and $fileState.Status -eq "InProgress") {
            Write-DebugMessage "File is in progress and not forcing reprocessing - skipping"
            return $false
        }
    }
    
    # Check issue severity and priority filtering
    $hasCriticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
    $hasMajorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $hasMinorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }
    
    # Apply priority filter
    $passesFilter = $false
    switch ($PriorityFilter) {
        "Critical" { $passesFilter = $hasCriticalIssues.Count -gt 0 }
        "Major" { $passesFilter = $hasMajorIssues.Count -gt 0 }
        "Minor" { $passesFilter = $hasMinorIssues.Count -gt 0 }
        default { $passesFilter = $true }  # "All"
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
    
    # Original logic for non-critical issues
    if (-not $hasCriticalIssues -and -not $ForceReprocessing) {
        Write-DebugMessage "No critical issues found - considering skip"
        
        # Only process if we have a reasonable number of issues (unless priority filter is set)
        if ($Issues.Count -lt 3 -and $PriorityFilter -eq "All") {
            Write-DebugMessage "Few non-critical issues - skipping for now"
            return $false
        }
    }
    
    Write-DebugMessage "File should be processed"
    return $true
}

# Update file processing state
function Update-FileState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FilePath,
        [string]$Status,
        [string]$IssueNumber = "",
        [string]$PRNumber = "",
        [string]$ErrorMessage = ""
    )
    
    if ($PSCmdlet.ShouldProcess($FilePath, "Update file state to $Status")) {
        Write-DebugMessage "Updating file state: $FilePath -> $Status"
    
    if (-not $script:IssueState.ContainsKey($FilePath)) {
        $script:IssueState[$FilePath] = @{
            Attempts = 0
            CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    
    $fileState = $script:IssueState[$FilePath]
    $fileState.Status = $Status
    $fileState.LastProcessed = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    if ($Status -eq "InProgress") {
        $fileState.Attempts += 1
    }
    
    if ($IssueNumber) {
        $fileState.IssueNumber = $IssueNumber
    }
    
    if ($PRNumber) {
        $fileState.PRNumber = $PRNumber
    }
    
    if ($ErrorMessage) {
        $fileState.LastError = $ErrorMessage
    }
    
    $script:IssueState[$FilePath] = $fileState
    
    # Save state immediately
    Save-IssueState | Out-Null
    
    Write-DebugMessage "File state updated and saved"
    }
}

# Generate comprehensive issue content
function New-CopilotIssueContent {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    if ($PSCmdlet.ShouldProcess($FilePath, "Generate issue content")) {
        Write-DebugMessage "Generating issue content for: $FilePath"
    
    # Categorize issues by severity
    $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
    $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }
    
    Write-DebugMessage "Issue breakdown: Critical=$($criticalIssues.Count), Major=$($majorIssues.Count), Minor=$($minorIssues.Count)"
    
    # Generate issue title
    $issueTitle = "🔧 RUTOS Compatibility Fix Required: $FilePath"
    
    # Generate issue body
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
            $issueBody += "- $($issue.Line)`n"
        }
    }
    
    # Add major issues section
    if ($majorIssues.Count -gt 0) {
        $issueBody += @"

### 🟡 **MAJOR ISSUES** (Should Fix)

These issues may cause problems in the busybox environment:

"@
        foreach ($issue in $majorIssues) {
            $issueBody += "- $($issue.Line)`n"
        }
    }
    
    # Add minor issues section
    if ($minorIssues.Count -gt 0) {
        $issueBody += @"

### 🔵 **MINOR ISSUES** (Best Practices)

These issues represent best practices and portability improvements:

"@
        foreach ($issue in $minorIssues) {
            $issueBody += "- $($issue.Line)`n"
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

### **Validation Process**
After making fixes, the validation system will automatically:
1. ✅ **Re-validate** the file using `pre-commit-validation.ps1`
2. 🚀 **Trigger workflows** if validation passes
3. 🔄 **Fix any workflow failures** that occur
4. 🔀 **Resolve merge conflicts** if they arise
5. ✅ **Merge and close** when everything is green

### **Scope Control**
**🎯 CRITICAL REQUIREMENT**: Only modify the file mentioned above (`$FilePath`). 

**❌ STRICTLY FORBIDDEN - Do NOT make changes to:**
- Other shell scripts or configuration files
- Validation scripts or tooling
- Documentation files (unless fixing syntax in the target file)
- GitHub Actions workflow files (.github/workflows/)
- Any files not explicitly mentioned in this issue

**⚠️ REMINDER**: Your commit should contain changes to ONLY the single target file. Any additional file modifications will be rejected.

## 📋 **Acceptance Criteria**
- [ ] All critical issues resolved
- [ ] All major issues resolved (if possible)
- [ ] Minor issues addressed (if time permits)
- [ ] File passes `pre-commit-validation.ps1` with no errors
- [ ] All GitHub Actions workflows pass
- [ ] No merge conflicts
- [ ] Only the target file is modified

## 🔍 **Verification**
The system will automatically verify fixes by:
1. Running validation: ``wsl bash -c "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT '$FilePath'"``
2. Checking for zero exit code and no error output
3. Ensuring all workflows pass
4. Confirming no merge conflicts exist

---

## 🤖 **Automation Notes**
- This issue was automatically created by the RUTOS Copilot Issue System
- Progress will be monitored automatically
- The issue will be closed when all fixes are verified
- Maximum of $MAX_RETRIES attempts will be made

**⚠️ Anti-Loop Protection**: This issue has built-in protection against infinite loops and will escalate to manual review if needed.

---

*Generated by create-copilot-issues.ps1 v$SCRIPT_VERSION on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

    # Generate intelligent labels (fallback to basic labels if module not available)
    $intelligentLabels = @()
    
    if (Get-Command "Get-IntelligentLabels" -ErrorAction SilentlyContinue) {
        # Use enhanced label system
        $intelligentLabels = Get-IntelligentLabels -FilePath $FilePath -Issues $Issues -Context "issue" -IssueTitle $issueTitle -IssueBody $issueBody
    } else {
        # Fallback to basic labels
        $intelligentLabels = @("rutos-compatibility", "copilot-fix", "automated", "shell-script")
        
        # Add basic priority detection
        $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
        $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
        
        if ($criticalIssues.Count -gt 0) {
            $intelligentLabels += "priority-critical"
        } elseif ($majorIssues.Count -gt 0) {
            $intelligentLabels += "priority-major"
        } else {
            $intelligentLabels += "priority-minor"
        }
    }

    return @{
        Title = $issueTitle
        Body = $issueBody
        Labels = $intelligentLabels
    }
    }
}

# Create GitHub issue with Copilot assignment
function New-CopilotIssue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FilePath,
        [array]$Issues
    )
    
    if ($PSCmdlet.ShouldProcess($FilePath, "Create GitHub issue")) {
        Write-StepMessage "Creating Copilot issue for: $FilePath"
        
        if ($DryRun) {
            Write-SuccessMessage "[DRY RUN] Would create issue for: $FilePath"
            return @{ Success = $true; IssueNumber = "DRY-RUN"; DryRun = $true }
        }
    
    try {
        # Generate issue content
        $issueContent = New-CopilotIssueContent -FilePath $FilePath -Issues $Issues
        
        Write-DebugMessage "Issue title: $($issueContent.Title)"
        Write-DebugMessage "Issue body length: $($issueContent.Body.Length) characters"
        Write-DebugMessage "Issue labels: $($issueContent.Labels -join ', ')"
        
        # Create temporary file for issue body
        $tempFile = [System.IO.Path]::GetTempFileName()
        $issueContent.Body | Out-File -FilePath $tempFile -Encoding UTF8
        
        # Build GitHub CLI command arguments
        $ghArgs = @('issue', 'create', '-t', $issueContent.Title, '-F', $tempFile)
        foreach ($label in $issueContent.Labels) {
            $ghArgs += @('-l', $label)
        }
        
        Write-DebugMessage "Executing: gh $($ghArgs -join ' ')"
        
        if ($TestMode) {
            Write-SuccessMessage "[TEST MODE] Would execute: gh $($ghArgs -join ' ')"
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            return @{ Success = $true; IssueNumber = "TEST-MODE"; TestMode = $true }
        }
        
        # Execute GitHub CLI command
        $result = & gh @ghArgs
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            # Extract issue number from result
            $issueNumber = ""
            if ($result -match "https://github\.com/[^/]+/[^/]+/issues/(\d+)") {
                $issueNumber = $Matches[1]
            }
            
            Write-SuccessMessage "Created issue #$issueNumber for: $FilePath"
            
            # Wait for rate limiting
            Start-Sleep -Seconds $RATE_LIMIT_DELAY
            
            # Assign Copilot to the issue
            $assignResult = Set-CopilotAssignment -IssueNumber $issueNumber
            
            if ($assignResult.Success) {
                Write-SuccessMessage "Assigned Copilot to issue #$issueNumber"
                
                # Update tracking
                $script:CreatedIssues += @{
                    IssueNumber = $issueNumber
                    FilePath = $FilePath
                    CreatedAt = Get-Date
                    IssueCount = $Issues.Count
                }
                
                return @{ 
                    Success = $true
                    IssueNumber = $issueNumber
                    FilePath = $FilePath
                }
            } else {
                Write-WarningMessage "Issue created but Copilot assignment failed: $($assignResult.Error)"
                return @{ 
                    Success = $true
                    IssueNumber = $issueNumber
                    FilePath = $FilePath
                    Warning = "Copilot assignment failed"
                }
            }
        } else {
            Add-CollectedError -ErrorMessage "Failed to create issue: $result" -FunctionName "Create-GitHubIssue" -Context "GitHub CLI command failed for $FilePath" -AdditionalInfo @{FilePath = $FilePath; IssueTitle = $IssueTitle; GitHubResult = $result; LastExitCode = $LASTEXITCODE}
            Write-ErrorMessage "Failed to create issue: $result"
            return @{ 
                Success = $false
                Error = "GitHub CLI command failed: $result"
            }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error creating issue: $($_.Exception.Message)" -FunctionName "Create-GitHubIssue" -Exception $_.Exception -Context "Creating GitHub issue for $FilePath" -AdditionalInfo @{FilePath = $FilePath; IssueTitle = $IssueTitle; LastExitCode = $LASTEXITCODE}
        Write-ErrorMessage "Error creating issue: $($_.Exception.Message)"
        return @{ 
            Success = $false
            Error = $_.Exception.Message
        }
    }
    }
}

# Assign Copilot to an issue with comprehensive role assignment
function Set-CopilotAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$IssueNumber)
    
    if ($PSCmdlet.ShouldProcess("Issue #$IssueNumber", "Assign Copilot")) {
        Write-DebugMessage "Assigning Copilot to issue #$IssueNumber with comprehensive roles"
    
    try {
        if ($DryRun -or $TestMode) {
            Write-SuccessMessage "[DRY RUN] Would assign Copilot with full roles to issue #$IssueNumber"
            return @{ Success = $true; DryRun = $true }
        }
        
        # Step 1: Assign Copilot as assignee (primary role)
        Write-DebugMessage "Step 1: Assigning Copilot as assignee..."
        $assignResult = gh issue edit $IssueNumber --add-assignee "@copilot" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to assign Copilot as assignee: $assignResult"
            return @{ Success = $false; Error = $assignResult }
        }
        
        Write-DebugMessage "✅ Copilot assigned as assignee successfully!"
        
        # Step 2: Add to RUTOS project if available (enhance project management)
        Write-DebugMessage "Step 2: Adding to RUTOS project..."
        $projectResult = gh issue edit $IssueNumber --add-project "RUTOS Compatibility" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "✅ Added to RUTOS Compatibility project!"
        } else {
            Write-DebugMessage "ℹ️  RUTOS project not available or already assigned: $projectResult"
        }
        
        # Step 3: Add to Current Sprint milestone if available
        Write-DebugMessage "Step 3: Adding to milestone..."
        $milestoneResult = gh issue edit $IssueNumber --milestone "RUTOS Fixes" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "✅ Added to RUTOS Fixes milestone!"
        } else {
            Write-DebugMessage "ℹ️  RUTOS Fixes milestone not available: $milestoneResult"
        }
        
        # Step 4: Add high-priority label for autonomous handling
        Write-DebugMessage "Step 4: Adding autonomous handling labels..."
        $labelResult = gh issue edit $IssueNumber --add-label "copilot-assigned,autonomous-fix,high-priority" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-DebugMessage "✅ Added autonomous handling labels!"
        } else {
            Write-DebugMessage "ℹ️  Label addition may have had issues: $labelResult"
        }
        
        # Step 5: Verify the assignment worked
        Write-DebugMessage "Step 5: Verifying comprehensive assignment..."
        Start-Sleep -Seconds 2  # Give GitHub API time to process
        
        # Step 6: Post comprehensive @github-copilot assignment comment
        $assignmentComment = @"
🤖 **Comprehensive Copilot Assignment**

@github-copilot you have been assigned to this issue with full project management roles:

## 🎯 **Your Roles:**
- ✅ **Assignee** - Primary responsibility for resolution
- 📍 **Project Member** - Added to RUTOS Compatibility project (if available)
- 🎯 **Milestone Participant** - Part of RUTOS Fixes milestone tracking
- 🏷️ **Priority Handler** - Labeled for autonomous processing

## 📋 **Task Details:**
Please fix the RUTOS compatibility issues listed above with these requirements:

### 🔧 **Technical Requirements:**
1. **Fix all issues** listed in the issue description
2. **Follow RUTOS compatibility guidelines** exactly (POSIX sh, busybox support)
3. **Only modify the target file** mentioned in the issue title
4. **Test your changes** to ensure they work correctly
5. **Preserve all existing functionality** while making fixes

### 🎯 **Quality Standards:**
- ✅ ShellCheck compliance (no SC errors)
- ✅ POSIX sh compatibility (no bash-specific syntax)
- ✅ Busybox shell support
- ✅ Error handling preservation
- ✅ Debug mode functionality maintained

### 🚀 **Automation Integration:**
- The autonomous system will detect your PR and handle workflows
- Merge conflicts will be resolved automatically if they occur
- Quality validation will run automatically

## 🎊 **Success Criteria:**
Your fix will be considered complete when:
1. All validation issues are resolved
2. Code passes ShellCheck and formatting checks
3. PR is successfully merged by autonomous system

Thank you for your comprehensive assistance! 🤖✨

*This is an enhanced assignment with full project management integration*
"@
            
            # Create temporary file for comment
            $tempFile = [System.IO.Path]::GetTempFileName()
            $assignmentComment | Out-File -FilePath $tempFile -Encoding UTF8
            
            # Post comprehensive assignment comment
            $ghArgs = @('issue', 'comment', $IssueNumber, '-F', $tempFile)
            Write-DebugMessage "Executing comprehensive assignment: gh $($ghArgs -join ' ')"
            
            $result = & gh @ghArgs
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            if ($LASTEXITCODE -eq 0) {
                Write-DebugMessage "✅ Comprehensive Copilot assignment completed!"
                Write-SuccessMessage "🎯 Copilot assigned with full project management roles to issue #$IssueNumber"
                return @{ 
                    Success = $true; 
                    Roles = @("assignee", "project-member", "milestone-participant", "priority-handler")
                }
            } else {
                Write-WarningMessage "Copilot assigned but comprehensive comment posting failed: $result"
                return @{ Success = $true; Warning = "Comment posting failed but assignment succeeded" }
            }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in comprehensive Copilot assignment: $($_.Exception.Message)" -FunctionName "Set-CopilotAssignment" -Exception $_.Exception -Context "Comprehensive assignment to issue $IssueNumber" -AdditionalInfo @{IssueNumber = $IssueNumber; LastExitCode = $LASTEXITCODE}
        Write-ErrorMessage "Error in comprehensive Copilot assignment: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    }
}

# Enhanced Copilot PR assignment with reviewer capabilities
function Set-CopilotPRAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$PRNumber,
        [string]$ReviewerUsername = "mranv", # GitHub username for reviewer since @copilot doesn't work for reviewers
        [string]$ProjectName = "RUTOS Compatibility",
        [string]$MilestoneName = "RUTOS Fixes",
        [string]$Labels = "copilot-assigned,autonomous-fix,high-priority,needs-review"
    )
    
    if ($PSCmdlet.ShouldProcess("PR #$PRNumber", "Assign Copilot and set PR properties")) {
        Write-DebugMessage "🎯 Starting comprehensive Copilot PR assignment for PR #$PRNumber"
        
        try {
            # Step 1: Assign Copilot as assignee
            Write-DebugMessage "Assigning @copilot as PR assignee..."
            $assignResult = gh pr edit $PRNumber --add-assignee "@copilot" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-WarningMessage "Failed to assign @copilot to PR: $assignResult"
            } else {
                Write-DebugMessage "✅ @copilot assigned as PR assignee"
            }
        
        # Step 2: Add reviewer (human username since @copilot doesn't work)
        if ($ReviewerUsername) {
            Write-DebugMessage "Adding reviewer: $ReviewerUsername"
            $reviewResult = gh pr edit $PRNumber --add-reviewer $ReviewerUsername 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-WarningMessage "Failed to add reviewer $ReviewerUsername: $reviewResult"
            } else {
                Write-DebugMessage "✅ Reviewer $ReviewerUsername added"
            }
        }
        
        # Step 3: Add to project (if specified)
        if ($ProjectName) {
            Write-DebugMessage "Adding to project: $ProjectName"
            $projectResult = gh pr edit $PRNumber --add-project $ProjectName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-WarningMessage "Failed to add to project '$ProjectName': $projectResult"
            } else {
                Write-DebugMessage "✅ Added to project '$ProjectName'"
            }
        }
        
        # Step 4: Add to milestone (if specified)
        if ($MilestoneName) {
            Write-DebugMessage "Adding to milestone: $MilestoneName"
            $milestoneResult = gh pr edit $PRNumber --milestone $MilestoneName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-WarningMessage "Failed to add to milestone '$MilestoneName': $milestoneResult"
            } else {
                Write-DebugMessage "✅ Added to milestone '$MilestoneName'"
            }
        }
        
        # Step 5: Add comprehensive labels
        Write-DebugMessage "Adding comprehensive labels: $Labels"
        $labelResult = gh pr edit $PRNumber --add-label $Labels 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMessage "Failed to add all labels: $labelResult"
        } else {
            Write-DebugMessage "✅ Comprehensive labels added"
        }
        
        # Step 6: Add comprehensive assignment comment
        $assignmentMessage = @"
🤖 **Comprehensive Copilot PR Assignment Complete!**

**Assigned Roles:**
- 👤 **Assignee**: @copilot (Primary AI reviewer)
- 👥 **Reviewer**: @$ReviewerUsername (Human oversight)
- 📁 **Project**: $ProjectName (Project management)
- 🎯 **Milestone**: $MilestoneName (Release tracking)
- 🏷️ **Labels**: Enhanced automation and priority tags

**Assignment Capabilities:**
✅ **Full Project Management**: This PR is now integrated into our project management workflow
✅ **Dual Review Process**: AI (@copilot) + Human ($ReviewerUsername) review coverage
✅ **Milestone Tracking**: Linked to release milestone for progress tracking
✅ **Priority Handling**: Marked for autonomous processing and high-priority attention
✅ **Enhanced Automation**: Tagged for advanced automation features

**Next Steps:**
- @copilot will provide AI-powered code review
- @$ReviewerUsername will provide human oversight and final approval
- Autonomous conflict resolution active for merge conflicts
- Progress tracked in '$ProjectName' project and '$MilestoneName' milestone

*This comprehensive assignment ensures maximum coverage and efficient PR processing! 🚀*
"@
            
            # Write to temp file to handle multi-line content
            $tempFile = Join-Path $env:TEMP "copilot-pr-assignment-$(Get-Random).md"
            $assignmentMessage | Out-File -FilePath $tempFile -Encoding utf8
            
            # Post comprehensive assignment comment
            $ghArgs = @('pr', 'comment', $PRNumber, '-F', $tempFile)
            Write-DebugMessage "Executing comprehensive PR assignment: gh $($ghArgs -join ' ')"
            
            $result = & gh @ghArgs
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            if ($LASTEXITCODE -eq 0) {
                Write-DebugMessage "✅ Comprehensive Copilot PR assignment completed!"
                Write-SuccessMessage "🎯 Copilot assigned with full roles + reviewer to PR #$PRNumber"
                return @{ 
                    Success = $true; 
                    Roles = @("assignee", "reviewer-oversight", "project-member", "milestone-participant")
                    Reviewer = $ReviewerUsername
                }
            } else {
                Write-WarningMessage "Copilot assigned but comprehensive comment posting failed: $result"
                return @{ Success = $true; Warning = "Comment posting failed but assignment succeeded" }
            }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in comprehensive Copilot PR assignment: $($_.Exception.Message)" -FunctionName "Set-CopilotPRAssignment" -Exception $_.Exception -Context "Comprehensive PR assignment to PR $PRNumber" -AdditionalInfo @{PRNumber = $PRNumber; LastExitCode = $LASTEXITCODE; ReviewerUsername = $ReviewerUsername}
        Write-ErrorMessage "Error in comprehensive Copilot PR assignment: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    }
}

# Check environment and prerequisites
function Test-Environment {
    Write-StepMessage "Checking environment and prerequisites..."
    
    # Check if we're in a git repository
    if (-not (Test-Path ".git")) {
        Add-CollectedError -ErrorMessage "Not in a git repository root" -FunctionName "Test-Environment" -Context "Checking git repository" -AdditionalInfo @{CurrentDirectory = $PWD}
        Write-ErrorMessage "Not in a git repository root"
        return $false
    }
    
    # Check GitHub CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Add-CollectedError -ErrorMessage "GitHub CLI (gh) is not installed or not in PATH" -FunctionName "Test-Environment" -Context "Checking GitHub CLI availability" -AdditionalInfo @{PATH = $env:PATH}
        Write-ErrorMessage "GitHub CLI (gh) is not installed or not in PATH"
        return $false
    }
    
    # Check GitHub CLI authentication
    $authResult = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CollectedError -ErrorMessage "GitHub CLI is not authenticated. Run: gh auth login" -FunctionName "Test-Environment" -Context "Checking GitHub CLI authentication" -AdditionalInfo @{AuthResult = $authResult; LastExitCode = $LASTEXITCODE}
        Write-ErrorMessage "GitHub CLI is not authenticated. Run: gh auth login"
        return $false
    }
    
    # Check WSL availability
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "WSL is not available. This script requires WSL to run the validation script."
        return $false
    }
    
    # Check validation script exists
    if (-not (Test-Path $VALIDATION_SCRIPT)) {
        Write-ErrorMessage "Validation script not found: $VALIDATION_SCRIPT"
        return $false
    }
    
    # Test validation script
    Write-DebugMessage "Testing validation script..."
    try {
        $testResult = wsl bash -c "cd /mnt/c/GitHub/rutos-starlink-failover && ./$VALIDATION_SCRIPT --help" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMessage "Validation script test failed: $testResult"
        } else {
            Write-DebugMessage "Validation script test passed"
        }
    } catch {
        Add-CollectedError -ErrorMessage "Could not test validation script: $($_.Exception.Message)" -FunctionName "Test-Environment" -Exception $_.Exception -Context "Testing validation script $VALIDATION_SCRIPT" -AdditionalInfo @{ValidationScript = $VALIDATION_SCRIPT}
        Write-WarningMessage "Could not test validation script: $($_.Exception.Message)"
    }
    
    Write-SuccessMessage "Environment check passed"
    return $true
}

# Main execution function
function Start-CopilotIssueCreation {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    if ($PSCmdlet.ShouldProcess("RUTOS repository", "Create Copilot issues")) {
        Write-StatusMessage "🚀 Starting Autonomous RUTOS Copilot Issue Creation System v$SCRIPT_VERSION" -Color $GREEN
    
    # Environment check
    if (-not (Test-Environment)) {
        Write-ErrorMessage "Environment check failed"
        return $false
    }
    
    # Load state
    Get-IssueState | Out-Null
    
    # Run validation if not skipped
    if (-not $SkipValidation) {
        Write-StepMessage "Running comprehensive validation..."
        
        $validationResult = if ($TargetFile) {
            # Single file validation
            Invoke-ValidationScript -FilePath $TargetFile -ParseOutput
        } else {
            # Multi-step validation: first get summary, then detailed results
            Write-DebugMessage "Step 1: Getting validation summary..."
            $summaryResult = Invoke-ValidationScript -ParseOutput
            
            if ($summaryResult.IsSummary) {
                Write-DebugMessage "Step 2: Getting detailed validation results..."
                
                # Get list of files to validate
                $filesToValidate = Get-FilesForValidation -FilePattern "*.sh" -MaxFiles 30
                
                if ($filesToValidate.Count -gt 0) {
                    Write-DebugMessage "Step 3: Running detailed validation on $($filesToValidate.Count) files..."
                    $validationResult = Get-DetailedValidationResult -Files $filesToValidate -MaxFiles 20
                } else {
                    Write-WarningMessage "No files found for validation"
                    $validationResult = @{
                        Success = $false
                        FileIssues = @{}
                        TotalFiles = 0
                        TotalIssues = 0
                    }
                }
            } else {
                # Already detailed results
                $validationResult = $summaryResult
            }
        }
        
        if (-not $validationResult.Success) {
            Write-WarningMessage "Validation found issues - this is expected for issue creation"
        }
        
        Write-DebugMessage "Validation result structure: Success=$($validationResult.Success), TotalFiles=$($validationResult.TotalFiles), TotalIssues=$($validationResult.TotalIssues)"
        
        # Safe handling of validation results
        $totalFilesCount = if ($validationResult.TotalFiles) { $validationResult.TotalFiles } else { 0 }
        $totalIssuesCount = if ($validationResult.TotalIssues) { $validationResult.TotalIssues } else { 0 }
        
        Write-StatusMessage "Validation completed: $totalFilesCount files with issues" -Color $BLUE
        Write-DebugMessage "Total issues found: $totalIssuesCount"
        
    } else {
        Write-WarningMessage "Skipping validation - using existing state"
        $validationResult = @{
            Success = $false
            FileIssues = @{}
            TotalFiles = 0
            TotalIssues = 0
        }
    }
    
    # Process files with issues
    $issuesCreated = 0
    $filesProcessed = 0
    $filesSkipped = 0
    
    # Sort files by priority if requested
    $filesToProcess = if ($SortByPriority) {
        Write-DebugMessage "Sorting files by priority..."
        
        # Check if FileIssues exists and has content
        if (-not $validationResult.FileIssues -or $validationResult.FileIssues.Count -eq 0) {
            Write-DebugMessage "No files with issues to sort"
            @()
        } else {
            # Calculate priority score for each file
            $filesPriority = @()
            foreach ($filePath in $validationResult.FileIssues.Keys) {
                $issues = $validationResult.FileIssues[$filePath]
                $criticalCount = ($issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }).Count
                $majorCount = ($issues | Where-Object { $_.Type -eq "Major" }).Count
                $minorCount = ($issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }).Count
                
                # Priority score: Critical = 100, Major = 10, Minor = 1
                $priorityScore = ($criticalCount * 100) + ($majorCount * 10) + ($minorCount * 1)
                
                $filesPriority += @{
                    FilePath = $filePath
                    Issues = $issues
                    PriorityScore = $priorityScore
                    CriticalCount = $criticalCount
                    MajorCount = $majorCount
                    MinorCount = $minorCount
                }
            }
            
            # Sort by priority score (highest first)
            $sortedFiles = $filesPriority | Sort-Object -Property PriorityScore -Descending
            
            Write-DebugMessage "File priority order:"
            foreach ($file in $sortedFiles) {
                Write-DebugMessage "  $($file.FilePath): Score=$($file.PriorityScore) (C:$($file.CriticalCount), M:$($file.MajorCount), m:$($file.MinorCount))"
            }
            
            $sortedFiles
        }
    } else {
        # Use original order
        # Check if FileIssues exists and has content
        if (-not $validationResult.FileIssues -or $validationResult.FileIssues.Count -eq 0) {
            Write-DebugMessage "No files with issues to process"
            @()
        } else {
            $validationResult.FileIssues.Keys | ForEach-Object {
                @{
                    FilePath = $_
                    Issues = $validationResult.FileIssues[$_]
                    PriorityScore = 0
                }
            }
        }
    }
    
    foreach ($fileInfo in $filesToProcess) {
        $filesProcessed++
        $filePath = $fileInfo.FilePath
        $issues = $fileInfo.Issues
        
        Write-StepMessage "Processing file ($filesProcessed/$($filesToProcess.Count)): $filePath"
        Write-DebugMessage "File has $($issues.Count) issues$(if ($SortByPriority) { " (Priority Score: $($fileInfo.PriorityScore))" })"
        
        # Check if we should process this file
        if (-not (Test-ShouldProcessFile -FilePath $filePath -Issues $issues)) {
            Write-WarningMessage "Skipping file: $filePath"
            $filesSkipped++
            continue
        }
        
        # Check if we've reached the limit
        if ($issuesCreated -ge $MaxIssuesPerRun) {
            Write-WarningMessage "Reached maximum issues per run ($MaxIssuesPerRun) - stopping"
            break
        }
        
        # Update state to in progress
        Update-FileState -FilePath $filePath -Status "InProgress"
        
        # Create issue
        Write-StepMessage "Creating issue for: $filePath"
        $issueResult = New-CopilotIssue -FilePath $filePath -Issues $issues
        
        if ($issueResult.Success) {
            $issuesCreated++
            Write-SuccessMessage "Successfully created issue #$($issueResult.IssueNumber) for: $filePath"
            
            # Update state
            Update-FileState -FilePath $filePath -Status "IssueCreated" -IssueNumber $issueResult.IssueNumber
            
            # Add delay for rate limiting
            if ($issuesCreated -lt $MaxIssuesPerRun) {
                Write-DebugMessage "Rate limiting delay..."
                Start-Sleep -Seconds $RATE_LIMIT_DELAY
            }
        } else {
            Add-CollectedError -ErrorMessage "Failed to create issue for: $filePath - $($issueResult.Error)" -FunctionName "Start-CopilotIssueCreation" -Context "Creating issue for file $filePath" -AdditionalInfo @{FilePath = $filePath; IssueResult = $issueResult; IssuesCreated = $issuesCreated; MaxIssuesPerRun = $MaxIssuesPerRun}
            Write-ErrorMessage "Failed to create issue for: $filePath - $($issueResult.Error)"
            Update-FileState -FilePath $filePath -Status "Failed" -ErrorMessage $issueResult.Error
        }
    }
    
    # Summary
    Write-StatusMessage "`n" + ("=" * 80) -Color $PURPLE
    Write-StatusMessage "🎉 Autonomous Issue Creation Completed!" -Color $GREEN
    Write-StatusMessage "📊 Summary:" -Color $BLUE
    Write-StatusMessage "   Files processed: $filesProcessed" -Color $CYAN
    Write-StatusMessage "   Files skipped: $filesSkipped" -Color $CYAN
    Write-StatusMessage "   Issues created: $issuesCreated" -Color $CYAN
    Write-StatusMessage "   Max issues per run: $MaxIssuesPerRun" -Color $CYAN
    Write-StatusMessage "   Priority filter: $PriorityFilter" -Color $CYAN
    Write-StatusMessage "   Min issues per file: $MinIssuesPerFile" -Color $CYAN
    Write-StatusMessage "   Sort by priority: $SortByPriority" -Color $CYAN
    
    if ($DryRun) {
        Write-StatusMessage "   🧪 DRY RUN MODE - No actual issues created" -Color $YELLOW
    } elseif ($TestMode) {
        Write-StatusMessage "   🧪 TEST MODE - No actual issues created" -Color $YELLOW
    }
    
    Write-StatusMessage ("=" * 80) -Color $PURPLE
    
    # Save final state
    Save-IssueState | Out-Null
    
    return $issuesCreated -gt 0
    }
}

# Display help information
function Show-Help {
    $helpText = @"
🤖 Autonomous RUTOS Copilot Issue Creation System v$SCRIPT_VERSION

This script creates targeted GitHub issues for RUTOS compatibility problems and 
assigns Copilot to automatically fix them.

USAGE:
    .\create-copilot-issues.ps1 [OPTIONS]

OPTIONS:
    -TestMode              Run in test mode (no actual issues created)
    -DryRun                Show what would be done without making changes
    -MaxIssuesPerRun N     Create maximum N issues per run (default: 5)
    -PriorityFilter LEVEL  Filter by priority: All, Critical, Major, Minor (default: All)
    -MinIssuesPerFile N    Skip files with fewer than N issues (default: 1)
    -SortByPriority        Process files with critical issues first
    -SkipValidation        Skip validation step (use existing state)
    -DebugMode             Enable detailed debug logging
    -ForceReprocessing     Force reprocessing of previously handled files
    -TargetFile PATH       Process only specified file (for testing)
    -Help                  Show this help message

EXAMPLES:
    .\create-copilot-issues.ps1 -TestMode -DebugMode
    .\create-copilot-issues.ps1 -DryRun -MaxIssuesPerRun 3
    .\create-copilot-issues.ps1 -PriorityFilter Critical -MaxIssuesPerRun 2
    .\create-copilot-issues.ps1 -SortByPriority -MinIssuesPerFile 3
    .\create-copilot-issues.ps1 -TargetFile "scripts/validate-config.sh"

WORKFLOW:
    1. Run validation script to identify issues
    2. Create targeted issues for problematic files
    3. Assign Copilot to automatically fix issues
    4. Monitor progress via monitoring script
    5. Automatic merge when all checks pass

SAFETY FEATURES:
    - Anti-loop protection (max $MAX_RETRIES attempts per file)
    - Rate limiting ($RATE_LIMIT_DELAY seconds between API calls)
    - State persistence (resume from where left off)
    - Scope control (only target file is modified)

FILES:
    - State file: $STATE_FILE
    - Validation: $VALIDATION_SCRIPT  
    - Log file: automation/create-copilot-issues.log
    - Execution: Uses WSL to run shell validation script

For more information, see the project documentation.
"@
    
    Write-Information $helpText -InformationAction Continue
}

# Main execution
try {
    # Handle help
    if ($args -contains "-Help" -or $args -contains "--help" -or $args -contains "-h") {
        Show-Help
        exit 0
    }
    
    # Display safety banner
    Write-Information "" -InformationAction Continue
    Write-Information "🛡️  AUTONOMOUS RUTOS COPILOT ISSUE CREATION SYSTEM v$SCRIPT_VERSION" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    if ($DryRun) {
        Write-Information "🧪 SAFETY MODE: DryRun enabled - No actual issues will be created" -InformationAction Continue
        Write-Information "   This is the default behavior for safety. Use -Production to create real issues." -InformationAction Continue
    } else {
        Write-Information "🚀 PRODUCTION MODE: Issues will be created and assigned to Copilot" -InformationAction Continue
        Write-Information "   Maximum $MaxIssuesPerRun issues will be created in this run." -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue
    
    # Display configuration
    Write-StatusMessage "🔧 Configuration:" -Color $CYAN
    Write-StatusMessage "   TestMode: $TestMode" -Color $GRAY
    Write-StatusMessage "   DryRun: $DryRun $(if ($DryRun) { '(SAFETY MODE)' } else { '(PRODUCTION)' })" -Color $(if ($DryRun) { $YELLOW } else { $GREEN })
    Write-StatusMessage "   MaxIssuesPerRun: $MaxIssuesPerRun" -Color $GRAY
    Write-StatusMessage "   Production: $Production" -Color $(if ($Production) { $GREEN } else { $YELLOW })
    Write-StatusMessage "   PriorityFilter: $PriorityFilter" -Color $GRAY
    Write-StatusMessage "   MinIssuesPerFile: $MinIssuesPerFile" -Color $GRAY
    Write-StatusMessage "   SortByPriority: $SortByPriority" -Color $GRAY
    Write-StatusMessage "   SkipValidation: $SkipValidation" -Color $GRAY
    Write-StatusMessage "   DebugMode: $DebugMode" -Color $GRAY
    Write-StatusMessage "   ForceReprocessing: $ForceReprocessing" -Color $GRAY
    Write-StatusMessage "   TargetFile: $(if ($TargetFile) { $TargetFile } else { 'All files' })" -Color $GRAY
    
    # Start the process
    $result = Start-CopilotIssueCreation
    
    if ($result) {
        Write-SuccessMessage "Issue creation completed successfully"
        exit 0
    } else {
        Write-WarningMessage "Issue creation completed with no new issues"
        exit 0
    }
    
} catch {
    Add-CollectedError -ErrorMessage "Critical error: $($_.Exception.Message)" -FunctionName "Main" -Exception $_.Exception -Context "Main script execution"
    Write-ErrorMessage "Critical error: $($_.Exception.Message)"
    Write-DebugMessage "Stack trace: $($_.ScriptStackTrace)"
    
    # Always show collected errors before exiting
    Show-CollectedError
    exit 1
}

# Always show collected errors at the end, even on success
Show-CollectedError

# Exit with appropriate code
if ($script:ErrorCount -gt 0) {
    Write-StatusMessage "⚠️ Script completed with $script:ErrorCount error(s) - see error report above" -Color $YELLOW
    exit 1
} else {
    Write-StatusMessage "✅ Script completed successfully with no errors" -Color $GREEN
    exit 0
}
