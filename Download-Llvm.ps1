# Download-Llvm.ps1: Enhanced LLVM prebuilt download and installation manager
# Requirements: PowerShell v5 or later
# Based on llvm-prebuilt bash implementation
# Usage:
#   .\Download-Llvm.ps1 [-Version <expression>] [-Platform <platform>] [-Arch <arch>] [-VerifyPolicy Warn|Strict|Skip]

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
    [ValidateSet("Warn", "Strict", "Skip")]
    [string]$VerifyPolicy,

    [Parameter(Mandatory = $false)]
    [string]$ReleaseKeysPath,

    [Parameter(Mandatory = $false)]
    [switch]$ArchiveOnly,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSec = 60,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [switch]$ResolveOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Text", "Json")]
    [string]$OutputFormat = "Text",

    [Parameter(Mandatory = $false)]
    [switch]$Quiet,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
$coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
if (Test-Path $coreModulePath) { Import-Module $coreModulePath -Force -DisableNameChecking }
$homeDir = Get-UserHome
$script:LLVM_HOME = if ($env:LLVM_HOME) { $env:LLVM_HOME } else { Join-Path $homeDir ".llvm" }
$script:TOOLCHAINS_DIR = if ($env:LLVM_TOOLCHAINS_DIR) { $env:LLVM_TOOLCHAINS_DIR } else { Join-Path $script:LLVM_HOME "toolchains" }
$defaultTemp = Get-TempDir
$script:TEMP_DIR = if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP "llvmup" } else { Join-Path $defaultTemp "llvm_temp" }

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
    if (-not $Quiet) { Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Error "❌ $Message"
}

function Write-SuccessLog {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "✅ $Message" -ForegroundColor Green }
}

function Write-WarningLog {
    param([string]$Message)
    Write-Warning "⚠️  $Message"
}

function Write-ProgressLog {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "🔄 $Message" -ForegroundColor Yellow }
}

function Resolve-LlvmVerificationPolicy {
    [CmdletBinding()]
    param([string]$RequestedPolicy)

    if ($RequestedPolicy) { return $RequestedPolicy.ToLowerInvariant() }
    if ($env:LLVMUP_VERIFY_POLICY) { return $env:LLVMUP_VERIFY_POLICY.ToLowerInvariant() }

    $legacySkip = $SkipVerify -or $env:LLVMUP_SKIP_VERIFY -in @('1', 'true', 'TRUE')
    $legacyRequire = $env:LLVMUP_REQUIRE_VERIFY -in @('1', 'true', 'TRUE')
    if ($legacySkip -and $legacyRequire) {
        throw 'LLVMUP_SKIP_VERIFY and LLVMUP_REQUIRE_VERIFY cannot both be enabled'
    }
    if ($legacySkip) { return 'skip' }
    if ($legacyRequire) { return 'strict' }
    return 'warn'
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

    if ($env:LLVMUP_RELEASES_FILE) {
        if (-not (Test-Path -LiteralPath $env:LLVMUP_RELEASES_FILE -PathType Leaf)) {
            throw "LLVMUP_RELEASES_FILE does not exist: $($env:LLVMUP_RELEASES_FILE)"
        }
        return Get-Content -LiteralPath $env:LLVMUP_RELEASES_FILE -Raw | ConvertFrom-Json
    }

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
        $headers = @{ Accept = 'application/vnd.github+json' }
        $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
        if ($token) { $headers.Authorization = "Bearer $token" }
        $response = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
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

function Get-StableLlvmReleases {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [object[]]$Releases)

    return @($Releases | Where-Object {
        -not $_.draft -and -not $_.prerelease -and
        $_.tag_name -match '^llvmorg-\d+\.\d+\.\d+$'
    })
}

function Resolve-LlvmRemoteRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Releases,
        [string]$Expression = 'latest'
    )

    $stable = Get-StableLlvmReleases -Releases $Releases
    if (-not $stable) { throw 'No stable LLVM releases were identified' }

    $tags = @($stable | ForEach-Object { $_.tag_name })
    try {
        $matches = @(Invoke-LlvmMatchVersions -Expression $Expression -CandidateVersions $tags)
    } catch {
        throw "Invalid version expression '$Expression': $($_.Exception.Message)"
    }

    if (-not $matches) {
        $shown = ($tags | Select-Object -First 10) -join ', '
        throw "No stable LLVM release matches '$Expression'. Identified releases: $shown"
    }

    $selectedTag = $matches | Sort-Object {
        $parsed = ConvertFrom-LlvmVersion $_
        [version](Normalize-LlvmSemver $parsed.Version)
    } | Select-Object -Last 1

    return $stable | Where-Object { $_.tag_name -eq $selectedTag } | Select-Object -First 1
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

        [switch]$PreferInstaller,

        [switch]$ArchiveOnly
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
                    if ($ArchiveOnly) { continue }
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
    $jsonlFile = $Assets | Where-Object { $_.name -eq "$($best.Asset.name).jsonl" } | Select-Object -First 1
    $sigFile = $sigFile | Select-Object -First 1
    $checksumFile = $Assets | Where-Object {
        $_.name -in @(
            "$($best.Asset.name).sha256",
            "$($best.Asset.name).sha256sum",
            "$($best.Asset.name).sha256.txt",
            "$($best.Asset.name).sha256sum.txt"
        )
    } | Select-Object -First 1

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
        ChecksumFile = $checksumFile
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

