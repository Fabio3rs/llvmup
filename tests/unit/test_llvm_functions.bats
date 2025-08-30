#!/usr/bin/env bats

# Test setup
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-19.1.7"
    export TEST_VERSION2="llvmorg-20.1.0"

    # Create mock LLVM toolchains
    mkdir -p "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin"
    mkdir -p "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION2/bin"

    # Create mock LLVM binaries
    for binary in clang clang++ clangd lld llvm-config lldb opt llc lli llvm-objdump llvm-nm llvm-strip; do
        touch "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        touch "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION2/bin/$binary"
        chmod +x "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/$binary"
        chmod +x "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION2/bin/$binary"
    done

    # Create mock script files
    export MOCK_SCRIPT_DIR="$TEST_DIR/.local/bin"
    mkdir -p "$MOCK_SCRIPT_DIR"

    # Create mock llvm-activate script
    cat > "$MOCK_SCRIPT_DIR/llvm-activate" << 'EOF'
#!/bin/bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed directly."
    exit 1
fi

VERSION="$1"
LLVM_DIR="$HOME/.llvm/toolchains/$VERSION"

if [ ! -d "$LLVM_DIR" ]; then
    echo "Error: Version '$VERSION' is not installed."
    return 1
fi

if [ -n "$_ACTIVE_LLVM" ]; then
    echo "Error: Another version is already active: $_ACTIVE_LLVM."
    return 1
fi

export _OLD_PATH="$PATH"
export _OLD_CC="$CC"
export _OLD_CXX="$CXX"
export _OLD_LD="$LD"
export _OLD_PS1="$PS1"

export PATH="$LLVM_DIR/bin:$PATH"
export CC="$LLVM_DIR/bin/clang"
export CXX="$LLVM_DIR/bin/clang++"
export LD="$LLVM_DIR/bin/lld"
export PS1="(LLVM: $VERSION) $_OLD_PS1"
export _ACTIVE_LLVM="$VERSION"
export _ACTIVE_LLVM_PATH="$LLVM_DIR"

echo "LLVM version '$VERSION' activated for this session."
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-activate"

    # Create mock llvm-deactivate script
    cat > "$MOCK_SCRIPT_DIR/llvm-deactivate" << 'EOF'
#!/bin/bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed directly."
    exit 1
fi

if [ -z "$_ACTIVE_LLVM" ]; then
    echo "No LLVM version is currently active."
    return 0
fi

export PATH="$_OLD_PATH"
export CC="$_OLD_CC"
export CXX="$_OLD_CXX"
export LD="$_OLD_LD"
export PS1="$_OLD_PS1"

unset _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_PS1
unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH

echo "LLVM version deactivated. Environment variables have been restored."
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-deactivate"

    # Create mock llvm-vscode-activate script
    cat > "$MOCK_SCRIPT_DIR/llvm-vscode-activate" << 'EOF'
#!/bin/bash
VERSION="$1"
LLVM_DIR="$HOME/.llvm/toolchains/$VERSION"

if [ ! -d "$LLVM_DIR" ]; then
    echo "Version '$VERSION' is not installed."
    exit 1
fi

if [ ! -d ".vscode" ]; then
    echo "Not in a VSCode workspace."
    exit 1
fi

echo "VSCode workspace settings updated for LLVM version '$VERSION'."
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-vscode-activate"

    # Source the functions under test
    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"

    # Save original environment
    export PATH_BACKUP="$PATH"
    export CC_BACKUP="$CC"
    export CXX_BACKUP="$CXX"
    export LD_BACKUP="$LD"
    export PS1_BACKUP="$PS1"

    # Clear any active LLVM state
    unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_PS1
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
    unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_PS1

    # Clean up test directory
    rm -rf "$TEST_DIR"
}

@test "llvm-functions.sh loads without errors" {
    run source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
    [ "$status" -eq 0 ]
}

