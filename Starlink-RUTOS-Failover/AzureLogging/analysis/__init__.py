# Network Performance Analysis Package
"""
Modular network performance analysis package for RUTOS Starlink systems.

This package provides:
- Data downloading from Azure Storage
- Log parsing and processing
- Performance metrics analysis
- Visualization generation
- Report creation
"""

__version__ = "1.0.0"
__author__ = "RUTOS Starlink Project"

# Import main classes for easy access
from .data_downloader import DataDownloader
from .log_parser import LogParser
from .performance_analyzer import PerformanceAnalyzer
from .visualizer import Visualizer
from .network_analyzer import NetworkAnalyzer

__all__ = [
    "DataDownloader",
    "LogParser",
    "PerformanceAnalyzer",
    "Visualizer",
    "NetworkAnalyzer",
]
