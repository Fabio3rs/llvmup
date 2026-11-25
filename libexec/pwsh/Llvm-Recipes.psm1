# Declarative recipe loader and provider-specific release/asset resolution, finalization, and validation.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}
$script:ManifestModule = Join-Path $PSScriptRoot 'Llvm-Manifest.psm1'
if ((Test-Path -LiteralPath $script:ManifestModule) -and -not (Get-Module -Name 'Llvm-Manifest')) {
    Import-Module $script:ManifestModule -DisableNameChecking
}
$script:ExtractorModule = Join-Path $PSScriptRoot 'Llvm-Extractor.psm1'
if ((Test-Path -LiteralPath $script:ExtractorModule) -and -not (Get-Module -Name 'Llvm-Extractor')) {
    Import-Module $script:ExtractorModule -DisableNameChecking
}

function Get-LlvmRecipesDirectory {
    return (Join-Path (Split-Path $PSScriptRoot -Parent) 'recipes')
}

function Get-LlvmProviderList {
    [CmdletBinding()]
    param()
    $dir = Get-LlvmRecipesDirectory
    $providers = @()
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object Name)) {
        $recipe = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        if ($recipe -and $recipe.provider) {
            $providers += $recipe
        }
    }
    return $providers
}

function Get-LlvmRecipe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Provider)

    $norm = $Provider.Trim().ToLowerInvariant()
    $path = Join-Path (Get-LlvmRecipesDirectory) "$norm.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $available = (@(Get-LlvmProviderList | ForEach-Object { $_.provider }) -join ', ')
        throw "Unknown provider '$Provider'. Available providers: $available"
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Normalize-LlvmHostOs {
    [CmdletBinding()]
    param([string]$Platform = '')
    if (-not $Platform) {
        if (Test-LlvmIsWindows) { return 'windows' }
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) { return 'linux' }
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { return 'macos' }
        throw 'Unsupported host OS'
    }
    switch ($Platform.ToLowerInvariant()) {
        'windows' { return 'windows' }
        'linux' { return 'linux' }
        'macos' { return 'macos' }
        'darwin' { return 'macos' }
        default { throw "Unsupported platform: $Platform" }
    }
}

function Normalize-LlvmHostArch {
    [CmdletBinding()]
    param([string]$Arch = '')
    if (-not $Arch) {
        $proc = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        switch ([string]$proc) {
            'X64' { return 'x64' }
            'X86' { return 'x86' }
            'Arm64' { return 'arm64' }
            'Arm' { return 'armv7a' }
            default { return 'x64' }
        }
    }
    switch ($Arch.ToLowerInvariant()) {
        { $_ -in @('x64', 'x86_64', 'amd64') } { return 'x64' }
        { $_ -in @('arm64', 'aarch64') } { return 'arm64' }
        { $_ -in @('armv7a', 'armv7', 'arm') } { return 'armv7a' }
        { $_ -in @('x86', 'i386', 'i686') } { return 'x86' }
        default { throw "Unsupported architecture: $Arch" }
    }
}

function Test-LlvmVersionSatisfies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidateVersion,
        [Parameter(Mandatory = $true)][string]$Expression
    )

    $expr = $Expression.Trim()
    if ($expr -in @('latest', 'newest', 'prebuilt')) { return $true }

    # Support partial versions like "23" or "23.1" cleanly
    if ($expr -match '^(\d+)$') {
        $maj = $matches[1]
        return ($CandidateVersion -match "^$maj\.")
    }
    if ($expr -match '^(\d+)\.(\d+)$') {
        $maj = $matches[1]; $min = $matches[2]
        return ($CandidateVersion -match "^$maj\.$min\.")
    }

    try {
        $matched = @(Invoke-LlvmMatchVersions -Expression $expr -CandidateVersions @($CandidateVersion))
        return ($matched.Count -gt 0)
    } catch {
        return $false
    }
}

function Get-LlvmVerificationAssetsFromRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Assets,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    $sig = $Assets | Where-Object { $_.name -eq "$AssetName.sig" } | Select-Object -First 1
    $jsonl = $Assets | Where-Object { $_.name -eq "$AssetName.jsonl" } | Select-Object -First 1
    $sha256 = $Assets | Where-Object {
        $_.name -in @("$AssetName.sha256", "$AssetName.sha256sum", "$AssetName.sha256.txt", "$AssetName.sha256sum.txt")
    } | Select-Object -First 1
    $sha512 = $Assets | Where-Object {
        $_.name -in @("$AssetName.sha512", "$AssetName.sha512sum", "$AssetName.sha512.txt")
    } | Select-Object -First 1

    return [ordered]@{
        sig = $sig
        jsonl = $jsonl
        sha256 = $sha256
        sha512 = $sha512
    }
}

function Select-LlvmOfficialAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Recipe,
        [Parameter(Mandatory = $true)][object[]]$Assets,
        [Parameter(Mandatory = $true)][string]$HostOs,
        [Parameter(Mandatory = $true)][string]$HostArch,
        [switch]$PreferInstaller,
        [switch]$ArchiveOnly,
        [string[]]$AvailableFormats = @()
    )

    $key = "${HostOs}:${HostArch}"
    $targetSpec = $Recipe.asset_rules.targets.$key
    if (-not $targetSpec) { return $null }

    $candidates = @()
    foreach ($asset in $Assets) {
        $name = [string]$asset.name
        if ($name -match '\.(sig|jsonl|sha256|sha512|sha256sum|txt)$') { continue }
        if ($name -match '(\.src\.|_doxygen|_man_pages|test-suite)') { continue }

        if (-not $ArchiveOnly -and $PreferInstaller -and $targetSpec.installer_patterns) {
            foreach ($rule in $targetSpec.installer_patterns) {
                if ($name -match $rule.pattern) {
                    $candidates += [pscustomobject]@{ Asset = $asset; Priority = ([int]$rule.priority + 20); Format = $rule.format }
                }
            }
        }
        if ($targetSpec.archive_patterns) {
            foreach ($rule in $targetSpec.archive_patterns) {
                if ($name -match $rule.pattern) {
                    $candidates += [pscustomobject]@{ Asset = $asset; Priority = [int]$rule.priority; Format = $rule.format }
                }
            }
        }
        if (-not $ArchiveOnly -and -not $PreferInstaller -and $targetSpec.installer_patterns) {
            foreach ($rule in $targetSpec.installer_patterns) {
                if ($name -match $rule.pattern) {
                    $candidates += [pscustomobject]@{ Asset = $asset; Priority = ([int]$rule.priority - 30); Format = $rule.format }
                }
            }
        }
    }

    if ($AvailableFormats.Count -gt 0) {
        # Never pick an asset this machine cannot unpack (e.g. .tar.zst without a zstd backend).
        $candidates = @($candidates | Where-Object { $AvailableFormats -contains $_.Format })
    }
    if ($candidates.Count -eq 0) { return $null }
    $best = $candidates | Sort-Object Priority -Descending | Select-Object -First 1
    $stdLib = if ($HostOs -eq 'windows') { 'msvc' } elseif ($HostOs -eq 'macos') { 'libc++' } else { 'libstdc++' }
    return [ordered]@{
        asset = $best.Asset
        format = $best.Format
        supported_targets = @($targetSpec.supported_targets)
        default_target = $targetSpec.supported_targets[0]
        variant = [ordered]@{
            crt = 'system'
            threads = 'system'
            exceptions = 'system'
            cxx_stdlib = $stdLib
            default_compiler = 'clang'
        }
    }
}

