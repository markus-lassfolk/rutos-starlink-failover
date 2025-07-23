# Deployment and Validation Checklist

**Version:** 2.6.0 | **Updated:** 2025-07-24

**Version:** 2.5.0 | **Updated:** 2025-07-24

**Version:** 2.4.12 | **Updated:** 2025-07-21

**Version:** 2.4.11 | **Updated:** 2025-07-21

**Version:** 2.4.10 | **Updated:** 2025-07-21

**Version:** 2.4.9 | **Updated:** 2025-07-21

**Version:** 2.4.8 | **Updated:** 2025-07-21

**Version:** 2.4.7 | **Updated:** 2025-07-21

## Pre-Deployment Requirements

### Azure Prerequisites

- [ ] Azure subscription with appropriate permissions
- [ ] Resource group created
- [ ] Azure CLI or PowerShell installed
- [ ] Bicep CLI extension installed

### RUTOS Device Prerequisites

- [ ] SSH access to RUTOS device
- [ ] Starlink connected and operational
- [ ] grpcurl and jq installed (for Starlink monitoring)
- [ ] Internet connectivity for Azure communication

## Azure Infrastructure Deployment

### 1. Deploy Infrastructure

```bash
# Clone repository and navigate to Azure logging
cd Starlink-RUTOS-Failover/AzureLogging

# Update parameters file with your values
# Edit main.parameters.json

# Deploy to Azure
az deployment group create \
  --resource-group your-resource-group \
  --template-file main.bicep \
  --parameters @main.parameters.json
```

### 2. Verify Azure Resources

- [ ] Function App deployed successfully
- [ ] Storage Account created with managed identity
- [ ] Application Insights configured
- [ ] Both blob containers created (system-logs, starlink-performance)
- [ ] Function URL accessible

### 3. Test Azure Function

```bash
# Test the function endpoint
curl -X POST https://your-function-app.azurewebsites.net/api/HttpLogIngestor \
  -H "Content-Type: text/plain" \
  -H "X-Log-Type: system-logs" \
  -d "Test log entry from deployment validation"
```

## RUTOS Device Configuration

### 4. Copy Scripts to Device

```bash
# Copy all scripts to RUTOS device
scp *.sh root@YOUR_ROUTER_IP:/tmp/
```

### 5. Run Unified Setup

```bash
# Connect to RUTOS device
ssh root@YOUR_ROUTER_IP

# Run the unified setup script
cd /tmp
chmod +x unified-azure-setup.sh
./unified-azure-setup.sh
```

### 6. Verify RUTOS Configuration

- [ ] Persistent logging enabled (`uci show system | grep log`)
- [ ] Log shipper cron job installed (`crontab -l`)
- [ ] Azure configuration saved (`uci show azure`)
- [ ] Log files created (`ls -la /overlay/`)

### 7. Test System Logging

```bash
# Generate test log entry
logger -t "azure-test" "Test system log entry"

# Wait for next cron execution (max 5 minutes)
# Check local log file has content
tail /overlay/messages

# Check Azure blob storage for uploaded logs
```

### 8. Test Starlink Monitoring (if enabled)

```bash
# Check Starlink CSV collection
ls -la /overlay/starlink_performance.csv

# Manually run monitoring script
/usr/bin/starlink-azure-monitor.sh

# Verify CSV data is collected
head -5 /overlay/starlink_performance.csv

# Check Azure blob storage for performance data
```

## Validation and Monitoring

### 9. Azure Portal Verification

- [ ] Function App shows successful executions
- [ ] Application Insights shows telemetry data
- [ ] Blob containers contain uploaded files
- [ ] No error messages in Function logs

### 10. RUTOS Device Health Check

```bash
# Check system logs for errors
grep -i error /overlay/messages | tail -10

# Check cron job execution
grep azure /var/log/cron

# Verify disk usage isn't growing unexpectedly
df -h /overlay
```

### 11. End-to-End Data Flow Verification

- [ ] System logs appear in Azure 'system-logs' container
- [ ] Starlink data appears in Azure 'starlink-performance' container
- [ ] Data format is correct (text for logs, CSV for performance)
- [ ] Timestamps are accurate
- [ ] No data loss during transmission

## Ongoing Monitoring

### 12. Set up Alerts (Optional)

```bash
# Azure Function execution failures
# Storage account access issues
# High log volume alerts
# Device connectivity issues
```

### 13. Regular Maintenance Tasks

- [ ] Monitor Azure costs
- [ ] Review log retention policies
- [ ] Update scripts as needed
- [ ] Backup UCI configuration

## Troubleshooting Common Issues

### Azure Function Issues

```bash
# Check Function App logs
az monitor activity-log list --resource-group your-rg

# Test function directly
curl -v https://your-function.azurewebsites.net/api/HttpLogIngestor
```

### RUTOS Connectivity Issues

```bash
# Test internet connectivity
ping 8.8.8.8

# Test Azure endpoint specifically
wget -O - https://your-function.azurewebsites.net/api/HttpLogIngestor

# Check firewall rules
iptables -L -n
```

### Data Collection Issues

```bash
# Check cron service
/etc/init.d/cron status

# Verify log files exist and grow
watch -n 5 'ls -la /overlay/'

# Test manual script execution
/usr/bin/log-shipper.sh
/usr/bin/starlink-azure-monitor.sh
```

## Success Criteria

### System Logging Success

- [ ] RUTOS system events appear in Azure within 5 minutes
- [ ] Local log files rotate properly without filling storage
- [ ] No error messages in system logs
- [ ] Azure Function shows successful executions

### Starlink Monitoring Success (if enabled)

- [ ] Performance data collected every 2 minutes
- [ ] CSV format is valid and complete
- [ ] Data appears in Azure blob storage
- [ ] All Starlink metrics are captured correctly

### Overall Integration Success

- [ ] Both systems operate independently without conflicts
- [ ] Resource usage on RUTOS remains acceptable
- [ ] Azure costs are within expected ranges
- [ ] Data is accessible for analysis and monitoring

## Performance Baselines

### Expected Data Volumes

- **System Logs**: 50-200 KB per hour (varies by activity)
- **Starlink Performance**: ~1 KB per 2-minute interval
- **Storage Growth**: <10 MB per day for typical usage

### Expected Timing

- **Log Upload**: Every 5 minutes via cron
- **Performance Collection**: Every 2 minutes
- **Azure Processing**: Near real-time (<30 seconds)
- **Data Availability**: Within 1-2 minutes in blob storage

### Resource Usage

- **RUTOS Storage**: <50 MB for log files
- **RUTOS CPU**: <1% additional usage
- **Network**: <1 MB per day for log transmission
- **Azure Costs**: <$5/month for typical usage
