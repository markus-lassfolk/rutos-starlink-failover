#!/usr/bin/env python3
"""
Network Performance and Failover Analysis Tool
==============================================

⚠️  DEPRECATION NOTICE: This file is over 1300 lines and will be refactored.
    For new development, please use the modular version: network-analyzer.py

    The new modular structure provides:
    - Better maintainability (split into analysis/ modules)
    - Improved testability
    - Enhanced readability
    - Easier extensibility

This script analyzes Azure Storage logs and CSV performance data to provide insights into:
- Failover frequency and patterns
- Threshold effectiveness
- Network stability trends
- System reliability metrics
- Starlink performance correlation with system events

Requirements:
- Azure Storage Account access
- Python packages: azure-storage-blob, pandas, matplotlib, seaborn, azure-identity
- Azure CLI authenticated or managed identity configured

Usage:
    python analyze-network-performance.py --storage-account myaccount --days 30

Recommended (new modular version):
    python network-analyzer.py --storage-account myaccount --days 30 --visualizations
"""

import argparse
import logging
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import re
import json
from pathlib import Path

# Azure and data analysis imports
try:
    from azure.storage.blob import BlobServiceClient
    from azure.identity import DefaultAzureCredential
    import pandas as pd
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
    import seaborn as sns
    from collections import defaultdict, Counter
