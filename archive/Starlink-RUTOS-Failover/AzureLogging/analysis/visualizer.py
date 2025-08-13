#!/usr/bin/env python3
"""
Visualizer Module
================

This module provides visualization capabilities for network analysis data.
It creates charts, graphs, and visual representations of performance metrics.
"""

from typing import Dict, List, Any, Optional
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
from datetime import datetime
import io
import base64


class Visualizer:
    """Creates visualizations for network analysis data"""

    def __init__(self):
        # Set style for consistent plotting
        plt.style.use("default")
        sns.set_palette("husl")

    def create_latency_chart(
        self, data: List[Dict[str, Any]], output_path: Optional[str] = None
    ) -> Optional[str]:
        """Create a latency over time chart"""
        if not data:
            return None

        df = pd.DataFrame(data)
        if "timestamp" not in df or "ping_latency_ms" not in df:
            return None

        plt.figure(figsize=(12, 6))
        plt.plot(
            df["timestamp"],
            df["ping_latency_ms"],
            linewidth=1,
            alpha=0.7,
            label="Ping Latency",
        )
        plt.title("Network Latency Over Time")
        plt.xlabel("Time")
        plt.ylabel("Latency (ms)")
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.legend()

        if output_path:
            plt.savefig(output_path, dpi=300, bbox_inches="tight")
            plt.close()
            return output_path
        else:
            # Return base64 encoded image
            buffer = io.BytesIO()
            plt.savefig(buffer, format="png", dpi=300, bbox_inches="tight")
            buffer.seek(0)
            image_base64 = base64.b64encode(buffer.getvalue()).decode()
            plt.close()
            return image_base64

    def create_throughput_chart(
        self, data: List[Dict[str, Any]], output_path: Optional[str] = None
    ) -> Optional[str]:
        """Create a throughput over time chart"""
        if not data:
            return None

        df = pd.DataFrame(data)
        required_cols = ["timestamp", "downlink_throughput_bps"]
        if not all(col in df.columns for col in required_cols):
            return None

        plt.figure(figsize=(12, 6))

        # Convert to Mbps for better readability
        df["downlink_mbps"] = df["downlink_throughput_bps"] / 1_000_000
        if "uplink_throughput_bps" in df.columns:
            df["uplink_mbps"] = df["uplink_throughput_bps"] / 1_000_000
            plt.plot(
                df["timestamp"],
                df["uplink_mbps"],
                linewidth=1,
                alpha=0.7,
                label="Uplink",
            )

        plt.plot(
            df["timestamp"],
            df["downlink_mbps"],
            linewidth=1,
            alpha=0.7,
            label="Downlink",
        )

        plt.title("Network Throughput Over Time")
        plt.xlabel("Time")
        plt.ylabel("Throughput (Mbps)")
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.legend()

        if output_path:
            plt.savefig(output_path, dpi=300, bbox_inches="tight")
            plt.close()
            return output_path
        else:
            buffer = io.BytesIO()
            plt.savefig(buffer, format="png", dpi=300, bbox_inches="tight")
            buffer.seek(0)
            image_base64 = base64.b64encode(buffer.getvalue()).decode()
            plt.close()
            return image_base64

    def create_packet_loss_chart(
        self, data: List[Dict[str, Any]], output_path: Optional[str] = None
    ) -> Optional[str]:
        """Create a packet loss over time chart"""
        if not data:
            return None

        df = pd.DataFrame(data)
        if "timestamp" not in df or "packet_loss_pct" not in df:
            return None

        plt.figure(figsize=(12, 6))
        plt.plot(
            df["timestamp"],
            df["packet_loss_pct"],
            linewidth=1,
            alpha=0.7,
            color="red",
            label="Packet Loss",
        )
        plt.title("Packet Loss Over Time")
        plt.xlabel("Time")
        plt.ylabel("Packet Loss (%)")
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.legend()

        if output_path:
            plt.savefig(output_path, dpi=300, bbox_inches="tight")
            plt.close()
            return output_path
        else:
            buffer = io.BytesIO()
            plt.savefig(buffer, format="png", dpi=300, bbox_inches="tight")
            buffer.seek(0)
            image_base64 = base64.b64encode(buffer.getvalue()).decode()
            plt.close()
            return image_base64

    def create_statistics_summary(
        self, stats: Dict[str, Any], output_path: Optional[str] = None
    ) -> Optional[str]:
        """Create a visual summary of statistics"""
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle("Network Performance Statistics Summary", fontsize=16)

        # Ping statistics
        if "ping_stats" in stats:
            ping_stats = stats["ping_stats"]
            metrics = ["mean", "median", "min", "max"]
            values = [ping_stats.get(m, 0) for m in metrics]

            axes[0, 0].bar(metrics, values, color="skyblue")
            axes[0, 0].set_title("Ping Latency Statistics (ms)")
            axes[0, 0].set_ylabel("Latency (ms)")

        # Packet loss statistics
        if "packet_loss_stats" in stats:
            loss_stats = stats["packet_loss_stats"]
            metrics = ["mean", "median", "max"]
            values = [loss_stats.get(m, 0) for m in metrics]

            axes[0, 1].bar(metrics, values, color="lightcoral")
            axes[0, 1].set_title("Packet Loss Statistics (%)")
            axes[0, 1].set_ylabel("Packet Loss (%)")

        # Throughput statistics
        if "throughput_stats" in stats:
            throughput = stats["throughput_stats"]
            labels = ["Downlink", "Uplink"]
            values = [
                throughput.get("downlink_mean_mbps", 0),
                throughput.get("uplink_mean_mbps", 0),
            ]

            axes[1, 0].bar(labels, values, color="lightgreen")
            axes[1, 0].set_title("Average Throughput (Mbps)")
            axes[1, 0].set_ylabel("Throughput (Mbps)")

        # Record count
        axes[1, 1].text(
            0.5,
            0.5,
            f"Total Records\n{stats.get('total_records', 0)}",
            ha="center",
            va="center",
            fontsize=20,
            transform=axes[1, 1].transAxes,
        )
        axes[1, 1].set_title("Data Summary")
        axes[1, 1].axis("off")

        plt.tight_layout()

        if output_path:
            plt.savefig(output_path, dpi=300, bbox_inches="tight")
            plt.close()
            return output_path
        else:
            buffer = io.BytesIO()
            plt.savefig(buffer, format="png", dpi=300, bbox_inches="tight")
            buffer.seek(0)
            image_base64 = base64.b64encode(buffer.getvalue()).decode()
            plt.close()
            return image_base64

    def create_all_charts(
        self,
        data: List[Dict[str, Any]],
        stats: Dict[str, Any],
        output_dir: str = "./charts",
    ) -> Dict[str, str]:
        """Create all visualization charts and return paths"""
        charts = {}

        # Create output directory if it doesn't exist
        import os

        os.makedirs(output_dir, exist_ok=True)

        # Generate all charts
        latency_path = f"{output_dir}/latency_chart.png"
        throughput_path = f"{output_dir}/throughput_chart.png"
        packet_loss_path = f"{output_dir}/packet_loss_chart.png"
        summary_path = f"{output_dir}/statistics_summary.png"

        charts["latency"] = self.create_latency_chart(data, latency_path)
        charts["throughput"] = self.create_throughput_chart(data, throughput_path)
        charts["packet_loss"] = self.create_packet_loss_chart(data, packet_loss_path)
        charts["summary"] = self.create_statistics_summary(stats, summary_path)

        return charts
