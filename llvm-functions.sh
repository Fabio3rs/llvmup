#!/bin/bash
# llvm-functions.sh: Bash functions for LLVM version management
# This file should be sourced in the user's shell profile (.bashrc, .profile, etc.)
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

# Log error messages (always shown)
log_error() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo -e "${RED}Error: $*${NC}" >&2
}

# Log warning messages (always shown)
log_warn() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
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

llvmup() {
    local runtime_script
    runtime_script="$(llvm-find-runtime-script llvmup)" || runtime_script=""

    case "${1:-}" in
        activate)
            shift
            llvm-activate "$@"
            return $?
            ;;
        deactivate)
            shift
            llvm-deactivate "$@"
            return $?
            ;;
        vscode-activate)
            shift
            llvm-vscode-activate "$@"
            return $?
            ;;
        status)
            shift
            llvm-status "$@"
            return $?
            ;;
        list)
            shift
            llvm-list "$@"
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
                    llvm-config-load >/dev/null && llvm-config-apply "$@"
                    ;;
                activate)
                    llvm-config-load >/dev/null && llvm-config-activate "$@"
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
                *)
                    log_error "Unknown default subcommand: $default_subcommand"
                    log_info "Available subcommands: set, show"
                    return 1
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
        echo "╭─ LLVM Activation Help ─────────────────────────────────────╮"
        echo "│ Usage: llvm-activate <version>                            │"
        echo "│                                                            │"
        echo "│ Examples:                                                  │"
        echo "│   llvm-activate 18.1.8     # Activate specific version    │"
        echo "│   llvm-activate 19.1.0     # Activate another version     │"
        echo "│                                                            │"
        echo "│ What this does:                                            │"
        echo "│ • Sets PATH to use LLVM tools (clang, clang++, etc.)      │"
        echo "│ • Updates CC, CXX, and LD environment variables           │"
        echo "│ • Modifies shell prompt to show active LLVM version       │"
        echo "│                                                            │"
        echo "│ To deactivate: llvm-deactivate                            │"
        echo "│ To check status: llvm-status                              │"
        echo "╰────────────────────────────────────────────────────────────╯"
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
    local script_path
    script_path="$(llvm-find-runtime-script llvm-deactivate)" || script_path=""

    if [ -f "$script_path" ]; then
        log_progress "Deactivating LLVM environment..."
        source "$script_path"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            unset _LLVMUP_AUTOACTIVATE_ACTIVE
            unset _LLVMUP_AUTOACTIVATE_ROOT
            log_success "LLVM environment successfully deactivated"
            log_tip "Your shell prompt and environment variables have been restored"
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
        echo "╭─ LLVM VSCode Integration Help ─────────────────────────────╮"
        echo "│ Usage: llvm-vscode-activate <version>                     │"
        echo "│                                                            │"
        echo "│ Examples:                                                  │"
        echo "│   llvm-vscode-activate 18.1.8  # Setup LLVM for VSCode    │"
        echo "│                                                            │"
        echo "│ What this does:                                            │"
        echo "│ • Updates .vscode/settings.json with LLVM paths           │"
        echo "│ • Configures clangd language server                       │"
        echo "│ • Sets up CMake integration with LLVM                     │"
        echo "│ • Configures LLDB debugger paths                          │"
        echo "│                                                            │"
        echo "│ Note: Must be run from your VSCode project root!          │"
        echo "╰────────────────────────────────────────────────────────────╯"
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
    echo "╭─ LLVM Environment Status ──────────────────────────────────╮"
    if [ -n "$_ACTIVE_LLVM" ]; then
        echo -e "│ ${GREEN}Status: ACTIVE${NC}                                          │"
        echo "│ Version: $_ACTIVE_LLVM                                    │"
        if [ -n "$_ACTIVE_LLVM_PATH" ]; then
            echo "│ Path: $_ACTIVE_LLVM_PATH"
        fi
        echo "│                                                            │"
        echo "│ Available tools:                                           │"
        local llvm_path="$_ACTIVE_LLVM_PATH/bin"
        if [ -d "$llvm_path" ]; then
            if [ -x "$llvm_path/clang" ]; then
                echo "│   • clang (C compiler)                                 │"
            fi
            if [ -x "$llvm_path/clang++" ]; then
                echo "│   • clang++ (C++ compiler)                             │"
            fi
            if [ -x "$llvm_path/clangd" ]; then
                echo "│   • clangd (Language Server)                           │"
            fi
            if [ -x "$llvm_path/lldb" ]; then
                echo "│   • lldb (Debugger)                                    │"
            fi
        fi
        echo "│                                                            │"
        echo -e "│ ${BLUE}To deactivate: llvm-deactivate${NC}                         │"
    else
        echo -e "│ ${RED}Status: INACTIVE${NC}                                        │"
        echo "│                                                            │"
        echo -e "│ ${BLUE}To activate a version: llvm-activate <version>${NC}         │"
        echo "│ To see available versions: llvm-list                      │"
        echo "│ To install new versions: llvmup                           │"
    fi
    echo "╰────────────────────────────────────────────────────────────╯"
}

