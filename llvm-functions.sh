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
        if [ $? -eq 0 ]; then
            echo "✅ LLVM $version successfully activated!"
            echo "🛠️  Available tools are now in PATH:"
            echo "   • clang, clang++, ld.lld, lldb, clangd, etc."
            echo "💡 Tip: Your shell prompt now shows the active LLVM version"
            echo "📊 Use 'llvm-status' to see detailed information"
        else
            echo "❌ Failed to activate LLVM $version"
            echo "💡 Check if the version is installed: llvm-list"
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
        if [ $? -eq 0 ]; then
            echo "✅ LLVM environment successfully deactivated"
            echo "💡 Your shell prompt and environment variables have been restored"
        fi
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
        if [ $? -eq 0 ]; then
            echo "✅ VSCode workspace successfully configured!"
            echo "🔄 Please reload your VSCode window (Ctrl+Shift+P → 'Developer: Reload Window')"
        fi
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
if command -v complete &> /dev/null; then
    complete -F _llvm_complete_versions llvm-activate
    complete -F _llvm_complete_versions llvm-vscode-activate
fi

# Function to show comprehensive help for LLVM manager
llvm-help() {
    echo "╭─ LLVM Manager - Complete Usage Guide ──────────────────────╮"
    echo "│                                                            │"
    echo "│ 🚀 INSTALLATION COMMANDS:                                  │"
    echo "│   llvmup                      # Install latest prebuilt    │"
    echo "│   llvmup 18.1.8              # Install specific version    │"
    echo "│   llvmup --from-source        # Build from source          │"
    echo "│   llvmup --verbose            # Show detailed output       │"
    echo "│                                                            │"
    echo "│ 🔧 ENVIRONMENT MANAGEMENT:                                  │"
    echo "│   llvm-activate <version>     # Activate LLVM version      │"
    echo "│   llvm-deactivate             # Deactivate current version │"
    echo "│   llvm-status                 # Show current status        │"
    echo "│   llvm-list                   # List installed versions    │"
    echo "│                                                            │"
    echo "│ 💻 DEVELOPMENT INTEGRATION:                                 │"
    echo "│   llvm-vscode-activate <ver>  # Setup VSCode integration   │"
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
    echo "│ 📚 WORKFLOW EXAMPLES:                                       │"
    echo "│   1. Install and activate LLVM:                            │"
    echo "│      llvmup 18.1.8                                         │"
    echo "│      llvm-activate 18.1.8                                  │"
    echo "│                                                            │"
    echo "│   2. Setup for VSCode development:                         │"
    echo "│      cd /your/project                                      │"
    echo "│      llvm-vscode-activate 18.1.8                           │"
    echo "│                                                            │"
    echo "│   3. Switch between versions:                              │"
    echo "│      llvm-deactivate                                       │"
    echo "│      llvm-activate 19.1.0                                  │"
    echo "│                                                            │"
    echo "│ 💡 TIPS:                                                    │"
    echo "│   • Use TAB completion for version names                   │"
    echo "│   • Check llvm-status after activation                     │"
    echo "│   • Your PS1 prompt shows active LLVM version              │"
    echo "│   • Environment is isolated per terminal session           │"
    echo "│                                                            │"
    echo "│ 🔗 MORE INFO: https://github.com/Fabio3rs/llvmup           │"
    echo "╰────────────────────────────────────────────────────────────╯"
}
