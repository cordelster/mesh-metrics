FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    meshtastic \
    cryptography

# Create user
RUN groupadd -r meshtastic && useradd -r -g meshtastic meshtastic

# Create directories
RUN mkdir -p /etc/meshtastic-telemetry /var/lib/meshtastic-telemetry /var/log

# Copy daemon
COPY meshmetricsd.py /usr/local/bin/meshmetricsd
RUN chmod +x /usr/local/bin/meshmetricsd

# Copy default config
COPY meshmetricsd.conf /etc/meshtastic-telemetry/meshmetricsd.conf
COPY devices.csv /etc/meshtastic-telemetry/devices.csv

# Set permissions
RUN chown -R meshtastic:meshtastic /var/lib/meshtastic-telemetry /var/log
RUN chmod 644 /etc/meshtastic-telemetry/meshmetricsd.conf /etc/meshtastic-telemetry/devices.csv

# Switch to non-root user
USER meshtastic

# Expose volume for persistent data
VOLUME ["/var/lib/meshtastic-telemetry", "/etc/meshtastic-telemetry"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD test -f /var/lib/meshtastic-telemetry/stats.json || exit 1

# Run daemon
CMD ["/usr/local/bin/meshmetricsd", "-c", "/etc/meshtastic-telemetry/meshmetricsd.conf"]