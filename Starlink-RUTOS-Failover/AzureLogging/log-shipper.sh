#!/bin/sh

# === RUTOS Log Shipper for Azure ===
# This script reads the local log file, sends its content to an Azure Function,
# and clears the local file upon successful transmission.

# --- CONFIGURATION ---
# IMPORTANT: Paste the URL for your Azure Function here.
# You will get this URL after deploying the Function App. It will look like:
# https://<your-app-name>.azurewebsites.net/api/HttpLogIngestor?code=<some_key>
AZURE_FUNCTION_URL="PASTE_YOUR_AZURE_FUNCTION_URL_HERE"

# The local log file to monitor and ship.
LOG_FILE="/overlay/messages"

# --- SCRIPT LOGIC ---

# Exit immediately if the log file doesn't exist or is empty.
# The '-s' flag checks for existence and non-zero size.
if [ ! -s "$LOG_FILE" ]; then
    # echo "Log file is empty or does not exist. Nothing to do."
    exit 0
fi

# Send the log file content to the Azure Function via HTTP POST.
# -sS: Silent mode, but show errors.
# -w '%{http_code}': Write out the HTTP status code to stdout.
# -o /dev/null: Discard the response body from the server.
# --data-binary @...: Sends the raw content of the file as the request body.
HTTP_STATUS=$(curl -sS -w '%{http_code}' -o /dev/null --data-binary "@$LOG_FILE" "$AZURE_FUNCTION_URL")

# Check if the transmission was successful (HTTP status 200 OK).
if [ "$HTTP_STATUS" -eq 200 ]; then
    # Success! Clear the local log file by truncating it to zero size.
    # This is safer than 'rm' as it preserves file permissions.
    > "$LOG_FILE"
    # echo "Successfully sent logs to Azure. Local log file cleared."
else
    # Failure. Do not clear the local file. It will be retried on the next run.
    # You can check the system log for any curl error messages.
    # echo "Failed to send logs to Azure. HTTP Status: $HTTP_STATUS. Retaining local logs."
    exit 1
fi

exit 0
