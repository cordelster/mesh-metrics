#!/usr/bin/with-contenv bashio
# Home Assistant Add-on run script for Meshtastic Metrics Daemon

set -e

bashio::log.info "Starting Meshtastic Metrics Daemon..."

CONFIG_FILE="/data/meshmetricsd.conf"
DEVICES_FILE="/data/devices.csv"
PASSWORD_FILE="/data/password"

# Read all configuration from Home Assistant options
CONNECTION_MODE=$(bashio::config 'connection_mode')
DEVICE_PORT=$(bashio::config 'device_port')
POLL_INTERVAL=$(bashio::config 'poll_interval')
DWELL_TIME=$(bashio::config 'dwell_time')
LOG_LEVEL=$(bashio::config 'log_level')
OUTPUT_DIR=$(bashio::config 'output_directory')
OUTPUT_FORMAT=$(bashio::config 'output_format')
INDIVIDUAL_FILES=$(bashio::config 'individual_files')
ATOMIC_WRITES=$(bashio::config 'atomic_writes')
DEVICES_LIST=$(bashio::config 'devices_list')
DEVICES_ENCRYPTED=$(bashio::config 'devices_encrypted')
DEVICES_PASSWORD=$(bashio::config 'devices_password')
PROMETHEUS_PUSH_URL=$(bashio::config 'prometheus_push_url')
PROMETHEUS_JOB_NAME=$(bashio::config 'prometheus_job_name')
PROMETHEUS_INSTANCE=$(bashio::config 'prometheus_instance')
PROMETHEUS_TIMEOUT=$(bashio::config 'prometheus_timeout')
ENABLE_STATS=$(bashio::config 'enable_stats')

# Generate complete configuration file from options
bashio::log.info "Generating configuration from add-on options..."

cat > "$CONFIG_FILE" <<EOF
[daemon]
poll_interval = ${POLL_INTERVAL}
log_level = ${LOG_LEVEL}
log_file = /data/meshmetricsd.log
pid_file = /var/run/meshmetricsd.pid

[meshtastic]
mode = ${CONNECTION_MODE}
port = ${DEVICE_PORT}
dwell_time = ${DWELL_TIME}

[devices]
file = ${DEVICES_FILE}
encrypted = ${DEVICES_ENCRYPTED}
password_file = ${PASSWORD_FILE}

[output]
directory = ${OUTPUT_DIR}
format = ${OUTPUT_FORMAT}
individual_files = ${INDIVIDUAL_FILES}
atomic_writes = ${ATOMIC_WRITES}

[prometheus]
EOF

# Add Prometheus push URL if configured
if [ -n "$PROMETHEUS_PUSH_URL" ]; then
    echo "push_url = ${PROMETHEUS_PUSH_URL}" >> "$CONFIG_FILE"
else
    echo "# push_url = " >> "$CONFIG_FILE"
fi

cat >> "$CONFIG_FILE" <<EOF
job_name = ${PROMETHEUS_JOB_NAME}
EOF

# Add Prometheus instance if configured
if [ -n "$PROMETHEUS_INSTANCE" ]; then
    echo "instance = ${PROMETHEUS_INSTANCE}" >> "$CONFIG_FILE"
else
    echo "# instance = " >> "$CONFIG_FILE"
fi

cat >> "$CONFIG_FILE" <<EOF
timeout = ${PROMETHEUS_TIMEOUT}

[monitoring]
enable_stats = ${ENABLE_STATS}
stats_file = /data/stats.json
EOF

bashio::log.info "Configuration file created: ${CONFIG_FILE}"

# Write device list from configuration to file
bashio::log.info "Writing device list..."
echo "$DEVICES_LIST" > "$DEVICES_FILE"
bashio::log.info "Device list written: ${DEVICES_FILE}"

# Handle password file if encryption is enabled
if bashio::config.true 'devices_encrypted'; then
    if [ -n "$DEVICES_PASSWORD" ]; then
        echo "$DEVICES_PASSWORD" > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        bashio::log.info "Password file created for encrypted device list"
    else
        bashio::log.error "Encryption enabled but no password provided!"
        exit 1
    fi
else
    # Remove password file if encryption is disabled
    rm -f "$PASSWORD_FILE"
fi

# Check device access for serial mode
if [ "$CONNECTION_MODE" = "serial" ]; then
    if [ ! -e "$DEVICE_PORT" ]; then
        bashio::log.error "Serial device not found: $DEVICE_PORT"
        bashio::log.error "Make sure the USB device is connected and accessible"
        bashio::log.error "Available devices:"
        ls -la /dev/tty* || true
        exit 1
    fi
    bashio::log.info "Serial device found: $DEVICE_PORT"
else
    bashio::log.info "Using IP mode, connecting to: $DEVICE_PORT"
fi

# Display configuration summary
bashio::log.info "Configuration Summary:"
bashio::log.info "  Connection: ${CONNECTION_MODE} at ${DEVICE_PORT}"
bashio::log.info "  Poll interval: ${POLL_INTERVAL}s, Dwell time: ${DWELL_TIME}s"
bashio::log.info "  Log level: ${LOG_LEVEL}"
bashio::log.info "  Output: ${OUTPUT_DIR} (individual files: ${INDIVIDUAL_FILES})"
bashio::log.info "  Atomic writes: ${ATOMIC_WRITES}"
if [ -n "$PROMETHEUS_PUSH_URL" ]; then
    bashio::log.info "  Prometheus push: ${PROMETHEUS_PUSH_URL}"
fi
bashio::log.info "  Statistics: ${ENABLE_STATS}"

# Count devices
DEVICE_COUNT=$(echo "$DEVICES_LIST" | grep -c "^!" || echo "0")
bashio::log.info "  Monitoring ${DEVICE_COUNT} device(s)"

# Start the daemon in foreground mode
bashio::log.info "Starting daemon..."
exec /app/meshmetricsd.py \
    --foreground \
    --config "$CONFIG_FILE"
