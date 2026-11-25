# Unified recipe-driven prebuilt resolution, download, verification, extraction, staging, and publishing.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}
foreach ($modName in @('Llvm-Manifest.psm1', 'Llvm-Recipes.psm1', 'Llvm-Resolver.psm1', 'Llvm-Downloader.psm1', 'Llvm-Verifier.psm1', 'Llvm-Extractor.psm1')) {
    $modBase = [IO.Path]::GetFileNameWithoutExtension($modName)
    $modPath = Join-Path $PSScriptRoot $modName
    if ((Test-Path -LiteralPath $modPath) -and -not (Get-Module -Name $modBase)) {
        Import-Module $modPath -DisableNameChecking
    }
}

function Invoke-LlvmInstallPrebuiltFromRecipe {
    [CmdletBinding()]
    param(
        [string]$Selector = 'latest',
        [string]$Provider = '',
        [string]$ReleaseTag = '',
        [string]$Platform = '',
        [string]$Arch = '',
        [string]$Crt = '',
        [string]$Threads = '',
        [string]$Target = '',
        [string]$Compiler = '',
        [string]$Name = '',
        [string]$Profile = '',
        [string[]]$Components = @(),
        [switch]$Strip,
        [string]$Extractor = 'auto',
        [string]$VerifyPolicy = '',
        [switch]$SkipVerify,
        [string]$ReleaseKeysPath = '',
        [switch]$ArchiveOnly,
        [switch]$Force,
        [switch]$NoCache,
        [switch]$TestMode,
        [switch]$ResolveOnly,
        [int]$TimeoutSec = 120,
        [int]$MaxRetries = 3,
        [string]$ToolchainsPath = '',
        [string]$HomePath = '',
        $LockedEntry = $null,
        [switch]$Quiet,
        [switch]$VerboseMode
    )

    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    if (-not $ToolchainsPath) { $ToolchainsPath = Get-LlvmSessionToolchainsPath }

    $split = Split-LlvmSelector -Selector $Selector -ExplicitProvider $Provider
    $effProvider = if ($split.provider) { $split.provider } else { 'official' }
    $effExpr = if ($split.expression) { $split.expression } else { 'latest' }
    $policy = Resolve-LlvmVerifyPolicy -RequestedPolicy $VerifyPolicy -SkipVerify:$SkipVerify
    if ($LockedEntry -and $LockedEntry.verify_policy) {
        # Locked mode never weakens the verification policy recorded in the lockfile.
        $rank = @{ skip = 0; warn = 1; strict = 2 }
        $lockedPolicy = ([string]$LockedEntry.verify_policy).ToLowerInvariant()
        if ($rank.ContainsKey($lockedPolicy) -and $rank[$policy] -lt $rank[$lockedPolicy]) {
            throw "Verification policy '$policy' is weaker than the locked policy '$lockedPolicy'."
        }
    }

    $recipe = Get-LlvmRecipe -Provider $effProvider
    $hostOs = Normalize-LlvmHostOs -Platform $Platform
    $hostArch = Normalize-LlvmHostArch -Arch $Arch

    $selectionModule = Join-Path (Split-Path $PSScriptRoot -Parent) 'Llvm-Selection.psm1'
    Import-Module $selectionModule -Force -DisableNameChecking
    $effProfile = if ($Profile) { $Profile } else { '' }
    $selection = $null
    if ($effProvider -eq 'official') {
        if (-not $ResolveOnly) {
            $selection = Get-LlvmSelection -Profile $effProfile -Components $Components -Strip:$Strip
            if ($selection.selective -and $hostOs -notin @('linux', 'windows')) {
                throw 'Selective installation supports Linux and Windows'
            }
            if ($Strip -and $hostOs -ne 'linux') {
                throw 'Strip is supported only for Linux ELF executables'
            }
            if ($selection.selective) { $ArchiveOnly = $true }
        }
    } else {
        if ($effProfile -and $effProfile -ne 'full') {
            throw "Provider '$effProvider' currently supports only the 'full' profile (requested '$effProfile')."
        }
        if ($Components -and $Components.Count -gt 0) {
            throw "Provider '$effProvider' does not support selective --component filtering; omit --component to install the full distribution."
        }
        if ($Strip) {
            throw '--strip is supported only for official Linux ELF builds.'
        }
    }

    $releases = Invoke-LlvmProviderReleases -Provider $effProvider -ApiUrl $recipe.api_url -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -TestMode:$TestMode
    if (-not $releases -or $releases.Count -eq 0) {
        throw "No releases returned for provider '$effProvider'."
    }

    $plan = Resolve-LlvmRecipeInstallPlan `
        -Provider $effProvider `
        -Releases $releases `
        -VersionExpression $effExpr `
        -ReleaseTag $ReleaseTag `
        -Platform $hostOs `
        -Arch $hostArch `
        -Crt $Crt `
        -Threads $Threads `
        -Target $Target `
        -Compiler $Compiler `
        -Profile $(if ($effProfile) { $effProfile } else { 'full' }) `
        -Extractor $Extractor `
        -PreferInstaller:(-not $ArchiveOnly -and $effProvider -eq 'official' -and -not ($selection -and $selection.selective)) `
        -ArchiveOnly:$ArchiveOnly

    if ($LockedEntry) {
        # Enforce the lock before any download: same provider, release, asset name and digest.
        $la = $LockedEntry.asset
        if ($LockedEntry.provider -and $plan.provider -ne $LockedEntry.provider) {
            throw "Locked provider '$($LockedEntry.provider)' differs from resolved provider '$($plan.provider)'."
        }
        if ($LockedEntry.release -and $plan.release_tag -ne $LockedEntry.release) {
            throw "Locked release '$($LockedEntry.release)' differs from resolved release '$($plan.release_tag)'."
        }
        if ($la -and $la.name -and $plan.asset.name -ne $la.name) {
            throw "Locked asset '$($la.name)' differs from resolved asset '$($plan.asset.name)'. Update the lockfile with 'llvmup config lock'."
        }
        if ($la -and $la.digest) {
            if ($plan.asset.digest -and $plan.asset.digest -ne $la.digest) {
                throw "Locked digest $($la.digest) differs from the upstream digest $($plan.asset.digest) for '$($plan.asset.name)'."
            }
            # Pin the download to the locked digest even if upstream metadata no longer publishes one.
            $plan.asset.digest = [string]$la.digest
        }
    }

    if ($ResolveOnly) {
        return [ordered]@{
            provider = $plan.provider
            release = $plan.release_tag
            version = $plan.release_tag
            llvm_version = $plan.llvm_version
            gcc_version = $plan.gcc_version
            mingw_version = $plan.mingw_version
            canonical_id = $plan.canonical_id
            asset_name = $plan.asset.name
            asset_url = $plan.asset.url
            asset_digest = $plan.asset.digest
            asset_id = $plan.asset.id
            signature_url = if ($plan.verification_assets.sig) { [string]$plan.verification_assets.sig.browser_download_url } else { '' }
            checksum_url = if ($plan.verification_assets.sha256) { [string]$plan.verification_assets.sha256.browser_download_url } elseif ($plan.verification_assets.sha512) { [string]$plan.verification_assets.sha512.browser_download_url } else { '' }
            attestation_url = if ($plan.verification_assets.jsonl) { [string]$plan.verification_assets.jsonl.browser_download_url } else { '' }
            platform = $plan.host.os
            architecture = $plan.host.arch
            crt = $plan.variant.crt
            target = $plan.default_target
        }
    }

    $installName = if ($Name) { $Name } else { $plan.canonical_id }
    if ($installName -in @('.', '..') -or $installName.Contains('/') -or $installName.Contains('\')) {
        throw "Invalid installation name: $installName"
    }
    $installPath = Join-Path $ToolchainsPath $installName
    $null = New-Item -ItemType Directory -Path $ToolchainsPath -Force

    $lockHandle = Enter-LlvmToolchainLock -ToolchainsPath $ToolchainsPath -InstallName $installName
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-op-' + [guid]::NewGuid().ToString('N'))
    $stagingPath = "$installPath.installing-$([guid]::NewGuid().ToString('N'))"
    $backupPath = "$installPath.backup-$([guid]::NewGuid().ToString('N'))"
    $published = $false

    try {
        if ((Test-Path -LiteralPath $installPath) -and -not $Force) {
            $existingManifest = Read-LlvmToolchainManifest -Root $installPath -InstallName $installName
            if (-not $existingManifest -or -not $existingManifest.capabilities -or $existingManifest.capabilities.compilers.Count -eq 0) {
                throw "Incomplete toolchain already exists at $installPath. Remove it or pass --force."
            }
            if ($effProvider -eq 'official' -and $selection) {
                Invoke-LlvmSelection -Operation check -Root $installPath -Selection $selection
            }
            if ($policy -eq 'strict') {
                $verFile = Join-Path $installPath '.llvmup-verification.json'
                if (-not (Test-Path -LiteralPath $verFile)) {
                    throw 'Strict verification cannot trust the existing toolchain: verification record is missing.'
                }
                $verRec = Get-Content -LiteralPath $verFile -Raw | ConvertFrom-Json
                if ($verRec.gpg -ne 'valid' -and $verRec.attestation -ne 'valid') {
                    throw 'Strict verification cannot trust the existing toolchain: no authenticated origin is recorded.'
                }
            }
            if (-not $Quiet) {
                Write-Host "[INFO] Toolchain '$installName' is already installed at $installPath" -ForegroundColor Cyan
            }
            return [pscustomobject][ordered]@{
                install_name = $installName
                install_path = $installPath
                manifest = $existingManifest
                plan = $plan
                already_installed = $true
                cache_hit = $false
            }
        }

        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        if (-not $Quiet) {
            Write-Host "[INFO] Installing $($plan.provider) ($($plan.release_tag), LLVM $($plan.llvm_version)) -> $installName" -ForegroundColor Cyan
        }

        $dlResult = Get-LlvmCachedOrDownload `
            -Provider $plan.provider `
            -AssetName $plan.asset.name `
            -Url $plan.asset.url `
            -AssetDigest $plan.asset.digest `
            -AssetId $plan.asset.id `
            -CacheDir (Get-LlvmDownloadCacheDir -HomePath $HomePath) `
            -WorkDir $tempRoot `
            -TimeoutSec $TimeoutSec `
            -MaxRetries $MaxRetries `
            -NoCache:$NoCache `
            -Quiet:$Quiet

        $verifyResult = Invoke-LlvmAssetVerify `
            -ArtifactPath $dlResult.path `
            -Plan $plan `
            -TempPath $tempRoot `
            -Policy $policy `
            -ReleaseKeysPath $ReleaseKeysPath `
            -TimeoutSec $TimeoutSec `
            -MaxRetries $MaxRetries `
            -Quiet:$Quiet

        $extractInfo = $null
        if ($effProvider -eq 'official' -and $selection -and $selection.selective) {
            Invoke-LlvmSelection -Operation extract -Root $stagingPath -Archive $dlResult.path -Selection $selection
            Invoke-LlvmSelection -Operation finalize -Root $stagingPath -Selection $selection
        } else {
            $expectedTop = if ($plan.recipe.layout -and $plan.recipe.layout.expected_top_dirs) { @($plan.recipe.layout.expected_top_dirs) } else { @() }
            $extractInfo = Invoke-LlvmArchiveExtract `
                -ArchivePath $dlResult.path `
                -DestinationPath $stagingPath `
                -Extractor $Extractor `
                -ExpectedTopDirs $expectedTop `
                -UnwrapSingleRoot
            $null = Invoke-LlvmRecipeFinalize -Plan $plan -StagingRoot $stagingPath
            if ($effProvider -eq 'official') {
                Invoke-LlvmSelection -Operation finalize -Root $stagingPath -Selection (Get-LlvmSelection)
            }
        }

        $null = Test-LlvmRecipeStagingValid -Plan $plan -StagingRoot $stagingPath

        # Write compatible verification marker + rich versioned toolchain manifest
        $legacyVer = [ordered]@{
            schema = 1
            version = $plan.release_tag
            provider = $plan.provider
            asset_name = $plan.asset.name
            asset_digest = $plan.asset.digest
            policy = $verifyResult.policy
            checksum = $verifyResult.checksum
            gpg = $verifyResult.gpg
            attestation = $verifyResult.attestation
            methods = ($verifyResult.methods -join '+')
            gpg_fingerprint = $verifyResult.gpg_fingerprint
            authenticated_identity = $verifyResult.authenticated_identity
        }
        Write-LlvmJsonFile -Path (Join-Path $stagingPath '.llvmup-verification.json') -Data $legacyVer -Depth 6

        $manifest = New-LlvmToolchainManifest `
            -Id $plan.canonical_id `
            -InstallName $installName `
            -Provider $plan.provider `
            -Origin 'managed' `
            -ProviderRelease $plan.release_tag `
            -ProviderRevision $plan.revision `
            -LlvmVersion $plan.llvm_version `
            -GccVersion $plan.gcc_version `
            -MingwVersion $plan.mingw_version `
            -HostOs $plan.host.os `
            -HostArch $plan.host.arch `
            -SupportedTargets $plan.supported_targets `
            -DefaultTarget $plan.default_target `
            -Variant $plan.variant `
            -Root $stagingPath `
            -Asset $plan.asset `
            -Verification $verifyResult

        if ($extractInfo) {
            $manifest['installation'] = [ordered]@{
                extractor = [string]$extractInfo.extractor
                strategy = [string]$extractInfo.strategy
                extractor_version = [string]$extractInfo.extractor_version
                extract_seconds = $extractInfo.seconds
                cache_hit = [bool]$dlResult.cache_hit
            }
        }
        $null = Write-LlvmToolchainManifest -Root $stagingPath -Manifest $manifest

        # Atomic publish with rollback on replacement
        if (Test-Path -LiteralPath $installPath) {
            Move-Item -LiteralPath $installPath -Destination $backupPath -ErrorAction Stop
        }
        try {
            Move-Item -LiteralPath $stagingPath -Destination $installPath -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $backupPath) {
                Move-Item -LiteralPath $backupPath -Destination $installPath -ErrorAction Stop
            }
            throw
        }
        $published = $true
        $manifest['root_path'] = $installPath

        if (-not $Quiet) {
            Write-Host "[OK] Installed '$installName' at $installPath (verify=$($verifyResult.methods -join '+'))" -ForegroundColor Green
        }

        return [pscustomobject][ordered]@{
            install_name = $installName
            install_path = $installPath
            manifest = $manifest
            plan = $plan
            already_installed = $false
            cache_hit = $dlResult.cache_hit
        }
    } finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($published -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Exit-LlvmToolchainLock -LockHandle $lockHandle
    }
}

Export-ModuleMember -Function @(
    'Invoke-LlvmInstallPrebuiltFromRecipe'
)
