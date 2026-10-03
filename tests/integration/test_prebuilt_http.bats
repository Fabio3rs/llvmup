#!/usr/bin/env bats

@test "llvm-prebuilt reports final HTTP size and installs through redirects" {
    run python3 "$BATS_TEST_DIRNAME/prebuilt_http.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}
