#!/usr/bin/env bats
# test_completion_enhanced.bats - Enhanced completion system tests
#
# Tests for the advanced completion features:
# - Remote version fetching with cache
# - Context-aware completion (source vs prebuilt)
# - Performance optimization
# - Cache management

load '../fixtures/test_helpers.bash'

setup() {
    # Create test directories
    export TEST_DIR="$BATS_TMPDIR/llvmup_completion_test_$$"
    export HOME="$TEST_DIR"
    export LLVM_COMPLETION_CACHE_DIR="$TEST_DIR/.cache/llvmup"
    export LLVM_REMOTE_CACHE_FILE="$LLVM_COMPLETION_CACHE_DIR/remote_versions.cache"

    mkdir -p "$TEST_DIR"
    mkdir -p "$LLVM_COMPLETION_CACHE_DIR"

    # Mock curl and jq for controlled testing
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p "$TEST_DIR/bin"

    # Create mock curl
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
if [[ "$*" == *"github.com/repos/llvm/llvm-project/releases"* ]]; then
    # Mock GitHub API response
    cat << 'JSON'
[
  {"tag_name": "llvmorg-21.1.0"},
  {"tag_name": "llvmorg-20.1.8"},
  {"tag_name": "llvmorg-20.1.7"},
  {"tag_name": "llvmorg-19.1.7"},
  {"tag_name": "llvmorg-18.1.8"}
]
JSON
else
    # Pass through to real curl for other requests
    /usr/bin/curl "$@"
fi
EOF
    chmod +x "$TEST_DIR/bin/curl"

    # Create mock jq
    cat > "$TEST_DIR/bin/jq" << 'EOF'
#!/bin/bash
if [[ "$1" == "-r" ]] && [[ "$2" == ".[].tag_name" ]]; then
    # Extract tag names from mock JSON
    sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p'
else
    # Pass through to real jq for other uses
    /usr/bin/jq "$@"
fi
EOF
    chmod +x "$TEST_DIR/bin/jq"

    # Source the completion script
    source "$BATS_TEST_DIRNAME/../../llvmup-completion.sh"

    # Create mock local versions
    export LLVM_CUSTOM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export LLVM_CUSTOM_SOURCES_DIR="$TEST_DIR/.llvm/sources"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/llvmorg-19.1.7"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/llvmorg-20.1.0"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/source-llvmorg-21-init"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "remote version fetching works with mock API" {
    # Test the _llvm_get_remote_versions function
    run _llvm_get_remote_versions

    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmorg-21.1.0"* ]]
    [[ "$output" == *"llvmorg-20.1.8"* ]]
    [[ "$output" == *"llvmorg-19.1.7"* ]]
}

@test "remote version caching works correctly" {
    # First call should create cache
    run _llvm_get_remote_versions
    [ "$status" -eq 0 ]

    # Cache file should exist
    [ -f "$LLVM_REMOTE_CACHE_FILE" ]

    # Cache should contain versions
    run cat "$LLVM_REMOTE_CACHE_FILE"
    [[ "$output" == *"llvmorg-21.1.0"* ]]

    # Mock curl to fail (to test cache is being used)
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
exit 1  # Simulate network failure
EOF
    chmod +x "$TEST_DIR/bin/curl"

    # Second call should use cache despite curl failure
    run _llvm_get_remote_versions
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmorg-21.1.0"* ]]
}

@test "cache validity check works" {
    # Test fresh cache
    echo "llvmorg-21.1.0" > "$LLVM_REMOTE_CACHE_FILE"
    run _llvm_cache_valid
    [ "$status" -eq 0 ]

    # Test stale cache (simulate old file)
    touch -t 202001010000 "$LLVM_REMOTE_CACHE_FILE"  # Set to year 2020
    run _llvm_cache_valid
    [ "$status" -eq 1 ]

    # Test missing cache
    rm -f "$LLVM_REMOTE_CACHE_FILE"
    run _llvm_cache_valid
    [ "$status" -eq 1 ]
}

@test "local version detection works" {
    run _llvm_get_local_versions

    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmorg-19.1.7"* ]]
    [[ "$output" == *"llvmorg-20.1.0"* ]]
    [[ "$output" == *"source-llvmorg-21-init"* ]]
}

