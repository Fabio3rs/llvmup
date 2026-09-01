# Llvm-Functions.psm1: PowerShell module for LLVM version management
# This module should be imported in the user's PowerShell profile
#
# Usage after importing:
#   Activate-Llvm <version>    - Activate an LLVM version
#   Deactivate-Llvm           - Deactivate current LLVM version
#   Get-LlvmStatus            - Show current status
#   Get-LlvmList              - List installed versions
#   Initialize-LlvmConfig     - Initialize .llvmup-config
#   Import-LlvmConfig         - Load project config

$modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
$coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
if (Test-Path $coreModulePath) { Import-Module $coreModulePath -Force -DisableNameChecking }
$homeDir = Get-UserHome
$script:LLVM_HOME = if ($env:LLVM_HOME) { $env:LLVM_HOME } elseif ($env:LLVM_CUSTOM_HOME) { $env:LLVM_CUSTOM_HOME } else { Join-Path $homeDir ".llvm" }
$script:TOOLCHAINS_DIR = if ($env:LLVM_TOOLCHAINS_DIR) { $env:LLVM_TOOLCHAINS_DIR } elseif ($env:LLVM_CUSTOM_TOOLCHAINS_DIR) { $env:LLVM_CUSTOM_TOOLCHAINS_DIR } else { Join-Path $script:LLVM_HOME "toolchains" }

# Auto-import completion module when running interactively
try {
    if ($Host.Name -ne 'ServerRemoteHost' -and $Host.UI.RawUI) {
        $compModule = Join-Path $PSScriptRoot 'Llvm-Completion.psm1'
        if (Test-Path $compModule) {
            # Import idempotently
            if (-not (Get-Module -ListAvailable -Name Llvm-Completion)) {
                Import-Module -Force $compModule | Out-Null
            }
        }
    }
} catch {}

function Write-LlvmLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )

    $color = switch ($Level) {
        "Info" { "Cyan" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
    }

    $emoji = switch ($Level) {
        "Info" { "📋" }
        "Warning" { "⚠️ " }
        "Error" { "❌" }
        "Success" { "✅" }
    }

    Write-Host "$emoji $Message" -ForegroundColor $color
}

function Activate-Llvm {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Version
    )

    if (-not $Version) {
        Write-Host "╭─ LLVM Activation Help ─────────────────────────────────────╮" -ForegroundColor Cyan
        Write-Host "│ Usage: Activate-Llvm <version>                            │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ Examples:                                                  │" -ForegroundColor White
        Write-Host "│   Activate-Llvm 18.1.8     # Activate specific version    │" -ForegroundColor White
        Write-Host "│   Activate-Llvm 19.1.0     # Activate another version     │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ What this does:                                            │" -ForegroundColor White
        Write-Host "│ • Sets PATH to use LLVM tools (clang, clang++, etc.)      │" -ForegroundColor White
        Write-Host "│ • Updates environment variables                            │" -ForegroundColor White
        Write-Host "│ • Modifies prompt to show active LLVM version             │" -ForegroundColor White
        Write-Host "│                                                            │" -ForegroundColor White
        Write-Host "│ To deactivate: Deactivate-Llvm                            │" -ForegroundColor White
        Write-Host "│ To check status: Get-LlvmStatus                           │" -ForegroundColor White
        Write-Host "╰────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
        Write-Host ""
        if (Test-Path $script:TOOLCHAINS_DIR) {
            Get-ChildItem $script:TOOLCHAINS_DIR -Directory |
                ForEach-Object { $_.Name }
        }
        return
    }

    # Import core implementation from Llvm-Functions-Core.psm1 to avoid duplication
    $coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
    if (-not (Test-Path $coreModulePath)) {
        $coreModulePath = Join-Path $PSScriptRoot '..\Llvm-Functions-Core.psm1'
    }
    if (Test-Path $coreModulePath) { Import-Module -Force -DisableNameChecking $coreModulePath }

    # Delegate activation to core implementation if available
    if (Get-Command -Name Invoke-LlvmActivate -ErrorAction SilentlyContinue) {
        try {
            return Invoke-LlvmActivate -Version $Version
        } catch {
            Write-LlvmLog "Activation failed: $($_.Exception.Message)" -Level Error
            return $false
        }
    } else {
        Write-LlvmLog "Core activation function not available (Invoke-LlvmActivate)" -Level Error
        return $false
    }
}

