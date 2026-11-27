[CmdletBinding()]
param(
    [string]$Version = '@LLVMUP_VERSION@',
    [string]$InstallDir,
    [switch]$NoProfile,
    [string]$ProfilePath,
    [switch]$NoPath,
    [switch]$Import,
    [switch]$Quiet,
    # Mirror of the release assets (https, or http for a trusted local mirror) or a local directory
    # holding SHA256SUMS and llvmup-windows.zip. Defaults to the GitHub release of -Version.
    [string]$BaseUrl = $env:LLVMUP_BOOTSTRAP_BASE_URL,
    [string]$PackageDir = ''
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$') { throw 'Use a release bootstrap or supply -Version vX.Y.Z' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-bootstrap-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$oldProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
    [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
    if ($PackageDir) {
        if (-not $Quiet) { Write-Host "Reading LLVMUP $Version package from $PackageDir" }
        foreach ($name in @('SHA256SUMS', 'llvmup-windows.zip')) {
            Copy-Item -LiteralPath (Join-Path $PackageDir $name) -Destination (Join-Path $work $name) -ErrorAction Stop
        }
    } else {
        if (-not $Quiet) { Write-Host "Downloading LLVMUP $Version package" }
        $base = if ($BaseUrl) { $BaseUrl.TrimEnd('/') } else { "https://github.com/Fabio3rs/llvmup/releases/download/$Version" }
        if ($base -notmatch '^https?://') { throw "Unsupported bootstrap URL '$base' (use https://, http:// for a local mirror, or -PackageDir)" }
        if ($base -match '^http://') { Write-Warning "Downloading over plain HTTP from $base; the checksum only detects corruption, not tampering by the mirror." }
        foreach ($name in @('SHA256SUMS', 'llvmup-windows.zip')) {
            Invoke-WebRequest -Uri "$base/$name" -OutFile (Join-Path $work $name) -UseBasicParsing -TimeoutSec 120 -MaximumRedirection 5
        }
    }
    $lines = @(Get-Content -LiteralPath (Join-Path $work 'SHA256SUMS') | Where-Object { $_ -match '^[a-fA-F0-9]{64}  llvmup-windows\.zip$' })
    if ($lines.Count -ne 1) { throw 'Missing or invalid package checksum' }
    $archive = Join-Path $work 'llvmup-windows.zip'
    if (-not $Quiet) { Write-Host 'Verifying SHA-256 checksum' }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne ($lines[0] -split ' ')[0]) { throw 'Package checksum mismatch' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notmatch '^llvmup/([A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+$' -or $entry.FullName -match '/\.\.?(/|$)' -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -notin @(0, 0x8000)) { throw 'Unsafe archive entry' }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $work)
    if ((Get-Content -LiteralPath (Join-Path $work 'llvmup/VERSION') -Raw).Trim() -ne $Version) { throw 'Package version mismatch' }
    $options = @{ NoProfile = $NoProfile; NoPath = $NoPath; Import = $Import; Quiet = $Quiet }
    if ($InstallDir) { $options.InstallDir = $InstallDir }
    if ($ProfilePath) { $options.ProfilePath = $ProfilePath }
    & (Join-Path $work 'llvmup/packaging/Install-Llvmup.ps1') @options
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    Remove-Item -LiteralPath $work -Recurse -Force
}
