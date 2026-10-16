# Installs LLVMUP itself. Install-Llvm.ps1 continues to manage LLVM toolchains.
[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:LLVMUP_INSTALL_DIR) { $env:LLVMUP_INSTALL_DIR } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'llvmup' } else { Join-Path $HOME '.local/share/llvmup' }),
    [switch]$NoProfile,
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $PSScriptRoot 'runtime-files.tsv'
$InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
if ($ProfilePath) { $ProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath) }
$files = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match '^\s*(#|$)') { continue }
    $parts = $line -split '\s+'
    if ($parts[0] -notin @('common', 'powershell')) { continue }
    if ($parts.Count -ne 3 -or $parts[2] -notmatch '^(libexec/)?[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid runtime manifest' }
    $source = Join-Path $root $parts[2]
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing runtime file: $source" }
    $files += @{ Source = $source; Name = $parts[2] }
}
$files += @{ Source = $manifest; Name = 'llvmup-files.tsv' }
if (Test-Path -LiteralPath (Join-Path $root 'VERSION')) { $files += @{ Source = (Join-Path $root 'VERSION'); Name = 'llvmup-version' } }
# Refuse directory links, including ancestor junctions, rather than follow them
# during replacement or rollback.
$ancestor = $InstallDir
while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unsafe installation directory: $ancestor" }
    }
    $ancestor = Split-Path $ancestor -Parent
}
$support = Join-Path $InstallDir 'libexec'
if (Test-Path -LiteralPath $support) {
    $item = Get-Item -LiteralPath $support -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe libexec directory' }
}
foreach ($file in $files) {
    $target = Join-Path $InstallDir $file.Name
    if (Test-Path -LiteralPath $target) {
        $item = Get-Item -LiteralPath $target -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing non-regular destination: $target" }
    }
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-install-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$null = New-Item -ItemType Directory -Path (Join-Path $work 'libexec')
$touched = @()
$committed = $false
$lock = $null
try {
    foreach ($file in $files) { Copy-Item -LiteralPath $file.Source -Destination (Join-Path $work $file.Name) }
    $null = New-Item -ItemType Directory -Path $InstallDir -Force
    $null = New-Item -ItemType Directory -Path $support -Force
    $lockPath = Join-Path $InstallDir '.llvmup-install.lock'
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    foreach ($file in $files) {
        $target = Join-Path $InstallDir $file.Name
        $backup = Join-Path $work ($file.Name + '.backup')
        $exists = Test-Path -LiteralPath $target
        if ($exists) { Copy-Item -LiteralPath $target -Destination $backup }
        $touched += @{ Target = $target; Backup = $backup; Existed = $exists }
        Copy-Item -LiteralPath (Join-Path $work $file.Name) -Destination $target -Force
    }
    $committed = $true
} finally {
    $recoveryFailed = $false
    if (-not $committed) {
        foreach ($entry in $touched) {
            try {
                if ($entry.Existed) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force }
                elseif (Test-Path -LiteralPath $entry.Target) { Remove-Item -LiteralPath $entry.Target -Force }
            } catch { $recoveryFailed = $true; Write-Warning "Recovery failed for $($entry.Target); backups retained at $work" }
        }
    }
    if ($lock) { $lock.Dispose(); Remove-Item -LiteralPath $lockPath -Force }
    if (-not $recoveryFailed) { Remove-Item -LiteralPath $work -Recurse -Force }
}
$module = (Join-Path $InstallDir 'Llvm-Functions.psm1').Replace("'", "''")
$import = "Import-Module '$module' -Force"
if (-not $NoProfile) {
    if (-not $ProfilePath) { throw 'No profile path is available; use -NoProfile and import the module manually.' }
    $text = if (Test-Path -LiteralPath $ProfilePath) { [IO.File]::ReadAllText($ProfilePath) } else { '' }
    $pattern = '(?ms)^# LLVMUP module - Start\r?\n.*?^# LLVMUP module - End(?:\r?\n|$)'
    $block = "# LLVMUP module - Start`n$import`n# LLVMUP module - End`n"
    if ($text -match $pattern) { $updated = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }) }
    else { $updated = $text + "`n" + $block }
    if ($updated -ne $text) {
        $null = New-Item -ItemType Directory -Path (Split-Path $ProfilePath -Parent) -Force
        if (Test-Path -LiteralPath $ProfilePath) { Copy-Item -LiteralPath $ProfilePath -Destination ($ProfilePath + '.llvmup-backup') -Force }
        [IO.File]::WriteAllText($ProfilePath, $updated, [Text.UTF8Encoding]::new($true))
    }
}
Write-Host "LLVMUP installed in $InstallDir. To load it in this session:"
Write-Host $import
Write-Host "Uninstall with: & '$(Join-Path $InstallDir 'Uninstall-Llvmup.ps1')'"
