# mesh_metrics

# Description
This script allows interfacing directly with a Meshtastic node to poll repeaters for their status over the mesh network. It only requires a computer setup with [Prometheus](https://prometheus.io/) or [Victoria Metrics](https://victoriametrics.com), node_exporter (at this time), and a serial connection to a Meshtastic radio. It has no requirment for internet access.
These scripts are for special scenarios, as most should be running one of the client configurations. If you need this, you will have zero doubt.

![Meshtastic dashboard](https://github.com/cordelster/mesh-metrics/blob/main/pics/Dashboard.png)

<a href='https://ko-fi.com/L3L0V38OP' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi2.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

# 🚀 NEW PYTHON SCRIPT
# meshmetricsd.py

This python script imports meshtastic-cli python functions which allows for more versatility.
It has all of the same functions as the bash script, though it's been extended with several features and requires a configuration file in addition to the node list, this way you may still encrypt the node list, and simplifies runs.

## 🔍 Features added ontop of what is available in the bash script:
- daemon mode - works with openRC or systemd (optional)
- Atomic prometheus file writes (optional)
- Write individual files per node, or one file.
- Prometheus exposition web push (optional has cravats)
- Statistics, Writes collection statistics to a json file (optional)
- 

### Requirements
- Python >= 3.9
- Python Meshtastic-cli
- meshmetricsd.py
- meshmetricsd.conf (meshmetricsd.conf.example in the scripts folder)
- device.csv        (any list you have that worked with the bash version, example.lst also in the scripts folder)

## How to use:
The cli is very basic, most settings are in the configuration file.
```
$ ./meshmetricsd.py --help

Meshtastic Repeater Telemetry Daemon MTM-v0.98-Daemon, python version: 3.9.6

optional arguments:
  -h, --help            show this help message and exit
  -c CONFIG, --config CONFIG
                        Configuration file path
  -f, --foreground      Run in foreground (don't daemonize)
  -p PATH, --pid-file PATH
                        PID file path (overrides config)
  -l PATH, --log-file PATH
                        Log file path (overrides config)
  -u USER, --user USER  User to run as (requires root)
  -g GROUP, --group GROUP
                        Group to run as (requires root)
  -t, --test-config     Test configuration and exit
  --version             show program's version number and exit
```


<<<<<<< HEAD
# ✨ mesh_metrics.sh
=======
# ✨ mesh_metrics.sh_
>>>>>>> bc4299845a23ebd7144d6850ab011e91e1b81c39
## Requirements:
- Prometheus or Victoria Metrics
- node_exporter
- Meshtastic_cli
- Meshtastic client connected via USB or via network.
- Prometheus alertmanager, used to change alerting nodes color in the geomap panel (optional).

  
## How to use
```
Usage:  -f <dev_file> -d <path/folder> [options]...
Options:
  -h            This help text.
  -d </Path/to/write/directory>
                 Path to the directory to output files.
  -f </path/to/device_file.lst>
                 Input file. If \"-\", stdin will be used instead.
  -i             Make individual files for each node in device list.
  -l | -L        Show what will run from the device list.
  -m             Connection mode serial|ip (default- serial)
  -o <format>    Output format of written file
                 node_exporter - For ingest by Prometheus node_exoprter.
                 csv - [TODO] Create a comma delimited file.
                 (Default- node_exporter)
  -p <Device_port>|<HOST|IP>
                 Device serial port, or IP. (default- /dev/ttyACM0)
  -P <password>   Password for encrypted device file.
  -t              Passive dwell time between polling each node.
  -v              Show verbose output/debug
  -H <URL>        HTTP endpoint to POST metrics to (e.g., http://pushgateway:9091/metrics/job/meshtastic)
                  Metrics will be sent in Prometheus exposition format after each node collection.
  -T <seconds>    HTTP timeout for curl requests (default: 10)
  -A <header>     Additional HTTP header for curl (can be used multiple times)
                  Example: -A "Authorization: Bearer token123"
  --              Do not interpret any more arguments as options.
  Device File format is CSV, Only the NodeID is required
         NodeID,Contact_Name,LOCATION,LATITUDE,LONGITUDE
```


NOTE: Arguments required are -f <path/device.lst>  -p <serial_device>
                             
   With no output directory defined, the script prints to stdout on the screen. 
```sh
./mesh_metrics.sh -f dev.lst -p /dev/tty.usbmodem0
```

Example using network:
```
./mesh_metrics.sh -f dev.lst -p 192.168.1.21 -m ip
```

## Use
Run via a CRON job at an interval suitable for your network. The larger the network, the dwell time should be increased to keep channel utilization values realistic and not lose metrics.


# Device file

Device file options:
Only the NodeID is required to pole nodes though all the commas need to be represented on each line.
All other fields are optional, though GPS coordinates are needed for the dashboard map to post points.

|NODE ID | CONTACT | PROPERTY NAME | LATITUDE | LONGITUDE |
|-----|-----|-----|-----|-----|
|!2f67c123|Jon Derps|Derp Hill| 21.1234|-122.56789|
|!2c4354f4|Dan Mann|The man hill|21.254554|-122.56123|

!2f67c123,Jon Derps,Derp Hill,21.1234,-122.56789

!2c4354f4,Dan Mann,The man hill,21.254554,-122.56123

!56a58b6a,,,,


# Grafana
The Dashboard geomap plugin can change the point color to red for alerting nodes which requires Prometheus alertmanager to be installed and configured. This requirement is a limitation of the geomap plugin and grafana not having any means to otherwise relay that data, or it's intirely possibile I just have not found how to get that alert data from Grafana into the Geomap plugin... (I'm still searching to reduce any extra dependancies).

# Encrypted node list
It possible to encrypt the node list using ssl and a password and provide the password via the the command line in various ways.
To encrypt the file:
```
# set this to whatever password your scripts will use
DEVFILEPASS="YourSecretPassword"

# encrypt plaintext.csv → plaintext.csv.enc
openssl enc \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 1000 \
  -md sha256 \
  -salt \
  -in plaintext.csv \
  -out plaintext.csv.enc \
  -pass pass:"${DEVFILEPASS}"
```

TODO:

