# Test script for error handling system
param([switch]$Help)

if ($Help) {
    Write-Host "Test Help"
    exit 0
}

# Global error collection
$global:CollectedErrors = @()
$global:ErrorCount = 0

function Add-CollectedError {
    param([string]$ErrorMessage)
    $global:ErrorCount++
    Write-Host "Error: $ErrorMessage"
}

function Show-CollectedErrors {
    Write-Host "Total errors: $global:ErrorCount"
}

# Test
Add-CollectedError "Test error"
Show-CollectedErrors
