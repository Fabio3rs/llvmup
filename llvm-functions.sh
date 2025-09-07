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

# Log error messages (always shown)
log_error() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo "❌ Error: $*" >&2
}

# Log warning messages (always shown)
log_warn() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo "⚠️  $*" >&2
}

# Log success messages (always shown)
log_success() {
    if [ "$QUIET_SUCCESS" -eq 1 ] || [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo "✅ $*"
}

# Log info messages (only in verbose mode or test mode)
log_info() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo "💡 $*"
    fi
}

# Log debug messages (only in verbose mode or test mode)
log_debug() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo "🔍 $*"
    fi
}

# Log progress messages (only in verbose mode or test mode)
log_progress() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo "🔄 $*"
    fi
}

# Log configuration messages (only in verbose mode or test mode)
log_config() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo "🎯 $*"
    fi
}

# Log tips and suggestions (only in verbose mode or test mode)
log_tip() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ -n "$LLVM_VERBOSE" ] || [ -n "$LLVM_TEST_MODE" ]; then
        echo "💡 $*"
    fi
}

# Log expression parsing details (controlled by EXPRESSION_VERBOSE)
log_expression_verbose() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ "$EXPRESSION_VERBOSE" -eq 1 ] || [ -n "$LLVM_VERBOSE" ]; then
        echo "🔍 Expression: $*"
    fi
}

# Log expression debug information (controlled by EXPRESSION_DEBUG)
log_expression_debug() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    if [ "$EXPRESSION_DEBUG" -eq 1 ] || [ -n "$LLVM_VERBOSE" ]; then
        echo "🐛 Debug: $*"
    fi
}

# Log expression results (always visible unless QUIET_MODE)
log_expression_result() {
    if [ "$QUIET_MODE" -eq 1 ]; then
        return
    fi
    echo "✨ $*"
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
    echo "✅ Verbose mode disabled for LLVM functions"
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
        echo "📦 Installed versions:"
        llvm-list
        echo ""
        log_tip "Use TAB completion to auto-complete version names"
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-activate"

    if [ -f "$script_path" ]; then
        log_progress "Activating LLVM version $version..."
        source "$script_path" "$version"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
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
        log_error "llvm-activate script not found at $script_path"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi
}

# Function to deactivate the current LLVM version
llvm-deactivate() {
    local script_path="$HOME/.local/bin/llvm-deactivate"

    if [ -f "$script_path" ]; then
        log_progress "Deactivating LLVM environment..."
        source "$script_path"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log_success "LLVM environment successfully deactivated"
            log_tip "Your shell prompt and environment variables have been restored"
        fi
        return $exit_code
    else
        log_error "llvm-deactivate script not found at $script_path"
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
        echo "📦 Installed versions:"
        llvm-list
        echo ""
        log_tip "Run this from your VSCode workspace root directory"
        log_tip "After running, reload VSCode window for changes to take effect"
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-vscode-activate"

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
        log_error "llvm-vscode-activate script not found at $script_path"
        log_tip "Run the installation script to install LLVM manager tools."
        log_tip "  ./install.sh"
        return 1
    fi
}

# Function to show current LLVM status
llvm-status() {
    echo "╭─ LLVM Environment Status ──────────────────────────────────╮"
    if [ -n "$_ACTIVE_LLVM" ]; then
        echo "│ ✅ Status: ACTIVE                                          │"
        echo "│ 📦 Version: $_ACTIVE_LLVM"
        if [ -n "$_ACTIVE_LLVM_PATH" ]; then
            echo "│ 📁 Path: $_ACTIVE_LLVM_PATH"
        fi
        echo "│                                                            │"
        echo "│ 🛠️  Available tools:                                        │"
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
        echo "│ 💡 To deactivate: llvm-deactivate                         │"
    else
        echo "│ ❌ Status: INACTIVE                                        │"
        echo "│                                                            │"
        echo "│ 💡 To activate a version: llvm-activate <version>         │"
        echo "│ 📦 To see available versions: llvm-list                   │"
        echo "│ 🚀 To install new versions: llvmup                        │"
    fi
    echo "╰────────────────────────────────────────────────────────────╯"
}

