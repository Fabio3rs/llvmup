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
        echo "Usage: llvm-activate <version>"
        echo "Example: llvm-activate 18.1.8"
        echo ""
        echo "Installed versions:"
        llvm-list
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-activate"

    if [ -f "$script_path" ]; then
        source "$script_path" "$version"
    else
        echo "Warning: llvm-activate script not found at $script_path"
        echo "Run the installation script to install LLVM manager tools."
        return 1
    fi
}

# Function to deactivate the current LLVM version
llvm-deactivate() {
    local script_path="$HOME/.local/bin/llvm-deactivate"

    if [ -f "$script_path" ]; then
        source "$script_path"
    else
        echo "Warning: llvm-deactivate script not found at $script_path"
        echo "Run the installation script to install LLVM manager tools."
        return 1
    fi
}

# Function to activate LLVM for VSCode
llvm-vscode-activate() {
    if [ $# -eq 0 ]; then
        echo "Usage: llvm-vscode-activate <version>"
        echo "Example: llvm-vscode-activate 18.1.8"
        echo ""
        echo "Installed versions:"
        llvm-list
        return 1
    fi

    local version="$1"
    local script_path="$HOME/.local/bin/llvm-vscode-activate"

    if [ -f "$script_path" ]; then
        "$script_path" "$version"
    else
        echo "Warning: llvm-vscode-activate script not found at $script_path"
        echo "Run the installation script to install LLVM manager tools."
        return 1
    fi
}

# Function to show current LLVM status
llvm-status() {
    if [ -n "$_ACTIVE_LLVM" ]; then
        echo "Active LLVM version: $_ACTIVE_LLVM"
        if [ -n "$_ACTIVE_LLVM_PATH" ]; then
            echo "LLVM path: $_ACTIVE_LLVM_PATH"
        fi
    else
        echo "No LLVM version is currently active"
    fi
}

# Function to list installed LLVM versions
llvm-list() {
    local toolchains_dir="$HOME/.llvm/toolchains"

    if [ ! -d "$toolchains_dir" ]; then
        echo "No LLVM toolchains found. Use 'llvmup' to install a version."
        return 0
    fi

    echo "Installed LLVM versions:"
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            local version=$(basename "$dir")
            if [ -n "$_ACTIVE_LLVM" ] && [ "$version" = "$_ACTIVE_LLVM" ]; then
                echo "  * $version (active)"
            else
                echo "    $version"
            fi
        fi
    done
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
