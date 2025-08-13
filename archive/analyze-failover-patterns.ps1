# PowerShell Failover Analysis Script
# analyze-failover-patterns.ps1

param(
    [string]$TempDir = "temp",
    [string]$OutputFile = "failover_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
)

Write-Host "Starting Failover Pattern Analysis..." -ForegroundColor Green

# Initialize report
$report = @"
# Comprehensive Failover Analysis Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Executive Summary
This analysis examines every failover event in your RUTOS Starlink monitoring logs to assess:
- Whether failovers were justified (real quality degradation)
- If earlier detection was possible
- Whether short glitches caused unnecessary failovers
- Optimal timing for failover decisions

"@

# Get all log files
$logFiles = Get-ChildItem -Path $TempDir -Filter "starlink_monitor_*.log" | Sort-Object Name

Write-Host "Found $($logFiles.Count) log files to analyze" -ForegroundColor Cyan

$report += @"

## Log Files Analyzed
$($logFiles | ForEach-Object { "- $($_.Name)" } | Out-String)

## Detailed Failover Analysis

"@

$totalTransitions = 0
$justifiedFailovers = 0
$questionableFailovers = 0
$failbacks = 0

foreach ($logFile in $logFiles) {
    Write-Host "Analyzing $($logFile.Name)..." -ForegroundColor Yellow
    
    $report += "### $($logFile.Name)`n`n"
    
    # Read all state lines
    $stateLines = Select-String -Path $logFile.FullName -Pattern "Current state:" | ForEach-Object { $_.Line }
    
    if ($stateLines.Count -eq 0) {
        $report += "No state information found in this file.`n`n"
        continue
    }
    
    # Track state changes
    $previousState = $null
    $transitionCount = 0
    
    for ($i = 0; $i -lt $stateLines.Count; $i++) {
        $line = $stateLines[$i]
        
        # Parse current state
        if ($line -match "Current state: (\w+), Stability: (\d+), Metric: (\d+)") {
            $currentState = $matches[1]
            $stability = $matches[2]
            $metric = $matches[3]
            $timestamp = ($line -split '\[')[0].Trim()
            
            # Check for state transition
            if ($previousState -and $currentState -ne $previousState) {
                $transitionCount++
                $totalTransitions++
                
                $report += "#### Transition #$transitionCount - $timestamp`n"
                $report += "**Change**: $previousState → $currentState`n"
                $report += "**Stability**: $stability | **Metric**: $metric`n`n"
                
                # Analyze this transition
                $analysis = Analyze-Transition -LogFile $logFile.FullName -Timestamp $timestamp -FromState $previousState -ToState $currentState -LineIndex $i -AllLines $stateLines
                $report += $analysis
                
                # Count transition types
                if ($analysis -match "JUSTIFIED FAILOVER") { $justifiedFailovers++ }
                elseif ($analysis -match "QUESTIONABLE FAILOVER") { $questionableFailovers++ }
                elseif ($analysis -match "FAILBACK") { $failbacks++ }
            }
            
            $previousState = $currentState
        }
    }
    
    if ($transitionCount -eq 0) {
        $report += "No state transitions found in this file.`n`n"
    }
}

# Generate summary
$report += @"

## Executive Summary & Recommendations

### Transition Analysis Results

| Transition Type | Count | Quality Assessment |
|----------------|-------|-------------------|
| Justified Failovers | $justifiedFailovers | ✅ Appropriate decisions |
| Questionable Failovers | $questionableFailovers | ⚠️ May need tuning |
| Successful Failbacks | $failbacks | ✅ Normal operation |
| **Total Transitions** | **$totalTransitions** | |

"@

if (($justifiedFailovers + $questionableFailovers) -gt 0) {
    $successRate = [math]::Round(($justifiedFailovers / ($justifiedFailovers + $questionableFailovers)) * 100, 1)
    
    $report += @"
### Overall Failover Quality: $successRate%

"@
    
    if ($successRate -ge 80) {
        $report += "✅ **EXCELLENT** - Your failover system is making good decisions`n"
    } elseif ($successRate -ge 60) {
        $report += "⚠️ **GOOD** - Minor tuning could improve performance`n"
    } else {
        $report += "❌ **NEEDS IMPROVEMENT** - Significant threshold tuning recommended`n"
    }
}

$report += @"

### Key Findings & Recommendations

"@

if ($questionableFailovers -gt 0) {
    $report += @"
#### ⚠️ Questionable Failovers ($questionableFailovers found)
- **Issue**: Some failovers occurred without clear threshold violations
- **Recommendation**: Consider increasing threshold sensitivity slightly
- **Solution**: Implement hysteresis (different thresholds for failover vs recovery)

"@
}

if ($justifiedFailovers -gt 0) {
    $report += @"
#### ✅ Justified Failovers ($justifiedFailovers found)  
- **Assessment**: System correctly detected quality degradation
- **Performance**: Appropriate failover timing
- **Action**: Continue with current threshold configuration

"@
}

if ($failbacks -gt 0) {
    $report += @"
#### ✅ Successful Failbacks ($failbacks found)
- **Assessment**: System properly restored primary connectivity
- **Performance**: Backup system worked as designed
- **Action**: Failback logic is working correctly

"@
}

