# Shared GitHub Releases API client (with Link pagination), downloader, cache, and locking.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}

function Set-LlvmTls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}
}

function Get-LlvmDownloadCacheDir {
    [CmdletBinding()]
    param([string]$HomePath)
    if ($env:LLVMUP_CACHE_DIR) { return $env:LLVMUP_CACHE_DIR }
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    return (Join-Path (Join-Path $HomePath 'cache') 'downloads')
}

function Get-LlvmSafeCacheKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)
    $clean = [regex]::Replace($Value, '[^A-Za-z0-9._-]', '_')
    if ($clean.Length -gt 80) { $clean = $clean.Substring(0, 80) }
    return $clean
}

function Invoke-LlvmHttpGetJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3
    )

    Set-LlvmTls12
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'llvmup'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
            $nextUrl = $null
            if ($resp.Headers -and $resp.Headers['Link']) {
                $linkHeader = @($resp.Headers['Link']) -join ','
                if ($linkHeader -match '<([^>]+)>;\s*rel="next"') {
                    $nextUrl = $matches[1]
                }
            }
            $data = $resp.Content | ConvertFrom-Json
            return [pscustomobject]@{
                Data = $data
                NextUrl = $nextUrl
            }
        } catch {
            if ($attempt -ge $MaxRetries) {
                # Never include Authorization token in errors
                throw "GitHub API request failed ($Url): $($_.Exception.Message)"
            }
            $waitSec = [Math]::Pow(2, $attempt - 1)
            Start-Sleep -Seconds $waitSec
            $attempt++
        }
    }
}

function Invoke-LlvmProviderReleases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$ApiUrl,
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3,
        [int]$MaxPages = 5,
        [switch]$TestMode
    )

    $providerEnvKey = 'LLVMUP_' + ($Provider.ToUpperInvariant() -replace '[^A-Z0-9]', '_') + '_RELEASES_FILE'
    $providerFixture = [Environment]::GetEnvironmentVariable($providerEnvKey, 'Process')
    if ($providerFixture) {
        if (-not (Test-Path -LiteralPath $providerFixture -PathType Leaf)) {
            throw "$providerEnvKey does not exist: $providerFixture"
        }
        return @((Get-Content -LiteralPath $providerFixture -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
    }

    if ($Provider -eq 'official' -and $env:LLVMUP_RELEASES_FILE) {
        if (-not (Test-Path -LiteralPath $env:LLVMUP_RELEASES_FILE -PathType Leaf)) {
            throw "LLVMUP_RELEASES_FILE does not exist: $($env:LLVMUP_RELEASES_FILE)"
        }
        return @((Get-Content -LiteralPath $env:LLVMUP_RELEASES_FILE -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
    }

    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if ($Provider -eq 'official' -and ($TestMode -or $env:LLVM_TEST_MODE -eq '1')) {
        $cacheFile = Join-Path $repoRoot 'githubreleases.json'
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            return @((Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json))
        }
    }

    $allReleases = @()
    $sep = if ($ApiUrl -match '\?') { '&' } else { '?' }
    $nextUrl = "${ApiUrl}${sep}per_page=100"
    $page = 1
    try {
        while ($nextUrl -and $page -le $MaxPages) {
            $result = Invoke-LlvmHttpGetJson -Url $nextUrl -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
            if ($result.Data) {
                $allReleases += @($result.Data)
            }
            $nextUrl = $result.NextUrl
            $page++
        }
        return $allReleases
    } catch {
        if ($Provider -eq 'official') {
            $fallback = Join-Path $repoRoot 'githubreleases.json'
            if (Test-Path -LiteralPath $fallback -PathType Leaf) {
                Write-Warning "GitHub API unavailable ($($_.Exception.Message)); falling back to bundled githubreleases.json."
                return @((Get-Content -LiteralPath $fallback -Raw | ConvertFrom-Json))
            }
        }
        throw
    }
}

function Invoke-LlvmDownloadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [int]$TimeoutSec = 120,
        [int]$MaxRetries = 3,
        [string]$ExpectedSha256 = '',
        [switch]$Quiet
    )

    if ($Url -match '^file://') {
        if ($env:LLVMUP_ALLOW_FILE_URLS -ne '1') {
            throw "Refusing unsupported download scheme: $Url"
        }
        $localSrc = ([Uri]$Url).LocalPath
        if (-not (Test-Path -LiteralPath $localSrc -PathType Leaf)) {
            throw "Local file download source not found: $localSrc"
        }
        $parent = Split-Path $DestinationPath -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }
        Copy-Item -LiteralPath $localSrc -Destination $DestinationPath -Force
        if ($ExpectedSha256) {
            $expected = $ExpectedSha256.ToLowerInvariant() -replace '^sha256:', ''
            $actual = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
                throw "Checksum mismatch while downloading $Url (expected $expected, got $actual)"
            }
        }
        return $DestinationPath
    }

    if (-not ($Url -match '^https?://')) {
        throw "Refusing unsupported download scheme: $Url"
    }

    $parent = Split-Path $DestinationPath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    $attempt = 1
    while ($attempt -le $MaxRetries) {
        $partPath = "$DestinationPath.part-$([guid]::NewGuid().ToString('N'))"
        try {
            Set-LlvmTls12
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Timeout = $TimeoutSec * 1000
            $request.ReadWriteTimeout = $TimeoutSec * 1000
            $request.AllowAutoRedirect = $true
            $request.MaximumAutomaticRedirections = 10
            $request.UserAgent = 'llvmup'
            $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
            if ($token -and $Url -match '^https://(api\.github\.com|github\.com)/') {
                $request.Headers['Authorization'] = "Bearer $token"
            }

            $response = $request.GetResponse()
            try {
                $totalBytes = $response.ContentLength
                $stream = $response.GetResponseStream()
                $fileStream = [System.IO.File]::Create($partPath)
                try {
                    $buffer = New-Object byte[] 65536
                    [long]$downloaded = 0
                    $lastPercent = -1
                    while ($true) {
                        $read = $stream.Read($buffer, 0, $buffer.Length)
                        if ($read -le 0) { break }
                        $fileStream.Write($buffer, 0, $read)
                        $downloaded += $read
                        if (-not $Quiet -and $totalBytes -gt 0) {
                            $pct = [int](($downloaded * 100) / $totalBytes)
                            if ($pct -ge ($lastPercent + 20)) {
                                $lastPercent = $pct
                                Write-Host ("  downloaded {0}% ({1} / {2} MiB)" -f $pct, [Math]::Round($downloaded / 1MB, 1), [Math]::Round($totalBytes / 1MB, 1)) -ForegroundColor Gray
                            }
                        }
                    }
                } finally {
                    $fileStream.Dispose()
                    $stream.Dispose()
                }
            } finally {
                $response.Dispose()
            }

            if (-not (Test-Path -LiteralPath $partPath -PathType Leaf) -or (Get-Item -LiteralPath $partPath).Length -eq 0) {
                throw "Downloaded file is missing or empty"
            }

            if ($ExpectedSha256) {
                $expected = $ExpectedSha256.ToLowerInvariant() -replace '^sha256:', ''
                $actual = (Get-FileHash -LiteralPath $partPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actual -ne $expected) {
                    throw "SHA256 digest mismatch. Expected: $expected, Actual: $actual"
                }
            }

            if (Test-Path -LiteralPath $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Force
            }
            Move-Item -LiteralPath $partPath -Destination $DestinationPath -Force
            return $DestinationPath
        } catch {
            if (Test-Path -LiteralPath $partPath) {
                Remove-Item -LiteralPath $partPath -Force -ErrorAction SilentlyContinue
            }
            if ($attempt -ge $MaxRetries) {
                throw "Failed to download after $MaxRetries attempts ($Url): $($_.Exception.Message)"
            }
            $waitSec = [Math]::Pow(2, $attempt - 1) * 2
            Start-Sleep -Seconds $waitSec
            $attempt++
        }
    }
}

