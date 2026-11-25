# Archive extraction abstraction with 7-Zip discovery, path-traversal protection, and capability checks.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}

function Find-Llvm7Zip {
    [CmdletBinding()]
    param([string]$CustomPath = '')

    $candidates = @()
    if ($CustomPath) { $candidates += $CustomPath }
    if ($env:LLVMUP_7Z_PATH) { $candidates += $env:LLVMUP_7Z_PATH }

    foreach ($cmdName in @('7z.exe', '7z', '7zz.exe', '7zz')) {
        $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
    }

    if (Test-LlvmIsWindows) {
        if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
        $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        if ($pf86) { $candidates += (Join-Path $pf86 '7-Zip\7z.exe') }
        $candidates += 'C:\Program Files\7-Zip\7z.exe'
        $candidates += 'C:\Program Files (x86)\7-Zip\7z.exe'
        foreach ($regPath in @('HKLM:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip')) {
            try {
                $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
                if ($props -and $props.Path) {
                    $candidates += (Join-Path $props.Path '7z.exe')
                }
            } catch {}
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $resolved = $candidate
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { continue }
        $resolved = (Resolve-Path -LiteralPath $resolved).Path
        if ($seen.ContainsKey($resolved.ToLowerInvariant())) { continue }
        $seen[$resolved.ToLowerInvariant()] = $true

        $version = ''
        $variant = if ([IO.Path]::GetFileNameWithoutExtension($resolved) -match '^7zz') { '7zz' } else { '7z' }
        try {
            $infoLines = @(& $resolved i 2>&1)
            if ($LASTEXITCODE -eq 0) {
                $banner = ($infoLines | Select-Object -First 4) -join ' '
                if ($banner -match '7-Zip(?:\s+\([^)]+\))?\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)') {
                    $version = $matches[1]
                }
                $textAll = $infoLines -join "`n"
                return [pscustomobject][ordered]@{
                    available = $true
                    path = $resolved
                    version = $version
                    variant = $variant
                    supports_xz = ($textAll -match '\bxz\b')
                    supports_7z = ($textAll -match '\b7z\b')
                    supports_zip = ($textAll -match '\bzip\b')
                    supports_tar = ($textAll -match '\btar\b')
                }
            }
        } catch {}
    }

    return [pscustomobject][ordered]@{
        available = $false
        path = $null
        version = ''
        variant = ''
        supports_xz = $false
        supports_7z = $false
        supports_zip = $false
        supports_tar = $false
    }
}

function Get-LlvmAvailableExtractors {
    [CmdletBinding()]
    param([string]$Custom7ZipPath = '')

    $sevenZip = Find-Llvm7Zip -CustomPath $Custom7ZipPath
    $tarCmd = Get-Command tar -ErrorAction SilentlyContinue | Select-Object -First 1
    $tarPath = if ($tarCmd -and $tarCmd.Source) { $tarCmd.Source } else { $null }
    $tarVersion = ''
    if ($tarPath) {
        try { $tarVersion = (& $tarPath --version 2>&1 | Select-Object -First 1) } catch {}
    }
    $msiCmd = if (Test-LlvmIsWindows) { Get-Command msiexec.exe -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }

    return [pscustomobject][ordered]@{
        sevenzip = $sevenZip
        tar = [pscustomobject][ordered]@{
            available = [bool]$tarPath
            path = $tarPath
            version = [string]$tarVersion
        }
        zip_dotnet = [pscustomobject][ordered]@{
            available = $true
        }
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
    $items = @(Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction Stop)
    foreach ($item in $items) {
        $itemFull = [IO.Path]::GetFullPath($item.FullName)
        if (-not $itemFull.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Extracted path escapes staging root: $itemFull"
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = $null
            try { $target = $item.Target } catch {}
            if ($target) {
                $targetPath = @($target)[0]
                if ([IO.Path]::IsPathRooted($targetPath)) {
                    $resolvedTarget = [IO.Path]::GetFullPath($targetPath)
                } else {
                    $resolvedTarget = [IO.Path]::GetFullPath((Join-Path (Split-Path $item.FullName -Parent) $targetPath))
                }
                if (-not $resolvedTarget.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Unsafe reparse point escaping staging root: $($item.FullName) -> $targetPath"
                }
            }
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

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $zip.Entries) {
            if (-not (Test-LlvmSafeArchiveEntryName -EntryName $entry.FullName)) {
                throw "Unsafe ZIP archive entry: $($entry.FullName)"
            }
            $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($mode -eq 0xA000) {
                throw "Unsupported POSIX symlink entry in ZIP archive on Windows: $($entry.FullName)"
            }
            $rel = $entry.FullName.TrimEnd('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (-not $rel) { continue }
            $targetPath = [IO.Path]::GetFullPath((Join-Path $fullDest $rel))
            if (-not $targetPath.StartsWith($fullDestWithSep, [StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP entry escapes destination: $($entry.FullName)"
            }
            if ($entry.FullName.EndsWith('/')) {
                $null = New-Item -ItemType Directory -Path $targetPath -Force
                continue
            }
            $parentDir = Split-Path $targetPath -Parent
            if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
                $null = New-Item -ItemType Directory -Path $parentDir -Force
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

    $entries = @(Get-ChildItem -LiteralPath $RawRoot -Force)
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer -and -not ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $topDir = $entries[0]
        if (Test-Path -LiteralPath $FinalStagingPath) {
            Remove-Item -LiteralPath $FinalStagingPath -Recurse -Force
        }
        Move-Item -LiteralPath $topDir.FullName -Destination $FinalStagingPath -ErrorAction Stop
        return
    }

    if ($ExpectedTopDirs.Count -gt 0) {
        foreach ($expected in $ExpectedTopDirs) {
            $cand = Join-Path $RawRoot $expected
            if (Test-Path -LiteralPath $cand -PathType Container) {
                if (Test-Path -LiteralPath $FinalStagingPath) {
                    Remove-Item -LiteralPath $FinalStagingPath -Recurse -Force
                }
                Move-Item -LiteralPath $cand -Destination $FinalStagingPath -ErrorAction Stop
                return
            }
        }
    }

    if (Test-Path -LiteralPath $FinalStagingPath) {
        Remove-Item -LiteralPath $FinalStagingPath -Recurse -Force
    }
    Move-Item -LiteralPath $RawRoot -Destination $FinalStagingPath -ErrorAction Stop
}

function Invoke-Llvm7ZipCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & $SevenZipPath @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $tail = ($output | Select-Object -Last 8) -join "`n"
        throw "7-Zip failed with exit code ${code}: $tail"
    }
}

function Invoke-LlvmArchiveExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [ValidateSet('auto', '7z', 'tar', 'zip', 'msi')]
        [string]$Extractor = '',
        [string]$Custom7ZipPath = '',
        [string[]]$ExpectedTopDirs = @(),
        [switch]$UnwrapSingleRoot = $true
    )

    if (-not $Extractor) {
        $Extractor = if ($env:LLVMUP_EXTRACTOR) { $env:LLVMUP_EXTRACTOR.ToLowerInvariant() } else { 'auto' }
    } else {
        $Extractor = $Extractor.ToLowerInvariant()
    }
    if ($Extractor -notin @('auto', '7z', 'tar', 'zip', 'msi')) {
        throw "Invalid extractor '$Extractor'. Expected auto, 7z, tar, zip, or msi."
    }

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive file not found: $ArchivePath"
    }

    $caps = Get-LlvmAvailableExtractors -Custom7ZipPath $Custom7ZipPath
    $name = [IO.Path]::GetFileName($ArchivePath).ToLowerInvariant()

    $isTarXz = $name.EndsWith('.tar.xz') -or $name.EndsWith('.txz')
    $isTarGz = $name.EndsWith('.tar.gz') -or $name.EndsWith('.tgz')
    $isTar = $name.EndsWith('.tar')
    $is7z = $name.EndsWith('.7z')
    $isZip = $name.EndsWith('.zip')
    $isMsi = $name.EndsWith('.msi')
    $isExe = $name.EndsWith('.exe')

    $chosen = $Extractor
    if ($chosen -eq 'auto') {
        if ($is7z) { $chosen = '7z' }
        elseif ($isZip) { $chosen = 'zip' }
        elseif ($isMsi) { $chosen = 'msi' }
        elseif ($isExe) { $chosen = 'exe' }
        elseif ($isTarXz) {
            if ($caps.sevenzip.available -and $caps.sevenzip.supports_xz -and $caps.sevenzip.supports_tar) { $chosen = '7z' }
            elseif ($caps.tar.available) { $chosen = 'tar' }
            else { throw "No extractor available for .tar.xz (need tar or 7-Zip)." }
        } elseif ($isTarGz -or $isTar) {
            if ($caps.tar.available) { $chosen = 'tar' }
            elseif ($caps.sevenzip.available -and $caps.sevenzip.supports_tar) { $chosen = '7z' }
            else { throw "No extractor available for TAR archive." }
        } else {
            throw "Unsupported archive format: $ArchivePath"
        }
    }

    # Validate explicit extractor capability without silent fallback
    switch ($chosen) {
        '7z' {
            if (-not $caps.sevenzip.available) {
                throw "Requested extractor '7z' is not available. Install 7-Zip or pass --extractor auto."
            }
            if (-not ($is7z -or $isZip -or $isTarXz -or $isTarGz -or $isTar)) {
                throw "Extractor '7z' cannot handle archive format: $ArchivePath"
            }
        }
        'tar' {
            if (-not $caps.tar.available) {
                throw "Requested extractor 'tar' is not available."
            }
            if (-not ($isTarXz -or $isTarGz -or $isTar)) {
                throw "Extractor 'tar' cannot handle archive format: $ArchivePath"
            }
        }
        'zip' {
            if (-not $isZip) {
                throw "Extractor 'zip' only supports .zip archives: $ArchivePath"
            }
        }
        'msi' {
            if (-not $isMsi -or -not $caps.msi.available) {
                throw "MSI extractor requires a .msi file and msiexec.exe on Windows."
            }
        }
    }

    $rawStage = "$DestinationPath.raw-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $rawStage -Force
    $tarStage = $null

    try {
        if ($chosen -eq 'exe') {
            $proc = Start-Process -FilePath $ArchivePath -ArgumentList @('/S', "/D=$rawStage") -Wait -PassThru
            if ($proc.ExitCode -ne 0) { throw "Installer failed with exit code $($proc.ExitCode)" }
        } elseif ($chosen -eq 'msi') {
            $proc = Start-Process -FilePath $caps.msi.path -ArgumentList @('/a', "`"$ArchivePath`"", '/qn', "TARGETDIR=`"$rawStage`"") -Wait -PassThru
            if ($proc.ExitCode -ne 0) { throw "MSI extraction failed with exit code $($proc.ExitCode)" }
        } elseif ($chosen -eq 'zip') {
            Expand-LlvmZipDotNet -ArchivePath $ArchivePath -DestinationPath $rawStage
        } elseif ($chosen -eq 'tar') {
            $null = & $caps.tar.path -xf $ArchivePath -C $rawStage 2>&1
            if ($LASTEXITCODE -ne 0) { throw "tar extraction failed with exit code $LASTEXITCODE" }
        } elseif ($chosen -eq '7z') {
            $szPath = $caps.sevenzip.path
            if ($isTarXz -or $isTarGz) {
                $tarStage = "$DestinationPath.tarstage-$([guid]::NewGuid().ToString('N'))"
                $null = New-Item -ItemType Directory -Path $tarStage -Force
                # Step 1: decompress .tar.xz / .tar.gz into temporary .tar
                Invoke-Llvm7ZipCommand -SevenZipPath $szPath -Arguments @('x', $ArchivePath, "-o$tarStage", '-y', '-bd')
                $tarFile = Get-ChildItem -LiteralPath $tarStage -Filter '*.tar' -File | Select-Object -First 1
                if (-not $tarFile) {
                    throw "7-Zip decompression did not produce a .tar archive for $ArchivePath"
                }
                # Step 2: extract .tar cleanly into rawStage
                Invoke-Llvm7ZipCommand -SevenZipPath $szPath -Arguments @('x', $tarFile.FullName, "-o$rawStage", '-y', '-bd')
            } else {
                Invoke-Llvm7ZipCommand -SevenZipPath $szPath -Arguments @('x', $ArchivePath, "-o$rawStage", '-y', '-bd')
            }
        }

        Test-LlvmStagingTreeSafety -RootPath $rawStage | Out-Null

        if ($UnwrapSingleRoot) {
            Move-LlvmSingleRootUp -RawRoot $rawStage -FinalStagingPath $DestinationPath -ExpectedTopDirs $ExpectedTopDirs
        } else {
            if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Recurse -Force }
            Move-Item -LiteralPath $rawStage -Destination $DestinationPath -ErrorAction Stop
        }

        Test-LlvmStagingTreeSafety -RootPath $DestinationPath | Out-Null

        return [pscustomobject][ordered]@{
            extractor = $chosen
            extractor_path = if ($chosen -eq '7z') { $caps.sevenzip.path } elseif ($chosen -eq 'tar') { $caps.tar.path } else { 'builtin' }
            destination = $DestinationPath
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
    'Get-LlvmAvailableExtractors',
    'Test-LlvmSafeArchiveEntryName',
    'Test-LlvmStagingTreeSafety',
    'Invoke-LlvmArchiveExtract'
)
