# Core PowerShell functions for LLVM version management

function ConvertFrom-LlvmVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$VersionString
    )

    if ([string]::IsNullOrEmpty($VersionString)) { return $null }

    # Remove common prefixes and extract components
    $clean = $VersionString -replace '^(source-llvmorg-|llvmorg-|source-)', ''

    # Parse version with optional suffix (e.g., "19.1.5-rc2")
    if ($clean -match '^(\d+(?:\.\d+)*)(?:-(.+))?$') {
        $version = $matches[1]
        $suffix = if ($matches[2]) { $matches[2] } else { '' }

        return @{
            Version = $version
            Suffix = $suffix
            Full = $VersionString
            Display = if ($suffix) { "$version-$suffix" } else { $version }
        }
    }

    return $null
}

function Normalize-LlvmSemver {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)] [string]$Version)

    if ([string]::IsNullOrEmpty($Version)) { return $null }

    # Handle already normalized versions
    if ($Version -match '^\d+\.\d+\.\d+$') {
        return $Version
    }

    # Split version parts
    $parts = $Version -split '\.'

    # Ensure we have at least 3 parts for System.Version compatibility
    while ($parts.Count -lt 3) { $parts += '0' }

    # Take only first 3 parts to avoid System.Version issues
    if ($parts.Count -gt 3) {
        $parts = $parts[0..2]
    }

    return $parts -join '.'
}

function Compare-LlvmVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Version1,
        [Parameter(Mandatory=$true)] [string]$Version2
    )

    $v1Obj = ConvertFrom-LlvmVersion $Version1
    $v2Obj = ConvertFrom-LlvmVersion $Version2

    if (-not $v1Obj -or -not $v2Obj) { return $null }

    # Normalize versions for System.Version comparison
    $v1Norm = Normalize-LlvmSemver $v1Obj.Version
    $v2Norm = Normalize-LlvmSemver $v2Obj.Version

    try {
        $sys1 = [System.Version]$v1Norm
        $sys2 = [System.Version]$v2Norm

        $baseComparison = $sys1.CompareTo($sys2)
        if ($baseComparison -ne 0) { return $baseComparison }

        # If base versions are equal, compare suffixes
        $suffix1 = $v1Obj.Suffix
        $suffix2 = $v2Obj.Suffix

        if (-not $suffix1 -and -not $suffix2) { return 0 }
        if ($suffix1 -and -not $suffix2) { return -1 }  # suffixed < non-suffixed
        if (-not $suffix1 -and $suffix2) { return 1 }   # non-suffixed > suffixed

        # Both have suffixes, compare them
        return [string]::Compare($suffix1, $suffix2, [System.StringComparison]::Ordinal)

    } catch {
        # Fallback to string comparison
        if ($v1Obj.Display -eq $v2Obj.Display) { return 0 }
        if ($v1Obj.Display -gt $v2Obj.Display) { return 1 }
        return -1
    }
}

