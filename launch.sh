#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

architecture=arm
if uname -m | grep -q '64'; then
    architecture=arm64
fi

export HOME="$USERDATA_PATH/$PAK_NAME"
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"

SERVICE_NAME="syncthing"
HUMAN_READABLE_NAME="Syncthing"
LAUNCHES_SCRIPT="false"
NETWORK_PORT=8384
NETWORK_SCHEME="http"

service_off() {
    killall "$SERVICE_NAME"
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    if [ "$seconds" = "forever" ]; then
        minui-presenter --message "$message" --timeout -1 &
    else
        minui-presenter --message "$message" --timeout "$seconds"
    fi
}

disable_start_on_boot() {
    sed -i "/${PAK_NAME}.pak-on-boot/d" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    sync
    return 0
}

enable_start_on_boot() {
    if [ ! -f "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" ]; then
        echo '#!/bin/sh' >"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
        echo '' >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    fi

    echo "test -f \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME.pak/bin/on-boot\" && \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME.pak/bin/on-boot\" # ${PAK_NAME}.pak-on-boot" >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    chmod +x "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    sync
    return 0
}

will_start_on_boot() {
    if grep -q "${PAK_NAME}.pak-on-boot" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" >/dev/null 2>&1; then
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

get_service_pid() {
    if [ "$LAUNCHES_SCRIPT" = "true" ]; then
        pgrep -fn "$SERVICE_NAME" 2>/dev/null | sort | head -n 1 || true
    else
        pgrep "$SERVICE_NAME" 2>/dev/null | sort | head -n 1 || true
    fi
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

current_settings() {
    minui_list_file="/tmp/${PAK_NAME}-settings.json"
    rm -f "$minui_list_file"

    jq -rM '{settings: .settings}' "$PAK_DIR/settings.json" >"$minui_list_file"
    if is_service_running; then
        jq '.settings[0].selected = 1' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    if will_start_on_boot; then
        jq '.settings[1].selected = 1' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    cat "$minui_list_file"
}

main_screen() {
    settings="$1"
    minui_list_file="/tmp/${PAK_NAME}-minui-list.json"
    rm -f "$minui_list_file"

    echo "$settings" >"$minui_list_file"

    if is_service_running; then
        service_pid="$(get_service_pid)"
        jq --arg pid "$service_pid" '.settings[.settings | length] |= . + {"name": "PID", "options": [$pid], "selected": 0, "features": {"unselectable": true}}' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"

        ip_address="$(get_ip_address)"
        if [ -n "$ip_address" ]; then
            jq --arg ip "$ip_address" '.settings[.settings | length] |= . + {"name": "Address", "options": [$ip], "selected": 0, "features": {"unselectable": true}}' "$minui_list_file" >"$minui_list_file.tmp"
            mv "$minui_list_file.tmp" "$minui_list_file"
        fi
    fi

    minui-list --disable-auto-sleep --file "$minui_list_file" --format json --title "$HUMAN_READABLE_NAME" --confirm-text "SAVE" --item-key "settings" --write-value state
}

cleanup() {
    rm -f "/tmp/${PAK_NAME}-old-settings.json"
    rm -f "/tmp/${PAK_NAME}-new-settings.json"
    rm -f "/tmp/${PAK_NAME}-settings.json"
    rm -f "/tmp/${PAK_NAME}-minui-list.json"
    rm -f /tmp/stay_awake
    killall minui-presenter >/dev/null 2>&1 || true
}

main() {
    echo "1" >/tmp/stay_awake
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

    if ! command -v minui-list >/dev/null 2>&1; then
        show_message "minui-list not found" 2
        return 1
    fi

    if ! command -v minui-presenter >/dev/null 2>&1; then
        show_message "minui-presenter not found" 2
        return 1
    fi

    chmod +x "$PAK_DIR/bin/$architecture/$SERVICE_NAME"
    chmod +x "$PAK_DIR/bin/$architecture/jq"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-list"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-presenter"
    chmod +x "$PAK_DIR/bin/service-on"
    chmod +x "$PAK_DIR/bin/on-boot"

    if [ "$PLATFORM" = "rg35xxplus" ]; then
        RGXX_MODEL="$(strings /mnt/vendor/bin/dmenu.bin | grep ^RG)"
        if [ "$RGXX_MODEL" = "RG28xx" ]; then
            show_message "Wifi not supported on RG28XX" 2
            return 1
        fi
    fi

    while true; do
        settings="$(current_settings)"
        new_settings="$(main_screen "$settings")"
        exit_code=$?
        # exit codes: 2 = back button, 3 = menu button
        if [ "$exit_code" -ne 0 ]; then
            break
        fi

        echo "$settings" >"/tmp/${PAK_NAME}-old-settings.json"
        echo "$new_settings" >"/tmp/${PAK_NAME}-new-settings.json"

        old_enabled="$(jq -rM '.settings[0].selected' "/tmp/${PAK_NAME}-old-settings.json")"
        enabled="$(jq -rM '.settings[0].selected' "/tmp/${PAK_NAME}-new-settings.json")"

        old_start_on_boot="$(jq -rM '.settings[1].selected' "/tmp/${PAK_NAME}-old-settings.json")"
        start_on_boot="$(jq -rM '.settings[1].selected' "/tmp/${PAK_NAME}-new-settings.json")"

        if [ "$old_enabled" != "$enabled" ]; then
            if [ "$enabled" = "1" ]; then
                show_message "Enabling $HUMAN_READABLE_NAME" 2
                if ! service-on; then
                    show_message "Failed to enable $HUMAN_READABLE_NAME!" 2
                    continue
                fi

                show_message "Waiting for $HUMAN_READABLE_NAME to be running" forever
                if ! wait_for_service 10; then
                    show_message "Failed to start $HUMAN_READABLE_NAME" 2
                fi
                killall minui-presenter >/dev/null 2>&1 || true
            else
                show_message "Disabling $HUMAN_READABLE_NAME" 2
                if ! service_off; then
                    show_message "Failed to disable $HUMAN_READABLE_NAME!" 2
                fi

                show_message "Waiting for $HUMAN_READABLE_NAME to stop" forever
                if ! wait_for_service_to_stop 10; then
                    show_message "Failed to stop $HUMAN_READABLE_NAME" 2
                fi
                killall minui-presenter >/dev/null 2>&1 || true
            fi
        fi

        if [ "$old_start_on_boot" != "$start_on_boot" ]; then
            if [ "$start_on_boot" = "1" ]; then
                show_message "Enabling start on boot" 2
                if ! enable_start_on_boot; then
                    show_message "Failed to enable start on boot!" 2
                fi
            else
                show_message "Disabling start on boot" 2
                if ! disable_start_on_boot; then
                    show_message "Failed to disable start on boot!" 2
                fi
            fi
        fi
    done
}

main "$@"
