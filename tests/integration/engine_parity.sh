#!/usr/bin/env bash
# Behavioural parity between the Bash engine (libexec/sh/llvmup-engine.sh) and the PowerShell
# engine (libexec/pwsh) for remote resolution, using the same recorded upstream release metadata.
#
# Usage: tests/integration/engine_parity.sh            (needs bash, jq and pwsh/pwsh.exe)
#   PWSH=pwsh.exe can be used from WSL; paths are converted with wslpath automatically.
set -u -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/tests/fixtures/releases"
ENGINE="$ROOT/libexec/sh/llvmup-engine.sh"
PWSH="${PWSH:-pwsh}"

if ! command -v "$PWSH" >/dev/null 2>&1; then
    echo "SKIP: $PWSH not available"
    exit 0
fi

to_ps_path() {
    case "$PWSH" in
        *.exe) wslpath -w "$1" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

PS_MODULE="$(to_ps_path "$ROOT/Llvm-Functions.psm1")"
PS_OFF="$(to_ps_path "$FIX/official.json")"
PS_WL="$(to_ps_path "$FIX/winlibs.json")"
PS_LM="$(to_ps_path "$FIX/llvm-mingw.json")"

# provider-selector | platform | arch | crt | asset formats | expectation (ok|fail)
CASES=(
    "official@latest|windows|x64||zip,7z,tar.xz|ok"
    "official@23.1.3|windows|x64||tar.xz|ok"
    "official@23|linux|x64||tar.xz,tar.zst|ok"
    "official@23|linux|x64||tar.xz|ok"
    "official@~23.1|windows|arm64||tar.xz|ok"
    "official@23.*|linux|x64||tar.xz|ok"
    "official@>=23.1.4|windows|x64||tar.xz|ok"
    "official@99|windows|x64||tar.xz|fail"
    "winlibs@23|windows|x64|ucrt|zip,7z|ok"
    "winlibs@latest|windows|x64|msvcrt|zip|ok"
    "winlibs@23.1.3|windows|x86|ucrt|7z,zip|ok"
    "winlibs@23|linux|x64||tar.xz|fail"
    "llvm-mingw@23|linux|x64|ucrt|tar.xz|ok"
    "llvm-mingw@23.1.4|windows|x64|ucrt|zip|ok"
    "llvm-mingw@latest|macos|arm64|ucrt|tar.xz|ok"
    "llvm-mingw@20261104|windows|arm64|ucrt|zip|ok"
    "llvm-mingw@23|linux|x64|msvcrt|tar.xz|ok"
    "official@>=23.1.2,<23.1.5|windows|x64||tar.xz|fail"
    "llvm-mingw@23|windows|x64|ucrt|tar.xz|fail"
)

FIELDS='{provider, release, llvm_version, gcc_version: (.gcc_version // null | if . == "" then null else . end), canonical_id, asset_name, asset_digest, crt, target, platform, architecture}'

pass=0 fail=0
for c in "${CASES[@]}"; do
    IFS='|' read -r sel os arch crt formats expect <<<"$c"
    crt_args=()
    [ -z "$crt" ] || crt_args=(--crt "$crt")

    sh_out="$(LLVMUP_ASSET_FORMATS="$formats" LLVMUP_OFFICIAL_RELEASES_FILE="$FIX/official.json" \
        LLVMUP_WINLIBS_RELEASES_FILE="$FIX/winlibs.json" LLVMUP_LLVM_MINGW_RELEASES_FILE="$FIX/llvm-mingw.json" \
        bash "$ENGINE" resolve "$sel" --platform "$os" --arch "$arch" "${crt_args[@]}" --format json 2>/dev/null)"
    sh_rc=$?

    ps_script="\$env:LLVMUP_ASSET_FORMATS='$formats'; \$env:LLVMUP_OFFICIAL_RELEASES_FILE='$PS_OFF'; \$env:LLVMUP_WINLIBS_RELEASES_FILE='$PS_WL'; \$env:LLVMUP_LLVM_MINGW_RELEASES_FILE='$PS_LM';"
    ps_script+=" Import-Module '$PS_MODULE' -DisableNameChecking -WarningAction SilentlyContinue;"
    ps_script+=" \$r = llvmup resolve '$sel' --platform $os --arch $arch $( [ -z "$crt" ] || printf -- '--crt %s' "$crt") --format json 2>\$null;"
    ps_script+=" if (\$r -is [string]) { \$r } elseif (\$r -is [array]) { \$r | Where-Object { \$_ -is [string] } } else { exit 1 }"
    ps_out="$("$PWSH" -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null | tr -d '\r')"
    ps_rc=$?
    [ -n "$ps_out" ] && jq -e . >/dev/null 2>&1 <<<"$ps_out" || ps_rc=1

    if [ "$expect" = fail ]; then
        if [ "$sh_rc" -ne 0 ] && [ "$ps_rc" -ne 0 ]; then pass=$((pass + 1)); echo "ok   $c (both reject)"
        else fail=$((fail + 1)); echo "FAIL $c expected both to fail (bash=$sh_rc pwsh=$ps_rc)"; fi
        continue
    fi
    if [ "$sh_rc" -ne 0 ] || [ "$ps_rc" -ne 0 ]; then
        fail=$((fail + 1)); echo "FAIL $c (bash=$sh_rc pwsh=$ps_rc)"; continue
    fi
    a="$(jq -cS "$FIELDS" <<<"$sh_out")"
    b="$(jq -cS "$FIELDS" <<<"$ps_out")"
    if [ "$a" = "$b" ]; then
        pass=$((pass + 1)); echo "ok   $c -> $(jq -r '.asset_name' <<<"$sh_out")"
    else
        fail=$((fail + 1)); echo "FAIL $c"; echo "  bash: $a"; echo "  pwsh: $b"
    fi
done
echo "parity: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
