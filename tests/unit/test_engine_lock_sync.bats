#!/usr/bin/env bats
# Offline tests for the Bash engine: config lock, sync [--locked], run --locked, resolve --config,
# project compiler/target selection, list --remote --provider and update. Uses recorded upstream metadata.

setup() {
    export TEST_HOME="$BATS_TMPDIR/llvmup_lock_$$"
    export HOME="$TEST_HOME"
    export LLVM_HOME="$TEST_HOME/llvm-home"
    unset LLVM_TOOLCHAINS_DIR LLVMUP_SESSION_OVERRIDE _ACTIVE_LLVM LLVMUP_ACTIVE_COMPILER LLVMUP_ACTIVE_TARGET
    export LLVMUP_DISABLE_AUTOACTIVATE=1
    export LLVMUP_SCRIPT="$BATS_TEST_DIRNAME/../../llvmup"
    FIX="$BATS_TEST_DIRNAME/../fixtures/releases"
    export LLVMUP_OFFICIAL_RELEASES_FILE="$FIX/official.json"
    export LLVMUP_WINLIBS_RELEASES_FILE="$FIX/winlibs.json"
    export LLVMUP_LLVM_MINGW_RELEASES_FILE="$FIX/llvm-mingw.json"
    export LLVMUP_ASSET_FORMATS="tar.xz,zip"
    PROJ="$TEST_HOME/proj"
    mkdir -p "$LLVM_HOME/toolchains" "$PROJ"
    cd "$PROJ"
}

teardown() {
    cd /
    rm -rf "$TEST_HOME"
}

# fake_toolchain <name> <provider> <llvm> <release> <digest> [targets-json]
fake_toolchain() {
    local root="$LLVM_HOME/toolchains/$1"
    mkdir -p "$root/bin"
    for t in clang clang++ x86_64-w64-mingw32-clang x86_64-w64-mingw32-clang++ aarch64-w64-mingw32-clang aarch64-w64-mingw32-clang++; do
        printf '#!/bin/sh\necho "%s $*"\n' "$t" > "$root/bin/$t"
        chmod +x "$root/bin/$t"
    done
    local asset
    asset="$(jq -c '.entries["linux-x64"].asset // {"name":"x"}' .llvmup-lock.json 2>/dev/null || printf '{"name":"x"}')"
    jq -n --argjson asset "$asset" --arg id "$1" --arg p "$2" --arg v "$3" --arg r "$4" --arg d "$5" --argjson tg "${6:-[\"x86_64-w64-mingw32\",\"aarch64-w64-mingw32\"]}" '
        {schema: 1, id: $id, origin: "managed", provider: $p, provider_release: $r, llvm_version: $v,
         host: {os: "linux", arch: "x64"}, supported_targets: $tg, default_target: $tg[0],
         variant: {crt: "ucrt", default_compiler: "clang", cxx_stdlib: "libc++"},
         tools: {clang: "bin/clang", "clang++": "bin/clang++",
                 target_wrappers: {"x86_64-w64-mingw32": {clang: "bin/x86_64-w64-mingw32-clang", "clang++": "bin/x86_64-w64-mingw32-clang++"},
                                   "aarch64-w64-mingw32": {clang: "bin/aarch64-w64-mingw32-clang", "clang++": "bin/aarch64-w64-mingw32-clang++"}}},
         capabilities: {compilers: ["clang"]}, asset: ($asset + {digest: $d}), verification: {policy: "warn"}}' > "$root/.llvmup-toolchain.json"
}

write_managed_manifest_for_request() {
    local root="$1" metadata="$2"
    jq -n --argjson r "$metadata" '
        {schema: 1, id: $r.canonical_id, origin: "managed", provider: $r.provider,
         provider_release: $r.release, llvm_version: $r.llvm_version,
         host: {os: $r.platform, arch: $r.architecture},
         asset: {name: $r.asset_name, digest: $r.asset_digest, id: $r.asset_id},
         tools: {clang: "bin/clang"}, capabilities: {compilers: ["clang"]}}
    ' > "$root/.llvmup-toolchain.json"
}

write_config() {
    cat > "$PROJ/.llvmup-config" <<EOF
# keep this comment
[version]
default = "$1"

[toolchain]
provider = "$2"
crt = "ucrt"
${3:-}
EOF
}

