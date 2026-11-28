#!/usr/bin/env bats
# Regression tests for user-facing diagnostics: the real cause of a failure must reach the user,
# recovery hints must name supported commands, and quiet mode must never hide errors or warnings.

setup() {
    export TEST_HOME="$BATS_TMPDIR/llvmup_ux_$$"
    export HOME="$TEST_HOME"
    export LLVM_HOME="$TEST_HOME/llvm-home"
    unset LLVM_TOOLCHAINS_DIR LLVMUP_SESSION_OVERRIDE _ACTIVE_LLVM LLVMUP_ACTIVE_COMPILER LLVMUP_ACTIVE_TARGET
    export LLVMUP_DISABLE_AUTOACTIVATE=1
    export LLVMUP_SCRIPT="$BATS_TEST_DIRNAME/../../llvmup"
    export FUNCTIONS="$BATS_TEST_DIRNAME/../../llvm-functions.sh"
    mkdir -p "$LLVM_HOME/toolchains"
    cd "$TEST_HOME"
}

teardown() {
    cd /
    rm -rf "$TEST_HOME"
}

# fake_toolchain <name> <provider> <llvm> [compilers-json] [targets-json]
fake_toolchain() {
    local root="$LLVM_HOME/toolchains/$1"
    mkdir -p "$root/bin"
    printf '#!/bin/sh\necho clang\n' > "$root/bin/clang"
    cp "$root/bin/clang" "$root/bin/clang++"
    chmod +x "$root/bin/clang" "$root/bin/clang++"
    jq -n --arg id "$1" --arg p "$2" --arg v "$3" --argjson cc "${4:-[\"clang\"]}" --argjson tg "${5:-[\"x86_64-w64-mingw32\"]}" '
        {schema: 1, id: $id, origin: "managed", provider: $p, provider_release: $v, llvm_version: $v,
         host: {os: "linux", arch: "x64"}, supported_targets: $tg, default_target: $tg[0],
         variant: {crt: "ucrt", default_compiler: "clang"},
         tools: {clang: "bin/clang", "clang++": "bin/clang++"},
         capabilities: {compilers: $cc}, asset: {name: "x", digest: "sha256:00"}}' > "$root/.llvmup-toolchain.json"
}

@test "engine env reports a missing toolchain with install and list hints" {
    run "$LLVMUP_SCRIPT" env official@99
    [ "$status" -ne 0 ]
    [[ "$output" == *"No installed toolchain matches 'official@99'"* ]]
    [[ "$output" == *"llvmup install official@99"* ]]
    [[ "$output" == *"llvmup list"* ]]
}

@test "engine quotes selectors with shell metacharacters in recovery hints" {
    run "$LLVMUP_SCRIPT" run '>=99.1' -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"llvmup install '>=99.1'"* ]]
}

@test "ambiguous selector lists candidates and suggests disambiguating commands" {
    fake_toolchain official-dev official 23.1.6
    fake_toolchain win-dev winlibs 23.1.3
    run "$LLVMUP_SCRIPT" run 23 -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"'23' matches multiple providers"* ]]
    [[ "$output" == *"official-dev"* ]]
    [[ "$output" == *"win-dev"* ]]
    [[ "$output" == *"llvmup use official@23"* ]]
    [[ "$output" == *"llvmup use winlibs@23"* ]]
    [[ "$output" != *"No installed toolchain"* ]]
}

@test "unavailable compiler is reported with alternatives and without a reinstall hint" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run "$LLVMUP_SCRIPT" env cross-dev --compiler gcc
    [ "$status" -ne 0 ]
    [[ "$output" == *"cross-dev does not provide GCC"* ]]
    [[ "$output" == *"clang"* ]]
    [[ "$output" == *"llvmup provides gcc"* ]]
    [[ "$output" != *"jq: error"* ]]
    [[ "$output" != *"llvmup install"* ]]
}

@test "unsupported target lists the supported targets" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run "$LLVMUP_SCRIPT" env cross-dev --target riscv64-none
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not support target riscv64-none"* ]]
    [[ "$output" == *"x86_64-w64-mingw32"* ]]
    [[ "$output" != *"jq: error"* ]]
}

