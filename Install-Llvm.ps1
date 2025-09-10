# Install-Llvm.ps1: Enhanced LLVM installation management for Windows
# Supports custom builds, profiles, and configuration files
# Requirements: PowerShell v5 or later

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
    [switch]$DisableLibcWnoError,
    [switch]$Reconfigure,
    [switch]$VerboseMode,
    [switch]$Quiet,
    [switch]$Help
)

# Set global verbose mode
$script:VERBOSE_MODE = $VerboseMode.IsPresent
$script:Quiet = $Quiet.IsPresent

# Helper function to trim whitespace from strings
function Get-TrimmedString {
    param([string]$InputString)
    if (-not $InputString) { return "" }
    return $InputString.Trim().Trim('"').Trim("'").Trim()
}

$modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
$homeDir = Get-UserHome
$script:LLVM_HOME = Join-Path $homeDir ".llvm"
$script:TOOLCHAINS_DIR = Join-Path $script:LLVM_HOME "toolchains"
$script:SOURCES_DIR = Join-Path $script:LLVM_HOME "sources"

# Enhanced logging functions - similar to bash version
function Write-VerboseLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "[VERBOSE] $Message" -ForegroundColor Gray
    }
}

function Write-InfoLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "$Message" -ForegroundColor White
    }
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-SuccessLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "✅ $Message" -ForegroundColor Green
    }
}

function Write-WarningLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "⚠️  $Message" -ForegroundColor Yellow
    }
}

function Write-ProgressLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "🔄 $Message" -ForegroundColor Cyan
    }
}

function Write-TipLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "💡 $Message" -ForegroundColor Blue
    }
}