# Function to list installed LLVM versions
llvm-list() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"

    echo "╭─ Installed LLVM Versions ──────────────────────────────────╮"
    if [ ! -d "$toolchains_dir" ]; then
        echo -e "│ ${RED}No LLVM toolchains found${NC}                                │"
        echo "│                                                            │"
        echo -e "│ ${BLUE}To install LLVM versions:${NC}                               │"
        echo "│   • llvmup                    # Install prebuilt version   │"
        echo "│   • llvmup --from-source      # Build from source          │"
        echo "│   • llvmup 18.1.8            # Install specific version    │"
        echo "╰────────────────────────────────────────────────────────────╯"
        return 0
    fi

    local has_versions=false
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            has_versions=true
            local version=$(basename "$dir")
            if [ -n "$_ACTIVE_LLVM" ] && [ "$version" = "$_ACTIVE_LLVM" ]; then
                echo -e "│ ${GREEN}$version (ACTIVE)${NC}"
            else
                echo "│ $version"
            fi
        fi
    done

    if [ "$has_versions" = false ]; then
        echo -e "│ ${RED}No valid LLVM installations found${NC}                       │"
    fi

    echo "│                                                            │"
    echo -e "│ ${BLUE}Usage:${NC}                                                   │"
    echo "│   • llvm-activate <version>   # Activate a version         │"
    echo "│   • llvm-status              # Check current status        │"
    echo "│   • llvmup                   # Install more versions       │"
    echo "╰────────────────────────────────────────────────────────────╯"
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
llvm-help() {
    echo "╭─ LLVM Manager - Complete Usage Guide ──────────────────────╮"
    echo "│                                                            │"
    echo -e "│ ${GREEN}INSTALLATION COMMANDS:${NC}                                  │"
    echo "│   llvmup install                  # Install latest prebuilt│"
    echo "│   llvmup install 18.1.8          # Install specific version│"
    echo "│   llvmup resolve latest          # Resolve latest stable tag│"
    echo "│   llvmup install --from-source    # Build from source      │"
    echo "│   llvmup install --name my-llvm   # Custom installation name│"
    echo "│   llvmup install --default        # Set as default version │"
    echo "│   llvmup install --profile minimal # Use minimal profile   │"
    echo "│   llvmup install --cmake-flags '-DCMAKE_BUILD_TYPE=Debug'  │"
    echo "│                                                            │"
    echo -e "│ ${CYAN}VERSION MANAGEMENT:${NC}                                      │"
    echo "│   llvm-activate <version>     # Activate LLVM version      │"
    echo "│   llvm-deactivate             # Deactivate current version │"
    echo "│   llvm-status                 # Show current status        │"
    echo "│   llvm-list                   # List installed versions    │"
    echo "│   llvm-disk-usage            # Show disk usage by install │"
    echo "│   llvmup default set <ver>    # Set default version        │"
    echo "│   llvmup default show         # Show current default       │"
    echo "│                                                            │"
    echo -e "│ ${BLUE}VERSION PARSING & UTILITIES:${NC}                             │"
    echo "│   llvm-parse-version <ver>    # Parse version string       │"
    echo "│   llvm-get-versions [format]  # List versions (list/simple/json)│"
    echo "│   llvm-version-exists <ver>   # Check if version exists    │"
    echo "│   llvm-get-active-version     # Get currently active version│"
    echo "│   llvm-version-compare <v1> <v2> # Compare two versions    │"
    echo "│   llvm-get-latest-version     # Find latest installed version│"
    echo "│   llvm-match-versions <expr>  # Match versions by expression│"
    echo "│   llvmup env --format github <ver> # Export to GitHub Actions│"
    echo "│   llvm-test-expressions       # Test expression matching   │"
    echo "│                                                            │"
    echo -e "│ ${YELLOW}VERBOSITY CONTROLS:${NC}                                      │"
    echo "│   llvm-verbose-on/off         # Toggle general verbose mode │"
    echo "│   llvm-expression-verbose-on/off # Toggle expression verbose│"
    echo "│   llvm-expression-debug-on/off   # Toggle expression debug  │"
    echo "│                                                            │"
    echo -e "│ ${BLUE}VERSION EXPRESSIONS (for auto-activate):${NC}                 │"
    echo "│   • Selectors: latest, oldest, newest, earliest            │"
    echo "│   • Type filters: prebuilt, source, latest-prebuilt        │"
    echo "│   • Ranges: >=18.0.0, <=19.1.0, ~19.1, 18.*              │"
    echo "│   • Specific: llvmorg-18.1.8, source-llvmorg-20.1.0       │"
    echo "│                                                            │"
    echo -e "│ ${GREEN}DEVELOPMENT INTEGRATION:${NC}                                 │"
    echo "│   llvm-vscode-activate <ver>  # Setup VSCode integration   │"
    echo "│   llvm-config-init            # Initialize .llvmup-config  │"
    echo "│   llvm-config-load            # Load project config        │"
    echo "│   llvm-config-apply           # Install from config        │"
    echo "│   llvm-config-activate        # Activate configured version│"
    echo "│                                                            │"
    echo -e "│ ${CYAN}AVAILABLE TOOLS AFTER ACTIVATION:${NC}                       │"
    echo "│   • clang/clang++    # C/C++ compilers                     │"
    echo "│   • ld.lld          # LLVM linker                          │"
    echo "│   • lldb            # LLVM debugger                        │"
    echo "│   • clangd          # Language server for IDEs             │"
    echo "│   • llvm-ar         # Archiver                             │"
    echo "│   • llvm-nm         # Symbol table dumper                  │"
    echo "│   • opt             # LLVM optimizer                       │"
    echo "│                                                            │"
    echo -e "│ ${BLUE}PROJECT CONFIGURATION (.llvmup-config):${NC}                  │"
    echo "│   [version]                                                │"
    echo "│   default = \"llvmorg-21.1.0\"                              │"
    echo "│   [build]                                                  │"
    echo "│   name = \"21.1.0-debug\"                                   │"
    echo "│   cmake_flags = [\"-DCMAKE_BUILD_TYPE=Debug\"]              │"
    echo "│   [profile]                                                │"
    echo "│   type = \"full\"                                           │"
    echo "│                                                            │"
    echo -e "│ ${BLUE}TIPS:${NC}                                                    │"
    echo "│   • Use TAB completion for version names                   │"
    echo "│   • Check llvm-status after activation                     │"
    echo "│   • Your PS1 prompt shows active LLVM version              │"
    echo "│   • Environment is isolated per terminal session           │"
    echo "│   • Use .llvmup-config for project-specific settings       │"
    echo "│                                                            │"
    echo -e "│ ${CYAN}MORE INFO: https://github.com/Fabio3rs/llvmup${NC}           │"
    echo "╰────────────────────────────────────────────────────────────╯"
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
            mapfile -t installed_versions < <(ls -1 "$toolchains_dir" 2>/dev/null | grep -v "^$")
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
            read -p "Build profile [minimal/full/custom]: " profile
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
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=[[:space:]]*\[ ]]; then
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
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
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

