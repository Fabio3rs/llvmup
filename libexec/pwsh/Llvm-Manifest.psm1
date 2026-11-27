# Versioned toolchain manifest (.llvmup-toolchain.json), aliases, and external registries.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}

function Get-LlvmAliasesPath {
    [CmdletBinding()]
    param([string]$HomePath)
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    return Join-Path $HomePath 'aliases.json'
}

function Get-LlvmExternalRegistryPath {
    [CmdletBinding()]
    param([string]$HomePath)
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    return Join-Path $HomePath 'external-toolchains.json'
}

function Get-LlvmSessionStatePath {
    [CmdletBinding()]
    param([string]$HomePath)
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    return Join-Path $HomePath 'session-state.json'
}

function Read-LlvmJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($Path)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-LlvmJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Data,
        [int]$Depth = 10
    )
    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $json = $Data | ConvertTo-Json -Depth $Depth
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $json + "`n", $utf8NoBom)
}

function Find-LlvmRelativeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Candidates
    )
    foreach ($rel in $Candidates) {
        $variants = @($rel)
        if ($rel -notmatch '\.(exe|cmd|bat|dll|so|dylib)$') {
            $variants = @("$rel.exe", "$rel.cmd", $rel)
        }
        foreach ($v in $variants) {
            $full = Join-Path $Root ($v.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                return $v.Replace('\', '/')
            }
        }
    }
    return $null
}

function Get-LlvmDiscoveredToolchainCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Provider = '',
        [string]$HostOs = 'windows',
        [string]$HostArch = 'x64'
    )

    $tools = [ordered]@{}
    $compilers = @()
    $linkers = @()
    $rcs = @()
    $debuggers = @()

    $clang = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clang')
    $clangxx = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clang++')
    $clangCl = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clang-cl')
    $gcc = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/gcc')
    $gxx = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/g++')

    # Note: in llvm-mingw, gcc/g++ may be Clang wrappers. Distinguish winlibs real GCC vs llvm-mingw wrapper.
    $gccIsWrapper = ($Provider -eq 'llvm-mingw')
    if ($clang) { $tools.clang = $clang; $compilers += 'clang' }
    if ($clangxx) { $tools['clang++'] = $clangxx }
    if ($clangCl) { $tools['clang-cl'] = $clangCl }
    if ($gcc -and -not $gccIsWrapper) {
        $tools.gcc = $gcc
        if ($compilers -notcontains 'gcc') { $compilers += 'gcc' }
    } elseif ($gcc) {
        $tools.gcc_wrapper = $gcc
    }
    if ($gxx -and -not $gccIsWrapper) { $tools['g++'] = $gxx }
    elseif ($gxx) { $tools.gxx_wrapper = $gxx }

    $lldLink = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/lld-link')
    $ldLld = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/ld.lld')
    $lld = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/lld')
    $ldBfd = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/ld')
    if ($lldLink) { $tools['lld-link'] = $lldLink; $linkers += 'lld-link' }
    if ($ldLld) { $tools['ld.lld'] = $ldLld; $linkers += 'ld.lld' }
    if ($lld) { $tools.lld = $lld; if ($linkers -notcontains 'lld') { $linkers += 'lld' } }
    if ($ldBfd) { $tools.ld = $ldBfd; if ($linkers -notcontains 'ld') { $linkers += 'ld' } }

    $llvmAr = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/llvm-ar')
    $gnuAr = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/ar', 'bin/gcc-ar')
    $llvmRanlib = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/llvm-ranlib')
    $gnuRanlib = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/ranlib', 'bin/gcc-ranlib')
    if ($llvmAr) { $tools['llvm-ar'] = $llvmAr }
    if ($gnuAr) { $tools.ar = $gnuAr }
    if ($llvmRanlib) { $tools['llvm-ranlib'] = $llvmRanlib }
    if ($gnuRanlib) { $tools.ranlib = $gnuRanlib }

    $llvmWindres = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/llvm-windres')
    $windres = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/windres')
    $llvmRc = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/llvm-rc')
    if ($llvmWindres) { $tools['llvm-windres'] = $llvmWindres; $rcs += 'llvm-windres' }
    if ($windres) { $tools.windres = $windres; $rcs += 'windres' }
    if ($llvmRc) { $tools['llvm-rc'] = $llvmRc; $rcs += 'llvm-rc' }

    # Binutils-style helpers (mirrors WinLibs mingwvars.bat: NM, STRIP, DLLTOOL, WINDRES, PKG_CONFIG).
    $extraTools = [ordered]@{
        'gcc-ar' = 'bin/gcc-ar'; 'gcc-ranlib' = 'bin/gcc-ranlib'; 'gcc-nm' = 'bin/gcc-nm'
        'nm' = 'bin/nm'; 'llvm-nm' = 'bin/llvm-nm'
        'strip' = 'bin/strip'; 'llvm-strip' = 'bin/llvm-strip'
        'objcopy' = 'bin/objcopy'; 'llvm-objcopy' = 'bin/llvm-objcopy'
        'dlltool' = 'bin/dlltool'; 'llvm-dlltool' = 'bin/llvm-dlltool'
        'pkgconf' = 'bin/pkgconf'; 'pkg-config' = 'bin/pkg-config'
        'gfortran' = 'bin/gfortran'; 'mingw32-make' = 'bin/mingw32-make'
        'cmake' = 'bin/cmake'; 'ninja' = 'bin/ninja'
    }
    foreach ($kv in $extraTools.GetEnumerator()) {
        $found = Find-LlvmRelativeTool -Root $Root -Candidates @($kv.Value)
        if ($found) { $tools[$kv.Key] = $found }
    }
    if ($gnuAr -and $gnuAr -match 'gcc-ar') {
        # 'bin/ar' missing and gcc-ar matched as fallback: keep both keys consistent.
        $tools['gcc-ar'] = $gnuAr
    }

    $llvmConfig = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/llvm-config')
    $clangd = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clangd')
    $clangFormat = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clang-format')
    $clangTidy = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/clang-tidy')
    $lldb = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/lldb')
    $gdb = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/gdb')
    $libclang = Find-LlvmRelativeTool -Root $Root -Candidates @('bin/libclang.dll', 'lib/libclang.dll', 'lib/libclang.so', 'lib/libclang.dylib')

    if ($llvmConfig) { $tools['llvm-config'] = $llvmConfig }
    if ($clangd) { $tools.clangd = $clangd }
    if ($clangFormat) { $tools['clang-format'] = $clangFormat }
    if ($clangTidy) { $tools['clang-tidy'] = $clangTidy }
    if ($lldb) { $tools.lldb = $lldb; $debuggers += 'lldb' }
    if ($gdb) { $tools.gdb = $gdb; $debuggers += 'gdb' }
    if ($libclang) { $tools.libclang = $libclang }

    # Discover target-prefixed wrappers in bin/ (e.g., x86_64-w64-mingw32-clang)
    $binDir = Join-Path $Root 'bin'
    $discoveredTargets = @()
    $targetWrappers = [ordered]@{}
    if (Test-Path -LiteralPath $binDir -PathType Container) {
        $wrapperFiles = @(Get-ChildItem -LiteralPath $binDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^([a-z0-9_]+-w64-mingw32)-clang(\.exe)?$' })
        foreach ($wf in $wrapperFiles) {
            if ($wf.Name -notmatch '^([a-z0-9_]+-w64-mingw32)-clang(\.exe)?$') { continue }
            $triple = $matches[1]
            if ($discoveredTargets -notcontains $triple) { $discoveredTargets += $triple }
            $tw = [ordered]@{}
            foreach ($suffix in @('clang', 'clang++', 'ar', 'ranlib', 'windres', 'ld', 'gcc', 'g++', 'nm', 'strip', 'dlltool', 'objcopy')) {
                $foundWrapper = Find-LlvmRelativeTool -Root $Root -Candidates @("bin/$triple-$suffix")
                if ($foundWrapper) { $tw[$suffix] = $foundWrapper }
            }
            $targetWrappers[$triple] = $tw
        }
    }
    if ($targetWrappers.Count -gt 0) {
        $tools.target_wrappers = $targetWrappers
    }

    $caps = [ordered]@{
        compilers = @($compilers)
        linkers = @($linkers)
        resource_compilers = @($rcs)
        debuggers = @($debuggers)
        has_llvm_config = [bool]$llvmConfig
        has_libclang = [bool]$libclang
        has_clangd = [bool]$clangd
        multi_target = ($discoveredTargets.Count -gt 1)
        discovered_targets = @($discoveredTargets)
    }

    return [ordered]@{
        tools = $tools
        capabilities = $caps
    }
}