@test "config lock records the resolved asset per host and keeps other hosts" {
    write_config 23 llvm-mingw
    run "$LLVMUP_SCRIPT" config lock
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.llvmup-lock.json" ]
    jq -e '.schema == 1 and .entries["linux-x64"].provider == "llvm-mingw"' "$PROJ/.llvmup-lock.json"
    jq -e '.entries["linux-x64"].release == "20261117" and (.entries["linux-x64"].asset.digest | startswith("sha256:"))' "$PROJ/.llvmup-lock.json"
    jq -e '.entries["linux-x64"].asset.name | test("ubuntu.*x86_64\\.tar\\.xz$")' "$PROJ/.llvmup-lock.json"

    run "$LLVMUP_SCRIPT" config lock --platform windows --arch x64
    [ "$status" -eq 0 ]
    jq -e '(.entries | keys) == ["linux-x64", "windows-x64"]' "$PROJ/.llvmup-lock.json"
    jq -e '.entries["windows-x64"].asset.name == "llvm-mingw-20261117-ucrt-x86_64.zip"' "$PROJ/.llvmup-lock.json"
    grep -q '# keep this comment' "$PROJ/.llvmup-config"
}

@test "config lock refuses source builds" {
    write_config 23 official 'kind = "source"'
    run "$LLVMUP_SCRIPT" config lock
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot be locked"* ]]
}

@test "sync --locked accepts the installed locked toolchain and rejects a digest mismatch" {
    write_config 23 llvm-mingw
    "$LLVMUP_SCRIPT" config lock >/dev/null
    local cid digest
    cid="$(jq -r '.entries["linux-x64"].canonical_id' "$PROJ/.llvmup-lock.json")"
    digest="$(jq -r '.entries["linux-x64"].asset.digest' "$PROJ/.llvmup-lock.json")"
    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "$digest"
    fake_toolchain other winlibs 23.1.3 other ''
    "$LLVMUP_SCRIPT" alias set "$cid" other >/dev/null

    run "$LLVMUP_SCRIPT" sync --locked
    [ "$status" -eq 0 ]
    [[ "$output" == *"$LLVM_HOME/toolchains/$cid"* ]]
    run "$LLVMUP_SCRIPT" run --locked -- clang --version
    [ "$status" -eq 0 ]

    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "sha256:0000"
    run "$LLVMUP_SCRIPT" sync --locked
    [ "$status" -ne 0 ]
    [[ "$output" == *"differs from the requested asset digest"* ]]
}

@test "an alias rejects a different toolchain installed under its original target name" {
    fake_toolchain reused llvm-mingw 23.1.6 20261117 ''
    "$LLVMUP_SCRIPT" alias set mine reused >/dev/null
    local manifest="$LLVM_HOME/toolchains/reused/.llvmup-toolchain.json"
    jq '.id = "different"' "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    run "$LLVMUP_SCRIPT" where mine
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer matches an installed toolchain"* ]]
}

@test "sync --locked reports a missing host entry, provider conflicts and weaker policies" {
    write_config 23 llvm-mingw
    "$LLVMUP_SCRIPT" config lock --platform windows >/dev/null
    run "$LLVMUP_SCRIPT" sync --locked
    [ "$status" -ne 0 ]
    [[ "$output" == *"no entry for host 'linux-x64' (available: windows-x64)"* ]]

    "$LLVMUP_SCRIPT" config lock --verify strict >/dev/null
    run "$LLVMUP_SCRIPT" sync --locked --verify warn
    [ "$status" -ne 0 ]
    [[ "$output" == *"weaker than the locked policy 'strict'"* ]]

    write_config 23 official
    run "$LLVMUP_SCRIPT" sync --locked
    [ "$status" -ne 0 ]
    [[ "$output" == *"conflicts with .llvmup-config provider 'official'"* ]]
}

@test "sync --locked refuses a lockfile asset that no longer matches before downloading" {
    write_config 23 llvm-mingw
    "$LLVMUP_SCRIPT" config lock >/dev/null
    jq '.entries["linux-x64"].asset.name = "llvm-mingw-renamed.tar.xz"' "$PROJ/.llvmup-lock.json" > "$PROJ/l.tmp" && mv "$PROJ/l.tmp" "$PROJ/.llvmup-lock.json"
    run "$LLVMUP_SCRIPT" sync --locked
    [ "$status" -ne 0 ]
    [[ "$output" == *"Locked asset 'llvm-mingw-renamed.tar.xz' differs"* ]]
    [ -z "$(ls -A "$LLVM_HOME/toolchains")" ]
}

