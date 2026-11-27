#!/bin/bash
# install.sh: Installation script for the LLVMUP tools.
# This script installs the following commands:
#   - llvm-prebuilt   : Downloads and installs pre-built LLVM releases.
#   - llvm-activate   : Activates a selected LLVM version for the current shell.
#   - llvm-deactivate : Deactivates the currently active LLVM version.
#   - llvm-vscode-activate : Updates VSCode workspace settings with the selected LLVM configuration.
#   - llvmup          : Wrapper command to choose between source build or pre-built install (use --from-source for source build).
#   - llvmup-completion.sh : Bash completion script for llvmup commands.
#   - _llvmup             : Native Zsh completion script for llvmup commands.
#
# Environment Variables for Customization:
#   LLVMUP_PREFIX       : Base installation prefix (default: $HOME/.local)
#   LLVMUP_INSTALL_DIR  : Directory for executable scripts (default: $LLVMUP_PREFIX/bin)
#   LLVMUP_COMPLETION_DIR: Directory for bash completion (default: $LLVMUP_PREFIX/share/bash-completion/completions)
#   LLVMUP_SYSTEM_INSTALL: Set to 1 for system-wide installation (requires sudo)
#   LLVMUP_ZSH_COMPLETION_DIR: Directory for zsh completion (default: $LLVMUP_PREFIX/share/zsh/site-functions)
#
# Examples:
#   ./install.sh                              # Install to ~/.local/bin (default)
#   LLVMUP_PREFIX=/usr/local ./install.sh     # Install to /usr/local/bin
#   LLVMUP_SYSTEM_INSTALL=1 ./install.sh      # System-wide install to /usr/local
#   LLVMUP_INSTALL_DIR=/opt/llvmup ./install.sh  # Custom installation directory
#
# Usage:
#   ./install.sh [--ci|--no-profile|--files-only|--configure-shell]

set -e

# Locate packaged files independently of the caller working directory.
INSTALL_SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

QUIET=0
print_info() { if [ "$QUIET" -eq 0 ]; then printf '%s\n' "$1"; fi; }
print_success() { print_info "$1"; }
print_warning() { printf 'Warning: %s\n' "$1" >&2; }
print_error() { printf 'Error: %s\n' "$1" >&2; }

usage() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --ci               Install for CI usage without modifying shell profiles
  --no-profile       Install files but do not modify ~/.bashrc, ~/.profile, or ~/.zshrc
  --files-only       Install files and completions only
  --configure-shell  Configure shell profiles only for an existing installation
  --quiet            Show only warnings and errors
  -h, --help         Show this help message
EOF
}

CI_MODE=0
SKIP_PROFILE=0
FILES_ONLY=0
CONFIGURE_SHELL_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) QUIET=1 ;;
        --ci)
            CI_MODE=1
            SKIP_PROFILE=1
            ;;
        --no-profile)
            SKIP_PROFILE=1
            ;;
        --files-only)
            FILES_ONLY=1
            SKIP_PROFILE=1
            ;;
        --configure-shell)
            CONFIGURE_SHELL_ONLY=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$FILES_ONLY" -eq 1 ] && [ "$CONFIGURE_SHELL_ONLY" -eq 1 ]; then
    print_error "--files-only and --configure-shell cannot be used together"
    exit 1
fi

# Determine installation directories based on environment variables
if [ -n "$LLVMUP_SYSTEM_INSTALL" ] && [ "$LLVMUP_SYSTEM_INSTALL" = "1" ]; then
    # System-wide installation
    DEFAULT_PREFIX="/usr/local"
    REQUIRES_SUDO=true
    print_info "System-wide installation mode enabled"
else
    # User installation (default)
    DEFAULT_PREFIX="$HOME/.local"
    REQUIRES_SUDO=false
fi

# Set prefix
PREFIX="${LLVMUP_PREFIX:-$DEFAULT_PREFIX}"

