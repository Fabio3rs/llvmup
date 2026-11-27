#!/bin/bash
# llvmup-completion.sh - Bash completion for llvmup and LLVM functions

_llvmup_completion_resolve_helper() {
    local current_dir helper_path llvm_path
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    for helper_path in \
        "$current_dir/llvmup-completion-common.sh" \
        "${LLVMUP_INSTALL_DIR:-}/llvmup-completion-common.sh"
    do
        if [ -n "$helper_path" ] && [ -f "$helper_path" ]; then
            echo "$helper_path"
            return 0
        fi
    done

    # llvm-functions.sh defines a wrapper named llvmup. Search PATH for the
    # executable even when that function (or an alias) shadows it.
    llvm_path="$(type -P llvmup 2>/dev/null)"
    if [ -n "$llvm_path" ] && [ -f "$(dirname "$llvm_path")/llvmup-completion-common.sh" ]; then
        echo "$(dirname "$llvm_path")/llvmup-completion-common.sh"
        return 0
    fi

    return 1
}

LLVMUP_COMPLETION_COMMON_HELPER="$(_llvmup_completion_resolve_helper)"
if [ -n "$LLVMUP_COMPLETION_COMMON_HELPER" ]; then
    # shellcheck source=/dev/null
    source "$LLVMUP_COMPLETION_COMMON_HELPER"
fi

_llvm_cache_valid() { _llvmup_cache_valid "$@"; }

_llvmup_collect_values() {
    local generator="$1"
    local cur="$2"
    local values=()
    local seen=""
    local value group desc

    while IFS=$'\t' read -r value group desc; do
        [ -z "$value" ] && continue
        if [[ "$seen" == *$'\n'"$value"$'\n'* ]]; then
            continue
        fi
        seen="${seen}"$'\n'"$value"$'\n'
        values+=("$value")
    done < <("$generator")

    COMPREPLY=( $(compgen -W "${values[*]}" -- "$cur") )
}

_llvmup_collect_combined_values() {
    local cur="$1"
    shift
    local values=()
    local seen=""
    local generator value group desc

    for generator in "$@"; do
        while IFS=$'\t' read -r value group desc; do
            [ -z "$value" ] && continue
            if [[ "$seen" == *$'\n'"$value"$'\n'* ]]; then
                continue
            fi
            seen="${seen}"$'\n'"$value"$'\n'
            values+=("$value")
        done < <("$generator")
    done

    COMPREPLY=( $(compgen -W "${values[*]}" -- "$cur") )
}

_llvmup_print_install_hint() {
    local local_preview remote_preview

    if [ -n "${COMP_TYPE:-}" ] && [ "$COMP_CWORD" -ge 2 ] && [ -z "${COMP_WORDS[COMP_CWORD]}" ]; then
        local_preview="$(_llvmup_get_local_versions | head -3 | tr '\n' ' ')"
        remote_preview="$(_llvmup_get_remote_versions | head -3 | tr '\n' ' ')"
        echo >&2
        echo "Expressions: latest latest-prebuilt >=18.0.0 18.*" >&2
        [ -n "$local_preview" ] && echo "Installed locally: $local_preview" >&2
        [ -n "$remote_preview" ] && echo "Available remotely: $remote_preview" >&2
    fi
}

