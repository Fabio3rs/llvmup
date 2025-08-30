#!/bin/bash
# llvmup-completion.sh - Bash completion for llvmup and LLVM functions
#
# This completion script supports:
#   llvmup [--from-source] [--verbose] [--quiet] [--help] [version]
#
# The script also extends the completion already defined in llvm-functions.sh
# for llvm-activate and llvm-vscode-activate functions.
#
# Note: For demonstration purposes, the tag list is obtained by a git ls-remote
# call on the official LLVM repository. In a production setting you might want to
# cache this result to improve performance.

_llvmup_completions() {
    local cur prev opts versions tags
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Handle flags and options
    case "$prev" in
        --from-source|--verbose|--quiet|--help)
            # After flags, we can complete with LLVM versions or more flags
            opts="--from-source --verbose --quiet --help"
            if [ -d "$HOME/.llvm/toolchains" ]; then
                versions=$(find "$HOME/.llvm/toolchains" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort)
                opts="$opts $versions"
            fi
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            return 0
            ;;
    esac

    # If the current word starts with '-', complete with flags
    if [[ "$cur" == -* ]]; then
        opts="--from-source --verbose --quiet --help"
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # For version completion, check if we already have flags
    local has_flags=0
    for word in "${COMP_WORDS[@]:1:$((COMP_CWORD-1))}"; do
        if [[ "$word" == --* ]]; then
            has_flags=1
            break
        fi
    done

    # If no version specified yet, complete with flags and available versions
    if [ -d "$HOME/.llvm/toolchains" ]; then
        versions=$(find "$HOME/.llvm/toolchains" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort)
        if [ $has_flags -eq 0 ]; then
            opts="--from-source --verbose --quiet --help $versions"
        else
            opts="$versions"
        fi
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    else
        # No installed versions, just complete with flags
        if [ $has_flags -eq 0 ]; then
            opts="--from-source --verbose --quiet --help"
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        fi
    fi
}

complete -F _llvmup_completions llvmup
