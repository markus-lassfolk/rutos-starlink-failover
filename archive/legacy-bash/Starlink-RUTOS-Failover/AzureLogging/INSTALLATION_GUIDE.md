# Azure Logging Installation and Verification Guide

Version: 2.7.1

This guide covers the comprehensive installation and verification system for Azure logging integration with RUTOS,
Starlink monitoring, and GPS data collection.

## Overview

The Azure logging solution provides:

- System log forwarding to Azure Functions
- Starlink performance monitoring with CSV logging
- GPS location data integration (RUTOS primary, Starlink fallback)
- Automated installation and verification scripts
- UCI-based configuration management

## Installation

### 1. Run the Unified Installation Script

```bash
# Make sure the script is executable
chmod +x /root/unified-azure-setup.sh

# Run the installation (interactive mode)
/root/unified-azure-setup.sh

# Or run in batch mode with pre-configured values
AZURE_ENDPOINT="https://your-app.azurewebsites.net/api/HttpLogIngestor?code=..." \
RUTOS_USERNAME="admin" \
RUTOS_PASSWORD="your-password" \
/root/unified-azure-setup.sh --batch
```

### 2. What the Installation Script Does

The `unified-azure-setup.sh` script automatically:

- **Dependency Installation**: Installs grpcurl, jq, curl, bc, and other required packages
- **UCI Configuration**: Sets up all Azure, GPS, and system configuration parameters
- **Script Installation**: Copies all logging scripts to /root/ and makes them executable
- **GPS Setup**: Configures RUTOS GPS integration with Starlink fallback
- **Network Validation**: Verifies network routes and connectivity
- **Cron Jobs**: Sets up automated monitoring schedules
- **Backup Creation**: Creates backups of existing configurations

### 3. UCI Configuration Parameters

The system uses UCI for centralized configuration:

```bash
# Azure System Logging
uci set azure.system=section
uci set azure.system.enabled='true'
uci set azure.system.endpoint='https://your-app.azurewebsites.net/api/HttpLogIngestor'
uci set azure.system.log_shipper_path='/root/log-shipper.sh'

# Starlink Monitoring
uci set azure.starlink=section
uci set azure.starlink.enabled='true'
uci set azure.starlink.endpoint='https://your-app.azurewebsites.net/api/HttpLogIngestor'
uci set azure.starlink.starlink_ip='192.168.100.1'
uci set azure.starlink.starlink_port='9200'
uci set azure.starlink.csv_file='/overlay/starlink_performance.csv'
uci set azure.starlink.max_size='1048576'

# GPS Configuration
uci set azure.gps=section
uci set azure.gps.enabled='true'
uci set azure.gps.rutos_ip='192.168.80.1'
uci set azure.gps.rutos_username='admin'
uci set azure.gps.rutos_password='your-password'
uci set azure.gps.accuracy_threshold='100'

uci commit azure
```

## Verification

### 1. Run the Verification Script

```bash
# Run comprehensive verification
/root/verify-azure-setup.sh

# Run specific test categories
/root/verify-azure-setup.sh --category dependencies
/root/verify-azure-setup.sh --category logging
/root/verify-azure-setup.sh --category gps
```

### 2. Verification Categories

The verification script tests:

1. **Dependencies**: Checks for required packages (grpcurl, jq, curl, bc)
2. **Logging Configuration**: Validates UCI settings and Azure endpoints
3. **UCI Settings**: Verifies all configuration parameters
4. **Script Installation**: Confirms all scripts are in place and executable
5. **Cron Jobs**: Validates scheduled monitoring tasks
6. **Network Connectivity**: Tests internet and Azure connectivity
7. **Starlink API**: Verifies Starlink gRPC API access
8. **RUTOS GPS**: Tests GPS data collection from RUTOS
9. **Azure Connectivity**: Tests actual Azure Function communication
10. **Live Data Collection**: Validates end-to-end data flow

### 3. Manual Testing

Test individual components:

```bash
# Test Azure logging
/root/test-azure-logging.sh

# Test Starlink monitoring
/root/starlink-azure-monitor.sh

# Test log shipping
/root/log-shipper.sh

# Check cron jobs
crontab -l | grep -E "(log-shipper|starlink-azure-monitor)"
```

## Configuration Management

### Viewing Current Configuration

```bash
# View all Azure configuration
uci show azure

# View specific sections
uci show azure.system
uci show azure.starlink
uci show azure.gps
```

### Modifying Configuration

```bash
# Update Azure endpoint
uci set azure.system.endpoint='https://new-endpoint.com/api/HttpLogIngestor'
uci commit azure

# Enable/disable components
uci set azure.starlink.enabled='false'
uci commit azure

# Update GPS credentials
uci set azure.gps.rutos_username='newuser'
uci set azure.gps.rutos_password='newpass'
uci commit azure
```

## Troubleshooting

### Common Issues

1. **Dependencies Missing**

   ```bash
   # Re-run dependency installation
   /root/unified-azure-setup.sh --dependencies-only
   ```

2. **Network Connectivity**

   ```bash
   # Check internet connectivity
   ping -c 3 8.8.8.8

   # Check Azure endpoint
   curl -I "$(uci get azure.system.endpoint)"
   ```

3. **GPS Not Working**

   ```bash
   # Test RUTOS GPS directly
   curl -u "$(uci get azure.gps.rutos_username):$(uci get azure.gps.rutos_password)" \
        "http://$(uci get azure.gps.rutos_ip)/api/gps/position/status"
   ```

4. **Starlink API Issues**

   ```bash
   # Test Starlink gRPC
   /root/grpcurl -plaintext -d '{"get_status": {}}' \
        "$(uci get azure.starlink.starlink_ip)" SpaceX.API.Device.Device/Handle
   ```

### Log Files

Check these locations for troubleshooting:

- System logs: `/var/log/messages`
- Installation log: `/tmp/azure-setup-*.log`
- Verification log: `/tmp/azure-verification-*.log`
- Starlink CSV: `$(uci get azure.starlink.csv_file)`
- Cron logs: `/var/log/cron` (if available)

## File Structure

```text
/root/
├── unified-azure-setup.sh          # Main installation script
├── verify-azure-setup.sh           # Comprehensive verification script
├── log-shipper.sh                  # System log forwarding
├── starlink-azure-monitor.sh       # Starlink performance monitoring
└── test-azure-logging.sh           # End-to-end testing

/overlay/
├── starlink_performance.csv        # Starlink performance data
└── azure-setup-backup-*/           # Configuration backups
```

## Maintenance

### Regular Checks

1. Run verification weekly: `crontab -e` and add:

   ```shell
   0 2 * * 0 /root/verify-azure-setup.sh > /tmp/weekly-verification.log 2>&1
   ```

2. Monitor CSV file sizes:

   ```bash
   # Check current size
   ls -lh "$(uci get azure.starlink.csv_file)"
   ```

3. Review Azure Function logs in Azure portal for any errors

### Updates

To update the configuration or scripts:

1. Modify UCI settings as needed
2. Re-run verification: `/root/verify-azure-setup.sh`
3. Test end-to-end: `/root/test-azure-logging.sh`

## Support

For issues or questions:

1. Run the verification script for detailed diagnostics
2. Check the troubleshooting section above
3. Review log files for specific error messages
4. Ensure all UCI configuration parameters are correctly set
