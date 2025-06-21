#!/bin/bash
# Control script for Meshtastic Telemetry Daemon

DAEMON_NAME="meshmetricsd"
CONFIG_FILE="/etc/meshtastic-telemetry/meshmetricsd.conf"
STATS_FILE="/var/lib/meshtastic-telemetry/stats.json"

# Detect init system
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif [ -f /sbin/openrc-run ]; then
    INIT_SYSTEM="openrc"
else
    echo "Error: Unsupported init system"
    exit 1
fi

show_usage() {
    cat << EOF
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
            rc-service $DAEMON_NAME reload
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
    local follow=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--follow)
                follow=true
                shift
                ;;
            -n|--lines)
                lines="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    case $INIT_SYSTEM in
        systemd)
            if $follow; then
                journalctl -u $DAEMON_NAME.service -f
            else
                journalctl -u $DAEMON_NAME.service -n $lines
            fi
            ;;
        openrc)
            local logfile="/var/log/meshtastic-telemetry.log"
            if $follow; then
                tail -f "$logfile"
            else
                tail -n $lines "$logfile"
            fi
            ;;
    esac
}

show_stats() {
    if [ -f "$STATS_FILE" ]; then
        echo "Daemon Statistics:"
        python3 -m json.tool "$STATS_FILE"
    else
        echo "Statistics file not found: $STATS_FILE"
        echo "Make sure the daemon is running and stats are enabled in config"
    fi
}

test_config() {
    echo "Testing configuration..."
    meshtastic-telemetry-daemon -c "$CONFIG_FILE" --test-config
}

list_devices() {
    echo "Configured devices:"
    if [ -f "$CONFIG_FILE" ]; then
        # Extract device file path from config
        local device_file=$(grep -E "^file\s*=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        if [ -f "$device_file" ]; then
            echo "Device file: $device_file"
            echo
            grep -v "^#" "$device_file" | grep -v "^$" | while IFS=, read -r node_id contact location lat lon; do
                printf "%-12s %-20s %-30s %-12s %s\n" "$node_id" "$contact" "$location" "$lat" "$lon"
            done
        else
            echo "Device file not found: $device_file"
        fi
    else
        echo "Configuration file not found: $CONFIG_FILE"
    fi
}

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
    *)
        show_usage
        exit 1
        ;;
esac