_llvmup_completions() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    if [ "$cword" -eq 1 ]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "--from-source --verify --verbose --quiet --version --help" -- "$cur") )
        else
            _llvmup_collect_combined_values "$cur" \
                _llvmup_get_main_command_items \
                _llvmup_get_expression_items \
                _llvmup_get_remote_version_items
        fi
        return 0
    fi

    local command="install"
    if [ ${#words[@]} -gt 1 ]; then
        case "${words[1]}" in
            doctor|install|activate|deactivate|env|resolve|vscode-activate|status|list|remove|disk-usage|default|config|help|\
            use|run|which|where|provides|info|alias|pin|sync|update|pick|toolchain|shell|cmake-toolchain)
                command="${words[1]}"
                ;;
        esac
    fi

    # Options shared by the provider-aware commands.
    case "$prev" in
        --provider) _llvmup_collect_values _llvmup_get_provider_items "$cur"; return 0 ;;
        --compiler) _llvmup_collect_values _llvmup_get_compiler_items "$cur"; return 0 ;;
        --target) _llvmup_collect_values _llvmup_get_target_items "$cur"; return 0 ;;
        --crt) _llvmup_collect_values _llvmup_get_crt_items "$cur"; return 0 ;;
        --extractor) _llvmup_collect_values _llvmup_get_extractor_items "$cur"; return 0 ;;
        --toolchain) _llvmup_collect_values _llvmup_get_toolchain_items "$cur"; return 0 ;;
        --output|-o) COMPREPLY=( $(compgen -f -- "$cur") ); return 0 ;;
    esac

    case "$command" in
        use|run|which|where|info|shell|cmake-toolchain|update)
            local w
            for w in "${words[@]:2:cword-2}"; do [ "$w" != -- ] || { COMPREPLY=( $(compgen -c -- "$cur") ); return 0; }; done
            if [[ "$cur" == -* ]]; then
                case "$command" in
                    use) _llvmup_collect_values _llvmup_get_use_flag_items "$cur" ;;
                    *) _llvmup_collect_values _llvmup_get_run_flag_items "$cur" ;;
                esac
            elif [ "$command" = which ] && [ "$cword" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "clang clang++ clangd clang-format clang-tidy lld ld.lld lld-link llvm-ar llvm-config gcc g++ gdb lldb cmake ninja windres" -- "$cur") )
            else
                _llvmup_collect_combined_values "$cur" _llvmup_get_toolchain_items _llvmup_get_provider_selector_items
            fi
            return 0
            ;;
        provides)
            COMPREPLY=( $(compgen -W "clang clang++ clangd lld ld.lld lld-link llvm-config libclang gcc g++ gdb lldb windres cmake ninja" -- "$cur") )
            return 0
            ;;
        alias)
            case "$cword" in
                2) COMPREPLY=( $(compgen -W "set list show remove" -- "$cur") ) ;;
                3) case "$prev" in show|remove) _llvmup_collect_values _llvmup_get_alias_items "$cur" ;; esac ;;
                4) _llvmup_collect_values _llvmup_get_toolchain_items "$cur" ;;
            esac
            return 0
            ;;
        toolchain)
            case "$cword" in
                2) COMPREPLY=( $(compgen -W "link unlink list" -- "$cur") ) ;;
                3) [ "$prev" = unlink ] && COMPREPLY=( $(compgen -W "$(_llvmup_get_external_names)" -- "$cur") ) ;;
                4) COMPREPLY=( $(compgen -d -- "$cur") ) ;;
            esac
            return 0
            ;;
        pin)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--current --fuzzy --crt --target --compiler" -- "$cur") )
            else
                _llvmup_collect_combined_values "$cur" _llvmup_get_toolchain_items _llvmup_get_provider_selector_items
            fi
            return 0
            ;;
        sync)
            COMPREPLY=( $(compgen -W "--locked --verify" -- "$cur") )
            return 0
            ;;
        pick)
            return 0
            ;;
    esac

    case "$command" in
        activate|vscode-activate)
            _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
            return 0
            ;;
        env)
            case "$prev" in
                env)
                    COMPREPLY=( $(compgen -W "--config --format" -- "$cur") )
                    if [ -n "${COMPREPLY[*]}" ]; then
                        return 0
                    fi
                    _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
                    return 0
                    ;;
                --format)
                    COMPREPLY=( $(compgen -W "shell github json" -- "$cur") )
                    return 0
                    ;;
            esac

            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--config --format" -- "$cur") )
                return 0
            fi

            _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
            return 0
            ;;
        resolve)
            case "$prev" in
                --format)
                    COMPREPLY=( $(compgen -W "tag json" -- "$cur") )
                    return 0
                    ;;
                --platform)
                    COMPREPLY=( $(compgen -W "Linux macOS" -- "$cur") )
                    return 0
                    ;;
                --arch)
                    COMPREPLY=( $(compgen -W "X64 ARM64" -- "$cur") )
                    return 0
                    ;;
            esac
            if [[ "$cur" == -* ]]; then
                _llvmup_collect_values _llvmup_get_resolve_flag_items "$cur"
            else
                _llvmup_collect_combined_values "$cur" \
                    _llvmup_get_expression_items \
                    _llvmup_get_range_template_items \
                    _llvmup_get_remote_version_items
            fi
            return 0
            ;;
        doctor)
            COMPREPLY=( $(compgen -W "--verbose --deep --network --json --help" -- "$cur") )
            return 0
            ;;
        help)
            # 'llvmup help <command>' completes the commands that have their own help.
            if [ "$COMP_CWORD" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "install use run list status config sync pin default alias remove update env deactivate which where provides resolve doctor toolchain shell pick info disk-usage cmake-toolchain vscode-activate" -- "$cur") )
            fi
            return 0
            ;;
        deactivate|status)
            return 0
            ;;
        list)
            if [[ "$cur" == -* ]]; then
                _llvmup_collect_values _llvmup_get_list_flag_items "$cur"
            fi
            return 0
            ;;
        remove)
            if [[ "$cur" == -* ]]; then
                _llvmup_collect_values _llvmup_get_remove_flag_items "$cur"
            else
                _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
            fi
            return 0
            ;;
        disk-usage)
            if [[ "$cur" == -* ]]; then
                _llvmup_collect_values _llvmup_get_disk_usage_flag_items "$cur"
            fi
            return 0
            ;;
        default)
            case "$prev" in
                default)
                    COMPREPLY=( $(compgen -W "set show unset" -- "$cur") )
                    return 0
                    ;;
                set)
                    _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
                    return 0
                    ;;
            esac
            ;;
        config)
            if [ "$prev" = "config" ]; then
                _llvmup_collect_values _llvmup_get_config_action_items "$cur"
                return 0
            fi
            ;;
        help)
            return 0
            ;;
        install)
            case "$prev" in
                --verify)
                    COMPREPLY=( $(compgen -W "warn strict skip" -- "$cur") )
                    return 0
                    ;;
                -c|--cmake-flags)
                    _llvmup_collect_values _llvmup_get_cmake_flag_items "$cur"
                    return 0
                    ;;
                -n|--name)
                    return 0
                    ;;
                -p|--profile)
                    _llvmup_collect_values _llvmup_get_profile_items "$cur"
                    return 0
                    ;;
                --component)
                    _llvmup_collect_values _llvmup_get_component_items "$cur"
                    return 0
                    ;;
            esac

            local has_target=0
            local i
            for (( i=2; i<cword; i++ )); do
                case "${words[i]}" in
                    ""|--from-source|--verbose|--quiet|--help|--default|--reconfigure|--disable-libc-wno-error|--list-only)
                        ;;
                    -c|--cmake-flags|-n|--name|-p|--profile|--component|--verify)
                        ((i++))
                        ;;
                    -*)
                        ;;
                    *)
                        has_target=1
                        ;;
                esac
            done

            if [[ "$cur" == -* ]]; then
                _llvmup_collect_values _llvmup_get_install_flag_items "$cur"
                return 0
            fi

            if [ "$has_target" -eq 0 ]; then
                _llvmup_collect_combined_values "$cur" \
                    _llvmup_get_provider_selector_items \
                    _llvmup_get_expression_items \
                    _llvmup_get_range_template_items \
                    _llvmup_get_local_version_items \
                    _llvmup_get_remote_version_items \
                    _llvmup_get_install_flag_items
                _llvmup_print_install_hint
                return 0
            fi
            ;;
    esac

}

_llvm_enhanced_completions() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
}

_llvm_tool_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    case "${COMP_WORDS[0]}" in
        clang|clang++)
            COMPREPLY=( $(compgen -f -X '!*.@(c|cpp|cc|cxx|C|h|hpp|hxx)' -- "$cur") )
            ;;
        lldb)
            COMPREPLY=( $(compgen -f -X '!*' -- "$cur") )
            ;;
    esac
}

complete -F _llvmup_completions llvmup
complete -F _llvm_enhanced_completions llvm-activate
complete -F _llvm_enhanced_completions llvm-vscode-activate

if command -v clang >/dev/null 2>&1 && [[ -n "$_ACTIVE_LLVM" ]]; then
    complete -F _llvm_tool_completions clang
    complete -F _llvm_tool_completions clang++
    complete -F _llvm_tool_completions lldb
fi
