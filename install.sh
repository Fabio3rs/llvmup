#!/bin/bash
# install.sh: Installation script for the LLVMUP tools.
# This script installs the following commands:
#   - llvm-prebuilt   : Downloads and installs pre-built LLVM releases.
#   - llvm-activate   : Activates a selected LLVM version for the current shell.
#   - llvm-deactivate : Deactivates the currently active LLVM version.
#   - llvm-vscode-activate : Updates VSCode workspace settings with the selected LLVM configuration.
#   - llvmup          : Wrapper command to choose between source build or pre-built install (use --from-source for source build).
#
# The scripts are copied to $HOME/.local/bin. Make sure that this directory is in your PATH.
#
# Usage:
#   ./install.sh

set -e

# Define the installation directory.
INSTALL_DIR="$HOME/.local/bin"

echo "Creating installation directory at $INSTALL_DIR (if it doesn't exist)..."
mkdir -p "$INSTALL_DIR"

# Define an associative array mapping source filenames to target filenames.
declare -A scripts=(
    ["llvm-prebuilt"]="llvm-prebuilt"
    ["llvm-activate"]="llvm-activate"
    ["llvm-deactivate"]="llvm-deactivate"
    ["llvm-vscode-activate"]="llvm-vscode-activate"
    ["llvm-build"]="llvm-build"
    ["llvmup"]="llvmup"
)

echo "Copying scripts to $INSTALL_DIR..."
for src in "${!scripts[@]}"; do
    if [ ! -f "$src" ]; then
        echo "Error: Script '$src' not found in the current directory."
        exit 1
    fi
    cp "$src" "$INSTALL_DIR/${scripts[$src]}"
done

echo "Making scripts executable..."
chmod +x "$INSTALL_DIR/llvm-prebuilt" "$INSTALL_DIR/llvm-activate" "$INSTALL_DIR/llvm-deactivate" "$INSTALL_DIR/llvm-vscode-activate" "$INSTALL_DIR/llvm-build" "$INSTALL_DIR/llvmup"

echo "Installation complete!"

# Check if INSTALL_DIR is in PATH.
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "Warning: $INSTALL_DIR is not in your PATH."
    echo "To add it temporarily for this session, run:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo "To add it permanently, add the above line to your ~/.bashrc or ~/.profile file."
else
    echo "$INSTALL_DIR is already in your PATH."
fi

echo "You can now use the following commands from any terminal:"
echo "  llvmup              : Wrapper command (use --from-source to build from source)"
echo "  llvm-prebuilt       : Download and install pre-built LLVM releases"
echo "  llvm-activate       : Activate a selected LLVM version for the current shell"
echo "  llvm-deactivate     : Deactivate the active LLVM version"
echo "  llvm-vscode-activate: Update VSCode workspace settings with the selected LLVM configuration"
