# This script is triggered by an HTTP POST request.
# It takes the request body (log data from the router) and writes it to 
# appropriate blob storage based on the log type.

using namespace System.Net

# Input bindings are passed as parameters.
param($Request, $TriggerMetadata)

# Get the log content from the body of the HTTP request.
$logData = $Request.Body

# Check if any data was sent.
if ($null -eq $logData -or $logData.Length -eq 0) {
    Write-Host "Received an empty request body."
    # Return a "Bad Request" response if no data is present.
    $statusCode = [HttpStatusCode]::BadRequest
    $body = "Request body cannot be empty."
}
else {
    # Determine log type from headers
    $logType = $Request.Headers['X-Log-Type']
    if ($null -eq $logType) {
        $logType = "system-logs"  # Default to system logs
    }
    
    Write-Host "Received $($logData.Length) bytes of $logType data. Processing..."
    
    # Route to appropriate blob output based on log type
    if ($logType -eq "starlink-performance") {
        # For CSV performance data, write as-is to performance blob
        Push-OutputBinding -Name performanceBlob -Value $logData
        Write-Host "Wrote performance data to starlink-performance CSV"
    } else {
        # For system logs, add timestamp and write to system log blob
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $formattedLogData = "[$timestamp] " + $logData + "`n"
        Push-OutputBinding -Name outputBlob -Value $formattedLogData
        Write-Host "Wrote system log data with timestamp"
    }
    
    # Return a success response.
    $statusCode = [HttpStatusCode]::OK
    $body = "Log data accepted and stored as $logType."
}

# Construct the HTTP response to send back to the RUTOS device.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
})