function New-LlvmToolchainManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$InstallName,
        [Parameter(Mandatory = $true)][string]$Provider,
        [string]$Origin = 'managed',
        [string]$ProviderRelease = '',
        [Nullable[int]]$ProviderRevision = $null,
        [string]$LlvmVersion = '',
        [string]$GccVersion = '',
        [string]$MingwVersion = '',
        [string]$HostOs = 'windows',
        [string]$HostArch = 'x64',
        [string[]]$SupportedTargets = @(),
        [string]$DefaultTarget = '',
        [hashtable]$Variant = @{},
        [string]$Root = '',
        [hashtable]$Asset = @{},
        [hashtable]$Verification = @{},
        $Discovered = $null
    )

    if (-not $Discovered) {
        $Discovered = if ($Root -and (Test-Path -LiteralPath $Root -PathType Container)) {
            Get-LlvmDiscoveredToolchainCapabilities -Root $Root -Provider $Provider -HostOs $HostOs -HostArch $HostArch
        } else {
            @{ tools = @{}; capabilities = @{} }
        }
    }

    $targets = @($SupportedTargets)
    if ($discovered.capabilities.discovered_targets -and $discovered.capabilities.discovered_targets.Count -gt 0) {
        foreach ($dt in $discovered.capabilities.discovered_targets) {
            if ($targets -notcontains $dt) { $targets += $dt }
        }
    }
    if (-not $DefaultTarget -and $targets.Count -gt 0) {
        $DefaultTarget = $targets[0]
    }

    return [ordered]@{
        schema = 1
        id = $Id
        install_name = $InstallName
        origin = $Origin
        provider = $Provider
        provider_release = $ProviderRelease
        provider_revision = $ProviderRevision
        llvm_version = $LlvmVersion
        gcc_version = if ($GccVersion) { $GccVersion } else { $null }
        mingw_version = if ($MingwVersion) { $MingwVersion } else { $null }
        host = [ordered]@{
            os = $HostOs
            arch = $HostArch
        }
        supported_targets = @($targets)
        default_target = $DefaultTarget
        variant = $Variant
        tools = $discovered.tools
        capabilities = $discovered.capabilities
        asset = $Asset
        verification = $Verification
        installed_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Write-LlvmToolchainManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Manifest
    )
    $path = Join-Path $Root '.llvmup-toolchain.json'
    Write-LlvmJsonFile -Path $path -Data $Manifest -Depth 10
    return $path
}

