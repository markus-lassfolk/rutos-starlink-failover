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

# Import the enhanced label management module
$labelModulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $labelModulePath) {
    Import-Module $labelModulePath -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Loaded enhanced label management system (100 labels)" -ForegroundColor Green
} else {
    Write-Host "⚠️  Enhanced label management module not found - basic functionality only" -ForegroundColor Yellow
}

# Enhanced status message function with color support
function Write-StatusMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
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

# Enhanced Copilot PR detection with multiple strategies
function Get-CopilotPRs {
    Write-StatusMessage "🔍 Fetching open Copilot PRs with enhanced detection..." -Color $BLUE
    
    try {
        # Get all open PRs with comprehensive data
        $prs = gh pr list --state open --json number,title,headRefName,author,labels,createdAt,updatedAt --limit 100
        
        if ($LASTEXITCODE -ne 0) {
            Add-CollectedError -ErrorMessage "Failed to fetch PR list" -FunctionName "Get-CopilotPRs" -Context "GitHub CLI pr list command failed" -AdditionalInfo @{LastExitCode=$LASTEXITCODE}
            return @()
        }
        
        $prData = $prs | ConvertFrom-Json
        
        # Advanced Copilot PR detection with multiple criteria
        $copilotPRs = $prData | Where-Object { 
            # Check author patterns
            ($_.author.login -match "copilot" -or 
             $_.author.login -eq "app/github-copilot" -or 
             $_.author.login -eq "app/copilot-swe-agent" -or
             $_.author.login -match "github-copilot" -or
             $_.author.login -match "swe-agent") -or
            
            # Check title patterns
            ($_.title -match "copilot" -or
             $_.title -match "Fix" -or
             $_.title -match "automated" -or
             $_.title -match "compatibility") -or
            
            # Check branch patterns
            ($_.headRefName -match "copilot" -or
             $_.headRefName -match "fix-" -or
             $_.headRefName -match "automated") -or
            
            # Check labels
            ($_.labels -and ($_.labels | Where-Object { $_.name -match "copilot" -or $_.name -match "automated" }))
        } | ForEach-Object {
            @{
                Number = $_.number
                Title = $_.title
                HeadRef = $_.headRefName
                Author = $_.author.login
                IsBot = $_.author.is_bot
                CreatedAt = $_.createdAt
                UpdatedAt = $_.updatedAt
                Labels = $_.labels
            }
        }
        
        if ($copilotPRs.Count -eq 0) {
            Write-StatusMessage "ℹ️  No Copilot PRs found using advanced detection" -Color $CYAN
            
            if ($DebugMode) {
                Write-StatusMessage "🔍 Debug: Found $($prData.Count) total PRs, analyzing..." -Color $GRAY
                foreach ($pr in $prData) {
                    Write-StatusMessage "   PR #$($pr.number): Author=$($pr.author.login), IsBot=$($pr.author.is_bot), Title=$($pr.title)" -Color $GRAY
                }
            }
            return @()
        }
        
        Write-StatusMessage "✅ Found $($copilotPRs.Count) Copilot PR(s) using advanced detection" -Color $GREEN
        foreach ($pr in $copilotPRs) {
            $botStatus = if ($pr.IsBot) { "(Bot)" } else { "" }
            Write-StatusMessage "   PR #$($pr.Number): $($pr.Title) by $($pr.Author) $botStatus" -Color $BLUE
        }
        
        return $copilotPRs
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in enhanced Copilot PR detection" -FunctionName "Get-CopilotPRs" -Context "Enhanced Copilot PR detection failed" -Exception $_.Exception
        return @()
    }
}

