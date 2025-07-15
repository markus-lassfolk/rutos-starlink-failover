#!/usr/bin/env python3
"""
Network Performance and Failover Analysis Tool (Refactored)
==========================================================

This is the new modular version of the network analysis tool.
The original analyze-network-performance.py has been split into modules for better maintainability.

Usage:
    python network-analyzer.py --storage-account myaccount --days 30 --visualizations
"""

import argparse
import logging
import sys
from pathlib import Path

# Add the analysis module to the path
sys.path.insert(0, str(Path(__file__).parent / "analysis"))

try:
    from analysis import NetworkAnalyzer
except ImportError as e:
    print(f"Missing analysis modules: {e}")
    print("Please ensure all analysis modules are present in the analysis/ directory")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def main():
    """
    Main function to run the network analysis
    """
    parser = argparse.ArgumentParser(
        description="Analyze network performance and failover patterns (Modular Version)"
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
        logger.info("Initializing Network Performance Analyzer (Modular Version)...")
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
        print("NETWORK ANALYSIS SUMMARY (Modular Version)")
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