function Read-LlvmToolchainManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$InstallName = '',
        [string]$OriginOverride = ''
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    if (-not $InstallName) { $InstallName = Split-Path $Root -Leaf }

    $manifestPath = Join-Path $Root '.llvmup-toolchain.json'
    $rawManifest = Read-LlvmJsonFile -Path $manifestPath
    if ($rawManifest -and $rawManifest.schema -eq 1) {
        $ht = ConvertTo-LlvmHashtable -InputObject $rawManifest
        $ht['install_name'] = $InstallName
        $ht['root_path'] = $Root
        if ($OriginOverride) { $ht['origin'] = $OriginOverride }
        return $ht
    }

    # Legacy or unmanifested toolchain fallback: never fabricate provenance or verification.
    $isSource = $InstallName -like 'source-*'
    $origin = if ($OriginOverride) { $OriginOverride } elseif ($isSource) { 'source' } else { 'legacy' }
    $verObj = ConvertFrom-LlvmVersion $InstallName
    $llvmVer = if ($verObj) { $verObj.Version } else { '' }
    $verMarker = Read-LlvmJsonFile -Path (Join-Path $Root '.llvmup-verification.json')
    $instMarker = Read-LlvmJsonFile -Path (Join-Path $Root '.llvmup-installation.json')

    $discovered = Get-LlvmDiscoveredToolchainCapabilities -Root $Root -Provider 'official'
    $verification = if ($verMarker) {
        ConvertTo-LlvmHashtable -InputObject $verMarker
    } else {
        [ordered]@{ policy = 'unknown'; methods = 'unverified'; authenticated_identity = $null; scope = 'none' }
    }
    $profile = if ($instMarker -and $instMarker.profile) { [string]$instMarker.profile } else { 'unknown' }

    return [ordered]@{
        schema = 1
        id = $InstallName
        install_name = $InstallName
        root_path = $Root
        origin = $origin
        provider = if ($OriginOverride -eq 'external') { 'external' } else { 'official' }
        provider_release = if ($verMarker -and $verMarker.version) { [string]$verMarker.version } else { $InstallName }
        provider_revision = $null
        llvm_version = $llvmVer
        gcc_version = $null
        mingw_version = $null
        host = [ordered]@{
            os = if (Test-LlvmIsWindows) { 'windows' } else { 'unknown' }
            arch = 'unknown'
        }
        supported_targets = @($discovered.capabilities.discovered_targets)
        default_target = if ($discovered.capabilities.discovered_targets.Count) { $discovered.capabilities.discovered_targets[0] } else { '' }
        variant = [ordered]@{
            crt = 'unknown'
            threads = 'unknown'
            exceptions = 'unknown'
            cxx_stdlib = 'unknown'
            profile = $profile
            default_compiler = if ($discovered.capabilities.compilers -contains 'clang') { 'clang' } elseif ($discovered.capabilities.compilers.Count) { $discovered.capabilities.compilers[0] } else { '' }
        }
        tools = $discovered.tools
        capabilities = $discovered.capabilities
        asset = if ($verMarker -and $verMarker.asset_name) { [ordered]@{ name = $verMarker.asset_name; digest = $verMarker.asset_digest } } else { @{} }
        verification = $verification
    }
}

function Get-LlvmAliases {
    [CmdletBinding()]
    param([string]$HomePath)
    $path = Get-LlvmAliasesPath -HomePath $HomePath
    $raw = Read-LlvmJsonFile -Path $path
    if (-not $raw -or -not $raw.aliases) { return @{} }
    return (ConvertTo-LlvmHashtable -InputObject $raw.aliases)
}

function Save-LlvmAliases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Aliases,
        [string]$HomePath
    )
    $path = Get-LlvmAliasesPath -HomePath $HomePath
    Write-LlvmJsonFile -Path $path -Data ([ordered]@{ schema = 1; aliases = $Aliases })
}

function Set-LlvmAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AliasName,
        [Parameter(Mandatory = $true)][string]$TargetSelector,
        [string]$ToolchainsPath,
        [string]$HomePath
    )

    if ($AliasName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid alias name '$AliasName'. Use alphanumeric characters, '.', '-', or '_'."
    }
    $aliases = Get-LlvmAliases -HomePath $HomePath
    if ($aliases.ContainsKey($TargetSelector)) {
        throw "Alias chains are not allowed: '$TargetSelector' is already an alias."
    }
    if ($AliasName -eq $TargetSelector) {
        throw "Alias '$AliasName' cannot reference itself."
    }

    $resolved = Resolve-LlvmInstalledToolchain -Selector $TargetSelector -ToolchainsPath $ToolchainsPath -HomePath $HomePath -AllowAlias:$false
    if (-not $resolved) {
        throw "Cannot create alias '$AliasName': target '$TargetSelector' does not match any installed toolchain."
    }

    $aliases[$AliasName] = [ordered]@{
        target_name = $resolved.install_name
        target_id = $resolved.id
        provider = $resolved.provider
        llvm_version = $resolved.llvm_version
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Save-LlvmAliases -Aliases $aliases -HomePath $HomePath
    return $aliases[$AliasName]
}

function Remove-LlvmAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AliasName,
        [string]$HomePath
    )
    $aliases = Get-LlvmAliases -HomePath $HomePath
    if (-not $aliases.ContainsKey($AliasName)) {
        throw "Alias '$AliasName' does not exist."
    }
    $aliases.Remove($AliasName)
    Save-LlvmAliases -Aliases $aliases -HomePath $HomePath
    return $true
}

function Get-LlvmExternalToolchains {
    [CmdletBinding()]
    param([string]$HomePath)
    $path = Get-LlvmExternalRegistryPath -HomePath $HomePath
    $raw = Read-LlvmJsonFile -Path $path
    if (-not $raw -or -not $raw.toolchains) { return @{} }
    return (ConvertTo-LlvmHashtable -InputObject $raw.toolchains)
}