# Process a single PR with comprehensive automation
function Process-SinglePR {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🎯 Processing PR #$PRNumber with comprehensive automation..." -Color $GREEN
    
    try {
        # Get PR information
        $pr = Get-SpecificPR -PRNumber $PRNumber
        if (-not $pr) {
            Add-CollectedError -ErrorMessage "Could not retrieve PR #$PRNumber" -FunctionName "Process-SinglePR" -Context "PR retrieval failed"
            return $false
        }
        
        Write-StatusMessage "📋 Processing: $($pr.Title)" -Color $BLUE
        
        # Check for merge conflicts and request autonomous resolution
        if ($RequestCopilotForConflicts) {
            $conflictResult = Resolve-MergeConflictsAutonomously -PRNumber $PRNumber
            if ($conflictResult.HasConflicts) {
                Write-StatusMessage "🔧 Autonomous conflict resolution requested" -Color $YELLOW
            }
        }
        
        # Transfer labels from original issue
        if (-not $SkipValidation) {
            $labelResult = Transfer-IssueLabels -PRNumber $PRNumber -PRTitle $pr.Title
            if ($labelResult.Success) {
                Write-StatusMessage "✅ Label transfer completed" -Color $GREEN
            }
        }
        
        # Trigger and approve workflows
        if (-not $SkipWorkflowApproval) {
            $workflowResult = Trigger-WorkflowRuns -PRNumber $PRNumber -HeadRef $pr.HeadRef
            if ($workflowResult.Success) {
                Write-StatusMessage "✅ Workflows triggered successfully" -Color $GREEN
            } else {
                Add-CollectedError -ErrorMessage "PR #$PRNumber workflow failed" -FunctionName "Process-SinglePR" -Context "Workflow triggering failed" -AdditionalInfo @{PRNumber=$PRNumber; Error=$workflowResult.Error}
            }
        }
        
        return $true
        
    } catch {
        Add-CollectedError -ErrorMessage "Error processing PR #$PRNumber" -FunctionName "Process-SinglePR" -Context "Single PR processing failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return $false
    }
}

# Continuous monitoring loop with intelligent automation
function Start-CopilotPRMonitoring {
    param(
        [int]$IntervalSeconds = 300,
        [int]$MaxIterations = 0  # 0 means infinite
    )
    
    Write-StatusMessage "🤖 Starting intelligent Copilot PR monitoring..." -Color $GREEN
    Write-StatusMessage "⏱️  Check interval: $IntervalSeconds seconds" -Color $CYAN
    Write-StatusMessage "🔄 Max iterations: $(if ($MaxIterations -eq 0) { 'Infinite' } else { $MaxIterations })" -Color $CYAN
    Write-StatusMessage "🎯 Monitor only mode: $MonitorOnly" -Color $CYAN
    
    $iteration = 0
    
    do {
        $iteration++
        Write-StatusMessage "`n🔄 [Iteration $iteration] Starting monitoring cycle..." -Color $PURPLE
        
        try {
            # Fetch Copilot PRs
            $copilotPRs = Get-CopilotPRs
            
            if ($copilotPRs.Count -eq 0) {
                Write-StatusMessage "ℹ️  No Copilot PRs found in this cycle" -Color $CYAN
            } else {
                Write-StatusMessage "📋 Found $($copilotPRs.Count) Copilot PR(s) to process" -Color $GREEN
                
                # Process each PR unless in monitor-only mode
                foreach ($pr in $copilotPRs) {
                    if ($MonitorOnly) {
                        Write-StatusMessage "👀 [MONITOR ONLY] Found PR #$($pr.Number): $($pr.Title)" -Color $YELLOW
                    } else {
                        $workflowResult = Process-SinglePR -PRNumber $pr.Number
                        if (-not $workflowResult) {
                            Add-CollectedError -ErrorMessage "PR #$($pr.Number) workflow failed" -FunctionName "Start-CopilotPRMonitoring" -Context "PR processing failed in monitoring loop" -AdditionalInfo @{PRNumber=$pr.Number; Error=$workflowResult.Error}
                        }
                    }
                }
            }
            
        } catch {
            Add-CollectedError -ErrorMessage "[Iteration $iteration] Error in monitoring cycle" -FunctionName "Start-CopilotPRMonitoring" -Context "Monitoring cycle exception" -Exception $_.Exception -AdditionalInfo @{Iteration=$iteration}
        }
        
        # Sleep before next iteration (unless it's the last one)
        if ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations) {
            Write-StatusMessage "💤 Sleeping for $IntervalSeconds seconds before next cycle..." -Color $GRAY
            Start-Sleep -Seconds $IntervalSeconds
        }
        
    } while ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations)
    
    Write-StatusMessage "🏁 Monitoring completed after $iteration iteration(s)" -Color $GREEN
}

