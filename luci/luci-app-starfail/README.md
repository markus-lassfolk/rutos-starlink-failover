# LuCI App for Starfail Multi-Interface Failover

This is the LuCI web interface for the Starfail multi-interface failover daemon. It provides a comprehensive web-based management interface for monitoring and configuring the Starfail system.

## Features

### Overview Page
- Real-time system status display
- Daemon control (start/stop/restart/reload)
- Current member status
- Quick statistics

### Configuration Page
- Complete UCI configuration interface
- Main settings (intervals, thresholds, etc.)
- Monitoring settings (metrics, health endpoints)
- MQTT configuration
- Notification settings

### Members Page
- Real-time member interface status
- Health scores and metrics
- Detailed member information
- Interface selection and details

### Telemetry Page
- Telemetry data overview
- Recent samples and events
- Health summary for all members
- Performance analytics

### Logs Page
- Real-time log viewing
- Log level filtering
- Log statistics
- Download and management tools

## Installation

### Prerequisites
- OpenWrt/LEDE system with LuCI
- Starfail daemon (`starfaild`) installed
- `luci-compat` package installed

### Building from Source
```bash
# Clone the repository
git clone <repository-url>
cd luci-app-starfail

# Build the package
make package/luci-app-starfail/compile V=s
```

### Installation on Target Device
```bash
# Install the package
opkg install luci-app-starfail_*.ipk

# Restart LuCI
/etc/init.d/uhttpd restart
```

## Configuration

### UCI Configuration
The application uses the standard UCI configuration system. The main configuration is stored in `/etc/config/starfail`.

Key configuration options:
- `enable`: Enable/disable the Starfail daemon
- `use_mwan3`: Enable mwan3 integration
- `poll_interval_ms`: Polling interval for metrics
- `decision_interval_ms`: Decision engine interval
- `metrics_listener`: Enable Prometheus metrics
- `health_listener`: Enable health check endpoints
- `mqtt_enabled`: Enable MQTT telemetry publishing

### Web Interface Access
After installation, the Starfail interface will be available at:
- **URL**: `http://<router-ip>/cgi-bin/luci/admin/network/starfail`
- **Menu**: Network → Starfail Failover

## API Integration

The LuCI application integrates with the Starfail daemon through:
- **ubus**: For real-time status and control
- **UCI**: For configuration management
- **HTTP**: For metrics and health endpoints

### ubus Methods Used
- `starfail status`: Get system status
- `starfail members`: Get member information
- `starfail telemetry`: Get telemetry data
- `starfail reload`: Reload configuration
- `starfail action`: Execute control actions

## Development

### File Structure
```
luci-app-starfail/
├── Makefile                    # Package build configuration
├── root/                       # Files to install on target
│   ├── etc/config/starfail     # Default UCI configuration
│   ├── etc/init.d/starfail     # Init script
│   ├── etc/hotplug.d/iface/    # Interface hotplug handler
│   └── usr/lib/lua/luci/       # LuCI application files
│       ├── controller/         # URL routing and AJAX handlers
│       ├── model/cbi/          # UCI configuration models
│       └── view/               # HTML templates
└── README.md                   # This file
```

### Adding New Features
1. **Controller**: Add new routes in `controller/starfail.lua`
2. **Model**: Add configuration options in `model/cbi/starfail/config.lua`
3. **View**: Create new templates in `view/starfail/`
4. **Configuration**: Update UCI schema and defaults

### Testing
```bash
# Test the package build
make package/luci-app-starfail/compile V=s

# Test on target device
opkg install --force-reinstall luci-app-starfail_*.ipk
```

## Troubleshooting

### Common Issues

1. **Interface not appearing in LuCI menu**
   - Ensure `luci-compat` is installed
   - Check that the controller file is properly installed
   - Restart uhttpd service

2. **AJAX calls failing**
   - Verify ubus is working: `ubus list | grep starfail`
   - Check daemon is running: `ps aux | grep starfaild`
   - Review browser console for JavaScript errors

3. **Configuration not saving**
   - Check UCI permissions
   - Verify configuration file syntax
   - Review system logs for errors

### Debug Mode
Enable debug logging in the LuCI interface:
1. Go to Configuration page
2. Set Log Level to "Debug"
3. Save and apply configuration
4. Check logs in the Logs page

### Log Files
- **System logs**: `logread | grep starfail`
- **LuCI logs**: `/var/log/uhttpd.log`
- **Daemon logs**: Check the Logs page in the interface

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the GPL-3.0-or-later License.

## Support

For support and questions:
- Check the main Starfail documentation
- Review the troubleshooting section
- Open an issue on the project repository
