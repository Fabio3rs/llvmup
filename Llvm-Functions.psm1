# Llvm-Functions.psm1: PowerShell module for LLVM version management
# This module should be imported in the user's PowerShell profile
#
# Usage after importing:
#   Activate-Llvm <version>    - Activate an LLVM version
#   Deactivate-Llvm           - Deactivate current LLVM version
#   Get-LlvmStatus            - Show current status
#   Get-LlvmList              - List installed versions
#   Initialize-LlvmConfig     - Initialize .llvmup-config
#   Import-LlvmConfig         - Load project config

# Global variables
$script:LLVM_HOME = "$env:USERPROFILE\.llvm"
$script:TOOLCHAINS_DIR = "$script:LLVM_HOME\toolchains"

function Write-LlvmLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )

    $color = switch ($Level) {
        "Info" { "Cyan" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
    }

    $emoji = switch ($Level) {
        "Info" { "📋" }
        "Warning" { "⚠️ " }
        "Error" { "❌" }
        "Success" { "✅" }
    }

    Write-Host "$emoji $Message" -ForegroundColor $color
}

function Activate-Llvm {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Version
    )

    if (-not $Version) {
        Write-Host "╭─ LLVM Activation Help ─────────────────────────────────────╮" -ForegroundColor Cyan
        Write-Host "│ Usage: Activate-Llvm <version>                            │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ Examples:                                                  │" -ForegroundColor White
        Write-Host "│   Activate-Llvm 18.1.8     # Activate specific version    │" -ForegroundColor White
        Write-Host "│   Activate-Llvm 19.1.0     # Activate another version     │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ What this does:                                            │" -ForegroundColor White
        Write-Host "│ • Sets PATH to use LLVM tools (clang, clang++, etc.)      │" -ForegroundColor White
        Write-Host "│ • Updates environment variables                            │" -ForegroundColor White
        Write-Host "│ • Modifies prompt to show active LLVM version             │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ To deactivate: Deactivate-Llvm                            │" -ForegroundColor White
        Write-Host "│ To check status: Get-LlvmStatus                           │" -ForegroundColor White
        Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📦 Installed versions:" -ForegroundColor Cyan
        Get-LlvmList
        Write-Host ""
        Write-Host "💡 Tip: Use TAB completion to auto-complete version names" -ForegroundColor Yellow
        return
    }

    $versionPath = Join-Path $script:TOOLCHAINS_DIR $Version

    if (-not (Test-Path $versionPath)) {
        Write-LlvmLog "LLVM version $Version not found" -Level Error
        Write-LlvmLog "Check installed versions with: Get-LlvmList" -Level Info
        return
    }

    # Store previous environment for deactivation
    $env:_LLVM_OLD_PATH = $env:PATH
    $env:_LLVM_OLD_PROMPT = $function:prompt

    # Set environment variables
    $llvmBinPath = Join-Path $versionPath "bin"
    $env:PATH = "$llvmBinPath;$env:PATH"
    $env:_ACTIVE_LLVM = $Version
    $env:_ACTIVE_LLVM_PATH = $versionPath

    # Update prompt to show active LLVM version
    $global:function:prompt = {
        "($Version) PS $($executionContext.SessionState.Path.CurrentLocation)> "
    }

    Write-LlvmLog "LLVM $Version successfully activated!" -Level Success
    Write-LlvmLog "🛠️  Available tools are now in PATH:" -Level Info
    Write-Host "   • clang, clang++, lld, lldb, clangd, etc." -ForegroundColor Gray
    Write-LlvmLog "💡 Your prompt now shows the active LLVM version" -Level Info
    Write-LlvmLog "📊 Use 'Get-LlvmStatus' to see detailed information" -Level Info
}

