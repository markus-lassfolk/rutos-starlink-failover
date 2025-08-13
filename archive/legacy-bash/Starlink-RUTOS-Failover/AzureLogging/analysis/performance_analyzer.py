#!/usr/bin/env python3
"""
Performance Analyzer Module
==========================

This module provides performance analysis capabilities for network data.
It calculates statistics, identifies patterns, and generates insights.
"""

from typing import Dict, List, Any, Optional
import pandas as pd
import numpy as np


class PerformanceAnalyzer:
    """Analyzes performance metrics and calculates statistics"""

    def __init__(self):
        self.stats = {}

    def calculate_statistics(self, data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate comprehensive performance statistics"""
        if not data:
            return {}

        df = pd.DataFrame(data)

        stats = {
            "total_records": len(df),
            "time_range": {
                "start": df["timestamp"].min() if "timestamp" in df else None,
                "end": df["timestamp"].max() if "timestamp" in df else None,
            },
        }

        # Network performance stats
        if "ping_latency_ms" in df.columns:
            stats["ping_stats"] = {
                "mean": df["ping_latency_ms"].mean(),
                "median": df["ping_latency_ms"].median(),
                "std": df["ping_latency_ms"].std(),
                "min": df["ping_latency_ms"].min(),
                "max": df["ping_latency_ms"].max(),
            }

        if "packet_loss_pct" in df.columns:
            stats["packet_loss_stats"] = {
                "mean": df["packet_loss_pct"].mean(),
                "median": df["packet_loss_pct"].median(),
                "max": df["packet_loss_pct"].max(),
            }

        if "downlink_throughput_bps" in df.columns:
            stats["throughput_stats"] = {
                "downlink_mean_mbps": df["downlink_throughput_bps"].mean() / 1_000_000,
                "uplink_mean_mbps": (
                    df["uplink_throughput_bps"].mean() / 1_000_000
                    if "uplink_throughput_bps" in df
                    else 0
                ),
            }

        return stats

    def identify_patterns(self, data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Identify patterns in performance data"""
        if not data:
            return {}

        patterns = {
            "high_latency_events": [],
            "packet_loss_events": [],
            "throughput_drops": [],
        }

        # Analyze for patterns
        df = pd.DataFrame(data)

        if "ping_latency_ms" in df.columns:
            high_latency_threshold = df["ping_latency_ms"].quantile(0.95)
            patterns["high_latency_events"] = df[
                df["ping_latency_ms"] > high_latency_threshold
            ].to_dict("records")

        if "packet_loss_pct" in df.columns:
            patterns["packet_loss_events"] = df[df["packet_loss_pct"] > 1.0].to_dict(
                "records"
            )

        return patterns

    def generate_insights(self, stats: Dict[str, Any]) -> List[str]:
        """Generate human-readable insights from statistics"""
        insights = []

        if "ping_stats" in stats:
            ping_stats = stats["ping_stats"]
            if ping_stats["mean"] > 100:
                insights.append("High average latency detected (>100ms)")
            if ping_stats["std"] > 50:
                insights.append("High latency variability detected")

        if "packet_loss_stats" in stats:
            loss_stats = stats["packet_loss_stats"]
            if loss_stats["mean"] > 1.0:
                insights.append("Significant packet loss detected (>1%)")

        if "throughput_stats" in stats:
            throughput = stats["throughput_stats"]
            if throughput["downlink_mean_mbps"] < 10:
                insights.append("Low average throughput detected (<10 Mbps)")

        return insights
