# Fix Rate Limited PRs Script
# Specifically designed to help PRs stuck due to GitHub API rate limits
# Handles PR #282 and similar cases with intelligent retry and backoff

param(
    [int]$PRNumber,
    [switch]$CheckAllPRs = $false,
    [switch]$DebugMode = $false,
    [switch]$DryRun = $false,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
🔧 Fix Rate Limited PRs - GitHub API Rate Limit Recovery Tool

USAGE:
    Fix-RateLimitPRs.ps1 [OPTIONS]

OPTIONS:
    -PRNumber <int>       Fix specific PR number (e.g., 282)
    -CheckAllPRs          Check all stuck PRs for rate limit issues
    -DebugMode            Enable detailed debug output
    -DryRun               Show what would be done without making changes
    -Help                 Show this help message

EXAMPLES:
    # Fix specific PR that's stuck due to rate limits
    .\Fix-RateLimitPRs.ps1 -PRNumber 282 -DebugMode

    # Check all PRs for rate limit issues
    .\Fix-RateLimitPRs.ps1 -CheckAllPRs -DebugMode

    # Dry run to see what would be fixed
    .\Fix-RateLimitPRs.ps1 -CheckAllPRs -DryRun

"@
    exit 0
}

# Color definitions
$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"
$CYAN = "Cyan"
$BLUE = "Blue"
$PURPLE = "Magenta"

