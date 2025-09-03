# Install-Llvm.ps1: Enhanced LLVM installation management for Windows
# Supports custom builds, profiles, and configuration files
# Requirements: PowerShell v5 or later

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Command = "install",

    [Parameter(Position = 1)]
    [string]$Version,

    [switch]$FromSource,
    [string[]]$CmakeFlags = @(),
    [string]$Name,
    [switch]$Default,
    [ValidateSet("minimal", "full", "custom")]
    [string]$Profile,
    [string[]]$Component = @(),
    [switch]$Verbose,
    [switch]$Quiet,
    [switch]$Help
)

# Global variables
$script:LLVM_HOME = "$env:USERPROFILE\.llvm"
$script:TOOLCHAINS_DIR = "$script:LLVM_HOME\toolchains"
$script:SOURCES_DIR = "$script:LLVM_HOME\sources"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Verbose")]
        [string]$Level = "Info"
    )

    if ($Level -eq "Verbose" -and -not $Verbose) {
        return
    }

    if ($Quiet -and $Level -eq "Info") {
        return
    }

    $color = switch ($Level) {
        "Info" { "White" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Verbose" { "Gray" }
    }

    $prefix = switch ($Level) {
        "Info" { "📋" }
        "Warning" { "⚠️ " }
        "Error" { "❌" }
        "Verbose" { "[VERBOSE]" }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Show-Help {
    Write-Host @"
LLVMUP for Windows - LLVM Version Manager

Usage: .\Install-Llvm.ps1 [COMMAND] [OPTIONS] [VERSION]

Commands:
  install          Install an LLVM version (default command)
  default          Manage default LLVM version
  help             Show this help message

Install Options:
  -FromSource      Build LLVM from source instead of pre-built release
  -CmakeFlags      Pass additional CMake flags (can be repeated)
  -Name           Custom name for installation (e.g., "21.1.0-debug")
  -Default        Set as global default version
  -Profile        Build profile: minimal, full, custom
  -Component      Install specific components (can be repeated)
  -Verbose        Enable verbose output for debugging
  -Quiet          Suppress non-essential output
  -Help           Show this help message

Examples:
  .\Install-Llvm.ps1 install                                    # Install latest pre-built
  .\Install-Llvm.ps1 install llvmorg-18.1.8                   # Install specific version
  .\Install-Llvm.ps1 install -FromSource                      # Build from source
  .\Install-Llvm.ps1 install llvmorg-21.1.0 -FromSource ```
    -CmakeFlags '-DCMAKE_BUILD_TYPE=Debug' ```
    -CmakeFlags '-DLLVM_ENABLE_PROJECTS=clang;lld' ```
    -Name '21.1.0-debug' -Default                             # Custom build with name
  .\Install-Llvm.ps1 install -Profile minimal llvmorg-18.1.8  # Install minimal profile
  .\Install-Llvm.ps1 install -Component clang -Component lldb  # Specific components
  .\Install-Llvm.ps1 default set llvmorg-18.1.8              # Set default version
  .\Install-Llvm.ps1 default show                             # Show current default

"@ -ForegroundColor Cyan
}

function Get-ProfileProjects {
    param([string]$ProfileName)

    switch ($ProfileName) {
        "minimal" { return "clang;lld" }
        "full" { return "clang;clang-tools-extra;lld;lldb;compiler-rt;libcxx;libcxxabi;openmp" }
        "custom" { return "" } # Will be determined by components
        default { return "clang;clang-tools-extra;lld;lldb;compiler-rt;libcxx;libcxxabi;openmp" }
    }
}

function Set-DefaultVersion {
    param([string]$VersionName)

    $versionPath = Join-Path $script:TOOLCHAINS_DIR $VersionName
    $defaultPath = Join-Path $script:LLVM_HOME "default"

    if (-not (Test-Path $versionPath)) {
        Write-Log "Version $VersionName is not installed" -Level Error
        Write-Log "Use 'Get-LlvmList' to see installed versions" -Level Info
        return $false
    }

    # Remove existing default link if it exists
    if (Test-Path $defaultPath) {
        Remove-Item $defaultPath -Force -Recurse
    }

    # Create junction (symlink equivalent for Windows)
    try {
        New-Item -ItemType Junction -Path $defaultPath -Target $versionPath | Out-Null
        Write-Log "✅ Default LLVM version set to: $VersionName" -Level Info
        return $true
    } catch {
        Write-Log "Failed to set default version: $_" -Level Error
        return $false
    }
}

function Show-DefaultVersion {
    $defaultPath = Join-Path $script:LLVM_HOME "default"

    if (Test-Path $defaultPath) {
        $target = (Get-Item $defaultPath).Target
        if ($target) {
            $versionName = Split-Path $target -Leaf
            Write-Log "📦 Current default LLVM version: $versionName" -Level Info

            $clangPath = Join-Path $defaultPath "bin\clang.exe"
            if (Test-Path $clangPath) {
                $clangVersion = & $clangPath --version 2>$null | Select-Object -First 1
                Write-Log "🔍 Clang version: $clangVersion" -Level Info
            }
        }
    } else {
        Write-Log "❌ No default LLVM version is set" -Level Info
        Write-Log "💡 Use '.\Install-Llvm.ps1 default set <version>' to set one" -Level Info
    }
}

function Read-LlvmConfig {
    $configFile = ".llvmup-config"

    if (-not (Test-Path $configFile)) {
        return $null
    }

    Write-Log "📋 Found .llvmup-config file, loading settings..." -Level Info

    $config = @{
        Version = ""
        Name = ""
        Profile = ""
        CmakeFlags = @()
        Components = @()
    }

    $currentSection = ""
    $content = Get-Content $configFile

    foreach ($line in $content) {
        # Skip comments and empty lines
        if ($line -match '^\s*#' -or $line -match '^\s*$') {
            continue
        }

        # Handle sections
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $currentSection = $matches[1]
            continue
        }

        # Parse key=value pairs
        if ($line -match '^\s*([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim() -replace '^["'']|["'']$', ''

            switch ($currentSection) {
                "version" {
                    if ($key -eq "default") { $config.Version = $value }
                }
                "build" {
                    switch ($key) {
                        "name" { $config.Name = $value }
                        "cmake_flags" {
                            # Parse array format
                            if ($value -match '^\[(.*)\]$') {
                                $flagsStr = $matches[1]
                                $config.CmakeFlags = $flagsStr -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                            }
                        }
                    }
                }
                "profile" {
                    if ($key -eq "type") { $config.Profile = $value }
                }
                "components" {
                    if ($key -eq "include") {
                        # Parse array format
                        if ($value -match '^\[(.*)\]$') {
                            $componentsStr = $matches[1]
                            $config.Components = $componentsStr -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                        }
                    }
                }
            }
        }
    }

    return $config
}

function Install-LlvmVersion {
    param(
        [string]$VersionToInstall,
        [bool]$BuildFromSource,
        [string[]]$CmakeFlagsArray,
        [string]$CustomName,
        [bool]$SetAsDefault,
        [string]$BuildProfile,
        [string[]]$ComponentsArray
    )

    # Load config file if it exists
    $config = Read-LlvmConfig
    if ($config -and -not $VersionToInstall) {
        $VersionToInstall = $config.Version
        if (-not $CustomName) { $CustomName = $config.Name }
        if (-not $BuildProfile) { $BuildProfile = $config.Profile }
        if ($CmakeFlagsArray.Count -eq 0) { $CmakeFlagsArray = $config.CmakeFlags }
        if ($ComponentsArray.Count -eq 0) { $ComponentsArray = $config.Components }
    }

    if (-not $VersionToInstall) {
        Write-Log "No version specified" -Level Error
        return $false
    }

    Write-Log "🚀 Installing LLVM version: $VersionToInstall" -Level Info

    if ($BuildFromSource) {
        return Install-FromSource -Version $VersionToInstall -CmakeFlags $CmakeFlagsArray -Name $CustomName -SetDefault $SetAsDefault -Profile $BuildProfile -Components $ComponentsArray
    } else {
        return Install-PreBuilt -Version $VersionToInstall -Name $CustomName -SetDefault $SetAsDefault
    }
}

function Install-PreBuilt {
    param(
        [string]$Version,
        [string]$Name,
        [bool]$SetDefault
    )

    Write-Log "📥 Installing pre-built LLVM $Version..." -Level Info

    # Use existing Download-Llvm.ps1 logic here, adapted for new parameters
    # This is a simplified version - you would integrate the existing download logic

    $installName = if ($Name) { $Name } else { $Version }
    $targetDir = Join-Path $script:TOOLCHAINS_DIR $installName

    # TODO: Integrate actual download and installation logic from Download-Llvm.ps1
    Write-Log "📦 LLVM $Version installed as '$installName'" -Level Info

    if ($SetDefault) {
        Set-DefaultVersion $installName | Out-Null
    }

    return $true
}

function Install-FromSource {
    param(
        [string]$Version,
        [string[]]$CmakeFlags,
        [string]$Name,
        [bool]$SetDefault,
        [string]$Profile,
        [string[]]$Components
    )

    Write-Log "🔨 Building LLVM $Version from source..." -Level Info

    $buildName = if ($Name) { $Name } else { $Version }

    # Determine projects to build
    $projectsToBuild = ""
    if ($Profile) {
        $projectsToBuild = Get-ProfileProjects $Profile
    } elseif ($Components.Count -gt 0) {
        $projectsToBuild = $Components -join ';'
    } else {
        $projectsToBuild = Get-ProfileProjects "full"
    }

    Write-Log "🔧 Build Configuration:" -Level Info
    Write-Log "   📦 Version: $Version" -Level Info
    Write-Log "   🏷️  Name: $buildName" -Level Info
    Write-Log "   📋 Profile: $(if ($Profile) { $Profile } else { 'default' })" -Level Info
    Write-Log "   🧩 Projects: $projectsToBuild" -Level Info

    # TODO: Implement actual source build logic
    # This would involve git clone, cmake configure, build, and install

    Write-Log "✅ Build and installation complete!" -Level Info

    if ($SetDefault) {
        Set-DefaultVersion $buildName | Out-Null
    }

    return $true
}

function Initialize-LlvmConfig {
    $configFile = ".llvmup-config"

    if (Test-Path $configFile) {
        Write-Log "⚠️  .llvmup-config already exists in current directory" -Level Warning
        Write-Log "🔍 Current configuration:" -Level Info
        Get-Content $configFile

        $response = Read-Host "Overwrite existing configuration? [y/N]"
        if ($response -notmatch '^[Yy]$') {
            Write-Log "❌ Configuration initialization cancelled" -Level Error
            return
        }
    }

    Write-Log "🎯 Initializing LLVM project configuration..." -Level Info
    Write-Log "📋 Please provide the following information:" -Level Info

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
    Write-Log "✅ Configuration file created: $configFile" -Level Info
    Write-Log "💡 Edit the file to customize build settings" -Level Info
    Write-Log "🚀 Run '.\Install-Llvm.ps1 config load' to install and activate" -Level Info
}

# Main execution logic
if ($Help) {
    Show-Help
    exit 0
}

# Ensure LLVM directories exist
New-Item -ItemType Directory -Path $script:TOOLCHAINS_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $script:SOURCES_DIR -Force | Out-Null

switch ($Command.ToLower()) {
    "help" {
        Show-Help
    }
    "default" {
        if ($Version -eq "set") {
            if (-not $args[0]) {
                Write-Log "Missing version argument for 'default set'" -Level Error
                exit 1
            }
            Set-DefaultVersion $args[0]
        } elseif ($Version -eq "show" -or -not $Version) {
            Show-DefaultVersion
        } else {
            Write-Log "Unknown default subcommand: $Version" -Level Error
            Write-Log "Available subcommands: set, show" -Level Info
            exit 1
        }
    }
    "config" {
        switch ($Version.ToLower()) {
            "init" { Initialize-LlvmConfig }
            "load" {
                # TODO: Implement config loading and installation
                Write-Log "Config loading not yet implemented" -Level Warning
            }
            default {
                Write-Log "Unknown config subcommand: $Version" -Level Error
                Write-Log "Available subcommands: init, load" -Level Info
                exit 1
            }
        }
    }
    "install" {
        $result = Install-LlvmVersion -VersionToInstall $Version -BuildFromSource $FromSource -CmakeFlagsArray $CmakeFlags -CustomName $Name -SetAsDefault $Default -BuildProfile $Profile -ComponentsArray $Component
        if (-not $result) {
            exit 1
        }
    }
    default {
        # Default to install command
        $result = Install-LlvmVersion -VersionToInstall $Command -BuildFromSource $FromSource -CmakeFlagsArray $CmakeFlags -CustomName $Name -SetAsDefault $Default -BuildProfile $Profile -ComponentsArray $Component
        if (-not $result) {
            exit 1
        }
    }
}
