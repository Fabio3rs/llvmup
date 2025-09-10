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
$homeDir = Get-UserHome
$script:LLVM_HOME = Join-Path $homeDir ".llvm"
$script:TOOLCHAINS_DIR = Join-Path $script:LLVM_HOME "toolchains"

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
                Where-Object { $_.Name -like "$wordToComplete*" } |
                ForEach-Object { $_.Name }
        }
    }

    # Import core implementation from Llvm-Functions-Core.psm1 to avoid duplication
    $coreModulePath = Join-Path $PSScriptRoot '..\Llvm-Functions-Core.psm1'
    if (Test-Path $coreModulePath) { Import-Module -Force $coreModulePath }

    $result = @{
        installed_versions = $versionObjects
        active_version = $env:_ACTIVE_LLVM
    }

    return $result | ConvertTo-Json -Depth 3
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
    } else {
        Write-LlvmLog "No LLVM version is currently active" -Level Error
        return $null
    }
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

        Get-ChildItem $script:TOOLCHAINS_DIR -Directory |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object { $_.Name }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Activate-Llvm',
    'Deactivate-Llvm',
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
