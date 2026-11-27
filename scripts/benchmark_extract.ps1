<#
.SYNOPSIS
Reproducible benchmark of the llvmup extraction backends on real toolchain archives.

.DESCRIPTION
For every archive and every backend that can read it, this script extracts the archive through the same
code path llvmup uses (Invoke-LlvmArchiveExtract) into a fresh directory and records:

  - extractor, strategy, executable path and version
  - archive name, SHA-256 and compressed size
  - extracted size and file count
  - decompression time and extraction time (measured separately for the 7-Zip temp-file strategy,
    which is the only one with two observable phases), and total time
  - peak temporary space (the intermediate .tar for the temp strategy; 0 for streaming backends)
  - extra copies/moves performed after extraction (llvmup moves the staged tree; it never copies it)
  - a content fingerprint (relative path + size of every file, plus SHA-256 of key binaries) so that
    results can be compared for functional equivalence across backends

Nothing is downloaded; pass archives that are already on disk (for example the llvmup download cache).

.EXAMPLE
pwsh -File scripts/benchmark_extract.ps1 -Archive (Get-ChildItem $env:LLVMUP_CACHE_DIR -Recurse -File).FullName -WorkDir D:\bench -OutFile bench.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Archive,
    [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) 'llvmup-extract-bench'),
    [string[]]$Backend = @(),
    [int]$Repeat = 1,
    [string]$OutFile = '',
    [switch]$KeepTrees
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'libexec\pwsh\Llvm-Extractor.psm1') -Force -DisableNameChecking