llvm-print-env-exports() {
    local version="$1"
    local format="${2:-shell}"
    local llvm_dir

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

    case "$format" in
        shell)
            printf 'export PATH=%q\n' "$llvm_dir/bin:$PATH"
            printf 'export CC=%q\n' "$llvm_dir/bin/clang"
            printf 'export CXX=%q\n' "$llvm_dir/bin/clang++"
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

llvm-register-autoactivate-hooks() {
    if [ -n "$LLVMUP_DISABLE_AUTOACTIVATE" ] || [ -n "$LLVM_TEST_MODE" ]; then
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
            add-zsh-hook precmd __llvmup_autoactivate_hook 2>/dev/null || true
        fi
    fi
}

__llvmup_autoactivate_hook() {
    llvm-autoactivate 2>/dev/null || true
}

# Function to apply loaded .llvmup-config settings
llvm-config-apply() {
    # Check if config is loaded
    if [ -z "$LLVM_CONFIG_VERSION" ]; then
        log_error "No configuration loaded. Run 'llvm-config-load' first"
        return 1
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

llvm-release-asset-pattern() {
    local platform="$1"
    local architecture="$2"

    case "$platform:$architecture" in
        Linux:X64) printf '(Linux-X64|x86_64-linux-gnu[^/]*)\\.tar\\.xz$\n' ;;
        Linux:ARM64) printf '(Linux-ARM64|aarch64-linux-gnu[^/]*)\\.tar\\.xz$\n' ;;
        macOS:ARM64) printf '(macOS-ARM64|arm64-apple-darwin[^/]*)\\.tar\\.xz$\n' ;;
        *)
            log_error "No pre-built LLVM archive mapping for $platform $architecture"
            return 1
            ;;
    esac
}

