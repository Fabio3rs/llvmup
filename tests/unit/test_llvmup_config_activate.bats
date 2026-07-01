#!/usr/bin/env bats

# Test setup for llvmup config activate command
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export MOCK_SCRIPT_DIR="$TEST_DIR/mock_scripts"
    mkdir -p "$MOCK_SCRIPT_DIR"

    # Path to the actual llvmup script
    export LLVMUP_SCRIPT="$(pwd)/llvmup"
}

teardown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "llvmup config activate - shows env guidance for executables" {
    run "$LLVMUP_SCRIPT" config activate

    [ "$status" -eq 1 ]
    [[ "$output" == *"config activate"* ]]
    [[ "$output" == *"llvmup env --config"* ]]
}

@test "llvmup config activate - ignores extra args and still shows env guidance" {
    run "$LLVMUP_SCRIPT" config activate --verbose --some-arg

    [ "$status" -eq 1 ]
    [[ "$output" == *"llvmup env --config"* ]]
}

@test "llvmup config - shows available subcommands including activate" {
    run "$LLVMUP_SCRIPT" config

    [ "$status" -eq 1 ]
    [[ "$output" == *"Available subcommands: init, load, apply, activate"* ]]
}

@test "llvmup config init auto-loads sibling llvm-functions.sh" {
    export TEST_CONFIG_DIR="$TEST_DIR/config_sibling"
    mkdir -p "$TEST_CONFIG_DIR"
    cp "$LLVMUP_SCRIPT" "$TEST_CONFIG_DIR/llvmup"
    cp "$(pwd)/llvm-functions.sh" "$TEST_CONFIG_DIR/llvm-functions.sh"
    chmod +x "$TEST_CONFIG_DIR/llvmup"

    cd "$TEST_CONFIG_DIR"
    export LLVM_TEST_MODE=1
    export LLVM_TEST_DEFAULT_VERSION="llvmorg-18.1.8"
    export LLVM_TEST_PROFILE="full"

    run ./llvmup config init

    [ "$status" -eq 0 ]
    [ -f "$TEST_CONFIG_DIR/.llvmup-config" ]
}

@test "llvmup help - shows config command in usage" {
    run "$LLVMUP_SCRIPT" help

    [ "$status" -eq 0 ]
    [[ "$output" == *"LLVM Manager - Complete Usage Guide"* ]]
    [[ "$output" == *"llvm-config-init"* ]]
    [[ "$output" == *"llvm-config-activate"* ]]
}
