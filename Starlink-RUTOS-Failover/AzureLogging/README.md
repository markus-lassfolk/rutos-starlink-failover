# RUTOS to Azure: A Cost-Effective Logging Solution

**Version:** 2.6.0 | **Updated:** 2025-07-24

**Version:** 2.5.0 | **Updated:** 2025-07-24

**Version:** 2.4.12 | **Updated:** 2025-07-21

**Version:** 2.4.11 | **Updated:** 2025-07-21

**Version:** 2.4.10 | **Updated:** 2025-07-21

**Version:** 2.4.9 | **Updated:** 2025-07-21

**Version:** 2.4.8 | **Updated:** 2025-07-21

**Version:** 2.4.7 | **Updated:** 2025-07-21

This document contains all the code and instructions needed to set up a serverless, highly cost-effective logging
pipeline from your RUTOS device to Azure Blob Storage.

> **Note**: This solution integrates with the existing Starlink monitoring infrastructure in this repository. It
> provides centralized log storage for all device logs including failover events, performance metrics, and system
> status.

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed and configured
- RUTOS device with internet connectivity
- Existing Starlink monitoring setup (from main repository)
- Root access to RUTOS device for logging configuration

## Important: Log Source Configuration

By default, RUTOS only keeps logs in RAM (circular buffer) with a 200KB limit (~2 hours of logs). For Azure logging
integration, we need persistent storage with larger capacity.

**Default RUTOS logging:**

- `log_type`: circular (RAM only)
- `log_size`: 200KB
- `log_file`: not set
- Storage: RAM only, lost on reboot

**Required for Azure integration:**

- `log_type`: file (persistent storage)
- `log_size`: 5120KB (5MB)
- `log_file`: `/overlay/messages`
- Storage: Flash memory, survives reboot

The `setup-persistent-logging.sh` script automatically configures these settings.

## Solution Components

This directory contains all necessary files for the Azure logging solution:

### Infrastructure & Cloud Components

- **`main.bicep`** - Azure infrastructure as code (Function App, Storage Account, etc.)
- **`HttpLogIngestor/run.ps1`** - Azure Function PowerShell code
- **`HttpLogIngestor/function.json`** - Function binding configuration

### RUTOS Device Scripts

- **`setup-persistent-logging.sh`** - Configures RUTOS for persistent file logging
- **`log-shipper.sh`** - Ships system logs from RUTOS to Azure (runs via cron)
- **`starlink-azure-monitor.sh`** - Collects Starlink performance data and ships to Azure
- **`unified-azure-setup.sh`** - Automated full setup script (system logs + optional Starlink monitoring)
- **`complete-setup.sh`** - Legacy setup script (system logs only)
- **`test-azure-logging.sh`** - Tests the Azure Function integration

### Documentation

- **`README.md`** - This comprehensive guide
- **`SOLUTION_OVERVIEW.md`** - Technical architecture overview
- **`DEPLOYMENT_CHECKLIST.md`** - Step-by-step deployment validation
- **`ANALYSIS_GUIDE.md`** - Network performance analysis guide

### Analysis Tools

- **`analyze-network-performance.py`** - Python tool for analyzing collected data
- **`requirements.txt`** - Python dependencies for analysis tool
- **`setup-analysis-environment.sh`** - Linux/macOS setup script
- **`setup-analysis-environment.ps1`** - Windows PowerShell setup script

## Analysis and Optimization

After collecting data for a few days/weeks, you can analyze performance patterns and optimize your failover thresholds:

### Performance Analysis Tool

The included Python analysis tool provides comprehensive insights:

```bash
# Set up analysis environment
./setup-analysis-environment.sh  # Linux/macOS
# OR
.\setup-analysis-environment.ps1  # Windows

# Run analysis for last 30 days with visualizations
python analyze-network-performance.py --storage-account mystorageaccount --days 30 --visualizations
```

**What it analyzes:**

- **Failover Patterns**: Frequency, timing, and effectiveness
- **Performance Trends**: Latency, packet loss, throughput over time
- **Threshold Optimization**: Data-driven recommendations for your specific environment
- **Event Correlation**: How system events relate to performance issues
- **Long-term Trends**: Identification of degrading performance or improved stability
- **GPS and Mobility Analysis**: Location-based performance patterns, speed correlation, coverage mapping
- **Movement Patterns**: How mobility affects network performance and failover behavior (using existing VenusOS GPS flow
  patterns)

**Output includes:**

- Detailed JSON report with all metrics including GPS data
- Performance trend visualizations with location mapping
- GPS coverage maps with performance overlays
- Mobility analysis charts (speed vs performance)
- Threshold optimization recommendations
- Event timeline charts
- Location-based performance insights
- Summary statistics and insights

This helps answer questions like:

- Are my failover thresholds too aggressive or too weak?
- When do most network issues occur?
- Is Starlink performance improving or degrading over time?
- How often do forced reboots happen and why?
- What performance patterns predict failover events?
- **Does location affect network performance quality?**
- **How does movement/speed impact connectivity stability?**
- **Are there specific geographic areas with poor performance?**
- **Should failover thresholds be adjusted based on mobility state?**

