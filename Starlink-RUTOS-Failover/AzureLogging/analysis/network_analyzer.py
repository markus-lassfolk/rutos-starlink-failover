#!/usr/bin/env python3
"""
Network Analyzer Module
======================

This module orchestrates the complete network analysis workflow,
coordinating data downloading, parsing, analysis, and visualization.
"""

from typing import Dict, List, Any, Optional
import argparse
import sys
from datetime import datetime, timedelta

from .data_downloader import AzureDataDownloader
from .log_parser import LogParser
from .performance_analyzer import PerformanceAnalyzer
from .visualizer import Visualizer


class NetworkAnalyzer:
    """Main orchestrator for network analysis workflow"""

    def __init__(self, storage_account: str, container_name: str = "logs"):
        self.storage_account = storage_account
        self.container_name = container_name

        # Initialize components
        self.downloader = AzureDataDownloader(storage_account, container_name)
        self.parser = LogParser()
        self.analyzer = PerformanceAnalyzer()
        self.visualizer = Visualizer()

    def run_analysis(
        self,
        days: int = 7,
        generate_visualizations: bool = False,
        output_dir: str = "./analysis_output",
    ) -> Dict[str, Any]:
        """Run complete network analysis workflow"""
        print(f"🚀 Starting network analysis for last {days} days...")

        # Step 1: Download data
        print("📥 Downloading data from Azure Storage...")
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)

        raw_data = self.downloader.download_logs_for_period(start_date, end_date)
        if not raw_data:
            print("❌ No data found for the specified period")
            return {}

        print(f"✅ Downloaded {len(raw_data)} log files")

        # Step 2: Parse data
        print("🔍 Parsing log data...")
        parsed_data = []
        performance_data = []

        for date_str, content in raw_data.items():
            # Parse system logs
            log_entries = self.parser.parse_log_content(content, date_str)
            parsed_data.extend(log_entries)

            # Parse performance data if available
            perf_entries = self.parser.parse_performance_data(content, date_str)
            performance_data.extend(perf_entries)

        print(f"✅ Parsed {len(parsed_data)} log entries")
        print(f"✅ Parsed {len(performance_data)} performance entries")

        # Step 3: Analyze data
        print("📊 Analyzing performance metrics...")
        stats = self.analyzer.calculate_statistics(performance_data)
        patterns = self.analyzer.identify_patterns(performance_data)
        insights = self.analyzer.generate_insights(stats)

        # Step 4: Generate visualizations if requested
        charts = {}
        if generate_visualizations:
            print("📈 Generating visualizations...")
            charts = self.visualizer.create_all_charts(
                performance_data, stats, output_dir
            )
            print(f"✅ Generated {len(charts)} visualization charts")

        # Compile results
        results = {
            "analysis_period": {
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
                "days_analyzed": days,
            },
            "data_summary": {
                "log_entries": len(parsed_data),
                "performance_entries": len(performance_data),
                "log_files_processed": len(raw_data),
            },
            "statistics": stats,
            "patterns": patterns,
            "insights": insights,
            "charts": charts,
        }

        print("🎉 Analysis completed successfully!")
        return results

    def print_summary(self, results: Dict[str, Any]):
        """Print a human-readable summary of analysis results"""
        if not results:
            print("❌ No results to display")
            return

        print("\n" + "=" * 60)
        print("📋 NETWORK ANALYSIS SUMMARY")
        print("=" * 60)

        # Analysis period
        period = results.get("analysis_period", {})
        print(f"📅 Analysis Period: {period.get('days_analyzed')} days")
        print(f"   From: {period.get('start_date', 'N/A')}")
        print(f"   To: {period.get('end_date', 'N/A')}")

        # Data summary
        data_summary = results.get("data_summary", {})
        print(f"\n📊 Data Processed:")
        print(f"   Log entries: {data_summary.get('log_entries', 0):,}")
        print(f"   Performance entries: {data_summary.get('performance_entries', 0):,}")
        print(f"   Log files: {data_summary.get('log_files_processed', 0):,}")

        # Key statistics
        stats = results.get("statistics", {})
        if "ping_stats" in stats:
            ping = stats["ping_stats"]
            print(f"\n🏓 Ping Latency:")
            print(f"   Average: {ping.get('mean', 0):.1f} ms")
            print(f"   Median: {ping.get('median', 0):.1f} ms")
            print(f"   Range: {ping.get('min', 0):.1f} - {ping.get('max', 0):.1f} ms")

        if "packet_loss_stats" in stats:
            loss = stats["packet_loss_stats"]
            print(f"\n📉 Packet Loss:")
            print(f"   Average: {loss.get('mean', 0):.2f}%")
            print(f"   Maximum: {loss.get('max', 0):.2f}%")

        if "throughput_stats" in stats:
            throughput = stats["throughput_stats"]
            print(f"\n🌐 Throughput:")
            dl_mbps = throughput.get("downlink_mean_mbps", 0)
            ul_mbps = throughput.get("uplink_mean_mbps", 0)
            print(f"   Downlink: {dl_mbps:.1f} Mbps")
            print(f"   Uplink: {ul_mbps:.1f} Mbps")

        # Insights
        insights = results.get("insights", [])
        if insights:
            print(f"\n💡 Key Insights:")
            for insight in insights:
                print(f"   • {insight}")

        # Charts
        charts = results.get("charts", {})
        if charts:
            print(f"\n📈 Generated Charts:")
            for chart_type, path in charts.items():
                if path:
                    print(f"   • {chart_type}: {path}")

        print("\n" + "=" * 60)


def main():
    """Main entry point for command-line usage"""
    parser = argparse.ArgumentParser(
        description="Analyze network performance from Azure Storage logs"
    )
    parser.add_argument(
        "--storage-account", required=True, help="Azure Storage account name"
    )
    parser.add_argument(
        "--container", default="logs", help="Storage container name (default: logs)"
    )
    parser.add_argument(
        "--days", type=int, default=7, help="Number of days to analyze (default: 7)"
    )
    parser.add_argument(
        "--visualizations", action="store_true", help="Generate visualization charts"
    )
    parser.add_argument(
        "--output-dir",
        default="./analysis_output",
        help="Output directory for charts and reports",
    )

    args = parser.parse_args()

    try:
        # Create analyzer and run analysis
        analyzer = NetworkAnalyzer(args.storage_account, args.container)
        results = analyzer.run_analysis(
            days=args.days,
            generate_visualizations=args.visualizations,
            output_dir=args.output_dir,
        )

        # Print summary
        analyzer.print_summary(results)

        return 0

    except Exception as e:
        print(f"❌ Analysis failed: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
