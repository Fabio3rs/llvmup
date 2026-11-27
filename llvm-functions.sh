#!/bin/bash
# llvm-functions.sh: loader for the llvmup shell integration (Bash and Zsh).
# Source this file from your shell profile (.bashrc, .zshrc, ...).
#
# Sourcing it is cheap on purpose: it defines one small stub per public function and the
# directory-change hook. The implementation (llvmup-core.sh, next to this file) is loaded the
# first time one of those functions is actually used, so an idle terminal pays for neither the
# parsing time nor the ~85 functions and helper variables of the core.
#
# Usage after sourcing:
#   llvmup <command> ...      - the main command (use, install, list, status, deactivate, ...)
#   llvm-activate <version>   - Activate an LLVM version
#   llvm-deactivate           - Deactivate current LLVM version
#
# LLVMUP_FUNCTIONS_EAGER=1 loads the core immediately (for scripts that rely on its variables).

# Where this file lives. The core and the runtime helpers are looked up next to it.
if [ -n "${ZSH_VERSION:-}" ]; then
    # Captured while loading: inside a function %N is its name.
    _LLVMUP_FUNCTIONS_DIR="${${(%):-%x}:A:h}"
elif [ -n "${BASH_SOURCE[0]:-}" ]; then
    case "${BASH_SOURCE[0]}" in
        /*) _LLVMUP_FUNCTIONS_DIR="${BASH_SOURCE[0]%/*}" ;;
        */*) _LLVMUP_FUNCTIONS_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" ;;
        *) _LLVMUP_FUNCTIONS_DIR="$PWD" ;;
    esac
fi

# Every function the core defines. A test keeps this list identical to the core.
_LLVMUP_API="
    _llvm_complete_versions llvm-activate llvm-autoactivate llvm-autoactivate-enhanced
    llvm-config-activate llvm-config-apply llvm-config-apply-directories llvm-config-init
    llvm-config-load llvm-deactivate llvm-default-set llvm-default-show llvm-default-unset
    llvm-detect-architecture llvm-detect-platform llvm-disk-usage llvm-engine-path
    llvm-env-needs-engine llvm-expression-debug-off llvm-expression-debug-on
    llvm-expression-verbose-off llvm-expression-verbose-on llvm-find-config-root
    llvm-find-runtime-script llvm-format-bytes llvm-get-active-version llvm-get-default-link
    llvm-get-default-version llvm-get-directory-bytes llvm-get-home-dir llvm-get-install-dir
    llvm-get-installation-name llvm-get-latest-version llvm-get-remote-stable-releases
    llvm-get-sources-dir llvm-get-toolchain-path llvm-get-toolchains-dir llvm-get-versions
    llvm-get-versions-json llvm-get-versions-list llvm-get-versions-simple
    llvm-github-api-request llvm-help llvm-help-command llvm-list llvm-load-config-from-root
    llvm-load-session-helpers llvm-macos-sdk-root llvm-match-version-list
    llvm-match-versions llvm-normalize-version-id llvm-parse-version
    llvm-parse-version-expression llvm-pick llvm-print-config-env-exports
    llvm-print-env-exports llvm-print-remote-release-candidates llvm-remove
    llvm-resolve-remote-release llvm-run-runtime-script llvm-status llvm-test-expressions
    llvm-try-command-help llvm-use llvm-validate-toolchain-path llvm-verbose-off
    llvm-verbose-on llvm-version-compare llvm-version-exists llvm-version-matches-range
    llvm-version-sort llvm-vscode-activate llvmup log_config log_debug log_error
    log_expression_debug log_expression_result log_expression_verbose log_info log_progress
    log_success log_tip log_warn
"

# Sourcing the loader again (for example after an upgrade) must give the new core a chance to load.
unset _LLVMUP_CORE_LOADED

