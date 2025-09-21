#!/usr/bin/env bats

load "../fixtures/test_helpers.bash"

@test "llvmup passes --disable-libc-wno-error to llvm-build" {
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    run ./llvmup --from-source --verbose --disable-libc-wno-error llvmorg-18.1.8

    assert_success
    assert_output --partial "Option: LIBC_WNO_ERROR flag disabled"
    assert_output --partial "Arguments to pass to target script:"
    assert_output --partial "--disable-libc-wno-error"
    assert_output --partial "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
}

@test "llvmup help includes --disable-libc-wno-error option" {
    run ./llvmup --help

    # Help exits successfully when requested explicitly
    assert_success
    assert_output --partial "--disable-libc-wno-error"
    assert_output --partial "Disable LIBC_WNO_ERROR=ON flag"
}

@test "llvmup works without --disable-libc-wno-error (default behavior)" {
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    run ./llvmup --from-source --verbose llvmorg-18.1.8

    assert_success
    assert_output --partial "Added LIBC_WNO_ERROR=ON flag"
    # Should not contain the disabled message
    run bash -c 'echo "$output" | grep -v "LIBC_WNO_ERROR flag disabled"'
    assert_success
}
