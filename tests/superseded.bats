#!/usr/bin/env bats

load test_helper

# A gh on PATH that lists the open pull requests in $GH_STUB/open, one
# "<number> <branch>" per line, and records every other call in $GH_STUB/calls.
setup() {
    GH_STUB="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$GH_STUB/bin"
    : >"$GH_STUB/open"
    : >"$GH_STUB/calls"
    cat >"$GH_STUB/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "pr list") cat "$GH_STUB/open" ;;
    *) printf '%s\n' "$*" >>"$GH_STUB/calls" ;;
esac
EOF
    chmod +x "$GH_STUB/bin/gh"
    PATH="$GH_STUB/bin:$PATH"
    export GH_STUB PATH

    CLOSE="$REPO_ROOT/scripts/close-superseded-syncthing-prs.sh"
    BRANCH="deps/github_releases/syncthing/syncthing-2.1.8"
}

@test "older syncthing bumps are closed as superseded by the new one" {
    cat >"$GH_STUB/open" <<'EOF'
90 deps/github_releases/syncthing/syncthing-2.1.7
91 deps/github_releases/syncthing/syncthing-2.1.8
EOF
    run "$CLOSE" "$BRANCH" 91
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_STUB/calls")" = "$(printf '%s\n' \
        "pr comment 90 --body Superseded by #91." \
        "pr close 90 --delete-branch")" ]
}

@test "pull requests from other branches are left open" {
    cat >"$GH_STUB/open" <<'EOF'
80 dependabot/github_actions/actions/checkout-7
81 feature/syncthing-docs
82 deps/github_releases/other/thing-1.0.0
91 deps/github_releases/syncthing/syncthing-2.1.8
EOF
    run "$CLOSE" "$BRANCH" 91
    [ "$status" -eq 0 ]
    [ ! -s "$GH_STUB/calls" ]
}

@test "a bad branch or pull request number is refused" {
    run "$CLOSE" build/update-syncthing 91
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a deps/github_releases/syncthing/syncthing-* branch"* ]]
    run "$CLOSE" "$BRANCH" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a pull request number"* ]]
    [ ! -s "$GH_STUB/calls" ]
}

@test "the workflow names its branches the way the script expects" {
    wf="$REPO_ROOT/.github/workflows/update-syncthing.yaml"
    grep -qF 'branch="deps/github_releases/syncthing/syncthing-${latest#v}"' "$wf"
    grep -q "scripts/close-superseded-syncthing-prs.sh" "$wf"
}
