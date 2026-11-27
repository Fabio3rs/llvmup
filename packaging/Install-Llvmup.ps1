# Installs LLVMUP itself. Install-Llvm.ps1 continues to manage LLVM toolchains.
[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:LLVMUP_INSTALL_DIR) { $env:LLVMUP_INSTALL_DIR } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'llvmup' } else { Join-Path $HOME '.local/share/llvmup' }),
    [switch]$NoProfile,
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
    [switch]$AddToPath,
    [switch]$NoPath,
    [switch]$Import
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $PSScriptRoot 'runtime-files.tsv'
$InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
$explicitProfile = $PSBoundParameters.ContainsKey('ProfilePath')
if ($ProfilePath) { $ProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath) }

$files = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match '^\s*(#|$)') { continue }
    $parts = $line -split '\s+'
    if ($parts[0] -notin @('common', 'powershell')) { continue }
    if ($parts.Count -ne 3 -or $parts[2] -notmatch '^(libexec/([A-Za-z0-9_-]+/)*)?[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid runtime manifest' }
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

$subDirs = @{}
foreach ($file in $files) {
    $relParent = Split-Path $file.Name -Parent
    while ($relParent) {
        $subDirs[$relParent] = $true
        $relParent = Split-Path $relParent -Parent
    }
}
foreach ($subDir in ($subDirs.Keys | Sort-Object)) {
    $targetSub = Join-Path $InstallDir $subDir
    if (Test-Path -LiteralPath $targetSub) {
        $item = Get-Item -LiteralPath $targetSub -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unsafe runtime subdirectory: $targetSub" }
    }
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
$touched = @()
$committed = $false
$lock = $null
try {
    foreach ($file in $files) {
        $workTarget = Join-Path $work $file.Name
        $workParent = Split-Path $workTarget -Parent
        if (-not (Test-Path -LiteralPath $workParent)) {
            $null = New-Item -ItemType Directory -Path $workParent -Force
        }
        Copy-Item -LiteralPath $file.Source -Destination $workTarget
    }
    $null = New-Item -ItemType Directory -Path $InstallDir -Force
    foreach ($subDir in ($subDirs.Keys | Sort-Object)) {
        $null = New-Item -ItemType Directory -Path (Join-Path $InstallDir $subDir) -Force
    }
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

$modulePath = Join-Path $InstallDir 'Llvm-Functions.psm1'
$module = $modulePath.Replace("'", "''")
# -DisableNameChecking: the module exports legacy names (Activate-Llvm, ...) that would otherwise
# print an "unapproved verbs" warning in every new PowerShell session.
$importCmd = "Import-Module '$module' -Force -DisableNameChecking"

$shouldAddToPath = $AddToPath -or (-not $NoProfile -and -not $NoPath -and -not $explicitProfile)
if ($shouldAddToPath) {
    $isWin = ($PSVersionTable.PSVersion.Major -lt 6) -or ($null -ne $IsWindows -and $IsWindows)
    if ($isWin) {
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $entries = @()
        if ($userPath) { $entries = @($userPath -split ';' | Where-Object { $_ }) }
        $already = $false
        foreach ($entry in $entries) {
            if ($entry.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) { $already = $true; break }
        }
        if (-not $already) {
            $newUserPath = (@($InstallDir) + $entries) -join ';'
            [Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
        }
        $procEntries = @($env:PATH -split ';' | Where-Object { $_ })
        if (-not ($procEntries | Where-Object { $_.TrimEnd('\') -ieq $InstallDir.TrimEnd('\') })) {
            $env:PATH = "$InstallDir;$env:PATH"
        }
    }
}

if (-not $NoProfile) {
    if (-not $ProfilePath) { throw 'No profile path is available; use -NoProfile and import the module manually.' }
    $profileTargets = @($ProfilePath)
    if (-not $explicitProfile) {
        $docs = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)
        if ($docs) {
            foreach ($editionDir in @('WindowsPowerShell', 'PowerShell')) {
                $candidateProfile = Join-Path (Join-Path $docs $editionDir) 'profile.ps1'
                if ($profileTargets -notcontains $candidateProfile) {
                    $profileTargets += $candidateProfile
                }
            }
        }
    }
    $pattern = '(?ms)^# LLVMUP module - Start\r?\n.*?^# LLVMUP module - End(?:\r?\n|$)'
    $block = "# LLVMUP module - Start`n$importCmd`n# LLVMUP module - End`n"
    foreach ($targetProfile in $profileTargets) {
        $text = if (Test-Path -LiteralPath $targetProfile) { [IO.File]::ReadAllText($targetProfile) } else { '' }
        if ($text -match $pattern) { $updated = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }) }
        else { $updated = if ($text) { $text.TrimEnd("`r", "`n") + "`n`n" + $block } else { $block } }
        if ($updated -ne $text) {
            $null = New-Item -ItemType Directory -Path (Split-Path $targetProfile -Parent) -Force
            if (Test-Path -LiteralPath $targetProfile) { Copy-Item -LiteralPath $targetProfile -Destination ($targetProfile + '.llvmup-backup') -Force }
            [IO.File]::WriteAllText($targetProfile, $updated, [Text.UTF8Encoding]::new($true))
        }
    }
}

if ($Import) {
    Import-Module $modulePath -Force -Global -DisableNameChecking
}

Write-Host "LLVMUP installed in $InstallDir. To load it in this session:"
Write-Host $importCmd
Write-Host "CLI launcher: $(Join-Path $InstallDir 'llvmup.cmd')"
Write-Host "Uninstall with: & '$(Join-Path $InstallDir 'Uninstall-Llvmup.ps1')'"
