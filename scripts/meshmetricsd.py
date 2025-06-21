#!/usr/bin/env python3
"""
Meshtastic Repeater Telemetry Daemon
Copyright 2023 Corey DeLasaux <cordelster@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
"""

import argparse
import csv
import os
import pwd
import grp
import re
import sys
import time
import signal
import logging
import configparser
import threading
import itertools
import getpass
import json
import tempfile
import shutil
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from datetime import datetime

try:
    import meshtastic
    import meshtastic.serial_interface
    import meshtastic.tcp_interface
    from meshtastic import portnums_pb2, telemetry_pb2
except ImportError:
    print("Error: meshtastic package not found. Install with: pip install meshtastic, or your package manager.")
    sys.exit(1)

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.backends import default_backend
    import base64
    CRYPTO_AVAILABLE = True
except ImportError:
    CRYPTO_AVAILABLE = False

VERSION = "MTM-v0.98-Daemon"

class DaemonConfig:
    """Configuration management for the daemon"""

    def __init__(self, config_file: str = "/etc/meshtastic-telemetry/meshmetricsd.conf"):
        self.config_file = config_file
        self.config = configparser.ConfigParser()
        self.load_defaults()
        self.load_config()

    def load_defaults(self):
        """Load default configuration values"""
        self.config['daemon'] = {
            'poll_interval': '300',  # 5 minutes
            'log_level': 'INFO'
        }

        self.config['meshtastic'] = {
            'mode': 'serial',
            'port': '/dev/ttyACM0',
            'dwell_time': '10'
        }

        self.config['devices'] = {
            'file': '/etc/meshtastic-telemetry/devices.csv',
            'encrypted': 'false',
            'password_file': ''
        }

        self.config['output'] = {
            'directory': '/var/lib/node_exporter/textfile_collector',
            'format': 'node_exporter',
            'individual_files': 'false',
            'atomic_writes': 'true'
        }

        self.config['prometheus'] = {
            'push_url': '',
            'job_name': 'meshtastic_repeater_telemetry',
            'instance': '',
            'timeout': '30'
        }

        self.config['monitoring'] = {
            'enable_stats': 'true',
            'stats_file': '/var/lib/meshtastic-telemetry/stats.json'
        }

    def load_config(self):
        """Load configuration from file"""
        if os.path.exists(self.config_file):
            self.config.read(self.config_file)

    def get(self, section: str, key: str, fallback=None):
        """Get configuration value"""
        return self.config.get(section, key, fallback=fallback)

    def getint(self, section: str, key: str, fallback=0):
        """Get integer configuration value"""
        return self.config.getint(section, key, fallback=fallback)

    def getboolean(self, section: str, key: str, fallback=False):
        """Get boolean configuration value"""
        return self.config.getboolean(section, key, fallback=fallback)

class PrometheusExporter:
    """Handle Prometheus push gateway operations"""

    def __init__(self, config: DaemonConfig, logger):
        self.config = config
        self.logger = logger
        self.push_url = config.get('prometheus', 'push_url', '').strip()
        self.job_name = config.get('prometheus', 'job_name', 'meshtastic_repeater_telemetry')
        self.instance = config.get('prometheus', 'instance', '')
        self.timeout = config.getint('prometheus', 'timeout', 30)

    def push_metrics(self, metrics_data: List[str]) -> bool:
        """Push metrics to Prometheus push gateway"""
        if not self.push_url:
            return True  # No push URL configured, skip silently

        try:
            # Construct the push URL with job and instance
            url_parts = [self.push_url.rstrip('/'), 'metrics', 'job', urllib.parse.quote(self.job_name)]

            if self.instance:
                url_parts.extend(['instance', urllib.parse.quote(self.instance)])

            push_url = '/'.join(url_parts)

            # Prepare the metrics payload
            payload = '\n'.join(metrics_data) + '\n'
            payload_bytes = payload.encode('utf-8')

            # Create the HTTP request
            req = urllib.request.Request(
                push_url,
                data=payload_bytes,
                headers={
                    'Content-Type': 'text/plain; version=0.0.4; charset=utf-8',
                    'Content-Length': str(len(payload_bytes))
                },
                method='POST'
            )

            # Send the request
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                if response.status == 200:
                    self.logger.debug(f"Successfully pushed {len(metrics_data)} metrics to {push_url}")
                    return True
                else:
                    self.logger.error(f"Push gateway returned status {response.status}")
                    return False

        except urllib.error.URLError as e:
            self.logger.error(f"Failed to push metrics to {self.push_url}: {e}")
            return False
        except Exception as e:
            self.logger.error(f"Unexpected error pushing metrics: {e}")
            return False

