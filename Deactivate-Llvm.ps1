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

    # Clear backup variables
    Remove-Item Env:\_OLD_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_CC -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_CXX -ErrorAction SilentlyContinue
    Remove-Item Env:\_OLD_LD -ErrorAction SilentlyContinue
    # Remove any saved original prompt function and restore prompt if present
    if (Test-Path Function:\__llvm_original_prompt) {
        try {
            # Restore original prompt function
            $orig = Get-Item -Path Function:\__llvm_original_prompt
            if ($orig) {
                Set-Item -Path Function:\prompt -Value $orig.Value
            }
        } catch {
            # ignore
        }
        Remove-Item -Path Function:\__llvm_original_prompt -ErrorAction SilentlyContinue
    }
}

# Clear active version indicator
Remove-Item Env:\_ACTIVE_LLVM -ErrorAction SilentlyContinue

Write-Output "LLVM version deactivated. Environment variables restored."