# Loads the implementation. Called by the stubs; $1 names the function that was requested.
_llvmup_load_core() {
    if [ "${_LLVMUP_CORE_LOADED:-0}" = 1 ]; then
        # The core is loaded, so a stub can only be reached when the core lacks the function.
        echo "llvmup: internal error: '$1' is not defined by llvmup-core.sh" >&2
        return 1
    fi
    if [ ! -r "${_LLVMUP_FUNCTIONS_DIR:-}/llvmup-core.sh" ]; then
        echo "llvmup: cannot read llvmup-core.sh next to llvm-functions.sh (${_LLVMUP_FUNCTIONS_DIR:-unknown directory})." >&2
        echo "Reinstall LLVMUP, or run 'llvmup doctor' to check the installation." >&2
        return 1
    fi
    _LLVMUP_CORE_LOADED=1
    # shellcheck source=llvmup-core.sh
    . "$_LLVMUP_FUNCTIONS_DIR/llvmup-core.sh" || { unset _LLVMUP_CORE_LOADED; return 1; }
}

# One stub per public function: load the core, then call the real implementation it just defined.
if [ -n "${ZSH_VERSION:-}" ]; then _llvmup_names=(${=_LLVMUP_API}); else _llvmup_names=($_LLVMUP_API); fi
for _llvmup_fn in "${_llvmup_names[@]}"; do
    eval "${_llvmup_fn}() { _llvmup_load_core ${_llvmup_fn} && ${_llvmup_fn} \"\$@\"; }"
done
unset _llvmup_fn _llvmup_names

# -----------------------------------------------------------------------------
# Directory auto-activation hook. Bash has no directory-change event, so the hook runs before
# every prompt but returns at once unless the directory changed since the last time. On a change
# it looks for .llvmup-config with shell built-ins only (no subshell, no dirname) and loads the
# core only inside a project, or to undo an earlier auto-activation. Editing .llvmup-config in
# the current directory is therefore picked up on the next directory change, or explicitly with
# 'llvmup use --auto'.
# -----------------------------------------------------------------------------
__llvmup_autoactivate_hook() {
    if [ -n "${LLVMUP_DISABLE_AUTOACTIVATE:-}" ] || [ -n "${LLVM_TEST_MODE:-}" ]; then
        return 0
    fi
    if [ "${_LLVMUP_HOOK_PWD:-}" = "$PWD" ]; then
        return 0
    fi
    _LLVMUP_HOOK_PWD="$PWD"
    if [ "${_LLVMUP_AUTOACTIVATE_ACTIVE:-0}" != 1 ]; then
        local dir="$PWD"
        while :; do
            [ -f "$dir/.llvmup-config" ] && break
            if [ "$dir" = / ]; then return 0; fi
            dir="${dir%/*}"
            [ -n "$dir" ] || dir=/
        done
    fi
    llvm-autoactivate 2>/dev/null || true
}

llvm-register-autoactivate-hooks() {
    if [ -n "${LLVMUP_DISABLE_AUTOACTIVATE:-}" ] || [ -n "${LLVM_TEST_MODE:-}" ]; then
        return 0
    fi

    if [ -n "${BASH_VERSION:-}" ]; then
        case ";${PROMPT_COMMAND:-};" in
            *";__llvmup_autoactivate_hook;"*)
                ;;
            "")
                PROMPT_COMMAND="__llvmup_autoactivate_hook"
                ;;
            *)
                PROMPT_COMMAND="__llvmup_autoactivate_hook;$PROMPT_COMMAND"
                ;;
        esac
        export PROMPT_COMMAND
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        autoload -Uz add-zsh-hook 2>/dev/null || true
        if typeset -f add-zsh-hook >/dev/null 2>&1; then
            add-zsh-hook chpwd __llvmup_autoactivate_hook 2>/dev/null || true
        fi
    fi
}

if [ -z "${LLVMUP_DISABLE_AUTOACTIVATE:-}" ] && [ -z "${LLVM_TEST_MODE:-}" ]; then
    llvm-register-autoactivate-hooks
    __llvmup_autoactivate_hook
fi

if [ "${LLVMUP_FUNCTIONS_EAGER:-0}" = 1 ]; then
    _llvmup_load_core eager || true
fi