# Set installation directories
INSTALL_DIR="${LLVMUP_INSTALL_DIR:-$PREFIX/bin}"
COMPLETION_DIR="${LLVMUP_COMPLETION_DIR:-$PREFIX/share/bash-completion/completions}"
ZSH_COMPLETION_DIR="${LLVMUP_ZSH_COMPLETION_DIR:-$PREFIX/share/zsh/site-functions}"
# Persist absolute destinations so the installed uninstaller is cwd-independent.
[[ $INSTALL_DIR == /* ]] || INSTALL_DIR="$PWD/$INSTALL_DIR"
[[ $COMPLETION_DIR == /* ]] || COMPLETION_DIR="$PWD/$COMPLETION_DIR"
[[ $ZSH_COMPLETION_DIR == /* ]] || ZSH_COMPLETION_DIR="$PWD/$ZSH_COMPLETION_DIR"
FUNCTIONS_FILE="$INSTALL_DIR/llvm-functions.sh"

version=$(cat "$INSTALL_SOURCE_DIR/VERSION" 2>/dev/null || printf development)
previous=$(cat "$INSTALL_DIR/llvmup-version" 2>/dev/null || true)
action=Installation
if [ "$CONFIGURE_SHELL_ONLY" -eq 1 ]; then
    action='Shell configuration'
elif [ -n "$previous" ]; then
    if [ "$previous" = "$version" ]; then action=Reinstallation; else action="Update from $previous"; fi
elif [ -f "$INSTALL_DIR/llvmup-files.tsv" ]; then
    action='Replacement of existing installation'
fi

print_info "LLVMUP $version Installer"
print_info "Operation: $action"
for dependency in jq tar; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        print_warning "$dependency is missing. Install it to use provider toolchains."
    fi
done
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    print_warning "Neither curl nor wget is available for toolchain downloads."
fi

# Check for sudo if required
if [ "$REQUIRES_SUDO" = true ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        print_error "System installation requires sudo, but sudo is not available"
        exit 1
    fi
    print_warning "This installation requires sudo privileges"
    SUDO_CMD="sudo"
else
    SUDO_CMD=""
fi

create_install_directories() {
    print_info "Creating installation directories..."
    $SUDO_CMD mkdir -p "$INSTALL_DIR"
    $SUDO_CMD mkdir -p "$COMPLETION_DIR"
    $SUDO_CMD mkdir -p "$ZSH_COMPLETION_DIR"
}

. "$INSTALL_SOURCE_DIR/packaging/install-files.sh"

# Quote absolute paths for POSIX-style profile commands.
profile_quote() {
    local value=${1//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

# Replace complete managed blocks only. A truncated block could contain user
# lines after its start marker, so reject it before writing anything.
update_profile_block() (
    local profile_file="$1" start="$2" end="$3" block="$4" work
    work=$(mktemp)
    trap 'rm -f -- "$work"' EXIT
    if [ -f "$profile_file" ]; then
        if ! LLVMUP_PROFILE_BLOCK="$block" awk -v start="$start" -v end="$end" '
            $0 == start {
                if (inside) { broken = 1; exit 1 }
                inside = 1
                if (!found++) print ENVIRON["LLVMUP_PROFILE_BLOCK"]
                next
            }
            $0 == end {
                if (!inside) { broken = 1; exit 1 }
                inside = 0
                next
            }
            !inside { print }
            END {
                if (broken || inside) exit 1
                if (!found) { if (NR) print ""; print ENVIRON["LLVMUP_PROFILE_BLOCK"] }
            }
        ' "$profile_file" > "$work"; then
            print_error "Could not update LLVMUP profile block in $profile_file"
            exit 1
        fi
        cmp -s "$work" "$profile_file" && exit 0
    else
        printf '%s\n' "$block" > "$work"
    fi
    cat "$work" > "$profile_file"
)

configure_shell_profiles() {
    if [ ! -f "$FUNCTIONS_FILE" ]; then
        print_error "Cannot configure shell profiles because $FUNCTIONS_FILE is not installed"
        exit 1
    fi
    if [ "$REQUIRES_SUDO" = true ]; then
        print_info "Shell profiles skipped for system installation."
        return 0
    fi
    local bash_profile="$HOME/.bashrc" zsh_profile="${ZDOTDIR:-$HOME}/.zshrc"
    local start='# LLVM Manager Functions - Start' end='# LLVM Manager Functions - End'
    local block completion quoted_functions quoted_bin quoted_zsh
    if [ -f "$HOME/.profile" ] && ! grep -Fxq "$start" "$bash_profile" 2>/dev/null; then
        if [ ! -f "$bash_profile" ] || grep -Fxq "$start" "$HOME/.profile"; then bash_profile="$HOME/.profile"; fi
    fi
    quoted_functions=$(profile_quote "$FUNCTIONS_FILE")
    quoted_bin=$(profile_quote "$INSTALL_DIR")
    quoted_zsh=$(profile_quote "$ZSH_COMPLETION_DIR")
    # Bash 3.2 can mistake ')' in a here-document for the end of $(...).
    printf -v block '%s\n' \
        "$start" \
        'case ":$PATH:" in' \
        "    *:$quoted_bin:*) ;;" \
        "    *) export PATH=$quoted_bin:\"\$PATH\" ;;" \
        'esac' \
        "if [ -n \"\${BASH_VERSION:-}\${ZSH_VERSION:-}\" ] && [ -f $quoted_functions ]; then" \
        "    . $quoted_functions" \
        'fi' \
        "$end"
    block=${block%$'\n'}
    update_profile_block "$bash_profile" "$start" "$end" "$block"
    mkdir -p -- "$(dirname -- "$zsh_profile")"
    update_profile_block "$zsh_profile" "$start" "$end" "$block"
    completion=$(cat <<EOF
# LLVMUP Zsh Completion - Start
if [ -d $quoted_zsh ]; then
    typeset -U fpath
    fpath=($quoted_zsh "\${fpath[@]}")
    if [[ -o interactive ]] && ! (( \$+functions[compdef] )); then
        autoload -Uz compinit
        compinit
    fi
    if (( \$+functions[compdef] )) && [ -z "\${_comps[llvmup]:-}" ]; then
        autoload -Uz _llvmup
        compdef _llvmup llvmup
    fi
fi
# LLVMUP Zsh Completion - End
EOF
)
    update_profile_block "$zsh_profile" '# LLVMUP Zsh Completion - Start' '# LLVMUP Zsh Completion - End' "$completion"
    print_info "Shell profiles: $bash_profile, $zsh_profile"
}

if [ "$CONFIGURE_SHELL_ONLY" -eq 1 ]; then
    configure_shell_profiles
else
    print_info "Installing runtime files"
    install_files
    if [ "$SKIP_PROFILE" -eq 0 ]; then
        configure_shell_profiles
    else
        print_info "Shell profiles skipped."
    fi
fi

toolchains=${LLVM_TOOLCHAINS_DIR:-${LLVM_CUSTOM_TOOLCHAINS_DIR:-${LLVM_HOME:-${LLVM_CUSTOM_HOME:-$HOME/.llvm}}/toolchains}}
print_success "$action complete!"
print_info "Install Directory: $INSTALL_DIR"
print_info "Toolchain Directory: $toolchains"
case ":${PATH:-}:" in
    *":$INSTALL_DIR:"*) ;;
    *) print_info "  export PATH=$(profile_quote "$INSTALL_DIR"):\"\$PATH\"" ;;
esac
if [ "$CI_MODE" -eq 1 ]; then
    print_info 'Export a selected toolchain in CI: eval "$(llvmup env <version>)"'
else
    print_info "Load LLVMUP in this Bash or Zsh session:"
    print_info "  source $(profile_quote "$FUNCTIONS_FILE")"
    print_info "Get started: llvmup --version, llvmup list --providers, llvmup doctor"
    print_info "Install and activate Clang: llvmup install official@latest --use"
fi
