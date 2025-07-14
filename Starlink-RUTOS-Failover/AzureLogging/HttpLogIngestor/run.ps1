# This script is triggered by an HTTP POST request.
# It takes the entire request body (the log data from the router)
# and writes it to an append blob in Azure Storage.

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
    Write-Host "Received $($logData.Length) bytes of log data. Pushing to output blob."
    # Set the output binding variable. The Azure Functions runtime will handle
    # creating the blob and appending the data.
    Push-OutputBinding -Name outputBlob -Value $logData

    # Return a success response.
    $statusCode = [HttpStatusCode]::OK
    $body = "Log data accepted."
}

# Construct the HTTP response to send back to the RUTOS device.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
})
