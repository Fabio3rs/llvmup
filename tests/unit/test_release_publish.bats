#!/usr/bin/env bats
setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../packaging/publish.sh"
    export GITHUB_REPOSITORY=Fabio3rs/llvmup
    export MOCK_ROOT="$BATS_TEST_TMPDIR"
    mkdir -p "$MOCK_ROOT/bin" "$MOCK_ROOT/dist" "$MOCK_ROOT/remote"
    for name in llvmup-linux.tar.gz llvmup-windows.zip bootstrap.sh bootstrap.ps1 SHA256SUMS; do echo "$name" > "$MOCK_ROOT/dist/$name"; done
    export PATH="$MOCK_ROOT/bin:$PATH"
    cat > "$MOCK_ROOT/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_ROOT/calls"
if [[ $1 == api ]]; then
    if [[ -f $MOCK_ROOT/api-error ]]; then cat "$MOCK_ROOT/api-error" >&2; exit 1; fi
    jq -n --args '$ARGS.positional | map({name: .}) | {assets: .}' $(ls "$MOCK_ROOT/remote")
elif [[ $2 == download ]]; then
    cp "$MOCK_ROOT/remote/$5" "$7/$5"
elif [[ $2 == upload || $2 == create ]]; then
    for arg in "$@"; do [[ ! -f $arg ]] || cp "$arg" "$MOCK_ROOT/remote/"; done
else exit 99
fi
SH
    chmod +x "$MOCK_ROOT/bin/gh"
}
@test "uploads assets to a manually created release without recreating it" {
    run bash "$SCRIPT" v0.6.0 "$MOCK_ROOT/dist"
    [ "$status" -eq 0 ]
    grep -q '^release upload v0.6.0 ' "$MOCK_ROOT/calls"
    ! grep -q '^release create' "$MOCK_ROOT/calls"
    [ -f "$MOCK_ROOT/remote/SHA256SUMS" ]
}
@test "repeated publication skips identical assets" {
    cp "$MOCK_ROOT/dist/"* "$MOCK_ROOT/remote/"
    run bash "$SCRIPT" v0.6.0 "$MOCK_ROOT/dist"
    [ "$status" -eq 0 ]
    ! grep -Eq '^release (upload|create)' "$MOCK_ROOT/calls"
}
@test "partial publication uploads only missing assets" {
    cp "$MOCK_ROOT/dist/bootstrap.sh" "$MOCK_ROOT/remote/"
    run bash "$SCRIPT" v0.6.0 "$MOCK_ROOT/dist"
    [ "$status" -eq 0 ]
    line=$(grep '^release upload' "$MOCK_ROOT/calls")
    [[ $line != *'/bootstrap.sh'* ]]
    [ -f "$MOCK_ROOT/remote/SHA256SUMS" ]
}
@test "conflicting asset aborts before uploading anything" {
    echo different > "$MOCK_ROOT/remote/bootstrap.ps1"
    run bash "$SCRIPT" v0.6.0 "$MOCK_ROOT/dist"
    [ "$status" -ne 0 ]
    [[ $output == *'Existing asset differs'* ]]
    ! grep -Eq '^release (upload|create)' "$MOCK_ROOT/calls"
}
@test "missing release is created and prerelease suffix is honored" {
    echo 'gh: Not Found (HTTP 404)' > "$MOCK_ROOT/api-error"
    run bash "$SCRIPT" v0.6.1-rc.1 "$MOCK_ROOT/dist"
    [ "$status" -eq 0 ]
    grep -q 'release create v0.6.1-rc.1 --verify-tag --generate-notes --prerelease' "$MOCK_ROOT/calls"
}
@test "API failure does not attempt to create or upload a release" {
    echo 'gh: unavailable (HTTP 503)' > "$MOCK_ROOT/api-error"
    run bash "$SCRIPT" v0.6.0 "$MOCK_ROOT/dist"
    [ "$status" -ne 0 ]
    ! grep -Eq '^release (upload|create)' "$MOCK_ROOT/calls"
}
