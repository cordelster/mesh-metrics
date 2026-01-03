# Meshtastic Metrics Daemon - Home Assistant Add-on

Monitor Meshtastic repeater telemetry and export metrics to Prometheus from Home Assistant.

## About

This add-on connects to a Meshtastic device (USB or network) and polls repeater nodes for telemetry data. Metrics are exported in Prometheus format for monitoring and visualization.

## Configuration

All configuration is done through the Home Assistant web interface. No need to edit files manually.

### Connection Settings

connection_mode (required)
- serial: Connect via USB
- ip: Connect via network

device_port (required)
- Serial mode: Device path like /dev/ttyACM0
- IP mode: IP address or hostname like 192.168.1.100

poll_interval (default: 300)
- Seconds between polling cycles (60-3600)

dwell_time (default: 10)
- Seconds between polling individual nodes (5-60)

### Output Settings

output_directory (default: /data)
- Where to write metrics files

output_format (default: node_exporter)
- Prometheus exposition format

individual_files (default: true)
- true: Separate file for each node
- false: Single file for all nodes

atomic_writes (default: true)
- Use atomic file writes for reliability

### Device List

devices_list (required)
- Enter your Meshtastic nodes directly in this text area
- Format: !NodeID,Contact,Location,Latitude,Longitude
- One node per line

Example:
```
!2f67c123,Repeater 1,Mountain Top,37.7749,-122.4194
!2c4354f4,Repeater 2,Valley Site,37.8044,-122.2712
```

### Prometheus Settings

prometheus_push_url (optional)
- URL to Prometheus push gateway
- Example: http://pushgateway:9091/metrics/job/meshtastic

prometheus_job_name (default: meshtastic_repeater_telemetry)
- Job identifier for Prometheus

prometheus_instance (optional)
- Instance identifier for Prometheus

prometheus_timeout (default: 30)
- Request timeout in seconds (5-120)

### Other Settings

log_level (default: INFO)
- DEBUG, INFO, WARNING, ERROR, CRITICAL

enable_stats (default: true)
- Collect daemon statistics to /data/stats.json

devices_encrypted (default: false)
- Enable if using encrypted device list

devices_password (optional)
- Password for encrypted device list

## USB Device Access

For serial mode:

1. Connect Meshtastic device via USB
2. In Home Assistant: Settings > Add-ons > Meshtastic Metrics Daemon
3. Ensure correct device is configured in options
4. Add-on automatically requests access to /dev/ttyACM0 and /dev/ttyUSB0

## Metrics Output

Metrics are written to /data directory:

Single file mode: /data/meshtastic.prom
Individual files: /data/meshtastic-[NodeID].prom

Configure Prometheus to scrape these files or use the push gateway option.

## Integration with Prometheus

Method 1: File-based
- Mount or access /data directory from Prometheus node_exporter

Method 2: Push Gateway
- Configure prometheus_push_url option
- Metrics pushed automatically after each poll

## Troubleshooting

USB device not found:
- Check device is connected to Home Assistant host
- Verify in Settings > System > Hardware
- Check device_port in configuration

Metrics not appearing:
- View add-on logs for errors
- Verify device list is configured
- Check devices_list format

Configuration issues:
1. Stop add-on
2. Edit options in Configuration tab
3. Start add-on
4. Configuration regenerates automatically

## Support

GitHub: https://github.com/cordelster/mesh-metrics/issues

## License

GPL-3.0
