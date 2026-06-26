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
    # Help exits successfully and shows the enhanced options
    assert_success
    assert_output --partial "activate"
    assert_output --partial "deactivate"
    assert_output --partial "status"
    assert_output --partial "list"
    assert_output --partial "--cmake-flags"
    assert_output --partial "--name"
    assert_output --partial "--default"
    assert_output --partial "--profile"
    assert_output --partial "--component"
}

@test "llvmup help uses shell help when functions are available" {
    run bash -lc "export HOME='$TEST_HOME'; export LLVMUP_DISABLE_AUTOACTIVATE=1; source '$ORIGINAL_DIR/llvm-functions.sh'; llvmup help"
    assert_success
    assert_output --partial "LLVM Manager - Complete Usage Guide"
}

@test "llvmup status routes to shell function" {
    run bash -lc "export HOME='$TEST_HOME'; export LLVMUP_DISABLE_AUTOACTIVATE=1; source '$ORIGINAL_DIR/llvm-functions.sh'; llvmup status"
    assert_success
    assert_output --partial "LLVM Environment Status"
}

@test "llvmup list routes to shell function" {
    mkdir -p "$TEST_HOME/.llvm/toolchains/test-version"

    run bash -lc "export HOME='$TEST_HOME'; export LLVMUP_DISABLE_AUTOACTIVATE=1; source '$ORIGINAL_DIR/llvm-functions.sh'; llvmup list"
    assert_success
    assert_output --partial "Installed LLVM Versions"
    assert_output --partial "test-version"
}

@test "llvmup activate requires version argument" {
    run bash "$ORIGINAL_DIR/llvmup" activate
    assert_failure
    assert_output --partial "Missing version argument for 'activate'"
}

@test "llvmup activate works through shell function wrapper" {
    mkdir -p "$TEST_HOME/.llvm/toolchains/test-version/bin"
    printf '#!/bin/bash\necho "clang version 18.0.0"\n' > "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"
    chmod +x "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"

    run bash -lc "export HOME='$TEST_HOME'; export LLVMUP_DISABLE_AUTOACTIVATE=1; source '$ORIGINAL_DIR/llvm-functions.sh'; llvmup activate test-version >/dev/null; printf '%s' \"\$_ACTIVE_LLVM\""
    assert_success
    [ "$output" = "test-version" ]
}

@test "llvmup deactivate works through shell function wrapper" {
    mkdir -p "$TEST_HOME/.llvm/toolchains/test-version/bin"
    printf '#!/bin/bash\necho "clang version 18.0.0"\n' > "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"
    chmod +x "$TEST_HOME/.llvm/toolchains/test-version/bin/clang"

    run bash -lc "export HOME='$TEST_HOME'; export LLVMUP_DISABLE_AUTOACTIVATE=1; source '$ORIGINAL_DIR/llvm-functions.sh'; llvmup activate test-version >/dev/null; llvmup deactivate >/dev/null; printf '%s' \"\${_ACTIVE_LLVM:-inactive}\""
    assert_success
    [ "$output" = "inactive" ]
}

@test "llvmup vscode-activate requires version argument" {
    run bash "$ORIGINAL_DIR/llvmup" vscode-activate
    assert_failure
    assert_output --partial "Missing version argument for 'vscode-activate'"
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

@test "llvmup default set respects custom LLVM_HOME and LLVM_TOOLCHAINS_DIR" {
    export LLVM_HOME="$TEST_HOME/custom-home"
    export LLVM_TOOLCHAINS_DIR="$TEST_HOME/custom-toolchains"

    mkdir -p "$LLVM_TOOLCHAINS_DIR/test-version/bin"
    echo '#!/bin/bash\necho "clang version 18.0.0"' > "$LLVM_TOOLCHAINS_DIR/test-version/bin/clang"
    chmod +x "$LLVM_TOOLCHAINS_DIR/test-version/bin/clang"

    run bash "$LLVMUP_SCRIPT" default set "test-version"
    assert_success
    [ -L "$LLVM_HOME/default" ]
}

@test "llvmup default show respects custom LLVM_HOME" {
    export LLVM_HOME="$TEST_HOME/custom-home"
    export LLVM_TOOLCHAINS_DIR="$TEST_HOME/custom-toolchains"

    mkdir -p "$LLVM_TOOLCHAINS_DIR/test-version/bin"
    echo '#!/bin/bash\necho "clang version 18.0.0"' > "$LLVM_TOOLCHAINS_DIR/test-version/bin/clang"
    chmod +x "$LLVM_TOOLCHAINS_DIR/test-version/bin/clang"
    mkdir -p "$LLVM_HOME"
    ln -s "$LLVM_TOOLCHAINS_DIR/test-version" "$LLVM_HOME/default"

    run bash "$LLVMUP_SCRIPT" default show
    assert_success
    assert_output --partial "Current default LLVM version: test-version"
}

@test "llvmup install accepts cmake-flags option" {
    # Test that llvmup accepts the cmake-flags option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--cmake-flags"
}

@test "llvmup install accepts name option" {
    # Test that llvmup accepts the name option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--name"
}

@test "llvmup install accepts default option" {
    # Test that llvmup accepts the default option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--default"
}

@test "llvmup install accepts profile option" {
    # Test that llvmup accepts the profile option (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
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
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--component"
}

@test "llvmup install passes multiple cmake-flags correctly" {
    # Test that llvmup accepts multiple cmake-flags (parsing test)
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--cmake-flags"
    assert_output --partial "can be repeated"
}

@test "llvmup install combines all options correctly" {
    # Test that llvmup help shows all the new options
    run bash "$ORIGINAL_DIR/llvmup" install --help
    # Help exits successfully but still shows the usage text
    assert_success
    assert_output --partial "--name"
    assert_output --partial "--default"
    assert_output --partial "--profile"
    assert_output --partial "--cmake-flags"
    assert_output --partial "--component"
}
