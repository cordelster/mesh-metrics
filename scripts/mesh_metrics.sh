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

VERSION="MTM-v0.98";
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
MODE="serial"
ORPASS="";
CUSER="";
EXPECT="/usr/bin/expect";
OPENSSL="/usr/bin/openssl";
MESHTASTIC="/usr/bin/meshtastic";
TPUT="/usr/bin/tput"
CURL="/usr/bin/curl"
EXPECTAGR="-nN -f -";

# New HTTP POST variables
HTTP_ENDPOINT="";
HTTP_TIMEOUT=10;
HTTP_HEADERS="";

OPENSSL_OPT="-pbkdf2 -iter 1000 -aes-256-cbc -md SHA256";

GREPARGS="Battery|Voltage|utilization"

usage() {
cat <<-__EOF__
Script description

Usage: $PROGNAME -f <dev_file> -d <path/folder> [options]...

Options:

  -h            This help text.

  -d </Path/to/write/directory>
                 Path to the directory to output files.

  -f </path/to/device_file.lst>
                 Input file. If \"-\", stdin will be used instead.
                 
  -i             Make individual files for each node in device list.

  -l | -L        Show what will run from the device list.

  -m             Connection mode serial|ip (default- $MODE)
  
  -o <format>    Output format of written file
                 node_exporter - For ingest by Prometheus node_exoprter.
                 csv - [TODO] Create a comma delimited file.
                 (Default- $FORMAT)

  -p <Device_port>|<HOST|IP> 
                 Device serial port, or IP. (default- $PORT)

  -P <password>   Password for encrypted device file.

  -t              Passive dwell time between polling each node.

  -v              Show verbose output/debug

  -H <URL>        HTTP endpoint to POST metrics to (e.g., http://pushgateway:9091/metrics/job/meshtastic)
                  Metrics will be sent in Prometheus exposition format after each node collection.

  -T <seconds>    HTTP timeout for curl requests (default: $HTTP_TIMEOUT)

  -A <header>     Additional HTTP header for curl (can be used multiple times)
                  Example: -A "Authorization: Bearer token123"

  --              Do not interpret any more arguments as options.

  Device File format is CSV, Only the NodeID is required
         NodeID,Contact_Name,LOCATION,LATITUDE,LONGITUDE
         
__EOF__
  echo -ne "Contact: Corey DeLasaux <cordelster@gmail.com>\nVersion: ""$VERSION""\n\n";
}


while getopts "f:o:d:m:u:hip:P:t:lvLH:T:A:" opt; do
  case $opt in
    f) DEVFILE="${OPTARG}";;
    d) DLST="${OPTARG}";;
    h) usage; exit 0 ;;
    i) INDIV=1;;
    m) MODE="${OPTARG}";;
    o) FORMAT="${OPTARG}";;
    k) SSHO=1;;
    l) DOLS=1;;
    L) DOLS=2;;
    p) PORT="${OPTARG}";;
    t) PDT="${OPTARG}";;
    u) CUSER="${OPTARG}";;
    v) VERB=1;;
    H) HTTP_ENDPOINT="${OPTARG}";;
    T) HTTP_TIMEOUT="${OPTARG}";;
    A) HTTP_HEADERS="${HTTP_HEADERS} -H \"${OPTARG}\"";;

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

# Check for curl if HTTP endpoint is specified
if [ ! -z "$HTTP_ENDPOINT" ] && [ ! -x $CURL ]; then
  if [ -x /usr/local/bin/curl ]; then
    CURL="/usr/local/bin/curl"
  else
    echo "curl not found but HTTP endpoint specified!" >&2
    exit 1
  fi
fi

if [ "${VERB}" -eq 1 ]; then
  echo -ne "Contact: Corey DeLasaux <cordelster@gmail.com>\nVersion: ""$VERSION""\nCopyright 2023\n\n";
  if [ ! -z "$HTTP_ENDPOINT" ]; then
    echo "HTTP endpoint configured: $HTTP_ENDPOINT"
  fi
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