@test "run --locked uses the lockfile toolchain and rejects an explicit selector" {
    write_config 23 llvm-mingw
    "$LLVMUP_SCRIPT" config lock >/dev/null
    cid="$(jq -r '.entries["linux-x64"].canonical_id' "$PROJ/.llvmup-lock.json")"
    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "$(jq -r '.entries["linux-x64"].asset.digest' "$PROJ/.llvmup-lock.json")"
    fake_toolchain other-tc llvm-mingw 23.1.4 20261104 "sha256:1111"

    run "$LLVMUP_SCRIPT" run --locked -- sh -c 'printf "%s|%s" "$LLVMUP_ACTIVE_VERSION" "$CC"'
    [ "$status" -eq 0 ]
    [[ "$output" == "$cid|$LLVM_HOME/toolchains/$cid/bin/x86_64-w64-mingw32-clang" ]]

    run "$LLVMUP_SCRIPT" run other-tc --locked -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"do not pass a selector"* ]]
}

@test "project config compiler and target are applied to run and env" {
    fake_toolchain lm llvm-mingw 23.1.6 20261117 "sha256:2222"
    write_config 23 llvm-mingw 'target = "aarch64-w64-mingw32"'
    run "$LLVMUP_SCRIPT" run -- sh -c 'printf "%s|%s" "$LLVMUP_ACTIVE_TARGET" "$CC"'
    [ "$status" -eq 0 ]
    [ "$output" = "aarch64-w64-mingw32|$LLVM_HOME/toolchains/lm/bin/aarch64-w64-mingw32-clang" ]

    run "$LLVMUP_SCRIPT" run --target x86_64-w64-mingw32 -- sh -c 'printf "%s" "$LLVMUP_ACTIVE_TARGET"'
    [ "$output" = "x86_64-w64-mingw32" ]
}

@test "resolve --config resolves the project request remotely" {
    write_config 23.1 llvm-mingw
    run "$LLVMUP_SCRIPT" resolve --config --format json
    [ "$status" -eq 0 ]
    jq -e '.provider == "llvm-mingw" and .release == "20261117" and .crt == "ucrt"' <<<"$output"
}

@test "list --remote --provider lists compatible provider releases" {
    run "$LLVMUP_SCRIPT" list --remote --provider llvm-mingw
    [ "$status" -eq 0 ]
    [[ "$output" == *"20261117  LLVM 23.1.6"* ]]
    run "$LLVMUP_SCRIPT" list --remote --provider llvm-mingw --json
    jq -e 'length >= 2 and .[0].release == "20261117"' <<<"$output"
}

@test "update reports an up-to-date toolchain and leaves aliases alone" {
    cid="$("$LLVMUP_SCRIPT" resolve llvm-mingw@23 --crt ucrt --format json | jq -r .canonical_id)"
    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "sha256:3333"
    "$LLVMUP_SCRIPT" alias set mine "$cid" >/dev/null
    run "$LLVMUP_SCRIPT" update mine
    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date ($cid)"* ]]
    jq -e --arg c "$cid" '.aliases.mine.target_name == $c' "$LLVM_HOME/aliases.json"
}

# fake_winlibs <name>: a WinLibs-like bundle with both Clang and GCC.
fake_winlibs() {
    local root="$LLVM_HOME/toolchains/$1"
    mkdir -p "$root/bin"
    for t in clang clang++ gcc g++ gcc-ar ar llvm-ar windres; do printf '#!/bin/sh\necho %s\n' "$t" > "$root/bin/$t"; chmod +x "$root/bin/$t"; done
    local asset
    asset="$(jq -c '.entries["linux-x64"].asset // {"name":"x"}' .llvmup-lock.json 2>/dev/null || printf '{"name":"x"}')"
    jq -n --argjson asset "$asset" --arg id "$1" '{schema: 1, id: $id, origin: "managed", provider: "winlibs", llvm_version: "23.1.3", gcc_version: "16.2.0",
        supported_targets: ["x86_64-w64-mingw32"], default_target: "x86_64-w64-mingw32",
        variant: {crt: "ucrt", default_compiler: "clang"},
        tools: {clang: "bin/clang", "clang++": "bin/clang++", gcc: "bin/gcc", "g++": "bin/g++", "gcc-ar": "bin/gcc-ar", ar: "bin/ar", "llvm-ar": "bin/llvm-ar", windres: "bin/windres"},
        capabilities: {compilers: ["clang", "gcc"]}}' > "$root/.llvmup-toolchain.json"
}

