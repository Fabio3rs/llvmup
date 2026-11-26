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

function ConvertFrom-LlvmWin32CommandLine {
    # Splits a command line with the MSVC/CommandLineToArgvW rules used by C programs:
    # 2n backslashes + quote -> n backslashes and a quote toggle; 2n+1 -> n backslashes and a
    # literal quote; "" inside a quoted run is a literal quote.
    param([string]$CommandLine)
    $result = New-Object System.Collections.Generic.List[string]
    $i = 0
    $n = $CommandLine.Length
    while ($i -lt $n) {
        while ($i -lt $n -and ($CommandLine[$i] -eq ' ' -or $CommandLine[$i] -eq "`t")) { $i++ }
        if ($i -ge $n) { break }
        $sb = New-Object System.Text.StringBuilder
        $inQuotes = $false
        while ($i -lt $n) {
            $ch = $CommandLine[$i]
            if (-not $inQuotes -and ($ch -eq ' ' -or $ch -eq "`t")) { break }
            if ($ch -eq '\') {
                $bs = 0
                while ($i -lt $n -and $CommandLine[$i] -eq '\') { $bs++; $i++ }
                if ($i -lt $n -and $CommandLine[$i] -eq '"') {
                    $null = $sb.Append('\', [int][Math]::Floor($bs / 2))
                    if ($bs % 2 -eq 1) { $null = $sb.Append('"'); $i++ }
                } else {
                    $null = $sb.Append('\', $bs)
                }
                continue
            }
            if ($ch -eq '"') {
                if ($inQuotes -and ($i + 1) -lt $n -and $CommandLine[$i + 1] -eq '"') {
                    $null = $sb.Append('"'); $i += 2; continue
                }
                $inQuotes = -not $inQuotes
                $i++
                continue
            }
            $null = $sb.Append($ch)
            $i++
        }
        $result.Add($sb.ToString())
    }
    return , $result.ToArray()
}

# llvmup.cmd passes a sentinel before the user's arguments. PowerShell's -File binder would
# otherwise reinterpret arguments such as "-DCMAKE_TOOLCHAIN_FILE=C:\a b\t.cmake" or "-c:x"
# (splitting them at '=' / ':'), so the original arguments are recovered from the raw command line.
$tokens = @($args | ForEach-Object { [string]$_ })
$rawTokens = ConvertFrom-LlvmWin32CommandLine ([Environment]::CommandLine)
$sentinel = [Array]::IndexOf($rawTokens, '--llvmup-args')
if ($sentinel -ge 0) {
    # @() keeps a single argument as an array (an 'if' expression would unroll it to a string).
    $tokens = @(if ($sentinel + 1 -lt $rawTokens.Count) { $rawTokens[($sentinel + 1)..($rawTokens.Count - 1)] })
}
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
# Errors of llvmup itself are printed as one plain "Error: ..." line instead of PowerShell's
# CategoryInfo/FullyQualifiedErrorId block. Programs started by run/shell write to the console directly.
$emit = {
    if ($_ -is [bool]) {
        if (-not $_) { $script:failed = $true }
    } elseif ($_ -is [System.Management.Automation.ErrorRecord]) {
        $script:failed = $true
        [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    } elseif ($null -ne $_) {
        $_
    }
}
if ($runsProgram) { llvmup @tokens | ForEach-Object $emit } else { llvmup @tokens 2>&1 | ForEach-Object $emit }

$cmdExit = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
if ($runsProgram) {
    if ($script:failed -and $cmdExit -eq 0) { exit 1 }
    exit $cmdExit
}
if ($script:failed) { exit 1 }
if ($cmdExit -ne 0) { exit $cmdExit }
exit 0
