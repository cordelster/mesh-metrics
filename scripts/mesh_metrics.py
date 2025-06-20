#!/usr/bin/env python3
"""
Meshtastic Repeater Telemetry Metrics Collector
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
import re
import sys
import time
import tempfile
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import threading
import itertools
import getpass

try:
    import meshtastic
    import meshtastic.serial_interface
    import meshtastic.tcp_interface
except ImportError:
    print("Error:  required meshtastic package not found. Install with: pip install meshtastic, or your package manager")
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

VERSION = "MTM-v0.96-Python"

class MeshtasticTelemetryCollector:
    def __init__(self):
        self.interface = None
        self.verbose = False
        self.grep_args = ["Battery", "Voltage", "utilization"]

    def spinner_animation(self, stop_event):
        """Display a spinner animation while processing"""
        spinner_chars = itertools.cycle(['⠁', '⠂', '⠄', '⡀', '⢀', '⠠', '⠐', '⠈'])
        while not stop_event.is_set():
            sys.stdout.write(f'\r{next(spinner_chars)}')
            sys.stdout.flush()
            time.sleep(0.1)
        sys.stdout.write('\r')
        sys.stdout.flush()

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

        if filepath == "-":
            content = sys.stdin.read()
        else:
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

    def connect_to_meshtastic(self, mode: str, port: str) -> bool:
        """Connect to Meshtastic device"""
        try:
            if mode == "serial":
                self.interface = meshtastic.serial_interface.SerialInterface(port)
            elif mode == "ip":
                self.interface = meshtastic.tcp_interface.TCPInterface(hostname=port)
            else:
                print(f"Invalid mode: {mode}")
                return False

            if self.verbose:
                print(f"Connected to Meshtastic device via {mode} at {port}")
            return True

        except Exception as e:
            print(f"Failed to connect to Meshtastic device: {e}")
            return False

    def request_telemetry(self, node_id: str) -> Dict:
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
            telemetry = self.interface.sendText("Request telemetry", destinationId=node_num, wantAck=True)

            # Get node info
            node_info = self.interface.nodes.get(node_num, {})

            # Extract telemetry data
            telemetry_data = {}
            if 'deviceMetrics' in node_info:
                metrics = node_info['deviceMetrics']
                if 'batteryLevel' in metrics:
                    telemetry_data['Battery'] = metrics['batteryLevel']
                if 'voltage' in metrics:
                    telemetry_data['Voltage'] = metrics['voltage']
                if 'channelUtilization' in metrics:
                    telemetry_data['utilization'] = metrics['channelUtilization']

            return telemetry_data

        except Exception as e:
            if self.verbose:
                print(f"Failed to get telemetry from {node_id}: {e}")
            return {}

    def format_prometheus_output(self, node_id: str, telemetry_data: Dict, device_info: Dict) -> List[str]:
        """Format telemetry data for Prometheus node_exporter"""
        output_lines = []

        # Clean node_id for use in metric name
        clean_node_id = node_id.replace('!', '')

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
            output_lines.append(f'meshtastic_location{{node="{clean_node_id}",location="{device_info["location"]}"}} 1')

        if device_info.get('latitude'):
            output_lines.append(f'meshtastic_latitude{{node="{clean_node_id}"}} {device_info["latitude"]}')

        if device_info.get('longitude'):
            output_lines.append(f'meshtastic_longitude{{node="{clean_node_id}"}} {device_info["longitude"]}')

        # Add up metric
        up_value = 1 if telemetry_data else 0
        output_lines.append(f'meshtastic_up{{node="{clean_node_id}",version="{VERSION}"}} {up_value}')
        
        return output_lines

    def write_output(self, output_lines: List[str], output_dir: str, individual: bool, node_id: str = None):
        """Write output to file(s)"""
        if not output_dir:
            # Print to stdout
            for line in output_lines:
                print(line)
            return

        # Create output directory if it doesn't exist
        Path(output_dir).mkdir(parents=True, exist_ok=True)

        if individual and node_id:
            # Individual file for each node
            clean_node_id = node_id.replace('!', '')
            filename = f"meshtastic-{clean_node_id}.prom"
            filepath = Path(output_dir) / filename

            with open(filepath, 'w') as f:
                for line in output_lines:
                    f.write(line + '\n')
        else:
            # Single file for all nodes
            filename = "meshtastic.prom"
            filepath = Path(output_dir) / filename

            with open(filepath, 'a') as f:
                for line in output_lines:
                    f.write(line + '\n')

    def collect_telemetry(self, devices: List[Dict], output_dir: str, individual: bool, 
                         dwell_time: int, list_only: int):
        """Main telemetry collection function"""

        if list_only == 1:
            # Show node IDs only
            for device in devices:
                print(device['node_id'])
            return

        if list_only == 2:
            # Show full device list
            for device in devices:
                print(f"{device['node_id']},{device['contact_name']},{device['location']},{device['latitude']},{device['longitude']}")
            return

        # Clear output file if not individual
        if output_dir and not individual:
            filepath = Path(output_dir) / "meshtastic.prom"
            if filepath.exists():
                filepath.unlink()

        count = 0
        for device in devices:
            node_id = device['node_id']

            if self.verbose:
                print(f"\nProcessing node: {node_id}")
                print(f"Contact: {device['contact_name']}")
                print(f"Location: {device['location']}")
                print(f"Latitude: {device['latitude']}")
                print(f"Longitude: {device['longitude']}")

            # Request telemetry
            telemetry_data = self.request_telemetry(node_id)

            if telemetry_data:
                count += 1

            # Format output
            output_lines = self.format_prometheus_output(node_id, telemetry_data, device)

            if self.verbose:
                print(f"Generated {len(output_lines)} metrics for {node_id}")

            # Write output
            self.write_output(output_lines, output_dir, individual, node_id)

            # Wait between requests
            if dwell_time > 0:
                time.sleep(dwell_time)

        if self.verbose:
            print(f"\nProcessed {count} nodes successfully")

    def cleanup(self):
        """Clean up resources"""
        if self.interface:
            self.interface.close()

def main():
    parser = argparse.ArgumentParser(
        description='Meshtastic Telemetry Metrics Collector',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Device File format is CSV, Only the NodeID is required:
    NodeID,Contact_Name,LOCATION,LATITUDE,LONGITUDE

Examples:
    %(prog)s -f devices.csv -d /tmp/metrics
    %(prog)s -f devices.csv -m ip -p 192.168.1.100
    %(prog)s -f - -P password < encrypted_devices.csv
        """
    )

    parser.add_argument('-f', '--file', required=True,
                        help='Input device file. Use "-" for stdin.')

    parser.add_argument('-d', '--directory',
                        help='Path to output directory. If not specified, output to stdout.')

    parser.add_argument('-i', '--individual', action='store_true',
                        help='Create individual files for each node.')

    parser.add_argument('-l', '--list', action='count', default=0,
                        help='Show device list. Use -l for node IDs only, -ll for full list.')

    parser.add_argument('-m', '--mode', choices=['serial', 'ip'], default='serial',
                        help='Connection mode (default: serial)')

    parser.add_argument('-o', '--output-format', choices=['node_exporter'], default='node_exporter',
                        help='Output format (default: node_exporter)')

    parser.add_argument('-p', '--port', default='/dev/ttyACM0',
                        help='Device port or IP address (default: /dev/ttyACM0)')

    parser.add_argument('-P', '--password', action='store_true',
                        help='Prompt for device file password')

    parser.add_argument('-t', '--dwell-time', type=int, default=10,
                        help='Dwell time between polling nodes in seconds (default: 10)')

    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Show verbose output')

    parser.add_argument('--version', action='version', version=VERSION)

    args = parser.parse_args()

    # Handle interactive/non-interactive mode
    interactive = sys.stdout.isatty()

    # Create collector instance
    collector = MeshtasticTelemetryCollector()
    collector.verbose = args.verbose

    try:
        # Get password if needed
        password = None
        if args.password:
            password = getpass.getpass("Device file password: ")

        # Parse device file
        devices = collector.parse_device_file(args.file, password)
        
        if not devices:
            print("No devices found in device file")
            sys.exit(1)

        if args.verbose:
            print(f"Loaded {len(devices)} devices from {args.file}")

        # Connect to Meshtastic if not just listing
        if args.list == 0:
            if not collector.connect_to_meshtastic(args.mode, args.port):
                sys.exit(1)

        # Start spinner if interactive and not listing
        stop_spinner = threading.Event()
        spinner_thread = None

        if interactive and args.list == 0 and not args.verbose:
            spinner_thread = threading.Thread(target=collector.spinner_animation, args=(stop_spinner,))
            spinner_thread.start()

        try:
            # Collect telemetry
            collector.collect_telemetry(
                devices=devices,
                output_dir=args.directory,
                individual=args.individual,
                dwell_time=args.dwell_time,
                list_only=args.list
            )
        finally:
            # Stop spinner
            if spinner_thread:
                stop_spinner.set()
                spinner_thread.join()

    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        collector.cleanup()

if __name__ == "__main__":
    main()
