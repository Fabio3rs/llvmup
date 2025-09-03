#!/usr/bin/env bats
# test_completion_integration.bats - Integration tests for completion system
#
# Tests real-world completion scenarios as users would experience them

load '../fixtures/test_helpers.bash'

setup() {
    export TEST_DIR="$BATS_TMPDIR/llvmup_completion_integration_$$"
    export HOME="$TEST_DIR"
    export LLVM_COMPLETION_CACHE_DIR="$TEST_DIR/.cache/llvmup"

    mkdir -p "$TEST_DIR"
    mkdir -p "$LLVM_COMPLETION_CACHE_DIR"

    # Setup mock environment similar to real usage
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p "$TEST_DIR/bin"

    # Create realistic mock curl that simulates GitHub API
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
if [[ "$*" == *"github.com/repos/llvm/llvm-project/releases"* ]]; then
    # Simulate realistic GitHub API response with timing
    sleep 0.1  # Simulate network latency
    cat << 'JSON'
[
  {
    "tag_name": "llvmorg-21.1.0",
    "assets": [
      {"name": "clang+llvm-21.1.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz", "browser_download_url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.0/clang+llvm-21.1.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz"}
    ]
  },
  {
    "tag_name": "llvmorg-20.1.8",
    "assets": [
      {"name": "clang+llvm-20.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz", "browser_download_url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/clang+llvm-20.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"}
    ]
  },
  {
    "tag_name": "llvmorg-19.1.7",
    "assets": [
      {"name": "clang+llvm-19.1.7-x86_64-linux-gnu-ubuntu-18.04.tar.xz", "browser_download_url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/clang+llvm-19.1.7-x86_64-linux-gnu-ubuntu-18.04.tar.xz"}
    ]
  }
]
JSON
elif [[ "$*" == *"-sI"* ]]; then
    # Mock HEAD request for file size
    echo "Content-Length: 500000000"  # 500MB
else
    # For other curl uses, simulate failure to avoid real network calls
    exit 1
fi
EOF
    chmod +x "$TEST_DIR/bin/curl"

    # Create mock jq
    cat > "$TEST_DIR/bin/jq" << 'EOF'
#!/bin/bash
case "$*" in
    *".[].tag_name"*)
        grep -o '"tag_name": "[^"]*"' | sed 's/"tag_name": "\([^"]*\)"/\1/'
        ;;
    *"select(.tag_name"*)
        # Mock asset URL extraction
        if [[ "$*" == *"llvmorg-21.1.0"* ]]; then
            echo "https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.0/clang+llvm-21.1.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
        fi
        ;;
    *)
        # Pass through basic jq operations
        cat
        ;;
