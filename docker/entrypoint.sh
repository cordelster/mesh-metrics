#!/bin/bash
# Entrypoint script for Meshtastic Metrics Daemon Docker container

set -e

# Configuration file location
CONFIG_FILE="/data/meshmetricsd.conf"
DEVICES_FILE="/data/devices.csv"

# Initialize configuration if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No configuration found. Creating default configuration..."
    cp /app/default.conf "$CONFIG_FILE"
    echo "Configuration created at: $CONFIG_FILE"
fi

# Initialize devices file if it doesn't exist
if [ ! -f "$DEVICES_FILE" ]; then
    echo "No devices file found. Creating example devices file..."
    cp /app/example.lst "$DEVICES_FILE"
    echo "Devices file created at: $DEVICES_FILE"
    echo "WARNING: Please edit $DEVICES_FILE with your actual device list!"
fi

# Check if running with device access
if [ ! -e "/dev/ttyACM0" ] && ! grep -q "^mode = ip" "$CONFIG_FILE"; then
    echo "WARNING: No USB device found at /dev/ttyACM0"
    echo "If using serial mode, make sure to run with --device=/dev/ttyACM0"
    echo "Or configure IP mode in $CONFIG_FILE"
fi

# Display configuration info
echo "======================================"
echo "Meshtastic Metrics Daemon - Docker"
echo "======================================"
echo "Configuration: $CONFIG_FILE"
echo "Devices file: $DEVICES_FILE"
echo "Data directory: /data"
echo "Log directory: /var/log/meshtastic-telemetry"
echo "======================================"
echo ""

# Execute the daemon with passed arguments
exec /app/meshmetricsd.py "$@"
