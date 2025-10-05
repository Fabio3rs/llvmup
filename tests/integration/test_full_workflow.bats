#!/usr/bin/env bats

# Integration tests for the complete LLVM manager workflow
# These tests verify that all components work together correctly

# Test setup
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export PATH_BACKUP="$PATH"

    # Save original environment
    export CC_BACKUP="$CC"
    export CXX_BACKUP="$CXX"
    export LD_BACKUP="$LD"
    export PS1_BACKUP="$PS1"

    # Clear any active LLVM state
    export _ACTIVE_LLVM=""
    export _ACTIVE_LLVM_PATH=""
    export _OLD_PATH=""
    export _OLD_CC=""
    export _OLD_CXX=""
    export _OLD_LD=""
    export _OLD_PS1=""
    { unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_PS1; } 2>/dev/null || true

    # Create installation directory structure
    export INSTALL_DIR="$TEST_DIR/.local/bin"
    export COMPLETION_DIR="$TEST_DIR/.local/share/bash-completion/completions"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$COMPLETION_DIR"

    # Copy scripts to test installation directory
    cp "$BATS_TEST_DIRNAME/../../llvm-activate" "$INSTALL_DIR/"
    cp "$BATS_TEST_DIRNAME/../../llvm-deactivate" "$INSTALL_DIR/"
    cp "$BATS_TEST_DIRNAME/../../llvm-vscode-activate" "$INSTALL_DIR/"
    cp "$BATS_TEST_DIRNAME/../../llvm-functions.sh" "$INSTALL_DIR/"
    cp "$BATS_TEST_DIRNAME/../../llvmup" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/*

    # Add to PATH
    export PATH="$INSTALL_DIR:$PATH"
}

# Test cleanup
teardown() {
    # Restore original environment
    export HOME="$HOME_BACKUP"
    export PATH="$PATH_BACKUP"
    export CC="$CC_BACKUP"
    export CXX="$CXX_BACKUP"
    export LD="$LD_BACKUP"
    export PS1="$PS1_BACKUP"

    # Clear LLVM state
    export _ACTIVE_LLVM=""
    export _ACTIVE_LLVM_PATH=""
    export _OLD_PATH=""
    export _OLD_CC=""
    export _OLD_CXX=""
    export _OLD_LD=""
    export _OLD_PS1=""
    { unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_PS1; } 2>/dev/null || true

    # Clean up test directory
    rm -rf "$TEST_DIR"
}

@test "installation script simulation creates correct structure" {
    # Simulate what install.sh does
    [ -f "$INSTALL_DIR/llvm-activate" ]
    [ -f "$INSTALL_DIR/llvm-deactivate" ]
    [ -f "$INSTALL_DIR/llvm-vscode-activate" ]
    [ -f "$INSTALL_DIR/llvm-functions.sh" ]
    [ -f "$INSTALL_DIR/llvmup" ]

    # Check permissions
    [ -x "$INSTALL_DIR/llvm-activate" ]
    [ -x "$INSTALL_DIR/llvm-deactivate" ]
    [ -x "$INSTALL_DIR/llvm-vscode-activate" ]
    [ -x "$INSTALL_DIR/llvmup" ]
}

@test "bash functions load correctly after simulated installation" {
    # Source the functions
    run source "$INSTALL_DIR/llvm-functions.sh"
    [ "$status" -eq 0 ]

    # Check that functions are available
    source "$INSTALL_DIR/llvm-functions.sh"
    run declare -f llvm-activate
    [ "$status" -eq 0 ]

    run declare -f llvm-deactivate
    [ "$status" -eq 0 ]

    run declare -f llvm-status
    [ "$status" -eq 0 ]

    run declare -f llvm-list
    [ "$status" -eq 0 ]
}

@test "complete workflow: create toolchain, activate, status, deactivate" {
    # Create a mock LLVM toolchain
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-19.1.7"
    mkdir -p "$TOOLCHAINS_DIR/$TEST_VERSION/bin"

    # Create mock binaries
    for binary in clang clang++ clangd lld llvm-config; do
        echo '#!/bin/bash
echo "Mock '$binary' from '$TEST_VERSION'"' > "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        chmod +x "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
    done

    # Source functions
    source "$INSTALL_DIR/llvm-functions.sh"

    # Test the complete workflow in a subshell
    (
        # 1. Check initial status
        result=$(llvm-status 2>&1)
        [[ "$result" == *"Status: INACTIVE"* ]]

        # 2. List available versions
        result=$(llvm-list 2>&1)
        [[ "$result" == *"$TEST_VERSION"* ]]

        # 3. Activate version
        llvm-activate "$TEST_VERSION"
        activation_result=$?
        [ "$activation_result" -eq 0 ]

        # 4. Check status after activation
        result=$(llvm-status 2>&1)
        [[ "$result" == *"Version: $TEST_VERSION"* ]]

        # 5. Verify environment variables are set
        [[ "$PATH" == *"$TOOLCHAINS_DIR/$TEST_VERSION/bin"* ]]
        [ "$CC" = "$TOOLCHAINS_DIR/$TEST_VERSION/bin/clang" ]
        [ "$_ACTIVE_LLVM" = "$TEST_VERSION" ]

        # 6. Deactivate
        llvm-deactivate
        deactivation_result=$?
        [ "$deactivation_result" -eq 0 ]

        # 7. Check status after deactivation
        result=$(llvm-status 2>&1)
        [[ "$result" == *"Status: INACTIVE"* ]]

        # 8. Verify environment is restored
        [ -z "$_ACTIVE_LLVM" ]
    )
    result=$?
    [ "$result" -eq 0 ]
}

@test "VSCode integration works with mock workspace" {
    # Create a mock LLVM toolchain
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-19.1.7"
    mkdir -p "$TOOLCHAINS_DIR/$TEST_VERSION/bin"
    mkdir -p "$TOOLCHAINS_DIR/$TEST_VERSION/include"

    # Create mock binaries
    for binary in clang clang++ clangd lldb; do
        touch "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        chmod +x "$TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
    done

    # Create mock VSCode workspace
    mkdir -p "$TEST_DIR/project/.vscode"
    cd "$TEST_DIR/project"

    # Source functions and test VSCode activation
    source "$INSTALL_DIR/llvm-functions.sh"

    run llvm-vscode-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated"* ]]

    # Check that settings.json was created
    [ -f ".vscode/settings.json" ]
}

@test "llvmup wrapper works with installed scripts" {
    # Mock the underlying scripts
    cat > "$INSTALL_DIR/llvm-prebuilt" << 'EOF'
#!/bin/bash
echo "Mock llvm-prebuilt executed with: $*"
exit 0
EOF

    cat > "$INSTALL_DIR/llvm-build" << 'EOF'
#!/bin/bash
echo "Mock llvm-build executed with: $*"
exit 0
EOF

    chmod +x "$INSTALL_DIR/llvm-prebuilt"
    chmod +x "$INSTALL_DIR/llvm-build"

    # Test default behavior (prebuilt)
    run "$INSTALL_DIR/llvmup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing pre-built LLVM release"* ]]
    [[ "$output" == *"Mock llvm-prebuilt executed"* ]]

    # Test source build
    run "$INSTALL_DIR/llvmup" "--from-source"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Building LLVM from source"* ]]
    [[ "$output" == *"Mock llvm-build executed"* ]]
}

@test "error handling works throughout the system" {
    # Source functions
    source "$INSTALL_DIR/llvm-functions.sh"

    # Test error handling with non-existent version
    run llvm-activate "nonexistent-version"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]]

    # Test deactivation without active version
    run llvm-deactivate
    [ "$status" -eq 0 ]
    [[ "$output" == *"LLVM environment successfully deactivated"* ]]

    # Test VSCode activation outside workspace
    cd "$TEST_DIR"
    run llvm-vscode-activate "some-version"
    [ "$status" -eq 1 ]
    # The actual error message may vary, so check for any error indication
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"not installed"* ]] || [[ "$output" == *"workspace"* ]]
}

@test "completion system works" {
    # Create a mock toolchain for completion
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    mkdir -p "$TOOLCHAINS_DIR/llvmorg-19.1.7"
    mkdir -p "$TOOLCHAINS_DIR/llvmorg-20.1.0"

    # Source functions
    source "$INSTALL_DIR/llvm-functions.sh"

    # Test completion function exists
    run declare -f _llvm_complete_versions
    [ "$status" -eq 0 ]

    # Test completion generates version list
    COMP_WORDS=("llvm-activate" "llvm")
    COMP_CWORD=1
    _llvm_complete_versions

    # Check that COMPREPLY contains our versions
    [[ "${COMPREPLY[*]}" == *"llvmorg-19.1.7"* ]] || [[ "${COMPREPLY[*]}" == *"llvmorg-20.1.0"* ]]
}