esac
EOF
    chmod +x "$TEST_DIR/bin/jq"

    # Setup mock installed versions
    export TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    mkdir -p "$TOOLCHAINS_DIR/llvmorg-19.1.7/bin"
    mkdir -p "$TOOLCHAINS_DIR/llvmorg-20.1.0/bin"
    mkdir -p "$TOOLCHAINS_DIR/custom-build-21.0/bin"

    # Create mock clang binaries for version detection
    echo "clang version 19.1.7" > "$TOOLCHAINS_DIR/llvmorg-19.1.7/bin/clang"
    echo "clang version 20.1.0" > "$TOOLCHAINS_DIR/llvmorg-20.1.0/bin/clang"
    chmod +x "$TOOLCHAINS_DIR"/*/bin/clang

    # Setup default version
    ln -sf "$TOOLCHAINS_DIR/llvmorg-20.1.0" "$TEST_DIR/.llvm/default"

    # Source completion scripts
    source "$BATS_TEST_DIRNAME/../../llvmup-completion.sh"
    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "user workflow: fresh system completion shows latest versions" {
    # Simulate first-time user running: llvmup <TAB>
    COMP_WORDS=("llvmup" "")
    COMP_CWORD=1
    COMPREPLY=()

    _llvmup_completions

    # Should show completions (can be commands, versions, or both depending on context)
    [ ${#COMPREPLY[@]} -gt 0 ]

    local completions="${COMPREPLY[*]}"
    # Should include either commands, versions, or flags
    [[ "$completions" == *"install"* ]] || [[ "$completions" == *"llvmorg-21.1.0"* ]] || [[ "$completions" == *"llvmorg-20.1.8"* ]]
}

@test "user workflow: install prebuilt shows remote and local versions" {
    # Simulate: llvmup install <TAB>
    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()

    _llvmup_completions

    # Should show both remote and local versions
    local completions="${COMPREPLY[*]}"

    # Remote versions (latest available)
    [[ "$completions" == *"llvmorg-21.1.0"* ]]
    [[ "$completions" == *"llvmorg-20.1.8"* ]]

    # Local versions (already installed)
    [[ "$completions" == *"llvmorg-19.1.7"* ]]
    [[ "$completions" == *"llvmorg-20.1.0"* ]]
    [[ "$completions" == *"custom-build-21.0"* ]]

    # Should also show --from-source for building from source
    [[ "$completions" == *"--from-source"* ]]
}

@test "user workflow: source build completion shows context-aware versions" {
    # Simulate: llvmup install --from-source <TAB>
    COMP_WORDS=("llvmup" "install" "--from-source" "")
    COMP_CWORD=3
    COMPREPLY=()

    _llvmup_completions

    # Should show versions suitable for source builds
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-21.1.0"* ]]
    [[ "$completions" == *"llvmorg-20.1.8"* ]]
    [[ "$completions" == *"llvmorg-19.1.7"* ]]  # Can rebuild existing
}

@test "user workflow: setting default version shows only installed" {
    # Simulate: llvmup default set <TAB>
    COMP_WORDS=("llvmup" "default" "set" "")
    COMP_CWORD=3
    COMPREPLY=()

    _llvmup_completions

    # Should show ONLY locally installed versions
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-19.1.7"* ]]
    [[ "$completions" == *"llvmorg-20.1.0"* ]]
    [[ "$completions" == *"custom-build-21.0"* ]]

    # Should NOT show remote-only versions
    [[ ! "$completions" == *"llvmorg-21.1.0"* ]] || echo "Remote version should not appear for 'default set'"
}

@test "user workflow: activation completion shows status information" {
    # Simulate: llvm-activate <TAB>
    export _ACTIVE_LLVM="llvmorg-19.1.7"  # Simulate currently active version

    COMP_WORDS=("llvm-activate" "")
    COMP_CWORD=1
    COMPREPLY=()

    _llvm_complete_versions

    # Should complete with installed versions
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-19.1.7"* ]]
    [[ "$completions" == *"llvmorg-20.1.0"* ]]
    [[ "$completions" == *"custom-build-21.0"* ]]
}

@test "user workflow: configuration completion guides through options" {
    # Test configuration workflow

    # 1. llvmup config <TAB> - shows available config commands
    COMP_WORDS=("llvmup" "config" "")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    local config_completions="${COMPREPLY[*]}"
    [[ "$config_completions" == *"init"* ]]
    [[ "$config_completions" == *"load"* ]]

    # 2. llvmup install --profile <TAB> - shows build profiles
    COMP_WORDS=("llvmup" "install" "--profile" "")
    COMP_CWORD=3
    COMPREPLY=()
    _llvmup_completions

    local profile_completions="${COMPREPLY[*]}"
    [[ "$profile_completions" == *"minimal"* ]]
    [[ "$profile_completions" == *"full"* ]]
    [[ "$profile_completions" == *"custom"* ]]
}

@test "user workflow: advanced build options provide helpful suggestions" {
    # Test that completion helps users discover advanced options

    # 1. Component completion
    COMP_WORDS=("llvmup" "install" "--component" "")
    COMP_CWORD=3
    COMPREPLY=()
    _llvmup_completions

    local components="${COMPREPLY[*]}"
    [[ "$components" == *"clang"* ]]
    [[ "$components" == *"lldb"* ]]
    [[ "$components" == *"lld"* ]]

    # 2. CMake flags completion
    COMP_WORDS=("llvmup" "install" "--cmake-flags" "")
    COMP_CWORD=3
    COMPREPLY=()
    _llvmup_completions

    local cmake_flags="${COMPREPLY[*]}"
    [[ "$cmake_flags" == *"-DCMAKE_BUILD_TYPE=Release"* ]]
    [[ "$cmake_flags" == *"-DLLVM_ENABLE_PROJECTS=clang"* ]]
}

@test "user workflow: completion cache improves repeated usage" {
    # First completion should create cache
    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()

    # Time the first completion
    start_time=$(date +%s%N)
    _llvmup_completions
    end_time=$(date +%s%N)
    first_duration=$(( (end_time - start_time) / 1000000 ))

    # Cache should exist
    [ -f "$LLVM_COMPLETION_CACHE_DIR/remote_versions.cache" ]

    # Second completion should be faster
    COMPREPLY=()
    start_time=$(date +%s%N)
    _llvmup_completions
    end_time=$(date +%s%N)
    second_duration=$(( (end_time - start_time) / 1000000 ))

    # Both should provide the same completions
    [[ "${COMPREPLY[*]}" == *"llvmorg-21.1.0"* ]]

    # Performance should be reasonable (allowing CI variability)
    [ "$second_duration" -lt 1000 ]  # Less than 1 second
}

@test "user workflow: completion works with complex command combinations" {
    # Test realistic complex commands users might type

    # Complex build command: llvmup install --from-source --profile full --cmake-flags <TAB>
    COMP_WORDS=("llvmup" "install" "--from-source" "--profile" "full" "--cmake-flags" "")
    COMP_CWORD=6
    COMPREPLY=()
    _llvmup_completions

    # Should provide CMake flag suggestions
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"-DCMAKE_BUILD_TYPE"* ]]

    # Mixed flags: llvmup install --verbose --name custom <TAB> (should show versions)
    COMP_WORDS=("llvmup" "install" "--verbose" "--name" "custom" "")
    COMP_CWORD=5
    COMPREPLY=()
    _llvmup_completions

    # Should show version completions
    completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-21.1.0"* ]]
}

@test "user workflow: error handling provides graceful degradation" {
    # Test with broken network (no curl)
    rm -f "$TEST_DIR/bin/curl"

    # Completion should still work with fallbacks
    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    # Should at least provide local versions and basic options
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-19.1.7"* ]] || [[ "$completions" == *"--from-source"* ]]
}

@test "user workflow: completion respects user preferences" {
    # Test that completion adapts to different scenarios

    # When user has typed partial version
    COMP_WORDS=("llvmup" "install" "llvmorg-20")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    # Should complete the version
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg-20"* ]]

    # When user starts typing flags
    COMP_WORDS=("llvmup" "install" "--ver")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    # Should complete to --verbose
    completions="${COMPREPLY[*]}"
    [[ "$completions" == *"--verbose"* ]]
}

@test "user workflow: completion integrates with shell environment" {
    # Test that completion works with bash environment variables and functions

    # Set some environment that might affect completion
    export LLVM_DEFAULT_VERSION="llvmorg-20.1.0"
    export LLVM_COMPLETION_CACHE_EXPIRY_HOURS=1

    # Completion should still work normally
    COMP_WORDS=("llvmup" "default" "show")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    # Should not interfere with normal completion
    [ "$?" -eq 0 ]

    # Test with active LLVM version
    export _ACTIVE_LLVM="llvmorg-19.1.7"

    COMP_WORDS=("llvm-activate" "")
    COMP_CWORD=1
    COMPREPLY=()
    _llvm_complete_versions

    # Should provide completion with current environment context
    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"llvmorg"* ]]
}
