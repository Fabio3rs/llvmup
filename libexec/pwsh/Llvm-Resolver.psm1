# Normalized request parsing and local/remote selection resolution.

$script:CoreModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Llvm-Functions-Core.psm1'
if ((Test-Path -LiteralPath $script:CoreModule) -and -not (Get-Module -Name 'Llvm-Functions-Core')) {
    Import-Module $script:CoreModule -DisableNameChecking
}
$script:ManifestModule = Join-Path $PSScriptRoot 'Llvm-Manifest.psm1'
if ((Test-Path -LiteralPath $script:ManifestModule) -and -not (Get-Module -Name 'Llvm-Manifest')) {
    Import-Module $script:ManifestModule -DisableNameChecking
}
$script:RecipesModule = Join-Path $PSScriptRoot 'Llvm-Recipes.psm1'
if ((Test-Path -LiteralPath $script:RecipesModule) -and -not (Get-Module -Name 'Llvm-Recipes')) {
    Import-Module $script:RecipesModule -DisableNameChecking
}

function Split-LlvmSelector {
    [CmdletBinding()]
    param(
        [string]$Selector = '',
        [string]$ExplicitProvider = ''
    )

    $provider = if ($ExplicitProvider) { $ExplicitProvider.Trim().ToLowerInvariant() } else { '' }
    $expr = if ($Selector) { $Selector.Trim() } else { '' }
    $hasAt = $false

    if ($expr -match '^([A-Za-z0-9][A-Za-z0-9-]*?)@(.+)$') {
        $parsedProv = $matches[1].ToLowerInvariant()
        $parsedExpr = $matches[2].Trim()
        if ($provider -and $provider -ne $parsedProv) {
            throw "Conflicting providers: --provider '$provider' vs selector '$Selector'."
        }
        $provider = $parsedProv
        $expr = $parsedExpr
        $hasAt = $true
    }

    return [pscustomobject][ordered]@{
        raw = $Selector
        provider = $provider
        expression = $expr
        has_provider_prefix = $hasAt
    }
}

