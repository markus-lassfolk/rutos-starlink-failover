#!/usr/bin/env python3
"""
Log Parser Module
================

Handles parsing of system logs and performance data.
"""

import logging
import csv
from datetime import datetime
from io import StringIO
from typing import Dict, List, Any
import re

logger = logging.getLogger(__name__)


class LogParser:
    """
    Parses various log formats and extracts structured data
    """

    def __init__(self):
        """Initialize the log parser"""
        self.system_logs = []
        self.performance_data = []

    def parse_system_logs(
        self, content: str, log_date: datetime.date
    ) -> List[Dict[str, Any]]:
        """
        Parse system log content and extract relevant events

        Args:
            content: Raw log file content
            log_date: Date of the log file

        Returns:
            List of parsed log entries
        """
        entries = []

        try:
            for line in content.split("\n"):
                if not line.strip():
                    continue

                entry = self._parse_log_line(line, log_date)
                if entry:
                    entries.append(entry)

        except Exception as e:
            logger.error(f"Error parsing system logs for {log_date}: {e}")

        return entries

    def parse_performance_data(
        self, content: str, log_date: datetime.date
    ) -> List[Dict[str, Any]]:
        """
        Parse performance CSV data

        Args:
            content: Raw CSV content
            log_date: Date of the data file

        Returns:
            List of parsed performance entries
        """
        entries = []

        try:
            csv_reader = csv.DictReader(StringIO(content))

            for row in csv_reader:
                entry = self._parse_csv_row(row, log_date)
                if entry:
                    entries.append(entry)

        except Exception as e:
            logger.error(f"Error parsing performance data for {log_date}: {e}")

        return entries

    def _parse_log_line(self, line: str, log_date: datetime.date) -> Dict[str, Any]:
        """
        Parse a single log line into structured data
        """
        # Syslog format: timestamp hostname process[pid]: message
        syslog_pattern = r"^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+([^:\[]+)(?:\[(\d+)\])?\s*:\s*(.*)$"

        match = re.match(syslog_pattern, line)
        if not match:
            return None

        timestamp_str, hostname, process, pid, message = match.groups()

        # Convert timestamp
        try:
            timestamp = datetime.strptime(
                f"{log_date.year} {timestamp_str}", "%Y %b %d %H:%M:%S"
            )
        except ValueError:
            timestamp = datetime.combine(log_date, datetime.min.time())

        return {
            "timestamp": timestamp,
            "hostname": hostname,
            "process": process,
            "pid": int(pid) if pid else None,
            "message": message.strip(),
            "log_level": self._extract_log_level(message),
            "event_type": self._classify_event(process, message),
        }

    def _parse_csv_row(
        self, row: Dict[str, str], log_date: datetime.date
    ) -> Dict[str, Any]:
        """
        Parse a CSV row into structured performance data
        """
        try:
            # Expected CSV columns: timestamp,ping_latency_ms,packet_loss_pct,downlink_throughput_bps,uplink_throughput_bps,speed_kmh,latitude,longitude
            return {
                "timestamp": datetime.fromisoformat(row.get("timestamp", "")),
                "ping_latency_ms": float(row.get("ping_latency_ms", 0)),
                "packet_loss_pct": float(row.get("packet_loss_pct", 0)),
                "downlink_throughput_bps": float(row.get("downlink_throughput_bps", 0)),
                "uplink_throughput_bps": float(row.get("uplink_throughput_bps", 0)),
                "speed_kmh": float(row.get("speed_kmh", 0)),
                "latitude": (
                    float(row.get("latitude", 0)) if row.get("latitude") else None
                ),
                "longitude": (
                    float(row.get("longitude", 0)) if row.get("longitude") else None
                ),
            }
        except (ValueError, TypeError) as e:
            logger.warning(f"Error parsing CSV row: {e}")
            return None

    def _extract_log_level(self, message: str) -> str:
        """Extract log level from message"""
        message_upper = message.upper()

        if any(level in message_upper for level in ["ERROR", "ERR"]):
            return "ERROR"
        elif any(level in message_upper for level in ["WARN", "WARNING"]):
            return "WARNING"
        elif any(level in message_upper for level in ["INFO", "INFORMATION"]):
            return "INFO"
        elif any(level in message_upper for level in ["DEBUG"]):
            return "DEBUG"
        else:
            return "UNKNOWN"

    def _classify_event(self, process: str, message: str) -> str:
        """Classify the type of event based on process and message"""
        message_lower = message.lower()
        process_lower = process.lower()

        # Failover events
        if any(
            keyword in message_lower
            for keyword in ["failover", "switching", "route change", "metric"]
        ):
            return "FAILOVER"

        # Reboot events
        if any(
            keyword in message_lower
            for keyword in ["reboot", "restart", "startup", "shutdown"]
        ):
            return "REBOOT"

        # Network events
        if any(
            keyword in message_lower
            for keyword in ["network", "interface", "connection", "link"]
        ):
            return "NETWORK"

        # GPS events
        if any(
            keyword in message_lower for keyword in ["gps", "location", "coordinate"]
        ):
            return "GPS"

        # Starlink specific
        if any(
            keyword in message_lower for keyword in ["starlink", "dishy", "satellite"]
        ):
            return "STARLINK"

        # System events
        if any(keyword in process_lower for keyword in ["kernel", "systemd", "cron"]):
            return "SYSTEM"

        return "OTHER"
