# Introduction
This project provides a reliable internet failover for Starlink using Teltonika RUTOS, and a redundant GPS feed for Victron systems. It’s intended for tech-savvy RV and boat owners who want uninterrupted connectivity and accurate solar forecasting. 

# Advanced RUTOS, Starlink, and Victron Integration for Mobile Setups
This repository contains a collection of projects designed to create a highly integrated and resilient connectivity and power management system for mobile environments like RVs (motorhomes) and boats. These solutions leverage the power of Teltonika's RUTOS, Starlink, and Victron's Venus OS to solve common challenges faced by mobile users.

Projects in this Repository
## 1. Proactive Starlink & Cellular Failover for RUTOS
Directory: `Starlink-RUTOS-Failover`

This project provides a suite of scripts to create a truly intelligent multi-WAN failover system on a Teltonika RUTOS device. Instead of relying on simple ping tests, this solution uses Starlink's internal gRPC API to monitor real-time quality metrics like latency, packet loss, and physical obstruction.

### Key Features:
Proactive Failover: Detects degrading connection quality before a full outage occurs.
"Soft" Failover Logic: Avoids dropping existing connections (like VPNs or video calls) by adjusting routing metrics rather than taking an interface completely offline.
Intelligent Notifications: Sends detailed Pushover alerts that distinguish between different types of failures (e.g., quality-based vs. link loss).
Stability-Aware Recovery: Prevents a "flapping" connection by waiting for a configurable period of stability before failing back to Starlink.

## 2. Redundant GPS for Victron Cerbo GX/CX
Directory: `VenusOS-GPS-RUTOS`

This project features a Node-RED flow designed to run on a Victron Cerbo GX/CX, ensuring your system always has an accurate GPS location for features like Solar Forecasting. It intelligently polls for GPS data from both a Teltonika RUTOS router (Primary) and a Starlink dish (Secondary), selecting the best source to publish to the Victron D-Bus.

This is essential for any mobile Victron installation, guaranteeing that your solar production forecasts are always based on your current location. The flow also includes a feature to automatically reset the Starlink obstruction map if it detects the vehicle has moved more than 500 meters, optimizing performance at each new location.

# Disclaimer
These projects were developed and tested on my personal setup, which includes a Teltonika RUTX50 and a Victron Cerbo GX. I have made every effort to provide comprehensive documentation and include all necessary prerequisites.

While these scripts work reliably on my system, they are provided as-is. I do not have a formal development or testing environment, so I cannot guarantee they are entirely bug-free or that the documentation covers every possible scenario. Please use these scripts at your own discretion and be prepared to adapt them to your specific hardware and software versions. 
