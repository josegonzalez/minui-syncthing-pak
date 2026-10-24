#!/bin/bash
# Move the pinned Syncthing release to <tag>.
#
# Usage: bump-syncthing.sh <tag> [root]
#
# Rewrites SYNCTHING_VERSION in the Makefile of the repo at [root] (default:
# the one this script lives in). update-syncthing.yaml runs it when upstream
# publishes a release.
#
# A tag that is not vX.Y.Z is refused rather than written: a prerelease or a
# branch name would download fine and quietly ship something other than a
# stable release.
set -euo pipefail

TAG="${1:-}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: '$TAG' is not a release tag of the form vX.Y.Z" >&2
    exit 1
fi

# Not sed -i: its syntax differs between GNU and BSD, and this runs on both.
sed -E "s/^(SYNCTHING_VERSION[[:space:]]*\?=[[:space:]]*).*/\1$TAG/" "$ROOT/Makefile" >"$ROOT/Makefile.tmp"
mv "$ROOT/Makefile.tmp" "$ROOT/Makefile"

# A pattern that stopped matching would leave the old version in place and
# exit 0, so check the result rather than trusting the substitution.
if ! grep -qE "^SYNCTHING_VERSION[[:space:]]*\?=[[:space:]]*$TAG\$" "$ROOT/Makefile"; then
    echo "error: SYNCTHING_VERSION in $ROOT/Makefile was not updated" >&2
    exit 1
fi

echo "Syncthing pinned at $TAG"