function Write-StatusMessage {
    param(
        [string]$Message,
        [string]$Color = "White",
        [string]$Prefix = "ℹ️"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Prefix $Message" -ForegroundColor $Color
}

function Test-GitHubRateLimit {
    Write-StatusMessage "🔍 Checking GitHub API rate limit status..." -Color $CYAN -Prefix "🔍"
    
    try {
        $rateLimitResponse = gh api rate_limit | ConvertFrom-Json
        
        $coreLimit = $rateLimitResponse.rate
        $remaining = $coreLimit.remaining
        $total = $coreLimit.limit
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($coreLimit.reset).ToString("yyyy-MM-dd HH:mm:ss")
        
        Write-StatusMessage "📊 Rate Limit Status:" -Color $BLUE -Prefix "📊"
        Write-StatusMessage "   Remaining: $remaining / $total requests" -Color $CYAN -Prefix "  "
        Write-StatusMessage "   Reset Time: $resetTime" -Color $CYAN -Prefix "  "
        
        if ($remaining -lt 100) {
            Write-StatusMessage "⚠️  LOW RATE LIMIT: Only $remaining requests remaining!" -Color $YELLOW -Prefix "⚠️"
            return @{
                IsLimited = $true
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $true
            }
        } elseif ($remaining -lt 500) {
            Write-StatusMessage "⚠️  MODERATE RATE LIMIT: $remaining requests remaining" -Color $YELLOW -Prefix "⚠️"
            return @{
                IsLimited = $false
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $false
            }
        } else {
            Write-StatusMessage "✅ Rate limit OK: $remaining requests remaining" -Color $GREEN -Prefix "✅"
            return @{
                IsLimited = $false
                Remaining = $remaining
                ResetTime = $resetTime
                ShouldWait = $false
            }
        }
    } catch {
        Write-StatusMessage "❌ Failed to check rate limit: $($_.Exception.Message)" -Color $RED -Prefix "❌"
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
    
    Write-StatusMessage "⏳ Waiting $WaitMinutes minutes for rate limit recovery..." -Color $YELLOW -Prefix "⏳"
    
    for ($i = $WaitMinutes; $i -gt 0; $i--) {
        Write-StatusMessage "   Waiting: $i minutes remaining..." -Color $CYAN -Prefix "  "
        Start-Sleep -Seconds 60
    }
    
    Write-StatusMessage "✅ Wait complete, checking rate limit again..." -Color $GREEN -Prefix "✅"
}

function Get-PRRateLimitFailures {
    param([int]$PRNumber)
    
    Write-StatusMessage "🔍 Checking PR #$PRNumber for rate limit failures..." -Color $CYAN -Prefix "🔍"
    
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
                                            WorkflowName = $check.workflowName
                                            CheckName = $check.name
                                            RunId = $check.databaseId
                                            JobId = $job.id
                                            JobName = $job.name
                                            FailureReason = "Rate Limit Exceeded"
                                            DetailsUrl = $check.detailsUrl
                                        }
                                        
                                        Write-StatusMessage "🔴 Found rate limit failure: $($check.workflowName) - $($check.name)" -Color $RED -Prefix "🔴"
                                    }
                                } catch {
                                    # If we can't get logs, but the pattern suggests rate limiting, include it
                                    if ($check.workflowName -match "Autonomous|Copilot" -and $job.conclusion -eq "failure") {
                                        $rateLimitFailures += @{
                                            WorkflowName = $check.workflowName
                                            CheckName = $check.name
                                            RunId = $check.databaseId
                                            JobId = $job.id
                                            JobName = $job.name
                                            FailureReason = "Suspected Rate Limit (Log Access Failed)"
                                            DetailsUrl = $check.detailsUrl
                                        }
                                        
                                        Write-StatusMessage "🟡 Suspected rate limit failure: $($check.workflowName) - $($check.name)" -Color $YELLOW -Prefix "🟡"
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    if ($DebugMode) {
                        Write-StatusMessage "   ⚠️ Could not check run details for $($check.name)" -Color $YELLOW -Prefix "  "
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
        Write-StatusMessage "❌ Failed to analyze PR #$PRNumber`: $($_.Exception.Message)" -Color $RED -Prefix "❌"
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
    
    Write-StatusMessage "🔄 Retrying failed workflows for PR #$PRNumber..." -Color $BLUE -Prefix "🔄"
    
    $retryCount = 0
    $maxRetries = 3
    $successCount = 0
    
    foreach ($failure in $RateLimitFailures) {
        Write-StatusMessage "🔧 Retrying: $($failure.WorkflowName) - $($failure.CheckName)" -Color $CYAN -Prefix "🔧"
        
        if ($DryRun) {
            Write-StatusMessage "   [DRY RUN] Would retry run ID: $($failure.RunId)" -Color $YELLOW -Prefix "  "
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
                    Write-StatusMessage "   ⏳ Rate limit low, waiting before retry..." -Color $YELLOW -Prefix "  "
                    Wait-ForRateLimit -WaitMinutes 5
                }
                
                # Retry the workflow run
                $result = gh api "repos/:owner/:repo/actions/runs/$($failure.RunId)/rerun" -X POST 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "   ✅ Successfully retried (attempt $attempt)" -Color $GREEN -Prefix "  "
                    $retrySuccess = $true
                    $successCount++
                } else {
                    Write-StatusMessage "   ❌ Retry attempt $attempt failed: $result" -Color $RED -Prefix "  "
                    
                    if ($result -match "rate limit|HTTP 403") {
                        Write-StatusMessage "   ⏳ Rate limit hit, waiting before next attempt..." -Color $YELLOW -Prefix "  "
                        Wait-ForRateLimit -WaitMinutes 2
                    }
                }
            } catch {
                Write-StatusMessage "   ❌ Retry attempt $attempt failed: $($_.Exception.Message)" -Color $RED -Prefix "  "
            }
            
            if (-not $retrySuccess -and $attempt -lt $maxRetries) {
                Write-StatusMessage "   ⏳ Waiting 30 seconds before next retry attempt..." -Color $YELLOW -Prefix "  "
                Start-Sleep -Seconds 30
            }
        }
        
        if (-not $retrySuccess) {
            Write-StatusMessage "   ❌ All retry attempts failed for $($failure.WorkflowName)" -Color $RED -Prefix "  "
        }
    }
    
    Write-StatusMessage "📊 Retry Summary: $successCount / $($RateLimitFailures.Count) workflows retried successfully" -Color $BLUE -Prefix "📊"
    return @{
        TotalAttempted = $RateLimitFailures.Count
        SuccessfulRetries = $successCount
        FailedRetries = $RateLimitFailures.Count - $successCount
    }
}

