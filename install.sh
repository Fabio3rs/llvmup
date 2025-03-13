#!/bin/bash
# install.sh: Installation script for the LLVMUP tools.
# This script installs the following commands:
#   - llvmup-prebuilt.sh   : Downloads and installs pre-built LLVM releases.
#   - llvmup-build.sh     : Builds LLVM from source.
#   - llvmup              : Wrapper command to choose between source build or pre-built install (use --from-source for source build).
#   - llvmup-activate.sh  : Activates a selected LLVM version for the current shell.
#   - llvmup-deactivate.sh: Deactivates the currently active LLVM version.
#   - llvmup-vscode.sh    : Updates VSCode workspace settings with the selected LLVM configuration.
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
    ["llvm_prebuilt.sh"]="llvmup-prebuilt.sh"
    ["activate_llvm.sh"]="llvmup-activate.sh"
    ["deactivate_llvm.sh"]="llvmup-deactivate.sh"
    ["activate_llvm_vscode.sh"]="llvmup-vscode.sh"
    ["build_llvm_source.sh"]="llvmup-build.sh"
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
chmod +x "$INSTALL_DIR/llvmup-prebuilt.sh" "$INSTALL_DIR/llvmup-activate.sh" "$INSTALL_DIR/llvmup-deactivate.sh" "$INSTALL_DIR/llvmup-vscode.sh" "$INSTALL_DIR/llvmup-build.sh" "$INSTALL_DIR/llvmup"

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
echo "  llvmup-prebuilt.sh   : Download and install pre-built LLVM releases."
echo "  llvmup-build.sh     : Build LLVM from source."
echo "  llvmup              : Wrapper command (use --from-source to build from source)."
echo "  llvmup-activate.sh  : Activate a selected LLVM version for the current shell."
echo "  llvmup-deactivate.sh: Deactivate the active LLVM version."
echo "  llvmup-vscode.sh    : Update VSCode workspace settings with the selected LLVM configuration."
