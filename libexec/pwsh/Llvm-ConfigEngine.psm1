# Project config (.llvmup-config) pin/sync and reproducible lockfile (.llvmup-lock.json) management.

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
$script:ResolverModule = Join-Path $PSScriptRoot 'Llvm-Resolver.psm1'
if ((Test-Path -LiteralPath $script:ResolverModule) -and -not (Get-Module -Name 'Llvm-Resolver')) {
    Import-Module $script:ResolverModule -DisableNameChecking
}

function Set-LlvmIniSettingPreserving {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$FormattedValue
    )

    $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Content) {
        foreach ($l in ($Content -split "\r?\n")) { $lines.Add($l) }
    }

    $secHeader = "[$Section]"
    $secStart = -1
    $secEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $name = $matches[1].Trim().ToLowerInvariant()
            if ($secStart -ge 0) {
                $secEnd = $i
                break
            }
            if ($name -eq $Section.ToLowerInvariant()) {
                $secStart = $i
            }
        }
    }

    $assignment = "$Key = $FormattedValue"
    if ($secStart -ge 0) {
        for ($i = $secStart + 1; $i -lt $secEnd; $i++) {
            $trimmed = $lines[$i].Trim()
            if (-not $trimmed -or $trimmed -match '^[#;]') { continue }
            if ($trimmed -match "^$([regex]::Escape($Key))\s*=") {
                $lines[$i] = $assignment
                return ($lines.ToArray() -join $newline)
            }
        }
        $lines.Insert($secEnd, $assignment)
        return ($lines.ToArray() -join $newline)
    }

    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add('')
    }
    $lines.Add($secHeader)
    $lines.Add($assignment)
    return ($lines.ToArray() -join $newline)
}

function Update-LlvmConfigPin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$VersionValue,
        [string]$Provider = '',
        [string]$Kind = 'prebuilt',
        [string]$Crt = '',
        [string]$Target = '',
        [string]$Compiler = '',
        [string]$ReleaseTag = ''
    )

    $content = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        [IO.File]::ReadAllText($ConfigPath)
    } else {
        "# .llvmup-config - LLVMUP project configuration`n"
    }

    $content = Set-LlvmIniSettingPreserving -Content $content -Section 'version' -Key 'default' -FormattedValue "`"$VersionValue`""
    if ($Provider) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'provider' -FormattedValue "`"$Provider`"" }
    if ($Kind) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'kind' -FormattedValue "`"$Kind`"" }
    if ($Crt) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'crt' -FormattedValue "`"$Crt`"" }
    if ($Target) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'target' -FormattedValue "`"$Target`"" }
    if ($Compiler) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'compiler' -FormattedValue "`"$Compiler`"" }
    if ($ReleaseTag) { $content = Set-LlvmIniSettingPreserving -Content $content -Section 'toolchain' -Key 'release' -FormattedValue "`"$ReleaseTag`"" }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if (-not $content.EndsWith("`n")) { $content += "`n" }
    [IO.File]::WriteAllText($ConfigPath, $content, $utf8NoBom)
    return $ConfigPath
}

function Get-LlvmHostKey {
    [CmdletBinding()]
    param(
        [string]$HostOs = '',
        [string]$HostArch = ''
    )
    $os = Normalize-LlvmHostOs -Platform $HostOs
    $arch = Normalize-LlvmHostArch -Arch $HostArch
    return "${os}-${arch}"
}

function Read-LlvmLockfile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LockPath)
    $raw = Read-LlvmJsonFile -Path $LockPath
    if (-not $raw) { return $null }
    if ($raw.schema -ne 1) { throw "Unsupported lockfile schema in $LockPath" }
    return (ConvertTo-LlvmHashtable -InputObject $raw)
}

function Write-LlvmLockfileEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)]$Plan,
        [string]$Profile = 'full',
        [string[]]$Components = @(),
        [string]$VerifyPolicy = 'warn'
    )

    $existing = if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
        Read-LlvmLockfile -LockPath $LockPath
    } else {
        [ordered]@{ schema = 1; entries = [ordered]@{} }
    }
    if (-not $existing.entries) { $existing.entries = [ordered]@{} }

    $hostKey = Get-LlvmHostKey -HostOs $Plan.host.os -HostArch $Plan.host.arch
    $existing.entries[$hostKey] = [ordered]@{
        provider = [string]$Plan.provider
        release = [string]$Plan.release_tag
        llvm_version = [string]$Plan.llvm_version
        gcc_version = if ($Plan.gcc_version) { [string]$Plan.gcc_version } else { $null }
        canonical_id = [string]$Plan.canonical_id
        host = [ordered]@{
            os = [string]$Plan.host.os
            arch = [string]$Plan.host.arch
        }
        variant = $Plan.variant
        target = [string]$Plan.default_target
        asset = [ordered]@{
            name = [string]$Plan.asset.name
            url = [string]$Plan.asset.url
            digest = [string]$Plan.asset.digest
            id = [string]$Plan.asset.id
        }
        profile = $Profile
        components = @($Components)
        verify_policy = $VerifyPolicy
        locked_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-LlvmJsonFile -Path $LockPath -Data $existing -Depth 10
    return $existing
}

function Get-LlvmLockfileEntryForHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [string]$HostOs = '',
        [string]$HostArch = ''
    )

    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        throw "Lockfile does not exist: $LockPath. Run 'llvmup config lock' first."
    }
    $lock = Read-LlvmLockfile -LockPath $LockPath
    $hostKey = Get-LlvmHostKey -HostOs $HostOs -HostArch $HostArch
    if (-not $lock.entries -or -not $lock.entries.ContainsKey($hostKey)) {
        $avail = if ($lock.entries) { ($lock.entries.Keys -join ', ') } else { 'none' }
        throw "Lockfile '$LockPath' has no entry for host '$hostKey' (available: $avail). Update the lockfile with 'llvmup config lock'."
    }
    return $lock.entries[$hostKey]
}

Export-ModuleMember -Function @(
    'Set-LlvmIniSettingPreserving',
    'Update-LlvmConfigPin',
    'Get-LlvmHostKey',
    'Read-LlvmLockfile',
    'Write-LlvmLockfileEntry',
    'Get-LlvmLockfileEntryForHost'
)
