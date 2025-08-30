#!/usr/bin/env bats

setup() {
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-19.1.7"
    export TEST_VERSION2="llvmorg-20.1.0"

    mkdir -p "$TOOLCHAINS_DIR/$TEST_VERSION/bin"
    mkdir -p "$TOOLCHAINS_DIR/$TEST_VERSION2/bin"

    for binary in clang clang++ clangd lld llvm-config lldb; do
        echo '#!/bin/bash
echo "Mock '$binary' version 19.1.7"' > "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        echo '#!/bin/bash
echo "Mock '$binary' version 20.1.0"' > "$TOOLCHAINS_DIR/$TEST_VERSION2/bin/$binary"
        chmod +x "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        chmod +x "$TOOLCHAINS_DIR/$TEST_VERSION2/bin/$binary"
    done

    mkdir -p "$TEST_DIR/.local/bin"
    cp "$BATS_TEST_DIRNAME/../../llvm-activate" "$TEST_DIR/.local/bin/"
    cp "$BATS_TEST_DIRNAME/../../llvm-deactivate" "$TEST_DIR/.local/bin/"
    cp "$BATS_TEST_DIRNAME/../../llvm-vscode-activate" "$TEST_DIR/.local/bin/"

    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
}

teardown() {
    export HOME="$HOME_BACKUP"
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
}

@test "llvm-activate function shows usage when no argument provided" {
    run llvm-activate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: llvm-activate <version>"* ]]
    [[ "$output" == *"$TEST_VERSION"* ]]
}

@test "llvm-activate function fails with non-existent version" {
    run llvm-activate "nonexistent-version"
    [ "$status" -eq 1 ]
}

@test "llvm-activate function activates existing version successfully" {
    (
        llvm-activate "$TEST_VERSION"
        result=$?
        [ "$result" -eq 0 ]
        [[ "$PATH" == *"$TOOLCHAINS_DIR/$TEST_VERSION/bin"* ]]
    )
}

@test "llvm-deactivate function works" {
    (
        llvm-activate "$TEST_VERSION"
        llvm-deactivate
        result=$?
        [ "$result" -eq 0 ]
    )
}

@test "llvm-status shows no active version initially" {
    run llvm-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"❌ Status: INACTIVE"* ]]
}

@test "llvm-list shows installed versions" {
    run llvm-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_VERSION"* ]]
    [[ "$output" == *"$TEST_VERSION2"* ]]
}
