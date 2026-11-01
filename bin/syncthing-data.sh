#!/bin/sh
# shellcheck shell=sh
#
# Provisions a filesystem for Syncthing's database.
#
# Syncthing 2.x keeps its index in SQLite, which needs a filesystem that can
# host a write-ahead log and its "-shm" shared-memory file. MinUI and NextUI
# require the card to be exFAT or FAT32, and neither can provide coherent
# shared memory, so WAL checkpointing never completes. Index writes then fail
# with "disk I/O error: input/output error", dropping every peer connection
# roughly every seven seconds. Syncthing 1.x used LevelDB and had no such
# requirement, so this only affects 2.x.
#
# The database goes on a small ext4 image, loop-mounted from the card. Only the
# database moves: configuration, certificates and the device key stay on the
# card, so the device ID survives and peers need no re-approval.
#
# Where no filesystem can be provisioned the database stays on the card, which
# is what --home did, so such a platform behaves exactly as it does today
# rather than failing to start.
#
# The mount is deliberately left in place when Syncthing stops. It is reused on
# the next start and goes away on reboot; ext4 is journalled, which is why it
# was chosen, so a clean unmount buys little on a device that is normally
# switched off abruptly.

# Overridable so the test suite can point them at a temporary directory.
SYNCTHING_CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-$USERDATA_PATH/Syncthing/config}"
SYNCTHING_DATA_DIR="${SYNCTHING_DATA_DIR:-/tmp/Syncthing-data}"
_SD_IMAGE="$USERDATA_PATH/Syncthing/data.ext4"

_sd_log() {
    echo "syncthing-data: $*"
}

# mountpoint compares device numbers rather than path strings. Matching the
# path against /proc/mounts would miss a mount recorded under a resolved
# symlink, and a missed match here means attaching the image to a second loop
# device and stacking another ext4 on top of the live one, which corrupts it.
_sd_is_mounted() {
    mountpoint -q "$SYNCTHING_DATA_DIR"
}

_sd_ensure_image() {
    [ -f "$_SD_IMAGE" ] && return 0

    if [ ! -f "$PAK_DIR/share/data.ext4.gz" ]; then
        _sd_log "no image template shipped with the pak"
        return 1
    fi

    _sd_log "creating database image at $_SD_IMAGE"
    mkdir -p "$(dirname "$_SD_IMAGE")" || return 1
    # Expand under a temporary name: a half-written image left behind by a
    # power-off must not be mistaken for a usable one on the next start.
    if ! gunzip -c "$PAK_DIR/share/data.ext4.gz" >"$_SD_IMAGE.tmp"; then
        _sd_log "could not expand the image template (card full?)"
        rm -f "$_SD_IMAGE.tmp"
        return 1
    fi
    sync
    mv "$_SD_IMAGE.tmp" "$_SD_IMAGE" || return 1
    sync
}

_sd_provision() {
    _sd_ensure_image || return 1

    # Belt and braces for the check above: if the image is already attached,
    # attaching it again would put a second ext4 on one backing file and
    # corrupt it. Keeping the database on the card is worse but not damaging.
    if losetup -a 2>/dev/null | grep -qF "$_SD_IMAGE"; then
        _sd_log "image is already attached to a loop device"
        return 1
    fi

    # Loop devices are contended: BaseOS on h700 already holds loop0 for
    # usr-lib.sqfs, so take whichever one is free.
    _sd_loop="$(losetup -f 2>/dev/null)"
    if [ -z "$_sd_loop" ] || ! losetup "$_sd_loop" "$_SD_IMAGE" 2>/dev/null; then
        _sd_log "no loop device available"
        return 1
    fi

    if ! mount -t ext4 -o noatime "$_sd_loop" "$SYNCTHING_DATA_DIR" 2>/dev/null; then
        _sd_log "could not mount $_SD_IMAGE"
        losetup -d "$_sd_loop" 2>/dev/null
        return 1
    fi
}

# A full image reports the same "disk I/O error" as a filesystem that cannot
# host the database at all, so say which it is. There is no resize2fs on these
# devices; the image has to be rebuilt at a larger DATA_IMAGE_SIZE.
_sd_warn_if_low_on_space() {
    _sd_free="$(df -k "$SYNCTHING_DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ -n "$_sd_free" ] && [ "$_sd_free" -lt 16384 ]; then
        _sd_log "only ${_sd_free}K free for the database; a full image reports disk I/O errors"
    fi
}

# Leaves SYNCTHING_DATA_DIR pointing at wherever the database should live.
syncthing_data_start() {
    mkdir -p "$SYNCTHING_DATA_DIR" 2>/dev/null

    if _sd_is_mounted || _sd_provision; then
        _sd_log "database on ext4 image"
        _sd_warn_if_low_on_space
        return 0
    fi

    # --config and --data pointing at one directory is what --home did, so a
    # platform that cannot provision a filesystem keeps its current behaviour.
    _sd_log "keeping the database on the card; expect SQLite errors on exFAT"
    SYNCTHING_DATA_DIR="$SYNCTHING_CONFIG_DIR"
}
