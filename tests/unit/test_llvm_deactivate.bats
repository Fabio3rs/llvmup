#!/usr/bin/env bats

# Test setup for bash functions testing (using llvm-functions.sh)
setup() {
    # Set test mode environment variables
    export LLVM_TEST_MODE=1
    export LLVMUP_DISABLE_AUTOACTIVATE=1

    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-19.1.7"

    # Set up directory configuration for new system
    export LLVM_CUSTOM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export LLVM_CUSTOM_SOURCES_DIR="$TEST_DIR/.llvm/sources"

    # Create mock LLVM toolchain
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/$TEST_VERSION/bin"

    # Create mock LLVM binaries
    for binary in clang clang++ clangd lld llvm-config lldb; do
        echo '#!/bin/bash
echo "Mock '$binary' version 19.1.7"' > "$LLVM_CUSTOM_TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        chmod +x "$LLVM_CUSTOM_TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
    done

    # Create mock scripts in ~/.local/bin for the functions to find
    mkdir -p "$TEST_DIR/.local/bin"

    # Copy real scripts to mock location
    cp "$BATS_TEST_DIRNAME/../../llvm-activate" "$TEST_DIR/.local/bin/"
    cp "$BATS_TEST_DIRNAME/../../llvm-deactivate" "$TEST_DIR/.local/bin/"
    cp "$BATS_TEST_DIRNAME/../../llvm-vscode-activate" "$TEST_DIR/.local/bin/"

    # Source the functions
    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
}

# Test cleanup
teardown() {
    # Restore original environment
    export HOME="$HOME_BACKUP"

    # Clean up test directory
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
}

@test "llvm-deactivate function handles no active version gracefully" {
    run llvm-deactivate
    [ "$status" -eq 0 ]
    # Should handle the case where no LLVM version is active
}

@test "llvm-deactivate function can be called after activation" {
    # First activate an LLVM version
    run llvm-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]

    # Then deactivate
    run llvm-deactivate
    [ "$status" -eq 0 ]
    [[ "$output" == *"LLVM environment successfully deactivated"* ]]
}

@test "llvm-deactivate function works with bash function integration" {
    # Simple test that the function exists and can be called
    run llvm-deactivate
    [ "$status" -eq 0 ]
}