# New function to send metrics via HTTP POST
function send_http_metrics() {
    local metrics="$1"
    local node_id="$2"
    local status="$3"  # "success" or "failed"
    
    if [ -z "$HTTP_ENDPOINT" ]; then
        return 0
    fi
    
    if [ "${VERB}" -eq 1 ]; then
        echo "Sending metrics for node $node_id via HTTP ($status)"
    fi
    
    # Create temporary file for metrics
    local temp_file=$(mktemp)
    echo "$metrics" > "$temp_file"
    
    # Build curl command
    local curl_cmd="$CURL -X POST"
    curl_cmd="$curl_cmd --max-time $HTTP_TIMEOUT"
    curl_cmd="$curl_cmd --data-binary @$temp_file"
    curl_cmd="$curl_cmd --header 'Content-Type: text/plain; version=0.0.4; charset=utf-8'"
    
    # Add custom headers if specified
    if [ ! -z "$HTTP_HEADERS" ]; then
        curl_cmd="$curl_cmd $HTTP_HEADERS"
    fi
    
    # Add URL
    curl_cmd="$curl_cmd \"$HTTP_ENDPOINT\""
    
    # Execute curl command
    if [ "${VERB}" -eq 1 ]; then
        echo "Executing: $curl_cmd"
        eval $curl_cmd
        local curl_exit=$?
    else
        eval $curl_cmd >/dev/null 2>&1
        local curl_exit=$?
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    if [ $curl_exit -eq 0 ]; then
        if [ "${VERB}" -eq 1 ]; then
            echo "Successfully sent metrics for node $node_id"
        fi
    else
        echo "Warning: Failed to send metrics for node $node_id (curl exit code: $curl_exit)" >&2
    fi
    
    return $curl_exit
}

case "$TERM" in
    *dumb*) INTERACT=0;;
    *)      INTERACT=1;;
esac;

if [ ! -f $DEVFILE ]; then echo ${DEVFILE} " not found!"; exit 1; fi
if  [ "$MODE" == "serial" ] && [ ! -c $PORT ]; then echo ${PORT} " port not found!"; exit 1; fi
if [ ! -x $MESHTASTIC ]; then echo ${MESHTASTIC} " not found!"; exit 1; fi

function promnode() {

      arr=("$@")
      local node_metrics=""

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
      
      # Collect metrics for HTTP sending
      if [ ! -z "$HTTP_ENDPOINT" ]; then
        if [ -z "$node_metrics" ]; then
          node_metrics="$PNEX_OUTPUT"
        else
          node_metrics="$node_metrics"$'\n'"$PNEX_OUTPUT"
        fi
      fi
      
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
  
  # Return collected metrics for HTTP sending
  echo "$node_metrics"
}

function ocsv() {
  echo "Not developed yet."
  exit 1
}

case $MODE in
  serial) METHOD="--port";;
    ip) METHOD="--host";;
       :) echo "Option -$OPTARG requires an argument." >&2;exit 1;;
    \?) echo "Invalid option: -$OPTARG"; usage >&2;exit 1;;
esac;
  
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
    array+=( $(${MESHTASTIC} $METHOD $PORT --request-telemetry --dest $NODE | grep -ahE "${GREPARGS}") );
      if [ "${VERB}" -eq 1 ]; then
        echo "${MESHTASTIC} $METHOD $PORT --request-telemetry --dest $NODE"
      fi
      
    local collection_success=0
  if [ ! -z "${array[2]}" ]; then
      (( count++ ))
      collection_success=1
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
  
  local node_metrics=""
      case $FORMAT in
        node_exporter) node_metrics=$(promnode "${array[@]}");;
                *) echo "Invalid option: -c $FORMAT"; usage >&2;exit 1;;
    esac;
    
  # Send metrics via HTTP if endpoint is configured
  if [ ! -z "$HTTP_ENDPOINT" ] && [ ! -z "$node_metrics" ]; then
    if [ $collection_success -eq 1 ]; then
      send_http_metrics "$node_metrics" "$NODE" "success"
    else
      send_http_metrics "$node_metrics" "$NODE" "failed"
    fi
  fi
    
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
