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

if [ "$DEVICE" = "rgsp" ]; then
    export RGXX_MODEL="RG34xx"
fi

SERVICE_NAME="syncthing"
HUMAN_READABLE_NAME="Syncthing"
LAUNCHES_SCRIPT="false"
NETWORK_PORT=8384
NETWORK_SCHEME="http"

# shellcheck source=bin/syncthing-version.sh
. "$PAK_DIR/bin/syncthing-version.sh"

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

# A failure worth reading. Waits for a button instead of flashing past, and
# names the folder holding the logs: launch.sh sends everything it and the
# service scripts print there, so it is the right place to look for any of
# these. Two seconds was not long enough to read a message, let alone act on it.
show_error() {
    message="$1"

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    minui-presenter --message "$message\nLog: .userdata/$PLATFORM/logs" \
        --timeout 0 --confirm-show --confirm-text "OK"
}

# A blocking question. Returns 0 only when the user explicitly confirms, so
# cancelling and the dialog failing both read as "no".
confirm_message() {
    message="$1"

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    # A timeout of 0 waits for a button and keeps the screen awake. B is acted
    # on whether it is drawn or not, so draw it and label what it does.
    minui-presenter --message "$message" --timeout 0 \
        --confirm-show --confirm-text "CONTINUE" \
        --cancel-show --cancel-text "CANCEL"
}

