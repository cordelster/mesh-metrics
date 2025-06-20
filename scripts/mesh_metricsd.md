# Meshtastic Telemetry Daemon Configuration and Service Files

## Configuration File: `/etc/meshtastic-telemetry/meshmetricsd.conf`

```conf
[daemon]
# Polling interval in seconds (default: 300 = 5 minutes)
poll_interval = 300

# Log level: DEBUG, INFO, WARNING, ERROR, CRITICAL
log_level = INFO

# Log file path
log_file = /var/log/meshmetricsd.log

# PID file path
pid_file = /var/run/meshmetricsd.pid

# User and group to run as (create these if they don't exist)
user = meshtastic
group = meshtastic

[meshtastic]
# Connection mode: serial or ip
mode = serial

# Device port (for serial) or IP address (for ip mode)
port = /dev/ttyACM0

# Time to wait between polling individual nodes (seconds)
dwell_time = 10

[devices]
# Path to devices CSV file
file = /etc/meshtastic-telemetry/devices.csv

# Whether the device file is encrypted
encrypted = false

# Path to password file (if encrypted = true)
password_file = /etc/meshtastic-telemetry/password

[output]
# Output directory for metrics files
directory = /var/lib/node_exporter/textfile_collector

# Output format (currently only node_exporter supported)
format = node_exporter

# Create individual files for each node (true) or single file (false)
individual_files = false

[monitoring]
# Enable daemon statistics collection
enable_stats = true

# Path to statistics file
stats_file = /var/lib/meshtastic-telemetry/stats.json
```

## Sample Devices File: `/etc/meshtastic-telemetry/devices.csv`

```csv
# Meshtastic Device List
# Format: NodeID,Contact_Name,LOCATION,LATITUDE,LONGITUDE
# Only NodeID is required, other fields are optional

!12345678,Alice,Home Base,37.7749,-122.4194
!87654321,Bob,Mobile Unit,37.7849,-122.4094
!abcdef01,Charlie,Repeater Station,37.7649,-122.4294
```

## SystemD Service File: `/etc/systemd/system/meshmetricsd.service`

```conf
[Unit]
Description=Meshtastic Telemetry Collector Daemon
Documentation=https://github.com/yourusername/meshtastic-telemetry
After=network.target
Wants=network.target

[Service]
Type=simple
User=meshtastic
Group=meshtastic
ExecStart=/usr/local/bin/meshtastic-telemetry-daemon -c /etc/meshtastic-telemetry/meshmetricsd.conf
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=30
TimeoutStartSec=30
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/meshtastic-telemetry /var/lib/node_exporter/textfile_collector /var/log
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Process limits
LimitNOFILE=1024
LimitNPROC=512

[Install]
WantedBy=multi-user.target
```

## OpenRC Init Script: `/etc/init.d/meshtastic-telemetry`

```bash
#!/sbin/openrc-run
# Copyright 2023 Corey DeLasaux
# Distributed under the terms of the GNU General Public License v3

name="meshtastic-telemetry"
description="Meshtastic Telemetry Collector Daemon"

: ${MESHTASTIC_USER:=meshtastic}
: ${MESHTASTIC_GROUP:=meshtastic}
: ${MESHTASTIC_CONFIG:=/etc/meshtastic-telemetry/meshmetricsd.conf}
: ${MESHTASTIC_PIDFILE:=/var/run/meshmetricsd.pid}
: ${MESHTASTIC_LOGFILE:=/var/log/meshmetricsd.log}

command="/usr/local/bin/meshtastic-telemetry-daemon"
command_args="-c ${MESHTASTIC_CONFIG}"
command_user="${MESHTASTIC_USER}:${MESHTASTIC_GROUP}"
command_background="true"
pidfile="${MESHTASTIC_PIDFILE}"
start_stop_daemon_args="--stdout ${MESHTASTIC_LOGFILE} --stderr ${MESHTASTIC_LOGFILE}"

depend() {
    need net
    after logger
}

start_pre() {
    # Create necessary directories
    checkpath --directory --owner ${MESHTASTIC_USER}:${MESHTASTIC_GROUP} --mode 0755 \
        /var/lib/meshtastic-telemetry \
        /var/lib/node_exporter/textfile_collector \
        /var/log

    # Check configuration
    ${command} -c ${MESHTASTIC_CONFIG} --test-config || {
        eerror "Configuration test failed"
        return 1
    }
}

reload() {
    ebegin "Reloading ${name}"
    kill -HUP $(cat ${pidfile}) 2>/dev/null
    eend $?
}
```

## OpenRC Configuration File: `/etc/conf.d/meshtastic-telemetry`

```bash
# Configuration for meshtastic-telemetry daemon

# User and group to run the daemon as
MESHTASTIC_USER="meshtastic"
MESHTASTIC_GROUP="meshtastic"

# Configuration file path
MESHTASTIC_CONFIG="/etc/meshtastic-telemetry/meshmetricsd.conf"

# PID file path
MESHTASTIC_PIDFILE="/var/run/meshmetricsd.pid"

# Log file path
MESHTASTIC_LOGFILE="/var/log/meshmetricsd.log"
```

## Installation Script: `install.sh`

```bash
#!/bin/bash
# Installation script for Meshtastic Telemetry Daemon

set -e

DAEMON_USER="meshtastic"
DAEMON_GROUP="meshtastic"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/meshtastic-telemetry"
DATA_DIR="/var/lib/meshtastic-telemetry"
LOG_DIR="/var/log"

echo "Installing Meshtastic Telemetry Daemon..."

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
cp meshtastic-telemetry-daemon.py "$INSTALL_DIR/meshtastic-telemetry-daemon"
chmod 755 "$INSTALL_DIR/meshtastic-telemetry-daemon"

# Install configuration file if it doesn't exist
if [ ! -f "$CONFIG_DIR/meshmetricsd.conf" ]; then
    echo "Installing default configuration..."
    cp meshmetricsd.conf "$CONFIG_DIR/"
    chown root:root "$CONFIG_DIR/meshmetricsd.conf"
    chmod 644 "$CONFIG_DIR/