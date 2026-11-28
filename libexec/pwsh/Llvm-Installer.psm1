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
    if (-not $ResolveOnly -and $hostOs -ne (Normalize-LlvmHostOs)) {
        throw "Cannot install a toolchain for host '$hostOs' on $(Normalize-LlvmHostOs). Use 'llvmup resolve --platform' to inspect it."
    }

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
            if ($selection.selective -and $Extractor -ne 'auto') {
                throw 'Selective installation uses the selection engine. Omit --extractor.'
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
        if ($LockedEntry.canonical_id -and $plan.canonical_id -cne $LockedEntry.canonical_id) {
            throw "Locked toolchain identity differs from the resolved identity '$($plan.canonical_id)'."
        }
        if ($la.id -and [string]$plan.asset.id -cne [string]$la.id) {
            throw "Locked asset ID differs from the upstream asset ID."
        }
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

    if ($env:LLVMUP_EXPECTED_ASSET_JSON) {
        $expected = ConvertFrom-Json -InputObject $env:LLVMUP_EXPECTED_ASSET_JSON -ErrorAction Stop
        if ($plan.canonical_id -cne $expected.canonical_id -or $plan.release_tag -cne $expected.release -or
            $plan.asset.name -cne $expected.asset_name -or [string]$plan.asset.id -cne [string]$expected.asset_id -or
            [string]$plan.asset.digest -cne [string]$expected.asset_digest) {
            throw 'Resolved asset changed since the installation was planned.'
        }
    }

    $installName = if ($Name) { $Name } else { $plan.canonical_id }
    if ($installName -match '[<>:"/\\|?*\x00-\x1f]' -or $installName -match '[. ]$' -or
        $installName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' -or
        $installName -match '\.(installing|backup)-(?:[0-9a-f]{8}|[0-9a-f]{32})(?:\.(raw|tarstage)-[0-9a-f]+)?$') {
        throw "Invalid installation name: $installName"
    }
    $installPath = Join-Path $ToolchainsPath $installName
    $null = New-Item -ItemType Directory -Path $ToolchainsPath -Force
    if (-not $Quiet) {
        foreach ($w in @(Get-LlvmRecipePathConstraintWarnings -Provider $effProvider -RootPath $installPath)) { Write-Warning $w }
    }

    $lockHandle = Enter-LlvmToolchainLock -ToolchainsPath $ToolchainsPath -InstallName $installName
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-op-' + [guid]::NewGuid().ToString('N'))
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $stagingPath = "$installPath.installing-$suffix"
    $backupPath = "$installPath.backup-$suffix"
    $published = $false

    try {
        if ((Test-Path -LiteralPath $installPath) -and -not $Force) {
            $existingManifest = Read-LlvmToolchainManifest -Root $installPath -InstallName $installName
            if (-not $existingManifest -or -not $existingManifest.capabilities -or $existingManifest.capabilities.compilers.Count -eq 0) {
                throw "Incomplete toolchain already exists at $installPath. Remove it or pass --force."
            }
            if ($existingManifest.id -and $plan.canonical_id -and ([string]$existingManifest.id -ne [string]$plan.canonical_id)) {
                $arg = Format-LlvmCommandArgument $Selector
                $rows = @(
                    @('Provider', $existingManifest.provider, $plan.provider),
                    @('Release', $existingManifest.provider_release, $plan.release_tag),
                    @('LLVM', $existingManifest.llvm_version, $plan.llvm_version),
                    @('GCC', $existingManifest.gcc_version, $plan.gcc_version),
                    @('OS', $existingManifest.host.os, $plan.host.os),
                    @('Architecture', $existingManifest.host.arch, $plan.host.arch),
                    @('CRT', $existingManifest.variant.crt, $plan.variant.crt),
                    @('Threads', $existingManifest.variant.threads, $plan.variant.threads),
                    @('Exceptions', $existingManifest.variant.exceptions, $plan.variant.exceptions),
                    @('C++ library', $existingManifest.variant.cxx_stdlib, $plan.variant.cxx_stdlib),
                    @('Profile', $existingManifest.variant.profile, $plan.variant.profile),
                    @('Asset', $existingManifest.asset.name, $plan.asset.name)
                ) | Where-Object { [string]$_[1] -ne [string]$_[2] }
                if (-not $rows -or @($rows).Count -eq 0) {
                    $rows = @(@('Identity', $existingManifest.id, $plan.canonical_id))
                }
                $have = ($rows | ForEach-Object { "  $($_[0]): $(if ([string]$_[1]) { $_[1] } else { '-' })" }) -join "`n"
                $want = ($rows | ForEach-Object { "  $($_[0]): $(if ([string]$_[2]) { $_[2] } else { '-' })" }) -join "`n"
                throw ("Installation name '$installName' is already in use.`n`nExisting installation:`n$have`n`nRequested installation:`n$want`n`n" +
                    "Choose a different name:`n  llvmup install $arg --name <new-name>`n`n" +
                    "To replace the existing installation explicitly, add --force. This deletes it first.`nThe existing installation was not modified.")
            }
            Assert-LlvmManagedAsset -Manifest $existingManifest -Expected @{
                canonical_id = $plan.canonical_id
                provider = $plan.provider
                release = $plan.release_tag
                host = $plan.host
                asset = $plan.asset
            } -Policy $policy
            if ($effProvider -eq 'official' -and $selection) {
                Invoke-LlvmSelection -Operation check -Root $installPath -Selection $selection
            }
            if (-not $Quiet) {
                Write-Host "$installName is already installed and validated ($installPath). Reusing it." -ForegroundColor Cyan
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
            Write-Host "Resolving $Selector..." -ForegroundColor Cyan
            $summary = [ordered]@{
                'Provider' = $plan.provider; 'Release' = $plan.release_tag; 'LLVM' = $plan.llvm_version
                'GCC' = $plan.gcc_version; 'Architecture' = $plan.host.arch; 'CRT' = $plan.variant.crt
                'Threads' = $plan.variant.threads; 'Exceptions' = $plan.variant.exceptions
                'C++ library' = $plan.variant.cxx_stdlib
                'Profile' = $(if ($plan.variant.profile -and $plan.variant.profile -ne 'full') { $plan.variant.profile } else { $null })
                'Asset' = $plan.asset.name; 'Name' = $installName; 'Directory' = $installPath
            }
            foreach ($k in $summary.Keys) {
                $v = [string]$summary[$k]
                if (-not $v -or $v -eq 'system' -or $v -eq 'unknown') { continue }
                Write-Host ("  {0,-14}{1}" -f ($k + ':'), $v)
            }
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
            -Quiet:$Quiet `
            -DeferOriginNotice:(-not $Quiet)

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

        $discovered = Test-LlvmRecipeStagingValid -Plan $plan -StagingRoot $stagingPath

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
            -Discovered $discovered `
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
            $vr = $verifyResult
            $algo = if ($vr.checksum_algorithm) { ([string]$vr.checksum_algorithm).ToUpperInvariant() -replace '^SHA', 'SHA-' } else { '' }
            Write-Host $(if ($vr.checksum -eq 'valid') { "Integrity: Verified ($algo)" } else { 'Integrity: Not verified' })
            if ($vr.gpg -eq 'valid') { Write-Host 'Authenticity: Verified (GPG)' }
            elseif ($vr.attestation -eq 'valid') { Write-Host 'Authenticity: Verified (GitHub/Sigstore attestation)' }
            elseif ($vr.authenticode -eq 'valid' -or ($vr.methods -contains 'authenticode')) { Write-Host 'Authenticity: Verified (Authenticode)' }
            elseif ($vr.policy -eq 'skip') { Write-Host 'Verification: Skipped by user request' }
            elseif ($vr.gpg -eq 'unavailable' -or $vr.attestation -eq 'unavailable') { Write-Host 'Authenticity: Verification tool or data unavailable' }
            else { Write-Host 'Authenticity: Not provided by upstream' }
            Write-Host "Installed $installName successfully." -ForegroundColor Green
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
