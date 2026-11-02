#!/bin/sh
# shellcheck shell=sh
#
# Which Syncthing the pak runs.
#
# Syncthing 2.x keeps its index in SQLite. MinUI and NextUI require the card to
# be exFAT or FAT32, and SQLite's WAL mode needs a shared-memory file with
# coherent mmap, which FAT cannot provide, so a checkpoint never completes. On
# h700 that escalates to "disk I/O error: input/output error" roughly twenty
# times a minute, each one taking a peer connection down with it. Syncthing 1.x
# kept its index in LevelDB and is unaffected, so which one runs is a setting
# rather than a fixed choice.
#
# The selection lives under $USERDATA_PATH because that survives a pak update,
# whereas $PAK_DIR is replaced wholesale by one.

# Overridable so the test suite can point it at a temporary file.
SYNCTHING_VERSION_FILE="${SYNCTHING_VERSION_FILE:-$USERDATA_PATH/Syncthing/version}"

# 2 is the default, both because it is what the pak has always shipped and
# because an unreadable, empty or unrecognised file must never be the reason
# the service fails to start.
syncthing_selected_version() {
    case "$(cat "$SYNCTHING_VERSION_FILE" 2>/dev/null)" in
        1) echo 1 ;;
        *) echo 2 ;;
    esac
}

syncthing_set_version() {
    case "$1" in
        1 | 2) ;;
        *) return 1 ;;
    esac

    mkdir -p "$(dirname "$SYNCTHING_VERSION_FILE")" || return 1
    echo "$1" >"$SYNCTHING_VERSION_FILE" || return 1
    # The card is removable and these devices are powered off abruptly, so the
    # choice is flushed rather than left to the page cache.
    sync
}
