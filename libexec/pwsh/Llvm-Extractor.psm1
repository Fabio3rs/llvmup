# Archive extraction abstraction with 7-Zip discovery, path-traversal protection, and capability checks.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}

$script:ProbeCache = @{}

function Get-LlvmProbeCacheKey {
    param([string]$Name, [string]$Extra = '')
    # Invalidate whenever discovery inputs change (tests and users may edit PATH at runtime).
    return "$Name|$Extra|$($env:PATH)|$($env:LLVMUP_7Z_PATH)|$($env:LLVMUP_TAR_PATH)|$($env:LLVMUP_PYTHON)|$($env:LLVMUP_DISABLE_PYTHON_EXTRACTOR)"
}

function Get-Llvm7ZipProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $key = Get-LlvmProbeCacheKey -Name 'Get-Llvm7ZipProbe' -Extra $Path
    if (-not $script:ProbeCache.ContainsKey($key)) { $script:ProbeCache[$key] = Get-Llvm7ZipProbeUncached -Path $Path }
    return $script:ProbeCache[$key]
}

function Get-Llvm7ZipProbeUncached {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $variant = if ([IO.Path]::GetFileNameWithoutExtension($Path) -match '^7zz') { '7zz' } else { '7z' }
    try {
        $infoLines = @(& $Path i 2>&1 | ForEach-Object { [string]$_ })
        if ($LASTEXITCODE -ne 0) { return $null }
    } catch {
        return $null
    }
    $banner = ($infoLines | Select-Object -First 4) -join ' '
    $version = ''
    if ($banner -match '7-Zip(?:\s+\([^)]+\)|\s+\[[^\]]+\])?\s+([0-9]+\.[0-9]+)') {
        $version = $matches[1]
    }
    # Only inspect the "Formats:" table; codec/hash sections would otherwise produce false positives.
    $formatLines = @()
    $inFormats = $false
    foreach ($line in $infoLines) {
        if ($line -match '^\s*Formats:') { $inFormats = $true; continue }
        if ($inFormats -and $line -match '^\s*(Codecs|Hashers):') { break }
        if ($inFormats) { $formatLines += $line }
    }
    if ($formatLines.Count -eq 0) { $formatLines = $infoLines }
    $fmtText = ($formatLines -join "`n")
    $parsedVersion = [version]'0.0'
    if ($version) { try { $parsedVersion = [version]$version } catch {} }

    return [pscustomobject][ordered]@{
        available = $true
        path = $Path
        version = $version
        parsed_version = $parsedVersion
        variant = $variant
        supports_xz = [bool]($fmtText -match '(?i)\sxz\s')
        supports_7z = [bool]($fmtText -match '(?i)\s7z\s')
        supports_zip = [bool]($fmtText -match '(?i)\szip\s')
        supports_tar = [bool]($fmtText -match '(?i)\star\s')
        supports_nsis = [bool]($fmtText -match '(?i)\snsis\s')
        supports_zstd = [bool]($fmtText -match '(?i)\szstd\s')
        # LZMA2/BCJ2 (modern .7z archives such as WinLibs), -so/-si streaming and -bso/-bsp switches need 15.x+.
        modern = ($parsedVersion -ge [version]'15.0')
        source = 'discovered'
    }
}

function Find-Llvm7Zip {
    [CmdletBinding()]
    param(
        [string]$CustomPath = '',
        [switch]$All
    )

    $explicit = @()
    if ($CustomPath) { $explicit += $CustomPath }
    if ($env:LLVMUP_7Z_PATH) { $explicit += $env:LLVMUP_7Z_PATH }

    $candidates = @()
    foreach ($cmdName in @('7z', '7zz', '7za')) {
        foreach ($cmd in @(Get-Command $cmdName -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
        }
    }
    if (Test-LlvmIsWindows) {
        foreach ($regPath in @('HKCU:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip')) {
            try {
                $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
                foreach ($prop in @('Path64', 'Path')) {
                    if ($props -and $props.$prop) { $candidates += (Join-Path $props.$prop '7z.exe') }
                }
            } catch {}
        }
        foreach ($base in @($env:ProgramW6432, $env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'))) {
            if ($base) { $candidates += (Join-Path $base '7-Zip\7z.exe') }
        }
        if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\7-Zip\7z.exe') }
        if ($env:USERPROFILE) { $candidates += (Join-Path $env:USERPROFILE 'scoop\apps\7zip\current\7z.exe') }
    } else {
        $candidates += @('/usr/bin/7zz', '/usr/bin/7z', '/usr/local/bin/7zz', '/opt/homebrew/bin/7zz')
    }

    $probes = @()
    $seen = @{}
    # An explicitly configured executable always wins and is never silently replaced.
    foreach ($candidate in $explicit) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Configured 7-Zip executable does not exist: $candidate"
        }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $probe = Get-Llvm7ZipProbe -Path $resolved
        if (-not $probe) { throw "Configured 7-Zip executable is not usable: $resolved" }
        $probe.source = 'configured'
        if (-not $All) { return $probe }
        $probes += $probe
        $seen[$resolved.ToLowerInvariant()] = $true
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $key = $resolved.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $probe = Get-Llvm7ZipProbe -Path $resolved
        if ($probe) { $probes += $probe }
    }

    if ($All) { return $probes }

    # Prefer the newest modern build; never pick an ancient 7-Zip merely because it comes first on PATH.
    $best = $probes | Sort-Object -Property @(
        @{ Expression = { [int]$_.modern }; Descending = $true },
        @{ Expression = { $_.parsed_version }; Descending = $true }
    ) | Select-Object -First 1
    if ($best) { return $best }

    return [pscustomobject][ordered]@{
        available = $false
        path = $null
        version = ''
        parsed_version = [version]'0.0'
        variant = ''
        supports_xz = $false
        supports_7z = $false
        supports_zip = $false
        supports_tar = $false
        supports_nsis = $false
        supports_zstd = $false
        modern = $false
        source = 'none'
    }
}