See `ANALYSIS_GUIDE.md` for complete usage instructions.

Architecture Overview

The solution works in two main parts:

RUTOS Device: A script runs every 5 minutes. It reads the local log file (/overlay/messages), sends its contents to a
secure URL in Azure, and—only upon successful transfer—clears the local file. This prevents log loss and keeps local
storage free.

Azure Cloud: A serverless Azure Function provides the secure URL. When it receives log data, it automatically appends it
to a daily log file in Azure Blob Storage. This entire process runs on a consumption plan, making it effectively free
for this use case.

+--------------+ +-----------------+ +-----------------+ +---------------------+

| RUTOS Device | | Log Shipper | | Azure Function | | Azure Blob Storage |

|--------------| |-----------------| |-----------------| |---------------------|

| | | | | | | |

| /overlay/ |----->| 1. Read log |----->| 3. Receive log |----->| 4. Append to daily |

| messages | | | | data (HTTP) | | log file |

| | | 2. Send w/ cURL | | | | (e.g., 2025-07-15.log)|

| | | | | | | |

+--------------+ +-----------------+ +-----------------+ +---------------------+

## Quick Start Guide

For a complete automated setup with both system logs and optional Starlink monitoring:

```bash
# Copy all scripts to your RUTOS device
scp *.sh root@YOUR_ROUTER_IP:/tmp/

# Run the unified setup
ssh root@YOUR_ROUTER_IP
cd /tmp
chmod +x unified-azure-setup.sh
./unified-azure-setup.sh
```

This will automatically:

1. Configure persistent logging
2. Install system log shipping to Azure
3. Optionally install Starlink performance monitoring
4. Set up automated scheduling for both systems

**What gets monitored:**

- **System Logs**: All RUTOS system events, failover notifications, network changes
- **Starlink Performance** (optional): Real-time metrics in CSV format including:
  - Throughput (up/down)
  - Latency and packet loss
  - Obstruction data
  - SNR and alerts
  - Device state and mobility class
  - **GPS Location Data**: Coordinates, altitude, accuracy (using existing repository GPS patterns)
  - **Movement Analysis**: Speed patterns, location-based performance correlation (compatible with VenusOS GPS flow)

## Manual Setup (Alternative)

If you prefer to set up components individually:

### System Logging Only

## Part 0: RUTOS Logging Setup (Required First Step)

Before deploying Azure resources, configure persistent logging on your RUTOS device:

### 0.1. Configure Persistent Logging

1. **Copy the setup script to your RUTOS device:**

   ```bash
   scp setup-persistent-logging.sh root@YOUR_ROUTER_IP:/tmp/
   ```

2. **Run the setup script on the RUTOS device:**

   ```bash
   ssh root@YOUR_ROUTER_IP
   chmod +x /tmp/setup-persistent-logging.sh
   /tmp/setup-persistent-logging.sh
   ```

3. **Verify the configuration:** The script will:
   - Backup your current configuration
   - Change logging from circular (RAM) to file (persistent)
   - Increase log size from 200KB to 5MB
   - Set log file to `/overlay/messages`
   - Test that logging works correctly

**What this fixes:**

- **Before:** Logs stored in RAM only, 200KB limit, lost on reboot
- **After:** Logs stored persistently on flash, 5MB limit, survives reboot

### Adding Starlink Performance Monitoring

After setting up system logging, you can optionally add Starlink performance monitoring:

1. **Install the Starlink monitoring script:**

   ```bash
   scp starlink-azure-monitor.sh root@YOUR_ROUTER_IP:/usr/bin/
   ssh root@YOUR_ROUTER_IP "chmod +x /usr/bin/starlink-azure-monitor.sh"
   ```

2. **Set up the cron job for performance monitoring:**

   ```bash
   ssh root@YOUR_ROUTER_IP
   echo "*/2 * * * * /usr/bin/starlink-azure-monitor.sh" >> /etc/crontabs/root
   /etc/init.d/cron restart
   ```

3. **Configure the Azure endpoint (same as system logs):**

   ```bash
   uci set azure.starlink.endpoint='https://your-function-app.azurewebsites.net/api/HttpLogIngestor'
   uci commit azure
   ```

This will collect Starlink performance data every 2 minutes and ship it to Azure Blob Storage in CSV format.

## Part 1: Azure Deployment (Bicep & PowerShell)

First, we define and deploy the cloud infrastructure.

1.1. Azure Infrastructure as Code (main.bicep)

This Bicep file defines all necessary Azure resources. You can deploy it using the Azure CLI or PowerShell.

Excellent! That's a very robust and well-thought-out plan. Using the local log file as a temporary buffer is the perfect
way to handle potential internet outages without risking data loss or filling up the device's storage.

I have everything I need to proceed. I will now generate a complete solution for you in a Canvas document. This will
include:

Azure Infrastructure as Code (Bicep): A template to deploy all the necessary Azure resources with a single command.

Azure Function Code (PowerShell): The serverless code that will receive and store your logs.

RUTOS Device Scripts: The shell script to send the logs and the service configuration to run it automatically.

