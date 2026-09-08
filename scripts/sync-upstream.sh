#!/bin/bash
# Read the generated UPSTREAM.toml format without evaluating repository content.
set -eu
cd -- "$(git rev-parse --show-toplevel)"
repo= subdir= pin=
exclude=()
include=()
while IFS= read -r line; do
    case "$line" in
        repo\ *=*) repo=${line#*\"}; repo=${repo%%\"*} ;;
        subdir\ *=*) subdir=${line#*\"}; subdir=${subdir%%\"*} ;;
        pin\ *=*) pin=${line#*\"}; pin=${pin%%\"*} ;;
        exclude\ *=*|include\ *=*)
            field=${line%% *}
            rest=${line#*[}
            while [[ "$rest" == *\"* ]]; do
                rest=${rest#*\"}
                if [[ "$field" == include ]]; then include+=("${rest%%\"*}")
                else exclude+=("${rest%%\"*}"); fi
                rest=${rest#*\"}
            done ;;
    esac
done < UPSTREAM.toml
[[ -n "$repo" && -n "$subdir" && "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid UPSTREAM.toml' >&2; exit 2; }
target=main
mode=${0##*/}
if [[ "$mode" == sync-upstream.sh ]]; then
    if [[ $# == 2 && "$1" == --to ]]; then target=$2
    elif [[ $# != 0 ]]; then echo 'Usage: scripts/sync-upstream.sh [--to <ref>]' >&2; exit 2; fi
    [[ -z "$(git status --porcelain --untracked-files=all)" ]] || { echo 'Refusing to sync a dirty tree.' >&2; exit 2; }
else
    [[ $# == 0 ]] || { echo 'Usage: scripts/check-drift.sh' >&2; exit 2; }
fi
# Fetch into this fork so three-way apply can access upstream base blobs.
git fetch --no-tags -- "$repo" "$target"
to=$(git rev-parse 'FETCH_HEAD^{commit}')
if ! git cat-file -e "$pin^{commit}" 2>/dev/null; then git fetch --no-tags -- "$repo" "$pin"; fi
git merge-base --is-ancestor "$pin" "$to" || { echo 'Target does not descend from the recorded pin.' >&2; exit 2; }
if [[ "$mode" != sync-upstream.sh ]]; then
    commits=$(git log --format='%h %s' "$pin..$to" -- "$subdir")
    if [[ -n "$commits" ]]; then printf '%s\n' "$commits"; exit 1; fi
    echo "No upstream drift for $subdir at $pin."
    exit 0
fi
paths=()
if [[ ${#include[@]} == 0 ]]; then paths+=("$subdir")
else for path in "${include[@]}"; do paths+=("$subdir/$path"); done; fi
paths+=(":(exclude)$subdir/Cargo.toml" ":(exclude)$subdir/README.md")
if [[ ${#exclude[@]} != 0 ]]; then
    for path in "${exclude[@]}"; do paths+=(":(exclude)$subdir/$path"); done
fi
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# --relative strips only the vendored directory, including binary diffs.
git diff --binary --full-index --relative="$subdir" "$pin" "$to" -- "${paths[@]}" > "$tmp/upstream.patch"
if [[ -s "$tmp/upstream.patch" ]]; then
    if ! git apply --3way "$tmp/upstream.patch"; then
        echo 'Upstream apply failed. Resolve conflicts and review the diff; the pin is unchanged.' >&2
        git status --short
        exit 1
    fi
fi
while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in pin\ *=*) printf 'pin = "%s"\n' "$to" ;; *) printf '%s\n' "$line" ;; esac
done < UPSTREAM.toml > "$tmp/UPSTREAM.toml"
# Use shell redirection so file permissions remain unchanged.
while IFS= read -r line; do printf '%s\n' "$line"; done < "$tmp/UPSTREAM.toml" > UPSTREAM.toml
echo "Synced $subdir to $to. Review source deltas, update dependencies, and run build and tests before committing."
