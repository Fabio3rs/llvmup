#!/usr/bin/env bats

# Test setup for llvm-prebuilt script testing
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"

    # Save original environment
    export PATH_BACKUP="$PATH"

    # Ensure required tools are available
    if ! command -v curl >/dev/null 2>&1; then
        skip "curl is required for testing"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is required for testing"
    fi
}

create_installed_toolchain() {
    local version="$1"
    local bin_dir="$LLVM_TOOLCHAINS_DIR/$version/bin"

    mkdir -p "$bin_dir"
    printf '#!/bin/sh\nexit 0\n' > "$bin_dir/clang"
    printf '#!/bin/sh\nexit 0\n' > "$bin_dir/clang++"
    chmod +x "$bin_dir/clang" "$bin_dir/clang++"
}

create_download_fixture() {
    local digest_override="${1:-}"
    local verification_material="${2:-none}"
    local package_dir="$TEST_DIR/package/LLVM-20.1.8-Linux-X64"
    local archive="$TEST_DIR/LLVM-20.1.8-Linux-X64.tar.xz"
    local digest

    mkdir -p "$package_dir/bin"
    printf '#!/bin/sh\necho clang version 20.1.8\n' > "$package_dir/bin/clang"
    printf '#!/bin/sh\necho clang version 20.1.8\n' > "$package_dir/bin/clang++"
    chmod +x "$package_dir/bin/clang" "$package_dir/bin/clang++"
    tar -cf "$archive" -C "$TEST_DIR/package" "$(basename "$package_dir")"

    digest="sha256:$(sha256sum "$archive" | awk '{print $1}')"
    [ -n "$digest_override" ] && digest="$digest_override"

    printf 'test signature\n' > "$archive.sig"
    printf '{"test":"attestation bundle"}\n' > "$archive.jsonl"

    jq -n \
        --arg url "file://$archive" \
        --arg digest "$digest" \
        --arg sig_url "file://$archive.sig" \
        --arg jsonl_url "file://$archive.jsonl" \
        --arg material "$verification_material" \
        '[{
          tag_name: "llvmorg-20.1.8", draft: false, prerelease: false,
          assets: ([{
            id: 2018, name: "LLVM-20.1.8-Linux-X64.tar.xz",
            state: "uploaded", browser_download_url: $url, digest: $digest
          }] +
          (if ($material == "sig" or $material == "both") then [{
            id: 2019, name: "LLVM-20.1.8-Linux-X64.tar.xz.sig",
            state: "uploaded", browser_download_url: $sig_url
          }] else [] end) +
          (if ($material == "jsonl" or $material == "both") then [{
            id: 2020, name: "LLVM-20.1.8-Linux-X64.tar.xz.jsonl",
            state: "uploaded", browser_download_url: $jsonl_url
          }] else [] end))
        }]' > "$TEST_DIR/releases.json"

    export LLVMUP_RELEASES_FILE="$TEST_DIR/releases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
}

install_fake_gh() {
    local exit_code="${1:-0}"
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf '%s\\n' \"\$*\" >> '$TEST_DIR/gh-calls.log'" \
        'case "$*" in *"--help"*) exit 0 ;; esac' \
        "exit $exit_code" > "$fake_bin/gh"
    chmod +x "$fake_bin/gh"
    export PATH="$fake_bin:$PATH"
}

install_fake_gpg() {
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    printf 'test keys\n' > "$TEST_DIR/release-keys.asc"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf '%s\\n' \"\$*\" >> '$TEST_DIR/gpg-calls.log'" \
        'case "$*" in' \
        '  *"--import"*) exit 0 ;;' \
        "  *\"--verify\"*) printf '[GNUPG:] VALIDSIG AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 0 0 0 0 0 0 0 0 0\\n'; exit 0 ;;" \
        'esac' \
        'exit 1' > "$fake_bin/gpg"
    chmod +x "$fake_bin/gpg"
    export PATH="$fake_bin:$PATH"
    export LLVMUP_RELEASE_KEYS_FILE="$TEST_DIR/release-keys.asc"
}

# Test cleanup
teardown() {
    # Restore original environment
    export HOME="$HOME_BACKUP"
    export PATH="$PATH_BACKUP"

    # Clean up test directory
    rm -rf "$TEST_DIR"
}

@test "llvm-prebuilt checks for required dependencies" {
    # Create temporary PATH without required tools
    local temp_path="/tmp/empty_path_$$"
    mkdir -p "$temp_path"

    # Test with empty PATH (no commands available)
    PATH="$temp_path" run "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"curl"* ]] || [[ "$output" == *"jq"* ]]

    rmdir "$temp_path"
}

@test "llvm-prebuilt shows help message" {
    # Test help flag - script returns 0 for help, not 1
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "llvm-prebuilt resolves releases through the shared offline fixture" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
    create_installed_toolchain "llvmorg-20.1.8"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolving stable LLVM release: 20.1.8"* ]]
    [[ "$output" == *"llvmorg-20.1.8 is already installed"* ]]
}

@test "llvm-prebuilt defaults to the latest stable release" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
    create_installed_toolchain "llvmorg-21.1.0"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolving stable LLVM release: latest"* ]]
    [[ "$output" == *"llvmorg-21.1.0 is already installed"* ]]
}

@test "llvm-prebuilt handles invalid version selection gracefully" {
    local script_path="$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    run "$script_path" "not-a-version"

    # Should fail with invalid selection
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"invalid"* ]]
}

@test "llvm-prebuilt creates necessary directories" {
    # Test that the script contains the correct directory creation logic
    run grep -iq "mkdir.*toolchains" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]

    # Test that the script references the correct paths
    run grep -q "HOME/.llvm/toolchains" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]
}

