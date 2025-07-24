#!/usr/bin/env pwsh
# Autonomous Scheduler Setup for Copilot PR Management
# Creates Windows Task Scheduler jobs for fully autonomous operation

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [string]$Schedule = "Continuous", # Continuous, Hourly, Daily, WorkHours
    [switch]$EnableAutoApproval,
    [switch]$DryRun
)

# Configuration
$ErrorActionPreference = "Continue"
$TaskNamePrefix = "GitHubCopilotAutomation"

# Enhanced logging
function Write-LogInfo { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-LogWarning { param($Message) Write-Host "⚠️ $Message" -ForegroundColor Yellow }
function Write-LogError { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-LogStep { param($Message) Write-Host "🔄 $Message" -ForegroundColor Blue }

# Function to get current script directory
function Get-ScriptDirectory {
    return Split-Path -Parent $PSCommandPath
}

# Function to create monitoring task
function New-MonitoringTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Arguments,
        [string]$Schedule,
        [string]$Description
    )
    
    Write-LogStep "Creating task: $TaskName"
    
    if ($DryRun) {
        Write-LogInfo "DRY RUN: Would create task '$TaskName' with schedule '$Schedule'"
        return $true
    }
    
    try {
        # Define the action
        $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-WindowStyle Hidden -File `"$ScriptPath`" $Arguments"
        
        # Define the trigger based on schedule type
        $triggers = @()
        switch ($Schedule) {
            "Continuous" {
                # Start immediately and run in daemon mode
                $triggers += New-ScheduledTaskTrigger -AtStartup
                $triggers += New-ScheduledTaskTrigger -AtLogOn
                $Arguments += " -DaemonMode -QuietMode"
                $Description += " (Continuous autonomous mode)"
            }
            "Hourly" {
                # Every hour during work hours
                for ($hour = 8; $hour -le 18; $hour++) {
                    $triggers += New-ScheduledTaskTrigger -Daily -At "$($hour):00"
                }
                $Description += " (Hourly during work hours)"
            }
            "Daily" {
                # Once per day
                $triggers += New-ScheduledTaskTrigger -Daily -At "09:00"
                $Description += " (Daily at 9 AM)"
            }
            "WorkHours" {
                # Every 30 minutes during work hours
                for ($hour = 8; $hour -le 18; $hour++) {
                    $triggers += New-ScheduledTaskTrigger -Daily -At "$($hour):00"
                    $triggers += New-ScheduledTaskTrigger -Daily -At "$($hour):30"
                }
                $Description += " (Every 30 minutes during work hours)"
            }
        }
        
        # Task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Principal (run as current user)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        
        # Register the task
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description $Description -Force
        
        Write-LogInfo "✅ Task '$TaskName' created successfully"
        return $true
    }
    catch {
        Write-LogError "Failed to create task '$TaskName': $_"
        return $false
    }
}

