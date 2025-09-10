# Llvm-Completion.psm1 - PowerShell completions for LLVMUP
# Registers argument completers for key commands (Activate-Llvm, Install-Llvm, etc.)

# NOTE: do not import Get-UserHome helper at module import time.
# We will lazily load it inside Resolve-UserHome only if no session-defined Get-UserHome exists.

# Resolve user home, preferring a session/script-defined Get-UserHome (so tests can mock it)
function Resolve-UserHome {
    # If a Get-UserHome function exists, try calling it directly — this respects any session/test
    # overrides (the PS engine will resolve the visible function at call time).
    try {
        $cmds = Get-Command -Name Get-UserHome -CommandType Function -ErrorAction SilentlyContinue -All
        if ($cmds -and $cmds.Count -gt 0) {
            $selected = $cmds[-1]
            try {
                if ($selected.ScriptBlock) { $val = & $selected.ScriptBlock } else { $val = & $selected.Name }
                return $val
            } catch {}
        } else {
            # No session-defined Get-UserHome; attempt to lazy-load our helper module/script
            try {
                $helperPath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
                if (Test-Path $helperPath) { Import-Module $helperPath -Force -ErrorAction SilentlyContinue }
                elseif (Test-Path (Join-Path $PSScriptRoot 'Get-UserHome.ps1')) { . "$PSScriptRoot\Get-UserHome.ps1" }
                # After lazy load, try again to get the function
                $cmds = Get-Command -Name Get-UserHome -CommandType Function -ErrorAction SilentlyContinue -All
                if ($cmds -and $cmds.Count -gt 0) {
                    $selected = $cmds[-1]
                    if ($selected.ScriptBlock) { $val = & $selected.ScriptBlock } else { $val = & $selected.Name }
                    return $val
                }
            } catch {}
        }
    } catch {}

    # Fallback to environment variables
    if ($env:HOME) { return $env:HOME }
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($IsWindows) { return $env:SystemDrive + '\' }
    return '/tmp'
}

# Compatibility shim for environments that lack built-in ArgumentCompleter cmdlets (older hosts)
if (-not (Get-Command Get-ArgumentCompleter -ErrorAction SilentlyContinue)) {
    # Store registrations in module-scoped variable
    if (-not (Get-Variable -Name '__llvm_completers' -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name '__llvm_completers' -Value @() -Scope Script
    }

    function Register-ArgumentCompleter {
        param(
            [Parameter(Mandatory=$true)][string]$CommandName,
            [Parameter(Mandatory=$false)][string]$ParameterName,
            [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock
        )
        $entry = [PSCustomObject]@{
            CommandName = $CommandName
            ParameterName = $ParameterName
            ScriptBlock = $ScriptBlock
        }
        $script:__llvm_completers += $entry
    }

    function Get-ArgumentCompleter {
        param(
            [Parameter(Mandatory=$false)][string]$CommandName
        )
        if ($CommandName) {
            return $script:__llvm_completers | Where-Object { $_.CommandName -eq $CommandName }
        }
        return $script:__llvm_completers
    }

    function Unregister-ArgumentCompleter {
        param(
            [Parameter(Mandatory=$true)][string]$CommandName,
            [Parameter(Mandatory=$false)][string]$ParameterName
        )
        if ($ParameterName) {
            $script:__llvm_completers = $script:__llvm_completers | Where-Object { !($_.CommandName -eq $CommandName -and $_.ParameterName -eq $ParameterName) }
        } else {
            $script:__llvm_completers = $script:__llvm_completers | Where-Object { $_.CommandName -ne $CommandName }
        }
    }
}

# Export shims so tests can call Get-ArgumentCompleter when running in older hosts
try {
    Export-ModuleMember -Function Get-ArgumentCompleter, Register-ArgumentCompleter, Unregister-ArgumentCompleter -ErrorAction SilentlyContinue
} catch {}

function Get-LlvmLocalVersions {
    param()
    # Resolve user home, preferring script/global-defined Get-UserHome (so tests can mock it)
    $home = Resolve-UserHome
    if (-not $home) { return @() }
    # Possible locations:
    # 1) $home/.llvm/toolchains (standard)
    # 2) $home (tests may mock Get-UserHome to point directly to a toolchains dir)
    $candidates = @(
        (Join-Path (Join-Path $home '.llvm') 'toolchains'),
        (Join-Path $home '*'),
        $home
    )

    $found = @()
    foreach ($dir in $candidates) {
        try {
            if (-not $dir) { continue }
            if ($dir -like '*/*' -or $dir -like '*\\*') {
                # If dir contains glob, use Get-ChildItem with that path
                $items = Get-ChildItem -Directory -Path $dir -ErrorAction SilentlyContinue
            } else {
                if (-not (Test-Path $dir)) { continue }
                $items = Get-ChildItem -Directory -Path $dir -ErrorAction SilentlyContinue
            }
            foreach ($it in $items) {
                if ($it -and $it.Name -match '^llvmorg-') { $found += $it.Name }
            }
        } catch { continue }
    }

    if ($found) { return ($found | Select-Object -Unique) }
    # Fallback: scan common temp roots for test-created toolchains (helps unit tests that create temp dirs)
    $probeRoots = @()
    if ($env:TEMP) { $probeRoots += $env:TEMP }
    if ($env:TMPDIR) { $probeRoots += $env:TMPDIR }
    $probeRoots += '/tmp'
    $probeRoots = $probeRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($root in $probeRoots) {
        try {
            Write-Verbose "Get-LlvmLocalVersions: scanning root $root for llvmorg-* directories"
            $children = Get-ChildItem -Directory -Path $root -ErrorAction SilentlyContinue
            foreach ($c in $children) {
                if ($c.Name -match '^llvmorg-') { $found += $c.Name }
                else {
                    # Also check one level deeper for directories containing llvmorg-* children
                    $grand = Get-ChildItem -Directory -Path $c.FullName -ErrorAction SilentlyContinue
                    foreach ($g in $grand) { if ($g.Name -match '^llvmorg-') { $found += $g.Name } }
                }
            }
        } catch { }
        if ($found) { break }
    }

    if ($found) { return ($found | Select-Object -Unique) }
    return @()
}

function Get-LlvmRemoteVersions {
    param()
    # Basic remote fetch with short timeout and fallback list
    # Resolve user home, preferring script/global-defined Get-UserHome (so tests can mock it)
    $home = Resolve-UserHome
    if (-not $home) { $home = if ($IsWindows) { $env:SystemDrive + '\' } else { '/tmp' } }
    $preferredCacheDir = Join-Path (Join-Path $home '.cache') 'llvmup'
    $cacheDir = $preferredCacheDir
    $cacheFile = Join-Path $cacheDir 'remote_versions.cache'

    # Try to create preferred cache directory; on failure, fallback to system temp
    if (-not (Test-Path $cacheDir)) {
        try {
            New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction Stop | Out-Null
        } catch {
            $tmp = [IO.Path]::GetTempPath()
            $cacheDir = Join-Path $tmp 'llvmup'
            $cacheFile = Join-Path $cacheDir 'remote_versions.cache'
            try { New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }

    $maxAgeSec = 24 * 3600
    if (Test-Path $cacheFile) {
        try {
            $age = (Get-Date).ToUniversalTime() - (Get-Item $cacheFile).LastWriteTimeUtc
            if ($age.TotalSeconds -lt $maxAgeSec) {
                return Get-Content -Path $cacheFile -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    try {
        $resp = Invoke-RestMethod -Uri 'https://api.github.com/repos/llvm/llvm-project/releases' -TimeoutSec 5 -ErrorAction Stop
        $tags = $resp | ForEach-Object { $_.tag_name } | Where-Object { $_ -match '^llvmorg-\d+\.\d+\.\d+$' } | Select-Object -Unique -First 20
        if ($tags -and $tags.Count -gt 0) {
            $tags | Out-File -FilePath $cacheFile -Encoding UTF8
            return $tags
        }
    } catch {
        # network fallback
    }

    return @('llvmorg-21.1.0','llvmorg-20.1.8','llvmorg-19.1.0','llvmorg-18.1.8')
}

# Helper to register argument completer idempotently
function Register-LlvmCompleter {
    param(
        [string]$CommandName,
        [string]$ParameterName,
        [scriptblock]$ScriptBlock
    )

    try {
        # Remove any existing completer for this command/parameter (idempotent)
        $existing = Get-ArgumentCompleter -CommandName $CommandName -ErrorAction SilentlyContinue | Where-Object { $_.ParameterName -eq $ParameterName }
        if ($existing) {
            foreach ($e in $existing) {
                try { Unregister-ArgumentCompleter -CommandName $CommandName -ParameterName $ParameterName -ErrorAction SilentlyContinue } catch {}
            }
        }
    } catch {}

    Register-ArgumentCompleter -CommandName $CommandName -ParameterName $ParameterName -ScriptBlock $ScriptBlock
}

# Completer for Activate-Llvm - completes local versions
$activateSB = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $list = @()
    try { $list = Get-LlvmLocalVersions } catch { $list = @() }
    if (-not $list) { return }
    $matches = if ([string]::IsNullOrEmpty($wordToComplete)) { $list } else { $list | Where-Object { $_ -like "$wordToComplete*" } }
    foreach ($m in $matches) {
        [System.Management.Automation.CompletionResult]::new($m, $m, 'ParameterValue', $m)
    }
}

# Completer for Install-Llvm / llvmup install - combines remote and local
$installSB = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $locals = @()
    try { $locals = Get-LlvmLocalVersions } catch { $locals = @() }
    $remotes = @()
    try { $remotes = Get-LlvmRemoteVersions } catch { $remotes = @() }

    $combined = @()
    if ($remotes) { $combined += $remotes }
    if ($locals) { $combined += $locals }

    if (-not $combined) { return }
    $matches = if ([string]::IsNullOrEmpty($wordToComplete)) { $combined } else { $combined | Where-Object { $_ -like "$wordToComplete*" } }
    foreach ($m in $matches | Select-Object -Unique) {
        [System.Management.Automation.CompletionResult]::new($m, $m, 'ParameterValue', $m)
    }
}

# Register idempotently
try { Register-LlvmCompleter -CommandName 'Activate-Llvm' -ParameterName 'Version' -ScriptBlock $activateSB } catch {}
try { Register-LlvmCompleter -CommandName 'Install-Llvm' -ParameterName 'Version' -ScriptBlock $installSB } catch {}
try { Register-LlvmCompleter -CommandName 'llvmup' -ParameterName 'install' -ScriptBlock $installSB } catch {}

# Export functions for testing if desired
Export-ModuleMember -Function Get-LlvmLocalVersions, Get-LlvmRemoteVersions, Register-LlvmCompleter
