#!/bin/bash
# install-examples.sh: Demonstration of different installation modes for LLVMUP

set -e

echo "🚀 LLVMUP Installation Examples"
echo "This script demonstrates different ways to install LLVMUP"
echo ""

# Function to print colored headers
print_header() {
    echo -e "\033[1;36m=== $1 ===\033[0m"
}

print_example() {
    echo -e "\033[1;33m$1\033[0m"
    echo -e "\033[0;37m$2\033[0m"
    echo ""
}

print_header "Available Installation Modes"
echo ""

print_example "1. Default User Installation" \
"./install.sh
# Installs to ~/.local/bin (default)
# Automatically configures shell profile"

print_example "2. Custom User Directory" \
"LLVMUP_INSTALL_DIR=~/bin ./install.sh
# Install scripts to ~/bin instead of ~/.local/bin"

print_example "3. Custom Prefix" \
"LLVMUP_PREFIX=~/.llvmup ./install.sh
# Install to ~/.llvmup/bin and ~/.llvmup/share/bash-completion/completions"

print_example "4. System-Wide Installation" \
"LLVMUP_SYSTEM_INSTALL=1 ./install.sh
# Install to /usr/local/bin (requires sudo)
# Does not modify user shell profiles"

print_example "5. Custom System Directory" \
"LLVMUP_PREFIX=/opt/llvmup ./install.sh
# Install to /opt/llvmup/bin"

print_example "6. Development/Testing Setup" \
"LLVMUP_PREFIX=\$PWD/test-install ./install.sh
# Install to current directory for testing"

print_header "Environment Variables Reference"

cat << 'EOF'
LLVMUP_PREFIX        : Base installation prefix (default: $HOME/.local)
LLVMUP_INSTALL_DIR   : Directory for executable scripts
                       (default: $LLVMUP_PREFIX/bin)
LLVMUP_COMPLETION_DIR: Directory for bash completion
                       (default: $LLVMUP_PREFIX/share/bash-completion/completions)
LLVMUP_SYSTEM_INSTALL: Set to 1 for system-wide installation
                       (default prefix becomes /usr/local, requires sudo)
EOF

print_header "Interactive Installation Helper"
echo ""

read -p "Would you like to run an interactive installation? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Choose installation type:"
    echo "1) Default user installation (~/.local/bin)"
    echo "2) Custom user directory"
    echo "3) System-wide installation (/usr/local/bin)"
    echo "4) Custom prefix"
    echo ""
    read -p "Enter choice (1-4): " -n 1 -r choice
    echo ""

    case $choice in
        1)
            echo "Running: ./install.sh"
            ./install.sh
            ;;
        2)
            read -p "Enter custom directory: " custom_dir
            echo "Running: LLVMUP_INSTALL_DIR='$custom_dir' ./install.sh"
            LLVMUP_INSTALL_DIR="$custom_dir" ./install.sh
            ;;
        3)
            echo "Running: LLVMUP_SYSTEM_INSTALL=1 ./install.sh"
            LLVMUP_SYSTEM_INSTALL=1 ./install.sh
            ;;
        4)
            read -p "Enter custom prefix: " custom_prefix
            echo "Running: LLVMUP_PREFIX='$custom_prefix' ./install.sh"
            LLVMUP_PREFIX="$custom_prefix" ./install.sh
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    echo "Installation examples shown above. Run ./install.sh with desired environment variables."
fi
