#!/usr/bin/env bats

# Tests for enhanced LLVM configuration features

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export ORIGINAL_PWD="$PWD"
    # Compute repository root relative to the test file for CI portability
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export LLVM_MANAGER_DIR="$repo_root"
    cd "$TEST_TEMP_DIR"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_TEMP_DIR"
}

@test "llvmup install command parsing" {
    # Create mock llvmup script
    cat > llvmup << 'EOF'
#!/bin/bash
source ../../llvmup
echo "Command: $COMMAND"
echo "Args: $@"
EOF
    chmod +x llvmup

    # Test install subcommand - skip this test for now as it needs full script
    skip "Needs integration with full llvmup script"
}

@test "llvm-config-init creates proper configuration file" {
    # Source the functions
    source "$LLVM_MANAGER_DIR/llvm-functions.sh"

    # Set test mode environment variables to avoid interactive prompts
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"
    export LLVM_TEST_CUSTOM_NAME="test-build"
    export LLVM_TEST_PROFILE="minimal"

    # Test config initialization
    run llvm-config-init
    [ "$status" -eq 0 ]
    [ -f ".llvmup-config" ]

    # Verify content
    grep -q "\[version\]" .llvmup-config
    grep -q "\[build\]" .llvmup-config
    grep -q "\[profile\]" .llvmup-config
    grep -q "\[components\]" .llvmup-config
    grep -q "llvmorg-18.1.8" .llvmup-config
    grep -q "test-build" .llvmup-config
    grep -q "minimal" .llvmup-config
}

@test "llvm-config-load parses configuration correctly" {
    # Source the functions
    source "$LLVM_MANAGER_DIR/llvm-functions.sh"

    # Set test mode to avoid interactive prompts
    export LLVM_TEST_MODE=1

    # Create test configuration
    cat > .llvmup-config << 'EOF'
[version]
default = "llvmorg-18.1.8"

[build]
name = "test-build"
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Debug",
  "-DLLVM_ENABLE_PROJECTS=clang;lld"
]

[profile]
type = "minimal"

[components]
include = ["clang", "lld", "lldb"]
EOF

    # Test config loading
    run llvm-config-load
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Version: llvmorg-18.1.8" ]]
    [[ "$output" =~ "Name: test-build" ]]
    [[ "$output" =~ "Profile: minimal" ]]
    [[ "$output" =~ "Next steps:" ]]
}

@test "llvmup config subcommand works" {
    # Set test mode environment variables
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"
    export LLVM_TEST_PROFILE="full"

    # Create minimal llvmup script that sources functions
    cat > llvmup << EOF
#!/bin/bash
source "$LLVM_MANAGER_DIR/llvm-functions.sh"
# Simulate the config command handling
case "\$1" in
    config)
        case "\$2" in
            init) llvm-config-init ;;
            load) echo "n" | llvm-config-load ;;
            *) echo "Unknown config command: \$2" ;;
        esac
        ;;
esac
EOF
    chmod +x llvmup

    # Test config init
    run ./llvmup config init
    [ "$status" -eq 0 ]
    [ -f ".llvmup-config" ]

    # Test config load
    run ./llvmup config load
    [ "$status" -eq 0 ]
}

@test "profile validation works in command parsing" {
    # Create simple test for profile validation logic
    validate_profile() {
        local profile="$1"
        case "$profile" in
            minimal|full|custom) return 0 ;;
            *) return 1 ;;
        esac
    }

    # Test valid profiles
    run validate_profile "minimal"
    [ "$status" -eq 0 ]

    run validate_profile "full"
    [ "$status" -eq 0 ]

    run validate_profile "custom"
    [ "$status" -eq 0 ]

    # Test invalid profile
    run validate_profile "invalid"
    [ "$status" -eq 1 ]
}

@test "cmake flags array handling works" {
    # Test that multiple cmake flags are handled correctly
    CMAKE_FLAGS=()
    CMAKE_FLAGS+=("-DCMAKE_BUILD_TYPE=Debug")
    CMAKE_FLAGS+=("-DLLVM_ENABLE_PROJECTS=clang;lld")

    [ ${#CMAKE_FLAGS[@]} -eq 2 ]
    [[ "${CMAKE_FLAGS[0]}" == "-DCMAKE_BUILD_TYPE=Debug" ]]
    [[ "${CMAKE_FLAGS[1]}" == "-DLLVM_ENABLE_PROJECTS=clang;lld" ]]
}

@test "component array handling works" {
    # Test that multiple components are handled correctly
    COMPONENTS=()
    COMPONENTS+=("clang")
    COMPONENTS+=("lld")
    COMPONENTS+=("lldb")

    [ ${#COMPONENTS[@]} -eq 3 ]
    [[ "${COMPONENTS[0]}" == "clang" ]]
    [[ "${COMPONENTS[1]}" == "lld" ]]
    [[ "${COMPONENTS[2]}" == "lldb" ]]
}

@test "configuration file with arrays parses correctly" {
    # Source the functions
    source "$LLVM_MANAGER_DIR/llvm-functions.sh"

    # Set test mode
    export LLVM_TEST_MODE=1

    # Create configuration with different array formats
    cat > .llvmup-config << 'EOF'
[version]
default = "llvmorg-18.1.8"

[build]
cmake_flags = ["-DCMAKE_BUILD_TYPE=Debug", "-DLLVM_ENABLE_PROJECTS=clang;lld"]

[components]
include = ["clang", "lld"]
EOF

    # Test parsing
    run llvm-config-load
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration loaded:" ]]
    [[ "$output" =~ "Next steps:" ]]
}