class MeshtasticTelemetryDaemon:
    def __init__(self, config: DaemonConfig, args):
        self.config = config
        self.args = args
        self.interface = None
        self.running = False
        self.logger = None
        self.prometheus_exporter = None
        self.stats = {
            'start_time': None,
            'last_poll': None,
            'total_polls': 0,
            'successful_polls': 0,
            'failed_polls': 0,
            'nodes_processed': 0,
            'nodes_successful': 0,
            'push_successful': 0,
            'push_failed': 0
        }

    def drop_privileges(self):
        """Drop privileges to specified user/group"""
        if os.getuid() != 0:
            # Not running as root, can't drop privileges
            return

        if self.args.group:
            try:
                gid = grp.getgrnam(self.args.group).gr_gid
                os.setgid(gid)
                self.logger.info(f"Dropped to group: {self.args.group}")
            except KeyError:
                self.logger.error(f"Group not found: {self.args.group}")
                sys.exit(1)
            except PermissionError:
                self.logger.error(f"Cannot change to group: {self.args.group}")
                sys.exit(1)

        if self.args.user:
            try:
                uid = pwd.getpwnam(self.args.user).pw_uid
                os.setuid(uid)
                self.logger.info(f"Dropped to user: {self.args.user}")
            except KeyError:
                self.logger.error(f"User not found: {self.args.user}")
                sys.exit(1)
            except PermissionError:
                self.logger.error(f"Cannot change to user: {self.args.user}")
                sys.exit(1)

    def setup_logging(self):
        """Setup logging configuration"""
        log_level = getattr(logging, self.config.get('daemon', 'log_level', 'INFO'))

        # Use log file from args if provided, otherwise from config
        log_file = self.args.log_file or self.config.get('daemon', 'log_file')

        handlers = []

        # Add file handler if log file specified
        if log_file:
            # Create log directory if it doesn't exist
            log_dir = os.path.dirname(log_file)
            if log_dir:
                os.makedirs(log_dir, exist_ok=True)
            handlers.append(logging.FileHandler(log_file))

        # Add console handler if running in foreground
        if self.args.foreground:
            handlers.append(logging.StreamHandler(sys.stdout))

        if not handlers:
            # Fallback to console if no other handlers
            handlers.append(logging.StreamHandler(sys.stdout))

        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=handlers
        )
        self.logger = logging.getLogger('meshtastic-telemetry')

        # Initialize Prometheus exporter
        self.prometheus_exporter = PrometheusExporter(self.config, self.logger)

    def write_pid_file(self):
        """Write process ID to PID file"""
        if not self.args.pid_file:
            return

        pid_dir = os.path.dirname(self.args.pid_file)
        if pid_dir:
            os.makedirs(pid_dir, exist_ok=True)

        try:
            with open(self.args.pid_file, 'w') as f:
                f.write(str(os.getpid()))
            self.logger.debug(f"PID file written: {self.args.pid_file}")
        except Exception as e:
            self.logger.error(f"Failed to write PID file {self.args.pid_file}: {e}")
            sys.exit(1)

    def remove_pid_file(self):
        """Remove PID file"""
        if not self.args.pid_file:
            return

        try:
            os.unlink(self.args.pid_file)
            self.logger.debug(f"PID file removed: {self.args.pid_file}")
        except FileNotFoundError:
            pass
        except Exception as e:
            self.logger.warning(f"Failed to remove PID file: {e}")

    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.running = False

    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)

        # Handle SIGHUP for configuration reload
        if hasattr(signal, 'SIGHUP'):
            signal.signal(signal.SIGHUP, self.reload_handler)

    def reload_handler(self, signum, frame):
        """Handle configuration reload signal"""
        self.logger.info("Received SIGHUP, reloading configuration...")
        try:
            self.config.load_config()
            # Reinitialize Prometheus exporter with new config
            self.prometheus_exporter = PrometheusExporter(self.config, self.logger)
            self.logger.info("Configuration reloaded successfully")
        except Exception as e:
            self.logger.error(f"Failed to reload configuration: {e}")

    def daemonize(self):
        """Daemonize the process (Unix double-fork)"""
        if self.args.foreground:
            return

        try:
            # First fork
            pid = os.fork()
            if pid > 0:
                sys.exit(0)  # Exit parent
        except OSError as e:
            self.logger.error(f"First fork failed: {e}")
            sys.exit(1)

        # Decouple from parent environment
        os.chdir('/')
        os.setsid()
        os.umask(0)

        try:
            # Second fork
            pid = os.fork()
            if pid > 0:
                sys.exit(0)  # Exit first child
        except OSError as e:
            self.logger.error(f"Second fork failed: {e}")
            sys.exit(1)

        # Redirect standard file descriptors
        sys.stdout.flush()
        sys.stderr.flush()

        # Close stdin, stdout, stderr
        with open(os.devnull, 'r') as f:
            os.dup2(f.fileno(), sys.stdin.fileno())
        with open(os.devnull, 'w') as f:
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())

    def decrypt_device_file(self, filepath: str, password: str) -> str:
        """Decrypt device file using AES-256-CBC with PBKDF2"""
        if not CRYPTO_AVAILABLE:
            raise ImportError("cryptography package required for decryption. Install with: pip install cryptography")

        with open(filepath, 'rb') as f:
            encrypted_data = f.read()

        # Decode base64 if the file is base64 encoded
        try:
            encrypted_data = base64.b64decode(encrypted_data)
        except:
            pass  # File might not be base64 encoded

        # Extract salt and IV (OpenSSL format: Salted__<salt><encrypted_data>)
        if encrypted_data.startswith(b'Salted__'):
            salt = encrypted_data[8:16]
            encrypted_data = encrypted_data[16:]
        else:
            salt = b'12345678'  # Default salt if not found

        # Derive key and IV using PBKDF2
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=48,  # 32 bytes for key + 16 bytes for IV
            salt=salt,
            iterations=1000,
            backend=default_backend()
        )
        key_iv = kdf.derive(password.encode())
        key = key_iv[:32]
        iv = key_iv[32:48]

        # Decrypt
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()
        decrypted_data = decryptor.update(encrypted_data) + decryptor.finalize()

        # Remove PKCS7 padding
        padding_length = decrypted_data[-1]
        decrypted_data = decrypted_data[:-padding_length]

        return decrypted_data.decode('utf-8')

    def parse_device_file(self, filepath: str, password: Optional[str] = None) -> List[Dict]:
        """Parse device file (CSV format) with optional decryption"""
        devices = []

        if password:
            content = self.decrypt_device_file(filepath, password)
        else:
            with open(filepath, 'r') as f:
                content = f.read()

        # Remove comments and empty lines
        lines = [line.strip() for line in content.split('\n') 
                if line.strip() and not line.strip().startswith('#')]

        # Parse CSV
        csv_reader = csv.reader(lines)
        for row in csv_reader:
            if len(row) >= 1:  # At least NodeID is required
                device = {
                    'node_id': row[0].strip(),
                    'contact_name': row[1].strip() if len(row) > 1 else '',
                    'location': row[2].strip() if len(row) > 2 else '',
                    'latitude': row[3].strip() if len(row) > 3 else '',
                    'longitude': row[4].strip() if len(row) > 4 else ''
                }
                devices.append(device)

        return devices

    def connect_to_meshtastic(self) -> bool:
        """Connect to Meshtastic device"""
        try:
            mode = self.config.get('meshtastic', 'mode', 'serial')
            port = self.config.get('meshtastic', 'port', '/dev/ttyACM0')

            if mode == "serial":
                self.interface = meshtastic.serial_interface.SerialInterface(port)
            elif mode == "ip":
                self.interface = meshtastic.tcp_interface.TCPInterface(hostname=port)
            else:
                self.logger.error(f"Invalid mode: {mode}")
                return False

            self.logger.info(f"Connected to Meshtastic device via {mode} at {port}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to connect to Meshtastic device: {e}")
            return False

    def request_telemetry(self, node_id: str, timeout: int = 30) -> Dict:
        """Request telemetry from a specific node"""
        if not self.interface:
            return {}

        try:
            # Convert node_id to integer if it's a hex string
            if node_id.startswith('!'):
                node_num = int(node_id[1:], 16)
            else:
                node_num = int(node_id, 16)

            # Request telemetry
            self.logger.debug(f"Requesting telemetry from node {node_num:08x}")
            
            # Send proper telemetry request using sendData with raw bytes
            # Create an empty telemetry request (standard way to request telemetry)
            self.interface.sendData(
                data=b'',  # Empty payload requests telemetry
                destinationId=node_num,
                portNum=portnums_pb2.PortNum.TELEMETRY_APP,
                wantAck=False,
                wantResponse=True
            )
            
            # Wait a bit for response to arrive
            time.sleep(min(timeout, 15))  # Cap at 15 seconds to avoid blocking too long
            
            # Check if we have fresh telemetry data
            node_info = self.interface.nodes.get(node_num, {})
            
            # Also check the nodedb for updated info
            if hasattr(self.interface, 'nodesByNum') and node_num in self.interface.nodesByNum:
                node_info = self.interface.nodesByNum[node_num]

            # Extract telemetry data
            telemetry_data = {}
            if 'deviceMetrics' in node_info:
                metrics = node_info['deviceMetrics']
                if 'batteryLevel' in metrics:
                    telemetry_data['Battery'] = metrics['Battery_level']
                if 'voltage' in metrics:
                    telemetry_data['Voltage'] = metrics['Voltage']
                if 'channelUtilization' in metrics:
                    telemetry_data['utilization'] = metrics['Total_channel_utilization']
                if 'airUtilTx' in metrics:
                    telemetry_data['airtime_tx'] = metrics['Transmit_air_utilization']
                if 'uptimeSeconds' in metrics:
                    telemetry_data['uptime'] = metrics['uptimeSeconds']

            # Check for environment metrics
            if 'environmentMetrics' in node_info:
                env_metrics = node_info['environmentMetrics']
                if 'temperature' in env_metrics:
                    telemetry_data['temperature'] = env_metrics['temperature']
                if 'relativeHumidity' in env_metrics:
                    telemetry_data['humidity'] = env_metrics['relativeHumidity']
                if 'barometricPressure' in env_metrics:
                    telemetry_data['pressure'] = env_metrics['barometricPressure']
            
            if telemetry_data:
                self.logger.debug(f"Collected telemetry from {node_id}: {list(telemetry_data.keys())}")
            else:
                self.logger.debug(f"No telemetry data available for {node_id}")

            return telemetry_data

        except Exception as e:
            self.logger.debug(f"Failed to get telemetry from {node_id}: {e}")
            return {}

    def format_prometheus_output(self, node_id: str, telemetry_data: Dict, device_info: Dict) -> List[str]:
        """Format telemetry data for Prometheus node_exporter"""
        output_lines = []

        # Clean node_id for use in metric name