function Select-LlvmWinLibsAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Recipe,
        [Parameter(Mandatory = $true)][object[]]$Assets,
        [Parameter(Mandatory = $true)][string]$HostOs,
        [Parameter(Mandatory = $true)][string]$HostArch,
        [string]$Crt = 'ucrt',
        [string]$Threads = 'posix',
        [string]$Extractor = 'auto',
        [string[]]$AvailableFormats = @()
    )

    if ($HostOs -ne 'windows') { return $null }
    $archName = switch ($HostArch) {
        'x64' { 'x86_64' }
        'x86' { 'i686' }
        default { return $null }
    }
    $targetTriple = if ($HostArch -eq 'x64') { 'x86_64-w64-mingw32' } else { 'i686-w64-mingw32' }
    $reqCrt = if ($Crt) { $Crt.ToLowerInvariant() } else { 'ucrt' }
    $reqThreads = if ($Threads) { $Threads.ToLowerInvariant() } else { 'posix' }

    # .7z is less than half the size of the .zip; use it whenever a modern 7-Zip can unpack it.
    $formats = if ($AvailableFormats.Count -gt 0) { $AvailableFormats } else { @('zip', '7z') }
    $prefer7z = ($formats -contains '7z')

    $pattern = $Recipe.asset_rules.filename_pattern
    $candidates = @()
    foreach ($asset in $Assets) {
        $name = [string]$asset.name
        if ($name -match '\.(sha256|sha512|sig|jsonl|txt)$') { continue }
        if ($name -notmatch $pattern) { continue }

        $aArch = $matches[1]
        $aThreads = $matches[2]
        $aExceptions = $matches[3]
        $aGcc = $matches[4]
        $aLlvm = $matches[5]
        $aCrt = $matches[6]
        $aMingw = $matches[7]
        $aRev = [int]$matches[8]
        $aExt = $matches[9].ToLowerInvariant()

        if (-not $aLlvm) { continue } # Must include LLVM/Clang
        if ($aArch -ne $archName) { continue }
        if ($aCrt -ne $reqCrt) { continue }
        if ($aThreads -ne $reqThreads) { continue }
        if ($formats -notcontains $aExt) { continue }

        $fmtScore = if ($prefer7z) { if ($aExt -eq '7z') { 20 } else { 10 } } else { if ($aExt -eq 'zip') { 20 } else { 5 } }
        $candidates += [pscustomobject]@{
            Asset = $asset
            GccVersion = $aGcc
            LlvmVersion = $aLlvm
            MingwVersion = $aMingw
            Revision = $aRev
            Threads = $aThreads
            Exceptions = $aExceptions
            Crt = $aCrt
            Format = $aExt
            Score = $fmtScore
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    $best = $candidates | Sort-Object Score -Descending | Select-Object -First 1
    return [ordered]@{
        asset = $best.Asset
        format = $best.Format
        llvm_version = $best.LlvmVersion
        gcc_version = $best.GccVersion
        mingw_version = $best.MingwVersion
        revision = $best.Revision
        supported_targets = @($targetTriple)
        default_target = $targetTriple
        variant = [ordered]@{
            crt = $best.Crt
            threads = $best.Threads
            exceptions = $best.Exceptions
            cxx_stdlib = 'libstdc++'
            default_compiler = 'clang'
        }
    }
}

function Select-LlvmMinGWAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Recipe,
        [Parameter(Mandatory = $true)][object[]]$Assets,
        [Parameter(Mandatory = $true)][string]$HostOs,
        [Parameter(Mandatory = $true)][string]$HostArch,
        [string]$Crt = 'ucrt'
    )

    $key = "${HostOs}:${HostArch}"
    $pattern = $Recipe.asset_rules.host_patterns.$key
    if (-not $pattern) { return $null }

    $reqCrt = if ($Crt) { $Crt.ToLowerInvariant() } else { 'ucrt' }
    $matched = $null
    foreach ($asset in $Assets) {
        $name = [string]$asset.name
        if ($name -match '\.(sha256|sha512|sig|jsonl|txt)$') { continue }
        if ($name -match $pattern) {
            $aCrt = $matches[1].ToLowerInvariant()
            if ($aCrt -eq $reqCrt) {
                $matched = $asset
                break
            }
        }
    }
    if (-not $matched) { return $null }

    $defaultTarget = $Recipe.asset_rules.default_target_map.$HostArch
    if (-not $defaultTarget) { $defaultTarget = 'x86_64-w64-mingw32' }
    $fmt = if ($matched.name -match '\.tar\.xz$') { 'tar.xz' } elseif ($matched.name -match '\.zip$') { 'zip' } else { 'archive' }

    return [ordered]@{
        asset = $matched
        format = $fmt
        supported_targets = @($Recipe.asset_rules.multi_target_triples)
        default_target = $defaultTarget
        variant = [ordered]@{
            crt = $reqCrt
            threads = 'posix'
            exceptions = 'seh'
            cxx_stdlib = 'libc++'
            default_compiler = 'clang'
        }
    }
}