# Function to install autonomous scheduling
function Install-AutonomousScheduling {
    Write-LogInfo "🚀 Installing autonomous GitHub Copilot PR management scheduling..."
    Write-LogInfo "Schedule type: $Schedule"
    Write-LogInfo "Auto-approval enabled: $EnableAutoApproval"
    
    $scriptDir = Get-ScriptDirectory
    $success = $true
    
    # Task 1: Main PR Monitoring
    $monitorArgs = "-VerboseOutput"
    if ($EnableAutoApproval) {
        $monitorArgs += " -AutoApproveWorkflows"
    }
    
    $monitorTask = New-MonitoringTask -TaskName "$TaskNamePrefix-PRMonitoring" `
        -ScriptPath "$scriptDir\Monitor-CopilotPRs-Complete.ps1" `
        -Arguments $monitorArgs `
        -Schedule $Schedule `
        -Description "Autonomous GitHub Copilot PR monitoring and management"
    
    $success = $success -and $monitorTask
    
    # Task 2: Rate Limit Monitoring (only for continuous mode)
    if ($Schedule -eq "Continuous") {
        $rateLimitTask = New-MonitoringTask -TaskName "$TaskNamePrefix-RateLimitMonitor" `
            -ScriptPath "$scriptDir\Intelligent-Rate-Limit-Recovery.ps1" `
            -Arguments "-MonitorMode" `
            -Schedule "Continuous" `
            -Description "Intelligent GitHub API rate limit monitoring and recovery"
        
        $success = $success -and $rateLimitTask
    }
    
    # Task 3: Auto-merge (daily cleanup)
    $autoMergeTask = New-MonitoringTask -TaskName "$TaskNamePrefix-AutoMerge" `
        -ScriptPath "$scriptDir\Intelligent-Auto-Merge.ps1" `
        -Arguments "" `
        -Schedule "Daily" `
        -Description "Intelligent auto-merge for safe Copilot PRs"
    
    $success = $success -and $autoMergeTask
    
    if ($success) {
        Write-LogInfo "🎉 Autonomous scheduling installed successfully!"
        Write-LogInfo "Your GitHub Copilot PRs will now be managed automatically"
        
        # Show what was installed
        Write-LogInfo "📋 Installed tasks:"
        Get-ScheduledTask -TaskName "$TaskNamePrefix*" | ForEach-Object {
            Write-LogInfo "   • $($_.TaskName): $($_.Description)"
        }
        
        Write-LogInfo "💡 Use '-Status' to check task status anytime"
        Write-LogInfo "💡 Use '-Uninstall' to remove autonomous scheduling"
    } else {
        Write-LogError "❌ Some tasks failed to install. Check the logs above."
        return $false
    }
    
    return $true
}

# Function to uninstall autonomous scheduling
function Uninstall-AutonomousScheduling {
    Write-LogStep "Removing autonomous GitHub Copilot PR management scheduling..."
    
    if ($DryRun) {
        $tasks = Get-ScheduledTask -TaskName "$TaskNamePrefix*" -ErrorAction SilentlyContinue
        Write-LogInfo "DRY RUN: Would remove $($tasks.Count) task(s)"
        return $true
    }
    
    try {
        $tasks = Get-ScheduledTask -TaskName "$TaskNamePrefix*" -ErrorAction SilentlyContinue
        
        if ($tasks) {
            foreach ($task in $tasks) {
                Write-LogStep "Removing task: $($task.TaskName)"
                Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
                Write-LogInfo "✅ Removed task: $($task.TaskName)"
            }
            Write-LogInfo "🧹 All autonomous scheduling tasks removed successfully"
        } else {
            Write-LogWarning "No autonomous scheduling tasks found to remove"
        }
        
        return $true
    }
    catch {
        Write-LogError "Failed to remove scheduling tasks: $_"
        return $false
    }
}

