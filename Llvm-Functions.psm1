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
# =============================================================================
# VERSION PARSING AND MANAGEMENT FUNCTIONS
# =============================================================================

function ConvertFrom-LlvmVersion {
    <#
    .SYNOPSIS
    Parse version string from LLVM version identifier

    .DESCRIPTION
    Supports formats: llvmorg-18.1.8, source-llvmorg-20.1.0, 19.1.7

    .PARAMETER VersionString
    The version string to parse

    .EXAMPLE
    ConvertFrom-LlvmVersion "llvmorg-18.1.8"
    Returns: 18.1.8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VersionString
    )

    if ([string]::IsNullOrEmpty($VersionString)) { return $null }

    # Remove common prefixes (including source-llvmorg- for parity with bash)
    $clean = $VersionString -replace '^(source-llvmorg-|llvmorg-|source-)', ''

    # Extract version numbers
    if ($clean -match '^(\d+(?:\.\d+)*(?:-[a-zA-Z0-9]+)?)$') {
        return $matches[1]
    }

    return $null
}

function Get-LlvmVersions {
    <#
    .SYNOPSIS
    Get all installed LLVM versions in a structured format

    .PARAMETER Format
    Output format: List, Json, Simple

    .EXAMPLE
    Get-LlvmVersions -Format Simple
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("List", "Json", "Simple")]
        [string]$Format = "List"
    )

    if (-not (Test-Path $script:TOOLCHAINS_DIR)) {
        Write-LlvmLog "No LLVM toolchains directory found at $script:TOOLCHAINS_DIR" -Level Error
        return
    }

    switch ($Format) {
        "Json" { Get-LlvmVersionsJson }
        "Simple" { Get-LlvmVersionsSimple }
        default { Get-LlvmVersionsList }
    }
}

function Get-LlvmVersionsSimple {
    <#
    .SYNOPSIS
    Get versions in simple array format
    #>
    [CmdletBinding()]
    param()

    $versions = Get-ChildItem $script:TOOLCHAINS_DIR -Directory |
                Sort-Object Name |
                Select-Object -ExpandProperty Name

    return $versions
}

function Get-LlvmVersionsList {
    <#
    .SYNOPSIS
    Get versions in detailed list format with visual formatting
    #>
    [CmdletBinding()]
    param()

    Write-Host "╭─ Available LLVM Versions ──────────────────────────────────╮" -ForegroundColor Cyan

    $versions = Get-ChildItem $script:TOOLCHAINS_DIR -Directory | Sort-Object Name
    $foundVersions = $false

    foreach ($version in $versions) {
        $foundVersions = $true
        $versionName = $version.Name
        $parsedVersion = ConvertFrom-LlvmVersion $versionName
        $isActive = ""
        $typeInfo = ""

        # Check if this version is active
        if ($env:_ACTIVE_LLVM -eq $versionName) {
            $isActive = " (ACTIVE)"
        }

        # Determine version type
        if ($versionName -match "^source-") {
            $typeInfo = " [Source Build]"
        } else {
            $typeInfo = " [Prebuilt]"
        }

        # Format output
        if ($parsedVersion -and $parsedVersion -ne $versionName) {
            $line = "│ 📦 {0,-20} (v{1}){2}{3}" -f $versionName, $parsedVersion, $typeInfo, $isActive
        } else {
            $line = "│ 📦 {0,-35}{1}{2}" -f $versionName, $typeInfo, $isActive
        }

        if ($isActive) {
            Write-Host $line -ForegroundColor Green
        } else {
            Write-Host $line -ForegroundColor White
        }
    }

    if (-not $foundVersions) {
        Write-Host "│ ❌ No LLVM versions found                                   │" -ForegroundColor Red
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ 💡 Use '.\Install-Llvm.ps1' to install LLVM versions       │" -ForegroundColor Yellow
    }

    Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
}

function Get-LlvmVersionsJson {
    <#
    .SYNOPSIS
    Get versions in JSON format
    #>
    [CmdletBinding()]
    param()

    $versions = Get-ChildItem $script:TOOLCHAINS_DIR -Directory | Sort-Object Name
    $versionObjects = @()

    foreach ($version in $versions) {
        $versionName = $version.Name
        $parsedVersion = ConvertFrom-LlvmVersion $versionName
        $isActive = ($env:_ACTIVE_LLVM -eq $versionName)
        $installType = if ($versionName -match "^source-") { "source" } else { "prebuilt" }

        $versionObjects += @{
            name = $versionName
            version = if ($parsedVersion) { $parsedVersion } else { $versionName }
            type = $installType
            active = $isActive
            path = $version.FullName
        }
    }

    $result = @{
        installed_versions = $versionObjects
        active_version = $env:_ACTIVE_LLVM
    }

    return $result | ConvertTo-Json -Depth 3
}

function Test-LlvmVersionExists {
    <#
    .SYNOPSIS
    Check if a specific LLVM version is installed

    .PARAMETER Version
    The version identifier to check

    .EXAMPLE
    Test-LlvmVersionExists "llvmorg-18.1.8"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $versionPath = Join-Path $script:TOOLCHAINS_DIR $Version
    return Test-Path $versionPath
}