function Invoke-LlvmParseVersionExpression {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)] [string]$Expression)

    $expr = $Expression.Trim().ToLower()

    # Handle combined selectors first
    if ($expr -match '^(latest|newest|oldest|earliest)-(prebuilt|source)$') {
        return @{
            kind = 'combined'
            selector = $matches[1] -replace 'newest', 'latest' -replace 'earliest', 'oldest'
            type = $matches[2]
        }
    }

    # Simple selectors
    if ($expr -in @('latest', 'newest')) {
        return @{ kind = 'selector'; selector = 'latest' }
    }

    if ($expr -in @('oldest', 'earliest')) {
        return @{ kind = 'selector'; selector = 'oldest' }
    }

    # Type filters
    if ($expr -eq 'prebuilt') {
        return @{ kind = 'type'; type = 'prebuilt' }
    }

    if ($expr -eq 'source') {
        return @{ kind = 'type'; type = 'source' }
    }

    # Range expressions
    if ($expr -match '^~\s*(\d+(?:\.\d+)*)$') {
        return @{ kind = 'range'; range = @{ op = '~'; version = $matches[1] } }
    }

    if ($expr -match '^(>=|<=|>|<|=)\s*(.+)$') {
        return @{ kind = 'range'; range = @{ op = $matches[1]; version = $matches[2] } }
    }

    # Wildcard patterns
    if ($expr -match '^(\d+)\.?\*$') {
        return @{ kind = 'wildcard'; pattern = $expr; major = $matches[1] }
    }

    if ($expr -match '^(\d+)\.(\d+)\.?\*$') {
        return @{ kind = 'wildcard'; pattern = $expr; major = $matches[1]; minor = $matches[2] }
    }

    # Specific version (preserve original case)
    if ($Expression -match '^(source-llvmorg-|llvmorg-|source-)?\d+(?:\.\d+)*(?:-[a-zA-Z0-9]+)?$') {
        return @{ kind = 'specific'; specific = $Expression.Trim() }
    }

    throw "Invalid version expression: $Expression"
}

function Invoke-LlvmVersionMatchesRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$CandidateVersion,
        [Parameter(Mandatory=$true)] [string]$RangeExpression
    )

    $candidateObj = ConvertFrom-LlvmVersion $CandidateVersion
    if (-not $candidateObj) { return $false }

    $parsed = Invoke-LlvmParseVersionExpression -Expression $RangeExpression
    if ($parsed.kind -eq 'range' -and $parsed.range.op -eq '~') {
        # Tilde range: ~19.1 means >=19.1.0 and <19.2.0
        $parts = $parsed.range.version -split '\.'
        $major = [int]$parts[0]
        $minor = if ($parts.Count -ge 2) { [int]$parts[1] } else { 0 }

        $minVer = "$major.$minor.0"
        $maxVer = "$major.$([int]($minor + 1)).0"

        # Use normalized comparison
        $candidateNorm = Normalize-LlvmSemver $candidateObj.Version
        $minNorm = Normalize-LlvmSemver $minVer
        $maxNorm = Normalize-LlvmSemver $maxVer

        try {
            $candidateSystemVer = [System.Version]$candidateNorm
            $minSystemVer = [System.Version]$minNorm
            $maxSystemVer = [System.Version]$maxNorm

            return ($candidateSystemVer -ge $minSystemVer) -and ($candidateSystemVer -lt $maxSystemVer)
        } catch {
            # Fallback to string comparison with suffix handling
            $cmpMin = Compare-LlvmVersion $candidateObj.Full $minVer
            $cmpMax = Compare-LlvmVersion $candidateObj.Full $maxVer
            return ($cmpMin -ge 0) -and ($cmpMax -lt 0)
        }
    }

    return $false
}

function Get-LlvmVersionsSimple {
    [CmdletBinding()]
    param([string]$ToolchainsPath = $null)

    # Use provided path or try different potential locations
    $possiblePaths = @()

    if ($ToolchainsPath) {
        $possiblePaths += $ToolchainsPath
    }

    # Load helper and determine home-based defaults
    $modulePath = Join-Path $PSScriptRoot 'Get-UserHome.psm1'
    if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { . "$PSScriptRoot\Get-UserHome.ps1" }
    $homeDir = Get-UserHome

    if ($script:TOOLCHAINS_DIR) {
        $possiblePaths += $script:TOOLCHAINS_DIR
    } else {
        $possiblePaths += Join-Path $homeDir ".llvm\toolchains"
    }
    $possiblePaths += Join-Path $homeDir ".llvm/toolchains"
    $possiblePaths += "/tmp/.llvm/toolchains"
    $possiblePaths += "$(Get-Location)/.llvm/toolchains"

    foreach ($toolchainsDir in $possiblePaths) {
        if ($toolchainsDir -and (Test-Path $toolchainsDir)) {
            Write-Verbose "Found toolchains directory: $toolchainsDir"
            return Get-ChildItem $toolchainsDir -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
        }
    }

    Write-Verbose "No toolchains directory found"
    return @()
}