function Get-LlvmPlanFormats {
    # Formats eligible for asset selection. For the current host this is what the local backends can
    # unpack (narrowed by an explicit --extractor); for another host (e.g. writing a lockfile entry
    # for Linux from Windows) a portable baseline is used, since its extractors are unknown here.
    [CmdletBinding()]
    param(
        [string]$HostOs,
        [string]$HostArch,
        [string]$Extractor = 'auto'
    )
    if ($env:LLVMUP_ASSET_FORMATS) {
        return @($env:LLVMUP_ASSET_FORMATS -split '[,; ]+' | Where-Object { $_ })
    }
    $localOs = Normalize-LlvmHostOs
    if ($HostOs -and $HostOs -ne $localOs) {
        return @('tar.xz', 'tar.gz', 'tar', 'zip', '7z')
    }
    $formats = @(Get-LlvmExtractableFormats)
    $byExtractor = @{
        '7z' = @('7z', 'zip', 'tar.xz', 'tar.gz', 'tar', 'exe', 'tar.zst')
        'tar' = @('tar.xz', 'tar.gz', 'tar.zst', 'tar')
        'zip' = @('zip')
        'python' = @('tar.xz', 'tar.gz', 'tar.zst', 'tar', 'zip')
        'msi' = @('msi')
    }
    $ext = if ($Extractor) { $Extractor.ToLowerInvariant() } else { 'auto' }
    if ($byExtractor.ContainsKey($ext)) {
        $allowed = $byExtractor[$ext]
        $formats = @($formats | Where-Object { $allowed -contains $_ })
        if ($formats.Count -eq 0) { throw "Extractor '$ext' cannot unpack any archive format on this machine." }
    }
    return $formats
}

