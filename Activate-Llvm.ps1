# Activate-Llvm.ps1: Activates a specific LLVM version for the current session.
# Usage:
#   . Activate-Llvm.ps1             -> Lists available versions
#   . Activate-Llvm.ps1 <version>   -> Activates the specified version

param (
    [Parameter(Mandatory = $false)]
    [string]$Version
)

$toolchainsDir = Join-Path $env:USERPROFILE ".llvm/toolchains"

# If no version is specified, list installed versions
if (-not $Version) {
    Write-Output "Installed versions in ${toolchainsDir}:"
    if (Test-Path $toolchainsDir) {
        Get-ChildItem -Directory $toolchainsDir | ForEach-Object {
            Write-Output "  - $($_.Name)"
        }
    } else {
        Write-Output "No versions installed in ${toolchainsDir}."
    }
    return
}

$llvmDir = Join-Path $toolchainsDir $Version

# Check if the version is installed
if (-not (Test-Path $llvmDir)) {
    Write-Error "Version '$Version' is not installed in ${toolchainsDir}."
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
}

# Update PATH to include the selected LLVM's bin directory
$env:PATH = "$($llvmDir)/bin;$env:PATH"

# Update compiler variables (CC and CXX)
$env:CC = Join-Path $llvmDir "bin/clang.exe"
$env:CXX = Join-Path $llvmDir "bin/clang++.exe"

# Update LD if lld exists
if (Test-Path (Join-Path $llvmDir "bin/lld.exe")) {
    $env:LD = Join-Path $llvmDir "bin/lld.exe"
}

# Set internal variable to indicate active version
$env:_ACTIVE_LLVM = $Version

# Prompt customization: enabled by default; user can disable via environment var
# If LLVMUP_DISABLE_PROMPT is set to '1' or 'true' (case-insensitive), skip prompt wrapping
$disablePrompt = $false
if ($env:LLVMUP_DISABLE_PROMPT) {
    if ($env:LLVMUP_DISABLE_PROMPT -eq '1' -or $env:LLVMUP_DISABLE_PROMPT.ToLower() -eq 'true') {
        $disablePrompt = $true
    }
}

if (-not $disablePrompt) {
    try {
        # Save original prompt function if not already saved
        if (-not (Test-Path Function:\__llvm_original_prompt)) {
            if (Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue) {
                $orig = (Get-Command prompt).ScriptBlock.ToString()
                Set-Item -Path Function:\__llvm_original_prompt -Value ([ScriptBlock]::Create($orig))
            } else {
                # Provide a basic fallback prompt implementation
                Set-Item -Path Function:\__llvm_original_prompt -Value { "PS " + (Get-Location) + "> " }
            }
        }

        # Create a lightweight wrapper prompt that prefixes the active LLVM version
        Set-Item -Path Function:\prompt -Value {
            try {
                $versionPrefix = if ($env:_ACTIVE_LLVM) {"(LLVM: $($env:_ACTIVE_LLVM)) " } else {""}
                return $versionPrefix + (& __llvm_original_prompt)
            } catch {
                return "(LLVM: $($env:_ACTIVE_LLVM)) "
            }
        }
    } catch {
        Write-Warning "Failed to set prompt wrapper: $($_.Exception.Message)"
    }
}

Write-Output "LLVM version '$Version' activated for this session."
Write-Output "CC, CXX, and LD have been set; PATH and PS1 have been updated."
Write-Output "To deactivate, run 'Deactivate-Llvm.ps1'."
