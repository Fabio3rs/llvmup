#!/usr/bin/env bats
setup() {
    REPO=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    export LLVMUP_DISABLE_AUTOACTIVATE=1 LLVM_TEST_MODE=1
    export LLVM_HOME="$BATS_TEST_TMPDIR/data with spaces"
    export LLVM_TOOLCHAINS_DIR="$LLVM_HOME/custom toolchains"
    export LLVMUP_INSTALL_DIR="$REPO"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME" "$LLVM_TOOLCHAINS_DIR" "$BATS_TEST_TMPDIR/project"
    cd "$BATS_TEST_TMPDIR/project"
    # Stop ancestor lookup at our fixture, even if another suite left /tmp config.
    printf '[version]\ndefault = "latest"\n' > .llvmup-config
    unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC_SET _OLD_CXX_SET LLVMUP_ACTIVE_VERSION LLVM_ACTIVE_VERSION
}
check() { printf '%s' "$output" | jq -e --arg id "$1" --arg state "$2" '.checks | any(.id == $id and .status == $state)' >/dev/null; }
fake_toolchain() {
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin"
    for tool in clang clang++; do
        printf '#!/bin/sh\nexit 0\n' > "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin/$tool"
        chmod +x "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin/$tool"
    done
}
@test 'healthy custom installation emits schema JSON without a toolchain or default' {
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    check toolchain.empty SKIP
    check toolchain.default SKIP
    printf '%s' "$output" | jq -e '.schema_version == 1 and .exit_code == 0 and all(.checks[]; has("severity") and has("recommendation") and has("subject"))'
}
@test 'incomplete installation remains diagnosable' {
    mkdir "$BATS_TEST_TMPDIR/runtime"
    cp "$REPO/llvmup" "$REPO"/llvmup-doctor*.sh "$BATS_TEST_TMPDIR/runtime/"
    run "$BATS_TEST_TMPDIR/runtime/llvmup" doctor --json
    [ "$status" -eq 1 ]
    check installation.file FAIL
}
@test 'incomplete toolchain and broken default fail without removing anything' {
    mkdir -p "$LLVM_TOOLCHAINS_DIR/broken/bin"
    ln -s "$LLVM_TOOLCHAINS_DIR/nonexistent" "$LLVM_HOME/default"
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 1 ]
    check toolchain.compilers FAIL
    check toolchain.default FAIL
    [ -L "$LLVM_HOME/default" ]
    [ -d "$LLVM_TOOLCHAINS_DIR/broken" ]
}
@test 'healthy fake toolchain and verification record do not execute binaries' {
    fake_toolchain
    printf '{"schema":1,"version":"18.1.8","policy":"strict"}' > "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/.llvmup-verification.json"
    printf '#!/bin/sh\ntouch "%s"\n' "$BATS_TEST_TMPDIR/executed" > "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin/clang"
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    check toolchain.compilers PASS
    check toolchain.metadata PASS
    [ ! -e "$BATS_TEST_TMPDIR/executed" ]
}
@test 'missing dependencies still produce valid JSON without jq' {
    mkdir "$BATS_TEST_TMPDIR/bin"
    for tool in bash dirname; do ln -s "$(command -v "$tool")" "$BATS_TEST_TMPDIR/bin/$tool"; done
    run env PATH="$BATS_TEST_TMPDIR/bin" /bin/bash "$REPO/llvmup-doctor.sh" --json
    [ "$status" -eq 0 ]
    check dependency.jq WARN
    check dependency.curl WARN
    check dependency.timeout WARN
}
@test 'invalid config is reported without evaluation' {
    printf '[version]\ndefault = "$(touch %s)"\n' "$BATS_TEST_TMPDIR/executed" > .llvmup-config
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 1 ]
    check project.config FAIL
    [ ! -e "$BATS_TEST_TMPDIR/executed" ]
}
@test 'project expression uses installed versions offline' {
    fake_toolchain
    printf '[version]\ndefault = "~18.1.8"\n[project]\nauto_activate = true\n' > .llvmup-config
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    check project.version PASS
    check project.autoactivate WARN
}
@test 'stale active environment fails and intentional CC override warns' {
    export _ACTIVE_LLVM=missing
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 1 ]
    check environment.active FAIL
    fake_toolchain
    export _ACTIVE_LLVM=llvmorg-18.1.8 CC=ccache
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    check environment.override WARN
    check environment.compiler WARN
}
@test 'duplicate shell initialization and broken completion are detected' {
    printf 'source "%s/llvm-functions.sh"\nsource "%s/llvm-functions.sh"\n' "$REPO" "$REPO" > "$HOME/.bashrc"
    run "$REPO/llvmup" doctor --json
    check shell.initialization WARN
    mkdir "$BATS_TEST_TMPDIR/runtime"
    cp "$REPO/llvmup" "$REPO"/llvmup-doctor*.sh "$BATS_TEST_TMPDIR/runtime/"
    run "$BATS_TEST_TMPDIR/runtime/llvmup" doctor --json
    check shell.completion FAIL
}
@test 'offline read-only repeated runs preserve filesystem and environment' {
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\ntouch "%s"\nexit 99\n' "$BATS_TEST_TMPDIR/network-called" > "$BATS_TEST_TMPDIR/bin/curl"
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    fake_toolchain
    before=$(find "$HOME" "$LLVM_HOME" "$PWD" -printf '%p %s %T@\n' | sort)
    old_path=$PATH
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    first=$output
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    [ "$first" = "$output" ]
    after=$(find "$HOME" "$LLVM_HOME" "$PWD" -printf '%p %s %T@\n' | sort)
    [ "$before" = "$after" ]
    [ "$PATH" = "$old_path" ]
    [ ! -e "$BATS_TEST_TMPDIR/network-called" ]
}
@test 'deep probes restore state in isolation and clean temporary files' {
    export TMPDIR="$BATS_TEST_TMPDIR" CC='custom compiler'
    run "$REPO/llvmup" doctor --deep --json
    [ "$status" -eq 0 ]
    check deep.activation PASS
    check deep.completion PASS
    [ "$CC" = 'custom compiler' ]
    [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'llvmup-doctor.*' -print)" ]
}
@test 'invalid options have exit 2 and valid JSON' {
    run "$REPO/llvmup" doctor --fix --json
    [ "$status" -eq 2 ]
    check arguments FAIL
}
@test 'shell function dispatch does not pollute JSON or mutate caller state' {
    run bash -c 'source "$1/llvm-functions.sh"; llvmup doctor --json' _ "$REPO"
    [ "$status" -eq 0 ]
    check shell.function PASS
}
@test 'doctor completion flags are available without remote queries' {
    run bash -c 'source "$1/llvmup-completion.sh"; COMP_WORDS=(llvmup doctor --); COMP_CWORD=2; _llvmup_completions; printf "%s\n" "${COMPREPLY[@]}"' _ "$REPO"
    [ "$status" -eq 0 ]
    [[ $output == *--deep* && $output == *--json* && $output == *--network* ]]
}
@test 'installer packages doctor from a different working directory' {
    export LLVMUP_INSTALL_DIR="$BATS_TEST_TMPDIR/installed/bin" LLVMUP_PREFIX="$BATS_TEST_TMPDIR/installed"
    run bash "$REPO/install.sh" --no-profile
    [ "$status" -eq 0 ]
    run "$LLVMUP_INSTALL_DIR/llvmup" doctor --deep --json
    [ "$status" -eq 0 ]
    check deep.activation PASS
}
@test 'Zsh function finds doctor beside sourced functions without an install override' {
    command -v zsh >/dev/null || skip 'Zsh unavailable'
    unset LLVMUP_INSTALL_DIR
    run zsh -fc 'source "$1/llvm-functions.sh"; llvmup doctor --json' _ "$REPO"
    [ "$status" -eq 0 ]
    check shell.function PASS
}
@test 'malformed config, duplicate keys, and invalid range are rejected' {
    for content in $'[version]\ndefault = "18.1.8"\ninvalid line' $'[version]\ndefault="18"\ndefault="19"' $'[version]\ndefault="~garbage"'; do
        printf '%s\n' "$content" > .llvmup-config
        run "$REPO/llvmup" doctor --json
        [ "$status" -eq 1 ]
        check project.config FAIL
    done
}
@test 'current safe profile markers are not reported as obsolete' {
    printf '# LLVM Manager Functions - Start\nsource "%s/llvm-functions.sh"\n# LLVM Manager Functions - End\n' "$REPO" > "$HOME/.bashrc"
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    ! check shell.legacy WARN
}
@test 'JSON escapes control characters, quotes and non-ASCII paths' {
    export LLVM_TOOLCHAINS_DIR="$LLVM_HOME/quoted\"dir"$'\tñ'
    mkdir -p "$LLVM_TOOLCHAINS_DIR"
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e --arg path "$LLVM_TOOLCHAINS_DIR" '.checks | any(.subject == $path)'
}
@test 'network probes are opt-in and bounded with curl timeout arguments' {
    mkdir "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$NETWORK_CALLS"
printf '[{"tag_name":"llvmorg-18.1.8"}]'
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export NETWORK_CALLS="$BATS_TEST_TMPDIR/network-calls" PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    run "$REPO/llvmup" doctor --network --json
    [ "$status" -eq 0 ]
    check network.github PASS
    check network.redirect PASS
    [ "$(wc -l < "$NETWORK_CALLS")" -eq 2 ]
    [ "$(grep -c -- '--connect-timeout 3 --max-time 8' "$NETWORK_CALLS")" -eq 2 ]
}
@test 'completion fetch does not require the optional timeout command' {
    run bash -c '
        export LLVM_COMPLETION_CACHE_DIR="$2/cache"
        source "$1/llvmup-completion-common.sh"
        timeout() { return 99; }
        curl() { printf "[{\"tag_name\":\"llvmorg-18.1.8\"}]"; }
        _llvmup_get_remote_versions
    ' _ "$REPO" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = llvmorg-18.1.8 ]
}
@test 'profile initialization pointing at a removed installation warns' {
    printf 'source "/missing/llvmup/llvm-functions.sh"\n' > "$HOME/.bashrc"
    run "$REPO/llvmup" doctor --json
    [ "$status" -eq 0 ]
    check shell.source WARN
}
@test 'missing doctor component is reported as JSON without stopping other checks' {
    mkdir "$BATS_TEST_TMPDIR/runtime"
    cp "$REPO/llvmup" "$REPO"/llvmup-doctor*.sh "$BATS_TEST_TMPDIR/runtime/"
    rm "$BATS_TEST_TMPDIR/runtime/llvmup-doctor-project.sh"
    run "$BATS_TEST_TMPDIR/runtime/llvmup" doctor --json
    [ "$status" -eq 1 ]
    check installation.module FAIL
    check network.github SKIP
}