function Get-LlvmTarProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $key = Get-LlvmProbeCacheKey -Name 'Get-LlvmTarProbe' -Extra $Path
    if (-not $script:ProbeCache.ContainsKey($key)) { $script:ProbeCache[$key] = Get-LlvmTarProbeUncached -Path $Path }
    return $script:ProbeCache[$key]
}

function Get-LlvmTarProbeUncached {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $ver = ''
    try { $ver = [string](@(& $Path --version 2>&1) | Select-Object -First 1) } catch { return $null }
    if ($LASTEXITCODE -ne 0 -and -not $ver) { return $null }
    $isGnu = $ver -match 'GNU tar'
    $isBsd = $ver -match 'bsdtar'
    $hasXzProgram = [bool](Get-Command xz -CommandType Application -ErrorAction SilentlyContinue)
    $hasZstdProgram = [bool](Get-Command zstd -CommandType Application -ErrorAction SilentlyContinue)
    # bsdtar links its codecs (the Windows inbox build ships zlib only and would try to spawn an external
    # "xz", which can hang); GNU tar always delegates to the external xz/zstd programs.
    $xz = if ($isBsd) { $ver -match 'liblzma' } elseif ($isGnu) { $hasXzProgram } else { $false }
    $zstd = if ($isBsd) { $ver -match 'libzstd' } elseif ($isGnu) { $hasZstdProgram } else { $false }
    return [pscustomobject][ordered]@{
        available = $true
        path = $Path
        version = $ver
        flavor = if ($isGnu) { 'gnu' } elseif ($isBsd) { 'bsdtar' } else { 'unknown' }
        supports_gz = ($isGnu -or ($ver -match 'zlib'))
        supports_xz = [bool]$xz
        supports_zstd = [bool]$zstd
        extra_args = if ($isGnu -and (Test-LlvmIsWindows)) { @('--force-local') } else { @() }
    }
}

function Find-LlvmTar {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'tar', 'tar.gz', 'tar.xz', 'tar.zst')]
        [string]$Format = '',
        [switch]$All
    )

    $candidates = @()
    if ($env:LLVMUP_TAR_PATH) { $candidates += $env:LLVMUP_TAR_PATH }
    if (Test-LlvmIsWindows) {
        $sysRoot = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
        $candidates += (Join-Path $sysRoot 'System32\tar.exe')
    }
    foreach ($cmd in @(Get-Command tar -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ($cmd.Source) { $candidates += $cmd.Source }
    }

    $probes = @()
    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $key = ([IO.Path]::GetFullPath($candidate)).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $probe = Get-LlvmTarProbe -Path $candidate
        if ($probe) { $probes += $probe }
    }
    if ($All) { return $probes }

    foreach ($probe in $probes) {
        $ok = switch ($Format) {
            'tar.xz' { $probe.supports_xz }
            'tar.zst' { $probe.supports_zstd }
            'tar.gz' { $probe.supports_gz }
            default { $true }
        }
        if ($ok) { return $probe }
    }
    return [pscustomobject][ordered]@{ available = $false; path = $null; version = ''; flavor = ''; supports_gz = $false; supports_xz = $false; supports_zstd = $false; extra_args = @() }
}

function Find-LlvmPythonExtractor {
    [CmdletBinding()]
    param()
    $key = Get-LlvmProbeCacheKey -Name 'python'
    if (-not $script:ProbeCache.ContainsKey($key)) { $script:ProbeCache[$key] = Find-LlvmPythonExtractorUncached }
    return $script:ProbeCache[$key]
}

