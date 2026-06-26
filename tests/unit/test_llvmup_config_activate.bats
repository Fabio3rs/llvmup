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

@test "llvmup config activate - calls llvm-config-activate function" {
    # Create mock llvm-config-activate function
    cat > "$MOCK_SCRIPT_DIR/llvm-config-activate" <<EOF
#!/bin/bash
echo "Mock llvm-config-activate called with args: \$@"
exit 0
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-config-activate"

    # Add mock directory to PATH
    export PATH="$MOCK_SCRIPT_DIR:$PATH"

    # Run llvmup config activate
    run "$LLVMUP_SCRIPT" config activate

    [ "$status" -eq 0 ]
    [[ "$output" == *"Mock llvm-config-activate called with args:"* ]]
}

@test "llvmup config activate - passes arguments to llvm-config-activate" {
    # Create mock llvm-config-activate function
    cat > "$MOCK_SCRIPT_DIR/llvm-config-activate" <<EOF
#!/bin/bash
echo "llvm-config-activate called with: \$@"
exit 0
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-config-activate"

    # Add mock directory to PATH
    export PATH="$MOCK_SCRIPT_DIR:$PATH"

    # Run with arguments
    run "$LLVMUP_SCRIPT" config activate --verbose --some-arg

    [ "$status" -eq 0 ]
    [[ "$output" == *"llvm-config-activate called with: --verbose --some-arg"* ]]
}

@test "llvmup config activate - shows error when function not available" {
    # Ensure llvm-config-activate is not available
    export PATH="/usr/bin:/bin"
    export TEST_ISOLATED_DIR="$TEST_DIR/isolated"
    mkdir -p "$TEST_ISOLATED_DIR"
    cp "$LLVMUP_SCRIPT" "$TEST_ISOLATED_DIR/llvmup"
    chmod +x "$TEST_ISOLATED_DIR/llvmup"

    run "$TEST_ISOLATED_DIR/llvmup" config activate

    [ "$status" -eq 1 ]
    [[ "$output" == *"llvm-config-activate function not available"* ]]
    [[ "$output" == *"Make sure llvm-functions.sh is installed next to llvmup or loaded in your shell"* ]]
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
