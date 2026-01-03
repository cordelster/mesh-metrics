# Makefile for Meshtastic Metrics Daemon
# Supports host installation, Docker, and Home Assistant add-on builds

# Variables
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SYSCONFDIR = /etc/meshtastic-telemetry
DATADIR = /var/lib/meshtastic-telemetry
SYSTEMDDIR = /etc/systemd/system
LOGDIR = /var/log/meshtastic-telemetry

PYTHON ?= python3
PIP ?= pip3

# Docker variables
DOCKER_IMAGE_NAME ?= meshmetricsd
DOCKER_TAG ?= latest
DOCKER_REGISTRY ?=

# Home Assistant variables
HA_ADDON_NAME ?= meshmetricsd-homeassistant
HA_ADDON_TAG ?= latest

.PHONY: help
help:
	@echo "Meshtastic Metrics Daemon - Installation Options"
	@echo ""
	@echo "Available targets:"
	@echo "  install              - Install on host system (requires root/sudo)"
	@echo "  uninstall            - Remove from host system"
	@echo "  docker-build         - Build standard Docker image with /data directory"
	@echo "  docker-run           - Run Docker container"
	@echo "  homeassistant-build  - Build Home Assistant add-on Docker image"
	@echo "  homeassistant-run    - Run Home Assistant add-on container"
	@echo "  clean                - Clean build artifacts"
	@echo "  test                 - Test configuration"
	@echo ""
	@echo "Installation paths (customizable with PREFIX=/path):"
	@echo "  Binary: $(BINDIR)"
	@echo "  Config: $(SYSCONFDIR)"
	@echo "  Data:   $(DATADIR)"
	@echo "  Logs:   $(LOGDIR)"
	@echo ""

.PHONY: install
install: install-dirs install-python-deps install-scripts install-config install-systemd
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Edit configuration: $(SYSCONFDIR)/meshmetricsd.conf"
	@echo "  2. Create device list: $(SYSCONFDIR)/devices.csv"
	@echo "  3. Enable service: sudo systemctl enable meshmetricsd"
	@echo "  4. Start service: sudo systemctl start meshmetricsd"
	@echo "  5. Check status: sudo systemctl status meshmetricsd"
	@echo ""

.PHONY: install-dirs
install-dirs:
	@echo "Creating directories..."
	install -d -m 755 $(BINDIR)
	install -d -m 755 $(SYSCONFDIR)
	install -d -m 755 $(DATADIR)
	install -d -m 755 $(LOGDIR)

.PHONY: install-python-deps
install-python-deps:
	@echo "Installing Python dependencies..."
	$(PIP) install --upgrade -r requirements.txt

.PHONY: install-scripts
install-scripts:
	@echo "Installing scripts..."
	install -m 755 scripts/meshmetricsd.py $(BINDIR)/meshmetricsd
	install -m 755 scripts/mesh_metrics.sh $(BINDIR)/mesh_metrics.sh

.PHONY: install-config
install-config:
	@echo "Installing configuration files..."
	@if [ ! -f $(SYSCONFDIR)/meshmetricsd.conf ]; then \
		install -m 644 scripts/meshmetricsd.conf.example $(SYSCONFDIR)/meshmetricsd.conf; \
		echo "Created $(SYSCONFDIR)/meshmetricsd.conf"; \
	else \
		echo "Config exists, skipping: $(SYSCONFDIR)/meshmetricsd.conf"; \
	fi
	@if [ ! -f $(SYSCONFDIR)/devices.csv ]; then \
		install -m 644 scripts/example.lst $(SYSCONFDIR)/devices.csv; \
		echo "Created $(SYSCONFDIR)/devices.csv"; \
	else \
		echo "Device list exists, skipping: $(SYSCONFDIR)/devices.csv"; \
	fi

.PHONY: install-systemd
install-systemd:
	@echo "Installing systemd service..."
	install -m 644 scripts/meshmetricsd.service $(SYSTEMDDIR)/meshmetricsd.service
	systemctl daemon-reload
	@echo "Systemd service installed. Use 'systemctl enable meshmetricsd' to enable."