# Resolve a remote, stable LLVM release and its platform asset. The JSON output
# is shared by the CLI installer and GitHub Action so both use identical rules.
llvm-resolve-remote-release() {
    local expression="${1:-latest}"
    local platform
    local architecture
    local parsed_expression
    local release_json=""
    local selected_version=""
    local releases_json=""
    local asset_pattern
    local asset_json
    local asset_name
    local signature_url
    local checksum_url
    local attestation_url

    command -v curl >/dev/null 2>&1 || {
        log_error "The 'curl' command is required to resolve LLVM releases"
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        log_error "The 'jq' command is required to resolve LLVM releases"
        return 1
    }

    platform="$(llvm-detect-platform "${2:-}")" || return 1
    architecture="$(llvm-detect-architecture "${3:-}")" || return 1
    parsed_expression="$(llvm-parse-version-expression "$expression" 2>/dev/null)" || {
        log_error "Invalid version expression: $expression"
        return 1
    }

    case "$parsed_expression" in
        selector:latest|type:prebuilt|type:prebuilt,selector:latest)
            release_json="$(llvm-github-api-request /latest)" || {
                log_error "Failed to resolve the latest stable LLVM release"
                llvm-print-remote-release-candidates
                return 1
            }
            ;;
        type:source*|*type:source*)
            log_error "Source-only expressions cannot select a pre-built release"
            return 1
            ;;
        specific:*)
            local specific_version="${parsed_expression#specific:}"
            case "$(printf '%s' "$specific_version" | tr '[:upper:]' '[:lower:]')" in
                source-*)
                    log_error "Source installation identifiers cannot select a pre-built release: $specific_version"
                    return 1
                    ;;
            esac
            selected_version="$(llvm-normalize-version-id "$specific_version")" || return 1
            release_json="$(llvm-github-api-request "/tags/$selected_version")" || {
                log_error "LLVM release not found: $selected_version"
                llvm-print-remote-release-candidates
                return 1
            }
            ;;
        *)
            releases_json="$(llvm-get-remote-stable-releases)" || return 1
            local remote_versions=()
            local matching_versions=()
            mapfile -t remote_versions < <(jq -r '.[].tag_name' <<< "$releases_json")
            mapfile -t matching_versions < <(llvm-match-version-list "$expression" "${remote_versions[@]}" 2>/dev/null)

            if [ ${#matching_versions[@]} -eq 0 ]; then
                log_error "No stable remote LLVM release matches: $expression"
                llvm-print-remote-release-candidates "$releases_json"
                return 1
            fi

            selected_version="${matching_versions[0]}"
            local candidate
            for candidate in "${matching_versions[@]:1}"; do
                if llvm-version-compare "$candidate" "$selected_version" 2>/dev/null; then
                    selected_version="$candidate"
                fi
            done
            release_json="$(jq -c --arg tag "$selected_version" '[.[] | select(.tag_name == $tag)][0] // empty' <<< "$releases_json")"
            ;;
    esac

    if [ -z "$release_json" ] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$release_json"; then
        log_error "No release metadata found for expression: $expression"
        llvm-print-remote-release-candidates "$releases_json"
        return 1
    fi

    if [ "$(jq -r '.draft // false' <<< "$release_json")" = "true" ] ||
       [ "$(jq -r '.prerelease // false' <<< "$release_json")" = "true" ]; then
        log_error "Resolved LLVM release is not stable: $(jq -r '.tag_name' <<< "$release_json")"
        llvm-print-remote-release-candidates "$releases_json"
        return 1
    fi

    if ! jq -e '.tag_name | test("^llvmorg-[0-9]+\\.[0-9]+\\.[0-9]+$")' >/dev/null 2>&1 <<< "$release_json"; then
        log_error "Resolved LLVM release does not use a stable release tag: $(jq -r '.tag_name' <<< "$release_json")"
        llvm-print-remote-release-candidates "$releases_json"
        return 1
    fi

    asset_pattern="$(llvm-release-asset-pattern "$platform" "$architecture")" || return 1
    asset_json="$(jq -c --arg pattern "$asset_pattern" '
        [.assets[]?
          | select((.state // "uploaded") == "uploaded")
          | select(.name | test($pattern; "i"))][0] // empty
    ' <<< "$release_json")"

    if [ -z "$asset_json" ] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$asset_json"; then
        log_error "No pre-built LLVM archive found for $platform $architecture in $(jq -r '.tag_name' <<< "$release_json")"
        return 1
    fi

    asset_name="$(jq -r '.name' <<< "$asset_json")"
    signature_url="$(jq -r --arg name "$asset_name" '[.assets[]? | select(.name == ($name + ".sig"))][0].browser_download_url // ""' <<< "$release_json")"
    checksum_url="$(jq -r --arg name "$asset_name" '[.assets[]? | select(.name == ($name + ".sha256") or .name == ($name + ".sha256sum") or .name == ($name + ".sha256.txt") or .name == ($name + ".sha256sum.txt"))][0].browser_download_url // ""' <<< "$release_json")"
    attestation_url="$(jq -r --arg name "$asset_name" '[.assets[]? | select(.name == ($name + ".jsonl"))][0].browser_download_url // ""' <<< "$release_json")"

    jq -cn \
        --arg version "$(jq -r '.tag_name' <<< "$release_json")" \
        --arg asset_name "$asset_name" \
        --arg asset_url "$(jq -r '.browser_download_url' <<< "$asset_json")" \
        --arg asset_digest "$(jq -r '.digest // ""' <<< "$asset_json")" \
        --arg asset_id "$(jq -r '.id // ""' <<< "$asset_json")" \
        --arg signature_url "$signature_url" \
        --arg checksum_url "$checksum_url" \
        --arg attestation_url "$attestation_url" \
        --arg platform "$platform" \
        --arg architecture "$architecture" \
        '{version: $version, asset_name: $asset_name, asset_url: $asset_url,
          asset_digest: $asset_digest, asset_id: $asset_id,
          signature_url: $signature_url, checksum_url: $checksum_url,
          attestation_url: $attestation_url, platform: $platform,
          architecture: $architecture}'
}

# Resolve the public verification policy while preserving the legacy environment
# variables used by older llvmup releases. An explicit argument always wins.
llvm-resolve-verification-policy() {
    local requested="${1:-}"
    local skip_set=0
    local require_set=0

    case "${LLVMUP_SKIP_VERIFY:-}" in 1|true|TRUE) skip_set=1 ;; esac
    case "${LLVMUP_REQUIRE_VERIFY:-}" in 1|true|TRUE) require_set=1 ;; esac

    if [ -n "$requested" ]; then
        :
    elif [ -n "${LLVMUP_VERIFY_POLICY:-}" ]; then
        requested="$LLVMUP_VERIFY_POLICY"
    elif [ "$skip_set" -eq 1 ] && [ "$require_set" -eq 1 ]; then
        log_error "LLVMUP_SKIP_VERIFY and LLVMUP_REQUIRE_VERIFY cannot both be enabled"
        return 1
    elif [ "$skip_set" -eq 1 ]; then
        requested="skip"
    elif [ "$require_set" -eq 1 ]; then
        requested="strict"
    else
        requested="warn"
    fi

    requested="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
    case "$requested" in
        warn|strict|skip) printf '%s\n' "$requested" ;;
        *)
            log_error "Invalid verification policy: $requested (expected warn, strict, or skip)"
            return 1
            ;;
    esac
}