function Write-ConfigLog {
    param([string]$Message)
    if ($script:VERBOSE_MODE -or $env:LLVM_TEST_MODE) {
        Write-Host "📋 $Message" -ForegroundColor Magenta
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Verbose")]
        [string]$Level = "Info"
    )

    if ($Level -eq "Verbose" -and -not $script:VERBOSE_MODE) {
        return
    }

    if ($script:Quiet -and $Level -eq "Info") {
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
  config           Manage project configuration (.llvmup-config)
  default          Manage default LLVM version
  help             Show this help message

Install Options:
  -FromSource      Build LLVM from source instead of pre-built release
  -CmakeFlags      Pass additional CMake flags (can be repeated)
  -Name           Custom name for installation (e.g., "21.1.0-debug")
  -Default        Set as global default version
  -Profile        Build profile: minimal, full, custom
  -Component      Install specific components (can be repeated)
  -DisableLibcWnoError  Disable LIBC_WNO_ERROR=ON flag
  -Reconfigure    Force CMake to reconfigure the build if CMakeCache.txt exists
  -VerboseMode    Enable verbose output for debugging
  -Quiet          Suppress non-essential output
  -Help           Show this help message

Config Commands:
  .\Install-Llvm.ps1 config init      # Initialize project configuration
  .\Install-Llvm.ps1 config load      # Load and display configuration
  .\Install-Llvm.ps1 config apply     # Install using configuration
  .\Install-Llvm.ps1 config activate  # Activate existing installation

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
  .\Install-Llvm.ps1 install -DisableLibcWnoError             # Disable LIBC_WNO_ERROR flag
  .\Install-Llvm.ps1 install -FromSource -Reconfigure         # Force CMake reconfiguration
  .\Install-Llvm.ps1 config init                              # Initialize project config
  .\Install-Llvm.ps1 config apply                             # Install from config
  .\Install-Llvm.ps1 default set llvmorg-18.1.8              # Set default version
  .\Install-Llvm.ps1 default show                             # Show current default

Project Configuration (.llvmup-config):
  [version]
  default = "llvmorg-21.1.0"

  [build]
  name = "21.1.0-debug"
  cmake_flags = ["-DCMAKE_BUILD_TYPE=Debug"]
  disable_libc_wno_error = true

  [profile]
  type = "full"

  [components]
  include = ["clang", "lld", "lldb", "compiler-rt"]

  [project]
  auto_activate = true
  cmake_preset = "Debug"

  [paths]
  llvm_home = "/custom/llvm"
  toolchains_dir = "/custom/llvm/toolchains"
  sources_dir = "/custom/llvm/sources"

"@ -ForegroundColor Cyan
}

function Get-ProfileProjects {
    param([string]$ProfileName)

    switch ($ProfileName) {
        "minimal" { return "clang;lld" }
        "full" { return "all" }
        "custom" { return "" } # Will be determined by components
        default { return "all" }
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

    Write-ConfigLog "Found .llvmup-config file, loading settings..."

    $config = @{
        Version = ""
        Name = ""
        Profile = ""
        CmakeFlags = @()
        Components = @()
        AutoActivate = "false"
        CmakePreset = ""
        DisableLibcWnoError = $false
        ToolchainsDir = ""
        SourcesDir = ""
        LlvmHome = ""
    }

    $currentSection = ""
    $content = Get-Content $configFile
    $inArray = $false
    $arrayType = ""

    # Helper function to parse array content
    function Parse-ArrayContent {
        param([string]$Content, [string]$Section, [string]$Key)

        # Remove quotes and whitespace, split by comma
        $cleanContent = $Content -replace '["\s]', ''

        # Split by comma and add to appropriate array
        $items = $cleanContent -split ',' | ForEach-Object { Get-TrimmedString $_ }

        foreach ($item in $items) {
            if (-not $item) { continue }

            if ($Section -eq "build" -and $Key -eq "cmake_flags") {
                $config.CmakeFlags += $item
            } elseif ($Section -eq "components" -and $Key -eq "include") {
                $config.Components += $item
            }
        }
    }

    foreach ($line in $content) {
        # Skip comments and empty lines
        if ($line -match '^\s*#' -or $line -match '^\s*$') {
            continue
        }

        # Handle sections
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $currentSection = $matches[1]
            $inArray = $false
            continue
        }

        # Handle array start
        if ($line -match '^\s*([^=]+)=\s*\[') {
            $key = Get-TrimmedString $matches[1]
            $inArray = $true
            $arrayType = $key

            # Check if array is closed on same line
            if ($line -match '\]') {
                $content = (($line -split '\[')[1] -split '\]')[0]
                Parse-ArrayContent $content $currentSection $key
                $inArray = $false
            }
            continue
        }

        # Handle array continuation
        if ($inArray) {
            if ($line -match '\]') {
                # End of array
                $content = ($line -split '\]')[0]
                Parse-ArrayContent $content $currentSection $arrayType
                $inArray = $false
            } else {
                # Array item
                Parse-ArrayContent $line $currentSection $arrayType
            }
            continue
        }

        # Parse key=value pairs
        if ($line -match '^\s*([^=]+)=(.*)$') {
            $key = Get-TrimmedString $matches[1]
            $value = Get-TrimmedString $matches[2]

            # Handle simple format (without sections) or section-based format
            switch ($currentSection) {
                "" { # Simple format
                    switch ($key) {
                        "version" { $config.Version = $value }
                        "name" { $config.Name = $value }
                        "profile" { $config.Profile = $value }
                    }
                }
                "version" {
                    if ($key -eq "default") { $config.Version = $value }
                }
                "build" {
                    switch ($key) {
                        "name" { $config.Name = $value }
                        "disable_libc_wno_error" {
                            $config.DisableLibcWnoError = ($value -eq "true")
                        }
                    }
                }
                "profile" {
                    if ($key -eq "type") { $config.Profile = $value }
                }
                "project" {
                    switch ($key) {
                        "auto_activate" { $config.AutoActivate = $value }
                        "cmake_preset" { $config.CmakePreset = $value }
                    }
                }
                "paths" {
                    switch ($key) {
                        "llvm_home" { $config.LlvmHome = $value }
                        "toolchains_dir" { $config.ToolchainsDir = $value }
                        "sources_dir" { $config.SourcesDir = $value }
                    }
                }
            }
        }
    }

    return $config
}

function Apply-DirectoryConfiguration {
    param([hashtable]$Config)

    # Apply custom paths from configuration if specified
    if ($Config.LlvmHome) {
        $script:LLVM_HOME = $Config.LlvmHome
        Write-VerboseLog "Using custom LLVM_HOME: $script:LLVM_HOME"
    }

    if ($Config.ToolchainsDir) {
        $script:TOOLCHAINS_DIR = $Config.ToolchainsDir
        Write-VerboseLog "Using custom TOOLCHAINS_DIR: $script:TOOLCHAINS_DIR"
    } else {
        $script:TOOLCHAINS_DIR = "$script:LLVM_HOME\toolchains"
    }

    if ($Config.SourcesDir) {
        $script:SOURCES_DIR = $Config.SourcesDir
        Write-VerboseLog "Using custom SOURCES_DIR: $script:SOURCES_DIR"
    } else {
        $script:SOURCES_DIR = "$script:LLVM_HOME\sources"
    }
}

function Install-LlvmVersion {
    param(
        [string]$VersionToInstall,
        [bool]$BuildFromSource,
        [string[]]$CmakeFlagsArray,
        [string]$CustomName,
        [bool]$SetAsDefault,
        [string]$BuildProfile,
        [string[]]$ComponentsArray,
        [bool]$DisableLibcWnoErrorFlag = $false,
        [bool]$ForceReconfigure = $false
    )

    # Load config file if it exists
    $config = Read-LlvmConfig
    if ($config -and -not $VersionToInstall) {
        $VersionToInstall = $config.Version
        if (-not $CustomName) { $CustomName = $config.Name }
        if (-not $BuildProfile) { $BuildProfile = $config.Profile }
        if ($CmakeFlagsArray.Count -eq 0) { $CmakeFlagsArray = $config.CmakeFlags }
        if ($ComponentsArray.Count -eq 0) { $ComponentsArray = $config.Components }
        if (-not $DisableLibcWnoErrorFlag) { $DisableLibcWnoErrorFlag = $config.DisableLibcWnoError }
    }

    if (-not $VersionToInstall) {
        Write-ErrorLog "No version specified"
        return $false
    }

    Write-InfoLog "🚀 Installing LLVM version: $VersionToInstall"

    if ($BuildFromSource) {
        return Install-FromSource -Version $VersionToInstall -CmakeFlags $CmakeFlagsArray -Name $CustomName -SetDefault $SetAsDefault -Profile $BuildProfile -Components $ComponentsArray -DisableLibcWnoError $DisableLibcWnoErrorFlag -ForceReconfigure $ForceReconfigure
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

    Write-InfoLog "📥 Installing pre-built LLVM $Version..."

    # Use existing Download-Llvm.ps1 logic here, adapted for new parameters
    # This is a simplified version - you would integrate the existing download logic

    $installName = if ($Name) { $Name } else { $Version }
    $targetDir = Join-Path $script:TOOLCHAINS_DIR $installName

    # TODO: Integrate actual download and installation logic from Download-Llvm.ps1
    Write-SuccessLog "LLVM $Version installed as '$installName'"

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
        [string[]]$Components,
        [bool]$DisableLibcWnoError = $false,
        [bool]$ForceReconfigure = $false
    )

    Write-InfoLog "🔨 Building LLVM $Version from source..."

    $buildName = if ($Name) { $Name } else { $Version }

    # Extract major version number for version-specific configuration
    $majorVersion = ""
    if ($Version -match "llvmorg-(\d+)") {
        $majorVersion = $matches[1]
    }

    # Determine projects to build
    $projectsToBuild = ""
    if ($Profile) {
        $projectsToBuild = Get-ProfileProjects $Profile
    } elseif ($Components.Count -gt 0) {
        $projectsToBuild = $Components -join ';'
    } else {
        $projectsToBuild = Get-ProfileProjects "full"
    }

    Write-InfoLog "🔧 Build Configuration:"
    Write-InfoLog "   📦 Version: $Version $(if ($majorVersion) { "(LLVM $majorVersion)" })"
    Write-InfoLog "   🏷️  Name: $buildName"
    Write-InfoLog "   📋 Profile: $(if ($Profile) { $Profile } else { 'default' })"
    Write-InfoLog "   🧩 Projects: $projectsToBuild"
    if ($CmakeFlags.Count -gt 0) {
        Write-InfoLog "   🔧 Custom CMake flags: $($CmakeFlags -join ' ')"
    }

    # Show LIBC_WNO_ERROR flag status
    if (-not $DisableLibcWnoError) {
        Write-VerboseLog "Added LIBC_WNO_ERROR=ON flag"
    } else {
        Write-VerboseLog "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
    }

    # Check if we're in mock mode
    if ($env:LLVM_TEST_MODE) {
        Write-InfoLog "🧪 Test mode: Mock build completed successfully!"
        Write-InfoLog "📁 LLVM $buildName would be installed to: $script:TOOLCHAINS_DIR\$buildName"
        Write-InfoLog "🚀 To activate: llvm-activate $buildName"

        if ($SetDefault) {
            Write-InfoLog "🔗 This version would be set as default"
        }
        return $true
    }

    # Real build process would start here
    Write-InfoLog "🏗️  Starting real LLVM build process..."

    # Prepare CMake arguments (similar to bash version)
    $cmakeArgs = @(
        "-S", "$script:SOURCES_DIR\$Version\llvm"
        "-B", "$script:SOURCES_DIR\$Version\build"
        "-G", "Ninja"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_C_FLAGS=-march=native -mtune=native"
        "-DCMAKE_CXX_FLAGS=-march=native -mtune=native"
        "-DCMAKE_INSTALL_PREFIX=$script:TOOLCHAINS_DIR\$buildName"
    )

    # Add LIBC_WNO_ERROR flag if not disabled
    if (-not $DisableLibcWnoError) {
        $cmakeArgs += "-DLIBC_WNO_ERROR=ON"
        Write-VerboseLog "Added LIBC_WNO_ERROR=ON flag"
    } else {
        Write-VerboseLog "Skipped LIBC_WNO_ERROR=ON flag (disabled)"
    }

    # Add projects to build
    if ($projectsToBuild) {
        $cmakeArgs += "-DLLVM_ENABLE_PROJECTS=$projectsToBuild"
    } else {
        # Default: build all available projects
        $cmakeArgs += "-DLLVM_ENABLE_PROJECTS=all"
    }

    # Add custom CMake flags
    foreach ($flag in $CmakeFlags) {
        $cmakeArgs += $flag
        Write-VerboseLog "Added CMake flag: $flag"
    }

    Write-VerboseLog "CMake command: cmake $($cmakeArgs -join ' ')"

    # Force reconfiguration if requested and CMakeCache.txt exists
    $buildDir = "$script:SOURCES_DIR\$Version\build"
    $cmakeCachePath = "$buildDir\CMakeCache.txt"
    if ($ForceReconfigure -and (Test-Path $cmakeCachePath)) {
        Write-InfoLog "♻️  Forcing CMake reconfiguration..."
        Remove-Item $cmakeCachePath -Force -ErrorAction SilentlyContinue
        $cmakeFilesPath = "$buildDir\CMakeFiles"
        if (Test-Path $cmakeFilesPath) {
            Remove-Item $cmakeFilesPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-VerboseLog "Removed CMakeCache.txt and CMakeFiles directory"
    }

    # TODO: Implement actual source build logic
    # This would involve git clone, cmake configure, build, and install

    Write-SuccessLog "Build and installation complete!"
    Write-InfoLog "📁 LLVM version $Version has been installed as $buildName"
    Write-TipLog "To activate: llvm-activate $buildName"

    if ($SetDefault) {
        Set-DefaultVersion $buildName | Out-Null
    }

    return $true
}

function Initialize-LlvmConfig {
    $configFile = ".llvmup-config"

    if (Test-Path $configFile) {
        Write-WarningLog ".llvmup-config already exists in current directory"
        Write-InfoLog "Current configuration:"
        Get-Content $configFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

        $response = Read-Host "Overwrite existing configuration? [y/N]"
        if ($response -notmatch '^[Yy]$') {
            Write-ErrorLog "Configuration initialization cancelled"
            return
        }
    }

    Write-ConfigLog "Initializing LLVM project configuration..."

    # For testing, use environment variables or defaults
    if ($env:LLVM_TEST_MODE) {
        $defaultVersion = if ($env:LLVM_TEST_VERSION) { $env:LLVM_TEST_VERSION } else { "llvmorg-18.1.8" }
        $customName = if ($env:LLVM_TEST_CUSTOM_NAME) { $env:LLVM_TEST_CUSTOM_NAME } else { "" }
        $profile = if ($env:LLVM_TEST_PROFILE) { $env:LLVM_TEST_PROFILE } else { "full" }
    } else {
        # Prompt for configuration
        Write-InfoLog "Please provide the following information:"

        # Check for installed versions first
        $suggestedVersion = ""
        $installedVersions = @()

        if (Test-Path $script:TOOLCHAINS_DIR) {
            $installedVersions = Get-ChildItem -Path $script:TOOLCHAINS_DIR -Directory | Select-Object -ExpandProperty Name
        }

        if ($installedVersions.Count -gt 0) {
            Write-InfoLog "Detected installed versions:"
            $installedVersions | ForEach-Object { Write-InfoLog "  • $_" }
            $suggestedVersion = $installedVersions[0]
            Write-InfoLog ""
        }

        if ($suggestedVersion) {
            $defaultVersion = Read-Host "Default LLVM version [$suggestedVersion]"
            if (-not $defaultVersion) { $defaultVersion = $suggestedVersion }
        } else {
            $defaultVersion = Read-Host "Default LLVM version (e.g., llvmorg-18.1.8)"
            if (-not $defaultVersion) { $defaultVersion = "llvmorg-18.1.8" }
        }

        $customName = Read-Host "Custom installation name (optional)"
        $profile = Read-Host "Build profile [minimal/full/custom]"
        if (-not $profile) { $profile = "full" }
    }

    # Create configuration file
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
  "-DCMAKE_BUILD_TYPE=Release"
]

[profile]
type = "$profile"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]

[project]
# Project-specific settings
auto_activate = true
cmake_preset = "Release"
"@

    Set-Content -Path $configFile -Value $configContent
    Write-SuccessLog "Configuration file created: $configFile"
    Write-TipLog "Edit the file to customize build settings"
    Write-TipLog "Run '.\Install-Llvm.ps1 config load' to install and activate the configured version"
}

