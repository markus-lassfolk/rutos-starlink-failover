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

from .data_downloader import DataDownloader
from .log_parser import LogParser
from .performance_analyzer import PerformanceAnalyzer
from .visualizer import Visualizer


class NetworkAnalyzer:
    """Main orchestrator for network analysis workflow"""

    def __init__(self, storage_account: str, container_name: str = "logs"):
        self.storage_account = storage_account
        self.container_name = container_name

        # Initialize components
        self.downloader = DataDownloader(storage_account)
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

        self.downloader.download_data(days)
        if not self.downloader.system_logs and not self.downloader.performance_data:
            print("❌ No data found for the specified period")
            return {}

        print(f"✅ Downloaded {len(self.downloader.system_logs)} system log files and {len(self.downloader.performance_data)} performance data files")

        # Step 2: Parse data
        print("🔍 Parsing log data...")
        parsed_data = self.downloader.system_logs
        performance_data = self.downloader.performance_data

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
                "log_files_processed": len(self.downloader.system_logs) + len(self.downloader.performance_data),
            },
            "statistics": stats,
            "patterns": patterns,
            "insights": insights,
            "charts": charts,
        }

        print("🎉 Analysis completed successfully!")
        return results

    def download_data(self, days_back: int = 7) -> None:
        """Download data from Azure Storage for the specified number of days"""
        print(f"📥 Downloading data for the last {days_back} days...")
        self.downloader.download_data(days_back)

    def generate_report(
        self, days_back: int = 7, include_summary: bool = True
    ) -> Dict[str, Any]:
        """Generate analysis report"""
        print("📊 Generating analysis report...")

        # First download data if needed
        self.download_data(days_back)

        # Get analyzed data
        if hasattr(self.downloader, "system_logs") and hasattr(
            self.downloader, "performance_data"
        ):
            system_logs = self.downloader.system_logs
            performance_data = self.downloader.performance_data
        else:
            system_logs = []
            performance_data = []

        # Analyze the data
        if performance_data:
            stats = self.analyzer.calculate_statistics(performance_data)
            patterns = self.analyzer.identify_patterns(performance_data)
            insights = self.analyzer.generate_insights(performance_data)
        else:
            stats = {}
            patterns = []
            insights = []

        report = {
            "analysis_period": {
                "days_analyzed": days_back,
                "total_system_logs": len(system_logs),
                "total_performance_data": len(performance_data),
            },
            "statistics": stats,
            "patterns": patterns,
            "insights": insights,
            "generated_at": datetime.now().isoformat(),
        }

        return report

    def create_visualizations(self, output_dir: str = "./charts") -> None:
        """Create visualization charts"""
        print(f"📈 Creating visualizations in {output_dir}...")

        # Get performance data
        if hasattr(self.downloader, "performance_data"):
            performance_data = self.downloader.performance_data
        else:
            print("⚠️ No performance data available for visualizations")
            return

        if not performance_data:
            print("⚠️ No performance data to visualize")
            return

        # Create various charts
        self.visualizer.create_latency_chart(performance_data, output_dir)
        self.visualizer.create_throughput_chart(performance_data, output_dir)
        self.visualizer.create_packet_loss_chart(performance_data, output_dir)

        print(f"✅ Visualizations saved to {output_dir}")

    def print_summary(self, results: Dict[str, Any]) -> None:
        """Print a summary of analysis results"""
        print("\n" + "=" * 60)
        print("📊 NETWORK ANALYSIS SUMMARY")
        print("=" * 60)

        if "analysis_period" in results:
            period = results["analysis_period"]
            print(f"📅 Analysis Period: {period.get('days_analyzed', 'Unknown')} days")
            print(f"📝 System Logs: {period.get('total_system_logs', 0):,}")
            print(
                f"📈 Performance Data Points: {period.get('total_performance_data', 0):,}"
            )

        if "statistics" in results and results["statistics"]:
            print(f"\n📊 Performance Statistics:")
            stats = results["statistics"]
            if "latency" in stats:
                lat = stats["latency"]
                print(
                    f"   • Latency: avg={lat.get('mean', 0):.1f}ms, "
                    f"min={lat.get('min', 0):.1f}ms, max={lat.get('max', 0):.1f}ms"
                )
            if "throughput" in stats:
                tput = stats["throughput"]
                print(f"   • Throughput: avg={tput.get('mean', 0):.1f} Mbps")

        if "insights" in results and results["insights"]:
            print(f"\n🔍 Key Insights ({len(results['insights'])} found):")
            for i, insight in enumerate(results["insights"][:3], 1):  # Show top 3
                print(f"   {i}. {insight}")

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
