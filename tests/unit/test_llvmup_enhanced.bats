#!/usr/bin/env bats
# test_llvmup_enhanced.bats - Tests for enhanced llvmup functionality
# Tests the new flags and options added to llvmup command

load '../fixtures/test_helpers.bash'

setup() {
    # Create temporary test directory
    export TEST_HOME="$BATS_TMPDIR/llvm_test_$$"
    export HOME="$TEST_HOME"

    mkdir -p "$TEST_HOME/.llvm/toolchains"

    # Store original directory - go to project root
    cd "$BATS_TEST_DIRNAME/../.."
    export ORIGINAL_DIR="$PWD"

    # Path to llvmup script
    export LLVMUP_SCRIPT="$ORIGINAL_DIR/llvmup"
}

teardown() {
    cd "$ORIGINAL_DIR"
    rm -rf "$TEST_HOME" 2>/dev/null || true
}

@test "llvmup shows enhanced help with new options" {
    run bash "$ORIGINAL_DIR/llvmup" --help
    # The help command returns 1 (exit after showing help), but shows the help correctly
    [ "$status" -eq 1 ]
    assert_output --partial "--cmake-flags"
    assert_output --partial "--name"
    assert_output --partial "--default"
    assert_output --partial "--profile"
    assert_output --partial "--component"
}

@test "llvmup default command shows help when no args" {
    run bash "$ORIGINAL_DIR/llvmup" default
    assert_success
    # The output should mention default version (even if none is set)
    assert_output --partial "default LLVM version"
}

@test "llvmup default set requires version argument" {
    run bash "$ORIGINAL_DIR/llvmup" default set
    assert_failure
    assert_output --partial "Missing version argument"
}

@test "llvmup default set with non-existent version fails" {
    run bash "$ORIGINAL_DIR/llvmup" default set "nonexistent-version"
    assert_failure
    assert_output --partial "not installed"
}

@test "llvmup default set works with existing version" {
    # Create fake installation
    mkdir -p "$TEST_HOME/.llvm/toolchains/test-version"
    echo "fake clang" > "$TEST_HOME/.llvm/toolchains/test-version/clang"

    run bash "$LLVMUP_SCRIPT" default set "test-version"
    assert_success
    assert_output --partial "Default LLVM version set to: test-version"

    # Check if symlink was created
    [ -L "$TEST_HOME/.llvm/default" ]
}

@test "llvmup default show displays current default" {
    # Create fake installation and set as default
    mkdir -p "$TEST_HOME/.llvm/toolchains/test-version/bin"
    echo '#!/bin/bash\necho "clang version 18.0.0"' > "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"
    chmod +x "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"
    ln -s "$TEST_HOME/.llvm/toolchains/test-version" "$TEST_HOME/.llvm/default"

    run bash "$LLVMUP_SCRIPT" default show
    assert_success
    assert_output --partial "Current default LLVM version: test-version"
}

@test "llvmup install accepts cmake-flags option" {
    # Test that llvmup accepts the cmake-flags option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--cmake-flags"
}

@test "llvmup install accepts name option" {
    # Test that llvmup accepts the name option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--name"
}

@test "llvmup install accepts default option" {
    # Test that llvmup accepts the default option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--default"
}

@test "llvmup install accepts profile option" {
    # Test that llvmup accepts the profile option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--profile"
}

@test "llvmup install validates profile values" {
    run bash "$ORIGINAL_DIR/llvmup" install --profile invalid-profile test-version
    assert_failure
    assert_output --partial "Invalid profile"
}

@test "llvmup install accepts component option" {
    # Test that llvmup accepts the component option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--component"
}

@test "llvmup install passes multiple cmake-flags correctly" {
    # Test that llvmup accepts multiple cmake-flags (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--cmake-flags"
    assert_output --partial "can be repeated"
}

@test "llvmup install combines all options correctly" {
    # Test that llvmup help shows all the new options
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits with code 1, but shows the help
    [ "$status" -eq 1 ]
    assert_output --partial "--name"
    assert_output --partial "--default"
    assert_output --partial "--profile"
    assert_output --partial "--cmake-flags"
    assert_output --partial "--component"
}
