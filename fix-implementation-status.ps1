#!/usr/bin/env pwsh

# Fix IMPLEMENTATION_STATUS.md formatting issues
$filePath = ".\IMPLEMENTATION_STATUS.md"

if (Test-Path $filePath) {
    Write-Host "Fixing IMPLEMENTATION_STATUS.md formatting..."
    
    $content = Get-Content $filePath -Raw
    
    # Remove trailing spaces (MD009)
    $content = $content -replace ' +$', ''
    
    # Fix headings - ensure blank lines around headings (MD022)
    # First ensure there's a blank line before headings (except at start)
    $content = $content -replace '(?<!^)(?<!\n\n)(#### )', "`n`$1"
    
    # Ensure blank line after lists before headings (MD032)
    $content = $content -replace '(\n- .+?)(\n#### )', "`$1`n`n`$2"
    
    # Ensure lists have blank lines around them (MD032)
    $content = $content -replace '(####.+?\n)(\- )', "`$1`n`$2"
    
    # Clean up any multiple consecutive blank lines we might have created
    $content = $content -replace '\r?\n\r?\n\r?\n+', "`n`n"
    
    # Ensure file ends with exactly one newline
    $content = $content.TrimEnd() + "`n"
    
    Set-Content -Path $filePath -Value $content -NoNewline
    Write-Host "Fixed IMPLEMENTATION_STATUS.md formatting issues"
} else {
    Write-Host "IMPLEMENTATION_STATUS.md not found"
}
