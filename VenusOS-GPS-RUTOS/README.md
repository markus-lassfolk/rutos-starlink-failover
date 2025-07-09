# Victron GPS Failover with Node-RED, RUTOS, and Starlink

This project provides a robust solution for ensuring a Victron Cerbo GX (or Cerbo CX) has a consistent and accurate GPS location, which is critical for features like Solar Forecast. It uses Node-RED running on the Cerbo to pull GPS data from two independent sources—a Teltonika RUTX50 router and a Starlink dish—and intelligently selects the best source to publish to the Victron system.

## The Goal

The Victron system's solar forecast relies on knowing the vessel or vehicle's precise location. While the Cerbo can have its own GPS, this project creates a redundant system for mobile setups (RVs, boats) where multiple GPS sources are often available. By using the high-quality GPS from a cellular router (RUTX50) as the primary source and the Starlink dish's GPS as a reliable backup, we ensure the system never loses its location, even if one device is offline.

## How It Works

The entire logic is contained within a single Node-RED flow running on the Cerbo GX.

- **Trigger:** Every 30 minutes, the flow is triggered to begin the data gathering process.
- **Data Fetching:** It makes two simultaneous API calls to poll for location data:
  - One to the Teltonika RUTX50 API to get its GPS data (latitude, longitude, altitude, accuracy, etc.).
  - One to the Starlink gRPC API to get its diagnostic data, which includes GPS location.
- **Quality Check & Selection:** A central function node analyzes the data from both sources. It prioritizes the RUTOS GPS due to its typically higher accuracy but will seamlessly fail over to the Starlink GPS if the RUTOS signal is poor or unavailable. The selection is based on GPS fix status and horizontal accuracy (hAcc).
- **Format & Publish:** The data from the selected source is formatted into the specific JSON structure required by the Victron D-Bus service.
- **MQTT Injection:** The formatted GPS data is published to the Cerbo's local MQTT broker. The Victron system listens to these specific MQTT topics and updates the system's official location accordingly.
- **Movement Detection & Obstruction Map Reset:** The flow includes a powerful secondary function: it calculates the distance moved since the last successful GPS update. If the vehicle has moved more than 500 meters, it automatically triggers a command to reset the Starlink dish's obstruction map. This is crucial for mobile users, as it ensures Starlink immediately begins scanning for a clear view of the sky at each new location, optimizing performance.

## Prerequisites

### 1. Hardware

- A Victron Cerbo GX or Cerbo CX.
- A Teltonika RUTX50 router (or another RUTOS device with an active GPS and accessible API).
- A Starlink dish running in Bypass Mode.

### 2. Victron Cerbo GX / Venus OS

- You must be running a **Venus OS Large** image.
- Enable MQTT on LAN (SSL and plain text) in `Settings -> Services`.

### 3. Node-RED

No special community nodes are required. The flow uses default nodes (http request, exec, mqtt, function, etc.).

Install `grpcurl` via SSH:

```sh
curl -fL https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_armv7.tar.gz -o /tmp/grpcurl.tar.gz
tar -zxvf /tmp/grpcurl.tar.gz -C /usr/local/bin/ grpcurl
chmod +x /usr/local/bin/grpcurl
rm /tmp/grpcurl.tar.gz
```

### 4. Teltonika RUTX50 Router

- The API must be accessible from the Cerbo GX.
- Enable GPS on the router via WebUI or SSH:

```sh
uci set gps.gpsd.enabled='1'
uci commit gps
/etc/init.d/gpsd restart
```

### 5. Starlink Dish

- Must be in Bypass Mode.
- Ensure the RUTX50 has a static route to `192.168.100.1` for API access.

## Installation and Configuration

### 1. Copy the Flow

Open `victron-gps-flow.json` and copy all content to your clipboard.

### 2. Import into Node-RED

1. Navigate to Node-RED: `http://<cerbo-ip-address>:1880`
2. Click ☰ → Import
3. Paste the JSON code and click **Import**

### 3. Configure Credentials

1. Open the `Trigger Branches` function node.
2. Replace:

```js
return [{payload:"go"},{payload:{username:"YOUR_RUTOS_USERNAME",password:"YOUR_RUTOS_PASSWORD"}}];
```

with your actual RUTOS login credentials.

### 4. Verify IP Addresses

- Ensure `RUTOS login` and `Get RUTOS GPS` nodes point to the correct router IP (default: `192.168.80.1`).
- Check `Get Starlink GPS` uses `192.168.100.1:9200`.

### 5. Deploy the Flow

Click **Deploy** in Node-RED. The flow will run immediately and then every 30 minutes.

Use the Debug sidebar to confirm GPS fetching, source selection, and MQTT updates.

---

Enjoy a rock-solid GPS system that ensures Victron accuracy even in mobile, roaming environments.