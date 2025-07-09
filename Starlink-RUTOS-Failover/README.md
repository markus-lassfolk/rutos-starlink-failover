Advanced Starlink Failover & Monitoring for RUTOS/OpenWrt
This repository contains a collection of scripts designed to create a highly robust, proactive, and intelligent multi-WAN failover system on a Teltonika RUTOS or other OpenWrt-based router. It uses the Starlink gRPC API to make real-time decisions about connection quality, providing a much more seamless experience than standard ping-based checks alone.

Features
Proactive Quality Monitoring: Uses Starlink's internal API to monitor real-time Latency, Packet Loss, and Obstruction data.

"Soft" Failover: Instead of dropping all connections, the system intelligently changes the routing metrics (uci set mwan3...) to reroute traffic without interrupting existing sessions like VPNs or SSH.

Intelligent Notifications: A centralized notifier script sends detailed Pushover alerts for different failure scenarios (e.g., "Quality Failover due to High Latency" vs. "Hard Failover due to Link Loss").

Stability-Aware Failback: Prevents a "flapping" connection by requiring Starlink to be stable for a configurable period before failing back.

Data Logging & Analysis: Includes a script to log Starlink's performance over time to a CSV file, perfect for analysis in Excel to fine-tune thresholds.

API Change Detection: A daily script monitors for changes in the Starlink API version and sends an alert, ensuring the scripts don't break silently after a firmware update.

Prerequisites
Before setting up these scripts, ensure your router meets the following requirements:

Hardware: A Teltonika RUTX50 or similar OpenWrt-based router with an ARMv7 architecture.

Starlink: A Starlink dish running in Bypass Mode.

Packages & Binaries: You will need to install several tools on the router via SSH.

# 1. Install grpcurl (32-bit ARMv7 version for RUTX50)
# This is the correct binary for the RUTX50's armv7l architecture.
curl -fL https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz -o /tmp/grpcurl.tar.gz
tar -zxvf /tmp/grpcurl.tar.gz -C /root/ grpcurl
chmod +x /root/grpcurl
rm /tmp/grpcurl.tar.gz

# 2. Install jq (32-bit ARMv7/armhf version for RUTX50)
# The 'armhf' version is correct for this hardware.
curl -fL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf -o /root/jq
chmod +x /root/jq

# 3. The scripts use 'awk' and 'logger', which are included in BusyBox by default.

Core Components (The Scripts)
This solution is comprised of several scripts that work together.

starlink_monitor.sh: The Brain. Runs every minute via cron to check Starlink quality, performs the soft failover by changing mwan3 metrics, and calls the notifier script.

99-pushover_notify: The Messenger. A centralized script that sends Pushover notifications. It's triggered by the monitor script for soft failovers and by the system's hotplug events for hard failovers.

starlink_logger.sh: A data logger that runs every minute to capture performance metrics to a CSV file.

check_starlink_api.sh: A utility script that runs once a day to alert you if the Starlink API version changes.

generate_api_docs.sh: A utility script to generate a full dump of the Starlink API data for future reference.

Configuration
Proper configuration of the router's networking is critical for this system to work.

1. mwan3 Configuration
The following uci commands will configure mwan3 for a responsive failover. This assumes your Starlink is wan (member1), your primary SIM is mob1s1a1 (member3), and your roaming SIM is mob1s2a1 (member4).

Set Member Metrics
# Set member metrics (lower is higher priority)
uci set mwan3.member1.metric='1'
uci set mwan3.member3.metric='2'
uci set mwan3.member4.metric='4'

Configure Starlink (WAN) Health Checks
These settings are for the standard mwan3 ping check, which acts as a backup to our proactive script.

# Configure Starlink (wan) tracking for aggressive but stable recovery
uci set mwan3.@condition[1].interface='wan'
uci set mwan3.@condition[1].down='2'
uci set mwan3.@condition[1].up='3'
uci set mwan3.wan.recovery_wait='10' # Wait 10s after recovery before use

Configure Mobile Interface Health Checks (Crucial)
This ensures your mobile connections are also checked for internet connectivity, not just a modem signal.

# Configure Primary SIM (mob1s1a1)
uci set mwan3.@condition[0].interface='mob1s1a1'
uci set mwan3.@condition[0].track_method='ping'
uci set mwan3.@condition[0].track_ip='1.1.1.1' '8.8.8.8'
uci set mwan3.@condition[0].reliability='1'
uci set mwan3.@condition[0].count='2'
uci set mwan3.@condition[0].down='4'
uci set mwan3.@condition[0].up='4'

# Configure Roaming SIM (mob1s2a1)
uci set mwan3.@condition[2].interface='mob1s2a1'
uci set mwan3.@condition[2].track_method='ping'
uci set mwan3.@condition[2].track_ip='1.1.1.1' '8.8.4.4'
uci set mwan3.@condition[2].reliability='1'
uci set mwan3.@condition[2].count='2'
uci set mwan3.@condition[2].down='3'
uci set mwan3.@condition[2].up='3'
uci set mwan3.@condition[2].interval='10' # Check less frequently

Commit and Restart
# Apply all mwan3 changes and restart the service
uci commit mwan3
mwan3 restart

2. Static Route for Starlink
You must add a static route so the router can access the dish's API at 192.168.100.1.

uci add network route
uci set network.@route[-1].interface='wan'
uci set network.@route[-1].target='192.168.100.0/24'
uci commit network
/etc/init.d/network restart

3. SSH & WebUI Timeouts (Optional)
To prevent sessions from timing out during configuration:

# SSH Timeout (infinite)
uci set dropbear.@dropbear[0].IdleTimeout='0'
uci commit dropbear
/etc/init.d/dropbear restart

# WebUI Timeout (1 year)
uci set uhttpd.main.session_timeout='31536000'
uci commit uhttpd
/etc/init.d/uhttpd restart

4. Script Configuration
All scripts have a Configuration section at the top. You must edit the 99-pushover_notify script to set your Pushover credentials. You can also tune all thresholds in the monitor script.

Installation & Setup
Install Prerequisites: Run the commands in the Prerequisites section above.

Place Scripts:

Place starlink_monitor.sh, starlink_logger.sh, check_starlink_api.sh, and generate_api_docs.sh in the /root/ directory.

Place 99-pushover_notify in the /etc/hotplug.d/iface/ directory.

Make Executable: Run chmod +x on all scripts.

chmod +x /root/starlink_monitor.sh
chmod +x /etc/hotplug.d/iface/99-pushover_notify
# ... and so on for the other scripts

Apply UCI Changes: Run the commands in the Configuration section above.

Set up Cron Jobs: Run crontab -e and add the following lines:

# Run the main quality monitor every minute
* * * * * /root/starlink_monitor.sh

# Run the performance logger every minute
* * * * * /root/starlink_logger.sh

# Check for an API version change once a day at 3:30 AM
30 3 * * * /root/check_starlink_api.sh

Usage & Testing
You can test the different parts of the system manually:

Test Soft Failover: Temporarily set a very low threshold in starlink_monitor.sh (e.g., LATENCY_THRESHOLD_MS=1) and run it manually: /root/starlink_monitor.sh.

Test Hard Failover: Manually trigger the hotplug script by setting environment variables: ACTION=ifdown INTERFACE=wan /etc/hotplug.d/iface/99-pushover_notify.