# Function to show status of autonomous scheduling
function Show-SchedulingStatus {
    Write-LogInfo "📊 Autonomous GitHub Copilot PR Management Status"
    Write-LogInfo "==============================================="
    
    try {
        $tasks = Get-ScheduledTask -TaskName "$TaskNamePrefix*" -ErrorAction SilentlyContinue
        
        if ($tasks) {
            Write-LogInfo "🤖 Autonomous scheduling is ACTIVE"
            Write-LogInfo "Found $($tasks.Count) active task(s):"
            
            foreach ($task in $tasks) {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName
                $nextRun = if ($taskInfo.NextRunTime) { $taskInfo.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Not scheduled" }
                $lastRun = if ($taskInfo.LastRunTime -and $taskInfo.LastRunTime -ne [DateTime]::MinValue) { 
                    $taskInfo.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss") 
                } else { 
                    "Never" 
                }
                $lastResult = $taskInfo.LastTaskResult
                $resultIcon = if ($lastResult -eq 0) { "✅" } elseif ($lastResult -eq 267011) { "🔄" } else { "❌" }
                
                Write-LogInfo ""
                Write-LogInfo "   📋 Task: $($task.TaskName)"
                Write-LogInfo "      State: $($task.State)"
                Write-LogInfo "      Last run: $lastRun"
                Write-LogInfo "      Next run: $nextRun"
                Write-LogInfo "      Last result: $resultIcon $lastResult"
                Write-LogInfo "      Description: $($task.Description)"
            }
            
            # Check if GitHub CLI is authenticated
            Write-LogInfo ""
            Write-LogStep "Checking GitHub CLI authentication..."
            try {
                $authStatus = gh auth status 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "✅ GitHub CLI is authenticated and ready"
                } else {
                    Write-LogWarning "⚠️ GitHub CLI authentication issue: $authStatus"
                }
            }
            catch {
                Write-LogWarning "⚠️ GitHub CLI not available or not authenticated"
            }
            
            # Show recent activity
            Write-LogInfo ""
            Write-LogStep "Recent autonomous activity:"
            $logPath = Join-Path (Get-ScriptDirectory) "copilot-pr-monitoring.log"
            if (Test-Path $logPath) {
                $recentLogs = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
                if ($recentLogs) {
                    foreach ($log in $recentLogs) {
                        Write-LogInfo "   $log"
                    }
                } else {
                    Write-LogInfo "   No recent activity logged"
                }
            } else {
                Write-LogInfo "   No log file found yet"
            }
            
        } else {
            Write-LogWarning "🚫 Autonomous scheduling is NOT ACTIVE"
            Write-LogInfo "Use '-Install' to set up autonomous PR management"
        }
    }
    catch {
        Write-LogError "Failed to get scheduling status: $_"
        return $false
    }
    
    return $true
}

# Main execution
function Main {
    Write-LogInfo "🤖 Autonomous GitHub Copilot PR Management Scheduler"
    Write-LogInfo "==================================================="
    
    # Validate we're running on Windows with Task Scheduler
    if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT") {
        Write-LogError "This script requires Windows with Task Scheduler"
        exit 1
    }
    
    # Check if running as administrator for task creation
    if ($Install -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-LogWarning "⚠️ Installing tasks may require administrator privileges"
        Write-LogInfo "💡 Consider running as administrator if task creation fails"
    }
    
    if ($Install) {
        $result = Install-AutonomousScheduling
        if ($result) {
            Write-LogInfo "🎉 Installation completed successfully!"
        } else {
            Write-LogError "❌ Installation failed"
            exit 1
        }
    }
    elseif ($Uninstall) {
        $result = Uninstall-AutonomousScheduling
        if ($result) {
            Write-LogInfo "🧹 Uninstallation completed successfully!"
        } else {
            Write-LogError "❌ Uninstallation failed"
            exit 1
        }
    }
    elseif ($Status) {
        Show-SchedulingStatus
    }
    else {
        Write-LogInfo "Usage: .\Autonomous-Scheduler-Setup.ps1 [options]"
        Write-LogInfo ""
        Write-LogInfo "Options:"
        Write-LogInfo "  -Install              Install autonomous scheduling"
        Write-LogInfo "  -Uninstall            Remove autonomous scheduling"
        Write-LogInfo "  -Status               Show current status"
        Write-LogInfo "  -Schedule <type>      Schedule type: Continuous, Hourly, Daily, WorkHours (default: Continuous)"
        Write-LogInfo "  -EnableAutoApproval   Enable automatic workflow approval"
        Write-LogInfo "  -DryRun               Show what would be done without doing it"
        Write-LogInfo ""
        Write-LogInfo "Examples:"
        Write-LogInfo "  .\Autonomous-Scheduler-Setup.ps1 -Install -Schedule Continuous -EnableAutoApproval"
        Write-LogInfo "  .\Autonomous-Scheduler-Setup.ps1 -Status"
        Write-LogInfo "  .\Autonomous-Scheduler-Setup.ps1 -Uninstall"
    }
}

# Execute main function
Main
