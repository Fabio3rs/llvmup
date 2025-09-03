# test_helpers.bash - Helper functions for LLVM manager tests

# Simple assertion functions for bats
assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "Expected success, but got status $status"
        echo "Output: $output"
        return 1
    fi
}

assert_failure() {
    if [ "$status" -eq 0 ]; then
        echo "Expected failure, but got status $status"
        echo "Output: $output"
        return 1
    fi
}

assert_output() {
    local flag="$1"
    local expected="$2"

    if [ "$flag" = "--partial" ]; then
        if [[ "$output" != *"$expected"* ]]; then
            echo "Expected output to contain '$expected'"
            echo "Actual output: $output"
            return 1
        fi
    else
        expected="$flag"
        if [ "$output" != "$expected" ]; then
            echo "Expected output: '$expected'"
            echo "Actual output: '$output'"
            return 1
        fi
    fi
}

# Setup common test environment
setup_test_env() {
    export LLVM_TEST_HOME="$BATS_TMPDIR/llvm_test_$$"
    export HOME="$LLVM_TEST_HOME"

    # Create directory structure
    mkdir -p "$LLVM_TEST_HOME/.llvm/toolchains"
    mkdir -p "$LLVM_TEST_HOME/.llvm/sources"
    mkdir -p "$LLVM_TEST_HOME/.local/bin"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$LLVM_TEST_HOME" 2>/dev/null || true
}

# Create a fake LLVM installation for testing
create_fake_llvm_installation() {
    local version="$1"
    local install_dir="$LLVM_TEST_HOME/.llvm/toolchains/$version"

    mkdir -p "$install_dir/bin"
    mkdir -p "$install_dir/lib"
    mkdir -p "$install_dir/include"

    # Create fake binaries
    cat > "$install_dir/bin/clang" << 'EOF'
#!/bin/bash
echo "clang version 18.0.0 (fake)"
echo "Target: x86_64-unknown-linux-gnu"
EOF

    cat > "$install_dir/bin/clang++" << 'EOF'
#!/bin/bash
echo "clang version 18.0.0 (fake c++)"
EOF

    cat > "$install_dir/bin/lldb" << 'EOF'
#!/bin/bash
echo "lldb version 18.0.0 (fake)"
EOF

    chmod +x "$install_dir/bin"/*
}

# Create a mock script that records its arguments
create_mock_script() {
    local script_name="$1"
    local behavior="$2"

    cat > "$script_name" << EOF
#!/bin/bash
echo "Mock $script_name called with: \$@" >&2
$behavior
EOF
    chmod +x "$script_name"
}

# Assert that a file contains specific content
assert_file_contains() {
    local file="$1"
    local content="$2"

    [ -f "$file" ] || return 1
    grep -q "$content" "$file"
}

# Assert that a directory exists
assert_dir_exists() {
    local dir="$1"
    [ -d "$dir" ]
}

# Assert that a symlink exists and points to the correct target
assert_symlink_exists() {
    local link="$1"
    local expected_target="$2"

    [ -L "$link" ] || return 1

    if [ -n "$expected_target" ]; then
        local actual_target=$(readlink "$link")
        [ "$actual_target" = "$expected_target" ]
    fi
}

# Mock git command for testing
mock_git() {
    local command="$1"
    shift

    case "$command" in
        "ls-remote")
            echo "refs/tags/llvmorg-18.1.8"
            echo "refs/tags/llvmorg-19.1.0"
            echo "refs/tags/llvmorg-20.0.0"
            ;;
        "clone"|"fetch"|"checkout")
            # Just create the target directory
            local target="${@: -1}"  # Last argument is usually the target
            mkdir -p "$target/llvm" 2>/dev/null || true
            ;;
        *)
            echo "Mock git: $command $@"
            ;;
    esac
}

# Mock cmake command for testing
mock_cmake() {
    echo "Mock cmake called with: $@"

    # Look for build directory argument
    for arg in "$@"; do
        if [[ "$arg" == -B* ]]; then
            local build_dir="${arg#-B}"
            mkdir -p "$build_dir"
            echo "ninja build file created" > "$build_dir/build.ninja"
        fi
    done

    return 0
}

# Mock ninja command for testing
mock_ninja() {
    echo "Mock ninja build completed"
    return 0
}

# Setup mocked external dependencies
setup_mocks() {
    export -f mock_git
    export -f mock_cmake
    export -f mock_ninja

    # Create wrapper scripts
    cat > "$BATS_TMPDIR/git" << 'EOF'
#!/bin/bash
mock_git "$@"
EOF

    cat > "$BATS_TMPDIR/cmake" << 'EOF'
#!/bin/bash
mock_cmake "$@"
EOF

    cat > "$BATS_TMPDIR/ninja" << 'EOF'
#!/bin/bash
mock_ninja "$@"
EOF

    chmod +x "$BATS_TMPDIR/git" "$BATS_TMPDIR/cmake" "$BATS_TMPDIR/ninja"
    export PATH="$BATS_TMPDIR:$PATH"
}

# Cleanup mocks
cleanup_mocks() {
    rm -f "$BATS_TMPDIR/git" "$BATS_TMPDIR/cmake" "$BATS_TMPDIR/ninja"
}

# Create a minimal .llvmup-config for testing
create_test_config() {
    local version="${1:-llvmorg-18.1.8}"
    local name="${2:-}"
    local profile="${3:-full}"

    cat > .llvmup-config << EOF
[version]
default = "$version"

[build]
EOF

    if [ -n "$name" ]; then
        echo "name = \"$name\"" >> .llvmup-config
    fi

    cat >> .llvmup-config << EOF
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Release",
  "-DLLVM_ENABLE_PROJECTS=clang;lld"
]

[profile]
type = "$profile"

[components]
include = ["clang", "lld", "lldb"]
EOF
}

# Verify that all required bats functions are available
check_bats_availability() {
    if ! command -v bats >/dev/null 2>&1; then
        echo "Error: bats testing framework is not installed"
        echo "Please install bats: https://github.com/bats-core/bats-core"
        return 1
    fi

    # Check for bats-assert if using assert_* functions
    if ! bats --version | grep -q "1."; then
        echo "Warning: Consider upgrading to bats 1.x for better assertion support"
    fi
}

# Run a command with timeout to prevent hanging tests
run_with_timeout() {
    local timeout_duration="${1:-10}"
    shift

    timeout "$timeout_duration" "$@"
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
        echo "Command timed out after $timeout_duration seconds"
    fi

    return $exit_code
}
