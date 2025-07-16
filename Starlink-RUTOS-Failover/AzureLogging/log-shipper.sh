#!/bin/sh
# shellcheck disable=SC1091 # Dynamic source files

# === RUTOS Log Shipper for Azure ===
# This script reads the # local log file, sends its content to an Azure Function,
# and clears the # local file upon successful transmission.
#
# IMPORTANT: Requires persistent logging to be configured first!
# Run setup-persistent-logging.sh to configure RUTOS for file-based logging
# before using this script.

# --- CONFIGURATION ---
# Read configuration from UCI if available, otherwise use defaults
AZURE_FUNCTION_URL=$(uci get azure.system.endpoint 2>/dev/null || echo "")
LOG_FILE=$(uci get azure.system.log_file 2>/dev/null || echo "/overlay/messages")
# shellcheck disable=SC2034  # MAX_SIZE may be used for future file rotation
MAX_SIZE=$(uci get azure.system.max_size 2>/dev/null || echo "1048576") # 1MB default
ENABLED=$(uci get azure.system.enabled 2>/dev/null || echo "1")

# --- VALIDATION ---
# Check if Azure logging is enabled
if [ "$ENABLED" != "1" ]; then
	# Silently exit if disabled
	exit 0
fi

# Check if the Azure Function URL has been configured
if [ -z "$AZURE_FUNCTION_URL" ]; then
	echo "Error: Azure Function URL not configured. Please set azure.system.endpoint in UCI."
	logger -t "log-shipper" "ERROR: Azure Function URL not configured"
	exit 1
fi

# Validate URL format (basic HTTPS check, allow custom domains)
if ! echo "$AZURE_FUNCTION_URL" | grep -q "^https://"; then
	echo "Error: Azure Function URL must use HTTPS protocol."
	echo "Provided URL: $AZURE_FUNCTION_URL"
	exit 1
fi

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
# --max-time 30: Timeout after 30 seconds
HTTP_STATUS=$(curl -sS -w '%{http_code}' -o /dev/null --max-time 30 --data-binary "@$LOG_FILE" "$AZURE_FUNCTION_URL" 2>/dev/null)
CURL_EXIT_CODE=$?

# Check curl command exit status first
if [ "$CURL_EXIT_CODE" -ne 0 ]; then
	logger -t "azure-log-shipper" "curl failed with exit code $CURL_EXIT_CODE"
	exit 1
fi

# Check if the transmission was successful (HTTP status 200 OK).
if [ "$HTTP_STATUS" -eq 200 ]; then
	# Success! Clear the # local log file by truncating it to zero size.
	# This is safer than 'rm' as it preserves file permissions.
	true >"$LOG_FILE"
	logger -t "azure-log-shipper" "Successfully sent logs to Azure. # local log file cleared."
else
	# Failure. Do not clear the # local file. It will be retried on the next run.
	logger -t "azure-log-shipper" "Failed to send logs to Azure. HTTP Status: $HTTP_STATUS. Retaining # local logs."
	exit 1
fi

exit 0
