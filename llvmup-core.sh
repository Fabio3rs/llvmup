#!/bin/bash
# llvmup-core.sh: implementation of the llvmup shell functions.
# Do not source this file from a profile: llvm-functions.sh (the loader) sources it on first use.
#
# Usage after sourcing:
#   llvm-activate <version>    - Activate an LLVM version
#   llvm-deactivate           - Deactivate current LLVM version
#   llvm-vscode-activate <version> - Activate LLVM for VSCode

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

QUIET_MODE=${QUIET_MODE:-0}
QUIET_SUCCESS=${QUIET_SUCCESS:-0}
EXPRESSION_VERBOSE=${EXPRESSION_VERBOSE:-0}
EXPRESSION_DEBUG=${EXPRESSION_DEBUG:-0}

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Colors are only a visual aid: off for NO_COLOR, dumb terminals and non-interactive output.
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = dumb ] || { [ ! -t 1 ] && [ ! -t 2 ]; }; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# Log error messages (always shown)
log_error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

# Log warning messages (always shown, including in quiet mode)
log_warn() {
    echo -e "${YELLOW}Warning: $*${NC}" >&2
}

# Log success messages (always shown)
log_success() {
    if [ "$QUIET_SUCCESS" -eq 1 ] || [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo -e "${GREEN}$*${NC}"
}

# Log info messages (only in verbose mode or test mode)
log_info() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo -e "${BLUE}Info: $*${NC}"
    fi
}

# Log debug messages (only in verbose mode or test mode)
log_debug() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo -e "${CYAN}Debug: $*${NC}"
    fi
}

# Log progress messages (only in verbose mode or test mode)
log_progress() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo -e "${CYAN}Progress: $*${NC}"
    fi
}

# Log configuration messages (only in verbose mode or test mode)
log_config() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo -e "${BLUE}Config: $*${NC}"
    fi
}

# Log tips and suggestions (only in verbose mode or test mode)
log_tip() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo -e "${BLUE}Tip: $*${NC}"
    fi
}

# Log expression parsing details (controlled by EXPRESSION_VERBOSE)
log_expression_verbose() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ "$EXPRESSION_VERBOSE" -eq 1 ] || [ -n "$LLVM_VERBOSE" ]; then
        echo -e "${CYAN}Expression: $*${NC}" >&2
    fi
}

# Log expression debug information (controlled by EXPRESSION_DEBUG)
log_expression_debug() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ "$EXPRESSION_DEBUG" -eq 1 ] || [ -n "$LLVM_VERBOSE" ]; then
        echo -e "${CYAN}Debug: $*${NC}" >&2
    fi
}

# Log expression results (always visible unless QUIET_MODE)
log_expression_result() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo -e "${GREEN}$*${NC}"
}

# =============================================================================
# VERBOSE MODE CONTROL
# =============================================================================

# Enable verbose logging for this session
llvm-verbose-on() {
    export LLVM_VERBOSE=1
    log_success "Verbose mode enabled for LLVM functions"
    log_info "All informational messages will now be shown"
    log_tip "Use 'llvm-verbose-off' to disable verbose mode"
}

# Disable verbose logging for this session
llvm-verbose-off() {
    unset LLVM_VERBOSE
    echo -e "${GREEN}Verbose mode disabled for LLVM functions${NC}"
}

# Enable expression verbose logging
llvm-expression-verbose-on() {
    export EXPRESSION_VERBOSE=1
    log_success "Expression verbose mode enabled"
    log_info "Expression processing details will be shown"
    log_tip "Use 'llvm-expression-verbose-off' to disable"
}

# Disable expression verbose logging
llvm-expression-verbose-off() {
    export EXPRESSION_VERBOSE=0
    log_success "Expression verbose mode disabled"
}

# Enable expression debug logging
llvm-expression-debug-on() {
    export EXPRESSION_DEBUG=1
    log_success "Expression debug mode enabled"
    log_info "Detailed expression parsing information will be shown"
    log_tip "Use 'llvm-expression-debug-off' to disable"
}

# Disable expression debug logging
llvm-expression-debug-off() {
    export EXPRESSION_DEBUG=0
    log_success "Expression debug mode disabled"
}

# Resolve the directory that contains the installed LLVMUP executables.
llvm-get-install-dir() {
    if [ -n "$LLVMUP_INSTALL_DIR" ]; then
        echo "$LLVMUP_INSTALL_DIR"
        return 0
    fi

    if [ -n "${ZSH_VERSION:-}" ] && [ -n "${_LLVMUP_FUNCTIONS_DIR:-}" ]; then
        printf '%s\n' "$_LLVMUP_FUNCTIONS_DIR"
        return 0
    fi

    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        local source_dir
        source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -n "$source_dir" ]; then
            echo "$source_dir"
            return 0
        fi
    fi

    echo "$HOME/.local/bin"
}

# Find a runtime helper script either in the install dir or in the legacy default path.
llvm-find-runtime-script() {
    local script_name="$1"
    local install_dir
    install_dir="$(llvm-get-install-dir)"

    if [ -f "$install_dir/$script_name" ]; then
        echo "$install_dir/$script_name"
        return 0
    fi

    if [ -f "$HOME/.local/bin/$script_name" ]; then
        echo "$HOME/.local/bin/$script_name"
        return 0
    fi

    return 1
}

llvm-run-runtime-script() {
    local script_name="$1"
    shift

    local script_path
    script_path="$(llvm-find-runtime-script "$script_name")" || script_path=""

    if [ ! -f "$script_path" ]; then
        log_error "$script_name script not found"
        log_tip "Expected install directory: $(llvm-get-install-dir)"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi

    "$script_path" "$@"
}

llvm-get-home-dir() {
    if [ -n "$LLVM_HOME" ]; then
        echo "$LLVM_HOME"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        echo "$LLVM_CUSTOM_HOME"
    else
        echo "$HOME/.llvm"
    fi
}

llvm-get-default-link() {
    echo "$(llvm-get-home-dir)/default"
}