function Find-LlvmPythonExtractorUncached {
    # Optional backend. Never required: only used when explicitly selected or when it is the only
    # backend able to read a format (e.g. .tar.zst on stock Windows).
    [CmdletBinding()]
    param()

    $none = [pscustomobject][ordered]@{ available = $false; path = $null; version = ''; prefix_args = @(); supports_xz = $false; supports_gz = $false; supports_zstd = $false; script = '' }
    if ($env:LLVMUP_DISABLE_PYTHON_EXTRACTOR -eq '1') { return $none }
    $script = Join-Path (Split-Path $PSScriptRoot -Parent) 'llvmup-extract.py'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { return $none }

    $candidates = @()
    if ($env:LLVMUP_PYTHON) { $candidates += , @($env:LLVMUP_PYTHON) }
    if (Test-LlvmIsWindows) {
        $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($py) { $candidates += , @($py.Source, '-3') }
    }
    foreach ($n in @('python3', 'python')) {
        foreach ($cmd in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            # Skip Windows Store "app execution alias" stubs, which open the Store instead of running.
            if ($cmd.Source -and $cmd.Source -notmatch '[\\/]WindowsApps[\\/]') { $candidates += , @($cmd.Source) }
        }
    }

    $best = $null
    foreach ($cand in $candidates) {
        $exe = $cand[0]
        $prefix = @()
        if ($cand.Count -gt 1) { $prefix = @($cand[1..($cand.Count - 1)]) }
        try {
            # Capture all output: Select-Object -First would stop the native process early and
            # leave $LASTEXITCODE unreliable.
            $probeOut = @(& $exe @prefix -I $script probe 2>$null)
            if ($LASTEXITCODE -ne 0) { continue }
            $json = @($probeOut | Where-Object { "$_".StartsWith('{') }) | Select-Object -First 1
            if (-not $json) { continue }
            $info = $json | ConvertFrom-Json
        } catch { continue }
        if (-not $info.data_filter) { continue }
        $entry = [pscustomobject][ordered]@{
            available = $true
            path = $exe
            version = [string]$info.version
            parsed_version = [version]$info.version
            prefix_args = $prefix
            supports_xz = [bool]$info.xz
            supports_gz = [bool]$info.gz
            supports_zstd = [bool]$info.zstd
            script = $script
        }
        if (-not $best -or $entry.parsed_version -gt $best.parsed_version) { $best = $entry }
    }
    if ($best) { return $best }
    return $none
}

function Get-LlvmExtractableFormats {
    # Archive formats that the currently available backends can read; used to prefer smaller
    # upstream assets (e.g. .tar.zst) only when they can actually be unpacked.
    [CmdletBinding()]
    param($Caps = $null)
    if (-not $Caps) { $Caps = Get-LlvmAvailableExtractors -IncludePython }
    $formats = @('zip')
    $sz = $Caps.sevenzip
    if ($sz.available -and $sz.modern) { $formats += '7z'; if ($sz.supports_nsis) { $formats += 'exe' } }
    $tarXz = Find-LlvmTar -Format 'tar.xz'
    $tarZst = Find-LlvmTar -Format 'tar.zst'
    $py = $Caps.python
    if (($sz.available -and $sz.modern -and $sz.supports_xz) -or $tarXz.available -or ($py -and $py.available -and $py.supports_xz)) { $formats += 'tar.xz' }
    if (($sz.available -and $sz.modern -and $sz.supports_zstd) -or $tarZst.available -or ($py -and $py.available -and $py.supports_zstd)) { $formats += 'tar.zst' }
    if ($Caps.tar.available -or ($py -and $py.available)) { $formats += @('tar.gz', 'tar') }
    if ($Caps.msi.available) { $formats += 'msi' }
    return @($formats | Select-Object -Unique)
}

function Get-LlvmAvailableExtractors {
    [CmdletBinding()]
    param([string]$Custom7ZipPath = '', [string]$Format = '', [switch]$IncludePython)

    $sevenZip = Find-Llvm7Zip -CustomPath $Custom7ZipPath
    $tarFormat = if ($Format -in @('tar', 'tar.gz', 'tar.xz', 'tar.zst')) { $Format } else { '' }
    $tar = Find-LlvmTar -Format $tarFormat
    $msiCmd = if (Test-LlvmIsWindows) { Get-Command msiexec.exe -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }

    return [pscustomobject][ordered]@{
        sevenzip = $sevenZip
        tar = $tar
        zip_dotnet = [pscustomobject][ordered]@{ available = $true }
        python = if ($IncludePython) { Find-LlvmPythonExtractor } else { [pscustomobject]@{ available = $false } }
        msi = [pscustomobject][ordered]@{
            available = [bool]$msiCmd
            path = if ($msiCmd) { $msiCmd.Source } else { $null }
        }
    }
}

function Test-LlvmSafeArchiveEntryName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$EntryName)

    if ([string]::IsNullOrWhiteSpace($EntryName)) { return $false }
    if ($EntryName.IndexOf([char]0) -ge 0) { return $false }
    $normalized = $EntryName.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:') { return $false }
    foreach ($part in ($normalized -split '/')) {
        if ($part -eq '..') { return $false }
    }
    return $true
}

function Test-LlvmStagingTreeSafety {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $fullRoot = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    # Walk directories without following reparse points, so a link cannot redirect the scan outside staging.
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push([IO.Path]::GetFullPath($RootPath))
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)) {
            $itemFull = [IO.Path]::GetFullPath($item.FullName)
            if (-not $itemFull.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Extracted path escapes staging root: $itemFull"
            }
            $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isLink) {
                $target = $null
                try { $target = $item.Target } catch {}
                if (-not $target) {
                    try { $target = $item.LinkTarget } catch {}
                }
                if ($target) {
                    $targetPath = [string](@($target)[0])
                    $resolvedTarget = if ([IO.Path]::IsPathRooted($targetPath)) {
                        [IO.Path]::GetFullPath($targetPath)
                    } else {
                        [IO.Path]::GetFullPath((Join-Path (Split-Path $item.FullName -Parent) $targetPath))
                    }
                    if (-not $resolvedTarget.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
                        throw "Unsafe link escaping staging root: $($item.FullName) -> $targetPath"
                    }
                }
                continue
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    return $true
}

