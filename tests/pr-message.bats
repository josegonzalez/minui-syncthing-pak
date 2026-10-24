#!/usr/bin/env bats

load test_helper

# A gh on PATH that answers from canned files instead of the GitHub API:
# $GH_STUB/tags for `gh release list` and $GH_STUB/notes/<tag> for
# `gh release view <tag>`.
setup() {
    GH_STUB="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$GH_STUB/bin" "$GH_STUB/notes"
    cat >"$GH_STUB/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "release list") cat "$GH_STUB/tags" ;;
    "release view") cat "$GH_STUB/notes/$3" ;;
    *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
    chmod +x "$GH_STUB/bin/gh"
    PATH="$GH_STUB/bin:$PATH"
    export GH_STUB PATH

    OUT="$BATS_TEST_TMPDIR/out"
    MESSAGE="$REPO_ROOT/scripts/syncthing-pr-message.sh"
}

# Canned releases: one tag per argument, each with notes naming its tag.
releases() {
    printf '%s\n' "$@" >"$GH_STUB/tags"
    for tag in "$@"; do
        printf 'Notes for %s\n' "$tag" >"$GH_STUB/notes/$tag"
    done
}

@test "the commit message matches dependabot's layout" {
    releases v2.1.7 v2.1.6 v2.1.5
    run "$MESSAGE" v2.1.5 v2.1.7 "$OUT"
    [ "$status" -eq 0 ]
    expected="$(
        cat <<'EOF'
chore(deps): bump syncthing/syncthing from 2.1.5 to 2.1.7

Bumps [syncthing/syncthing](https://github.com/syncthing/syncthing) from 2.1.5 to 2.1.7.
- [Release notes](https://github.com/syncthing/syncthing/releases)
- [Commits](https://github.com/syncthing/syncthing/compare/v2.1.5...v2.1.7)

---
updated-dependencies:
- dependency-name: syncthing/syncthing
  dependency-version: 2.1.7
  dependency-type: direct:production
  update-type: version-update:semver-patch
...
EOF
    )"
    [ "$(cat "$OUT/commit-message.txt")" = "$expected" ]
}

@test "the update type follows the part of the version that moved" {
    releases v3.0.0 v2.2.0 v2.1.7 v2.1.5
    for case in "v2.1.7 semver-patch" "v2.2.0 semver-minor" "v3.0.0 semver-major"; do
        set -- $case
        run "$MESSAGE" v2.1.5 "$1" "$OUT"
        [ "$status" -eq 0 ] || return 1
        grep -qx "  update-type: version-update:$2" "$OUT/commit-message.txt" || return 1
    done
}

@test "the body follows dependabot's structure" {
    releases v2.1.7 v2.1.5
    run "$MESSAGE" v2.1.5 v2.1.7 "$OUT"
    [ "$status" -eq 0 ]
    body="$(cat "$OUT/pr-body.md")"
    [ "$(head -n 1 "$OUT/pr-body.md")" = "Bumps [syncthing/syncthing](https://github.com/syncthing/syncthing) from 2.1.5 to 2.1.7." ]
    [[ "$body" == *"<summary>Release notes</summary>"*"> ## v2.1.7"$'\n'"> Notes for v2.1.7"*"</details>"* ]]
    [[ "$body" == *"<summary>Commits</summary>"*"[compare view](https://github.com/syncthing/syncthing/compare/v2.1.5...v2.1.7)"*"</details>" ]]
}

@test "only stable releases after the pin, up to the target, are listed newest first" {
    # Published out of version order, with a prerelease, the pin itself and a
    # release newer than the target mixed in.
    releases v2.1.6 v2.2.0 v2.1.10 v2.1.5 v2.1.8-rc.1 v2.1.8 v2.1.4
    run "$MESSAGE" v2.1.5 v2.1.10 "$OUT"
    [ "$status" -eq 0 ]
    run grep '^> ## ' "$OUT/pr-body.md"
    [ "$output" = "$(printf '> ## %s\n' v2.1.10 v2.1.8 v2.1.6)" ]
}

@test "upstream mentions, issue references and links are defused" {
    releases v2.1.7 v2.1.5
    cat >"$GH_STUB/notes/v2.1.7" <<'EOF'
* fix: thing (fixes #10924) by @calmh in https://github.com/syncthing/syncthing/pull/10925
Contact: someone@example.com
EOF
    run "$MESSAGE" v2.1.5 v2.1.7 "$OUT"
    [ "$status" -eq 0 ]
    zwsp="$(printf '\342\200\213')"
    grep -qF "> * fix: thing (fixes [#10924](https://redirect.github.com/syncthing/syncthing/issues/10924)) by @${zwsp}calmh in https://redirect.github.com/syncthing/syncthing/pull/10925" "$OUT/pr-body.md"
    grep -qF "> Contact: someone@example.com" "$OUT/pr-body.md"
}

@test "notes too long for a pull request body are truncated" {
    releases v2.1.7 v2.1.5
    for i in $(seq 1 2000); do
        printf 'A line of release notes that is long enough to add up quickly, number %s\n' "$i"
    done >"$GH_STUB/notes/v2.1.7"
    run "$MESSAGE" v2.1.5 v2.1.7 "$OUT"
    [ "$status" -eq 0 ]
    [ "$(wc -m <"$OUT/pr-body.md")" -le 65536 ]
    grep -qx '\.\.\. (truncated)' "$OUT/pr-body.md"
    # The Commits block survives the cut.
    tail -n 1 "$OUT/pr-body.md" | grep -qx '</details>'
    grep -qF "[compare view]" "$OUT/pr-body.md"
}

@test "anything but a release tag is refused" {
    releases v2.1.7 v2.1.5
    for bad in "" main v2.1 2.1.7 v2.1.7-rc.1; do
        run "$MESSAGE" v2.1.5 "$bad" "$OUT"
        [ "$status" -ne 0 ] || return 1
        [[ "$output" == *"is not a release tag"* ]] || return 1
        run "$MESSAGE" "$bad" v2.1.7 "$OUT"
        [ "$status" -ne 0 ] || return 1
        [[ "$output" == *"is not a release tag"* ]] || return 1
    done
    [ ! -e "$OUT" ]
}

@test "a target that is not newer than the pin is refused" {
    releases v2.1.7 v2.1.5
    run "$MESSAGE" v2.1.7 v2.1.5 "$OUT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not newer than"* ]]
    run "$MESSAGE" v2.1.7 v2.1.7 "$OUT"
    [ "$status" -ne 0 ]
}
