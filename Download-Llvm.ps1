# Download-Llvm.ps1: Enhanced LLVM prebuilt download and installation manager
# Requirements: PowerShell v5 or later
# Based on llvm-prebuilt bash implementation
# Usage:
#   .\Download-Llvm.ps1 [-Version <expression>] [-Platform <platform>] [-Arch <arch>] [-VerifyPolicy Warn|Strict|Skip]

param (
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$Provider = "",

    [Parameter(Mandatory = $false)]
    [string]$Release = "",

    [Parameter(Mandatory = $false)]
    [string]$Crt = "",

    [Parameter(Mandatory = $false)]
    [string]$Threads = "",

    [Parameter(Mandatory = $false)]
    [string]$Target = "",

    [Parameter(Mandatory = $false)]
    [string]$Compiler = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("auto", "7z", "tar", "zip", "msi", "python")]
    [string]$Extractor = "auto",

    [switch]$NoCache,

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

    [ValidateSet("", "minimal", "compiler", "full", "custom")]
    [string]$Profile,
    [string[]]$Component = @(),
    [switch]$Strip,
    [switch]$VerboseMode,

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
    [switch]$ListOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Text", "Json")]
    [string]$OutputFormat = "Text",

    [Parameter(Mandatory = $false)]
    [switch]$Quiet,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

if (-not ($ResolveOnly -or $ListOnly -or $Help)) {
    Import-Module (Join-Path $PSScriptRoot 'libexec/Llvm-Selection.psm1') -DisableNameChecking
    $selectionConfig = Get-LlvmSelectionConfig
    if (-not $PSBoundParameters.ContainsKey('Profile')) { $Profile = $selectionConfig.Profile }
    if (-not $PSBoundParameters.ContainsKey('Component')) { $Component = $selectionConfig.Components }
}

function Write-InfoLog {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
}