function Test-LlvmToolchainPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $bin = Join-Path $Path 'bin'
    foreach ($name in @('clang', 'clang++')) {
        $compiler = Get-ChildItem -LiteralPath $bin -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -eq $name -or $_.Name -eq "$name.cmd" } |
            Select-Object -First 1
        if (-not $compiler) { return $false }
        try {
            & $compiler.FullName --version *> $null
            if ($LASTEXITCODE -ne 0) { return $false }
        } catch { return $false }
    }
    return $true
}

function Add-LlvmVerificationMethod {
    param([string]$Method)
    if ($script:VerificationMethods -notcontains $Method) {
        $script:VerificationMethods += $Method
    }
}

function Invoke-LlvmGpgVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ArtifactPath,
        [Parameter(Mandatory = $true)] [object]$SignatureAsset,
        [Parameter(Mandatory = $true)] [string]$TempPath
    )

    $gpg = Get-Command gpg -ErrorAction SilentlyContinue
    if (-not $gpg) {
        $script:VerificationGpg = 'unavailable'
        Write-WarningLog "GPG signature is available, but 'gpg' is not installed; trying another verifier."
        return
    }

    $signaturePath = Join-Path $TempPath $SignatureAsset.name
    try {
        Download-File -Url $SignatureAsset.browser_download_url -OutPath $signaturePath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries | Out-Null
    } catch {
        $script:VerificationGpg = 'unavailable'
        Write-WarningLog "Could not download the GPG signature: $($_.Exception.Message)"
        return
    }

    $keysPath = Join-Path $TempPath 'llvm-release-keys.asc'
    $configuredKeys = if ($ReleaseKeysPath) { $ReleaseKeysPath } elseif ($env:LLVMUP_RELEASE_KEYS_FILE) { $env:LLVMUP_RELEASE_KEYS_FILE } else { $null }
    if ($configuredKeys) {
        if (-not (Test-Path -LiteralPath $configuredKeys -PathType Leaf)) {
            throw "LLVM release keys file does not exist: $configuredKeys"
        }
        Copy-Item -LiteralPath $configuredKeys -Destination $keysPath -Force
    } else {
        try {
            Download-File -Url 'https://releases.llvm.org/release-keys.asc' -OutPath $keysPath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries | Out-Null
        } catch {
            $script:VerificationGpg = 'unavailable'
            Write-WarningLog "Could not obtain the official LLVM release keys; trying another verifier."
            return
        }
    }

    $gpgHome = Join-Path $TempPath 'gnupg'
    New-Item -ItemType Directory -Path $gpgHome -Force | Out-Null
    $importOutput = & $gpg.Source --batch --homedir $gpgHome --import $keysPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $script:VerificationGpg = 'unavailable'
        Write-WarningLog "Could not import the official LLVM release keys into the isolated keyring."
        return
    }

    $verifyOutput = & $gpg.Source --batch --homedir $gpgHome --status-fd 1 --verify $signaturePath $ArtifactPath 2>&1
    $gpgExit = $LASTEXITCODE
    $statusText = ($verifyOutput | Out-String)
    if ($gpgExit -eq 0 -and $statusText -match '\[GNUPG:\]\s+VALIDSIG\s+([0-9A-Fa-f]+)') {
        $script:VerificationGpg = 'valid'
        $script:VerificationGpgFingerprint = $matches[1].ToUpperInvariant()
        Add-LlvmVerificationMethod 'gpg'
        Write-InfoLog "GPG signature verified with LLVM release key $($script:VerificationGpgFingerprint)"
        return
    }
    if ($statusText -match '\[GNUPG:\]\s+NO_PUBKEY\s+') {
        $script:VerificationGpg = 'unavailable'
        Write-WarningLog 'The signature key is not present in the official LLVM release key set; trying another verifier.'
        return
    }

    $script:VerificationGpg = 'invalid'
    throw "LLVM GPG signature validation failed for $(Split-Path $ArtifactPath -Leaf)"
}

