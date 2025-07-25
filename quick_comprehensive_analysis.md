# RUTOS Comprehensive Data Analysis

## System State Analysis
- UP states: 1166
- DOWN states: 221

## Routing Analysis
- Good routing (Metric: 1): 1166
- Failover routing (Metric: 20): 221

## Stability Counter Analysis
- Stability 0: 1371 occurrences
- Stability 1: 4 occurrences
- Stability 2: 4 occurrences
- Stability 3: 4 occurrences
- Stability 4: 4 occurrences

## Enhanced GPS Analysis
- Valid GPS: 1269
- Invalid GPS: 0
- GPS satellite range: 0 to 18 satellites
- GPS unique values: 13

## Signal Quality (SNR) Analysis
- SNR Poor conditions: 2 events
- SNR Good conditions: 1269 events
- Above noise floor: 1269 times
- Below noise floor: 0 times
- Persistently low SNR: 0 times
- SNR not persistently low: 1269 times

## Threshold Breach Analysis
- High packet loss flags: 205 events
- High obstruction flags: 187 events
- High latency flags: 0 events

## Monitoring Frequency Analysis
- Monitor starts: 1396
- Monitor completions: 1327
- Monitor stops: 1396
- API errors/failures: 259

## Data Quality Summary
- Total log lines: 11377
- Basic metrics entries: 1269
- Enhanced metrics entries: 1269

## Additional Metrics Available
### New data points discovered:
1. **System state tracking** - Connection up/down status
2. **Routing metrics** - Priority values (1=good, 20=failover)
3. **Stability counters** - Progressive tracking for failback decisions
4. **GPS validity status** - Beyond just satellite counts
5. **SNR quality flags** - Multiple signal quality indicators
6. **Threshold breach flags** - Real-time high flags for each metric
7. **Monitoring health** - API success/failure tracking