function Resolve-LlvmRecipeInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][object[]]$Releases,
        [string]$VersionExpression = 'latest',
        [string]$ReleaseTag = '',
        [string]$Platform = '',
        [string]$Arch = '',
        [string]$Crt = '',
        [string]$Threads = '',
        [string]$Target = '',
        [string]$Compiler = '',
        [string]$Profile = 'full',
        [string]$Extractor = 'auto',
        [switch]$PreferInstaller,
        [switch]$ArchiveOnly,
        [string[]]$AvailableFormats = @()
    )

    $recipe = Get-LlvmRecipe -Provider $Provider
    $hostOs = Normalize-LlvmHostOs -Platform $Platform
    $hostArch = Normalize-LlvmHostArch -Arch $Arch
    $flatReleases = @($Releases | ForEach-Object { $_ })
    if (-not $AvailableFormats -or $AvailableFormats.Count -eq 0) {
        $AvailableFormats = Get-LlvmPlanFormats -HostOs $hostOs -HostArch $hostArch -Extractor $Extractor
    }

    if ($Profile -and ($recipe.profiles -notcontains $Profile)) {
        $allowed = $recipe.profiles -join ', '
        throw "Provider '$Provider' does not support profile '$Profile'. Supported profiles: $allowed"
    }

    if ($Compiler -and ($recipe.available_compilers -notcontains $Compiler.ToLowerInvariant())) {
        $allowedC = $recipe.available_compilers -join ', '
        throw "Provider '$Provider' does not support compiler '$Compiler'. Available compilers: $allowedC"
    }

    $candidates = @()
    foreach ($rel in $flatReleases) {
        if ($rel.draft -or $rel.prerelease) { continue }
        $tag = [string]$rel.tag_name
        if (-not $tag) { continue }

        if ($ReleaseTag -and $tag -ne $ReleaseTag) { continue }
        if (-not $ReleaseTag -and $tag -notmatch $recipe.tag_rules.release_tag_pattern) { continue }

        $llvmVer = ''
        $gccVer = ''
        $mingwVer = ''
        $revNum = $null

        switch ($Provider) {
            'official' {
                if ($tag -match '^llvmorg-(\d+\.\d+\.\d+)$') { $llvmVer = $matches[1] }
                $picked = Select-LlvmOfficialAsset -Recipe $recipe -Assets @($rel.assets) -HostOs $hostOs -HostArch $hostArch -PreferInstaller:$PreferInstaller -ArchiveOnly:$ArchiveOnly -AvailableFormats $AvailableFormats
            }
            'winlibs' {
                $picked = Select-LlvmWinLibsAsset -Recipe $recipe -Assets @($rel.assets) -HostOs $hostOs -HostArch $hostArch -Crt $Crt -Threads $Threads -Extractor $Extractor -AvailableFormats $AvailableFormats
                if ($picked) {
                    $llvmVer = $picked.llvm_version
                    $gccVer = $picked.gcc_version
                    $mingwVer = $picked.mingw_version
                    $revNum = $picked.revision
                }
            }
            'llvm-mingw' {
                $metaText = "$($rel.name)`n$($rel.body)"
                if ($metaText -match $recipe.tag_rules.llvm_version_metadata_regex) {
                    $llvmVer = $matches[1]
                }
                $picked = Select-LlvmMinGWAsset -Recipe $recipe -Assets @($rel.assets) -HostOs $hostOs -HostArch $hostArch -Crt $Crt
            }
        }

        if (-not $picked) { continue }
        if (-not $ReleaseTag) {
            $tagMatched = ($tag -ieq $VersionExpression)
            if (-not $tagMatched) {
                if (-not $llvmVer) { continue }
                if (-not (Test-LlvmVersionSatisfies -CandidateVersion $llvmVer -Expression $VersionExpression)) { continue }
            }
        }

        if ($Target -and ($picked.supported_targets -notcontains $Target)) {
            continue
        }

        $candidates += [pscustomobject]@{
            Release = $rel
            Tag = $tag
            LlvmVersion = $llvmVer
            GccVersion = $gccVer
            MingwVersion = $mingwVer
            Revision = if ($null -ne $revNum) { [int]$revNum } else { 0 }
            DateNum = if ($tag -match '^\d{8}$') { [int]$tag } else { 0 }
            Picked = $picked
        }
    }

    if ($candidates.Count -eq 0) {
        if ($ReleaseTag) {
            throw "No compatible asset found in provider '$Provider' release '$ReleaseTag' for $hostOs $hostArch (crt=$(if ($Crt) { $Crt } else { 'default' }))."
        }
        throw "No stable release of provider '$Provider' matches '$VersionExpression' for $hostOs $hostArch (crt=$(if ($Crt) { $Crt } else { 'default' }))."
    }

    $chosen = $candidates | Sort-Object -Property @(
        @{ Expression = { if ($_.LlvmVersion) { try { [version](Normalize-LlvmSemver $_.LlvmVersion) } catch { [version]'0.0.0' } } else { [version]'0.0.0' } }; Descending = $true },
        @{ Expression = { $_.DateNum }; Descending = $true },
        @{ Expression = { if ($_.GccVersion) { try { [version](Normalize-LlvmSemver $_.GccVersion) } catch { [version]'0.0.0' } } else { [version]'0.0.0' } }; Descending = $true },
        @{ Expression = { $_.Revision }; Descending = $true }
    ) | Select-Object -First 1

    $verAssets = Get-LlvmVerificationAssetsFromRelease -Assets @($chosen.Release.assets) -AssetName $chosen.Picked.asset.name
    # Canonical identity: provider + exact upstream release + the variant/host axes that change content.
    # Official keeps the historical 'llvmorg-X.Y.Z' directory name for compatibility with existing installs.
    $canonicalId = if ($Provider -eq 'official') {
        $chosen.Tag
    } elseif ($Provider -eq 'winlibs') {
        # The WinLibs tag already encodes GCC, LLVM, MinGW, threads, CRT and revision.
        "winlibs-$($chosen.Tag)-$($hostArch)"
    } else {
        "llvm-mingw-$($chosen.Tag)-$($chosen.Picked.variant.crt)-$($hostOs)-$($hostArch)"
    }

    $variant = $chosen.Picked.variant
    $variant['profile'] = if ($Profile) { $Profile } else { 'full' }
    if ($Compiler) { $variant['default_compiler'] = $Compiler.ToLowerInvariant() }
    $selectedTarget = if ($Target) { $Target } else { $chosen.Picked.default_target }

    return [ordered]@{
        provider = $Provider
        recipe = $recipe
        release_tag = $chosen.Tag
        revision = if ($chosen.Revision -gt 0) { $chosen.Revision } else { $null }
        llvm_version = $chosen.LlvmVersion
        gcc_version = $chosen.GccVersion
        mingw_version = $chosen.MingwVersion
        canonical_id = $canonicalId
        host = [ordered]@{ os = $hostOs; arch = $hostArch }
        supported_targets = $chosen.Picked.supported_targets
        default_target = $selectedTarget
        variant = $variant
        asset = [ordered]@{
            name = [string]$chosen.Picked.asset.name
            url = [string]$chosen.Picked.asset.browser_download_url
            size = if ($chosen.Picked.asset.size) { [int64]$chosen.Picked.asset.size } else { 0 }
            digest = if ($chosen.Picked.asset.digest) { [string]$chosen.Picked.asset.digest } else { '' }
            id = if ($chosen.Picked.asset.id) { [string]$chosen.Picked.asset.id } else { '' }
            format = $chosen.Picked.format
        }
        verification_assets = $verAssets
    }
}