function Invoke-LlvmAttestationVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ArtifactPath,
        [Parameter(Mandatory = $true)] [object]$AttestationAsset,
        [Parameter(Mandatory = $true)] [string]$TempPath
    )

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        $script:VerificationAttestation = 'unavailable'
        Write-WarningLog "A GitHub attestation is available, but 'gh' is not installed; trying another verifier."
        return
    }
    & $gh.Source attestation verify --help *> $null
    if ($LASTEXITCODE -ne 0) {
        $script:VerificationAttestation = 'unavailable'
        Write-WarningLog "The installed 'gh' does not support attestation verification; trying another verifier."
        return
    }

    $bundlePath = Join-Path $TempPath $AttestationAsset.name
    try {
        Download-File -Url $AttestationAsset.browser_download_url -OutPath $bundlePath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries | Out-Null
    } catch {
        $script:VerificationAttestation = 'unavailable'
        Write-WarningLog "Could not download the GitHub attestation bundle: $($_.Exception.Message)"
        return
    }

    if (-not $env:GH_TOKEN -and $env:GITHUB_TOKEN) { $env:GH_TOKEN = $env:GITHUB_TOKEN }
    $verifyOutput = & $gh.Source attestation verify $ArtifactPath --repo llvm/llvm-project --bundle $bundlePath 2>&1
    if ($LASTEXITCODE -eq 0) {
        $script:VerificationAttestation = 'valid'
        Add-LlvmVerificationMethod 'sigstore'
        Write-InfoLog 'GitHub/Sigstore attestation verified for llvm/llvm-project'
        return
    }

    $script:VerificationAttestation = 'invalid'
    $detail = ($verifyOutput | Select-Object -First 5) -join [Environment]::NewLine
    throw "GitHub/Sigstore attestation validation failed for $(Split-Path $ArtifactPath -Leaf). $detail"
}

function Invoke-LlvmReleaseVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ArtifactPath,
        [Parameter(Mandatory = $true)] [object]$SelectedAsset,
        [Parameter(Mandatory = $true)] [string]$TempPath,
        [Parameter(Mandatory = $true)] [ValidateSet('warn', 'strict', 'skip')] [string]$Policy
    )

    $script:VerificationChecksum = 'not-provided'
    $script:VerificationGpg = if ($SelectedAsset.SigFile) { 'unavailable' } else { 'not-provided' }
    $script:VerificationAttestation = if ($SelectedAsset.JsonlFile) { 'unavailable' } else { 'not-provided' }
    $script:VerificationMethods = @()
    $script:VerificationGpgFingerprint = ''

    if ($Policy -eq 'skip') {
        $script:VerificationChecksum = 'skipped'
        $script:VerificationGpg = 'skipped'
        $script:VerificationAttestation = 'skipped'
        $script:VerificationMethods = @('skipped')
        Write-WarningLog 'Release verification was explicitly skipped.'
        return
    }

    if ($SelectedAsset.Digest) {
        $expected = $SelectedAsset.Digest.ToLowerInvariant() -replace '^sha256:', ''
        $actual = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            $script:VerificationChecksum = 'invalid'
            throw "SHA256 digest mismatch. Expected: $expected, Actual: $actual"
        }
        $script:VerificationChecksum = 'valid'
        Write-InfoLog 'SHA256 asset.digest matches the downloaded file.'
    } elseif ($SelectedAsset.ChecksumFile) {
        $checksumPath = Join-Path $TempPath $SelectedAsset.ChecksumFile.name
        try {
            Download-File -Url $SelectedAsset.ChecksumFile.browser_download_url -OutPath $checksumPath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries | Out-Null
            $match = [regex]::Match((Get-Content -LiteralPath $checksumPath -Raw), '(?i)[0-9a-f]{64}')
            if (-not $match.Success) {
                $script:VerificationChecksum = 'invalid'
                throw 'The advertised checksum file does not contain a SHA256 digest.'
            }
            $actual = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $match.Value.ToLowerInvariant()) {
                $script:VerificationChecksum = 'invalid'
                throw "SHA256 checksum mismatch. Expected: $($match.Value), Actual: $actual"
            }
            $script:VerificationChecksum = 'valid'
        } catch {
            if ($script:VerificationChecksum -eq 'invalid') { throw }
            $script:VerificationChecksum = 'unavailable'
            Write-WarningLog "Could not use the advertised checksum file: $($_.Exception.Message)"
        }
    }

    if ($SelectedAsset.SigFile) {
        Invoke-LlvmGpgVerification -ArtifactPath $ArtifactPath -SignatureAsset $SelectedAsset.SigFile -TempPath $TempPath
    }
    if ($SelectedAsset.JsonlFile) {
        Invoke-LlvmAttestationVerification -ArtifactPath $ArtifactPath -AttestationAsset $SelectedAsset.JsonlFile -TempPath $TempPath
    }

    if ($script:VerificationGpg -ne 'valid' -and $script:VerificationAttestation -ne 'valid') {
        if ($Policy -eq 'strict') {
            throw 'Strict verification requires a valid LLVM GPG signature or llvm/llvm-project Sigstore attestation.'
        }
        Write-WarningLog 'The asset integrity may be checked, but its LLVM origin was not cryptographically authenticated.'
        if ($script:VerificationMethods.Count -eq 0) {
            $script:VerificationMethods = if ($script:VerificationChecksum -eq 'valid') { @('checksum-only') } else { @('unverified') }
        }
    }
    Write-InfoLog "Verification summary: checksum=$script:VerificationChecksum, gpg=$script:VerificationGpg, sigstore=$script:VerificationAttestation"
}

