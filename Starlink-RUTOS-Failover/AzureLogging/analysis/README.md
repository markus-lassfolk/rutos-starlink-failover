# Analysis Module Structure

This directory contains the refactored network performance analysis modules.

## Architecture

```text
analysis/
├── __init__.py              # Package initialization
├── data_downloader.py       # Azure Storage data downloading
├── log_parser.py           # Log parsing and event extraction
├── performance_analyzer.py  # Performance metrics analysis
├── visualizer.py           # Chart and graph generation
└── network_analyzer.py     # Main orchestrator class
```text

## Usage

### New Modular Version (Recommended)

```bash
python network-analyzer.py --storage-account myaccount --days 30 --visualizations
```text

### Legacy Version (Deprecated)

```bash
python analyze-network-performance.py --storage-account myaccount --days 30
```text

## Benefits of Modular Structure

- **Maintainability**: Each module has a single responsibility
- **Testability**: Individual components can be unit tested
- **Readability**: Smaller, focused files are easier to understand
- **Extensibility**: New features can be added without modifying existing code
- **Reusability**: Modules can be imported and used independently

## Migration Guide

The new modular version provides the same functionality as the original script but with improved architecture. All
command-line arguments remain the same for backward compatibility.