llvm-compute-sha256() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        return 127
    fi
}

# Reset the result globals populated by llvm-verify-release-asset.
llvm-reset-verification-result() {
    LLVMUP_VERIFICATION_CHECKSUM="not-provided"
    LLVMUP_VERIFICATION_GPG="not-provided"
    LLVMUP_VERIFICATION_ATTESTATION="not-provided"
    LLVMUP_VERIFICATION_METHODS=""
    LLVMUP_VERIFICATION_GPG_FINGERPRINT=""
}

llvm-verification-add-method() {
    local method="$1"
    if [ -z "$LLVMUP_VERIFICATION_METHODS" ]; then
        LLVMUP_VERIFICATION_METHODS="$method"
    else
        LLVMUP_VERIFICATION_METHODS="$LLVMUP_VERIFICATION_METHODS+$method"
    fi
}

llvm-download-verification-material() {
    local url="$1"
    local destination="$2"

    curl --fail --silent --show-error --location \
        --connect-timeout 30 --max-time 300 --retry 2 \
        "$url" -o "$destination"
}

llvm-verify-gpg-material() {
    local artifact="$1"
    local signature_url="$2"
    local temp_dir="$3"
    local signature_file="$temp_dir/$(basename "$artifact").sig"
    local keys_file="$temp_dir/llvm-release-keys.asc"
    local gpg_home="$temp_dir/gnupg"
    local status_file="$temp_dir/gpg-status.txt"
    local error_file="$temp_dir/gpg-error.txt"

    [ -n "$signature_url" ] || {
        LLVMUP_VERIFICATION_GPG="not-provided"
        return 0
    }

    if ! command -v gpg >/dev/null 2>&1; then
        LLVMUP_VERIFICATION_GPG="unavailable"
        log_warn "GPG signature is available, but 'gpg' is not installed; trying another verifier."
        return 0
    fi

    if ! llvm-download-verification-material "$signature_url" "$signature_file"; then
        LLVMUP_VERIFICATION_GPG="unavailable"
        log_warn "Could not download the GPG signature: $signature_url"
        return 0
    fi

    if [ -n "${LLVMUP_RELEASE_KEYS_FILE:-}" ]; then
        if [ ! -f "$LLVMUP_RELEASE_KEYS_FILE" ]; then
            log_error "LLVMUP_RELEASE_KEYS_FILE does not exist: $LLVMUP_RELEASE_KEYS_FILE"
            return 1
        fi
        cp "$LLVMUP_RELEASE_KEYS_FILE" "$keys_file" || return 1
    elif ! llvm-download-verification-material \
        "https://releases.llvm.org/release-keys.asc" "$keys_file"; then
        LLVMUP_VERIFICATION_GPG="unavailable"
        log_warn "Could not obtain the official LLVM release keys; trying another verifier."
        return 0
    fi

    mkdir -p "$gpg_home" || return 1
    chmod 700 "$gpg_home" || return 1
    if ! gpg --batch --homedir "$gpg_home" --import "$keys_file" \
        >"$temp_dir/gpg-import.txt" 2>&1; then
        LLVMUP_VERIFICATION_GPG="unavailable"
        log_warn "Could not import the official LLVM release keys into the isolated keyring."
        return 0
    fi

    if gpg --batch --homedir "$gpg_home" --status-fd 1 \
        --verify "$signature_file" "$artifact" >"$status_file" 2>"$error_file"; then
        LLVMUP_VERIFICATION_GPG_FINGERPRINT="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; exit }' "$status_file")"
        if [ -z "$LLVMUP_VERIFICATION_GPG_FINGERPRINT" ]; then
            LLVMUP_VERIFICATION_GPG="error"
            log_error "GPG returned success without a VALIDSIG fingerprint"
            return 1
        fi
        LLVMUP_VERIFICATION_GPG="valid"
        llvm-verification-add-method "gpg"
        log_info "GPG signature verified with LLVM release key $LLVMUP_VERIFICATION_GPG_FINGERPRINT"
        return 0
    fi

    if grep -q '\[GNUPG:\] NO_PUBKEY ' "$status_file"; then
        LLVMUP_VERIFICATION_GPG="unavailable"
        log_warn "The signature key is not present in the official LLVM release key set; trying another verifier."
        return 0
    fi

    LLVMUP_VERIFICATION_GPG="invalid"
    log_error "LLVM GPG signature validation failed for $(basename "$artifact")"
    [ -s "$error_file" ] && sed -n '1,10p' "$error_file" >&2
    return 1
}