function Test-LlvmVersionExists {
    <#
    .SYNOPSIS
    Check if a specific LLVM version is installed

    .PARAMETER Version
    The version identifier to check

    .EXAMPLE
    Test-LlvmVersionExists "llvmorg-18.1.8"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $versionPath = Join-Path $script:TOOLCHAINS_DIR $Version
    return Test-Path $versionPath
}

function Get-LlvmActiveVersion {
    <#
    .SYNOPSIS
    Get the currently active LLVM version

    .EXAMPLE
    Get-LlvmActiveVersion
    #>
    [CmdletBinding()]
    param()

    if ($env:_ACTIVE_LLVM) {
        return $env:_ACTIVE_LLVM
    }
    return $null
}

function Compare-LlvmVersion {
    <#
    .SYNOPSIS
    Compare two LLVM version strings

    .PARAMETER Version1
    First version to compare

    .PARAMETER Version2
    Second version to compare

    .OUTPUTS
    Returns 1 if Version1 > Version2, 0 if equal, -1 if Version1 < Version2

    .EXAMPLE
    Compare-LlvmVersion "18.1.8" "19.1.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version1,

        [Parameter(Mandatory = $true)]
        [string]$Version2
    )

    $v1 = ConvertFrom-LlvmVersion $Version1
    $v2 = ConvertFrom-LlvmVersion $Version2

    if (-not $v1 -or -not $v2) { return $null }

    try {
        # Simple normalization for version comparison
        $semver1 = [System.Version]($v1 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Substring(0, [Math]::Min(7, ($v1 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Length))
        $semver2 = [System.Version]($v2 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Substring(0, [Math]::Min(7, ($v2 -replace '^(\d+(?:\.\d+)?).*', '$1.0.0').Length))
        return $semver1.CompareTo($semver2)
    }
    catch {
        # Fallback to string comparison
        if ($v1 -eq $v2) { return 0 }
        if ($v1 -gt $v2) { return 1 }
        return -1
    }
}

function Get-LlvmLatestVersion {
    <#
    .SYNOPSIS
    Find the latest installed LLVM version

    .EXAMPLE
    Get-LlvmLatestVersion
    #>
    [CmdletBinding()]
    param()

    $versions = Get-LlvmVersionsSimple

    if (-not $versions) {
        Write-LlvmLog "No LLVM versions installed" -Level Error
        return $null
    }

    $parsedVersions = @()
    foreach ($version in $versions) {
        $parsed = ConvertFrom-LlvmVersion $version
        if ($parsed) {
            $parsedVersions += @{
                Original = $version
                Parsed = $parsed
            }
        }
    }

    if ($parsedVersions.Count -eq 0) {
        return $versions | Select-Object -Last 1
    }

    # Sort by parsed version and get the latest
    $latest = $parsedVersions | Sort-Object { [System.Version]$_.Parsed } | Select-Object -Last 1
    return $latest.Original
}

function Normalize-LlvmSemver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    # Convert inputs like '18', '18.1' or '18.1.8' into '18.1.8' form
    if (-not $Version) { return $null }
    $parts = $Version -split '\.'
    while ($parts.Count -lt 3) { $parts += '0' }
    return ($parts[0..2] -join '.')
}

function Invoke-LlvmParseVersionExpression {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)] [string]$Expression)

    $expr = $Expression.Trim()

    if ($expr -eq 'latest') { return @{ kind='selector'; selector='latest' } }
    if ($expr -eq 'oldest') { return @{ kind='selector'; selector='oldest' } }
    if ($expr -eq 'prebuilt') { return @{ kind='type'; type='prebuilt' } }
    if ($expr -eq 'source') { return @{ kind='type'; type='source' } }

    if ($expr -match '^~\s*(\d+(?:\.\d+)*)$') {
        return @{ kind='range'; range=@{ op='~'; version=$matches[1] } }
    }

    if ($expr -match '^(>=|<=|>|<|=)\s*(.+)$') {
        return @{ kind='range'; range=@{ op=$matches[1]; version=$matches[2] } }
    }

    if ($expr -match '\*$') {
        return @{ kind='wildcard'; wildcard=$expr }
    }

    return @{ kind='specific'; specific=$expr }
}