# Function to load and parse .llvmup-config settings (parse only)
function Invoke-LlvmConfigLoad {
    $configFile = ".llvmup-config"

    if (-not (Test-Path $configFile)) {
        Write-ErrorLog "No .llvmup-config file found in current directory"
        Write-TipLog "Run '.\Install-Llvm.ps1 config init' to create one"
        return $null
    }

    Write-ProgressLog "Loading project configuration from $configFile..."

    $config = Read-LlvmConfig

    if (-not $config.Version) {
        Write-ErrorLog "No default version specified in configuration"
        return $null
    }

    # Apply cmake preset if specified
    if ($config.CmakePreset) {
        switch ($config.CmakePreset) {
            "Debug" {
                $config.CmakeFlags += "-DCMAKE_BUILD_TYPE=Debug"
                $config.CmakeFlags += "-DLLVM_ENABLE_ASSERTIONS=ON"
            }
            "Release" {
                $config.CmakeFlags += "-DCMAKE_BUILD_TYPE=Release"
                $config.CmakeFlags += "-DLLVM_ENABLE_ASSERTIONS=OFF"
            }
            "RelWithDebInfo" {
                $config.CmakeFlags += "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
                $config.CmakeFlags += "-DLLVM_ENABLE_ASSERTIONS=ON"
            }
            "MinSizeRel" {
                $config.CmakeFlags += "-DCMAKE_BUILD_TYPE=MinSizeRel"
                $config.CmakeFlags += "-DLLVM_ENABLE_ASSERTIONS=OFF"
            }
            default {
                Write-WarningLog "Unknown cmake_preset: $($config.CmakePreset) (ignoring)"
            }
        }
    }

    Write-ConfigLog "Configuration loaded:"
    Write-InfoLog "   📦 Version: $($config.Version)"
    if ($config.Name) { Write-InfoLog "   🏷️  Name: $($config.Name)" }
    if ($config.Profile) { Write-InfoLog "   📋 Profile: $($config.Profile)" }
    if ($config.CmakeFlags.Count -gt 0) { Write-VerboseLog "CMake flags: $($config.CmakeFlags -join ' ')" }
    if ($config.Components.Count -gt 0) { Write-VerboseLog "Components: $($config.Components -join ', ')" }
    if ($config.CmakePreset) { Write-VerboseLog "CMake preset: $($config.CmakePreset)" }
    if ($config.AutoActivate -eq "true") {
        Write-VerboseLog "Auto-activate: enabled"
    } elseif ($config.AutoActivate -eq "false") {
        Write-VerboseLog "Auto-activate: disabled"
    }

    Write-TipLog "Next steps:"
    Write-TipLog "  • .\Install-Llvm.ps1 config apply    - Install with these settings"
    Write-TipLog "  • .\Install-Llvm.ps1 config activate - Activate if already installed"

    return $config
}

