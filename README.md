# Introduction
This project provides a reliable internet failover for Starlink using Teltonika RUTOS, and a redundant GPS feed for Victron systems. It’s intended for tech-savvy RV and boat owners who want uninterrupted connectivity and accurate solar forecasting. 

# Advanced RUTOS, Starlink, and Victron Integration for Mobile Setups
This repository contains a collection of projects designed to create a highly integrated and resilient connectivity and power management system for mobile environments like RVs (motorhomes) and boats. These solutions leverage the power of Teltonika's RUTOS, Starlink, and Victron's Venus OS to solve common challenges faced by mobile users.

Projects in this Repository
## 1. [Proactive Starlink & Cellular Failover for RUTOS](Starlink-RUTOS-Failover/README.md)
Directory: `Starlink-RUTOS-Failover` 

This project provides a suite of scripts to create a truly intelligent multi-WAN failover system on a Teltonika RUTOS device. Instead of relying on simple ping tests, this solution uses Starlink's internal gRPC API to monitor real-time quality metrics like latency, packet loss, and physical obstruction.

### Key Features:
Proactive Failover: Detects degrading connection quality before a full outage occurs.
"Soft" Failover Logic: Avoids dropping existing connections (like VPNs or video calls) by adjusting routing metrics rather than taking an interface completely offline.
Intelligent Notifications: Sends detailed Pushover alerts that distinguish between different types of failures (e.g., quality-based vs. link loss).
Stability-Aware Recovery: Prevents a "flapping" connection by waiting for a configurable period of stability before failing back to Starlink.

## 2. [Redundant GPS for Victron Cerbo GX/CX](VenusOS-GPS-RUTOS/README.md)
Directory: `VenusOS-GPS-RUTOS`

This project features a Node-RED flow designed to run on a Victron Cerbo GX/CX, ensuring your system always has an accurate GPS location for features like Solar Forecasting. It intelligently polls for GPS data from both a Teltonika RUTOS router (Primary) and a Starlink dish (Secondary), selecting the best source to publish to the Victron D-Bus.

This is essential for any mobile Victron installation, guaranteeing that your solar production forecasts are always based on your current location. The flow also includes a feature to automatically reset the Starlink obstruction map if it detects the vehicle has moved more than 500 meters, optimizing performance at each new location.

## Quick Start
**Starlink Failover (Teltonika RUTOS):**  
1. **Prerequisites:** Teltonika RUTX50 (or similar) with RUTOS, Starlink dish in Bypass Mode, and internet failover configured (mwan3). Install `grpcurl` and `jq` on the router:contentReference[oaicite:6]{index=6}.  
2. **Deploy Scripts:** Copy the failover scripts (`starlink_monitor.sh`, `starlink_logger.sh`, etc.) to the router’s `/root/` directory, and place the `99-pushover_notify` script in `/etc/hotplug.d/iface/`:contentReference[oaicite:7]{index=7}. Make them executable with `chmod +x`.  
3. **Configure Router:** Apply the provided `uci` settings for multi-WAN failover and add a static route to Starlink’s management IP:contentReference[oaicite:8]{index=8}:contentReference[oaicite:9]{index=9}. Insert your Pushover API keys into the `99-pushover_notify` script.  
4. **Schedule Cron Jobs:** Set up cron entries (via `crontab -e`) to run the monitor and logger every minute, and the API-check daily:contentReference[oaicite:10]{index=10}.  
5. **Test:** Reboot or run the scripts manually. Use `logread | grep StarlinkMonitor` to verify it's working:contentReference[oaicite:11]{index=11}. You should receive Pushover alerts on failover events.

**Victron GPS (Node-RED on Cerbo GX/CX):**  
1. **Prerequisites:** Victron Cerbo GX running **Venus OS Large** (for Node-RED) and a Teltonika RUT router with GPS enabled. Ensure the Cerbo is network-connected to the router and Starlink (Starlink must be in Bypass Mode with a static route set on the router to `192.168.100.1`):contentReference[oaicite:12]{index=12}:contentReference[oaicite:13]{index=13}.  
2. **Install Tools:** On the Cerbo, enable the local MQTT service (in Settings → Services):contentReference[oaicite:14]{index=14} and install `grpcurl` on the Cerbo (as shown in the docs):contentReference[oaicite:15]{index=15}.  
3. **Import Node-RED Flow:** Copy the contents of `venusos-gps-rutos/victron-gps-flow.json` and import it into Node-RED on the Cerbo GX (Node-RED UI → Import → paste JSON):contentReference[oaicite:16]{index=16}.  
4. **Configure Credentials:** In the Node-RED flow, open the “Trigger Branches” function and insert your router’s *API URL* (if different) and credentials (username/password) for the RUTOS API:contentReference[oaicite:17]{index=17}. Ensure the HTTP request nodes point to the correct IPs for the router (default `192.168.80.1`) and Starlink (`192.168.100.1:9200`):contentReference[oaicite:18]{index=18}.  
5. **Deploy and Verify:** Click **Deploy** in Node-RED. The flow will run every 30 minutes. Check the Node-RED debug console for messages showing GPS data retrieved and published. On the Victron VRM portal, confirm that the location is updating with the combined GPS feed.



# Disclaimer
These projects were developed and tested on my personal setup, which includes a Teltonika RUTX50 and a Victron Cerbo GX. I have made every effort to provide comprehensive documentation and include all necessary prerequisites.

While these scripts work reliably on my system, they are provided as-is. I do not have a formal development or testing environment, so I cannot guarantee they are entirely bug-free or that the documentation covers every possible scenario. Please use these scripts at your own discretion and be prepared to adapt them to your specific hardware and software versions. 
