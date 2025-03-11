#!/bin/bash
# activate_llvm_vscode.sh
#
# Usage:
#   ./activate_llvm_vscode.sh <llvm-version>
#
# This script updates your VSCode workspace settings by merging new LLVM configuration
# settings into the existing .vscode/settings.json. This way, any other settings in the file
# remain intact.
#
# It configures:
#   - cmake.additionalCompilerSearchDirs
#   - clangd.path
#   - clangd.fallbackFlags
#   - cmake.configureEnvironment (PATH)

set -e

LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <llvm-version>"
    echo "Versões instaladas em $LLVM_TOOLCHAINS_DIR:"
    echo "Installed versions in $LLVM_TOOLCHAINS_DIR:"
    if [ -d "$LLVM_TOOLCHAINS_DIR" ]; then
        for dir in "$LLVM_TOOLCHAINS_DIR"/*; do
            if [ -d "$dir" ]; then
                echo "  - $(basename "$dir")"
            fi
        done
    else
        echo "Nenhuma versão instalada em $LLVM_TOOLCHAINS_DIR."
        echo "No versions installed in $LLVM_TOOLCHAINS_DIR."
    fi
    exit 1
fi

LLVM_VERSION="$1"
LLVM_DIR="$LLVM_TOOLCHAINS_DIR/$LLVM_VERSION"

if [ ! -d "$LLVM_DIR" ]; then
    echo "Error: LLVM version '$LLVM_VERSION' is not installed in $LLVM_TOOLCHAINS_DIR."
    exit 1
fi

# Define the paths based on the LLVM_DIR
CLANGD_PATH="$LLVM_DIR/bin/clangd"
COMPILER_SEARCH_DIR="$LLVM_DIR/bin"

# Extract the major version for fallback flags (assumes version format like llvmorg-20.1.0)
clangMajor=$(echo "$LLVM_VERSION" | grep -o '[0-9]\+' | head -n 1)
if [ -z "$clangMajor" ]; then
    clangMajor="20"
fi

# Construct fallback flags; adjust include paths as necessary
FALLBACK_FLAGS="-isystem $LLVM_DIR/lib/clang/$clangMajor/include -isystem $LLVM_DIR/include/c++/v1"

# Build the new PATH for CMake configuration by prepending the LLVM bin directory
NEW_PATH="$LLVM_DIR/bin:$PATH"

# Define the VSCode settings file location (relative to the current directory)
VSCODE_DIR=".vscode"
SETTINGS_FILE="$VSCODE_DIR/settings.json"

# Ensure the .vscode directory exists
mkdir -p "$VSCODE_DIR"

# If the settings file doesn't exist, create an empty JSON object
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "{}" > "$SETTINGS_FILE"
fi

# Merge new settings using jq
tmp=$(mktemp)
jq --arg clangd_path "$CLANGD_PATH" \
   --arg comp_search "$COMPILER_SEARCH_DIR" \
   --arg fallback_flags "$FALLBACK_FLAGS" \
   --arg new_path "$NEW_PATH" \
   '. + {
       "cmake.additionalCompilerSearchDirs": [$comp_search],
       "clangd.path": $clangd_path,
       "clangd.fallbackFlags": [$fallback_flags],
       "cmake.configureEnvironment": { "PATH": $new_path }
    }' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

echo "VSCode settings updated to use LLVM version '$LLVM_VERSION'."
echo "Please reload your VSCode workspace for the changes to take effect."
