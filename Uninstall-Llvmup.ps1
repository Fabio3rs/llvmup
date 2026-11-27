[CmdletBinding()]
param(
    [switch]$NoProfile,
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
    [switch]$KeepPath
)
$ErrorActionPreference = 'Stop'
$explicitProfile = $PSBoundParameters.ContainsKey('ProfilePath')
if ($ProfilePath) { $ProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath) }
$manifest = Join-Path $PSScriptRoot 'llvmup-files.tsv'
if (-not (Test-Path -LiteralPath $manifest)) { throw 'Run the installed Uninstall-Llvmup.ps1, not the checkout copy.' }

$names = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match '^\s*(#|$)') { continue }
    $parts = $line -split '\s+'
    if ($parts[0] -notin @('common', 'powershell')) { continue }
    if ($parts.Count -ne 3 -or $parts[2] -notmatch '^(libexec/([A-Za-z0-9_-]+/)*)?[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid runtime manifest' }
    $names += $parts[2]
}

foreach ($name in $names) {
    $relParent = Split-Path $name -Parent
    while ($relParent) {
        $subPath = Join-Path $PSScriptRoot $relParent
        if (Test-Path -LiteralPath $subPath) {
            if ((Get-Item -LiteralPath $subPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unsafe runtime directory: $subPath" }
        }
        $relParent = Split-Path $relParent -Parent
    }
}

if (-not $NoProfile -and $ProfilePath) {
    $profileTargets = @($ProfilePath)
    if (-not $explicitProfile) {
        $docs = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)
        if ($docs) {
            foreach ($editionDir in @('WindowsPowerShell', 'PowerShell')) {
                $candidateProfile = Join-Path (Join-Path $docs $editionDir) 'profile.ps1'
                if ($profileTargets -notcontains $candidateProfile) { $profileTargets += $candidateProfile }
            }
        }
    }
    $module = Join-Path $PSScriptRoot 'Llvm-Functions.psm1'
    $moduleItem = Get-Item -LiteralPath $module -ErrorAction SilentlyContinue
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $pattern = "(?m)^# LLVMUP module - Start\r?\nImport-Module '(?<path>(?:[^'\r\n]|'')+)' -Force(?: -DisableNameChecking)?\r?\n# LLVMUP module - End(?:\r?\n|$)"
    foreach ($targetProfile in $profileTargets) {
        if (-not (Test-Path -LiteralPath $targetProfile)) { continue }
        $text = [IO.File]::ReadAllText($targetProfile)
        $updated = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $recordedPath = $match.Groups['path'].Value.Replace("''", "'")
            if ([string]::Equals($recordedPath, $module, $comparison)) { return '' }
            if ($moduleItem -and [IO.Path]::IsPathRooted($recordedPath)) {
                $recordedItem = Get-Item -LiteralPath $recordedPath -ErrorAction SilentlyContinue
                if ($recordedItem -and [string]::Equals($recordedItem.FullName, $moduleItem.FullName, $comparison)) { return '' }
            }
            return $match.Value
        })
        if ($updated -ne $text) {
            Copy-Item -LiteralPath $targetProfile -Destination ($targetProfile + '.llvmup-backup') -Force
            [IO.File]::WriteAllText($targetProfile, $updated, [Text.UTF8Encoding]::new($true))
        }
    }
}

if (-not $KeepPath -and -not $NoProfile -and -not $explicitProfile) {
    $isWin = ($PSVersionTable.PSVersion.Major -lt 6) -or ($null -ne $IsWindows -and $IsWindows)
    if ($isWin) {
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($userPath) {
            $filtered = @($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ine $PSScriptRoot.TrimEnd('\')) })
            $newPath = $filtered -join ';'
            if ($newPath -ne $userPath) {
                [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
            }
        }
    }
}

foreach ($name in ($names + @('llvmup-files.tsv', 'llvmup-version'))) {
    $path = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing non-regular file: $path" }
        Remove-Item -LiteralPath $path -Force
    }
}
Write-Host 'LLVMUP removed. LLVM toolchains and unrelated files were preserved. Open a new shell to unload imported functions.'