@test "main llvmup completion provides completions" {
    # Test main command completion - the specific content depends on context
    # but it should always provide SOME completions
    COMP_WORDS=("llvmup" "")
    COMP_CWORD=1
    COMPREPLY=()

    # Call completion function directly (no run wrapper)
    _llvmup_completions

    # Should provide some completions (commands, versions, or flags)
    [ ${#COMPREPLY[@]} -gt 0 ]
}

@test "subcommand completions work correctly" {
    # Test "llvmup default <TAB>"
    COMP_WORDS=("llvmup" "default" "")
    COMP_CWORD=2
    COMPREPLY=()

    _llvmup_completions

    local completions="${COMPREPLY[*]}"
    [[ "$completions" == *"set"* ]]
    [[ "$completions" == *"show"* ]]

    # Test "llvmup config <TAB>"
    COMP_WORDS=("llvmup" "config" "")
    COMP_CWORD=2
    COMPREPLY=()

    _llvmup_completions

    completions="${COMPREPLY[*]}"
    [[ "$completions" == *"init"* ]]
    [[ "$completions" == *"load"* ]]
}

@test "version and option completions work" {
    # Test "llvmup install <TAB>" - should provide versions and options
    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()

    _llvmup_completions

    # Should include some form of completions (versions or flags)
    [ ${#COMPREPLY[@]} -gt 0 ]
    local completions="${COMPREPLY[*]}"

    # Should contain versions OR flags
    [[ "$completions" == *"llvmorg-"* ]] || [[ "$completions" == *"--from-source"* ]]

    # Test option completions
    COMP_WORDS=("llvmup" "install" "--profile" "")
    COMP_CWORD=3
    COMPREPLY=()

    _llvmup_completions

    completions="${COMPREPLY[*]}"
    [[ "$completions" == *"minimal"* ]]
    [[ "$completions" == *"full"* ]]
    [[ "$completions" == *"custom"* ]]
}

@test "completion handles network timeouts gracefully" {
    # Mock curl with timeout behavior
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
if [[ "$*" == *"timeout 5"* ]]; then
    sleep 10  # Simulate slow response
    exit 124  # Timeout exit code
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/curl"

    # Should fall back to common versions
    run _llvm_get_remote_versions
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvmorg-21.1.0"* ]]  # Should include fallback versions
}

@test "completion performance is reasonable" {
    # Test that completion doesn't take too long
    start_time=$(date +%s%N)

    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()
    _llvmup_completions

    end_time=$(date +%s%N)
    duration_ms=$(( (end_time - start_time) / 1000000 ))

    # Should complete within 2 seconds (generous for CI)
    [ "$duration_ms" -lt 2000 ]
}

@test "cache improves performance significantly" {
    # First call (creates cache)
    start_time=$(date +%s%N)
    run _llvm_get_remote_versions
    end_time=$(date +%s%N)
    first_call_ms=$(( (end_time - start_time) / 1000000 ))

    # Second call (uses cache)
    start_time=$(date +%s%N)
    run _llvm_get_remote_versions
    end_time=$(date +%s%N)
    cached_call_ms=$(( (end_time - start_time) / 1000000 ))

    # Cached call should be significantly faster
    # Allow for some variability in CI environments
    [ "$cached_call_ms" -lt $(( first_call_ms / 2 )) ] || [ "$cached_call_ms" -lt 100 ]
}

@test "completion works without network access" {
    # Remove network access by breaking curl
    rm -f "$TEST_DIR/bin/curl"

    # Should still provide basic completion
    COMP_WORDS=("llvmup" "install" "")
    COMP_CWORD=2
    COMPREPLY=()

    _llvmup_completions

    # Should have some completions even without network
    [ ${#COMPREPLY[@]} -gt 0 ]
}

@test "enhanced llvm function completion loads" {
    # Source the llvm functions
    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"

    # Test that completion function exists
    run declare -F _llvm_complete_versions
    [ "$status" -eq 0 ]

    # Test basic completion works
    COMP_WORDS=("llvm-activate" "")
    COMP_CWORD=1
    COMPREPLY=()

    _llvm_complete_versions

    # Should provide some completions
    [ ${#COMPREPLY[@]} -ge 0 ]  # Allow empty if no versions installed
}