function Invoke-LlvmMatchVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Expression,
        [string]$ToolchainsPath = $null
    )

    $parsed = Invoke-LlvmParseVersionExpression -Expression $Expression
    if (-not $parsed) { return @() }

    $installed = Get-LlvmVersionsSimple -ToolchainsPath $ToolchainsPath
    if (-not $installed) { return @() }

    switch ($parsed.kind) {
        'combined' {
            # Handle combined selectors like latest-prebuilt, oldest-source
            $typeFilter = $parsed.type
            $selector = $parsed.selector

            # First filter by type
            if ($typeFilter -eq 'prebuilt') {
                $candidates = $installed | Where-Object { $_ -notmatch '^source-' }
            } elseif ($typeFilter -eq 'source') {
                $candidates = $installed | Where-Object { $_ -match '^source-' }
            } else {
                $candidates = $installed
            }

            if (-not $candidates) { return @() }

            # Then apply selector
            if ($selector -eq 'latest') {
                $sorted = $candidates | Sort-Object {
                    $vObj = ConvertFrom-LlvmVersion $_
                    if ($vObj) {
                        $norm = Normalize-LlvmSemver $vObj.Version
                        try { [System.Version]$norm } catch { [System.Version]'0.0.0' }
                    } else {
                        [System.Version]'0.0.0'
                    }
                }
                return ,($sorted | Select-Object -Last 1)
            } elseif ($selector -eq 'oldest') {
                $sorted = $candidates | Sort-Object {
                    $vObj = ConvertFrom-LlvmVersion $_
                    if ($vObj) {
                        $norm = Normalize-LlvmSemver $vObj.Version
                        try { [System.Version]$norm } catch { [System.Version]'0.0.0' }
                    } else {
                        [System.Version]'0.0.0'
                    }
                }
                return ,($sorted | Select-Object -First 1)
            }
        }
        'selector' {
            if ($parsed.selector -eq 'latest') {
                $sorted = $installed | Sort-Object {
                    $vObj = ConvertFrom-LlvmVersion $_
                    if ($vObj) {
                        $norm = Normalize-LlvmSemver $vObj.Version
                        try { [System.Version]$norm } catch { [System.Version]'0.0.0' }
                    } else {
                        [System.Version]'0.0.0'
                    }
                }
                return ,($sorted | Select-Object -Last 1)
            }
            if ($parsed.selector -eq 'oldest') {
                $sorted = $installed | Sort-Object {
                    $vObj = ConvertFrom-LlvmVersion $_
                    if ($vObj) {
                        $norm = Normalize-LlvmSemver $vObj.Version
                        try { [System.Version]$norm } catch { [System.Version]'0.0.0' }
                    } else {
                        [System.Version]'0.0.0'
                    }
                }
                return ,($sorted | Select-Object -First 1)
            }
        }
        'type' {
            if ($parsed.type -eq 'prebuilt') {
                return $installed | Where-Object { $_ -notmatch '^source-' }
            }
            if ($parsed.type -eq 'source') {
                return $installed | Where-Object { $_ -match '^source-' }
            }
        }
        'wildcard' {
            if ($parsed.major -and $parsed.minor) {
                # 18.1.* pattern
                $pattern = "^(source-llvmorg-|llvmorg-|source-)?$($parsed.major)\.$($parsed.minor)\."
                return $installed | Where-Object { $_ -match $pattern }
            } elseif ($parsed.major) {
                # 18.* pattern
                $pattern = "^(source-llvmorg-|llvmorg-|source-)?$($parsed.major)\."
                return $installed | Where-Object { $_ -match $pattern }
            } else {
                # Fallback to original pattern
                $pattern = '^' + ($parsed.pattern -replace '\*','.*') + '$'
                return $installed | Where-Object { $_ -match $pattern }
            }
        }
        'specific' {
            $target = $parsed.specific
            # Exact match first
            $exact = $installed | Where-Object { $_ -eq $target }
            if ($exact) { return $exact }

            # Fallback: match by normalized version
            $targetObj = ConvertFrom-LlvmVersion $target
            if ($targetObj) {
                $targetNorm = Normalize-LlvmSemver $targetObj.Version
                return $installed | Where-Object {
                    $candObj = ConvertFrom-LlvmVersion $_
                    if ($candObj) {
                        $candNorm = Normalize-LlvmSemver $candObj.Version
                        return $candNorm -eq $targetNorm
                    }
                    return $false
                }
            }
            return @()
        }
        'range' {
            $res = @()
            foreach ($v in $installed) {
                if (Invoke-LlvmVersionMatchesRange -CandidateVersion $v -RangeExpression ($parsed.range.op + $parsed.range.version)) {
                    $res += $v
                }
            }
            return $res
        }
        default { return @() }
    }
}

