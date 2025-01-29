#!/bin/sh
echo "$0" "$@"
progdir="$(dirname "$0")"
cd "$progdir" || exit 1
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$progdir/lib"
echo 1 >/tmp/stay_awake
trap "rm -f /tmp/stay_awake" EXIT INT TERM HUP QUIT
BUTTON_LOG="$progdir/log/buttons.log"

if uname -m | grep -q '64'; then
    SERVICE_NAME="syncthing-arm64"
else
    SERVICE_NAME="syncthing-arm"
fi
HUMAN_READABLE_NAME="Syncthing"
ONLY_LAUNCH_THEN_EXIT=0
LAUNCHES_SCRIPT="false"
service_on() {
    cd "$SDCARD_PATH" || exit 1
    if [ -f "$progdir/log/service.log" ]; then
        mv "$progdir/log/service.log" "$progdir/log/service.log.old"
    fi

    chmod +x "$progdir/bin/$SERVICE_NAME"

    if [ ! -f "$progdir/config/config.xml" ]; then
        show_message "Generating configuration for $HUMAN_READABLE_NAME" forever
        mkdir -p "$progdir/config"
        "$progdir/bin/$SERVICE_NAME" generate --no-default-folder "--home=$progdir/config/" >"$progdir/log/generate.log" 2>&1 &
        max_counter="30"
        counter=0

        while ! is_service_running; do
            counter=$((counter + 1))
            if [ "$counter" -gt "$max_counter" ]; then
                return 1
            fi
            sleep 1
        done
    fi

    sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|g" "$progdir/config/config.xml"

    show_message "Running $HUMAN_READABLE_NAME" forever
    ("$progdir/bin/$SERVICE_NAME" serve "--home=$progdir/config/" >"$progdir/log/service.log" &) &
}

service_off() {
    killall "$SERVICE_NAME"
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall sdl2imgshow
    echo "$message"
    if [ "$seconds" = "forever" ]; then
        "$progdir/bin/sdl2imgshow" \
            -i "$progdir/res/background.png" \
            -f "$progdir/res/fonts/BPreplayBold.otf" \
            -s 27 \
            -c "220,220,220" \
            -q \
            -t "$message" &
    else
        "$progdir/bin/sdl2imgshow" \
            -i "$progdir/res/background.png" \
            -f "$progdir/res/fonts/BPreplayBold.otf" \
            -s 27 \
            -c "220,220,220" \
            -q \
            -t "$message"
        sleep "$seconds"
    fi
}

monitor_buttons() {
    if [ -f "$BUTTON_LOG" ]; then
        mv "$BUTTON_LOG" "$BUTTON_LOG.old"
    fi
    touch "$BUTTON_LOG"

    chmod +x "$progdir/bin/evtest"
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        "$progdir/bin/evtest" "$dev" 2>&1 | while read -r line; do
            if echo "$line" | grep -q "code 17 (ABS_HAT0Y).*value -1"; then
                echo "D_PAD_UP detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 17 (ABS_HAT0Y).*value 1"; then
                echo "D_PAD_DOWN detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 16 (ABS_HAT0X).*value 1"; then
                echo "D_PAD_RIGHT detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 16 (ABS_HAT0X).*value -1"; then
                echo "D_PAD_LEFT detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 308 (BTN_WEST).*value 1"; then
                echo "BUTTON_X detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 305 (BTN_EAST).*value 1"; then
                echo "BUTTON_A detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 304 (BTN_SOUTH).*value 1"; then
                echo "BUTTON_B detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 307 (BTN_NORTH).*value 1"; then
                echo "BUTTON_Y detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 317 (BTN_THUMBL).*value 1"; then
                echo "HOTKEY_1 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 318 (BTN_THUMBR).*value 1"; then
                echo "HOTKEY_2 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 310 (BTN_TL).*value 1"; then
                echo "L1 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 311 (BTN_TR).*value 1"; then
                echo "R1 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 2 (ABS_Z).*value 255"; then
                echo "L2 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 5 (ABS_RZ).*value 255"; then
                echo "R2 detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 316 (BTN_MODE).*value 1"; then
                echo "MENU detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 314 (BTN_SELECT).*value 1"; then
                echo "SELECT detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 315 (BTN_START).*value 1"; then
                echo "START detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 115 (KEY_VOLUMEUP).*value 1"; then
                echo "VOLUME_UP detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 114 (KEY_VOLUMEDOWN).*value 1"; then
                echo "VOLUME_DOWN detected" >>"$BUTTON_LOG"
            elif echo "$line" | grep -q "code 116 (KEY_POWER).*value 1"; then
                echo "POWER detected" >>"$BUTTON_LOG"
            fi
        done &
    done
}

wait_for_button() {
    button="$1"
    while true; do
        if grep -q "$button" "$BUTTON_LOG"; then
            break
        fi
        sleep 0.1
    done
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

main_daemonize() {
    echo "Toggling $SERVICE_NAME..."
    if is_service_running; then
        show_message "Disabling the $HUMAN_READABLE_NAME" 2
        service_off
    else
        show_message "Enabling the $HUMAN_READABLE_NAME" 2
        service_on

        if ! wait_for_service 10; then
            show_message "Failed to start $HUMAN_READABLE_NAME" 2
            return 1
        fi
    fi

    show_message "Done" 1
}

main_process() {
    if is_service_running; then
        show_message "Disabling the $HUMAN_READABLE_NAME" 2
        service_off
    fi

    show_message "Starting $HUMAN_READABLE_NAME" 2
    service_on
    sleep 1

    echo "Waiting for $HUMAN_READABLE_NAME to be running"
    if ! wait_for_service 10; then
        show_message "Failed to start $HUMAN_READABLE_NAME" 2
        return 1
    fi

    show_message "Press B to exit"
    monitor_buttons

    wait_for_button "BUTTON_B"
    show_message "Stopping $HUMAN_READABLE_NAME"
    service_off
    killall evtest
    sync
    sleep 1
    show_message "Done" 1
}

main() {
    if [ "$ONLY_LAUNCH_THEN_EXIT" -eq 1 ]; then
        service_on
        return $?
    fi

    if [ -f "$progdir/daemon-mode" ]; then
        main_daemonize
    else
        main_process
    fi
    killall sdl2imgshow
}

mkdir -p "$progdir/log"
if [ -f "$progdir/log/launch.log" ]; then
    mv "$progdir/log/launch.log" "$progdir/log/launch.log.old"
fi

main "$@" >"$progdir/log/launch.log" 2>&1
