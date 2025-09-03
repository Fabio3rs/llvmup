#!/bin/bash
# llvmup-completion.sh - Enhanced Bash completion for llvmup and LLVM functions
#
# This completion script provides intelligent completion for:
#   - llvmup commands (install, default, config)
#   - All flags and options with context awareness
#   - Remote version fetching for installation
#   - Differentiated completion for --from-source vs prebuilt
#   - Local installed versions for activation
#   - Cached remote versions for better performance

# Cache directory for remote version lists
LLVM_COMPLETION_CACHE_DIR="$HOME/.cache/llvmup"
LLVM_REMOTE_CACHE_FILE="$LLVM_COMPLETION_CACHE_DIR/remote_versions.cache"
LLVM_CACHE_EXPIRY_HOURS=24

# Create cache directory if it doesn't exist
mkdir -p "$LLVM_COMPLETION_CACHE_DIR" 2>/dev/null

# Function to check if cache is still valid
_llvm_cache_valid() {
    if [ ! -f "$LLVM_REMOTE_CACHE_FILE" ]; then
        return 1
    fi

    local cache_age=$(( $(date +%s) - $(stat -c %Y "$LLVM_REMOTE_CACHE_FILE" 2>/dev/null || echo 0) ))
    local max_age=$(( LLVM_CACHE_EXPIRY_HOURS * 3600 ))

    [ $cache_age -lt $max_age ]
}

# Function to fetch remote LLVM versions (with caching)
_llvm_get_remote_versions() {
    # Check if we have valid cached data
    if _llvm_cache_valid && [ -s "$LLVM_REMOTE_CACHE_FILE" ]; then
        cat "$LLVM_REMOTE_CACHE_FILE"
        return 0
    fi

    # Fetch from GitHub API (with timeout for completion responsiveness)
    local versions
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        versions=$(timeout 5 curl -s "https://api.github.com/repos/llvm/llvm-project/releases" 2>/dev/null | \
                  jq -r '.[].tag_name' 2>/dev/null | \
                  grep -E '^llvmorg-[0-9]+\.[0-9]+\.[0-9]+$' | \
                  head -20)

        # Cache the results if successful
        if [ $? -eq 0 ] && [ -n "$versions" ]; then
            echo "$versions" > "$LLVM_REMOTE_CACHE_FILE" 2>/dev/null
            echo "$versions"
            return 0
        fi
    fi

    # Fallback: provide some common versions if remote fetch fails
    echo "llvmorg-21.1.0
llvmorg-20.1.8
llvmorg-19.1.0
llvmorg-18.1.8
llvmorg-17.0.6"
}

# Function to get locally installed versions
_llvm_get_local_versions() {
    local toolchains_dir="$HOME/.llvm/toolchains"
    if [ -d "$toolchains_dir" ]; then
        find "$toolchains_dir" -maxdepth 1 -type d -exec basename {} \; | \
        grep -v "^toolchains$" | sort
    fi
}

# Main completion function for llvmup
_llvmup_completions() {
    local cur prev words cword opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    # Determine the main command
    local command="install"  # default
    local cmd_pos=1

    if [ ${#words[@]} -gt 1 ]; then
        case "${words[1]}" in
            install|default|config|help)
                command="${words[1]}"
                cmd_pos=2
                ;;
        esac
    fi

    # Handle completion based on command and context
    case "$command" in
        default)
            case "$prev" in
                default)
                    COMPREPLY=( $(compgen -W "set show" -- "$cur") )
                    return 0
                    ;;
                set)
                    # Complete with locally installed versions only
                    local versions=$(_llvm_get_local_versions)
                    COMPREPLY=( $(compgen -W "$versions" -- "$cur") )
                    return 0
                    ;;
            esac
            ;;

        config)
            case "$prev" in
                config)
                    COMPREPLY=( $(compgen -W "init load" -- "$cur") )
                    return 0
                    ;;
            esac
            ;;

        help)
            # No further completion for help
            return 0
            ;;

        install)
            # Handle install command completion
            case "$prev" in
                -c|--cmake-flags)
                    # Complete common CMake flags
                    local cmake_flags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_TYPE=Debug -DLLVM_ENABLE_PROJECTS=clang -DLLVM_ENABLE_RUNTIMES=libcxx -DLLVM_TARGETS_TO_BUILD=X86"
                    COMPREPLY=( $(compgen -W "$cmake_flags" -- "$cur") )
                    return 0
                    ;;
                -n|--name)
                    # No specific completion for custom names
                    return 0
                    ;;
                -p|--profile)
                    COMPREPLY=( $(compgen -W "minimal full custom" -- "$cur") )
                    return 0
                    ;;
                --component)
                    local components="clang clang++ lld lldb compiler-rt libcxx libcxxabi llvm-ar llvm-nm opt"
                    COMPREPLY=( $(compgen -W "$components" -- "$cur") )
                    return 0
                    ;;
            esac

            # Check if --from-source flag is present
            local has_from_source=0
            local has_version=0
            local i

            for (( i=1; i<cword; i++ )); do
                case "${words[i]}" in
                    --from-source)
                        has_from_source=1
                        ;;
                    llvmorg-*|[0-9]*.*)
                        # Version-like argument found
                        has_version=1
                        ;;
                esac
            done

            # Complete with flags if current word starts with -
            if [[ "$cur" == -* ]]; then
                local all_flags="--from-source --verbose --quiet --help --cmake-flags --name --default --profile --component"
                COMPREPLY=( $(compgen -W "$all_flags" -- "$cur") )
                return 0
            fi

            # Version completion based on context
            if [ $has_version -eq 0 ]; then
                local versions

                if [ $has_from_source -eq 1 ]; then
                    # For --from-source, show remote versions (with source indication)
                    versions=$(_llvm_get_remote_versions | sed 's/^/📦 /')
                    # Add local versions with different marker
                    local local_versions=$(_llvm_get_local_versions)
                    if [ -n "$local_versions" ]; then
                        versions="$versions
