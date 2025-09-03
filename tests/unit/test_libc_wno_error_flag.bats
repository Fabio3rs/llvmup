#!/usr/bin/env bats

load "../fixtures/test_helpers.bash"

@test "LIBC_WNO_ERROR flag is enabled by default" {
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    run ./llvm-build --verbose llvmorg-18.1.8

    assert_success
    assert_output --partial "Added LIBC_WNO_ERROR=ON flag"
}

@test "LIBC_WNO_ERROR flag can be disabled via command line" {
    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    run ./llvm-build --verbose --disable-libc-wno-error llvmorg-18.1.8

    assert_success
    assert_output --partial "LIBC_WNO_ERROR flag disabled"
    assert_output --partial "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
}

@test "LIBC_WNO_ERROR flag can be disabled via config file" {
    # Create a temporary config file
    cat > .llvmup-config.test << EOF
[build]
disable_libc_wno_error = true
EOF

    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    # Rename config file temporarily
    mv .llvmup-config.test .llvmup-config

    run ./llvm-build --verbose llvmorg-18.1.8

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "Config: LIBC_WNO_ERROR flag disabled"
    assert_output --partial "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
}

@test "Command line --disable-libc-wno-error overrides config file setting" {
    # Create a config file that enables the flag
    cat > .llvmup-config.test << EOF
[build]
disable_libc_wno_error = false
EOF

    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    # Rename config file temporarily
    mv .llvmup-config.test .llvmup-config

    run ./llvm-build --verbose --disable-libc-wno-error llvmorg-18.1.8

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "LIBC_WNO_ERROR flag disabled"
    assert_output --partial "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
}

@test "Help text includes disable-libc-wno-error option" {
    run ./llvm-build --help

    assert_success
    assert_output --partial "--disable-libc-wno-error"
    assert_output --partial "Disable LIBC_WNO_ERROR=ON flag"
}

@test "Config file with disable_libc_wno_error = true works" {
    # Create a temporary config file
    cat > .llvmup-config.test << EOF
[build]
name = "test-build"
disable_libc_wno_error = true
EOF

    export LLVM_TEST_MODE=1
    export LLVM_TEST_VERSION="llvmorg-18.1.8"

    # Rename config file temporarily
    mv .llvmup-config.test .llvmup-config

    run ./llvm-build --verbose llvmorg-18.1.8

    # Clean up
    rm -f .llvmup-config

    assert_success
    assert_output --partial "Config: Custom name set to test-build"
    assert_output --partial "Config: LIBC_WNO_ERROR flag disabled"
    assert_output --partial "Name: test-build"
}
