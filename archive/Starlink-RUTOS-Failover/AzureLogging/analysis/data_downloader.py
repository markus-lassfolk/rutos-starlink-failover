#!/usr/bin/env python3
"""
Data Downloader Module
======================

Handles downloading data from Azure Storage containers.
"""

import logging
from datetime import datetime, timedelta
from typing import Optional
import re

from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)


class DataDownloader:
    """
    Downloads system logs and performance data from Azure Storage
    """

    def __init__(self, storage_account: str, credential=None):
        """
        Initialize the downloader with Azure Storage credentials

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
                return None
        return None

    def _parse_system_logs(self, content: str, log_date: datetime.date) -> None:
        """
        Parse system log content and extract relevant events
        """
        # This will be moved to LogParser module
        pass

    def _parse_performance_data(self, content: str, log_date: datetime.date) -> None:
        """
        Parse performance CSV data
        """
        # This will be moved to LogParser module
        pass
