#!/bin/bash
# Close the Syncthing bump pull requests a newer one replaces.
#
# Usage: close-superseded-syncthing-prs.sh <branch> <pr-number>
#
# Every open pull request from another deps/github_releases/syncthing/syncthing-*
# branch gets a "Superseded by #<pr-number>." comment and is closed with its
# branch deleted, the way dependabot retires an outdated bump. <branch> is the
# one update-syncthing.yaml just opened <pr-number> from, and is left alone.
set -euo pipefail

PREFIX="deps/github_releases/syncthing/syncthing-"

BRANCH="${1:-}"
NUMBER="${2:-}"

if [[ "$BRANCH" != "$PREFIX"* ]]; then
    echo "error: '$BRANCH' is not a $PREFIX* branch" >&2
    exit 1
fi
if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: '$NUMBER' is not a pull request number" >&2
    exit 1
fi

while read -r number head; do
    [[ "$head" == "$PREFIX"* ]] || continue
    [ "$head" != "$BRANCH" ] || continue
    gh pr comment "$number" --body "Superseded by #$NUMBER."
    gh pr close "$number" --delete-branch
    echo "Closed #$number from $head"
done < <(gh pr list --state open --limit 100 --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"')
