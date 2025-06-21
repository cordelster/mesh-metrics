#!/bin/sh
# Installation script for Meshtastic Telemetry Daemon
# Compatible with Alpine Linux (ash shell)

set -e

DAEMON_USER="meshtastic"
DAEMON_GROUP="meshtastic"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/meshtastic-telemetry"
DATA_DIR="/var/lib/meshmetricsd"
LOG_DIR="/var/log"

echo "Installing Meshtastic Repeater Telemetry Daemon..."

# Detect if we're on Alpine Linux
if [ -f /etc/alpine-release ]; then
    ALPINE_LINUX=1
    echo "Detected Alpine Linux"
else
    ALPINE_LINUX=0
fi

# Create user and group
if ! getent group "$DAEMON_GROUP" > /dev/null 2>&1; then
    echo "Creating group $DAEMON_GROUP..."
    if [ "$ALPINE_LINUX" = "1" ]; then
        addgroup -S "$DAEMON_GROUP"
    else
        groupadd --system "$DAEMON_GROUP"
    fi
fi

if ! getent passwd "$DAEMON_USER" > /dev/null 2>&1; then
    echo "Creating user $DAEMON_USER..."
    if [ "$ALPINE_LINUX" = "1" ]; then
        adduser -S -G "$DAEMON_GROUP" -h "$DATA_DIR" \
                -s /bin/false -g "Meshtastic Telemetry Daemon" "$DAEMON_USER"
    else
        useradd --system --gid "$DAEMON_GROUP" --home-dir "$DATA_DIR" \
                --shell /bin/false --comment "Meshtastic Telemetry Daemon" "$DAEMON_USER"
    fi
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
if [ ! -f "meshmetricsd.py" ]; then
    echo "Error: meshmetricsd.py not found in current directory"
    exit 1
fi
cp meshmetricsd.py "$INSTALL_DIR/meshmetricsd"
chmod 755 "$INSTALL_DIR/meshmetricsd"

# Install configuration file if it doesn't exist
if [ ! -f "$CONFIG_DIR/meshmetricsd.conf" ]; then
    echo "Installing default configuration..."
    if [ -f "meshmetricsd.conf" ]; then
        cp meshmetricsd.conf "$CONFIG_DIR/"
        chown root:root "$CONFIG_DIR/meshmetricsd.conf"
        chmod 644 "$CONFIG_DIR/meshmetricsd.conf"
    else
        echo "Warning: meshmetricsd.conf not found in current directory"
    fi
fi

# Install sample devices file if it doesn't exist
if [ ! -f "$CONFIG_DIR/devices.csv" ]; then
    echo "Installing sample devices file..."
    if [ -f "devices.csv" ]; then
        cp devices.csv "$CONFIG_DIR/"
        chown root:root "$CONFIG_DIR/devices.csv"
        chmod 644 "$CONFIG_DIR/devices.csv"
    else
        echo "Warning: devices.csv not found in current directory"
    fi
fi

# Install service files
if command -v systemctl >/dev/null 2>&1; then
    echo "Installing systemd service..."
    if [ -f "meshmetricsd.service" ]; then
        cp meshmetricsd.service /etc/systemd/system/
        systemctl daemon-reload
        echo "To enable and start the service:"
        echo "  systemctl enable meshmetricsd.service"
        echo "  systemctl start meshmetricsd.service"
    else
        echo "Warning: meshmetricsd.service not found"
    fi
fi

# Check for OpenRC (Alpine Linux, Gentoo uses OpenRC)
if [ -d /etc/init.d ] && ([ -d /etc/conf.d ] || [ "$ALPINE_LINUX" = "1" ]); then
    echo "Installing OpenRC service..."
    if [ -f "meshmetricsd.init" ]; then
        cp meshmetricsd.init /etc/init.d/meshmetricsd
        chmod 755 /etc/init.d/meshmetricsd
        echo "OpenRC init script installed"
    else
        echo "Warning: meshmetricsd.init not found"
    fi
    
    if [ -f "meshmetricsd.confd" ]; then
        # Alpine Linux doesn't always have /etc/conf.d, create it if needed
        [ ! -d /etc/conf.d ] && mkdir -p /etc/conf.d
        cp meshmetricsd.confd /etc/conf.d/meshmetricsd
        chmod 644 /etc/conf.d/meshmetricsd
        echo "OpenRC conf.d file installed"
    else
        echo "Warning: meshmetricsd.confd not found"
    fi
    
    echo "To enable and start the service:"
    echo "  rc-update add meshmetricsd default"
    echo "  rc-service meshmetricsd start"
fi

echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit $CONFIG_DIR/meshmetricsd.conf to match your setup"
echo "2. Edit $CONFIG_DIR/devices.csv to add your Meshtastic nodes"
echo "3. Test the configuration: meshmetricsd --test-config"
echo "4. Enable and start the service using the commands shown above"

# Test basic functionality
echo ""
echo "Testing installation..."
if [ -x "$INSTALL_DIR/meshmetricsd" ]; then
    echo "✓ Daemon script installed successfully"
else
    echo "✗ Daemon script installation failed"
    exit 1
fi

if [ -d "$CONFIG_DIR" ] && [ -d "$DATA_DIR" ]; then
    echo "✓ Directories created successfully"
else
    echo "✗ Directory creation failed"
    exit 1
fi

if getent passwd "$DAEMON_USER" > /dev/null 2>&1; then
    echo "✓ Daemon user created successfully"
else
    echo "✗ Daemon user creation failed"
    exit 1
fi

echo "Installation test completed successfully!"