function Invoke-LlvmAutoActivate {
    [CmdletBinding()]
    param([string]$StartDirectory = (Get-Location).Path)

    $config = Join-Path $StartDirectory '.llvmup-config'
    if (Test-Path $config) {
        $lines = Get-Content $config
        foreach ($line in $lines) {
            $trim = $line.Trim()
            if ($trim -like '[*]') { continue }
            if ($trim -notlike '*=*') { continue }

            # Split on first '=' and extract right-hand side
            $parts = $trim -split '=', 2
            if ($parts.Count -lt 2) { continue }
            $value = $parts[1].Trim()

            # Unescape common escape sequences (e.g. \" or `") produced by test fixtures
                $value = $value -replace '\\"', '"' -replace "\\'", "'"

            # Remove leading/trailing backticks or backslashes leftover
            while ($value.Length -gt 0 -and ($value[0] -eq '`' -or $value[0] -eq '\\')) { $value = $value.Substring(1) }
            while ($value.Length -gt 0 -and ($value[$value.Length-1] -eq '`' -or $value[$value.Length-1] -eq '\\')) { $value = $value.Substring(0, $value.Length-1) }

            # Remove surrounding quotes (single or double)
            if ($value.Length -ge 2) {
                if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }

            if ($value) { return $value }
        }
    }
    return $null
}

function Get-LlvmActiveVersion {
    [CmdletBinding()]
    param()

    # Check environment variable that would be set by activation
    if ($env:_ACTIVE_LLVM) {
        return $env:_ACTIVE_LLVM
    }

    # Alternative: check PATH for active LLVM installation
    if ($env:PATH -match '\.llvm\\toolchains\\([^\\;]+)') {
        return $matches[1]
    }

    return $null
}

function Test-LlvmVersionSatisfiesExpression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$ActiveVersion,
        [Parameter(Mandatory=$true)] [string]$Expression,
        [string]$ToolchainsPath = $null
    )

    try {
        $matched = Invoke-LlvmMatchVersions -Expression $Expression -ToolchainsPath $ToolchainsPath
        return $matched -contains $ActiveVersion
    } catch {
        return $false
    }
}

