#!/usr/bin/env bats

@test "llvm-prebuilt installs and verifies through HTTP redirects without a HEAD request" {
    run python3 "$BATS_TEST_DIRNAME/prebuilt_http.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}
