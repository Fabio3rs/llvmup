# Non-interactive CLI entrypoint for llvmup on Windows (invoked by llvmup.cmd).
$ErrorActionPreference = 'Continue'

$rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $rootDir 'Llvm-Functions.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    [Console]::Error.WriteLine("[ERROR] Llvm-Functions.psm1 was not found at $modulePath")
    exit 1
}

Import-Module $modulePath -Force -DisableNameChecking -WarningAction SilentlyContinue

$tokens = @($args | ForEach-Object { [string]$_ })
$first = if ($tokens.Count -gt 0) { $tokens[0].ToLowerInvariant() } else { '' }
if ($first -in @('activate', 'deactivate', 'use')) {
    [Console]::Error.WriteLine("[ERROR] 'llvmup $first' cannot modify the parent shell when invoked via llvmup.cmd (child process).")
    [Console]::Error.WriteLine("[INFO] To modify the current PowerShell session, import the module first:")
    [Console]::Error.WriteLine("       Import-Module '$modulePath' -Force")
    [Console]::Error.WriteLine("[INFO] For one-off execution without modifying the shell, use: llvmup run <toolchain> -- <cmd> (or llvmup +<toolchain> -- <cmd>)")
    [Console]::Error.WriteLine("[INFO] In PowerShell scripts/CI, you can also run: Invoke-Expression ((llvmup env <version>) -join `"`n`")")
    exit 1
}

$global:LASTEXITCODE = 0
$result = @(llvmup @tokens)
$cmdExit = if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { [int]$LASTEXITCODE } else { 0 }

$failed = $false
$outputItems = @()
foreach ($item in $result) {
    if ($item -is [bool]) {
        if (-not $item) { $failed = $true }
    } elseif ($null -ne $item) {
        $outputItems += $item
    }
}

foreach ($item in $outputItems) {
    Write-Output $item
}

if ($cmdExit -ne 0) { exit $cmdExit }
if ($failed) { exit 1 }
exit 0
