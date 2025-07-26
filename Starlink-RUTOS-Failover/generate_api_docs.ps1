<#
.SYNOPSIS
    Starlink API Documentation Generator (PowerShell Edition)
    Version: 1.0 (Public Edition)

.DESCRIPTION
    This PowerShell script is a utility for developers and enthusiasts who want to explore
    the Starlink gRPC API. It systematically calls a list of known "get" methods,
    formats the JSON response, and saves everything to a single, timestamped
    Markdown file.

    The resulting file serves as a perfect snapshot of the API structure for a
    given firmware version, making it invaluable for tracking changes over time
    and discovering new data points for monitoring.

.NOTES
    Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
    Author: Markus Lassfolk 
    Date:   2025-07-09
    Requires: PowerShell, grpcurl.exe

.LINK
    grpcurl GitHub Repository (for installation):
    https://github.com/fullstorydev/grpcurl
#>

# --- User Configuration ---

# The IP address and port for the Starlink gRPC API. This is standard.
$starlinkIp = "192.168.100.1"
$starlinkPort = "9200"

# The output directory for the documentation file.
# $PSScriptRoot is a special variable that means "the same directory as this script".
$outputDir = $PSScriptRoot

# --- API Methods to Call ---
# This list contains the known safe, read-only "get" commands.
# Action commands like 'reboot' or 'dish_stow' are intentionally excluded.
$methodsToCall = @(
    "get_status",
    "get_history",
    "get_device_info",
    "get_diagnostics",
    "get_location"
)

# --- Main Script ---
Write-Host "--- Starlink API Documentation Generator ---" -ForegroundColor Green

# --- 1. Get API Version for Filename ---
try {
    Write-Host "Fetching current API version..."
    $apiVersionPayload = '{"get_device_info":{}}'
    # Note: Ensure 'grpcurl.exe' is in your system's PATH or in the same directory as this script.
    $versionResponse = & grpcurl.exe -plaintext -max-time 5 -d $apiVersionPayload $starlinkIp SpaceX.API.Device.Device/Handle
    
    # Use PowerShell's native JSON parser to safely extract the version.
    $apiVersion = ($versionResponse | ConvertFrom-Json).apiVersion

    if (-not $apiVersion) { throw "API version not found in response." }
    Write-Host "API version found: $apiVersion" -ForegroundColor Cyan
}
catch {
    Write-Warning "Could not determine API version. Using 'UNKNOWN'."
    $apiVersion = "UNKNOWN"
}

# --- 2. Define Output File ---
# The filename includes the API version and current date for easy tracking.
# The .md extension allows for nice formatting on GitHub.
$dateString = (Get-Date).ToString('yyyy-MM-dd')
$filename = "starlink_api_dump_v${apiVersion}_${dateString}.md"
$fullPath = Join-Path -Path $outputDir -ChildPath $filename

Write-Host "Full output will be saved to: $fullPath" -ForegroundColor Yellow
"=================================================" | Out-File -FilePath $fullPath -Encoding utf8

# --- 3. Loop Through Methods and Generate Documentation ---
foreach ($method in $methodsToCall) {
    Write-Host "`n--- Executing: $method ---"
    
    # The JSON payload required by grpcurl.
    $payload = "{""$($method)"":{}}"
    # Construct the full command string for documentation purposes.
    $fullCommand = "grpcurl.exe -plaintext -max-time 10 -d '$($payload)' $($starlinkIp) SpaceX.API.Device.Device/Handle"

    # Add Markdown headers to the output file.
    "`n## Command: ${method}" | Add-Content -Path $fullPath
    "### Full Command Executed:" | Add-Content -Path $fullPath
    "`# $($fullCommand)" | Add-Content -Path $fullPath
    '```json' | Add-Content -Path $fullPath

    try {
        # Execute the grpcurl command.
        $jsonOutput = & grpcurl.exe -plaintext -max-time 10 -d $payload $starlinkIp SpaceX.API.Device.Device/Handle
        
        # Pretty-print the JSON natively in PowerShell for clean formatting.
        # The -Depth parameter is crucial for deeply nested JSON objects.
        $prettyJson = $jsonOutput | ConvertFrom-Json | ConvertTo-Json -Depth 100

        # Add the pretty-printed JSON to the file.
        $prettyJson | Add-Content -Path $fullPath
    }
    catch {
        $errorMessage = "ERROR: grpcurl.exe command failed for method: $method"
        Write-Warning $errorMessage
        $errorMessage | Add-Content -Path $fullPath
    }

    # Close the Markdown code block.
    '```' | Add-Content -Path $fullPath
}

"=================================================" | Add-Content -Path $fullPath
Write-Host "`nDone. API documentation saved to $fullPath" -ForegroundColor Green
