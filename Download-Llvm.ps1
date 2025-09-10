# Download-Llvm.ps1: Enhanced LLVM prebuilt download and installation manager
# Requirements: PowerShell v5 or later
# Based on llvm-prebuilt bash implementation
# Usage:
#   . Download-Llvm.ps1 [version] [-Platform <platform>] [-Arch <arch>] [-Force] [-TestMode] [-SkipVerify]

param (
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Windows", "Linux", "macOS")]
    [string]$Platform,

    [Parameter(Mandatory = $false)]
    [ValidateSet("x64", "x86", "arm64", "armv7a")]
    [string]$Arch,

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$TestMode,

    [Parameter(Mandatory = $false)]
    [switch]$SkipVerify,

    [Parameter(Mandatory = $false)]
    [switch]$ArchiveOnly,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSec = 60,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
$homeDir = Get-UserHome
$script:LLVM_HOME = Join-Path $homeDir ".llvm"
$script:TOOLCHAINS_DIR = Join-Path $script:LLVM_HOME "toolchains"
$defaultTemp = Get-TempDir
$script:TEMP_DIR = Join-Path $defaultTemp "llvm_temp"

# =============================================================================
# LOGGING FUNCTIONS (ported from bash)
# =============================================================================

function Write-VerboseLog {
    param([string]$Message)
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "VERBOSE: $Message" -ForegroundColor Gray
    }
}

function Write-InfoLog {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Error "❌ $Message"
}

function Write-SuccessLog {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-WarningLog {
    param([string]$Message)
    Write-Warning "⚠️  $Message"
}

function Write-ProgressLog {
    param([string]$Message)
    Write-Host "🔄 $Message" -ForegroundColor Yellow
}

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

function Get-CurrentPlatform {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return "Windows"
    } elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return "Linux"
    } elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return "macOS"
    } else {
        throw "Unsupported platform"
    }
}

function Get-CurrentArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    switch ($arch) {
        "X64" { return "x64" }
        "X86" { return "x86" }
        "Arm64" { return "arm64" }
        "Arm" { return "armv7a" }
        default { return "x64" }  # fallback
    }
}

# =============================================================================
# RELEASE MANAGEMENT (ported from llvm-prebuilt)
# =============================================================================

function Get-LlvmReleases {
    [CmdletBinding()]
    param(
        [string]$ApiUrl = "https://api.github.com/repos/llvm/llvm-project/releases",
        [int]$TimeoutSec = 60
    )

    Write-VerboseLog "Fetching LLVM releases from GitHub API: $ApiUrl"

    # In test mode, use cached releases
    if ($env:LLVM_TEST_MODE -eq "1" -or $TestMode) {
        $cacheFile = Join-Path $PSScriptRoot "githubreleases.json"
        if (Test-Path $cacheFile) {
            Write-InfoLog "Using cached releases (Test Mode)"
            $content = Get-Content $cacheFile -Raw | ConvertFrom-Json
            return $content
        }
    }

    try {
        Write-ProgressLog "Connecting to GitHub API..."
        $response = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec $TimeoutSec -ErrorAction Stop
        Write-SuccessLog "Successfully retrieved release information from GitHub"
        Write-VerboseLog "API response received ($($response.Count) releases)"
        return $response
    }
    catch {
        Write-ErrorLog "Failed to fetch releases from GitHub API: $($_.Exception.Message)"

        # Fallback to cached file if available
        $cacheFile = Join-Path $PSScriptRoot "githubreleases.json"
        if (Test-Path $cacheFile) {
            Write-WarningLog "Falling back to cached releases"
            $content = Get-Content $cacheFile -Raw | ConvertFrom-Json
            return $content
        }

        throw "Unable to fetch releases from API or cache"
    }
}

function Normalize-Architecture {
    param([string]$Arch)

    switch ($Arch.ToLower()) {
        { $_ -in @("x86_64", "amd64", "x64") } { return "x64" }
        { $_ -in @("aarch64", "arm64") } { return "arm64" }
        { $_ -in @("armv7a", "armv7", "arm") } { return "armv7a" }
        { $_ -in @("x86", "i386", "i686") } { return "x86" }
        default { return $Arch }
    }
}