function Invoke-LlvmVersionMatchesRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CandidateVersion,
        [Parameter(Mandatory=$true)]
        [string]$RangeExpression
    )

    # Normalize candidate parsed version
    $cand = ConvertFrom-LlvmVersion $CandidateVersion
    if (-not $cand) { return $false }
    $candNorm = Normalize-LlvmSemver $cand

    $parsed = Invoke-LlvmParseVersionExpression -Expression $RangeExpression
    if (-not $parsed) { return $false }

    switch ($parsed.kind) {
        'range' {
            $op = $parsed.range.op
            $ver = $parsed.range.version
            if ($op -eq '~') {
                # Tilde range: >= ver.0 and < next minor
                $baseParts = ($ver -split '\.')
                $major = [int]$baseParts[0]
                $minor = if ($baseParts.Count -ge 2) { [int]$baseParts[1] } else { 0 }
                $min = Normalize-LlvmSemver "$major.$minor.0"
                $nextMinor = Normalize-LlvmSemver "$major.$([int]($minor + 1)).0"
                $cmpMin = Compare-LlvmVersion $candNorm $min
                $cmpMax = Compare-LlvmVersion $candNorm $nextMinor
                # Compare-LlvmVersion returns -1/0/1 semantics; ensure inclusive lower bound and exclusive upper
                if (($cmpMin -ge 0) -and ($cmpMax -lt 0)) { return $true } else { return $false }
            } else {
                $targetNorm = Normalize-LlvmSemver (ConvertFrom-LlvmVersion $ver)
                $cmp = Compare-LlvmVersion $candNorm $targetNorm
                switch ($op) {
                    '>'  { return ($cmp -gt 0) }
                    '>=' { return ($cmp -ge 0) }
                    '<'  { return ($cmp -lt 0) }
                    '<=' { return ($cmp -le 0) }
                    '='  { return ($cmp -eq 0) }
                }
            }
        }
        'wildcard' {
            # e.g. 18.* -> match major
            if ($parsed.wildcard -match '^([0-9]+)\.') {
                $maj = $matches[1]
                if ($cand -match "^$maj\\.") { return $true } else { return $false }
            }
            return $false
        }
        default {
            # Unknown kind: return false
            return $false
        }
    }
}

function Invoke-LlvmMatchVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Expression
    )

    $parsed = Invoke-LlvmParseVersionExpression -Expression $Expression
    if (-not $parsed) { return @() }

    $installed = Get-LlvmVersionsSimple
    if (-not $installed) { return @() }

    $matches = @()

    switch ($parsed.kind) {
        'selector' {
            $type = $parsed.type
            if ($parsed.selector -eq 'latest') {
                if ($type -eq 'prebuilt') {
                    # choose latest non-source
                    $cand = $installed | Where-Object { $_ -notmatch '^source-' } | ForEach-Object { $_ }
                } elseif ($type -eq 'source') {
                    $cand = $installed | Where-Object { $_ -match '^source-' } | ForEach-Object { $_ }
                } else {
                    $cand = $installed
                }
                if ($cand) {
                    $sorted = $cand | Sort-Object { [System.Version](Normalize-LlvmSemver (ConvertFrom-LlvmVersion $_)) }
                    return ,($sorted | Select-Object -Last 1)
                }
                return @()
            }
            if ($parsed.selector -eq 'oldest') {
                if ($type -eq 'prebuilt') {
                    $cand = $installed | Where-Object { $_ -notmatch '^source-' }
                } elseif ($type -eq 'source') {
                    $cand = $installed | Where-Object { $_ -match '^source-' }
                } else {
                    $cand = $installed
                }
                if ($cand) {
                    $sorted = $cand | Sort-Object { [System.Version](Normalize-LlvmSemver (ConvertFrom-LlvmVersion $_)) }
                    return ,($sorted | Select-Object -First 1)
                }
                return @()
            }
        }
        'type' {
            if ($parsed.type -eq 'prebuilt') { return $installed | Where-Object { $_ -notmatch '^source-' } }
            if ($parsed.type -eq 'source') { return $installed | Where-Object { $_ -match '^source-' } }
            return @()
        }
        'wildcard' {
            $pat = '^' + ($parsed.wildcard -replace '\*', '.*')
            return $installed | Where-Object { $_ -match $pat }
        }
        'specific' {
            $target = $parsed.specific
            # exact match first
            $exact = $installed | Where-Object { $_ -eq $target }
            if ($exact) { return $exact }
            # fallback: match by numeric parsed version
            $targetNum = ConvertFrom-LlvmVersion $target
            if ($targetNum) { return $installed | Where-Object { (ConvertFrom-LlvmVersion $_) -eq $targetNum } }
            return @()
        }
        'range' {
            $res = @()
            foreach ($v in $installed) {
                if (Invoke-LlvmVersionMatchesRange -CandidateVersion $v -RangeExpression $parsed.raw) { $res += $v }
            }
            return $res
        }
        default { return @() }
    }
}

