#!/bin/bash
# Installation script for Meshtastic Telemetry Daemon

set -e

DAEMON_USER="meshtastic"
DAEMON_GROUP="meshtastic"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/meshtastic-telemetry"
DATA_DIR="/var/lib/meshmetricsd"
LOG_DIR="/var/log"

echo "Installing Meshtastic Repeater Telemetry Daemon..."

# Create user and group
if ! getent group "$DAEMON_GROUP" > /dev/null 2>&1; then
    echo "Creating group $DAEMON_GROUP..."
    groupadd --system "$DAEMON_GROUP"
fi

if ! getent passwd "$DAEMON_USER" > /dev/null 2>&1; then
    echo "Creating user $DAEMON_USER..."
    useradd --system --gid "$DAEMON_GROUP" --home-dir "$DATA_DIR" \
            --shell /bin/false --comment "Meshtastic Telemetry Daemon" "$DAEMON_USER"
fi

# Create directories
echo "Creating directories..."
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
mkdir -p /var/lib/node_exporter/textfile_collector

# Set permissions
chown "$DAEMON_USER:$DAEMON_GROUP" "$DATA_DIR"
chmod 755 "$CONFIG_DIR" "$DATA_DIR"

# Install daemon script
echo "Installing daemon script..."
cp meshmetricsd.py "$INSTALL_DIR/meshmetricsd"
chmod 755 "$INSTALL_DIR/meshmetricsd"

# Install configuration file if it doesn't exist
if [ ! -f "$CONFIG_DIR/meshmetricsd.conf" ]; then
    echo "Installing default configuration..."
    cp meshmetricsd.conf "$CONFIG_DIR/"
    chown root:root "$CONFIG_DIR/meshmetricsd.conf"
    chmod 644 "$CONFIG_DIR/meshmetricsd.conf"
fi

# Install sample devices file if it doesn't exist
if [ ! -f "$CONFIG_DIR/devices.csv" ]; then
    echo "Installing sample devices file..."
    cp devices.csv "$CONFIG_DIR/"
    chown root:root "$CONFIG_DIR/devices.csv"
    chmod 644 "$CONFIG_DIR/devices.csv"
fi

# Install service files
if command -v systemctl >/dev/null 2>&1; then
    echo "Installing systemd service..."
    cp meshmetricsd.service /etc/systemd/system/
    systemctl daemon-reload
    echo "To enable and start the service:"
    echo "  systemctl enable meshmetricsd.service"
    echo "  systemctl start meshmetricsd.service"
fi

if [ -d /etc/init.d ] && [ -d /etc/conf.d ]; then
    echo "Installing OpenRC service..."
    cp meshmetricsd.init /etc/init.d/meshmetricsd
    cp meshmetricsd.confd /etc/conf.d/meshmetricsd
    chmod 755 /etc/init.d/meshmetricsd
    chmod 644 /etc/conf.d/meshmetricsd
    echo "To enable and start the service:"
    echo "  rc-update add meshtastic-telemetry default"
    echo "  rc-service meshtastic-telemetry start"
fi

echo "Installation complete!"
echo
echo "Next steps:"
echo "1. Edit $CONFIG_DIR/meshmetricsd.conf to match your setup"
echo "2. Edit $CONFIG_DIR/devices.csv to add your Meshtastic nodes"
echo "3. Test the configuration: meshmetricsd --test-config"
echo "4. Enable and start the service using the commands shown above"