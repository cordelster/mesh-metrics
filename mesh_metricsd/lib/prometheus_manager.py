#!/usr/bin/env python3
"""
Prometheus Manager for Meshtastic Repeater Telemetry
Handles Prometheus metrics formatting, file operations, and push gateway operations
"""

import os
import re
import json
import tempfile
import shutil
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from datetime import datetime


class PrometheusFormatter:
    """Handle Prometheus metrics formatting"""
    
    def __init__(self, node_id_format: str = "default", version: str = "MTM-v0.98-Daemon"):
        """
        Initialize formatter
        
        Args:
            node_id_format: Format for node IDs in metrics ('default' keeps '!', 'clean' removes '!')
            version: Version string for metrics
        """
        self.node_id_format = node_id_format
        self.version = version
    
    def format_node_id_for_metric(self, node_id: str) -> str:
        """Format node ID for use in Prometheus metrics"""
        if self.node_id_format == "clean":
            return node_id.replace('!', '')
        return node_id  # default behavior - keep the '!'
    
    def sanitize_filename(self, node_id: str) -> str:
        """Sanitize node ID for use in filenames"""
        return node_id.replace('!', '').replace('/', '_').replace('\\', '_')
    
    def format_prometheus_metrics(self, node_id: str, telemetry_data: Dict, device_info: Dict) -> List[str]:
        """Format telemetry data for Prometheus node_exporter"""
        output_lines = []
        
        # Format node ID for metrics (configurable)
        metric_node_id = self.format_node_id_for_metric(node_id)
        
        # Process telemetry data
        for key, value in telemetry_data.items():
            metric_name = f"meshtastic_{key.lower().replace(' ', '_')}"
            
            # Check if value is numeric
            if isinstance(value, (int, float)) or (isinstance(value, str) and 
                re.match(r'^[+-]?[0-9]+\.?[0-9]*$', str(value))):
                # Numeric value
                output_lines.append(f'{metric_name}{{node="{metric_node_id}"}} {value}')
            else:
                # String value
                output_lines.append(f'{metric_name}{{node="{metric_node_id}",str="{value}"}} 1')
        
        # Add device info as metrics
        if device_info.get('contact_name'):
            output_lines.append(f'meshtastic_contact{{node="{metric_node_id}",contact="{device_info["contact_name"]}"}} 1')
        
        if device_info.get('location'):
            output_lines.append(f'meshtastic_location{{node="{metric_node_id}",location="{device_info["location"]}"}} 1')
        
        if device_info.get('latitude'):
            output_lines.append(f'meshtastic_latitude{{node="{metric_node_id}"}} {device_info["latitude"]}')
        
        if device_info.get('longitude'):
            output_lines.append(f'meshtastic_longitude{{node="{metric_node_id}"}} {device_info["longitude"]}')
        
        # Add up metric
        up_value = 1 if telemetry_data else 0
        output_lines.append(f'meshtastic_up{{node="{metric_node_id}",version="{self.version}"}} {up_value}')
        
        return output_lines