@test "env output stays clean shell code on success" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run bash -c "'$LLVMUP_SCRIPT' env cross-dev 2>&1 >/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "llvm-use keeps the real cause for an incompatible compiler and does not install" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run bash -c "source '$FUNCTIONS'; llvm-use cross-dev --compiler gcc --install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cross-dev does not provide GCC"* ]]
    [[ "$output" != *"No installed toolchain matches"* ]]
    [[ "$output" != *"installing it first"* ]]
}

@test "llvm-use keeps the real cause for an invalid target and does not install" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run bash -c "source '$FUNCTIONS'; llvm-use cross-dev --target riscv64-none --install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not support target riscv64-none"* ]]
    [[ "$output" != *"installing it first"* ]]
}

@test "llvm-use reports an ambiguous selector instead of a missing toolchain" {
    fake_toolchain official-dev official 23.1.6
    fake_toolchain win-dev winlibs 23.1.3
    run bash -c "source '$FUNCTIONS'; llvm-use 23 --install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"matches multiple providers"* ]]
    [[ "$output" != *"installing it first"* ]]
}

@test "llvm-use reports a broken alias instead of a missing toolchain" {
    printf '{"aliases":{"work":{"target_name":"gone"}}}' > "$LLVM_HOME/aliases.json"
    run bash -c "source '$FUNCTIONS'; llvm-use work --install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Alias 'work'"* ]]
    [[ "$output" != *"installing it first"* ]]
}

@test "llvm-use without --install explains a missing toolchain and how to install it" {
    run bash -c "source '$FUNCTIONS'; llvm-use official@99"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No installed toolchain matches 'official@99'"* ]]
    [[ "$output" == *"llvmup use official@99 --install"* ]]
}

@test "quiet mode still shows errors and warnings" {
    run bash -c "source '$FUNCTIONS'; QUIET_MODE=1; log_error boom; log_warn careful; log_success hidden"
    [[ "$output" == *"Error: boom"* ]]
    [[ "$output" == *"Warning: careful"* ]]
    [[ "$output" != *"hidden"* ]]
}

@test "command help works for the main commands, in the executable and the shell function" {
    for c in install use run list status config sync pin; do
        run "$LLVMUP_SCRIPT" $c --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"llvmup $c"* || "$output" == *"Usage:"* ]]
        run bash -c "source '$FUNCTIONS'; llvmup $c --help"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "help has no side effects and rejects unknown topics" {
    run "$LLVMUP_SCRIPT" install --help
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$LLVM_HOME/toolchains")" ]
    run "$LLVMUP_SCRIPT" help nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"No help available for 'nope'"* ]]
}

@test "help does not intercept arguments of the command run after --" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run "$LLVMUP_SCRIPT" run cross-dev -- sh -c 'echo "$1"' sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--help"* ]]
}

@test "disk-usage keeps -h as human-readable units" {
    run "$LLVMUP_SCRIPT" disk-usage -h
    [ "$status" -eq 0 ]
    [[ "$output" != *"Usage:"* ]]
}

@test "name collision shows only diverging identity fields and a non-destructive suggestion" {
    export LLVMUP_OFFICIAL_RELEASES_FILE="$BATS_TEST_DIRNAME/../fixtures/releases/official.json"
    export LLVMUP_WINLIBS_RELEASES_FILE="$BATS_TEST_DIRNAME/../fixtures/releases/winlibs.json"
    export LLVMUP_LLVM_MINGW_RELEASES_FILE="$BATS_TEST_DIRNAME/../fixtures/releases/llvm-mingw.json"
    export LLVMUP_ASSET_FORMATS="tar.xz,zip"
    fake_toolchain dev official 23.1.6
    run "$LLVMUP_SCRIPT" install llvm-mingw@23 --name dev
    [ "$status" -ne 0 ]
    [[ "$output" == *"Installation name 'dev' is already in use"* ]]
    [[ "$output" == *"Existing installation:"* ]]
    [[ "$output" == *"Requested installation:"* ]]
    [[ "$output" == *"Provider: official"* ]]
    [[ "$output" == *"Provider: llvm-mingw"* ]]
    [[ "$output" == *"--name <new-name>"* ]]
    [[ "$output" == *"explicitly"* ]]
    [[ "$output" == *"was not modified"* ]]
    [ -f "$LLVM_HOME/toolchains/dev/.llvmup-toolchain.json" ]
}