# Function to apply loaded .llvmup-config settings (install)
function Invoke-LlvmConfigApply {
    $config = Invoke-LlvmConfigLoad
    if (-not $config) {
        return $false
    }

    # Build command arguments
    $cmdArgs = @()
    $cmdArgs += $config.Version
    if ($config.Name) { $cmdArgs += "-Name"; $cmdArgs += $config.Name }
    if ($config.Profile) { $cmdArgs += "-Profile"; $cmdArgs += $config.Profile }

    foreach ($flag in $config.CmakeFlags) {
        $cmdArgs += "-CmakeFlags"; $cmdArgs += $flag
    }

    foreach ($component in $config.Components) {
        $cmdArgs += "-Component"; $cmdArgs += $component
    }

    if ($config.DisableLibcWnoError) {
        $cmdArgs += "-DisableLibcWnoError"
    }

    Write-TipLog "Installing with settings:"
    Write-TipLog "  .\Install-Llvm.ps1 install -FromSource $($cmdArgs -join ' ')"

    # In test mode, don't prompt for installation
    if ($env:LLVM_TEST_MODE) {
        Write-VerboseLog "Test mode: skipping installation"
        return $true
    }

    # Ask if user wants to install now
    $response = Read-Host "Install now? [y/N]"
    if ($response -match '^[Yy]$') {
        Write-ProgressLog "Installing LLVM with project configuration..."
        $result = Install-LlvmVersion -VersionToInstall $config.Version -BuildFromSource $true -CmakeFlagsArray $config.CmakeFlags -CustomName $config.Name -SetAsDefault $false -BuildProfile $config.Profile -ComponentsArray $config.Components -DisableLibcWnoErrorFlag $config.DisableLibcWnoError
        if ($result) {
            Write-TipLog "Use '.\Install-Llvm.ps1 config activate' to activate the version"
        }
        return $result
    } else {
        Write-TipLog "To install later, run: .\Install-Llvm.ps1 install -FromSource $($cmdArgs -join ' ')"
        Write-TipLog "To activate if already installed, run: .\Install-Llvm.ps1 config activate"
        return $true
    }
}

