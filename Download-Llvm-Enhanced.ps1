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

# Global variables
$script:LLVM_HOME = "$env:USERPROFILE\.llvm"
$script:TOOLCHAINS_DIR = "$script:LLVM_HOME\toolchains"
$script:TEMP_DIR = "$env:TEMP\llvm_temp"

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
        [Parameter(Mandatory = $false)]
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
    $assetCount = if ($Assets) { $Assets.Count } else { 0 }
    Write-VerboseLog "Available assets: $assetCount"

    # Defensive: handle empty or null asset lists gracefully
    if (-not $Assets -or $assetCount -eq 0) {
        Write-VerboseLog "No assets provided to Select-LlvmAssetForPlatform"
        return $null
    }

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

# =============================================================================
# DOWNLOAD FUNCTIONS (with retry and verification)
# =============================================================================

function Download-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutPath,

        [int]$TimeoutSec = 60,
        [int]$MaxRetries = 3,
        [string]$ExpectedDigest
    )

    $attempt = 1
    $success = $false

    while ($attempt -le $MaxRetries -and -not $success) {
        try {
            Write-ProgressLog "Downloading (attempt $attempt/$MaxRetries): $(Split-Path $Url -Leaf)"
            Write-VerboseLog "URL: $Url"
            Write-VerboseLog "Output: $OutPath"

            # Ensure directory exists
            $dir = Split-Path $OutPath -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            # Download with progress (PowerShell 5+ compatible)
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutPath)
            $webClient.Dispose()

            # Verify file exists and has content
            if (-not (Test-Path $OutPath) -or (Get-Item $OutPath).Length -eq 0) {
                throw "Downloaded file is missing or empty"
            }

            # Verify digest if provided
            if ($ExpectedDigest) {
                Write-VerboseLog "Verifying SHA256 digest..."
                $actualDigest = (Get-FileHash -Path $OutPath -Algorithm SHA256).Hash.ToLower()
                $expectedDigest = $ExpectedDigest.ToLower().Replace("sha256:", "")

                if ($actualDigest -ne $expectedDigest) {
                    throw "Digest verification failed. Expected: $expectedDigest, Actual: $actualDigest"
                }
                Write-VerboseLog "Digest verification passed"
            }

            $success = $true
            Write-SuccessLog "Download completed: $(Split-Path $Url -Leaf)"
        }
        catch {
            Write-WarningLog "Download attempt $attempt failed: $($_.Exception.Message)"

            if ($attempt -lt $MaxRetries) {
                $waitTime = [Math]::Pow(2, $attempt - 1) * 2  # Exponential backoff: 2, 4, 8 seconds
                Write-VerboseLog "Waiting $waitTime seconds before retry..."
                Start-Sleep -Seconds $waitTime
            }

            $attempt++
        }
    }

    if (-not $success) {
        throw "Failed to download after $MaxRetries attempts"
    }

    return $OutPath
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

function Test-ExtractorAvailable {
    [CmdletBinding()]
    param([string]$Type)

    switch ($Type) {
        "tar" {
            # Check for Windows 10+ built-in tar or external tar
            try {
                $null = Get-Command tar -ErrorAction Stop
                return $true
            } catch {
                return $false
            }
        }
        "7zip" {
            # Check for 7-Zip
            $paths = @(
                "${env:ProgramFiles}\7-Zip\7z.exe",
                "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                "7z.exe"
            )
            foreach ($path in $paths) {
                if (Get-Command $path -ErrorAction SilentlyContinue) {
                    return $true
                }
            }
            return $false
        }
        default { return $false }
    }
}