function Write-LlvmVerificationMarker {
    [CmdletBinding()]
    param(
        [string]$TargetPath, [string]$Version, [object]$SelectedAsset, [string]$Policy
    )
    $marker = [ordered]@{
        schema = 1; version = $Version; asset_name = $SelectedAsset.Name
        asset_digest = if ($SelectedAsset.Digest) { [string]$SelectedAsset.Digest } else { '' }
        policy = $Policy; checksum = $script:VerificationChecksum
        gpg = $script:VerificationGpg; attestation = $script:VerificationAttestation
        methods = ($script:VerificationMethods -join '+')
        gpg_fingerprint = $script:VerificationGpgFingerprint
    }
    $marker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TargetPath '.llvmup-verification.json') -Encoding UTF8
}

function Test-LlvmVerificationMarker {
    [CmdletBinding()]
    param([string]$TargetPath, [string]$Version, [string]$Digest, [string]$Policy)

    $path = Join-Path $TargetPath '.llvmup-verification.json'
    $valid = $false
    $marker = $null
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $marker = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $valid = $marker.schema -eq 1 -and $marker.version -eq $Version -and
                (-not $Digest -or $marker.asset_digest -eq $Digest)
        }
    } catch { $valid = $false }

    if (-not $valid) {
        if ($Policy -eq 'strict') { throw 'Strict verification cannot trust the existing toolchain: its verification marker is missing or incompatible.' }
        Write-WarningLog 'Existing toolchain has no compatible verification marker.'
        $script:VerificationMethods = @('unverified')
        return $false
    }
    if ($Policy -eq 'strict' -and $marker.gpg -ne 'valid' -and $marker.attestation -ne 'valid') {
        throw 'Strict verification cannot trust the existing toolchain: no authenticated origin is recorded.'
    }
    $script:VerificationMethods = @([string]$marker.methods)
    return $true
}