#         clean_node_id = node_id.replace('!', '')

        # Process telemetry data
        for key, value in telemetry_data.items():
            metric_name = f"meshtastic_{key.lower().replace(' ', '_')}"

            # Check if value is numeric
            if isinstance(value, (int, float)) or (isinstance(value, str) and 
                re.match(r'^[+-]?[0-9]+\.?[0-9]*$', str(value))):
                # Numeric value
                output_lines.append(f'{metric_name}{{node="{clean_node_id}"}} {value}')
            else:
                # String value
                output_lines.append(f'{metric_name}{{node="{clean_node_id}",str="{value}"}} 1')

        # Add device info as metrics
        if device_info.get('contact_name'):
            output_lines.append(f'meshtastic_contact{{node="{clean_node_id}",contact="{device_info["contact_name"]}"}} 1')

        if device_info.get('location'):
            output_lines.append(f'meshtastic_Location{{node="{clean_node_id}",location="{device_info["location"]}"}} 1')

        if device_info.get('latitude'):
            output_lines.append(f'meshtastic_Latitude{{node="{clean_node_id}"}} {device_info["latitude"]}')

        if device_info.get('longitude'):
            output_lines.append(f'meshtastic_Longitude{{node="{clean_node_id}"}} {device_info["longitude"]}')

        # Add up metric
        up_value = 1 if telemetry_data else 0
        output_lines.append(f'meshtastic_up{{node="{clean_node_id}",version="{VERSION}"}} {up_value}')

        return output_lines

    def write_output_atomic(self, content: str, filepath: Path):
        """Write content to file atomically using temporary file"""
        temp_fd = None
        temp_path = None

        try:
            # Create temporary file in the same directory as target
            temp_fd, temp_path = tempfile.mkstemp(
                suffix='.tmp',
                prefix=f'.{filepath.name}.',
                dir=filepath.parent
            )

            # Write content to temporary file
            with os.fdopen(temp_fd, 'w') as temp_file:
                temp_file.write(content)
                temp_file.flush()
                os.fsync(temp_file.fileno())

            temp_fd = None  # File is closed now

            # Atomically move temporary file to target
            if os.name == 'nt':  # Windows
                # On Windows, we need to remove the target first
                if filepath.exists():
                    filepath.unlink()
                shutil.move(temp_path, filepath)
            else:  # Unix-like systems
                os.rename(temp_path, filepath)

            temp_path = None  # Successfully moved
            self.logger.debug(f"Atomically wrote file: {filepath}")

        except Exception as e:
            self.logger.error(f"Failed to write file atomically {filepath}: {e}")
            # Clean up temporary file if it exists
            if temp_fd is not None:
                try:
                    os.close(temp_fd)
                except:
                    pass
            if temp_path and os.path.exists(temp_path):
                try:
                    os.unlink(temp_path)
                except:
                    pass
            raise

    def write_output(self, all_output_lines: List[str]):
        """Write all collected output to file(s) and optionally push to gateway"""
        output_dir = self.config.get('output', 'directory')
        individual = self.config.getboolean('output', 'individual_files')
        atomic_writes = self.config.getboolean('output', 'atomic_writes', True)

        # Write to files if output directory is configured
        if output_dir:
            # Create output directory if it doesn't exist
            Path(output_dir).mkdir(parents=True, exist_ok=True)

            if individual:
                # Group output lines by node for individual files
                node_outputs = {}
                for line in all_output_lines:
                    # Extract node from metric line
                    match = re.search(r'node="([^"]+)"', line)
                    if match:
                        node_id = match.group(1)
                        if node_id not in node_outputs:
                            node_outputs[node_id] = []
                        node_outputs[node_id].append(line)

                # Write individual files
                for node_id, lines in node_outputs.items():
                    filename = f"meshtastic-{node_id}.prom"
                    filepath = Path(output_dir) / filename
                    content = '\n'.join(lines) + '\n'

                    try:
                        if atomic_writes:
                            self.write_output_atomic(content, filepath)
                        else:
                            with open(filepath, 'w') as f:
                                f.write(content)
                    except Exception as e:
                        self.logger.error(f"Failed to write individual file {filepath}: {e}")
            else:
                # Single file for all nodes
                filename = "meshtastic.prom"
                filepath = Path(output_dir) / filename
                content = '\n'.join(all_output_lines) + '\n'

                try:
                    if atomic_writes:
                        self.write_output_atomic(content, filepath)
                    else:
                        with open(filepath, 'w') as f:
                            f.write(content)
                except Exception as e:
                    self.logger.error(f"Failed to write output file {filepath}: {e}")

        # Push to Prometheus gateway if configured
        if self.prometheus_exporter.push_url:
            if self.prometheus_exporter.push_metrics(all_output_lines):
                self.stats['push_successful'] += 1
                self.logger.debug("Successfully pushed metrics to Prometheus gateway")
            else:
                self.stats['push_failed'] += 1

    def update_stats(self, nodes_processed: int, nodes_successful: int):
        """Update daemon statistics"""
        self.stats['last_poll'] = datetime.now().isoformat()
        self.stats['total_polls'] += 1
        self.stats['nodes_processed'] += nodes_processed
        self.stats['nodes_successful'] += nodes_successful

        if nodes_successful > 0:
            self.stats['successful_polls'] += 1
        else:
            self.stats['failed_polls'] += 1

        # Write stats to file if enabled
        if self.config.getboolean('monitoring', 'enable_stats'):
            stats_file = self.config.get('monitoring', 'stats_file')
            stats_dir = os.path.dirname(stats_file)
            if stats_dir:
                os.makedirs(stats_dir, exist_ok=True)

            try:
                with open(stats_file, 'w') as f:
                    json.dump(self.stats, f, indent=2)
            except Exception as e:
                self.logger.warning(f"Failed to write stats file: {e}")

    def poll_devices(self, devices: List[Dict]):
        """Poll all devices for telemetry"""
        self.logger.info(f"Starting poll of {len(devices)} devices")

        nodes_processed = 0
        nodes_successful = 0
        dwell_time = self.config.getint('meshtastic', 'dwell_time', 10)
        all_output_lines = []

        for device in devices:
            if not self.running:
                break

            node_id = device['node_id']
            nodes_processed += 1

            self.logger.debug(f"Processing node: {node_id}")

            # Request telemetry
            telemetry_data = self.request_telemetry(node_id, dwell_time)

            if telemetry_data:
                nodes_successful += 1
                self.logger.debug(f"Successfully collected telemetry from {node_id}")
            else:
                self.logger.warning(f"No telemetry data from {node_id}")

            # Format output
            output_lines = self.format_prometheus_output(node_id, telemetry_data, device)
            all_output_lines.extend(output_lines)

            # Wait between requests
            if dwell_time > 0 and self.running:
                time.sleep(dwell_time)

        # Write all collected data after polling is complete
        if all_output_lines:
            self.write_output(all_output_lines)

        self.update_stats(nodes_processed, nodes_successful)
        self.logger.info(f"Poll completed: {nodes_successful}/{nodes_processed} nodes successful")

    def run(self):
        """Main daemon loop"""
        # Setup logging first (before daemonization)
        self.setup_logging()

        # Daemonize if not running in foreground
        self.daemonize()

        # After daemonization, setup logging again for daemon process
        if not self.args.foreground:
            self.setup_logging()

        self.logger.info("Starting Meshtastic Telemetry Daemon")
        self.stats['start_time'] = datetime.now().isoformat()

        # Setup signal handlers
        self.setup_signal_handlers()

        # Drop privileges if running as root
        self.drop_privileges()

        # Write PID file after privilege drop
        self.write_pid_file()

        try:
            # Load devices
            device_file = self.config.get('devices', 'file')
            password = None

            if self.config.getboolean('devices', 'encrypted'):
                password_file = self.config.get('devices', 'password_file')
                if password_file and os.path.exists(password_file):
                    with open(password_file, 'r') as f:
                        password = f.read().strip()
                else:
                    self.logger.error("Encrypted device file specified but no password file found")
                    return 1

            devices = self.parse_device_file(device_file, password)
            if not devices:
                self.logger.error("No devices found in device file")
                return 1

            self.logger.info(f"Loaded {len(devices)} devices from {device_file}")

            # Connect to Meshtastic
            if not self.connect_to_meshtastic():
                return 1

            # Main polling loop
            self.running = True
            poll_interval = self.config.getint('daemon', 'poll_interval', 300)

            self.logger.info(f"Starting polling loop with {poll_interval}s interval")
            if self.prometheus_exporter.push_url:
                self.logger.info(f"Prometheus push gateway configured: {self.prometheus_exporter.push_url}")

            while self.running:
                try:
                    self.poll_devices(devices)

                    # Wait for next poll
                    sleep_time = 0
                    while sleep_time < poll_interval and self.running:
                        time.sleep(1)
                        sleep_time += 1

                except Exception as e:
                    self.logger.error(f"Error during polling: {e}")
                    if self.running:
                        time.sleep(60)  # Wait a minute before retrying

        except Exception as e:
            self.logger.error(f"Fatal error: {e}")
            return 1
        finally:
            self.cleanup()

        self.logger.info("Daemon shutdown complete")
        return 0

    def cleanup(self):
        """Clean up resources"""
        if self.interface:
            try:
                self.interface.close()
            except:
                pass
        self.remove_pid_file()