llvm-format-bytes() {
    local bytes="$1"
    local units=("B" "KiB" "MiB" "GiB" "TiB" "PiB")
    local unit_index=0
    local whole="$bytes"
    local remainder=0

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "$bytes"
        return 0
    fi

    while [ "$whole" -ge 1024 ] && [ "$unit_index" -lt $((${#units[@]} - 1)) ]; do
        remainder=$((whole % 1024))
        whole=$((whole / 1024))
        unit_index=$((unit_index + 1))
    done

    if [ "$unit_index" -eq 0 ]; then
        echo "${whole} ${units[$unit_index]}"
        return 0
    fi

    local decimal=$(( (remainder * 10 + 512) / 1024 ))
    if [ "$decimal" -eq 10 ]; then
        whole=$((whole + 1))
        decimal=0
    fi

    echo "${whole}.${decimal} ${units[$unit_index]}"
}

llvm-get-directory-bytes() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        echo 0
        return 0
    fi

    du -sb "$dir" 2>/dev/null | cut -f1
}

llvm-default-set() {
    local version="$1"
    local toolchains_dir
    local default_link
    local version_path

    toolchains_dir="$(llvm-get-toolchains-dir)"
    default_link="$(llvm-get-default-link)"
    version_path="$toolchains_dir/$version"

    if [ ! -d "$version_path" ]; then
        log_error "Version $version is not installed"
        log_info "Use 'llvm-list' to see installed versions"
        return 1
    fi

    mkdir -p "$(dirname "$default_link")"

    if [ -L "$default_link" ] || [ -e "$default_link" ]; then
        rm -f "$default_link"
    fi

    ln -s "$version_path" "$default_link"
    log_success "Default LLVM version set to: $version"
    log_info "Default link: $default_link"
}

llvm-default-show() {
    local default_link
    default_link="$(llvm-get-default-link)"

    if [ -L "$default_link" ] && [ -e "$default_link" ]; then
        local target
        local version
        target=$(readlink "$default_link")
        version=$(basename "$target")
        echo "Current default LLVM version: $version"

        if [ -x "$default_link/bin/clang" ]; then
            local clang_version
            if clang_version=$("$default_link/bin/clang" --version 2>/dev/null | head -1); then
                [ -n "$clang_version" ] && echo "Clang version: $clang_version"
            fi
        fi
    else
        echo "No default LLVM version is set"
        echo "Use 'llvmup default set <version>' to set one"
    fi

    return 0
}

llvm-default-unset() {
    local default_link
    default_link="$(llvm-get-default-link)"

    if [ -L "$default_link" ]; then
        rm -f -- "$default_link"
        log_success "Default LLVM version cleared"
        return 0
    fi

    if [ -e "$default_link" ]; then
        log_error "Refusing to remove non-symlink default path: $default_link"
        return 1
    fi

    echo "No default LLVM version is set"
    return 0
}

llvm-get-default-version() {
    local default_link
    local target

    default_link="$(llvm-get-default-link)"
    [ -L "$default_link" ] || return 1
    target="$(readlink "$default_link" 2>/dev/null)" || return 1
    [ -n "$target" ] || return 1
    basename "$target"
}

llvm-remove() {
    local version=""
    local force=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                force=1
                ;;
            -h|--help)
                cat <<EOF
Usage: llvmup remove <installed-id> [--force]

Remove one installed LLVM toolchain. Source checkouts and build directories are preserved.

Options:
  --force   Allow removal of the active or default toolchain
EOF
                return 0
                ;;
            -*)
                log_error "Unknown remove option: $1"
                return 1
                ;;
            *)
                if [ -n "$version" ]; then
                    log_error "Only one installed LLVM identifier can be removed"
                    return 1
                fi
                version="$1"
                ;;
        esac
        shift
    done

    if [ -z "$version" ]; then
        log_error "Missing installed LLVM identifier for 'remove'"
        return 1
    fi

    case "$version" in
        .|..|*/*|*\\*)
            log_error "Invalid installed LLVM identifier: $version"
            return 1
            ;;
    esac

    local toolchains_dir
    local target
    local active_version
    local default_version=""
    toolchains_dir="$(llvm-get-toolchains-dir)"
    target="$toolchains_dir/$version"
    active_version="${_ACTIVE_LLVM:-${LLVMUP_ACTIVE_VERSION:-}}"
    default_version="$(llvm-get-default-version 2>/dev/null)" || default_version=""

    if [ ! -d "$target" ] && [ ! -L "$target" ]; then
        log_error "LLVM version '$version' is not installed in $toolchains_dir"
        echo "To see installed toolchains: llvmup list" >&2
        return 1
    fi

    if [ "$active_version" = "$version" ] && [ "$force" -ne 1 ]; then
        log_error "Cannot remove active LLVM version '$version' without --force"
        echo "It is active in this terminal. Run 'llvmup deactivate' first, or pass --force to remove it anyway." >&2
        return 1
    fi

    if [ "$default_version" = "$version" ] && [ "$force" -ne 1 ]; then
        log_error "Cannot remove default LLVM version '$version' without --force"
        echo "It is the user default. Pick another with 'llvmup default <toolchain>', or pass --force to remove it and clear the default." >&2
        return 1
    fi

    if [ "$active_version" = "$version" ]; then
        if [ "${_ACTIVE_LLVM:-}" = "$version" ] && command -v llvm-deactivate >/dev/null 2>&1; then
            llvm-deactivate >/dev/null || return $?
        else
            unset LLVMUP_ACTIVE_VERSION LLVMUP_ACTIVE_PATH
            log_warn "PATH may still reference the removed toolchain; restart or repair the current shell"
        fi
        if [ "${LLVMUP_EXECUTABLE_MODE:-0}" = "1" ]; then
            log_warn "The parent shell may still reference the removed toolchain; deactivate or restart it"
        fi
    fi

    if [ "$default_version" = "$version" ]; then
        llvm-default-unset || return $?
    fi

    rm -rf -- "$target"
    log_success "Removed $version."
    [ "$default_version" != "$version" ] || log_success "The user default was cleared."
    log_info "Preserved source checkouts under $(llvm-get-sources-dir)"
}

llvm-disk-usage() {
    local human_readable=0
    local toolchains_dir
    local total_bytes=0
    local found=0
    local arg

    for arg in "$@"; do
        case "$arg" in
            -h|--human-readable)
                human_readable=1
                ;;
            --help)
                cat <<EOF
Usage: llvm-disk-usage [OPTIONS]

Options:
  -h, --human-readable   Show sizes using binary units
      --help             Show this help message
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for llvm-disk-usage: $arg"
                return 1
                ;;
        esac
    done

    toolchains_dir="$(llvm-get-toolchains-dir)"
    if [ ! -d "$toolchains_dir" ]; then
        echo "No LLVM toolchains found at $toolchains_dir"
        return 0
    fi

    local dir
    for dir in "$toolchains_dir"/*; do
        [ -d "$dir" ] || continue
        found=1
        local version
        local bytes
        local size

        version="$(basename "$dir")"
        bytes="$(llvm-get-directory-bytes "$dir")"
        total_bytes=$((total_bytes + bytes))

        if [ "$human_readable" -eq 1 ]; then
            size="$(llvm-format-bytes "$bytes")"
            printf '%s\t%s\n' "$size" "$version"
        else
            printf '%s\t%s\n' "$bytes" "$version"
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "No LLVM toolchains found at $toolchains_dir"
        return 0
    fi

    if [ "$human_readable" -eq 1 ]; then
        printf 'total\t%s\t%s\n' "$(llvm-format-bytes "$total_bytes")" "$toolchains_dir"
    else
        printf 'total\t%s\t%s\n' "$total_bytes" "$toolchains_dir"
    fi
}

llvm-find-config-root() {
    local dir="${1:-$PWD}"

    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.llvmup-config" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    if [ -f "/.llvmup-config" ]; then
        echo "/"
        return 0
    fi

    return 1
}

llvm-load-config-from-root() {
    local config_root="$1"
    local current_dir="$PWD"

    if [ -z "$config_root" ] || [ ! -f "$config_root/.llvmup-config" ]; then
        log_error "No .llvmup-config file found"
        return 1
    fi

    cd "$config_root" || return 1
    llvm-config-load
    local load_result=$?
    cd "$current_dir" || return 1
    return $load_result
}

# ---------------------------------------------------------------------------------------------
# Provider engine integration (libexec/sh/llvmup-engine.sh) and session selection ('use').
# ---------------------------------------------------------------------------------------------

llvm-engine-path() {
    local p
    p="$(llvm-get-install-dir)/libexec/sh/llvmup-engine.sh"
    [ -f "$p" ] || p="$HOME/.local/bin/libexec/sh/llvmup-engine.sh"
    [ -f "$p" ] || return 1
    printf '%s\n' "$p"
}

llvm-load-session-helpers() {
    command -v _llvmup_session_save >/dev/null 2>&1 && return 0
    local helper
    helper="$(llvm-get-install-dir)/libexec/sh/llvmup-session.sh"
    [ -f "$helper" ] || helper="$HOME/.local/bin/libexec/sh/llvmup-session.sh"
    [ -f "$helper" ] || return 1
    # shellcheck source=/dev/null
    . "$helper"
}

# True when 'env' arguments need the provider engine (see the executable's env_needs_engine).
llvm-env-needs-engine() {
    local prev="" a home tc
    home="${LLVM_HOME:-$HOME/.llvm}"
    tc="${LLVM_TOOLCHAINS_DIR:-$home/toolchains}"
    for a in "$@"; do
        if [ "$prev" = --format ] && { [ "$a" = json ] || [ "$a" = cmd ]; }; then return 0; fi
        case "$a" in
            --target|--compiler|*@*) return 0 ;;
            -*|"") ;;
            *)
                if [ "$prev" != --format ]; then
                    [ ! -f "$tc/$a/.llvmup-toolchain.json" ] || return 0
                    if [ -f "$home/aliases.json" ] && grep -q "\"$a\"" "$home/aliases.json" 2>/dev/null; then return 0; fi
                fi
                ;;
        esac
        prev="$a"
    done
    return 1
}

# llvm-pick: numbered selector over local installations and aliases. It never queries remote
# releases and fails immediately (exit 2) without a terminal instead of waiting for input.
llvm-pick() {
    local engine
    engine="$(llvm-engine-path)" || { log_error "llvmup provider engine not found"; return 1; }
    command -v jq >/dev/null 2>&1 || { log_error "llvmup pick requires jq"; return 1; }
    local all
    all="$(bash "$engine" list --json 2>/dev/null)" || all='[]'
    local rows
    rows="$(jq -r --arg active "${_ACTIVE_LLVM:-}" --arg def "$(basename "$(readlink "${LLVM_HOME:-$HOME/.llvm}/default" 2>/dev/null)" 2>/dev/null)" '
        (if type == "array" then . else (.toolchains // .installed // []) end)
        | map(select((.missing_on_disk // false) | not))
        | .[] | [.install_name, (.provider // "official"), (.llvm_version // "?"),
                 ((.variant.crt // "") | select(. != "unknown" and . != "system") // ""),
                 (.default_target // ""),
                 ([if .install_name == $active then "active" else empty end, if .install_name == $def then "default" else empty end] | join(","))]
        | @tsv' <<<"$all")"
    [ -n "$rows" ] || { log_error "No installed toolchains found."; return 1; }
    local aliases="" af="${LLVM_HOME:-$HOME/.llvm}/aliases.json"
    [ ! -f "$af" ] || aliases="$(jq -r '.aliases // {} | to_entries[] | "\(.value.target_name)\t\(.key)"' "$af" 2>/dev/null)"
    local i=0 names=() name prov ver crt tgt tags al
    while IFS=$'\t' read -r name prov ver crt tgt tags; do
        i=$((i + 1)); names+=("$name")
        al="$(printf '%s\n' "$aliases" | awk -F'\t' -v n="$name" '$1 == n { printf "%s%s", sep, $2; sep = "," }')"
        printf '  %2d) %-46s %-10s LLVM %-8s %s%s%s%s\n' "$i" "$name" "$prov" "$ver" "${crt:+crt=$crt }" "${tgt:+target=$tgt }" "${al:+aliases=$al }" "${tags:+[$tags]}"
    done <<<"$rows"
    if [ ! -t 0 ]; then
        log_error "llvmup pick needs an interactive terminal; use 'llvmup use <toolchain>' in scripts."
        return 2
    fi
    local choice
    read -r -p "Select toolchain (1-$i, q to cancel): " choice || return 1
    case "$choice" in q|Q|"") return 1 ;; esac
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$i" ]; then
        log_error "Invalid selection '$choice'"; return 1
    fi
    llvm-use "${names[$((choice - 1))]}"
}

# llvm-use <selector|-|--auto> [--compiler C] [--target T] [--crt C] [--install]
# Applies a toolchain to the current shell from its manifest. A manual selection overrides
# directory auto-activation until 'llvm-use --auto' or 'llvm-deactivate'.
llvm-use() {
    local engine
    engine="$(llvm-engine-path)" || { log_error "llvmup provider engine not found"; return 1; }
    llvm-load-session-helpers || { log_error "llvmup session helpers not found"; return 1; }

    local selector="" install=0 auto=0 args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --compiler|--target|--crt) [ $# -ge 2 ] || { log_error "$1 requires a value"; return 1; }; args+=("$1" "$2"); shift 2 ;;
            --install) install=1; shift ;;
            --auto) auto=1; shift ;;
            -) selector="-"; shift ;;
            -*) log_error "Unknown use option: $1"; return 1 ;;
            *) selector="$1"; shift ;;
        esac
    done

    if [ "$auto" -eq 1 ]; then
        unset LLVMUP_SESSION_OVERRIDE
        llvm-deactivate >/dev/null 2>&1 || true
        # An explicit request: re-evaluate even though the directory did not change.
        unset _LLVMUP_HOOK_PWD
        if command -v __llvmup_autoactivate_hook >/dev/null 2>&1; then __llvmup_autoactivate_hook; fi
        return 0
    fi

    if [ "$selector" = "-" ]; then
        [ -n "${LLVMUP_PREVIOUS_SESSION:-}" ] || { log_error "No previous toolchain selection recorded in this session."; return 1; }
        local prev_name prev_compiler prev_target
        IFS='|' read -r prev_name prev_compiler prev_target <<<"$LLVMUP_PREVIOUS_SESSION"
        selector="$prev_name"
        [ -z "$prev_compiler" ] || args+=(--compiler "$prev_compiler")
        [ -z "$prev_target" ] || args+=(--target "$prev_target")
    fi
    [ -n "$selector" ] || { log_error "Missing toolchain selector for 'use'"; return 1; }

    # Keep the engine's diagnostics: only a genuinely missing installation may trigger --install.
    local exports errfile err
    errfile="$(mktemp "${TMPDIR:-/tmp}/llvmup-use.XXXXXX")" || errfile=/dev/null
    if ! exports="$(bash "$engine" env "$selector" "${args[@]}" --format shell 2>"$errfile")"; then
        err="$(cat "$errfile" 2>/dev/null)"
        [ "$errfile" = /dev/null ] || rm -f "$errfile"
        case "$err" in
            *"No installed toolchain matches"*)
                if [ "$install" -eq 1 ]; then
                    local crt_arg=() i
                    for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[$i]}" = --crt ] && crt_arg=(--crt "${args[$((i + 1))]}"); done
                    echo "No installed toolchain matches '$selector'; installing it first." >&2
                    bash "$engine" install "$selector" "${crt_arg[@]}" >/dev/null || return 1
                    exports="$(bash "$engine" env "$selector" "${args[@]}" --format shell)" || return 1
                else
                    printf '%s\n' "$err" >&2
                    printf '\nTo install and activate it in one step:\n  llvmup use %s --install\n' "$selector" >&2
                    return 1
                fi
                ;;
            *)
                [ -n "$err" ] || err="Error: Could not prepare the environment for '$selector'."
                printf '%s\n' "$err" >&2
                return 1
                ;;
        esac
    else
        [ "$errfile" = /dev/null ] || rm -f "$errfile"
    fi

    local previous=""
    [ -z "${_ACTIVE_LLVM:-}" ] || previous="${_ACTIVE_LLVM}|${LLVMUP_ACTIVE_COMPILER:-}|${LLVMUP_ACTIVE_TARGET:-}"

    # Restore the original environment first so nothing from the previous toolchain leaks.
    if [ "${_LLVMUP_ENV_SAVED:-0}" = 1 ]; then
        _llvmup_session_restore
    elif [ -n "${_ACTIVE_LLVM:-}" ]; then
        llvm-deactivate >/dev/null 2>&1 || true
    fi
    _llvmup_session_save
    # The exports are generated by llvmup-engine.sh with printf %q quoting; no user input is evaluated.
    eval "$exports"
    export LLVMUP_SESSION_OVERRIDE="$_ACTIVE_LLVM"
    [ -z "$previous" ] || export LLVMUP_PREVIOUS_SESSION="$previous"
    log_success "Using $_ACTIVE_LLVM (${LLVMUP_ACTIVE_PROVIDER:-official}, compiler ${LLVMUP_ACTIVE_COMPILER:-clang}${LLVMUP_ACTIVE_TARGET:+, target $LLVMUP_ACTIVE_TARGET})"
}

llvmup() {
    local runtime_script
    runtime_script="$(llvm-find-runtime-script llvmup)" || runtime_script=""

    local help_rc=0
    llvm-try-command-help "$@" || help_rc=$?
    [ "$help_rc" -eq 1 ] || return "$help_rc"

    case "${1:-}" in
        doctor)
            shift
            local doctor_script
            doctor_script="$(llvm-find-runtime-script llvmup-doctor.sh)" || return 1
            local doctor_completion=0
            if command -v _llvmup_completions >/dev/null 2>&1 || command -v _llvmup >/dev/null 2>&1; then
                doctor_completion=1
            fi
            LLVMUP_DOCTOR_SHELL_FUNCTION=1 LLVMUP_DOCTOR_COMPLETION="$doctor_completion" \
                LLVMUP_DOCTOR_CLANG="$(command -v clang 2>/dev/null)" \
                LLVMUP_DOCTOR_CLANGXX="$(command -v clang++ 2>/dev/null)" \
                bash "$doctor_script" "$@"
            return $?
            ;;
        activate)
            shift
            llvm-activate "$@"
            return $?
            ;;
        deactivate)
            shift
            unset LLVMUP_SESSION_OVERRIDE LLVMUP_PREVIOUS_SESSION
            if [ "${_LLVMUP_ENV_SAVED:-0}" = 1 ] && llvm-load-session-helpers; then
                local _deactivated_name="${_ACTIVE_LLVM:-}"
                _llvmup_session_restore
                unset _LLVMUP_AUTOACTIVATE_ACTIVE _LLVMUP_AUTOACTIVATE_ROOT
                log_success "Deactivated ${_deactivated_name:-the active toolchain}. Previous shell environment restored."
                return 0
            fi
            llvm-deactivate "$@"
            return $?
            ;;
        use)
            shift
            llvm-use "$@"
            return $?
            ;;
        pick)
            shift
            llvm-pick "$@"
            return $?
            ;;
        install)
            # 'install ... --use' installs through the CLI, then selects the result in this shell.
            case " $* " in
                *" --use "*)
                    shift
                    local a prev="" sel="" name="" inst=() use_args=()
                    for a in "$@"; do
                        case "$prev" in
                            --name|-n) name="$a" ;;
                            --compiler|--target|--crt) use_args+=("$prev" "$a") ;;
                        esac
                        if [ "$a" != --use ]; then inst+=("$a"); fi
                        case "$a" in
                            -*) ;;
                            *) case "$prev" in --name|-n|--compiler|--target|--crt|--release|--provider|--profile|-p|--component|--verify|--extractor|--threads|--cmake-flags|-c) ;; *) [ -n "$sel" ] || sel="$a" ;; esac ;;
                        esac
                        prev="$a"
                    done
                    [ -n "$runtime_script" ] || { log_error "llvmup runtime script not found"; return 1; }
                    LLVMUP_SUPPRESS_USE_HINT=1 "$runtime_script" install "${inst[@]}" || return $?
                    # Installation succeeded; activation is a separate step that can still fail.
                    if ! llvm-use "${name:-${sel:-latest}}" "${use_args[@]}"; then
                        log_warn "The toolchain was installed, but it was not activated in this terminal."
                        return 1
                    fi
                    return 0
                    ;;
            esac
            ;;
        vscode-activate)
            shift
            llvm-vscode-activate "$@"
            return $?
            ;;
        status)
            shift
            case " $* " in
                *" --explain "*|*" --json "*) [ -z "$runtime_script" ] || { "$runtime_script" status "$@"; return $?; } ;;
            esac
            llvm-status "$@"
            return $?
            ;;
        list)
            shift
            case " $* " in
                *" --providers "*|*" --provider "*) [ -z "$runtime_script" ] || { "$runtime_script" list "$@"; return $?; } ;;
            esac
            llvm-list "$@"
            return $?
            ;;
        remove)
            shift
            llvm-remove "$@"
            return $?
            ;;
        disk-usage)
            shift
            llvm-disk-usage "$@"
            return $?
            ;;
        help)
            shift
            llvm-help "$@"
            return $?
            ;;
        env)
            shift
            # Provider toolchains, aliases, JSON/cmd output and target/compiler selection use the engine.
            if [ -n "$runtime_script" ] && llvm-env-needs-engine "$@"; then
                "$runtime_script" env "$@"
                return $?
            fi
            case "${1:-}" in
                --config)
                    llvm-print-config-env-exports shell
                    ;;
                --format)
                    local env_format="${2:-}"
                    if [ "$env_format" != "shell" ] && [ "$env_format" != "github" ]; then
                        log_error "Unsupported env format: $env_format"
                        return 1
                    fi
                    shift 2
                    if [ $# -eq 0 ]; then
                        log_error "Missing version argument for 'env'"
                        return 1
                    fi
                    if [ "$1" = "--config" ]; then
                        llvm-print-config-env-exports "$env_format"
                    else
                        llvm-print-env-exports "$1" "$env_format"
                    fi
                    ;;
                "")
                    log_error "Missing version argument for 'env'"
                    return 1
                    ;;
                *)
                    llvm-print-env-exports "$1"
                    ;;
            esac
            return $?
            ;;
        config)
            local config_subcommand="${2:-}"
            shift
            [ $# -gt 0 ] && shift

            case "$config_subcommand" in
                init)
                    llvm-config-init "$@"
                    ;;
                load)
                    llvm-config-load "$@"
                    ;;
                apply)
                    local config_root
                    config_root="$(llvm-find-config-root)" || config_root=""
                    llvm-load-config-from-root "$config_root" >/dev/null && llvm-config-apply "$@"
                    ;;
                activate)
                    local config_root
                    config_root="$(llvm-find-config-root)" || config_root=""
                    llvm-load-config-from-root "$config_root" >/dev/null && llvm-config-activate "$@"
                    ;;
                *)
                    if [ -n "$runtime_script" ]; then
                        "$runtime_script" config "$config_subcommand" "$@"
                    else
                        log_error "llvmup runtime script not found"
                        return 1
                    fi
                    ;;
            esac
            return $?
            ;;
        default)
            local default_subcommand="${2:-show}"
            case "$default_subcommand" in
                set)
                    if [ $# -lt 3 ]; then
                        log_error "Missing version argument for 'default set'"
                        return 1
                    fi
                    llvm-default-set "$3"
                    ;;
                show)
                    llvm-default-show
                    ;;
                unset)
                    llvm-default-unset
                    ;;
                -*)
                    log_error "Unknown default subcommand: $default_subcommand"
                    log_info "Available subcommands: set, show, unset, or <toolchain>"
                    return 1
                    ;;
                *)
                    # 'llvmup default <toolchain>' is short for 'default set'; selectors such as
                    # winlibs@23 or an alias resolve to the exact installation name.
                    local engine target
                    if engine="$(llvm-engine-path)" && target="$(bash "$engine" where "$default_subcommand" 2>/dev/null)"; then
                        llvm-default-set "$(basename "$target")"
                    else
                        llvm-default-set "$default_subcommand"
                    fi
                    ;;
            esac
            return $?
            ;;
    esac

    if [ -n "$runtime_script" ]; then
        "$runtime_script" "$@"
        return $?
    fi

    log_error "llvmup runtime script not found"
    log_tip "Expected install directory: $(llvm-get-install-dir)"
    return 1
}

# Function to activate an LLVM version
llvm-activate() {
    if [ $# -eq 0 ]; then
        cat <<'EOF'
Usage: llvm-activate <version>

Select an installed toolchain in this terminal only. 'llvmup use <toolchain>' is the
current equivalent and also supports --compiler and --target.

Examples:
  llvm-activate 18.1.8
  llvm-activate 19.1.0

What it changes in this shell: PATH, CC, CXX, LD and the prompt.
To restore the previous environment: llvm-deactivate
To see the current selection: llvm-status
EOF
        echo ""
        echo "Installed versions:"
        llvm-list
        echo ""
        log_tip "Use TAB completion to auto-complete version names"
        return 1
    fi

    local version="$1"
    local script_path
    script_path="$(llvm-find-runtime-script llvm-activate)" || script_path=""

    if [ -f "$script_path" ]; then
        log_progress "Activating LLVM version $version..."
        source "$script_path" "$version"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            if [ "${LLVMUP_AUTOACTIVATE_MODE:-0}" = "1" ]; then
                export _LLVMUP_AUTOACTIVATE_ACTIVE=1
                export _LLVMUP_AUTOACTIVATE_ROOT="${LLVMUP_AUTOACTIVATE_ROOT:-}"
            else
                unset _LLVMUP_AUTOACTIVATE_ACTIVE
                unset _LLVMUP_AUTOACTIVATE_ROOT
            fi
            log_success "LLVM $version successfully activated!"
            log_info "Available tools are now in PATH:"
            log_info "  • clang, clang++, ld.lld, lldb, clangd, etc."
            log_tip "Your shell prompt now shows the active LLVM version"
            log_tip "Use 'llvm-status' to see detailed information"
        else
            log_error "Failed to activate LLVM $version"
            log_tip "Check if the version is installed: llvm-list"
            return $exit_code
        fi
    else
        log_error "llvm-activate script not found"
        log_tip "Expected install directory: $(llvm-get-install-dir)"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi
}

# Function to deactivate the current LLVM version
llvm-deactivate() {
    local _deactivated_name="${_ACTIVE_LLVM:-}"
    if [ "${_LLVMUP_ENV_SAVED:-0}" = 1 ] && llvm-load-session-helpers; then
        _llvmup_session_restore
        unset LLVMUP_SESSION_OVERRIDE _LLVMUP_AUTOACTIVATE_ACTIVE _LLVMUP_AUTOACTIVATE_ROOT
        log_success "Deactivated ${_deactivated_name:-the active toolchain}. Previous shell environment restored."
        return 0
    fi
    local script_path
    script_path="$(llvm-find-runtime-script llvm-deactivate)" || script_path=""

    if [ -f "$script_path" ]; then
        log_progress "Deactivating LLVM environment..."
        source "$script_path"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            unset _LLVMUP_AUTOACTIVATE_ACTIVE
            unset _LLVMUP_AUTOACTIVATE_ROOT
            log_success "Deactivated ${_deactivated_name:-the active toolchain}. Previous shell environment restored."
        fi
        return $exit_code
    else
        log_error "llvm-deactivate script not found"
        log_tip "Expected install directory: $(llvm-get-install-dir)"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi
}

# Function to activate LLVM for VSCode
llvm-vscode-activate() {
    if [ $# -eq 0 ]; then
        cat <<'EOF'
Usage: llvm-vscode-activate <version>

Configure VS Code to use an installed toolchain. Run it from your project root.

Example:
  llvm-vscode-activate 18.1.8

It updates .vscode/settings.json in the current directory (clangd, CMake and
LLDB paths). No toolchain files are modified.
EOF
        echo ""
        echo "Installed versions:"
        llvm-list
        echo ""
        log_tip "Run this from your VSCode workspace root directory"
        log_tip "After running, reload VSCode window for changes to take effect"
        return 1
    fi

    local version="$1"
    local script_path
    script_path="$(llvm-find-runtime-script llvm-vscode-activate)" || script_path=""

    if [ -f "$script_path" ]; then
        log_progress "Configuring VSCode workspace for LLVM $version..."
        "$script_path" "$version"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log_success "VSCode workspace successfully configured!"
            log_tip "Please reload your VSCode window (Ctrl+Shift+P → 'Developer: Reload Window')"
        fi
        return $exit_code
    else
        log_error "llvm-vscode-activate script not found"
        log_tip "Expected install directory: $(llvm-get-install-dir)"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi
}

# Function to show current LLVM status
llvm-status() {
    local default_name=""
    local default_link
    default_link="$(llvm-get-default-link)"
    [ -L "$default_link" ] && default_name="$(basename "$(readlink "$default_link" 2>/dev/null)" 2>/dev/null)"
    if [ -n "${_ACTIVE_LLVM:-}" ]; then
        echo "Active toolchain: $_ACTIVE_LLVM"
        [ -z "${LLVMUP_ACTIVE_PROVIDER:-}" ] || echo "  Provider: $LLVMUP_ACTIVE_PROVIDER"
        [ -z "${LLVMUP_ACTIVE_COMPILER:-}" ] || echo "  Compiler: $LLVMUP_ACTIVE_COMPILER"
        [ -z "${LLVMUP_ACTIVE_TARGET:-}" ] || echo "  Target:   $LLVMUP_ACTIVE_TARGET"
        [ -z "${_ACTIVE_LLVM_PATH:-}" ] || echo "  Path:     $_ACTIVE_LLVM_PATH"
        echo
        if [ -n "${LLVMUP_SESSION_OVERRIDE:-}" ]; then
            echo "Selection: Manual session override"
        elif [ -n "${_LLVMUP_AUTOACTIVATE_ACTIVE:-}" ]; then
            echo "Selection: Project configuration${_LLVMUP_AUTOACTIVATE_ROOT:+ ($_LLVMUP_AUTOACTIVATE_ROOT)}"
        else
            echo "Selection: Activated in this terminal"
        fi
        [ -z "$default_name" ] || echo "Default:   $default_name"
        echo "Run 'llvmup deactivate' to restore this terminal's previous environment."
    else
        echo "No toolchain is active in this terminal."
        [ -z "$default_name" ] || echo "Default: $default_name"
        echo
        echo "To select one:  llvmup use <toolchain>"
        echo "To see choices: llvmup list"
    fi
}

# Function to list installed LLVM versions
llvm-list() {
    local remote=0
    local json=0
    local arg

    for arg in "$@"; do
        case "$arg" in
            --remote) remote=1 ;;
            --json) json=1 ;;
            -h|--help)
                cat <<EOF
Usage: llvmup list [--remote] [--json]

Options:
  --remote   List stable LLVM releases available remotely
  --json     Emit machine-readable JSON
EOF
                return 0
                ;;
            *)
                log_error "Unknown option for llvmup list: $arg"
                return 1
                ;;
        esac
    done

    if [ "$remote" -eq 1 ]; then
        local releases_json
        releases_json="$(llvm-get-remote-stable-releases)" || return $?
        if [ "$json" -eq 1 ]; then
            jq '{remote_versions: ([.[].tag_name]
                | sort_by(sub("^llvmorg-"; "") | split(".") | map(tonumber))
                | reverse)}' <<< "$releases_json"
        else
            jq -r '[.[].tag_name]
                | sort_by(sub("^llvmorg-"; "") | split(".") | map(tonumber))
                | reverse[]' <<< "$releases_json"
        fi
        return $?
    fi

    if [ "$json" -eq 1 ]; then
        llvm-get-versions-json
        return $?
    fi

    local toolchains_dir
    toolchains_dir="$(llvm-get-toolchains-dir)"

    local default_name="" default_link
    default_link="$(llvm-get-default-link)"
    [ -L "$default_link" ] && default_name="$(basename "$(readlink "$default_link" 2>/dev/null)" 2>/dev/null)"

    local dir name provider ver marker count=0 manifest
    for dir in "$toolchains_dir"/*; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        provider="official"; ver="${name#llvmorg-}"; ver="${ver#source-llvmorg-}"
        manifest="$dir/.llvmup-toolchain.json"
        if [ -f "$manifest" ] && command -v jq >/dev/null 2>&1; then
            provider="$(jq -r '.provider // "official"' "$manifest" 2>/dev/null)"
            ver="$(jq -r '.llvm_version // empty' "$manifest" 2>/dev/null)"
        fi
        marker=" "
        [ "$name" != "$default_name" ] || marker="+"
        [ -z "${_ACTIVE_LLVM:-}" ] || [ "$name" != "$_ACTIVE_LLVM" ] || marker="*"
        if [ "$count" -eq 0 ]; then printf '   %-28s %-11s %s\n' NAME PROVIDER LLVM; fi
        printf '%s  %-28s %-11s %s\n' "$marker" "$name" "$provider" "${ver:--}"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        echo "No toolchains installed."
        echo "Try 'llvmup install latest'."
        return 0
    fi
    echo
    echo "* active   + default"
    if [ "$count" -eq 1 ]; then echo "1 toolchain installed."; else echo "$count toolchains installed."; fi
}

# Enhanced completion function for llvm-activate and llvm-vscode-activate
_llvm_complete_versions() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ -d "$toolchains_dir" ]; then
        local versions=$(find "$toolchains_dir" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort)

        # Add context information for better UX
        if [ -z "$versions" ]; then
            # Show helpful message when no versions installed
            echo >&2
            echo -e "${BLUE}No LLVM versions installed yet. Use 'llvmup install' to install versions.${NC}" >&2
            return 0
        fi

        # Check for default and active versions to provide better context
        local default_version=""
        local active_version="$_ACTIVE_LLVM"

        local default_link
        default_link="$(llvm-get-default-link)"
        if [ -L "$default_link" ]; then
            default_version=$(basename "$(readlink "$default_link" 2>/dev/null)" 2>/dev/null)
        fi

        # Show status indicators in stderr (doesn't affect completion)
        if [ "$COMP_CWORD" -eq 1 ] && [ ${#COMP_WORDS[@]} -eq 2 ] && [ -z "$cur" ]; then
            echo >&2
            echo -e "${BLUE}Available versions:${NC}" >&2
            while IFS= read -r version; do
                local status=""
                if [ "$version" = "$default_version" ]; then
                    status="(default)"
                elif [ "$version" = "$active_version" ]; then
                    status="(active)"
                fi
                echo "   $version $status" >&2
            done <<< "$versions"
            echo >&2
        fi

        COMPREPLY=($(compgen -W "$versions" -- "$cur"))
    else
        echo >&2
        echo -e "${BLUE}LLVM toolchains directory not found. Install LLVM versions first.${NC}" >&2
    fi
}

# Register completion functions
if command -v complete &> /dev/null && declare -F _llvm_complete_versions &> /dev/null; then
    complete -F _llvm_complete_versions llvm-activate 2>/dev/null || true
    complete -F _llvm_complete_versions llvm-vscode-activate 2>/dev/null || true
fi

# Function to show comprehensive help for LLVM manager
# llvm-try-command-help <args...>: handles 'llvmup <command> --help' and 'llvmup help [command]'.
# Returns 0 when help was shown, 2 for an unknown help topic, 1 when the arguments are not a help request.
llvm-try-command-help() {
    local cmd="${1:-}" a
    case "$cmd" in
        help) shift; llvm-help "$@" || return 2; return 0 ;;
        --help|-h) llvm-help; return 0 ;;
        install|use|activate|run|list|status|config|sync|pin|default|alias|remove|update|env|deactivate|which|where|provides|resolve|doctor|toolchain|shell|pick|info|disk-usage|cmake-toolchain|vscode-activate) ;;
        *) return 1 ;;
    esac
    shift
    for a in "$@"; do
        case "$a" in
            --) return 1 ;;
            --help) llvm-help-command "$cmd"; return 0 ;;
            -h) [ "$cmd" = disk-usage ] || { llvm-help-command "$cmd"; return 0; } ;;
        esac
    done
    return 1
}

llvm-help() {
    case "${1:-}" in
        "") ;;
        *) llvm-help-command "$1" && return 0
           log_error "No help available for '$1'. Run 'llvmup help' for the list of commands."
           return 1 ;;
    esac
    cat <<'EOF'
LLVMUP - C/C++ Toolchain Manager
Your toolchains. Your terminal. Your environment.

Usage:
  llvmup <command> [options]
  llvmup +<toolchain> -- <command>
  llvmup help <command>

Getting started:
  install       Install a toolchain (official LLVM, WinLibs, LLVM-MinGW)
  use           Select a toolchain for this terminal
  list          List installed toolchains
  run           Run a command with a toolchain, without changing the shell
  status        Show the current selection

Toolchain management:
  update        Install a newer release of an installed toolchain
  remove        Remove an installed toolchain
  default       Choose the user default toolchain
  alias         Give toolchains stable names
  resolve       Show which release a selector would install
  toolchain     Link or unlink an external toolchain
  disk-usage    Show disk usage of installed toolchains

Projects:
  pin           Record the toolchain in .llvmup-config
  sync          Install what .llvmup-config or the lockfile asks for
  config        Manage .llvmup-config (init, load, apply, activate, lock)

Environment:
  deactivate    Restore this terminal's previous environment
  shell         Open a subshell with a toolchain active
  pick          Choose an installed toolchain from a list
  env           Print environment settings for scripts and CI

Integration:
  cmake-toolchain   Write a CMake toolchain file
  vscode-activate   Configure VS Code for a toolchain

Inspection:
  info  which  where  provides  doctor

Common flows:
  llvmup install latest --use
  llvmup install winlibs@23
  llvmup use winlibs@23 --compiler gcc
  llvmup run llvm-mingw@23 -- clang++ --version
  llvmup pin --current
  llvmup sync

Options:
  --version     Show the LLVMUP version
  -h, --help    Show this help, or help for a command

Historical commands such as 'activate' and the 'llvmup <version>' install shorthand still work.
More: https://github.com/Fabio3rs/llvmup
EOF
}

# llvm-help-command <command>: short, side-effect free help for one command (returns 1 if unknown).
llvm-help-command() {
    case "$1" in
        install) cat <<'EOF'
Install a toolchain.

Usage:
  llvmup install [<provider>@]<selector> [options]

Selectors:
  latest, 23, ~23.1, >=23.1.4, 23.*, winlibs@23, llvm-mingw@23, official@latest
  Quote selectors containing > < or *, for example: llvmup install '>=23.1'

Options:
  --use                  Select the toolchain in this terminal after installing (shell function)
  -n, --name <NAME>      Installation name (default: derived from the release)
  --provider <P>         official, winlibs or llvm-mingw
  --release <TAG>        Pin the upstream release
  --crt <ucrt|msvcrt>    C runtime (WinLibs and LLVM-MinGW)
  --verify <POLICY>      warn (default), strict or skip
  --extractor <E>        auto, tar, 7z, zip or python
  -p, --profile <P>      Component profile: minimal, compiler, full, custom
  -d, --default          Also make it the user default
  --force                Replace an existing installation with the same name
  --no-cache             Download again instead of reusing the cache
  -q, --quiet / -v, --verbose

Selective installs (official LLVM):
  --component <NAME>     Add an installation component (can be repeated)
  --strip                Strip Linux ELF executables

Source builds (official LLVM only):
  --from-source          Build LLVM from source instead of installing a prebuilt release
  -c, --cmake-flags "<FLAGS>"  Extra CMake flags (can be repeated)
  --disable-libc-wno-error   Disable LIBC_WNO_ERROR=ON flag
  --reconfigure          Force CMake to reconfigure (removes CMakeCache.txt)
  --list-only            List available source releases and exit

Examples:
  llvmup install latest --use
  llvmup install winlibs@23 --name win-dev
  llvmup install llvm-mingw@23 --crt ucrt

Effects: downloads and verifies an archive, then creates a new directory under the
toolchains folder. It never changes this terminal unless --use is given.
EOF
        ;;
        use|activate) cat <<'EOF'
Select a toolchain for this terminal.

Usage:
  llvmup use <selector|installation|alias> [--compiler clang|gcc] [--target <T>] [--crt <C>] [--install]
  llvmup use -        Return to the previous selection of this terminal
  llvmup use --auto   Drop the manual selection and follow .llvmup-config or the default

Options:
  --compiler <C>   Compiler to export as CC/CXX (only compilers the toolchain provides)
  --target <T>     Target triple (only targets the toolchain supports)
  --install        Install the toolchain first, only if no installation matches

Examples:
  llvmup use official@23
  llvmup use winlibs@23 --compiler gcc

Effects: changes PATH and related variables of the current terminal only. This works
through the 'llvmup' shell function; the standalone executable cannot do it. Use
'llvmup run <toolchain> -- <command>' for a one-off command instead.
EOF
        ;;
        run) cat <<'EOF'
Run a command with a toolchain, without changing the current shell.

Usage:
  llvmup run [<selector>] [--compiler C] [--target T] [--install] -- <command> [args...]
  llvmup +<selector> -- <command> [args...]
  llvmup run --locked -- <command>    Use the toolchain recorded in .llvmup-lock.json

Without a selector, the effective toolchain is used (session, project, then default).

Examples:
  llvmup run llvm-mingw@23 -- clang++ --version
  llvmup +winlibs@23 -- gcc --version

The command's own output and exit code are passed through unchanged.
EOF
        ;;
        list) cat <<'EOF'
List installed toolchains.

Usage:
  llvmup list [--json]
  llvmup list --remote [--provider <P>] [--json]
  llvmup list --providers

--remote queries upstream releases (network); the other forms are offline.
EOF
        ;;
        status) cat <<'EOF'
Show the current selection.

Usage:
  llvmup status [--explain] [--json]

--explain shows why the toolchain was selected (session override, project
configuration or user default). --json prints machine-readable output only.
EOF
        ;;
        config) cat <<'EOF'
Manage the project configuration (.llvmup-config).

Usage:
  llvmup config init        Create a .llvmup-config in this directory
  llvmup config load        Show the configuration that applies here
  llvmup config apply       Install what the configuration asks for
  llvmup config activate    Select the configured toolchain in this terminal
  llvmup config lock        Write .llvmup-lock.json with exact asset identities

See also: llvmup pin, llvmup sync.
EOF
        ;;
        sync) cat <<'EOF'
Install the toolchain requested by the project.

Usage:
  llvmup sync [--locked]

Reads .llvmup-config and installs the matching toolchain if it is missing.
With --locked, the exact asset recorded in .llvmup-lock.json is required.
EOF
        ;;
        pin) cat <<'EOF'
Record a toolchain in .llvmup-config.

Usage:
  llvmup pin [<selector>]
  llvmup pin --current     Record the active toolchain

Only .llvmup-config in the current project is modified.
EOF
        ;;
        default) cat <<'EOF'
Manage the user default toolchain.

Usage:
  llvmup default [<selector>]    Show the default, or set it when a selector is given
  llvmup default set <selector>
  llvmup default show
  llvmup default unset

The default applies when neither a manual selection nor a project configuration exists.
EOF
        ;;
        alias) cat <<'EOF'
Give installations stable names.

Usage:
  llvmup alias set <name> <installation>
  llvmup alias list | show <name> | remove <name>

Removing an alias never removes the toolchain it points to.
EOF
        ;;
        remove) cat <<'EOF'
Remove an installed toolchain.

Usage:
  llvmup remove <installation> [--force]

The default toolchain is refused unless --force is given. Only the installation
directory is deleted.
EOF
        ;;
        update) cat <<'EOF'
Install a newer release of an installed toolchain.

Usage:
  llvmup update [<selector>]

The previous installation is kept, and aliases, defaults and pins are not changed.
EOF
        ;;
        env) cat <<'EOF'
Print environment settings for scripts and CI.

Usage:
  llvmup env [<selector>|--config] [--compiler C] [--target T] [--format shell|github|json]

Examples:
  eval "$(llvmup env official@23)"
  llvmup env win-dev --format json

Only the settings are written to stdout; diagnostics go to stderr.
EOF
        ;;
        deactivate) cat <<'EOF'
Restore this terminal's previous environment.

Usage:
  llvmup deactivate

Works through the 'llvmup' shell function.
EOF
        ;;
        which|where) cat <<'EOF'
Print paths for scripts.

Usage:
  llvmup which <tool> [--toolchain <S>]   Path of a tool inside a toolchain
  llvmup where [<selector>]               Root directory of a toolchain

Only the path is written to stdout.
EOF
        ;;
        provides) cat <<'EOF'
Find installed toolchains that provide a tool.

Usage:
  llvmup provides <tool> [--json]

Examples:
  llvmup provides gcc
EOF
        ;;
        resolve) cat <<'EOF'
Show which upstream release a selector resolves to, without installing.

Usage:
  llvmup resolve [<provider>@]<selector> [--format tag|json|plan] [--release TAG] [--crt C]
  llvmup resolve --config
EOF
        ;;
        doctor) cat <<'EOF'
Diagnose the LLVMUP installation and environment. Read-only and offline by default.

Usage:
  llvmup doctor [--verbose] [--deep] [--network] [--json]
EOF
        ;;
        toolchain) cat <<'EOF'
Link an existing toolchain that LLVMUP did not install.

Usage:
  llvmup toolchain link <name> <path>
  llvmup toolchain list
  llvmup toolchain unlink <name>

Unlinking forgets the entry. The external files are never deleted.
EOF
        ;;
        shell) cat <<'EOF'
Open a subshell with a toolchain active.

Usage:
  llvmup shell [<selector>]

Exit the subshell to return to your previous environment.
EOF
        ;;
        pick) cat <<'EOF'
Choose an installed toolchain from a numbered list and select it.

Usage:
  llvmup pick

Needs an interactive terminal and the 'llvmup' shell function. In scripts use 'llvmup use <toolchain>'.
EOF
        ;;
        info) cat <<'EOF'
Show details of an installed toolchain (provider, versions, targets, compilers).

Usage:
  llvmup info [<selector>] [--json]
EOF
        ;;
        disk-usage) cat <<'EOF'
Show disk usage of installed toolchains.

Usage:
  llvmup disk-usage [-h]

-h prints sizes in binary units. Nothing is modified.
EOF
        ;;
        cmake-toolchain) cat <<'EOF'
Write a CMake toolchain file for a toolchain.

Usage:
  llvmup cmake-toolchain [<selector>] [--target T] [--compiler C] [--output FILE]
EOF
        ;;
        vscode-activate) cat <<'EOF'
Configure VS Code to use an installed toolchain.

Usage:
  llvmup vscode-activate <installation>

Writes workspace settings in the current directory.
EOF
        ;;
        *) return 1 ;;
    esac
}

# Function to initialize a .llvmup-config file in the current directory
llvm-config-init() {
    local config_file=".llvmup-config"

    if [ -f "$config_file" ]; then
        log_warn ".llvmup-config already exists in current directory"
        log_debug "Current configuration:"
        log_debug "$(cat "$config_file")"
        log_debug ""

        # For testing environments, allow skipping interactive prompts
        local overwrite_choice="n"
        if [ -n "$LLVM_TEST_MODE" ]; then
            overwrite_choice="${LLVM_TEST_OVERWRITE:-n}"
        else
            read -p "Overwrite existing configuration? [y/N] " -n 1 -r
            echo
            overwrite_choice="$REPLY"
        fi

        if [[ ! $overwrite_choice =~ ^[Yy]$ ]]; then
            log_error "Configuration initialization cancelled"
            return 1
        fi
    fi

    log_config "Initializing LLVM project configuration..."

    # For testing, use environment variables or defaults
    if [ -n "$LLVM_TEST_MODE" ]; then
        local default_version="${LLVM_TEST_VERSION:-llvmorg-18.1.8}"
        local custom_name="${LLVM_TEST_CUSTOM_NAME:-}"
        local profile="${LLVM_TEST_PROFILE:-full}"
    else
        # Prompt for configuration
        echo -e "${BLUE}Please provide the following information:${NC}"

        # Check for installed versions first
        local toolchains_dir="$(llvm-get-toolchains-dir)"
        local suggested_version=""
        local installed_versions=()

        if [ -d "$toolchains_dir" ]; then
            # Simply list all directories in toolchains (much simpler and more reliable)
            while IFS= read -r version; do installed_versions+=("$version"); done < <(ls -1 "$toolchains_dir" 2>/dev/null | grep -v "^$")
        fi

        if [ ${#installed_versions[@]} -gt 0 ]; then
            log_info "Found installed LLVM versions:"
            for i in "${!installed_versions[@]}"; do
                log_info "  $((i+1)). ${installed_versions[i]}"
            done
            suggested_version="${installed_versions[0]}"
            echo ""
            read -p "Default LLVM version (suggested: $suggested_version): " default_version
            if [ -z "$default_version" ]; then
                default_version="$suggested_version"
            fi
        else
            log_error "No LLVM versions currently installed"
            log_debug "Would you like to see available remote versions to choose from?"

            # For testing environments, skip interactive prompts
            local list_choice="Y"
            if [ -n "$LLVM_TEST_MODE" ]; then
                list_choice="${LLVM_TEST_LIST_REMOTE:-Y}"
            else
                read -p "List remote versions? [Y/n]: " -n 1 -r
                echo
                list_choice="$REPLY"
            fi

            if [[ ! $list_choice =~ ^[Nn]$ ]]; then
                log_progress "Fetching available LLVM versions from GitHub..."
                if command -v curl >/dev/null 2>&1; then
                    log_tip "Latest available versions:"
                    local remote_versions=$(curl -s "https://api.github.com/repos/llvm/llvm-project/releases?per_page=10" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
                    if [ -n "$remote_versions" ]; then
                        echo "$remote_versions" | head -10 | while IFS= read -r version; do
                            echo "  • $version"
                        done
                        echo ""
                    else
                        log_warn "Unable to fetch remote versions from GitHub"
                        log_tip "You can use versions like: llvmorg-18.1.8, llvmorg-17.0.6, llvmorg-16.0.6"
                    fi
                elif command -v llvm-prebuilt >/dev/null 2>&1; then
                    log_tip "You can check available versions by running:"
                    log_tip "  llvmup install"
                    log_tip "Common versions: llvmorg-18.1.8, llvmorg-17.0.6, llvmorg-16.0.6"
                else
                    log_warn "Unable to fetch remote versions"
                    log_tip "Common versions: llvmorg-18.1.8, llvmorg-17.0.6, llvmorg-16.0.6"
                fi
            fi

            # For testing environments, use default version
            if [ -n "$LLVM_TEST_MODE" ]; then
                default_version="${LLVM_TEST_DEFAULT_VERSION:-llvmorg-18.1.8}"
            else
                read -p "Default LLVM version (e.g., llvmorg-18.1.8): " default_version
                if [ -z "$default_version" ]; then
                    default_version="llvmorg-18.1.8"
                fi
            fi
        fi

        # For testing environments, use default values
        if [ -n "$LLVM_TEST_MODE" ]; then
            custom_name="${LLVM_TEST_CUSTOM_NAME:-}"
            profile="${LLVM_TEST_PROFILE:-full}"
        else
            read -p "Custom installation name (optional): " custom_name
            read -p "Build profile [minimal/compiler/full/custom]: " profile
            if [ -z "$profile" ]; then
                profile="full"
            fi
        fi
    fi

    # Create configuration file
    cat > "$config_file" << EOF
# .llvmup-config - LLVM project configuration
# Generated on $(date)

[version]
default = "$default_version"

[build]
EOF

    if [ -n "$custom_name" ]; then
        echo "name = \"$custom_name\"" >> "$config_file"
    fi

    cat >> "$config_file" << EOF
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Release"
]

[profile]
type = "$profile"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]

[project]
# Project-specific settings
auto_activate = true
cmake_preset = "Release"  # Options: Debug, Release, RelWithDebInfo, MinSizeRel

# Optional: Custom directory paths (useful for Docker/containers)
# [paths]
# llvm_home = "./llvm"
# toolchains_dir = "./llvm/toolchains"
# sources_dir = "./llvm/sources"

# VERSION EXPRESSION EXAMPLES:
# Specific version:     default = "llvmorg-18.1.8"
# Latest available:     default = "latest"
# Latest prebuilt:      default = "latest-prebuilt"
# Latest source build:  default = "latest-source"
# Version range:        default = ">=18.0.0"
# Tilde range:          default = "~19.1"
# Wildcard:             default = "18.*"
# Only prebuilt:        default = "prebuilt"
# Only source builds:   default = "source"
# Oldest version:       default = "oldest"
EOF

    log_success "Configuration file created: $config_file"
    log_tip "Edit the file to customize build settings"
    log_tip "Run 'llvm-config-load' to install and activate the configured version"
}

# Function to load and parse .llvmup-config settings
llvm-config-load() {
    local config_file=".llvmup-config"

    if [ ! -f "$config_file" ]; then
        log_error "No .llvmup-config file found in current directory"
        log_tip "Run 'llvm-config-init' to create one"
        return 1
    fi

    log_progress "Loading project configuration from $config_file..."

    # Initialize global variables for config
    LLVM_CONFIG_VERSION=""
    LLVM_CONFIG_NAME=""
    LLVM_CONFIG_PROFILE=""
    LLVM_CONFIG_AUTO_ACTIVATE="false"
    LLVM_CONFIG_CMAKE_PRESET=""
    LLVM_CONFIG_DISABLE_LIBC_WNO_ERROR="false"
    LLVM_CONFIG_CMAKE_FLAGS=()
    LLVM_CONFIG_COMPONENTS=()

    # Directory customization variables
    LLVM_CONFIG_LLVM_HOME=""
    LLVM_CONFIG_TOOLCHAINS_DIR=""
    LLVM_CONFIG_SOURCES_DIR=""

    # Parse configuration file
    local current_section=""
    local in_array=0
    local array_type=""

    # Helper function to trim whitespace from a string
    trim() {
        local var="$1"
        # Remove leading and trailing whitespace
        var="${var#"${var%%[![:space:]]*}"}"
        var="${var%"${var##*[![:space:]]}"}"
        echo "$var"
    }

    # Helper function to parse array content
    parse_array_content() {
        local content="$1"
        local section="$2"
        local key="$3"

        # Remove quotes and whitespace, split by comma
        content=$(echo "$content" | sed 's/[[:space:]]*["'"'"']//g; s/["'"'"'][[:space:]]*//g')

        # Split by comma and add to appropriate array
        IFS=',' read -ra items <<< "$content"
        for item in "${items[@]}"; do
            item=$(trim "$item")
            [ -z "$item" ] && continue

            case "$section" in
                "build"|"")
                    if [ "$key" = "cmake_flags" ]; then
                        LLVM_CONFIG_CMAKE_FLAGS+=("$item")
                    fi
                    ;;
                "components"|"")
                    if [ "$key" = "components" ] || [ "$key" = "include" ]; then
                        LLVM_CONFIG_COMPONENTS+=("$item")
                    fi
                    ;;
            esac
        done
    }

    local array_assignment='^[[:space:]]*([^=]+)=[[:space:]]*\['
    local assignment='^[[:space:]]*([^=]+)=(.*)$'
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Handle sections
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            current_section="${line//[\[\]]/}"
            in_array=0
            continue
        fi

        # Handle array start
        if [[ "$line" =~ $array_assignment ]]; then
            key="${BASH_REMATCH[1]// /}"
            in_array=1
            array_type="$key"

            # Check if array is closed on same line
            if [[ "$line" =~ \] ]]; then
                # Extract array content
                content=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
                parse_array_content "$content" "$current_section" "$key"
                in_array=0
            fi
            continue
        fi

        # Handle array continuation
        if [ "$in_array" -eq 1 ]; then
            if [[ "$line" =~ \] ]]; then
                # End of array
                content=$(echo "$line" | sed 's/].*//')
                parse_array_content "$content" "$current_section" "$array_type"
                in_array=0
            else
                # Array item
                parse_array_content "$line" "$current_section" "$array_type"
            fi
            continue
        fi

        # Parse key=value pairs
        if [[ "$line" =~ $assignment ]]; then
            key="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]}"
            # Remove quotes and whitespace
            value=$(echo "$value" | sed 's/^[[:space:]]*["'"'"']//;s/["'"'"'][[:space:]]*$//')
            value=$(trim "$value")

            # Handle simple format (without sections) or section-based format
            case "$current_section" in
                "") # Simple format
                    case "$key" in
                        "version")
                            LLVM_CONFIG_VERSION=$(trim "$value")
                            ;;
                        "name")
                            LLVM_CONFIG_NAME=$(trim "$value")
                            ;;
                        "profile")
                            LLVM_CONFIG_PROFILE=$(trim "$value")
                            ;;
                        "auto_activate")
                            LLVM_CONFIG_AUTO_ACTIVATE=$(trim "$value")
                            ;;
                        "cmake_preset")
                            LLVM_CONFIG_CMAKE_PRESET=$(trim "$value")
                            ;;
                    esac
                    ;;
                "version")
                    if [ "$key" = "default" ]; then
                        LLVM_CONFIG_VERSION=$(trim "$value")
                    fi
                    ;;
                "build")
                    if [ "$key" = "name" ]; then
                        LLVM_CONFIG_NAME=$(trim "$value")
                    elif [ "$key" = "disable_libc_wno_error" ]; then
                        LLVM_CONFIG_DISABLE_LIBC_WNO_ERROR=$(trim "$value")
                    fi
                    ;;
                "profile")
                    if [ "$key" = "type" ]; then
                        LLVM_CONFIG_PROFILE=$(trim "$value")
                    fi
                    ;;
                "project")
                    if [ "$key" = "auto_activate" ]; then
                        LLVM_CONFIG_AUTO_ACTIVATE=$(trim "$value")
                    elif [ "$key" = "cmake_preset" ]; then
                        LLVM_CONFIG_CMAKE_PRESET=$(trim "$value")
                    fi
                    ;;
                "paths")
                    case "$key" in
                        "llvm_home")
                            LLVM_CONFIG_LLVM_HOME=$(trim "$value")
                            ;;
                        "toolchains_dir")
                            LLVM_CONFIG_TOOLCHAINS_DIR=$(trim "$value")
                            ;;
                        "sources_dir")
                            LLVM_CONFIG_SOURCES_DIR=$(trim "$value")
                            ;;
                    esac
                    ;;
            esac
        fi
    done < "$config_file"

    if [ -z "$LLVM_CONFIG_VERSION" ]; then
        log_error "No default version specified in configuration"
        return 1
    fi

    # Apply cmake preset if specified
    if [ -n "$LLVM_CONFIG_CMAKE_PRESET" ]; then
        case "$LLVM_CONFIG_CMAKE_PRESET" in
            "Debug")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DCMAKE_BUILD_TYPE=Debug")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DLLVM_ENABLE_ASSERTIONS=ON")
                ;;
            "Release")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DCMAKE_BUILD_TYPE=Release")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DLLVM_ENABLE_ASSERTIONS=OFF")
                ;;
            "RelWithDebInfo")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DCMAKE_BUILD_TYPE=RelWithDebInfo")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DLLVM_ENABLE_ASSERTIONS=ON")
                ;;
            "MinSizeRel")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DCMAKE_BUILD_TYPE=MinSizeRel")
                LLVM_CONFIG_CMAKE_FLAGS+=("-DLLVM_ENABLE_ASSERTIONS=OFF")
                ;;
            *)
                log_warn "Unknown cmake_preset: $LLVM_CONFIG_CMAKE_PRESET (ignoring)"
                ;;
        esac
    fi

    # Apply custom directory settings if specified
    if [ -n "$LLVM_CONFIG_LLVM_HOME" ] || [ -n "$LLVM_CONFIG_TOOLCHAINS_DIR" ] || [ -n "$LLVM_CONFIG_SOURCES_DIR" ]; then
        log_debug "Applying custom directory configuration..."

        if [ -n "$LLVM_CONFIG_LLVM_HOME" ]; then
            log_debug "Using custom LLVM_HOME: $LLVM_CONFIG_LLVM_HOME"
        fi

        if [ -n "$LLVM_CONFIG_TOOLCHAINS_DIR" ]; then
            log_debug "Using custom TOOLCHAINS_DIR: $LLVM_CONFIG_TOOLCHAINS_DIR"
        fi

        if [ -n "$LLVM_CONFIG_SOURCES_DIR" ]; then
            log_debug "Using custom SOURCES_DIR: $LLVM_CONFIG_SOURCES_DIR"
        fi
    fi

    # Apply custom directory configuration
    llvm-config-apply-directories

    log_config "Configuration loaded:"
    log_info "   Version: $LLVM_CONFIG_VERSION"
    [ -n "$LLVM_CONFIG_NAME" ] && log_info "   Name: $LLVM_CONFIG_NAME"
    [ -n "$LLVM_CONFIG_PROFILE" ] && log_info "   Profile: $LLVM_CONFIG_PROFILE"
    [ ${#LLVM_CONFIG_CMAKE_FLAGS[@]} -gt 0 ] && log_debug "CMake flags: ${LLVM_CONFIG_CMAKE_FLAGS[*]}"
    [ ${#LLVM_CONFIG_COMPONENTS[@]} -gt 0 ] && log_debug "Components: ${LLVM_CONFIG_COMPONENTS[*]}"
    [ -n "$LLVM_CONFIG_CMAKE_PRESET" ] && log_debug "CMake preset: $LLVM_CONFIG_CMAKE_PRESET"
    [ "$LLVM_CONFIG_DISABLE_LIBC_WNO_ERROR" = "true" ] && log_debug "LIBC_WNO_ERROR disabled"
    [ -n "$LLVM_CONFIG_LLVM_HOME" ] && log_debug "LLVM Home: $LLVM_CONFIG_LLVM_HOME"
    [ -n "$LLVM_CONFIG_TOOLCHAINS_DIR" ] && log_debug "Toolchains Dir: $LLVM_CONFIG_TOOLCHAINS_DIR"
    [ -n "$LLVM_CONFIG_SOURCES_DIR" ] && log_debug "Sources Dir: $LLVM_CONFIG_SOURCES_DIR"
    if [ "$LLVM_CONFIG_AUTO_ACTIVATE" = "true" ]; then
        log_debug "Auto-activate: enabled"
    elif [ "$LLVM_CONFIG_AUTO_ACTIVATE" = "false" ]; then
        log_debug "Auto-activate: disabled"
    fi

    log_tip "Next steps:"
    log_tip "  • llvm-config-apply    - Install with these settings"
    log_tip "  • llvm-config-activate - Activate if already installed"
    return 0
}

# Function to apply directory configuration from loaded config
llvm-config-apply-directories() {
    local directory_var

    # Restore the environment that existed before the first project config was
    # applied. This prevents paths from one project leaking into the next one.
    if [ "${_LLVM_CONFIG_DIRECTORY_STATE_INITIALIZED:-0}" -eq 1 ]; then
        for directory_var in LLVM_HOME LLVM_TOOLCHAINS_DIR LLVM_SOURCES_DIR LLVM_CUSTOM_HOME LLVM_CUSTOM_TOOLCHAINS_DIR LLVM_CUSTOM_SOURCES_DIR; do
            local set_var="_LLVM_CONFIG_ORIGINAL_${directory_var}_SET"
            local value_var="_LLVM_CONFIG_ORIGINAL_${directory_var}"
            if [ "${!set_var:-0}" -eq 1 ]; then
                printf -v "$directory_var" '%s' "${!value_var}"
                export "$directory_var"
            else
                unset "$directory_var"
            fi
        done
    else
        for directory_var in LLVM_HOME LLVM_TOOLCHAINS_DIR LLVM_SOURCES_DIR LLVM_CUSTOM_HOME LLVM_CUSTOM_TOOLCHAINS_DIR LLVM_CUSTOM_SOURCES_DIR; do
            local set_var="_LLVM_CONFIG_ORIGINAL_${directory_var}_SET"
            local value_var="_LLVM_CONFIG_ORIGINAL_${directory_var}"
            if declare -p "$directory_var" >/dev/null 2>&1; then
                printf -v "$set_var" '%s' 1
                printf -v "$value_var" '%s' "${!directory_var}"
            else
                printf -v "$set_var" '%s' 0
                printf -v "$value_var" '%s' ''
            fi
        done
        _LLVM_CONFIG_DIRECTORY_STATE_INITIALIZED=1
    fi

    # Set global variables that scripts can use
    if [ -n "$LLVM_CONFIG_LLVM_HOME" ]; then
        export LLVM_CUSTOM_HOME="$LLVM_CONFIG_LLVM_HOME"
    fi

    if [ -n "$LLVM_CONFIG_TOOLCHAINS_DIR" ]; then
        export LLVM_CUSTOM_TOOLCHAINS_DIR="$LLVM_CONFIG_TOOLCHAINS_DIR"
    elif [ -n "$LLVM_CONFIG_LLVM_HOME" ]; then
        export LLVM_CUSTOM_TOOLCHAINS_DIR="$LLVM_CONFIG_LLVM_HOME/toolchains"
    fi

    if [ -n "$LLVM_CONFIG_SOURCES_DIR" ]; then
        export LLVM_CUSTOM_SOURCES_DIR="$LLVM_CONFIG_SOURCES_DIR"
    elif [ -n "$LLVM_CONFIG_LLVM_HOME" ]; then
        export LLVM_CUSTOM_SOURCES_DIR="$LLVM_CONFIG_LLVM_HOME/sources"
    fi

    # Also export canonical environment variables for portability
    # Prefer explicit canonical vars if they are already set, otherwise derive from custom vars
    if [ -n "$LLVM_TOOLCHAINS_DIR" ]; then
        export LLVM_TOOLCHAINS_DIR="$LLVM_TOOLCHAINS_DIR"
    elif [ -n "$LLVM_CUSTOM_TOOLCHAINS_DIR" ]; then
        export LLVM_TOOLCHAINS_DIR="$LLVM_CUSTOM_TOOLCHAINS_DIR"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        export LLVM_TOOLCHAINS_DIR="$LLVM_CUSTOM_HOME/toolchains"
    else
        export LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"
    fi

    if [ -n "$LLVM_SOURCES_DIR" ]; then
        export LLVM_SOURCES_DIR="$LLVM_SOURCES_DIR"
    elif [ -n "$LLVM_CUSTOM_SOURCES_DIR" ]; then
        export LLVM_SOURCES_DIR="$LLVM_CUSTOM_SOURCES_DIR"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        export LLVM_SOURCES_DIR="$LLVM_CUSTOM_HOME/sources"
    else
        export LLVM_SOURCES_DIR="$HOME/.llvm/sources"
    fi

    if [ -n "$LLVM_HOME" ]; then
        export LLVM_HOME="$LLVM_HOME"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        export LLVM_HOME="$LLVM_CUSTOM_HOME"
    else
        export LLVM_HOME="$HOME/.llvm"
    fi
}

# Function to get effective toolchains directory (respects config)
llvm-get-toolchains-dir() {
    local default_toolchains_dir="$HOME/.llvm/toolchains"

    if [ -n "$LLVM_TOOLCHAINS_DIR" ] && { [ -z "$LLVM_HOME" ] || [ "$LLVM_TOOLCHAINS_DIR" != "$default_toolchains_dir" ]; }; then
        echo "$LLVM_TOOLCHAINS_DIR"
    elif [ -n "$LLVM_CUSTOM_TOOLCHAINS_DIR" ]; then
        echo "$LLVM_CUSTOM_TOOLCHAINS_DIR"
    elif [ -n "$LLVM_HOME" ]; then
        echo "$LLVM_HOME/toolchains"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        echo "$LLVM_CUSTOM_HOME/toolchains"
    else
        echo "$HOME/.llvm/toolchains"
    fi
}

# Function to get effective sources directory (respects config)
llvm-get-sources-dir() {
    local default_sources_dir="$HOME/.llvm/sources"

    if [ -n "$LLVM_SOURCES_DIR" ] && { [ -z "$LLVM_HOME" ] || [ "$LLVM_SOURCES_DIR" != "$default_sources_dir" ]; }; then
        echo "$LLVM_SOURCES_DIR"
    elif [ -n "$LLVM_CUSTOM_SOURCES_DIR" ]; then
        echo "$LLVM_CUSTOM_SOURCES_DIR"
    elif [ -n "$LLVM_HOME" ]; then
        echo "$LLVM_HOME/sources"
    elif [ -n "$LLVM_CUSTOM_HOME" ]; then
        echo "$LLVM_CUSTOM_HOME/sources"
    else
        echo "$HOME/.llvm/sources"
    fi
}

llvm-get-installation-name() {
    if [ -n "$LLVM_CONFIG_NAME" ]; then
        echo "$LLVM_CONFIG_NAME"
    else
        echo "$LLVM_CONFIG_VERSION"
    fi
}

llvm-get-toolchain-path() {
    local version="$1"

    if [ -z "$version" ]; then
        log_error "Version is required"
        return 1
    fi

    echo "$(llvm-get-toolchains-dir)/$version"
}

llvm-validate-toolchain-path() {
    local llvm_dir="$1"
    local compiler

    if [ -z "$llvm_dir" ] || [ ! -d "$llvm_dir" ]; then
        log_error "LLVM toolchain directory does not exist: ${llvm_dir:-<empty>}"
        return 1
    fi

    for compiler in clang clang++; do
        if [ ! -x "$llvm_dir/bin/$compiler" ]; then
            log_error "LLVM toolchain is incomplete: $llvm_dir/bin/$compiler is missing or not executable"
            return 1
        fi

        if ! "$llvm_dir/bin/$compiler" --version >/dev/null 2>&1; then
            log_error "LLVM toolchain is unusable: $llvm_dir/bin/$compiler --version failed"
            return 1
        fi
    done

    return 0
}

llvm-macos-sdk-root() {
    if [ -n "${SDKROOT:-}" ]; then
        case "$SDKROOT" in
            /*) if [ -d "$SDKROOT" ] && [ "$SDKROOT" != / ]; then printf '%s\n' "$SDKROOT"; return 0; fi ;;
        esac
    fi
    if ! command -v xcrun >/dev/null 2>&1; then
        log_warn "macOS SDK not found: xcrun is unavailable; C/C++ linking may fail"
        return 0
    fi
    local sdk_root
    sdk_root="$(xcrun --sdk macosx --show-sdk-path)" || {
        log_warn "macOS SDK discovery failed; C/C++ linking may fail"
        return 0
    }
    case "$sdk_root" in
        /*) ;;
        *) sdk_root="" ;;
    esac
    if [ -z "$sdk_root" ] || [ "$sdk_root" = / ] || [ ! -d "$sdk_root" ]; then
        log_warn "xcrun did not return an available macOS SDK; C/C++ linking may fail"
        return 0
    fi
    printf '%s\n' "$sdk_root"
}

llvm-print-env-exports() {
    local version="$1"
    local format="${2:-shell}"
    local llvm_dir
    local sdk_root=""

    if [ -z "$version" ]; then
        log_error "Version is required"
        return 1
    fi

    llvm_dir="$(llvm-get-toolchain-path "$version")"
    if [ ! -d "$llvm_dir" ]; then
        log_error "Version '$version' is not installed in $(llvm-get-toolchains-dir)."
        return 1
    fi
    llvm-validate-toolchain-path "$llvm_dir" || return 1
    if [ "$(uname -s)" = Darwin ]; then
        sdk_root="$(llvm-macos-sdk-root)" || return 1
    fi

    case "$format" in
        shell)
            printf 'export PATH=%q\n' "$llvm_dir/bin:$PATH"
            printf 'export CC=%q\n' "$llvm_dir/bin/clang"
            printf 'export CXX=%q\n' "$llvm_dir/bin/clang++"
            [ -z "$sdk_root" ] || printf 'export SDKROOT=%q\n' "$sdk_root"
            if [ -x "$llvm_dir/bin/lld" ]; then
                printf 'export LD=%q\n' "$llvm_dir/bin/lld"
            fi
            printf 'export LLVMUP_ACTIVE_VERSION=%q\n' "$version"
            printf 'export LLVMUP_ACTIVE_PATH=%q\n' "$llvm_dir"
            ;;
        github)
            if [ -z "${GITHUB_PATH:-}" ] || [ -z "${GITHUB_ENV:-}" ]; then
                log_error "GITHUB_PATH and GITHUB_ENV are required for GitHub format"
                return 1
            fi

            printf '%s\n' "$llvm_dir/bin" >> "$GITHUB_PATH"
            {
                printf 'CC=%s\n' "$llvm_dir/bin/clang"
                printf 'CXX=%s\n' "$llvm_dir/bin/clang++"
                [ -z "$sdk_root" ] || printf 'SDKROOT=%s\n' "$sdk_root"
                if [ -x "$llvm_dir/bin/lld" ]; then
                    printf 'LD=%s\n' "$llvm_dir/bin/lld"
                fi
                printf 'LLVMUP_ACTIVE_VERSION=%s\n' "$version"
                printf 'LLVMUP_ACTIVE_PATH=%s\n' "$llvm_dir"
            } >> "$GITHUB_ENV"
            ;;
        *)
            log_error "Unsupported env format: $format"
            return 1
            ;;
    esac
}

llvm-print-config-env-exports() {
    local format="${1:-shell}"
    local config_root

    config_root="$(llvm-find-config-root)" || config_root=""
    if [ -z "$config_root" ]; then
        log_error "No .llvmup-config file found"
        return 1
    fi

    (
        cd "$config_root" || exit 1
        llvm-config-load >/dev/null 2>&1 || exit $?
        llvm-print-env-exports "$(llvm-get-installation-name)" "$format"
    )
}


# Function to apply loaded .llvmup-config settings
llvm-config-apply() {
    # Check if config is loaded
    if [ -z "$LLVM_CONFIG_VERSION" ]; then
        log_error "No configuration loaded. Run 'llvm-config-load' first"
        return 1
    fi

    # [toolchain] kind decides between a prebuilt install (through 'llvmup sync', which honors
    # provider, release, CRT and target) and a source build. Legacy configs without kind are source
    # builds only when they carry build options or a source- selector, as in PowerShell.
    local config_root kind=""
    config_root="$(llvm-find-config-root)" || config_root="."
    if [ -f "$config_root/.llvmup-config" ]; then
        kind="$(awk '/^[[:space:]]*\[/{s=$0; gsub(/[][[:space:]]/, "", s); sec=tolower(s); next}
                     sec == "toolchain" && /^[[:space:]]*kind[[:space:]]*=/ {v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/["'"'"'[:space:]]/, "", v); print tolower(v); exit}' "$config_root/.llvmup-config")"
    fi
    if [ -z "$kind" ]; then
        if [[ "$LLVM_CONFIG_VERSION" == source-* ]] || [ ${#LLVM_CONFIG_CMAKE_FLAGS[@]} -gt 0 ]; then kind=source; else kind=prebuilt; fi
    fi
    if [ "$kind" = prebuilt ]; then
        log_tip "Installing with settings:"
        log_tip "  llvmup sync    (prebuilt ${LLVM_CONFIG_VERSION} from $config_root/.llvmup-config)"
        local apply_choice="n"
        if [ -n "$LLVM_TEST_MODE" ]; then
            apply_choice="${LLVM_TEST_INSTALL_NOW:-n}"
        else
            read -p "Install now? [y/N]: " -n 1 -r
            echo
            apply_choice="$REPLY"
        fi
        if [[ $apply_choice =~ ^[Yy]$ ]]; then
            (cd "$config_root" && llvmup sync)
            return $?
        fi
        log_tip "To install later, run: llvmup sync"
        log_tip "To activate if already installed, run: llvm-config-activate"
        return 0
    fi

    # Build command arguments
    local cmd_args=("$LLVM_CONFIG_VERSION")
    [ -n "$LLVM_CONFIG_NAME" ] && cmd_args+=(--name "$LLVM_CONFIG_NAME")
    [ -n "$LLVM_CONFIG_PROFILE" ] && cmd_args+=(--profile "$LLVM_CONFIG_PROFILE")

    for flag in "${LLVM_CONFIG_CMAKE_FLAGS[@]}"; do
        cmd_args+=(--cmake-flags "$flag")
    done

    for comp in "${LLVM_CONFIG_COMPONENTS[@]}"; do
        cmd_args+=(--component "$comp")
    done

    log_tip "Installing with settings:"
    log_tip "  llvmup install --from-source ${cmd_args[*]}"

    # Ask if user wants to install now
    # For testing environments, skip interactive prompts
    local install_choice="n"
    if [ -n "$LLVM_TEST_MODE" ]; then
        install_choice="${LLVM_TEST_INSTALL_NOW:-n}"
        log_debug "Test mode: install choice = $install_choice"
    else
        read -p "Install now? [y/N]: " -n 1 -r
        echo
        install_choice="$REPLY"
    fi

    if [[ $install_choice =~ ^[Yy]$ ]]; then
        log_progress "Installing LLVM with project configuration..."
        if command -v llvmup >/dev/null 2>&1; then
            llvmup install --from-source "${cmd_args[@]}"
            if [ $? -eq 0 ]; then
                log_success "Installation complete!"
                log_tip "Use 'llvm-config-activate' to activate the version"
            fi
        else
            log_error "llvmup command not found in PATH"
            log_tip "Make sure LLVM manager is installed and in your PATH"
            return 1
        fi
    else
        log_tip "To install later, run: llvmup install --from-source ${cmd_args[*]}"
        log_tip "To activate if already installed, run: llvm-config-activate"
    fi
}

# Function to handle activation based on configuration
llvm-config-activate() {
    # Check if config is loaded
    if [ -z "$LLVM_CONFIG_VERSION" ]; then
        log_error "No configuration loaded. Run 'llvm-config-load' first"
        return 1
    fi

    # Determine installation name (same logic as apply)
    local installation_name="${LLVM_CONFIG_VERSION}"

    log_config "Activating LLVM configuration:"
    log_info "   Version: $LLVM_CONFIG_VERSION"
    [ -n "$LLVM_CONFIG_NAME" ] && log_debug "Name: $LLVM_CONFIG_NAME"
    [ -n "$LLVM_CONFIG_PROFILE" ] && log_debug "Profile: $LLVM_CONFIG_PROFILE"
    log_debug "Installation: $installation_name"

    # Try to activate the installation
    if command -v llvm-activate >/dev/null 2>&1; then
        llvm-activate "$installation_name"
        local activate_result=$?

        if [ $activate_result -eq 0 ]; then
            log_success "LLVM $installation_name activated successfully"

            # Display current activated version info if verbose
            if [ -n "$LLVM_CONFIG_VERBOSE" ] || [ "$1" = "--verbose" ] || [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
                log_debug "Active LLVM environment:"
                command -v clang && clang --version | head -1
                command -v llvm-config && log_debug "LLVM Config: $(llvm-config --version)"
            fi
        else
            log_error "Failed to activate LLVM $installation_name"
            log_tip "Make sure the installation exists with: llvm-list"
            return $activate_result
        fi
    else
        log_error "llvm-activate command not found in PATH"
        log_tip "Make sure LLVM manager is installed and in your PATH"
        return 1
    fi
}

# =============================================================================
# VERSION PARSING AND MANAGEMENT FUNCTIONS
# =============================================================================

# Parse version string from LLVM version identifier
# Supports formats: llvmorg-18.1.8, source-llvmorg-20.1.0, 19.1.7
llvm-parse-version() {
    local version_string="$1"

    if [ -z "$version_string" ]; then
        log_error "Version string is required"
        return 1
    fi

    # Remove common prefixes
    local clean_version="${version_string#llvmorg-}"
    clean_version="${clean_version#source-llvmorg-}"
    clean_version="${clean_version#source-}"

    # Extract version numbers (major.minor.patch or major.minor)
    if echo "$clean_version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?$'; then
        echo "$clean_version"
        return 0
    else
        # Try to extract version from complex strings like "21-init"
        local extracted=$(echo "$clean_version" | sed -n 's/^\([0-9]\+\).*/\1/p')
        if [ -n "$extracted" ]; then
            echo "$extracted"
            return 0
        fi
    fi

    log_error "Unable to parse version from: $version_string"
    return 1
}

# Normalize a specific LLVM version to the canonical release tag used upstream.
# Version expressions such as "latest" are deliberately handled by
# llvm-resolve-remote-release instead of being normalized here.
llvm-normalize-version-id() {
    local version_string="$1"
    local parsed_version

    if [ -z "$version_string" ]; then
        log_error "Version string is required"
        return 1
    fi

    parsed_version="$(llvm-parse-version "$version_string" 2>/dev/null)" || {
        log_error "Unable to normalize version: $version_string"
        return 1
    }

    printf 'llvmorg-%s\n' "$parsed_version"
}

llvm-detect-platform() {
    local platform="${1:-$(uname -s 2>/dev/null)}"

    case "$(printf '%s' "$platform" | tr '[:upper:]' '[:lower:]')" in
        linux*) printf 'Linux\n' ;;
        darwin*|macos*) printf 'macOS\n' ;;
        mingw*|msys*|cygwin*|windows*) printf 'Windows\n' ;;
        *)
            log_error "Unsupported platform: $platform"
            return 1
            ;;
    esac
}

