#!/usr/bin/env pwsh

# Fix MD012 violations (multiple consecutive blank lines) in all markdown files
$files = Get-ChildItem -Path . -Filter "*.md" -Exclude "archive\*" | Where-Object { -not $_.PSIsContainer }

foreach ($file in $files) {
    Write-Host "Processing $($file.Name)..."
    
    $content = Get-Content $file.FullName -Raw
    if ($content) {
        # Replace multiple consecutive blank lines with single blank line
        # This regex matches 3 or more consecutive newlines and replaces with 2 newlines (one blank line)
        $fixedContent = $content -replace '\r?\n\r?\n\r?\n+', "`n`n"
        
        # Ensure file ends with exactly one newline (MD047)
        $fixedContent = $fixedContent.TrimEnd() + "`n"
        
        Set-Content -Path $file.FullName -Value $fixedContent -NoNewline
        Write-Host "Fixed MD012 and MD047 violations in $($file.Name)"
    }
}

Write-Host "MD012 and MD047 fixes complete for all markdown files"
