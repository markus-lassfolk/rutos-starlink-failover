#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test version of enhanced Go verification script

.DESCRIPTION
    Simple test to debug the enhanced verification script
#>

param(
    [Parameter(Position=0)]
    [string]$Mode = "all",
    [switch]$Verbose
)

Write-Host "Enhanced Go Verification Script - Test Version"
Write-Host "Mode: $Mode"
Write-Host "Verbose: $Verbose"

# Test basic functionality
if (Get-Command "go" -ErrorAction SilentlyContinue) {
    Write-Host "Go is available"
    $goVersion = go version
    Write-Host "Go version: $goVersion"
} else {
    Write-Host "Go is not available"
}

# Test file finding
$goFiles = Get-ChildItem -Path . -Filter "*.go" -Recurse | 
    Where-Object { 
        $_.FullName -notmatch "vendor|\.git|\.cache|bin|obj" 
    } |
    ForEach-Object { $_.FullName }

Write-Host "Found $($goFiles.Count) Go files"

Write-Host "Test completed successfully"
