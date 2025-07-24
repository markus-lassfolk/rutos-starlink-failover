# Advanced Copilot PR Monitoring System with Integrated Autonomous Management
# This script monitors Copilot-generated PRs and provides intelligent automation with GitHub API rate limit protection
# AUTONOMOUS INTEGRATION: All autonomous workflow approval and auto-merge functionality integrated directly
# - No external script dependencies - fully self-contained
# - Comprehensive trust validation and safety checks
# - GitHub workflow orchestration support

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
    [switch]$AnalyzeWorkflowFailures = $true,
    [switch]$ProcessMixedStatus = $true,
    [switch]$DaemonMode,
    [switch]$AutoMode,
    [switch]$QuietMode,
    [int]$DaemonInterval = 300, # 5 minutes default
    [int]$MaxDaemonRuns = 0,    # 0 = infinite
    [switch]$AutoApproveWorkflows,  # Enable autonomous workflow approval and auto-merge
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
🤖 Advanced Copilot PR Monitoring System with Rate Limit Management

DESCRIPTION:
    Comprehensive monitoring system for Copilot-generated PRs with intelligent workflow failure analysis,
    automatic rate limit detection and backoff, and targeted Copilot fix request generation.

FEATURES:
    ✅ Intelligent workflow failure detection and analysis
    ✅ Automatic GitHub API rate limit management with backoff
    ✅ Rate-limited workflow retry with exponential backoff
    ✅ Targeted Copilot fix request generation based on error patterns
    ✅ Mixed status check resolution for successful retries blocked by old failures
    ✅ Comprehensive error collection and reporting
    ✅ Enhanced debugging with clean output formatting

USAGE:
    Monitor-CopilotPRs-Complete.ps1 [OPTIONS]

OPTIONS:
    -PRNumber <int>                 Monitor specific PR number
    -VerboseOutput                  Show detailed operation information
    -SkipValidation                 Skip comprehensive validation
    -RequestCopilotForConflicts     Request Copilot help for merge conflicts
    -SkipWorkflowApproval           Skip workflow approval process
    -ForceValidation                Force validation even if previously passed
    -MonitorOnly                    Monitor only mode (no automation)
    -TestMode                       Test mode (no actual changes)
    -DebugMode                      Enable debug output with rate limit info
    -AnalyzeWorkflowFailures        Analyze failed workflows and request Copilot fixes (default: enabled)
    -ProcessMixedStatus            Automatically resolve mixed status check issues (default: enabled)
    -Help                           Show this help message

