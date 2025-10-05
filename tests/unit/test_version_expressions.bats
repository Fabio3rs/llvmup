#!/usr/bin/env bats

# Test setup
setup() {
    # Set test mode environment variables
    export LLVM_TEST_MODE=1
    export LLVMUP_DISABLE_AUTOACTIVATE=1

    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"

    # Set up directory configuration for new system
    export LLVM_CUSTOM_TOOLCHAINS_DIR="$TEST_DIR/.llvm/toolchains"
    export LLVM_CUSTOM_SOURCES_DIR="$TEST_DIR/.llvm/sources"

    # Create mock LLVM toolchains with diverse versions
    # Prebuilt versions
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/llvmorg-19.1.7/bin"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/llvmorg-20.1.0/bin"

    # Source build versions
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/source-llvmorg-20.1.0/bin"
    mkdir -p "$LLVM_CUSTOM_TOOLCHAINS_DIR/source-llvmorg-21-init/bin"

    # Create mock LLVM binaries for all versions
    for version_dir in "$LLVM_CUSTOM_TOOLCHAINS_DIR"/*; do
        if [ -d "$version_dir/bin" ]; then
            for binary in clang clang++ clangd lld llvm-config lldb opt llc lli; do
                touch "$version_dir/bin/$binary"
                chmod +x "$version_dir/bin/$binary"
            done
        fi
    done

    # Enable test mode and disable logs
    export QUIET_MODE=1
    export EXPRESSION_VERBOSE=0
    export EXPRESSION_DEBUG=0

    # Source the functions
    source "$BATS_TEST_DIRNAME/../../llvm-functions.sh"
}

# Test teardown
teardown() {
    # Restore original HOME and remove test directory
    export HOME="$HOME_BACKUP"
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"

    # Clean up environment variables
    unset LLVM_TEST_MODE
    unset QUIET_MODE
    unset EXPRESSION_VERBOSE
    unset EXPRESSION_DEBUG
    unset _ACTIVE_LLVM
}

# =============================================================================
# VERSION EXPRESSION PARSING TESTS
# =============================================================================

@test "llvm-parse-version-expression: latest selector" {
    run llvm-parse-version-expression "latest"
    [ "$status" -eq 0 ]
    [ "$output" = "selector:latest" ]
}

@test "llvm-parse-version-expression: oldest selector" {
    run llvm-parse-version-expression "oldest"
    [ "$status" -eq 0 ]
    [ "$output" = "selector:oldest" ]
}

@test "llvm-parse-version-expression: newest selector (alias for latest)" {
    run llvm-parse-version-expression "newest"
    [ "$status" -eq 0 ]
    [ "$output" = "selector:latest" ]
}

@test "llvm-parse-version-expression: earliest selector (alias for oldest)" {
    run llvm-parse-version-expression "earliest"
    [ "$status" -eq 0 ]
    [ "$output" = "selector:oldest" ]
}

@test "llvm-parse-version-expression: prebuilt type filter" {
    run llvm-parse-version-expression "prebuilt"
    [ "$status" -eq 0 ]
    [ "$output" = "type:prebuilt" ]
}

@test "llvm-parse-version-expression: source type filter" {
    run llvm-parse-version-expression "source"
    [ "$status" -eq 0 ]
    [ "$output" = "type:source" ]
}

@test "llvm-parse-version-expression: latest-prebuilt combined expression" {
    run llvm-parse-version-expression "latest-prebuilt"
    [ "$status" -eq 0 ]
    [ "$output" = "type:prebuilt,selector:latest" ]
}

@test "llvm-parse-version-expression: latest-source combined expression" {
    run llvm-parse-version-expression "latest-source"
    [ "$status" -eq 0 ]
    [ "$output" = "type:source,selector:latest" ]
}

@test "llvm-parse-version-expression: version range >=18.0.0" {
    run llvm-parse-version-expression ">=18.0.0"
    [ "$status" -eq 0 ]
    [ "$output" = "range:>=18.0.0" ]
}

@test "llvm-parse-version-expression: version range <=19.1.0" {
    run llvm-parse-version-expression "<=19.1.0"
    [ "$status" -eq 0 ]
    [ "$output" = "range:<=19.1.0" ]
}

@test "llvm-parse-version-expression: tilde range ~19.1" {
    run llvm-parse-version-expression "~19.1"
    [ "$status" -eq 0 ]
    [ "$output" = "range:~19.1" ]
}

@test "llvm-parse-version-expression: wildcard range 18.*" {
    run llvm-parse-version-expression "18.*"
    [ "$status" -eq 0 ]
    [ "$output" = "range:18.*" ]
}

@test "llvm-parse-version-expression: specific version llvmorg-18.1.8" {
    run llvm-parse-version-expression "llvmorg-18.1.8"
    [ "$status" -eq 0 ]
    [ "$output" = "specific:llvmorg-18.1.8" ]
}

@test "llvm-parse-version-expression: specific version with numeric format" {
    run llvm-parse-version-expression "18.1.8"
    [ "$status" -eq 0 ]
    [ "$output" = "specific:18.1.8" ]
}

@test "llvm-parse-version-expression: invalid expression" {
    run llvm-parse-version-expression "invalid-expression"
    [ "$status" -eq 1 ]
}

@test "llvm-parse-version-expression: empty expression" {
    run llvm-parse-version-expression ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# VERSION MATCHING TESTS
# =============================================================================

@test "llvm-match-versions: latest selector returns newest version" {
    run llvm-match-versions "latest"
    [ "$status" -eq 0 ]
    [ "$output" = "source-llvmorg-21-init" ]
}

@test "llvm-match-versions: oldest selector returns oldest version" {
    run llvm-match-versions "oldest"
    [ "$status" -eq 0 ]
    [ "$output" = "llvmorg-18.1.8" ]
}

@test "llvm-match-versions: prebuilt filter returns only prebuilt versions" {
    run llvm-match-versions "prebuilt"
    [ "$status" -eq 0 ]

    # Should contain exactly 3 prebuilt versions
    [ $(echo "$output" | wc -l) -eq 3 ]

    # Should contain the expected prebuilt versions
    echo "$output" | grep -q "llvmorg-18.1.8"
    echo "$output" | grep -q "llvmorg-19.1.7"
    echo "$output" | grep -q "llvmorg-20.1.0"

    # Should NOT contain source versions
    ! echo "$output" | grep -q "source-"
}

@test "llvm-match-versions: source filter returns only source versions" {
    run llvm-match-versions "source"
    [ "$status" -eq 0 ]

    # Should contain exactly 2 source versions
    [ $(echo "$output" | wc -l) -eq 2 ]

    # Should contain the expected source versions
    echo "$output" | grep -q "source-llvmorg-20.1.0"
    echo "$output" | grep -q "source-llvmorg-21-init"

    # Should only contain source versions
    echo "$output" | grep -q "^source-"
}

@test "llvm-match-versions: latest-prebuilt returns newest prebuilt version" {
    run llvm-match-versions "latest-prebuilt"
    [ "$status" -eq 0 ]
    [ "$output" = "llvmorg-20.1.0" ]
}

@test "llvm-match-versions: latest-source returns newest source version" {
    run llvm-match-versions "latest-source"
    [ "$status" -eq 0 ]
    [ "$output" = "source-llvmorg-21-init" ]
}

@test "llvm-match-versions: specific version match" {
    run llvm-match-versions "llvmorg-18.1.8"
    [ "$status" -eq 0 ]
    [ "$output" = "llvmorg-18.1.8" ]
}

@test "llvm-match-versions: specific source version match" {
    run llvm-match-versions "source-llvmorg-20.1.0"
    [ "$status" -eq 0 ]
    [ "$output" = "source-llvmorg-20.1.0" ]
}

@test "llvm-match-versions: nonexistent version returns error" {
    run llvm-match-versions "nonexistent-version"
    [ "$status" -eq 1 ]
}

@test "llvm-match-versions: empty expression returns error" {
    run llvm-match-versions ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# VERSION RANGE MATCHING TESTS
# =============================================================================

@test "llvm-version-matches-range: version matches >=18.0.0" {
    run llvm-version-matches-range "llvmorg-18.1.8" ">=18.0.0"
    [ "$status" -eq 0 ]
}

@test "llvm-version-matches-range: version matches <=20.0.0" {
    run llvm-version-matches-range "llvmorg-19.1.7" "<=20.0.0"
    [ "$status" -eq 0 ]
}

@test "llvm-version-matches-range: version matches ~19.1 (tilde range)" {
    run llvm-version-matches-range "llvmorg-19.1.7" "~19.1"
    [ "$status" -eq 0 ]
}

@test "llvm-version-matches-range: version matches 18.* wildcard" {
    run llvm-version-matches-range "llvmorg-18.1.8" "18.*"
    [ "$status" -eq 0 ]
}

@test "llvm-version-matches-range: version does not match >20.0.0" {
    run llvm-version-matches-range "llvmorg-18.1.8" ">20.0.0"
    [ "$status" -eq 1 ]
}

@test "llvm-version-matches-range: version does not match <18.0.0" {
    run llvm-version-matches-range "llvmorg-19.1.7" "<18.0.0"
    [ "$status" -eq 1 ]
}

@test "llvm-version-matches-range: source version matches range" {
    run llvm-version-matches-range "source-llvmorg-20.1.0" ">=19.0.0"
    [ "$status" -eq 0 ]
}

# =============================================================================
# VERBOSITY CONTROL TESTS
# =============================================================================

@test "llvm-match-versions: silent mode produces clean output" {
    export QUIET_MODE=1
    export EXPRESSION_VERBOSE=0
    export EXPRESSION_DEBUG=0

    run llvm-match-versions "latest"
    [ "$status" -eq 0 ]

    # Output should not contain log prefixes
    ! echo "$output" | grep -q "🔍"
    ! echo "$output" | grep -q "🐛"
    ! echo "$output" | grep -q "Expression:"
    ! echo "$output" | grep -q "Debug:"
}

@test "llvm-match-versions: verbose mode shows expression logs" {
    export QUIET_MODE=0
    export EXPRESSION_VERBOSE=1
    export EXPRESSION_DEBUG=0

    run llvm-match-versions "latest"
    [ "$status" -eq 0 ]

    # Output should contain verbose logs
    echo "$output" | grep -q "Expression:"
}

@test "llvm-match-versions: debug mode shows detailed logs" {
    export QUIET_MODE=0
    export EXPRESSION_VERBOSE=0
    export EXPRESSION_DEBUG=1

    run llvm-match-versions "latest"
    [ "$status" -eq 0 ]

    # Output should contain debug logs
    echo "$output" | grep -q "Debug:"
}

# =============================================================================
# INTEGRATION TESTS WITH EXISTING FUNCTIONS
# =============================================================================

@test "integration: expressions work with llvm-get-versions" {
    # Verify that the test setup creates versions that can be listed
    run llvm-get-versions simple
    [ "$status" -eq 0 ]

    # Should list all 5 test versions
    [ $(echo "$output" | wc -l) -eq 5 ]

    # Verify specific versions exist
    echo "$output" | grep -q "llvmorg-18.1.8"
    echo "$output" | grep -q "source-llvmorg-21-init"
}

@test "integration: expressions work with llvm-parse-version" {
    # Test that version parsing works for expression-matched versions
    run llvm-match-versions "latest"
    [ "$status" -eq 0 ]
    latest_version="$output"

    run llvm-parse-version "$latest_version"
    [ "$status" -eq 0 ]
    [ "$output" = "21" ]
}

@test "integration: expressions work with llvm-version-exists" {
    # Test that matched versions actually exist
    run llvm-match-versions "latest-prebuilt"
    [ "$status" -eq 0 ]
    latest_prebuilt="$output"

    run llvm-version-exists "$latest_prebuilt"
    [ "$status" -eq 0 ]
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "edge case: expression with whitespace is handled" {
    run llvm-parse-version-expression " latest "
    [ "$status" -eq 0 ]
    [ "$output" = "selector:latest" ]
}

@test "edge case: case insensitive expressions" {
    run llvm-parse-version-expression "LATEST"
    [ "$status" -eq 0 ]
    [ "$output" = "selector:latest" ]
}

@test "edge case: mixed case expressions" {
    run llvm-parse-version-expression "Latest-Prebuilt"
    [ "$status" -eq 0 ]
    [ "$output" = "type:prebuilt,selector:latest" ]
}

@test "edge case: no versions available" {
    # Remove all version directories
    rm -rf "$LLVM_TOOLCHAINS_DIR"/*

    run llvm-match-versions "latest"
    [ "$status" -eq 1 ]
}

@test "edge case: expression matches no versions" {
    # Try to match a range that no version satisfies
    run llvm-match-versions ">=25.0.0"
    [ "$status" -eq 1 ]
}

@test "error handling: invalid range operator" {
    run llvm-version-matches-range "llvmorg-18.1.8" "??18.0.0"
    [ "$status" -eq 1 ]
}

@test "error handling: malformed version in range check" {
    run llvm-version-matches-range "invalid-version" ">=18.0.0"
    [ "$status" -eq 1 ]
}