function Install-PrebuiltLlvm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$SelectedAsset,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string]$CustomName,
        [switch]$Force,
        [Parameter(Mandatory = $true)]
        [ValidateSet('warn', 'strict', 'skip')]
        [string]$Policy
    )

    $installName = if ($CustomName) { $CustomName } else { $Version }
    $installPath = Join-Path $script:TOOLCHAINS_DIR $installName

    # Check if already installed
    if ((Test-Path $installPath) -and -not $Force) {
        if (-not (Test-LlvmToolchainPath -Path $installPath)) {
            throw "Incomplete LLVM installation already exists at $installPath"
        }
        Test-LlvmVerificationMarker -TargetPath $installPath -Version $Version -Digest $SelectedAsset.Digest -Policy $Policy | Out-Null
        Write-WarningLog "LLVM $installName is already installed at $installPath"
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
        Download-File -Url $SelectedAsset.Url -OutPath $downloadPath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries | Out-Null
        Invoke-LlvmReleaseVerification -ArtifactPath $downloadPath -SelectedAsset $SelectedAsset -TempPath $tempDir -Policy $Policy

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
        if (-not (Test-LlvmToolchainPath -Path $installPath)) {
            throw "Installation verification failed: clang and clang++ are not usable"
        }

        Write-LlvmVerificationMarker -TargetPath $installPath -Version $Version -SelectedAsset $SelectedAsset -Policy $Policy

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
  -VerifyPolicy <mode> Verification policy: Warn, Strict, or Skip
  -SkipVerify          Compatibility alias for -VerifyPolicy Skip
  -ReleaseKeysPath     Local LLVM release-keys.asc for GPG/offline use
  -ArchiveOnly         Prefer archive over installer (Windows)
  -ResolveOnly         Resolve the stable release and asset without installing
  -OutputFormat        Text or Json output for -ResolveOnly
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

try {
    $resolvedPolicy = Resolve-LlvmVerificationPolicy -RequestedPolicy $VerifyPolicy
    if ($resolvedPolicy -notin @('warn', 'strict', 'skip')) {
        throw "Invalid verification policy: $resolvedPolicy"
    }

    # Get available releases
    Write-InfoLog "🚀 LLVM Prebuilt Installation Manager"
    $releases = Get-LlvmReleases -TimeoutSec $TimeoutSec

    if (-not $releases -or $releases.Count -eq 0) {
        throw "No releases found"
    }

    # Select version if not provided
    if (-not $Version -and $ResolveOnly) {
        $Version = 'latest'
    } elseif (-not $Version) {
        $stableReleases = Get-StableLlvmReleases -Releases $releases
        Write-InfoLog "Available versions:"
        for ($i = 0; $i -lt [Math]::Min($stableReleases.Count, 10); $i++) {
            $release = $stableReleases[$i]
            $installPath = Join-Path $script:TOOLCHAINS_DIR $release.tag_name
            $installed = if (Test-Path $installPath) { " [INSTALLED]" } else { "" }
            Write-Host "  $($i + 1)) $($release.tag_name)$installed"
        }

        if ($stableReleases.Count -gt 10) {
            Write-Host "  ... and $($stableReleases.Count - 10) more versions"
        }

        $selection = Read-Host "Select version (1-$([Math]::Min($releases.Count, 10))) or enter tag name"

        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $stableReleases.Count) {
                $Version = $stableReleases[$index].tag_name
            } else {
                throw "Invalid selection"
            }
        } else {
            $Version = $selection
        }
    }

    $selectedRelease = Resolve-LlvmRemoteRelease -Releases $releases -Expression $Version
    $Version = $selectedRelease.tag_name

    Write-InfoLog "Selected version: $Version"
    Write-VerboseLog "Release assets: $($selectedRelease.assets.Count)"

    # Select appropriate asset
    $selectedAsset = Select-LlvmAssetForPlatform -Assets $selectedRelease.assets -Platform $Platform -Architecture $Arch -PreferInstaller:(-not $ArchiveOnly) -ArchiveOnly:$ArchiveOnly

    if (-not $selectedAsset) {
        throw "No suitable prebuilt asset found for $Platform $Arch"
    }

    Write-InfoLog "Selected asset: $($selectedAsset.Name)"
    Write-InfoLog "Size: $([Math]::Round($selectedAsset.Size / 1MB, 2)) MB"

    if ($ResolveOnly) {
        $metadata = [ordered]@{
            version = $Version
            asset_name = $selectedAsset.Name
            asset_url = $selectedAsset.Url
            asset_digest = if ($selectedAsset.Digest) { [string]$selectedAsset.Digest } else { '' }
            asset_id = if ($selectedAsset.Asset.id) { [string]$selectedAsset.Asset.id } else { '' }
            signature_url = if ($selectedAsset.SigFile) { [string]$selectedAsset.SigFile.browser_download_url } else { '' }
            checksum_url = if ($selectedAsset.ChecksumFile) { [string]$selectedAsset.ChecksumFile.browser_download_url } else { '' }
            attestation_url = if ($selectedAsset.JsonlFile) { [string]$selectedAsset.JsonlFile.browser_download_url } else { '' }
            platform = $Platform
            architecture = $Arch
        }
        if ($OutputFormat -eq 'Json') {
            Write-Output ($metadata | ConvertTo-Json -Compress)
        } else {
            Write-Output $Version
        }
        return
    }

    New-Item -ItemType Directory -Path $script:TOOLCHAINS_DIR -Force | Out-Null

    # Install the selected asset
    $installPath = Install-PrebuiltLlvm -SelectedAsset $selectedAsset -Version $Version -CustomName $Name -Force:$Force -Policy $resolvedPolicy

    Write-SuccessLog "Installation completed successfully!"
    Write-InfoLog "📁 Installation path: $installPath"
    Write-InfoLog "🔄 To activate: Import-Module Llvm-Functions-Core; Invoke-LlvmActivate '$Version'"

} catch {
    Write-ErrorLog "Installation failed: $($_.Exception.Message)"
    exit 1
}
