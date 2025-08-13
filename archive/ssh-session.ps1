#!/usr/bin/env pwsh
<#
.SYNOPSIS
Maintains a persistent SSH session to RUTOS device for debugging

.DESCRIPTION
This script creates and maintains an SSH session to the RUTOS router,
allowing you to run multiple commands without re-entering credentials.

.PARAMETER RouterIP
The IP address of the RUTOS router (default: 192.168.80.1)

.PARAMETER Username
The SSH username (default: root)

.PARAMETER KeyFile
Path to SSH private key file (optional)

.EXAMPLE
.\ssh-session.ps1 -RouterIP 192.168.80.1
.\ssh-session.ps1 -RouterIP 192.168.80.1 -KeyFile ~/.ssh/id_rsa
#>

param(
    [string]$RouterIP = "192.168.80.1",
    [string]$Username = "root",
    [string]$KeyFile = $null
)

# Set up SSH connection parameters
$sshParams = @()
if ($KeyFile) {
    $sshParams += @("-i", $KeyFile)
}
$sshParams += @("-o", "ServerAliveInterval=60")
$sshParams += @("-o", "ServerAliveCountMax=3")
$sshParams += @("-o", "ConnectTimeout=10")

Write-Host "🔧 RUTOS SSH Session Manager" -ForegroundColor Cyan
Write-Host "Router: $Username@$RouterIP" -ForegroundColor Yellow

# Function to run a command via SSH
function Invoke-SSHCommand {
    param([string]$Command)
    
    $fullCommand = $sshParams + @("$Username@$RouterIP", $Command)
    Write-Host "🚀 Executing: $Command" -ForegroundColor Green
    & ssh @fullCommand
}

# Function to open interactive SSH session
function Start-InteractiveSSH {
    $fullCommand = $sshParams + @("$Username@$RouterIP")
    Write-Host "🔗 Opening interactive SSH session..." -ForegroundColor Green
    & ssh @fullCommand
}

# Menu system
while ($true) {
    Write-Host "`n" + "="*50 -ForegroundColor Blue
    Write-Host "SSH Session Menu" -ForegroundColor Blue
    Write-Host "="*50 -ForegroundColor Blue
    Write-Host "1. Interactive SSH session"
    Write-Host "2. Check system status"
    Write-Host "3. Check starlink services"
    Write-Host "4. View starlink logs"
    Write-Host "5. Test monitoring script"
    Write-Host "6. Check MWAN3 configuration"
    Write-Host "7. Custom command"
    Write-Host "8. View deployment files"
    Write-Host "q. Quit"
    Write-Host ""
    
    $choice = Read-Host "Enter your choice"
    
    switch ($choice.ToLower()) {
        "1" { Start-InteractiveSSH }
        "2" { 
            Invoke-SSHCommand "uptime && free -h && df -h"
        }
        "3" {
            Invoke-SSHCommand "/etc/init.d/starlink-monitor status && /etc/init.d/starlink-logger status"
        }
        "4" {
            Invoke-SSHCommand "ls -la /usr/local/starlink/logs/ && tail -20 /usr/local/starlink/logs/*.log 2>/dev/null || echo 'No logs found'"
        }
        "5" {
            Invoke-SSHCommand "DEBUG=1 /usr/local/starlink/bin/starlink_monitor_unified-rutos.sh test --debug"
        }
        "6" {
            Invoke-SSHCommand "uci show mwan3 | head -20"
        }
        "7" {
            $customCmd = Read-Host "Enter command to execute"
            if ($customCmd) {
                Invoke-SSHCommand $customCmd
            }
        }
        "8" {
            Invoke-SSHCommand "ls -la /usr/local/starlink/bin/ && ls -la /usr/local/starlink/lib/ && ls -la /usr/local/starlink/config/"
        }
        "q" { 
            Write-Host "Goodbye!" -ForegroundColor Yellow
            break 
        }
        default { 
            Write-Host "Invalid choice!" -ForegroundColor Red 
        }
    }
}