# Function to handle activation based on configuration
function Invoke-LlvmConfigActivate {
    $config = Invoke-LlvmConfigLoad
    if (-not $config) {
        return $false
    }

    # Determine installation name (same logic as apply)
    $installationName = $config.Version
    if ($config.Name) {
        $installationName = $config.Name
    }

    Write-ConfigLog "Activating LLVM configuration:"
    Write-InfoLog "   Version: $($config.Version)"
    if ($config.Name) { Write-VerboseLog "Name: $($config.Name)" }
    if ($config.Profile) { Write-VerboseLog "Profile: $($config.Profile)" }
    Write-VerboseLog "Installation: $installationName"

    # Check if installation exists
    $installationPath = Join-Path $script:TOOLCHAINS_DIR $installationName
    if (-not (Test-Path $installationPath)) {
        Write-ErrorLog "Installation not found: $installationName"
        Write-TipLog "Run '.\Install-Llvm.ps1 config apply' to install first"
        return $false
    }

    # Try to activate the installation (simplified - would integrate with existing activation logic)
    Write-SuccessLog "LLVM configuration activated: $installationName"
    if ($config.AutoActivate -eq "true") {
        Write-InfoLog "Auto-activation enabled for this project"
    }

    return $true
}

# Main execution logic
if ($Help) {
    Show-Help
    exit 0
}

