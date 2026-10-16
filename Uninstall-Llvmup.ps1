[CmdletBinding()]
param([switch]$NoProfile, [string]$ProfilePath = $PROFILE.CurrentUserAllHosts)
$ErrorActionPreference = 'Stop'
if ($ProfilePath) { $ProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath) }
$manifest = Join-Path $PSScriptRoot 'llvmup-files.tsv'
if (-not (Test-Path -LiteralPath $manifest)) { throw 'Run the installed Uninstall-Llvmup.ps1, not the checkout copy.' }
$support = Join-Path $PSScriptRoot 'libexec'
if (Test-Path -LiteralPath $support) {
    if ((Get-Item -LiteralPath $support -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe libexec directory' }
}
$names = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    $parts = $line -split '\s+'
    if ($parts[0] -notin @('common', 'powershell')) { continue }
    if ($parts.Count -ne 3 -or $parts[2] -notmatch '^(libexec/)?[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid runtime manifest' }
    $names += $parts[2]
}
if (-not $NoProfile -and $ProfilePath -and (Test-Path -LiteralPath $ProfilePath)) {
    $text = [IO.File]::ReadAllText($ProfilePath)
    $module = (Join-Path $PSScriptRoot 'Llvm-Functions.psm1').Replace("'", "''")
    $pattern = '(?m)^# LLVMUP module - Start\r?\n' + [regex]::Escape("Import-Module '$module' -Force") + '\r?\n# LLVMUP module - End(?:\r?\n|$)'
    $updated = [regex]::Replace($text, $pattern, '')
    if ($updated -ne $text) {
        Copy-Item -LiteralPath $ProfilePath -Destination ($ProfilePath + '.llvmup-backup') -Force
        [IO.File]::WriteAllText($ProfilePath, $updated, [Text.UTF8Encoding]::new($true))
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
