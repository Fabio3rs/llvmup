#!/usr/bin/env bats
setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    export LLVMUP_PREFIX="$BATS_TEST_TMPDIR/prefix with spaces"
    unset LLVMUP_INSTALL_DIR LLVMUP_COMPLETION_DIR LLVMUP_ZSH_COMPLETION_DIR LLVMUP_SYSTEM_INSTALL
    mkdir -p "$HOME" "$BATS_TEST_TMPDIR/elsewhere"
    python3 "$REPO/packaging/build.py" v0.0.0-test --output "$BATS_TEST_TMPDIR/dist"
    tar -xzf "$BATS_TEST_TMPDIR/dist/llvmup-linux.tar.gz" -C "$BATS_TEST_TMPDIR"
    PACKAGE="$BATS_TEST_TMPDIR/llvmup"
    cd "$BATS_TEST_TMPDIR/elsewhere"
}
@test "release build is reproducible and excludes local reports" {
    python3 "$REPO/packaging/build.py" v0.0.0-test --output "$BATS_TEST_TMPDIR/again"
    cmp "$BATS_TEST_TMPDIR/dist/SHA256SUMS" "$BATS_TEST_TMPDIR/again/SHA256SUMS"
    [ ! -e "$PACKAGE/REVIEW_FINDINGS.md" ]
    [ ! -e "$PACKAGE/.git" ]
    [ -e "$PACKAGE/githubreleases.json" ]
    grep -q "version='v0.0.0-test'" "$BATS_TEST_TMPDIR/dist/bootstrap.sh"
}
@test "package installs from another cwd, repeats, and uninstalls without checkout or directory variables" {
    echo '# keep profile' > "$HOME/.bashrc"
    run bash "$PACKAGE/install.sh" --no-profile
    [ "$status" -eq 0 ]
    run bash "$PACKAGE/install.sh" --no-profile
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.bashrc")" = '# keep profile' ]
    [ -x "$LLVMUP_PREFIX/bin/llvmup" ]
    [ -x "$LLVMUP_PREFIX/bin/uninstall.sh" ]
    mkdir -p "$HOME/.llvm/toolchains/keep"
    echo untouched > "$LLVMUP_PREFIX/bin/unrelated"
    bin="$LLVMUP_PREFIX/bin"
    rm -rf "$PACKAGE"
    unset LLVMUP_PREFIX
    run bash "$bin/uninstall.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$bin/llvmup" ]
    [ ! -e "$BATS_TEST_TMPDIR/prefix with spaces/share/bash-completion/completions/llvmup" ]
    [ -d "$HOME/.llvm/toolchains/keep" ]
    [ "$(cat "$bin/unrelated")" = untouched ]
}
@test "incomplete package cannot change an existing installation" {
    bash "$PACKAGE/install.sh" --no-profile >/dev/null
    before=$(sha256sum "$LLVMUP_PREFIX/bin/llvmup")
    echo broken > "$PACKAGE/llvmup"
    rm "$PACKAGE/llvm-build"
    run bash "$PACKAGE/install.sh" --no-profile
    [ "$status" -ne 0 ]
    [ "$before" = "$(sha256sum "$LLVMUP_PREFIX/bin/llvmup")" ]
}
@test "copy failure rolls back files already replaced" {
    bash "$PACKAGE/install.sh" --no-profile >/dev/null
    before=$(sha256sum "$LLVMUP_PREFIX/bin/llvmup")
    echo changed > "$PACKAGE/llvmup"
    mkdir "$BATS_TEST_TMPDIR/mock"
    export REAL_CP="$(command -v cp)"
    cat > "$BATS_TEST_TMPDIR/mock/cp" <<'SH'
#!/bin/bash
case "${@: -1}" in */llvm-prebuilt.llvmup-new-*) exit 1 ;; esac
exec "$REAL_CP" "$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/mock/cp"
    PATH="$BATS_TEST_TMPDIR/mock:$PATH" run bash "$PACKAGE/install.sh" --no-profile
    [ "$status" -ne 0 ]
    [ "$before" = "$(sha256sum "$LLVMUP_PREFIX/bin/llvmup")" ]
    [ ! -e "$LLVMUP_PREFIX/bin/.llvmup-install.lock" ]
}
mock_downloads() {
    export FIXTURE_ASSETS="$BATS_TEST_TMPDIR/dist"
    mkdir "$BATS_TEST_TMPDIR/mock"
    cat > "$BATS_TEST_TMPDIR/mock/curl" <<'SH'
#!/bin/bash
while (($#)); do
    case "$1" in --output) destination=$2; shift ;; https://*) url=$1 ;; esac
    shift
done
[[ $url == https://github.com/Fabio3rs/llvmup/releases/download/v0.0.0-test/* ]] || exit 90
[[ ${INTERRUPT_DOWNLOAD:-0} == 0 ]] || { echo truncated > "$destination"; exit 18; }
cp "$FIXTURE_ASSETS/${url##*/}" "$destination"
SH
    chmod +x "$BATS_TEST_TMPDIR/mock/curl"
    export PATH="$BATS_TEST_TMPDIR/mock:$PATH"
}
@test "bootstrap installs a verified package with mocked HTTPS downloads" {
    mock_downloads
    run bash "$BATS_TEST_TMPDIR/dist/bootstrap.sh" --no-profile
    [ "$status" -eq 0 ]
    [ -x "$LLVMUP_PREFIX/bin/llvmup" ]
    [ "$(cat "$LLVMUP_PREFIX/bin/llvmup-version")" = v0.0.0-test ]
}
@test "checksum mismatch and interrupted downloads never install files" {
    mock_downloads
    echo corrupted >> "$FIXTURE_ASSETS/llvmup-linux.tar.gz"
    run bash "$BATS_TEST_TMPDIR/dist/bootstrap.sh" --no-profile
    [ "$status" -ne 0 ]
    [[ "$output" == *'checksum mismatch'* ]]
    [ ! -e "$LLVMUP_PREFIX" ]
    export INTERRUPT_DOWNLOAD=1
    run bash "$BATS_TEST_TMPDIR/dist/bootstrap.sh" --no-profile
    [ "$status" -ne 0 ]
    [ ! -e "$LLVMUP_PREFIX" ]
}
@test "bootstrap rejects traversal even with a matching checksum" {
    mock_downloads
    python3 - "$FIXTURE_ASSETS" <<'PY'
import hashlib, io, pathlib, sys, tarfile
p = pathlib.Path(sys.argv[1])
with tarfile.open(p / 'llvmup-linux.tar.gz', 'w:gz') as t:
    info = tarfile.TarInfo('llvmup/../../escaped'); info.size = 1
    t.addfile(info, io.BytesIO(b'x'))
(p / 'SHA256SUMS').write_text(hashlib.sha256((p / 'llvmup-linux.tar.gz').read_bytes()).hexdigest() + '  llvmup-linux.tar.gz\n')
PY
    run bash "$BATS_TEST_TMPDIR/dist/bootstrap.sh" --no-profile
    [ "$status" -ne 0 ]
    [[ "$output" == *'Unsafe archive path'* ]]
    [ ! -e "$LLVMUP_PREFIX" ]
}
@test "profiles preserve literal shell metacharacters in installation paths" {
    export LLVMUP_PREFIX="$BATS_TEST_TMPDIR/literal-\$HOME-\`echo bad\`"
    touch "$HOME/.bashrc"
    run bash "$PACKAGE/install.sh"
    [ "$status" -eq 0 ]
    # Replace the sourced helper to observe the actual path without activation.
    echo 'echo literal-path-loaded' > "$LLVMUP_PREFIX/bin/llvm-functions.sh"
    run bash -c 'source "$HOME/.bashrc"'
    [ "$status" -eq 0 ]
    [ "$output" = literal-path-loaded ]
}