function Invoke-LlvmAutoActivateEnhanced {
    [CmdletBinding()]
    param(
        [string]$StartDirectory = (Get-Location).Path,
        [string]$ConfigExpression = $null,
        [string]$ToolchainsPath = $null
    )

    # Get configuration from file or parameter
    $versionExpr = $ConfigExpression
    if (-not $versionExpr) {
        $versionExpr = Invoke-LlvmAutoActivate -StartDirectory $StartDirectory
    }

    if (-not $versionExpr) {
        Write-Verbose "No version expression found in configuration"
        return $null
    }

    Write-Verbose "Auto-activation with expression: '$versionExpr'"

    # Check if already activated
    $activeVersion = Get-LlvmActiveVersion
    if ($activeVersion) {
        Write-Verbose "LLVM already active: $activeVersion"

        # Check if current version satisfies the expression
        if (Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $versionExpr -ToolchainsPath $ToolchainsPath) {
            Write-Verbose "Current version $activeVersion satisfies expression '$versionExpr'"
            return @{
                Action = 'NoChange'
                ActiveVersion = $activeVersion
                Expression = $versionExpr
                Reason = 'Current version satisfies expression'
            }
        } else {
            Write-Verbose "Current version $activeVersion does not satisfy expression '$versionExpr'"
            # In a real implementation, we would deactivate here
            # For now, we'll just return the recommendation
            return @{
                Action = 'ShouldDeactivateAndReactivate'
                ActiveVersion = $activeVersion
                Expression = $versionExpr
                Reason = 'Current version does not satisfy expression'
            }
        }
    }

    # Find matching versions
    try {
        $matched = Invoke-LlvmMatchVersions -Expression $versionExpr -ToolchainsPath $ToolchainsPath

        if (-not $matched -or $matched.Count -eq 0) {
            Write-Verbose "No versions match expression '$versionExpr'"
            return @{
                Action = 'NoMatch'
                ActiveVersion = $activeVersion
                Expression = $versionExpr
                Reason = 'No installed versions match expression'
            }
        }

        # Select the first (best) match
        $selectedVersion = $matched[0]

        Write-Verbose "Auto-activating version: $selectedVersion (matched expression: $versionExpr)"

        return @{
            Action = 'ShouldActivate'
            ActiveVersion = $activeVersion
            SelectedVersion = $selectedVersion
            Expression = $versionExpr
            Reason = "Should activate $selectedVersion"
            MatchedVersions = $matched
        }

    } catch {
        Write-Verbose "Error matching versions for expression '$versionExpr': $($_.Exception.Message)"
        return @{
            Action = 'Error'
            ActiveVersion = $activeVersion
            Expression = $versionExpr
            Reason = "Error: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# ENVIRONMENT ACTIVATION/DEACTIVATION FUNCTIONS
# =============================================================================

function Get-LlvmSysEnvironmentVariables {
    <#
    .SYNOPSIS
    Gets all LLVM_SYS_*_PREFIX environment variables currently set

    .OUTPUTS
    Hashtable with variable names and values
    #>

    $llvmSysVars = @{}

    # Get all environment variables that match LLVM_SYS_*_PREFIX pattern
    Get-ChildItem Env: | Where-Object { $_.Name -match '^LLVM_SYS_\d+_PREFIX$' } | ForEach-Object {
        $llvmSysVars[$_.Name] = $_.Value
    }

    return $llvmSysVars
}

function Clear-LlvmSysEnvironmentVariables {
    <#
    .SYNOPSIS
    Clears all LLVM_SYS_*_PREFIX environment variables
    #>

    Get-ChildItem Env: | Where-Object { $_.Name -match '^LLVM_SYS_\d+_PREFIX$' } | ForEach-Object {
        Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
        Write-Verbose "Cleared environment variable: $($_.Name)"
    }
}

function Backup-LlvmEnvironment {
    <#
    .SYNOPSIS
    Creates a backup of current environment variables before LLVM activation

    .DESCRIPTION
    Saves current PATH, LLVM-related environment variables (including all LLVM_SYS_*_PREFIX),
    and other relevant variables to allow complete restoration when deactivating LLVM

    .OUTPUTS
    Hashtable containing backed up environment state
    #>

    # Get all LLVM_SYS variables dynamically
    $llvmSysVars = Get-LlvmSysEnvironmentVariables

    $backup = @{
        PATH = $env:PATH
        LIBCLANG_PATH = $env:LIBCLANG_PATH
        LLVM_CONFIG_PATH = $env:LLVM_CONFIG_PATH
        CC = $env:CC
        CXX = $env:CXX
        AR = $env:AR
        RANLIB = $env:RANLIB
        _ACTIVE_LLVM = $env:_ACTIVE_LLVM
        _LLVM_BACKUP = $env:_LLVM_BACKUP
        LLVM_SYS_VARS = $llvmSysVars
        Timestamp = Get-Date
    }

    # Store backup in environment as JSON for persistence across function calls
    $env:_LLVM_BACKUP = ($backup | ConvertTo-Json -Compress)

    return $backup
}

function Restore-LlvmEnvironment {
    <#
    .SYNOPSIS
    Restores environment from backup created by Backup-LlvmEnvironment

    .DESCRIPTION
    Restores PATH and other environment variables to their pre-activation state,
    including dynamic cleanup of all LLVM_SYS_*_PREFIX variables

    .PARAMETER Backup
    Optional backup hashtable. If not provided, reads from $_LLVM_BACKUP env var

    .OUTPUTS
    Boolean indicating success of restoration
    #>
    param(
        [hashtable]$Backup
    )

    # Try to get backup from parameter or environment
    if (-not $Backup -and $env:_LLVM_BACKUP) {
        try {
            $Backup = ($env:_LLVM_BACKUP | ConvertFrom-Json -AsHashtable)
        } catch {
            Write-Warning "Failed to parse backup from environment: $_"
            return $false
        }
    }

    if (-not $Backup) {
        Write-Warning "No environment backup found to restore"
        return $false
    }

    # Clear all current LLVM_SYS variables (cleanup before restore)
    Clear-LlvmSysEnvironmentVariables

    # Restore basic environment variables
    $env:PATH = $Backup.PATH
    $env:LIBCLANG_PATH = $Backup.LIBCLANG_PATH
    $env:LLVM_CONFIG_PATH = $Backup.LLVM_CONFIG_PATH
    $env:CC = $Backup.CC
    $env:CXX = $Backup.CXX
    $env:AR = $Backup.AR
    $env:RANLIB = $Backup.RANLIB

    # Restore LLVM_SYS variables from backup (if any existed before activation)
    if ($Backup.LLVM_SYS_VARS) {
        foreach ($varName in $Backup.LLVM_SYS_VARS.Keys) {
            $varValue = $Backup.LLVM_SYS_VARS[$varName]
            if ($varValue) {
                [Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
                Write-Verbose "Restored environment variable: $varName = $varValue"
            }
        }
    }

    # Clear active LLVM marker and backup
    Remove-Item Env:_ACTIVE_LLVM -ErrorAction SilentlyContinue
    Remove-Item Env:_LLVM_BACKUP -ErrorAction SilentlyContinue

    return $true
}

function Invoke-LlvmActivate {
    <#
    .SYNOPSIS
    Activates an LLVM version by modifying environment variables

    .DESCRIPTION
    Sets up PATH and LLVM environment variables for the specified version.
    Creates backup of current environment for later restoration.

    .PARAMETER Version
    LLVM version to activate (e.g., "18.1.8", "llvmorg-19.1.0")

    .PARAMETER ToolchainsPath
    Path to toolchains directory (for testing)

    .PARAMETER Force
    Force activation even if another version is already active

    .OUTPUTS
    Boolean indicating success of activation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [string]$ToolchainsPath,

        [switch]$Force
    )

    # Determine toolchains path
    if (-not $ToolchainsPath) {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile) }
        $ToolchainsPath = if ($script:TOOLCHAINS_DIR) { $script:TOOLCHAINS_DIR } else { Join-Path $homeDir ".llvm\toolchains" }
    }

    # Check if version exists
    $versionPath = Join-Path $ToolchainsPath $Version
    if (-not (Test-Path $versionPath)) {
        throw "LLVM version '$Version' not found at: $versionPath"
    }

    # Check if already active (unless forced)
    if ($env:_ACTIVE_LLVM -eq $Version -and -not $Force) {
        Write-Information "LLVM version '$Version' is already active"
        return $true
    }

    # Backup current environment if not already backed up
    if (-not $env:_LLVM_BACKUP) {
        $null = Backup-LlvmEnvironment
    }

    # Set up LLVM paths
    $binPath = Join-Path $versionPath "bin"
    $libPath = Join-Path $versionPath "lib"
    $includePath = Join-Path $versionPath "include"

    # Add to PATH (prepend to ensure priority)
    if (Test-Path $binPath) {
        $env:PATH = "$binPath;$env:PATH"
    }

    # Set LLVM-specific environment variables
    $env:LLVM_CONFIG_PATH = Join-Path $binPath "llvm-config.exe"
    $env:LIBCLANG_PATH = Join-Path $libPath "libclang.dll"

    # Clean up any existing LLVM_SYS variables (to avoid conflicts between versions)
    Clear-LlvmSysEnvironmentVariables

    # Set version-specific variables (for Rust bindgen compatibility)
    $versionObj = ConvertFrom-LlvmVersion $Version
    if ($versionObj -and $versionObj.Version) {
        $parsedVersion = $versionObj.Version
        # Extract major.minor and create environment variable
        if ($parsedVersion -match '^(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            # Pattern: LLVM_SYS_<major*10+minor rounded down to nearest 10>_PREFIX
            $combined = $major * 10 + $minor
            $rounded = [math]::Floor($combined / 10) * 10
            $envVarName = "LLVM_SYS_${rounded}_PREFIX"
            [Environment]::SetEnvironmentVariable($envVarName, $versionPath, "Process")
            Write-Verbose "Set environment variable $envVarName = $versionPath (for LLVM $parsedVersion)"
        }
    }

    # Set compiler environment variables
    if (Test-Path (Join-Path $binPath "clang.exe")) {
        $env:CC = Join-Path $binPath "clang.exe"
        $env:CXX = Join-Path $binPath "clang++.exe"
    }

    if (Test-Path (Join-Path $binPath "llvm-ar.exe")) {
        $env:AR = Join-Path $binPath "llvm-ar.exe"
    }

    if (Test-Path (Join-Path $binPath "llvm-ranlib.exe")) {
        $env:RANLIB = Join-Path $binPath "llvm-ranlib.exe"
    }

    # Mark as active
    $env:_ACTIVE_LLVM = $Version

    Write-Information "Successfully activated LLVM version: $Version"
    return $true
}

function Invoke-LlvmDeactivate {
    <#
    .SYNOPSIS
    Deactivates the currently active LLVM version

    .DESCRIPTION
    Restores environment variables to their pre-activation state

    .OUTPUTS
    Boolean indicating success of deactivation
    #>

    if (-not $env:_ACTIVE_LLVM) {
        Write-Information "No LLVM version is currently active"
        return $true
    }

    $activeVersion = $env:_ACTIVE_LLVM

    if (Restore-LlvmEnvironment) {
        Write-Information "Successfully deactivated LLVM version: $activeVersion"
        return $true
    } else {
        Write-Error "Failed to deactivate LLVM version: $activeVersion"
        return $false
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-LlvmVersion',
    'Normalize-LlvmSemver',
    'Compare-LlvmVersion',
    'Invoke-LlvmParseVersionExpression',
    'Invoke-LlvmVersionMatchesRange',
    'Get-LlvmVersionsSimple',
    'Invoke-LlvmMatchVersions',
    'Invoke-LlvmAutoActivate',
    'Get-LlvmActiveVersion',
    'Test-LlvmVersionSatisfiesExpression',
    'Invoke-LlvmAutoActivateEnhanced',
    'Get-LlvmSysEnvironmentVariables',
    'Clear-LlvmSysEnvironmentVariables',
    'Backup-LlvmEnvironment',
    'Restore-LlvmEnvironment',
    'Invoke-LlvmActivate',
    'Invoke-LlvmDeactivate'
)