function Invoke-LlvmAutoActivate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$StartDirectory = (Get-Location).Path
    )

    # Walk up looking for .llvmup-config
    $dir = Resolve-Path -Path $StartDirectory
    while ($dir) {
        $config = Join-Path $dir '.llvmup-config'
        if (Test-Path $config) {
            Import-LlvmConfig
            return
        }
        $parent = Split-Path $dir -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

function Get-LlvmDiskUsage {
    <#
    .SYNOPSIS
    Get disk usage for installed LLVM toolchains

    .PARAMETER HumanReadable
    Include a formatted human-readable size column
    #>
    [CmdletBinding()]
    param(
        [switch]$HumanReadable
    )

    $coreModulePath = Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1'
    if (-not (Test-Path $coreModulePath)) {
        $coreModulePath = Join-Path $PSScriptRoot '..\Llvm-Functions-Core.psm1'
    }
    if (Test-Path $coreModulePath) { Import-Module -Force -DisableNameChecking $coreModulePath }

    if (-not (Get-Command -Name Get-LlvmDiskUsageData -ErrorAction SilentlyContinue)) {
        throw "Core disk usage function not available (Get-LlvmDiskUsageData)"
    }

    $toolchainsPath = if ($env:LLVM_TOOLCHAINS_DIR) {
        $env:LLVM_TOOLCHAINS_DIR
    } elseif ($env:LLVM_CUSTOM_TOOLCHAINS_DIR) {
        $env:LLVM_CUSTOM_TOOLCHAINS_DIR
    } else {
        $script:TOOLCHAINS_DIR
    }

    $results = Get-LlvmDiskUsageData -ToolchainsPath $toolchainsPath -HumanReadable:$HumanReadable
    if (-not $results) {
        Write-LlvmLog "No LLVM toolchains found" -Level Info
        return @()
    }

    return $results
}

function Deactivate-Llvm {
    [CmdletBinding()]
    param()
    return Invoke-LlvmDeactivate
}

function Get-LlvmStatus {
    [CmdletBinding()]
    param()

    $active = Get-LlvmActiveVersion
    if (-not $active) {
        return [pscustomobject]@{ Status = 'INACTIVE'; Version = $null; Path = $null }
    }
    $toolchainsPath = Get-LlvmSessionToolchainsPath
    return [pscustomobject]@{
        Status = 'ACTIVE'
        Version = $active
        Path = Join-Path $toolchainsPath $active
    }
}

function Get-LlvmList {
    [CmdletBinding()]
    param([switch]$Remote, [switch]$Json)

    if ($Remote) {
        $downloadScript = Join-Path $PSScriptRoot 'Download-Llvm.ps1'
        if (-not (Test-Path -LiteralPath $downloadScript)) { throw 'Download-Llvm.ps1 was not found' }
        $format = if ($Json) { 'Json' } else { 'Text' }
        return & $downloadScript -ListOnly -OutputFormat $format -Quiet
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $active = Get-LlvmActiveVersion
    $default = Get-LlvmDefaultVersion
    $versions = @()
    if (Test-Path -LiteralPath $toolchainsPath) {
        $versions = @(Get-ChildItem -LiteralPath $toolchainsPath -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name | ForEach-Object {
                [pscustomobject]@{
                    name = $_.Name
                    version = $_.Name -replace '^(source-)?llvmorg-', ''
                    type = if ($_.Name -like 'source-*') { 'source' } else { 'prebuilt' }
                    active = $_.Name -eq $active
                    default = $_.Name -eq $default
                    path = $_.FullName
                }
            })
    }

    if ($Json) {
        return [pscustomobject]@{
            installed_versions = $versions
            active_version = $active
            default_version = $default
        } | ConvertTo-Json -Depth 5
    }
    return $versions
}

function Find-LlvmConfigRoot {
    [CmdletBinding()]
    param([string]$StartDirectory = (Get-Location).Path)

    $current = [IO.Path]::GetFullPath($StartDirectory)
    while ($current) {
        if (Test-Path -LiteralPath (Join-Path $current '.llvmup-config') -PathType Leaf) { return $current }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Import-LlvmConfig {
    [CmdletBinding()]
    param([string]$StartDirectory = (Get-Location).Path)

    $root = Find-LlvmConfigRoot -StartDirectory $StartDirectory
    if (-not $root) { throw 'No .llvmup-config file found' }
    $path = Join-Path $root '.llvmup-config'
    $section = ''
    $version = $null
    $name = $null
    $autoActivate = $true
    foreach ($rawLine in Get-Content -LiteralPath $path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }
        if ($line -match '^\[(.+)\]$') { $section = $matches[1].ToLowerInvariant(); continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key = $parts[0].Trim().ToLowerInvariant()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($section -eq 'version' -and $key -eq 'default') { $version = $value }
        if ($section -eq 'build' -and $key -eq 'name') { $name = $value }
        if ($section -eq 'project' -and $key -eq 'auto_activate') { $autoActivate = $value.ToLowerInvariant() -ne 'false' }
    }
    if (-not $version) { throw "No version.default value was found in $path" }
    return [pscustomobject]@{ Root = $root; Path = $path; Version = $version; Name = $name; AutoActivate = $autoActivate }
}

function Initialize-LlvmConfig {
    [CmdletBinding()]
    param()
    $installScript = Join-Path $PSScriptRoot 'Install-Llvm.ps1'
    return & $installScript config init
}

function Show-LlvmHelp {
    @'
LLVMUP for PowerShell

Usage: llvmup [COMMAND] [OPTIONS] [VERSION]

Commands:
  install, activate, deactivate, env, resolve, vscode-activate
  status, list, remove, disk-usage, default, config, help

Examples:
  llvmup install 21.1.0
  llvmup activate llvmorg-21.1.0
  llvmup list --remote
  llvmup remove llvmorg-20.1.8
  llvmup default unset
'@
}

function Get-LlvmVersions { param([string]$Format = 'list') switch ($Format.ToLowerInvariant()) { 'json' { Get-LlvmList -Json } 'simple' { Get-LlvmVersionsSimple } default { Get-LlvmList } } }
function Get-LlvmVersionsSimple { @(Get-LlvmList | ForEach-Object { $_.name }) }
function Get-LlvmVersionsList { Get-LlvmList }
function Get-LlvmVersionsJson { Get-LlvmList -Json }

function Invoke-LlvmUpInstall {
    param([string[]]$Tokens)

    $fromSource = $false
    $listOnly = $false
    $setDefault = $false
    $quiet = $false
    $verboseMode = $false
    $name = $null
    $profile = $null
    $verify = $null
    $version = $null
    $cmakeFlags = @()
    $components = @()
    $disableLibcWnoError = $false
    $reconfigure = $false

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = $Tokens[$i]
        switch ($token) {
            '--from-source' { $fromSource = $true }
            '--list-only' { $listOnly = $true }
            '--default' { $setDefault = $true }
            '--quiet' { $quiet = $true }
            '-q' { $quiet = $true }
            '--verbose' { $verboseMode = $true }
            '-v' { $verboseMode = $true }
            '--disable-libc-wno-error' { $disableLibcWnoError = $true }
            '--reconfigure' { $reconfigure = $true }
            '--name' { if (++$i -ge $Tokens.Count) { throw '--name requires a value' }; $name = $Tokens[$i] }
            '-n' { if (++$i -ge $Tokens.Count) { throw '-n requires a value' }; $name = $Tokens[$i] }
            '--profile' { if (++$i -ge $Tokens.Count) { throw '--profile requires a value' }; $profile = $Tokens[$i] }
            '-p' { if (++$i -ge $Tokens.Count) { throw '-p requires a value' }; $profile = $Tokens[$i] }
            '--verify' { if (++$i -ge $Tokens.Count) { throw '--verify requires a value' }; $verify = $Tokens[$i] }
            '--cmake-flags' { if (++$i -ge $Tokens.Count) { throw '--cmake-flags requires a value' }; $cmakeFlags += $Tokens[$i] }
            '-c' { if (++$i -ge $Tokens.Count) { throw '-c requires a value' }; $cmakeFlags += $Tokens[$i] }
            '--component' { if (++$i -ge $Tokens.Count) { throw '--component requires a value' }; $components += $Tokens[$i] }
            '-h' { Show-LlvmHelp; return }
            '--help' { Show-LlvmHelp; return }
            default {
                if ($token.StartsWith('-')) { throw "Unknown install option: $token" }
                if ($version) { throw 'Only one LLVM version can be installed at a time' }
                $version = $token
            }
        }
    }

    if (-not $version) { $version = 'latest' }
    $downloadScript = Join-Path $PSScriptRoot 'Download-Llvm.ps1'
    if ($listOnly) { return & $downloadScript -ListOnly -OutputFormat Text -Quiet }

    if ($fromSource) {
        if ($verify) { throw '--verify applies only to prebuilt releases' }
        $installScript = Join-Path $PSScriptRoot 'Install-Llvm.ps1'
        $parameters = @{ FromSource = $true }
        if ($name) { $parameters.Name = $name }
        if ($profile) { $parameters.Profile = $profile }
        if ($cmakeFlags.Count) { $parameters.CmakeFlags = $cmakeFlags }
        if ($components.Count) { $parameters.Component = $components }
        if ($setDefault) { $parameters.Default = $true }
        if ($disableLibcWnoError) { $parameters.DisableLibcWnoError = $true }
        if ($reconfigure) { $parameters.Reconfigure = $true }
        if ($verboseMode) { $parameters.VerboseMode = $true }
        if ($quiet) { $parameters.Quiet = $true }
        return & $installScript install $version @parameters
    }

    if ($profile -or $cmakeFlags.Count -or $components.Count -or $disableLibcWnoError -or $reconfigure) {
        throw 'Source build options require --from-source'
    }
    $downloadParameters = @{ Version = $version }
    if ($name) { $downloadParameters.Name = $name }
    if ($verify) { $downloadParameters.VerifyPolicy = $verify }
    if ($quiet) { $downloadParameters.Quiet = $true }
    if ($verboseMode) { $downloadParameters.Verbose = $true }

    $defaultTarget = $name
    if ($setDefault -and -not $defaultTarget) {
        $resolvedText = (& $downloadScript -Version $version -ResolveOnly -OutputFormat Json -Quiet | Out-String)
        $defaultTarget = ($resolvedText | ConvertFrom-Json).version
    }
    & $downloadScript @downloadParameters
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { return $false }
    if ($setDefault) { return Set-LlvmDefaultVersion -Version $defaultTarget }
}

function Invoke-LlvmUpResolve {
    param([string[]]$Tokens)
    $version = 'latest'
    $format = 'Text'
    $platform = $null
    $arch = $null
    $useConfig = $false
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--format' {
                if (++$i -ge $Tokens.Count) { throw '--format requires a value' }
                if ($Tokens[$i] -notin @('tag', 'json')) { throw '--format must be tag or json' }
                $format = if ($Tokens[$i] -eq 'json') { 'Json' } else { 'Text' }
            }
            '--platform' { if (++$i -ge $Tokens.Count) { throw '--platform requires a value' }; $platform = $Tokens[$i] }
            '--arch' { if (++$i -ge $Tokens.Count) { throw '--arch requires a value' }; $arch = $Tokens[$i] }
            '--config' { $useConfig = $true }
            default { if ($Tokens[$i].StartsWith('-')) { throw "Unknown resolve option: $($Tokens[$i])" }; $version = $Tokens[$i] }
        }
    }
    if ($useConfig) { $version = (Import-LlvmConfig).Version }
    $parameters = @{ Version = $version; ResolveOnly = $true; OutputFormat = $format; Quiet = $true }
    if ($platform) { $parameters.Platform = $platform }
    if ($arch) { $parameters.Arch = $arch }
    & (Join-Path $PSScriptRoot 'Download-Llvm.ps1') @parameters
}