function Get-LlvmActiveVersion {
    <#
    .SYNOPSIS
    Get the currently active LLVM version

    .EXAMPLE
    Get-LlvmActiveVersion
    #>
    [CmdletBinding()]
    param()

    if ($env:_ACTIVE_LLVM) {
        return $env:_ACTIVE_LLVM
    } else {
        Write-LlvmLog "No LLVM version is currently active" -Level Error
        return $null
    }
}

function Compare-LlvmVersion {
    <#
    .SYNOPSIS
    Compare two LLVM version strings

    .PARAMETER Version1
    First version to compare

    .PARAMETER Version2
    Second version to compare

    .OUTPUTS
    Returns 1 if Version1 > Version2, 0 if equal, -1 if Version1 < Version2

    .EXAMPLE
    Compare-LlvmVersion "18.1.8" "19.1.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version1,

        [Parameter(Mandatory = $true)]
        [string]$Version2
    )

    $v1 = ConvertFrom-LlvmVersion $Version1
    $v2 = ConvertFrom-LlvmVersion $Version2

    if (-not $v1 -or -not $v2) { return $null }

    try {
        # Simple normalization for version comparison
        $semver1 = [System.Version]($v1 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Substring(0, [Math]::Min(7, ($v1 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Length))
        $semver2 = [System.Version]($v2 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Substring(0, [Math]::Min(7, ($v2 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Length))
        return $semver1.CompareTo($semver2)
    }
    catch {
        # Fallback to string comparison
        if ($v1 -eq $v2) { return 0 }
        if ($v1 -gt $v2) { return 1 }
        return -1
    }
}

function Get-LlvmLatestVersion {
    <#
    .SYNOPSIS
    Find the latest installed LLVM version

    .EXAMPLE
    Get-LlvmLatestVersion
    #>
    [CmdletBinding()]
    param()

    $versions = Get-LlvmVersionsSimple

    if (-not $versions) {
        Write-LlvmLog "No LLVM versions installed" -Level Error
        return $null
    }

    $parsedVersions = @()
    foreach ($version in $versions) {
        $parsed = ConvertFrom-LlvmVersion $version
        if ($parsed) {
            $parsedVersions += @{
                Original = $version
                Parsed = $parsed
            }
        }
    }

    if ($parsedVersions.Count -eq 0) {
        return $versions | Select-Object -Last 1
    }

    # Sort by parsed version and get the latest
    $latest = $parsedVersions | Sort-Object { [System.Version]$_.Parsed } | Select-Object -Last 1
    return $latest.Original
}

function Normalize-LlvmSemver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    # Convert inputs like '18', '18.1' or '18.1.8' into '18.1.8' form
    if (-not $Version) { return $null }
    $parts = $Version -split '\.'
    while ($parts.Count -lt 3) { $parts += '0' }
    return ($parts[0..2] -join '.')
}

function Invoke-LlvmParseVersionExpression {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)] [string]$Expression)

    $expr = $Expression.Trim()

    if ($expr -eq 'latest') { return @{ kind='selector'; selector='latest' } }
    if ($expr -eq 'oldest') { return @{ kind='selector'; selector='oldest' } }
    if ($expr -eq 'prebuilt') { return @{ kind='type'; type='prebuilt' } }
    if ($expr -eq 'source') { return @{ kind='type'; type='source' } }

    if ($expr -match '^~\s*(\d+(?:\.\d+)*)$') {
        return @{ kind='range'; range=@{ op='~'; version=$matches[1] } }
    }

    if ($expr -match '^(>=|<=|>|<|=)\s*(.+)$') {
        return @{ kind='range'; range=@{ op=$matches[1]; version=$matches[2] } }
    }

    if ($expr -match '\*$') {
        return @{ kind='wildcard'; wildcard=$expr }
    }

    return @{ kind='specific'; specific=$expr }
}

