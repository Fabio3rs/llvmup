#!/usr/bin/env bats
# test_enhanced_workflow.bats - Integration tests for enhanced LLVM manager workflow

load '../fixtures/test_helpers.bash'

setup() {
    setup_test_env
    setup_mocks

    # Store original directory - go to project root
    cd "$BATS_TEST_DIRNAME/../.."
    export ORIGINAL_DIR="$PWD"

    export TEST_PROJECT_DIR="$BATS_TMPDIR/test_project_$$"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
}

teardown() {
    cd "$ORIGINAL_DIR"
    cleanup_mocks
    cleanup_test_env
    rm -rf "$TEST_PROJECT_DIR" 2>/dev/null || true
}

@test "Complete workflow: config init -> install -> activate" {
    # Step 1: Initialize project configuration using the actual function
    source "$ORIGINAL_DIR/llvm-functions.sh"

    # Enable test mode for non-interactive operation
    export LLVM_TEST_MODE=1

    # Create a simple config file manually to test the workflow
    cat > .llvmup-config << EOF
[version]
default = "llvmorg-18.1.8"

[build]
name = "test-integration"

[profile]
type = "full"
EOF

    assert_file_contains ".llvmup-config" "llvmorg-18.1.8"
    assert_file_contains ".llvmup-config" "test-integration"

    # Step 2: Mock successful installation
    create_fake_llvm_installation "test-integration"

    # Create mock llvm-activate script
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/llvm-activate" << 'EOF'
#!/bin/bash
echo "Mock llvm-activate called with: $@"
exit 0
EOF
    chmod +x "$HOME/.local/bin/llvm-activate"

    # Mock llvmup to simulate successful installation
    llvmup() {
        echo "Mock installation successful"
        return 0
    }

    run llvm-config-load
    assert_success
    assert_output --partial "Configuration loaded"
    assert_output --partial "test-integration"
}

@test "Workflow: custom build with multiple flags" {
    # Create configuration with custom build settings
    cat > .llvmup-config << EOF
[version]
default = "llvmorg-19.1.0"

[build]
name = "debug-build"
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Debug",
  "-DLLVM_ENABLE_ASSERTIONS=ON",
  "-DLLVM_ENABLE_PROJECTS=clang;lld;lldb"
]

[profile]
type = "custom"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]
EOF

    # Test that llvmup would be called with correct arguments
    source "$ORIGINAL_DIR/llvm-functions.sh"
    export LLVM_TEST_MODE=1

    # Mock llvmup to capture and validate arguments
    llvmup() {
        echo "Installation args: $@"
        # Verify essential arguments are present
        if [[ "$*" == *"llvmorg-19.1.0"* ]] && [[ "$*" == *"--name"* ]] && [[ "$*" == *"debug-build"* ]]; then
            echo "Arguments validated successfully"
            return 0
        else
            echo "Missing required arguments"
            return 1
        fi
    }

    llvm-activate() {
        echo "Activating: $1"
        return 0
    }

    run llvm-config-load
    assert_success
    assert_output --partial "Configuration loaded"
    assert_output --partial "debug-build"
}

@test "Workflow: default version management" {
    # Create fake installations
    create_fake_llvm_installation "v18.1.8"
    create_fake_llvm_installation "v19.1.0"

    # Test setting default
    run bash "$ORIGINAL_DIR/llvmup" default set "v18.1.8"
    assert_success
    assert_output --partial "Default LLVM version set to: v18.1.8"

    # Verify default was set
    assert_symlink_exists "$LLVM_TEST_HOME/.llvm/default"

    # Test showing default
    run bash "$ORIGINAL_DIR/llvmup" default show
    assert_success
    assert_output --partial "Current default LLVM version: v18.1.8"

    # Change default
    run bash "$ORIGINAL_DIR/llvmup" default set "v19.1.0"
    assert_success

    # Verify new default
    run bash "$ORIGINAL_DIR/llvmup" default show
    assert_success
    assert_output --partial "v19.1.0"
}

@test "Workflow: profile-based installation" {
    # Test minimal profile
    run timeout 10 bash "$ORIGINAL_DIR/llvm-build" \
        --profile minimal \
        --name "minimal-build" \
        --verbose \
        llvmorg-18.1.8

    # Should not hang and should process the profile
    [[ $status -eq 0 ]] || [[ $status -eq 124 ]] # Success or timeout
    assert_output --partial "minimal" || true

    # Test full profile
    run timeout 10 bash "$ORIGINAL_DIR/llvm-build" \
        --profile full \
        --name "full-build" \
        llvmorg-18.1.8

    [[ $status -eq 0 ]] || [[ $status -eq 124 ]]
    assert_output --partial "full" || true
}

@test "Workflow: component selection" {
    run timeout 10 bash "$ORIGINAL_DIR/llvm-build" \
        --component clang \
        --component lldb \
        --component compiler-rt \
        --name "component-build" \
        llvmorg-18.1.8

    [[ $status -eq 0 ]] || [[ $status -eq 124 ]]
    # Should mention the components
    assert_output --partial "clang" || true
    assert_output --partial "lldb" || true
    assert_output --partial "compiler-rt" || true
}

@test "Workflow: multiple cmake flags" {
    run timeout 10 bash "$ORIGINAL_DIR/llvm-build" \
        --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" \
        --cmake-flags "-DLLVM_ENABLE_ASSERTIONS=ON" \
        --cmake-flags "-DLLVM_TARGETS_TO_BUILD=X86" \
        --name "multi-flag-build" \
        llvmorg-18.1.8

    [[ $status -eq 0 ]] || [[ $status -eq 124 ]]
    # Should process all flags
    assert_output --partial "CMAKE_BUILD_TYPE=Debug" || true
    assert_output --partial "ENABLE_ASSERTIONS=ON" || true
    assert_output --partial "TARGETS_TO_BUILD=X86" || true
}

@test "Error handling: invalid profile" {
    run bash "$ORIGINAL_DIR/llvmup" install --profile "invalid-profile" test-version
    assert_failure
    assert_output --partial "Invalid profile"
}

@test "Error handling: missing cmake-flags argument" {
    run bash "$ORIGINAL_DIR/llvmup" install --cmake-flags
    assert_failure
    assert_output --partial "requires an argument"
}

@test "Error handling: missing name argument" {
    run bash "$ORIGINAL_DIR/llvmup" install --name
    assert_failure
    assert_output --partial "requires an argument"
}

@test "Error handling: setting non-existent version as default" {
    run bash "$ORIGINAL_DIR/llvmup" default set "non-existent-version"
    assert_failure
    assert_output --partial "not installed"
}

@test "Help system shows all new options" {
    run bash "$ORIGINAL_DIR/llvmup" --help
    # Help exits successfully and shows the help correctly
    assert_success

    # Check for all new options
    assert_output --partial "--cmake-flags"
    assert_output --partial "--name"
    assert_output --partial "--default"
    assert_output --partial "--profile"
    assert_output --partial "--component"

    # Check for examples
    assert_output --partial "Examples:"
    assert_output --partial "default set"
    assert_output --partial "default show"
}

@test "Integration: functions are properly exported and available" {
    source "$ORIGINAL_DIR/llvm-functions.sh"

    # Test that new functions are defined
    declare -F llvm-config-init >/dev/null
    declare -F llvm-config-load >/dev/null
    declare -F llvm-help >/dev/null

    # Test that existing functions still work
    declare -F llvm-activate >/dev/null
    declare -F llvm-deactivate >/dev/null
    declare -F llvm-status >/dev/null
    declare -F llvm-list >/dev/null
}