function Deactivate-Llvm {
    [CmdletBinding()]
    param()

    if (-not $env:_ACTIVE_LLVM) {
        Write-LlvmLog "No LLVM environment is currently active" -Level Warning
        return
    }

    # Restore previous environment
    if ($env:_LLVM_OLD_PATH) {
        $env:PATH = $env:_LLVM_OLD_PATH
        Remove-Item Env:\_LLVM_OLD_PATH
    }

    if ($env:_LLVM_OLD_PROMPT) {
        $global:function:prompt = [scriptblock]::Create($env:_LLVM_OLD_PROMPT)
        Remove-Item Env:\_LLVM_OLD_PROMPT
    }

    Remove-Item Env:\_ACTIVE_LLVM
    Remove-Item Env:\_ACTIVE_LLVM_PATH -ErrorAction SilentlyContinue

    Write-LlvmLog "LLVM environment successfully deactivated" -Level Success
    Write-LlvmLog "💡 Your environment and prompt have been restored" -Level Info
}

function Get-LlvmStatus {
    [CmdletBinding()]
    param()

    Write-Host "╭─ LLVM Environment Status ──────────────────────────────────╮" -ForegroundColor Cyan

    if ($env:_ACTIVE_LLVM) {
        Write-Host "│ ✅ Status: ACTIVE                                          │" -ForegroundColor Green
        Write-Host "│ 📦 Version: $($env:_ACTIVE_LLVM)" -ForegroundColor White

        if ($env:_ACTIVE_LLVM_PATH) {
            Write-Host "│ 📁 Path: $($env:_ACTIVE_LLVM_PATH)" -ForegroundColor White
        }

        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ 🛠️  Available tools:                                        │" -ForegroundColor White

        $llvmPath = Join-Path $env:_ACTIVE_LLVM_PATH "bin"
        if (Test-Path $llvmPath) {
            if (Test-Path (Join-Path $llvmPath "clang.exe")) {
                Write-Host "│   • clang (C compiler)                                 │" -ForegroundColor Gray
            }
            if (Test-Path (Join-Path $llvmPath "clang++.exe")) {
                Write-Host "│   • clang++ (C++ compiler)                             │" -ForegroundColor Gray
            }
            if (Test-Path (Join-Path $llvmPath "clangd.exe")) {
                Write-Host "│   • clangd (Language Server)                           │" -ForegroundColor Gray
            }
            if (Test-Path (Join-Path $llvmPath "lldb.exe")) {
                Write-Host "│   • lldb (Debugger)                                    │" -ForegroundColor Gray
            }
        }

        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ 💡 To deactivate: Deactivate-Llvm                         │" -ForegroundColor Yellow
    } else {
        Write-Host "│ ❌ Status: INACTIVE                                        │" -ForegroundColor Red
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ 💡 To activate a version: Activate-Llvm <version>         │" -ForegroundColor Yellow
        Write-Host "│ 📦 To see available versions: Get-LlvmList                │" -ForegroundColor Yellow
        Write-Host "│ 🚀 To install new versions: .\Install-Llvm.ps1            │" -ForegroundColor Yellow
    }

    Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
}

function Get-LlvmList {
    [CmdletBinding()]
    param()

    Write-Host "╭─ Installed LLVM Versions ──────────────────────────────────╮" -ForegroundColor Cyan

    if (-not (Test-Path $script:TOOLCHAINS_DIR)) {
        Write-Host "│ ❌ No LLVM toolchains found                                │" -ForegroundColor Red
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ 💡 To install LLVM versions:                               │" -ForegroundColor Yellow
        Write-Host "│   • .\Install-Llvm.ps1       # Install prebuilt version   │" -ForegroundColor White
        Write-Host "│   • .\Install-Llvm.ps1 -FromSource  # Build from source   │" -ForegroundColor White
        Write-Host "│   • .\Install-Llvm.ps1 18.1.8  # Install specific version │" -ForegroundColor White
        Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
        return
    }

    $versions = Get-ChildItem $script:TOOLCHAINS_DIR -Directory | Sort-Object Name
    $hasVersions = $false

    foreach ($version in $versions) {
        $hasVersions = $true
        $versionName = $version.Name

        if ($env:_ACTIVE_LLVM -eq $versionName) {
            Write-Host "│ ✅ $versionName (ACTIVE)" -ForegroundColor Green
        } else {
            Write-Host "│ 📦 $versionName" -ForegroundColor White
        }
    }

    if (-not $hasVersions) {
        Write-Host "│ ❌ No valid LLVM installations found                       │" -ForegroundColor Red
    }

    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 💡 Usage:                                                   │" -ForegroundColor Yellow
    Write-Host "│   • Activate-Llvm <version>   # Activate a version         │" -ForegroundColor White
    Write-Host "│   • Get-LlvmStatus            # Check current status       │" -ForegroundColor White
    Write-Host "│   • .\Install-Llvm.ps1        # Install more versions      │" -ForegroundColor White
    Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
}

