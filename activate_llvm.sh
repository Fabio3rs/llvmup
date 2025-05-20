#!/bin/bash
# activate_llvm.sh: Activates a specific LLVM version for the current session.
# Usage:
#   source activate_llvm.sh             -> Lists available versions
#   source activate_llvm.sh <version>   -> Activates the specified version

LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"

# If no argument is passed, list installed versions
if [ "$#" -eq 0 ]; then
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
    return 0 2>/dev/null || exit 0
fi

VERSION="$1"
export LLVM_DIR="$LLVM_TOOLCHAINS_DIR/$VERSION"

if [ ! -d "$LLVM_DIR" ]; then
    echo "Version '$VERSION' is not installed in $LLVM_TOOLCHAINS_DIR."
    return 1 2>/dev/null || exit 1
fi

# Check if another version is already active
if [ -n "$_ACTIVE_LLVM" ]; then
    echo "Another version is already active: $_ACTIVE_LLVM."
    echo "To change, run 'source deactivate_llvm.sh' first."
    return 1 2>/dev/null || exit 1
fi

# Backup environment variables if not already backed up
[ -z "$_OLD_PATH" ] && export _OLD_PATH="$PATH"
[ -z "$_OLD_CC" ] && export _OLD_CC="${CC:-}"
[ -z "$_OLD_CXX" ] && export _OLD_CXX="${CXX:-}"
[ -z "$_OLD_LD" ] && export _OLD_LD="${LD:-}"
[ -z "$_OLD_PS1" ] && export _OLD_PS1="$PS1"

# Update PATH to include the selected LLVM's bin directory
export PATH="$LLVM_DIR/bin:$PATH"

# Update compiler variables (CC and CXX)
export CC="$LLVM_DIR/bin/clang"
export CXX="$LLVM_DIR/bin/clang++"

# Update LD if lld exists
if [ -x "$LLVM_DIR/bin/lld" ]; then
    export LD="$LLVM_DIR/bin/lld"
fi

# Modify the prompt to indicate active LLVM version
export PS1="(LLVM: $VERSION) $_OLD_PS1"

# Set internal variable to indicate active version
export _ACTIVE_LLVM="$VERSION"

echo "LLVM version '$VERSION' activated for this session."
echo "CC, CXX, and LD have been set; PATH and PS1 have been updated."
echo "To deactivate, run 'source deactivate_llvm.sh'."
