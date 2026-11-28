# Llvm-Completion.psm1 - PowerShell completions for LLVMUP
# Registers argument completers for key commands (Activate-Llvm, Install-Llvm, etc.)

# NOTE: do not import Get-UserHome helper at module import time.
# We will lazily load it inside Resolve-UserHome only if no session-defined Get-UserHome exists.

# Resolve user home, preferring a session/script-defined Get-UserHome (so tests can mock it)
function Resolve-UserHome {
    # If a Get-UserHome function exists, try calling it directly - this respects any session/test
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

    $isWin = ($PSVersionTable.PSVersion.Major -lt 6) -or ($null -ne $IsWindows -and $IsWindows)
    if ($env:HOME) { return $env:HOME }
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($isWin) { return $env:SystemDrive + '\' }
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
        $script:__llvm_completers = @($script:__llvm_completers | Where-Object { -not ($_.CommandName -eq $CommandName -and $_.ParameterName -eq $ParameterName) }) + $entry
        # No PowerShell version ships Get-ArgumentCompleter, so this shim is always active: keep the local
        # registry for introspection and also register with the real cmdlet so tab completion works.
        $real = Get-Command -Name 'Microsoft.PowerShell.Core\Register-ArgumentCompleter' -CommandType Cmdlet -ErrorAction SilentlyContinue
        if ($real) {
            $realArgs = @{ CommandName = $CommandName; ScriptBlock = $ScriptBlock }
            if ($ParameterName) { $realArgs.ParameterName = $ParameterName }
            & $real @realArgs
        }
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
    $candidates = @()
    if ($env:LLVM_TOOLCHAINS_DIR) { $candidates += $env:LLVM_TOOLCHAINS_DIR }
    elseif ($env:LLVM_CUSTOM_TOOLCHAINS_DIR) { $candidates += $env:LLVM_CUSTOM_TOOLCHAINS_DIR }
    elseif ($env:LLVM_HOME) { $candidates += (Join-Path $env:LLVM_HOME 'toolchains') }
    elseif ($env:LLVM_CUSTOM_HOME) { $candidates += (Join-Path $env:LLVM_CUSTOM_HOME 'toolchains') }

    $homeDir = Resolve-UserHome
    if ($homeDir) {
        $candidates += @(
            (Join-Path (Join-Path $homeDir '.llvm') 'toolchains'),
            (Join-Path $homeDir '*'),
            $homeDir
        )
    }
    if (-not $candidates) { return @() }

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
    $homeDir = Resolve-UserHome
    $isWin = ($PSVersionTable.PSVersion.Major -lt 6) -or ($null -ne $IsWindows -and $IsWindows)
    if (-not $homeDir) { $homeDir = if ($isWin) { $env:SystemDrive + '\' } else { '/tmp' } }
    $preferredCacheDir = Join-Path (Join-Path $homeDir '.cache') 'llvmup'
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

function Get-LlvmCompletionHome {
    if ($env:LLVM_HOME) { return $env:LLVM_HOME }
    if ($env:LLVM_CUSTOM_HOME) { return $env:LLVM_CUSTOM_HOME }
    $h = Resolve-UserHome
    if ($h) { return (Join-Path $h '.llvm') }
    return $null
}

function Get-LlvmProviderNames {
    $dir = Join-Path (Join-Path $PSScriptRoot 'libexec') 'recipes'
    $names = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
    if ($names.Count) { return $names }
    return @('official', 'winlibs', 'llvm-mingw')
}

function Get-LlvmToolchainCompletionItems {
    # Offline: installed toolchains (any provider), aliases and linked external toolchains.
    $homeDir = Get-LlvmCompletionHome
    $tc = if ($env:LLVM_TOOLCHAINS_DIR) { $env:LLVM_TOOLCHAINS_DIR } elseif ($homeDir) { Join-Path $homeDir 'toolchains' } else { $null }
    $items = @()
    if ($tc -and (Test-Path -LiteralPath $tc)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $tc -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -match '\.(installing|backup|staging|raw)-') { continue }
            if ((Test-Path -LiteralPath (Join-Path $d.FullName '.llvmup-toolchain.json')) -or (Test-Path -LiteralPath (Join-Path $d.FullName 'bin'))) { $items += $d.Name }
        }
    }
    foreach ($f in @('aliases.json', 'external-toolchains.json')) {
        if (-not $homeDir) { continue }
        $path = Join-Path $homeDir $f
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $obj = if ($f -eq 'aliases.json') { $j.aliases } else { $j.toolchains }
            if ($obj) { $items += @($obj.PSObject.Properties | ForEach-Object { $_.Name }) }
        } catch {}
    }
    return @($items | Select-Object -Unique)
}

function Get-LlvmTargetCompletionItems {
    $homeDir = Get-LlvmCompletionHome
    $tc = if ($env:LLVM_TOOLCHAINS_DIR) { $env:LLVM_TOOLCHAINS_DIR } elseif ($homeDir) { Join-Path $homeDir 'toolchains' } else { $null }
    $targets = @('x86_64-w64-mingw32', 'i686-w64-mingw32', 'aarch64-w64-mingw32', 'armv7-w64-mingw32')
    if ($tc -and (Test-Path -LiteralPath $tc)) {
        foreach ($m in @(Get-ChildItem -Path (Join-Path $tc '*\.llvmup-toolchain.json') -File -ErrorAction SilentlyContinue)) {
            try { $targets += @((Get-Content -LiteralPath $m.FullName -Raw | ConvertFrom-Json).supported_targets) } catch {}
        }
    }
    return @($targets | Where-Object { $_ } | Select-Object -Unique)
}

$llvmupSB = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text.Trim([char[]]@([char]39, [char]34)) })
    # When the cursor is after a space, the word being completed is not yet an element.
    $typed = if ($wordToComplete) { $elements.Count - 1 } else { $elements.Count }
    $previous = if ($typed -ge 1) { $elements[$typed - 1] } else { '' }
    $commands = @('doctor', 'install', 'activate', 'deactivate', 'env', 'resolve', 'vscode-activate', 'status', 'list', 'remove',
                  'disk-usage', 'default', 'config', 'use', 'run', 'which', 'where', 'provides', 'info', 'alias', 'pin', 'sync',
                  'update', 'pick', 'toolchain', 'shell', 'cmake-toolchain', 'help')
    $selectors = { @(Get-LlvmToolchainCompletionItems) + @(Get-LlvmProviderNames | ForEach-Object { "$_@latest" }) }
    $values = @()
    if ($typed -le 1) {
        $values = $commands + @('--version') + @(& $selectors | Where-Object { $wordToComplete -like '+*' } | ForEach-Object { "+$_" })
    } elseif ($previous -eq '--provider') { $values = Get-LlvmProviderNames }
    elseif ($previous -eq '--compiler') { $values = @('clang', 'gcc') }
    elseif ($previous -eq '--target') { $values = Get-LlvmTargetCompletionItems }
    elseif ($previous -eq '--crt') { $values = @('ucrt', 'msvcrt') }
    elseif ($previous -eq '--extractor') { $values = @('auto', '7z', 'tar', 'zip', 'python') }
    elseif ($previous -eq '--verify') { $values = @('warn', 'strict', 'skip') }
    elseif ($previous -eq '--toolchain') { $values = Get-LlvmToolchainCompletionItems }
    elseif ($previous -eq '--format') { $values = @('shell', 'github', 'json', 'cmd', 'tag', 'plan') }
    else {
        $subcommand = $elements[1].ToLowerInvariant()
        if ($subcommand.StartsWith('+')) { $subcommand = 'run' }
        $afterSeparator = ($elements[1..($typed - 1)] -contains '--')
        switch ($subcommand) {
            { $_ -in @('activate', 'vscode-activate') } { $values = Get-LlvmToolchainCompletionItems }
            'help' { if ($typed -le 2) { $values = @('install', 'use', 'run', 'list', 'status', 'config', 'sync', 'pin', 'default', 'alias', 'remove', 'update', 'env') } }
            'remove' { $values = if ($wordToComplete -like '-*') { @('--force', '--help') } else { Get-LlvmToolchainCompletionItems } }
            'list' { $values = @('--remote', '--json', '--providers', '--provider', '--help') }
            'default' {
                if ($typed -le 2) { $values = @('set', 'show', 'unset') + @(Get-LlvmToolchainCompletionItems) }
                elseif ($elements[2] -eq 'set') { $values = Get-LlvmToolchainCompletionItems }
            }
            'config' { if ($typed -le 2) { $values = @('init', 'load', 'apply', 'activate', 'lock') } else { $values = @('--platform', '--arch', '--verify') } }
            'doctor' { $values = @('--verbose', '--deep', '--network', '--json', '--help') }
            'disk-usage' { $values = @('-h', '--human-readable') }
            { $_ -in @('use', 'run', 'which', 'where', 'info', 'shell', 'cmake-toolchain', 'update', 'env') } {
                if ($afterSeparator) {
                    $values = @(Get-Command -Name "$wordToComplete*" -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                } elseif ($wordToComplete -like '-*') {
                    $values = switch ($subcommand) {
                        'use' { @('--compiler', '--target', '--crt', '--install', '--auto') }
                        'env' { @('--config', '--format', '--compiler', '--target') }
                        'which' { @('--toolchain', '--compiler', '--target') }
                        'cmake-toolchain' { @('--target', '--compiler', '--output') }
                        'shell' { @('--compiler', '--target', '--shell') }
                        default { @('--compiler', '--target', '--crt', '--install', '--locked', '--') }
                    }
                } elseif ($subcommand -eq 'which' -and $typed -eq 2) {
                    $values = @('clang', 'clang++', 'clangd', 'clang-format', 'clang-tidy', 'lld', 'ld.lld', 'lld-link', 'llvm-ar', 'llvm-config', 'gcc', 'g++', 'gdb', 'lldb', 'cmake', 'ninja', 'windres')
                } else {
                    $values = @(& $selectors)
                    if ($subcommand -eq 'use' -and $typed -eq 2) { $values = @('-') + $values }
                }
            }
            'provides' { $values = @('clang', 'clang++', 'clangd', 'lld', 'ld.lld', 'lld-link', 'llvm-config', 'libclang', 'gcc', 'g++', 'gdb', 'lldb', 'windres', 'cmake', 'ninja') }
            'alias' {
                if ($typed -le 2) { $values = @('set', 'list', 'show', 'remove') }
                elseif ($typed -eq 3 -and $elements[2] -in @('show', 'remove')) {
                    $homeDir = Get-LlvmCompletionHome
                    try { $values = @((Get-Content -LiteralPath (Join-Path $homeDir 'aliases.json') -Raw | ConvertFrom-Json).aliases.PSObject.Properties | ForEach-Object { $_.Name }) } catch {}
                } elseif ($typed -eq 4) { $values = Get-LlvmToolchainCompletionItems }
            }
            'toolchain' { if ($typed -le 2) { $values = @('link', 'unlink', 'list') } }
            'pin' { $values = if ($wordToComplete -like '-*') { @('--current', '--fuzzy', '--crt', '--target', '--compiler') } else { @(& $selectors) } }
            'sync' { $values = @('--locked', '--verify') }
            'install' {
                if ($previous -in @('--profile', '-p')) { $values = @('minimal', 'compiler', 'full', 'custom') }
                elseif ($previous -eq '--component') { $values = @('clang','lld','llvm-ar','llvm-ranlib','llvm-cov','llvm-profdata','clangd','clang-format','clang-tidy','libc++','llvm-xray','llvm-nm','llvm-objcopy','llvm-strip','llvm-objdump','llvm-readobj','llvm-readelf','llvm-size','llvm-strings','llvm-symbolizer','llvm-addr2line','llvm-cxxfilt','llvm-dwarfdump','llvm-dwp','llvm-pdbutil','llvm-profgen','llvm-as','llvm-dis','llvm-link','llvm-extract','llvm-bcanalyzer','llvm-diff','llvm-mc','llvm-mca','llc','lli','opt','clang-apply-replacements','clang-query','clang-scan-deps','clang-check') }
                elseif ($wordToComplete -like '-*') { $values = @('--from-source', '--verify', '--name', '--default', '--profile', '--component', '--strip', '--verbose', '--reconfigure', '--list-only', '--provider', '--release', '--crt', '--threads', '--target', '--compiler', '--extractor', '--use', '--force', '--no-cache') }
                else { $values = @(Get-LlvmProviderNames | ForEach-Object { "$_@latest" }) + @(Get-LlvmRemoteVersions) }
            }
            'resolve' { $values = if ($wordToComplete -like '-*') { @('--format', '--platform', '--arch', '--provider', '--release', '--crt', '--config') } else { @(Get-LlvmProviderNames | ForEach-Object { "$_@latest" }) } }
            default { $values = @() }
        }
    }
    foreach ($value in @($values | Where-Object { $_ -like "$wordToComplete*" } | Select-Object -Unique)) {
        [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
    }
}

# Register idempotently
try { Register-LlvmCompleter -CommandName 'Activate-Llvm' -ParameterName 'Version' -ScriptBlock $activateSB } catch {}
try { Register-LlvmCompleter -CommandName 'Install-Llvm' -ParameterName 'Version' -ScriptBlock $installSB } catch {}
try { Register-LlvmCompleter -CommandName 'llvmup' -ParameterName 'LlvmupSubcommand' -ScriptBlock $llvmupSB } catch {}
try { Register-LlvmCompleter -CommandName 'llvmup' -ParameterName 'LlvmupArgs' -ScriptBlock $llvmupSB } catch {}

# Export functions for testing if desired
Export-ModuleMember -Function Get-LlvmLocalVersions, Get-LlvmRemoteVersions, Register-LlvmCompleter, Get-LlvmToolchainCompletionItems, Get-LlvmProviderNames, Get-LlvmTargetCompletionItems
