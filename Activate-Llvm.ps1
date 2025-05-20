# Activate-Llvm.ps1: Activates a specific LLVM version for the current session.
# Usage:
#   . Activate-Llvm.ps1             -> Lists available versions
#   . Activate-Llvm.ps1 <version>   -> Activates the specified version

param (
    [Parameter(Mandatory = $false)]
    [string]$Version
)

$toolchainsDir = Join-Path $env:USERPROFILE ".llvm\toolchains"

# If no version is specified, list installed versions
if (-not $Version) {
    Write-Output "Installed versions in $toolchainsDir:"
    if (Test-Path $toolchainsDir) {
        Get-ChildItem -Directory $toolchainsDir | ForEach-Object {
            Write-Output "  - $($_.Name)"
        }
    } else {
        Write-Output "No versions installed in $toolchainsDir."
    }
    return
}

$llvmDir = Join-Path $toolchainsDir $Version

# Check if the version is installed
if (-not (Test-Path $llvmDir)) {
    Write-Error "Version '$Version' is not installed in $toolchainsDir."
    return 1
}

# Check if another version is already active
if ($env:_ACTIVE_LLVM) {
    Write-Error "Another version is already active: $env:_ACTIVE_LLVM."
    Write-Error "To change, run 'Deactivate-Llvm.ps1' first."
    return 1
}

# Backup environment variables if not already backed up
if (-not $env:_OLD_PATH) {
    $env:_OLD_PATH = $env:PATH
    $env:_OLD_CC = $env:CC
    $env:_OLD_CXX = $env:CXX
    $env:_OLD_LD = $env:LD
    $env:_OLD_PS1 = $env:PS1
}

# Update PATH to include the selected LLVM's bin directory
$env:PATH = "$($llvmDir)\bin;$env:PATH"

# Update compiler variables (CC and CXX)
$env:CC = Join-Path $llvmDir "bin\clang.exe"
$env:CXX = Join-Path $llvmDir "bin\clang++.exe"

# Update LD if lld exists
if (Test-Path (Join-Path $llvmDir "bin\lld.exe")) {
    $env:LD = Join-Path $llvmDir "bin\lld.exe"
}

# Modify the prompt to indicate active LLVM version
$env:PS1 = "(LLVM: $Version) $env:_OLD_PS1"

# Set internal variable to indicate active version
$env:_ACTIVE_LLVM = $Version

Write-Output "LLVM version '$Version' activated for this session."
Write-Output "CC, CXX, and LD have been set; PATH and PS1 have been updated."
Write-Output "To deactivate, run 'Deactivate-Llvm.ps1'."
