# Advanced Starlink Failover & Monitoring for RUTOS/OpenWrt

This directory contains a collection of scripts designed to create a highly robust, proactive, and intelligent multi-WAN failover system on a Teltonika RUTOS or other OpenWrt-based router. It uses the Starlink gRPC API to make real-time decisions about connection quality, providing a much more seamless experience than standard ping-based checks alone.

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

4.  **Pushover:** Register a free account at https://pushover.net/ and create an application so you get both a User and Application API-Key. Then install the Pushover application on your mobile device and login with your account.


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
The following uci commands will configure mwan3 for a responsive failover. This assumes your Starlink is wan (member1), your primary SIM is mob1s1a1 (member3), and your roaming SIM is mob1s2a1 (member4).

Set Member Metrics
The metric determines the priority of the interface (lower is better). This setup prioritizes Starlink, then the primary SIM, and finally the roaming SIM.

```sh
# Set member metrics (lower is higher priority)
uci set mwan3.member1.metric='1'
uci set mwan3.member3.metric='2'
uci set mwan3.member4.metric='4'
```

Configure tracking for interfaces similarly, commit and restart the service afterward.

### 2. Configure Starlink (WAN) Health Checks
These settings configure the traditional ping-based health check for Starlink, which serves as a vital backup to our proactive API monitoring script.

```sh
# Configure Starlink (wan) tracking for aggressive but stable recovery
uci set mwan3.@condition[1].interface='wan'
uci set mwan3.@condition[1].track_method='ping'
uci set mwan3.@condition[1].track_ip='1.0.0.1' '8.8.8.8'
uci set mwan3.@condition[1].reliability='1'
uci set mwan3.@condition[1].timeout='1'
uci set mwan3.@condition[1].interval='1'
uci set mwan3.@condition[1].count='1'
uci set mwan3.@condition[1].down='2' # Mark as down after 2 failed ping cycles
uci set mwan3.@condition[1].up='3'   # Mark as up after 3 successful ping cycles
uci set mwan3.wan.recovery_wait='10' # Wait 10s after recovery before use
```

### 3. Configure Mobile Interface Health Checks (Crucial)
This ensures your cellular connections are also checked for actual internet connectivity by pinging reliable external hosts, not just relying on the modem's signal status.

```sh
# Configure Primary SIM (mob1s1a1)
uci set mwan3.@condition[0].interface='mob1s1a1'
uci set mwan3.@condition[0].track_method='ping'
uci set mwan3.@condition[0].track_ip='1.1.1.1' '8.8.8.8'
uci set mwan3.@condition[0].reliability='1'
uci set mwan3.@condition[0].timeout='2'
uci set mwan3.@condition[0].interval='3'
uci set mwan3.@condition[0].count='2'
uci set mwan3.@condition[0].down='4'
uci set mwan3.@condition[0].up='4'

# Configure Roaming SIM (mob1s2a1)
uci add mwan3 condition
uci set mwan3.@condition[-1].interface='mob1s2a1'
uci set mwan3.@condition[-1].track_method='ping'
uci set mwan3.@condition[-1].track_ip='1.1.1.1' '8.8.4.4'
uci set mwan3.@condition[-1].reliability='1'
uci set mwan3.@condition[-1].count='2'
uci set mwan3.@condition[-1].timeout='3'
uci set mwan3.@condition[-1].interval='10' # Check less frequently
uci set mwan3.@condition[-1].down='3'
uci set mwan3.@condition[-1].up='3'
```

### 4. Commit and Restart
```sh
# Apply all mwan3 changes and restart the service
uci commit mwan3
mwan3 restart
```

### 5. Static Route for Starlink
This step is non-negotiable. You must add a static route to tell the router that the dish's management IP (192.168.100.1) is accessible through the wan interface. Without this, the monitoring scripts cannot communicate with the dish.
```sh
uci add network route
uci set network.@route[-1].interface='wan'
uci set network.@route[-1].target='192.168.100.0/24'
uci commit network
/etc/init.d/network restart
```

### 6. SSH & WebUI Timeouts (Optional)
For convenience during setup and monitoring, you can extend the default session timeouts. Be aware of the security implications of leaving sessions logged in indefinitely.
```sh
# SSH Timeout (infinite)
uci set dropbear.@dropbear[0].IdleTimeout='0'
uci commit dropbear
/etc/init.d/dropbear restart

# WebUI Timeout (1 year)
uci set uhttpd.main.session_timeout='31536000'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

### 7. Script Configuration (Important) 
All scripts have a Configuration section at the top. You must edit the `99-pushover_notify` script to set your Pushover API Token and User Key. It is highly recommended to start with the default thresholds in `starlink_monitor.sh` and use the data from `starlink_logger.sh` to fine-tune them over a few days of usage.


## Installation & Setup

1. Install Prerequisites: Run the commands in the Prerequisites section above to download and install `grpcurl` and `jq`. 
2. Place scripts
   Place `starlink_monitor.sh`, `starlink_logger.sh`, `check_starlink_api.sh`, and `generate_api_docs.sh` in the `/root/` directory.
   Place `99-pushover_notify` in the `/etc/hotplug.d/iface/` directory. This is the correct location for scripts that need to be triggered by interface events.
3. Make scripts executable
```sh
chmod +x /root/starlink_monitor.sh
chmod +x /etc/hotplug.d/iface/99-pushover_notify
chmod +x /root/starlink_logger.sh
chmod +x /root/check_starlink_api.sh
chmod +x /root/generate_api_docs.sh
```
4. Apply UCI Changes: Run the commands in the Configuration section above to set up mwan3 and the necessary static route.
5. Set up Cron Jobs: Run `crontab -e` to open the cron editor and add the following lines to schedule the scripts.
   ```cron
   # Run the main quality monitor every minute
   * * * * * /root/starlink_monitor.sh
   
   # Run the performance logger every minute (optional) 
   * * * * * /root/starlink_logger.sh   
   
   # Check for an API version change once a day at 5:30 AM  (optional) 
   30 5 * * * /root/check_starlink_api.sh  
   ```

## Usage & Testing

Use `logread | grep StarlinkMonitor` to verify, and simulate events manually for testing failover behaviors.

After setup, it's important to verify that the system is working as expected.
* Initial Verification: After one or two minutes, check the system log with `logread | grep StarlinkMonitor`. You should see entries from the monitor script confirming it is running and checking the connection quality.
* Test Soft Failover: To test the proactive monitoring, temporarily set a very low threshold in `starlink_monitor.sh` (e.g., LATENCY_THRESHOLD_MS=1). Run the script manually: `/root/starlink_monitor.sh`. You should see the script detect the "bad" quality, change the metric, and receive a "Quality Failover" notification from Pushover. Remember to change the threshold back afterwards. 
* Test Hard Failover: To test the failsafe notifier, manually trigger a hotplug event by setting the required environment variables from the command line. This simulates what the system does when mwan3's own ping checks fail.
```sh
ACTION=ifdown INTERFACE=wan /etc/hotplug.d/iface/99-pushover_notify
```
   This should trigger the "Starlink Offline (Hard)" notification.