function Select-LlvmAssetForPlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Assets,

        [Parameter(Mandatory = $true)]
        [string]$Platform,

        [Parameter(Mandatory = $true)]
        [string]$Architecture,

        [switch]$PreferInstaller
    )

    $normalizedArch = Normalize-Architecture $Architecture
    $candidates = @()

    Write-VerboseLog "Selecting asset for platform: $Platform, architecture: $normalizedArch"
    Write-VerboseLog "Available assets: $($Assets.Count)"

    foreach ($asset in $Assets) {
        $score = 0
        $assetName = $asset.name

        # Skip signature files
        if ($assetName -match '\.(sig|jsonl)$') {
            continue
        }

        Write-VerboseLog "Evaluating asset: $assetName"

        # Platform-specific scoring
        switch ($Platform) {
            "Windows" {
                # Prefer LLVM-*-win*.exe (installer) or clang+llvm-*-windows-msvc.tar.xz (archive)
                if ($assetName -match "LLVM-.*-win(64|32)\.exe") {
                    $score += 100
                    if ($PreferInstaller) { $score += 20 }
                } elseif ($assetName -match "clang\+llvm-.*-.*-pc-windows-msvc\.tar\.xz") {
                    $score += 80
                    if (-not $PreferInstaller) { $score += 20 }
                } elseif ($assetName -match "LLVM-.*-woa64\.exe" -and $normalizedArch -eq "arm64") {
                    $score += 90
                }
            }
            "Linux" {
                # Prefer LLVM-*-Linux-*.tar.xz or clang+llvm-*-linux-*.tar.*
                if ($assetName -match "LLVM-.*-Linux-.*\.tar\.xz") {
                    $score += 100
                } elseif ($assetName -match "clang\+llvm-.*-.*-linux-.*\.tar\.(gz|xz)") {
                    $score += 80
                }
            }
            "macOS" {
                # Prefer LLVM-*-macOS-*.tar.xz or clang+llvm-*-apple-darwin*.tar.*
                if ($assetName -match "LLVM-.*-macOS-.*\.tar\.xz") {
                    $score += 100
                } elseif ($assetName -match "clang\+llvm-.*-apple-darwin.*\.tar\.(gz|xz)") {
                    $score += 80
                }
            }
        }

        # Architecture-specific scoring
        if ($score -gt 0) {
            switch ($normalizedArch) {
                "x64" {
                    if ($assetName -match "(X64|x86_64|amd64)") { $score += 50 }
                }
                "arm64" {
                    if ($assetName -match "(ARM64|aarch64)") { $score += 50 }
                }
                "armv7a" {
                    if ($assetName -match "armv7a") { $score += 50 }
                }
                "x86" {
                    if ($assetName -match "(win32|x86|i386)") { $score += 50 }
                }
            }
        }

        if ($score -gt 0) {
            $candidates += @{
                Asset = $asset
                Score = $score
                Name = $assetName
            }
        }
    }

    if ($candidates.Count -eq 0) {
        Write-WarningLog "No suitable prebuilt asset found for $Platform $normalizedArch"
        return $null
    }

    # Sort by score (highest first) and return the best match
    $best = $candidates | Sort-Object Score -Descending | Select-Object -First 1
    Write-VerboseLog "Selected asset: $($best.Name) (score: $($best.Score))"

    # Check for verification file
    $verifiable = $false
    $sigFile = $Assets | Where-Object { $_.name -eq "$($best.Asset.name).sig" }
    $jsonlFile = $Assets | Where-Object { $_.name -eq "$($best.Asset.name).jsonl" }

    if ($sigFile -or $jsonlFile) {
        $verifiable = $true
        Write-VerboseLog "Asset has verification file available"
    }

    return @{
        Asset = $best.Asset
        Name = $best.Asset.name
        Url = $best.Asset.browser_download_url
        Size = $best.Asset.size
        Digest = $best.Asset.digest
        Verifiable = $verifiable
        SigFile = $sigFile
        JsonlFile = $jsonlFile
    }
}

    # If input is a number, use it as an index (1-based)
    if ($Input -match '^\d+$') {
        $index = [int]$Input - 1
        if ($index -ge 0 -and $index -lt $releaseList.Count) {
            return $releaseList[$index]
        }
    } else {
        # Otherwise, assume it's a version tag
        if ($releaseList -contains $Input) {
            return $Input
        }
    }
    return $null
}

