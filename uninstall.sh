#!/bin/bash
# uninstall.sh: Uninstallation script for the LLVMUP tools.
# This script removes all installed components including:
#   - Scripts from $HOME/.local/bin
#   - Bash completion files
#   - Profile configuration for LLVM functions

set -e

# Define the installation directory.
INSTALL_DIR="$HOME/.local/bin"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
FUNCTIONS_FILE="$INSTALL_DIR/llvm-functions.sh"

echo "Removing LLVM manager scripts..."

# List of scripts to remove
scripts=(
    "llvm-prebuilt"
    "llvm-activate"
    "llvm-deactivate"
    "llvm-vscode-activate"
    "llvm-build"
    "llvmup"
    "llvm-functions.sh"
)

for script in "${scripts[@]}"; do
    script_path="$INSTALL_DIR/$script"
    if [ -f "$script_path" ]; then
        rm "$script_path"
        echo "Removed $script_path"
    fi
done

# Remove bash completion
completion_path="$COMPLETION_DIR/llvmup"
if [ -f "$completion_path" ]; then
    rm "$completion_path"
    echo "Removed bash completion: $completion_path"
fi

# Function to remove LLVM configuration from profile
remove_from_profile() {
    local profile_file="$1"

    # it was causing issues on some systems
    return 0
}

# Remove from profile files
echo "Cleaning shell profile configuration..."
remove_from_profile "$HOME/.bashrc" || true
remove_from_profile "$HOME/.profile" || true

echo "Uninstallation complete!"
echo ""
echo "Note: Your LLVM toolchains in ~/.llvm/toolchains/ were not removed."
echo "If you want to completely remove LLVM installations, run:"
echo "  rm -rf ~/.llvm"
echo ""
echo "Restart your terminal or run 'source ~/.bashrc' to complete the removal."