# Get specific PR by number
function Get-SpecificPR {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🔍 Fetching specific PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get PR information
        $prInfo = gh pr view $PRNumber --json number,title,headRefName,author,labels,createdAt,updatedAt,state
        
        if ($LASTEXITCODE -ne 0) {
            Add-CollectedError -ErrorMessage "Failed to fetch PR #$PRNumber" -FunctionName "Get-SpecificPR" -Context "GitHub CLI pr view command failed" -AdditionalInfo @{PRNumber=$PRNumber; LastExitCode=$LASTEXITCODE}
            return $null
        }
        
        $prData = $prInfo | ConvertFrom-Json
        
        # Check if PR is open
        if ($prData.state -ne "OPEN") {
            Write-StatusMessage "⚠️  PR #$PRNumber is not open (state: $($prData.state))" -Color $YELLOW
            return $null
        }
        
        # Convert to standard format
        $pr = @{
            Number = $prData.number
            Title = $prData.title
            HeadRef = $prData.headRefName
            Author = $prData.author.login
            IsBot = $prData.author.is_bot
            CreatedAt = $prData.createdAt
            UpdatedAt = $prData.updatedAt
            Labels = $prData.labels
        }
        
        $botStatus = if ($pr.IsBot) { "(Bot)" } else { "" }
        Write-StatusMessage "✅ Found PR #$($pr.Number): $($pr.Title) by $($pr.Author) $botStatus" -Color $GREEN
        
        return $pr
        
    } catch {
        Add-CollectedError -ErrorMessage "Error fetching PR #$PRNumber" -FunctionName "Get-SpecificPR" -Context "Single PR fetch operation failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return $null
    }
}

