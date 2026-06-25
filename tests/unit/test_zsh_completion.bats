#!/usr/bin/env bats

setup() {
    export TEST_DIR="$BATS_TMPDIR/llvmup_zsh_completion_test_$$"
    export HOME="$TEST_DIR"
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/.cache/llvmup" "$TEST_DIR/.llvm/toolchains/llvmorg-19.1.7" "$TEST_DIR/.llvm/toolchains/source-llvmorg-20.1.0"

    cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/bin/bash
cat <<'JSON'
[
  {"tag_name": "llvmorg-21.1.0"},
  {"tag_name": "llvmorg-20.1.8"}
]
JSON
EOF
    chmod +x "$TEST_DIR/bin/curl"

    cat > "$TEST_DIR/bin/jq" <<'EOF'
#!/bin/bash
sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p'
EOF
    chmod +x "$TEST_DIR/bin/jq"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "zsh completion loads and exposes compdef" {
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi

    run zsh -fc "source '$BATS_TEST_DIRNAME/../../_llvmup'; whence -w _llvmup | grep -q function"
    [ "$status" -eq 0 ]
}

@test "zsh completion groups install suggestions" {
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi

    run zsh -fc "export HOME='$TEST_DIR'; export PATH='$TEST_DIR/bin:'\"\$PATH\"; source '$BATS_TEST_DIRNAME/../../_llvmup'; _llvmup_zsh_collect_specs _llvmup_get_install_target_items; print -r -- \"\${_LLVMUP_ZSH_EXPRESSIONS[*]}\"; print -r -- \"\${_LLVMUP_ZSH_LOCALS[*]}\"; print -r -- \"\${_LLVMUP_ZSH_REMOTES[*]}\"; print -r -- \"\${_LLVMUP_ZSH_TEMPLATES[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"latest:Newest matching version"* ]]
    [[ "$output" == *"llvmorg-19.1.7:Installed locally"* ]]
    [[ "$output" == *"llvmorg-21.1.0:Available remotely"* ]]
    [[ "$output" == *"18.*:Any 18.x version"* ]]
}

@test "zsh completion adapts config actions to config presence" {
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi

    run zsh -fc "export HOME='$TEST_DIR'; cd '$TEST_DIR'; source '$BATS_TEST_DIRNAME/../../_llvmup'; _llvmup_zsh_collect_specs _llvmup_get_config_action_items; print -r -- \"\${_LLVMUP_ZSH_CONFIGS[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == init:* ]]

    cat > "$TEST_DIR/.llvmup-config" <<'EOF'
[version]
default = "latest-prebuilt"
EOF

    run zsh -fc "export HOME='$TEST_DIR'; cd '$TEST_DIR'; source '$BATS_TEST_DIRNAME/../../_llvmup'; _llvmup_zsh_collect_specs _llvmup_get_config_action_items; print -r -- \"\${_LLVMUP_ZSH_CONFIGS[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == load:* ]]
}
