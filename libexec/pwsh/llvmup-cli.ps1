# Non-interactive CLI entrypoint for llvmup on Windows (invoked by llvmup.cmd).
#
# This runs in a child process, so it can never change the caller's environment. Output is streamed
# as it is produced (never buffered), and the process exit code reflects the command result:
#   - run / +toolchain / shell: the exit code of the executed program
#   - everything else: 0 on success, 1 on failure
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
if ($first -in @('activate', 'deactivate', 'use', 'pick')) {
    [Console]::Error.WriteLine("[ERROR] 'llvmup $first' cannot modify the parent shell when invoked via llvmup.cmd (child process).")
    [Console]::Error.WriteLine("[INFO] To modify the current PowerShell session, import the module first:")
    [Console]::Error.WriteLine("       Import-Module '$modulePath'")
    [Console]::Error.WriteLine("[INFO] For one-off execution without modifying the shell: llvmup run <toolchain> -- <cmd>  (or llvmup +<toolchain> -- <cmd>)")
    [Console]::Error.WriteLine("[INFO] For a subshell with the toolchain active: llvmup shell <toolchain>")
    [Console]::Error.WriteLine("[INFO] In cmd.exe scripts: for /f ""delims="" %i in ('llvmup env <toolchain> --format cmd') do %i")
    exit 2
}

$runsProgram = ($first -in @('run', 'shell')) -or ($first.StartsWith('+') -and $first.Length -gt 1)
$global:LASTEXITCODE = 0
$script:failed = $false

# Stream every object as soon as it is emitted; the facade's [bool] status values are consumed here.
llvmup @tokens | ForEach-Object {
    if ($_ -is [bool]) {
        if (-not $_) { $script:failed = $true }
    } elseif ($null -ne $_) {
        $_
    }
}

$cmdExit = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
if ($runsProgram) {
    if ($script:failed -and $cmdExit -eq 0) { exit 1 }
    exit $cmdExit
}
if ($script:failed) { exit 1 }
if ($cmdExit -ne 0) { exit $cmdExit }
exit 0