function Save-LlvmExternalToolchains {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Entries,
        [string]$HomePath
    )
    $path = Get-LlvmExternalRegistryPath -HomePath $HomePath
    Write-LlvmJsonFile -Path $path -Data ([ordered]@{ schema = 1; toolchains = $Entries })
}

function Register-LlvmExternalToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ToolchainsPath,
        [string]$HomePath
    )

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid toolchain name '$Name'."
    }
    if (-not $ToolchainsPath) { $ToolchainsPath = Get-LlvmSessionToolchainsPath }
    if (Test-Path -LiteralPath (Join-Path $ToolchainsPath $Name)) {
        throw "A managed toolchain named '$Name' already exists in $ToolchainsPath."
    }

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "External toolchain directory does not exist: $fullPath"
    }

    $discovered = Get-LlvmDiscoveredToolchainCapabilities -Root $fullPath -Provider 'external'
    if (-not $discovered.capabilities.compilers -or $discovered.capabilities.compilers.Count -eq 0) {
        throw "External toolchain directory '$fullPath' does not contain a recognizable compiler under bin/."
    }

    $entries = Get-LlvmExternalToolchains -HomePath $HomePath
    $entries[$Name] = [ordered]@{
        name = $Name
        path = $fullPath
        origin = 'external'
        registered_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Save-LlvmExternalToolchains -Entries $entries -HomePath $HomePath

    return (Read-LlvmToolchainManifest -Root $fullPath -InstallName $Name -OriginOverride 'external')
}

function Unregister-LlvmExternalToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$HomePath
    )
    $entries = Get-LlvmExternalToolchains -HomePath $HomePath
    if (-not $entries.ContainsKey($Name)) {
        throw "External toolchain '$Name' is not registered."
    }
    $entries.Remove($Name)
    Save-LlvmExternalToolchains -Entries $entries -HomePath $HomePath
    return $true
}

function Get-LlvmAllToolchains {
    [CmdletBinding()]
    param(
        [string]$ToolchainsPath,
        [string]$HomePath
    )

    if (-not $ToolchainsPath) { $ToolchainsPath = Get-LlvmSessionToolchainsPath }
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }

    $results = @()
    if (Test-Path -LiteralPath $ToolchainsPath -PathType Container) {
        $dirs = @(Get-ChildItem -LiteralPath $ToolchainsPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($d in $dirs) {
            if ($d.Name -match '\.installing[.-]|\.backup[.-]|\.staging[.-]') { continue }
            $manifest = Read-LlvmToolchainManifest -Root $d.FullName -InstallName $d.Name
            if ($manifest) { $results += $manifest }
        }
    }

    $externals = Get-LlvmExternalToolchains -HomePath $HomePath
    foreach ($name in ($externals.Keys | Sort-Object)) {
        $entry = $externals[$name]
        $extPath = [string]$entry.path
        if ($extPath -and (Test-Path -LiteralPath $extPath -PathType Container)) {
            $manifest = Read-LlvmToolchainManifest -Root $extPath -InstallName $name -OriginOverride 'external'
            if ($manifest) {
                $manifest['external_registered'] = $true
                $results += $manifest
            }
        } else {
            $results += [ordered]@{
                schema = 1
                id = $name
                install_name = $name
                root_path = $extPath
                origin = 'external-missing'
                provider = 'external'
                provider_release = ''
                llvm_version = ''
                tools = @{}
                capabilities = @{ compilers = @() }
                verification = @{ methods = 'unverified'; policy = 'unknown' }
                missing_on_disk = $true
            }
        }
    }

    return $results
}

function Format-LlvmNoMatchMessage {
    # Message for the one case where --install may help: no installation matches the selector.
    param([Parameter(Mandatory)][string]$Selector, [switch]$OfferUseInstall)
    $arg = if ($Selector -match '^[A-Za-z0-9@._+:=/-]+$') { $Selector } else { "'" + $Selector.Replace("'", "''") + "'" }
    $msg = "No installed toolchain matches '$Selector'.`n`nTo install it:`n  llvmup install $arg"
    if ($OfferUseInstall) { $msg += "`n`nTo install and activate it in one step:`n  llvmup use $arg --install" }
    return $msg + "`n`nTo see installed toolchains:`n  llvmup list"
}

