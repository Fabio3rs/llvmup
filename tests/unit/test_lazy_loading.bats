#!/usr/bin/env bats
# llvm-functions.sh is a loader: sourcing it must be cheap and side-effect free, and the
# implementation (llvmup-core.sh) must load transparently the first time a function is used.

setup() {
    export TEST_HOME="$BATS_TMPDIR/llvmup_lazy_$$"
    export HOME="$TEST_HOME"
    unset LLVM_HOME LLVM_TOOLCHAINS_DIR LLVMUP_SESSION_OVERRIDE _ACTIVE_LLVM LLVM_TEST_MODE
    export LLVMUP_DISABLE_AUTOACTIVATE=1
    export LOADER="$BATS_TEST_DIRNAME/../../llvm-functions.sh"
    export CORE="$BATS_TEST_DIRNAME/../../llvmup-core.sh"
    mkdir -p "$TEST_HOME/proj"
    cd "$TEST_HOME/proj"
}

# The "outside a project" cases only make sense when no ancestor directory carries a .llvmup-config.
require_no_ancestor_config() {
    local d="$TEST_HOME"
    while :; do
        [ -f "$d/.llvmup-config" ] && skip "an ancestor directory ($d) has a .llvmup-config"
        [ "$d" = / ] && break
        d="${d%/*}"; [ -n "$d" ] || d=/
    done
}

teardown() {
    cd /
    rm -rf "$TEST_HOME"
}

@test "sourcing the loader defines only stubs and leaves the core unloaded" {
    run bash -c "b=\$(compgen -v | wc -l); source '$LOADER'; a=\$(compgen -v | wc -l)
        echo core=\${_LLVMUP_CORE_LOADED:-0}; echo newvars=\$((a - b)); echo quiet=\${QUIET_MODE-unset}; echo red=\${RED-unset}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"core=0"* ]]
    [[ "$output" == *"quiet=unset"* ]]
    [[ "$output" == *"red=unset"* ]]
    # A handful of loader variables, not the dozens of the core.
    n="$(sed -n 's/^newvars=//p' <<<"$output")"
    [ "$n" -le 12 ]
}

@test "the first call loads the core, which replaces the stubs" {
    run bash -c "source '$LOADER'
        declare -f llvm-parse-version | grep -q _llvmup_load_core && echo stub-before
        llvm-parse-version llvmorg-18.1.8
        echo core=\${_LLVMUP_CORE_LOADED:-0}
        declare -f llvm-parse-version | grep -q _llvmup_load_core && echo stub-after || echo real-after"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub-before"* ]]
    [[ "$output" == *"18.1.8"* ]]
    [[ "$output" == *"core=1"* ]]
    [[ "$output" == *"real-after"* ]]
}

@test "the loader's API list is exactly the set of functions the core defines" {
    run bash -c "source '$LOADER'; printf '%s\n' \$_LLVMUP_API | sort"
    [ "$status" -eq 0 ]
    listed="$output"
    run bash -c "grep -o '^[A-Za-z_][A-Za-z0-9_-]*()' '$CORE' | tr -d '()' | sort"
    [ "$status" -eq 0 ]
    [ "$listed" = "$output" ]
}

@test "the core defines nothing at load time except functions and plain variables" {
    # Hooks and automatic activation belong to the loader; the core must not re-register them.
    ! grep -q '^__llvmup_autoactivate_hook()' "$CORE"
    ! grep -q '^llvm-register-autoactivate-hooks()' "$CORE"
    ! grep -q '^    llvm-autoactivate 2>' "$CORE"
}

@test "a missing core gives a clear message instead of a loop" {
    mkdir -p "$TEST_HOME/lone"
    cp "$LOADER" "$TEST_HOME/lone/llvm-functions.sh"
    run bash -c "source '$TEST_HOME/lone/llvm-functions.sh'; llvm-status"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read llvmup-core.sh"* ]]
    [[ "$output" == *"llvmup doctor"* ]]
}

@test "sourcing the loader again after the core is loaded still works" {
    run bash -c "source '$LOADER'; llvm-parse-version llvmorg-18.1.8 >/dev/null; source '$LOADER'; llvm-parse-version llvmorg-19.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"19.1.0"* ]]
}

