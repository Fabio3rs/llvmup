# Child-process execution ('run', '+toolchain', and 'shell') without mutating parent shell or using shims.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}
$script:EnvModule = Join-Path $PSScriptRoot 'Llvm-Environment.psm1'
if ((Test-Path -LiteralPath $script:EnvModule) -and -not (Get-Module -Name 'Llvm-Environment')) {
    Import-Module $script:EnvModule -DisableNameChecking
}

function Resolve-LlvmChildExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)]$Delta
    )

    $manifest = $Delta.manifest
    $root = [string]$manifest.root_path
    $tools = $manifest.tools
    $base = [IO.Path]::GetFileNameWithoutExtension($CommandName).ToLowerInvariant()

    # Map logical aliases ('cc', 'c++', 'cxx') via active Delta; exact binary names look up tools/PATH directly.
    if (-not $CommandName.Contains('/') -and -not $CommandName.Contains('\')) {
        $mapped = switch ($base) {
            'cc' { $Delta.set['CC'] }
            'c++' { $Delta.set['CXX'] }
            'cxx' { $Delta.set['CXX'] }
            'ld' { $Delta.set['LD'] }
            default { $null }
        }
        if ($mapped -and (Test-Path -LiteralPath $mapped -PathType Leaf)) {
            return $mapped
        }

        # With a target selected, a known tool resolves to the distribution's target wrapper
        # (llvm-mingw: clang -> x86_64-w64-mingw32-clang, which sets the target and sysroot).
        if ($Delta.target -and $tools -and $tools.target_wrappers) {
            $tw = $tools.target_wrappers
            $wrap = if ($tw -is [System.Collections.IDictionary]) { if ($tw.Contains($Delta.target)) { $tw[$Delta.target] } } elseif ($tw.PSObject.Properties[$Delta.target]) { $tw.($Delta.target) }
            if ($wrap) {
                foreach ($key in @($CommandName, $base)) {
                    $val = if ($wrap -is [System.Collections.IDictionary]) { if ($wrap.Contains($key)) { $wrap[$key] } } elseif ($wrap.PSObject.Properties[$key]) { $wrap.$key }
                    if ($val -is [string] -and $val) {
                        $cand = Join-Path $root ($val.Replace('/', [IO.Path]::DirectorySeparatorChar))
                        if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
                    }
                }
            }
        }

        if ($tools) {
            foreach ($key in @($CommandName, $base)) {
                if ($tools -is [System.Collections.IDictionary] -and $tools.Contains($key)) {
                    $val = $tools[$key]
                    if ($val -is [string] -and $val) {
                        $cand = Join-Path $root ($val.Replace('/', [IO.Path]::DirectorySeparatorChar))
                        if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
                    }
                } elseif ($tools.PSObject -and $tools.PSObject.Properties[$key]) {
                    $val = $tools.$key
                    if ($val -is [string] -and $val) {
                        $cand = Join-Path $root ($val.Replace('/', [IO.Path]::DirectorySeparatorChar))
                        if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
                    }
                }
            }
        }
    }

    # Fall back to searching the augmented PATH (bin/ first, then existing PATH)
    $sep = [string][IO.Path]::PathSeparator
    $searchDirs = @($Delta.prepend_path) + @($env:PATH -split [regex]::Escape($sep) | Where-Object { $_ })
    $exts = if (Test-LlvmIsWindows) {
        if ([IO.Path]::HasExtension($CommandName)) { @('') } else { @('.exe', '.cmd', '.bat', '') }
    } else { @('') }

    if ([IO.Path]::IsPathRooted($CommandName) -or $CommandName.Contains('/') -or $CommandName.Contains('\')) {
        if (Test-Path -LiteralPath $CommandName -PathType Leaf) {
            return (Resolve-Path -LiteralPath $CommandName).Path
        }
    }

    foreach ($dir in $searchDirs) {
        foreach ($ext in $exts) {
            $cand = Join-Path $dir "$CommandName$ext"
            if (Test-Path -LiteralPath $cand -PathType Leaf) {
                return $cand
            }
        }
    }

    throw "Executable '$CommandName' was not found in toolchain '$($manifest.install_name)' or PATH."
}

function Format-LlvmWindowsArg {
    param([string]$Arg)
    if ($null -eq $Arg -or $Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('"')
    $bsCount = 0
    for ($i = 0; $i -lt $Arg.Length; $i++) {
        $ch = $Arg[$i]
        if ($ch -eq '\') {
            $bsCount++
        } elseif ($ch -eq '"') {
            $null = $sb.Append('\', $bsCount * 2 + 1)
            $null = $sb.Append('"')
            $bsCount = 0
        } else {
            if ($bsCount -gt 0) {
                $null = $sb.Append('\', $bsCount)
                $bsCount = 0
            }
            $null = $sb.Append($ch)
        }
    }
    if ($bsCount -gt 0) {
        $null = $sb.Append('\', $bsCount * 2)
    }
    $null = $sb.Append('"')
    return $sb.ToString()
}

function Invoke-LlvmProcessWithDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Delta,
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @(),
        [switch]$InheritShellOverride
    )

    $resolvedExe = Resolve-LlvmChildExecutable -CommandName $Executable -Delta $Delta
    $keysToSave = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $keysToSave.Add('PATH')
    foreach ($u in $Delta.unset) { $null = $keysToSave.Add([string]$u) }
    foreach ($k in $Delta.set.Keys) { $null = $keysToSave.Add([string]$k) }
    if ($InheritShellOverride) { $null = $keysToSave.Add('LLVMUP_SESSION_OVERRIDE') }

    $saved = @{}
    foreach ($k in $keysToSave) {
        $item = Get-Item -LiteralPath "Env:$k" -ErrorAction SilentlyContinue
        $saved[$k] = if ($item) { @{ Present = $true; Value = $item.Value } } else { @{ Present = $false; Value = $null } }
    }

    try {
        $sep = [string][IO.Path]::PathSeparator
        $curPath = $env:PATH
        if ($Delta.prepend_path.Count -gt 0) {
            $prefix = $Delta.prepend_path -join $sep
            $env:PATH = if ($curPath) { "$prefix$sep$curPath" } else { $prefix }
        }
        foreach ($u in $Delta.unset) {
            Remove-Item -LiteralPath "Env:$u" -ErrorAction SilentlyContinue
        }
        foreach ($k in $Delta.set.Keys) {
            Set-Item -LiteralPath "Env:$k" -Value ([string]$Delta.set[$k])
        }
        if ($InheritShellOverride) {
            $env:LLVMUP_SESSION_OVERRIDE = '1'
        }

        $global:LASTEXITCODE = 0
        & $resolvedExe @Arguments
        $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        $global:LASTEXITCODE = $code
    } finally {
        foreach ($kv in $saved.GetEnumerator()) {
            if ($kv.Value.Present) {
                Set-Item -LiteralPath "Env:$($kv.Key)" -Value $kv.Value.Value
            } else {
                Remove-Item -LiteralPath "Env:$($kv.Key)" -ErrorAction SilentlyContinue
            }
        }
    }
    $global:LASTEXITCODE = $code
}

Export-ModuleMember -Function @(
    'Resolve-LlvmChildExecutable',
    'Invoke-LlvmProcessWithDelta'
)