@test "bash completion offers help topics and zsh completion still parses" {
    run bash -c "source '$BATS_TEST_DIRNAME/../../llvmup-completion.sh'; COMP_WORDS=(llvmup help ''); COMP_CWORD=2; _llvmup_completions; printf '%s\n' \"\${COMPREPLY[@]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"config"* ]]
    if command -v zsh >/dev/null 2>&1; then
        run zsh -n "$BATS_TEST_DIRNAME/../../_llvmup"
        [ "$status" -eq 0 ]
    fi
}

@test "doctor reports an invalid runtime inventory once, not once per bad line" {
    local root="$TEST_HOME/pkg"
    mkdir -p "$root"
    cp "$BATS_TEST_DIRNAME"/../../llvmup-doctor*.sh "$root/"
    printf 'bash 755 ../escape\nbash 755 bad name extra\nbash 755 also/../bad\n' > "$root/llvmup-files.tsv"
    run bash "$root/llvmup-doctor.sh"
    [ "$(grep -c "Invalid runtime inventory" <<<"$output")" -eq 1 ]
    [[ "$output" == *"Reinstall a complete LLVMUP package"* ]]
}

@test "status --explain lists the precedence tiers with their real state" {
    fake_toolchain official-dev official 23.1.6
    fake_toolchain win-dev winlibs 23.1.3
    ln -s "$LLVM_HOME/toolchains/official-dev" "$LLVM_HOME/default"
    printf '[toolchain]\nversion = 99\nprovider = winlibs\n' > "$TEST_HOME/.llvmup-config"

    run "$LLVMUP_SCRIPT" status --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"Selection precedence"* ]]
    [[ "$output" == *"Project config"*"winlibs@99"*"not installed"* ]]
    [[ "$output" == *"User default"*"official-dev"*"selected"* ]]

    LLVMUP_SESSION_OVERRIDE=win-dev run "$LLVMUP_SCRIPT" status --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"Session override"*"win-dev"*"selected"* ]]
    [[ "$output" == *"User default"*"official-dev"*"overridden"* ]]
    [[ "$output" == *"llvmup use --auto"* ]]
}

@test "messages carry no ANSI escapes when redirected or when NO_COLOR is set" {
    run bash -c "source '$FUNCTIONS'; log_error boom 2>&1; log_warn careful 2>&1"
    [[ "$output" == *"Error: boom"* ]]
    [[ "$output" != *$'\033'* ]]
    run env NO_COLOR=1 bash -c "source '$FUNCTIONS'; log_error boom 2>&1"
    [[ "$output" != *$'\033'* ]]
    run "$LLVMUP_SCRIPT" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command 'frobnicate'"* ]]
    [[ "$output" != *$'\033'* ]]
}

@test "GitHub rate limiting is reported as such, without exposing the token" {
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/curl" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in -D) hdr="$2"; shift 2 ;; *) shift ;; esac
done
printf 'HTTP/2 403\r\nx-ratelimit-remaining: 0\r\nx-ratelimit-reset: 1893456000\r\n\r\n' > "$hdr"
exit 22
STUB
    chmod +x "$TEST_HOME/bin/curl"
    run env PATH="$TEST_HOME/bin:$PATH" GITHUB_TOKEN=ghp_secret123 "$LLVMUP_SCRIPT" resolve llvm-mingw@23
    [ "$status" -ne 0 ]
    [[ "$output" == *"rate limit was exceeded"* ]]
    [[ "$output" == *"GITHUB_TOKEN"* ]]
    [[ "$output" != *"ghp_secret123"* ]]
}

