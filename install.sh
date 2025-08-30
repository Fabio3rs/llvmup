#!/bin/bash
# install.sh: Installation script for the LLVMUP tools.
# This script installs the following commands:
#   - llvm-prebuilt   : Downloads and installs pre-built LLVM releases.
#   - llvm-activate   : Activates a selected LLVM version for the current shell.
#   - llvm-deactivate : Deactivates the currently active LLVM version.
#   - llvm-vscode-activate : Updates VSCode workspace settings with the selected LLVM configuration.
#   - llvmup          : Wrapper command to choose between source build or pre-built install (use --from-source for source build).
#   - llvmup-completion.sh : Bash completion script for llvmup commands.
#
# The scripts are copied to $HOME/.local/bin. Make sure that this directory is in your PATH.
#
# Usage:
#   ./install.sh

set -e

# Define the installation directory.
INSTALL_DIR="$HOME/.local/bin"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
FUNCTIONS_FILE="$INSTALL_DIR/llvm-functions.sh"

echo "Creating installation directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$COMPLETION_DIR"

# Define an associative array mapping source filenames to target filenames.
declare -A scripts=(
    ["llvm-prebuilt"]="llvm-prebuilt"
    ["llvm-activate"]="llvm-activate"
    ["llvm-deactivate"]="llvm-deactivate"
    ["llvm-vscode-activate"]="llvm-vscode-activate"
    ["llvm-build"]="llvm-build"
    ["llvmup"]="llvmup"
    ["llvm-functions.sh"]="llvm-functions.sh"
)

echo "Copying scripts to $INSTALL_DIR..."
for src in "${!scripts[@]}"; do
    if [ ! -f "$src" ]; then
        echo "Error: Script '$src' not found in the current directory."
        exit 1
    fi
    cp "$src" "$INSTALL_DIR/${scripts[$src]}"
done

echo "Installing bash completion..."
if [ -f "llvmup-completion.sh" ]; then
    cp "llvmup-completion.sh" "$COMPLETION_DIR/llvmup"
    echo "Bash completion installed to $COMPLETION_DIR/llvmup"
fi

echo "Making scripts executable..."
chmod +x "$INSTALL_DIR/llvm-prebuilt" "$INSTALL_DIR/llvm-activate" "$INSTALL_DIR/llvm-deactivate" "$INSTALL_DIR/llvm-vscode-activate" "$INSTALL_DIR/llvm-build" "$INSTALL_DIR/llvmup"

# Also make uninstall script executable if it exists
if [ -f "uninstall.sh" ]; then
    chmod +x uninstall.sh
fi

# Function to add source line to profile if not already present
add_to_profile() {
    local profile_file="$1"
    local source_line="# LLVM Manager Functions
if [ -f \"$FUNCTIONS_FILE\" ]; then
    source \"$FUNCTIONS_FILE\"
fi"

    if [ -f "$profile_file" ]; then
        if ! grep -q "llvm-functions.sh" "$profile_file"; then
            echo "" >> "$profile_file"
            echo "$source_line" >> "$profile_file"
            echo "Added LLVM functions to $profile_file"
            return 0
        else
            echo "LLVM functions already configured in $profile_file"
            return 1
        fi
    fi
    return 1
}

# Try to add to user's profile files
echo "Configuring shell profile..."
profile_configured=false

# Try .bashrc first (most common for interactive bash)
if add_to_profile "$HOME/.bashrc"; then
    profile_configured=true
fi

# If .bashrc doesn't exist or wasn't modified, try .profile
if [ "$profile_configured" = false ]; then
    if add_to_profile "$HOME/.profile"; then
        profile_configured=true
    fi
fi

# If neither exists, create .bashrc
if [ "$profile_configured" = false ]; then
    if [ ! -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.profile" ]; then
        echo "Creating $HOME/.bashrc..."
        cat > "$HOME/.bashrc" << EOF
# ~/.bashrc: executed by bash(1) for non-login shells.

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific aliases and functions
# You can add your custom configuration here

# LLVM Manager Functions
if [ -f "$FUNCTIONS_FILE" ]; then
    source "$FUNCTIONS_FILE"
fi
EOF
        echo "Created $HOME/.bashrc with LLVM functions"
        profile_configured=true
    fi
fi

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

# Check if bash-completion is installed
if ! command -v bash-completion &> /dev/null; then
    echo "Note: bash-completion is not installed. To enable command completion, install bash-completion:"
    echo "  Ubuntu/Debian: sudo apt-get install bash-completion"
    echo "  Fedora: sudo dnf install bash-completion"
    echo "  macOS: brew install bash-completion"
fi

echo "You can now use the following commands from any terminal:"
echo "  llvmup              : Wrapper command (use --from-source to build from source)"
echo "  llvm-prebuilt       : Download and install pre-built LLVM releases"
echo "  llvm-activate       : Activate a selected LLVM version (bash function)"
echo "  llvm-deactivate     : Deactivate the active LLVM version (bash function)"
echo "  llvm-vscode-activate: Update VSCode workspace settings (bash function)"
echo "  llvm-status         : Show current LLVM status (bash function)"
echo "  llvm-list           : List installed LLVM versions (bash function)"
echo ""
if [ "$profile_configured" = true ]; then
    echo "LLVM functions have been added to your shell profile."
    echo "Start a new terminal session or run 'source ~/.bashrc' (or ~/.profile) to use the functions."
else
    echo "Could not automatically configure shell profile."
    echo "To manually enable LLVM functions, add this line to your ~/.bashrc or ~/.profile:"
    echo "  source \"$FUNCTIONS_FILE\""
fi