# Transfer labels from original issue to Copilot PR
function Transfer-IssueLabels {
    param(
        [int]$PRNumber,
        [string]$PRTitle
    )
    
    Write-StatusMessage "🏷️  Checking for labels to transfer from original issue to PR #$PRNumber..." -Color $BLUE
    
    try {
        # Extract issue number from PR title if it exists
        $issueNumber = $null
        if ($PRTitle -match "#(\d+)") {
            $issueNumber = $Matches[1]
        }
        
        if (-not $issueNumber) {
            Write-StatusMessage "ℹ️  No issue reference found in PR title - skipping label transfer" -Color $CYAN
            return @{ Success = $false; Reason = "No issue reference found" }
        }
        
        Write-StatusMessage "🔍 Found issue reference #$issueNumber in PR title - fetching issue labels..." -Color $BLUE
        
        # Get issue labels
        $issueLabels = gh issue view $issueNumber --json labels --jq '.labels[].name' 2>$null
        
        if (-not $issueLabels -or $issueLabels.Count -eq 0) {
            Write-StatusMessage "ℹ️  No labels found on issue #$issueNumber" -Color $CYAN
            return @{ Success = $false; Reason = "No labels on issue" }
        }
        
        $labelList = $issueLabels -split "`n" | Where-Object { $_ -ne "" }
        Write-StatusMessage "📋 Found $($labelList.Count) labels on issue #$issueNumber" -Color $BLUE
        
        # Get current PR labels
        $currentPRLabels = gh pr view $PRNumber --json labels --jq '.labels[].name' 2>$null
        $currentLabels = if ($currentPRLabels) { $currentPRLabels -split "`n" | Where-Object { $_ -ne "" } } else { @() }
        
        # Filter labels to transfer (exclude labels that are already on the PR)
        $labelsToTransfer = $labelList | Where-Object { $_ -notin $currentLabels }
        
        if ($labelsToTransfer.Count -eq 0) {
            Write-StatusMessage "ℹ️  All relevant labels already exist on PR #$PRNumber" -Color $CYAN
            return @{ Success = $true; Reason = "All labels already present" }
        }
        
        Write-StatusMessage "🏷️  Transferring $($labelsToTransfer.Count) labels from issue #$issueNumber to PR #$PRNumber..." -Color $GREEN
        
        # Transfer labels to PR
        foreach ($label in $labelsToTransfer) {
            Write-StatusMessage "   Adding label: $label" -Color $CYAN
            $result = gh pr edit $PRNumber --add-label "$label" 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-StatusMessage "⚠️  Failed to add label '$label': $result" -Color $YELLOW
            }
        }
        
        Write-StatusMessage "✅ Successfully transferred labels from issue #$issueNumber to PR #$PRNumber" -Color $GREEN
        
        return @{ 
            Success = $true; 
            IssueNumber = $issueNumber; 
            TransferredLabels = $labelsToTransfer.Count 
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error transferring labels" -FunctionName "Transfer-IssueLabels" -Context "Label transfer operation failed" -Exception $_.Exception -AdditionalInfo @{IssueNumber=$IssueNumber; PRNumber=$PRNumber}
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Trigger workflow runs for a PR
function Trigger-WorkflowRuns {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🚀 Triggering workflow runs for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get existing workflow runs
        $runs = gh run list --branch $HeadRef --json databaseId,status,conclusion,workflowName,createdAt,updatedAt --limit 10 | ConvertFrom-Json
        
        if ($runs.Count -eq 0) {
            Write-StatusMessage "ℹ️  No workflow runs found for PR #$PRNumber" -Color $CYAN
            # Try to trigger workflows by creating an empty commit
            Write-StatusMessage "🔄 Creating trigger comment to start workflows..." -Color $CYAN
            
            $triggerComment = "🚀 **Workflow Trigger Request**`n`nTrigger GitHub Actions workflows for this PR.`n`n*This comment was automatically generated to trigger workflows.*"
            gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$triggerComment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Posted trigger comment" -Color $GREEN
                return @{ Success = $true; Error = $null; TriggeredCount = 1 }
            } else {
                return @{ Success = $false; Error = "Failed to post trigger comment"; TriggeredCount = 0 }
            }
        }
        
        Write-StatusMessage "📋 Found $($runs.Count) workflow run(s) for PR #$PRNumber" -Color $BLUE
        
        # Check for pending runs that need approval
        $pendingRuns = $runs | Where-Object { 
            $_.status -eq "waiting" -or 
            ($_.status -eq "completed" -and $_.conclusion -eq "action_required")
        }
        
        if ($pendingRuns.Count -gt 0) {
            Write-StatusMessage "🔓 Found $($pendingRuns.Count) workflow(s) needing approval..." -Color $CYAN
            Write-StatusMessage "⚠️  These workflows require manual approval through GitHub web interface" -Color $YELLOW
            
            foreach ($run in $pendingRuns) {
                $statusMsg = if ($run.status -eq "waiting") { "waiting" } else { "action_required" }
                Write-StatusMessage "   🔓 Workflow needs approval: $($run.workflowName) (Status: $statusMsg)" -Color $CYAN
                Write-StatusMessage "   🌐 Manual approval: https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$($run.databaseId)" -Color $BLUE
            }
            
            return @{ Success = $true; Error = $null; TriggeredCount = $pendingRuns.Count; ManualApprovalRequired = $true }
        }
        
        # Check for active runs
        $activeRuns = $runs | Where-Object { $_.status -in @("queued", "in_progress") }
        if ($activeRuns.Count -gt 0) {
            Write-StatusMessage "⚡ Found $($activeRuns.Count) active workflow run(s) - no triggering needed" -Color $GREEN
            return @{ Success = $true; Error = $null; TriggeredCount = $activeRuns.Count }
        }
        
        Write-StatusMessage "✅ Workflows are available and running for PR #$PRNumber" -Color $GREEN
        return @{ Success = $true; Error = $null; TriggeredCount = $runs.Count }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error triggering workflows" -FunctionName "Trigger-WorkflowRuns" -Context "Workflow triggering failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{ Success = $false; Error = $_.Exception.Message; TriggeredCount = 0 }
    }
}

