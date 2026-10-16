#!/usr/bin/env bash
# Publish only missing assets. Never change release notes or overwrite assets.
set -euo pipefail
tag=${1:?Usage: publish.sh TAG DIST}
dist=${2:?Usage: publish.sh TAG DIST}
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || { echo 'Invalid release tag' >&2; exit 2; }
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
assets=(llvmup-linux.tar.gz llvmup-windows.zip bootstrap.sh bootstrap.ps1 SHA256SUMS)
for name in "${assets[@]}"; do [[ -f $dist/$name ]] || { echo "Missing asset: $name" >&2; exit 1; }; done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if ! gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" > "$work/release.json" 2> "$work/error"; then
    if ! grep -q 'HTTP 404' "$work/error"; then cat "$work/error" >&2; exit 1; fi
    args=(--verify-tag --generate-notes)
    [[ $tag != *-* ]] || args+=(--prerelease)
    paths=()
    for name in "${assets[@]}"; do paths+=("$dist/$name"); done
    gh release create "$tag" "${args[@]}" "${paths[@]}"
    exit
fi
# Check every existing asset before uploading anything, including SHA256SUMS.
# This makes retries safe without mixing packages from different builds.
missing=()
for name in "${assets[@]}"; do
    if jq -e --arg name "$name" '.assets | any(.name == $name)' "$work/release.json" >/dev/null; then
        gh release download "$tag" --pattern "$name" --dir "$work"
        cmp -s "$dist/$name" "$work/$name" || { echo "Existing asset differs: $name. Refusing to overwrite; use a new version or review the existing release." >&2; exit 1; }
    else
        missing+=("$dist/$name")
    fi
done
if ((${#missing[@]})); then
    gh release upload "$tag" "${missing[@]}"
else
    echo "Release $tag already contains identical assets."
fi
