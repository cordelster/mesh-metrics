#!/bin/bash
########################
## Copyright 2023 Corey DeLasaux <cordelster@gmail.com
##
##    This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <https://www.gnu.org/licenses/>.
##
########################

VERSION="MTM-v0.93";
RS=0;

R1="^([0-9a-fA-F!]{9}),"
R1+="([a-zA-Z0-9\s ]+)?,"
R1+="([a-zA-Z0-9\s ]+)?,"
R1+="([0-9.\-]+)?,"
R1+="([0-9.\-]+)?";


DEVFILE="";
DEVFILEPASS="";
DLST="";
DOLS=0;
VERB=0;
SSHO=0;
FORMAT="node_exporter"; 
PDT=10;
PORT="/dev/ttyACM0";
ORPASS="";
CUSER="";
EXPECT="/usr/bin/expect";
OPENSSL="/usr/bin/openssl";
MESHTASTIC="/usr/bin/meshtastic";
TPUT="/usr/bin/tput"
EXPECTAGR="-nN -f -";

OPENSSL_OPT="-pbkdf2 -iter 1000 -aes-256-cbc -md SHA256";

GREPARGS="Battery|Voltage|utilization"

usage() {
cat <<-__EOF__
Script description

Usage: $PROGNAME -f <dev_file> -d <path/folder> [options]...

Options:

 -h             This help text.

 -d </Path/to/write/directory>
                 Path to the directory to output files.

 -f </path/to/device_file.lst>
                 Input file. If \"-\", stdin will be used instead.
                 
 -i              Make individual files for each node in device list.

  -l | -L        Show what will run from the device list.

  -o <format>    Output format of written file
                 node_exporter - For ingest by Prometheus node_exoprter.
                 csv - [TODO] Create a comma delimited file.
                 (Default- $FORMAT)

  -p <Device_port> Device serial port. (default- $PORT)

  -P <password>   Password for encrypted device file.

  -t              Passive dwell time between polling each node.

  -v              Show verbose output/debug

  --              Do not interpret any more arguments as options.

  Device File format is CSV, Only the NodeID is required
         NodeID,Contact_Name,LOCATION,LATITUDE,LONGITUDE
         
__EOF__
	echo -ne "Contact: Corey DeLasaux <cordelster@gmail.com>\nVersion: ""$VERSION""\n\n";
}


while getopts "f:o:d:u:hip:P:t:lvL" opt; do
	case $opt in
		f) DEVFILE="${OPTARG}";;
		d) DLST="${OPTARG}";;
		h) usage; exit 0 ;;
		i) INDIV=1;;
		o) FORMAT="${OPTARG}";;
		k) SSHO=1;;
		l) DOLS=1;;
		L) DOLS=2;;
		p) PORT="${OPTARG}";;
		t) PDT="${OPTARG}";;
		u) CUSER="${OPTARG}";;
		v) VERB=1;;

		P) read -s -p "DEVFILE Password: " DEVFILEPASS;;
		:) echo "Option -$OPTARG requires an argument." >&2;exit 1;;
		\?) echo "Invalid option: -$OPTARG"; usage >&2;exit 1;;
	esac;
done;
readonly PROGNAME=$(basename $0)

readonly PROGBASENAME=${PROGNAME%.*}

readonly PROGDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

readonly ARGS="$@"

readonly ARGNUM="$#"

if [ ! -x $MESHTASTIC ]; then
	if [ -x /usr/local/bin/meshtastic ]; then
		MESHTASTIC="/usr/local/bin/meshtastic"
		echo "meshtastic found at: "${MESHTASTIC}
	fi
fi

if [ "${VERB}" -eq 1 ]; then
	echo -ne "Contact: Corey DeLasaux <cordelster@gmail.com>\nVersion: ""$VERSION""\nCopyright 2023\n\n";
	
fi;
###


function cursorBack() {
  echo -en "\033[$1D"
}

function spinner() {
  local LC_CTYPE=C
  local pid=$1
  case $(($RANDOM % 12)) in
  0)
    local spin='⠁⠂⠄⡀⢀⠠⠐⠈'
    local charwidth=3
    ;;
  1)
    local spin='-\|/'
    local charwidth=1
    ;;
  2)
    local spin="▁▂▃▄▅▆▇█▇▆▅▄▃▂▁"
    local charwidth=3
    ;;
  3)
    local spin="▉▊▋▌▍▎▏▎▍▌▋▊▉"
    local charwidth=3
    ;;
  4)
    local spin='←↖↑↗→↘↓↙'
    local charwidth=3
    ;;
  5)
    local spin='▖▘▝▗'
    local charwidth=3
    ;;
  6)
    local spin='┤┘┴└├┌┬┐'
    local charwidth=3
    ;;
  7)
    local spin='◢◣◤◥'
    local charwidth=3
    ;;
  8)
    local spin='◰◳◲◱'
    local charwidth=3
    ;;
  9)
    local spin='◴◷◶◵'
    local charwidth=3
    ;;
  10)
    local spin='◐◓◑◒'
    local charwidth=3
    ;;
  11)
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3
    ;;
  esac

  local i=0
  if [ -f "$TPUT" ]; then tput civis; fi
	while kill -0 $pid 2>/dev/null; do
    local i=$(((i + $charwidth) % ${#spin}))
  printf "%s" "${spin:$i:$charwidth}"

    cursorBack 1
    sleep .1
	done
	  if [ -f "$TPUT" ]; then tput cnorm; fi
wait $pid # capture exit code
return $?
}

case "$TERM" in
    *dumb*) INTERACT=0;;
    *)      INTERACT=1;;
