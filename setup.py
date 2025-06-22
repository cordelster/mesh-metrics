#!/usr/bin/env python3
"""
Setup script for meshtastic-repeater-telemetry-daemon
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    try:
        with open('README.md', 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return "Meshtastic-repeater-telemetry-daemon - A daemon for collecting and exporting Meshtastic node telemetry data"

# Read requirements from requirements.txt
def read_requirements():
    try:
        with open('requirements.txt', 'r') as f:
            return [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except FileNotFoundError:
        return [
            'meshtastic>=2.0.0',
            'cryptography>=3.0.0',
        ]

setup(
    name="meshtastic-repeater-telemetry-daemon",
    version="0.98.0",
    author="Corey DeLasaux",
    author_email="cordelster@gmail.com",
    description="A daemon for collecting and exporting Meshtastic repeater node telemetry data",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/cordelster/mesh-metrics",  # Update with your repo
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: System Administrators",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Networking :: Monitoring",
        "License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Operating System :: POSIX :: Linux",
        "Operating System :: MacOS",
        "Operating System :: Microsoft :: Windows",
    ],
    python_requires=">=3.7",
    install_requires=read_requirements(),
    extras_require={
        'dev': [
            'pytest>=6.0',
            'pytest-cov',
            'flake8',
            'black',
            'mypy',
        ],
        'systemd': [
            'systemd-python',
        ],
    },
    entry_points={
        'console_scripts': [
            'meshmetricsd=mesh-metricsd.meshmetricsd:main',
            'meshtastic-repeater-telemetry-daemon=mesh-metricsd.meshmetricsd:main',
        ],
    },
    data_files=[
        ('etc/meshtastic-telemetry', ['config/meshmetricsd.conf.example']),
        ('etc/systemd/system', ['systemd/meshmetricsd.service']),
        ('usr/share/doc/meshtastic-telemetry-daemon', ['README.md', 'LICENSE']),
    ],
    include_package_data=True,
    package_data={
        'meshtastic_telemetry': [
            'config/*.conf',
            'systemd/*.service',
        ],
    },
    zip_safe=False,
    keywords="meshtastic repeater telemetry monitoring prometheus daemon",
    project_urls={
        "Bug Reports": "https://github.com/cordelster/mesh-metrics/issues",
        "Source": "https://github.com/cordelster/mesh-metrics",
        "Documentation": "https://github.com/cordelster/mesh-metrics/blob/main/README.md",
    },
)
