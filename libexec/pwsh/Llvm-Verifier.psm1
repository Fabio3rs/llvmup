# Integrity (SHA256/SHA512) and Origin Authentication (GPG, Sigstore, Authenticode) verification.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}
$script:DownloaderModule = Join-Path $PSScriptRoot 'Llvm-Downloader.psm1'
if ((Test-Path -LiteralPath $script:DownloaderModule) -and -not (Get-Module -Name 'Llvm-Downloader')) {
    Import-Module $script:DownloaderModule -DisableNameChecking
}

function Resolve-LlvmVerifyPolicy {
    [CmdletBinding()]
    param(
        [string]$RequestedPolicy = '',
        [switch]$SkipVerify
    )

    $policy = ''
    if ($RequestedPolicy) { $policy = $RequestedPolicy }
    elseif ($env:LLVMUP_VERIFY_POLICY) { $policy = $env:LLVMUP_VERIFY_POLICY }
    else {
        $legacySkip = $SkipVerify -or ($env:LLVMUP_SKIP_VERIFY -in @('1', 'true', 'TRUE'))
        $legacyReq = $env:LLVMUP_REQUIRE_VERIFY -in @('1', 'true', 'TRUE')
        if ($legacySkip -and $legacyReq) {
            throw 'LLVMUP_SKIP_VERIFY and LLVMUP_REQUIRE_VERIFY cannot both be enabled.'
        }
        if ($legacySkip) { $policy = 'skip' }
        elseif ($legacyReq) { $policy = 'strict' }
        else { $policy = 'warn' }
    }
    $policy = $policy.ToLowerInvariant()
    if ($policy -notin @('warn', 'strict', 'skip')) {
        throw "Invalid verification policy '$policy'. Expected warn, strict, or skip."
    }
    return $policy
}

function Find-LlvmChecksumDigestInText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [ValidateSet('SHA256', 'SHA512')]
        [string]$Algorithm = 'SHA256'
    )

    $hexLen = if ($Algorithm -eq 'SHA512') { 128 } else { 64 }
    $lines = @($Content -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $lines) {
        if ($line -match "^\s*([0-9a-fA-F]{$hexLen})\s+[\*\s]?(.+?)\s*$") {
            $hash = $matches[1].ToLowerInvariant()
            $fileRef = $matches[2].Trim()
            if ($fileRef -eq $AssetName -or [IO.Path]::GetFileName($fileRef) -eq $AssetName) {
                return $hash
            }
        }
    }
    if ($lines.Count -eq 1 -and $lines[0] -match "(?i)([0-9a-f]{$hexLen})") {
        return $matches[1].ToLowerInvariant()
    }
    return $null
}

function Test-LlvmAuthenticodePublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$AllowedPublishers = @()
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return [ordered]@{ status = 'unavailable'; subject = ''; scope = 'none' }
    }
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        return [ordered]@{ status = 'unavailable'; subject = ''; scope = 'none' }
    }
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $FilePath
        if ($sig.Status -eq 'NotSigned') {
            return [ordered]@{ status = 'not-provided'; subject = ''; scope = 'file' }
        }
        $subject = if ($sig.SignerCertificate) { [string]$sig.SignerCertificate.Subject } else { '' }
        if ($sig.Status -ne 'Valid') {
            return [ordered]@{ status = 'invalid'; subject = $subject; scope = 'file' }
        }
        if ($AllowedPublishers.Count -gt 0) {
            $matched = $false
            foreach ($pub in $AllowedPublishers) {
                if ($subject -like "*$pub*") { $matched = $true; break }
            }
            if (-not $matched) {
                return [ordered]@{ status = 'wrong-identity'; subject = $subject; scope = 'file' }
            }
        }
        return [ordered]@{ status = 'valid'; subject = $subject; scope = 'file' }
    } catch {
        return [ordered]@{ status = 'unavailable'; subject = ''; scope = 'file' }
    }
}