@test "env selects GCC or Clang inside one WinLibs bundle and exports llvm-sys prefixes" {
    fake_winlibs wl
    run "$LLVMUP_SCRIPT" env wl --compiler gcc --format json
    [ "$status" -eq 0 ]
    jq -e --arg r "$LLVM_HOME/toolchains/wl" '.set.CC == ($r + "/bin/gcc") and .set.CXX == ($r + "/bin/g++") and .set.AR == ($r + "/bin/gcc-ar")' <<<"$output"
    jq -e '.set.LLVMUP_ACTIVE_COMPILER == "gcc" and .set.LLVM_SYS_230_PREFIX and .set.LLVM_SYS_231_PREFIX' <<<"$output"
    run "$LLVMUP_SCRIPT" env wl --format json
    jq -e '(.set.CC | endswith("/bin/clang")) and (.set.AR | endswith("/bin/llvm-ar"))' <<<"$output"
    run "$LLVMUP_SCRIPT" env wl --compiler msvc --format json
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not provide compiler msvc"* ]]
}

@test "which resolves tools inside the selected toolchain only and cmake-toolchain writes cross settings" {
    fake_toolchain lm llvm-mingw 23.1.6 20261117 "sha256:4444"
    # The bundle's default target is selected, so clang++ resolves to that target's wrapper.
    run "$LLVMUP_SCRIPT" which clang++ --toolchain lm
    [ "$status" -eq 0 ]
    [ "$output" = "$LLVM_HOME/toolchains/lm/bin/x86_64-w64-mingw32-clang++" ]
    run "$LLVMUP_SCRIPT" which clang --toolchain lm --target aarch64-w64-mingw32
    [ "$output" = "$LLVM_HOME/toolchains/lm/bin/aarch64-w64-mingw32-clang" ]
    run "$LLVMUP_SCRIPT" run lm --target aarch64-w64-mingw32 -- clang --version
    [ "$output" = "aarch64-w64-mingw32-clang --version" ]
    run "$LLVMUP_SCRIPT" which definitely-missing-tool --toolchain lm
    [ "$status" -ne 0 ]
    run "$LLVMUP_SCRIPT" cmake-toolchain lm --target aarch64-w64-mingw32 --output "$PROJ/tc.cmake"
    [ "$status" -eq 0 ]
    grep -q 'set(CMAKE_SYSTEM_NAME Windows)' "$PROJ/tc.cmake"
    grep -q 'aarch64-w64-mingw32-clang' "$PROJ/tc.cmake"
}

fn() { bash -c "source '$BATS_TEST_DIRNAME/../../llvm-functions.sh'; $*"; }

@test "pick lists local toolchains with aliases and fails fast without a terminal" {
    fake_toolchain lm llvm-mingw 23.1.6 20261117 "sha256:5555"
    fake_winlibs wl
    "$LLVMUP_SCRIPT" alias set mine wl >/dev/null
    run fn "llvmup pick < /dev/null"
    [ "$status" -eq 2 ]
    [[ "$output" == *"lm"*"llvm-mingw"*"LLVM 23.1.6"* ]]
    [[ "$output" == *"wl"*"winlibs"*"aliases=mine"* ]]
    [[ "$output" == *"needs an interactive terminal"* ]]
}

@test "the shell function routes provider env, status --json and list --providers to the engine" {
    fake_winlibs wl
    run fn "llvmup env wl --compiler gcc --format json"
    [ "$status" -eq 0 ]
    jq -e '.set.LLVMUP_ACTIVE_COMPILER == "gcc"' <<<"$output"
    run fn "llvmup list --providers"
    [[ "$output" == *"winlibs"* ]]
    run fn "llvmup status --json"
    [ "$status" -eq 0 ]
    jq -e 'type == "object"' <<<"$output"
}

@test "default accepts a selector shorthand and records the exact installation" {
    fake_winlibs wl
    "$LLVMUP_SCRIPT" alias set win-dev wl >/dev/null
    run fn "llvmup default win-dev && llvmup default show"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wl"* ]]
}

