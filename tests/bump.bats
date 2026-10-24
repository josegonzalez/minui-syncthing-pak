#!/usr/bin/env bats

load test_helper

# A scratch copy of the Makefile the bump rewrites, so the repo is never
# touched. pak.json comes along because the Makefile reads it when parsed.
setup() {
    WORK="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$WORK"
    cp "$REPO_ROOT/Makefile" "$REPO_ROOT/pak.json" "$WORK/"
    BUMP="$REPO_ROOT/scripts/bump-syncthing.sh"
}

@test "a new release is pinned in the Makefile" {
    run "$BUMP" v9.8.7 "$WORK"
    [ "$status" -eq 0 ]
    mk SYNCTHING_VERSION "$WORK"
    [ "$output" = "v9.8.7" ]
}

@test "only the pin changes" {
    run "$BUMP" v9.8.7 "$WORK"
    [ "$status" -eq 0 ]
    run diff "$REPO_ROOT/Makefile" "$WORK/Makefile"
    [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 2 ]
    [[ "$output" == *"> SYNCTHING_VERSION ?= v9.8.7"* ]]
}

@test "bumping to the current pin changes nothing" {
    mk SYNCTHING_VERSION
    run "$BUMP" "$output" "$WORK"
    [ "$status" -eq 0 ]
    cmp "$REPO_ROOT/Makefile" "$WORK/Makefile"
}

@test "anything but a release tag is refused and nothing is written" {
    for bad in "" main v2.1 2.1.7 v2.1.7-rc.1; do
        run "$BUMP" "$bad" "$WORK"
        [ "$status" -ne 0 ] || return 1
        [[ "$output" == *"is not a release tag"* ]] || return 1
    done
    cmp "$REPO_ROOT/Makefile" "$WORK/Makefile"
}

@test "a Makefile that no longer pins SYNCTHING_VERSION fails the bump" {
    # Otherwise the substitution silently matches nothing and the old release
    # keeps shipping.
    sed 's/^SYNCTHING_VERSION ?=/SYNCTHING_VERSION :=/' "$REPO_ROOT/Makefile" >"$WORK/Makefile"
    run "$BUMP" v9.8.7 "$WORK"
    [ "$status" -ne 0 ]
    [[ "$output" == *"was not updated"* ]]
}

@test "the workflow pins and writes its messages through the scripts" {
    wf="$REPO_ROOT/.github/workflows/update-syncthing.yaml"
    [ -f "$wf" ]
    grep -q "scripts/bump-syncthing.sh" "$wf"
    grep -q "scripts/syncthing-pr-message.sh" "$wf"
    grep -q "print-SYNCTHING_VERSION" "$wf"
}