if ($Help) {
    Write-Host @"
LLVM Prebuilt Download and Installation Manager

Usage: Download-Llvm.ps1 [options] [version]

Options:
  -Profile <name>       minimal, compiler, full, or custom
  -Component <names>    Selected components (Clang is always included)
  -Strip                Strip Linux ELF executables
  -VerboseMode          Report progress and disk usage
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
  -ListOnly            List all stable remote release tags without installing
  -OutputFormat        Text or Json output for -ResolveOnly or -ListOnly
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

try {
    if ($ListOnly) { $Quiet = $true }
    Import-Module (Join-Path $PSScriptRoot 'libexec/pwsh/Llvm-Verifier.psm1') -DisableNameChecking
    $resolvedPolicy = Resolve-LlvmVerifyPolicy -RequestedPolicy $VerifyPolicy -SkipVerify:$SkipVerify

    $installerModule = Join-Path $PSScriptRoot 'libexec/pwsh/Llvm-Installer.psm1'
    $recipesModule = Join-Path $PSScriptRoot 'libexec/pwsh/Llvm-Recipes.psm1'
    $downloaderModule = Join-Path $PSScriptRoot 'libexec/pwsh/Llvm-Downloader.psm1'
    Import-Module $recipesModule -Force -DisableNameChecking
    Import-Module $downloaderModule -Force -DisableNameChecking
    Import-Module $installerModule -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1') -DisableNameChecking

    $effProvider = if ($Provider) { $Provider.ToLowerInvariant() } elseif ($Version -match '^([a-z0-9][a-z0-9-]*?)@') { $matches[1].ToLowerInvariant() } else { 'official' }

    if ($ListOnly) {
        $recipe = Get-LlvmRecipe -Provider $effProvider
        $releases = Invoke-LlvmProviderReleases -Provider $effProvider -ApiUrl $recipe.api_url -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -TestMode:$TestMode
        if (-not $releases -or $releases.Count -eq 0) { throw "No releases found for provider '$effProvider'" }
        $stableTags = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match $recipe.tag_rules.release_tag_pattern } | ForEach-Object { $_.tag_name })
        if ($effProvider -eq 'official') {
            $stableTags = @($stableTags | Sort-Object {
                $value = $_ -replace '^llvmorg-', ''
                try { [version]$value } catch { [version]'0.0.0' }
            } -Descending)
        }
        if ($OutputFormat -eq 'Json') {
            Write-Output (@{ provider = $effProvider; remote_versions = $stableTags } | ConvertTo-Json -Depth 3)
        } else {
            $stableTags | ForEach-Object { Write-Output $_ }
        }
        return
    }

    $targetVersionExpr = if ($Version) { $Version } else { 'latest' }
    if ($ResolveOnly) {
        $resolved = Invoke-LlvmInstallPrebuiltFromRecipe `
            -Selector $targetVersionExpr `
            -Provider $Provider `
            -ReleaseTag $Release `
            -Platform $Platform `
            -Arch $Arch `
            -Crt $Crt `
            -Threads $Threads `
            -Target $Target `
            -Compiler $Compiler `
            -Extractor $Extractor `
            -VerifyPolicy $resolvedPolicy `
            -ArchiveOnly:$ArchiveOnly `
            -TestMode:$TestMode `
            -ResolveOnly `
            -TimeoutSec $TimeoutSec `
            -MaxRetries $MaxRetries `
            -Quiet:$Quiet `
            -VerboseMode:$VerboseMode
        if ($OutputFormat -eq 'Json') {
            Write-Output ($resolved | ConvertTo-Json -Compress)
        } else {
            Write-Output $resolved.version
        }
        return
    }

    # Interactive version selection when no version or release was supplied
    if (-not $Version -and -not $Release) {
        $recipe = Get-LlvmRecipe -Provider $effProvider
        $releases = Invoke-LlvmProviderReleases -Provider $effProvider -ApiUrl $recipe.api_url -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -TestMode:$TestMode
        $stableReleases = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match $recipe.tag_rules.release_tag_pattern })
        Write-InfoLog "Available versions ($effProvider):"
        for ($i = 0; $i -lt [Math]::Min($stableReleases.Count, 10); $i++) {
            $releaseItem = $stableReleases[$i]
            $installPath = Join-Path (Get-LlvmSessionToolchainsPath) $releaseItem.tag_name
            $installed = if (Test-Path $installPath) { " [INSTALLED]" } else { "" }
            Write-Host "  $($i + 1)) $($releaseItem.tag_name)$installed"
        }
        if ($stableReleases.Count -gt 10) {
            Write-Host "  ... and $($stableReleases.Count - 10) more versions"
        }
        $selection = Read-Host "Select version (1-$([Math]::Min($stableReleases.Count, 10))) or enter tag/expression"
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $stableReleases.Count) {
                $Release = $stableReleases[$index].tag_name
                $targetVersionExpr = $Release
            } else {
                throw "Invalid selection"
            }
        } else {
            $targetVersionExpr = $selection
        }
    }

    $installRes = Invoke-LlvmInstallPrebuiltFromRecipe `
        -Selector $targetVersionExpr `
        -Provider $Provider `
        -ReleaseTag $Release `
        -Platform $Platform `
        -Arch $Arch `
        -Crt $Crt `
        -Threads $Threads `
        -Target $Target `
        -Compiler $Compiler `
        -Name $Name `
        -Profile $Profile `
        -Components $Component `
        -Strip:$Strip `
        -Extractor $Extractor `
        -VerifyPolicy $resolvedPolicy `
        -ReleaseKeysPath $ReleaseKeysPath `
        -ArchiveOnly:$ArchiveOnly `
        -Force:$Force `
        -NoCache:$NoCache `
        -TestMode:$TestMode `
        -TimeoutSec $TimeoutSec `
        -MaxRetries $MaxRetries `
        -Quiet:$Quiet `
        -VerboseMode:$VerboseMode

    Write-InfoLog "Installation completed successfully!"
    Write-InfoLog "Installation path: $($installRes.install_path)"
    Write-InfoLog "To activate: llvmup use $($installRes.install_name)"

} catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}