function Resolve-LlvmUpConfigVersion {
    $config = Import-LlvmConfig
    if ($config.Name -and (Test-LlvmVersionExists $config.Name)) { return $config.Name }
    if (Test-LlvmVersionExists $config.Version) { return $config.Version }
    $matches = @(Invoke-LlvmMatchVersions -Expression $config.Version -ToolchainsPath (Get-LlvmSessionToolchainsPath))
    if (-not $matches.Count) { throw "No installed LLVM version matches '$($config.Version)'" }
    return $matches[0]
}

function Invoke-LlvmUpEnv {
    param([string[]]$Tokens)
    $format = 'powershell'
    $useConfig = $false
    $version = $null
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--config' { $useConfig = $true }
            '--format' { if (++$i -ge $Tokens.Count) { throw '--format requires a value' }; $format = $Tokens[$i].ToLowerInvariant() }
            default { if ($Tokens[$i].StartsWith('-')) { throw "Unknown env option: $($Tokens[$i])" }; $version = $Tokens[$i] }
        }
    }
    if ($useConfig) { $version = Resolve-LlvmUpConfigVersion }
    if (-not $version) { throw "Missing version argument for 'env'" }

    $toolchain = Join-Path (Get-LlvmSessionToolchainsPath) $version
    if (-not (Test-Path -LiteralPath $toolchain -PathType Container)) { throw "LLVM version '$version' is not installed" }
    $bin = Join-Path $toolchain 'bin'
    $clang = Join-Path $bin 'clang.exe'
    if (-not (Test-Path -LiteralPath $clang)) { $clang = Join-Path $bin 'clang' }
    $clangxx = Join-Path $bin 'clang++.exe'
    if (-not (Test-Path -LiteralPath $clangxx)) { $clangxx = Join-Path $bin 'clang++' }

    if ($format -eq 'github') {
        if (-not $env:GITHUB_PATH -or -not $env:GITHUB_ENV) { throw 'GITHUB_PATH and GITHUB_ENV are required for github format' }
        Add-Content -LiteralPath $env:GITHUB_PATH -Value $bin
        @("CC=$clang", "CXX=$clangxx", "LLVMUP_ACTIVE_VERSION=$version", "LLVMUP_ACTIVE_PATH=$toolchain") |
            Add-Content -LiteralPath $env:GITHUB_ENV
        return
    }
    if ($format -notin @('powershell', 'shell')) { throw "Unsupported env format: $format" }
    $escapedBin = $bin.Replace("'", "''")
    $escapedClang = $clang.Replace("'", "''")
    $escapedClangxx = $clangxx.Replace("'", "''")
    $escapedVersion = $version.Replace("'", "''")
    $escapedToolchain = $toolchain.Replace("'", "''")
    Write-Output "`$env:PATH = '$escapedBin' + [IO.Path]::PathSeparator + `$env:PATH"
    Write-Output "`$env:CC = '$escapedClang'"
    Write-Output "`$env:CXX = '$escapedClangxx'"
    Write-Output "`$env:LLVMUP_ACTIVE_VERSION = '$escapedVersion'"
    Write-Output "`$env:LLVMUP_ACTIVE_PATH = '$escapedToolchain'"
}

