
# Advanced Starlink Failover & Monitoring for RUTOS/OpenWrt

This repository contains a collection of scripts designed to create a highly robust, proactive, and intelligent multi-WAN failover system on a Teltonika RUTOS or other OpenWrt-based router. It uses the Starlink gRPC API to make real-time decisions about connection quality, providing a much more seamless experience than standard ping-based checks alone.

Standard failover systems typically rely on simple ping tests to determine if a connection is "down." This approach is inadequate for satellite internet like Starlink, which can suffer from unique issues such as temporary obstructions, micro-outages, or periods of high latency even while the basic connection remains active. This project transforms a simple reactive system into a proactive one that can anticipate problems and gracefully switch to a backup connection before the user's experience is significantly impacted.

## Features

This solution offers a suite of advanced features to create a truly resilient mobile internet setup.

* **Proactive Quality Monitoring:** Instead of waiting for a total failure, the system actively queries Starlink's internal API for key performance indicators:
    * **Latency:** Detects when the connection becomes congested or unresponsive, which is a primary indicator of a poor user experience for real-time applications like video calls.
    * **Packet Loss:** Monitors the rate of data packets that fail to reach the Starlink ground station, providing a direct measure of connection instability.
    * **Obstruction:** Uses the real-time sky obstruction data to preemptively fail over if a physical blockage is likely to cause intermittent signal loss.

* **"Soft" Failover:** This is a key feature for maintaining a seamless user experience. Instead of a "hard" failover (`ifdown`), which terminates all active connections, this system intelligently changes the routing metrics (`uci set mwan3...`). This makes the Starlink connection less desirable than the cellular backup, causing the router to send all *new* traffic to the backup link. Crucially, long-lived connections like VPNs, SSH sessions, large file downloads, or remote work sessions are not immediately killed, preventing disruptive interruptions.

* **Intelligent Notifications:** A centralized notifier script sends detailed Pushover alerts for different failure scenarios. This provides valuable context, allowing you to distinguish between a "soft" quality-based failover (e.g., `Reason: [High Latency]`) and a "hard" physical link failure (e.g., `Link is down`). This insight helps in diagnosing connection issues remotely.

* **Stability-Aware Failback:** A common problem with automated failover is "flapping," where the system rapidly switches back and forth between connections. This script solves that by implementing a stability timer. It requires the Starlink connection to demonstrate consistently good quality for a configurable period (e.g., 5 minutes) before it will automatically fail back, ensuring the primary connection is genuinely reliable.

* **Data Logging & Analysis:** A dedicated logger script captures Starlink's performance metrics (latency, packet loss, obstruction) over time and saves them to a standard CSV file. This data can be easily imported into Excel or other tools to analyze trends, identify recurring issues (like obstructions at certain times of day), and make data-driven decisions to fine-tune the failover thresholds for your specific environment.

* **API Change Detection:** The Starlink gRPC API is unofficial and can change with firmware updates. This solution includes a utility script that runs once a day to check if the API version has changed. If it has, it sends a notification, alerting you that the monitoring scripts may need updates, thus preventing silent failures.

## Prerequisites

Before setting up these scripts, ensure your router meets the following requirements:

1.  **Hardware:** A Teltonika RUTX50 or a similar OpenWrt-based router with sufficient processing power and an **ARMv7** architecture. While developed on a RUTX50, the principles are adaptable.

2.  **Starlink:** A Starlink dish running in **Bypass Mode**. This is essential as it allows the router to receive the WAN IP address directly from Starlink and manage the connection.

3.  **Packages & Binaries:** You will need to install several command-line tools on the router via SSH, as they are not included in the default RUTOS firmware.

    ```sh
    # 1. Install grpcurl (32-bit ARMv7 version for RUTX50)
    curl -fL https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz -o /tmp/grpcurl.tar.gz
    tar -zxvf /tmp/grpcurl.tar.gz -C /root/ grpcurl
    chmod +x /root/grpcurl
    rm /tmp/grpcurl.tar.gz

    # 2. Install jq (32-bit ARMv7/armhf version for RUTX50)
    curl -fL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf -o /root/jq
    chmod +x /root/jq

    # 3. The scripts use 'awk' and 'logger', which are included in the default BusyBox suite on RUTOS.
    ```

## Core Components (The Scripts)

This solution follows a "Brain" and "Messenger" architecture for a clean separation of concerns.

* `starlink_monitor.sh`: **The Brain.** This is the main logic engine.
* `99-pushover_notify`: **The Messenger.** Sends Pushover alerts.
* `starlink_logger.sh`: Captures metrics to CSV.
* `check_starlink_api.sh`: Checks if the Starlink API has changed.
* `generate_api_docs.sh`: Dumps current API response.

## Configuration

Proper configuration of the router's networking is critical for this system to work. These settings are applied via the `uci` utility.

### 1. mwan3 Configuration

```sh
# Set priority metrics
uci set mwan3.member1.metric='1'
uci set mwan3.member3.metric='2'
uci set mwan3.member4.metric='4'
```

Configure tracking for interfaces similarly, commit and restart the service afterward.

### 2. Static Route

```sh
uci add network route
uci set network.@route[-1].interface='wan'
uci set network.@route[-1].target='192.168.100.0/24'
uci commit network
/etc/init.d/network restart
```

### 3. SSH & WebUI Timeouts

```sh
uci set dropbear.@dropbear[0].IdleTimeout='0'
uci commit dropbear
/etc/init.d/dropbear restart

uci set uhttpd.main.session_timeout='31536000'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

## Installation & Setup

1. Install tools
2. Place scripts
3. Make scripts executable
4. Set up cron jobs:
    ```cron
    * * * * * /root/starlink_monitor.sh
    * * * * * /root/starlink_logger.sh
    30 3 * * * /root/check_starlink_api.sh
    ```

## Usage & Testing

Use `logread | grep StarlinkMonitor` to verify, and simulate events manually for testing failover behaviors.

