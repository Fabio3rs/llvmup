#!/bin/bash
# activate_llvm_vscode.sh: Updates VSCode workspace settings for LLVM integration.
# Usage:
#   ./activate_llvm_vscode.sh <version>

set -e

LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Installed versions in $LLVM_TOOLCHAINS_DIR:"
    if [ -d "$LLVM_TOOLCHAINS_DIR" ]; then
        for dir in "$LLVM_TOOLCHAINS_DIR"/*; do
            if [ -d "$dir" ]; then
                echo "  - $(basename "$dir")"
            fi
        done
    else
        echo "No versions installed in $LLVM_TOOLCHAINS_DIR."
    fi
    exit 1
fi

VERSION="$1"
LLVM_DIR="$LLVM_TOOLCHAINS_DIR/$VERSION"

if [ ! -d "$LLVM_DIR" ]; then
    echo "Version '$VERSION' is not installed in $LLVM_TOOLCHAINS_DIR."
    exit 1
fi

# Check if we're in a VSCode workspace
VSCODE_DIR=".vscode"
if [ ! -d "$VSCODE_DIR" ]; then
    echo "Not in a VSCode workspace. Please run this script from your project root."
    exit 1
fi

# Create settings.json if it doesn't exist
SETTINGS_FILE="$VSCODE_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "{}" > "$SETTINGS_FILE"
fi

# Merge new settings using jq
tmp=$(mktemp)
jq --arg bin_dir "$LLVM_DIR/bin" \
   --arg clangd_path "$LLVM_DIR/bin/clangd" \
   --arg include_dir "$LLVM_DIR/include" \
   --arg new_path "$LLVM_DIR/bin:$PATH" \
   '. + {
       "cmake.additionalCompilerSearchDirs": [$bin_dir],
       "clangd.path": $clangd_path,
       "clangd.fallbackFlags": ["-I" + $include_dir],
       "cmake.configureEnvironment": { "PATH": $new_path }
    }' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

echo "VSCode workspace settings updated for LLVM version '$VERSION'."
echo "Please reload your VSCode window for changes to take effect."