# Autonomous merge conflict resolution using Copilot
function Resolve-MergeConflictsAutonomously {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🔍 Checking for merge conflicts in PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get PR mergeable status
        $prInfo = gh pr view $PRNumber --json mergeable,mergeStateStatus,state | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            Add-CollectedError -ErrorMessage "Failed to get PR merge status for #$PRNumber" -FunctionName "Resolve-MergeConflictsAutonomously" -Context "GitHub CLI pr view failed" -AdditionalInfo @{PRNumber=$PRNumber}
            return @{ Success = $false; HasConflicts = $false; Error = "Failed to get PR status" }
        }
        
        $mergeable = $prInfo.mergeable
        $mergeState = $prInfo.mergeStateStatus
        
        Write-StatusMessage "   📊 PR #$PRNumber merge status: mergeable=$mergeable, state=$mergeState" -Color $CYAN
        
        # Check if there are merge conflicts
        if ($mergeable -eq "CONFLICTING" -or $mergeState -eq "DIRTY") {
            Write-StatusMessage "⚠️  Merge conflicts detected in PR #$PRNumber!" -Color $YELLOW
            
            # Request Copilot to resolve conflicts autonomously
            $conflictResolutionComment = @"
🤖 **Autonomous Conflict Resolution Request**

@copilot resolve merge conflicts and push the fixed version.

**Context:**
- PR #$PRNumber has merge conflicts that need resolution
- The autonomous monitoring system detected: mergeable=$mergeable, state=$mergeState
- Please resolve all conflicts while preserving the intent of both branches
- Focus on RUTOS compatibility and maintain existing functionality
- Push the resolved version to continue the automation pipeline

**Instructions:**
- Resolve all merge conflicts in the affected files
- Ensure RUTOS compatibility is maintained
- Preserve all functionality from both branches
- Test the resolution for syntax correctness
- Push the fixed version to the PR branch

*This request was automatically generated by the autonomous PR monitoring system.*
"@
            
            Write-StatusMessage "🤖 Requesting Copilot to resolve conflicts autonomously..." -Color $BLUE
            
            # Post comment to request Copilot assistance
            $result = gh pr comment $PRNumber --body $conflictResolutionComment 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Autonomous conflict resolution request posted successfully" -Color $GREEN
                Write-StatusMessage "🔄 Copilot will resolve conflicts and push fixes automatically" -Color $CYAN
                
                # Trigger the autonomous-copilot workflow to ensure it processes this immediately
                Write-StatusMessage "🚀 Triggering autonomous-copilot workflow..." -Color $BLUE
                $workflowTrigger = gh workflow run autonomous-copilot.yml --ref main 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "✅ Autonomous workflow triggered successfully" -Color $GREEN
                } else {
                    Write-StatusMessage "⚠️  Could not trigger autonomous workflow, but comment posted" -Color $YELLOW
                }
                
                return @{ 
                    Success = $true
                    HasConflicts = $true
                    ConflictResolutionRequested = $true
                    Message = "Copilot requested to resolve conflicts autonomously"
                }
            } else {
                Add-CollectedError -ErrorMessage "Failed to post conflict resolution comment" -FunctionName "Resolve-MergeConflictsAutonomously" -Context "GitHub CLI comment failed" -AdditionalInfo @{PRNumber=$PRNumber; Error=$result}
                return @{ Success = $false; HasConflicts = $true; Error = "Failed to request Copilot assistance" }
            }
            
        } elseif ($mergeable -eq "MERGEABLE") {
            Write-StatusMessage "✅ No merge conflicts detected in PR #$PRNumber" -Color $GREEN
            return @{ Success = $true; HasConflicts = $false; Message = "No conflicts detected" }
        } else {
            Write-StatusMessage "🔄 PR #$PRNumber merge status unclear: $mergeable (state: $mergeState)" -Color $CYAN
            return @{ Success = $true; HasConflicts = $false; Message = "Merge status unclear - may be checking" }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error checking merge conflicts" -FunctionName "Resolve-MergeConflictsAutonomously" -Context "Autonomous conflict resolution failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{ Success = $false; HasConflicts = $false; Error = $_.Exception.Message }
    }
}