function Fix-SinglePR {
    param([int]$PRNumber)
    
    Write-StatusMessage "🎯 Analyzing and fixing PR #$PRNumber..." -Color $GREEN -Prefix "🎯"
    
    # Check rate limit first
    $rateLimit = Test-GitHubRateLimit
    if ($rateLimit.ShouldWait) {
        Write-StatusMessage "⚠️  Rate limit is low, waiting before proceeding..." -Color $YELLOW -Prefix "⚠️"
        Wait-ForRateLimit
    }
    
    # Analyze PR for rate limit failures
    $analysis = Get-PRRateLimitFailures -PRNumber $PRNumber
    
    if ($analysis.Error) {
        Write-StatusMessage "❌ Failed to analyze PR #$PRNumber`: $($analysis.Error)" -Color $RED -Prefix "❌"
        return $false
    }
    
    Write-StatusMessage "📋 PR #$PRNumber`: $($analysis.Title)" -Color $BLUE -Prefix "📋"
    Write-StatusMessage "   Total Failed Checks: $($analysis.TotalFailures)" -Color $CYAN -Prefix "  "
    Write-StatusMessage "   Rate Limit Failures: $($analysis.RateLimitFailures.Count)" -Color $CYAN -Prefix "  "
    
    if (-not $analysis.HasRateLimitFailures) {
        Write-StatusMessage "✅ No rate limit failures found for PR #$PRNumber" -Color $GREEN -Prefix "✅"
        return $true
    }
    
    # Show detailed failure information
    Write-StatusMessage "🔍 Rate Limit Failures Detected:" -Color $YELLOW -Prefix "🔍"
    foreach ($failure in $analysis.RateLimitFailures) {
        Write-StatusMessage "   🔴 $($failure.WorkflowName) - $($failure.FailureReason)" -Color $RED -Prefix "  "
        Write-StatusMessage "     Details: $($failure.DetailsUrl)" -Color $CYAN -Prefix "    "
    }
    
    # Retry failed workflows
    $retryResult = Retry-FailedWorkflows -PRNumber $PRNumber -RateLimitFailures $analysis.RateLimitFailures
    
    if ($retryResult.SuccessfulRetries -gt 0) {
        Write-StatusMessage "✅ Successfully retried $($retryResult.SuccessfulRetries) workflows for PR #$PRNumber" -Color $GREEN -Prefix "✅"
        
        # Wait a bit for workflows to start
        Write-StatusMessage "⏳ Waiting 30 seconds for workflows to start..." -Color $CYAN -Prefix "⏳"
        Start-Sleep -Seconds 30
        
        # Check PR status again
        Write-StatusMessage "🔍 Checking PR status after retries..." -Color $CYAN -Prefix "🔍"
        $updatedAnalysis = Get-PRRateLimitFailures -PRNumber $PRNumber
        
        if ($updatedAnalysis.HasRateLimitFailures) {
            Write-StatusMessage "⚠️  Some failures still present, may need manual intervention" -Color $YELLOW -Prefix "⚠️"
        } else {
            Write-StatusMessage "✅ All rate limit failures resolved for PR #$PRNumber!" -Color $GREEN -Prefix "✅"
        }
        
        return $true
    } else {
        Write-StatusMessage "❌ Failed to retry workflows for PR #$PRNumber" -Color $RED -Prefix "❌"
        return $false
    }
}

function Get-AllStuckPRs {
    Write-StatusMessage "🔍 Finding all PRs stuck due to rate limits..." -Color $CYAN -Prefix "🔍"
    
    try {
        # Get all open PRs with basic info
        $allPRs = gh pr list --state open --json number,title,author --limit 50 | ConvertFrom-Json
        
        $stuckPRs = @()
        
        foreach ($pr in $allPRs) {
            # Focus on bot PRs that are likely to be affected
            if ($pr.author.login -match "copilot|github-copilot|app/copilot-swe-agent|swe-agent") {
                Write-StatusMessage "   🔍 Checking PR #$($pr.number)..." -Color $CYAN -Prefix "  "
                
                $analysis = Get-PRRateLimitFailures -PRNumber $pr.number
                
                if ($analysis.HasRateLimitFailures) {
                    $stuckPRs += $analysis
                    Write-StatusMessage "   🔴 PR #$($pr.number) has rate limit failures" -Color $RED -Prefix "  "
                } else {
                    Write-StatusMessage "   ✅ PR #$($pr.number) looks good" -Color $GREEN -Prefix "  "
                }
                
                # Rate limit check and wait if necessary
                $rateLimit = Test-GitHubRateLimit
                if ($rateLimit.Remaining -lt 50) {
                    Write-StatusMessage "   ⏳ Rate limit getting low, taking a break..." -Color $YELLOW -Prefix "  "
                    Start-Sleep -Seconds 10
                }
            }
        }
        
        return $stuckPRs
        
    } catch {
        Write-StatusMessage "❌ Failed to get stuck PRs: $($_.Exception.Message)" -Color $RED -Prefix "❌"
        return @()
    }
}