# Check if version was provided as parameter
if ($Version) {
    $selectedTag = Select-Version -Input $Version
    if ($selectedTag) {
        Write-Output "You selected: $selectedTag"
    } else {
        Write-Error "Invalid version selection: '$Version'"
        Write-Output "Please provide either a valid version number from the list or a valid version tag."
        exit 1
    }
} else {
    # No version provided: prompt the user
    $choice = Read-Host "Select a version by number"
    $selectedTag = Select-Version -Input $choice
    if ($selectedTag) {
        Write-Output "You selected: $selectedTag"
    } else {
        Write-Error "Invalid selection: '$choice'"
        Write-Output "Please provide either a valid version number from the list or a valid version tag."
        exit 1
    }
}

# Locate the asset that contains "win64.exe" for the selected release
$asset = $releases | Where-Object { $_.tag_name -eq $selectedTag } |
    Select-Object -ExpandProperty assets |
    Where-Object { $_.name -match "win64\.exe$" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No Windows 64-bit installer found for release $selectedTag."
    Write-Output "This might be because the release doesn't include a Windows installer or the asset naming has changed."
    Write-Output "Please try a different version or check the LLVM releases page manually."
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Output "Download URL found: $downloadUrl"

# Define the download directory
$downloadDir = Join-Path $env:USERPROFILE "llvm_temp\$selectedTag"
if (-not (Test-Path $downloadDir)) {
    try {
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
    } catch {
        Write-Error "Failed to create download directory: $downloadDir"
        Write-Output "Please check if you have write permissions in your user directory."
        exit 1
    }
}

$fileName = Split-Path $downloadUrl -Leaf
$outputFile = Join-Path $downloadDir $fileName

Write-Output "Downloading the installer..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    Write-Output "Download completed: $outputFile"
} catch {
    Write-Error "Download failed. Please check your internet connection and try again."
    Write-Output "Error details: $_"
    exit 1
}

# Define the target installation directory
$targetDir = Join-Path $env:USERPROFILE ".llvm\toolchains\$selectedTag"
$parentDir = Split-Path $targetDir -Parent
if (-not (Test-Path $parentDir)) {
    try {
        New-Item -ItemType Directory -Path $parentDir | Out-Null
    } catch {
        Write-Error "Failed to create installation directory: $parentDir"
        Write-Output "Please check if you have write permissions in your user directory."
        exit 1
    }
}

# Build the installer argument string
$arguments = "/S /D=$targetDir"

Write-Output "Starting silent installation of LLVM version '$selectedTag'..."
Write-Output "Installation directory: $targetDir"

# Start the NSIS installer with the silent and directory parameters
try {
    Start-Process -FilePath $outputFile -ArgumentList $arguments -Wait
} catch {
    Write-Error "Installation failed. Please check if you have administrator privileges and try again."
    Write-Output "Error details: $_"
    exit 1
}

Write-Output "LLVM $selectedTag installed in $targetDir."

# Clean up temporary files
try {
    Remove-Item -Path $downloadDir -Recurse -Force
} catch {
    Write-Warning "Failed to clean up temporary files in $downloadDir"
    Write-Output "You can safely delete this directory manually."
}

Write-Output "Run '. Activate-Llvm.ps1 $selectedTag' to activate the installed version."

# Show help if requested
if ($Help) {
    Write-Output "LLVMUP: Enhanced LLVM Version Manager for Windows"
    Write-Output ""
    Write-Output "Usage:"
    Write-Output "  Download-Llvm.ps1 [version] [options]"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Version <version>      LLVM version to install (e.g., 'llvmorg-18.1.8')"
    Write-Output "  -CMakeFlags <flags>     Additional CMake flags (can be specified multiple times)"
    Write-Output "  -Name <name>            Custom name for installation"
    Write-Output "  -Default                Set as default LLVM version"
    Write-Output "  -Profile <profile>      Build profile: minimal, full, custom"
    Write-Output "  -Component <component>  Specific components to install"
    Write-Output "  -FromSource             Build from source (requires build tools)"
    Write-Output "  -Verbose                Enable verbose output"
    Write-Output "  -Help                   Show this help message"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  Download-Llvm.ps1 llvmorg-18.1.8"
    Write-Output "  Download-Llvm.ps1 -Profile minimal llvmorg-18.1.8"
    Write-Output "  Download-Llvm.ps1 -CMakeFlags '-DCMAKE_BUILD_TYPE=Debug' -Name '18.1.8-debug'"
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

function Write-LogVerbose {
    param([string]$Message)
    if ($Verbose) {
        Write-Output "[VERBOSE] $Message"
    }
}