@test "llvm-activate function exists and shows usage when called without arguments" {
    run llvm-activate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: llvm-activate <version>"* ]]
    [[ "$output" == *"$TEST_VERSION"* ]]
    [[ "$output" == *"$TEST_VERSION2"* ]]
}

@test "llvm-activate function fails with non-existent version" {
    run llvm-activate "nonexistent-version"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]]
}

@test "llvm-activate function activates existing version successfully" {
    # Use a subshell to isolate the test
    (
        source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
        HOME="$TEST_DIR"

        # Call the function
        llvm-activate "$TEST_VERSION"
        result=$?

        # Check if activation was successful
        [ $result -eq 0 ]
        [ "$_ACTIVE_LLVM" = "$TEST_VERSION" ]
        [ "$_ACTIVE_LLVM_PATH" = "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION" ]
    )
}

@test "llvm-deactivate function works without active version" {
    run llvm-deactivate
    [ "$status" -eq 0 ]
    [[ "$output" == *"No LLVM version is currently active"* ]]
}

@test "llvm-status function shows no active version initially" {
    run llvm-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No LLVM version is currently active"* ]]
}

@test "llvm-status function shows active version after activation" {
    # Use a subshell to test activation flow
    (
        source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
        HOME="$TEST_DIR"

        # Activate a version
        source "$MOCK_SCRIPT_DIR/llvm-activate" "$TEST_VERSION"

        # Test status
        result=$(llvm-status 2>&1)
        [[ "$result" == *"Active LLVM version: $TEST_VERSION"* ]]
        [[ "$result" == *"LLVM path: $LLVM_TOOLCHAINS_DIR/$TEST_VERSION"* ]]
    )
}

@test "llvm-list function lists installed versions" {
    run llvm-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed LLVM versions:"* ]]
    [[ "$output" == *"$TEST_VERSION"* ]]
    [[ "$output" == *"$TEST_VERSION2"* ]]
}

@test "llvm-list function shows active indicator" {
    # Use a subshell to test with active version
    (
        source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
        HOME="$TEST_DIR"

        # Activate a version
        source "$MOCK_SCRIPT_DIR/llvm-activate" "$TEST_VERSION"

        # Test list
        result=$(llvm-list 2>&1)
        [[ "$result" == *"$TEST_VERSION (active)"* ]]
        [[ "$result" == *"$TEST_VERSION2"* ]] && [[ "$result" != *"$TEST_VERSION2 (active)"* ]]
    )
}

@test "llvm-vscode-activate function shows usage when called without arguments" {
    run llvm-vscode-activate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: llvm-vscode-activate <version>"* ]]
}

@test "llvm-vscode-activate function works in VSCode workspace" {
    # Create a mock VSCode workspace
    mkdir -p "$TEST_DIR/project/.vscode"
    cd "$TEST_DIR/project"

    HOME="$TEST_DIR" run llvm-vscode-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VSCode workspace settings updated"* ]]
}

@test "completion function is registered" {
    # Check if the completion function exists
    run declare -F _llvm_complete_versions
    [ "$status" -eq 0 ]
}

@test "functions handle missing scripts gracefully" {
    # Remove the mock scripts
    rm -f "$MOCK_SCRIPT_DIR/llvm-activate"
    rm -f "$MOCK_SCRIPT_DIR/llvm-deactivate"
    rm -f "$MOCK_SCRIPT_DIR/llvm-vscode-activate"

    run llvm-activate "$TEST_VERSION"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"* ]]
    [[ "$output" == *"not found"* ]]

    run llvm-deactivate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"* ]]
    [[ "$output" == *"not found"* ]]

    run llvm-vscode-activate "$TEST_VERSION"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"* ]]
    [[ "$output" == *"not found"* ]]
}

@test "llvm-list function handles missing toolchains directory" {
    # Remove toolchains directory
    rm -rf "$LLVM_TOOLCHAINS_DIR"

    run llvm-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No LLVM toolchains found"* ]]
    [[ "$output" == *"Use 'llvmup' to install a version"* ]]
}