except ImportError as e:
    print(f"Missing required package: {e}")
    print(
        "Install with: pip install azure-storage-blob pandas matplotlib seaborn azure-identity"
    )
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class NetworkAnalyzer:
    """
    Analyzes network performance and failover patterns from Azure Storage data
    """

    def __init__(self, storage_account: str, credential=None):
        """
        Initialize the analyzer with Azure Storage credentials

        Args:
            storage_account: Azure Storage account name
            credential: Azure credential (defaults to DefaultAzureCredential)
        """
        self.storage_account = storage_account
        self.credential = credential or DefaultAzureCredential()

        # Initialize Azure Storage client with managed identity
        self.blob_client = BlobServiceClient(
            account_url=f"https://{storage_account}.blob.core.windows.net",
            credential=self.credential,
        )

        # Data containers
        self.system_logs = []
        self.performance_data = []

        # Analysis results
        self.failover_events = []
        self.reboot_events = []
        self.performance_degradation = []
        self.threshold_violations = []

    def download_data(self, days_back: int = 30) -> None:
        """
        Download system logs and performance data from Azure Storage

        Args:
            days_back: Number of days to analyze (default: 30)
        """
        logger.info(f"Downloading data for the last {days_back} days...")

        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)

        try:
            # Download system logs
            system_container = self.blob_client.get_container_client("system-logs")
            self._download_logs(system_container, start_date, end_date, "system")

            # Download performance data
            performance_container = self.blob_client.get_container_client(
                "starlink-performance"
            )
            self._download_logs(
                performance_container, start_date, end_date, "performance"
            )

            logger.info(f"Downloaded {len(self.system_logs)} system log entries")
            logger.info(
                f"Downloaded {len(self.performance_data)} performance data points"
            )

        except Exception as e:
            logger.error(f"Error downloading data: {e}")
            raise

    def _download_logs(
        self, container_client, start_date: datetime, end_date: datetime, log_type: str
    ) -> None:
        """
        Download logs from a specific container within date range
        """
        try:
            blobs = container_client.list_blobs()

            for blob in blobs:
                # Parse date from blob name (assuming format: router-YYYY-MM-DD.log or YYYY-MM-DD.csv)
                blob_date = self._extract_date_from_blob_name(blob.name)

                if blob_date and start_date.date() <= blob_date <= end_date.date():
                    logger.info(f"Downloading {blob.name}")

                    blob_client = container_client.get_blob_client(blob.name)
                    content = blob_client.download_blob().readall().decode("utf-8")

                    if log_type == "system":
                        self._parse_system_logs(content, blob_date)
                    elif log_type == "performance":
                        self._parse_performance_data(content, blob_date)

        except Exception as e:
            logger.error(f"Error downloading {log_type} logs: {e}")
            raise

    def _extract_date_from_blob_name(self, blob_name: str) -> Optional[datetime.date]:
        """
        Extract date from blob name (router-YYYY-MM-DD.log or YYYY-MM-DD.csv)
        """
        # Pattern for router-YYYY-MM-DD.log or YYYY-MM-DD.csv
        date_pattern = r"(\d{4}-\d{2}-\d{2})"
        match = re.search(date_pattern, blob_name)

        if match:
            try:
                return datetime.strptime(match.group(1), "%Y-%m-%d").date()
            except ValueError:
                pass

        return None

    def _parse_system_logs(self, content: str, log_date: datetime.date) -> None:
        """
        Parse system logs and extract relevant events
        """
        lines = content.strip().split("\n")

        for line in lines:
            if not line.strip():
                continue

            # Parse log entry
            log_entry = self._parse_log_line(line, log_date)
            if log_entry:
                self.system_logs.append(log_entry)

                # Identify specific event types
                self._identify_events(log_entry)

    def _parse_log_line(self, line: str, log_date: datetime.date) -> Optional[Dict]:
        """
        Parse a single log line into structured data
        """
        # RUTOS log format: timestamp hostname process[pid]: message
        # Example: Jul 14 10:30:45 RUTX50 kernel: [12345.678] message

        log_pattern = r"(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\w+)\s+([^:]+):\s*(.+)"
        match = re.match(log_pattern, line)

        if match:
            timestamp_str, hostname, process, message = match.groups()

            # Parse timestamp (add year from log_date)
            try:
                timestamp = datetime.strptime(
                    f"{log_date.year} {timestamp_str}", "%Y %b %d %H:%M:%S"
                )

                return {
                    "timestamp": timestamp,
                    "hostname": hostname,
                    "process": process,
                    "message": message,
                    "raw_line": line,
                }
            except ValueError:
                logger.warning(f"Could not parse timestamp: {timestamp_str}")

        return None

    def _identify_events(self, log_entry: Dict) -> None:
        """
        Identify specific events from log entries
        """
        message = log_entry["message"].lower()
        timestamp = log_entry["timestamp"]

        # Failover events
        failover_keywords = [
            "failover",
            "switching to backup",
            "starlink down",
            "primary wan down",
            "backup wan up",
            "connection restored",
            "wan failover",
        ]

        if any(keyword in message for keyword in failover_keywords):
            self.failover_events.append(
                {
                    "timestamp": timestamp,
                    "type": "failover",
                    "message": log_entry["message"],
                    "process": log_entry["process"],
                }
            )

        # Reboot events
        reboot_keywords = [
            "system startup",
            "kernel:",
            "init:",
            "booting",
            "system halt",
            "restart",
            "reboot",
            "shutdown",
        ]

        if any(keyword in message for keyword in reboot_keywords):
            self.reboot_events.append(
                {
                    "timestamp": timestamp,
                    "type": "reboot",
                    "message": log_entry["message"],
                    "process": log_entry["process"],
                }
            )

    def _parse_performance_data(self, content: str, log_date: datetime.date) -> None:
        """
        Parse CSV performance data
        """
        try:
            # Parse CSV content
            lines = content.strip().split("\n")
            if not lines:
                return

            # Skip header if present
            if lines[0].startswith("timestamp"):
                lines = lines[1:]

            for line in lines:
                if not line.strip():
                    continue

                parts = line.split(",")
                if len(parts) >= 8:  # Minimum expected columns
                    try:
                        # Parse CSV fields
                        performance_entry = {
                            "timestamp": datetime.fromisoformat(
                                parts[0].replace("Z", "+00:00")
                            ),
                            "uptime_s": float(parts[1]) if parts[1] else 0,
                            "downlink_throughput_bps": (
                                float(parts[2]) if parts[2] else 0
                            ),
                            "uplink_throughput_bps": float(parts[3]) if parts[3] else 0,
                            "ping_drop_rate": float(parts[4]) if parts[4] else 0,
                            "ping_latency_ms": float(parts[5]) if parts[5] else 0,
                            "obstruction_duration_s": (
                                float(parts[6]) if parts[6] else 0
                            ),
                            "obstruction_fraction": float(parts[7]) if parts[7] else 0,
                        }

                        # Add additional fields if available
                        if len(parts) > 8:
                            performance_entry.update(
                                {
                                    "currently_obstructed": (
                                        parts[8].lower() == "true"
                                        if parts[8]
                                        else False
                                    ),
                                    "snr": (
                                        float(parts[9])
                                        if len(parts) > 9 and parts[9]
                                        else 0
                                    ),
                                    "alerts_thermal_throttle": (
                                        parts[10].lower() == "true"
                                        if len(parts) > 10 and parts[10]
                                        else False
                                    ),
                                    "alerts_thermal_shutdown": (
                                        parts[11].lower() == "true"
                                        if len(parts) > 11 and parts[11]
                                        else False
                                    ),
                                    "dishy_state": parts[13] if len(parts) > 13 else "",
                                    "mobility_class": (
                                        parts[14] if len(parts) > 14 else ""
                                    ),
                                }
                            )

                        # Add GPS data if available (new columns)
                        if len(parts) > 18:
                            performance_entry.update(
                                {
                                    "latitude": (
                                        float(parts[18])
                                        if parts[18] and parts[18] != ""
                                        else None
                                    ),
                                    "longitude": (
                                        float(parts[19])
                                        if parts[19] and parts[19] != ""
                                        else None
                                    ),
                                    "altitude_m": (
                                        float(parts[20])
                                        if len(parts) > 20
                                        and parts[20]
                                        and parts[20] != ""
                                        else None
                                    ),
                                    "speed_kmh": (
                                        float(parts[21])
                                        if len(parts) > 21
                                        and parts[21]
                                        and parts[21] != ""
                                        else None
                                    ),
                                    "heading_deg": (
                                        float(parts[22])
                                        if len(parts) > 22
                                        and parts[22]
                                        and parts[22] != ""
                                        else None
                                    ),
                                    "gps_source": (
                                        parts[23] if len(parts) > 23 else "none"
                                    ),
                                    "gps_satellites": (
                                        int(parts[24])
                                        if len(parts) > 24
                                        and parts[24]
                                        and parts[24] != ""
                                        else 0
                                    ),
                                    "gps_accuracy_m": (
                                        float(parts[25])
                                        if len(parts) > 25
                                        and parts[25]
                                        and parts[25] != ""
                                        else None
                                    ),
                                }
                            )

                        self.performance_data.append(performance_entry)

                        # Check for performance issues
                        self._check_performance_thresholds(performance_entry)

                    except (ValueError, IndexError) as e:
                        logger.warning(
                            f"Could not parse performance line: {line[:100]}... Error: {e}"
                        )

        except Exception as e:
            logger.error(f"Error parsing performance data: {e}")

    def _check_performance_thresholds(self, entry: Dict) -> None:
        """
        Check if performance metrics violate configured thresholds
        """
        # Define threshold violations (adjust based on your requirements)
        violations = []

        # High latency threshold (adjust based on your setup)
        if entry["ping_latency_ms"] > 600:  # 600ms
            violations.append(f"High latency: {entry['ping_latency_ms']:.1f}ms")

        # High packet loss threshold
        if entry["ping_drop_rate"] > 0.05:  # 5%
            violations.append(f"High packet loss: {entry['ping_drop_rate']*100:.1f}%")

        # Low throughput thresholds (adjust based on your requirements)
        if entry["downlink_throughput_bps"] < 10_000_000:  # 10 Mbps
            violations.append(
                f"Low downlink: {entry['downlink_throughput_bps']/1_000_000:.1f} Mbps"
            )

        # Obstruction issues
        if entry["obstruction_fraction"] > 0.02:  # 2%
            violations.append(
                f"High obstruction: {entry['obstruction_fraction']*100:.1f}%"
            )

        if violations:
            self.threshold_violations.append(
                {
                    "timestamp": entry["timestamp"],
                    "violations": violations,
                    "metrics": entry,
                }
            )

    def analyze_failover_patterns(self) -> Dict:
        """
        Analyze failover frequency and patterns
        """
        if not self.failover_events:
            return {"failover_count": 0, "message": "No failover events found"}

        # Group failovers by day
        daily_failovers = defaultdict(int)
        for event in self.failover_events:
            date_key = event["timestamp"].date()
            daily_failovers[date_key] += 1

        # Calculate statistics
        failover_count = len(self.failover_events)
        days_with_failovers = len(daily_failovers)
        avg_failovers_per_day = failover_count / max(days_with_failovers, 1)

        # Find patterns
        failover_hours = [event["timestamp"].hour for event in self.failover_events]
        peak_hour = (
            Counter(failover_hours).most_common(1)[0] if failover_hours else (0, 0)
        )

        return {
            "failover_count": failover_count,
            "days_with_failovers": days_with_failovers,
            "avg_failovers_per_day": avg_failovers_per_day,
            "peak_hour": peak_hour[0],
            "peak_hour_count": peak_hour[1],
            "daily_distribution": dict(daily_failovers),
        }

    def analyze_performance_trends(self) -> Dict:
        """
        Analyze Starlink performance trends including GPS-based insights
        """
        if not self.performance_data:
            return {"message": "No performance data found"}

        # Convert to DataFrame for easier analysis
        df = pd.DataFrame(self.performance_data)
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        df.set_index("timestamp", inplace=True)

        # Calculate daily averages
        daily_stats = (
            df.resample("D")
            .agg(
                {
                    "ping_latency_ms": ["mean", "max", "std"],
                    "ping_drop_rate": ["mean", "max"],
                    "downlink_throughput_bps": ["mean", "min"],
                    "uplink_throughput_bps": ["mean", "min"],
                    "obstruction_fraction": ["mean", "max"],
                }
            )
            .round(2)
        )

        # Performance degradation events
        degradation_count = len(self.threshold_violations)

        # GPS-based analysis
        gps_analysis = self.analyze_gps_patterns()
        mobility_analysis = self.analyze_mobility_patterns()

        return {
            "total_measurements": len(df),
            "avg_latency": df["ping_latency_ms"].mean(),
            "avg_packet_loss": df["ping_drop_rate"].mean() * 100,
            "avg_downlink_mbps": df["downlink_throughput_bps"].mean() / 1_000_000,
            "avg_uplink_mbps": df["uplink_throughput_bps"].mean() / 1_000_000,
            "avg_obstruction_pct": df["obstruction_fraction"].mean() * 100,
            "degradation_events": degradation_count,
            "daily_stats": daily_stats,
            "gps_analysis": gps_analysis,
            "mobility_analysis": mobility_analysis,
        }

    def analyze_gps_patterns(self) -> Dict:
        """
        Analyze GPS data patterns and location-based performance
        """
        gps_data = [
            p
            for p in self.performance_data
            if p.get("latitude") is not None and p.get("longitude") is not None
        ]

        if not gps_data:
            return {"message": "No GPS data available"}

        df = pd.DataFrame(gps_data)

        # Basic GPS statistics
        location_count = len(df)
        unique_locations = len(df.groupby(["latitude", "longitude"]))

        # GPS source analysis
        gps_sources = (
            df["gps_source"].value_counts().to_dict()
            if "gps_source" in df.columns
            else {}
        )

        # Calculate movement statistics
        movement_analysis = self._analyze_movement_patterns(df)

        # Performance by location patterns
        location_performance = self._analyze_location_performance(df)

        return {
            "gps_data_points": location_count,
            "unique_locations": unique_locations,
            "gps_sources": gps_sources,
            "coverage_area_km2": self._calculate_coverage_area(df),
            "movement_analysis": movement_analysis,
            "location_performance": location_performance,
        }

    def analyze_mobility_patterns(self) -> Dict:
        """
        Analyze mobility patterns and performance correlation
        """
        mobile_data = [
            p for p in self.performance_data if p.get("speed_kmh") is not None
        ]

        if not mobile_data:
            return {"message": "No mobility data available"}

        df = pd.DataFrame(mobile_data)

        # Speed statistics
        avg_speed = df["speed_kmh"].mean() if "speed_kmh" in df.columns else 0
        max_speed = df["speed_kmh"].max() if "speed_kmh" in df.columns else 0

        # Classify by mobility state
        df["mobility_state"] = df["speed_kmh"].apply(self._classify_mobility_state)
        mobility_distribution = df["mobility_state"].value_counts().to_dict()

        # Performance correlation with speed
        speed_performance_correlation = self._analyze_speed_performance_correlation(df)

        return {
            "avg_speed_kmh": round(avg_speed, 2),
            "max_speed_kmh": round(max_speed, 2),
            "mobility_distribution": mobility_distribution,
            "speed_performance_correlation": speed_performance_correlation,
        }

    def _analyze_movement_patterns(self, df: pd.DataFrame) -> Dict:
        """
        Analyze movement patterns from GPS data
        """
        if len(df) < 2:
            return {"message": "Insufficient data for movement analysis"}

        # Calculate distances between consecutive points
        distances = []
        total_distance = 0

        for i in range(1, len(df)):
            prev_lat, prev_lon = df.iloc[i - 1]["latitude"], df.iloc[i - 1]["longitude"]
            curr_lat, curr_lon = df.iloc[i]["latitude"], df.iloc[i]["longitude"]

            distance = self._calculate_distance(prev_lat, prev_lon, curr_lat, curr_lon)
            distances.append(distance)
            total_distance += distance

        avg_distance_per_measurement = (
            sum(distances) / len(distances) if distances else 0
        )

        return {
            "total_distance_km": round(total_distance, 2),
            "avg_distance_per_measurement_m": round(
                avg_distance_per_measurement * 1000, 2
            ),
            "max_distance_between_points_m": (
                round(max(distances) * 1000, 2) if distances else 0
            ),
        }

    def _analyze_location_performance(self, df: pd.DataFrame) -> Dict:
        """
        Analyze performance patterns by location
        """
        # Group by approximate location (rounded to ~100m precision)
        df["lat_rounded"] = (df["latitude"] * 1000).round() / 1000
        df["lon_rounded"] = (df["longitude"] * 1000).round() / 1000

        location_groups = df.groupby(["lat_rounded", "lon_rounded"])

        # Find best and worst performing locations
        location_performance = location_groups.agg(
            {
                "ping_latency_ms": "mean",
                "ping_drop_rate": "mean",
                "downlink_throughput_bps": "mean",
            }
        ).round(2)

        if len(location_performance) > 0:
            best_latency_location = location_performance["ping_latency_ms"].idxmin()
            worst_latency_location = location_performance["ping_latency_ms"].idxmax()

            best_throughput_location = location_performance[
                "downlink_throughput_bps"
            ].idxmax()
            worst_throughput_location = location_performance[
                "downlink_throughput_bps"
            ].idxmin()

            return {
                "total_locations_analyzed": len(location_performance),
                "best_latency_location": {
                    "lat": best_latency_location[0],
                    "lon": best_latency_location[1],
                    "avg_latency_ms": location_performance.loc[
                        best_latency_location, "ping_latency_ms"
                    ],
                },
                "worst_latency_location": {
                    "lat": worst_latency_location[0],
                    "lon": worst_latency_location[1],
                    "avg_latency_ms": location_performance.loc[
                        worst_latency_location, "ping_latency_ms"
                    ],
                },
                "best_throughput_location": {
                    "lat": best_throughput_location[0],
                    "lon": best_throughput_location[1],
                    "avg_throughput_mbps": location_performance.loc[
                        best_throughput_location, "downlink_throughput_bps"
                    ]
                    / 1_000_000,
                },
                "worst_throughput_location": {
                    "lat": worst_throughput_location[0],
                    "lon": worst_throughput_location[1],
                    "avg_throughput_mbps": location_performance.loc[
                        worst_throughput_location, "downlink_throughput_bps"
                    ]
                    / 1_000_000,
                },
            }

        return {"message": "Insufficient location data for analysis"}

    def _calculate_coverage_area(self, df: pd.DataFrame) -> float:
        """
        Calculate approximate coverage area in km²
        """
        if len(df) < 3:
            return 0

        # Simple bounding box calculation
        lat_range = df["latitude"].max() - df["latitude"].min()
        lon_range = df["longitude"].max() - df["longitude"].min()

        # Convert to approximate km (rough calculation)
        lat_km = lat_range * 111  # 1 degree latitude ≈ 111 km
        lon_km = (
            lon_range * 111 * abs(df["latitude"].mean()) / 90
        )  # Adjust for longitude at latitude

        return round(lat_km * lon_km, 2)

    def _calculate_distance(
        self, lat1: float, lon1: float, lat2: float, lon2: float
    ) -> float:
        """
        Calculate distance between two GPS points using Haversine formula (returns km)
        """
        import math

        # Convert to radians
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])

        # Haversine formula
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
        )
        c = 2 * math.asin(math.sqrt(a))

        # Earth radius in km
        r = 6371

        return c * r

    def _classify_mobility_state(self, speed_kmh: float) -> str:
        """
        Classify mobility state based on speed
        """
        if speed_kmh < 1:
            return "stationary"
        elif speed_kmh < 5:
            return "walking"
        elif speed_kmh < 25:
            return "cycling"
        elif speed_kmh < 60:
            return "driving_urban"
        elif speed_kmh < 100:
            return "driving_highway"
        else:
            return "high_speed"

    def _analyze_speed_performance_correlation(self, df: pd.DataFrame) -> Dict:
        """
        Analyze correlation between speed and network performance
        """
        # Group by mobility state
        mobility_performance = (
            df.groupby("mobility_state")
            .agg(
                {
                    "ping_latency_ms": "mean",
                    "ping_drop_rate": "mean",
                    "downlink_throughput_bps": "mean",
                    "obstruction_fraction": "mean",
                }
            )
            .round(2)
        )

        # Calculate correlations
        correlations = {}
        if "speed_kmh" in df.columns and len(df) > 10:
            correlations = {
                "speed_vs_latency": df["speed_kmh"].corr(df["ping_latency_ms"]),
                "speed_vs_packet_loss": df["speed_kmh"].corr(df["ping_drop_rate"]),
                "speed_vs_throughput": df["speed_kmh"].corr(
                    df["downlink_throughput_bps"]
                ),
            }

        return {
            "performance_by_mobility_state": mobility_performance.to_dict(),
            "speed_correlations": correlations,
        }

    def correlate_events_and_performance(self) -> Dict:
        """
        Correlate system events with performance degradation
        """
        correlations = []

        # Check performance around reboot events
        for reboot in self.reboot_events:
            reboot_time = reboot["timestamp"]

            # Find performance data within 1 hour before/after reboot
            relevant_performance = [
                p
                for p in self.performance_data
                if abs((p["timestamp"] - reboot_time).total_seconds()) <= 3600
            ]

            if relevant_performance:
                avg_latency = sum(
                    p["ping_latency_ms"] for p in relevant_performance
                ) / len(relevant_performance)
                avg_loss = sum(p["ping_drop_rate"] for p in relevant_performance) / len(
                    relevant_performance
                )

                correlations.append(
                    {
                        "event_type": "reboot",
                        "timestamp": reboot_time,
                        "performance_samples": len(relevant_performance),
                        "avg_latency_ms": avg_latency,
                        "avg_packet_loss_pct": avg_loss * 100,
                    }
                )

        # Check performance around failover events
        for failover in self.failover_events:
            failover_time = failover["timestamp"]

            # Find performance data within 30 minutes before/after failover
            relevant_performance = [
                p
                for p in self.performance_data
                if abs((p["timestamp"] - failover_time).total_seconds()) <= 1800
            ]

            if relevant_performance:
                avg_latency = sum(
                    p["ping_latency_ms"] for p in relevant_performance
                ) / len(relevant_performance)
                avg_loss = sum(p["ping_drop_rate"] for p in relevant_performance) / len(
                    relevant_performance
                )

                correlations.append(
                    {
                        "event_type": "failover",
                        "timestamp": failover_time,
                        "performance_samples": len(relevant_performance),
                        "avg_latency_ms": avg_latency,
                        "avg_packet_loss_pct": avg_loss * 100,
                    }
                )

        return {"correlations_found": len(correlations), "events": correlations}

    def generate_threshold_recommendations(self) -> Dict:
        """
        Generate threshold optimization recommendations
        """
        if not self.performance_data:
            return {"message": "Insufficient data for recommendations"}

        # Calculate percentiles for key metrics
        latencies = [p["ping_latency_ms"] for p in self.performance_data]
        packet_losses = [p["ping_drop_rate"] for p in self.performance_data]
        throughputs = [p["downlink_throughput_bps"] for p in self.performance_data]

        # Calculate statistics
        latency_95th = sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0
        latency_99th = sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0

        packet_loss_95th = (
            sorted(packet_losses)[int(len(packet_losses) * 0.95)]
            if packet_losses
            else 0
        )

        throughput_5th = (
            sorted(throughputs)[int(len(throughputs) * 0.05)] if throughputs else 0
        )

        # Generate recommendations
        recommendations = {
            "current_thresholds": {
                "latency_threshold_ms": 600,
                "packet_loss_threshold_pct": 5,
                "min_throughput_mbps": 10,
            },
            "recommended_thresholds": {
                "latency_warning_ms": int(
                    latency_95th * 1.1
                ),  # 10% above 95th percentile
                "latency_critical_ms": int(
                    latency_99th * 1.1
                ),  # 10% above 99th percentile
                "packet_loss_warning_pct": round(
                    packet_loss_95th * 100 * 1.2, 2
                ),  # 20% above 95th percentile
                "min_throughput_mbps": round(
                    throughput_5th / 1_000_000 * 0.8, 1
                ),  # 20% below 5th percentile
            },
            "violation_analysis": {
                "total_violations": len(self.threshold_violations),
                "violation_rate_pct": (
                    len(self.threshold_violations) / len(self.performance_data) * 100
                    if self.performance_data
                    else 0
                ),
            },
        }

        return recommendations

    def create_visualizations(self, output_dir: str = "./analysis_output") -> None:
        """
        Create visualization charts for the analysis
        """
        Path(output_dir).mkdir(exist_ok=True)

        # Set style
        plt.style.use("seaborn-v0_8")
        sns.set_palette("husl")

        try:
            # 1. Performance trends over time
            if self.performance_data:
                self._plot_performance_trends(output_dir)

            # 2. Event timeline
            if self.failover_events or self.reboot_events:
                self._plot_event_timeline(output_dir)

            # 3. Threshold violations
            if self.threshold_violations:
                self._plot_threshold_violations(output_dir)

            # 4. GPS and mobility visualizations
            gps_data = [
                p for p in self.performance_data if p.get("latitude") is not None
            ]
            if gps_data:
                self._plot_gps_coverage(output_dir, gps_data)
                self._plot_performance_by_location(output_dir, gps_data)

            # 5. Speed and mobility analysis
            mobile_data = [
                p for p in self.performance_data if p.get("speed_kmh") is not None
            ]
            if mobile_data:
                self._plot_mobility_analysis(output_dir, mobile_data)

            logger.info(f"Visualizations saved to {output_dir}/")

        except Exception as e:
            logger.error(f"Error creating visualizations: {e}")

    def _plot_performance_trends(self, output_dir: str) -> None:
        """
        Plot performance metrics over time
        """
        df = pd.DataFrame(self.performance_data)
        df["timestamp"] = pd.to_datetime(df["timestamp"])

        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle("Starlink Performance Trends", fontsize=16)

        # Latency
        axes[0, 0].plot(df["timestamp"], df["ping_latency_ms"], alpha=0.7)
        axes[0, 0].set_title("Ping Latency")
        axes[0, 0].set_ylabel("Latency (ms)")
        axes[0, 0].grid(True)

        # Packet Loss
        axes[0, 1].plot(
            df["timestamp"], df["ping_drop_rate"] * 100, alpha=0.7, color="red"
        )
        axes[0, 1].set_title("Packet Loss")
        axes[0, 1].set_ylabel("Packet Loss (%)")
        axes[0, 1].grid(True)

        # Throughput
        axes[1, 0].plot(
            df["timestamp"],
            df["downlink_throughput_bps"] / 1_000_000,
            alpha=0.7,
            label="Downlink",
        )
        axes[1, 0].plot(
            df["timestamp"],
            df["uplink_throughput_bps"] / 1_000_000,
            alpha=0.7,
            label="Uplink",
        )
        axes[1, 0].set_title("Throughput")
        axes[1, 0].set_ylabel("Speed (Mbps)")
        axes[1, 0].legend()
        axes[1, 0].grid(True)

        # Obstructions
        axes[1, 1].plot(
            df["timestamp"], df["obstruction_fraction"] * 100, alpha=0.7, color="orange"
        )
        axes[1, 1].set_title("Obstruction Fraction")
        axes[1, 1].set_ylabel("Obstruction (%)")
        axes[1, 1].grid(True)

        # Format x-axes
        for ax in axes.flat:
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%m-%d"))
            ax.xaxis.set_major_locator(mdates.DayLocator(interval=1))
            plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)

        plt.tight_layout()
        plt.savefig(
            f"{output_dir}/performance_trends.png", dpi=300, bbox_inches="tight"
        )
        plt.close()

    def _plot_event_timeline(self, output_dir: str) -> None:
        """
        Plot system events timeline
        """
        fig, ax = plt.subplots(figsize=(15, 6))

        # Plot failover events
        if self.failover_events:
            failover_times = [event["timestamp"] for event in self.failover_events]
            ax.scatter(
                failover_times,
                [1] * len(failover_times),
                c="red",
                s=100,
                alpha=0.7,
                label="Failover Events",
            )

        # Plot reboot events
        if self.reboot_events:
            reboot_times = [event["timestamp"] for event in self.reboot_events]
            ax.scatter(
                reboot_times,
                [2] * len(reboot_times),
                c="orange",
                s=100,
                alpha=0.7,
                label="Reboot Events",
            )

        ax.set_yticks([1, 2])
        ax.set_yticklabels(["Failovers", "Reboots"])
        ax.set_title("System Events Timeline")
        ax.grid(True, alpha=0.3)
        ax.legend()

        # Format x-axis
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%m-%d %H:%M"))
        ax.xaxis.set_major_locator(mdates.DayLocator(interval=1))
        plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)

        plt.tight_layout()
        plt.savefig(f"{output_dir}/events_timeline.png", dpi=300, bbox_inches="tight")
        plt.close()

    def _plot_threshold_violations(self, output_dir: str) -> None:
        """
        Plot threshold violations over time
        """
        if not self.threshold_violations:
            return

        # Group violations by day
        daily_violations = defaultdict(int)
        for violation in self.threshold_violations:
            date_key = violation["timestamp"].date()
            daily_violations[date_key] += 1

        dates = list(daily_violations.keys())
        counts = list(daily_violations.values())

        plt.figure(figsize=(12, 6))
        plt.bar(dates, counts, alpha=0.7, color="red")
        plt.title("Threshold Violations by Day")
        plt.xlabel("Date")
        plt.ylabel("Violation Count")
        plt.xticks(rotation=45)
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(
            f"{output_dir}/threshold_violations.png", dpi=300, bbox_inches="tight"
        )
        plt.close()

    def _plot_gps_coverage(self, output_dir: str, gps_data: List[Dict]) -> None:
        """
        Plot GPS coverage map with performance overlays
        """
        df = pd.DataFrame(gps_data)

        if len(df) < 2:
            return

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))

        # Coverage map
        scatter = ax1.scatter(
            df["longitude"],
            df["latitude"],
            c=df["ping_latency_ms"],
            cmap="RdYlBu_r",
            s=20,
            alpha=0.7,
        )
        ax1.set_title("Coverage Map - Colored by Latency")
        ax1.set_xlabel("Longitude")
        ax1.set_ylabel("Latitude")
        plt.colorbar(scatter, ax=ax1, label="Latency (ms)")

        # Throughput map
        scatter2 = ax2.scatter(
            df["longitude"],
            df["latitude"],
            c=df["downlink_throughput_bps"] / 1_000_000,
            cmap="RdYlGn",
            s=20,
            alpha=0.7,
        )
        ax2.set_title("Coverage Map - Colored by Throughput")
        ax2.set_xlabel("Longitude")
        ax2.set_ylabel("Latitude")
        plt.colorbar(scatter2, ax=ax2, label="Throughput (Mbps)")

        plt.tight_layout()
        plt.savefig(f"{output_dir}/gps_coverage_map.png", dpi=300, bbox_inches="tight")
        plt.close()

    def _plot_performance_by_location(
        self, output_dir: str, gps_data: List[Dict]
    ) -> None:
        """
        Plot performance metrics correlation with location
        """
        df = pd.DataFrame(gps_data)

        if len(df) < 10:
            return

        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle("Performance vs Location Analysis", fontsize=16)

        # Latency vs Latitude
        axes[0, 0].scatter(df["latitude"], df["ping_latency_ms"], alpha=0.6)
        axes[0, 0].set_title("Latency vs Latitude")
        axes[0, 0].set_xlabel("Latitude")
        axes[0, 0].set_ylabel("Latency (ms)")
        axes[0, 0].grid(True, alpha=0.3)

        # Latency vs Longitude
        axes[0, 1].scatter(df["longitude"], df["ping_latency_ms"], alpha=0.6)
        axes[0, 1].set_title("Latency vs Longitude")
        axes[0, 1].set_xlabel("Longitude")
        axes[0, 1].set_ylabel("Latency (ms)")
        axes[0, 1].grid(True, alpha=0.3)

        # Throughput vs Latitude
        axes[1, 0].scatter(
            df["latitude"],
            df["downlink_throughput_bps"] / 1_000_000,
            alpha=0.6,
            color="green",
        )
        axes[1, 0].set_title("Throughput vs Latitude")
        axes[1, 0].set_xlabel("Latitude")
        axes[1, 0].set_ylabel("Throughput (Mbps)")
        axes[1, 0].grid(True, alpha=0.3)

        # Throughput vs Longitude
        axes[1, 1].scatter(
            df["longitude"],
            df["downlink_throughput_bps"] / 1_000_000,
            alpha=0.6,
            color="green",
        )
        axes[1, 1].set_title("Throughput vs Longitude")
        axes[1, 1].set_xlabel("Longitude")
        axes[1, 1].set_ylabel("Throughput (Mbps)")
        axes[1, 1].grid(True, alpha=0.3)

        plt.tight_layout()
        plt.savefig(
            f"{output_dir}/performance_by_location.png", dpi=300, bbox_inches="tight"
        )
        plt.close()

    def _plot_mobility_analysis(self, output_dir: str, mobile_data: List[Dict]) -> None:
        """
        Plot mobility and speed analysis
        """
        df = pd.DataFrame(mobile_data)

        if len(df) < 10:
            return

        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle("Mobility and Speed Analysis", fontsize=16)

        # Speed over time
        df_time = df.copy()
        df_time["timestamp"] = pd.to_datetime(df_time["timestamp"])
        df_time = df_time.sort_values("timestamp")

        axes[0, 0].plot(df_time["timestamp"], df_time["speed_kmh"], alpha=0.7)
        axes[0, 0].set_title("Speed Over Time")
        axes[0, 0].set_ylabel("Speed (km/h)")
        axes[0, 0].grid(True, alpha=0.3)
        axes[0, 0].xaxis.set_major_formatter(mdates.DateFormatter("%m-%d"))
        plt.setp(axes[0, 0].xaxis.get_majorticklabels(), rotation=45)

        # Speed vs Latency
        axes[0, 1].scatter(df["speed_kmh"], df["ping_latency_ms"], alpha=0.6)
        axes[0, 1].set_title("Speed vs Latency")
        axes[0, 1].set_xlabel("Speed (km/h)")
        axes[0, 1].set_ylabel("Latency (ms)")
        axes[0, 1].grid(True, alpha=0.3)

        # Speed vs Throughput
        axes[1, 0].scatter(
            df["speed_kmh"],
            df["downlink_throughput_bps"] / 1_000_000,
            alpha=0.6,
            color="green",
        )
        axes[1, 0].set_title("Speed vs Throughput")
        axes[1, 0].set_xlabel("Speed (km/h)")
        axes[1, 0].set_ylabel("Throughput (Mbps)")
        axes[1, 0].grid(True, alpha=0.3)

        # Speed distribution
        axes[1, 1].hist(df["speed_kmh"], bins=20, alpha=0.7, color="blue")
        axes[1, 1].set_title("Speed Distribution")
        axes[1, 1].set_xlabel("Speed (km/h)")
        axes[1, 1].set_ylabel("Frequency")
        axes[1, 1].grid(True, alpha=0.3)

        plt.tight_layout()
        plt.savefig(f"{output_dir}/mobility_analysis.png", dpi=300, bbox_inches="tight")
        plt.close()

    def generate_report(
        self, output_file: str = "network_analysis_report.json"
    ) -> Dict:
        """
        Generate comprehensive analysis report
        """
        report = {
            "analysis_date": datetime.now().isoformat(),
            "data_summary": {
                "system_logs_count": len(self.system_logs),
                "performance_data_points": len(self.performance_data),
                "analysis_period": {
                    "start": (
                        min(p["timestamp"] for p in self.performance_data).isoformat()
                        if self.performance_data
                        else None
                    ),
                    "end": (
                        max(p["timestamp"] for p in self.performance_data).isoformat()
                        if self.performance_data
                        else None
                    ),
                },
            },
            "failover_analysis": self.analyze_failover_patterns(),
            "performance_analysis": self.analyze_performance_trends(),
            "event_correlation": self.correlate_events_and_performance(),
            "threshold_recommendations": self.generate_threshold_recommendations(),
        }

        # Save report
        with open(output_file, "w") as f:
            json.dump(report, f, indent=2, default=str)

        logger.info(f"Analysis report saved to {output_file}")
        return report