@test "eager mode loads the core immediately" {
    run bash -c "LLVMUP_FUNCTIONS_EAGER=1 source '$LOADER'; echo core=\${_LLVMUP_CORE_LOADED:-0}; echo quiet=\${QUIET_MODE-unset}"
    [[ "$output" == *"core=1"* ]]
    [[ "$output" == *"quiet=0"* ]]
}

@test "the prompt hook does nothing outside a project and loads the core inside one" {
    require_no_ancestor_config
    unset LLVMUP_DISABLE_AUTOACTIVATE
    mkdir -p "$TEST_HOME/proj/deep/er" "$TEST_HOME/elsewhere"
    run bash -c "cd '$TEST_HOME/elsewhere'; source '$LOADER'; __llvmup_autoactivate_hook; echo outside=\${_LLVMUP_CORE_LOADED:-0}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"outside=0"* ]]

    printf '[project]\nauto_activate = false\n' > "$TEST_HOME/proj/.llvmup-config"
    run bash -c "cd '$TEST_HOME/proj/deep/er'; source '$LOADER'; echo inside=\${_LLVMUP_CORE_LOADED:-0}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inside=1"* ]]
}

@test "the prompt hook acts on a directory change, not on every prompt" {
    unset LLVMUP_DISABLE_AUTOACTIVATE
    mkdir -p "$TEST_HOME/proj2"
    printf '[project]\nauto_activate = false\n' > "$TEST_HOME/proj/.llvmup-config"
    printf '[project]\nauto_activate = false\n' > "$TEST_HOME/proj2/.llvmup-config"
    run bash -c "cd '$TEST_HOME/proj'; source '$LOADER'
        llvm-autoactivate() { echo CALLED; }
        __llvmup_autoactivate_hook; __llvmup_autoactivate_hook
        cd '$TEST_HOME/proj2'; __llvmup_autoactivate_hook; __llvmup_autoactivate_hook
        cd '$TEST_HOME/proj'; __llvmup_autoactivate_hook"
    [ "$status" -eq 0 ]
    # Loading ran the hook for the starting directory. Repeated prompts in a directory do nothing;
    # each directory change re-evaluates once.
    [ "$(grep -c CALLED <<<"$output")" -eq 2 ]
}

@test "use --auto forces a re-evaluation in the same directory" {
    unset LLVMUP_DISABLE_AUTOACTIVATE
    printf '[project]\nauto_activate = false\n' > "$TEST_HOME/proj/.llvmup-config"
    run bash -c "cd '$TEST_HOME/proj'; source '$LOADER'; llvm-parse-version x >/dev/null 2>&1
        calls=0; llvm-autoactivate() { calls=\$((calls + 1)); }
        __llvmup_autoactivate_hook
        llvm-use --auto >/dev/null 2>&1
        echo calls=\$calls"
    [[ "$output" == *"calls=1"* ]]
}

@test "the prompt hook with no project is cheap" {
    require_no_ancestor_config
    unset LLVMUP_DISABLE_AUTOACTIVATE
    run bash -c "source '$LOADER'
        s=\$(date +%s%N)
        for i in \$(seq 50); do unset _LLVMUP_HOOK_PWD; __llvmup_autoactivate_hook; done
        echo \$(( (\$(date +%s%N) - s) / 50000 ))"
    [ "$status" -eq 0 ]
    # Microseconds per call with no subshell and no external command; generous bound for slow CI.
    [ "${lines[-1]}" -lt 5000 ]
}

@test "zsh gets the same stubs, lazy core and hook" {
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    run zsh -c "source '$LOADER'; echo core=\${_LLVMUP_CORE_LOADED:-0}; llvm-parse-version llvmorg-18.1.8; echo core=\${_LLVMUP_CORE_LOADED:-0}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"core=0"*"18.1.8"*"core=1"* ]]
    run zsh -c "unset LLVMUP_DISABLE_AUTOACTIVATE; cd '$TEST_HOME'; source '$LOADER'; echo hook=\${chpwd_functions[(r)__llvmup_autoactivate_hook]:-none}; echo pre=\${precmd_functions[(r)__llvmup_autoactivate_hook]:-none}"
    [[ "$output" == *"hook=__llvmup_autoactivate_hook"* ]]
    [[ "$output" == *"pre=none"* ]]
}