function Get-LlvmCachedOrDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$AssetDigest = '',
        [string]$AssetId = '',
        [string]$CacheDir = '',
        [string]$WorkDir = '',
        [int]$TimeoutSec = 120,
        [int]$MaxRetries = 3,
        [switch]$NoCache,
        [switch]$Quiet
    )

    if (-not $CacheDir) { $CacheDir = Get-LlvmDownloadCacheDir }
    $cacheKeyRaw = if ($AssetDigest) { $AssetDigest } elseif ($AssetId) { "id-$AssetId" } else { $AssetName }
    $cacheKey = Get-LlvmSafeCacheKey -Value $cacheKeyRaw

    if (-not $NoCache -and $env:LLVMUP_NO_CACHE -ne '1') {
        $entryDir = Join-Path (Join-Path $CacheDir $Provider) $cacheKey
        $cachedFile = Join-Path $entryDir $AssetName
        if (Test-Path -LiteralPath $cachedFile -PathType Leaf) {
            $cacheValid = $true
            if ($AssetDigest -and $AssetDigest -match '^(sha256:)?([0-9a-fA-F]{64})$') {
                $expected = $matches[2].ToLowerInvariant()
                $actual = (Get-FileHash -LiteralPath $cachedFile -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actual -ne $expected) {
                    $cacheValid = $false
                    Remove-Item -LiteralPath $cachedFile -Force -ErrorAction SilentlyContinue
                }
            }
            if ($cacheValid) {
                return [pscustomobject][ordered]@{
                    path = $cachedFile
                    cache_hit = $true
                }
            }
        }
        $dest = $cachedFile
    } else {
        if (-not $WorkDir) { $WorkDir = [IO.Path]::GetTempPath() }
        $dest = Join-Path $WorkDir $AssetName
    }

    $downloaded = Invoke-LlvmDownloadFile -Url $Url -DestinationPath $dest -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -ExpectedSha256 $AssetDigest -Quiet:$Quiet
    return [pscustomobject][ordered]@{
        path = $downloaded
        cache_hit = $false
    }
}

function Enter-LlvmToolchainLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ToolchainsPath,
        [Parameter(Mandatory = $true)][string]$InstallName
    )
    if (-not (Test-Path -LiteralPath $ToolchainsPath)) {
        $null = New-Item -ItemType Directory -Path $ToolchainsPath -Force
    }
    $lockPath = Join-Path $ToolchainsPath ".$InstallName.llvmup.lock"
    try {
        $stream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.Encoding]::UTF8.GetBytes("pid=$PID`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        return [pscustomobject]@{
            LockPath = $lockPath
            Stream = $stream
        }
    } catch {
        throw "Another llvmup operation is currently installing or modifying '$InstallName' ($lockPath)."
    }
}

function Exit-LlvmToolchainLock {
    [CmdletBinding()]
    param($LockHandle)
    if (-not $LockHandle) { return }
    try {
        if ($LockHandle.Stream) { $LockHandle.Stream.Dispose() }
    } catch {}
    if ($LockHandle.LockPath -and (Test-Path -LiteralPath $LockHandle.LockPath)) {
        Remove-Item -LiteralPath $LockHandle.LockPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function @(
    'Set-LlvmTls12',
    'Get-LlvmDownloadCacheDir',
    'Invoke-LlvmProviderReleases',
    'Invoke-LlvmDownloadFile',
    'Get-LlvmCachedOrDownload',
    'Enter-LlvmToolchainLock',
    'Exit-LlvmToolchainLock'
)