@test "zsh function exposes help, keeps use diagnostics and never colors redirected output" {
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run zsh -c "source '$FUNCTIONS'; llvmup use --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmup use"* ]]
    run zsh -c "source '$FUNCTIONS'; llvmup help nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No help available for 'nope'"* ]]
    run zsh -c "source '$FUNCTIONS'; llvmup use cross-dev --compiler gcc --install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not provide GCC"* ]]
    [[ "$output" != *"installing it first"* ]]
    [[ "$output" != *$'\033'* ]]
    run zsh -c "source '$FUNCTIONS'; llvmup use cross-dev && llvmup status && llvmup deactivate"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active toolchain: cross-dev"* ]]
    [[ "$output" == *"Deactivated cross-dev"* ]]
}

@test "download failures explain a write error, an HTTP error or an unreachable server" {
    mkdir -p "$TEST_HOME/bin"
    sed -n '/^eng_err()/,/^eng_die()/p;/^eng_download()/,/^}/p' "$BATS_TEST_DIRNAME/../../libexec/sh/llvmup-engine.sh" > "$TEST_HOME/dl.sh"
    try_download() {
        printf '#!/bin/sh\nexit %s\n' "$1" > "$TEST_HOME/bin/curl"
        chmod +x "$TEST_HOME/bin/curl"
        run env PATH="$TEST_HOME/bin:$PATH" bash -c "ENGINE_QUIET=1; source '$TEST_HOME/dl.sh'; eng_sha256() { :; }; (eng_download https://example.invalid/a.zip '$TEST_HOME/out/a.zip')"
        [ "$status" -ne 0 ]
    }
    try_download 6;  [[ "$output" == *"could not reach the server"* ]]
    try_download 23; [[ "$output" == *"disk may be full"* ]]
    try_download 22; [[ "$output" == *"server rejected the request"* ]]
}

@test "remove, alias remove and toolchain unlink say what was preserved" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run "$LLVMUP_SCRIPT" alias set work cross-dev
    [ "$status" -eq 0 ]
    run "$LLVMUP_SCRIPT" alias remove work
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alias 'work' removed. Toolchain preserved."* ]]
    [ -f "$LLVM_HOME/toolchains/cross-dev/.llvmup-toolchain.json" ]

    mkdir -p "$TEST_HOME/ext/bin"
    printf '#!/bin/sh\n' > "$TEST_HOME/ext/bin/clang"; chmod +x "$TEST_HOME/ext/bin/clang"
    cp "$TEST_HOME/ext/bin/clang" "$TEST_HOME/ext/bin/clang++"
    run "$LLVMUP_SCRIPT" toolchain link ext "$TEST_HOME/ext"
    [ "$status" -eq 0 ]
    run "$LLVMUP_SCRIPT" toolchain unlink ext
    [ "$status" -eq 0 ]
    [[ "$output" == *"unlinked. External files preserved."* ]]
    [ -x "$TEST_HOME/ext/bin/clang" ]

    ln -s "$LLVM_HOME/toolchains/cross-dev" "$LLVM_HOME/default"
    run "$LLVMUP_SCRIPT" remove cross-dev
    [ "$status" -ne 0 ]
    [[ "$output" == *"user default"* ]]
    [[ "$output" == *"--force"* ]]
    run "$LLVMUP_SCRIPT" remove nothing-here
    [[ "$output" == *"llvmup list"* ]]
}

@test "automation outputs stay undecorated: where, which, info --json, status --json, env" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run bash -c "'$LLVMUP_SCRIPT' where cross-dev 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "$LLVM_HOME/toolchains/cross-dev" ]

    run bash -c "'$LLVMUP_SCRIPT' which clang --toolchain cross-dev 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "$LLVM_HOME/toolchains/cross-dev/bin/clang" ]

    run bash -c "'$LLVMUP_SCRIPT' info cross-dev --json 2>/dev/null"
    [ "$status" -eq 0 ]
    jq -e '.install_name == "cross-dev"' <<<"$output"
    [[ "$output" != *$'\033'* ]]

    run bash -c "'$LLVMUP_SCRIPT' status --json 2>/dev/null"
    [ "$status" -eq 0 ]
    jq -e 'type == "object"' <<<"$output"

    run bash -c "'$LLVMUP_SCRIPT' env cross-dev --format json 2>/dev/null"
    [ "$status" -eq 0 ]
    jq -e '.set._ACTIVE_LLVM == "cross-dev"' <<<"$output"

    run bash -c "eval \"\$('$LLVMUP_SCRIPT' env cross-dev 2>/dev/null)\"; printf '%s' \"\$_ACTIVE_LLVM\""
    [ "$output" = "cross-dev" ]
}

