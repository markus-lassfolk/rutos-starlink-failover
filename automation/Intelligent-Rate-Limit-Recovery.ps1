#!/usr/bin/env pwsh
# Intelligent Rate Limit Recovery System
# Handles GitHub API rate limits with exponential backoff and automatic retry scheduling

param(
    [switch]$MonitorMode,
    [switch]$Debug,
    [int]$MaxRetries = 5
)

# Configuration
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Enhanced logging
function Write-LogInfo { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-LogWarning { param($Message) Write-Host "⚠️ $Message" -ForegroundColor Yellow }
function Write-LogError { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-LogDebug { param($Message) if ($Debug) { Write-Host "🔍 $Message" -ForegroundColor Cyan } }
function Write-LogStep { param($Message) Write-Host "🔄 $Message" -ForegroundColor Blue }

# Function to get current rate limit status
function Get-RateLimitStatus {
    try {
        $rateLimitInfo = gh api rate_limit | ConvertFrom-Json
        
        return @{
            Core = @{
                Limit = $rateLimitInfo.rate.limit
                Remaining = $rateLimitInfo.rate.remaining
                ResetTime = [DateTimeOffset]::FromUnixTimeSeconds($rateLimitInfo.rate.reset).LocalDateTime
                Used = $rateLimitInfo.rate.limit - $rateLimitInfo.rate.remaining
                PercentUsed = [math]::Round(($rateLimitInfo.rate.limit - $rateLimitInfo.rate.remaining) / $rateLimitInfo.rate.limit * 100, 2)
            }
            Search = @{
                Limit = $rateLimitInfo.search.limit
                Remaining = $rateLimitInfo.search.remaining
                ResetTime = [DateTimeOffset]::FromUnixTimeSeconds($rateLimitInfo.search.reset).LocalDateTime
            }
        }
    }
    catch {
        Write-LogError "Failed to get rate limit status: $_"
        return $null
    }
}

# Function to calculate intelligent wait time
function Get-IntelligentWaitTime {
    param(
        [int]$AttemptNumber,
        [datetime]$ResetTime,
        [int]$RemainingCalls
    )
    
    $now = Get-Date
    $timeUntilReset = ($ResetTime - $now).TotalSeconds
    
    # If we're close to reset and have very few calls left, wait for reset
    if ($timeUntilReset -le 300 -and $RemainingCalls -le 10) {
        Write-LogDebug "Close to reset time with few calls remaining - waiting for reset"
        return [math]::Max($timeUntilReset + 30, 60) # Wait for reset + buffer
    }
    
    # Exponential backoff with jitter
    $baseWait = [math]::Pow(2, $AttemptNumber) * 60 # Start with 2 minutes, double each time
    $jitter = Get-Random -Minimum 0 -Maximum 30 # Add randomness to avoid thundering herd
    $maxWait = 1800 # Cap at 30 minutes
    
    return [math]::Min($baseWait + $jitter, $maxWait)
}

# Function to execute API call with intelligent retry
function Invoke-APIWithRetry {
    param(
        [string]$APICommand,
        [string]$Description,
        [int]$MaxRetries = 5
    )
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-LogStep "Attempt $attempt/$MaxRetries: $Description"
        
        # Check rate limit before making call
        $rateLimitStatus = Get-RateLimitStatus
        
        if ($rateLimitStatus -and $rateLimitStatus.Core.Remaining -le 5) {
            $waitTime = ($rateLimitStatus.Core.ResetTime - (Get-Date)).TotalSeconds + 60
            Write-LogWarning "Rate limit nearly exhausted ($($rateLimitStatus.Core.Remaining) remaining). Waiting $([math]::Round($waitTime/60, 1)) minutes for reset..."
            
            if ($waitTime -gt 0) {
                Start-Sleep -Seconds $waitTime
            }
        }
        
        try {
            Write-LogDebug "Executing: $APICommand"
            $result = Invoke-Expression $APICommand
            Write-LogInfo "✅ API call successful: $Description"
            return $result
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-LogError "API call failed: $errorMessage"
            
            # Check if it's a rate limit error
            if ($errorMessage -match "rate limit|403|abuse") {
                $rateLimitStatus = Get-RateLimitStatus
                if ($rateLimitStatus) {
                    $waitTime = Get-IntelligentWaitTime -AttemptNumber $attempt -ResetTime $rateLimitStatus.Core.ResetTime -RemainingCalls $rateLimitStatus.Core.Remaining
                    Write-LogWarning "Rate limit hit. Waiting $([math]::Round($waitTime/60, 1)) minutes before retry $($attempt + 1)..."
                    Start-Sleep -Seconds $waitTime
                } else {
                    Write-LogWarning "Rate limit suspected but couldn't get status. Using exponential backoff..."
                    $waitTime = [math]::Pow(2, $attempt) * 60
                    Start-Sleep -Seconds $waitTime
                }
            } else {
                # Non-rate-limit error - shorter wait
                Write-LogWarning "Non-rate-limit error. Waiting 30 seconds before retry..."
                Start-Sleep -Seconds 30
            }
            
            if ($attempt -eq $MaxRetries) {
                Write-LogError "All retry attempts failed for: $Description"
                throw $_
            }
        }
    }
}

# Function to schedule future retry
function Schedule-FutureRetry {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Arguments,
        [datetime]$ScheduleTime
    )
    
    Write-LogStep "Scheduling future retry for $TaskName at $ScheduleTime"
    
    $taskAction = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$ScriptPath`" $Arguments"
    $taskTrigger = New-ScheduledTaskTrigger -Once -At $ScheduleTime
    $taskSettings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter (New-TimeSpan -Hours 1)
    
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Force
        Write-LogInfo "✅ Scheduled task '$TaskName' created for $ScheduleTime"
        return $true
    }
    catch {
        Write-LogError "Failed to create scheduled task: $_"
        return $false
    }
}

# Function to monitor and auto-recover from rate limits
function Start-RateLimitMonitoring {
    Write-LogInfo "🤖 Starting intelligent rate limit monitoring..."
    
    $monitoringInterval = 300 # Check every 5 minutes
    $consecutiveHealthyChecks = 0
    $requiredHealthyChecks = 3 # Need 3 consecutive healthy checks before resuming normal operations
    
    while ($MonitorMode) {
        $rateLimitStatus = Get-RateLimitStatus
        
        if ($rateLimitStatus) {
            $coreStatus = $rateLimitStatus.Core
            $timeUntilReset = ($coreStatus.ResetTime - (Get-Date)).TotalMinutes
            
            Write-LogInfo "📊 Rate Limit Status:"
            Write-LogInfo "   Core API: $($coreStatus.Remaining)/$($coreStatus.Limit) remaining ($($coreStatus.PercentUsed)% used)"
            Write-LogInfo "   Reset in: $([math]::Round($timeUntilReset, 1)) minutes"
            
            # Check if we're in a healthy state
            if ($coreStatus.Remaining -ge 100) {
                $consecutiveHealthyChecks++
                Write-LogInfo "✅ Rate limit healthy (check $consecutiveHealthyChecks/$requiredHealthyChecks)"
                
                if ($consecutiveHealthyChecks -ge $requiredHealthyChecks) {
                    Write-LogInfo "🚀 Rate limit fully recovered - triggering deferred operations"
                    
                    # Trigger any monitoring scripts that were waiting
                    $deferredScript = Join-Path $PSScriptRoot "Monitor-CopilotPRs-Complete.ps1"
                    if (Test-Path $deferredScript) {
                        Write-LogStep "Triggering deferred PR monitoring..."
                        & $deferredScript -AutoMode -QuietMode
                    }
                    
                    $consecutiveHealthyChecks = 0 # Reset counter
                }
            } else {
                $consecutiveHealthyChecks = 0
                
                if ($coreStatus.Remaining -le 50) {
                    Write-LogWarning "⚠️ Rate limit low - entering conservation mode"
                    $conservationWait = [math]::Max($timeUntilReset * 60 / 2, 600) # Wait for half the reset time or 10 minutes
                    Write-LogInfo "Waiting $([math]::Round($conservationWait/60, 1)) minutes in conservation mode..."
                    Start-Sleep -Seconds $conservationWait
                    continue
                }
            }
        } else {
            Write-LogError "Cannot get rate limit status - waiting before retry"
            Start-Sleep -Seconds 600 # Wait 10 minutes if we can't get status
        }
        
        if ($Debug) {
            Write-LogDebug "Next check in $($monitoringInterval/60) minutes..."
        }
        
        Start-Sleep -Seconds $monitoringInterval
    }
}

# Function to create intelligent retry wrapper for any script
function New-IntelligentRetryWrapper {
    param(
        [string]$TargetScript,
        [string]$OutputPath
    )
    
    $wrapperContent = @"
#!/usr/bin/env pwsh
# Auto-generated intelligent retry wrapper for $TargetScript
# This wrapper adds automatic rate limit handling and retry logic

param(
    [switch]`$ForceRetry,
    [Parameter(ValueFromRemainingArguments=`$true)]
    [string[]]`$PassThroughArgs
)

# Import rate limit recovery functions
. "$PSScriptRoot\Intelligent-Rate-Limit-Recovery.ps1"

`$maxAttempts = 3
`$baseScript = "$TargetScript"

for (`$attempt = 1; `$attempt -le `$maxAttempts; `$attempt++) {
    Write-Host "🔄 Attempt `$attempt/`$maxAttempts for `$baseScript" -ForegroundColor Blue
    
    try {
        # Check rate limits before execution
        `$rateLimitStatus = Get-RateLimitStatus
        if (`$rateLimitStatus -and `$rateLimitStatus.Core.Remaining -le 10) {
            `$waitTime = (`$rateLimitStatus.Core.ResetTime - (Get-Date)).TotalSeconds + 60
            Write-Host "⏳ Waiting `$([math]::Round(`$waitTime/60, 1)) minutes for rate limit reset..." -ForegroundColor Yellow
            Start-Sleep -Seconds `$waitTime
        }
        
        # Execute the target script
        & `$baseScript @PassThroughArgs
        
        if (`$LASTEXITCODE -eq 0) {
            Write-Host "✅ Script executed successfully" -ForegroundColor Green
            exit 0
        } else {
            throw "Script returned exit code `$LASTEXITCODE"
        }
    }
    catch {
        Write-Host "❌ Attempt `$attempt failed: `$_" -ForegroundColor Red
        
        if (`$attempt -lt `$maxAttempts) {
            `$waitTime = [math]::Pow(2, `$attempt) * 60
            Write-Host "⏳ Waiting `$([math]::Round(`$waitTime/60, 1)) minutes before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds `$waitTime
        }
    }
}

Write-Host "❌ All retry attempts failed" -ForegroundColor Red
exit 1
"@

    Set-Content -Path $OutputPath -Value $wrapperContent -Encoding UTF8
    Write-LogInfo "✅ Created intelligent retry wrapper: $OutputPath"
}

# Main execution
function Main {
    Write-LogInfo "🧠 Intelligent Rate Limit Recovery System"
    Write-LogInfo "========================================="
    
    $rateLimitStatus = Get-RateLimitStatus
    if ($rateLimitStatus) {
        Write-LogInfo "📊 Current Rate Limit Status:"
        Write-LogInfo "   Core API: $($rateLimitStatus.Core.Remaining)/$($rateLimitStatus.Core.Limit) ($($rateLimitStatus.Core.PercentUsed)% used)"
        Write-LogInfo "   Reset at: $($rateLimitStatus.Core.ResetTime)"
        
        $timeUntilReset = ($rateLimitStatus.Core.ResetTime - (Get-Date)).TotalMinutes
        Write-LogInfo "   Reset in: $([math]::Round($timeUntilReset, 1)) minutes"
    }
    
    if ($MonitorMode) {
        Write-LogInfo "🔄 Starting continuous rate limit monitoring..."
        Start-RateLimitMonitoring
    } else {
        # Create retry wrappers for key scripts
        $scriptsToWrap = @(
            "Monitor-CopilotPRs-Complete.ps1",
            "Auto-Approve-Copilot-Workflows.ps1"
        )
        
        foreach ($script in $scriptsToWrap) {
            $scriptPath = Join-Path $PSScriptRoot $script
            if (Test-Path $scriptPath) {
                $wrapperPath = Join-Path $PSScriptRoot "Retry-$script"
                New-IntelligentRetryWrapper -TargetScript $scriptPath -OutputPath $wrapperPath
            }
        }
    }
}

# Execute main function
Main
