#!/bin/bash
# uninstall.sh: Uninstallation script for the LLVMUP tools.
# This script removes all installed components including:
#   - Scripts from installation directory
#   - Bash completion files
#   - Profile configuration for LLVM functions
#
# Environment Variables (same as install.sh):
#   LLVMUP_PREFIX       : Base installation prefix (default: $HOME/.local)
#   LLVMUP_INSTALL_DIR  : Directory where scripts were installed
#   LLVMUP_COMPLETION_DIR: Directory where bash completion was installed
#   LLVMUP_SYSTEM_INSTALL: Set to 1 if original installation was system-wide

set -e

# Color output functions
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Determine installation directories (same logic as install.sh)
if [ -n "$LLVMUP_SYSTEM_INSTALL" ] && [ "$LLVMUP_SYSTEM_INSTALL" = "1" ]; then
    DEFAULT_PREFIX="/usr/local"
    REQUIRES_SUDO=true
    print_info "System-wide uninstallation mode enabled"
else
    DEFAULT_PREFIX="$HOME/.local"
    REQUIRES_SUDO=false
fi

PREFIX="${LLVMUP_PREFIX:-$DEFAULT_PREFIX}"
INSTALL_DIR="${LLVMUP_INSTALL_DIR:-$PREFIX/bin}"
COMPLETION_DIR="${LLVMUP_COMPLETION_DIR:-$PREFIX/share/bash-completion/completions}"
FUNCTIONS_FILE="$INSTALL_DIR/llvm-functions.sh"

print_info "Uninstallation Configuration:"
print_info "  Install Directory: $INSTALL_DIR"
print_info "  Completion Directory: $COMPLETION_DIR"
print_info "  Functions File: $FUNCTIONS_FILE"
print_info "  System Uninstall: $($REQUIRES_SUDO && echo "Yes (requires sudo)" || echo "No")"

# Check for sudo if required
if [ "$REQUIRES_SUDO" = true ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        print_error "System uninstallation requires sudo, but sudo is not available"
        exit 1
    fi
    SUDO_CMD="sudo"
else
    SUDO_CMD=""
fi

print_info "Removing LLVM manager scripts..."

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
        $SUDO_CMD rm "$script_path"
        print_success "Removed $script_path"
    else
        print_warning "Script not found: $script_path"
    fi
done

# Remove bash completion
completion_path="$COMPLETION_DIR/llvmup"
if [ -f "$completion_path" ]; then
    $SUDO_CMD rm "$completion_path"
    print_success "Removed bash completion: $completion_path"
else
    print_warning "Bash completion not found: $completion_path"
fi

# Function to safely remove LLVM configuration from profile
safe_remove_from_profile() {
    local profile_file="$1"

    if [ ! -f "$profile_file" ]; then
        return 0
    fi

    # Create a backup
    cp "$profile_file" "$profile_file.llvmup-backup"

    # Method 1: Remove using safe markers (preferred for new installations)
    if grep -q "# LLVM Manager Functions - Start" "$profile_file"; then
        sed -i '/# LLVM Manager Functions - Start/,/# LLVM Manager Functions - End/d' "$profile_file"
        print_info "Removed LLVM configuration using safety markers from $profile_file"

    # Method 2: Careful removal for old installations (without markers)
    elif grep -q "# LLVM Manager Functions" "$profile_file"; then
        print_warning "Found old-format LLVM configuration in $profile_file"
        print_info "Using conservative removal method..."

        # Use awk for more precise removal
        awk '
        BEGIN { in_llvm = 0; skip_blank = 0 }

        # Detect start of LLVM section
        /^# LLVM Manager Functions$/ {
            in_llvm = 1
            skip_blank = 1
            next
        }

        # In LLVM section - skip known patterns
        in_llvm && /^if \[ -f.*llvm-functions\.sh.*\]; then$/ { next }
        in_llvm && /^[[:space:]]*source.*llvm-functions\.sh.*$/ { next }
        in_llvm && /^fi$/ {
            in_llvm = 0
            skip_blank = 1
            next
        }

        # Skip one blank line after LLVM section
        skip_blank && /^$/ {
            skip_blank = 0
            next
        }

        # Print everything else
        !in_llvm { print }
        ' "$profile_file" > "$profile_file.tmp" && mv "$profile_file.tmp" "$profile_file"

        print_info "Conservative removal completed for $profile_file"
    else
        print_info "No LLVM configuration found in $profile_file"
    fi

    print_info "Backup created at $profile_file.llvmup-backup"
}

# Remove from profile files (only for user installations)
if [ "$REQUIRES_SUDO" = false ]; then
    print_info "Cleaning shell profile configuration..."
    safe_remove_from_profile "$HOME/.bashrc" || true
    safe_remove_from_profile "$HOME/.profile" || true
else
    print_info "System-wide uninstallation - skipping user profile cleanup"
fi

print_success "Uninstallation complete!"
echo ""

print_info "What was removed:"
echo "  ✓ LLVM manager scripts from $INSTALL_DIR"
echo "  ✓ Bash completion from $COMPLETION_DIR"
if [ "$REQUIRES_SUDO" = false ]; then
    echo "  ✓ Shell profile configuration (with backup)"
fi

echo ""
print_warning "Your LLVM toolchains in ~/.llvm/toolchains/ were NOT removed."
print_info "If you want to completely remove LLVM installations, run:"
echo "  rm -rf ~/.llvm"

echo ""
if [ "$REQUIRES_SUDO" = false ]; then
    print_info "Restart your terminal or run 'source ~/.bashrc' to complete the removal."
else
    print_info "System-wide uninstallation complete. Users may need to update their profiles."
fi
