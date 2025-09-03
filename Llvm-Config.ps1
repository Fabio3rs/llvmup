# Llvm-Config.ps1: LLVM project configuration management for Windows
# Requirements: PowerShell v5 or later
# Usage:
#   . Llvm-Config.ps1 -Command <init|load> [options]

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("init", "load")]
    [string]$Command,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Output "LLVM Configuration Manager for Windows"
    Write-Output ""
    Write-Output "Usage:"
    Write-Output "  Llvm-Config.ps1 -Command <init|load> [options]"
    Write-Output ""
    Write-Output "Commands:"
    Write-Output "  init    Create a new .llvmup-config file in current directory"
    Write-Output "  load    Load and apply configuration from .llvmup-config"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Help   Show this help message"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  Llvm-Config.ps1 -Command init"
    Write-Output "  Llvm-Config.ps1 -Command load"
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

function Initialize-LlvmConfig {
    $configFile = ".llvmup-config"

    if (Test-Path $configFile) {
        Write-LogError ".llvmup-config already exists in current directory"
        Write-LogInfo "Delete the existing file or edit it manually"
        return 1
    }

    Write-LogInfo "Creating .llvmup-config file..."

    $configContent = @"
# .llvmup-config - LLVM project configuration
#
# This file defines LLVM version and build settings for the current project
# Place it in your project root directory
#
# Format: INI-style configuration

[version]
# Default LLVM version to use for this project
default = "llvmorg-21.1.0"

[build]
# Custom name for the installation
name = "21.1.0-release"

# CMake flags for custom builds (array format)
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Release",
  "-DLLVM_ENABLE_PROJECTS=clang;lld;lldb",
  "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi"
]

[components]
# Components to include in custom builds (array format)
include = ["clang", "lld", "lldb", "compiler-rt"]

[profile]
# Build profile: minimal, full, custom
type = "full"

# Project-specific settings
[project]
# Auto-activate when entering directory (requires shell integration)
auto_activate = true
"@

    $configContent | Out-File -FilePath $configFile -Encoding UTF8
    Write-LogSuccess "Created $configFile with example configuration"
    Write-LogInfo "Edit the file to match your project requirements"
}

function Load-LlvmConfig {
    $configFile = ".llvmup-config"

    if (-not (Test-Path $configFile)) {
        Write-LogError "No .llvmup-config file found in current directory"
        Write-LogInfo "Run 'Llvm-Config.ps1 -Command init' to create one"
        return 1
    }

    Write-LogInfo "Loading project configuration from $configFile..."

    # Parse configuration file
    $defaultVersion = ""
    $customName = ""
    $profile = ""
    $cmakeFlags = @()
    $components = @()
    $currentSection = ""

    # Simple INI parser
    $content = Get-Content $configFile
    foreach ($line in $content) {
        $line = $line.Trim()

        # Skip comments and empty lines
        if ($line -match "^#" -or $line -eq "") { continue }

        # Handle sections
        if ($line -match "^\[(.+)\]$") {
            $currentSection = $matches[1]
            continue
        }

        # Handle array values
        if ($line -match "^\s*(\w+)\s*=\s*\[") {
            $key = $matches[1]
            $arrayContent = ""

            # Check if array is closed on same line
            if ($line -match "\]") {
                $arrayContent = ($line -replace ".*\[(.*)\].*", '$1')
            } else {
                # Multi-line array (simplified parsing)
                $i = $content.IndexOf($line)
                for ($j = $i + 1; $j -lt $content.Length; $j++) {
                    if ($content[$j] -match "\]") { break }
                    $arrayContent += $content[$j] + ","
                }
            }

            # Parse array content
            $items = $arrayContent -split ',' | ForEach-Object {
                $_.Trim() -replace '"', '' -replace "'", ""
            } | Where-Object { $_ -ne "" }

            switch ($currentSection) {
                "build" {
                    if ($key -eq "cmake_flags") {
                        $cmakeFlags = $items
                    }
                }
                "components" {
                    if ($key -eq "include") {
                        $components = $items
                    }
                }
            }
            continue
        }

        # Handle key=value pairs
        if ($line -match "^\s*(\w+)\s*=\s*(.+)$") {
            $key = $matches[1]
            $value = $matches[2] -replace '"', '' -replace "'", ""

            switch ($currentSection) {
                "version" {
                    if ($key -eq "default") {
                        $defaultVersion = $value
                    }
                }
                "build" {
                    if ($key -eq "name") {
                        $customName = $value
                    }
                }
                "profile" {
                    if ($key -eq "type") {
                        $profile = $value
                    }
                }
            }
        }
    }

    if ($defaultVersion -eq "") {
        Write-LogError "No default version specified in configuration"
        return 1
    }

    Write-LogInfo "🎯 Configuration loaded:"
    Write-LogInfo "   📦 Version: $defaultVersion"
    if ($customName) { Write-LogInfo "   🏷️  Name: $customName" }
    if ($profile) { Write-LogInfo "   📋 Profile: $profile" }
    if ($cmakeFlags) { Write-LogInfo "   🔧 CMake flags: $($cmakeFlags -join ', ')" }
    if ($components) { Write-LogInfo "   📦 Components: $($components -join ', ')" }

    # Build command
    $cmdArgs = @($defaultVersion)
    if ($customName) { $cmdArgs += @("-Name", $customName) }
    if ($profile) { $cmdArgs += @("-Profile", $profile) }

    foreach ($flag in $cmakeFlags) {
        $cmdArgs += @("-CMakeFlags", $flag)
    }

    foreach ($comp in $components) {
        $cmdArgs += @("-Component", $comp)
    }

    Write-LogInfo "💡 To install with these settings, run:"
    Write-LogInfo "   Download-Llvm.ps1 -FromSource $($cmdArgs -join ' ')"

    # Ask if user wants to install now
    $response = Read-Host "🤔 Install now? [y/N]"
    if ($response -match "^[Yy]") {
        Write-LogInfo "🚀 Installing LLVM with project configuration..."
        & "./Download-Llvm.ps1" -FromSource @cmdArgs
    }
}

# Execute command
switch ($Command) {
    "init" {
        Initialize-LlvmConfig
    }
    "load" {
        Load-LlvmConfig
    }
}
