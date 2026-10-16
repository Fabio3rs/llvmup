#!/usr/bin/env bash
# Non-interactive equivalent of pwshd, with Python in the disposable container.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
modules=${LLVMUP_PESTER_MODULES:-$HOME/.powershell_current}
docker run --rm \
    -e HOME=/tmp -e TEST_UID="$(id -u)" -e TEST_GID="$(id -g)" \
    -v "$repo:$repo" -w "$repo" \
    -v "$modules:/opt/test-powershell-modules:ro" \
    -e PSModulePath=/opt/test-powershell-modules/Modules:/opt/microsoft/powershell/7/Modules \
    "${LLVMUP_POWERSHELL_IMAGE:-mcr.microsoft.com/powershell:latest}" \
    sh -c '
        if ! command -v python3 >/dev/null; then
            apt-get update -qq && apt-get install -y -qq python3 >/tmp/llvmup-test-deps.log || exit 1
        fi
        exec setpriv --reuid="$TEST_UID" --regid="$TEST_GID" --clear-groups \
            pwsh -NoProfile -File tests/_pester_runner.ps1 "$@"
    ' llvmup-pester "$@"
