# Deactivate-Llvm.ps1: Deactivates the currently active LLVM version.
# Usage:
#   . Deactivate-Llvm.ps1

# Check if any version is active
if (-not $env:_ACTIVE_LLVM) {
    Write-Output "No LLVM version is currently active."
    return 0
}

# Restore original environment variables
if ($env:_OLD_PATH) {
    $env:PATH = $env:_OLD_PATH
    $env:CC = $env:_OLD_CC
    $env:CXX = $env:_OLD_CXX
    $env:LD = $env:_OLD_LD
    $env:PS1 = $env:_OLD_PS1

    # Clear backup variables
    Remove-Item Env:\_OLD_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_CC -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_CXX -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_LD -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_PS1 -ErrorAction SilentlyContinue
}

# Clear active version indicator
Remove-Item Env:\_ACTIVE_LLVM -ErrorAction SilentlyContinue

Write-Output "LLVM version deactivated. Environment variables restored."
