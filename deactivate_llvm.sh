#!/bin/bash
# deactivate_llvm.sh: Deactivates the currently active LLVM version.
# Usage:
#   source deactivate_llvm.sh

# Check if any version is active
if [ -z "$_ACTIVE_LLVM" ]; then
    echo "No LLVM version is currently active."
    return 0 2>/dev/null || exit 0
fi

# Restore original environment variables
if [ -n "$_OLD_PATH" ]; then
    export PATH="$_OLD_PATH"
    export CC="$_OLD_CC"
    export CXX="$_OLD_CXX"
    export LD="$_OLD_LD"
    export PS1="$_OLD_PS1"

    # Clear backup variables
    unset _OLD_PATH
    unset _OLD_CC
    unset _OLD_CXX
    unset _OLD_LD
    unset _OLD_PS1
fi

# Clear active version indicator
unset _ACTIVE_LLVM
unset LLVM_DIR

echo "LLVM version deactivated. Environment variables restored."
