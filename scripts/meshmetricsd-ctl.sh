#!/bin/sh
# Control script for Meshtastic Telemetry Daemon
# Compatible with Alpine Linux (ash shell)

DAEMON_NAME="meshmetricsd"
CONFIG_FILE="/etc/meshtastic-telemetry/meshmetricsd.conf"
STATS_FILE="/var/lib/meshtastic-telemetry/stats.json"

# Detect init system
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif [ -f /sbin/openrc-run ] || [ -f /sbin/rc-service ]; then
    INIT_SYSTEM="openrc"
else
    echo "Error: Unsupported init system"
    exit 1
fi

show_usage() {
    cat << 'EOF'
Usage: $0 COMMAND [OPTIONS]

Commands:
    start           Start the daemon
    stop            Stop the daemon
    restart         Restart the daemon
    reload          Reload configuration
    status          Show daemon status
    enable          Enable daemon to start at boot
    disable         Disable daemon from starting at boot
    logs            Show daemon logs
    stats           Show daemon statistics
    test-config     Test configuration
    list-devices    List configured devices

Options:
    -f, --follow    Follow logs (for logs command)
    -n, --lines N   Show last N lines (for logs command, default: 50)
EOF
}

daemon_start() {
    echo "Starting $DAEMON_NAME..."
    case $INIT_SYSTEM in
        systemd)
            systemctl start $DAEMON_NAME.service
            ;;
        openrc)
            rc-service $DAEMON_NAME start
            ;;
    esac
}

daemon_stop() {
    echo "Stopping $DAEMON_NAME..."
    case $INIT_SYSTEM in
        systemd)
            systemctl stop $DAEMON_NAME.service
            ;;
        openrc)
            rc-service $DAEMON_NAME stop
            ;;
    esac
}

daemon_restart() {
    echo "Restarting $DAEMON_NAME..."
    case $INIT_SYSTEM in
        systemd)
            systemctl restart $DAEMON_NAME.service
            ;;
        openrc)
            rc-service $DAEMON_NAME restart
            ;;
    esac
}

daemon_reload() {
    echo "Reloading $DAEMON_NAME configuration..."
    case $INIT_SYSTEM in
        systemd)
            systemctl reload $DAEMON_NAME.service
            ;;
        openrc)
            # OpenRC doesn't have a standard reload, try to send SIGHUP
            if [ -f "/var/run/$DAEMON_NAME.pid" ]; then
                kill -HUP "$(cat /var/run/$DAEMON_NAME.pid)" 2>/dev/null || {
                    echo "Failed to reload, trying restart..."
                    rc-service $DAEMON_NAME restart
                }
            else
                echo "PID file not found, trying restart..."
                rc-service $DAEMON_NAME restart
            fi
            ;;
    esac
}

daemon_status() {
    case $INIT_SYSTEM in
        systemd)
            systemctl status $DAEMON_NAME.service
            ;;
        openrc)
            rc-service $DAEMON_NAME status
            ;;
    esac
}

daemon_enable() {
    echo "Enabling $DAEMON_NAME to start at boot..."
    case $INIT_SYSTEM in
        systemd)
            systemctl enable $DAEMON_NAME.service
            ;;
        openrc)
            rc-update add $DAEMON_NAME default
            ;;
    esac
}

daemon_disable() {
    echo "Disabling $DAEMON_NAME from starting at boot..."
    case $INIT_SYSTEM in
        systemd)
            systemctl disable $DAEMON_NAME.service
            ;;
        openrc)
            rc-update del $DAEMON_NAME default
            ;;
    esac
}

show_logs() {
    local lines=50
    local follow=0
    
    # Parse arguments (ash-compatible)
    while [ $# -gt 0 ]; do
        case $1 in
            -f|--follow)
                follow=1
                shift
                ;;
            -n|--lines)
                if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
                    lines="$2"
                    shift 2
                else
                    echo "Error: --lines requires a numeric argument"
                    exit 1
                fi
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    case $INIT_SYSTEM in
        systemd)
            if [ "$follow" = "1" ]; then
                journalctl -u $DAEMON_NAME.service -f
            else
                journalctl -u $DAEMON_NAME.service -n $lines
            fi
            ;;
        openrc)
            local logfile="/var/log/meshtastic-telemetry.log"
            if [ -f "$logfile" ]; then
                if [ "$follow" = "1" ]; then
                    tail -f "$logfile"
                else
                    tail -n $lines "$logfile"
                fi
            else
                echo "Log file not found: $logfile"
                echo "Check if logging is enabled in the daemon configuration"
            fi
            ;;
    esac
}

show_stats() {
    if [ -f "$STATS_FILE" ]; then
        echo "Daemon Statistics:"
        # Try different JSON tools available on Alpine
        if command -v jq >/dev/null 2>&1; then
            jq . "$STATS_FILE"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m json.tool "$STATS_FILE"
        elif command -v python >/dev/null 2>&1; then
            python -m json.tool "$STATS_FILE"
        else
            echo "JSON formatting tool not found, showing raw content:"
            cat "$STATS_FILE"
        fi
    else
        echo "Statistics file not found: $STATS_FILE"
        echo "Make sure the daemon is running and stats are enabled in config"
    fi
}

test_config() {
    echo "Testing configuration..."
    if command -v meshmetricsd >/dev/null 2>&1; then
        meshmetricsd -c "$CONFIG_FILE" --test-config
    elif [ -x /usr/local/bin/meshmetricsd ]; then
        /usr/local/bin/meshmetricsd -c "$CONFIG_FILE" --test-config
    else
        echo "Error: meshmetricsd executable not found"
        echo "Make sure the daemon is properly installed"
        exit 1
    fi
}

list_devices() {
    echo "Configured devices:"
    if [ -f "$CONFIG_FILE" ]; then
        # Extract device file path from config (ash-compatible)
        local device_file
        device_file=$(grep -E "^file[[:space:]]*=" "$CONFIG_FILE" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -n "$device_file" ] && [ -f "$device_file" ]; then
            echo "Device file: $device_file"
            echo ""
            printf "%-12s %-20s %-30s %-12s %s\n" "NODE_ID" "CONTACT" "LOCATION" "LATITUDE" "LONGITUDE"
            printf "%-12s %-20s %-30s %-12s %s\n" "--------" "-------" "--------" "--------" "---------"
            
            # Read CSV file (ash-compatible)
            grep -v "^#" "$device_file" | grep -v "^$" | while IFS=, read -r node_id contact location lat lon; do
                # Remove leading/trailing whitespace
                node_id=$(echo "$node_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                contact=$(echo "$contact" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                location=$(echo "$location" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                lat=$(echo "$lat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                lon=$(echo "$lon" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                printf "%-12s %-20s %-30s %-12s %s\n" "$node_id" "$contact" "$location" "$lat" "$lon"
            done
        else
            echo "Device file not found or not specified: $device_file"
            echo "Check the 'file' setting in $CONFIG_FILE"
        fi
    else
        echo "Configuration file not found: $CONFIG_FILE"
    fi
}

# Validate command line arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

# Main command handling
case $1 in
    start)
        daemon_start
        ;;
    stop)
        daemon_stop
        ;;
    restart)
        daemon_restart
        ;;
    reload)
        daemon_reload
        ;;
    status)
        daemon_status
        ;;
    enable)
        daemon_enable
        ;;
    disable)
        daemon_disable
        ;;
    logs)
        shift
        show_logs "$@"
        ;;
    stats)
        show_stats
        ;;
    test-config)
        test_config
        ;;
    list-devices)
        list_devices
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac