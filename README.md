# mesh_metrics.sh
# Description
This script allows interfacing directly with a Meshtastic node to poll repeaters for their status over the mesh network. 


# How to use


 -f </path/devfile.lst> Device list

 -d </path/to/node_exporter/folder>

 -i Create individual metrics file per node.

 -p /dev/tyy.usbmodem[0-9]

 -v Output verbose debug info

 -P <password> Password to decrypt your openssl encrpted device list.





NOTE: Arguments required are -f <path/device.lst>
                             -p <serial_device>
```sh
./mesh-metrics.sh -f dev.lst -p /dev/tty.usbmodem0
```



# Device file

Device file options:
Only the NodeID is required to pole nodes though all the commas need to be represented on each line.
All other fields are optional, though GPS coordinates are needed for the dashboard map to post points.

|NODE ID | CONTACT | PROPERTY NAME | LATITUDE | LOGITUDE |
|-----|-----|-----|-----|-----|
|!2f67c123|Jon Derps|Derp Hill| 21.1234|-122.56789|
|!2c4354f4|Dan Mann|The man hill|21.254554|-122.56123|

!2f67c123,Jon Derps,Derp Hill,21.1234,-122.56789

!2c4354f4,Dan Mann,The man hill,21.254554,-122.56123

!56a58b6a,,,,

