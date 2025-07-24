# Network Performance Analysis Guide

**Version:** v2.6.0 | **Updated:** 2025-07-24

## Overview

The Network Performance Analysis tool helps you understand your RUTOS device behavior, Starlink performance patterns,
and optimize failover thresholds by analyzing the data collected in Azure Storage.

## What This Tool Analyzes

### System Events

- **Failover Events**: When RUTOS switches between Starlink and backup connections
- **Reboot Events**: System restarts (planned and unplanned)
- **Network Changes**: Interface up/down events, routing changes
- **System Errors**: Kernel messages, service failures

### Starlink Performance Metrics

- **Latency**: Ping response times and trends
- **Packet Loss**: Drop rates and patterns
- **Throughput**: Upload/download speeds over time
- **Obstructions**: Satellite view blockages
- **Signal Quality**: SNR measurements
- **Device State**: Connection status and mobility class
- **Alerts**: Thermal, mechanical, and software issues

### Correlation Analysis

- **Performance vs Events**: How network performance relates to system events
- **Threshold Effectiveness**: Whether your current thresholds are too aggressive or too weak
- **Timing Patterns**: When failures typically occur (time of day, day of week)
- **Trend Analysis**: Long-term performance degradation or improvement

## Prerequisites

### Azure Access

- Azure Storage Account with system logs and performance data
- Azure CLI authenticated OR managed identity configured
- Read access to both blob containers (`system-logs` and `starlink-performance`)

### Local Environment

- Python 3.8 or later
- Required packages (installed via requirements.txt)

## Quick Start

### 1. Environment Setup

**Linux/macOS:**

```bash
chmod +x setup-analysis-environment.sh
./setup-analysis-environment.sh
```

**Windows PowerShell:**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup-analysis-environment.ps1
```

### 2. Basic Analysis

```bash
# Activate virtual environment (Linux/macOS)
source venv/bin/activate

# Activate virtual environment (Windows)
venv\Scripts\Activate.ps1

# Run basic analysis for last 30 days
python analyze-network-performance.py --storage-account mystorageaccount --days 30

# Run analysis with visualizations
python analyze-network-performance.py --storage-account mystorageaccount --days 30 --visualizations
```

## Command Line Options

| Option              | Description                  | Default             | Example                  |
| ------------------- | ---------------------------- | ------------------- | ------------------------ |
| `--storage-account` | Azure Storage account name   | Required            | `mystorageaccount`       |
| `--days`            | Number of days to analyze    | 30                  | `--days 7`               |
| `--output-dir`      | Output directory for results | `./analysis_output` | `--output-dir ./reports` |
| `--visualizations`  | Generate charts and graphs   | False               | `--visualizations`       |

## Understanding the Output

### 1. Console Summary

The tool displays a real-time summary:

```text
============================================================
NETWORK ANALYSIS SUMMARY
============================================================
Analysis Period: 30 days
System Log Entries: 15,432
Performance Data Points: 21,600

Failover Events: 12
Average Failovers/Day: 0.4

Average Latency: 45.2 ms
Average Packet Loss: 0.12%
Average Downlink Speed: 87.3 Mbps
Performance Issues: 23

Threshold Recommendations:
  Latency Warning: 180 ms
  Packet Loss Warning: 2.1%
  Min Throughput: 25.4 Mbps