function Expand-LlvmZipDotNet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fullDest = [IO.Path]::GetFullPath($DestinationPath)
    $null = New-Item -ItemType Directory -Path $fullDest -Force
    $fullDestWithSep = $fullDest.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $createdDirs = @{}

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        # Validate every entry before writing anything.
        foreach ($entry in $zip.Entries) {
            if (-not (Test-LlvmSafeArchiveEntryName -EntryName $entry.FullName)) {
                throw "Unsafe ZIP archive entry: $($entry.FullName)"
            }
            $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($mode -eq 0xA000) {
                throw "Unsupported symlink entry in ZIP archive: $($entry.FullName)"
            }
        }
        foreach ($entry in $zip.Entries) {
            $rel = $entry.FullName.TrimEnd('/', '\').Replace('/', [IO.Path]::DirectorySeparatorChar).Replace('\', [IO.Path]::DirectorySeparatorChar)
            if (-not $rel) { continue }
            $targetPath = [IO.Path]::GetFullPath((Join-Path $fullDest $rel))
            if (-not $targetPath.StartsWith($fullDestWithSep, [StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP entry escapes destination: $($entry.FullName)"
            }
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                if (-not $createdDirs.ContainsKey($targetPath)) {
                    $null = [IO.Directory]::CreateDirectory($targetPath)
                    $createdDirs[$targetPath] = $true
                }
                continue
            }
            $parentDir = [IO.Path]::GetDirectoryName($targetPath)
            if ($parentDir -and -not $createdDirs.ContainsKey($parentDir)) {
                $null = [IO.Directory]::CreateDirectory($parentDir)
                $createdDirs[$parentDir] = $true
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
        }
    } finally {
        $zip.Dispose()
    }
}

function Move-LlvmSingleRootUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RawRoot,
        [Parameter(Mandatory = $true)][string]$FinalStagingPath,
        [string[]]$ExpectedTopDirs = @()
    )

    if (Test-Path -LiteralPath $FinalStagingPath) {
        Remove-Item -LiteralPath $FinalStagingPath -Recurse -Force
    }

    $entries = @(Get-ChildItem -LiteralPath $RawRoot -Force)
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer -and -not ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        # Directory rename (same volume): no recursive copy.
        Move-Item -LiteralPath $entries[0].FullName -Destination $FinalStagingPath -ErrorAction Stop
        return
    }

    foreach ($expected in $ExpectedTopDirs) {
        $cand = Join-Path $RawRoot $expected
        if (Test-Path -LiteralPath $cand -PathType Container) {
            Move-Item -LiteralPath $cand -Destination $FinalStagingPath -ErrorAction Stop
            return
        }
    }

    Move-Item -LiteralPath $RawRoot -Destination $FinalStagingPath -ErrorAction Stop
}

function Invoke-LlvmNativeChecked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $tail = ($output | Select-Object -Last 8) -join "`n"
        throw "$Label failed with exit code ${code}: $tail"
    }
}

