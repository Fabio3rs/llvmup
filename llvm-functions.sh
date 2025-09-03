#!/bin/bash
# llvm-functions.sh: Bash functions for LLVM version management
# This file should be sourced in the user's shell profile (.bashrc, .profile, etc.)
#
# Usage after sourcing:
#   llvm-activate <version>    - Activate an LLVM version
#   llvm-deactivate           - Deactivate current LLVM version
#   llvm-vscode-activate <version> - Activate LLVM for VSCode

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
        echo "💡 Tip: Use TAB completion to auto-complete version names"
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-activate"

    if [ -f "$script_path" ]; then
        echo "🔄 Activating LLVM version $version..."
        source "$script_path" "$version"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "✅ LLVM $version successfully activated!"
            echo "🛠️  Available tools are now in PATH:"
            echo "   • clang, clang++, ld.lld, lldb, clangd, etc."
            echo "💡 Tip: Your shell prompt now shows the active LLVM version"
            echo "📊 Use 'llvm-status' to see detailed information"
        else
            echo "❌ Failed to activate LLVM $version"
            echo "💡 Check if the version is installed: llvm-list"
            return $exit_code
        fi
    else
        echo "❌ Error: llvm-activate script not found at $script_path"
        echo "📥 Run the installation script to install LLVM manager tools."
        echo "   ./install.sh"
        return 1
    fi
}

# Function to deactivate the current LLVM version
llvm-deactivate() {
    local script_path="$HOME/.local/bin/llvm-deactivate"

    if [ -f "$script_path" ]; then
        echo "🔄 Deactivating LLVM environment..."
        source "$script_path"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "✅ LLVM environment successfully deactivated"
            echo "💡 Your shell prompt and environment variables have been restored"
        fi
        return $exit_code
    else
        echo "❌ Error: llvm-deactivate script not found at $script_path"
        echo "📥 Run the installation script to install LLVM manager tools."
        echo "   ./install.sh"
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
        echo "💡 Tip: Run this from your VSCode workspace root directory"
        echo "🔧 After running, reload VSCode window for changes to take effect"
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-vscode-activate"

    if [ -f "$script_path" ]; then
        echo "🔧 Configuring VSCode workspace for LLVM $version..."
        "$script_path" "$version"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "✅ VSCode workspace successfully configured!"
            echo "🔄 Please reload your VSCode window (Ctrl+Shift+P → 'Developer: Reload Window')"
        fi
        return $exit_code
    else
        echo "❌ Error: llvm-vscode-activate script not found at $script_path"
        echo "📥 Run the installation script to install LLVM manager tools."
        echo "   ./install.sh"
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

# Completion function for llvm-activate and llvm-vscode-activate
_llvm_complete_versions() {
    local toolchains_dir="$HOME/.llvm/toolchains"
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ -d "$toolchains_dir" ]; then
        local versions=$(find "$toolchains_dir" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort)
        COMPREPLY=($(compgen -W "$versions" -- "$cur"))
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
        echo "⚠️  .llvmup-config already exists in current directory"
        echo "🔍 Current configuration:"
        cat "$config_file"
        echo ""

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
            echo "❌ Configuration initialization cancelled"
            return 1
        fi
    fi

    echo "🎯 Initializing LLVM project configuration..."

    # For testing, use environment variables or defaults
    if [ -n "$LLVM_TEST_MODE" ]; then
        local default_version="${LLVM_TEST_VERSION:-llvmorg-18.1.8}"
        local custom_name="${LLVM_TEST_CUSTOM_NAME:-}"
        local profile="${LLVM_TEST_PROFILE:-full}"
    else
        # Prompt for configuration
        echo "📋 Please provide the following information:"

        read -p "Default LLVM version (e.g., llvmorg-18.1.8): " default_version
        if [ -z "$default_version" ]; then
            default_version="llvmorg-18.1.8"
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
  "-DCMAKE_BUILD_TYPE=Release",
  "-DLLVM_ENABLE_PROJECTS=clang;lld;lldb"
]

[profile]
type = "$profile"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]

[project]
auto_activate = true
EOF

    echo "✅ Configuration file created: $config_file"
    echo "💡 Edit the file to customize build settings"
    echo "🚀 Run 'llvm-config-load' to install and activate the configured version"
}

# Function to load and apply .llvmup-config settings
llvm-config-load() {
    local config_file=".llvmup-config"

    if [ ! -f "$config_file" ]; then
        echo "❌ No .llvmup-config file found in current directory"
        echo "💡 Run 'llvm-config-init' to create one"
        return 1
    fi

    echo "📋 Loading project configuration from $config_file..."

    # Parse configuration file
    local default_version=""
    local custom_name=""
    local profile=""
    local current_section=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Handle sections
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            current_section="${line//[\[\]]/}"
            continue
        fi

        # Parse key=value pairs
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]}"
            # Remove quotes
            value=$(echo "$value" | sed 's/^[[:space:]]*["'"'"']//;s/["'"'"'][[:space:]]*$//')

            case "$current_section" in
                "version")
                    if [ "$key" = "default" ]; then
                        default_version="$value"
                    fi
                    ;;
                "build")
                    if [ "$key" = "name" ]; then
                        custom_name="$value"
                    fi
                    ;;
                "profile")
                    if [ "$key" = "type" ]; then
                        profile="$value"
                    fi
                    ;;
            esac
        fi
    done < "$config_file"

    if [ -z "$default_version" ]; then
        echo "❌ No default version specified in configuration"
        return 1
    fi

    echo "🎯 Configuration loaded:"
    echo "   📦 Version: $default_version"
    [ -n "$custom_name" ] && echo "   🏷️  Name: $custom_name"
    [ -n "$profile" ] && echo "   📋 Profile: $profile"

    # Check if version is already installed
    local install_name="$default_version"
    if [ -n "$custom_name" ]; then
        install_name="$custom_name"
    fi

    if [ -d "$HOME/.llvm/toolchains/$install_name" ]; then
        echo "✅ Version already installed, activating..."
        llvm-activate "$install_name"
    else
        echo "📥 Version not found, installing..."

        # For testing environments, allow skipping interactive prompts
        local from_source_choice="n"
        if [ -n "$LLVM_TEST_MODE" ]; then
            from_source_choice="${LLVM_TEST_FROM_SOURCE:-n}"
        else
            read -p "Install from source? [y/N] " -n 1 -r
            echo
            from_source_choice="$REPLY"
        fi

        local install_args=("install" "$default_version")

        if [ -n "$custom_name" ]; then
            install_args+=("--name" "$custom_name")
        fi

        if [ -n "$profile" ]; then
            install_args+=("--profile" "$profile")
        fi

        if [[ $from_source_choice =~ ^[Yy]$ ]]; then
            install_args+=("--from-source")
        fi

        echo "� Running: llvmup ${install_args[*]}"
        llvmup "${install_args[@]}"

        if [ $? -eq 0 ]; then
            echo "✅ Installation complete, activating..."
            llvm-activate "$install_name"
        else
            echo "❌ Installation failed"
            return 1
        fi
    fi
}