function Get-TreeStats([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    $bytes = [long]0
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $bytes += $f.Length
        $lines.Add(($f.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/') + "`t" + $f.Length))
    }
    $lines.Sort([StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    $listing = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).Replace('-', '').ToLowerInvariant()
    $key = @{}
    foreach ($n in @('clang.exe', 'clang++.exe', 'gcc.exe', 'lld.exe', 'ld.lld.exe', 'libc++.dll')) {
        $hit = $files | Where-Object { $_.Name -ieq $n } | Select-Object -First 1
        if ($hit) { $key[$n] = (Get-FileHash -LiteralPath $hit.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return [pscustomobject]@{ files = $files.Count; bytes = $bytes; listing_sha256 = $listing; key_files = $key }
}

# 'powershell -File' passes "-Archive a,b" as one string; split it when it is not a file itself.
$Archive = @($Archive | ForEach-Object { if ((Test-Path -LiteralPath $_) -or $_ -notmatch ',') { $_ } else { $_ -split ',' } })
$null = New-Item -ItemType Directory -Path $WorkDir -Force
$probe = Get-LlvmAvailableExtractors -IncludePython
$results = @()
foreach ($a in $Archive) {
    $item = Get-Item -LiteralPath $a
    $format = Get-LlvmArchiveFormat -Name $item.Name
    if (-not $format) { Write-Warning "Skipping unsupported archive $($item.Name)"; continue }
    $digest = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    # Candidate backends for this format: (extractor, 7-Zip tar strategy)
    $cands = @()
    switch ($format) {
        'zip' { $cands = @(@('zip', ''), @('7z', ''), @('python', '')) }
        '7z' { $cands = @(, @('7z', '')) }
        'exe' { $cands = @(, @('7z', '')) }
        default { $cands = @(@('7z', 'stream'), @('7z', 'temp'), @('tar', ''), @('python', '')) }
    }
    if ($Backend.Count) { $cands = @($cands | Where-Object { $Backend -contains (($_[0], $_[1]) -join ':').TrimEnd(':') -or $Backend -contains $_[0] }) }

    foreach ($c in $cands) {
        $ext = $c[0]; $strategy = $c[1]
        $label = if ($strategy) { "${ext}:$strategy" } else { $ext }
        for ($run = 1; $run -le $Repeat; $run++) {
            $dest = Join-Path $WorkDir ("{0}-{1}-{2}" -f ($item.BaseName -replace '[^A-Za-z0-9.-]', '_'), ($label -replace ':', '-'), $run)
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            $row = [ordered]@{
                archive = $item.Name; archive_sha256 = $digest; compressed_bytes = $item.Length; format = $format
                backend = $label; run = $run; status = 'ok'; error = ''
                extractor_path = ''; extractor_version = ''
                decompress_seconds = $null; extract_seconds = $null; total_seconds = $null
                temp_bytes = 0; extracted_bytes = $null; files = $null
                post_extraction_copies = 0; post_extraction_moves = 1
                listing_sha256 = ''; key_files = @{}
            }
            $old = $env:LLVMUP_7Z_TAR_STRATEGY
            try {
                if ($strategy -eq 'temp') {
                    # Measure the two phases of the temp-file strategy directly with the same 7-Zip binary.
                    $sz = $probe.sevenzip
                    if (-not $sz.available) { throw '7-Zip not available' }
                    $tarDir = "$dest.tar"
                    $null = New-Item -ItemType Directory -Path $tarDir -Force
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    & $sz.path x $item.FullName "-o$tarDir" -y -bd -bso0 -bsp0 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "7-Zip decompression exit $LASTEXITCODE" }
                    $row.decompress_seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
                    $tarFile = Get-ChildItem -LiteralPath $tarDir -Filter *.tar | Select-Object -First 1
                    $row.temp_bytes = $tarFile.Length
                    $sw.Restart()
                    & $sz.path x $tarFile.FullName "-o$dest" -y -bd -bso0 -bsp0 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "7-Zip tar extraction exit $LASTEXITCODE" }
                    $row.extract_seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
                    $row.total_seconds = [math]::Round($row.decompress_seconds + $row.extract_seconds, 2)
                    $row.extractor_path = $sz.path; $row.extractor_version = $sz.version
                    Remove-Item -LiteralPath $tarDir -Recurse -Force
                    $tree = $dest
                } else {
                    if ($strategy) { $env:LLVMUP_7Z_TAR_STRATEGY = $strategy }
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    $r = Invoke-LlvmArchiveExtract -ArchivePath $item.FullName -DestinationPath $dest -Extractor $ext -UnwrapSingleRoot:$false
                    $row.total_seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
                    $row.extractor_path = $r.extractor_path; $row.extractor_version = $r.extractor_version
                    $tree = $dest
                }
                $st = Get-TreeStats $tree
                $row.extracted_bytes = $st.bytes; $row.files = $st.files
                $row.listing_sha256 = $st.listing_sha256; $row.key_files = $st.key_files
            } catch {
                $row.status = 'unavailable-or-failed'; $row.error = $_.Exception.Message
            } finally {
                $env:LLVMUP_7Z_TAR_STRATEGY = $old
                if (-not $KeepTrees -and (Test-Path -LiteralPath $dest)) { Remove-Item -LiteralPath $dest -Recurse -Force }
            }
            $results += [pscustomobject]$row
            Write-Host ("{0,-62} {1,-10} {2,-22} total={3,7}s files={4}" -f $item.Name, $label, $row.status, $row.total_seconds, $row.files)
        }
    }
}

# Equivalence: every successful backend for one archive must produce the same listing.
foreach ($g in ($results | Where-Object { $_.status -eq 'ok' } | Group-Object archive)) {
    $distinct = @($g.Group | Select-Object -ExpandProperty listing_sha256 -Unique)
    foreach ($r in $g.Group) { $r | Add-Member -NotePropertyName equivalent -NotePropertyValue ($distinct.Count -eq 1) -Force }
}

$report = [ordered]@{
    schema = 1
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    host = [ordered]@{ os = [Environment]::OSVersion.VersionString; ps = $PSVersionTable.PSVersion.ToString(); cpus = [Environment]::ProcessorCount }
    extractors = [ordered]@{
        sevenzip = if ($probe.sevenzip.available) { "$($probe.sevenzip.version) $($probe.sevenzip.path)" } else { 'unavailable' }
        tar = if ($probe.tar.available) { "$($probe.tar.version) $($probe.tar.path) xz=$($probe.tar.supports_xz) zstd=$($probe.tar.supports_zstd)" } else { 'unavailable' }
        python = if ($probe.python -and $probe.python.available) { "$($probe.python.version) zstd=$($probe.python.supports_zstd)" } else { 'unavailable' }
    }
    results = $results
}
$json = $report | ConvertTo-Json -Depth 6
if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $json -Encoding UTF8 } else { $json }
