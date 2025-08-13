# Advanced Copilot PR Monitoring System with Enhanced Error Handling
# This script monitors Copilot-generated PRs and provides intelligent automation

param(
    [int]$PRNumber,
    [switch]$VerboseOutput,
    [switch]$SkipValidation,
    [switch]$RequestCopilotForConflicts,
    [switch]$SkipWorkflowApproval,
    [switch]$ForceValidation,
    [switch]$MonitorOnly,
    [switch]$TestMode,
    [switch]$DebugMode,
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
🤖 Advanced Copilot PR Monitoring System

USAGE:
    Monitor-CopilotPRs-Advanced.ps1 [OPTIONS]

OPTIONS:
    -PRNumber <int>                 Monitor specific PR number
    -VerboseOutput                  Show detailed operation information
    -SkipValidation                 Skip comprehensive validation
    -RequestCopilotForConflicts     Request Copilot help for merge conflicts
    -SkipWorkflowApproval           Skip workflow approval process
    -ForceValidation                Force validation even if previously passed
    -MonitorOnly                    Monitor only mode (no automation)
    -TestMode                       Test mode (no actual changes)
    -DebugMode                      Enable debug output
    -Help                           Show this help message

EXAMPLES:
    # Monitor all Copilot PRs
    .\Monitor-CopilotPRs-Advanced.ps1

    # Monitor specific PR
    .\Monitor-CopilotPRs-Advanced.ps1 -PRNumber 42

    # Monitor only mode with debug
    .\Monitor-CopilotPRs-Advanced.ps1 -MonitorOnly -DebugMode

"@
    exit 0
}

# Define color constants
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$PURPLE = [ConsoleColor]::Magenta
$GRAY = [ConsoleColor]::Gray

# Global error collection for comprehensive reporting
$global:CollectedErrors = @()
$global:ErrorCount = 0

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
        StackTrace = if ($Exception) { $Exception.StackTrace } else { "N/A" }
        PowerShellStackTrace = if ($Exception) { $Exception.ScriptStackTrace } else { "N/A" }
        LastExitCode = $LASTEXITCODE
        ErrorActionPreference = $ErrorActionPreference
        AdditionalInfo = $AdditionalInfo
    }
    
    # Add to global collection
    $global:CollectedErrors += $errorInfo
    
    # Still display the error immediately for real-time feedback
    Write-StatusMessage "❌ Error #$global:ErrorCount in $FunctionName`: $ErrorMessage" -Color $RED
    
    if ($DebugMode) {
        Write-StatusMessage "   📍 Location: $Location" -Color $GRAY
        if ($Context) {
            Write-StatusMessage "   📝 Context: $Context" -Color $GRAY
        }
        if ($Exception) {
            Write-StatusMessage "   🔍 Exception: $($Exception.GetType().Name) - $($Exception.Message)" -Color $GRAY
        }
    }
}

# Display comprehensive error report at the end
function Show-CollectedErrors {
    if ($global:CollectedErrors.Count -eq 0) {
        Write-StatusMessage "✅ No errors collected during execution" -Color $GREEN
        return
    }
    
    Write-StatusMessage "`n" + ("=" * 100) -Color $RED
    Write-StatusMessage "🚨 COMPREHENSIVE ERROR REPORT - $($global:CollectedErrors.Count) Error(s) Found" -Color $RED
    Write-StatusMessage ("=" * 100) -Color $RED
    
    foreach ($errorInfo in $global:CollectedErrors) {
        Write-StatusMessage "`n📋 ERROR #$($errorInfo.ErrorNumber) - $($errorInfo.Timestamp)" -Color $RED
        Write-StatusMessage "   🎯 Function: $($errorInfo.FunctionName)" -Color $YELLOW
        Write-StatusMessage "   📍 Location: $($errorInfo.Location)" -Color $YELLOW
        Write-StatusMessage "   💬 Message: $($errorInfo.Message)" -Color $CYAN
        
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
    Write-StatusMessage "   Total Errors: $($global:CollectedErrors.Count)" -Color $RED
    Write-StatusMessage "   Functions with Errors: $($global:CollectedErrors | Select-Object -Unique FunctionName | Measure-Object).Count" -Color $YELLOW
    Write-StatusMessage "   Exception Types: $($global:CollectedErrors | Where-Object { $_.ExceptionType -ne 'N/A' } | Select-Object -Unique ExceptionType | Measure-Object).Count" -Color $PURPLE
    
    # Most common error types
    $errorTypes = $global:CollectedErrors | Group-Object -Property ExceptionType | Sort-Object Count -Descending
    if ($errorTypes.Count -gt 0) {
        Write-StatusMessage "   Most Common Error Types:" -Color $BLUE
        foreach ($type in $errorTypes | Select-Object -First 3) {
            Write-StatusMessage "      $($type.Name): $($type.Count) occurrence(s)" -Color $GRAY
        }
    }
    
    Write-StatusMessage "`n💡 DEBUGGING TIPS:" -Color $CYAN
    Write-StatusMessage "   • Run with -DebugMode for more detailed information" -Color $GRAY
    Write-StatusMessage "   • Use -TestMode to avoid making actual changes while debugging" -Color $GRAY
    Write-StatusMessage "   • Check the Location field for exact line numbers" -Color $GRAY
    Write-StatusMessage "   • Review the Context field for operation details" -Color $GRAY
    Write-StatusMessage "   • Exception details provide root cause information" -Color $GRAY
    
    Write-StatusMessage "`n" + ("=" * 100) -Color $RED
}

# Enhanced status message function
function Write-StatusMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Test basic functionality
try {
    Write-StatusMessage "✅ Advanced Copilot PR Monitoring System with Enhanced Error Handling loaded successfully!" -Color $GREEN
    Write-StatusMessage "🔧 Error handling system initialized" -Color $CYAN
    
    # Test error collection
    Add-CollectedError -ErrorMessage "Test error for validation" -FunctionName "Test" -Context "System initialization test"
    
    # Show test results
    Show-CollectedErrors
    
} catch {
    Write-Host "❌ Failed to initialize enhanced error handling: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