@test "inspection commands report one cause, and an empty provides result says so on stderr" {
    fake_toolchain cross-dev llvm-mingw 23.1.6
    run "$LLVMUP_SCRIPT" info nothing
    [ "$status" -ne 0 ]
    [[ "$output" == *"No installed toolchain matches 'nothing'"* ]]
    [[ "$output" != *"No toolchain is selected"* ]]
    [ "$(grep -c '^Error:' <<<"$output")" -eq 1 ]

    run "$LLVMUP_SCRIPT" info
    [ "$status" -ne 0 ]
    [[ "$output" == *"No toolchain is selected, configured, or set as default."* ]]
    [[ "$output" == *"llvmup use <toolchain>"* ]]

    run bash -c "'$LLVMUP_SCRIPT' provides gcc 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c "'$LLVMUP_SCRIPT' provides gcc 2>&1 >/dev/null"
    [[ "$output" == *"No installed toolchain provides 'gcc'"* ]]
}

@test "auto-activation announces a change once and stays silent when nothing changes" {
    # The legacy activation resolves toolchains below $HOME/.llvm.
    local tc="$HOME/.llvm/toolchains/llvmorg-18.1.8"
    mkdir -p "$tc/bin" "$TEST_HOME/proj"
    for t in clang clang++ clangd lld llvm-config; do printf '#!/bin/sh\n' > "$tc/bin/$t"; chmod +x "$tc/bin/$t"; done
    printf '[version]\ndefault = "llvmorg-18.1.8"\n[project]\nauto_activate = true\n' > "$TEST_HOME/proj/.llvmup-config"
    unset LLVMUP_DISABLE_AUTOACTIVATE LLVM_HOME
    # Sourcing the functions runs the hook once; repeating it must not announce anything again.
    run bash -c "cd '$TEST_HOME/proj'; source '$FUNCTIONS'; echo ---; llvm-autoactivate; llvm-autoactivate"
    [ "$status" -eq 0 ]
    first="${output%%---*}"; second="${output##*---}"
    [[ "$first" == *"Using llvmorg-18.1.8"* ]]
    [ "$(grep -c "Using llvmorg" <<<"$output")" -eq 1 ]
    [[ "$first" == *".llvmup-config"* ]]
    [ -z "$(tr -d '[:space:]' <<<"$second")" ]
}

@test "list fits long names, shows only the legend entries that apply, and works in zsh" {
    fake_toolchain llvm-mingw-20261117-ucrt-linux-x64 llvm-mingw 23.1.6
    fake_toolchain short official 23.1.1
    run bash -c "source '$FUNCTIONS'; llvm-list"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvm-mingw-20261117-ucrt-linux-x64"* ]]
    [[ "$output" == *"2 toolchains installed."* ]]
    [[ "$output" != *"* active"* ]]
    # every row has the provider column at the same offset
    # (marker is blank here, so field 1 is the name and field 2 the provider)
    awk 'NR > 1 && NF == 3 && $0 !~ /installed/ { n = index($0, $1) + length($1); print n + index(substr($0, n), $2) }' <<<"$output" | sort -u | wc -l | grep -qx 1
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    run zsh -c "source '$FUNCTIONS'; llvm-list"
    [ "$status" -eq 0 ]
    [[ "$output" == *"short"* && "$output" == *"2 toolchains installed."* ]]
}