# What the user is agreeing to differs by direction, so only ask where there is
# something worth saying.
confirm_version_switch() {
    if [ "$1" = "1" ]; then
        confirm_message "Use Syncthing 1.x?\nRebuilds the index (slow).\nNo longer updated."
        return $?
    fi

    # Going back to 2.x is choosing a version that is known to fail here.
    if [ "$PLATFORM" = "h700" ]; then
        confirm_message "Use Syncthing 2.x?\nHas disk errors on h700."
        return $?
    fi

    # Elsewhere there is nothing to warn about: 2.x is the default, and it
    # migrates the 1.x index itself in about a second.
    return 0
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

wait_for_service() {
    max_counter="$1"
    counter=0

    while ! service-is-running; do
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

    while service-is-running; do
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
    if service-is-running; then
        jq '.settings[0].selected = 1' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    if will_start_on_boot; then
        jq '.settings[1].selected = 1' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    if [ "$(syncthing_selected_version)" = 1 ]; then
        jq '.settings[2].selected = 1' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    cat "$minui_list_file"
}

main_screen() {
    settings="$1"
    minui_list_file="/tmp/${PAK_NAME}-minui-list.json"
    minui_list_write_location="/tmp/${PAK_NAME}-minui-list-write-location.out"
    rm -f "$minui_list_file"

    echo "$settings" >"$minui_list_file"

    # Syncthing 2.x cannot keep its SQLite index on a FAT card and reports disk
    # I/O errors continuously on this platform, dropping peer connections as it
    # goes; 1.x is unaffected. h700 is the only platform where the errors are
    # confirmed, so the note is not shown anywhere else, and it sits next to the
    # setting that resolves it rather than interrupting with a dialog.
    if [ "$PLATFORM" = "h700" ] && [ "$(syncthing_selected_version)" = 2 ]; then
        jq '.settings[.settings | length] |= . + {"name": "Note", "options": ["2.x has bugs on h700"], "selected": 0, "features": {"unselectable": true}}' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"
    fi

    if service-is-running; then
        service_pid="$(get_service_pid)"
        jq --arg pid "$service_pid" '.settings[.settings | length] |= . + {"name": "PID", "options": [$pid], "selected": 0, "features": {"unselectable": true}}' "$minui_list_file" >"$minui_list_file.tmp"
        mv "$minui_list_file.tmp" "$minui_list_file"

        ip_address="$(get_ip_address)"
        if [ -n "$ip_address" ]; then
            jq --arg ip "$ip_address" '.settings[.settings | length] |= . + {"name": "Address", "options": [$ip], "selected": 0, "features": {"unselectable": true}}' "$minui_list_file" >"$minui_list_file.tmp"
            mv "$minui_list_file.tmp" "$minui_list_file"
        fi
    fi

    minui-list --disable-auto-sleep --file "$minui_list_file" --format json --title "$HUMAN_READABLE_NAME" --confirm-text "SAVE" --item-key "settings" --write-value state --write-location "$minui_list_write_location" >/dev/null
    exit_code=$?
    cat "$minui_list_write_location"
    return $exit_code
}

cleanup() {
    rm -f "/tmp/${PAK_NAME}-old-settings.json"
    rm -f "/tmp/${PAK_NAME}-new-settings.json"
    rm -f "/tmp/${PAK_NAME}-settings.json"
    rm -f "/tmp/${PAK_NAME}-minui-list.json"
    rm -f "/tmp/${PAK_NAME}-minui-list-write-location.out"
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

    allowed_platforms="h700 miyoomini my282 my355 rg35xxplus tg5040 tg5050"
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
    chmod +x "$PAK_DIR/bin/v1/$architecture/$SERVICE_NAME"
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

    if [ "$PLATFORM" = "h700" ] && [ "$DEVICE" = "rg28xx" ]; then
        show_message "Wifi not supported on RG28XX" 2
        return 1
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
                    show_error "Could not start $HUMAN_READABLE_NAME."
                    continue
                fi

                show_message "Waiting for $HUMAN_READABLE_NAME to be running" forever
                if ! wait_for_service 10; then
                    show_error "$HUMAN_READABLE_NAME did not come up."
                fi
                killall minui-presenter >/dev/null 2>&1 || true
            else
                show_message "Disabling $HUMAN_READABLE_NAME" 2
                if ! service-off; then
                    show_error "Could not stop $HUMAN_READABLE_NAME."
                fi

                show_message "Waiting for $HUMAN_READABLE_NAME to stop" forever
                if ! wait_for_service_to_stop 10; then
                    show_error "$HUMAN_READABLE_NAME did not stop."
                fi
                killall minui-presenter >/dev/null 2>&1 || true
            fi
        fi

        old_version="$(jq -rM '.settings[2].selected' "/tmp/${PAK_NAME}-old-settings.json")"
        version="$(jq -rM '.settings[2].selected' "/tmp/${PAK_NAME}-new-settings.json")"

        if [ "$old_version" != "$version" ]; then
            if ! confirm_version_switch "$version"; then
                # Leave the stored choice alone. The loop redraws from
                # current_settings, so the row returns to what is running.
                continue
            fi

            if [ "$version" = "1" ]; then
                syncthing_set_version 1
            else
                syncthing_set_version 2
            fi

            # The two store their indexes in different formats, so whichever is
            # selected now has to build its own. Restart rather than waiting for
            # the next boot, so the setting matches what is actually running.
            if service-is-running; then
                show_message "Switching $HUMAN_READABLE_NAME version" 2
                if ! service-off; then
                    show_error "$HUMAN_READABLE_NAME did not stop."
                fi
                wait_for_service_to_stop 10

                if ! service-on; then
                    show_error "Could not start $HUMAN_READABLE_NAME."
                    continue
                fi

                show_message "Waiting for $HUMAN_READABLE_NAME to be running" forever
                if ! wait_for_service 10; then
                    show_error "$HUMAN_READABLE_NAME did not come up."
                fi
                killall minui-presenter >/dev/null 2>&1 || true
            fi
        fi

        if [ "$old_start_on_boot" != "$start_on_boot" ]; then
            if [ "$start_on_boot" = "1" ]; then
                show_message "Enabling start on boot" 2
                if ! enable_start_on_boot; then
                    show_error "Could not enable start on boot."
                fi
            else
                show_message "Disabling start on boot" 2
                if ! disable_start_on_boot; then
                    show_error "Could not disable start on boot."
                fi
            fi
        fi
    done
}

main "$@"
