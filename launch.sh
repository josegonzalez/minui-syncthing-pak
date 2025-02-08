#!/bin/sh
echo "$0" "$@"
progdir="$(dirname "$0")"
cd "$progdir" || exit 1
[ -f "$progdir/debug" ] && set -x
PAK_NAME="$(basename "$progdir")"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$progdir/lib"
echo 1 >/tmp/stay_awake

if uname -m | grep -q '64'; then
    SERVICE_NAME="syncthing-arm64"
else
    SERVICE_NAME="syncthing-arm"
fi
HUMAN_READABLE_NAME="Syncthing"
LAUNCHES_SCRIPT="false"
NETWORK_PORT=8384
NETWORK_SCHEME="http"
service_off() {
    killall "$SERVICE_NAME"
}

cleanup() {
    rm -f /tmp/stay_awake
    killall sdl2imgshow >/dev/null 2>&1 || true
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall sdl2imgshow >/dev/null 2>&1 || true
    echo "$message"
    if [ "$seconds" = "forever" ]; then
        "$progdir/bin/sdl2imgshow" \
            -i "$progdir/res/background.png" \
            -f "$progdir/res/fonts/BPreplayBold.otf" \
            -s 27 \
            -c "220,220,220" \
            -q \
            -t "$message" >/dev/null 2>&1 &
    else
        "$progdir/bin/sdl2imgshow" \
            -i "$progdir/res/background.png" \
            -f "$progdir/res/fonts/BPreplayBold.otf" \
            -s 27 \
            -c "220,220,220" \
            -q \
            -t "$message" >/dev/null 2>&1
        sleep "$seconds"
    fi
}

disable_start_on_boot() {
    sed -i "/${PAK_NAME}-on-boot/d" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    return 0
}

enable_start_on_boot() {
    if [ ! -f "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" ]; then
        echo '#!/bin/sh' >"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
        echo '' >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    fi

    echo "test -f \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME/bin/on-boot\" && \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME/bin/on-boot\" # ${PAK_NAME}-on-boot" >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    chmod +x "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    return 0
}

will_start_on_boot() {
    if grep -q "${PAK_NAME}-on-boot" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

is_service_running() {
    if pgrep "$SERVICE_NAME" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$LAUNCHES_SCRIPT" = "true" ]; then
        if pgrep -fn "$SERVICE_NAME" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

wait_for_service() {
    max_counter="$1"
    counter=0

    while ! is_service_running; do
        counter=$((counter + 1))
        if [ "$counter" -gt "$max_counter" ]; then
            return 1
        fi
        sleep 1
    done
}

wait_for_service_to_stop() {
    max_counter="$1"
    counter=0

    while is_service_running; do
        counter=$((counter + 1))
        if [ "$counter" -gt "$max_counter" ]; then
            return 1
        fi
        sleep 1
    done
}

get_ip_address() {
    if [ -z "$NETWORK_PORT" ]; then
        return
    fi

    enabled="$(cat /sys/class/net/wlan0/operstate)"
    if [ "$enabled" != "up" ]; then
        echo "Not connected to WiFi"
        return
    fi
    ip_address=""

    count=0
    while true; do
        count=$((count + 1))
        if [ "$count" -gt 5 ]; then
            break
        fi

        ip_address="$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)"
        if [ -n "$ip_address" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$ip_address" ]; then
        echo "Not connected to WiFi"
        return
    fi

    echo "$NETWORK_SCHEME://$ip_address:$NETWORK_PORT"
}

main_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file"
    touch "$minui_list_file"

    start_on_boot=false
    if will_start_on_boot; then
        start_on_boot=true
    fi

    echo "Enabled: false" >>"$minui_list_file"
    echo "Start on boot: $start_on_boot" >>"$minui_list_file"
    echo "Enable" >>"$minui_list_file"

    if is_service_running; then
        service_pid="$(pgrep "$SERVICE_NAME" 2>/dev/null | sort | head -n 1 || true)"
        ip_address="$(get_ip_address)"
        echo "Enabled: true (pid: $service_pid)" >"$minui_list_file"
        echo "Start on boot: $start_on_boot" >>"$minui_list_file"
        if [ -n "$ip_address" ]; then
            echo "Address: $ip_address" >>"$minui_list_file"
        fi
        echo "Disable" >>"$minui_list_file"
    fi

    if [ "$start_on_boot" = "true" ]; then
        echo "Disable start on boot" >>"$minui_list_file"
    else
        echo "Enable start on boot" >>"$minui_list_file"
    fi

    killall sdl2imgshow >/dev/null 2>&1 || true
    "$progdir/bin/minui-list-$PLATFORM" --file "$minui_list_file" --format text --header "$HUMAN_READABLE_NAME"
}

main() {
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export DEVICE="brick"
        export PLATFORM="tg5040"
    fi

    allowed_platforms="tg5040 rg35xxplus"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        show_message "$PLATFORM is not a supported platform" 2
        return 1
    fi

    if [ ! -f "$progdir/bin/minui-list-$PLATFORM" ]; then
        show_message "$progdir/bin/minui-list-$PLATFORM not found" 2
        return 1
    fi

    if ! cd "$progdir/bin"; then
        show_message "Failed to cd to $progdir/bin" 2
        return 1
    fi
    chmod +x *
    if ! cd "$progdir"; then
        show_message "Failed to cd to $progdir" 2
        return 1
    fi

    if [ "$PLATFORM" = "rg35xxplus" ]; then
        RGXX_MODEL="$(strings /mnt/vendor/bin/dmenu.bin | grep ^RG)"
        if [ "$RGXX_MODEL" = "RG28xx" ]; then
            show_message "Wifi not supported on RG28XX" 2
            return 1
        fi
    fi

    while true; do
        sync
        selection="$(main_screen)"
        exit_code=$?
        # exit codes: 2 = back button, 3 = menu button
        if [ "$exit_code" -ne 0 ]; then
            break
        fi

        if echo "$selection" | grep -q "^Enable$"; then
            show_message "Enabling $HUMAN_READABLE_NAME..." 1
            if ! "$progdir/bin/service-on"; then
                show_message "Failed to enable $HUMAN_READABLE_NAME!" 2
                continue
            fi

            show_message "Waiting for $HUMAN_READABLE_NAME to be running" forever
            if ! wait_for_service 10; then
                show_message "Failed to start $HUMAN_READABLE_NAME" 2
            fi
        elif echo "$selection" | grep -q "^Disable$"; then
            show_message "Disabling $HUMAN_READABLE_NAME..." 1
            if ! service_off; then
                show_message "Failed to disable $HUMAN_READABLE_NAME!" 2
            fi

            show_message "Waiting for $HUMAN_READABLE_NAME to stop" forever
            if ! wait_for_service_to_stop 10; then
                show_message "Failed to stop $HUMAN_READABLE_NAME" 2
            fi
        elif echo "$selection" | grep -q "^Enable start on boot$"; then
            show_message "Enabling start on boot..." 1
            if ! enable_start_on_boot; then
                show_message "Failed to enable start on boot!" 2
            fi
        elif echo "$selection" | grep -q "^Disable start on boot$"; then
            show_message "Disabling start on boot..." 1
            if ! disable_start_on_boot; then
                show_message "Failed to disable start on boot!" 2
            fi
        fi
    done
    sync
}

main "$@" >"$LOGS_PATH/$PAK_NAME.txt" 2>&1
