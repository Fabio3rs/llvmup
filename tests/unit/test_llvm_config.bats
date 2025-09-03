#!/usr/bin/env bats
# test_llvm_config.bats - Tests for .llvmup-config functionality

load '../fixtures/test_helpers.bash'

setup() {
    # Create temporary test directory
    export TEST_PROJECT_DIR="$BATS_TMPDIR/test_project_$$"
    export LLVM_TEST_HOME="$BATS_TMPDIR/llvm_test_$$"
    export HOME="$LLVM_TEST_HOME"

    mkdir -p "$TEST_PROJECT_DIR"
    mkdir -p "$LLVM_TEST_HOME/.llvm/toolchains"

    # Store original directory - go to project root
    cd "$BATS_TEST_DIRNAME/../.."
    export ORIGINAL_DIR="$PWD"
    cd "$TEST_PROJECT_DIR"

    # Enable test mode
    export LLVM_TEST_MODE=1

    # Source the functions to test
    source "$ORIGINAL_DIR/llvm-functions.sh"
}

teardown() {
    cd "$ORIGINAL_DIR"
    rm -rf "$TEST_PROJECT_DIR" "$LLVM_TEST_HOME" 2>/dev/null || true
}

@test "llvm-config-init creates configuration file" {
    # Set test environment variables
    export LLVM_TEST_VERSION="llvmorg-18.1.8"
    export LLVM_TEST_CUSTOM_NAME="test-build"
    export LLVM_TEST_PROFILE="full"

    run llvm-config-init
    assert_success

    [ -f ".llvmup-config" ]

    # Check content
    grep -q "default = \"llvmorg-18.1.8\"" .llvmup-config
    grep -q "name = \"test-build\"" .llvmup-config
    grep -q "type = \"full\"" .llvmup-config
}

@test "llvm-config-init prompts to overwrite existing config" {
    # Create existing config
    echo "[version]\ndefault = \"old-version\"" > .llvmup-config

    # Test overwrite prompt (answer no)
    export LLVM_TEST_OVERWRITE="n"

    run llvm-config-init
    assert_failure
    assert_output --partial "already exists"
    assert_output --partial "cancelled"

    # Original content should remain
    grep -q "old-version" .llvmup-config
}

@test "llvm-config-init overwrites when user confirms" {
    # Create existing config
    echo "[version]\ndefault = \"old-version\"" > .llvmup-config

    # Test overwrite prompt (answer yes)
    export LLVM_TEST_OVERWRITE="y"
    export LLVM_TEST_VERSION="llvmorg-19.1.0"
    export LLVM_TEST_CUSTOM_NAME=""
    export LLVM_TEST_PROFILE="minimal"

    run llvm-config-init
    assert_success

    # New content should be present
    grep -q "llvmorg-19.1.0" .llvmup-config
    grep -q "minimal" .llvmup-config
    ! grep -q "old-version" .llvmup-config
}

@test "llvm-config-load fails when no config file exists" {
    run llvm-config-load
    assert_failure
    assert_output --partial "No .llvmup-config file found"
    assert_output --partial "llvm-config-init"
}

@test "llvm-config-load parses configuration correctly" {
    # Create test configuration
    cat > .llvmup-config << EOF
[version]
default = "llvmorg-18.1.8"

[build]
name = "custom-build"
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Debug",
  "-DLLVM_ENABLE_PROJECTS=clang;lld"
]

[profile]
type = "minimal"

[components]
include = ["clang", "lld", "lldb"]
EOF

    # Mock llvmup command to avoid actual installation
    function llvmup() {
        echo "Mock llvmup called with args: $@"
        return 0
    }

    # Mock llvm-activate
    function llvm-activate() {
        echo "Mock activate called with: $1"
        return 0
    }

    run llvm-config-load
    assert_success
    assert_output --partial "Configuration loaded"
    assert_output --partial "Version: llvmorg-18.1.8"
    assert_output --partial "Name: custom-build"
    assert_output --partial "Profile: minimal"
}

@test "llvm-config-load activates existing installation" {
    # Create test configuration
    cat > .llvmup-config << EOF
[version]
default = "test-version"

[build]
name = "test-build"
EOF

    # Create fake installation
    mkdir -p "$LLVM_TEST_HOME/.llvm/toolchains/test-build"

    # Mock llvm-activate
    function llvm-activate() {
        echo "Activated: $1"
        return 0
    }

    run llvm-config-load
    assert_success
    assert_output --partial "already installed"
    assert_output --partial "Activated: test-build"
}

@test "llvm-config-load offers to install missing version" {
    # Create test configuration
    cat > .llvmup-config << EOF
[version]
default = "missing-version"
EOF

    # Mock llvmup command
    function llvmup() {
        echo "Installing with args: $@"
        return 0
    }

    function llvm-activate() {
        echo "Activated: $1"
        return 0
    }

    # Set test environment to answer "no" to from-source prompt
    export LLVM_TEST_FROM_SOURCE="n"

    run llvm-config-load
    assert_success
    assert_output --partial "not found"
    assert_output --partial "Installing with args"
    assert_output --partial "missing-version"
}

@test "llvm-config-load handles from-source installation" {
    # Create test configuration
    cat > .llvmup-config << EOF
[version]
default = "source-version"

[build]
name = "source-build"

[profile]
type = "minimal"
EOF

    # Mock llvmup command
    function llvmup() {
        echo "Installing with args: $@"
        return 0
    }

    function llvm-activate() {
        echo "Activated: $1"
        return 0
    }

    # Set test environment to answer "yes" to from-source prompt
    export LLVM_TEST_FROM_SOURCE="y"

    run llvm-config-load
    assert_success
    assert_output --partial "--from-source"
    assert_output --partial "source-version"
    assert_output --partial "--name source-build"
    assert_output --partial "--profile minimal"
}

@test "config file parsing ignores comments and empty lines" {
    cat > .llvmup-config << EOF
# This is a comment
[version]
# Another comment
default = "test-version"

# Empty line above
[build]
name = "test-name"
# Comment at end
EOF

    function llvmup() { echo "Mock install"; return 0; }
    function llvm-activate() { echo "Mock activate"; return 0; }

    export LLVM_TEST_FROM_SOURCE="n"

    run llvm-config-load
    assert_success
    assert_output --partial "Version: test-version"
    assert_output --partial "Name: test-name"
}

@test "config file parsing handles sections correctly" {
    cat > .llvmup-config << EOF
[version]
default = "v1"
other_key = "should_be_ignored"

[build]
name = "build1"
default = "should_not_override_version"

[profile]
type = "full"
EOF

    function llvmup() { echo "Mock install"; return 0; }
    function llvm-activate() { echo "Mock activate"; return 0; }

    export LLVM_TEST_FROM_SOURCE="n"

    run llvm-config-load
    assert_success
    assert_output --partial "Version: v1"
    assert_output --partial "Name: build1"
    assert_output --partial "Profile: full"
    # Should not contain the wrong default value
    ! grep -q "should_not_override_version" <<< "$output"
}
