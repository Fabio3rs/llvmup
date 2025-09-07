#!/usr/bin/env bats

load "../fixtures/test_helpers.bash"

setup() {
    # Set test mode environment variables
    export LLVM_TEST_MODE=1
    export LLVMUP_DISABLE_AUTOACTIVATE=1

    export TEST_TEMP_DIR="$(mktemp -d)"
    export ORIGINAL_PWD="$PWD"
    export LLVM_MANAGER_DIR="/mnt/projects/Projects/llvm-manager"
    cd "$TEST_TEMP_DIR"

    # Source the functions for testing
    source "$LLVM_MANAGER_DIR/llvm-functions.sh"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_TEMP_DIR"
}

@test "llvm-config-load supports auto_activate = true" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
auto_activate = true
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "Auto-activate: enabled"
}

@test "llvm-config-load supports auto_activate = false" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
auto_activate = false
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    # Should not contain auto-activate enabled message
    run bash -c 'echo "$output" | grep -v "Auto-activate: enabled"'
    assert_success
}

@test "llvm-config-load supports cmake_preset = Debug" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
cmake_preset = "Debug"
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "CMake preset: Debug"
    assert_output --partial "-DCMAKE_BUILD_TYPE=Debug"
    assert_output --partial "-DLLVM_ENABLE_ASSERTIONS=ON"
}

@test "llvm-config-load supports cmake_preset = Release" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
cmake_preset = "Release"
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "CMake preset: Release"
    assert_output --partial "-DCMAKE_BUILD_TYPE=Release"
    assert_output --partial "-DLLVM_ENABLE_ASSERTIONS=OFF"
}

@test "llvm-config-load supports cmake_preset = RelWithDebInfo" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
cmake_preset = "RelWithDebInfo"
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "CMake preset: RelWithDebInfo"
    assert_output --partial "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    assert_output --partial "-DLLVM_ENABLE_ASSERTIONS=ON"
}

@test "llvm-config-load handles unknown cmake_preset gracefully" {
    cat > .llvmup-config.test << 'EOF'
[version]
default = "llvmorg-18.1.8"

[project]
cmake_preset = "Unknown"
EOF

    mv .llvmup-config.test .llvmup-config

    export LLVM_TEST_MODE=1
    run llvm-config-load

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "Unknown cmake_preset: Unknown"
}

@test "llvm-config-init creates config with cmake_preset comment" {
    run llvm-config-init

    assert_success
    assert_output --partial "Configuration file created"

    # Check if file contains cmake_preset with comment
    run cat .llvmup-config
    assert_success
    assert_output --partial "cmake_preset"
    assert_output --partial "Options: Debug, Release, RelWithDebInfo, MinSizeRel"

    # Clean up
    rm -f .llvmup-config
}
