#!/usr/bin/env bats

# Test setup for llvm-prebuilt script testing
setup() {
    # Create temporary test directories
    export TEST_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    export HOME="$TEST_DIR"
    export LLVMUP_ALLOW_FILE_URLS=1
    export LLVMUP_ASSET_FORMATS=tar.xz
    unset LLVM_HOME LLVM_TOOLCHAINS_DIR LLVMUP_CACHE_DIR

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

@test "selection adapter accepts empty components under nounset" {
    run bash -c '
        set -euo pipefail
        SCRIPT_DIR=$1
        source "$SCRIPT_DIR/libexec/llvmup-selection.sh"
        PROFILE=""
        COMPONENTS=()
        STRIP=0
        llvm_selection_init
        [ "$LLVM_SELECTION_ENABLED" -eq 0 ]
        [ "$LLVM_SELECTION_JSON" = '\''{"selective":false,"legacy":false,"key":"full"}'\'' ]
        unset COMPONENTS
        llvm_selection_init
        [ "$LLVM_SELECTION_ENABLED" -eq 0 ]
    ' _ "$BATS_TEST_DIRNAME/../.."
    [ "$status" -eq 0 ]
}

@test "selection adapter preserves component arguments under nounset" {
    run bash -c '
        set -euo pipefail
        SCRIPT_DIR=$1
        source "$SCRIPT_DIR/libexec/llvmup-selection.sh"
        PROFILE=""
        COMPONENTS=("clang" "llvm-cov")
        STRIP=0
        llvm_selection_init
        [ "$LLVM_SELECTION_ENABLED" -eq 1 ]
        [ "${LLVM_SELECTION_ARGS[0]}" = --component ]
        [ "${LLVM_SELECTION_ARGS[1]}" = clang ]
        [ "${LLVM_SELECTION_ARGS[2]}" = --component ]
        [ "${LLVM_SELECTION_ARGS[3]}" = llvm-cov ]
    ' _ "$BATS_TEST_DIRNAME/../.."
    [ "$status" -eq 0 ]
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
    tar -cJf "$archive" -C "$TEST_DIR/package" "$(basename "$package_dir")"

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

@test "llvm-prebuilt exposes the supported prebuilt flags" {
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--profile"* && "$output" == *"--verify"* ]]
}

@test "llvm-prebuilt defaults to latest and reuses the exact managed installation" {
    create_download_fixture
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt"
    [ "$status" -eq 0 ]
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" 20.1.8
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}

@test "an alternate install name reuses the verified archive and records a cache hit" {
    create_download_fixture
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --name first
    [ "$status" -eq 0 ]
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --name "second toolchain's home"
    [ "$status" -eq 0 ]
    jq -e '.installation.cache_hit == true' "$LLVM_TOOLCHAINS_DIR/second toolchain's home/.llvmup-toolchain.json"
    [ ! -e "$LLVM_TOOLCHAINS_DIR/.second toolchain's home.llvmup.lock" ]
}

@test "llvm-prebuilt rejects a mismatched managed installation and preserves it" {
    create_download_fixture
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --name custom
    [ "$status" -eq 0 ]
    manifest="$LLVM_TOOLCHAINS_DIR/custom/.llvmup-toolchain.json"
    jq '.provider_release = "other"' "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --name custom
    [ "$status" -ne 0 ]
    [[ "$output" == *"identity or asset differs"* ]]
    [ -x "$LLVM_TOOLCHAINS_DIR/custom/bin/clang" ]
}

@test "llvm-prebuilt strict verifies digest and Sigstore attestation before installing" {
    create_download_fixture "" jsonl
    install_fake_gh 0
    export LLVMUP_REQUIRE_VERIFY=1

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -eq 0 ]
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
    [[ "$output" == *"origin is not authenticated"* ]]
}

@test "llvm-prebuilt strict rejects checksum-only verification" {
    create_download_fixture

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify strict "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a valid GPG signature"* ]]
}

@test "an invalid verification policy fails before writing a toolchain" {
    create_download_fixture
    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verify typo 20.1.8
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid verification policy"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8" ]
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
    [[ "$output" == *"Incomplete toolchain already exists"* ]]
}

@test "llvm-prebuilt rejects an incomplete restored toolchain" {
    create_download_fixture
    mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin"
    printf '#!/bin/sh\nexit 0\n' > "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang"
    chmod +x "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8/bin/clang"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Incomplete toolchain already exists"* ]]
}

@test "llvm-prebuilt installs a custom name and sets it as default" {
    create_download_fixture
    export LLVMUP_SKIP_VERIFY=1

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --name custom-llvm --default "20.1.8"

    [ "$status" -eq 0 ]
    [ -x "$LLVM_TOOLCHAINS_DIR/custom-llvm/bin/clang" ]
    [ -L "$HOME/.llvm/default" ]
    [ "$(basename "$(readlink "$HOME/.llvm/default")")" = "custom-llvm" ]
    [[ "$output" == *"Installed custom-llvm successfully"* ]]
}

@test "verbose extraction propagates tar failures" {
    create_download_fixture
    export LLVMUP_SKIP_VERIFY=1
    local real_tar
    real_tar="$(command -v tar)"
    mkdir -p "$TEST_DIR/fake-bin"
    cat > "$TEST_DIR/fake-bin/tar" << EOF
#!/bin/sh
if [ "\$1" = "-tf" ]; then
    exec "$real_tar" "\$@"
fi
exit 2
EOF
    chmod +x "$TEST_DIR/fake-bin/tar"
    export PATH="$TEST_DIR/fake-bin:$PATH"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" --verbose "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"tar"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8" ]
}

@test "invalid extracted toolchain is never published" {
    create_download_fixture
    export LLVMUP_SKIP_VERIFY=1
    local package_dir="$TEST_DIR/package/LLVM-20.1.8-Linux-X64"
    local archive="$TEST_DIR/LLVM-20.1.8-Linux-X64.tar.xz"
    rm "$package_dir/bin/clang++"
    tar -cJf "$archive" -C "$TEST_DIR/package" "$(basename "$package_dir")"
    jq '.[] .assets[0].digest = ""' "$LLVMUP_RELEASES_FILE" > "$TEST_DIR/releases.tmp"
    mv "$TEST_DIR/releases.tmp" "$LLVMUP_RELEASES_FILE"

    run "$BATS_TEST_DIRNAME/../../llvm-prebuilt" "20.1.8"

    [ "$status" -ne 0 ]
    [[ "$output" == *"official LLVM requires clang and clang++"* ]]
    [ ! -e "$LLVM_TOOLCHAINS_DIR/llvmorg-20.1.8" ]
}