@test "llvm-prebuilt handles network errors gracefully" {
    # Test network error handling by using an invalid URL or disconnected state
    # We'll test this by examining the error handling logic in the script

    # Check if the script has proper error handling for network failures
    run grep -q "Failed to fetch\|connection\|network" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"

    # If the script doesn't have explicit error messages, test with timeout
    if [ "$status" -ne 0 ]; then
        # Test with very short timeout to simulate network issues
        local script_path="$BATS_TEST_DIRNAME/../../llvm-prebuilt"
        export HOME="$TEST_DIR"

        # Use a very short timeout that will likely cause curl to fail
        run timeout 1 bash -c "echo '1' | '$script_path'" 2>/dev/null

        # Should exit with error status when network fails
        [ "$status" -ne 0 ]
    fi
}

@test "llvm-prebuilt shows helpful installation message with new bash functions" {
    # The script should show the correct activation command for the new system
    run grep -n "llvm-activate" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llvm-activate"* ]]

    # Should not contain the old "source activate_llvm.sh" format
    run grep -n "source activate_llvm" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -ne 0 ]
}

@test "llvm-prebuilt script syntax is valid" {
    # Test that the script has valid bash syntax
    run bash -n "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]
}

@test "llvm-prebuilt has executable permissions" {
    # Test that the script is executable
    [ -x "$BATS_TEST_DIRNAME/../../llvm-prebuilt" ]
}

@test "llvm-prebuilt contains required functions" {
    # Test that the script contains essential functions and patterns
    run grep -q "log_info\|log_error\|log_verbose" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]

    # Version selection is delegated to the shared resolver.
    run grep -q "llvm-resolve-remote-release" "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]

    run grep -q '^select_version()' "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -ne 0 ]
}

@test "llvm-prebuilt reports stable resolution and cache-aware installation state" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
    create_installed_toolchain "llvmorg-20.1.8"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolving stable LLVM release"* ]]
    [[ "$output" == *"already installed"* ]]
}

@test "llvm-prebuilt validates version selection input" {
    # Test input validation with real script behavior
    local script_path="$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    export HOME="$TEST_DIR"

    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    run "$script_path" "abc"

    # Should handle invalid input gracefully
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"invalid"* ]]
}

@test "llvm-prebuilt uses correct directory structure" {
    # Test that the script references the expected directory structure
    local script_path="$BATS_TEST_DIRNAME/../../llvm-prebuilt"

    # Check that the script contains references to the expected directory structure
    run grep -o '\$HOME/\.llvm/toolchains' "$script_path"
    [ "$status" -eq 0 ]

    # Temporary files use the runner temp directory when available.
    run grep -q 'RUNNER_TEMP.*TMPDIR' "$script_path"
    [ "$status" -eq 0 ]

    run grep -q 'mktemp -d' "$script_path"
    [ "$status" -eq 0 ]
}

@test "llvm-prebuilt treats a restored valid toolchain as already installed" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
    create_installed_toolchain "llvmorg-20.1.8"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}

@test "llvm-prebuilt strict verifies digest and Sigstore attestation before installing" {
    create_download_fixture "" jsonl
    install_fake_gh 0
    export LLVMUP_REQUIRE_VERIFY=1

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SHA256 asset.digest matches the downloaded file"* ]]
    [[ "$output" == *"GitHub/Sigstore attestation verified"* ]]
    [ -x "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang" ]
    [ -x "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang++" ]
    run jq -r '.attestation + ":" + .methods' "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/.llvmup-verification.json"
    [ "$output" = "valid:sigstore" ]
}

@test "llvm-prebuilt fails when asset.digest mismatches and REQUIRE_VERIFY set" {
    create_download_fixture "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    export LLVMUP_REQUIRE_VERIFY=1

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"SHA256 digest mismatch"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8" ]
}

@test "llvm-prebuilt warn permits checksum-only installation with an explicit warning" {
    create_download_fixture

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify warn "20.1.8"

    [ "$status" -eq 0 ]
    [[ "$output" == *"origin was not cryptographically authenticated"* ]]
}

@test "llvm-prebuilt strict rejects checksum-only verification" {
    create_download_fixture

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify strict "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a valid LLVM GPG signature"* ]]
}

@test "llvm-prebuilt aborts on an invalid Sigstore attestation even in warn mode" {
    create_download_fixture "" jsonl
    install_fake_gh 1

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify warn "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"attestation validation failed"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8" ]
}

@test "llvm-prebuilt validates both GPG and Sigstore when both materials coexist" {
    create_download_fixture "" both
    install_fake_gh 0
    install_fake_gpg

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify strict "20.1.8"

    [ "$status" -eq 0 ]
    run grep -c -- '--verify' "$TEST_DIR/gpg-calls.log"
    [ "$output" -eq 1 ]
    run grep -c -- '--repo llvm/llvm-project --bundle' "$TEST_DIR/gh-calls.log"
    [ "$output" -eq 1 ]
    run jq -r '.methods' "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/.llvmup-verification.json"
    [ "$output" = "gpg+sigstore" ]
}

@test "llvm-prebuilt strict rejects an existing toolchain without an authenticated marker" {
    create_download_fixture "" jsonl
    create_installed_toolchain "llvmorg-20.1.8"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify strict "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"verification marker is missing or incompatible"* ]]
}

@test "llvm-prebuilt rejects an incomplete restored toolchain" {
    export LLVMUP_RELEASES_FILE="$BATS_TEST_DIRNAME/../../githubreleases.json"
    export LLVM_TOOLCHAINS_DIR="$TEST_DIR/toolchains"
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin"
    printf '#!/bin/sh\nexit 0\n' > "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang"
    chmod +x "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"clang++ is missing or not executable"* ]]
    [[ "$output" == *"Incomplete LLVM installation already exists"* ]]
}