# Main execution
function Main {
    Write-StatusMessage "🚀 Starting Rate Limited PR Fix Tool..." -Color $GREEN -Prefix "🚀"
    
    # Show configuration
    Write-StatusMessage "🔧 Configuration:" -Color $BLUE -Prefix "🔧"
    Write-StatusMessage "   Debug Mode: $DebugMode" -Color $CYAN -Prefix "  "
    Write-StatusMessage "   Dry Run: $DryRun" -Color $CYAN -Prefix "  "
    Write-StatusMessage "   Check All PRs: $CheckAllPRs" -Color $CYAN -Prefix "  "
    if ($PRNumber) {
        Write-StatusMessage "   Target PR: #$PRNumber" -Color $CYAN -Prefix "  "
    }
    
    # Initial rate limit check
    $initialRateLimit = Test-GitHubRateLimit
    if ($initialRateLimit.ShouldWait) {
        Write-StatusMessage "⚠️  Initial rate limit check shows limits are low" -Color $YELLOW -Prefix "⚠️"
        if (-not $DryRun) {
            Wait-ForRateLimit
        }
    }
    
    $totalFixed = 0
    
    if ($PRNumber) {
        # Fix specific PR
        $result = Fix-SinglePR -PRNumber $PRNumber
        if ($result) {
            $totalFixed = 1
        }
    } elseif ($CheckAllPRs) {
        # Find and fix all stuck PRs
        $stuckPRs = Get-AllStuckPRs
        
        if ($stuckPRs.Count -eq 0) {
            Write-StatusMessage "✅ No PRs with rate limit failures found!" -Color $GREEN -Prefix "✅"
        } else {
            Write-StatusMessage "🔍 Found $($stuckPRs.Count) PRs with rate limit failures" -Color $YELLOW -Prefix "🔍"
            
            foreach ($pr in $stuckPRs) {
                Write-StatusMessage "`n🎯 Fixing PR #$($pr.PRNumber)..." -Color $GREEN -Prefix "🎯"
                $result = Fix-SinglePR -PRNumber $pr.PRNumber
                if ($result) {
                    $totalFixed++
                }
                
                # Pace the requests to avoid new rate limits
                if ($stuckPRs.IndexOf($pr) -lt ($stuckPRs.Count - 1)) {
                    Write-StatusMessage "⏳ Waiting 30 seconds before next PR..." -Color $CYAN -Prefix "⏳"
                    Start-Sleep -Seconds 30
                }
            }
        }
    } else {
        Write-StatusMessage "❓ Please specify -PRNumber or -CheckAllPRs" -Color $YELLOW -Prefix "❓"
        Write-StatusMessage "   Use -Help for usage information" -Color $CYAN -Prefix "  "
        exit 1
    }
    
    # Final summary
    Write-StatusMessage "`n📊 FINAL SUMMARY:" -Color $GREEN -Prefix "📊"
    Write-StatusMessage "   PRs Fixed: $totalFixed" -Color $CYAN -Prefix "  "
    Write-StatusMessage "   Mode: $(if ($DryRun) { 'Dry Run' } else { 'Live' })" -Color $CYAN -Prefix "  "
    
    $finalRateLimit = Test-GitHubRateLimit
    Write-StatusMessage "   Final Rate Limit: $($finalRateLimit.Remaining) requests remaining" -Color $CYAN -Prefix "  "
    
    if ($totalFixed -gt 0) {
        Write-StatusMessage "✅ Successfully processed $totalFixed PR(s)!" -Color $GREEN -Prefix "✅"
        Write-StatusMessage "💡 Monitor the PRs for a few minutes to see if workflows succeed" -Color $BLUE -Prefix "💡"
    }
}

# Execute main function
Main
