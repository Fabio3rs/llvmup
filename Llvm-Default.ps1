# Llvm-Default.ps1: LLVM default version manager for Windows
# Requirements: PowerShell v5 or later
# Usage:
#   . Llvm-Default.ps1 -Command <set|show> [-Version <version>]

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("set", "show", "unset")]
    [string]$Command,

    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Output "LLVM Default Version Manager for Windows"
    Write-Output ""
    Write-Output "Usage:"
    Write-Output "  Llvm-Default.ps1 -Command <set|show|unset> [-Version <version>]"
    Write-Output ""
    Write-Output "Commands:"
    Write-Output "  set     Set default LLVM version (requires -Version)"
    Write-Output "  show    Show current default LLVM version"
    Write-Output "  unset   Clear the current default LLVM version"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Version <version>  LLVM version to set as default"
    Write-Output "  -Help               Show this help message"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  Llvm-Default.ps1 -Command set -Version llvmorg-18.1.8"
    Write-Output "  Llvm-Default.ps1 -Command show"
    Write-Output "  Llvm-Default.ps1 -Command unset"
    exit 0
}

# Logging functions
function Write-LogInfo {
    param([string]$Message)
    Write-Output "ℹ️  $Message"
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Output "✅ $Message"
}

function Write-LogError {
    param([string]$Message)
    Write-Error "❌ $Message"
}

$coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
Import-Module $coreModulePath -Force -DisableNameChecking

function Set-DefaultVersion {
    param([string]$Version)

    if (-not $Version) {
        Write-LogError "Version parameter is required for 'set' command"
        Write-LogInfo "Usage: Llvm-Default.ps1 -Command set -Version <version>"
        return 1
    }

    $homeDir = Get-LlvmHomePath
    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $defaultPath = Get-LlvmDefaultPath -HomePath $homeDir
    try {
        Set-LlvmDefaultVersion -Version $Version -ToolchainsPath $toolchainsPath -HomePath $homeDir | Out-Null
        Write-LogSuccess "Default LLVM version set to: $Version"
        Write-LogInfo "💡 Default toolchain available at: $defaultPath"
    } catch {
        Write-LogError $_.Exception.Message
        return 1
    }
}

function Show-DefaultVersion {
    $homeDir = Get-LlvmHomePath
    $defaultPath = Get-LlvmDefaultPath -HomePath $homeDir

    if (Test-Path $defaultPath) {
        try {
            # Get the target of the junction
            $item = Get-Item $defaultPath
            if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
                $target = $item.Target
                $version = Split-Path $target -Leaf
                Write-LogInfo "📦 Current default LLVM version: $version"

                # Try to get clang version
                $clangPath = Join-Path $defaultPath "bin\clang.exe"
                if (Test-Path $clangPath) {
                    try {
                        $clangVersion = & $clangPath --version | Select-Object -First 1
                        Write-LogInfo "🔍 Clang version: $clangVersion"
                    } catch {
                        Write-LogInfo "🔍 Clang version: (unable to determine)"
                    }
                }
            } else {
                Write-LogError "Default path exists but is not a proper junction"
            }
        } catch {
            Write-LogError "Failed to read default version: $_"
            return 1
        }
    } else {
        Write-LogInfo "❌ No default LLVM version is set"
        Write-LogInfo "💡 Use 'Llvm-Default.ps1 -Command set -Version <version>' to set one"
    }
}

function Clear-DefaultVersion {
    $homeDir = Get-LlvmHomePath
    try {
        Clear-LlvmDefaultVersion -HomePath $homeDir | Out-Null
        Write-LogSuccess "Default LLVM version cleared"
    } catch {
        Write-LogError $_.Exception.Message
        return 1
    }
}

# Execute command
switch ($Command) {
    "set" {
        Set-DefaultVersion -Version $Version
    }
    "show" {
        Show-DefaultVersion
    }
    "unset" {
        Clear-DefaultVersion
    }
}