function Initialize-LlvmConfig {
    [CmdletBinding()]
    param()

    $configFile = ".llvmup-config"

    if (Test-Path $configFile) {
        Write-LlvmLog "⚠️  .llvmup-config already exists in current directory" -Level Warning
        Write-Host "🔍 Current configuration:" -ForegroundColor Cyan
        Get-Content $configFile | Write-Host -ForegroundColor Gray
        Write-Host ""

        $response = Read-Host "Overwrite existing configuration? [y/N]"
        if ($response -notmatch '^[Yy]$') {
            Write-LlvmLog "Configuration initialization cancelled" -Level Error
            return
        }
    }

    Write-LlvmLog "🎯 Initializing LLVM project configuration..." -Level Info
    Write-Host "📋 Please provide the following information:" -ForegroundColor Cyan

    $defaultVersion = Read-Host "Default LLVM version (e.g., llvmorg-18.1.8)"
    if (-not $defaultVersion) { $defaultVersion = "llvmorg-18.1.8" }

    $customName = Read-Host "Custom installation name (optional)"
    $profile = Read-Host "Build profile [minimal/full/custom]"
    if (-not $profile) { $profile = "full" }

    $configContent = @"
# .llvmup-config - LLVM project configuration
# Generated on $(Get-Date)

[version]
default = "$defaultVersion"

[build]
"@

    if ($customName) {
        $configContent += "`nname = `"$customName`""
    }

    $configContent += @"

cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Release",
  "-DLLVM_ENABLE_PROJECTS=clang;lld;lldb"
]

[profile]
type = "$profile"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]

[project]
auto_activate = true
"@

    Set-Content -Path $configFile -Value $configContent
    Write-LlvmLog "Configuration file created: $configFile" -Level Success
    Write-LlvmLog "💡 Edit the file to customize build settings" -Level Info
    Write-LlvmLog "🚀 Run '.\Install-Llvm.ps1 config load' to install and activate" -Level Info
}

function Import-LlvmConfig {
    [CmdletBinding()]
    param()

    $configFile = ".llvmup-config"

    if (-not (Test-Path $configFile)) {
        Write-LlvmLog "No .llvmup-config file found in current directory" -Level Error
        Write-LlvmLog "💡 Run 'Initialize-LlvmConfig' to create one" -Level Info
        return
    }

    Write-LlvmLog "📋 Loading project configuration from $configFile..." -Level Info

    # Parse configuration file (simplified parser)
    $config = @{
        Version = ""
        Name = ""
        Profile = ""
    }

    $content = Get-Content $configFile
    $currentSection = ""

    foreach ($line in $content) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }

        if ($line -match '^\s*\[(.+)\]\s*$') {
            $currentSection = $matches[1]
            continue
        }

        if ($line -match '^\s*([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim() -replace '^["'']|["'']$', ''

            switch ($currentSection) {
                "version" {
                    if ($key -eq "default") { $config.Version = $value }
                }
                "build" {
                    if ($key -eq "name") { $config.Name = $value }
                }
                "profile" {
                    if ($key -eq "type") { $config.Profile = $value }
                }
            }
        }
    }

    if (-not $config.Version) {
        Write-LlvmLog "No default version specified in configuration" -Level Error
        return
    }

    Write-Host "🎯 Configuration loaded:" -ForegroundColor Cyan
    Write-Host "   📦 Version: $($config.Version)" -ForegroundColor Gray
    if ($config.Name) { Write-Host "   🏷️  Name: $($config.Name)" -ForegroundColor Gray }
    if ($config.Profile) { Write-Host "   📋 Profile: $($config.Profile)" -ForegroundColor Gray }

    $installName = if ($config.Name) { $config.Name } else { $config.Version }
    $versionPath = Join-Path $script:TOOLCHAINS_DIR $installName

    if (Test-Path $versionPath) {
        Write-LlvmLog "Version already installed, activating..." -Level Success
        Activate-Llvm $installName
    } else {
        Write-LlvmLog "Version not found, manual installation required" -Level Warning
        Write-LlvmLog "🚀 Run: .\Install-Llvm.ps1 install $($config.Version)" -Level Info
        if ($config.Name) {
            Write-LlvmLog "    Add: -Name '$($config.Name)'" -Level Info
        }
    }
}

function Show-LlvmHelp {
    [CmdletBinding()]
    param()

    Write-Host "╭─ LLVM Manager for Windows - Complete Usage Guide ─────────╮" -ForegroundColor Cyan
    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 🚀 INSTALLATION COMMANDS:                                  │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install              # Latest prebuilt│" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install 18.1.8       # Specific ver  │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install -FromSource  # Build source   │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install -Name my-llvm# Custom name    │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install -Default     # Set as default │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 install -Profile minimal # Profile    │" -ForegroundColor White
    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 🔧 VERSION MANAGEMENT:                                      │" -ForegroundColor White
    Write-Host "│   Activate-Llvm <version>      # Activate LLVM version     │" -ForegroundColor White
    Write-Host "│   Deactivate-Llvm              # Deactivate current version│" -ForegroundColor White
    Write-Host "│   Get-LlvmStatus               # Show current status       │" -ForegroundColor White
    Write-Host "│   Get-LlvmList                 # List installed versions   │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 default set <ver>    # Set default    │" -ForegroundColor White
    Write-Host "│   .\Install-Llvm.ps1 default show         # Show default   │" -ForegroundColor White
    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 💻 DEVELOPMENT INTEGRATION:                                 │" -ForegroundColor White
    Write-Host "│   Initialize-LlvmConfig        # Initialize .llvmup-config │" -ForegroundColor White
    Write-Host "│   Import-LlvmConfig            # Load project config       │" -ForegroundColor White
    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 💡 TIPS:                                                    │" -ForegroundColor Yellow
    Write-Host "│   • Use TAB completion for version names                   │" -ForegroundColor White
    Write-Host "│   • Check Get-LlvmStatus after activation                  │" -ForegroundColor White
    Write-Host "│   • Your prompt shows active LLVM version                  │" -ForegroundColor White
    Write-Host "│   • Environment is isolated per PowerShell session        │" -ForegroundColor White
    Write-Host "│   • Use .llvmup-config for project-specific settings       │" -ForegroundColor White
    Write-Host "│                                                            │" -ForegroundColor White
    Write-Host "│ 🔗 MORE INFO: https://github.com/Fabio3rs/llvmup           │" -ForegroundColor White
    Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
}

# Tab completion for version names
Register-ArgumentCompleter -CommandName Activate-Llvm -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if (Test-Path $script:TOOLCHAINS_DIR) {
        Get-ChildItem $script:TOOLCHAINS_DIR -Directory |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object { $_.Name }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Activate-Llvm',
    'Deactivate-Llvm',
    'Get-LlvmStatus',
    'Get-LlvmList',
    'Initialize-LlvmConfig',
    'Import-LlvmConfig',
    'Show-LlvmHelp'
)