class PrometheusFileWriter:
    """Handle Prometheus file writing operations"""
    
    def __init__(self, output_dir: str, atomic_writes: bool = True, individual_files: bool = False):
        """
        Initialize file writer
        
        Args:
            output_dir: Directory to write metrics files
            atomic_writes: Whether to use atomic writes via temporary files
            individual_files: Whether to write individual files per node
        """
        self.output_dir = Path(output_dir) if output_dir else None
        self.atomic_writes = atomic_writes
        self.individual_files = individual_files
        self.formatter = PrometheusFormatter()
    
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
            
        except Exception as e:
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
            raise Exception(f"Failed to write file atomically {filepath}: {e}")
    
    def write_metrics_files(self, all_output_lines: List[str]) -> bool:
        """
        Write all collected metrics to file(s)
        
        Args:
            all_output_lines: List of formatted Prometheus metrics lines
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self.output_dir:
            return True  # No output directory configured, skip silently
        
        try:
            # Create output directory if it doesn't exist
            self.output_dir.mkdir(parents=True, exist_ok=True)
            
            if self.individual_files:
                return self._write_individual_files(all_output_lines)
            else:
                return self._write_single_file(all_output_lines)
                
        except Exception as e:
            raise Exception(f"Failed to write metrics files: {e}")
    
    def _write_individual_files(self, all_output_lines: List[str]) -> bool:
        """Write individual files per node"""
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
        success = True
        for node_id, lines in node_outputs.items():
            try:
                # Use sanitized filename
                sanitized_node = self.formatter.sanitize_filename(node_id)
                filename = f"meshtastic-{sanitized_node}.prom"
                filepath = self.output_dir / filename
                content = '\n'.join(lines) + '\n'
                
                if self.atomic_writes:
                    self.write_output_atomic(content, filepath)
                else:
                    with open(filepath, 'w') as f:
                        f.write(content)
                        
            except Exception as e:
                success = False
                raise Exception(f"Failed to write individual file for node {node_id}: {e}")
        
        return success
    
    def _write_single_file(self, all_output_lines: List[str]) -> bool:
        """Write single file for all nodes"""
        try:
            filename = "meshtastic.prom"
            filepath = self.output_dir / filename
            content = '\n'.join(all_output_lines) + '\n'
            
            if self.atomic_writes:
                self.write_output_atomic(content, filepath)
            else:
                with open(filepath, 'w') as f:
                    f.write(content)
            
            return True
            
        except Exception as e:
            raise Exception(f"Failed to write single metrics file: {e}")


class PrometheusPushGateway:
    """Handle Prometheus push gateway operations"""
    
    def __init__(self, push_url: str = "", job_name: str = "meshtastic_repeater_telemetry", 
                 instance: str = "", timeout: int = 30):
        """
        Initialize push gateway client
        
        Args:
            push_url: URL of the Prometheus push gateway
            job_name: Job name for metrics
            instance: Instance identifier
            timeout: Request timeout in seconds
        """
        self.push_url = push_url.strip()
        self.job_name = job_name
        self.instance = instance
        self.timeout = timeout
    
    def push_metrics(self, metrics_data: List[str]) -> Tuple[bool, str]:
        """
        Push metrics to Prometheus push gateway
        
        Args:
            metrics_data: List of formatted Prometheus metrics lines
            
        Returns:
            Tuple[bool, str]: (success, error_message)
        """
        if not self.push_url:
            return True, ""  # No push URL configured, skip silently
        
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
                    return True, ""
                else:
                    return False, f"Push gateway returned status {response.status}"
                    
        except urllib.error.URLError as e:
            return False, f"Failed to push metrics to {self.push_url}: {e}"
        except Exception as e:
            return False, f"Unexpected error pushing metrics: {e}"


class PrometheusManager:
    """Main manager class that coordinates all Prometheus operations"""
    
    def __init__(self, config, logger, node_id_format: str = "default", version: str = "MTM-v0.98-Daemon"):
        """
        Initialize Prometheus manager
        
        Args:
            config: Configuration object
            logger: Logger instance
            node_id_format: Format for node IDs in metrics ('default' or 'clean')
            version: Version string for metrics
        """
        self.config = config
        self.logger = logger
        self.version = version
        
        # Initialize formatter
        self.formatter = PrometheusFormatter(node_id_format, version)
        
        # Initialize file writer
        output_dir = config.get('output', 'directory')
        atomic_writes = config.getboolean('output', 'atomic_writes', True)
        individual_files = config.getboolean('output', 'individual_files', False)
        
        self.file_writer = PrometheusFileWriter(output_dir, atomic_writes, individual_files) if output_dir else None
        
        # Initialize push gateway
        push_url = config.get('prometheus', 'push_url', '').strip()
        job_name = config.get('prometheus', 'job_name', 'meshtastic_repeater_telemetry')
        instance = config.get('prometheus', 'instance', '')
        timeout = config.getint('prometheus', 'timeout', 30)
        
        self.push_gateway = PrometheusPushGateway(push_url, job_name, instance, timeout) if push_url else None
    
    def format_node_metrics(self, node_id: str, telemetry_data: Dict, device_info: Dict) -> List[str]:
        """Format telemetry data for a single node"""
        return self.formatter.format_prometheus_metrics(node_id, telemetry_data, device_info)
    
    def write_and_push_metrics(self, all_output_lines: List[str]) -> Tuple[bool, bool, str]:
        """
        Write metrics to files and push to gateway
        
        Args:
            all_output_lines: List of formatted Prometheus metrics lines
            
        Returns:
            Tuple[bool, bool, str]: (file_success, push_success, error_message)
        """
        file_success = True
        push_success = True
        error_messages = []
        
        # Write to files
        if self.file_writer:
            try:
                file_success = self.file_writer.write_metrics_files(all_output_lines)
                if file_success:
                    self.logger.debug(f"Successfully wrote {len(all_output_lines)} metrics to files")
            except Exception as e:
                file_success = False
                error_msg = f"File write failed: {e}"
                error_messages.append(error_msg)
                self.logger.error(error_msg)
        
        # Push to gateway
        if self.push_gateway:
            try:
                push_success, push_error = self.push_gateway.push_metrics(all_output_lines)
                if push_success:
                    self.logger.debug(f"Successfully pushed {len(all_output_lines)} metrics to gateway")
                else:
                    error_msg = f"Push failed: {push_error}"
                    error_messages.append(error_msg)
                    self.logger.error(error_msg)
            except Exception as e:
                push_success = False
                error_msg = f"Push gateway error: {e}"
                error_messages.append(error_msg)
                self.logger.error(error_msg)
        
        return file_success, push_success, "; ".join(error_messages)
    
    def reload_config(self, config):
        """Reload configuration for push gateway settings"""
        self.config = config
        
        # Reinitialize push gateway with new config
        push_url = config.get('prometheus', 'push_url', '').strip()
        job_name = config.get('prometheus', 'job_name', 'meshtastic_repeater_telemetry')
        instance = config.get('prometheus', 'instance', '')
        timeout = config.getint('prometheus', 'timeout', 30)
        
        self.push_gateway = PrometheusPushGateway(push_url, job_name, instance, timeout) if push_url else None
        
        # Reinitialize file writer with new config
        output_dir = config.get('output', 'directory')
        atomic_writes = config.getboolean('output', 'atomic_writes', True)
        individual_files = config.getboolean('output', 'individual_files', False)
        
        self.file_writer = PrometheusFileWriter(output_dir, atomic_writes, individual_files) if output_dir else None