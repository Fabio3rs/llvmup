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

    llvm_path="$(command -v llvmup 2>/dev/null)"
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
            COMPREPLY=( $(compgen -W "--from-source --verbose --quiet --help" -- "$cur") )
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
            install|activate|deactivate|vscode-activate|status|list|disk-usage|default|config|help)
                command="${words[1]}"
                ;;
        esac
    fi

    case "$command" in
        activate|vscode-activate)
            _llvmup_collect_values _llvmup_get_activation_version_items "$cur"
            return 0
            ;;
        deactivate|status|list|help)
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
                    COMPREPLY=( $(compgen -W "set show" -- "$cur") )
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
                    ""|--from-source|--verbose|--quiet|--help|--default|--reconfigure|--disable-libc-wno-error)
                        ;;
                    -c|--cmake-flags|-n|--name|-p|--profile|--component)
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
