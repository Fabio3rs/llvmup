# Llvm-Default.ps1: LLVM default version manager for Windows
# Requirements: PowerShell v5 or later
# Usage:
#   . Llvm-Default.ps1 -Command <set|show> [-Version <version>]

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("set", "show")]
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
    Write-Output "  Llvm-Default.ps1 -Command <set|show> [-Version <version>]"
    Write-Output ""
    Write-Output "Commands:"
    Write-Output "  set     Set default LLVM version (requires -Version)"
    Write-Output "  show    Show current default LLVM version"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Version <version>  LLVM version to set as default"
    Write-Output "  -Help               Show this help message"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  Llvm-Default.ps1 -Command set -Version llvmorg-18.1.8"
    Write-Output "  Llvm-Default.ps1 -Command show"
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

function Set-DefaultVersion {
    param([string]$Version)

    if (-not $Version) {
        Write-LogError "Version parameter is required for 'set' command"
        Write-LogInfo "Usage: Llvm-Default.ps1 -Command set -Version <version>"
        return 1
    }

    # Load helper and determine user home directory
    $modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
    if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
    $homeDir = Get-UserHome

    $defaultPath = Join-Path $homeDir ".llvm\default"
    $versionPath = Join-Path $homeDir ".llvm\toolchains\$Version"

    if (-not (Test-Path $versionPath)) {
        Write-LogError "Version $Version is not installed"
        Write-LogInfo "Available versions:"
    $toolchainsPath = Join-Path $homeDir ".llvm\toolchains"
        if (Test-Path $toolchainsPath) {
            Get-ChildItem $toolchainsPath -Directory | ForEach-Object {
                Write-LogInfo "  - $($_.Name)"
            }
        }
        return 1
    }

    # Remove existing default if it exists
    if (Test-Path $defaultPath) {
        Remove-Item $defaultPath -Force -Recurse
    }

    # Create directory junction (similar to symbolic link)
    try {
        New-Item -ItemType Junction -Path $defaultPath -Target $versionPath | Out-Null
        Write-LogSuccess "Default LLVM version set to: $Version"
        Write-LogInfo "💡 Default toolchain available at: $defaultPath"
    } catch {
        Write-LogError "Failed to create default version link: $_"
        return 1
    }
}

function Show-DefaultVersion {
    # Determine home directory cross-platform
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile) }

    $defaultPath = Join-Path $homeDir ".llvm\default"

    if (Test-Path $defaultPath) {
        try {
            # Get the target of the junction
            $item = Get-Item $defaultPath
            if ($item.LinkType -eq "Junction") {
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

# Execute command
switch ($Command) {
    "set" {
        Set-DefaultVersion -Version $Version
    }
    "show" {
        Show-DefaultVersion
    }
}