# Function to list installed LLVM versions
llvm-list() {
    local toolchains_dir="$HOME/.llvm/toolchains"

    echo "╭─ Installed LLVM Versions ──────────────────────────────────╮"
    if [ ! -d "$toolchains_dir" ]; then
        echo "│ ❌ No LLVM toolchains found                                │"
        echo "│                                                            │"
        echo "│ 💡 To install LLVM versions:                               │"
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
                echo "│ ✅ $version (ACTIVE)"
            else
                echo "│ 📦 $version"
            fi
        fi
    done

    if [ "$has_versions" = false ]; then
        echo "│ ❌ No valid LLVM installations found                       │"
    fi

    echo "│                                                            │"
    echo "│ 💡 Usage:                                                   │"
    echo "│   • llvm-activate <version>   # Activate a version         │"
    echo "│   • llvm-status              # Check current status        │"
    echo "│   • llvmup                   # Install more versions       │"
    echo "╰────────────────────────────────────────────────────────────╯"
}

# Enhanced completion function for llvm-activate and llvm-vscode-activate
_llvm_complete_versions() {
    local toolchains_dir="$HOME/.llvm/toolchains"
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ -d "$toolchains_dir" ]; then
        local versions=$(find "$toolchains_dir" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort)

        # Add context information for better UX
        if [ -z "$versions" ]; then
            # Show helpful message when no versions installed
            echo >&2
            echo "💡 No LLVM versions installed yet. Use 'llvmup install' to install versions." >&2
            return 0
        fi

        # Check for default and active versions to provide better context
        local default_version=""
        local active_version="$_ACTIVE_LLVM"

        if [ -L "$HOME/.llvm/default" ]; then
            default_version=$(basename "$(readlink "$HOME/.llvm/default" 2>/dev/null)" 2>/dev/null)
        fi

        # Show status indicators in stderr (doesn't affect completion)
        if [ "$COMP_CWORD" -eq 1 ] && [ ${#COMP_WORDS[@]} -eq 2 ] && [ -z "$cur" ]; then
            echo >&2
            echo "💡 Available versions:" >&2
            while IFS= read -r version; do
                local status=""
                if [ "$version" = "$default_version" ]; then
                    status="⭐ (default)"
                elif [ "$version" = "$active_version" ]; then
                    status="🟢 (active)"
                fi
                echo "   📦 $version $status" >&2
            done <<< "$versions"
            echo >&2
        fi

        COMPREPLY=($(compgen -W "$versions" -- "$cur"))
    else
        echo >&2
        echo "💡 LLVM toolchains directory not found. Install LLVM versions first." >&2
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
    echo "│ 🚀 INSTALLATION COMMANDS:                                  │"
    echo "│   llvmup install                  # Install latest prebuilt│"
    echo "│   llvmup install 18.1.8          # Install specific version│"
    echo "│   llvmup install --from-source    # Build from source      │"
    echo "│   llvmup install --name my-llvm   # Custom installation name│"
    echo "│   llvmup install --default        # Set as default version │"
    echo "│   llvmup install --profile minimal # Use minimal profile   │"
    echo "│   llvmup install --cmake-flags '-DCMAKE_BUILD_TYPE=Debug'  │"
    echo "│                                                            │"
    echo "│ 🔧 VERSION MANAGEMENT:                                      │"
    echo "│   llvm-activate <version>     # Activate LLVM version      │"
    echo "│   llvm-deactivate             # Deactivate current version │"
    echo "│   llvm-status                 # Show current status        │"
    echo "│   llvm-list                   # List installed versions    │"
    echo "│   llvmup default set <ver>    # Set default version        │"
    echo "│   llvmup default show         # Show current default       │"
    echo "│                                                            │"
    echo "│ 🔍 VERSION PARSING & UTILITIES:                             │"
    echo "│   llvm-parse-version <ver>    # Parse version string       │"
    echo "│   llvm-get-versions [format]  # List versions (list/simple/json)│"
    echo "│   llvm-version-exists <ver>   # Check if version exists    │"
    echo "│   llvm-get-active-version     # Get currently active version│"
    echo "│   llvm-version-compare <v1> <v2> # Compare two versions    │"
    echo "│   llvm-get-latest-version     # Find latest installed version│"
    echo "│   llvm-match-versions <expr>  # Match versions by expression│"
    echo "│   llvm-test-expressions       # Test expression matching   │"
    echo "│                                                            │"
    echo "│ �️  VERBOSITY CONTROLS:                                      │"
    echo "│   llvm-verbose-on/off         # Toggle general verbose mode │"
    echo "│   llvm-expression-verbose-on/off # Toggle expression verbose│"
    echo "│   llvm-expression-debug-on/off   # Toggle expression debug  │"
    echo "│                                                            │"
    echo "│ �🎯 VERSION EXPRESSIONS (for auto-activate):                 │"
    echo "│   • Selectors: latest, oldest, newest, earliest            │"
    echo "│   • Type filters: prebuilt, source, latest-prebuilt        │"
    echo "│   • Ranges: >=18.0.0, <=19.1.0, ~19.1, 18.*              │"
    echo "│   • Specific: llvmorg-18.1.8, source-llvmorg-20.1.0       │"
    echo "│                                                            │"
    echo "│ 💻 DEVELOPMENT INTEGRATION:                                 │"
    echo "│   llvm-vscode-activate <ver>  # Setup VSCode integration   │"
    echo "│   llvm-config-init            # Initialize .llvmup-config  │"
    echo "│   llvm-config-load            # Load project config        │"
    echo "│   llvm-config-apply           # Install from config        │"
    echo "│   llvm-config-activate        # Activate configured version│"
    echo "│                                                            │"
    echo "│ 🛠️  AVAILABLE TOOLS AFTER ACTIVATION:                       │"
    echo "│   • clang/clang++    # C/C++ compilers                     │"
    echo "│   • ld.lld          # LLVM linker                          │"
    echo "│   • lldb            # LLVM debugger                        │"
    echo "│   • clangd          # Language server for IDEs             │"
    echo "│   • llvm-ar         # Archiver                             │"
    echo "│   • llvm-nm         # Symbol table dumper                  │"
    echo "│   • opt             # LLVM optimizer                       │"
    echo "│                                                            │"
    echo "│ 📚 PROJECT CONFIGURATION (.llvmup-config):                  │"
    echo "│   [version]                                                │"
    echo "│   default = \"llvmorg-21.1.0\"                              │"
    echo "│   [build]                                                  │"
    echo "│   name = \"21.1.0-debug\"                                   │"
    echo "│   cmake_flags = [\"-DCMAKE_BUILD_TYPE=Debug\"]              │"
    echo "│   [profile]                                                │"
    echo "│   type = \"full\"                                           │"
    echo "│                                                            │"
    echo "│ 💡 TIPS:                                                    │"
    echo "│   • Use TAB completion for version names                   │"
    echo "│   • Check llvm-status after activation                     │"
    echo "│   • Your PS1 prompt shows active LLVM version              │"
    echo "│   • Environment is isolated per terminal session           │"
    echo "│   • Use .llvmup-config for project-specific settings       │"
    echo "│                                                            │"
    echo "│ 🔗 MORE INFO: https://github.com/Fabio3rs/llvmup           │"
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
        echo "📋 Please provide the following information:"

        # Check for installed versions first
        local toolchains_dir="$HOME/.llvm/toolchains"
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
            read -p "List remote versions? [Y/n]: " -n 1 -r
            echo

            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
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

            read -p "Default LLVM version (e.g., llvmorg-18.1.8): " default_version
            if [ -z "$default_version" ]; then
                default_version="llvmorg-18.1.8"
            fi
        fi

        read -p "Custom installation name (optional): " custom_name
        read -p "Build profile [minimal/full/custom]: " profile
        if [ -z "$profile" ]; then
            profile="full"
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
cmake_preset = "Release"

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
    LLVM_CONFIG_CMAKE_FLAGS=()
    LLVM_CONFIG_COMPONENTS=()

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

    log_config "Configuration loaded:"
    log_info "   📦 Version: $LLVM_CONFIG_VERSION"
    [ -n "$LLVM_CONFIG_NAME" ] && log_info "   🏷️  Name: $LLVM_CONFIG_NAME"
    [ -n "$LLVM_CONFIG_PROFILE" ] && log_info "   📋 Profile: $LLVM_CONFIG_PROFILE"
    [ ${#LLVM_CONFIG_CMAKE_FLAGS[@]} -gt 0 ] && log_debug "CMake flags: ${LLVM_CONFIG_CMAKE_FLAGS[*]}"
    [ ${#LLVM_CONFIG_COMPONENTS[@]} -gt 0 ] && log_debug "Components: ${LLVM_CONFIG_COMPONENTS[*]}"
    [ -n "$LLVM_CONFIG_CMAKE_PRESET" ] && log_debug "CMake preset: $LLVM_CONFIG_CMAKE_PRESET"
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

    # In test mode, don't prompt for installation
    if [ -n "$LLVM_TEST_MODE" ]; then
        log_debug "Test mode: skipping installation"
        return 0
    fi

    # Ask if user wants to install now
    read -p "🤔 Install now? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
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

# Get all installed LLVM versions in a structured format
llvm-get-versions() {
    local format="${1:-list}"  # Options: list, json, simple
    local toolchains_dir="$HOME/.llvm/toolchains"
    local sources_dir="$HOME/.llvm/sources"

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
    local toolchains_dir="$HOME/.llvm/toolchains"

    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            basename "$dir"
        fi
    done | sort -V
}

# Get versions in detailed list format
llvm-get-versions-list() {
    local toolchains_dir="$HOME/.llvm/toolchains"
    local sources_dir="$HOME/.llvm/sources"

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
                printf "│ 📦 %-20s (v%s)%s%s\n" "$version_name" "$parsed_version" "$type_info" "$is_active"
            else
                printf "│ 📦 %-35s%s%s\n" "$version_name" "$type_info" "$is_active"
            fi
        fi
    done

    if [ "$found_versions" = false ]; then
        echo "│ ❌ No LLVM versions found                                   │"
        echo "│                                                            │"
        echo "│ 💡 Use 'llvmup' to install LLVM versions                   │"
    fi

    echo "╰────────────────────────────────────────────────────────────╯"
}

# Get versions in JSON format
llvm-get-versions-json() {
    local toolchains_dir="$HOME/.llvm/toolchains"
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
    local toolchains_dir="$HOME/.llvm/toolchains"

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
            if echo "$expression" | grep -qE '^(llvmorg-|source-)?[0-9]+(\.[0-9]+)*(-[a-zA-Z0-9]+)?$'; then
                echo "specific:$expression"
            else
                log_error "Invalid version expression: $expression"
                return 1
            fi
            ;;
    esac
}

# Match versions against a comprehensive expression
llvm-match-versions() {
    local expression="$1"
    local available_versions=()

    if [ -z "$expression" ]; then
        log_error "Version expression is required"
        return 1
    fi

    # Get all available versions
    mapfile -t available_versions < <(llvm-get-versions simple 2>/dev/null)

    if [ ${#available_versions[@]} -eq 0 ]; then
        log_error "No LLVM versions available"
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
                # Exact match
                matched_versions=()
                for version in "${available_versions[@]}"; do
                    if [ "$version" = "$value" ]; then
                        matched_versions+=("$version")
                        log_expression_debug "Found specific match: $version"
                        break
                    fi
                done
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
            local base_version="${range_expr#~}"
            local major_minor=$(echo "$base_version" | cut -d. -f1-2)
            local next_minor=$(($(echo "$base_version" | cut -d. -f2) + 1))
            local next_version="$(echo "$base_version" | cut -d. -f1).$next_minor.0"

            llvm-version-compare "$parsed_version" "$base_version" 2>/dev/null && \
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
    if [ ! -f ".llvmup-config" ]; then
        return 0
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
    if llvm-activate "$selected_version" >/dev/null 2>&1; then
        log_success "Auto-activated LLVM $selected_version (expression: $version_expr)"
    else
        log_error "Failed to auto-activate LLVM $selected_version"
        QUIET_SUCCESS=$backup_quiet_success
        return 1
    fi

    QUIET_SUCCESS=$backup_quiet_success
    return 0
}

# Test function for comprehensive expressions
llvm-test-expressions() {
    echo "🧪 Testing Comprehensive Version Expressions"
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
        echo "📋 Expression: '$expr'"
        echo "----------------------------------------"

        local matches=()
        mapfile -t matches < <(llvm-match-versions "$expr" 2>/dev/null)

        if [ ${#matches[@]} -gt 0 ]; then
            echo "✅ Matches found:"
            for match in "${matches[@]}"; do
                local parsed=$(llvm-parse-version "$match" 2>/dev/null)
                local type="[Prebuilt]"
                if echo "$match" | grep -q "^source-"; then
                    type="[Source Build]"
                fi
                echo "   📦 $match (v$parsed) $type"
            done
        else
            echo "❌ No matches found"
        fi
    done

    # Restore verbose setting
    if [ -n "$original_verbose" ]; then
        export LLVM_VERBOSE="$original_verbose"
    fi

    echo ""
    echo "🎉 Expression testing completed!"
}

llvm-autoactivate() {
    if [ -f ".llvmup-config" ]; then
        BACKUP_QUIET_SUCCESS=$QUIET_SUCCESS
        QUIET_SUCCESS=1
        llvm-config-load
        if [ "$LLVM_CONFIG_AUTO_ACTIVATE" = "true" ]; then
            # Use enhanced auto-activation with expressions
            llvm-autoactivate-enhanced
        fi
        QUIET_SUCCESS=$BACKUP_QUIET_SUCCESS
    fi
}

# Se estiver ativo LLVM_TEST_MODE, não faça auto-ativação
if [ -n "$LLVM_TEST_MODE" ]; then
    return
fi

if [ -z "$LLVMUP_DISABLE_AUTOACTIVATE" ] && [ -z "$LLVMUP_AUTOACTIVATED" ]; then
    llvm-autoactivate
    export LLVMUP_AUTOACTIVATED=1
fi
