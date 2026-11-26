# Declarative environment delta construction and idempotent session activation/restoration.

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

function Resolve-LlvmManifestToolAbsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)]$ToolsMap,
        [string]$Key = ''
    )
    if (-not $ToolsMap -or -not $Key) { return $null }
    $rel = $null
    if ($ToolsMap -is [System.Collections.IDictionary] -and $ToolsMap.Contains($Key)) {
        $rel = [string]$ToolsMap[$Key]
    } elseif ($ToolsMap.PSObject -and $ToolsMap.PSObject.Properties[$Key]) {
        $rel = [string]$ToolsMap.$Key
    }
    if (-not $rel) { return $null }
    $full = Join-Path $RootPath ($rel.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    return $null
}

function Get-LlvmEnvironmentDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [string]$Target = '',
        [string]$Compiler = ''
    )

    $root = [string]$Manifest.root_path
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Toolchain root directory does not exist: $root"
    }

    $provider = if ($Manifest.provider) { [string]$Manifest.provider } else { 'official' }
    $effCompiler = if ($Compiler) { $Compiler.ToLowerInvariant() } elseif ($Manifest.variant -and $Manifest.variant.default_compiler) { [string]$Manifest.variant.default_compiler } else { 'clang' }
    $availableCompilers = if ($Manifest.capabilities -and $Manifest.capabilities.compilers) { @($Manifest.capabilities.compilers) } else { @() }
    if ($availableCompilers.Count -gt 0 -and $availableCompilers -notcontains $effCompiler) {
        throw "Toolchain '$($Manifest.install_name)' ($provider) does not provide compiler '$effCompiler'. Available: $($availableCompilers -join ', ')"
    }

    $effTarget = if ($Target) { $Target } elseif ($Manifest.default_target) { [string]$Manifest.default_target } else { '' }
    $supportedTargets = if ($Manifest.supported_targets) { @($Manifest.supported_targets) } else { @() }
    if ($Target -and $supportedTargets.Count -gt 0 -and ($supportedTargets -notcontains $Target)) {
        throw "Toolchain '$($Manifest.install_name)' ($provider) does not support target '$Target'. Supported: $($supportedTargets -join ', ')"
    }

    if ($effCompiler -eq 'gcc' -and (Get-Command Get-LlvmRecipePathConstraintWarnings -ErrorAction SilentlyContinue)) {
        foreach ($w in @(Get-LlvmRecipePathConstraintWarnings -Provider $provider -RootPath $root -Compiler $effCompiler)) { Write-Warning $w }
    }

    $tools = $Manifest.tools
    $setVars = [ordered]@{}
    $unsetVars = @()

    $binDir = Join-Path $root 'bin'
    $ccPath = $null; $cxxPath = $null; $arPath = $null; $ranlibPath = $null; $rcPath = $null; $ldPath = $null
    $nmPath = $null; $stripPath = $null; $dlltoolPath = $null

    # Target-specific wrappers take precedence on multi-target llvm-mingw when target differs or wrappers exist
    $wrappers = $null
    if ($effTarget -and $tools -and $tools.target_wrappers) {
        if ($tools.target_wrappers -is [System.Collections.IDictionary] -and $tools.target_wrappers.Contains($effTarget)) {
            $wrappers = $tools.target_wrappers[$effTarget]
        } elseif ($tools.target_wrappers.PSObject -and $tools.target_wrappers.PSObject.Properties[$effTarget]) {
            $wrappers = $tools.target_wrappers.$effTarget
        }
    }

    if ($provider -eq 'llvm-mingw' -and $wrappers) {
        $ccPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'clang'
        $cxxPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'clang++'
        $arPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'ar'
        $ranlibPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'ranlib'
        $rcPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'windres'
        $ldPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'ld'
        $nmPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'nm'
        $stripPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'strip'
        $dlltoolPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $wrappers -Key 'dlltool'
    }

    if ($effCompiler -eq 'gcc') {
        if (-not $ccPath) { $ccPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'gcc' }
        if (-not $cxxPath) { $cxxPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'g++' }
        # gcc-ar/gcc-ranlib/gcc-nm load the LTO plugin, as WinLibs' own mingwvars.bat configures.
        foreach ($k in @('gcc-ar', 'ar')) { if (-not $arPath) { $arPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        foreach ($k in @('gcc-ranlib', 'ranlib')) { if (-not $ranlibPath) { $ranlibPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        foreach ($k in @('gcc-nm', 'nm')) { if (-not $nmPath) { $nmPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        if (-not $stripPath) { $stripPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'strip' }
        if (-not $dlltoolPath) { $dlltoolPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'dlltool' }
        if (-not $rcPath) { $rcPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'windres' }
        if (-not $ldPath) { $ldPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'ld' }
    } else {
        if (-not $ccPath) { $ccPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'clang' }
        if (-not $cxxPath) { $cxxPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'clang++' }
        if (-not $arPath) { $arPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'llvm-ar' }
        if (-not $arPath) { $arPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'ar' }
        if (-not $ranlibPath) { $ranlibPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'llvm-ranlib' }
        if (-not $ranlibPath) { $ranlibPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'ranlib' }
        if (-not $rcPath) { $rcPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'llvm-windres' }
        if (-not $rcPath) { $rcPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'windres' }
        if (-not $rcPath) { $rcPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'llvm-rc' }
        foreach ($k in @('llvm-nm', 'nm')) { if (-not $nmPath) { $nmPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        foreach ($k in @('llvm-strip', 'strip')) { if (-not $stripPath) { $stripPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        foreach ($k in @('llvm-dlltool', 'dlltool')) { if (-not $dlltoolPath) { $dlltoolPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
        if (-not $ldPath) {
            if ($provider -eq 'official' -and (Test-LlvmIsWindows)) {
                $ldPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'lld-link'
            }
            if (-not $ldPath) { $ldPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'ld.lld' }
            if (-not $ldPath) { $ldPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'lld' }
        }
    }

    if ($ccPath) { $setVars['CC'] = $ccPath } else { $unsetVars += 'CC' }
    if ($cxxPath) { $setVars['CXX'] = $cxxPath } else { $unsetVars += 'CXX' }
    if ($arPath) { $setVars['AR'] = $arPath } else { $unsetVars += 'AR' }
    if ($ranlibPath) { $setVars['RANLIB'] = $ranlibPath } else { $unsetVars += 'RANLIB' }
    if ($rcPath) { $setVars['RC'] = $rcPath } else { $unsetVars += 'RC' }
    if ($ldPath) { $setVars['LD'] = $ldPath } else { $unsetVars += 'LD' }
    if ($nmPath) { $setVars['NM'] = $nmPath } else { $unsetVars += 'NM' }
    if ($stripPath) { $setVars['STRIP'] = $stripPath } else { $unsetVars += 'STRIP' }
    if ($dlltoolPath) { $setVars['DLLTOOL'] = $dlltoolPath } else { $unsetVars += 'DLLTOOL' }
    if ($rcPath -and $rcPath -match 'windres') { $setVars['WINDRES'] = $rcPath } else { $unsetVars += 'WINDRES' }
    $pkgConfigPath = $null
    foreach ($k in @('pkgconf', 'pkg-config')) { if (-not $pkgConfigPath) { $pkgConfigPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key $k } }
    if ($pkgConfigPath) { $setVars['PKG_CONFIG'] = $pkgConfigPath } else { $unsetVars += 'PKG_CONFIG' }

    $libclangPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'libclang'
    if ($libclangPath) { $setVars['LIBCLANG_PATH'] = $libclangPath } else { $unsetVars += 'LIBCLANG_PATH' }

    $llvmConfigPath = Resolve-LlvmManifestToolAbsPath -RootPath $root -ToolsMap $tools -Key 'llvm-config'
    if ($llvmConfigPath) { $setVars['LLVM_CONFIG_PATH'] = $llvmConfigPath } else { $unsetVars += 'LLVM_CONFIG_PATH' }

    if ($Manifest.llvm_version -and $Manifest.llvm_version -match '^(\d+)\.(\d+)') {
        $major = [int]$matches[1]; $minor = [int]$matches[2]
        # llvm-sys reads LLVM_SYS_<major><minor>_PREFIX (181 for 18.1); the rounded name is the historical llvmup one.
        $rounded = [math]::Floor(($major * 10 + $minor) / 10) * 10
        $setVars["LLVM_SYS_${rounded}_PREFIX"] = $root
        $setVars["LLVM_SYS_$($major * 10 + $minor)_PREFIX"] = $root
    }

    $setVars['_ACTIVE_LLVM'] = [string]$Manifest.install_name
    $setVars['_ACTIVE_LLVM_PATH'] = $root
    $setVars['LLVMUP_ACTIVE_VERSION'] = [string]$Manifest.install_name
    $setVars['LLVMUP_ACTIVE_PATH'] = $root
    $setVars['LLVMUP_ACTIVE_ID'] = [string]$Manifest.id
    $setVars['LLVMUP_ACTIVE_PROVIDER'] = $provider
    $setVars['LLVMUP_ACTIVE_COMPILER'] = $effCompiler
    if ($effTarget) { $setVars['LLVMUP_ACTIVE_TARGET'] = $effTarget } else { $unsetVars += 'LLVMUP_ACTIVE_TARGET' }

    $prependPath = @()
    # Target runtime directories (recipe layout.target_runtime_dirs) come first so programs built
    # for the selected target load that target's DLLs, not the host copies in bin/.
    if ($effTarget -and (Get-Command Get-LlvmRecipe -ErrorAction SilentlyContinue)) {
        $recipe = $null
        try { $recipe = Get-LlvmRecipe -Provider $provider } catch {}
        if ($recipe -and $recipe.layout -and $recipe.layout.PSObject.Properties['target_runtime_dirs']) {
            foreach ($pattern in @($recipe.layout.target_runtime_dirs)) {
                $rel = ([string]$pattern).Replace('{target}', $effTarget).Replace('/', [IO.Path]::DirectorySeparatorChar)
                $dir = Join-Path $root $rel
                if (Test-Path -LiteralPath $dir -PathType Container) { $prependPath += $dir }
            }
        }
    }
    if (Test-Path -LiteralPath $binDir -PathType Container) { $prependPath += $binDir }

    return [pscustomobject][ordered]@{
        manifest = $Manifest
        provider = $provider
        compiler = $effCompiler
        target = $effTarget
        prepend_path = $prependPath
        set = $setVars
        unset = $unsetVars
    }
}

function Apply-LlvmEnvironmentDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Delta,
        [switch]$SetSessionOverride
    )

    # Restore original environment before applying a new delta so switching between
    # providers never leaks incompatible variables or duplicates PATH entries.
    if ($env:_LLVM_BACKUP) {
        $null = Restore-LlvmEnvironment
    }

    $null = Backup-LlvmEnvironment
    Clear-LlvmSysEnvironmentVariables

    $sep = [string][IO.Path]::PathSeparator
    if ($Delta.prepend_path -and $Delta.prepend_path.Count -gt 0) {
        $newPath = ($Delta.prepend_path -join $sep)
        if ($env:PATH) { $env:PATH = "$newPath$sep$($env:PATH)" } else { $env:PATH = $newPath }
    }

    foreach ($varName in $Delta.unset) {
        Remove-Item -LiteralPath "Env:$varName" -ErrorAction SilentlyContinue
    }
    foreach ($key in $Delta.set.Keys) {
        Set-Item -LiteralPath "Env:$key" -Value ([string]$Delta.set[$key])
    }

    if ($SetSessionOverride) {
        Set-Item -LiteralPath 'Env:LLVMUP_SESSION_OVERRIDE' -Value ([string]$Delta.manifest.install_name)
    }

    return $true
}

function Format-LlvmEnvironmentDeltaExports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Delta,
        [ValidateSet('powershell', 'shell', 'sh', 'bash', 'cmd', 'github', 'json')]
        [string]$Format = 'powershell'
    )
    if ($Format -in @('sh', 'bash')) { $Format = 'shell' }

    if ($Format -eq 'json') {
        return ([ordered]@{
            schema = 1
            prepend_path = @($Delta.prepend_path)
            set = $Delta.set
            unset = @($Delta.unset)
        } | ConvertTo-Json -Depth 5)
    }

    if ($Format -eq 'cmd') {
        # Output is meant for: for /f "delims=" %i in ('llvmup env <tc> --format cmd') do %i
        $cmdOut = @()
        foreach ($u in $Delta.unset) { $cmdOut += "set `"$u=`"" }
        foreach ($key in $Delta.set.Keys) { $cmdOut += "set `"$key=$($Delta.set[$key])`"" }
        if ($Delta.prepend_path.Count -gt 0) {
            # %PATH% would not be re-expanded inside "for /f ... do %i"; the child inherits the caller's
            # PATH, so emit the fully expanded value.
            $cmdOut += "set `"PATH=$($Delta.prepend_path -join ';');$($env:PATH)`""
        }
        return ($cmdOut -join "`r`n")
    }

    $sep = [string][IO.Path]::PathSeparator
    if ($Format -eq 'github') {
        if (-not $env:GITHUB_PATH -or -not $env:GITHUB_ENV) {
            throw 'GITHUB_PATH and GITHUB_ENV are required for github format'
        }
        # Each GITHUB_PATH line is prepended to PATH, so write in reverse to keep the delta's order.
        $ordered = @($Delta.prepend_path)
        [array]::Reverse($ordered)
        foreach ($p in $ordered) {
            Add-Content -LiteralPath $env:GITHUB_PATH -Value $p
        }
        $lines = @()
        foreach ($key in $Delta.set.Keys) {
            if ($key.StartsWith('_')) { continue }
            $lines += "$key=$($Delta.set[$key])"
        }
        $lines | Add-Content -LiteralPath $env:GITHUB_ENV
        return
    }

    if ($Format -eq 'powershell') {
        $out = @()
        if ($Delta.prepend_path.Count -gt 0) {
            $joined = ($Delta.prepend_path -join $sep).Replace("'", "''")
            $out += "`$env:PATH = '$joined' + [IO.Path]::PathSeparator + `$env:PATH"
        }
        foreach ($u in $Delta.unset) {
            $out += "Remove-Item -LiteralPath 'Env:$u' -ErrorAction SilentlyContinue"
        }
        foreach ($key in $Delta.set.Keys) {
            $escaped = ([string]$Delta.set[$key]).Replace("'", "''")
            $out += "`$env:$key = '$escaped'"
        }
        return ($out -join "`n")
    }

    # POSIX shell format
    $shOut = @()
    if ($Delta.prepend_path.Count -gt 0) {
        $joined = ($Delta.prepend_path -join ':').Replace("'", "'\''")
        $shOut += "export PATH='$joined':`"`$PATH`""
    }
    foreach ($u in $Delta.unset) {
        $shOut += "unset $u"
    }
    foreach ($key in $Delta.set.Keys) {
        $escaped = ([string]$Delta.set[$key]).Replace("'", "'\''")
        $shOut += "export $key='$escaped'"
    }
    return ($shOut -join "`n")
}

Export-ModuleMember -Function @(
    'Get-LlvmEnvironmentDelta',
    'Apply-LlvmEnvironmentDelta',
    'Format-LlvmEnvironmentDeltaExports'
)