$report += @"

### Proposed Optimizations

Based on this analysis, consider implementing:

1. **Hysteresis Thresholds** (if questionable failovers > 0):
   ```bash
   # Failover thresholds (sensitive)
   OBSTRUCTION_FAILOVER=0.001     # 0.1%
   PACKET_LOSS_FAILOVER=0.03      # 3%
   LATENCY_FAILOVER_MS=150        # 150ms
   
   # Recovery thresholds (less sensitive)
   OBSTRUCTION_RECOVERY=0.0005    # 0.05%
   PACKET_LOSS_RECOVERY=0.01      # 1%
   LATENCY_RECOVERY_MS=100        # 100ms
   ```

2. **Enhanced Stability Requirements**:
   ```bash
   STABILITY_CHECKS_REQUIRED=6    # Increase from 5
   STABILITY_WINDOW_SECONDS=360   # 6 minutes
   ```

3. **Predictive Monitoring**:
   - Track metric trends over 2-3 minutes
   - Implement early warning system
   - Consider environmental factors (weather, movement)

### Next Steps

1. **Monitor Implementation**: Continue current monitoring approach
2. **Fine-tuning**: Adjust thresholds based on usage patterns  
3. **Pattern Analysis**: Track correlation with environmental factors
4. **Performance Tracking**: Monitor failover success rate over time

---
*Analysis completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*
"@

# Save report
$report | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "`nAnalysis Complete!" -ForegroundColor Green
Write-Host "Report saved to: $OutputFile" -ForegroundColor Cyan
Write-Host "`nQuick Summary:" -ForegroundColor Yellow
Write-Host "- Total Transitions: $totalTransitions" -ForegroundColor White
Write-Host "- Justified Failovers: $justifiedFailovers" -ForegroundColor Green
Write-Host "- Questionable Failovers: $questionableFailovers" -ForegroundColor Yellow
Write-Host "- Successful Failbacks: $failbacks" -ForegroundColor Green

function Analyze-Transition {
    param(
        [string]$LogFile,
        [string]$Timestamp,
        [string]$FromState,
        [string]$ToState,
        [int]$LineIndex,
        [string[]]$AllLines
    )
    
    $analysis = ""
    
    # Get metrics before and after the transition
    $beforeMetrics = Get-MetricsAroundTransition -LogFile $LogFile -Timestamp $Timestamp -Direction "Before"
    $afterMetrics = Get-MetricsAroundTransition -LogFile $LogFile -Timestamp $Timestamp -Direction "After"
    
    $analysis += "**Pre-transition metrics (last 5 minutes):**`n"
    if ($beforeMetrics) {
        $analysis += "``````n$beforeMetrics`n``````n"
        
        # Check for threshold violations
        $violations = ($beforeMetrics | Select-String "high: 1").Count
        $analysis += "- **Threshold violations detected**: $violations`n`n"
    } else {
        $analysis += "*No metrics found before transition*`n`n"
        $violations = 0
    }
    
    $analysis += "**Post-transition metrics:**`n"
    if ($afterMetrics) {
        $analysis += "``````n$afterMetrics`n``````n"
    } else {
        $analysis += "*No metrics found after transition*`n"
    }
    
    # Assess the transition
    $analysis += "`n**Assessment:**`n"
    
    switch ("$FromState->$ToState") {
        "up->down" {
            if ($violations -gt 0) {
                $analysis += "✅ **JUSTIFIED FAILOVER** - Switched to cellular backup`n"
                $analysis += "- Found $violations threshold violations before failover`n"
                $analysis += "- System correctly detected quality degradation`n"
                $analysis += "- **Timing**: Appropriate`n"
            } else {
                $analysis += "⚠️ **QUESTIONABLE FAILOVER** - Switched to cellular backup`n"
                $analysis += "- No clear threshold violations detected`n"
                $analysis += "- May have been triggered by transient issues`n"
                $analysis += "- **Recommendation**: Review threshold sensitivity`n"
            }
        }
        "down->up" {
            $analysis += "✅ **FAILBACK TO STARLINK** - Restored primary connection`n"
            $analysis += "- System detected improved Starlink quality`n"
            $analysis += "- Cellular backup successfully maintained connectivity`n"
            $analysis += "- **Timing**: Normal failback procedure`n"
        }
        default {
            $analysis += "ℹ️ **UNKNOWN TRANSITION** - $FromState to $ToState`n"
        }
    }
    
    $analysis += "`n---`n`n"
    
    return $analysis
}

function Get-MetricsAroundTransition {
    param(
        [string]$LogFile,
        [string]$Timestamp,
        [string]$Direction
    )
    
    try {
        if ($Direction -eq "Before") {
            $metrics = Select-String -Path $LogFile -Pattern "Metrics -" | Where-Object { $_.Line -lt $Timestamp } | Select-Object -Last 3
        } else {
            $metrics = Select-String -Path $LogFile -Pattern "Metrics -" | Where-Object { $_.Line -gt $Timestamp } | Select-Object -First 2
        }
        
        return ($metrics | ForEach-Object { $_.Line }) -join "`n"
    } catch {
        return $null
    }
}
