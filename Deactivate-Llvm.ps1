# Deactivate-Llvm.ps1: Deactivates the currently active LLVM version.
# Usage:
#   . Deactivate-Llvm.ps1

# Check if any version is active
if (-not $env:_ACTIVE_LLVM) {
    Write-Output "No LLVM version is currently active."
    return 0
}

$coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
if ($env:_LLVM_BACKUP -and (Test-Path -LiteralPath $coreModulePath)) {
    Import-Module $coreModulePath -Force -DisableNameChecking
    $null = Invoke-LlvmDeactivate
} elseif ($env:_OLD_PATH) {
    $env:PATH = $env:_OLD_PATH
    foreach ($pair in @(
        @('CC', '_OLD_CC'),
        @('CXX', '_OLD_CXX'),
        @('LD', '_OLD_LD')
    )) {
        $oldVal = [Environment]::GetEnvironmentVariable($pair[1], 'Process')
        if ([string]::IsNullOrEmpty($oldVal)) {
            [Environment]::SetEnvironmentVariable($pair[0], $null, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($pair[0], $oldVal, 'Process')
        }
        [Environment]::SetEnvironmentVariable($pair[1], $null, 'Process')
    }
    Remove-Item Env:\_OLD_PATH -ErrorAction SilentlyContinue
}

# Remove any saved original prompt function and restore prompt if present
if (Test-Path Function:\__llvm_original_prompt) {
    try {
        $orig = Get-Item -Path Function:\__llvm_original_prompt
        if ($orig) {
            Set-Item -Path Function:\prompt -Value $orig.Value
        }
    } catch {}
    Remove-Item -Path Function:\__llvm_original_prompt -ErrorAction SilentlyContinue
}

# Clear active version indicator
Remove-Item Env:\_ACTIVE_LLVM -ErrorAction SilentlyContinue
Remove-Item Env:\_ACTIVE_LLVM_PATH -ErrorAction SilentlyContinue

Write-Output "LLVM version deactivated. Environment variables restored."