llvm-verify-attestation-material() {
    local artifact="$1"
    local attestation_url="$2"
    local temp_dir="$3"
    local bundle_file="$temp_dir/$(basename "$artifact").jsonl"
    local output_file="$temp_dir/gh-attestation-output.txt"

    [ -n "$attestation_url" ] || {
        LLVMUP_VERIFICATION_ATTESTATION="not-provided"
        return 0
    }

    if ! command -v gh >/dev/null 2>&1 ||
       ! gh attestation verify --help >/dev/null 2>&1; then
        LLVMUP_VERIFICATION_ATTESTATION="unavailable"
        log_warn "A GitHub attestation is available, but a compatible 'gh' CLI is not installed; trying another verifier."
        return 0
    fi

    if ! llvm-download-verification-material "$attestation_url" "$bundle_file"; then
        LLVMUP_VERIFICATION_ATTESTATION="unavailable"
        log_warn "Could not download the GitHub attestation bundle: $attestation_url"
        return 0
    fi

    if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
        export GH_TOKEN="$GITHUB_TOKEN"
    fi

    if gh attestation verify "$artifact" --repo llvm/llvm-project \
        --bundle "$bundle_file" >"$output_file" 2>&1; then
        LLVMUP_VERIFICATION_ATTESTATION="valid"
        llvm-verification-add-method "sigstore"
        log_info "GitHub/Sigstore attestation verified for llvm/llvm-project"
        return 0
    fi

    LLVMUP_VERIFICATION_ATTESTATION="invalid"
    log_error "GitHub/Sigstore attestation validation failed for $(basename "$artifact")"
    [ -s "$output_file" ] && sed -n '1,15p' "$output_file" >&2
    return 1
}