function Resolve-LlvmInstalledToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Selector,
        [string]$ToolchainsPath,
        [string]$HomePath,
        [string]$ProviderFilter = '',
        [string]$CrtFilter = '',
        [bool]$AllowAlias = $true
    )

    if (-not $ToolchainsPath) { $ToolchainsPath = Get-LlvmSessionToolchainsPath }
    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }

    $all = @(Get-LlvmAllToolchains -ToolchainsPath $ToolchainsPath -HomePath $HomePath)
    if ($AllowAlias) {
        $aliases = Get-LlvmAliases -HomePath $HomePath
        if ($aliases.ContainsKey($Selector)) {
            $aliasEntry = $aliases[$Selector]
            $targetName = [string]$aliasEntry.target_name
            $targets = @($all | Where-Object {
                $_.install_name -eq $targetName -and -not $_.missing_on_disk -and
                (-not $aliasEntry.target_id -or $_.id -eq $aliasEntry.target_id) -and
                (-not $ProviderFilter -or $_.provider -eq $ProviderFilter) -and
                (-not $CrtFilter -or $_.variant.crt -eq $CrtFilter)
            })
            if ($targets.Count -ne 1) {
                throw "Alias '$Selector' no longer matches an installed toolchain at '$targetName'. Remove or update the alias."
            }
            $targetItem = $targets[0]
            $targetItem['resolved_via'] = "alias:$Selector"
            return $targetItem
        }
    }

    # Parse optional provider@expr syntax
    $requestedProvider = $ProviderFilter
    $expr = $Selector
    if ($Selector -match '^([a-z0-9][a-z0-9-]*?)@(.+)$') {
        $requestedProvider = $matches[1].ToLowerInvariant()
        $expr = $matches[2]
    }

    # Exact install_name or canonical id match (when no provider@ override conflicts)
    $exact = @($all | Where-Object {
        ($_.install_name -eq $Selector -or $_.id -eq $Selector) -and
        (-not $requestedProvider -or $_.provider -eq $requestedProvider) -and
        (-not $CrtFilter -or ($_.variant -and $_.variant.crt -eq $CrtFilter))
    })
    if ($exact.Count -eq 1) { return $exact[0] }

    # Filter candidates by provider/crt
    $candidates = @($all | Where-Object {
        (-not $_.missing_on_disk) -and
        (-not $requestedProvider -or $_.provider -eq $requestedProvider) -and
        (-not $CrtFilter -or ($_.variant -and $_.variant.crt -eq $CrtFilter))
    })
    if ($candidates.Count -eq 0) { return $null }

    # Match against install_name or llvm_version using core version matcher
    if ($expr -eq 'latest') {
        $sorted = @($candidates | Sort-Object {
            if ($_.llvm_version) {
                $norm = Normalize-LlvmSemver $_.llvm_version
                try { [version]$norm } catch { [version]'0.0.0' }
            } else { [version]'0.0.0' }
        })
        return ($sorted | Select-Object -Last 1)
    }

    $matched = @()
    foreach ($cand in $candidates) {
        $verKey = if ($cand.llvm_version) { $cand.llvm_version } else { $cand.install_name }
        if ($cand.install_name -eq $expr -or $cand.provider_release -eq $expr) {
            $matched += $cand
            continue
        }
        # Partial versions (major or major.minor) select the newest matching installation, like
        # remote resolution does ('llvm-mingw@23', 'official@23.1').
        if ($expr -match '^\d+(\.\d+)?$' -and $cand.llvm_version) {
            if ([string]$cand.llvm_version -like "$expr.*") { $matched += $cand }
            continue
        }
        try {
            $res = @(Invoke-LlvmMatchVersions -Expression $expr -CandidateVersions @($verKey))
            if ($res.Count -gt 0) { $matched += $cand; continue }
        } catch {}
        try {
            $res2 = @(Invoke-LlvmMatchVersions -Expression $expr -CandidateVersions @($cand.install_name))
            if ($res2.Count -gt 0) { $matched += $cand }
        } catch {}
    }

    if ($matched.Count -eq 0) { return $null }
    if ($matched.Count -eq 1) { return $matched[0] }

    # If multiple matches share the same provider and express a range/partial (e.g. official@23), pick newest ONLY if same provider & variant, else report ambiguity if across providers without provider filter
    $providers = @($matched | ForEach-Object { $_.provider } | Select-Object -Unique)
    if ($providers.Count -gt 1 -and -not $requestedProvider) {
        $lines = ($matched | ForEach-Object { "  $($_.install_name)  ($($_.provider), LLVM $($_.llvm_version))" }) -join "`n"
        $hints = (@($providers | Select-Object -First 2 | ForEach-Object { "  llvmup use $_@$Selector" }) + "  llvmup use $($matched[0].install_name)") -join "`n"
        throw "'$Selector' matches multiple providers.`n`nMatching installations:`n$lines`n`nSpecify a provider or an installation name:`n$hints"
    }

    $sortedMatches = @($matched | Sort-Object {
        if ($_.llvm_version) {
            $norm = Normalize-LlvmSemver $_.llvm_version
            try { [version]$norm } catch { [version]'0.0.0' }
        } else { [version]'0.0.0' }
    })
    return ($sortedMatches | Select-Object -Last 1)
}