.PHONY: uninstall
uninstall:
	@echo "Stopping and disabling service..."
	-systemctl stop meshmetricsd
	-systemctl disable meshmetricsd
	@echo "Removing files..."
	rm -f $(BINDIR)/meshmetricsd
	rm -f $(BINDIR)/mesh_metrics.sh
	rm -f $(SYSTEMDDIR)/meshmetricsd.service
	systemctl daemon-reload
	@echo "Uninstall complete. Configuration and data preserved in:"
	@echo "  $(SYSCONFDIR)"
	@echo "  $(DATADIR)"
	@echo "  $(LOGDIR)"

.PHONY: docker-build
docker-build:
	@echo "Building Docker image: $(DOCKER_IMAGE_NAME):$(DOCKER_TAG)"
	docker build -f docker/Dockerfile -t $(DOCKER_IMAGE_NAME):$(DOCKER_TAG) .
	@if [ -n "$(DOCKER_REGISTRY)" ]; then \
		docker tag $(DOCKER_IMAGE_NAME):$(DOCKER_TAG) $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_TAG); \
		echo "Tagged as: $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_TAG)"; \
	fi
	@echo ""
	@echo "Docker image built successfully!"
	@echo "Run with: make docker-run"
	@echo ""

.PHONY: docker-run
docker-run:
	@echo "Running Docker container..."
	docker run -d \
		--name meshmetricsd \
		--device=/dev/ttyACM0 \
		-v meshmetrics-data:/data \
		-e TZ=UTC \
		--restart unless-stopped \
		$(DOCKER_IMAGE_NAME):$(DOCKER_TAG)
	@echo ""
	@echo "Container started. View logs with: docker logs -f meshmetricsd"
	@echo "Config location: /data/meshmetricsd.conf (in container)"
	@echo ""

.PHONY: docker-stop
docker-stop:
	docker stop meshmetricsd
	docker rm meshmetricsd

.PHONY: homeassistant-build
homeassistant-build:
	@echo "Building Home Assistant add-on: $(HA_ADDON_NAME):$(HA_ADDON_TAG)"
	docker build -f docker/Dockerfile.homeassistant -t $(HA_ADDON_NAME):$(HA_ADDON_TAG) .
	@if [ -n "$(DOCKER_REGISTRY)" ]; then \
		docker tag $(HA_ADDON_NAME):$(HA_ADDON_TAG) $(DOCKER_REGISTRY)/$(HA_ADDON_NAME):$(HA_ADDON_TAG); \
		echo "Tagged as: $(DOCKER_REGISTRY)/$(HA_ADDON_NAME):$(HA_ADDON_TAG)"; \
	fi
	@echo ""
	@echo "Home Assistant add-on built successfully!"
	@echo ""
	@echo "To install in Home Assistant:"
	@echo "  1. Copy docker/homeassistant/ to /addons/meshmetricsd/ in Home Assistant"
	@echo "  2. Refresh add-on store in Home Assistant"
	@echo "  3. Install and configure the add-on"
	@echo ""

.PHONY: homeassistant-run
homeassistant-run:
	@echo "Running Home Assistant add-on container (test mode)..."
	docker run -d \
		--name meshmetricsd-ha \
		--device=/dev/ttyACM0 \
		-v ha-meshmetrics-data:/data \
		-e TZ=UTC \
		--restart unless-stopped \
		$(HA_ADDON_NAME):$(HA_ADDON_TAG)
	@echo ""
	@echo "Container started. View logs with: docker logs -f meshmetricsd-ha"
	@echo ""

.PHONY: homeassistant-stop
homeassistant-stop:
	docker stop meshmetricsd-ha
	docker rm meshmetricsd-ha

.PHONY: test
test:
	@echo "Testing configuration..."
	$(PYTHON) scripts/meshmetricsd.py --test-config --config scripts/meshmetricsd.conf.example

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	find . -type f -name '*.pyc' -delete
	find . -type d -name '__pycache__' -delete
	find . -type f -name '*.prom' -delete
	@echo "Clean complete."

.PHONY: docker-clean
docker-clean:
	@echo "Removing Docker images..."
	-docker rmi $(DOCKER_IMAGE_NAME):$(DOCKER_TAG)
	-docker rmi $(HA_ADDON_NAME):$(HA_ADDON_TAG)
	@echo "Docker images removed."