function Extract-Archive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $archiveName = Split-Path $ArchivePath -Leaf
    Write-ProgressLog "Extracting archive: $archiveName"

    # Ensure destination directory exists
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    # Determine archive type and extraction method
    if ($archiveName -match '\.(tar\.xz|tar\.gz)$') {
        # Try tar first (available on Windows 10+)
        if (Test-ExtractorAvailable "tar") {
            Write-VerboseLog "Using tar for extraction"
            $tarArgs = @("-xf", $ArchivePath, "-C", $DestinationPath, "--strip-components=1")
            & tar @tarArgs
            if ($LASTEXITCODE -ne 0) {
                throw "tar extraction failed with exit code $LASTEXITCODE"
            }
        } elseif (Test-ExtractorAvailable "7zip") {
            Write-VerboseLog "Using 7-Zip for extraction"
            # 7-Zip requires two-step extraction for .tar.xz
            $tempDir = Join-Path $env:TEMP "llvm_extract_$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                # First extract .tar.xz to .tar
                & 7z x $ArchivePath -o"$tempDir" -y
                $tarFile = Get-ChildItem -Path $tempDir -Filter "*.tar" | Select-Object -First 1

                if ($tarFile) {
                    # Then extract .tar to destination
                    & 7z x $tarFile.FullName -o"$tempDir" -y

                    # Move contents (skip first directory level)
                    $extracted = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
                    if ($extracted) {
                        Copy-Item -Path "$($extracted.FullName)\*" -Destination $DestinationPath -Recurse -Force
                    }
                }
            } finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            throw "No suitable extractor found for .tar.xz/.tar.gz files. Please install tar or 7-Zip."
        }
    } elseif ($archiveName -match '\.zip$') {
        # Use built-in Expand-Archive for .zip files
        Write-VerboseLog "Using Expand-Archive for ZIP extraction"
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
    } else {
        throw "Unsupported archive format: $archiveName"
    }

    Write-SuccessLog "Archive extracted successfully"
}