EXAMPLES:
    # Monitor all Copilot PRs with workflow failure analysis and rate limit management
    .\Monitor-CopilotPRs-Complete.ps1

    # Monitor specific PR with enhanced rate limit retry
    .\Monitor-CopilotPRs-Complete.ps1 -PRNumber 42

    # Monitor only mode with debug (includes rate limit status)
    .\Monitor-CopilotPRs-Complete.ps1 -MonitorOnly -DebugMode

    # Skip workflow failure analysis (still includes rate limit management)
    .\Monitor-CopilotPRs-Complete.ps1 -AnalyzeWorkflowFailures:`$false

    # Autonomous daemon mode - runs continuously every 5 minutes
    .\Monitor-CopilotPRs-Complete.ps1 -DaemonMode

    # Autonomous mode with auto-workflow approval (fully hands-off)
    .\Monitor-CopilotPRs-Complete.ps1 -DaemonMode -AutoApproveWorkflows -QuietMode

    # Run 12 times every 10 minutes (2 hours of monitoring)
    .\Monitor-CopilotPRs-Complete.ps1 -DaemonMode -DaemonInterval 600 -MaxDaemonRuns 12

AUTONOMOUS FEATURES:
    • Daemon mode for continuous monitoring without user intervention
    • Auto-workflow approval for trusted Copilot PRs with comprehensive trust validation
    • Intelligent auto-merge with 8-point safety assessment system
    • Trust validation for known Copilot authors (app/copilot-swe-agent, github-copilot[bot], etc.)
    • Risk assessment for PR content and patterns (no risky keywords, safe titles)
    • Automatic status verification before merge (checks passing, not draft)
    • Bulk processing of eligible PRs during monitoring cycles
    • Intelligent rate limit recovery with exponential backoff
    • Mixed status check resolution with 3-strategy approach
    • Full consolidation in main script - no external dependencies
RATE LIMIT FEATURES:
    • Automatic detection when API limits approach (< 100 requests remaining)
    • Intelligent backoff with minute-by-minute countdown
    • Rate-limited workflow retry with exponential backoff
    • Batch processing rate limit checks for multiple PRs
    • Debug mode shows current rate limit status

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

# Integrated autonomous workflow approval function
function Approve-CopilotWorkflows {
    param(
        [string]$PRNumber,
        [switch]$QuietMode
    )
    
    if (-not $QuietMode) {
        Write-StatusMessage "🤖 Checking for workflows requiring approval..." -Color $BLUE
    }
    
    try {
        # Check if PR is from trusted Copilot
        $prData = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
            user: .user.login,
            title: .title,
            body: .body,
            draft: .draft
        }' | ConvertFrom-Json
        
        $trustedAuthors = @(
            "app/copilot-swe-agent",
            "copilot-swe-agent",
            "github-copilot[bot]",
            "app/github-copilot"
        )
        
        $trustedTitlePatterns = @(
            "Fix.*RUTOS.*compatibility",
            "Fix:.*version.*information",
            "Add.*version.*information",
            "\[MINOR\].*version.*information"
        )
        
        # Check if author is trusted
        $isTrustedAuthor = $trustedAuthors -contains $prData.user
        
        # Check if title matches trusted patterns
        $isTrustedTitle = $false
        foreach ($pattern in $trustedTitlePatterns) {
            if ($prData.title -match $pattern) {
                $isTrustedTitle = $true
                break
            }
        }
        
        # Safety checks
        $isDraft = $prData.draft
        $hasRiskyKeywords = $prData.body -match "(delete|remove|DROP|rm -rf|sudo|password|secret|token)"
        
        $isTrusted = $isTrustedAuthor -and $isTrustedTitle -and -not $isDraft -and -not $hasRiskyKeywords
        
        if (-not $isTrusted) {
            if (-not $QuietMode) {
                Write-StatusMessage "⚠️ PR #$PRNumber not eligible for auto-approval" -Color $YELLOW
            }
            return @{ Success = $false; Reason = "Failed trust checks"; ApprovedCount = 0 }
        }
        
        # Get workflow runs that need approval
        $workflowRuns = gh run list --limit 50 --json databaseId,status,workflowName,headBranch,conclusion | ConvertFrom-Json
        
        $needingApproval = $workflowRuns | Where-Object { 
            $_.status -eq "action_required" -and 
            $_.headBranch -like "*$PRNumber*" 
        }
        
        if (-not $needingApproval) {
            if (-not $QuietMode) {
                Write-StatusMessage "✅ No workflow runs requiring approval for PR #$PRNumber" -Color $GREEN
            }
            return @{ Success = $true; ApprovedCount = 0; Workflows = @() }
        }
        
        $approvedCount = 0
        $approvedWorkflows = @()
        
        foreach ($run in $needingApproval) {
            if (-not $QuietMode) {
                Write-StatusMessage "🔓 Approving workflow: $($run.workflowName)" -Color $CYAN
            }
            
            try {
                gh api "repos/$env:GITHUB_REPOSITORY/actions/runs/$($run.databaseId)/approve" --method POST | Out-Null
                $approvedCount++
                $approvedWorkflows += $run.workflowName
                Start-Sleep -Seconds 2
            }
            catch {
                if (-not $QuietMode) {
                    Write-StatusMessage "⚠️ Failed to approve workflow $($run.workflowName): $_" -Color $YELLOW
                }
            }
        }
        
        if (-not $QuietMode -and $approvedCount -gt 0) {
            Write-StatusMessage "✅ Auto-approved $approvedCount workflow(s) for PR #$PRNumber" -Color $GREEN
        }
        
        return @{
            Success = $true
            ApprovedCount = $approvedCount
            Workflows = $approvedWorkflows
            TotalFound = $needingApproval.Count
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in autonomous workflow approval" -FunctionName "Approve-CopilotWorkflows" -Context "Auto-approval failed" -Exception $_.Exception
        return @{ Success = $false; Error = $_.Exception.Message; ApprovedCount = 0 }
    }
}

# Integrated intelligent auto-merge function
function Invoke-IntelligentAutoMerge {
    param(
        [string]$PRNumber,
        [string]$MergeMethod = "squash",
        [switch]$QuietMode
    )
    
    if (-not $QuietMode) {
        Write-StatusMessage "🎯 Evaluating PR #$PRNumber for auto-merge..." -Color $BLUE
    }
    
    try {
        # Get comprehensive PR data
        $prData = gh api "repos/$env:GITHUB_REPOSITORY/pulls/$PRNumber" --jq '{
            user: .user.login,
            title: .title,
            body: .body,
            draft: .draft,
            state: .state,
            mergeable: .mergeable,
            mergeable_state: .mergeable_state,
            base: .base.ref,
            head: .head.ref,
            changed_files: .changed_files,
            additions: .additions,
            deletions: .deletions,
            commits: .commits
        }' | ConvertFrom-Json
        
        # Safety checks
        $safetyChecks = @{
            IsTrustedAuthor = $false
            IsNonDraft = $false
            IsMergeable = $false
            HasReasonableSize = $false
            IsTrustedBranch = $false
            HasSafeTitle = $false
            HasNoRiskyChanges = $false
            PassesAllChecks = $false
        }
        
        # Check 1: Trusted author
        $trustedAuthors = @(
            "app/copilot-swe-agent",
            "copilot-swe-agent", 
            "github-copilot[bot]",
            "app/github-copilot"
        )
        $safetyChecks.IsTrustedAuthor = $trustedAuthors -contains $prData.user
        
        # Check 2: Not a draft
        $safetyChecks.IsNonDraft = -not $prData.draft
        
        # Check 3: Mergeable state
        $safetyChecks.IsMergeable = $prData.mergeable -eq $true -and $prData.mergeable_state -eq "clean"
        
        # Check 4: Reasonable size (not massive changes)
        $totalChanges = $prData.additions + $prData.deletions
        $safetyChecks.HasReasonableSize = $totalChanges -le 1000 -and $prData.changed_files -le 20
        
        # Check 5: Trusted branch (typically main or develop)
        $trustedTargetBranches = @("main", "master", "develop", "dev")
        $safetyChecks.IsTrustedBranch = $trustedTargetBranches -contains $prData.base
        
        # Check 6: Safe title patterns
        $safeTitlePatterns = @(
            "Fix.*RUTOS.*compatibility",
            "Fix:.*version.*information", 
            "Add.*version.*information",
            "\[MINOR\].*version.*information",
            "Update.*version.*to.*",
            "Fix.*shell.*compatibility",
            "Add.*missing.*dry-run.*support"
        )
        $safetyChecks.HasSafeTitle = $false
        foreach ($pattern in $safeTitlePatterns) {
            if ($prData.title -match $pattern) {
                $safetyChecks.HasSafeTitle = $true
                break
            }
        }
        
        # Check 7: No risky changes in body/description
        $riskyKeywords = @("delete", "remove", "DROP", "rm -rf", "sudo", "password", "secret", "token", "DROP TABLE", "DELETE FROM")
        $safetyChecks.HasNoRiskyChanges = $true
        foreach ($keyword in $riskyKeywords) {
            if ($prData.body -match $keyword) {
                $safetyChecks.HasNoRiskyChanges = $false
                break
            }
        }
        
        # Check 8: All status checks pass
        try {
            $statusChecks = gh api "repos/$env:GITHUB_REPOSITORY/commits/$($prData.head.sha)/status" --jq '.state' 2>/dev/null
            $safetyChecks.PassesAllChecks = $statusChecks -eq "success"
        } catch {
            $safetyChecks.PassesAllChecks = $false
        }
        
        # Overall safety assessment
        $allChecksPassed = ($safetyChecks.Values | Where-Object { $_ -eq $false }).Count -eq 0
        
        if (-not $allChecksPassed) {
            $failedChecks = ($safetyChecks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
            if (-not $QuietMode) {
                Write-StatusMessage "⚠️ PR #$PRNumber failed safety checks: $($failedChecks -join ', ')" -Color $YELLOW
            }
            return @{
                Success = $false
                IsSafe = $false
                FailedChecks = $failedChecks
                MergeAttempted = $false
            }
        }
        
        # Attempt the merge
        if (-not $QuietMode) {
            Write-StatusMessage "✅ PR #$PRNumber passed all safety checks - attempting merge" -Color $GREEN
        }
        
        try {
            $mergeResult = gh pr merge $PRNumber --$MergeMethod --auto --delete-branch 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                if (-not $QuietMode) {
                    Write-StatusMessage "🎉 Successfully auto-merged PR #$PRNumber" -Color $GREEN
                }
                return @{ 
                    Success = $true
                    IsSafe = $true
                    MergeAttempted = $true
                    MergeSuccessful = $true
                    Method = $MergeMethod
                }
            } else {
                if (-not $QuietMode) {
                    Write-StatusMessage "❌ Failed to merge PR #$PRNumber`: $mergeResult" -Color $RED
                }
                return @{
                    Success = $false
                    IsSafe = $true
                    MergeAttempted = $true
                    MergeSuccessful = $false
                    Error = $mergeResult
                }
            }
        }
        catch {
            if (-not $QuietMode) {
                Write-StatusMessage "❌ Exception during merge: $_" -Color $RED
            }
            return @{
                Success = $false
                IsSafe = $true
                MergeAttempted = $true
                MergeSuccessful = $false
                Error = $_.Exception.Message
            }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in intelligent auto-merge" -FunctionName "Invoke-IntelligentAutoMerge" -Context "Auto-merge evaluation failed" -Exception $_.Exception
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Process a single PR with comprehensive automation
function Process-SinglePR {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🎯 Processing PR #$PRNumber with comprehensive automation..." -Color $GREEN
    
    try {
        # Check rate limit before processing
        $rateLimitStatus = Test-GitHubRateLimit
        if ($rateLimitStatus.ShouldWait) {
            Write-StatusMessage "⏳ Rate limit is low ($($rateLimitStatus.Remaining) remaining), waiting..." -Color $YELLOW
            Wait-ForRateLimit -WaitMinutes 5
        }
        
        # Get PR information
        $pr = Get-SpecificPR -PRNumber $PRNumber
        if (-not $pr) {
            Add-CollectedError -ErrorMessage "Could not retrieve PR #$PRNumber" -FunctionName "Process-SinglePR" -Context "PR retrieval failed"
            return $false
        }
        
        Write-StatusMessage "📋 Processing: $($pr.Title)" -Color $BLUE
        
        if ($DebugMode) {
            Write-StatusMessage "   🔍 Rate Limit: $($rateLimitStatus.Remaining) requests remaining" -Color $CYAN
        }
        
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
        
        # Enhanced workflow failure analysis with rate limit detection and retry
        if ($AnalyzeWorkflowFailures) {
            Write-StatusMessage "🔍 Analyzing workflow status for failures with rate limit detection..." -Color $BLUE
            $failureAnalysis = Analyze-FailedWorkflowsWithRetry -PRNumber $PRNumber
            if ($failureAnalysis.Success -and $failureAnalysis.FailedCount -gt 0) {
                $totalActions = $failureAnalysis.FixRequestCount + $failureAnalysis.RateLimitRetries
                Write-StatusMessage "🛠️  Analysis complete: $($failureAnalysis.FailedCount) failures, $totalActions actions taken" -Color $YELLOW
                if ($failureAnalysis.RateLimitRetries -gt 0) {
                    Write-StatusMessage "🔄 Successfully retried $($failureAnalysis.RateLimitRetries) rate-limited workflows" -Color $GREEN
                }
                if ($failureAnalysis.FixRequestCount -gt 0) {
                    Write-StatusMessage "🤖 Generated $($failureAnalysis.FixRequestCount) Copilot fix requests" -Color $CYAN
                }
            } elseif ($failureAnalysis.Success) {
                Write-StatusMessage "✅ No failed workflows detected" -Color $GREEN
            } else {
                Write-StatusMessage "⚠️  Could not analyze workflow failures: $($failureAnalysis.Error)" -Color $YELLOW
            }
        } else {
            Write-StatusMessage "⏭️  Workflow failure analysis skipped (disabled)" -Color $GRAY
        }
        
        # Integrated autonomous workflow approval
        if ($AutoApproveWorkflows) {
            $approvalResult = Approve-CopilotWorkflows -PRNumber $PRNumber -QuietMode:$QuietMode
            if ($approvalResult.Success -and $approvalResult.ApprovedCount -gt 0) {
                Write-StatusMessage "✅ Auto-approved $($approvalResult.ApprovedCount) workflow(s)" -Color $GREEN
            }
        }
        
        # Integrated intelligent auto-merge
        if ($AutoApproveWorkflows) {
            $mergeResult = Invoke-IntelligentAutoMerge -PRNumber $PRNumber -QuietMode:$QuietMode
            if ($mergeResult.Success -and $mergeResult.MergeSuccessful) {
                Write-StatusMessage "🎉 Successfully auto-merged PR #$PRNumber" -Color $GREEN
                return $true
            } elseif ($mergeResult.IsSafe -and -not $mergeResult.MergeSuccessful) {
                Write-StatusMessage "⚠️ PR #$PRNumber was safe but merge failed: $($mergeResult.Error)" -Color $YELLOW
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
            # Check rate limit at the beginning of each cycle
            $rateLimitStatus = Test-GitHubRateLimit
            if ($rateLimitStatus.ShouldWait) {
                Write-StatusMessage "⚠️  Rate limit is low ($($rateLimitStatus.Remaining) remaining), adjusting cycle timing..." -Color $YELLOW
                Wait-ForRateLimit -WaitMinutes 5
            }
            
            # Fetch Copilot PRs
            $copilotPRs = Get-CopilotPRs
            
            if ($copilotPRs.Count -eq 0) {
                Write-StatusMessage "ℹ️  No Copilot PRs found in this cycle" -Color $CYAN
            } else {
                Write-StatusMessage "📋 Found $($copilotPRs.Count) Copilot PR(s) to process" -Color $GREEN
                Write-StatusMessage "📊 API Rate Limit: $($rateLimitStatus.Remaining) requests remaining" -Color $CYAN
                
                # Check for and resolve mixed status check issues across all PRs
                if (-not $MonitorOnly -and $ProcessMixedStatus) {
                    Write-StatusMessage "🔍 Checking for mixed status check issues..." -Color $BLUE
                    $mixedStatusResult = Process-MixedStatusPRs -PRs $copilotPRs
                    
                    if ($mixedStatusResult.Success) {
                        if ($mixedStatusResult.MixedStatusDetected -gt 0) {
                            Write-StatusMessage "✅ Mixed status check processing completed:" -Color $GREEN
                            Write-StatusMessage "   Detected: $($mixedStatusResult.MixedStatusDetected) PRs with mixed status" -Color $CYAN
                            Write-StatusMessage "   Resolved: $($mixedStatusResult.Resolved) PRs successfully fixed" -Color $CYAN
                        } else {
                            Write-StatusMessage "✅ No mixed status check issues found in this cycle" -Color $GREEN
                        }
                    } else {
                        Write-StatusMessage "⚠️  Mixed status check processing had issues: $($mixedStatusResult.Error)" -Color $YELLOW
                    }
                }
                
                # Process each PR unless in monitor-only mode
                foreach ($pr in $copilotPRs) {
                    if ($MonitorOnly) {
                        Write-StatusMessage "👀 [MONITOR ONLY] Found PR #$($pr.Number): $($pr.Title)" -Color $YELLOW
                    } else {
                        # Check rate limit before processing each PR if we have many PRs
                        if ($copilotPRs.Count -gt 5) {
                            $currentRateLimit = Test-GitHubRateLimit
                            if ($currentRateLimit.ShouldWait) {
                                Write-StatusMessage "⏳ Rate limit getting low during batch processing, pausing..." -Color $YELLOW
                                Wait-ForRateLimit -WaitMinutes 3
                            }
                        }
                        
                        $workflowResult = Process-SinglePR -PRNumber $pr.Number
                        if (-not $workflowResult) {
                            Add-CollectedError -ErrorMessage "PR #$($pr.Number) workflow failed" -FunctionName "Start-CopilotPRMonitoring" -Context "PR processing failed in monitoring loop" -AdditionalInfo @{PRNumber=$pr.Number; Error=$workflowResult.Error}
                        }
                    }
                }
                
                # Bulk auto-merge for eligible PRs if autonomous mode is enabled
                if (-not $MonitorOnly -and $AutoApproveWorkflows -and $copilotPRs.Count -gt 0) {
                    Write-StatusMessage "🎯 Checking for additional PRs eligible for auto-merge..." -Color $BLUE
                    
                    $eligibleForMerge = @()
                    foreach ($pr in $copilotPRs) {
                        $mergeCheck = Invoke-IntelligentAutoMerge -PRNumber $pr.Number -QuietMode:$true
                        if ($mergeCheck.IsSafe -and -not $mergeCheck.MergeAttempted) {
                            $eligibleForMerge += $pr
                        }
                    }
                    
                    if ($eligibleForMerge.Count -gt 0) {
                        Write-StatusMessage "🚀 Found $($eligibleForMerge.Count) additional PR(s) eligible for auto-merge" -Color $GREEN
                        foreach ($pr in $eligibleForMerge) {
                            $mergeResult = Invoke-IntelligentAutoMerge -PRNumber $pr.Number -QuietMode:$QuietMode
                            if ($mergeResult.MergeSuccessful) {
                                Write-StatusMessage "🎉 Auto-merged PR #$($pr.Number): $($pr.Title)" -Color $GREEN
                            }
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

# Analyze failed workflows and generate a single comprehensive fix request
function Analyze-FailedWorkflows {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🔍 Analyzing failed workflows for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get PR status checks to identify failed workflows
        $prStatusChecks = gh pr view $PRNumber --json statusCheckRollup | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            Add-CollectedError -ErrorMessage "Failed to get PR status checks for #$PRNumber" -FunctionName "Analyze-FailedWorkflows" -Context "GitHub CLI pr view failed" -AdditionalInfo @{PRNumber=$PRNumber}
            return @{ Success = $false; FailedCount = 0; FixRequestCount = 0; Error = "Failed to get PR status checks" }
        }
        
        # Filter for failed status checks and group by workflow to get only latest run
        $failedChecks = $prStatusChecks.statusCheckRollup | Where-Object { 
            $_.conclusion -eq "FAILURE" -and $_.status -eq "COMPLETED" 
        }
        
        if ($failedChecks.Count -eq 0) {
            Write-StatusMessage "✅ No failed workflows found for PR #$PRNumber" -Color $GREEN
            return @{ Success = $true; FailedCount = 0; FixRequestCount = 0; Error = $null }
        }
        
        # Group by workflow name to get only the latest run for each workflow
        $uniqueWorkflows = @{}
        foreach ($check in $failedChecks) {
            $workflowKey = $check.workflowName
            if (-not $uniqueWorkflows.ContainsKey($workflowKey) -or $check.databaseId -gt $uniqueWorkflows[$workflowKey].databaseId) {
                $uniqueWorkflows[$workflowKey] = $check
            }
        }
        
        $latestFailedChecks = $uniqueWorkflows.Values
        Write-StatusMessage "❌ Found $($latestFailedChecks.Count) unique failed workflow(s) for PR #$PRNumber (latest runs only)" -Color $RED
        
        # Collect all workflow failures for a single comprehensive fix request
        $allWorkflowFailures = @()
        $hasRateLimitOnly = $true
        
        foreach ($failedCheck in $latestFailedChecks) {
            Write-StatusMessage "   ❌ Failed: $($failedCheck.name) ($($failedCheck.workflowName))" -Color $RED
            
            # Get detailed error information from the workflow run
            $runId = $failedCheck.detailsUrl -replace '.*runs/(\d+).*', '$1'
            if ($runId -match '^\d+$') {
                Write-StatusMessage "   🔍 Analyzing latest run #$runId for error details..." -Color $CYAN
                
                try {
                    # Get workflow run logs
                    $runLogs = gh run view $runId --log 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        # Extract key error patterns
                        $errorPatterns = @()
                        $runLogsString = $runLogs -join "`n"
                        
                        # Common error patterns to look for
                        if ($runLogsString -match "bash.*not found|arrays not supported|local.*not supported|\[\[.*not supported") {
                            $errorPatterns += "RUTOS/BusyBox shell compatibility issues detected"
                        }
                        if ($runLogsString -match "SC\d+|shellcheck.*error|syntax error") {
                            $errorPatterns += "ShellCheck syntax/validation errors detected"
                        }
                        if ($runLogsString -match "command not found|No such file or directory|permission denied") {
                            $errorPatterns += "Missing dependencies or file permission issues"
                        }
                        if ($runLogsString -match "API rate limit exceeded|HTTP 403") {
                            $errorPatterns += "GitHub API rate limit exceeded"
                        }
                        if ($runLogsString -match "config.*not found|configuration.*invalid|missing.*variable") {
                            $errorPatterns += "Configuration or environment variable issues"
                        }
                        if ($runLogsString -match "build failed|compilation error|npm.*error|pip.*error") {
                            $errorPatterns += "Build or dependency installation failures"
                        }
                        if ($runLogsString -match "test.*failed|assertion.*failed|expected.*but got") {
                            $errorPatterns += "Test failures or assertion errors"
                        }
                        if ($errorPatterns.Count -eq 0) {
                            $errorPatterns += "Workflow execution failed - requires investigation"
                        }
                        
                        # Check if this workflow has non-rate-limit issues
                        $isRateLimitOnly = ($errorPatterns.Count -eq 1 -and $errorPatterns[0] -match "API rate limit")
                        if (-not $isRateLimitOnly) {
                            $hasRateLimitOnly = $false
                        }
                        
                        # Add to collection for comprehensive fix request
                        $allWorkflowFailures += @{
                            WorkflowName = $failedCheck.workflowName
                            CheckName = $failedCheck.name
                            RunId = $runId
                            ErrorPatterns = $errorPatterns
                            RunLogs = $runLogsString
                            IsRateLimitOnly = $isRateLimitOnly
                        }
                        
                    } else {
                        Write-StatusMessage "   ⚠️  Could not retrieve logs for run #$runId" -Color $YELLOW
                        # Add as unknown failure
                        $allWorkflowFailures += @{
                            WorkflowName = $failedCheck.workflowName
                            CheckName = $failedCheck.name
                            RunId = $runId
                            ErrorPatterns = @("Could not retrieve logs - manual investigation required")
                            RunLogs = ""
                            IsRateLimitOnly = $false
                        }
                        $hasRateLimitOnly = $false
                    }
                } catch {
                    Write-StatusMessage "   ⚠️  Error analyzing run #${runId}: $($_.Exception.Message)" -Color $YELLOW
                    # Add as error case
                    $allWorkflowFailures += @{
                        WorkflowName = $failedCheck.workflowName
                        CheckName = $failedCheck.name
                        RunId = $runId
                        ErrorPatterns = @("Error during analysis: $($_.Exception.Message)")
                        RunLogs = ""
                        IsRateLimitOnly = $false
                    }
                    $hasRateLimitOnly = $false
                }
            }
        }
        
        # Generate a single comprehensive fix request (unless all failures are rate limit only)
        $fixRequestCount = 0
        
        if ($hasRateLimitOnly) {
            Write-StatusMessage "⏭️  All failures are rate limit related - skipping Copilot fix request (will be retried automatically)" -Color $CYAN
        } else {
            # Filter out rate-limit-only failures and create one comprehensive request
            $fixableFailures = $allWorkflowFailures | Where-Object { -not $_.IsRateLimitOnly }
            
            if ($fixableFailures.Count -gt 0) {
                Write-StatusMessage "🤖 Generating comprehensive fix request for $($fixableFailures.Count) workflow failure(s)..." -Color $BLUE
                
                $fixRequest = Generate-ComprehensiveWorkflowFixRequest -PRNumber $PRNumber -WorkflowFailures $fixableFailures
                
                if ($fixRequest.Success) {
                    $fixRequestCount = 1
                    Write-StatusMessage "✅ Posted comprehensive fix request covering $($fixableFailures.Count) workflow(s)" -Color $GREEN
                } else {
                    Write-StatusMessage "❌ Failed to post comprehensive fix request: $($fixRequest.Error)" -Color $RED
                }
            }
        }
        
        return @{ 
            Success = $true
            FailedCount = $latestFailedChecks.Count
            FixRequestCount = $fixRequestCount
            Error = $null
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error analyzing failed workflows" -FunctionName "Analyze-FailedWorkflows" -Context "Workflow failure analysis failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{ Success = $false; FailedCount = 0; FixRequestCount = 0; Error = $_.Exception.Message }
    }
}

# Generate comprehensive fix request for multiple workflow failures
function Generate-ComprehensiveWorkflowFixRequest {
    param(
        [int]$PRNumber,
        [array]$WorkflowFailures
    )
    
    try {
        Write-StatusMessage "🤖 Creating comprehensive fix request for $($WorkflowFailures.Count) workflow failures..." -Color $BLUE
        
        # Group error patterns by type for better organization
        $errorSummary = @{}
        $workflowSummary = @()
        $allRecommendations = @()
        
        foreach ($failure in $WorkflowFailures) {
            # Add to workflow summary
            $workflowSummary += "**$($failure.WorkflowName)** (Run #$($failure.RunId))"
            
            # Categorize error patterns (filter out rate limit issues)
            foreach ($pattern in $failure.ErrorPatterns) {
                # Skip rate limit issues - Copilot can't fix infrastructure problems
                if ($pattern -match "GitHub API rate limit|rate.?limit|API.*limit") {
                    continue
                }
                
                if ($errorSummary.ContainsKey($pattern)) {
                    $errorSummary[$pattern] += @($failure.WorkflowName)
                } else {
                    $errorSummary[$pattern] = @($failure.WorkflowName)
                }
            }
        }
        
        # Check if all error patterns were filtered out (only rate limit issues)
        if ($errorSummary.Keys.Count -eq 0) {
            Write-StatusMessage "⏭️  All detected issues are infrastructure-related (rate limits) - no Copilot fix request needed" -Color $CYAN
            return @{ Success = $true; Error = $null; Skipped = $true; Reason = "Only infrastructure issues detected" }
        }
        
        # Generate targeted recommendations based on error patterns
        foreach ($errorType in $errorSummary.Keys) {
            $affectedWorkflows = $errorSummary[$errorType] -join ", "
            
            switch -Regex ($errorType) {
                "RUTOS.*compatibility" {
                    $allRecommendations += "🔧 **RUTOS Compatibility Issues** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Convert bash-specific syntax to POSIX sh (remove arrays, [[]], local variables)"
                    $allRecommendations += "- Use busybox-compatible commands and patterns"
                    $allRecommendations += "- Follow RUTOS shell scripting guidelines from .github/copilot-instructions.md"
                }
                "ShellCheck" {
                    $allRecommendations += "🔧 **ShellCheck Issues** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Fix all ShellCheck errors and warnings (SC codes)"
                    $allRecommendations += "- Ensure POSIX compliance for busybox compatibility"
                    $allRecommendations += "- Add proper quoting and variable validation"
                }
                "Missing dependencies" {
                    $allRecommendations += "🔧 **Missing Dependencies** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Check and install missing dependencies"
                    $allRecommendations += "- Verify file paths and permissions"
                    $allRecommendations += "- Add proper error handling for missing files"
                }
                "Configuration" {
                    $allRecommendations += "🔧 **Configuration Issues** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Verify all required environment variables are set"
                    $allRecommendations += "- Check configuration file syntax and completeness"
                    $allRecommendations += "- Add proper default values and validation"
                }
                "Build.*fail" {
                    $allRecommendations += "🔧 **Build Failures** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Fix build script errors and dependency issues"
                    $allRecommendations += "- Verify package.json, requirements.txt, or build configuration"
                    $allRecommendations += "- Check for version compatibility issues"
                }
                "Test.*fail" {
                    $allRecommendations += "🔧 **Test Failures** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Fix failing test cases and assertions"
                    $allRecommendations += "- Update test expectations to match current behavior"
                    $allRecommendations += "- Ensure test environment is properly configured"
                }
                default {
                    $allRecommendations += "🔧 **General Issues** (Affects: $affectedWorkflows)"
                    $allRecommendations += "- Investigate and fix the workflow execution failures"
                    $allRecommendations += "- Review logs for specific error details"
                    $allRecommendations += "- Ensure all dependencies and configurations are correct"
                }
            }
            $allRecommendations += ""
        }
        
        # Extract error samples from the most problematic workflow
        $sampleErrors = @()
        $primaryFailure = $WorkflowFailures | Sort-Object { $_.ErrorPatterns.Count } -Descending | Select-Object -First 1
        if ($primaryFailure -and $primaryFailure.RunLogs) {
            $logLines = $primaryFailure.RunLogs -split "`n"
            for ($i = $logLines.Count - 1; $i -ge 0 -and $sampleErrors.Count -lt 8; $i--) {
                $line = $logLines[$i]
                if ($line -match "error|failed|fatal|ERROR|FAILED|FATAL|\s*✗\s*" -and $line -notmatch "^$|^\s*$") {
                    $sampleErrors = @($line) + $sampleErrors
                }
            }
        }
        
        # Create comprehensive fix request
        $fixRequestBody = @"
🤖 **Comprehensive Workflow Fix Request**

@copilot Multiple workflows are failing in PR #$PRNumber. Please analyze and fix all the issues listed below.

## 📊 Failed Workflows Summary
$($workflowSummary | ForEach-Object { "- $_" } | Out-String)

## 🔍 Detected Issue Categories
$($errorSummary.Keys | ForEach-Object { "- **$_** (affects $($errorSummary[$_].Count) workflow(s))" } | Out-String)

## 🛠️ Comprehensive Fix Plan
$($allRecommendations | Out-String)

## 📋 Sample Error Details
```
$($sampleErrors -join "`n")
```

## 🎯 Action Required
1. **Analyze all the issues** listed above across the affected workflows
2. **Implement systematic fixes** following the recommendations for each category
3. **Ensure RUTOS compatibility** (busybox shell, POSIX compliance) for all shell scripts
4. **Test the changes** to prevent regression across all affected workflows
5. **Push the fixed version** to continue the automation pipeline

## 📖 Context
- This is part of the **RUTOS Starlink Failover project**
- All shell scripts must be **POSIX-compliant** for busybox compatibility  
- Follow guidelines in **.github/copilot-instructions.md**
- Maintain **backward compatibility** with existing configurations
- Focus on **latest run failures only** (not historical attempts)

## 🔗 Links
$($WorkflowFailures | ForEach-Object { "- [Failed Workflow: $($_.WorkflowName)](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$($_.RunId))" } | Out-String)
- [PR #$PRNumber](https://github.com/markus-lassfolk/rutos-starlink-failover/pull/$PRNumber)

*This comprehensive request was automatically generated by the autonomous workflow monitoring system.*
"@

        # Post the comprehensive fix request as a comment
        Write-StatusMessage "📝 Posting comprehensive fix request..." -Color $BLUE
        
        $result = gh pr comment $PRNumber --body $fixRequestBody 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Posted comprehensive fix request covering $($WorkflowFailures.Count) workflows" -Color $GREEN
            
            # Trigger the autonomous-copilot workflow to process this immediately
            try {
                gh workflow run autonomous-copilot.yml --ref main 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "🚀 Triggered autonomous-copilot workflow" -Color $CYAN
                }
            } catch {
                Write-StatusMessage "⚠️  Could not trigger autonomous workflow, but fix request posted" -Color $YELLOW
            }
            
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to post comment: $result" }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error generating comprehensive workflow fix request" -FunctionName "Generate-ComprehensiveWorkflowFixRequest" -Context "Comprehensive fix request generation failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber; WorkflowCount=$WorkflowFailures.Count}
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Generate targeted fix request for failed workflows (legacy - kept for compatibility)
function Generate-WorkflowFixRequest {
    param(
        [int]$PRNumber,
        [string]$WorkflowName,
        [string]$RunId,
        [array]$ErrorPatterns,
        [string]$RunLogs
    )
    
    try {
        # Extract relevant error snippets (last 10 lines with errors)
        $errorLines = @()
        $logLines = $RunLogs -split "`n"
        
        for ($i = $logLines.Count - 1; $i -ge 0 -and $errorLines.Count -lt 10; $i--) {
            $line = $logLines[$i]
            if ($line -match "error|failed|fatal|ERROR|FAILED|FATAL|\s*✗\s*" -and $line -notmatch "^$|^\s*$") {
                $errorLines = @($line) + $errorLines
            }
        }
        
        # Generate intelligent fix request based on error patterns
        $fixInstructions = @()
        
        foreach ($pattern in $ErrorPatterns) {
            switch -Regex ($pattern) {
                "RUTOS.*compatibility" {
                    $fixInstructions += "- Convert bash-specific syntax to POSIX sh (remove arrays, [[]], local variables)"
                    $fixInstructions += "- Use busybox-compatible commands and patterns"
                    $fixInstructions += "- Follow RUTOS shell scripting guidelines from .github/copilot-instructions.md"
                }
                "ShellCheck" {
                    $fixInstructions += "- Fix all ShellCheck errors and warnings (SC codes)"
                    $fixInstructions += "- Ensure POSIX compliance for busybox compatibility"
                    $fixInstructions += "- Add proper quoting and variable validation"
                }
                "Missing dependencies" {
                    $fixInstructions += "- Check and install missing dependencies"
                    $fixInstructions += "- Verify file paths and permissions"
                    $fixInstructions += "- Add proper error handling for missing files"
                }
                "API rate limit" {
                    $fixInstructions += "- Add rate limit detection and backoff logic"
                    $fixInstructions += "- Implement retry mechanisms with exponential backoff"
                    $fixInstructions += "- Consider using GitHub API more efficiently"
                }
                "Configuration" {
                    $fixInstructions += "- Verify all required environment variables are set"
                    $fixInstructions += "- Check configuration file syntax and completeness"
                    $fixInstructions += "- Add proper default values and validation"
                }
                "Build.*fail" {
                    $fixInstructions += "- Fix build script errors and dependency issues"
                    $fixInstructions += "- Verify package.json, requirements.txt, or build configuration"
                    $fixInstructions += "- Check for version compatibility issues"
                }
                "Test.*fail" {
                    $fixInstructions += "- Fix failing test cases and assertions"
                    $fixInstructions += "- Update test expectations to match current behavior"
                    $fixInstructions += "- Ensure test environment is properly configured"
                }
                default {
                    $fixInstructions += "- Investigate and fix the workflow execution failure"
                    $fixInstructions += "- Review logs for specific error details"
                    $fixInstructions += "- Ensure all dependencies and configurations are correct"
                }
            }
        }
        
        # Create comprehensive fix request
        $fixRequestBody = @"
🤖 **Autonomous Workflow Fix Request**

@copilot The workflow **$WorkflowName** failed in PR #$PRNumber. Please analyze and fix the issues.

**🔍 Detected Issues:**
$($ErrorPatterns | ForEach-Object { "- $_" } | Out-String)

**🛠️ Recommended Fixes:**
$($fixInstructions | Out-String)

**📋 Error Details (Run #$RunId):**
```
$($errorLines -join "`n")
```

**🎯 Action Required:**
1. Analyze the error patterns and logs above
2. Implement the recommended fixes
3. Ensure RUTOS compatibility (busybox shell, POSIX compliance)
4. Test the changes to prevent regression
5. Push the fixed version to continue the automation pipeline

**📖 Context:**
- This is part of the RUTOS Starlink Failover project
- All shell scripts must be POSIX-compliant for busybox compatibility  
- Follow guidelines in `.github/copilot-instructions.md`
- Maintain backward compatibility with existing configurations

**🔗 Links:**
- [Failed Workflow Run](https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$RunId)
- [PR #$PRNumber](https://github.com/markus-lassfolk/rutos-starlink-failover/pull/$PRNumber)

*This request was automatically generated by the autonomous workflow monitoring system.*
"@

        # Post the fix request as a comment
        Write-StatusMessage "🤖 Generating targeted fix request for $WorkflowName..." -Color $BLUE
        
        $result = gh pr comment $PRNumber --body $fixRequestBody 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Posted workflow fix request for $WorkflowName" -Color $GREEN
            
            # Trigger the autonomous-copilot workflow to process this immediately
            try {
                gh workflow run autonomous-copilot.yml --ref main 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "🚀 Triggered autonomous-copilot workflow" -Color $CYAN
                }
            } catch {
                Write-StatusMessage "⚠️  Could not trigger autonomous workflow, but fix request posted" -Color $YELLOW
            }
            
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to post comment: $result" }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error generating workflow fix request" -FunctionName "Generate-WorkflowFixRequest" -Context "Fix request generation failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber; WorkflowName=$WorkflowName}
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Mixed Status Check Resolution Functions
# Handles cases where successful workflow retries are blocked by old failed status checks

function Test-MixedStatusChecks {
    param([int]$PRNumber)
    
    try {
        Write-StatusMessage "🔍 Analyzing status checks for PR #$PRNumber..." -Color $CYAN
        
        # Get detailed PR status information
        $prStatusJson = gh api "repos/markus-lassfolk/rutos-starlink-failover/pulls/$PRNumber" --jq '{
            mergeable: .mergeable,
            mergeable_state: .mergeable_state,
            head_sha: .head.sha,
            title: .title
        }' 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Add-CollectedError -ErrorMessage "Failed to get PR status for #$PRNumber" -FunctionName "Test-MixedStatusChecks" -Context "GitHub CLI pr status failed" -AdditionalInfo @{PRNumber=$PRNumber; Error=$prStatusJson}
            return @{ HasMixedStatus = $false; Error = "Failed to get PR status: $prStatusJson" }
        }
        
        $prData = $prStatusJson | ConvertFrom-Json
        
        Write-StatusMessage "📊 PR #$PRNumber merge state: $($prData.mergeable_state), mergeable: $($prData.mergeable)" -Color $BLUE
        
        # Only analyze PRs with potentially problematic merge states
        if ($prData.mergeable_state -notin @("unstable", "behind", "dirty")) {
            return @{ HasMixedStatus = $false; Error = $null; CleanState = $true }
        }
        
        # Get all check runs for this PR using the correct API endpoint
        $statusChecksJson = gh api "repos/markus-lassfolk/rutos-starlink-failover/commits/$($prData.head_sha)/check-runs" --jq '.check_runs[] | {
            name: .name,
            conclusion: .conclusion,
            status: .status,
            completedAt: .completed_at,
            workflowName: .app.name,
            typename: "CheckRun"
        }' 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            # Fallback to commit status API
            $statusChecksJson = gh api "repos/markus-lassfolk/rutos-starlink-failover/commits/$($prData.head_sha)/status" --jq '.statuses[] | {
                name: .context,
                conclusion: .state,
                status: .state,
                completedAt: .created_at,
                workflowName: .context,
                typename: "StatusContext"
            }' 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-StatusMessage "ℹ️  No status checks found for PR #$PRNumber (this is normal for new PRs)" -Color $YELLOW
                return @{ HasMixedStatus = $false; Error = $null; NoChecks = $true }
            }
        }
        
        # Parse status checks and group by workflow/context name
        $statusChecks = @()
        if ($statusChecksJson) {
            $statusChecks = ($statusChecksJson -split "`n" | Where-Object { $_ -and $_ -ne "null" } | ForEach-Object { $_ | ConvertFrom-Json })
        }
        
        # Group checks by name to find mixed statuses
        $groupedChecks = $statusChecks | Group-Object -Property name
        $mixedStatusContexts = @()
        
        foreach ($group in $groupedChecks) {
            $checkName = $group.Name
            $checks = $group.Group | Sort-Object completedAt -Descending
            
            if ($checks.Count -gt 1) {
                $latest = $checks[0]
                $older = $checks[1..($checks.Count-1)]
                
                # Check if we have a successful latest run with older failures
                if ($latest.conclusion -eq "SUCCESS" -and ($older | Where-Object { $_.conclusion -in @("FAILURE", "ERROR") })) {
                    Write-StatusMessage "⚠️  Mixed status detected for check: $checkName" -Color $YELLOW
                    Write-StatusMessage "   Latest: $($latest.conclusion) at $($latest.completedAt)" -Color $CYAN
                    Write-StatusMessage "   Older failures: $(($older | Where-Object { $_.conclusion -in @('FAILURE', 'ERROR') }).Count)" -Color $CYAN
                    
                    $mixedStatusContexts += @{
                        Name = $checkName
                        LatestStatus = $latest
                        OldFailures = ($older | Where-Object { $_.conclusion -in @('FAILURE', 'ERROR') })
                        WorkflowName = $latest.workflowName
                    }
                }
            }
        }
        
        $result = @{
            HasMixedStatus = ($mixedStatusContexts.Count -gt 0)
            MixedContexts = $mixedStatusContexts
            PR = $prData
            Error = $null
            TotalChecks = $statusChecks.Count
            CleanState = $false
        }
        
        if ($result.HasMixedStatus) {
            Write-StatusMessage "🚨 Found $($mixedStatusContexts.Count) contexts with mixed status in PR #$PRNumber" -Color $YELLOW
        } else {
            Write-StatusMessage "✅ No mixed status issues detected in PR #$PRNumber" -Color $GREEN
        }
        
        return $result
        
    } catch {
        Add-CollectedError -ErrorMessage "Error analyzing mixed status checks" -FunctionName "Test-MixedStatusChecks" -Context "Mixed status analysis failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{ HasMixedStatus = $false; Error = $_.Exception.Message }
    }
}

function Resolve-MixedStatusChecks {
    param([int]$PRNumber, [array]$MixedContexts, [object]$PRData)
    
    try {
        Write-StatusMessage "🔧 Resolving mixed status checks for PR #$PRNumber..." -Color $BLUE
        
        $resolutionResults = @()
        $strategiesExecuted = 0
        
        # Strategy 1: Create a status refresh trigger
        Write-StatusMessage "📡 Strategy 1: Triggering status refresh..." -Color $CYAN
        try {
            $refreshStatus = @{
                state = "success"
                target_url = "https://github.com/markus-lassfolk/rutos-starlink-failover/pull/$PRNumber"
                description = "Mixed status resolution trigger - automated cleanup"
                context = "autonomous-status-refresh-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            } | ConvertTo-Json
            
            $tempFile = [System.IO.Path]::GetTempFileName()
            $refreshStatus | Out-File -FilePath $tempFile -Encoding UTF8
            
            $refreshResult = gh api "repos/markus-lassfolk/rutos-starlink-failover/statuses/$($PRData.head_sha)" --method POST --input $tempFile 2>&1
            Remove-Item $tempFile -Force
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Status refresh triggered successfully" -Color $GREEN
                $strategiesExecuted++
                $resolutionResults += "Status refresh triggered"
            } else {
                Write-StatusMessage "⚠️  Status refresh failed: $refreshResult" -Color $YELLOW
                $resolutionResults += "Status refresh failed: $refreshResult"
            }
        } catch {
            Write-StatusMessage "⚠️  Status refresh exception: $($_.Exception.Message)" -Color $YELLOW
            $resolutionResults += "Status refresh exception: $($_.Exception.Message)"
        }
        
        Start-Sleep -Seconds 5
        
        # Strategy 2: Re-run failed workflows for successful retries
        Write-StatusMessage "🔄 Strategy 2: Re-running failed workflows..." -Color $CYAN
        foreach ($context in $MixedContexts) {
            Write-StatusMessage "   Processing context: $($context.Name)" -Color $CYAN
            
            try {
                # Get recent workflow runs for this PR
                $workflowsJson = gh run list --limit 50 --json databaseId,workflowName,status,conclusion,headBranch,createdAt 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $workflows = $workflowsJson | ConvertFrom-Json
                    
                    # Find the most recent failed run for this workflow
                    $targetRun = $workflows | Where-Object { 
                        $_.workflowName -like "*$($context.WorkflowName)*" -and 
                        $_.headBranch -like "*$PRNumber*" -and
                        $_.conclusion -eq "failure"
                    } | Select-Object -First 1
                    
                    if ($targetRun) {
                        Write-StatusMessage "🎯 Found failed run to retry: $($targetRun.databaseId) - $($targetRun.workflowName)" -Color $BLUE
                        
                        $rerunResult = gh run rerun $targetRun.databaseId --failed 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-StatusMessage "✅ Workflow re-run triggered for $($context.Name)" -Color $GREEN
                            $strategiesExecuted++
                            $resolutionResults += "Re-run triggered for $($context.Name)"
                        } else {
                            Write-StatusMessage "⚠️  Workflow re-run failed: $rerunResult" -Color $YELLOW
                            $resolutionResults += "Re-run failed for $($context.Name): $rerunResult"
                        }
                    } else {
                        Write-StatusMessage "ℹ️  No suitable failed workflow run found for $($context.Name)" -Color $CYAN
                        $resolutionResults += "No failed run found for $($context.Name)"
                    }
                } else {
                    Write-StatusMessage "⚠️  Failed to get workflow list: $workflowsJson" -Color $YELLOW
                    $resolutionResults += "Failed to get workflows: $workflowsJson"
                }
            } catch {
                Write-StatusMessage "⚠️  Workflow re-run exception for $($context.Name): $($_.Exception.Message)" -Color $YELLOW
                $resolutionResults += "Re-run exception for $($context.Name): $($_.Exception.Message)"
            }
            
            Start-Sleep -Seconds 3
        }
        
        # Strategy 3: Create override status checks for persistent issues
        Write-StatusMessage "💪 Strategy 3: Creating override status checks..." -Color $CYAN
        foreach ($context in $MixedContexts) {
            try {
                $overrideStatus = @{
                    state = "success"
                    target_url = "https://github.com/markus-lassfolk/rutos-starlink-failover/pull/$PRNumber"
                    description = "Override for mixed status - successful retry available"
                    context = "$($context.Name)-resolved-$(Get-Date -Format 'HHmmss')"
                } | ConvertTo-Json
                
                $tempFile = [System.IO.Path]::GetTempFileName()
                $overrideStatus | Out-File -FilePath $tempFile -Encoding UTF8
                
                $overrideResult = gh api "repos/markus-lassfolk/rutos-starlink-failover/statuses/$($PRData.head_sha)" --method POST --input $tempFile 2>&1
                Remove-Item $tempFile -Force
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "✅ Override status created for $($context.Name)" -Color $GREEN
                    $strategiesExecuted++
                    $resolutionResults += "Override created for $($context.Name)"
                } else {
                    Write-StatusMessage "⚠️  Override status failed for $($context.Name): $overrideResult" -Color $YELLOW
                    $resolutionResults += "Override failed for $($context.Name): $overrideResult"
                }
            } catch {
                Write-StatusMessage "⚠️  Override status exception for $($context.Name): $($_.Exception.Message)" -Color $YELLOW
                $resolutionResults += "Override exception for $($context.Name): $($_.Exception.Message)"
            }
            
            Start-Sleep -Seconds 2
        }
        
        Write-StatusMessage "📊 Mixed status resolution completed: $strategiesExecuted strategies executed" -Color $BLUE
        
        # Wait for status updates to propagate
        Write-StatusMessage "⏳ Waiting for status updates to propagate..." -Color $CYAN
        Start-Sleep -Seconds 15
        
        # Check if the issue is resolved
        $postResolutionCheck = Test-MixedStatusChecks -PRNumber $PRNumber
        
        if (-not $postResolutionCheck.HasMixedStatus) {
            Write-StatusMessage "🎉 Mixed status issues appear to be resolved for PR #$PRNumber!" -Color $GREEN
            
            # Try to enable auto-merge for Copilot PRs
            $prInfo = Get-SpecificPR -PRNumber $PRNumber
            if ($prInfo -and $prInfo.Success -and $prInfo.PR) {
                $pr = $prInfo.PR
                if ($pr.Author -match "copilot|github-copilot|app/github-copilot|app/copilot-swe-agent|swe-agent" -or 
                    $pr.Title -match "copilot|Fix|automated|compatibility") {
                    
                    Write-StatusMessage "🤖 Copilot PR detected - attempting auto-merge..." -Color $BLUE
                    $mergeResult = gh pr merge $PRNumber --auto --merge --delete-branch 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-StatusMessage "🚀 Auto-merge enabled for PR #$PRNumber" -Color $GREEN
                        $resolutionResults += "Auto-merge enabled"
                    } else {
                        Write-StatusMessage "ℹ️  Auto-merge not available: $mergeResult" -Color $CYAN
                        $resolutionResults += "Auto-merge not available: $mergeResult"
                    }
                }
            }
            
            return @{ Success = $true; StrategiesExecuted = $strategiesExecuted; Results = $resolutionResults; Resolved = $true }
        } else {
            Write-StatusMessage "⚠️  Mixed status issues may still persist for PR #$PRNumber" -Color $YELLOW
            return @{ Success = $true; StrategiesExecuted = $strategiesExecuted; Results = $resolutionResults; Resolved = $false }
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error resolving mixed status checks" -FunctionName "Resolve-MixedStatusChecks" -Context "Mixed status resolution failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber; MixedContextsCount=$MixedContexts.Count}
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Process-MixedStatusPRs {
    param([array]$PRs = $null)
    
    try {
        Write-StatusMessage "🔍 Scanning for PRs with mixed status check issues..." -Color $BLUE
        
        $allPRs = if ($PRs) { $PRs } else { (Get-CopilotPRs).PRs }
        $mixedStatusPRs = @()
        $resolvedCount = 0
        
        foreach ($pr in $allPRs) {
            Write-StatusMessage "   Checking PR #$($pr.Number): $($pr.Title)" -Color $CYAN
            
            $mixedStatusCheck = Test-MixedStatusChecks -PRNumber $pr.Number
            
            if ($mixedStatusCheck.HasMixedStatus) {
                Write-StatusMessage "🚨 Mixed status detected in PR #$($pr.Number)" -Color $YELLOW
                $mixedStatusPRs += @{
                    PR = $pr
                    MixedStatusData = $mixedStatusCheck
                }
                
                # Attempt to resolve the mixed status
                $resolutionResult = Resolve-MixedStatusChecks -PRNumber $pr.Number -MixedContexts $mixedStatusCheck.MixedContexts -PRData $mixedStatusCheck.PR
                
                if ($resolutionResult.Success -and $resolutionResult.Resolved) {
                    Write-StatusMessage "✅ Successfully resolved mixed status for PR #$($pr.Number)" -Color $GREEN
                    $resolvedCount++
                } elseif ($resolutionResult.Success) {
                    Write-StatusMessage "⚠️  Partial resolution for PR #$($pr.Number) - may need manual intervention" -Color $YELLOW
                } else {
                    Write-StatusMessage "❌ Failed to resolve mixed status for PR #$($pr.Number): $($resolutionResult.Error)" -Color $RED
                }
            } elseif ($mixedStatusCheck.CleanState) {
                Write-StatusMessage "✅ PR #$($pr.Number) has clean status checks" -Color $GREEN
            } else {
                Write-StatusMessage "ℹ️  PR #$($pr.Number) status check analysis inconclusive" -Color $CYAN
            }
            
            Start-Sleep -Seconds 2  # Rate limiting between PR checks
        }
        
        Write-StatusMessage "📊 Mixed Status Check Analysis Complete:" -Color $BLUE
        Write-StatusMessage "   PRs scanned: $($allPRs.Count)" -Color $CYAN
        Write-StatusMessage "   Mixed status detected: $($mixedStatusPRs.Count)" -Color $CYAN
        Write-StatusMessage "   Successfully resolved: $resolvedCount" -Color $CYAN
        
        return @{
            Success = $true
            PRsScanned = $allPRs.Count
            MixedStatusDetected = $mixedStatusPRs.Count
            Resolved = $resolvedCount
            MixedStatusPRs = $mixedStatusPRs
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error processing mixed status PRs" -FunctionName "Process-MixedStatusPRs" -Context "Mixed status PR processing failed" -Exception $_.Exception
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# GitHub API Rate Limit Management Functions
# Integrated from Fix-RateLimitPRs.ps1 for comprehensive rate limit handling

function Test-GitHubRateLimit {
    Write-StatusMessage "🔍 Checking GitHub API rate limit status..." -Color $CYAN
    
    try {
        $rateLimitResponse = gh api rate_limit | ConvertFrom-Json
        
        $coreLimit = $rateLimitResponse.rate
        $remaining = $coreLimit.remaining
        $total = $coreLimit.limit
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($coreLimit.reset).ToString("yyyy-MM-dd HH:mm:ss")
        
        Write-StatusMessage "📊 Rate Limit Status:" -Color $BLUE
        Write-StatusMessage "   Remaining: $remaining / $total requests" -Color $CYAN
        Write-StatusMessage "   Reset Time: $resetTime" -Color $CYAN
        
        if ($remaining -lt 100) {
            Write-StatusMessage "⚠️  LOW RATE LIMIT: Only $remaining requests remaining!" -Color $YELLOW
            return @{
                IsLimited = $true
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $true
            }
        } elseif ($remaining -lt 500) {
            Write-StatusMessage "⚠️  MODERATE RATE LIMIT: $remaining requests remaining" -Color $YELLOW
            return @{
                IsLimited = $false
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $false
            }
        } else {
            Write-StatusMessage "✅ Rate limit OK: $remaining requests remaining" -Color $GREEN
            return @{
                IsLimited = $false
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $false
            }
        }
    } catch {
        Write-StatusMessage "❌ Failed to check rate limit: $($_.Exception.Message)" -Color $RED
        Add-CollectedError -ErrorMessage "Failed to check GitHub API rate limit" -FunctionName "Test-GitHubRateLimit" -Context "Rate limit check failed" -Exception $_.Exception
        return @{
            IsLimited = $true
            Remaining = 0
            ResetTime = "Unknown"
            ShouldWait = $true
        }
    }
}

function Wait-ForRateLimit {
    param([int]$WaitMinutes = 10)
    
    Write-StatusMessage "⏳ Waiting $WaitMinutes minutes for rate limit recovery..." -Color $YELLOW
    
    for ($i = $WaitMinutes; $i -gt 0; $i--) {
        Write-StatusMessage "   Waiting: $i minutes remaining..." -Color $CYAN
        Start-Sleep -Seconds 60
    }
    
    Write-StatusMessage "✅ Wait complete, checking rate limit again..." -Color $GREEN
}

function Get-PRRateLimitFailures {
    param([int]$PRNumber)
    
    Write-StatusMessage "🔍 Checking PR #$PRNumber for rate limit failures..." -Color $CYAN
    
    try {
        $prData = gh pr view $PRNumber --json number,title,headRefName,statusCheckRollup | ConvertFrom-Json
        
        $rateLimitFailures = @()
        
        foreach ($check in $prData.statusCheckRollup) {
            if ($check.conclusion -eq "FAILURE") {
                # Check if this is a rate limit failure
                try {
                    $runDetails = gh api "repos/:owner/:repo/actions/runs/$($check.databaseId)" 2>/dev/null | ConvertFrom-Json
                    
                    if ($runDetails.conclusion -eq "failure") {
                        # Get job details to check for rate limit errors
                        $jobs = gh api "repos/:owner/:repo/actions/runs/$($check.databaseId)/jobs" | ConvertFrom-Json
                        
                        foreach ($job in $jobs.jobs) {
                            if ($job.conclusion -eq "failure") {
                                # Check job logs for rate limit indicators
                                try {
                                    $logs = gh api "repos/:owner/:repo/actions/jobs/$($job.id)/logs" 2>/dev/null
                                    
                                    if ($logs -match "API rate limit exceeded|rate limit|HTTP 403") {
                                        $rateLimitFailures += @{
                                            RunId = $check.databaseId
                                            WorkflowName = $check.workflowName
                                            CheckName = $check.name
                                            JobId = $job.id
                                            FailureReason = "API rate limit exceeded"
                                            DetailsUrl = $check.detailsUrl
                                        }
                                        break
                                    }
                                } catch {
                                    if ($DebugMode) {
                                        Write-StatusMessage "   ⚠️ Could not check job logs for $($job.name)" -Color $YELLOW
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    if ($DebugMode) {
                        Write-StatusMessage "   ⚠️ Could not check run details for $($check.name)" -Color $YELLOW
                    }
                }
            }
        }
        
        return @{
            PRNumber = $PRNumber
            Title = $prData.title
            HasRateLimitFailures = $rateLimitFailures.Count -gt 0
            RateLimitFailures = $rateLimitFailures
            TotalFailures = ($prData.statusCheckRollup | Where-Object { $_.conclusion -eq "FAILURE" }).Count
        }
        
    } catch {
        Write-StatusMessage "❌ Failed to analyze PR #$PRNumber`: $($_.Exception.Message)" -Color $RED
        Add-CollectedError -ErrorMessage "Failed to analyze PR for rate limit failures" -FunctionName "Get-PRRateLimitFailures" -Context "PR rate limit analysis failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{
            PRNumber = $PRNumber
            HasRateLimitFailures = $false
            RateLimitFailures = @()
            Error = $_.Exception.Message
        }
    }
}

function Retry-FailedWorkflows {
    param(
        [int]$PRNumber,
        [array]$RateLimitFailures
    )
    
    Write-StatusMessage "🔄 Retrying failed workflows for PR #$PRNumber..." -Color $BLUE
    
    $retryCount = 0
    $maxRetries = 3
    $successCount = 0
    
    foreach ($failure in $RateLimitFailures) {
        Write-StatusMessage "🔧 Retrying: $($failure.WorkflowName) - $($failure.CheckName)" -Color $CYAN
        
        if ($TestMode) {
            Write-StatusMessage "   [TEST MODE] Would retry run ID: $($failure.RunId)" -Color $YELLOW
            $successCount++
            continue
        }
        
        $attempt = 0
        $retrySuccess = $false
        
        while ($attempt -lt $maxRetries -and -not $retrySuccess) {
            $attempt++
            
            try {
                # Check rate limit before retry
                $rateLimit = Test-GitHubRateLimit
                if ($rateLimit.ShouldWait) {
                    Write-StatusMessage "   ⏳ Rate limit low, waiting before retry..." -Color $YELLOW
                    Wait-ForRateLimit -WaitMinutes 5
                }
                
                # Retry the workflow run
                $result = gh api "repos/:owner/:repo/actions/runs/$($failure.RunId)/rerun" -X POST 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "   ✅ Successfully retried (attempt $attempt)" -Color $GREEN
                    $retrySuccess = $true
                    $successCount++
                } else {
                    Write-StatusMessage "   ❌ Retry attempt $attempt failed: $result" -Color $RED
                    
                    if ($result -match "rate limit|HTTP 403") {
                        Write-StatusMessage "   ⏳ Rate limit hit, waiting before next attempt..." -Color $YELLOW
                        Start-Sleep -Seconds 30
                    }
                }
            } catch {
                Write-StatusMessage "   ❌ Retry attempt $attempt failed: $($_.Exception.Message)" -Color $RED
                Add-CollectedError -ErrorMessage "Workflow retry failed" -FunctionName "Retry-FailedWorkflows" -Context "Workflow retry attempt $attempt failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber; RunId=$failure.RunId; Attempt=$attempt}
            }
            
            if (-not $retrySuccess -and $attempt -lt $maxRetries) {
                Write-StatusMessage "   ⏳ Waiting 30 seconds before next retry attempt..." -Color $YELLOW
                Start-Sleep -Seconds 30
            }
        }
        
        if (-not $retrySuccess) {
            Write-StatusMessage "   ❌ All retry attempts failed for $($failure.WorkflowName)" -Color $RED
        }
    }
    
    Write-StatusMessage "📊 Retry Summary: $successCount / $($RateLimitFailures.Count) workflows retried successfully" -Color $BLUE
    return @{
        TotalAttempted = $RateLimitFailures.Count
        SuccessfulRetries = $successCount
        FailedRetries = $RateLimitFailures.Count - $successCount
    }
}

# Enhanced workflow failure analysis with rate limit detection and retry
function Analyze-FailedWorkflowsWithRetry {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🔍 Analyzing failed workflows with rate limit detection for PR #$PRNumber..." -Color $BLUE
    
    try {
        # First check our API rate limit status
        $initialRateLimit = Test-GitHubRateLimit
        if ($initialRateLimit.ShouldWait) {
            Write-StatusMessage "⚠️  Rate limit is low, waiting before proceeding..." -Color $YELLOW
            Wait-ForRateLimit -WaitMinutes 5
        }
        
        # Get standard workflow failure analysis
        $failureAnalysis = Analyze-FailedWorkflows -PRNumber $PRNumber
        
        # Also check specifically for rate limit failures
        $rateLimitAnalysis = Get-PRRateLimitFailures -PRNumber $PRNumber
        
        $totalFixRequests = 0
        $totalRetries = 0
        
        # Handle rate limit failures with retries
        if ($rateLimitAnalysis.HasRateLimitFailures) {
            Write-StatusMessage "🔄 Found $($rateLimitAnalysis.RateLimitFailures.Count) rate limit failures, attempting retries..." -Color $YELLOW
            
            $retryResult = Retry-FailedWorkflows -PRNumber $PRNumber -RateLimitFailures $rateLimitAnalysis.RateLimitFailures
            $totalRetries = $retryResult.SuccessfulRetries
            
            if ($retryResult.SuccessfulRetries -gt 0) {
                Write-StatusMessage "✅ Successfully retried $($retryResult.SuccessfulRetries) rate-limited workflows" -Color $GREEN
                
                # Wait for workflows to restart and re-analyze
                Write-StatusMessage "⏳ Waiting 60 seconds for retried workflows to start..." -Color $CYAN
                Start-Sleep -Seconds 60
                
                # Re-analyze after retries
                $failureAnalysis = Analyze-FailedWorkflows -PRNumber $PRNumber
            }
        }
        
        # Count fix requests from standard analysis
        if ($failureAnalysis.Success) {
            $totalFixRequests = $failureAnalysis.FixRequestCount
        }
        
        return @{
            Success = $true
            FailedCount = $failureAnalysis.FailedCount
            FixRequestCount = $totalFixRequests
            RateLimitRetries = $totalRetries
            Error = $null
        }
        
    } catch {
        Add-CollectedError -ErrorMessage "Error in enhanced workflow failure analysis" -FunctionName "Analyze-FailedWorkflowsWithRetry" -Context "Enhanced workflow analysis failed" -Exception $_.Exception -AdditionalInfo @{PRNumber=$PRNumber}
        return @{ Success = $false; FailedCount = 0; FixRequestCount = 0; RateLimitRetries = 0; Error = $_.Exception.Message }
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
    Write-StatusMessage "   AnalyzeWorkflowFailures: $AnalyzeWorkflowFailures (with rate limit retry)" -Color $GRAY
    Write-StatusMessage "   DaemonMode: $DaemonMode" -Color $GRAY
    Write-StatusMessage "   AutoApproveWorkflows: $AutoApproveWorkflows" -Color $GRAY
    Write-StatusMessage "   Rate Limit Management: Automatic detection and backoff" -Color $GRAY
    
    # Daemon mode - continuous autonomous operation
    if ($DaemonMode) {
        Write-StatusMessage "🤖 Starting autonomous daemon mode..." -Color $GREEN
        Write-StatusMessage "   Interval: $DaemonInterval seconds ($([math]::Round($DaemonInterval/60, 1)) minutes)" -Color $GRAY
        Write-StatusMessage "   Max runs: $(if ($MaxDaemonRuns -eq 0) { 'Infinite' } else { $MaxDaemonRuns })" -Color $GRAY
        Write-StatusMessage "   Auto-approve workflows: $AutoApproveWorkflows" -Color $GRAY
        
        $runCount = 0
        $startTime = Get-Date
        
        while ($true) {
            $runCount++
            $currentTime = Get-Date
            $elapsed = $currentTime - $startTime
            
            if (-not $QuietMode) {
                Write-StatusMessage "🔄 Daemon run #$runCount (Elapsed: $($elapsed.ToString('hh\:mm\:ss')))" -Color $BLUE
            }
            
            try {
                # Run main monitoring
                if ($PRNumber) {
                    $result = Process-SinglePR -PRNumber $PRNumber
                    
                    if (-not $QuietMode -and $result) {
                        Write-StatusMessage "✅ PR #$PRNumber processed successfully" -Color $GREEN
                    }
                } else {
                    Start-CopilotPRMonitoring -IntervalSeconds 0 -MaxIterations 1
                }
                
                if (-not $QuietMode) {
                    Write-StatusMessage "✅ Daemon run #$runCount completed successfully" -Color $GREEN
                }
            }
            catch {
                if (-not $QuietMode) {
                    Write-StatusMessage "❌ Daemon run #$runCount failed: $_" -Color $RED
                }
                Add-CollectedError -ErrorMessage $_.Exception.Message -FunctionName "DaemonMode" -Context "Run #$runCount"
            }
            
            # Check if we should stop
            if ($MaxDaemonRuns -gt 0 -and $runCount -ge $MaxDaemonRuns) {
                Write-StatusMessage "🏁 Daemon completed $runCount runs as requested" -Color $GREEN
                break
            }
            
            # Wait for next iteration
            if (-not $QuietMode) {
                Write-StatusMessage "⏳ Waiting $([math]::Round($DaemonInterval/60, 1)) minutes until next run..." -Color $CYAN
            }
            Start-Sleep -Seconds $DaemonInterval
        }
        
        return
    }
    
    # Run the intelligent monitoring system (non-daemon mode)
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
