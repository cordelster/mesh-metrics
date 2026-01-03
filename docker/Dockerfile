# Dockerfile for Meshtastic Metrics Daemon
# Standard Docker deployment with /data volume

FROM python:3.11-slim

# Metadata
LABEL maintainer="Corey DeLasaux <cordelster@gmail.com>"
LABEL description="Meshtastic Repeater Telemetry Daemon - Standard Docker"
LABEL version="0.98"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Create application directory and user
RUN useradd -m -u 1000 -s /bin/bash meshtastic && \
    mkdir -p /app /data /var/log/meshtastic-telemetry && \
    chown -R meshtastic:meshtastic /app /data /var/log/meshtastic-telemetry

# Copy application files
COPY scripts/meshmetricsd.py /app/meshmetricsd.py
COPY scripts/meshmetricsd.conf.example /app/meshmetricsd.conf.example
COPY scripts/example.lst /app/example.lst

# Make script executable
RUN chmod +x /app/meshmetricsd.py

# Set working directory
WORKDIR /app

# Create default configuration if not exists
RUN cp /app/meshmetricsd.conf.example /app/default.conf && \
    sed -i 's|^file = .*|file = /data/devices.csv|g' /app/default.conf && \
    sed -i 's|^directory = .*|directory = /data|g' /app/default.conf && \
    sed -i 's|^log_file = .*|log_file = /var/log/meshtastic-telemetry/meshmetricsd.log|g' /app/default.conf && \
    sed -i 's|^pid_file = .*|pid_file = /var/run/meshmetricsd.pid|g' /app/default.conf && \
    sed -i 's|^stats_file = .*|stats_file = /data/stats.json|g' /app/default.conf && \
    chown meshtastic:meshtastic /app/default.conf

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set volumes
VOLUME ["/data"]

# Expose no ports (metrics are written to files or pushed)
# Add this if you want to serve metrics via HTTP in the future
# EXPOSE 9100

# Switch to non-root user
USER meshtastic

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD [ -f /var/run/meshmetricsd.pid ] || exit 1

# Run the daemon in foreground mode
ENTRYPOINT ["/entrypoint.sh"]
CMD ["--foreground", "--config", "/data/meshmetricsd.conf"]