function Find-LlvmProjectConfigPath {
    [CmdletBinding()]
    param([string]$StartDirectory = (Get-Location).Path)

    $current = [IO.Path]::GetFullPath($StartDirectory)
    while ($current) {
        $candidate = Join-Path $current '.llvmup-config'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Read-LlvmProjectConfigData {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    $section = ''
    $data = [ordered]@{
        root = Split-Path $ConfigPath -Parent
        path = $ConfigPath
        version = ''
        provider = ''
        kind = ''
        crt = ''
        target = ''
        compiler = ''
        release = ''
        arch = ''
        threads = ''
        name = ''
        profile = ''
        components = @()
        cmake_flags = @()
        cmake_preset = ''
        disable_libc_wno_error = $false
        auto_activate = $true
        llvm_home = ''
        toolchains_dir = ''
        sources_dir = ''
    }

    $lines = Get-Content -LiteralPath $ConfigPath -ErrorAction Stop
    $inArrayKey = $null
    $arrayBuffer = ''

    foreach ($rawLine in $lines) {
        $line = $rawLine.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }

        if ($inArrayKey) {
            $arrayBuffer += ' ' + $line
            if ($line.Contains(']')) {
                $items = @($arrayBuffer.Trim().TrimStart('[').TrimEnd(']') -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
                if ($inArrayKey -eq 'build.cmake_flags') { $data.cmake_flags = $items }
                elseif ($inArrayKey -eq 'components.include') { $data.components = $items }
                $inArrayKey = $null
                $arrayBuffer = ''
            }
            continue
        }

        if ($line -match '^\[([^\]]+)\]$') {
            $section = $matches[1].Trim().ToLowerInvariant()
            continue
        }

        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key = $parts[0].Trim().ToLowerInvariant()
        $valRaw = $parts[1].Trim()

        if ($valRaw.StartsWith('[')) {
            if ($valRaw.Contains(']')) {
                $items = @($valRaw.Trim().TrimStart('[').TrimEnd(']') -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
                if ("$section.$key" -eq 'build.cmake_flags') { $data.cmake_flags = $items }
                elseif ("$section.$key" -eq 'components.include') { $data.components = $items }
            } else {
                $inArrayKey = "$section.$key"
                $arrayBuffer = $valRaw
            }
            continue
        }

        $val = $valRaw.Trim().Trim('"').Trim("'")
        switch ("$section.$key") {
            'version.default' { $data.version = $val }
            '.version' { if (-not $data.version) { $data.version = $val } }
            'toolchain.provider' { $data.provider = $val.ToLowerInvariant() }
            'toolchain.kind' { $data.kind = $val.ToLowerInvariant() }
            'toolchain.crt' { $data.crt = $val.ToLowerInvariant() }
            'toolchain.target' { $data.target = $val }
            'toolchain.compiler' { $data.compiler = $val.ToLowerInvariant() }
            'toolchain.release' { $data.release = $val }
            'toolchain.arch' { $data.arch = $val }
            'toolchain.threads' { $data.threads = $val.ToLowerInvariant() }
            'build.name' { $data.name = $val }
            'build.disable_libc_wno_error' { $data.disable_libc_wno_error = ($val.ToLowerInvariant() -eq 'true') }
            'profile.type' { $data.profile = $val.ToLowerInvariant() }
            'project.auto_activate' { $data.auto_activate = ($val.ToLowerInvariant() -ne 'false') }
            'project.cmake_preset' { $data.cmake_preset = $val }
            'paths.llvm_home' { $data.llvm_home = $val }
            'paths.toolchains_dir' { $data.toolchains_dir = $val }
            'paths.sources_dir' { $data.sources_dir = $val }
        }
    }

    if ($inArrayKey) {
        throw "Unterminated array '$inArrayKey' in $ConfigPath"
    }

    # Infer kind if omitted in legacy configs
    if (-not $data.kind) {
        if ($data.cmake_flags.Count -gt 0 -or $data.cmake_preset -or $data.disable_libc_wno_error) {
            $data.kind = 'source'
        } else {
            $data.kind = 'prebuilt'
        }
    }

    return [pscustomobject]$data
}

function Resolve-LlvmEffectiveSelection {
    [CmdletBinding()]
    param(
        [string]$ExplicitSelector = '',
        [string]$ProviderFilter = '',
        [string]$CrtFilter = '',
        [string]$TargetOverride = '',
        [string]$CompilerOverride = '',
        [string]$StartDirectory = (Get-Location).Path,
        [string]$ToolchainsPath = '',
        [string]$HomePath = ''
    )

    if (-not $HomePath) { $HomePath = Get-LlvmHomePath }
    if (-not $ToolchainsPath) { $ToolchainsPath = Get-LlvmSessionToolchainsPath }

    $origin = ''
    $resolvedManifest = $null
    $effCompiler = $CompilerOverride
    $effTarget = $TargetOverride
    $effCrt = $CrtFilter
    $reason = ''

    # 1. Explicit selector
    if ($ExplicitSelector) {
        $split = Split-LlvmSelector -Selector $ExplicitSelector -ExplicitProvider $ProviderFilter
        $lookup = if ($split.has_provider_prefix) { $ExplicitSelector } elseif ($split.provider) { "$($split.provider)@$($split.expression)" } else { $split.expression }
        $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $lookup -ToolchainsPath $ToolchainsPath -HomePath $HomePath -ProviderFilter $split.provider -CrtFilter $effCrt
        if (-not $resolvedManifest) {
            throw "No installed toolchain matches selector '$ExplicitSelector'."
        }
        $origin = 'explicit'
        $reason = "Explicitly selected '$ExplicitSelector'"
    }

    # 2. Session override (llvmup use / activate)
    if (-not $resolvedManifest -and $env:LLVMUP_SESSION_OVERRIDE) {
        $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $env:LLVMUP_SESSION_OVERRIDE -ToolchainsPath $ToolchainsPath -HomePath $HomePath -ProviderFilter $ProviderFilter -CrtFilter $effCrt
        if ($resolvedManifest) {
            $origin = 'session-override'
            $reason = "Session override ($($env:LLVMUP_SESSION_OVERRIDE))"
            if (-not $effCompiler -and $env:LLVMUP_ACTIVE_COMPILER) { $effCompiler = $env:LLVMUP_ACTIVE_COMPILER }
            if (-not $effTarget -and $env:LLVMUP_ACTIVE_TARGET) { $effTarget = $env:LLVMUP_ACTIVE_TARGET }
        }
    }

    # 3. Project configuration (.llvmup-config)
    if (-not $resolvedManifest -and $env:LLVMUP_IGNORE_CONFIG -ne '1') {
        $cfgPath = Find-LlvmProjectConfigPath -StartDirectory $StartDirectory
        if ($cfgPath) {
            $cfg = Read-LlvmProjectConfigData -ConfigPath $cfgPath
            if ($cfg.version) {
                if (-not $effCompiler -and $cfg.compiler) { $effCompiler = $cfg.compiler }
                if (-not $effTarget -and $cfg.target) { $effTarget = $cfg.target }
                if (-not $effCrt -and $cfg.crt) { $effCrt = $cfg.crt }
                $cfgProvider = if ($ProviderFilter) { $ProviderFilter } else { $cfg.provider }

                if ($cfg.name) {
                    $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $cfg.name -ToolchainsPath $ToolchainsPath -HomePath $HomePath -ProviderFilter $cfgProvider -CrtFilter $effCrt
                }
                if (-not $resolvedManifest) {
                    $expr = if ($cfgProvider) { "$cfgProvider@$($cfg.version)" } else { $cfg.version }
                    $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $expr -ToolchainsPath $ToolchainsPath -HomePath $HomePath -ProviderFilter $cfgProvider -CrtFilter $effCrt
                }
                if ($resolvedManifest) {
                    $origin = 'project-config'
                    $reason = "Project config '$cfgPath' ($($cfg.version))"
                }
            }
        }
    }

    # 4. Currently active in environment (if not via override, e.g. legacy activate)
    if (-not $resolvedManifest -and $env:_ACTIVE_LLVM) {
        $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $env:_ACTIVE_LLVM -ToolchainsPath $ToolchainsPath -HomePath $HomePath
        if ($resolvedManifest) {
            $origin = 'active-session'
            $reason = "Active environment ($_ACTIVE_LLVM)"
        }
    }

    # 5. Global default
    if (-not $resolvedManifest) {
        $def = Get-LlvmDefaultVersion -HomePath $HomePath
        if ($def) {
            $resolvedManifest = Resolve-LlvmInstalledToolchain -Selector $def -ToolchainsPath $ToolchainsPath -HomePath $HomePath -AllowAlias:$false
            if ($resolvedManifest) {
                $origin = 'default'
                $reason = "Global default ($def)"
            }
        }
    }

    if (-not $resolvedManifest) { return $null }

    if (-not $effCompiler) {
        $effCompiler = if ($resolvedManifest.variant -and $resolvedManifest.variant.default_compiler) { [string]$resolvedManifest.variant.default_compiler } else { 'clang' }
    }
    if (-not $effTarget) {
        $effTarget = if ($resolvedManifest.default_target) { [string]$resolvedManifest.default_target } else { '' }
    }

    return [pscustomobject][ordered]@{
        manifest = $resolvedManifest
        origin = $origin
        reason = $reason
        compiler = $effCompiler
        target = $effTarget
    }
}

Export-ModuleMember -Function @(
    'Split-LlvmSelector',
    'Find-LlvmProjectConfigPath',
    'Read-LlvmProjectConfigData',
    'Resolve-LlvmEffectiveSelection'
)