$(echo "$local_versions" | sed 's/^/🏠 /')"
                    fi
                else
                    # For prebuilt, show remote versions (with prebuilt indication)
                    versions=$(_llvm_get_remote_versions | sed 's/^/⚡ /')
                    # Add local versions with different marker
                    local local_versions=$(_llvm_get_local_versions)
                    if [ -n "$local_versions" ]; then
                        versions="$versions
$(echo "$local_versions" | sed 's/^/🏠 /')"
                    fi
                fi

                # Clean up version names (remove emoji prefixes) for actual completion
                local clean_versions
                clean_versions=$(echo "$versions" | sed 's/^[^[:space:]]* //')

                # Combine with remaining flags if no flags yet
                local remaining_flags=""
                if [ $has_from_source -eq 0 ] && [[ ! "${words[*]}" =~ --from-source ]]; then
                    remaining_flags="--from-source"
                fi

                local combined_opts="$clean_versions $remaining_flags"
                COMPREPLY=( $(compgen -W "$combined_opts" -- "$cur") )
                return 0
            fi
            ;;
    esac

    # Fallback: show main commands if we're at the beginning
    if [ $cword -eq 1 ]; then
        if [[ "$cur" == -* ]]; then
            # Show flags if current word starts with dash
            COMPREPLY=( $(compgen -W "--from-source --verbose --quiet --help" -- "$cur") )
        else
            # Show commands or version-like input
            local main_commands="install default config help"
            local versions=""

            # Add remote versions for quick access
            if [ -z "$cur" ] || [[ "$cur" =~ ^[0-9] ]] || [[ "$cur" =~ ^llvmorg ]]; then
                versions=$(_llvm_get_remote_versions | head -10)
            fi

            local combined="$main_commands $versions"
            COMPREPLY=( $(compgen -W "$combined" -- "$cur") )
        fi
    fi
}

# Enhanced completion for llvm-activate and llvm-vscode-activate functions
_llvm_enhanced_completions() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Only complete with locally installed versions for activation
    local versions=$(_llvm_get_local_versions)

    if [ -n "$versions" ]; then
        # Add status indicators for installed versions
        local enhanced_versions=""
        local default_version=""

        # Check for default version
        if [ -L "$HOME/.llvm/default" ]; then
            default_version=$(basename "$(readlink "$HOME/.llvm/default" 2>/dev/null)" 2>/dev/null)
        fi

        # Check for currently active version
        local active_version="$_ACTIVE_LLVM"

        while IFS= read -r version; do
            local marker="📦"
            if [ "$version" = "$default_version" ]; then
                marker="⭐"  # Default version
            elif [ "$version" = "$active_version" ]; then
                marker="🟢"  # Currently active
            fi
            enhanced_versions="$enhanced_versions $marker $version"
        done <<< "$versions"

        # Clean completion (remove markers for actual completion)
        COMPREPLY=( $(compgen -W "$versions" -- "$cur") )
    else
        # No versions installed
        COMPREPLY=( $(compgen -W "# No LLVM versions installed. Run 'llvmup install' first." -- "") )
    fi
}

# Function to provide contextual help in completion
_llvm_show_completion_help() {
    local command="$1"
    echo >&2
    case "$command" in
        "llvmup-install-prebuilt")
            echo "💡 Available prebuilt versions (⚡ = remote, 🏠 = local):" >&2
            ;;
        "llvmup-install-source")
            echo "💡 Available source versions (📦 = remote, 🏠 = local):" >&2
            ;;
        "llvm-activate")
            echo "💡 Installed versions (⭐ = default, 🟢 = active, 📦 = available):" >&2
            ;;
    esac
}

# Register all completion functions
complete -F _llvmup_completions llvmup
complete -F _llvm_enhanced_completions llvm-activate
complete -F _llvm_enhanced_completions llvm-vscode-activate

# Additional completion for common LLVM commands when activated
_llvm_tool_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    case "${COMP_WORDS[0]}" in
        clang|clang++)
            # Basic C/C++ file completion
            COMPREPLY=( $(compgen -f -X '!*.@(c|cpp|cc|cxx|C|h|hpp|hxx)' -- "$cur") )
            ;;
        lldb)
            # Executable file completion
            COMPREPLY=( $(compgen -f -X '!*' -- "$cur") )
            ;;
    esac
}

# Conditionally register tool completions if tools are available
if command -v clang >/dev/null 2>&1 && [[ -n "$_ACTIVE_LLVM" ]]; then
    complete -F _llvm_tool_completions clang
    complete -F _llvm_tool_completions clang++
    complete -F _llvm_tool_completions lldb
fi

# Export functions for use by other scripts if needed
export -f _llvm_get_remote_versions
export -f _llvm_get_local_versions
export -f _llvm_cache_valid
