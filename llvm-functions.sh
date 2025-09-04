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

llvm-autoactivate() {
    if [ -f ".llvmup-config" ]; then
        BACKUP_QUIET_SUCCESS=$QUIET_SUCCESS
        QUIET_SUCCESS=1
        llvm-config-load
        if [ "$LLVM_CONFIG_AUTO_ACTIVATE" = "true" ]; then
            llvm-config-activate
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