# Validate integrity and provenance for one release asset. A cryptographic
# mismatch is always fatal; unavailable tooling/material follows the policy.
llvm-verify-release-asset() {
    local artifact="$1"
    local asset_digest="$2"
    local checksum_url="$3"
    local signature_url="$4"
    local attestation_url="$5"
    local temp_dir="$6"
    local policy
    local expected=""
    local actual=""
    local checksum_file="$temp_dir/$(basename "$artifact").sha256"

    policy="$(llvm-resolve-verification-policy "${7:-}")" || return 1
    llvm-reset-verification-result

    if [ "$policy" = "skip" ]; then
        LLVMUP_VERIFICATION_CHECKSUM="skipped"
        LLVMUP_VERIFICATION_GPG="skipped"
        LLVMUP_VERIFICATION_ATTESTATION="skipped"
        LLVMUP_VERIFICATION_METHODS="skipped"
        log_warn "Release verification was explicitly skipped."
        return 0
    fi

    if [ -n "$asset_digest" ]; then
        expected="$(printf '%s' "$asset_digest" | sed 's/^sha256://I')"
        actual="$(llvm-compute-sha256 "$artifact")" || {
            LLVMUP_VERIFICATION_CHECKSUM="unavailable"
            log_warn "No SHA256 implementation is available."
        }
        if [ -n "$actual" ]; then
            if [ "$actual" != "$expected" ]; then
                LLVMUP_VERIFICATION_CHECKSUM="invalid"
                log_error "SHA256 digest mismatch. Expected: $expected, Actual: $actual"
                return 1
            fi
            LLVMUP_VERIFICATION_CHECKSUM="valid"
            log_info "SHA256 asset.digest matches the downloaded file."
        fi
    elif [ -n "$checksum_url" ]; then
        if llvm-download-verification-material "$checksum_url" "$checksum_file"; then
            expected="$(grep -Eio '[0-9a-f]{64}' "$checksum_file" | head -1 || true)"
            if [ -z "$expected" ]; then
                LLVMUP_VERIFICATION_CHECKSUM="invalid"
                log_error "The advertised checksum file does not contain a SHA256 digest."
                return 1
            fi
            expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
            actual="$(llvm-compute-sha256 "$artifact")" || true
            if [ -z "$actual" ]; then
                LLVMUP_VERIFICATION_CHECKSUM="unavailable"
                log_warn "No SHA256 implementation is available."
            elif [ "$actual" != "$expected" ]; then
                LLVMUP_VERIFICATION_CHECKSUM="invalid"
                log_error "SHA256 checksum mismatch. Expected: $expected, Actual: $actual"
                return 1
            else
                LLVMUP_VERIFICATION_CHECKSUM="valid"
                log_info "SHA256 checksum matches the downloaded file."
            fi
        else
            LLVMUP_VERIFICATION_CHECKSUM="unavailable"
            log_warn "Could not download the advertised checksum file."
        fi
    fi

    llvm-verify-gpg-material "$artifact" "$signature_url" "$temp_dir" || return 1
    llvm-verify-attestation-material "$artifact" "$attestation_url" "$temp_dir" || return 1

    if [ "$LLVMUP_VERIFICATION_GPG" != "valid" ] &&
       [ "$LLVMUP_VERIFICATION_ATTESTATION" != "valid" ]; then
        if [ "$policy" = "strict" ]; then
            log_error "Strict verification requires a valid LLVM GPG signature or llvm/llvm-project Sigstore attestation."
            return 1
        fi
        log_warn "The asset integrity may be checked, but its LLVM origin was not cryptographically authenticated."
        if [ "$LLVMUP_VERIFICATION_CHECKSUM" = "valid" ]; then
            LLVMUP_VERIFICATION_METHODS="checksum-only"
        else
            LLVMUP_VERIFICATION_METHODS="unverified"
        fi
    fi

    log_info "Verification summary: checksum=$LLVMUP_VERIFICATION_CHECKSUM, gpg=$LLVMUP_VERIFICATION_GPG, sigstore=$LLVMUP_VERIFICATION_ATTESTATION"
    return 0
}

llvm-write-verification-marker() {
    local target_dir="$1"
    local version="$2"
    local asset_name="$3"
    local asset_digest="$4"
    local policy="$5"
    local marker="$target_dir/.llvmup-verification.json"

    command -v jq >/dev/null 2>&1 || return 1
    jq -n \
        --arg version "$version" \
        --arg asset_name "$asset_name" \
        --arg asset_digest "$asset_digest" \
        --arg policy "$policy" \
        --arg checksum "$LLVMUP_VERIFICATION_CHECKSUM" \
        --arg gpg "$LLVMUP_VERIFICATION_GPG" \
        --arg attestation "$LLVMUP_VERIFICATION_ATTESTATION" \
        --arg methods "$LLVMUP_VERIFICATION_METHODS" \
        --arg fingerprint "$LLVMUP_VERIFICATION_GPG_FINGERPRINT" \
        '{schema: 1, version: $version, asset_name: $asset_name,
          asset_digest: $asset_digest, policy: $policy,
          checksum: $checksum, gpg: $gpg, attestation: $attestation,
          methods: $methods, gpg_fingerprint: $fingerprint}' > "$marker"
}

llvm-validate-verification-marker() {
    local target_dir="$1"
    local version="$2"
    local asset_digest="$3"
    local policy="$4"
    local marker="$target_dir/.llvmup-verification.json"

    if [ ! -f "$marker" ] || ! jq -e --arg version "$version" \
        --arg digest "$asset_digest" '
          .schema == 1 and .version == $version and
          ($digest == "" or .asset_digest == $digest)
        ' "$marker" >/dev/null 2>&1; then
        [ "$policy" = "strict" ] && {
            log_error "Strict verification cannot trust the existing toolchain: its verification marker is missing or incompatible."
            return 1
        }
        log_warn "Existing toolchain has no compatible verification marker."
        return 0
    fi

    if [ "$policy" = "strict" ] && ! jq -e \
        '.gpg == "valid" or .attestation == "valid"' "$marker" >/dev/null 2>&1; then
        log_error "Strict verification cannot trust the existing toolchain: no authenticated origin is recorded."
        return 1
    fi

    LLVMUP_VERIFICATION_METHODS="$(jq -r '.methods // "unverified"' "$marker")"
    return 0
}

