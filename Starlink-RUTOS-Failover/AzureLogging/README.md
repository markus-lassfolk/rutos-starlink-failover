RUTOS to Azure: A Cost-Effective Logging Solution

This document contains all the code and instructions needed to set up a serverless, highly cost-effective logging pipeline from your RUTOS device to Azure Blob Storage.



Architecture Overview

The solution works in two main parts:



RUTOS Device: A script runs every 5 minutes. It reads the local log file (/overlay/messages), sends its contents to a secure URL in Azure, and—only upon successful transfer—clears the local file. This prevents log loss and keeps local storage free.



Azure Cloud: A serverless Azure Function provides the secure URL. When it receives log data, it automatically appends it to a daily log file in Azure Blob Storage. This entire process runs on a consumption plan, making it effectively free for this use case.



+--------------+      +-----------------+      +-----------------+      +---------------------+

| RUTOS Device |      |   Log Shipper   |      |  Azure Function |      | Azure Blob Storage  |

|--------------|      |-----------------|      |-----------------|      |---------------------|

|              |      |                 |      |                 |      |                     |

| /overlay/    |----->| 1. Read log     |----->| 3. Receive log  |----->| 4. Append to daily  |

| messages     |      |                 |      |    data (HTTP)  |      |    log file         |

|              |      | 2. Send w/ cURL |      |                 |      | (e.g., 2025-07-15.log)|

|              |      |                 |      |                 |      |                     |

+--------------+      +-----------------+      +-----------------+      +---------------------+



Part 1: Azure Deployment (Bicep \& PowerShell)

First, we define and deploy the cloud infrastructure.



1.1. Azure Infrastructure as Code (main.bicep)

This Bicep file defines all necessary Azure resources. You can deploy it using the Azure CLI or PowerShell.





Excellent! That's a very robust and well-thought-out plan. Using the local log file as a temporary buffer is the perfect way to handle potential internet outages without risking data loss or filling up the device's storage.



I have everything I need to proceed. I will now generate a complete solution for you in a Canvas document. This will include:



Azure Infrastructure as Code (Bicep): A template to deploy all the necessary Azure resources with a single command.



Azure Function Code (PowerShell): The serverless code that will receive and store your logs.



RUTOS Device Scripts: The shell script to send the logs and the service configuration to run it automatically.



Step-by-Step Guide: A full walkthrough of the deployment process from start to finish.



Here is the complete solution.

RUTOS to Azure Logging Solution

Jul 14, 8:49 AM



Open



1.2. Azure Function Code (PowerShell)

Create a folder named HttpLogIngestor. Inside that folder, create the following two files. This is the code that will receive the logs.



File 1: run.ps1

Azure Function Code (run.ps1)

Jul 14, 8:49 AM



Open



File 2: function.json

Azure Function Configuration (function.json)

Jul 14, 8:49 AM



Open



Part 2: RUTOS Device Setup

Now, we configure the router to send its logs.





2.1. The Log Shipper Script

Create this script on your local machine first, then you will copy it to the router.

RUTOS Log Shipper Script (log-shipper.sh)

Jul 14, 8:49 AM



2.2. Automating the Script with Cron

The easiest and most efficient way to run this script periodically is with a cron job.



Make the script executable: chmod +x /overlay/log-shipper.sh



Open the crontab editor on the router: crontab -e



Add the following line to run the script every 5 minutes:



\*/5 \* \* \* \* /overlay/log-shipper.sh

Save and exit the editor. The cron service will automatically pick up the change.



Part 3: Step-by-Step Deployment Guide

Follow these steps to deploy the entire solution.



Deploy Azure Resources:



Install the Azure CLI.



Save the Bicep code above as main.bicep.



Open a terminal, log in to Azure (az login), and set your subscription (az account set --subscription "My Subscription").



Run the deployment command. You can override the prefix or location if needed.



Bash



az deployment group create --resource-group YOUR\_RESOURCE\_GROUP\_NAME --template-file main.bicep --parameters prefix=rutos location=westeurope

Deploy the Function Code:



After the Bicep deployment finishes, find the name of your new Function App (it's an output of the command).



Create a folder named HttpLogIngestor and place run.ps1 and function.json inside it.



Zip the HttpLogIngestor folder. Important: The files must be at the root of the zip, not inside the folder itself.



Deploy the zipped code using the Azure CLI:



Bash



az functionapp deployment source config-zip -g YOUR\_RESOURCE\_GROUP\_NAME -n YOUR\_FUNCTION\_APP\_NAME --src HttpLogIngestor.zip

Get the Function URL:



Go to the Azure Portal, find your Function App, and navigate to the HttpLogIngestor function.



Click on "Get Function Url" and copy the full URL. It will contain a ?code=... key for security.



Configure the RUTOS Device:



Save the log-shipper.sh script. Paste the Function URL you just copied into the AZURE\_FUNCTION\_URL variable.



Use a tool like scp (or WinSCP) to copy the log-shipper.sh script to the /overlay/ directory on your RUTOS device.



SSH into your router.



Make the script executable: chmod +x /overlay/log-shipper.sh



Set up the cron job as described in section 2.2.



Verify:



Wait for 5-10 minutes.



Check the Azure Portal. Go to your Storage Account -> Containers -> logs. You should see a new log file named router-YYYY-MM-DD.log.



Check the local log file on the router: cat /overlay/messages. It should be empty or much smaller than before, indicating successful transfers.