esac;

if [ ! -f $DEVFILE ]; then echo ${DEVFILE} " not found!"; exit 1; fi
if [ ! -c $PORT ]; then echo ${PORT} " port not found!"; exit 1; fi
if [ ! -x $MESHTASTIC ]; then echo ${MESHTASTIC} " not found!"; exit 1; fi

function promnode() {

			arr=("$@")

    for i in "${arr[@]}"
    do 
    	if [ "${VERB}" -eq 1 ]; then
    	echo $NODE " Raw variable:  " $i
    	fi;

    	TELE=( $( echo $i | cut -d : -f 1 | sed -e 's/ /_/g' | awk '{$1=$1};1' ) )
    	TELE+=( $( echo $i | cut -d : -f 2 | sed -e 's/[Vv%]$//g' | awk '{$1=$1};1' ) )

    	if [ "${VERB}" -eq 1 ]; then
    	echo $NODE "Filtered array: "${TELE[@]}
    	fi;

    		PNEX_INDEX=(meshtastic_"${TELE[0]}")
    		if [[ ${TELE[1]} =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
    		PNEX_OUTPUT=(""${PNEX_INDEX}"{node=\""$NODE"\"} "${TELE[1]}"")
    		else
    		PNEX_OUTPUT=("${PNEX_INDEX}""{node=\""$NODE"\",str=\""${TELE[1]}"\"} 1")
    		fi
			if [ "${VERB}" -eq 1 ]; then echo "Node Exporter formated: "$PNEX_OUTPUT ${TELE[1]}; fi;
    		if [ -z "${DLST}" ]; then
    			echo $PNEX_OUTPUT;
    		else
    			if [ -z ${INDIV} ]; then
    			FILEOUT="${DLST}/meshtastic.prom"
    			else
    			FILEOUT="${DLST}/meshtastic-${NODEFILE}.prom"
    			fi
    			echo $PNEX_OUTPUT >> ${FILEOUT}.$$; #Maybe into array and return, handle write somewhere else
    		fi;

	done
}

function ocsv() {
	echo "Not developed yet."
	exit 1
}

    count=0
function invoke_telem() {
  trap - INT
  if [ -f "$DLST" ]; then
  rm ${DLST}
  fi
  if [ ${?} -eq 0 ]; then while read L; do if [[ ${L} =~ ${R1} ]]; then
	NODE="${BASH_REMATCH[1]}";
	PROP="${BASH_REMATCH[2]}";
	LOCA="${BASH_REMATCH[3]}";
	LATI="${BASH_REMATCH[4]}";
	LONG="${BASH_REMATCH[5]}";

	
	if [ "${VERB}" -eq 1 ]; then
		echo -ne "\n\nVERSION: ""${VERSION}""\n\nNODE: ""${NODE}""\nCONTACT: ""${PROP}""\nLOCATION: ""${LOCA}""\nLATITUDE: ""${LATI}""\nLONGITUDE: ""${LONG}""\nUSER: ""${USER}""\n";
	fi;
	
	if [ "${DOLS}" -eq 1 ]; then
		echo "${NODE}";
		continue;
	fi;

	if [ "${DOLS}" -eq 2 ]; then
		echo "${L}";
		continue;
	fi;
	NODEFILE=( $( echo $NODE | sed -e 's/\!//g' ) )
    array=()
	IFS=$'\n'
    array+=( $(${MESHTASTIC} --port $PORT --request-telemetry --dest $NODE | grep -ahE "${GREPARGS}") );
	if [ ! -z "${array[2]}" ]; then
    	(( count++ ))
    	if [ ! -z $PROP ]; then array+=("Contact: ${PROP}"); fi
    	if [ ! -z $LOCA ]; then array+=("Location: ${LOCA}"); fi
		if [ ! -z $LATI ]; then array+=("Latitude: ${LATI}"); fi
		if [ ! -z $LONG ]; then array+=("Longitude: ${LONG}"); fi
		array+=("up: ${VERSION}");
	else
		array+=("up: 0")
	fi
  
    for i in ${array[@]}
    do 
    	if [ "${VERB}" -eq 1 ]; then
    	echo $NODE " Raw variable:  " $i
    	fi;

	done
    	case $FORMAT in

			  node_exporter) promnode "${array[@]}";;
			        	*) echo "Invalid option: -c $FORMAT"; usage >&2;exit 1;;
		esac;
		
if [ ! -z $INDIV ]; then
if [ ! -z $DLST ]; then mv ${FILEOUT}.$$  ${FILEOUT}; fi
fi
		wait $PDT 2>/dev/null
	
 
  else
	echo "ERROR: incorrect device string: "${L}"";
	RS=1;
  fi;
  

 done < <((\
 IFS=$','
  if [ -z "${DEVFILEPASS}" ]; then \
  	cat "${DEVFILE}"; \
  else \
  	"${OPENSSL}" enc -in "${DEVFILE}" ${OPENSSL_OPT} -d -pass pass:"${DEVFILEPASS}"; \
  fi;) | grep -Ev "^( +)?#.*$|^$" | sort -u | sort -t@ -n);

fi;
if [ -z $INDIV ]; then
if [ ! -z $DLST ]; then mv ${FILEOUT}.$$  ${FILEOUT}; fi
fi
}



if [ "${INTERACT}" -eq 0 ]; then invoke_telem; else invoke_telem & spinner $!; fi;
exit ${RS};

