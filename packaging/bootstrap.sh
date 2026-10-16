#!/usr/bin/env bash
# Download this complete file before executing it. No LLVM archives are fetched.
set -euo pipefail
version='@LLVMUP_VERSION@'
if [[ ${1:-} == --version ]]; then
    [[ $# -ge 2 ]] || { echo 'Missing value for --version' >&2; exit 2; }
    version=$2; shift 2
fi
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || { echo 'Use a release bootstrap or supply --version vX.Y.Z' >&2; exit 2; }
for arg in "$@"; do
    case "$arg" in --ci|--no-profile|--files-only) ;; *) echo "Unsupported bootstrap option: $arg" >&2; exit 2 ;; esac
done
[[ $(uname -s) == Linux ]] || { echo 'This bootstrap supports Linux. Use bootstrap.ps1 on Windows.' >&2; exit 1; }
for tool in curl tar sha256sum mktemp; do command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }; done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
base="https://github.com/Fabio3rs/llvmup/releases/download/$version"
fetch() { curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --retry 2 --output "$2" "$base/$1"; }
fetch SHA256SUMS "$work/SHA256SUMS"
fetch llvmup-linux.tar.gz "$work/llvmup-linux.tar.gz"
expected=''
while read -r hash name rest; do
    if [[ $name == llvmup-linux.tar.gz ]]; then
        [[ -z $expected && $hash =~ ^[a-fA-F0-9]{64}$ && -z $rest ]] || { echo 'Invalid checksum manifest' >&2; exit 1; }
        expected=$hash
    fi
done < "$work/SHA256SUMS"
[[ -n $expected ]] || { echo 'Package checksum missing' >&2; exit 1; }
printf '%s  %s\n' "$expected" "$work/llvmup-linux.tar.gz" | sha256sum --check --status || { echo 'Package checksum mismatch' >&2; exit 1; }
# Packages contain regular files only; reject links and traversal before extraction.
tar -tzf "$work/llvmup-linux.tar.gz" > "$work/members"
while IFS= read -r member; do
    [[ $member =~ ^llvmup/([A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+$ && $member != */../* && $member != */.. && $member != */. ]] || { echo 'Unsafe archive path' >&2; exit 1; }
done < "$work/members"
tar -tvzf "$work/llvmup-linux.tar.gz" > "$work/types"
while IFS= read -r entry; do [[ $entry == -* ]] || { echo 'Archive contains a non-regular file' >&2; exit 1; }; done < "$work/types"
tar -xzf "$work/llvmup-linux.tar.gz" -C "$work" --no-same-owner
[[ $(cat "$work/llvmup/VERSION") == "$version" ]] || { echo 'Package version mismatch' >&2; exit 1; }
bash "$work/llvmup/install.sh" "$@"