function Format-LlvmProcessArgument {
    param([string]$Arg)
    if ($null -eq $Arg -or $Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('"')
    $bs = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') {
            $null = $sb.Append('\', $bs * 2 + 1).Append('"')
        } else {
            if ($bs) { $null = $sb.Append('\', $bs) }
            $null = $sb.Append($ch)
        }
        $bs = 0
    }
    if ($bs) { $null = $sb.Append('\', $bs * 2) }
    $null = $sb.Append('"')
    return $sb.ToString()
}

function New-LlvmSevenZipStartInfo {
    param([string]$SevenZipPath, [string[]]$ArgList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SevenZipPath
    $psi.Arguments = ((@($ArgList) | ForEach-Object { Format-LlvmProcessArgument $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    return $psi
}

function Invoke-Llvm7ZipStreamTar {
    # Decompress with one 7-Zip process (-so) and unpack the tar stream with another (-si), wiring the
    # two through .NET Process byte streams. This avoids the PowerShell pipeline (which would convert
    # bytes to text on PS 5.1) and avoids writing a multi-GB intermediate .tar.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    $psiA = New-LlvmSevenZipStartInfo -SevenZipPath $SevenZipPath -ArgList @('x', $ArchivePath, '-so', '-bd', '-bsp0', '-bse2')
    $psiA.RedirectStandardOutput = $true
    $psiB = New-LlvmSevenZipStartInfo -SevenZipPath $SevenZipPath -ArgList @('x', '-si', '-ttar', "-o$OutputDir", '-y', '-bd', '-bsp0', '-bso0', '-bse2')
    $psiB.RedirectStandardInput = $true
    $psiB.RedirectStandardOutput = $true

    $procA = [System.Diagnostics.Process]::Start($psiA)
    $procB = $null
    try {
        $procB = [System.Diagnostics.Process]::Start($psiB)
        $errA = $procA.StandardError.ReadToEndAsync()
        $errB = $procB.StandardError.ReadToEndAsync()
        $outB = $procB.StandardOutput.ReadToEndAsync()
        $copyFailed = $null
        $trailingBytes = [long]0
        $trailingNonZero = $false
        $src = $procA.StandardOutput.BaseStream
        $dst = $procB.StandardInput.BaseStream
        $buf = New-Object byte[] 1048576
        $draining = $false
        $written = [long]0
        try {
            # Explicit copy loop (about 4,000 iterations for a 4 GB toolchain). Before each write the
            # tar side is checked: 7-Zip stops reading at the tar end-of-archive marker and exits 0
            # while the decompressor still writes the archive's zero padding, and a failed tar side
            # stops reading too. A pipe without a reader may then fail, block or (on .NET Framework)
            # silently swallow writes, so after the tar side exits the rest is drained and checked
            # here instead of being written.
            while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) {
                if (-not $draining -and $procB.HasExited) { $draining = $true }
                if (-not $draining) {
                    try { $dst.Write($buf, 0, $n); $written += $n } catch { $draining = $true }
                    if (-not $draining) { continue }
                }
                if ($procB.HasExited -and $procB.ExitCode -ne 0) { try { $procA.Kill() } catch {}; break }
                $trailingBytes += $n
                if (-not $trailingNonZero) {
                    for ($k = 0; $k -lt $n; $k++) { if ($buf[$k] -ne 0) { $trailingNonZero = $true; break } }
                }
                if ($trailingNonZero -or $trailingBytes -gt 64MB) { try { $procA.Kill() } catch {}; break }
            }
        } catch {
            $copyFailed = $_.Exception.GetBaseException().Message
        } finally {
            try { $dst.Close() } catch {}
        }
        if ($draining) {
            $procB.WaitForExit()
            # Data the tar side never consumed is acceptable only when it finished successfully and the
            # remainder is padding. The chunk in flight when it stopped may hold the end marker.
            if ($procB.ExitCode -eq 0 -and -not @(Get-ChildItem -LiteralPath $OutputDir -Force -ErrorAction SilentlyContinue).Count) {
                # Seen in Windows Sandbox: the tar side, started by .NET, printed its banner and exited
                # 0 without reading or extracting anything ($written bytes reached its pipe). Distinct
                # marker so the caller can retry with the cmd.exe pipe.
                throw [System.IO.EndOfStreamException]::new('LLVMUP_7Z_TAR_SIDE_DID_NOT_READ: the 7-Zip tar extractor exited before reading its input.')
            }
            if ($procB.ExitCode -eq 0 -and $trailingNonZero) {
                $copyFailed = "the tar extractor stopped before the end of the stream (non-padding data follows; $trailingBytes bytes checked). 7-Zip tar side said: $($errB.Result.Trim()) $($outB.Result.Trim())"
            }
        }
        $procB.WaitForExit()
        if (-not $procA.WaitForExit(60000)) { try { $procA.Kill() } catch {}; $procA.WaitForExit() }
        $null = $outB.Result
        # The extractor's own error explains a broken pipe better than the decompressor's exit status.
        if ($procB.ExitCode -ne 0) {
            throw "7-Zip tar extraction failed with exit code $($procB.ExitCode): $($errB.Result.Trim())"
        }
        if ($copyFailed) { throw "7-Zip stream copy failed: $copyFailed" }
        if ($procA.ExitCode -ne 0) {
            throw "7-Zip decompression failed with exit code $($procA.ExitCode): $($errA.Result.Trim())"
        }
    } finally {
        foreach ($p in @($procA, $procB)) {
            if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
            if ($p) { $p.Dispose() }
        }
    }
}

function Invoke-Llvm7ZipCmdPipe {
    # Same two 7-Zip processes as Invoke-Llvm7ZipStreamTar, connected by cmd.exe's binary pipe.
    # Used when the .NET-connected tar side does not read its input (observed in Windows Sandbox),
    # or explicitly with LLVMUP_7Z_TAR_STRATEGY=pipe. The decompressor's stderr goes to a file and
    # any error there fails the extraction; the exit code is the tar side's.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )
    foreach ($path in @($SevenZipPath, $ArchivePath, $OutputDir)) {
        # cmd.exe expands %VAR% even inside quotes; refuse instead of guessing.
        if ($path -match '[%"]') { throw "The cmd.exe pipe cannot safely pass the path '$path' (contains % or a quote)." }
    }
    $errFile = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-7z-' + [guid]::NewGuid().ToString('N') + '.err')
    $line = '"{0}" x "{1}" -so -bd -bsp0 2>"{2}" | "{0}" x -si -ttar "-o{3}" -y -bd -bsp0 -bso0' -f $SevenZipPath, $ArchivePath, $errFile, $OutputDir
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /s /c "' + $line + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTar = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $errDec = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile -Raw) } else { '' }
        if ($errDec -and $errDec.Trim()) {
            throw "7-Zip decompression reported errors: $($errDec.Trim())"
        }
        if ($proc.ExitCode -ne 0) {
            throw "7-Zip tar extraction failed with exit code $($proc.ExitCode): $($errTar.Trim())"
        }
    } finally {
        $proc.Dispose()
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-LlvmArchiveFormat {
    param([Parameter(Mandatory = $true)][string]$Name)
    $n = $Name.ToLowerInvariant()
    if ($n.EndsWith('.tar.xz') -or $n.EndsWith('.txz')) { return 'tar.xz' }
    if ($n.EndsWith('.tar.gz') -or $n.EndsWith('.tgz')) { return 'tar.gz' }
    if ($n.EndsWith('.tar.zst') -or $n.EndsWith('.tzst')) { return 'tar.zst' }
    if ($n.EndsWith('.tar')) { return 'tar' }
    if ($n.EndsWith('.7z')) { return '7z' }
    if ($n.EndsWith('.zip')) { return 'zip' }
    if ($n.EndsWith('.msi')) { return 'msi' }
    if ($n.EndsWith('.exe')) { return 'exe' }
    return ''
}

function Get-Llvm7ZipTarStrategy {
    # Windows default: cmd.exe's binary pipe between the two 7-Zip processes (fastest in the
    # benchmark and the only pipe that works in Windows Sandbox). 'stream' wires them through .NET.
    $default = if (Test-LlvmIsWindows) { 'pipe' } else { 'stream' }
    $strategy = if ($env:LLVMUP_7Z_TAR_STRATEGY) { $env:LLVMUP_7Z_TAR_STRATEGY.ToLowerInvariant() } else { $default }
    if ($strategy -notin @('stream', 'temp', 'pipe')) {
        throw "Invalid LLVMUP_7Z_TAR_STRATEGY '$strategy'. Expected stream, pipe or temp."
    }
    return $strategy
}

function Resolve-LlvmExtractorChoice {
    # Returns the backend for an archive. An explicit choice is validated and never replaced;
    # 'auto' picks the best available backend for the format (see docs/EXTRACTION.md for benchmarks).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Format,
        [Parameter(Mandatory = $true)][string]$Extractor,
        [Parameter(Mandatory = $true)]$Caps,
        [string]$ArchivePath = ''
    )

    $sz = $Caps.sevenzip
    $chosen = $Extractor
    if ($chosen -eq 'auto') {
        switch ($Format) {
            '7z' { $chosen = '7z' }
            'zip' { $chosen = 'zip' }
            'msi' { $chosen = 'msi' }
            'exe' { $chosen = '7z' }
            'tar.xz' {
                if ($sz.available -and $sz.modern -and $sz.supports_xz) { $chosen = '7z' }
                elseif ($Caps.tar.available -and $Caps.tar.supports_xz) { $chosen = 'tar' }
                elseif ($Caps.python -and $Caps.python.available -and $Caps.python.supports_xz) { $chosen = 'python' }
                else { throw 'No extractor available for .tar.xz: install 7-Zip 15+ (or set LLVMUP_7Z_PATH) or provide a tar with xz support. The Windows inbox tar.exe lacks xz.' }
            }
            'tar.zst' {
                if ($Caps.tar.available -and $Caps.tar.supports_zstd) { $chosen = 'tar' }
                elseif ($sz.available -and $sz.modern -and $sz.supports_zstd) { $chosen = '7z' }
                elseif ($Caps.python -and $Caps.python.available -and $Caps.python.supports_zstd) { $chosen = 'python' }
                else { throw 'No extractor available for .tar.zst (need tar with zstd, 7-Zip with zstd, or Python 3.14+).' }
            }
            { $_ -in @('tar.gz', 'tar') } {
                if ($Caps.tar.available) { $chosen = 'tar' }
                elseif ($sz.available -and $sz.supports_tar) { $chosen = '7z' }
                else { throw 'No extractor available for TAR archive.' }
            }
            default { throw "Unsupported archive format: $ArchivePath" }
        }
    }

    switch ($chosen) {
        '7z' {
            if (-not $sz.available) {
                throw "Requested extractor '7z' is not available. Install 7-Zip, set LLVMUP_7Z_PATH, or pass --extractor auto."
            }
            if ($Format -notin @('7z', 'zip', 'tar.xz', 'tar.gz', 'tar.zst', 'tar', 'exe')) {
                throw "Extractor '7z' cannot handle archive format '$Format': $ArchivePath"
            }
            if ($Format -eq '7z' -and -not $sz.modern) {
                throw "7-Zip $($sz.version) at $($sz.path) is too old for modern .7z archives (need 15.0+). Set LLVMUP_7Z_PATH to a newer 7-Zip."
            }
            if ($Format -eq 'tar.xz' -and -not $sz.supports_xz) {
                throw "7-Zip $($sz.version) at $($sz.path) does not support xz."
            }
            if ($Format -eq 'tar.zst' -and -not $sz.supports_zstd) {
                throw "7-Zip $($sz.version) at $($sz.path) does not support zstd."
            }
            if ($Format -eq 'exe' -and -not $sz.supports_nsis) {
                throw "7-Zip $($sz.version) at $($sz.path) cannot unpack NSIS installers; use the .tar.xz archive (default) instead."
            }
        }
        'tar' {
            if (-not $Caps.tar.available) { throw "Requested extractor 'tar' is not available." }
            if ($Format -notin @('tar.xz', 'tar.gz', 'tar.zst', 'tar')) {
                throw "Extractor 'tar' cannot handle archive format '$Format': $ArchivePath"
            }
            if ($Format -eq 'tar.xz' -and -not $Caps.tar.supports_xz) {
                throw "Requested extractor 'tar' ($($Caps.tar.path)) cannot decompress xz. Use --extractor 7z or auto."
            }
            if ($Format -eq 'tar.zst' -and -not $Caps.tar.supports_zstd) {
                throw "Requested extractor 'tar' ($($Caps.tar.path)) cannot decompress zstd."
            }
        }
        'zip' {
            if ($Format -ne 'zip') { throw "Extractor 'zip' only supports .zip archives: $ArchivePath" }
        }
        'python' {
            $py = $Caps.python
            if (-not $py -or -not $py.available) {
                throw "Requested extractor 'python' is not available (need Python 3.12+ with the tarfile data filter; set LLVMUP_PYTHON)."
            }
            if ($Format -notin @('tar.xz', 'tar.gz', 'tar.zst', 'tar', 'zip')) {
                throw "Extractor 'python' cannot handle archive format '$Format': $ArchivePath"
            }
            if ($Format -eq 'tar.zst' -and -not $py.supports_zstd) { throw "Python $($py.version) has no zstd support (need 3.14+)." }
            if ($Format -eq 'tar.xz' -and -not $py.supports_xz) { throw "Python $($py.version) was built without lzma." }
        }
        'msi' {
            if ($Format -ne 'msi' -or -not $Caps.msi.available) {
                throw 'MSI extractor requires a .msi file and msiexec.exe on Windows.'
            }
        }
        default { throw "Invalid extractor '$chosen'." }
    }
    return $chosen
}

function Invoke-LlvmArchiveExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [string]$Extractor = '',
        [string]$Custom7ZipPath = '',
        [string[]]$ExpectedTopDirs = @(),
        [switch]$UnwrapSingleRoot = $true
    )

    if (-not $Extractor) {
        $Extractor = if ($env:LLVMUP_EXTRACTOR) { $env:LLVMUP_EXTRACTOR } else { 'auto' }
    }
    $Extractor = $Extractor.ToLowerInvariant()
    if ($Extractor -notin @('auto', '7z', 'tar', 'zip', 'msi', 'python')) {
        throw "Invalid extractor '$Extractor'. Expected auto, 7z, tar, zip, msi, or python."
    }
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive file not found: $ArchivePath"
    }

    $format = Get-LlvmArchiveFormat -Name ([IO.Path]::GetFileName($ArchivePath))
    if (-not $format) { throw "Unsupported archive format: $ArchivePath" }
    $needPython = ($Extractor -eq 'python') -or ($Extractor -eq 'auto' -and $format -in @('tar.zst', 'tar.xz'))
    $caps = Get-LlvmAvailableExtractors -Custom7ZipPath $Custom7ZipPath -Format $format -IncludePython:$needPython
    $chosen = Resolve-LlvmExtractorChoice -Format $format -Extractor $Extractor -Caps $caps -ArchivePath $ArchivePath

    $rawStage = "$DestinationPath.raw-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $rawStage -Force
    $tarStage = $null
    $strategy = 'direct'
    $sw = [Diagnostics.Stopwatch]::StartNew()

    try {
        switch ($chosen) {
            'msi' {
                $proc = Start-Process -FilePath $caps.msi.path -ArgumentList @('/a', "`"$ArchivePath`"", '/qn', "TARGETDIR=`"$rawStage`"") -Wait -PassThru
                if ($proc.ExitCode -ne 0) { throw "MSI administrative extraction failed with exit code $($proc.ExitCode)" }
            }
            'zip' { Expand-LlvmZipDotNet -ArchivePath $ArchivePath -DestinationPath $rawStage }
            'python' {
                $py = $caps.python
                $pyArgs = @($py.prefix_args) + @('-I', $py.script, 'extract', $ArchivePath, $rawStage)
                Invoke-LlvmNativeChecked -FilePath $py.path -Arguments $pyArgs -Label "Python $($py.version) extraction"
            }
            'tar' {
                $arcArg = $ArchivePath
                $dstArg = $rawStage
                if ($caps.tar.flavor -eq 'gnu' -and (Test-LlvmIsWindows)) {
                    # MSYS GNU tar treats backslashes as escapes; forward slashes are unambiguous.
                    $arcArg = $ArchivePath.Replace('\', '/')
                    $dstArg = $rawStage.Replace('\', '/')
                }
                $tarArgs = @($caps.tar.extra_args)
                if ($format -eq 'tar.zst' -and $caps.tar.flavor -eq 'gnu') {
                    # LLVM .tar.zst assets use a 1 GiB window (windowLog 30); zstd refuses it without --long.
                    $tarArgs += @('-I', 'zstd -d --long=31')
                }
                $tarArgs += @('-xf', $arcArg, '-C', $dstArg)
                Invoke-LlvmNativeChecked -FilePath $caps.tar.path -Arguments $tarArgs -Label 'tar extraction'
            }
            '7z' {
                $szPath = $caps.sevenzip.path
                if ($format -in @('tar.xz', 'tar.gz', 'tar.zst')) {
                    $strategy = Get-Llvm7ZipTarStrategy
                    if ($strategy -eq 'pipe' -and -not $env:LLVMUP_7Z_TAR_STRATEGY -and (@($szPath, $ArchivePath, $rawStage) -match '[%"]').Count) {
                        $strategy = 'stream'   # paths cmd.exe cannot pass safely
                    }
                    if ($strategy -eq 'pipe') {
                        Invoke-Llvm7ZipCmdPipe -SevenZipPath $szPath -ArchivePath $ArchivePath -OutputDir $rawStage
                    } elseif ($strategy -eq 'stream') {
                        try {
                            Invoke-Llvm7ZipStreamTar -SevenZipPath $szPath -ArchivePath $ArchivePath -OutputDir $rawStage
                        } catch {
                            # Only when the tar side consumed nothing (so nothing can be half-extracted)
                            # and the system pipe is available: same tool, same archive, other pipe.
                            $nothing = -not @(Get-ChildItem -LiteralPath $rawStage -Force -ErrorAction SilentlyContinue).Count
                            if ("$($_.Exception.Message)" -notmatch 'LLVMUP_7Z_TAR_SIDE_DID_NOT_READ' -or -not $nothing -or -not (Test-LlvmIsWindows)) { throw }
                            Write-Verbose '7-Zip tar side did not read from the .NET pipe; using the cmd.exe pipe.'
                            $strategy = 'pipe'
                            Invoke-Llvm7ZipCmdPipe -SevenZipPath $szPath -ArchivePath $ArchivePath -OutputDir $rawStage
                        }
                    } else {
                        $tarStage = "$DestinationPath.tarstage-$([guid]::NewGuid().ToString('N'))"
                        $null = New-Item -ItemType Directory -Path $tarStage -Force
                        Invoke-LlvmNativeChecked -FilePath $szPath -Arguments @('x', $ArchivePath, "-o$tarStage", '-y', '-bd') -Label '7-Zip decompression'
                        $tarFile = Get-ChildItem -LiteralPath $tarStage -Filter '*.tar' -File | Select-Object -First 1
                        if (-not $tarFile) { throw "7-Zip decompression did not produce a .tar archive for $ArchivePath" }
                        Invoke-LlvmNativeChecked -FilePath $szPath -Arguments @('x', $tarFile.FullName, "-o$rawStage", '-y', '-bd') -Label '7-Zip tar extraction'
                    }
                } elseif ($format -eq 'exe') {
                    # Unpack the NSIS installer payload without executing it (no UAC, no registry writes).
                    Invoke-LlvmNativeChecked -FilePath $szPath -Arguments @('x', $ArchivePath, "-o$rawStage", '-y', '-bd', '-x!$PLUGINSDIR', '-x!Uninstall.exe') -Label '7-Zip installer extraction'
                } else {
                    Invoke-LlvmNativeChecked -FilePath $szPath -Arguments @('x', $ArchivePath, "-o$rawStage", '-y', '-bd') -Label '7-Zip extraction'
                }
            }
        }

        if (-not @(Get-ChildItem -LiteralPath $rawStage -Force).Count) {
            throw "Extraction produced no files: $ArchivePath"
        }
        Test-LlvmStagingTreeSafety -RootPath $rawStage | Out-Null

        if ($UnwrapSingleRoot) {
            Move-LlvmSingleRootUp -RawRoot $rawStage -FinalStagingPath $DestinationPath -ExpectedTopDirs $ExpectedTopDirs
        } else {
            if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Recurse -Force }
            Move-Item -LiteralPath $rawStage -Destination $DestinationPath -ErrorAction Stop
        }

        return [pscustomobject][ordered]@{
            extractor = $chosen
            strategy = $strategy
            extractor_path = switch ($chosen) { '7z' { $caps.sevenzip.path } 'tar' { $caps.tar.path } 'python' { $caps.python.path } default { 'builtin' } }
            extractor_version = switch ($chosen) { '7z' { $caps.sevenzip.version } 'tar' { $caps.tar.version } 'python' { $caps.python.version } default { '' } }
            destination = $DestinationPath
            seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
        }
    } finally {
        if ($tarStage -and (Test-Path -LiteralPath $tarStage)) {
            Remove-Item -LiteralPath $tarStage -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $rawStage) {
            Remove-Item -LiteralPath $rawStage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function @(
    'Find-Llvm7Zip',
    'Find-LlvmTar',
    'Get-LlvmTarProbe',
    'Get-Llvm7ZipProbe',
    'Get-LlvmAvailableExtractors',
    'Find-LlvmPythonExtractor',
    'Get-LlvmExtractableFormats',
    'Get-LlvmArchiveFormat',
    'Resolve-LlvmExtractorChoice',
    'Test-LlvmSafeArchiveEntryName',
    'Test-LlvmStagingTreeSafety',
    'Invoke-LlvmArchiveExtract'
)
