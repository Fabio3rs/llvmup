#!/usr/bin/env bats

setup() {
    export TEST_HOME="$BATS_TMPDIR/llvmup_lifecycle_$$"
    export HOME="$TEST_HOME"
    export LLVM_HOME="$TEST_HOME/llvm-home"
    export LLVM_TOOLCHAINS_DIR="$TEST_HOME/toolchains"
    export LLVM_SOURCES_DIR="$TEST_HOME/sources"
    export LLVMUP_DISABLE_AUTOACTIVATE=1
    export LLVMUP_SCRIPT="$BATS_TEST_DIRNAME/../../llvmup"
    mkdir -p "$LLVM_HOME" "$LLVM_TOOLCHAINS_DIR" "$LLVM_SOURCES_DIR"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "llvmup list --json reports active and default versions with real nulls" {
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin" "$LLVM_TOOLCHAINS_DIR/source-custom/bin"
    ln -s "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8" "$LLVM_HOME/default"

    run bash -c "source '$BATS_TEST_DIRNAME/../../llvm-functions.sh'; export _ACTIVE_LLVM=source-custom; llvmup list --json"

    [ "$status" -eq 0 ]
    jq -e '.active_version == "source-custom" and .default_version == "llvmorg-18.1.8"' <<< "$output"
    jq -e '.installed_versions | length == 2' <<< "$output"
    jq -e '.installed_versions[] | select(.name == "llvmorg-18.1.8") | .default == true' <<< "$output"
}

@test "llvmup list --remote uses stable semver order and supports json" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"

    run "$LLVMUP_SCRIPT" list --remote --json

    [ "$status" -eq 0 ]
    jq -e '.remote_versions | type == "array" and length > 1' <<< "$output"
    [ "$(jq -r '.remote_versions[0]' <<< "$output")" = "llvmorg-21.1.0" ]
}

@test "llvmup remove refuses a default toolchain and force removes only its installation" {
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin" "$LLVM_SOURCES_DIR/llvmorg-18.1.8"
    mkdir -p "$LLVM_HOME"
    ln -s "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8" "$LLVM_HOME/default"

    run "$LLVMUP_SCRIPT" remove llvmorg-18.1.8
    [ "$status" -ne 0 ]
    [[ "$output" == *"default LLVM version"* ]]

    run "$LLVMUP_SCRIPT" remove llvmorg-18.1.8 --force
    [ "$status" -eq 0 ]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8" ]
    [ ! -L "$LLVM_HOME/default" ]
    [ -d "$LLVM_SOURCES_DIR/llvmorg-18.1.8" ]
}

@test "llvmup remove rejects traversal and multiple identifiers" {
    run "$LLVMUP_SCRIPT" remove ../outside
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid installed LLVM identifier"* ]]

    run "$LLVMUP_SCRIPT" remove one two
    [ "$status" -ne 0 ]
    [[ "$output" == *"Only one"* ]]
}

@test "forced removal warns when an env-export activation leaves PATH stale" {
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin"
    export LLVMUP_ACTIVE_VERSION="llvmorg-18.1.8"
    export LLVMUP_ACTIVE_PATH="$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8"

    run bash -c "source '$BATS_TEST_DIRNAME/../../llvm-functions.sh'; llvmup remove llvmorg-18.1.8 --force"

    [ "$status" -eq 0 ]
    [[ "$output" == *"PATH may still reference the removed toolchain"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8" ]
}

@test "llvmup default unset is idempotent and removes broken symlinks" {
    mkdir -p "$LLVM_HOME"
    ln -s "$LLVM_TOOLCHAINS_DIR/missing" "$LLVM_HOME/default"

    run "$LLVMUP_SCRIPT" default unset
    [ "$status" -eq 0 ]
    [ ! -L "$LLVM_HOME/default" ]

    run "$LLVMUP_SCRIPT" default unset
    [ "$status" -eq 0 ]
    [[ "$output" == *"No default LLVM version"* ]]
}

@test "llvmup default unset refuses an ordinary directory" {
    mkdir -p "$LLVM_HOME/default/keep"

    run "$LLVMUP_SCRIPT" default unset

    [ "$status" -ne 0 ]
    [ -d "$LLVM_HOME/default/keep" ]
    [[ "$output" == *"Refusing to remove non-symlink"* ]]
}

@test "executable config apply loads the nearest project config" {
    mkdir -p "$TEST_HOME/project/subdir"
    printf '[version]\ndefault = "llvmorg-18.1.8"\n' > "$TEST_HOME/project/.llvmup-config"

    run bash -c "cd '$TEST_HOME/project/subdir'; LLVM_TEST_MODE=1 '$LLVMUP_SCRIPT' config apply"

    [ "$status" -eq 0 ]
    [[ "$output" == *"To install later"* ]]
}

@test "llvmup forwards source list-only mode" {
    run env LLVM_TEST_MODE=1 "$LLVMUP_SCRIPT" install --from-source --list-only

    [ "$status" -eq 0 ]
    [[ "$output" == *"Available LLVM releases"* ]]
}
