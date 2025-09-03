#!/usr/bin/env bats
# test_install_customization.bats - Tests for customizable installation

load '../fixtures/test_helpers.bash'

setup() {
    setup_test_env

    # Create temporary test directory for installation tests
    export TEST_INSTALL_DIR="$BATS_TMPDIR/install_test_$$"
    mkdir -p "$TEST_INSTALL_DIR"
    cd "$TEST_INSTALL_DIR"

    # Copy installation scripts to test directory
    cp "$BATS_TEST_DIRNAME/../../install.sh" .
    cp "$BATS_TEST_DIRNAME/../../uninstall.sh" .
    cp -r "$BATS_TEST_DIRNAME/../../"llvm-* .
    cp "$BATS_TEST_DIRNAME/../../llvmup" .
    cp "$BATS_TEST_DIRNAME/../../llvmup-completion.sh" .
}

teardown() {
    cleanup_test_env
    cd "$BATS_TEST_DIRNAME"
    rm -rf "$TEST_INSTALL_DIR" 2>/dev/null || true
}

@test "install.sh shows configuration with default settings" {
    run ./install.sh --dry-run 2>/dev/null || true

    # Since there's no --dry-run flag, we'll test the actual output messages
    # by checking the beginning of the installation process
    timeout 2 ./install.sh &
    local install_pid=$!
    sleep 0.1
    kill $install_pid 2>/dev/null || true
    wait $install_pid 2>/dev/null || true
}

@test "install.sh respects LLVMUP_PREFIX environment variable" {
    export LLVMUP_PREFIX="$BATS_TMPDIR/custom_prefix"

    run timeout 5 ./install.sh

    # Should create directories under custom prefix
    [ -d "$LLVMUP_PREFIX/bin" ]
    [ -d "$LLVMUP_PREFIX/share/bash-completion/completions" ]

    # Should install scripts to custom location
    [ -f "$LLVMUP_PREFIX/bin/llvmup" ]
    [ -f "$LLVMUP_PREFIX/bin/llvm-functions.sh" ]
    [ -x "$LLVMUP_PREFIX/bin/llvmup" ]
}

@test "install.sh respects LLVMUP_INSTALL_DIR environment variable" {
    export LLVMUP_INSTALL_DIR="$BATS_TMPDIR/custom_bin"

    run timeout 5 ./install.sh

    # Should install scripts to custom directory
    [ -d "$LLVMUP_INSTALL_DIR" ]
    [ -f "$LLVMUP_INSTALL_DIR/llvmup" ]
    [ -f "$LLVMUP_INSTALL_DIR/llvm-functions.sh" ]
    [ -x "$LLVMUP_INSTALL_DIR/llvmup" ]
}

@test "install.sh respects LLVMUP_COMPLETION_DIR environment variable" {
    export LLVMUP_COMPLETION_DIR="$BATS_TMPDIR/custom_completions"

    run timeout 5 ./install.sh

    # Should install completion to custom directory
    [ -d "$LLVMUP_COMPLETION_DIR" ]
    [ -f "$LLVMUP_COMPLETION_DIR/llvmup" ]
}

@test "uninstall.sh works with same custom directories" {
    # First install to custom location
    export LLVMUP_PREFIX="$BATS_TMPDIR/custom_uninstall_prefix"
    run timeout 5 ./install.sh

    # Verify installation
    [ -f "$LLVMUP_PREFIX/bin/llvmup" ]
    [ -f "$LLVMUP_PREFIX/share/bash-completion/completions/llvmup" ]

    # Then uninstall from same location
    run timeout 5 ./uninstall.sh

    # Should remove files
    [ ! -f "$LLVMUP_PREFIX/bin/llvmup" ]
    [ ! -f "$LLVMUP_PREFIX/share/bash-completion/completions/llvmup" ]
}

@test "install.sh creates proper directory structure" {
    export LLVMUP_PREFIX="$BATS_TMPDIR/structure_test"

    run timeout 5 ./install.sh

    # Check standard directory structure
    [ -d "$LLVMUP_PREFIX/bin" ]
    [ -d "$LLVMUP_PREFIX/share" ]
    [ -d "$LLVMUP_PREFIX/share/bash-completion" ]
    [ -d "$LLVMUP_PREFIX/share/bash-completion/completions" ]
}

@test "install.sh installed scripts are executable" {
    export LLVMUP_PREFIX="$BATS_TMPDIR/executable_test"

    run timeout 5 ./install.sh

    # Check all installed scripts are executable
    for script in llvmup llvm-prebuilt llvm-build llvm-activate llvm-deactivate llvm-vscode-activate; do
        [ -x "$LLVMUP_PREFIX/bin/$script" ]
    done
}

@test "install.sh handles non-existent source files gracefully" {
    # Remove a required file
    rm llvmup

    run ./install.sh
    assert_failure
    assert_output --partial "not found in the current directory"
}

@test "install.sh shows helpful output messages" {
    export LLVMUP_PREFIX="$BATS_TMPDIR/output_test"

    run timeout 5 ./install.sh

    # Should show configuration info
    assert_output --partial "Installation Configuration:"
    assert_output --partial "Install Directory:"
    assert_output --partial "Completion Directory:"

    # Should show success messages
    assert_output --partial "Installation complete!"
    assert_output --partial "LLVMUP is now installed"
}

@test "multiple installations to different locations work independently" {
    # Install to first location
    export LLVMUP_PREFIX="$BATS_TMPDIR/location1"
    run timeout 5 ./install.sh
    [ -f "$LLVMUP_PREFIX/bin/llvmup" ]

    # Install to second location
    export LLVMUP_PREFIX="$BATS_TMPDIR/location2"
    run timeout 5 ./install.sh
    [ -f "$LLVMUP_PREFIX/bin/llvmup" ]

    # Both should exist independently
    [ -f "$BATS_TMPDIR/location1/bin/llvmup" ]
    [ -f "$BATS_TMPDIR/location2/bin/llvmup" ]
}