```

### 2. Detailed JSON Report

The tool generates `network_analysis_report.json` with comprehensive data:

```json
{
  "analysis_date": "2025-07-14T10:30:00",
  "data_summary": {
    "system_logs_count": 15432,
    "performance_data_points": 21600,
    "analysis_period": {
      "start": "2025-06-14T00:00:00",
      "end": "2025-07-14T10:30:00"
    }
  },
  "failover_analysis": {
    "failover_count": 12,
    "days_with_failovers": 8,
    "avg_failovers_per_day": 0.4,
    "peak_hour": 14,
    "peak_hour_count": 3
  },
  "performance_analysis": {
    "avg_latency": 45.2,
    "avg_packet_loss": 0.12,
    "avg_downlink_mbps": 87.3,
    "degradation_events": 23
  },
  "threshold_recommendations": {
    "recommended_thresholds": {
      "latency_warning_ms": 180,
      "latency_critical_ms": 220,
      "packet_loss_warning_pct": 2.1,
      "min_throughput_mbps": 25.4
    }
  }
}
```

### 3. Visualizations (with --visualizations flag)

#### Performance Trends Chart

- **Latency over time**: Shows ping response patterns
- **Packet loss over time**: Identifies problem periods
- **Throughput over time**: Upload/download speed trends
- **Obstruction fraction**: Satellite view blockages

#### Events Timeline

- **Failover events**: Red dots showing when failovers occurred
- **Reboot events**: Orange dots showing system restarts
- **Timeline correlation**: Visual relationship between events

#### Threshold Violations

- **Daily violation counts**: How often thresholds are exceeded
- **Pattern identification**: Peak problem periods

## Interpreting Results

### Failover Analysis

**Good Signs:**

- Low failover frequency (< 1 per day average)
- Failovers during known problem times (storms, maintenance)
- Quick recovery after failovers

**Warning Signs:**

- High failover frequency (> 3 per day average)
- Clustered failovers (many in short time)
- Failovers during good weather/conditions

**Action Items:**

- If too many failovers: Increase thresholds (make less sensitive)
- If too few failovers during problems: Decrease thresholds (make more sensitive)

### Performance Trends

**Good Signs:**

- Stable latency (< 100ms average)
- Low packet loss (< 1% average)
- Consistent throughput matching your plan
- Low obstruction rates (< 2%)

**Warning Signs:**

- Increasing latency trends over time
- High packet loss (> 5% regularly)
- Declining throughput trends
- Frequent obstructions (> 5%)

### Threshold Optimization

The tool recommends thresholds based on your actual performance:

- **Conservative approach**: Use 95th percentile values (fewer false alarms)
- **Aggressive approach**: Use 90th percentile values (faster failover)
- **Balanced approach**: Use 95th percentile for warnings, 99th for critical

### Event Correlation

**Key Patterns to Look For:**

- Performance degradation before failovers (indicates thresholds working)
- Random failovers with good performance (indicates thresholds too sensitive)
- Missed failovers during poor performance (indicates thresholds too relaxed)
- Reboot events correlating with performance issues

## Optimization Recommendations

### Based on Analysis Results

#### High Failover Rate (> 2/day average)

1. **Increase latency thresholds** by 20-30%
2. **Increase packet loss thresholds** by 20-30%
3. **Add hysteresis delays** to prevent flapping
4. **Check for interference sources**

#### Low Failover Rate During Problems

1. **Decrease latency thresholds** by 10-20%
2. **Decrease packet loss thresholds** by 10-20%
3. **Add additional monitoring metrics**
4. **Implement multi-factor triggering**

#### Performance Degradation Trends

1. **Check for obstructions** (trees growing, new buildings)
2. **Monitor thermal issues** (check alerts data)
3. **Verify Starlink firmware** is current
4. **Consider dish repositioning**

### Threshold Configuration Examples

Based on typical analysis results:

```bash
# Conservative settings (fewer failovers)
LATENCY_THRESHOLD=200ms
PACKET_LOSS_THRESHOLD=5%
MIN_THROUGHPUT=20Mbps

# Aggressive settings (faster failover)
LATENCY_THRESHOLD=120ms
PACKET_LOSS_THRESHOLD=2%
MIN_THROUGHPUT=40Mbps

# Balanced settings (recommended)
LATENCY_THRESHOLD=150ms
PACKET_LOSS_THRESHOLD=3%
MIN_THROUGHPUT=30Mbps
```

## Automation and Scheduling

### Regular Analysis

Create a script to run analysis weekly:

```bash
#!/bin/bash
# weekly-analysis.sh
cd /path/to/analysis
source venv/bin/activate
python analyze-network-performance.py \
  --storage-account mystorageaccount \
  --days 7 \
  --visualizations \
  --output-dir "./weekly-reports/$(date +%Y-%m-%d)"
```

### Azure Automation

You can also run this analysis in Azure:

- **Azure Container Instances**: Run analysis on demand
- **Azure Functions**: Triggered analysis on schedule
- **Azure Automation**: PowerShell-based scheduled analysis

## Troubleshooting

### Common Issues

**Authentication Errors:**

```bash
# Ensure Azure CLI is logged in
az login
az account show

# Or configure managed identity in Azure environment
```

**Missing Data:**

- Verify Azure Function is processing logs correctly
- Check blob containers have data for the specified date range
- Ensure both system-logs and starlink-performance containers exist

**Performance Issues:**

- Large datasets may take several minutes to process
- Consider reducing analysis period for faster results
- Use `--days 7` for quicker analysis

**Visualization Errors:**

- Ensure all Python packages are installed correctly
- Check that matplotlib backend supports display/file output
- Try running without `--visualizations` first

### Data Validation

```bash
# Check what data is available
az storage blob list --container-name system-logs --account-name mystorageaccount
az storage blob list --container-name starlink-performance --account-name mystorageaccount

# Verify recent data
az storage blob download --container-name system-logs --name router-2025-07-14.log --account-name mystorageaccount
```

## Advanced Usage

### Custom Analysis Scripts

You can extend the analyzer for custom needs:

```python
from analyze_network_performance import NetworkAnalyzer

# Initialize analyzer
analyzer = NetworkAnalyzer('mystorageaccount')
analyzer.download_data(days_back=7)

# Custom analysis
custom_results = analyzer.custom_analysis_function()
```

### Integration with Monitoring Systems

Export results to monitoring platforms:

- **Grafana**: Import JSON data for dashboards
- **Power BI**: Connect to JSON reports
- **Splunk**: Forward analysis results
- **Prometheus**: Export metrics format

This analysis tool will give you the insights you need to optimize your failover thresholds and understand your network
behavior patterns!