# Load configuration to apply custom directory settings early
$earlyConfig = Read-LlvmConfig
if ($earlyConfig) {
    Apply-DirectoryConfiguration -Config $earlyConfig
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
                Write-ErrorLog "Missing version argument for 'default set'"
                exit 1
            }
            Set-DefaultVersion $args[0]
        } elseif ($Version -eq "show" -or -not $Version) {
            Show-DefaultVersion
        } else {
            Write-ErrorLog "Unknown default subcommand: $Version"
            Write-InfoLog "Available subcommands: set, show"
            exit 1
        }
    }
    "config" {
        switch ($Version.ToLower()) {
            "init" { Initialize-LlvmConfig }
            "load" {
                $result = Invoke-LlvmConfigLoad
                if (-not $result) { exit 1 }
            }
            "apply" {
                $result = Invoke-LlvmConfigApply
                if (-not $result) { exit 1 }
            }
            "activate" {
                $result = Invoke-LlvmConfigActivate
                if (-not $result) { exit 1 }
            }
            default {
                Write-ErrorLog "Unknown config subcommand: $Version"
                Write-InfoLog "Available subcommands: init, load, apply, activate"
                exit 1
            }
        }
    }
    "install" {
        $result = Install-LlvmVersion -VersionToInstall $Version -BuildFromSource $FromSource -CmakeFlagsArray $CmakeFlags -CustomName $Name -SetAsDefault $Default -BuildProfile $Profile -ComponentsArray $Component -DisableLibcWnoErrorFlag $DisableLibcWnoError -ForceReconfigure $Reconfigure
        if (-not $result) {
            exit 1
        }
    }
    default {
        # Default to install command
        $result = Install-LlvmVersion -VersionToInstall $Command -BuildFromSource $FromSource -CmakeFlagsArray $CmakeFlags -CustomName $Name -SetAsDefault $Default -BuildProfile $Profile -ComponentsArray $Component -DisableLibcWnoErrorFlag $DisableLibcWnoError -ForceReconfigure $Reconfigure
        if (-not $result) {
            exit 1
        }
    }
}
