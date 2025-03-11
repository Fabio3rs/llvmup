# Activate-Llvm.ps1
param (
    [Parameter(Mandatory = $false)]
    [string]$Version
)

# Check if an LLVM version is already active.
if ($global:ACTIVE_LLVM_VERSION) {
    Write-Error "Another LLVM version ('$global:ACTIVE_LLVM_VERSION') is already active. Please deactivate it first."
    exit 1
}

$toolchainsDir = "$env:USERPROFILE\.llvm\toolchains"

if (-not $Version) {
    Write-Output "Installed LLVM versions:"
    if (Test-Path $toolchainsDir) {
        Get-ChildItem -Directory $toolchainsDir | ForEach-Object {
            Write-Output " - $($_.Name)"
        }
    }
    return
}

$llvmDir = Join-Path $toolchainsDir $Version

if (-not (Test-Path $llvmDir)) {
    Write-Error "Version '$Version' is not installed in $toolchainsDir."
    return
}

# Backup current environment variables if not already backed up
if (-not $env:_OLD_PATH) {
    $env:_OLD_PATH = $env:PATH
    $env:_OLD_CC   = $env:CC
    $env:_OLD_CXX  = $env:CXX
    # ... add other variables as needed
}

# Update PATH for current session
$env:PATH = "$($llvmDir)\bin;" + $env:PATH
# Optionally, set CC and CXX to point to the LLVM binaries:
$env:CC  = Join-Path $llvmDir "bin\clang.exe"
$env:CXX = Join-Path $llvmDir "bin\clang++.exe"

# Backup the original prompt function if not already done
if (-not $global:OLD_PROMPT) {
    $global:OLD_PROMPT = (Get-Command prompt).ScriptBlock
}

# Save the active LLVM version in a global variable
$global:ACTIVE_LLVM_VERSION = $Version

# Define a new prompt function that indicates the active LLVM version
function global:prompt {
    "(`$LLVM: $global:ACTIVE_LLVM_VERSION) " + (& $global:OLD_PROMPT)
}

Write-Output "LLVM version '$Version' activated for this session."