function Install-PrebuiltLlvm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$SelectedAsset,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string]$CustomName,
        [switch]$Force
    )

    $installName = if ($CustomName) { $CustomName } else { $Version }
    $installPath = Join-Path $script:TOOLCHAINS_DIR $installName

    # Check if already installed
    if ((Test-Path $installPath) -and -not $Force) {
        Write-WarningLog "LLVM $installName is already installed at $installPath"
        Write-InfoLog "Use -Force to reinstall"
        return $installPath
    }

    # Create temp directory
    $tempDir = Join-Path $script:TEMP_DIR $Version
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Download the asset
        $downloadPath = Join-Path $tempDir $SelectedAsset.Name
        Download-File -Url $SelectedAsset.Url -OutPath $downloadPath -ExpectedDigest $SelectedAsset.Digest -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries

        # Handle installation based on file type
        if ($SelectedAsset.Name -match '\.exe$') {
            # Windows installer
            Write-ProgressLog "Installing LLVM using Windows installer..."

            if (Test-Path $installPath) {
                Remove-Item -Path $installPath -Recurse -Force
            }

            $arguments = @("/S", "/D=$installPath")
            $process = Start-Process -FilePath $downloadPath -ArgumentList $arguments -Wait -PassThru

            if ($process.ExitCode -ne 0) {
                throw "Installer failed with exit code $($process.ExitCode)"
            }
        } else {
            # Archive extraction
            Write-ProgressLog "Extracting LLVM archive..."

            if (Test-Path $installPath) {
                Remove-Item -Path $installPath -Recurse -Force
            }

            Extract-Archive -ArchivePath $downloadPath -DestinationPath $installPath
        }

        # Verify installation
        $binPath = Join-Path $installPath "bin"
        if (-not (Test-Path $binPath)) {
            throw "Installation verification failed: bin directory not found"
        }

        Write-SuccessLog "LLVM $installName installed successfully at $installPath"
        return $installPath

    } finally {
        # Cleanup temp directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Show help if requested
if ($Help) {
    Write-Host @"
LLVM Prebuilt Download and Installation Manager

Usage: Download-Llvm.ps1 [options] [version]

Options:
  -Version <version>    LLVM version to download (e.g., llvmorg-21.1.0)
  -Platform <platform>  Target platform: Windows, Linux, macOS (auto-detected)
  -Arch <arch>         Target architecture: x64, x86, arm64, armv7a (auto-detected)
  -Name <name>         Custom installation name
  -Force               Force reinstallation if already exists
  -TestMode            Use cached releases (no network)
  -SkipVerify          Skip digest verification
  -ArchiveOnly         Prefer archive over installer (Windows)
  -TimeoutSec <sec>    Download timeout in seconds (default: 60)
  -MaxRetries <num>    Maximum download retries (default: 3)
  -Help                Show this help message

Examples:
  Download-Llvm.ps1 llvmorg-21.1.0
  Download-Llvm.ps1 -Version llvmorg-21.1.0 -Force
  Download-Llvm.ps1 -Platform Linux -Arch arm64 llvmorg-21.1.0

"@ -ForegroundColor Cyan
    return
}

# Auto-detect platform and architecture if not specified
if (-not $Platform) {
    $Platform = Get-CurrentPlatform
    Write-VerboseLog "Auto-detected platform: $Platform"
}

if (-not $Arch) {
    $Arch = Get-CurrentArchitecture
    Write-VerboseLog "Auto-detected architecture: $Arch"
}

# Ensure LLVM directories exist
New-Item -ItemType Directory -Path $script:TOOLCHAINS_DIR -Force | Out-Null

try {
    # Get available releases
    Write-InfoLog "🚀 LLVM Prebuilt Installation Manager"
    $releases = Get-LlvmReleases -TimeoutSec $TimeoutSec

    if (-not $releases -or $releases.Count -eq 0) {
        throw "No releases found"
    }

    # Select version if not provided
    if (-not $Version) {
        Write-InfoLog "Available versions:"
        for ($i = 0; $i -lt [Math]::Min($releases.Count, 10); $i++) {
            $release = $releases[$i]
            $installPath = Join-Path $script:TOOLCHAINS_DIR $release.tag_name
            $installed = if (Test-Path $installPath) { " [INSTALLED]" } else { "" }
            Write-Host "  $($i + 1)) $($release.tag_name)$installed"
        }

        if ($releases.Count -gt 10) {
            Write-Host "  ... and $($releases.Count - 10) more versions"
        }

        $selection = Read-Host "Select version (1-$([Math]::Min($releases.Count, 10))) or enter tag name"

        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $releases.Count) {
                $Version = $releases[$index].tag_name
            } else {
                throw "Invalid selection"
            }
        } else {
            $Version = $selection
        }
    }

    # Find the selected release
    $selectedRelease = $releases | Where-Object { $_.tag_name -eq $Version }
    if (-not $selectedRelease) {
        throw "Version '$Version' not found in available releases"
    }

    Write-InfoLog "Selected version: $Version"
    Write-VerboseLog "Release assets: $($selectedRelease.assets.Count)"

    # Select appropriate asset
    $selectedAsset = Select-LlvmAssetForPlatform -Assets $selectedRelease.assets -Platform $Platform -Architecture $Arch -PreferInstaller:(-not $ArchiveOnly)

    if (-not $selectedAsset) {
        Write-ErrorLog "No suitable prebuilt asset found for $Platform $Arch"
        Write-InfoLog "Consider building from source using Install-Llvm.ps1 -FromSource"
        return
    }

    Write-InfoLog "Selected asset: $($selectedAsset.Name)"
    Write-InfoLog "Size: $([Math]::Round($selectedAsset.Size / 1MB, 2)) MB"

    # Install the selected asset
    $installPath = Install-PrebuiltLlvm -SelectedAsset $selectedAsset -Version $Version -CustomName $Name -Force:$Force

    Write-SuccessLog "Installation completed successfully!"
    Write-InfoLog "📁 Installation path: $installPath"
    Write-InfoLog "🔄 To activate: Import-Module Llvm-Functions-Core; Invoke-LlvmActivate '$Version'"

} catch {
    Write-ErrorLog "Installation failed: $($_.Exception.Message)"
    exit 1
}