function Assert-LlvmManagedAsset {
    param($Manifest, $Expected, [string]$Policy = 'warn')

    if ($Manifest.origin -ne 'managed' -or $Manifest.id -cne $Expected.canonical_id -or
        $Manifest.provider -cne $Expected.provider -or $Manifest.provider_release -cne $Expected.release -or
        $Manifest.host.os -cne $Expected.host.os -or $Manifest.host.arch -cne $Expected.host.arch) {
        throw "Installed toolchain '$($Manifest.install_name)' identity differs from the requested managed installation."
    }
    if ($Expected.asset.digest -and $Manifest.asset.digest -ne $Expected.asset.digest) {
        throw "Installed toolchain '$($Manifest.install_name)' digest differs from the requested asset digest."
    }
    if (($Expected.asset.name -and $Manifest.asset.name -cne $Expected.asset.name) -or
        ($Expected.asset.id -and [string]$Manifest.asset.id -cne [string]$Expected.asset.id)) {
        throw "Installed toolchain '$($Manifest.install_name)' asset differs from the requested asset."
    }
    if ($Policy -eq 'strict') {
        $verification = $Manifest.verification
        if ($verification.gpg -ne 'valid' -and $verification.attestation -ne 'valid' -and
            ($verification.authenticode -ne 'valid' -or $verification.methods -notcontains 'authenticode')) {
            throw 'Strict verification cannot trust the existing toolchain: no authenticated origin is recorded.'
        }
    }
    if (-not $Manifest.capabilities.compilers -or -not $Manifest.tools) { throw 'Installed toolchain has no recorded compiler.' }
    $compilerNames = @($Manifest.capabilities.compilers)
    $compilerNames += @('clang++', 'g++' | Where-Object { $Manifest.tools[$_] })
    foreach ($compiler in $compilerNames) {
        $relative = [string]$Manifest.tools[$compiler]
        if ($relative -notmatch '^bin/[a-zA-Z0-9_.+-]+$' -or
            -not (Test-Path -LiteralPath (Join-Path $Manifest.root_path $relative) -PathType Leaf)) {
            throw "Installed toolchain compiler '$compiler' is unavailable under '$($Manifest.root_path)'. Remove it or reinstall with --force."
        }
    }
}

Export-ModuleMember -Function @(
    'Assert-LlvmManagedAsset',
    'Format-LlvmNoMatchMessage',
    'Get-LlvmAliasesPath',
    'Get-LlvmExternalRegistryPath',
    'Get-LlvmSessionStatePath',
    'Read-LlvmJsonFile',
    'Write-LlvmJsonFile',
    'Find-LlvmRelativeTool',
    'Get-LlvmDiscoveredToolchainCapabilities',
    'New-LlvmToolchainManifest',
    'Write-LlvmToolchainManifest',
    'Read-LlvmToolchainManifest',
    'Get-LlvmAliases',
    'Set-LlvmAlias',
    'Remove-LlvmAlias',
    'Get-LlvmExternalToolchains',
    'Register-LlvmExternalToolchain',
    'Unregister-LlvmExternalToolchain',
    'Get-LlvmAllToolchains',
    'Resolve-LlvmInstalledToolchain'
)