function Invoke-LlvmAssetVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$TempPath,
        [ValidateSet('warn', 'strict', 'skip')]
        [string]$Policy = 'warn',
        [string]$ReleaseKeysPath = '',
        [int]$TimeoutSec = 60,
        [int]$MaxRetries = 3,
        [switch]$Quiet
    )

    $assetName = [string]$Plan.asset.name
    $expectedDigest = if ($Plan.asset.digest) { [string]$Plan.asset.digest } else { '' }
    $sigAsset = $Plan.verification_assets.sig
    $jsonlAsset = $Plan.verification_assets.jsonl
    $sha256Asset = $Plan.verification_assets.sha256
    $sha512Asset = $Plan.verification_assets.sha512
    $gpgKeysUrl = if ($Plan.recipe.verification -and $Plan.recipe.verification.gpg_keys_url) { [string]$Plan.recipe.verification.gpg_keys_url } else { '' }
    $attestRepo = if ($Plan.recipe.verification -and $Plan.recipe.verification.attestation_repo) { [string]$Plan.recipe.verification.attestation_repo } else { '' }

    $result = [ordered]@{
        policy = $Policy
        provider = [string]$Plan.provider
        checksum = 'not-provided'
        checksum_algorithm = ''
        expected_digest = $expectedDigest
        actual_digest = ''
        gpg = if ($sigAsset) { 'unavailable' } else { 'not-provided' }
        gpg_fingerprint = ''
        attestation = if ($jsonlAsset) { 'unavailable' } else { 'not-provided' }
        authenticode = 'not-applicable'
        methods = @()
        authenticated_identity = $null
        scope = 'archive'
    }

    if ($Policy -eq 'skip') {
        $result.checksum = 'skipped'
        $result.gpg = 'skipped'
        $result.attestation = 'skipped'
        $result.methods = @('skipped')
        return $result
    }

    # 1. Integrity checks (SHA256 / SHA512)
    if ($expectedDigest -match '^(sha256:)?([0-9a-fA-F]{64})$') {
        $expectedHex = $matches[2].ToLowerInvariant()
        $actualHex = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.checksum_algorithm = 'sha256'
        $result.expected_digest = "sha256:$expectedHex"
        $result.actual_digest = "sha256:$actualHex"
        if ($actualHex -ne $expectedHex) {
            $result.checksum = 'invalid'
            throw "SHA256 digest mismatch for ${assetName}. Expected: $expectedHex, Actual: $actualHex"
        }
        $result.checksum = 'valid'
    } elseif ($sha256Asset) {
        $shaFile = Join-Path $TempPath $sha256Asset.name
        try {
            Invoke-LlvmDownloadFile -Url $sha256Asset.browser_download_url -DestinationPath $shaFile -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Quiet | Out-Null
            $raw = [IO.File]::ReadAllText($shaFile)
            $expectedHex = Find-LlvmChecksumDigestInText -Content $raw -AssetName $assetName -Algorithm SHA256
            if (-not $expectedHex) {
                $result.checksum = 'invalid'
                throw "Checksum file '$($sha256Asset.name)' does not contain a SHA256 digest for $assetName."
            }
            $actualHex = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $result.checksum_algorithm = 'sha256'
            $result.expected_digest = "sha256:$expectedHex"
            $result.actual_digest = "sha256:$actualHex"
            if ($actualHex -ne $expectedHex) {
                $result.checksum = 'invalid'
                throw "SHA256 checksum mismatch for ${assetName}. Expected: $expectedHex, Actual: $actualHex"
            }
            $result.checksum = 'valid'
        } catch {
            if ($result.checksum -eq 'invalid') { throw }
            $result.checksum = 'unavailable'
        }
    }

    if ($sha512Asset) {
        $sha512File = Join-Path $TempPath $sha512Asset.name
        try {
            Invoke-LlvmDownloadFile -Url $sha512Asset.browser_download_url -DestinationPath $sha512File -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Quiet | Out-Null
            $raw512 = [IO.File]::ReadAllText($sha512File)
            $expected512 = Find-LlvmChecksumDigestInText -Content $raw512 -AssetName $assetName -Algorithm SHA512
            if (-not $expected512) {
                $result.checksum = 'invalid'
                throw "Checksum file '$($sha512Asset.name)' does not contain a SHA512 digest for $assetName."
            }
            $actual512 = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA512).Hash.ToLowerInvariant()
            if ($actual512 -ne $expected512) {
                $result.checksum = 'invalid'
                throw "SHA512 checksum mismatch for ${assetName}. Expected: $expected512, Actual: $actual512"
            }
            if (-not $result.actual_digest) {
                $result.checksum_algorithm = 'sha512'
                $result.expected_digest = "sha512:$expected512"
                $result.actual_digest = "sha512:$actual512"
            }
            $result.checksum = 'valid'
        } catch {
            if ($result.checksum -eq 'invalid') { throw }
            if ($result.checksum -eq 'not-provided') { $result.checksum = 'unavailable' }
        }
    }

    # 2. GPG Origin Authentication (provider-scoped keys)
    if ($sigAsset -and ($gpgKeysUrl -or $ReleaseKeysPath -or $env:LLVMUP_RELEASE_KEYS_FILE)) {
        $gpg = Get-Command gpg -ErrorAction SilentlyContinue
        if ($gpg) {
            $sigPath = Join-Path $TempPath $sigAsset.name
            $keysPath = Join-Path $TempPath 'provider-release-keys.asc'
            $gpgOkToRun = $true
            try {
                Invoke-LlvmDownloadFile -Url $sigAsset.browser_download_url -DestinationPath $sigPath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Quiet | Out-Null
                $configuredKeys = if ($ReleaseKeysPath) { $ReleaseKeysPath } elseif ($env:LLVMUP_RELEASE_KEYS_FILE) { $env:LLVMUP_RELEASE_KEYS_FILE } else { $null }
                if ($configuredKeys) {
                    if (-not (Test-Path -LiteralPath $configuredKeys -PathType Leaf)) {
                        throw "Release keys file does not exist: $configuredKeys"
                    }
                    Copy-Item -LiteralPath $configuredKeys -Destination $keysPath -Force
                } else {
                    Invoke-LlvmDownloadFile -Url $gpgKeysUrl -DestinationPath $keysPath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Quiet | Out-Null
                }
            } catch {
                if ($_.Exception.Message -match 'does not exist') { throw }
                $result.gpg = 'unavailable'
                $gpgOkToRun = $false
            }

            if ($gpgOkToRun) {
                $gpgHome = Join-Path $TempPath 'gnupg'
                $null = New-Item -ItemType Directory -Path $gpgHome -Force
                $null = & $gpg.Source --batch --homedir $gpgHome --import $keysPath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $result.gpg = 'unavailable'
                } else {
                    $verifyOut = & $gpg.Source --batch --homedir $gpgHome --status-fd 1 --verify $sigPath $ArtifactPath 2>&1
                    $gpgExit = $LASTEXITCODE
                    $statusText = $verifyOut | Out-String
                    if ($gpgExit -eq 0 -and $statusText -match '\[GNUPG:\]\s+VALIDSIG\s+([0-9A-Fa-f]+)') {
                        $result.gpg = 'valid'
                        $result.gpg_fingerprint = $matches[1].ToUpperInvariant()
                        $result.methods += 'gpg'
                        $result.authenticated_identity = "gpg:$($result.gpg_fingerprint)"
                    } elseif ($statusText -match '\[GNUPG:\]\s+NO_PUBKEY\s+') {
                        $result.gpg = 'unavailable'
                    } else {
                        $result.gpg = 'invalid'
                        throw "GPG signature validation failed for $assetName (provider: $($Plan.provider))."
                    }
                }
            }
        }
    }

    # 3. GitHub / Sigstore Attestation (provider-scoped repository identity)
    if ($jsonlAsset -and $attestRepo) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if ($gh) {
            & $gh.Source attestation verify --help *> $null
            if ($LASTEXITCODE -eq 0) {
                $bundlePath = Join-Path $TempPath $jsonlAsset.name
                $dlOk = $true
                try {
                    Invoke-LlvmDownloadFile -Url $jsonlAsset.browser_download_url -DestinationPath $bundlePath -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Quiet | Out-Null
                } catch {
                    $result.attestation = 'unavailable'
                    $dlOk = $false
                }
                if ($dlOk) {
                    # Offer GITHUB_TOKEN to gh for this call only; never leave it behind in the session.
                    $setGhToken = (-not $env:GH_TOKEN -and $env:GITHUB_TOKEN)
                    if ($setGhToken) { $env:GH_TOKEN = $env:GITHUB_TOKEN }
                    try {
                        $attOut = & $gh.Source attestation verify $ArtifactPath --repo $attestRepo --bundle $bundlePath 2>&1
                        $attExit = $LASTEXITCODE
                    } finally {
                        if ($setGhToken) { Remove-Item -LiteralPath 'Env:GH_TOKEN' -ErrorAction SilentlyContinue }
                    }
                    if ($attExit -eq 0) {
                        $result.attestation = 'valid'
                        $result.methods += 'sigstore'
                        if (-not $result.authenticated_identity) {
                            $result.authenticated_identity = "github:$attestRepo"
                        }
                    } else {
                        $result.attestation = 'invalid'
                        $detail = ($attOut | Select-Object -First 5) -join "`n"
                        throw "GitHub/Sigstore attestation validation failed for $assetName against ${attestRepo}: $detail"
                    }
                }
            }
        }
    }

    # 4. Authenticode (Windows installers only). A valid signature authenticates only that file and
    #    only counts as origin authentication when the recipe pins the expected publisher identity.
    $fmt = if ($Plan.asset -and $Plan.asset.format) { [string]$Plan.asset.format } else { '' }
    if ($fmt -in @('exe', 'msi') -and (Test-LlvmIsWindows)) {
        $allowedPublishers = @()
        if ($Plan.recipe.verification -and $Plan.recipe.verification.authenticode_publishers) {
            $allowedPublishers = @($Plan.recipe.verification.authenticode_publishers)
        }
        $ac = Test-LlvmAuthenticodePublisher -FilePath $ArtifactPath -AllowedPublishers $allowedPublishers
        $result.authenticode = [string]$ac.status
        $result['authenticode_subject'] = [string]$ac.subject
        if ($ac.status -eq 'invalid' -or $ac.status -eq 'wrong-identity') {
            throw "Authenticode validation failed for ${assetName}: $($ac.status) (subject: $($ac.subject))."
        }
        if ($ac.status -eq 'valid' -and $allowedPublishers.Count -gt 0) {
            $result.methods += 'authenticode'
            if (-not $result.authenticated_identity) { $result.authenticated_identity = "authenticode:$($ac.subject)" }
            $result.scope = 'installer-file'
        } elseif ($ac.status -eq 'valid') {
            $result.authenticode = 'valid-unpinned'
        }
    }

    # 5. Policy enforcement
    $originOk = ($result.gpg -eq 'valid' -or $result.attestation -eq 'valid' -or $result.methods -contains 'authenticode')
    if (-not $originOk) {
        if ($Policy -eq 'strict') {
            if ($Plan.recipe.verification -and -not $Plan.recipe.verification.origin_authentication_available) {
                throw "Strict verification failed: provider '$($Plan.provider)' does not publish cryptographic origin signatures or attestations upstream (only checksums)."
            }
            throw "Strict verification requires a valid GPG signature or GitHub/Sigstore attestation for '$($Plan.provider)' ($attestRepo). Install gpg or gh, or use --verify warn."
        }
        if ($result.methods.Count -eq 0) {
            $result.methods = @(if ($result.checksum -eq 'valid') { 'checksum-only' } else { 'unverified' })
        }
        # Verification warnings are security-relevant: -Quiet silences progress, never these.
        if ($Policy -eq 'warn') {
            if ($result.checksum -eq 'valid') {
                Write-Warning "Integrity of $assetName verified ($($result.checksum_algorithm)), but its origin is not authenticated (gpg=$($result.gpg), attestation=$($result.attestation))."
            } else {
                Write-Warning "$assetName could not be verified: no digest, checksum, signature, or attestation was available (provider '$($Plan.provider)'). Use --verify strict to refuse unverified downloads."
            }
        }
    }

    return $result
}

Export-ModuleMember -Function @(
    'Resolve-LlvmVerifyPolicy',
    'Find-LlvmChecksumDigestInText',
    'Test-LlvmAuthenticodePublisher',
    'Invoke-LlvmAssetVerify'
)
