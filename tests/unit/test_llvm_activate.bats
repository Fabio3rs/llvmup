#!/usr/bin/env bats

# Test setup
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export TEST_VERSION="llvmorg-15.0.0"
    mkdir -p "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin"
    
    # Create mock LLVM binaries
    touch "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/clang"
    touch "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/clang++"
    touch "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/ld.lld"
    
    # Save original environment
    export OLD_PATH="$PATH"
    export OLD_CC="$CC"
    export OLD_CXX="$CXX"
    export OLD_LD="$LD"
    export OLD_PS1="$PS1"
    
    # Source the script under test with a version argument
    source "$BATS_TEST_DIRNAME/../../llvm-activate" "$TEST_VERSION"
}

# Test cleanup
teardown() {
    # Restore original environment
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

@test "llvm-activate lists versions when no argument provided" {
    # Create multiple versions
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-14.0.0/bin"
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-16.0.0/bin"
    
    # Reset environment for this test
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    run llvm-activate
    [ "$status" -eq 1 ]
    [[ "$output" == *"llvmorg-14.0.0"* ]]
    [[ "$output" == *"llvmorg-15.0.0"* ]]
    [[ "$output" == *"llvmorg-16.0.0"* ]]
}

@test "llvm-activate fails with non-existent version" {
    # Reset environment for this test
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    run llvm-activate "nonexistent-version"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]]
}

@test "llvm-activate sets environment variables correctly" {
    # Reset environment for this test
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    # Run the activation
    run llvm-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]
    
    # Verify environment variables
    [[ "$PATH" == *"$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin"* ]]
    [ "$CC" = "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/clang" ]
    [ "$CXX" = "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/clang++" ]
    [ "$LD" = "$LLVM_TOOLCHAINS_DIR/$TEST_VERSION/bin/ld.lld" ]
    [[ "$PS1" == *"[$TEST_VERSION]"* ]]
}

@test "llvm-activate prevents multiple activations" {
    # Reset environment for this test
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    # First activation
    run llvm-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]
    
    # Try to activate another version
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-16.0.0/bin"
    run llvm-activate "llvmorg-16.0.0"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already active"* ]]
}

@test "llvm-activate restores environment on deactivation" {
    # Reset environment for this test
    export PATH="$OLD_PATH"
    export CC="$OLD_CC"
    export CXX="$OLD_CXX"
    export LD="$OLD_LD"
    export PS1="$OLD_PS1"
    
    # Store original values
    local original_path="$PATH"
    local original_cc="$CC"
    local original_cxx="$CXX"
    local original_ld="$LD"
    local original_ps1="$PS1"
    
    # Activate a version
    run llvm-activate "$TEST_VERSION"
    [ "$status" -eq 0 ]
    
    # Deactivate
    run llvm-deactivate
    [ "$status" -eq 0 ]
    
    # Verify environment is restored
    [ "$PATH" = "$original_path" ]
    [ "$CC" = "$original_cc" ]
    [ "$CXX" = "$original_cxx" ]
    [ "$LD" = "$original_ld" ]
    [ "$PS1" = "$original_ps1" ]
} 