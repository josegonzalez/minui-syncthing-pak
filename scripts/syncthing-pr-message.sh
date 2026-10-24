#!/bin/bash
# Write the commit message and pull request body for a Syncthing bump.
#
# Usage: syncthing-pr-message.sh <from-tag> <to-tag> <out-dir>
#
# Writes <out-dir>/commit-message.txt and <out-dir>/pr-body.md in the layout
# dependabot uses for this repo's github-actions bumps, so both kinds of
# dependency update read the same. update-syncthing.yaml runs it after
# bump-syncthing.sh. Release notes are read with gh, so GH_TOKEN must be set
# outside of an authenticated shell.
set -euo pipefail

REPO="syncthing/syncthing"
REPO_URL="https://github.com/$REPO"
# GitHub refuses a pull request body longer than this.
BODY_LIMIT=65536

FROM="${1:-}"
TO="${2:-}"
OUT="${3:-}"

for tag in "$FROM" "$TO"; do
    if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: '$tag' is not a release tag of the form vX.Y.Z" >&2
        exit 1
    fi
done
if [ -z "$OUT" ]; then
    echo "error: no output directory given" >&2
    exit 1
fi

# A fixed-width key per version, so versions compare as plain strings.
version_key() {
    local major minor patch
    IFS=. read -r major minor patch <<<"${1#v}"
    printf '%06d%06d%06d' "$((10#$major))" "$((10#$minor))" "$((10#$patch))"
}

FROM_KEY="$(version_key "$FROM")"
TO_KEY="$(version_key "$TO")"
if ! [[ "$FROM_KEY" < "$TO_KEY" ]]; then
    echo "error: $TO is not newer than $FROM" >&2
    exit 1
fi

FROM_VERSION="${FROM#v}"
TO_VERSION="${TO#v}"
IFS=. read -r from_major from_minor _ <<<"$FROM_VERSION"
IFS=. read -r to_major to_minor _ <<<"$TO_VERSION"
if [ "$from_major" != "$to_major" ]; then
    UPDATE_TYPE="version-update:semver-major"
elif [ "$from_minor" != "$to_minor" ]; then
    UPDATE_TYPE="version-update:semver-minor"
else
    UPDATE_TYPE="version-update:semver-patch"
fi

# Every stable release after the pin, up to and including the target, newest
# first. gh lists by publish date, which is not version order once upstream
# ships a fix for an older line, so sort by version instead.
releases=()
while IFS= read -r tag; do
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    key="$(version_key "$tag")"
    if [[ "$FROM_KEY" < "$key" ]] && ! [[ "$TO_KEY" < "$key" ]]; then
        releases+=("$key $tag")
    fi
done < <(gh release list --repo "$REPO" --exclude-pre-releases --limit 100 --json tagName --jq '.[].tagName')

# Upstream notes, defused the way dependabot does it: a zero-width space keeps
# @mentions from pinging upstream people, bare #N references are pointed at
# upstream instead of this repo's issues, and pull request and issue links go
# through redirect.github.com so they leave no cross-reference upstream.
release_notes() {
    local zwsp
    zwsp="$(printf '\342\200\213')"
    gh release view "$1" --repo "$REPO" --json body --jq .body |
        sed -E \
            -e "s,https://github\.com/([^/]+/[^/]+/(pull|issues)/[0-9]+),https://redirect.github.com/\1,g" \
            -e "s,(^|[^[:alnum:]_/&[])#([0-9]+),\1[#\2](https://redirect.github.com/$REPO/issues/\2),g" \
            -e "s/(^|[^[:alnum:]_.])@([[:alnum:]])/\1@$zwsp\2/g"
}

notes=""
if [ "${#releases[@]}" -gt 0 ]; then
    while read -r _ tag; do
        [ -z "$notes" ] || notes+=$'>\n'
        notes+="> ## $tag"$'\n'
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            if [ -z "$line" ]; then
                notes+=$'>\n'
            else
                notes+="> $line"$'\n'
            fi
        done < <(release_notes "$tag")
    done < <(printf '%s\n' "${releases[@]}" | sort -r)
fi

summary="Bumps [$REPO]($REPO_URL) from $FROM_VERSION to $TO_VERSION."
compare_url="$REPO_URL/compare/$FROM...$TO"

mkdir -p "$OUT"

cat >"$OUT/commit-message.txt" <<EOF
chore(deps): bump $REPO from $FROM_VERSION to $TO_VERSION

$summary
- [Release notes]($REPO_URL/releases)
- [Commits]($compare_url)

---
updated-dependencies:
- dependency-name: $REPO
  dependency-version: $TO_VERSION
  dependency-type: direct:production
  update-type: $UPDATE_TYPE
...
EOF

render_body() {
    printf '%s\n' "$summary"
    if [ -n "$1" ]; then
        printf '<details>\n<summary>Release notes</summary>\n\n'
        printf '_Sourced from [%s'"'"'s releases](%s/releases)._\n\n' "$REPO" "$REPO_URL"
        printf '%s' "$1"
        if [ -n "$2" ]; then
            printf '\n... (truncated)\n'
        fi
        printf '\n</details>\n'
    fi
    printf '<details>\n<summary>Commits</summary>\n\n'
    printf -- '- See full diff in [compare view](%s)\n' "$compare_url"
    printf '</details>\n'
}

body="$(render_body "$notes" "")"
if [ "${#body}" -gt "$BODY_LIMIT" ]; then
    # Cut the notes back to whole lines, leaving room for the rest of the body
    # and the truncation marker.
    marker_body="$(render_body "" "")"
    budget=$((BODY_LIMIT - ${#marker_body} - 256))
    notes="${notes:0:budget}"
    notes="${notes%$'\n'*}"$'\n'
    body="$(render_body "$notes" "truncated")"
fi
printf '%s\n' "$body" >"$OUT/pr-body.md"

echo "Wrote $OUT/commit-message.txt and $OUT/pr-body.md"