def main():
    parser = argparse.ArgumentParser(
        description='Meshtastic Telemetry Daemon',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('-c', '--config', default='/etc/meshtastic-telemetry/meshmetricsd.conf',
                        help='Configuration file path')

    parser.add_argument('-f', '--foreground', action='store_true',
                        help='Run in foreground (don\'t daemonize)')

    parser.add_argument('-p', '--pid-file', metavar='PATH',
                        help='PID file path (overrides config)')

    parser.add_argument('-l', '--log-file', metavar='PATH',
                        help='Log file path (overrides config)')

    parser.add_argument('-u', '--user', metavar='USER',
                        help='User to run as (requires root)')

    parser.add_argument('-g', '--group', metavar='GROUP',
                        help='Group to run as (requires root)')

    parser.add_argument('-t', '--test-config', action='store_true',
                        help='Test configuration and exit')

    parser.add_argument('--version', action='version', version=VERSION)

    args = parser.parse_args()

    # Load configuration
    config = DaemonConfig(args.config)

    if args.test_config:
        print("Configuration test:")
        print(f"Config file: {args.config}")

        # Test runtime arguments
        print("\nRuntime arguments:")
        if args.pid_file:
            print(f"  PID file: {args.pid_file}")
        if args.log_file:
            print(f"  Log file: {args.log_file}")
        if args.user:
            print(f"  User: {args.user}")
        if args.group:
            print(f"  Group: {args.group}")

        print("\nConfiguration sections:")
        for section in config.config.sections():
            print(f"[{section}]")
            for key, value in config.config[section].items():
                print(f"  {key} = {value}")

        # Test device file loading
        try:
            device_file = config.get('devices', 'file')
            if os.path.exists(device_file):
                daemon = MeshtasticTelemetryDaemon(config, args)
                devices = daemon.parse_device_file(device_file)
                print(f"\nDevice file test: Found {len(devices)} devices")
            else:
                print(f"\nDevice file test: File not found: {device_file}")
        except Exception as e:
            print(f"\nDevice file test: Error - {e}")

        print("Configuration OK")
        return 0

    # Create daemon instance
    daemon = MeshtasticTelemetryDaemon(config, args)

    return daemon.run()

if __name__ == "__main__":
    sys.exit(main())