@test "install reclaims a stale lock, refuses a live one and restores an interrupted replacement" {
    local tc="$LLVM_HOME/toolchains" g=999999
    # Stale lock (owner gone) and a backup whose installation is missing.
    mkdir -p "$tc/.lm.llvmup.lock" "$tc/lm.backup-123/bin" "$tc/lm.installing-123/bin"
    echo "$g" > "$tc/.lm.llvmup.lock/pid"
    cp -r "$tc/lm.backup-123/." "$tc/lm.backup-123" 2>/dev/null || true
    write_managed_manifest_for_request "$tc/lm.backup-123" "$("$LLVMUP_SCRIPT" resolve llvm-mingw@23 --format json)"
    run "$LLVMUP_SCRIPT" install llvm-mingw@23 --name lm
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale lock"* ]]
    [[ "$output" == *"Restored 'lm'"* ]]
    [[ "$output" == *"already installed"* ]]
    [ -d "$tc/lm" ] && [ ! -e "$tc/lm.backup-123" ] && [ ! -e "$tc/lm.installing-123" ] && [ ! -e "$tc/.lm.llvmup.lock" ]

    local transaction="$tc/.lm.llvmup-txn.abc12345"
    mkdir -p "$transaction/staging"
    mv "$tc/lm" "$transaction/previous"
    run "$LLVMUP_SCRIPT" install llvm-mingw@23 --name lm
    [ "$status" -eq 0 ]
    [[ "$output" == *"Restored 'lm'"* ]]
    [ -d "$tc/lm" ] && [ ! -e "$transaction" ]

    mkdir "$tc/.lm.llvmup.lock" && echo "$$" > "$tc/.lm.llvmup.lock/pid"
    run "$LLVMUP_SCRIPT" install llvm-mingw@23 --name lm
    [ "$status" -ne 0 ]
    [[ "$output" == *"Another llvmup operation"* ]]
}

@test "the selected target's runtime directory precedes bin/ (and GITHUB_PATH keeps that order)" {
    fake_toolchain lm llvm-mingw 23.1.6 20261117 "sha256:6666"
    mkdir -p "$LLVM_HOME/toolchains/lm/aarch64-w64-mingw32/bin"
    run "$LLVMUP_SCRIPT" env lm --target aarch64-w64-mingw32 --format json
    [ "$status" -eq 0 ]
    jq -e --arg r "$LLVM_HOME/toolchains/lm" '.prepend_path == [$r + "/aarch64-w64-mingw32/bin", $r + "/bin"]' <<<"$output"
    export GITHUB_PATH="$TEST_HOME/gp" GITHUB_ENV="$TEST_HOME/ge"; : > "$GITHUB_PATH"; : > "$GITHUB_ENV"
    run "$LLVMUP_SCRIPT" env lm --target aarch64-w64-mingw32 --format github
    [ "$(head -1 "$GITHUB_PATH")" = "$LLVM_HOME/toolchains/lm/bin" ]
    [ "$(tail -1 "$GITHUB_PATH")" = "$LLVM_HOME/toolchains/lm/aarch64-w64-mingw32/bin" ]
}

@test "config apply installs prebuilt requests through sync and keeps source builds for build options" {
    write_config 23 llvm-mingw 'kind = "prebuilt"'
    local metadata
    metadata="$("$LLVMUP_SCRIPT" resolve --config --format json)"
    cid="$(jq -r .canonical_id <<<"$metadata")"
    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "sha256:7777"
    write_managed_manifest_for_request "$LLVM_HOME/toolchains/$cid" "$metadata"
    run bash -c "cd '$PROJ'; LLVM_TEST_MODE=1 LLVM_TEST_INSTALL_NOW=y '$LLVMUP_SCRIPT' config apply"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmup sync"* ]]
    [[ "$output" == *"already installed"* ]]
    [[ "$output" != *"--from-source"* ]]

    printf '[version]\ndefault = "llvmorg-18.1.8"\n\n[build]\ncmake_flags = ["-DLLVM_ENABLE_ASSERTIONS=ON"]\n' > "$PROJ/.llvmup-config"
    run bash -c "cd '$PROJ'; LLVM_TEST_MODE=1 '$LLVMUP_SCRIPT' config apply"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmup install --from-source"* ]]
}

@test "locked commands reject missing digest, a different asset, and unauthenticated strict reuse" {
    write_config 23 llvm-mingw
    "$LLVMUP_SCRIPT" config lock --verify strict >/dev/null
    local cid digest manifest
    cid="$(jq -r '.entries["linux-x64"].canonical_id' .llvmup-lock.json)"
    digest="$(jq -r '.entries["linux-x64"].asset.digest' .llvmup-lock.json)"
    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 ""
    run "$LLVMUP_SCRIPT" run --locked -- true
    [[ "$output" == *"differs from the requested asset digest"* ]]
    [ "$status" -ne 0 ]

    fake_toolchain "$cid" llvm-mingw 23.1.6 20261117 "$digest"
    run "$LLVMUP_SCRIPT" sync --locked
    [[ "$output" == *"no authenticated origin"* ]]
    [ "$status" -ne 0 ]

    manifest="$LLVM_HOME/toolchains/$cid/.llvmup-toolchain.json"
    jq '.asset.name = "different.tar.xz"' "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    run "$LLVMUP_SCRIPT" run --locked -- true
    [[ "$output" == *"identity or asset differs"* ]]
    [ "$status" -ne 0 ]
}