function Invoke-LlvmVersionMatchesRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CandidateVersion,
        [Parameter(Mandatory=$true)]
        [string]$RangeExpression
    )

    # Normalize candidate parsed version
    $cand = ConvertFrom-LlvmVersion $CandidateVersion
    if (-not $cand) { return $false }
    $candNorm = Normalize-LlvmSemver $cand

    $parsed = Invoke-LlvmParseVersionExpression -Expression $RangeExpression
    if (-not $parsed) { return $false }

    switch ($parsed.kind) {
        'range' {
            $op = $parsed.range.op
            $ver = $parsed.range.version
            if ($op -eq '~') {
                # Tilde range: >= ver.0 and < next minor
                $baseParts = ($ver -split '\.')
                $major = [int]$baseParts[0]
                $minor = if ($baseParts.Count -ge 2) { [int]$baseParts[1] } else { 0 }
                $min = Normalize-LlvmSemver "$major.$minor.0"
                $nextMinor = Normalize-LlvmSemver "$major.$([int]($minor + 1)).0"
                $cmpMin = Compare-LlvmVersion $candNorm $min
                $cmpMax = Compare-LlvmVersion $candNorm $nextMinor
                # Compare-LlvmVersion returns -1/0/1 semantics; ensure inclusive lower bound and exclusive upper
                if (($cmpMin -ge 0) -and ($cmpMax -lt 0)) { return $true } else { return $false }
            } else {
                $targetNorm = Normalize-LlvmSemver (ConvertFrom-LlvmVersion $ver)
                $cmp = Compare-LlvmVersion $candNorm $targetNorm
                switch ($op) {
                    '>'  { return ($cmp -gt 0) }
                    '>=' { return ($cmp -ge 0) }
                    '<'  { return ($cmp -lt 0) }
                    '<=' { return ($cmp -le 0) }
                    '='  { return ($cmp -eq 0) }
                }
            }
        }
        'wildcard' {
            # e.g. 18.* -> match major
            if ($parsed.wildcard -match '^([0-9]+)\.') {
                $maj = $matches[1]
                if ($cand -match "^$maj\\.") { return $true } else { return $false }
            }
            return $false
        }
        default {
            # Unknown kind: return false
            return $false
        }
    }
}

function Invoke-LlvmMatchVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Expression
    )

    $parsed = Invoke-LlvmParseVersionExpression -Expression $Expression
    if (-not $parsed) { return @() }

    $installed = Get-LlvmVersionsSimple
    if (-not $installed) { return @() }

    $matches = @()

    switch ($parsed.kind) {
        'selector' {
            $type = $parsed.type
            if ($parsed.selector -eq 'latest') {
                if ($type -eq 'prebuilt') {
                    # choose latest non-source
                    $cand = $installed | Where-Object { $_ -notmatch '^source-' } | ForEach-Object { $_ }
                } elseif ($type -eq 'source') {
                    $cand = $installed | Where-Object { $_ -match '^source-' } | ForEach-Object { $_ }
                } else {
                    $cand = $installed
                }
                if ($cand) {
                    $sorted = $cand | Sort-Object { [System.Version](Normalize-LlvmSemver (ConvertFrom-LlvmVersion $_)) }
                    return ,($sorted | Select-Object -Last 1)
                }
                return @()
            }
            if ($parsed.selector -eq 'oldest') {
                if ($type -eq 'prebuilt') {
                    $cand = $installed | Where-Object { $_ -notmatch '^source-' }
                } elseif ($type -eq 'source') {
                    $cand = $installed | Where-Object { $_ -match '^source-' }
                } else {
                    $cand = $installed
                }
                if ($cand) {
                    $sorted = $cand | Sort-Object { [System.Version](Normalize-LlvmSemver (ConvertFrom-LlvmVersion $_)) }
                    return ,($sorted | Select-Object -First 1)
                }
                return @()
            }
        }
        'type' {
            if ($parsed.type -eq 'prebuilt') { return $installed | Where-Object { $_ -notmatch '^source-' } }
            if ($parsed.type -eq 'source') { return $installed | Where-Object { $_ -match '^source-' } }
            return @()
        }
        'wildcard' {
            $pat = '^' + ($parsed.wildcard -replace '\*', '.*')
            return $installed | Where-Object { $_ -match $pat }
        }
        'specific' {
            $target = $parsed.specific
            # exact match first
            $exact = $installed | Where-Object { $_ -eq $target }
            if ($exact) { return $exact }
            # fallback: match by numeric parsed version
            $targetNum = ConvertFrom-LlvmVersion $target
            if ($targetNum) { return $installed | Where-Object { (ConvertFrom-LlvmVersion $_) -eq $targetNum } }
            return @()
        }
        'range' {
            $res = @()
            foreach ($v in $installed) {
                if (Invoke-LlvmVersionMatchesRange -CandidateVersion $v -RangeExpression $parsed.raw) { $res += $v }
            }
            return $res
        }
        default { return @() }
    }
}

function Invoke-LlvmAutoActivate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$StartDirectory = (Get-Location).Path
    )

    # Walk up looking for .llvmup-config
    $dir = Resolve-Path -Path $StartDirectory
    while ($dir) {
        $config = Join-Path $dir '.llvmup-config'
        if (Test-Path $config) {
            Import-LlvmConfig
            return
        }
        $parent = Split-Path $dir -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

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
    'Show-LlvmHelp',
    'ConvertFrom-LlvmVersion',
    'Get-LlvmVersions',
    'Get-LlvmVersionsSimple',
    'Get-LlvmVersionsList',
    'Get-LlvmVersionsJson',
    'Test-LlvmVersionExists',
    'Get-LlvmActiveVersion',
    'Compare-LlvmVersion',
    'Get-LlvmLatestVersion',
    'Normalize-LlvmSemver',
    'Invoke-LlvmParseVersionExpression',
    'Invoke-LlvmVersionMatchesRange',
    'Invoke-LlvmMatchVersions',
    'Invoke-LlvmAutoActivate'
)
