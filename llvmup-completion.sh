#!/bin/bash
# llvmup-completion.sh - Bash completion for llvmup
#
# This completion script supports the following subcommands:
#   install [--from-source] <tag> : completes the LLVM release tags.
#   activate <tag>               : completes installed LLVM versions (from ~/.llvm/toolchains)
#   build <tag>                  : equivalent to "install --from-source <tag>"
#   deactivate, help             : complete these general options.
#
# Note: For demonstration purposes, the tag list is obtained by a git ls-remote
# call on the official LLVM repository. In a production setting you might want to
# cache this result to improve performance.

_llvmup_completions() {
    local cur prev subcmd opts tags
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcmd="${COMP_WORDS[1]}"

    case "$subcmd" in
        install)
            if [[ "${COMP_WORDS[2]}" == "--from-source" ]]; then
                if [ $COMP_CWORD -eq 3 ]; then
                    # Complete tag list for source build.
                    tags=$(git ls-remote --tags "https://github.com/llvm/llvm-project.git" \
                           | grep 'refs/tags/llvmorg-' | sed 's/.*refs\/tags\///; s/\^{}//' | sort -V | uniq)
                    COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
                    return 0
                fi
            else
                if [ $COMP_CWORD -eq 2 ]; then
                    # Complete prebuilt tag list, prefixed by --from-source.
                    tags=$(git ls-remote --tags "https://github.com/llvm/llvm-project.git" \
                           | grep 'refs/tags/llvmorg-' | sed 's/.*refs\/tags\///; s/\^{}//' | sort -V | uniq)
                    COMPREPLY=( $(compgen -W "--from-source $tags" -- "$cur") )
                    return 0
                fi
            fi
            ;;
        activate)
            if [ $COMP_CWORD -eq 2 ]; then
                # Complete with the list of installed LLVM versions (directories in ~/.llvm/toolchains)
                if [ -d "$HOME/.llvm/toolchains" ]; then
                    opts=$(ls "$HOME/.llvm/toolchains")
                    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
                fi
                return 0
            fi
            ;;
        deactivate|help)
            opts="install activate deactivate build help"
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            return 0
            ;;
        build)
            # build is equivalent to "install --from-source"
            if [ $COMP_CWORD -eq 2 ]; then
                tags=$(git ls-remote --tags "https://github.com/llvm/llvm-project.git" \
                       | grep 'refs/tags/llvmorg-' | sed 's/.*refs\/tags\///; s/\^{}//' | sort -V | uniq)
                COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
                return 0
            fi
            ;;
        *)
            opts="install activate deactivate build help"
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            return 0
            ;;
    esac
}

complete -F _llvmup_completions llvmup