def main():
    """
    Main function to run the network analysis
    """
    parser = argparse.ArgumentParser(
        description="Analyze network performance and failover patterns"
    )
    parser.add_argument(
        "--storage-account", required=True, help="Azure Storage account name"
    )
    parser.add_argument(
        "--days", type=int, default=30, help="Number of days to analyze (default: 30)"
    )
    parser.add_argument(
        "--output-dir", default="./analysis_output", help="Output directory for results"
    )
    parser.add_argument(
        "--visualizations", action="store_true", help="Generate visualization charts"
    )

    args = parser.parse_args()

    try:
        # Initialize analyzer
        logger.info("Initializing Network Performance Analyzer...")
        analyzer = NetworkAnalyzer(args.storage_account)

        # Download and analyze data
        analyzer.download_data(days_back=args.days)

        # Generate analysis report
        report = analyzer.generate_report(
            f"{args.output_dir}/network_analysis_report.json"
        )

        # Create visualizations if requested
        if args.visualizations:
            analyzer.create_visualizations(args.output_dir)

        # Print summary
        print("\n" + "=" * 60)
        print("NETWORK ANALYSIS SUMMARY")
        print("=" * 60)

        failover_analysis = report["failover_analysis"]
        performance_analysis = report["performance_analysis"]

        print(f"Analysis Period: {args.days} days")
        print(f"System Log Entries: {report['data_summary']['system_logs_count']:,}")
        print(
            f"Performance Data Points: {report['data_summary']['performance_data_points']:,}"
        )

        print(f"\nFailover Events: {failover_analysis.get('failover_count', 0)}")
        print(
            f"Average Failovers/Day: {failover_analysis.get('avg_failovers_per_day', 0):.2f}"
        )

        if "avg_latency" in performance_analysis:
            print(f"\nAverage Latency: {performance_analysis['avg_latency']:.1f} ms")
            print(
                f"Average Packet Loss: {performance_analysis['avg_packet_loss']:.2f}%"
            )
            print(
                f"Average Downlink Speed: {performance_analysis['avg_downlink_mbps']:.1f} Mbps"
            )
            print(
                f"Performance Issues: {performance_analysis.get('degradation_events', 0)}"
            )

        recommendations = report["threshold_recommendations"]
        if "recommended_thresholds" in recommendations:
            print(f"\nThreshold Recommendations:")
            rec = recommendations["recommended_thresholds"]
            print(f"  Latency Warning: {rec.get('latency_warning_ms', 'N/A')} ms")
            print(
                f"  Packet Loss Warning: {rec.get('packet_loss_warning_pct', 'N/A')}%"
            )
            print(f"  Min Throughput: {rec.get('min_throughput_mbps', 'N/A')} Mbps")

        print(
            f"\nDetailed report saved to: {args.output_dir}/network_analysis_report.json"
        )
        if args.visualizations:
            print(f"Visualizations saved to: {args.output_dir}/")

    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
