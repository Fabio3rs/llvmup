#!/bin/bash
# install.sh: Installation script for the LLVM Version Manager tools.
# This script installs the following commands:
#   - llvm-manager      : Downloads and installs LLVM releases.
#   - llvm-activate     : Activates a selected LLVM version for the current shell.
#   - llvm-deactivate   : Deactivates the currently active LLVM version.
#
# The scripts are copied to $HOME/.local/bin. Make sure that this directory is in your PATH.
#
# Usage:
#   ./install.sh

set -e

# Define the installation directory
INSTALL_DIR="$HOME/.local/bin"

echo "Creating installation directory at $INSTALL_DIR (if it doesn't exist)..."
mkdir -p "$INSTALL_DIR"

echo "Copying scripts to $INSTALL_DIR..."
cp llvm_manager.sh "$INSTALL_DIR/llvm-manager"
cp activate_llvm.sh "$INSTALL_DIR/llvm-activate"
cp deactivate_llvm.sh "$INSTALL_DIR/llvm-deactivate"
cp activate_llvm_vscode.sh "$INSTALL_DIR/llvm-vscode-activate"

echo "Making scripts executable..."
chmod +x "$INSTALL_DIR/llvm-manager" "$INSTALL_DIR/llvm-activate" "$INSTALL_DIR/llvm-deactivate"

echo "Installation complete!"

# Check if INSTALL_DIR is in PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "Warning: $INSTALL_DIR is not in your PATH."
    echo "To add it temporarily for this session, run:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo "To add it permanently, add the above line to your ~/.bashrc or ~/.profile file."
else
    echo "$INSTALL_DIR is already in your PATH."
fi

echo "You can now use the commands 'llvm-manager', 'llvm-activate', and 'llvm-deactivate' from any terminal."

