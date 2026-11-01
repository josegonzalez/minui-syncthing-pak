#!/usr/bin/env bats

load test_helper

# bin/syncthing-data.sh provisions a filesystem for Syncthing's database.
# Mounting needs privileges a test run does not have, so mount, losetup, sync
# and df are stubbed on PATH; each records its arguments in $SD_CALLS and fails
# when the matching variable is set. Everything the library does to actual
# files is exercised for real.
#
# syncthing_data_start is mostly called without bats' `run`, because the
# fallback works by reassigning SYNCTHING_DATA_DIR and `run` would discard it.
setup() {
    SD_STUB="$BATS_TEST_TMPDIR/stub"
    SD_CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$SD_STUB"
    : >"$SD_CALLS"

    cat >"$SD_STUB/mount" <<'EOF'
#!/bin/bash
printf 'mount %s\n' "$*" >>"$SD_CALLS"
exit "${MOUNT_FAIL:-0}"
EOF
    cat >"$SD_STUB/losetup" <<'EOF'
#!/bin/bash
printf 'losetup %s\n' "$*" >>"$SD_CALLS"
if [ "$1" = "-a" ]; then
    [ -n "$ATTACHED" ] && echo "/dev/loop9: 0 $ATTACHED"
    exit 0
fi
if [ "$1" = "-f" ]; then
    [ -z "$NO_LOOP" ] && echo /dev/loop9
    exit 0
fi
exit "${LOSETUP_FAIL:-0}"
EOF
    printf '#!/bin/bash\nexit 0\n' >"$SD_STUB/sync"
    # Nothing is mounted unless a test sets MOUNTED.
    printf '#!/bin/bash\n[ -n "$MOUNTED" ]\n' >"$SD_STUB/mountpoint"
    chmod +x "$SD_STUB"/*

    PATH="$SD_STUB:$PATH"
    USERDATA_PATH="$BATS_TEST_TMPDIR/userdata"
    PAK_DIR="$BATS_TEST_TMPDIR/pak"
    SYNCTHING_DATA_DIR="$BATS_TEST_TMPDIR/data"
    mkdir -p "$USERDATA_PATH/Syncthing" "$PAK_DIR/share"
    export PATH SD_CALLS USERDATA_PATH PAK_DIR SYNCTHING_DATA_DIR

    # Stands in for the empty ext4 image built by `make share/data.ext4.gz`.
    # Nothing here mounts it, so its contents are irrelevant.
    printf 'filesystem' | gzip >"$PAK_DIR/share/data.ext4.gz"

    IMAGE="$USERDATA_PATH/Syncthing/data.ext4"
    ON_CARD="$USERDATA_PATH/Syncthing/config"
}

lib() {
    # shellcheck source=bin/syncthing-data.sh
    . "$REPO_ROOT/bin/syncthing-data.sh"
}

@test "the database image is created from the shipped template" {
    lib
    syncthing_data_start
    [ "$(cat "$IMAGE")" = "filesystem" ]
    [ ! -e "$IMAGE.tmp" ]
}

@test "an existing image is reused rather than overwritten" {
    echo "my database" >"$IMAGE"
    lib
    syncthing_data_start
    [ "$(cat "$IMAGE")" = "my database" ]
}

@test "the image is loop-mounted and the database points into it" {
    lib
    syncthing_data_start
    grep -q "losetup /dev/loop9 $IMAGE" "$SD_CALLS"
    grep -q "mount -t ext4 -o noatime /dev/loop9 $SYNCTHING_DATA_DIR" "$SD_CALLS"
    [ "$SYNCTHING_DATA_DIR" != "$ON_CARD" ]
}

@test "an already-mounted data directory is reused, not mounted again" {
    MOUNTED=1
    export MOUNTED
    lib
    syncthing_data_start
    [ ! -s "$SD_CALLS" ]
    [ "$SYNCTHING_DATA_DIR" != "$ON_CARD" ]
}

@test "a template missing from the pak leaves the database on the card" {
    rm -f "$PAK_DIR/share/data.ext4.gz"
    lib
    syncthing_data_start
    [ ! -e "$IMAGE" ]
    [ "$SYNCTHING_DATA_DIR" = "$ON_CARD" ]
}

@test "a truncated template leaves no partial image behind" {
    printf 'not gzip at all' >"$PAK_DIR/share/data.ext4.gz"
    lib
    syncthing_data_start
    [ ! -e "$IMAGE" ]
    [ ! -e "$IMAGE.tmp" ]
    [ "$SYNCTHING_DATA_DIR" = "$ON_CARD" ]
}

@test "no free loop device leaves the database on the card" {
    NO_LOOP=1
    export NO_LOOP
    lib
    syncthing_data_start
    [ "$SYNCTHING_DATA_DIR" = "$ON_CARD" ]
}

@test "a mount failure releases the loop device it attached" {
    MOUNT_FAIL=1
    export MOUNT_FAIL
    lib
    syncthing_data_start
    grep -q "losetup -d /dev/loop9" "$SD_CALLS"
    [ "$SYNCTHING_DATA_DIR" = "$ON_CARD" ]
}

@test "falling back to the card says so, because it still hits the bug" {
    rm -f "$PAK_DIR/share/data.ext4.gz"
    lib
    run syncthing_data_start
    [[ "$output" == *"keeping the database on the card"* ]]
}

@test "a nearly full image is called out in the log" {
    # A full image produces the same error as a filesystem that cannot host the
    # database, so the log has to distinguish them.
    printf '#!/bin/bash\nprintf "Filesystem 1K-blocks Used Available\\n/dev/loop9 113000 100000 8192\\n"\n' >"$SD_STUB/df"
    chmod +x "$SD_STUB/df"
    lib
    run syncthing_data_start
    [[ "$output" == *"only 8192K free for the database"* ]]
}

@test "an image with room to spare says nothing about space" {
    printf '#!/bin/bash\nprintf "Filesystem 1K-blocks Used Available\\n/dev/loop9 113000 10000 102400\\n"\n' >"$SD_STUB/df"
    chmod +x "$SD_STUB/df"
    lib
    run syncthing_data_start
    [[ "$output" != *"free for the database"* ]]
}


@test "an image already attached to a loop device is not attached twice" {
    # Two ext4 instances on one backing file would corrupt it, so this must
    # hold even when the mount check has somehow missed an existing mount.
    ATTACHED="$IMAGE"
    export ATTACHED
    lib
    syncthing_data_start
    ! grep -q "^mount " "$SD_CALLS"
    [ "$SYNCTHING_DATA_DIR" = "$ON_CARD" ]
}