llvm-detect-architecture() {
    local architecture="${1:-$(uname -m 2>/dev/null)}"

    case "$(printf '%s' "$architecture" | tr '[:lower:]' '[:upper:]')" in
        X86_64|AMD64|X64) printf 'X64\n' ;;
        AARCH64|ARM64) printf 'ARM64\n' ;;
        *)
            log_error "Unsupported architecture: $architecture"
            return 1
            ;;
    esac
}

# Query the LLVM GitHub releases API. Tests can provide LLVMUP_RELEASES_FILE
# containing a release array to exercise the exact same resolver offline.
llvm-github-api-request() {
    local endpoint="$1"
    local api_base="${LLVMUP_RELEASES_API_URL:-https://api.github.com/repos/llvm/llvm-project/releases}"
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    local curl_args=(
        -f
        --connect-timeout 30
        --max-time 60
        --retry 2
        --retry-delay 2
        --silent
        --show-error
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
    )

    if [ -n "${LLVMUP_RELEASES_FILE:-}" ]; then
        if [ ! -r "$LLVMUP_RELEASES_FILE" ]; then
            log_error "Release fixture is not readable: $LLVMUP_RELEASES_FILE"
            return 1
        fi

        case "$endpoint" in
            /latest)
                jq -c '[.[] | select(.draft != true and .prerelease != true)] | first // empty' "$LLVMUP_RELEASES_FILE"
                ;;
            /tags/*)
                local requested_tag="${endpoint#/tags/}"
                jq -c --arg tag "$requested_tag" '[.[] | select(.tag_name == $tag)][0] // empty' "$LLVMUP_RELEASES_FILE"
                ;;
            *)
                jq -c '.' "$LLVMUP_RELEASES_FILE"
                ;;
        esac
        return $?
    fi

    if [ -n "$token" ]; then
        curl_args+=(-H "Authorization: Bearer $token")
    fi

    curl "${curl_args[@]}" "${api_base}${endpoint}"
}

llvm-get-remote-stable-releases() {
    local releases

    releases="$(llvm-github-api-request '?per_page=100')" || {
        log_error "Failed to fetch LLVM releases from GitHub"
        return 1
    }

    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$releases"; then
        log_error "GitHub returned an invalid LLVM releases response"
        return 1
    fi

    jq -c '[.[]
        | select(.draft != true and .prerelease != true)
        | select(.tag_name | test("^llvmorg-[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ]' <<< "$releases"
}

llvm-print-remote-release-candidates() {
    local releases_json="${1:-}"
    local limit="${2:-10}"
    local versions
    local total

    if [ -z "$releases_json" ]; then
        releases_json="$(llvm-get-remote-stable-releases 2>/dev/null)" || return 0
    fi

    total="$(jq -r 'length' <<< "$releases_json" 2>/dev/null)" || return 0
    versions="$(jq -r --argjson limit "$limit" '.[0:$limit][].tag_name' <<< "$releases_json" 2>/dev/null)" || return 0
    [ -n "$versions" ] || return 0

    printf 'Stable LLVM releases identified by GitHub (showing up to %s of %s):\n' "$limit" "$total" >&2
    while IFS= read -r version; do
        printf '  - %s\n' "$version" >&2
    done <<< "$versions"
}

# Compatibility function for callers that expect official release metadata as JSON.
llvm-resolve-remote-release() {
    local expression="${1:-latest}" platform="${2:-}" arch="${3:-}" engine parsed status
    parsed="$(llvm-parse-version-expression "$expression" 2>/dev/null)" || {
        log_error "Invalid version expression: $expression"
        return 1
    }
    case "$parsed" in
        *type:source*|specific:source-*)
            log_error "Source installation identifiers cannot select a pre-built release: $expression"
            return 1
            ;;
    esac
    engine="$(llvm-engine-path)" || {
        log_error 'The provider engine is missing. Reinstall llvmup.'
        return 1
    }
    local args=("$expression" --provider official --format json)
    [ -z "$platform" ] || args+=(--platform "$platform")
    [ -z "$arch" ] || args+=(--arch "$arch")
    if bash "$engine" resolve "${args[@]}"; then
        return 0
    else
        status=$?
    fi
    llvm-print-remote-release-candidates
    return "$status"
}

llvm-get-versions() {
    local format="${1:-list}"  # Options: list, json, simple
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local sources_dir="$(llvm-get-sources-dir)"

    if [ ! -d "$toolchains_dir" ]; then
        log_error "No LLVM toolchains directory found at $toolchains_dir"
        return 1
    fi

    case "$format" in
        "json")
            llvm-get-versions-json
            ;;
        "simple")
            llvm-get-versions-simple
            ;;
        "list"|*)
            llvm-get-versions-list
            ;;
    esac
}

# Get versions in simple list format (one per line)
llvm-version-sort() {
    local version parsed major minor patch
    while IFS= read -r version; do
        [ -n "$version" ] || continue
        parsed="$(llvm-parse-version "$version" 2>/dev/null)" || parsed=""
        IFS=. read -r major minor patch <<< "$parsed"
        major=${major:-0}; minor=${minor:-0}; patch=${patch:-0}
        printf '%010d.%010d.%010d\t%s\n' "$major" "$minor" "$patch" "$version"
    done | LC_ALL=C sort | cut -f2-
}

llvm-get-versions-simple() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"

    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            basename "$dir"
        fi
    done | llvm-version-sort
}

# Get versions in detailed list format
llvm-get-versions-list() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local dir version_name parsed_version type_info marker found=false

    for dir in "$toolchains_dir"/*; do
        [ -d "$dir" ] || continue
        found=true
        version_name="$(basename "$dir")"
        parsed_version="$(llvm-parse-version "$version_name" 2>/dev/null)"
        marker=" "
        [ -z "${_ACTIVE_LLVM:-}" ] || [ "$version_name" != "$_ACTIVE_LLVM" ] || marker="*"
        if echo "$version_name" | grep -q "^source-"; then type_info="source build"; else type_info="prebuilt"; fi
        if [ -n "$parsed_version" ] && [ "$parsed_version" != "$version_name" ]; then
            printf '%s %-32s %-8s %s\n' "$marker" "$version_name" "v$parsed_version" "$type_info"
        else
            printf '%s %-32s %-8s %s\n' "$marker" "$version_name" "" "$type_info"
        fi
    done

    if [ "$found" = false ]; then
        echo "No toolchains installed."
        echo "Try 'llvmup install latest'."
        return 0
    fi
    echo
    echo "* active"
}

# Get versions in JSON format
llvm-get-versions-json() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local active_version="${_ACTIVE_LLVM:-${LLVMUP_ACTIVE_VERSION:-}}"
    local default_version=""
    local entries='[]'
    local dir

    default_version="$(llvm-get-default-version 2>/dev/null)" || default_version=""

    if [ -d "$toolchains_dir" ]; then
        for dir in "$toolchains_dir"/*; do
            [ -d "$dir" ] || continue
            local version_name
            local parsed_version
            local install_type="prebuilt"
            local is_active=false
            local is_default=false
            version_name="$(basename "$dir")"
            parsed_version="$(llvm-parse-version "$version_name" 2>/dev/null)" || parsed_version="$version_name"
            [ -n "$parsed_version" ] || parsed_version="$version_name"
            [[ "$version_name" == source-* ]] && install_type="source"
            [ "$version_name" = "$active_version" ] && is_active=true
            [ "$version_name" = "$default_version" ] && is_default=true
            entries="$(jq -c \
                --arg name "$version_name" \
                --arg version "$parsed_version" \
                --arg type "$install_type" \
                --arg path "$dir" \
                --argjson active "$is_active" \
                --argjson default "$is_default" \
                '. + [{name: $name, version: $version, type: $type, active: $active, default: $default, path: $path}]' \
                <<< "$entries")" || return 1
        done
    fi

    jq -n \
        --argjson installed_versions "$entries" \
        --arg active_version "$active_version" \
        --arg default_version "$default_version" \
        '{
            installed_versions: $installed_versions,
            active_version: (if $active_version == "" then null else $active_version end),
            default_version: (if $default_version == "" then null else $default_version end)
        }'
}

# Check if a specific version is installed
llvm-version-exists() {
    local version="$1"
    local toolchains_dir="$(llvm-get-toolchains-dir)"

    if [ -z "$version" ]; then
        log_error "Version parameter is required"
        return 1
    fi

    if [ -d "$toolchains_dir/$version" ]; then
        return 0
    else
        return 1
    fi
}

# Get the currently active LLVM version
llvm-get-active-version() {
    if [ -n "$_ACTIVE_LLVM" ]; then
        echo "$_ACTIVE_LLVM"
        return 0
    else
        log_error "No LLVM version is currently active"
        return 1
    fi
}

# Compare two version strings (returns 0 if v1 >= v2, 1 if v1 < v2)
llvm-version-compare() {
    local v1="$1"
    local v2="$2"

    if [ -z "$v1" ] || [ -z "$v2" ]; then
        log_error "Two version strings are required for comparison"
        return 2
    fi

    # Parse versions to clean format
    local clean_v1=$(llvm-parse-version "$v1")
    local clean_v2=$(llvm-parse-version "$v2")

    if [ -z "$clean_v1" ] || [ -z "$clean_v2" ]; then
        log_error "Unable to parse one or both version strings"
        return 2
    fi

    local v1_major v1_minor v1_patch v2_major v2_minor v2_patch
    IFS=. read -r v1_major v1_minor v1_patch <<< "$clean_v1"
    IFS=. read -r v2_major v2_minor v2_patch <<< "$clean_v2"
    v1_minor=${v1_minor:-0}; v1_patch=${v1_patch:-0}
    v2_minor=${v2_minor:-0}; v2_patch=${v2_patch:-0}
    local left right
    for left in "$v1_major" "$v1_minor" "$v1_patch"; do
        case "$left" in ''|*[!0-9]*) return 2 ;; esac
    done
    for right in "$v2_major" "$v2_minor" "$v2_patch"; do
        case "$right" in ''|*[!0-9]*) return 2 ;; esac
    done
    if [ "$v1_major" -ne "$v2_major" ]; then [ "$v1_major" -gt "$v2_major" ]; return; fi
    if [ "$v1_minor" -ne "$v2_minor" ]; then [ "$v1_minor" -gt "$v2_minor" ]; return; fi
    [ "$v1_patch" -ge "$v2_patch" ]
}

# Find the latest installed version
llvm-get-latest-version() {
    local versions=$(llvm-get-versions simple 2>/dev/null)

    if [ -z "$versions" ]; then
        log_error "No LLVM versions installed"
        return 1
    fi

    # Get the highest version using version sort
    echo "$versions" | while read -r version; do
        llvm-parse-version "$version"
    done | llvm-version-sort | tail -n1
}

# =============================================================================
# COMPREHENSIVE VERSION EXPRESSION PARSING AND MATCHING
# =============================================================================

# Parse and evaluate comprehensive version expressions
# Supports: specific versions, ranges, type filters, latest/oldest selectors
llvm-parse-version-expression() {
    local expression="$1"

    if [ -z "$expression" ]; then
        log_error "Version expression is required"
        return 1
    fi

    # Remove whitespace
    expression=$(echo "$expression" | tr -d '[:space:]')

    # Convert to lowercase for case-insensitive matching
    local expr_lower=$(echo "$expression" | tr '[:upper:]' '[:lower:]')

    log_expression_debug "Parsing version expression: '$expression'"

    # Parse different expression types
    case "$expr_lower" in
        # Latest/Oldest selectors
        "latest"|"newest"|"^")
            echo "selector:latest"
            ;;
        "oldest"|"first"|"earliest")
            echo "selector:oldest"
            ;;

        # Type filters
        "prebuilt"|"prebuilt-only"|"pre-built")
            echo "type:prebuilt"
            ;;
        "source"|"source-only"|"from-source")
            echo "type:source"
            ;;
        "latest-prebuilt"|"newest-prebuilt")
            echo "type:prebuilt,selector:latest"
            ;;
        "latest-source"|"newest-source")
            echo "type:source,selector:latest"
            ;;

        # Version ranges (e.g., >=18.0.0, ~19.1, 18.*)
        *">="*|*"<="*|*">"*|*"<"*|*"="*|*"~"*|*"*")
            echo "range:$expression"
            ;;

        # Specific version
        *)
            # Check if it looks like a version identifier
            if echo "$expression" | grep -qE '^(source-llvmorg-|llvmorg-|source-)?[0-9]+(\.[0-9]+)*(-[a-zA-Z0-9]+)?$'; then
                echo "specific:$expression"
            else
                log_error "Invalid version expression: $expression"
                return 1
            fi
            ;;
    esac
}

# Match an expression against a caller-provided version list. Keeping the
# matching engine independent from its data source lets installed and remote
# release workflows share exactly the same parsing and comparison behavior.
llvm-match-version-list() {
    local expression="$1"
    shift
    local available_versions=("$@")

    if [ -z "$expression" ]; then
        log_error "Version expression is required"
        return 1
    fi

    if [ ${#available_versions[@]} -eq 0 ]; then
        log_error "No LLVM versions were provided"
        return 1
    fi

    log_expression_verbose "Processing expression: '$expression'"
    log_expression_debug "Available versions: ${available_versions[*]}"

    # Parse the expression (suppress unwanted debug output)
    local parsed_expr
    if [ "$EXPRESSION_DEBUG" -eq 1 ]; then
        parsed_expr=$(llvm-parse-version-expression "$expression")
    else
        parsed_expr=$(llvm-parse-version-expression "$expression" 2>/dev/null)
    fi

    if [ $? -ne 0 ]; then
        log_error "Failed to parse expression: '$expression'"
        return 1
    fi

    log_expression_debug "Parsed expression: '$parsed_expr'"

    # Process the parsed expression
    local matched_versions=()
    local criteria=()

    # Split criteria by comma
    IFS=',' read -ra criteria <<< "$parsed_expr"

    # Start with all versions, then filter
    matched_versions=("${available_versions[@]}")

    for criterion in "${criteria[@]}"; do
        local type="${criterion%%:*}"
        local value="${criterion#*:}"

        log_expression_debug "Processing criterion: $type:$value"
        log_expression_debug "Current matches: ${matched_versions[*]}"

        case "$type" in
            "specific")
                # Prefer an exact installation name, then fall back to the
                # normalized semantic version so "22.1.8" matches
                # "llvmorg-22.1.8" as documented by the CLI.
                matched_versions=()
                for version in "${available_versions[@]}"; do
                    if [ "$version" = "$value" ]; then
                        matched_versions+=("$version")
                        log_expression_debug "Found specific match: $version"
                        break
                    fi
                done

                if [ ${#matched_versions[@]} -eq 0 ]; then
                    local target_parsed
                    target_parsed="$(llvm-parse-version "$value" 2>/dev/null)"
                    for version in "${available_versions[@]}"; do
                        local candidate_parsed
                        candidate_parsed="$(llvm-parse-version "$version" 2>/dev/null)"
                        [ -z "$candidate_parsed" ] && continue

                        if [ "$candidate_parsed" = "$target_parsed" ]; then
                            case "$value" in
                                source-*) [[ "$version" == source-* ]] || continue ;;
                                *) [[ "$version" != source-* ]] || continue ;;
                            esac
                            matched_versions+=("$version")
                            log_expression_debug "Found normalized specific match: $version"
                            break
                        fi
                    done
                fi
                ;;

            "type")
                # Filter by installation type
                local filtered=()
                for version in "${matched_versions[@]}"; do
                    case "$value" in
                        "prebuilt")
                            if ! echo "$version" | grep -q "^source-"; then
                                filtered+=("$version")
                                log_expression_debug "Prebuilt match: $version"
                            fi
                            ;;
                        "source")
                            if echo "$version" | grep -q "^source-"; then
                                filtered+=("$version")
                                log_expression_debug "Source match: $version"
                            fi
                            ;;
                    esac
                done
                matched_versions=("${filtered[@]}")
                ;;

            "selector")
                # Apply selector (latest/oldest)
                case "$value" in
                    "latest")
                        if [ ${#matched_versions[@]} -gt 0 ]; then
                            # Sort by parsed version and get latest
                            local latest_version=""
                            local latest_parsed=""

                            for version in "${matched_versions[@]}"; do
                                local parsed=$(llvm-parse-version "$version" 2>/dev/null)
                                if [ -n "$parsed" ]; then
                                    if [ -z "$latest_parsed" ] || llvm-version-compare "$parsed" "$latest_parsed" 2>/dev/null; then
                                        latest_version="$version"
                                        latest_parsed="$parsed"
                                        log_expression_debug "New latest candidate: $version ($parsed)"
                                    fi
                                fi
                            done

                            if [ -n "$latest_version" ]; then
                                matched_versions=("$latest_version")
                                log_expression_debug "Selected latest: $latest_version"
                            fi
                        fi
                        ;;
                    "oldest")
                        if [ ${#matched_versions[@]} -gt 0 ]; then
                            # Sort by parsed version and get oldest
                            local oldest_version=""
                            local oldest_parsed=""

                            for version in "${matched_versions[@]}"; do
                                local parsed=$(llvm-parse-version "$version" 2>/dev/null)
                                if [ -n "$parsed" ]; then
                                    if [ -z "$oldest_parsed" ] || ! llvm-version-compare "$parsed" "$oldest_parsed" 2>/dev/null; then
                                        oldest_version="$version"
                                        oldest_parsed="$parsed"
                                        log_expression_debug "New oldest candidate: $version ($parsed)"
                                    fi
                                fi
                            done

                            if [ -n "$oldest_version" ]; then
                                matched_versions=("$oldest_version")
                                log_expression_debug "Selected oldest: $oldest_version"
                            fi
                        fi
                        ;;
                esac
                ;;

            "range")
                # Handle version ranges
                local filtered=()
                for version in "${matched_versions[@]}"; do
                    if llvm-version-matches-range "$version" "$value" 2>/dev/null; then
                        filtered+=("$version")
                    fi
                done
                matched_versions=("${filtered[@]}")
                ;;
        esac
    done

    # Output matched versions
    if [ ${#matched_versions[@]} -gt 0 ]; then
        log_expression_debug "Final matches: ${matched_versions[*]}"
        log_expression_verbose "Found ${#matched_versions[@]} version(s) matching expression '$expression'"
        printf '%s\n' "${matched_versions[@]}"
        return 0
    else
        log_expression_debug "No versions matched expression: $expression"
        return 1
    fi
}

# Match against installed versions. This remains the public behavior used by
# activation and auto-activation; remote resolution uses the list matcher
# directly and therefore cannot unexpectedly change the active toolchain.
llvm-match-versions() {
    local expression="$1"
    local available_versions=()

    if [ -z "$expression" ]; then
        log_error "Version expression is required"
        return 1
    fi

    while IFS= read -r version; do available_versions+=("$version"); done < <(llvm-get-versions simple 2>/dev/null)
    llvm-match-version-list "$expression" "${available_versions[@]}"
}

# Check if a version matches a range expression
llvm-version-matches-range() {
    local version="$1"
    local range_expr="$2"

    local parsed_version=$(llvm-parse-version "$version" 2>/dev/null)
    if [ -z "$parsed_version" ]; then
        return 1
    fi

    log_expression_debug "Checking if version '$parsed_version' matches range '$range_expr'"

    # Handle different range operators
    case "$range_expr" in
        ">="*)
            local min_version="${range_expr#>=}"
            llvm-version-compare "$parsed_version" "$min_version" 2>/dev/null
            ;;
        "<="*)
            local max_version="${range_expr#<=}"
            ! llvm-version-compare "$parsed_version" "$max_version" 2>/dev/null || [ "$parsed_version" = "$max_version" ]
            ;;
        ">"*)
            local min_version="${range_expr#>}"
            llvm-version-compare "$parsed_version" "$min_version" 2>/dev/null && [ "$parsed_version" != "$min_version" ]
            ;;
        "<"*)
            local max_version="${range_expr#<}"
            ! llvm-version-compare "$parsed_version" "$max_version" 2>/dev/null
            ;;
        "="*)
            local exact_version="${range_expr#=}"
            [ "$parsed_version" = "$exact_version" ]
            ;;
        "~"*)
            # Tilde range: ~1.2.3 := >=1.2.3 <1.3.0
            local base_version=$(echo "$range_expr" | sed 's/^~//')
            local major=$(echo "$base_version" | cut -d. -f1)
            local minor=$(echo "$base_version" | cut -d. -f2)
            local patch=$(echo "$base_version" | cut -d. -f3)
            if [ -z "$minor" ]; then
                minor=0
            fi
            if [ -z "$patch" ]; then
                patch=0
            fi
            local next_minor=$((minor + 1))
            local next_version="$major.$next_minor.0"
            local floor_version="$major.$minor.$patch"

            llvm-version-compare "$parsed_version" "$floor_version" 2>/dev/null && \
            ! llvm-version-compare "$parsed_version" "$next_version" 2>/dev/null
            ;;
        *"*")
            # Wildcard matching: 18.* matches 18.x.x
            local pattern="${range_expr%\*}"
            echo "$parsed_version" | grep -q "^$pattern"
            ;;
        *)
            log_error "Unsupported range operator in: $range_expr"
            return 1
            ;;
    esac
}

# Enhanced auto-activation with comprehensive expressions
llvm-autoactivate-enhanced() {
    # Não executar auto-ativação em modo de teste
    if [ -n "$LLVM_TEST_MODE" ]; then
        return 0
    fi

    if [ -z "$LLVM_CONFIG_VERSION" ]; then
        local config_root="${LLVMUP_AUTOACTIVATE_ROOT:-}"
        if [ -n "$config_root" ] && [ -f "$config_root/.llvmup-config" ]; then
            llvm-load-config-from-root "$config_root" >/dev/null 2>&1 || return 0
        elif [ -f ".llvmup-config" ]; then
            llvm-config-load >/dev/null 2>&1 || return 0
        else
            return 0
        fi
    fi

    local backup_quiet_success=$QUIET_SUCCESS
    QUIET_SUCCESS=1

    # Load configuration
    llvm-config-load >/dev/null 2>&1

    # Check if auto-activate is enabled
    if [ "$LLVM_CONFIG_AUTO_ACTIVATE" != "true" ]; then
        QUIET_SUCCESS=$backup_quiet_success
        return 0
    fi

    # Get the version expression (could be specific version or expression)
    local version_expr="${LLVM_CONFIG_VERSION:-latest}"

    log_expression_debug "Auto-activation with expression: '$version_expr'"

    # Check if already activated
    if [ -n "$_ACTIVE_LLVM" ]; then
        log_expression_debug "LLVM already active: $_ACTIVE_LLVM"

        # Check if current version matches the expression
        local current_matches=false
        local matched_versions=()

        while IFS= read -r version; do matched_versions+=("$version"); done < <(llvm-match-versions "$version_expr" 2>/dev/null)

        for matched in "${matched_versions[@]}"; do
            if [ "$matched" = "$_ACTIVE_LLVM" ]; then
                current_matches=true
                break
            fi
        done

        if [ "$current_matches" = true ]; then
            log_expression_debug "Current version $_ACTIVE_LLVM satisfies expression '$version_expr'"
            QUIET_SUCCESS=$backup_quiet_success
            return 0
        else
            log_expression_debug "Current version $_ACTIVE_LLVM does not satisfy expression '$version_expr'"
            # Deactivate current and continue with new selection
            llvm-deactivate >/dev/null 2>&1
        fi
    fi

    # Find matching versions
    local matched_versions=()
    while IFS= read -r version; do matched_versions+=("$version"); done < <(llvm-match-versions "$version_expr" 2>/dev/null)

    if [ ${#matched_versions[@]} -eq 0 ]; then
        log_expression_debug "No versions match expression '$version_expr'"
        QUIET_SUCCESS=$backup_quiet_success
        return 1
    fi

    # Select the first (best) match
    local selected_version="${matched_versions[0]}"

    log_expression_debug "Auto-activating version: $selected_version (matched expression: $version_expr)"

    # Activate the selected version
    local previous_mode="${LLVMUP_AUTOACTIVATE_MODE:-}"
    local previous_root="${LLVMUP_AUTOACTIVATE_ROOT:-}"
    export LLVMUP_AUTOACTIVATE_MODE=1
    export LLVMUP_AUTOACTIVATE_ROOT="${LLVMUP_AUTOACTIVATE_ROOT:-$PWD}"

    # Activation must run in this shell (it exports the environment); capture its output in a file.
    local activate_log previous_active="${_ACTIVE_LLVM:-}"
    activate_log="$(mktemp "${TMPDIR:-/tmp}/llvmup-auto.XXXXXX" 2>/dev/null)" || activate_log=/dev/null
    if llvm-activate "$selected_version" >"$activate_log" 2>&1; then
        [ "$activate_log" = /dev/null ] || rm -f "$activate_log"
        # One short line, only when the automatic selection actually changed something (an unchanged
        # selection returns earlier), so the prompt hook stays quiet otherwise.
        if [ "$previous_active" != "$selected_version" ]; then
            QUIET_SUCCESS=${BACKUP_QUIET_SUCCESS:-0} log_success "Using $selected_version (from .llvmup-config: $version_expr)."
        fi
    else
        if [ -n "$previous_mode" ]; then
            export LLVMUP_AUTOACTIVATE_MODE="$previous_mode"
        else
            unset LLVMUP_AUTOACTIVATE_MODE
        fi
        if [ -n "$previous_root" ]; then
            export LLVMUP_AUTOACTIVATE_ROOT="$previous_root"
        else
            unset LLVMUP_AUTOACTIVATE_ROOT
        fi
        log_error "Failed to auto-activate $selected_version (from .llvmup-config: $version_expr)."
        # Keep the cause: the activation reports exactly what is wrong with the installation.
        [ "$activate_log" = /dev/null ] || { grep -i error "$activate_log" | head -2 >&2; rm -f "$activate_log"; }
        QUIET_SUCCESS=$backup_quiet_success
        return 1
    fi

    if [ -n "$previous_mode" ]; then
        export LLVMUP_AUTOACTIVATE_MODE="$previous_mode"
    else
        unset LLVMUP_AUTOACTIVATE_MODE
    fi
    if [ -n "$previous_root" ]; then
        export LLVMUP_AUTOACTIVATE_ROOT="$previous_root"
    else
        unset LLVMUP_AUTOACTIVATE_ROOT
    fi

    QUIET_SUCCESS=$backup_quiet_success
    return 0
}

# Test function for comprehensive expressions
llvm-test-expressions() {
    echo -e "${CYAN}Testing Comprehensive Version Expressions${NC}"
    echo "============================================="

    local test_expressions=(
        "latest"
        "oldest"
        "prebuilt"
        "source"
        "latest-prebuilt"
        "latest-source"
        ">=18.0.0"
        "~19.1"
        "18.*"
        "llvmorg-18.1.8"
    )

    # Disable debug output temporarily
    local original_verbose="$LLVM_VERBOSE"
    unset LLVM_VERBOSE

    for expr in "${test_expressions[@]}"; do
        echo ""
        echo -e "${BLUE}Expression: '$expr'${NC}"
        echo "----------------------------------------"

        local matches=()
        while IFS= read -r version; do matches+=("$version"); done < <(llvm-match-versions "$expr" 2>/dev/null)

        if [ ${#matches[@]} -gt 0 ]; then
            echo -e "${GREEN}Matches found:${NC}"
            for match in "${matches[@]}"; do
                local parsed=$(llvm-parse-version "$match" 2>/dev/null)
                local type="[Prebuilt]"
                if echo "$match" | grep -q "^source-"; then
                    type="[Source Build]"
                fi
                echo "   $match (v$parsed) $type"
            done
        else
            echo -e "${RED}No matches found${NC}"
        fi
    done

    # Restore verbose setting
    if [ -n "$original_verbose" ]; then
        export LLVM_VERBOSE="$original_verbose"
    fi

    echo ""
    echo -e "${GREEN}Expression testing completed!${NC}"
}

llvm-autoactivate() {
    # Não executar auto-ativação em modo de teste
    if [ -n "$LLVM_TEST_MODE" ]; then
        return 0
    fi

    # Não executar se LLVMUP_DISABLE_AUTOACTIVATE estiver definido
    if [ -n "$LLVMUP_DISABLE_AUTOACTIVATE" ]; then
        return 0
    fi

    local config_root=""
    config_root="$(llvm-find-config-root "$PWD")" || config_root=""

    if [ -z "$config_root" ]; then
        if [ "${_LLVMUP_AUTOACTIVATE_ACTIVE:-0}" = "1" ] && [ -n "${_ACTIVE_LLVM:-}" ]; then
            llvm-deactivate >/dev/null 2>&1 || true
        fi
        return 0
    fi

    BACKUP_QUIET_SUCCESS=$QUIET_SUCCESS
    QUIET_SUCCESS=1

    llvm-load-config-from-root "$config_root" >/dev/null 2>&1 || {
        QUIET_SUCCESS=$BACKUP_QUIET_SUCCESS
        return 0
    }

    if [ "$LLVM_CONFIG_AUTO_ACTIVATE" = "true" ]; then
        export LLVMUP_AUTOACTIVATE_ROOT="$config_root"
        llvm-autoactivate-enhanced || {
            QUIET_SUCCESS=$BACKUP_QUIET_SUCCESS
            return 0
        }
    elif [ "${_LLVMUP_AUTOACTIVATE_ACTIVE:-0}" = "1" ] && [ "${_LLVMUP_AUTOACTIVATE_ROOT:-}" != "$config_root" ]; then
        llvm-deactivate >/dev/null 2>&1 || true
    fi

    QUIET_SUCCESS=$BACKUP_QUIET_SUCCESS
}
