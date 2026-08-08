#!/usr/bin/env bats

# Test setup for llvmup wrapper script testing
setup() {
    # Set test mode environment variables
    export LLVM_TEST_MODE=1
    export LLVMUP_DISABLE_AUTOACTIVATE=1

    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export MOCK_SCRIPT_DIR="$TEST_DIR/mock_scripts"
    mkdir -p "$MOCK_SCRIPT_DIR"

    # Create mock llvm-prebuilt script
    cat > "$MOCK_SCRIPT_DIR/llvm-prebuilt" << 'EOF'
#!/bin/bash
echo "Mock llvm-prebuilt called with args: $*"
exit 0
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-prebuilt"

    # Create mock llvm-build script
    cat > "$MOCK_SCRIPT_DIR/llvm-build" << 'EOF'
#!/bin/bash
echo "Mock llvm-build called with args: $*"
exit 0
EOF
    chmod +x "$MOCK_SCRIPT_DIR/llvm-build"

    # Create a modified version of llvmup that uses our mock scripts
    cat > "$TEST_DIR/llvmup_test" << EOF
#!/bin/bash
set -e

SCRIPT_DIR="$MOCK_SCRIPT_DIR"

usage() {
    cat <<EOL
Usage: llvmup [--from-source] [args...]

Options:
  --from-source    Build LLVM from source instead of installing a pre-built release.

Examples:
  llvmup                    # Install a pre-built LLVM release
  llvmup --from-source     # Build LLVM from source
EOL
    exit 1
}

if [ "\$1" == "--from-source" ]; then
    shift
    echo "Building LLVM from source..."
    exec "\$SCRIPT_DIR/llvm-build" "\$@"
else
    echo "Installing pre-built LLVM release..."
    exec "\$SCRIPT_DIR/llvm-prebuilt" "\$@"
fi
EOF
    chmod +x "$TEST_DIR/llvmup_test"
}

# Test cleanup
teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

@test "llvmup shows usage when called with invalid flag" {
    run "$TEST_DIR/llvmup_test" "--help"
    # The script doesn't show usage directly, it passes --help to underlying scripts
    # So we just check that it runs and calls the appropriate script
    [[ "$output" == *"Installing pre-built LLVM release"* ]]
    [[ "$output" == *"Mock llvm-prebuilt called with args: --help"* ]]
}

@test "llvmup calls llvm-prebuilt by default" {
    run "$TEST_DIR/llvmup_test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing pre-built LLVM release"* ]]
    [[ "$output" == *"Mock llvm-prebuilt called"* ]]
}

@test "llvmup calls llvm-prebuilt with arguments" {
    run "$TEST_DIR/llvmup_test" "arg1" "arg2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing pre-built LLVM release"* ]]
    [[ "$output" == *"Mock llvm-prebuilt called with args: arg1 arg2"* ]]
}

@test "llvmup calls llvm-build with --from-source flag" {
    run "$TEST_DIR/llvmup_test" "--from-source"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Building LLVM from source"* ]]
    [[ "$output" == *"Mock llvm-build called with args:"* ]]
}

@test "llvmup calls llvm-build with --from-source and additional arguments" {
    run "$TEST_DIR/llvmup_test" "--from-source" "arg1" "arg2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Building LLVM from source"* ]]
    [[ "$output" == *"Mock llvm-build called with args: arg1 arg2"* ]]
}

@test "original llvmup script exists and is executable" {
    [ -f "$BATS_TEST_DIRNAME/../../llvmup" ]
    [ -x "$BATS_TEST_DIRNAME/../../llvmup" ]
}

@test "original llvmup script has correct shebang" {
    run head -1 "$BATS_TEST_DIRNAME/../../llvmup"
    [ "$status" -eq 0 ]
    [[ "$output" == "#!/bin/bash" ]]
}

@test "original llvmup script contains usage function" {
    run grep -n "usage()" "$BATS_TEST_DIRNAME/../../llvmup"
    [ "$status" -eq 0 ]
}

@test "original llvmup script contains --from-source check" {
    run grep -n "from-source" "$BATS_TEST_DIRNAME/../../llvmup"
    [ "$status" -eq 0 ]
}

@test "original llvmup resolves a short stable release version" {
    run env \
        LLVMUP_DISABLE_AUTOACTIVATE=1 \
        LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json" \
        "$BATS_TEST_DIRNAME/../../llvmup" resolve "20.1.8"
    [ "$status" -eq 0 ]
    [ "$output" = "llvmorg-20.1.8" ]
}

@test "original llvmup resolve supports JSON output for CI consumers" {
    run env \
        LLVMUP_DISABLE_AUTOACTIVATE=1 \
        LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json" \
        "$BATS_TEST_DIRNAME/../../llvmup" resolve --format json "~20.1"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' <<< "$output")" = "llvmorg-20.1.8" ]
}

@test "reusable action isolates caches by verification policy" {
    run grep -F '${{ inputs.verify }}' "$BATS_TEST_DIRNAME/../../action.yml"
    [ "$status" -eq 0 ]
    run grep -F 'auth-v1' "$BATS_TEST_DIRNAME/../../action.yml"
    [ "$status" -eq 0 ]
}

@test "original llvmup exposes and forwards the prebuilt verification policy" {
    run grep -F -- '--verify <POLICY>' "$BATS_TEST_DIRNAME/../../llvmup"
    [ "$status" -eq 0 ]
    run grep -F 'script_args+=("--verify" "$VERIFY_POLICY")' "$BATS_TEST_DIRNAME/../../llvmup"
    [ "$status" -eq 0 ]
}

@test "reusable action has native Linux and Windows execution paths" {
    run grep -F "runner.os == 'Windows'" "$BATS_TEST_DIRNAME/../../action.yml"
    [ "$status" -eq 0 ]
    run grep -F 'Download-Llvm.ps1' "$BATS_TEST_DIRNAME/../../action.yml"
    [ "$status" -eq 0 ]
    run grep -F 'verification:' "$BATS_TEST_DIRNAME/../../action.yml"
    [ "$status" -eq 0 ]
}

@test "action smoke test never saves the fake compiler fixture" {
    run bash -c "sed -n '/Smoke test reusable action/,/Verify action outputs/p' '$BATS_TEST_DIRNAME/../../.github/workflows/tests.yml' | grep -F 'cache: false'"
    [ "$status" -eq 0 ]
}
