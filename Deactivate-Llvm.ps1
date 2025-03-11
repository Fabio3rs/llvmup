# Deactivate-Llvm.ps1
# This script reverts the changes made by Activate-Llvm.ps1 for the current session.

# Check if an active LLVM version exists.
if (-not $global:ACTIVE_LLVM_VERSION) {
    Write-Output "No active LLVM version found."
    exit 0
}

# Restore PATH
if ($env:_OLD_PATH) {
    $env:PATH = $env:_OLD_PATH
    Remove-Item Env:_OLD_PATH
} else {
    Write-Output "No backup PATH found."
}

# Restore CC
if ($env:_OLD_CC) {
    $env:CC = $env:_OLD_CC
    Remove-Item Env:_OLD_CC
} else {
    Remove-Item Env:CC -ErrorAction SilentlyContinue
}

# Restore CXX
if ($env:_OLD_CXX) {
    $env:CXX = $env:_OLD_CXX
    Remove-Item Env:_OLD_CXX
} else {
    Remove-Item Env:CXX -ErrorAction SilentlyContinue
}

# Restore the original prompt function from the backup
if ($global:OLD_PROMPT) {
    Set-Item -Path function:prompt -Value $global:OLD_PROMPT
    Remove-Variable -Name OLD_PROMPT -Scope Global
} else {
    Write-Output "No backup prompt found."
}

# Remove the active LLVM version global variable if it exists
if ($global:ACTIVE_LLVM_VERSION) {
    Remove-Variable -Name ACTIVE_LLVM_VERSION -Scope Global
}

Write-Output "LLVM deactivated for this session."