Step-by-Step Guide: A full walkthrough of the deployment process from start to finish.

Here is the complete solution.

RUTOS to Azure Logging Solution

Jul 14, 8:49 AM

Open

1.2. Azure Function Code (PowerShell)

Create a folder named HttpLogIngestor. Inside that folder, create the following two files. This is the code that will
receive the logs.

File 1: run.ps1

Azure Function Code (run.ps1)

Jul 14, 8:49 AM

Open

File 2: function.json

Azure Function Configuration (function.json)

Jul 14, 8:49 AM

Open

## Part 2: RUTOS Device Setup

### 2.1. Verify Logging Setup

Ensure you have completed Part 0 (persistent logging setup) before proceeding. The log-shipper script depends on
persistent log files.

### 2.2. The Log Shipper Script

Create this script on your local machine first, then you will copy it to the router.

RUTOS Log Shipper Script (log-shipper.sh)

Jul 14, 8:49 AM

### 2.3. Automating the Script with Cron

**Important:** Only set up the cron job after confirming persistent logging is working.

Make the script executable: `chmod +x /overlay/log-shipper.sh`

Open the crontab editor on the router: `crontab -e`

Add the following line to run the script every 5 minutes:

```bash
*/5 * * * * /overlay/log-shipper.sh
```

Save and exit the editor. The cron service will automatically pick up the change.

## Part 3: Step-by-Step Deployment Guide

Follow these steps to deploy the entire solution.

### Step 0: Configure RUTOS Logging (Required First)

Run the persistent logging setup script as described in Part 0.

### Step 1: Deploy Azure Resources

Install the Azure CLI.

Save the Bicep code above as main.bicep.

Open a terminal, log in to Azure (az login), and set your subscription (az account set --subscription "My
Subscription").

Run the deployment command. You can override the prefix or location if needed.

Bash

az deployment group create --resource-group YOUR_RESOURCE_GROUP_NAME --template-file main.bicep --parameters
prefix=rutos location=westeurope

Deploy the Function Code:

After the Bicep deployment finishes, find the name of your new Function App (it's an output of the command).

Create a folder named HttpLogIngestor and place run.ps1 and function.json inside it.

Zip the HttpLogIngestor folder. Important: The files must be at the root of the zip, not inside the folder itself.

Deploy the zipped code using the Azure CLI:

Bash

az functionapp deployment source config-zip -g YOUR_RESOURCE_GROUP_NAME -n YOUR_FUNCTION_APP_NAME --src
HttpLogIngestor.zip

Get the Function URL:

Go to the Azure Portal, find your Function App, and navigate to the HttpLogIngestor function.

Click on "Get Function Url" and copy the full URL. It will contain a ?code=... key for security.

Configure the RUTOS Device:

Save the log-shipper.sh script. Paste the Function URL you just copied into the AZURE_FUNCTION_URL variable.

Use a tool like scp (or WinSCP) to copy the log-shipper.sh script to the /overlay/ directory on your RUTOS device.

SSH into your router.

Make the script executable: chmod +x /overlay/log-shipper.sh

Set up the cron job as described in section 2.2.

Verify:

Wait for 5-10 minutes.

Check the Azure Portal. Go to your Storage Account -> Containers -> logs. You should see a new log file named
router-YYYY-MM-DD.log.

Check the local log file on the router: cat /overlay/messages. It should be empty or much smaller than before,
indicating successful transfers.

## Testing and Validation

### Integration Testing

Use the provided test script to validate your deployment:

```bash
# Run the integration test
./test-azure-logging.sh "https://your-app.azurewebsites.net/api/HttpLogIngestor?code=..."
```

### Manual Verification

1. **Check Azure Function Logs**:

   ```bash
   az functionapp logs tail --name YOUR_FUNCTION_APP_NAME --resource-group YOUR_RESOURCE_GROUP_NAME
   ```

2. **Verify Storage Account Access**:

   ```bash
   az storage blob list --container-name logs --account-name YOUR_STORAGE_ACCOUNT_NAME
   ```

3. **Test Log Rotation**: The system automatically creates daily log files (router-YYYY-MM-DD.log)

## Security Considerations

- Uses managed identity authentication (no keys in code)
- HTTPS-only communication
- Function-level authentication keys
- Private blob storage (no public access)
- Minimal required permissions (Storage Blob Data Contributor)

## Cost Optimization

- Consumption plan: Pay only for execution time
- Standard LRS storage: Lowest cost storage tier
- Automatic log rotation prevents unlimited growth
- No continuous running costs

## Troubleshooting

- **HTTP 401/403**: Check Function App authentication key
- **HTTP 500**: Check Function App logs for errors
- **Curl timeouts**: Verify internet connectivity and Function App availability
- **Storage errors**: Verify managed identity permissions

## Integration with Starlink Monitoring

This Azure logging solution works alongside the existing Starlink monitoring scripts:

- Captures all system logs including failover events
- Provides centralized storage for performance analysis
- Enables long-term trend analysis for threshold optimization
- Supports the failover verification script (mentioned in main repository)