@test "doctor groups the accessible runtime files and states each piece of advice once" {
    run bash -c "'$BATS_TEST_DIRNAME/../../llvmup-doctor.sh' 2>&1"
    [ "$(grep -c '^PASS \[installation.file\]' <<<"$output")" -eq 1 ]
    [[ "$output" == *"runtime files are accessible"* ]]
    # --verbose and --json keep every file
    run bash -c "'$BATS_TEST_DIRNAME/../../llvmup-doctor.sh' --verbose 2>&1"
    [ "$(grep -c '^PASS \[installation.file\]' <<<"$output")" -gt 3 ]
    run bash -c "'$BATS_TEST_DIRNAME/../../llvmup-doctor.sh' --json 2>/dev/null"
    [ "$(jq '[.checks[] | select(.id == "installation.file")] | length' <<<"$output")" -gt 3 ]
}

@test "status --explain says when the project configuration requests no toolchain" {
    fake_toolchain official-dev official 23.1.6
    ln -s "$LLVM_HOME/toolchains/official-dev" "$LLVM_HOME/default"
    printf '[project]\nauto_activate = false\n' > "$TEST_HOME/.llvmup-config"
    run "$LLVMUP_SCRIPT" status --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not request a toolchain"* ]]
    [[ "$output" == *"Project config"*"not set"* ]]
}

@test "ambiguous selector quotes metacharacters and embedded single quotes in suggestions" {
    fake_toolchain official-dev official 23.1.6
    fake_toolchain win-dev winlibs 23.1.3
    run "$LLVMUP_SCRIPT" run '>=23' -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"llvmup use 'official@>=23'"* ]]
    [[ "$output" == *"llvmup use 'winlibs@>=23'"* ]]

    run "$LLVMUP_SCRIPT" run "23'foo" -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"llvmup install '23'\''foo'"* ]]
}

@test "eng_download maps wget exit codes separately from curl" {
    local mockbin="$TEST_HOME/mockbin" t
    mkdir -p "$mockbin"
    for t in dirname basename mkdir mktemp rm mv; do
        ln -s "$(command -v "$t")" "$mockbin/$t"
    done
    cat > "$mockbin/wget" <<'SH'
#!/bin/sh
exit "${MOCK_WGET_RC:-8}"
SH
    chmod +x "$mockbin/wget"

    run env PATH="$mockbin" MOCK_WGET_RC=3 /bin/bash -c "
        source '$BATS_TEST_DIRNAME/../../libexec/sh/llvmup-engine.sh' >/dev/null 2>&1 || true
        eng_download 'https://example.invalid/a.tar.xz' '$TEST_HOME/a.tar.xz'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"disk may be full"* ]]

    run env PATH="$mockbin" MOCK_WGET_RC=8 /bin/bash -c "
        source '$BATS_TEST_DIRNAME/../../libexec/sh/llvmup-engine.sh' >/dev/null 2>&1 || true
        eng_download 'https://example.invalid/a.tar.xz' '$TEST_HOME/a.tar.xz'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTP error"* ]]

    run env PATH="$mockbin" MOCK_WGET_RC=4 /bin/bash -c "
        source '$BATS_TEST_DIRNAME/../../libexec/sh/llvmup-engine.sh' >/dev/null 2>&1 || true
        eng_download 'https://example.invalid/a.tar.xz' '$TEST_HOME/a.tar.xz'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not reach the server"* ]]
}

@test "collision diagnostic reports differences in variant attributes like threads" {
    local existing plan
    existing='{"provider":"winlibs","provider_release":"15.2.0","llvm_version":"21.1.8","host":{"os":"windows","arch":"x64"},"variant":{"crt":"ucrt","threads":"posix"}}'
    plan='{"provider":"winlibs","release_tag":"15.2.0","llvm_version":"21.1.8","host":{"os":"windows","arch":"x64"},"variant":{"crt":"ucrt","threads":"mcf"}}'
    run bash -c "
        source '$BATS_TEST_DIRNAME/../../libexec/sh/llvmup-engine.sh' >/dev/null 2>&1 || true
        eng_collision_die '$existing' '$plan' 'winlibs@21' 'win-dev'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"Threads: posix"* ]]
    [[ "$output" == *"Threads: mcf"* ]]
}