function Invoke-LlvmRecipeFinalize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$StagingRoot
    )

    $binDir = Join-Path $StagingRoot 'bin'
    if (-not (Test-Path -LiteralPath $binDir -PathType Container)) {
        # Handle nested mingw64 / mingw32 or single wrapper dir if not yet unwrapped
        $expected = @()
        if ($Plan.recipe.layout -and $Plan.recipe.layout.expected_top_dirs) {
            $expected = @($Plan.recipe.layout.expected_top_dirs)
        }
        foreach ($sub in $expected) {
            $cand = Join-Path $StagingRoot $sub
            if (Test-Path -LiteralPath (Join-Path $cand 'bin') -PathType Container) {
                $tmpMove = "$StagingRoot.norm-$([guid]::NewGuid().ToString('N'))"
                Move-Item -LiteralPath $cand -Destination $tmpMove -ErrorAction Stop
                Remove-Item -LiteralPath $StagingRoot -Recurse -Force
                Move-Item -LiteralPath $tmpMove -Destination $StagingRoot -ErrorAction Stop
                break
            }
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $StagingRoot 'bin') -PathType Container)) {
        throw "Staging directory is missing bin/ for $($Plan.provider): $StagingRoot"
    }
    return $StagingRoot
}

function Test-LlvmRecipeStagingValid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$StagingRoot
    )

    $binDir = Join-Path $StagingRoot 'bin'
    if (-not (Test-Path -LiteralPath $binDir -PathType Container)) {
        throw "Validation failed: bin directory missing at $StagingRoot"
    }

    $caps = Get-LlvmDiscoveredToolchainCapabilities -Root $StagingRoot -Provider $Plan.provider -HostOs $Plan.host.os -HostArch $Plan.host.arch
    if (-not $caps.capabilities.compilers -or $caps.capabilities.compilers.Count -eq 0) {
        throw "Validation failed: no supported compiler found in $binDir"
    }

    foreach ($toolKey in @('clang', 'clang++')) {
        if ($caps.tools.Contains($toolKey)) {
            $exePath = Join-Path $StagingRoot ($caps.tools[$toolKey].Replace('/', [IO.Path]::DirectorySeparatorChar))
            & $exePath --version *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "Validation failed: '$exePath --version' returned exit code $LASTEXITCODE"
            }
        }
    }
    if ($Plan.provider -eq 'winlibs' -and $caps.tools.Contains('gcc')) {
        $gccPath = Join-Path $StagingRoot ($caps.tools['gcc'].Replace('/', [IO.Path]::DirectorySeparatorChar))
        & $gccPath --version *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Validation failed: '$gccPath --version' returned exit code $LASTEXITCODE"
        }
    }

    return $caps
}

Export-ModuleMember -Function @(
    'Get-LlvmRecipesDirectory',
    'Get-LlvmProviderList',
    'Get-LlvmRecipe',
    'Normalize-LlvmHostOs',
    'Normalize-LlvmHostArch',
    'Test-LlvmVersionSatisfies',
    'Resolve-LlvmRecipeInstallPlan',
    'Get-LlvmPlanFormats',
    'Invoke-LlvmRecipeFinalize',
    'Test-LlvmRecipeStagingValid'
)
