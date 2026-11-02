#!/usr/bin/env bats

load test_helper

# The library reads and writes one file. Point it at the test's own temporary
# directory so nothing touches a real card layout, and so the suite needs no
# USERDATA_PATH.
setup() {
    export SYNCTHING_VERSION_FILE="$BATS_TEST_TMPDIR/state/version"
    # shellcheck source=bin/syncthing-version.sh
    . "$REPO_ROOT/bin/syncthing-version.sh"
}

@test "with nothing selected yet the pak runs Syncthing 2.x" {
    [ ! -f "$SYNCTHING_VERSION_FILE" ]
    [ "$(syncthing_selected_version)" = 2 ]
}

@test "a selection of 1 is honoured" {
    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")"
    echo 1 >"$SYNCTHING_VERSION_FILE"
    [ "$(syncthing_selected_version)" = 1 ]
}

@test "a selection of 2 is honoured" {
    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")"
    echo 2 >"$SYNCTHING_VERSION_FILE"
    [ "$(syncthing_selected_version)" = 2 ]
}

# A half-written file is the realistic failure here: the card is removable and
# these devices lose power abruptly. Falling back to 2.x keeps the service
# starting rather than leaving it unable to choose.
@test "an unrecognised selection falls back to 2.x" {
    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")"
    printf 'banana' >"$SYNCTHING_VERSION_FILE"
    [ "$(syncthing_selected_version)" = 2 ]
}

@test "an empty selection falls back to 2.x" {
    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")"
    : >"$SYNCTHING_VERSION_FILE"
    [ "$(syncthing_selected_version)" = 2 ]
}

@test "an unreadable selection falls back to 2.x" {
    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")"
    echo 1 >"$SYNCTHING_VERSION_FILE"
    chmod 000 "$SYNCTHING_VERSION_FILE"
    # Root ignores the mode, so only assert where the read can actually fail.
    if [ -r "$SYNCTHING_VERSION_FILE" ]; then
        skip "running as root, the file is readable regardless of mode"
    fi
    [ "$(syncthing_selected_version)" = 2 ]
}

@test "selecting 1.x creates the directory and is read back" {
    [ ! -d "$(dirname "$SYNCTHING_VERSION_FILE")" ]
    run syncthing_set_version 1
    [ "$status" -eq 0 ]
    [ "$(cat "$SYNCTHING_VERSION_FILE")" = 1 ]
    [ "$(syncthing_selected_version)" = 1 ]
}

@test "a selection survives being changed back" {
    syncthing_set_version 1
    [ "$(syncthing_selected_version)" = 1 ]
    syncthing_set_version 2
    [ "$(syncthing_selected_version)" = 2 ]
}

@test "an unsupported version is refused and nothing is written" {
    run syncthing_set_version 3
    [ "$status" -ne 0 ]
    [ ! -f "$SYNCTHING_VERSION_FILE" ]
}

@test "an empty version is refused" {
    run syncthing_set_version ""
    [ "$status" -ne 0 ]
    [ ! -f "$SYNCTHING_VERSION_FILE" ]
}

# The settings file drives the pak's menu, and launch.sh reads the version from
# a fixed index, so a reordering there would silently move the wrong setting.
@test "the version is the third setting, where launch.sh looks for it" {
    run jq -r '.settings[2].name' "$REPO_ROOT/settings.json"
    [ "$status" -eq 0 ]
    [ "$output" = "Syncthing version" ]
    run jq -r '.settings[2].options[0]' "$REPO_ROOT/settings.json"
    [ "$output" = "2.x" ]
    run jq -r '.settings[2].options[1]' "$REPO_ROOT/settings.json"
    [ "$output" = "1.x" ]
}

# The 1.x build must sit in its own directory rather than being renamed, or
# service-off's killall, which matches process names exactly, stops working.
@test "the release ships the 1.x binary under its own directory" {
    run grep -qx "bin/v1/arm/syncthing" "$REPO_ROOT/.gitarchiveinclude"
    [ "$status" -eq 0 ]
    run grep -qx "bin/v1/arm64/syncthing" "$REPO_ROOT/.gitarchiveinclude"
    [ "$status" -eq 0 ]
}