function Invoke-LlvmUpConfig {
    param([string[]]$Tokens)
    $action = if ($Tokens.Count) { $Tokens[0].ToLowerInvariant() } else { '' }
    switch ($action) {
        'init' { return Initialize-LlvmConfig }
        'load' { return Import-LlvmConfig }
        'apply' {
            $config = Import-LlvmConfig
            Push-Location $config.Root
            try { return & (Join-Path $PSScriptRoot 'Install-Llvm.ps1') config apply }
            finally { Pop-Location }
        }
        'activate' {
            $version = Resolve-LlvmUpConfigVersion
            $active = Get-LlvmActiveVersion
            if ($active -and $active -ne $version) { $null = Deactivate-Llvm }
            return Activate-Llvm $version
        }
        default { throw 'Available config subcommands: init, load, apply, activate' }
    }
}

function llvmup {
    param($First)

    $tokens = @()
    if ($null -ne $First -and [string]$First -ne '') { $tokens += [string]$First }
    $tokens += @($args | ForEach-Object { [string]$_ })
    $knownCommands = @('install', 'activate', 'deactivate', 'env', 'resolve', 'vscode-activate', 'status', 'list', 'remove', 'disk-usage', 'default', 'config', 'help')
    $command = 'install'
    if ($tokens.Count -and $knownCommands -contains $tokens[0].ToLowerInvariant()) {
        $command = $tokens[0].ToLowerInvariant()
        $tokens = @($tokens | Select-Object -Skip 1)
    }

    try {
        switch ($command) {
            'install' { return Invoke-LlvmUpInstall -Tokens $tokens }
            'activate' { if (-not $tokens.Count) { throw "Missing version argument for 'activate'" }; return Activate-Llvm $tokens[0] }
            'deactivate' { return Deactivate-Llvm }
            'env' { return Invoke-LlvmUpEnv -Tokens $tokens }
            'resolve' { return Invoke-LlvmUpResolve -Tokens $tokens }
            'vscode-activate' {
                if (-not $tokens.Count) { throw "Missing version argument for 'vscode-activate'" }
                return & (Join-Path $PSScriptRoot 'Activate-LlvmVsCode.ps1') -Version $tokens[0]
            }
            'status' { return Get-LlvmStatus }
            'list' {
                $unknown = @($tokens | Where-Object { $_ -notin @('--remote', '--json') })
                if ($unknown.Count) { throw "Unknown list option: $($unknown[0])" }
                return Get-LlvmList -Remote:($tokens -contains '--remote') -Json:($tokens -contains '--json')
            }
            'remove' {
                $force = $tokens -contains '--force'
                $versions = @($tokens | Where-Object { $_ -ne '--force' })
                if ($versions.Count -ne 1) { throw 'remove requires exactly one installed LLVM identifier' }
                return Remove-LlvmVersion -Version $versions[0] -Force:$force
            }
            'disk-usage' {
                $unknown = @($tokens | Where-Object { $_ -notin @('-h', '--human-readable') })
                if ($unknown.Count) { throw "Unknown disk-usage option: $($unknown[0])" }
                return Get-LlvmDiskUsage -HumanReadable:($tokens.Count -gt 0)
            }
            'default' {
                $action = if ($tokens.Count) { $tokens[0].ToLowerInvariant() } else { 'show' }
                switch ($action) {
                    'set' { if ($tokens.Count -ne 2) { throw 'default set requires one version' }; return Set-LlvmDefaultVersion -Version $tokens[1] }
                    'show' {
                        $defaultVersion = Get-LlvmDefaultVersion
                        if ($defaultVersion) { return $defaultVersion }
                        Write-Output 'No default LLVM version is set'
                        return
                    }
                    'unset' { return Clear-LlvmDefaultVersion }
                    default { throw 'Available default subcommands: set, show, unset' }
                }
            }
            'config' { return Invoke-LlvmUpConfig -Tokens $tokens }
            'help' { return Show-LlvmHelp }
        }
    } catch {
        Write-Error $_.Exception.Message
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'llvmup',
    'Activate-Llvm',
    'Deactivate-Llvm',
    'Get-LlvmDiskUsage',
    'Get-LlvmStatus',
    'Get-LlvmList',
    'Initialize-LlvmConfig',
    'Import-LlvmConfig',
    'Show-LlvmHelp',
    'ConvertFrom-LlvmVersion',
    'Get-LlvmVersions',
    'Get-LlvmVersionsSimple',
    'Get-LlvmVersionsList',
    'Get-LlvmVersionsJson',
    'Test-LlvmVersionExists',
    'Get-LlvmActiveVersion',
    'Compare-LlvmVersion',
    'Get-LlvmLatestVersion',
    'Normalize-LlvmSemver',
    'Invoke-LlvmParseVersionExpression',
    'Invoke-LlvmVersionMatchesRange',
    'Invoke-LlvmMatchVersions',
    'Invoke-LlvmAutoActivate'
)
