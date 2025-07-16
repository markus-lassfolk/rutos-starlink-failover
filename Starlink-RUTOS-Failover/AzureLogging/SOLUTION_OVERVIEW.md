# Azure Logging Solution Overview

## Complete Unified System

This Azure logging solution provides comprehensive monitoring for RUTOS devices with optional Starlink performance data
collection. The system is designed to integrate seamlessly with existing Starlink monitoring while adding
enterprise-grade cloud logging capabilities.

## Solution Components

### Azure Infrastructure (Bicep)

- **Function App**: PowerShell-based HTTP trigger for log ingestion
- **Storage Account**: Managed identity authentication with separate containers
- **Application Insights**: Monitoring and diagnostics
- **Security**: No keys stored in configuration, using Azure managed identity

### RUTOS Device Scripts

- **System Logging**: `log-shipper.sh` - Ships system logs to Azure
- **Starlink Monitoring**: `starlink-azure-monitor.sh` - Collects performance data
- **Setup Scripts**: Automated configuration for both systems
- **Persistent Logging**: Enhanced configuration for reliable log storage

### Data Storage

- **System Logs**: Stored in `system-logs` blob container as text files
- **Performance Data**: Stored in `starlink-performance` blob container as CSV files
- **Separation**: Different containers allow for different retention policies and access controls

## Key Features

### Reliability

- **Persistent local storage** prevents data loss during internet outages
- **Automatic retry logic** for failed transmissions
- **Size-limited local files** prevent storage exhaustion
- **Graceful degradation** when Azure services are unavailable

### Security

- **Managed Identity** authentication eliminates key management
- **HTTPS-only** communication with Azure
- **Minimal permissions** following principle of least privilege
- **No credentials** stored on RUTOS devices

### Monitoring Capabilities

- **System Events**: All RUTOS logs including failover events
- **Network Changes**: Interface status, routing updates
- **Starlink Performance**: Real-time metrics every 2 minutes
- **Error Tracking**: Both system errors and performance issues

## Data Collected

### System Logs (Always)

- Kernel messages and system events
- Network interface changes
- Routing table updates
- Service status changes
- Manual administrative actions
- Failover trigger events

### Starlink Performance Data (Optional)

- **Throughput**: Up/down link speeds in bps
- **Latency**: Ping times and drop rates
- **Obstructions**: Duration and percentage
- **Signal Quality**: SNR measurements
- **Alerts**: Thermal, mechanical, and software issues
- **Device State**: Connection status and mobility class

## Setup Options

### Option 1: Complete Unified Setup (Recommended)

```bash
./unified-azure-setup.sh
```

- Interactive configuration
- Handles both system logs and optional Starlink monitoring
- Complete validation and testing
- Single script for entire setup

### Option 2: System Logs Only

```bash
./setup-persistent-logging.sh
./complete-setup.sh
```

- Basic system logging without Starlink data
- Smaller resource footprint
- Can add Starlink monitoring later

### Option 3: Manual Component Installation

- Individual script execution
- Maximum control over configuration
- Suitable for custom deployments

## File Organization

```
AzureLogging/
├── README.md                     # Complete setup documentation
├── SOLUTION_OVERVIEW.md          # This file
├── main.bicep                    # Azure infrastructure
├── main.parameters.json          # Deployment parameters
├── HttpLogIngestor/
│   ├── function.json            # Azure Function bindings
│   └── run.ps1                  # PowerShell log processing
├── unified-azure-setup.sh       # Complete setup script
├── starlink-azure-monitor.sh    # Starlink performance monitoring
├── log-shipper.sh              # System log transmission
├── setup-persistent-logging.sh  # RUTOS logging configuration
└── complete-setup.sh           # System log setup only
```

## Integration with Existing Systems

### Starlink Monitoring

- **Extends** existing `starlink_monitor.sh` functionality
- **Reuses** configuration from main Starlink monitoring setup
- **Compatible** with current CSV logging approach
- **Adds** Azure cloud integration without disrupting local monitoring

### RUTOS Configuration

- **Preserves** existing system configuration
- **Enhances** logging capabilities without breaking changes
- **Maintains** compatibility with standard RUTOS operations
- **Adds** persistent logging for improved reliability

## Deployment Workflow

1. **Deploy Azure Infrastructure**

   ```bash
   az deployment group create \
     --resource-group your-rg \
     --template-file main.bicep \
     --parameters @main.parameters.json
   ```

2. **Configure RUTOS Device**

   ```bash
   ./unified-azure-setup.sh
   ```

3. **Verify Operation**
   - Check Azure Function logs in Application Insights
   - Verify blob storage containers have data
   - Monitor RUTOS device logs for errors

## Maintenance and Monitoring

### Log Rotation

- Local files automatically managed with size limits
- Azure blob storage uses lifecycle management
- Performance data retained based on business requirements

### Error Handling

- Failed transmissions logged locally
- Automatic retry with exponential backoff
- Service degradation alerts via system logs

### Updates

- Scripts designed for easy updates
- Configuration preserved during upgrades
- Backward compatibility maintained

## Cost Optimization

### Resource Sizing

- **Consumption Plan**: Azure Functions scale to zero when idle
- **Standard Storage**: Cost-effective for log data
- **Application Insights**: Configurable retention periods

### Data Management

- Separate containers allow different retention policies
- Performance data can have shorter retention than system logs
- Compression and lifecycle policies reduce storage costs

## Security Considerations

### Authentication

- Managed Identity eliminates credential rotation
- Function-level authentication prevents unauthorized access
- Azure AD integration for administrative access

### Data Protection

- HTTPS encryption in transit
- Azure Storage encryption at rest
- Access policies limit data exposure

### Compliance

- Audit trails for all data access
- Retention policies for compliance requirements
- Geographic data residency options available