# Get all installed LLVM versions in a structured format
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
llvm-get-versions-simple() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"

    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            basename "$dir"
        fi
    done | sort -V
}

# Get versions in detailed list format
llvm-get-versions-list() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local sources_dir="$(llvm-get-sources-dir)"

    echo "╭─ Available LLVM Versions ──────────────────────────────────╮"

    local found_versions=false

    # Process toolchain versions
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            found_versions=true
            local version_name=$(basename "$dir")
            local parsed_version=$(llvm-parse-version "$version_name" 2>/dev/null)
            local is_active=""
            local type_info=""

            # Check if this version is active
            if [ -n "$_ACTIVE_LLVM" ] && [ "$version_name" = "$_ACTIVE_LLVM" ]; then
                is_active=" (ACTIVE)"
            fi

            # Determine version type
            if echo "$version_name" | grep -q "^source-"; then
                type_info=" [Source Build]"
            else
                type_info=" [Prebuilt]"
            fi

            # Format output
            if [ -n "$parsed_version" ] && [ "$parsed_version" != "$version_name" ]; then
                printf "│ %-20s (v%s)%s%s\n" "$version_name" "$parsed_version" "$type_info" "$is_active"
            else
                printf "│ %-35s%s%s\n" "$version_name" "$type_info" "$is_active"
            fi
        fi
    done

    if [ "$found_versions" = false ]; then
        echo -e "│ ${RED}No LLVM versions found${NC}                                   │"
        echo "│                                                            │"
        echo -e "│ ${BLUE}Use 'llvmup' to install LLVM versions${NC}                   │"
    fi

    echo "╰────────────────────────────────────────────────────────────╯"
}

# Get versions in JSON format
llvm-get-versions-json() {
    local toolchains_dir="$(llvm-get-toolchains-dir)"
    local first=true

    echo "{"
    echo "  \"installed_versions\": ["

    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            local version_name=$(basename "$dir")
            local parsed_version=$(llvm-parse-version "$version_name" 2>/dev/null)
            local is_active="false"
            local install_type="prebuilt"

            # Check if this version is active
            if [ -n "$_ACTIVE_LLVM" ] && [ "$version_name" = "$_ACTIVE_LLVM" ]; then
                is_active="true"
            fi

            # Determine installation type
            if echo "$version_name" | grep -q "^source-"; then
                install_type="source"
            fi

            # Add comma separator for multiple entries
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            echo "    {"
            echo "      \"name\": \"$version_name\","
            echo "      \"version\": \"${parsed_version:-$version_name}\","
            echo "      \"type\": \"$install_type\","
            echo "      \"active\": $is_active,"
            echo "      \"path\": \"$dir\""
            echo -n "    }"
        fi
    done

    echo ""
    echo "  ],"
    echo "  \"active_version\": \"${_ACTIVE_LLVM:-null}\""
    echo "}"
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

    # Use sort -V for version comparison
    local result=$(printf '%s\n%s\n' "$clean_v1" "$clean_v2" | sort -V | head -n1)

    if [ "$result" = "$clean_v2" ]; then
        return 0  # v1 >= v2
    else
        return 1  # v1 < v2
    fi
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
    done | sort -V | tail -n1
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

    mapfile -t available_versions < <(llvm-get-versions simple 2>/dev/null)
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
            if [ -z "$minor" ]; then
                minor=0
            fi
            local next_minor=$((minor + 1))
            local next_version="$major.$next_minor.0"
            local floor_version="$major.$minor.0"

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

        mapfile -t matched_versions < <(llvm-match-versions "$version_expr" 2>/dev/null)

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
    mapfile -t matched_versions < <(llvm-match-versions "$version_expr" 2>/dev/null)

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

    if llvm-activate "$selected_version" >/dev/null 2>&1; then
        log_success "Auto-activated LLVM $selected_version (expression: $version_expr)"
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
        log_error "Failed to auto-activate LLVM $selected_version"
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
        mapfile -t matches < <(llvm-match-versions "$expr" 2>/dev/null)

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

# Auto-ativação: executar sempre se houver .llvmup-config no diretório atual
# A função llvm-autoactivate já tem lógica para não reativar se a versão atual já satisfaz a expressão
if [ -z "$LLVMUP_DISABLE_AUTOACTIVATE" ] && [ -z "$LLVM_TEST_MODE" ]; then
    llvm-register-autoactivate-hooks
    llvm-autoactivate 2>/dev/null || true
fi