# Main execution with enhanced error handling
try {
    # Validate environment
    if (-not (Test-Path ".git")) {
        Add-CollectedError -ErrorMessage "This script must be run from the repository root" -FunctionName "Main" -Context "Environment validation failed - .git directory not found"
        exit 1
    }
    
    # Check GitHub CLI availability
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Add-CollectedError -ErrorMessage "GitHub CLI (gh) is not installed or not in PATH" -FunctionName "Main" -Context "GitHub CLI dependency check failed"
        Write-StatusMessage "📋 Install: https://cli.github.com/" -Color $CYAN
        exit 1
    }
    
    # Verify GitHub CLI authentication
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Add-CollectedError -ErrorMessage "GitHub CLI is not authenticated" -FunctionName "Main" -Context "GitHub CLI authentication check failed" -AdditionalInfo @{LastExitCode=$LASTEXITCODE}
        Write-StatusMessage "🔐 Run: gh auth login" -Color $CYAN
        exit 1
    }
    
    # Display configuration
    Write-StatusMessage "🔧 Configuration:" -Color $CYAN
    Write-StatusMessage "   VerboseOutput: $VerboseOutput" -Color $GRAY
    Write-StatusMessage "   SkipValidation: $SkipValidation" -Color $GRAY
    Write-StatusMessage "   RequestCopilotForConflicts: $RequestCopilotForConflicts" -Color $GRAY
    Write-StatusMessage "   SkipWorkflowApproval: $SkipWorkflowApproval" -Color $GRAY
    Write-StatusMessage "   ForceValidation: $ForceValidation" -Color $GRAY
    Write-StatusMessage "   MonitorOnly: $MonitorOnly" -Color $GRAY
    Write-StatusMessage "   TestMode: $TestMode" -Color $GRAY
    Write-StatusMessage "   DebugMode: $DebugMode" -Color $GRAY
    
    # Run the intelligent monitoring system
    if ($PRNumber) {
        Write-StatusMessage "🎯 Processing specific PR #$PRNumber..." -Color $GREEN
        $singlePRResult = Process-SinglePR -PRNumber $PRNumber
        
        if ($singlePRResult) {
            Write-StatusMessage "✅ Single PR processing completed successfully" -Color $GREEN
            exit 0
        } else {
            Add-CollectedError -ErrorMessage "Single PR processing failed" -FunctionName "Main" -Context "Single PR processing returned false/null" -AdditionalInfo @{PRNumber=$PRNumber}
            exit 1
        }
    } elseif ($MonitorOnly) {
        Write-StatusMessage "📊 Running in monitor-only mode - no automation actions will be taken" -Color $YELLOW
        Start-CopilotPRMonitoring -IntervalSeconds 300 -MaxIterations 1
    } else {
        Write-StatusMessage "🤖 Running full intelligent PR monitoring with automation..." -Color $GREEN
        Start-CopilotPRMonitoring -IntervalSeconds 300 -MaxIterations 0
    }
    
} catch {
    Add-CollectedError -ErrorMessage $_.Exception.Message -FunctionName "Main" -Context "Advanced monitoring system execution" -Exception $_.Exception
    exit 1
} finally {
    # Show comprehensive error report at the end
    Show-CollectedErrors
}
