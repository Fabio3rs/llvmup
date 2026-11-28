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
# Default console presentation of 'llvmup list' (the returned objects are unchanged). Optional: a missing
# or rejected format file only means the default PowerShell formatting is used.
$script:LlvmFormatFile = Join-Path $PSScriptRoot 'Llvm-Functions.Format.ps1xml'
if ((Test-Path -LiteralPath $script:LlvmFormatFile) -and -not (Get-FormatData -TypeName 'Llvmup.Toolchain' -ErrorAction SilentlyContinue)) {
    try { Update-FormatData -AppendPath $script:LlvmFormatFile -ErrorAction Stop } catch { }
}
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
        "Info" { "[INFO]" }
        "Warning" { "[WARN]" }
        "Error" { "[ERROR]" }
        "Success" { "[OK]" }
    }

    Write-Host "$emoji $Message" -ForegroundColor $color
}

function Activate-Llvm {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Version,
        [string]$Compiler = '',
        [string]$Target = ''
    )

    if (-not $Version) {
        Write-Host "+-- LLVM Activation Help ------------------------------------+" -ForegroundColor Cyan
        Write-Host "| Usage: Activate-Llvm <version>                            |" -ForegroundColor White
        Write-Host "|                                                            |" -ForegroundColor White
        Write-Host "| Examples:                                                  |" -ForegroundColor White
        Write-Host "|   Activate-Llvm 18.1.8     # Activate specific version    |" -ForegroundColor White
        Write-Host "|   Activate-Llvm 19.1.0     # Activate another version     |" -ForegroundColor White
        Write-Host "|                                                            |" -ForegroundColor White
        Write-Host "| What this does:                                            |" -ForegroundColor White
        Write-Host "| - Sets PATH to use LLVM tools (clang, clang++, etc.)      |" -ForegroundColor White
        Write-Host "| - Updates environment variables                            |" -ForegroundColor White
        Write-Host "| - Modifies prompt to show active LLVM version             |" -ForegroundColor White
        Write-Host "|                                                            |" -ForegroundColor White
        Write-Host "| To deactivate: Deactivate-Llvm                            |" -ForegroundColor White
        Write-Host "| To check status: Get-LlvmStatus                           |" -ForegroundColor White
        Write-Host "+------------------------------------------------------------+" -ForegroundColor Cyan
        Write-Host ""
        if (Test-Path $script:TOOLCHAINS_DIR) {
            Get-ChildItem $script:TOOLCHAINS_DIR -Directory |
                ForEach-Object { $_.Name }
        }
        return
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    $directPath = Join-Path $toolchainsPath $Version
    if (Test-Path -LiteralPath $directPath -PathType Container) {
        $manifest = Read-LlvmToolchainManifest -Root $directPath -InstallName $Version
    } else {
        $manifest = Resolve-LlvmInstalledToolchain -Selector $Version -ToolchainsPath $toolchainsPath -HomePath $homePath
    }
    if (-not $manifest) {
        Write-LlvmLog "Activation failed: Toolchain '$Version' not found." -Level Error
        return $false
    }

    if ($manifest.origin -eq 'legacy' -and -not $Compiler -and -not $Target -and -not (Test-Path -LiteralPath (Join-Path $manifest.root_path '.llvmup-toolchain.json'))) {
        # Legacy path retains direct compatibility with existing core activation tests
        if (Get-Command -Name Invoke-LlvmActivate -ErrorAction SilentlyContinue) {
            try {
                return Invoke-LlvmActivate -Version $manifest.install_name -ToolchainsPath $toolchainsPath -Force
            } catch {
                Write-LlvmLog "Activation failed: $($_.Exception.Message)" -Level Error
                return $false
            }
        }
    }

    try {
        $delta = Get-LlvmEnvironmentDelta -Manifest $manifest -Target $Target -Compiler $Compiler
        return (Apply-LlvmEnvironmentDelta -Delta $delta)
    } catch {
        Write-LlvmLog "Activation failed: $($_.Exception.Message)" -Level Error
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
    Remove-Item -LiteralPath 'Env:LLVMUP_SESSION_OVERRIDE' -ErrorAction SilentlyContinue
    # Deactivation returns to the original environment, including the 'use -' history.
    Remove-Item -LiteralPath 'Env:LLVMUP_PREVIOUS_SESSION' -ErrorAction SilentlyContinue
    return Invoke-LlvmDeactivate
}

$pwshLib = Join-Path (Join-Path $PSScriptRoot 'libexec') 'pwsh'
foreach ($helperMod in @('Llvm-Manifest.psm1', 'Llvm-Recipes.psm1', 'Llvm-Resolver.psm1', 'Llvm-Downloader.psm1', 'Llvm-Verifier.psm1', 'Llvm-Extractor.psm1', 'Llvm-Environment.psm1', 'Llvm-Runner.psm1', 'Llvm-ConfigEngine.psm1', 'Llvm-CMake.psm1', 'Llvm-Installer.psm1')) {
    $helperPath = Join-Path $pwshLib $helperMod
    if (Test-Path -LiteralPath $helperPath) {
        Import-Module $helperPath -DisableNameChecking -ErrorAction SilentlyContinue
    }
}

function Get-LlvmStatus {
    [CmdletBinding()]
    param([switch]$Explain, [switch]$Json)

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    $active = Get-LlvmActiveVersion
    $activePath = if ($env:_ACTIVE_LLVM_PATH) { $env:_ACTIVE_LLVM_PATH } elseif ($env:LLVMUP_ACTIVE_PATH) { $env:LLVMUP_ACTIVE_PATH } elseif ($active) { Join-Path $toolchainsPath $active } else { $null }

    if (-not $Explain -and -not $Json) {
        if (-not $active) {
            return [pscustomobject]@{ Status = 'INACTIVE'; Version = $null; Path = $null }
        }
        return [pscustomobject]@{
            Status = 'ACTIVE'
            Version = $active
            Path = $activePath
        }
    }

    $activeManifest = if ($activePath -and (Test-Path -LiteralPath $activePath -PathType Container)) {
        Read-LlvmToolchainManifest -Root $activePath -InstallName $active
    } else { $null }

    $selected = $null
    try {
        $selected = Resolve-LlvmEffectiveSelection -ToolchainsPath $toolchainsPath -HomePath $homePath
    } catch {}

    $targetManifest = if ($activeManifest) { $activeManifest } elseif ($selected) { $selected.manifest } else { $null }
    $verSummary = if ($targetManifest -and $targetManifest.verification -and $targetManifest.verification.methods) {
        @($targetManifest.verification.methods) -join '+'
    } else { 'unverified' }

    $payload = [ordered]@{
        schema = 1
        active_in_environment = [bool]$active
        active_version = $active
        active_path = $activePath
        active_compiler = if ($env:LLVMUP_ACTIVE_COMPILER) { $env:LLVMUP_ACTIVE_COMPILER } elseif ($activeManifest -and $activeManifest.variant) { $activeManifest.variant.default_compiler } else { $null }
        active_target = if ($env:LLVMUP_ACTIVE_TARGET) { $env:LLVMUP_ACTIVE_TARGET } elseif ($activeManifest) { $activeManifest.default_target } else { $null }
        selected_for_execution = if ($selected) {
            [ordered]@{
                install_name = $selected.manifest.install_name
                id = $selected.manifest.id
                provider = $selected.manifest.provider
                provider_release = $selected.manifest.provider_release
                llvm_version = $selected.manifest.llvm_version
                gcc_version = $selected.manifest.gcc_version
                host = $selected.manifest.host
                target = $selected.target
                crt = if ($selected.manifest.variant) { $selected.manifest.variant.crt } else { $null }
                cxx_stdlib = if ($selected.manifest.variant) { $selected.manifest.variant.cxx_stdlib } else { $null }
                compiler = $selected.compiler
                path = $selected.manifest.root_path
                origin = $selected.origin
                reason = $selected.reason
                verification = if ($selected.manifest.verification -and $selected.manifest.verification.methods) { @($selected.manifest.verification.methods) -join '+' } else { 'unverified' }
            }
        } else { $null }
    }

    if ($Json) {
        return ($payload | ConvertTo-Json -Depth 8)
    }

    $lines = @()
    $lines += "Environment status: $(if ($active) { "ACTIVE ($active)" } else { 'INACTIVE' })"
    if ($selected) {
        $m = $selected.manifest
        $lines += "Effective selection (for run/which): $($m.install_name)"
        $lines += "  Provider             : $($m.provider)"
        $lines += "  Provider release     : $($m.provider_release)"
        $lines += "  LLVM version         : $($m.llvm_version)"
        if ($m.gcc_version) { $lines += "  GCC version          : $($m.gcc_version)" }
        $lines += "  Host                 : $($m.host.os) $($m.host.arch)"
        $lines += "  Target               : $($selected.target)"
        if ($m.variant) {
            $lines += "  CRT                  : $($m.variant.crt)"
            $lines += "  C++ standard library : $($m.variant.cxx_stdlib)"
        }
        $lines += "  Selected compiler    : $($selected.compiler)"
        $lines += "  Installation path    : $($m.root_path)"
        $lines += "  Selection origin     : $($selected.origin) ($($selected.reason))"
        $lines += "  Verification state   : $verSummary"
    } else {
        $lines += "Effective selection (for run/which): none"
    }
    return ($lines -join "`n")
}

function Get-LlvmList {
    [CmdletBinding()]
    param([switch]$Remote, [switch]$Json, [switch]$Providers, [string]$Provider = '')

    if ($Providers) {
        $list = @(Get-LlvmProviderList | ForEach-Object {
            [pscustomobject][ordered]@{
                provider = $_.provider
                display_name = $_.display_name
                repository = $_.repository
                supports_source = [bool]$_.supports_source
                compilers = @($_.available_compilers)
                profiles = @($_.profiles)
            }
        })
        if ($Json) { return ([pscustomobject]@{ providers = $list } | ConvertTo-Json -Depth 5) }
        return $list
    }

    if ($Remote) {
        $downloadScript = Join-Path $PSScriptRoot 'Download-Llvm.ps1'
        if (-not (Test-Path -LiteralPath $downloadScript)) { throw 'Download-Llvm.ps1 was not found' }
        $format = if ($Json) { 'Json' } else { 'Text' }
        $dlParams = @{ ListOnly = $true; OutputFormat = $format; Quiet = $true }
        if ($Provider) { $dlParams.Provider = $Provider }
        return & $downloadScript @dlParams
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    $active = Get-LlvmActiveVersion
    $default = Get-LlvmDefaultVersion -HomePath $homePath
    $all = @(Get-LlvmAllToolchains -ToolchainsPath $toolchainsPath -HomePath $homePath)
    if ($Provider) {
        $all = @($all | Where-Object { $_.provider -eq $Provider.ToLowerInvariant() })
    }

    $versions = @($all | ForEach-Object {
        $verDisplay = if ($_.llvm_version) { $_.llvm_version } else { $_.install_name -replace '^(source-)?llvmorg-', '' }
        $typeVal = if ($_.origin -eq 'source' -or $_.install_name -like 'source-*') { 'source' } elseif ($_.origin -like 'external*') { 'external' } else { 'prebuilt' }
        $entry = [pscustomobject][ordered]@{
            name = $_.install_name
            id = $_.id
            provider = $_.provider
            provider_release = $_.provider_release
            llvm_version = $_.llvm_version
            gcc_version = $_.gcc_version
            version = $verDisplay
            type = $typeVal
            origin = $_.origin
            crt = if ($_.variant) { $_.variant.crt } else { $null }
            targets = @($_.supported_targets)
            active = ($_.install_name -eq $active)
            default = ($_.install_name -eq $default)
            path = $_.root_path
        }
        $entry.PSObject.TypeNames.Insert(0, 'Llvmup.Toolchain')
        $entry
    })

    if ($Json) {
        return [pscustomobject]@{
            installed_versions = $versions
            active_version = $active
            default_version = $default
        } | ConvertTo-Json -Depth 6
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

$script:LlvmCommandHelp = @{
    'install' = @'
Install a toolchain.

Usage:
  llvmup install [<provider>@]<selector> [options]

Selectors:
  latest, 23, ~23.1, >=23.1.4, 23.*, winlibs@23, llvm-mingw@23, official@latest
  Quote selectors containing > < or *, for example: llvmup install '>=23.1'

Options:
  --use                  Select the toolchain in this terminal after installing
  -n, --name <NAME>      Installation name (default: derived from the release)
  --provider <P>         official, winlibs or llvm-mingw
  --release <TAG>        Pin the upstream release
  --crt <ucrt|msvcrt>    C runtime (WinLibs and LLVM-MinGW)
  --threads <T>          Thread model, where the provider offers a choice
  --verify <POLICY>      warn (default), strict or skip
  --extractor <E>        auto, 7z, tar, zip or python
  --force                Replace an existing installation with the same name
  --archive-only         Install the prebuilt archive without a source build
  -q, --quiet / -v, --verbose

Examples:
  llvmup install latest --use
  llvmup install winlibs@23 --name win-dev
  llvmup install llvm-mingw@23 --crt ucrt

Effects: downloads and verifies an archive, then creates a new directory under the
toolchains folder. It never changes this terminal unless --use is given.
'@
    'use' = @'
Select a toolchain for this terminal.

Usage:
  llvmup use <selector|installation|alias> [--compiler clang|gcc] [--target <T>] [--crt <C>] [--install]
  llvmup use -        Return to the previous selection of this terminal
  llvmup use --auto   Drop the manual selection and follow .llvmup-config or the default

Options:
  --compiler <C>   Compiler to export as CC/CXX (only compilers the toolchain provides)
  --target <T>     Target triple (only targets the toolchain supports)
  --install        Install the toolchain first, only if no installation matches

Examples:
  llvmup use official@23
  llvmup use winlibs@23 --compiler gcc

Effects: changes PATH and related variables of the current PowerShell session only. This works
through the 'llvmup' function from the module; llvmup.cmd cannot do it. Use
'llvmup run <toolchain> -- <command>' for a one-off command instead.
'@
    'run' = @'
Run a command with a toolchain, without changing the current session.

Usage:
  llvmup run [<selector>] [--compiler C] [--target T] [--install] -- <command> [args...]
  llvmup +<selector> -- <command> [args...]
  llvmup run --locked -- <command>    Use the toolchain recorded in .llvmup-lock.json

Without a selector, the effective toolchain is used (session, project, then default).

Examples:
  llvmup run llvm-mingw@23 -- clang++ --version
  llvmup +winlibs@23 -- gcc --version

The command's own output and exit code are passed through unchanged.
'@
    'list' = @'
List installed toolchains.

Usage:
  llvmup list [--json]
  llvmup list --remote [--provider <P>] [--json]
  llvmup list --providers

--remote queries upstream releases (network); the other forms are offline.
'@
    'status' = @'
Show the current selection.

Usage:
  llvmup status [--explain] [--json]

--explain shows why the toolchain was selected (session override, project
configuration or user default). --json prints machine-readable output only.
'@
    'config' = @'
Manage the project configuration (.llvmup-config).

Usage:
  llvmup config init        Create a .llvmup-config in this directory
  llvmup config load        Show the configuration that applies here
  llvmup config apply       Install what the configuration asks for
  llvmup config activate    Select the configured toolchain in this session
  llvmup config lock        Write .llvmup-lock.json with exact asset identities

See also: llvmup pin, llvmup sync.
'@
    'sync' = @'
Install the toolchain requested by the project.

Usage:
  llvmup sync [--locked]

Reads .llvmup-config and installs the matching toolchain if it is missing.
With --locked, the exact asset recorded in .llvmup-lock.json is required.
'@
    'pin' = @'
Record a toolchain in .llvmup-config.

Usage:
  llvmup pin [<selector>]
  llvmup pin --current     Record the active toolchain

Only .llvmup-config in the current project is modified.
'@
    'default' = @'
Manage the user default toolchain.

Usage:
  llvmup default [<selector>]    Show the default, or set it when a selector is given
  llvmup default set <selector>
  llvmup default show
  llvmup default unset

The default applies when neither a manual selection nor a project configuration exists.
'@
    'alias' = @'
Give installations stable names.

Usage:
  llvmup alias set <name> <installation>
  llvmup alias list | show <name> | remove <name>

Removing an alias never removes the toolchain it points to.
'@
    'remove' = @'
Remove an installed toolchain.

Usage:
  llvmup remove <installation> [--force]

The default toolchain is refused unless --force is given. Only the installation
directory is deleted.
'@
    'update' = @'
Install a newer release of an installed toolchain.

Usage:
  llvmup update [<selector>]

The previous installation is kept, and aliases, defaults and pins are not changed.
'@
    'env' = @'
Print environment settings for scripts and CI.

Usage:
  llvmup env [<selector>|--config] [--compiler C] [--target T] [--format shell|cmd|github|json]

Only the settings are written to the output; diagnostics go to the error stream.
'@
    'resolve' = @'
Show which upstream release and asset a selector would install.

Usage:
  llvmup resolve [<selector>|--config] [--provider <P>] [--release <TAG>] [--crt <C>] [--threads <T>] [--platform <OS>] [--arch <A>] [--format tag|json]

Queries release metadata without downloading or installing any archive.
'@
    'toolchain' = @'
Link, unlink, or list external (non-managed) toolchains.

Usage:
  llvmup toolchain link <name> <path>
  llvmup toolchain unlink <name>
  llvmup toolchain list

Unlinking only removes the LLVMUP registration; external files on disk are preserved.
'@
    'disk-usage' = @'
Show disk usage of installed toolchains.

Usage:
  llvmup disk-usage [-h|--human-readable]
'@
    'deactivate' = @'
Restore this terminal session's environment to its state before LLVMUP activation.

Usage:
  llvmup deactivate
'@
    'shell' = @'
Start a subshell with a toolchain active.

Usage:
  llvmup shell [<selector>] [--compiler <C>] [--target <T>] [--shell <PATH>]
'@
    'pick' = @'
Interactively choose an installed toolchain from a list and activate it.

Usage:
  llvmup pick
'@
    'cmake-toolchain' = @'
Write a CMake toolchain file for a selected toolchain.

Usage:
  llvmup cmake-toolchain [<selector>] [--compiler <C>] [--target <T>] [-o|--output <PATH>]
'@
    'vscode-activate' = @'
Configure VS Code settings for a toolchain.

Usage:
  llvmup vscode-activate <selector>
'@
    'info' = @'
Show detailed metadata for a toolchain.

Usage:
  llvmup info [<selector>] [--json]
'@
    'which' = @'
Print the full path to a tool inside the selected toolchain.

Usage:
  llvmup which <tool> [--toolchain <selector>] [--compiler <C>] [--target <T>]
'@
    'where' = @'
Print the root directory of a toolchain.

Usage:
  llvmup where [<selector>]
'@
    'provides' = @'
Find installed toolchains that provide a given tool.

Usage:
  llvmup provides <tool> [--json]
'@
    'doctor' = @'
Check LLVMUP installation, environment, and project health.

Usage:
  llvmup doctor [--verbose] [--json]
'@
}

function Test-LlvmCommandHelp {
    param([Parameter(Mandatory)][string]$Command)
    $key = $Command.ToLowerInvariant()
    if ($key -eq 'activate') { $key = 'use' }
    return $script:LlvmCommandHelp.ContainsKey($key)
}

function Split-LlvmUpMessage {
    # PowerShell 7's default error view folds line breaks into one paragraph, so an error is reported
    # in two parts: Lines[0] as the error (callers and -ErrorVariable still see it) and the guidance
    # that follows it as plain text (Write-LlvmUpGuidance).
    param([Parameter(Mandatory)][string]$Message)
    return @($Message.Replace("`r`n", "`n") -split "`n")
}

function Write-LlvmUpGuidance {
    param([string[]]$Lines)
    if ($Lines.Count -gt 1) {
        $rest = ($Lines | Select-Object -Skip 1) -join [Environment]::NewLine
        if ($rest.Trim()) { Write-Host $rest }
    }
}

function Show-LlvmCommandHelp {
    # Writes the help text of one command (nothing when the command has none; see Test-LlvmCommandHelp).
    param([Parameter(Mandatory)][string]$Command)
    $key = $Command.ToLowerInvariant()
    if ($key -eq 'activate') { $key = 'use' }
    if ($script:LlvmCommandHelp.ContainsKey($key)) { $script:LlvmCommandHelp[$key] }
}

function Show-LlvmHelp {
    param([string]$Topic = '')
    if ($Topic) {
        if (Test-LlvmCommandHelp -Command $Topic) { Show-LlvmCommandHelp -Command $Topic; return }
        Write-Error "No help available for '$Topic'. Run 'llvmup help' for the list of commands." -ErrorAction Continue
        return
    }
    @'
LLVMUP - C/C++ Toolchain Manager
Your toolchains. Your terminal. Your environment.

Usage:
  llvmup <command> [options]
  llvmup +<toolchain> -- <command>
  llvmup help <command>

Getting started:
  install       Install a toolchain (official LLVM, WinLibs, LLVM-MinGW)
  use           Select a toolchain for this terminal
  list          List installed toolchains
  run           Run a command with a toolchain, without changing the session
  status        Show the current selection

Toolchain management:
  update        Install a newer release of an installed toolchain
  remove        Remove an installed toolchain
  default       Choose the user default toolchain
  alias         Give toolchains stable names
  resolve       Show which release a selector would install
  toolchain     Link or unlink an external toolchain
  disk-usage    Show disk usage of installed toolchains

Projects:
  pin           Record the toolchain in .llvmup-config
  sync          Install what .llvmup-config or the lockfile asks for
  config        Manage .llvmup-config (init, load, apply, activate, lock)

Environment:
  deactivate    Restore this session's previous environment
  shell         Start a subshell with a toolchain active
  pick          Choose an installed toolchain from a list
  env           Print environment settings for scripts and CI

Integration:
  cmake-toolchain   Write a CMake toolchain file
  vscode-activate   Configure VS Code for a toolchain

Inspection:
  info  which  where  provides  doctor

Common flows:
  llvmup install latest --use
  llvmup install winlibs@23
  llvmup use winlibs@23 --compiler gcc
  llvmup run llvm-mingw@23 -- clang++ --version
  llvmup pin --current
  llvmup sync

Options:
  --version     Show the LLVMUP version
  -h, --help    Show this help, or help for a command

Historical commands such as 'activate' and the 'llvmup <version>' install shorthand still work.
'@
}

function Get-LlvmVersions { param([string]$Format = 'list') switch ($Format.ToLowerInvariant()) { 'json' { Get-LlvmList -Json } 'simple' { Get-LlvmVersionsSimple } default { Get-LlvmList } } }
function Get-LlvmVersionsList { Get-LlvmList }
function Get-LlvmVersionsJson { Get-LlvmList -Json }

function Invoke-LlvmUpInstall {
    param([string[]]$Tokens)

    $strip = $false
    $fromSource = $false
    $listOnly = $false
    $setDefault = $false
    $useAfter = $false
    $quiet = $false
    $verboseMode = $false
    $force = $false
    $noCache = $false
    $preferInstaller = $false
    $name = $null
    $profile = $null
    $verify = $null
    $provider = ''
    $release = ''
    $crt = ''
    $threads = ''
    $target = ''
    $compiler = ''
    $extractor = 'auto'
    $version = $null
    $cmakeFlags = @()
    $components = @()
    $disableLibcWnoError = $false
    $reconfigure = $false

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = $Tokens[$i]
        switch ($token) {
            '--strip' { $strip = $true }
            '--from-source' { $fromSource = $true }
            '--list-only' { $listOnly = $true }
            '--default' { $setDefault = $true }
            '--use' { $useAfter = $true }
            '--force' { $force = $true }
            '--no-cache' { $noCache = $true }
            '--installer' { $preferInstaller = $true }
            '--archive-only' { $preferInstaller = $false }
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
            '--provider' { if (++$i -ge $Tokens.Count) { throw '--provider requires a value' }; $provider = $Tokens[$i] }
            '--release' { if (++$i -ge $Tokens.Count) { throw '--release requires a value' }; $release = $Tokens[$i] }
            '--crt' { if (++$i -ge $Tokens.Count) { throw '--crt requires a value' }; $crt = $Tokens[$i] }
            '--threads' { if (++$i -ge $Tokens.Count) { throw '--threads requires a value' }; $threads = $Tokens[$i] }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--compiler' { if (++$i -ge $Tokens.Count) { throw '--compiler requires a value' }; $compiler = $Tokens[$i] }
            '--extractor' { if (++$i -ge $Tokens.Count) { throw '--extractor requires a value' }; $extractor = $Tokens[$i] }
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
    if ($listOnly) {
        $listArgs = @{ ListOnly = $true; OutputFormat = 'Text'; Quiet = $true }
        if ($provider) { $listArgs.Provider = $provider }
        return & $downloadScript @listArgs
    }

    if ($fromSource) {
        if ($verify) { throw '--verify applies only to prebuilt releases' }
        if ($provider -and $provider -ne 'official') { throw 'Source builds are supported only for the official provider' }
        $installScript = Join-Path $PSScriptRoot 'Install-Llvm.ps1'
        $parameters = @{ FromSource = $true }
        if ($strip) { $parameters.Strip = $true }
        if ($name) { $parameters.Name = $name }
        if ($profile) { $parameters.Profile = $profile }
        if ($cmakeFlags.Count) { $parameters.CmakeFlags = $cmakeFlags }
        if ($components.Count) { $parameters.Component = $components }
        if ($setDefault) { $parameters.Default = $true }
        if ($disableLibcWnoError) { $parameters.DisableLibcWnoError = $true }
        if ($reconfigure) { $parameters.Reconfigure = $true }
        if ($verboseMode) { $parameters.VerboseMode = $true }
        if ($quiet) { $parameters.Quiet = $true }
        $srcRes = & $installScript install $version @parameters
        if ($useAfter -and $srcRes) {
            $targetName = if ($name) { $name } else { "source-$(if ($version -match '^llvmorg-') { $version } else { "llvmorg-$version" })" }
            $null = Invoke-LlvmUpUse -Tokens @($targetName)
        }
        return $srcRes
    }

    if ($cmakeFlags.Count -or $disableLibcWnoError -or $reconfigure) {
        throw 'Source build options require --from-source'
    }

    $installRes = Invoke-LlvmInstallPrebuiltFromRecipe `
        -Selector $version `
        -Provider $provider `
        -ReleaseTag $release `
        -Crt $crt `
        -Threads $threads `
        -Target $target `
        -Compiler $compiler `
        -Name $name `
        -Profile $(if ($profile) { $profile } else { '' }) `
        -Components $components `
        -Strip:$strip `
        -Extractor $extractor `
        -VerifyPolicy $(if ($verify) { $verify } else { '' }) `
        -ArchiveOnly:(-not $preferInstaller) `
        -Force:$force `
        -NoCache:$noCache `
        -ToolchainsPath (Get-LlvmSessionToolchainsPath) `
        -HomePath (Get-LlvmHomePath) `
        -Quiet:$quiet `
        -VerboseMode:$verboseMode

    if ($setDefault) {
        $null = Set-LlvmDefaultVersion -Version $installRes.install_name -ToolchainsPath (Get-LlvmSessionToolchainsPath) -HomePath (Get-LlvmHomePath)
    }
    if ($useAfter) {
        $useTokens = @($installRes.install_name)
        if ($compiler) { $useTokens += @('--compiler', $compiler) }
        if ($target) { $useTokens += @('--target', $target) }
        $null = Invoke-LlvmUpUse -Tokens $useTokens
    }
    return $true
}

function Invoke-LlvmUpResolve {
    param([string[]]$Tokens)
    $version = 'latest'
    $format = 'Text'
    $platform = $null
    $arch = $null
    $provider = ''
    $release = ''
    $crt = ''
    $threads = ''
    $target = ''
    $extractor = 'auto'
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
            '--provider' { if (++$i -ge $Tokens.Count) { throw '--provider requires a value' }; $provider = $Tokens[$i] }
            '--release' { if (++$i -ge $Tokens.Count) { throw '--release requires a value' }; $release = $Tokens[$i] }
            '--crt' { if (++$i -ge $Tokens.Count) { throw '--crt requires a value' }; $crt = $Tokens[$i] }
            '--threads' { if (++$i -ge $Tokens.Count) { throw '--threads requires a value' }; $threads = $Tokens[$i] }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--extractor' { if (++$i -ge $Tokens.Count) { throw '--extractor requires a value' }; $extractor = $Tokens[$i] }
            '--config' { $useConfig = $true }
            default { if ($Tokens[$i].StartsWith('-')) { throw "Unknown resolve option: $($Tokens[$i])" }; $version = $Tokens[$i] }
        }
    }
    if ($useConfig) {
        $cfgPath = Find-LlvmProjectConfigPath
        if (-not $cfgPath) { throw 'No .llvmup-config file found' }
        $cfg = Read-LlvmProjectConfigData -ConfigPath $cfgPath
        $version = $cfg.version
        if (-not $provider -and $cfg.provider) { $provider = $cfg.provider }
        if (-not $crt -and $cfg.crt) { $crt = $cfg.crt }
        if (-not $release -and $cfg.release) { $release = $cfg.release }
        if (-not $threads -and $cfg.threads) { $threads = $cfg.threads }
        if (-not $target -and $cfg.target) { $target = $cfg.target }
    }
    $resolved = Invoke-LlvmInstallPrebuiltFromRecipe `
        -Selector $version `
        -Provider $provider `
        -ReleaseTag $release `
        -Platform $(if ($platform) { $platform } else { '' }) `
        -Arch $(if ($arch) { $arch } else { '' }) `
        -Crt $crt `
        -Threads $threads `
        -Target $target `
        -Extractor $extractor `
        -ArchiveOnly `
        -ResolveOnly `
        -ToolchainsPath (Get-LlvmSessionToolchainsPath) `
        -HomePath (Get-LlvmHomePath) `
        -Quiet
    if ($format -eq 'Json') {
        Write-Output ($resolved | ConvertTo-Json -Compress)
    } else {
        Write-Output $resolved.version
    }
}

function Resolve-LlvmUpConfigVersion {
    $config = Import-LlvmConfig
    if ($config.Name -and (Test-LlvmVersionExists $config.Name)) { return $config.Name }
    if (Test-LlvmVersionExists $config.Version) { return $config.Version }
    $resolved = Resolve-LlvmInstalledToolchain -Selector $config.Version -ToolchainsPath (Get-LlvmSessionToolchainsPath) -HomePath (Get-LlvmHomePath)
    if ($resolved) { return $resolved.install_name }
    $matches = @(Invoke-LlvmMatchVersions -Expression $config.Version -ToolchainsPath (Get-LlvmSessionToolchainsPath))
    if (-not $matches.Count) { throw "No installed LLVM version matches '$($config.Version)'" }
    return $matches[0]
}

function Invoke-LlvmUpEnv {
    param([string[]]$Tokens)
    $format = 'powershell'
    $useConfig = $false
    $version = $null
    $target = ''
    $compiler = ''
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--config' { $useConfig = $true }
            '--format' { if (++$i -ge $Tokens.Count) { throw '--format requires a value' }; $format = $Tokens[$i].ToLowerInvariant() }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--compiler' { if (++$i -ge $Tokens.Count) { throw '--compiler requires a value' }; $compiler = $Tokens[$i] }
            default { if ($Tokens[$i].StartsWith('-')) { throw "Unknown env option: $($Tokens[$i])" }; $version = $Tokens[$i] }
        }
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    if ($useConfig) {
        $sel = Resolve-LlvmEffectiveSelection -TargetOverride $target -CompilerOverride $compiler -ToolchainsPath $toolchainsPath -HomePath $homePath
        if (-not $sel) { throw 'No installed toolchain matches project configuration' }
        $manifest = $sel.manifest
        if (-not $target) { $target = $sel.target }
        if (-not $compiler) { $compiler = $sel.compiler }
    } else {
        if (-not $version) { throw "Missing version argument for 'env'" }
        $manifest = Resolve-LlvmInstalledToolchain -Selector $version -ToolchainsPath $toolchainsPath -HomePath $homePath
        if (-not $manifest) { throw "LLVM version '$version' is not installed" }
    }

    $delta = Get-LlvmEnvironmentDelta -Manifest $manifest -Target $target -Compiler $compiler
    $exported = Format-LlvmEnvironmentDeltaExports -Delta $delta -Format $format
    if ($exported) { Write-Output $exported }
}

function Invoke-LlvmUpUse {
    param([string[]]$Tokens)
    $selector = ''
    $compiler = ''
    $target = ''
    $installMissing = $false
    $autoMode = $false
    $crt = ''
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--compiler' { if (++$i -ge $Tokens.Count) { throw '--compiler requires a value' }; $compiler = $Tokens[$i] }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--crt' { if (++$i -ge $Tokens.Count) { throw '--crt requires a value' }; $crt = $Tokens[$i] }
            '--install' { $installMissing = $true }
            '--auto' { $autoMode = $true }
            default { if ($Tokens[$i].StartsWith('-') -and $Tokens[$i] -ne '-') { throw "Unknown use option: $($Tokens[$i])" }; $selector = $Tokens[$i] }
        }
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath

    if ($autoMode) {
        Remove-Item -LiteralPath 'Env:LLVMUP_SESSION_OVERRIDE' -ErrorAction SilentlyContinue
        $cfgPath = Find-LlvmProjectConfigPath
        if ($cfgPath) {
            $sel = Resolve-LlvmEffectiveSelection -ToolchainsPath $toolchainsPath -HomePath $homePath
            if ($sel) {
                $delta = Get-LlvmEnvironmentDelta -Manifest $sel.manifest -Target $sel.target -Compiler $sel.compiler
                return (Apply-LlvmEnvironmentDelta -Delta $delta)
            }
        }
        return Deactivate-Llvm
    }

    if ($selector -eq '-') {
        if (-not $env:LLVMUP_PREVIOUS_SESSION) {
            throw 'No previous toolchain selection recorded in this session.'
        }
        # Same "name|compiler|target" format as the Bash 'use' (older sessions stored JSON).
        $raw = [string]$env:LLVMUP_PREVIOUS_SESSION
        $prev = if ($raw.StartsWith('{')) { $raw | ConvertFrom-Json } else {
            $parts = $raw.Split('|')
            [pscustomobject]@{ name = $parts[0]; compiler = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }); target = $(if ($parts.Count -gt 2) { $parts[2] } else { '' }) }
        }
        $selector = [string]$prev.name
        if (-not $compiler -and $prev.compiler) { $compiler = [string]$prev.compiler }
        if (-not $target -and $prev.target) { $target = [string]$prev.target }
    }

    if (-not $selector) { throw "Missing toolchain selector for 'use'" }

    # Save current active state for 'use -'
    if ($env:_ACTIVE_LLVM) {
        Set-Item -LiteralPath 'Env:LLVMUP_PREVIOUS_SESSION' -Value ("{0}|{1}|{2}" -f $env:_ACTIVE_LLVM, $env:LLVMUP_ACTIVE_COMPILER, $env:LLVMUP_ACTIVE_TARGET)
    }

    $manifest = Resolve-LlvmInstalledToolchain -Selector $selector -ToolchainsPath $toolchainsPath -HomePath $homePath -CrtFilter $crt
    if (-not $manifest) {
        if (-not $installMissing) {
            throw (Format-LlvmNoMatchMessage -Selector $selector -OfferUseInstall)
        }
        $res = Invoke-LlvmInstallPrebuiltFromRecipe -Selector $selector -Crt $crt -Target $target -Compiler $compiler -ArchiveOnly -ToolchainsPath $toolchainsPath -HomePath $homePath
        $manifest = $res.manifest
    }

    $delta = Get-LlvmEnvironmentDelta -Manifest $manifest -Target $target -Compiler $compiler
    $applied = Apply-LlvmEnvironmentDelta -Delta $delta -SetSessionOverride
    if ($applied) {
        # Same confirmation as the Bash function; written to the host so the boolean result stays clean.
        $detail = @([string]$manifest.provider, "compiler $($env:LLVMUP_ACTIVE_COMPILER)")
        if ($env:LLVMUP_ACTIVE_TARGET) { $detail += "target $($env:LLVMUP_ACTIVE_TARGET)" }
        Write-Host ("Using {0} ({1})." -f $manifest.install_name, ($detail -join ', '))
    }
    return $applied
}

function Invoke-LlvmUpRun {
    param([string[]]$Tokens, [string]$PresetSelector = '')

    $selector = $PresetSelector
    $compiler = ''
    $target = ''
    $crt = ''
    $installMissing = $false
    $locked = $false
    $cmdTokens = @()
    $hasExplicitSep = ($Tokens -contains '--')
    $foundSep = $false

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if ($foundSep) { $cmdTokens += $t; continue }
        if ($t -eq '--') { $foundSep = $true; continue }
        switch ($t) {
            '--compiler' { if (++$i -ge $Tokens.Count) { throw '--compiler requires a value' }; $compiler = $Tokens[$i] }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--crt' { if (++$i -ge $Tokens.Count) { throw '--crt requires a value' }; $crt = $Tokens[$i] }
            '--install' { $installMissing = $true }
            '--locked' { $locked = $true }
            default {
                if ($t.StartsWith('-')) { throw "Unknown run option: $t" }
                if (-not $hasExplicitSep -and ($selector -or $locked)) {
                    # Interactive PowerShell strips bare '--'; remaining tokens form the command.
                    $cmdTokens += $Tokens[$i..($Tokens.Count - 1)]
                    $i = $Tokens.Count
                    $foundSep = $true
                } elseif (-not $selector) {
                    $selector = $t
                } else {
                    throw "Unexpected argument '$t' before '--'. Use: llvmup run [selector] -- <command> [args...]"
                }
            }
        }
    }

    if ($cmdTokens.Count -eq 0) {
        throw 'Missing command after -- (e.g., llvmup run official@23 -- clang++ --version)'
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath

    if ($locked) {
        $cfgPath = Find-LlvmProjectConfigPath
        $lockRoot = if ($cfgPath) { Split-Path $cfgPath -Parent } else { (Get-Location).Path }
        $lockPath = Join-Path $lockRoot '.llvmup-lock.json'
        $entry = Get-LlvmLockfileEntryForHost -LockPath $lockPath
        $manifest = Resolve-LlvmInstalledToolchain -Selector $entry.canonical_id -ToolchainsPath $toolchainsPath -HomePath $homePath -AllowAlias:$false
        if (-not $manifest) {
            throw "Locked toolchain '$($entry.canonical_id)' is not installed. Run 'llvmup sync --locked' first."
        }
        Assert-LlvmLockedInstallation -Manifest $manifest -Entry $entry -Policy $entry.verify_policy
        if (-not $target -and $entry.target) { $target = [string]$entry.target }
        if (-not $compiler -and $entry.variant -and $entry.variant.default_compiler) { $compiler = [string]$entry.variant.default_compiler }
    } elseif ($selector) {
        $manifest = Resolve-LlvmInstalledToolchain -Selector $selector -ToolchainsPath $toolchainsPath -HomePath $homePath -CrtFilter $crt
        if (-not $manifest) {
            if (-not $installMissing) {
                throw (Format-LlvmNoMatchMessage -Selector $selector)
            }
            $res = Invoke-LlvmInstallPrebuiltFromRecipe -Selector $selector -Crt $crt -Target $target -Compiler $compiler -ArchiveOnly -ToolchainsPath $toolchainsPath -HomePath $homePath
            $manifest = $res.manifest
        }
    } else {
        $eff = Resolve-LlvmEffectiveSelection -TargetOverride $target -CompilerOverride $compiler -CrtFilter $crt -ToolchainsPath $toolchainsPath -HomePath $homePath
        if (-not $eff) {
            throw 'No toolchain is selected, configured, or set as default.'
        }
        $manifest = $eff.manifest
        if (-not $compiler) { $compiler = $eff.compiler }
        if (-not $target) { $target = $eff.target }
    }

    $delta = Get-LlvmEnvironmentDelta -Manifest $manifest -Target $target -Compiler $compiler
    $exe = $cmdTokens[0]
    $argsRest = if ($cmdTokens.Count -gt 1) { @($cmdTokens[1..($cmdTokens.Count - 1)]) } else { @() }
    Invoke-LlvmProcessWithDelta -Delta $delta -Executable $exe -Arguments $argsRest
    return
}

function Invoke-LlvmUpAlias {
    param([string[]]$Tokens)
    $homePath = Get-LlvmHomePath
    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $sub = if ($Tokens.Count) { $Tokens[0].ToLowerInvariant() } else { 'list' }
    switch ($sub) {
        'set' {
            if ($Tokens.Count -ne 3) { throw 'Usage: llvmup alias set <alias> <installed-selector>' }
            return Set-LlvmAlias -AliasName $Tokens[1] -TargetSelector $Tokens[2] -ToolchainsPath $toolchainsPath -HomePath $homePath
        }
        'list' {
            $aliases = Get-LlvmAliases -HomePath $homePath
            if ($Tokens -contains '--json') { return ($aliases | ConvertTo-Json -Depth 4) }
            $items = @()
            foreach ($k in ($aliases.Keys | Sort-Object)) {
                $items += [pscustomobject][ordered]@{ alias = $k; target = $aliases[$k].target_name; provider = $aliases[$k].provider; llvm_version = $aliases[$k].llvm_version }
            }
            return $items
        }
        'show' {
            if ($Tokens.Count -ne 2) { throw 'Usage: llvmup alias show <alias>' }
            $aliases = Get-LlvmAliases -HomePath $homePath
            if (-not $aliases.ContainsKey($Tokens[1])) { throw "Alias '$($Tokens[1])' does not exist." }
            return [pscustomobject]$aliases[$Tokens[1]]
        }
        'remove' {
            if ($Tokens.Count -ne 2) { throw 'Usage: llvmup alias remove <alias>' }
            $removed = Remove-LlvmAlias -AliasName $Tokens[1] -HomePath $homePath
            if ($removed) { Write-Host "Alias '$($Tokens[1])' removed. Toolchain preserved." }
            return $removed
        }
        default { throw 'Available alias subcommands: set, list, show, remove' }
    }
}

function Invoke-LlvmUpPin {
    param([string[]]$Tokens)
    $useCurrent = $false
    $fuzzy = $false
    $crt = ''
    $target = ''
    $compiler = ''
    $selector = ''
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--current' { $useCurrent = $true }
            '--fuzzy' { $fuzzy = $true }
            '--crt' { if (++$i -ge $Tokens.Count) { throw '--crt requires a value' }; $crt = $Tokens[$i] }
            '--target' { if (++$i -ge $Tokens.Count) { throw '--target requires a value' }; $target = $Tokens[$i] }
            '--compiler' { if (++$i -ge $Tokens.Count) { throw '--compiler requires a value' }; $compiler = $Tokens[$i] }
            default {
                if ($Tokens[$i].StartsWith('-')) { throw "Unknown pin option: $($Tokens[$i])" }
                $selector = $Tokens[$i]
            }
        }
    }

    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    $cfgPath = Find-LlvmProjectConfigPath
    if (-not $cfgPath) { $cfgPath = Join-Path (Get-Location).Path '.llvmup-config' }

    if ($useCurrent) {
        $eff = Resolve-LlvmEffectiveSelection -ToolchainsPath $toolchainsPath -HomePath $homePath
        if (-not $eff) { throw 'No active or selected toolchain to pin.' }
        $m = $eff.manifest
        $verVal = if ($m.provider -eq 'official' -and $m.provider_release) { $m.provider_release } elseif ($m.llvm_version) { $m.llvm_version } else { $m.install_name }
        $effCrt = if ($crt) { $crt } elseif ($m.variant -and $m.variant.crt -and $m.variant.crt -ne 'system' -and $m.variant.crt -ne 'unknown') { $m.variant.crt } else { '' }
        $effTarget = if ($target) { $target } else { $eff.target }
        $effCompiler = if ($compiler) { $compiler } else { $eff.compiler }
        $relVal = if ($m.provider -ne 'official' -and $m.provider_release) { $m.provider_release } else { '' }
        $null = Update-LlvmConfigPin -ConfigPath $cfgPath -VersionValue $verVal -Provider $m.provider -Kind $(if ($m.origin -eq 'source') { 'source' } else { 'prebuilt' }) -Crt $effCrt -Target $effTarget -Compiler $effCompiler -ReleaseTag $relVal
        return $cfgPath
    }

    if (-not $selector) { throw 'Specify a selector or --current for llvmup pin' }
    $split = Split-LlvmSelector -Selector $selector
    $effProvider = if ($split.provider) { $split.provider } else { '' }
    $effExpr = $split.expression

    if (-not $fuzzy) {
        # Expand personal aliases or exact local installs offline first; fallback to remote resolve
        $localMatch = Resolve-LlvmInstalledToolchain -Selector $selector -ToolchainsPath $toolchainsPath -HomePath $homePath -CrtFilter $crt
        if ($localMatch) {
            $verVal = if ($localMatch.provider -eq 'official' -and $localMatch.provider_release) { $localMatch.provider_release } elseif ($localMatch.llvm_version) { $localMatch.llvm_version } else { $localMatch.install_name }
            $effCrt = if ($crt) { $crt } elseif ($localMatch.variant -and $localMatch.variant.crt -and $localMatch.variant.crt -ne 'system' -and $localMatch.variant.crt -ne 'unknown') { $localMatch.variant.crt } else { '' }
            $effTarget = if ($target) { $target } else { $localMatch.default_target }
            $effCompiler = if ($compiler) { $compiler } elseif ($localMatch.variant) { $localMatch.variant.default_compiler } else { '' }
            $relVal = if ($localMatch.provider -ne 'official' -and $localMatch.provider_release) { $localMatch.provider_release } else { '' }
            $null = Update-LlvmConfigPin -ConfigPath $cfgPath -VersionValue $verVal -Provider $localMatch.provider -Kind $(if ($localMatch.origin -eq 'source') { 'source' } else { 'prebuilt' }) -Crt $effCrt -Target $effTarget -Compiler $effCompiler -ReleaseTag $relVal
            return $cfgPath
        }
        $remote = Invoke-LlvmInstallPrebuiltFromRecipe -Selector $selector -Provider $effProvider -Crt $crt -Target $target -Compiler $compiler -ResolveOnly -ToolchainsPath $toolchainsPath -HomePath $homePath -Quiet
        $verVal = if ($remote.provider -eq 'official') { $remote.release } else { $remote.llvm_version }
        $relVal = if ($remote.provider -ne 'official') { $remote.release } else { '' }
        $null = Update-LlvmConfigPin -ConfigPath $cfgPath -VersionValue $verVal -Provider $remote.provider -Kind 'prebuilt' -Crt $(if ($crt) { $crt } else { $remote.crt }) -Target $(if ($target) { $target } else { $remote.target }) -Compiler $compiler -ReleaseTag $relVal
        return $cfgPath
    }

    $null = Update-LlvmConfigPin -ConfigPath $cfgPath -VersionValue $effExpr -Provider $(if ($effProvider) { $effProvider } else { 'official' }) -Kind 'prebuilt' -Crt $crt -Target $target -Compiler $compiler
    return $cfgPath
}

function Invoke-LlvmUpSync {
    param([string[]]$Tokens)
    $locked = $false
    $verify = ''
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--locked' { $locked = $true }
            '--verify' { if (++$i -ge $Tokens.Count) { throw '--verify requires a value' }; $verify = $Tokens[$i] }
            default { throw "Unknown sync option: $($Tokens[$i])" }
        }
    }
    $cfgPath = Find-LlvmProjectConfigPath
    if (-not $cfgPath) { throw 'No .llvmup-config file found for sync.' }
    $cfg = Read-LlvmProjectConfigData -ConfigPath $cfgPath
    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath

    if ($locked) {
        $lockPath = Join-Path $cfg.root '.llvmup-lock.json'
        $entry = Get-LlvmLockfileEntryForHost -LockPath $lockPath
        $lockedPolicy = if ($entry.verify_policy) { $entry.verify_policy } else { 'warn' }
        $policy = if ($verify) { Resolve-LlvmVerifyPolicy -RequestedPolicy $verify } else { $lockedPolicy }
        $rank = @{ skip = 0; warn = 1; strict = 2 }
        if (-not $rank.ContainsKey($lockedPolicy) -or $rank[$policy] -lt $rank[$lockedPolicy]) {
            throw "Verification policy '$policy' is weaker than or incompatible with the locked policy '$lockedPolicy'."
        }
        if ($cfg.provider -and $entry.provider -ne $cfg.provider) {
            throw "Lockfile provider '$($entry.provider)' conflicts with .llvmup-config provider '$($cfg.provider)'."
        }
        if ($cfg.crt -and $entry.variant.crt -and $entry.variant.crt -ne $cfg.crt) {
            throw "Lockfile CRT '$($entry.variant.crt)' conflicts with .llvmup-config CRT '$($cfg.crt)'."
        }
        $existing = Resolve-LlvmInstalledToolchain -Selector $entry.canonical_id -ToolchainsPath $toolchainsPath -HomePath $homePath -AllowAlias:$false
        if ($existing) {
            Assert-LlvmLockedInstallation -Manifest $existing -Entry $entry -Policy $policy
            return $true
        }
        $res = Invoke-LlvmInstallPrebuiltFromRecipe `
            -Provider $entry.provider `
            -ReleaseTag $entry.release `
            -Crt $(if ($entry.variant.crt -and $entry.variant.crt -ne 'system') { $entry.variant.crt } else { '' }) `
            -Threads $(if ($entry.variant.threads -and $entry.variant.threads -ne 'system') { $entry.variant.threads } else { '' }) `
            -Target $(if ($entry.target) { $entry.target } else { '' }) `
            -Compiler $(if ($entry.variant.default_compiler) { $entry.variant.default_compiler } else { '' }) `
            -Name $entry.canonical_id `
            -Profile $(if ($entry.profile) { $entry.profile } else { 'full' }) `
            -Components @($entry.components) `
            -VerifyPolicy $policy `
            -LockedEntry $entry `
            -ArchiveOnly `
            -ToolchainsPath $toolchainsPath `
            -HomePath $homePath
        return $true
    }

    if ($cfg.kind -eq 'source') {
        $installScript = Join-Path $PSScriptRoot 'Install-Llvm.ps1'
        Push-Location $cfg.root
        try {
            $params = @{ FromSource = $true; Quiet = $true }
            if ($cfg.name) { $params.Name = $cfg.name }
            if ($cfg.profile) { $params.Profile = $cfg.profile }
            if ($cfg.components.Count) { $params.Component = $cfg.components }
            if ($cfg.cmake_flags.Count) { $params.CmakeFlags = $cfg.cmake_flags }
            return & $installScript install $cfg.version @params
        } finally { Pop-Location }
    }

    $provider = if ($cfg.provider) { $cfg.provider } else { 'official' }
    $null = Invoke-LlvmInstallPrebuiltFromRecipe `
        -Selector $cfg.version `
        -Provider $provider `
        -ReleaseTag $cfg.release `
        -Crt $cfg.crt `
        -Threads $cfg.threads `
        -Target $cfg.target `
        -Compiler $cfg.compiler `
        -Name $cfg.name `
        -Profile $(if ($cfg.profile) { $cfg.profile } else { 'full' }) `
        -Components @($cfg.components) `
        -VerifyPolicy $verify `
        -ArchiveOnly `
        -ToolchainsPath $toolchainsPath `
        -HomePath $homePath
    return $true
}

function Invoke-LlvmUpConfig {
    param([string[]]$Tokens)
    $action = if ($Tokens.Count) { $Tokens[0].ToLowerInvariant() } else { '' }
    switch ($action) {
        'init' { return Initialize-LlvmConfig }
        'load' { return Import-LlvmConfig }
        'apply' {
            $cfgPath = Find-LlvmProjectConfigPath
            if (-not $cfgPath) { throw 'No .llvmup-config file found' }
            $cfg = Read-LlvmProjectConfigData -ConfigPath $cfgPath
            if ($cfg.kind -eq 'source') {
                Push-Location $cfg.root
                try { return & (Join-Path $PSScriptRoot 'Install-Llvm.ps1') config apply }
                finally { Pop-Location }
            }
            return Invoke-LlvmUpSync -Tokens @()
        }
        'activate' {
            $toolchainsPath = Get-LlvmSessionToolchainsPath
            $homePath = Get-LlvmHomePath
            $sel = Resolve-LlvmEffectiveSelection -ToolchainsPath $toolchainsPath -HomePath $homePath
            if (-not $sel) { throw 'No installed toolchain matches project configuration' }
            $delta = Get-LlvmEnvironmentDelta -Manifest $sel.manifest -Target $sel.target -Compiler $sel.compiler
            return (Apply-LlvmEnvironmentDelta -Delta $delta)
        }
        'lock' {
            $cfgPath = Find-LlvmProjectConfigPath
            if (-not $cfgPath) { throw 'No .llvmup-config file found' }
            $cfg = Read-LlvmProjectConfigData -ConfigPath $cfgPath
            $provider = if ($cfg.provider) { $cfg.provider } else { 'official' }
            $recipe = Get-LlvmRecipe -Provider $provider
            $releases = Invoke-LlvmProviderReleases -Provider $provider -ApiUrl $recipe.api_url
            $lockOs = ''; $lockArch = ''; $lockVerify = ''
            for ($i = 1; $i -lt $Tokens.Count; $i++) {
                switch ($Tokens[$i]) {
                    '--platform' { $lockOs = $Tokens[++$i] }
                    '--arch' { $lockArch = $Tokens[++$i] }
                    '--verify' { $lockVerify = $Tokens[++$i] }
                    default { throw "Unknown config lock option: $($Tokens[$i])" }
                }
            }
            if ($cfg.kind -eq 'source') { throw "Source builds ($($cfg.version)) cannot be locked; only prebuilt provider assets have a reproducible identity." }
            $plan = Resolve-LlvmRecipeInstallPlan -Provider $provider -Releases $releases -VersionExpression $cfg.version -ReleaseTag $cfg.release -Platform $lockOs -Arch $lockArch -Crt $cfg.crt -Threads $cfg.threads -Target $cfg.target -Compiler $cfg.compiler -Profile $(if ($cfg.profile) { $cfg.profile } else { 'full' }) -ArchiveOnly
            $lockPath = Join-Path $cfg.root '.llvmup-lock.json'
            $null = Write-LlvmLockfileEntry -LockPath $lockPath -Plan $plan -Profile $(if ($cfg.profile) { $cfg.profile } else { 'full' }) -Components @($cfg.components) -VerifyPolicy (Resolve-LlvmVerifyPolicy -RequestedPolicy $lockVerify)
            return $lockPath
        }
        default { throw 'Available config subcommands: init, load, apply, activate, lock' }
    }
}

function Test-LlvmInteractiveConsole {
    # Separate function so tests (and hosts without a console) can decide interactivity.
    try {
        if ([Console]::IsInputRedirected -or -not $Host.UI -or -not $Host.UI.RawUI) { return $false }
        return [Environment]::UserInteractive
    } catch { return $false }
}

function Invoke-LlvmUpPick {
    # Numbered local selector: installations and aliases only, never remote releases.
    param([string[]]$Tokens)
    $toolchainsPath = Get-LlvmSessionToolchainsPath
    $homePath = Get-LlvmHomePath
    $all = @(Get-LlvmAllToolchains -ToolchainsPath $toolchainsPath -HomePath $homePath | Where-Object { -not $_.missing_on_disk })
    if ($all.Count -eq 0) { throw 'No installed toolchains found.' }

    $active = Get-LlvmActiveVersion
    $default = Get-LlvmDefaultVersion -HomePath $homePath
    $aliasMap = @{}
    try {
        $al = Get-LlvmAliases -HomePath $homePath
        if ($al -and $al.Count) {
            foreach ($k in @($al.Keys)) {
                $t = [string]$al[$k].target_name
                if (-not $aliasMap.ContainsKey($t)) { $aliasMap[$t] = @() }
                $aliasMap[$t] += $k
            }
        }
    } catch {}
    for ($i = 0; $i -lt $all.Count; $i++) {
        $t = $all[$i]
        $tags = @()
        if ($t.install_name -eq $active) { $tags += 'active' }
        if ($t.install_name -eq $default) { $tags += 'default' }
        $extra = @()
        if ($t.variant -and $t.variant.crt -and $t.variant.crt -notin @('unknown', 'system')) { $extra += "crt=$($t.variant.crt)" }
        if ($t.default_target) { $extra += "target=$($t.default_target)" }
        if ($t.capabilities -and $t.capabilities.compilers -and @($t.capabilities.compilers).Count -gt 1) { $extra += "compilers=$(@($t.capabilities.compilers) -join ',')" }
        if ($aliasMap.ContainsKey([string]$t.install_name)) { $extra += "aliases=$($aliasMap[[string]$t.install_name] -join ',')" }
        $tagStr = if ($tags.Count) { " [$($tags -join ', ')]" } else { '' }
        Write-Host ("  {0,2}) {1,-46} {2,-10} LLVM {3,-8} {4}{5}" -f ($i + 1), $t.install_name, $t.provider, $t.llvm_version, ($extra -join ' '), $tagStr)
    }
    if (-not (Test-LlvmInteractiveConsole)) {
        throw 'llvmup pick needs an interactive terminal; use llvmup use <toolchain> in scripts.'
    }
    $choice = Read-Host "Select toolchain (1-$($all.Count), or q to cancel)"
    if ($choice -eq 'q' -or -not $choice) { return $false }
    if ($choice -notmatch '^\d+$') { throw "Invalid selection '$choice'" }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $all.Count) { throw "Selection out of range" }
    return Invoke-LlvmUpUse -Tokens @($all[$idx].install_name)
}

function llvmup {
    param(
        [Parameter(Position = 0)]
        [string]$LlvmupSubcommand,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$LlvmupArgs
    )

    $tokens = @()
    if ($null -ne $LlvmupSubcommand -and $LlvmupSubcommand -ne '') { $tokens += $LlvmupSubcommand }
    if ($LlvmupArgs) { $tokens += @($LlvmupArgs | ForEach-Object { [string]$_ }) }

    if ($tokens.Count -and $tokens[0] -eq '--version') {
        if ($tokens.Count -ne 1) {
            Write-Error 'Usage: llvmup --version' -ErrorAction Continue
            return $false
        }
        foreach ($name in @('llvmup-version', 'VERSION')) {
            $versionPath = Join-Path $PSScriptRoot $name
            if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
                return ('llvmup ' + ([IO.File]::ReadAllText($versionPath).Trim() -creplace '^v', ''))
            }
        }
        return 'llvmup development'
    }

    # Support +<toolchain> shorthand (e.g. llvmup +official@23 -- clang++ --version)
    if ($tokens.Count -gt 0 -and $tokens[0].StartsWith('+') -and $tokens[0].Length -gt 1) {
        try {
            $preset = $tokens[0].Substring(1)
            $rest = if ($tokens.Count -gt 1) { @($tokens[1..($tokens.Count - 1)]) } else { @() }
            return Invoke-LlvmUpRun -Tokens $rest -PresetSelector $preset
        } catch {
            $lines = @(Split-LlvmUpMessage -Message $_.Exception.Message)
            Write-Error $lines[0] -ErrorAction Continue
            Write-LlvmUpGuidance -Lines $lines
            return $false
        }
    }

    $knownCommands = @(
        'doctor', 'install', 'use', 'run', 'activate', 'deactivate', 'env', 'resolve',
        'vscode-activate', 'status', 'list', 'remove', 'disk-usage', 'default', 'config',
        'alias', 'pin', 'sync', 'which', 'where', 'provides', 'info', 'update',
        'pick', 'toolchain', 'shell', 'cmake-toolchain', 'help'
    )
    $command = 'install'
    if ($tokens.Count -and $knownCommands -contains $tokens[0].ToLowerInvariant()) {
        $command = $tokens[0].ToLowerInvariant()
        $tokens = @($tokens | Select-Object -Skip 1)
    } elseif ($tokens.Count -and $tokens[0] -notmatch '^(-|[0-9~^<>=*]|latest$|newest$|prebuilt$|llvmorg-|[A-Za-z0-9][A-Za-z0-9-]*@)') {
        # Legacy 'llvmup <version>' installs; anything else is a typo, not a remote version query.
        Write-Error "Unknown command '$($tokens[0])'. Run 'llvmup help' for the list of commands." -ErrorAction Continue
        return $false
    }

    # Help is answered before anything touches the network or the installations.
    if ($command -ne 'help') {
        $beforeSep = @()
        foreach ($t in $tokens) { if ($t -eq '--') { break }; $beforeSep += $t }
        $wantsHelp = ($beforeSep -contains '--help') -or (($beforeSep -contains '-h') -and $command -ne 'disk-usage')
        if ($wantsHelp -and (Test-LlvmCommandHelp -Command $command)) { Show-LlvmCommandHelp -Command $command; return }
    }

    try {
        $toolchainsPath = Get-LlvmSessionToolchainsPath
        $homePath = Get-LlvmHomePath
        switch ($command) {
            'doctor' {
                Import-Module (Join-Path $PSScriptRoot 'Llvm-Doctor.psm1') -DisableNameChecking -ErrorAction Stop
                Invoke-LlvmDoctor -Tokens $tokens
                return
            }
            'install' { return Invoke-LlvmUpInstall -Tokens $tokens }
            'use' { return Invoke-LlvmUpUse -Tokens $tokens }
            'run' { return Invoke-LlvmUpRun -Tokens $tokens }
            'activate' {
                if (-not $tokens.Count) { throw "Missing version argument for 'activate'" }
                $comp = ''; $tgt = ''
                for ($i = 1; $i -lt $tokens.Count; $i++) {
                    if ($tokens[$i] -eq '--compiler' -and ($i + 1) -lt $tokens.Count) { $comp = $tokens[++$i] }
                    elseif ($tokens[$i] -eq '--target' -and ($i + 1) -lt $tokens.Count) { $tgt = $tokens[++$i] }
                }
                return Activate-Llvm -Version $tokens[0] -Compiler $comp -Target $tgt
            }
            'deactivate' { return Deactivate-Llvm }
            'env' { return Invoke-LlvmUpEnv -Tokens $tokens }
            'resolve' { return Invoke-LlvmUpResolve -Tokens $tokens }
            'vscode-activate' {
                if (-not $tokens.Count) { throw "Missing version argument for 'vscode-activate'" }
                return & (Join-Path $PSScriptRoot 'Activate-LlvmVsCode.ps1') -Version $tokens[0]
            }
            'status' {
                return Get-LlvmStatus -Explain:($tokens -contains '--explain') -Json:($tokens -contains '--json')
            }
            'list' {
                $prov = ''
                for ($i = 0; $i -lt $tokens.Count; $i++) {
                    if ($tokens[$i] -eq '--provider' -and ($i + 1) -lt $tokens.Count) { $prov = $tokens[++$i]; continue }
                    if ($tokens[$i] -notin @('--remote', '--json', '--providers')) { throw "Unknown list option: $($tokens[$i])" }
                }
                return Get-LlvmList -Remote:($tokens -contains '--remote') -Json:($tokens -contains '--json') -Providers:($tokens -contains '--providers') -Provider $prov
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
                    'set' {
                        if ($tokens.Count -ne 2) { throw 'default set requires one version' }
                        $res = Resolve-LlvmInstalledToolchain -Selector $tokens[1] -ToolchainsPath $toolchainsPath -HomePath $homePath
                        $targetName = if ($res) { $res.install_name } else { $tokens[1] }
                        return Set-LlvmDefaultVersion -Version $targetName
                    }
                    'show' {
                        $defaultVersion = Get-LlvmDefaultVersion
                        if ($defaultVersion) { return $defaultVersion }
                        Write-Output 'No default LLVM version is set'
                        return
                    }
                    'unset' { return Clear-LlvmDefaultVersion }
                    default {
                        if ($tokens.Count -eq 1) {
                            $res = Resolve-LlvmInstalledToolchain -Selector $tokens[0] -ToolchainsPath $toolchainsPath -HomePath $homePath
                            $targetName = if ($res) { $res.install_name } else { $tokens[0] }
                            return Set-LlvmDefaultVersion -Version $targetName
                        }
                        throw 'Available default subcommands: set, show, unset, or <selector>'
                    }
                }
            }
            'config' { return Invoke-LlvmUpConfig -Tokens $tokens }
            'alias' { return Invoke-LlvmUpAlias -Tokens $tokens }
            'pin' { return Invoke-LlvmUpPin -Tokens $tokens }
            'sync' { return Invoke-LlvmUpSync -Tokens $tokens }
            'which' {
                $toolName = ''; $tcSel = ''; $comp = ''; $tgt = ''
                for ($i = 0; $i -lt $tokens.Count; $i++) {
                    switch ($tokens[$i]) {
                        '--toolchain' { $tcSel = $tokens[++$i] }
                        '--compiler' { $comp = $tokens[++$i] }
                        '--target' { $tgt = $tokens[++$i] }
                        default { if ($tokens[$i].StartsWith('-')) { throw "Unknown which option: $($tokens[$i])" }; $toolName = $tokens[$i] }
                    }
                }
                if (-not $toolName) { throw 'Usage: llvmup which <tool> [--toolchain <selector>]' }
                $eff = Resolve-LlvmEffectiveSelection -ExplicitSelector $tcSel -CompilerOverride $comp -TargetOverride $tgt -ToolchainsPath $toolchainsPath -HomePath $homePath
                if (-not $eff) { throw 'No toolchain selected or installed.' }
                $delta = Get-LlvmEnvironmentDelta -Manifest $eff.manifest -Target $eff.target -Compiler $eff.compiler
                $resolvedTool = Resolve-LlvmChildExecutable -CommandName $toolName -Delta $delta
                # Ensure the resolved executable actually belongs to the selected toolchain root
                $rootPrefix = [IO.Path]::GetFullPath($eff.manifest.root_path).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
                if (-not [IO.Path]::GetFullPath($resolvedTool).StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Tool '$toolName' is not available in toolchain '$($eff.manifest.install_name)' ($($eff.manifest.provider))."
                }
                return $resolvedTool
            }
            'where' {
                $sel = if ($tokens.Count) { $tokens[0] } else { '' }
                $eff = Resolve-LlvmEffectiveSelection -ExplicitSelector $sel -ToolchainsPath $toolchainsPath -HomePath $homePath
                if (-not $eff) { throw 'No matching toolchain found.' }
                return $eff.manifest.root_path
            }
            'provides' {
                if (-not $tokens.Count) { throw 'Usage: llvmup provides <tool>' }
                $toolReq = $tokens[0].ToLowerInvariant()
                $all = @(Get-LlvmAllToolchains -ToolchainsPath $toolchainsPath -HomePath $homePath | Where-Object { -not $_.missing_on_disk })
                $matches = @()
                foreach ($m in $all) {
                    $hit = $false
                    if ($m.tools) {
                        foreach ($k in $m.tools.Keys) {
                            if ($k -eq 'target_wrappers') { continue }
                            if ($k.ToLowerInvariant() -eq $toolReq) { $hit = $true; break }
                        }
                    }
                    if (-not $hit -and (Test-Path -LiteralPath (Join-Path $m.root_path 'bin') -PathType Container)) {
                        foreach ($ext in @('.exe', '.cmd', '')) {
                            if (Test-Path -LiteralPath (Join-Path (Join-Path $m.root_path 'bin') "$toolReq$ext") -PathType Leaf) { $hit = $true; break }
                        }
                    }
                    if ($hit) {
                        $matches += [pscustomobject][ordered]@{ name = $m.install_name; provider = $m.provider; llvm_version = $m.llvm_version; path = $m.root_path }
                    }
                }
                if ($tokens -contains '--json') { return ($matches | ConvertTo-Json -Depth 4) }
                return $matches
            }
            'info' {
                $jsonOut = $tokens -contains '--json'
                $sel = @($tokens | Where-Object { $_ -ne '--json' }) | Select-Object -First 1
                $eff = Resolve-LlvmEffectiveSelection -ExplicitSelector $sel -ToolchainsPath $toolchainsPath -HomePath $homePath
                if (-not $eff) { throw 'No matching toolchain found.' }
                if ($jsonOut) { return ($eff.manifest | ConvertTo-Json -Depth 10) }
                return [pscustomobject]$eff.manifest
            }
            'update' {
                $sel = if ($tokens.Count) { $tokens[0] } else { '' }
                $targets = @(if ($sel) {
                    Resolve-LlvmInstalledToolchain -Selector $sel -ToolchainsPath $toolchainsPath -HomePath $homePath
                } else {
                    Get-LlvmAllToolchains -ToolchainsPath $toolchainsPath -HomePath $homePath | Where-Object { $_.origin -eq 'managed' }
                })
                if ($sel -and -not $targets[0]) { throw (Format-LlvmNoMatchMessage -Selector $sel) }
                $ok = $true
                foreach ($t in $targets) {
                    if (-not $t) { continue }
                    if ($t.origin -ne 'managed') { Write-Warning "Skipping $($t.install_name): $($t.origin) toolchains are not updated."; continue }
                    # Same provider, LLVM major and CRT; never replaces the installation, aliases, default or pins.
                    $majorExpr = if ($t.llvm_version -match '^(\d+)\.') { "$($matches[1]).*" } else { 'latest' }
                    $crtArg = if ($t.variant -and $t.variant.crt -and $t.variant.crt -notin @('system', 'unknown')) { $t.variant.crt } else { '' }
                    try {
                        $res = Invoke-LlvmInstallPrebuiltFromRecipe -Selector $majorExpr -Provider $t.provider -Crt $crtArg -ArchiveOnly -ResolveOnly -ToolchainsPath $toolchainsPath -HomePath $homePath
                        if (Resolve-LlvmInstalledToolchain -Selector $res.canonical_id -ToolchainsPath $toolchainsPath -HomePath $homePath -ErrorAction SilentlyContinue) {
                            Write-Host "$($t.install_name) is up to date ($($res.canonical_id))."
                            continue
                        }
                        Write-Host "Update available for $($t.install_name): installing $($res.canonical_id) as a new installation."
                        $null = Invoke-LlvmInstallPrebuiltFromRecipe -Selector $majorExpr -Provider $t.provider -ReleaseTag $res.release -Crt $crtArg -ArchiveOnly -ToolchainsPath $toolchainsPath -HomePath $homePath
                        Write-Host "The previous installation ($($t.install_name)) remains available; aliases, defaults and pins were not changed.`nTo use the new one:`n  llvmup use $(Format-LlvmCommandArgument $res.canonical_id)"
                    } catch {
                        Write-Warning "$($t.install_name): $($_.Exception.Message)"
                        $ok = $false
                    }
                }
                return $ok
            }
            'pick' { return Invoke-LlvmUpPick -Tokens $tokens }
            'toolchain' {
                $sub = if ($tokens.Count) { $tokens[0].ToLowerInvariant() } else { 'list' }
                switch ($sub) {
                    'link' {
                        if ($tokens.Count -ne 3) { throw 'Usage: llvmup toolchain link <name> <path>' }
                        return Register-LlvmExternalToolchain -Name $tokens[1] -Path $tokens[2] -ToolchainsPath $toolchainsPath -HomePath $homePath
                    }
                    'unlink' {
                        if ($tokens.Count -ne 2) { throw 'Usage: llvmup toolchain unlink <name>' }
                        $unlinked = Unregister-LlvmExternalToolchain -Name $tokens[1] -HomePath $homePath
                        if ($unlinked) { Write-Host "Toolchain '$($tokens[1])' unlinked. External files preserved." }
                        return $unlinked
                    }
                    'list' {
                        return Get-LlvmList
                    }
                    default { throw 'Available toolchain subcommands: link, unlink, list' }
                }
            }
            'shell' {
                $sel = ''; $comp = ''; $tgt = ''; $shellExe = ''
                for ($i = 0; $i -lt $tokens.Count; $i++) {
                    if ($tokens[$i] -eq '--compiler') { $comp = $tokens[++$i] }
                    elseif ($tokens[$i] -eq '--target') { $tgt = $tokens[++$i] }
                    elseif ($tokens[$i] -eq '--shell') { $shellExe = $tokens[++$i] }
                    elseif ($tokens[$i].StartsWith('-')) { throw "Unknown shell option: $($tokens[$i])" }
                    else { $sel = $tokens[$i] }
                }
                $eff = Resolve-LlvmEffectiveSelection -ExplicitSelector $sel -CompilerOverride $comp -TargetOverride $tgt -ToolchainsPath $toolchainsPath -HomePath $homePath
                if (-not $eff) { throw 'No matching toolchain found for shell.' }
                $delta = Get-LlvmEnvironmentDelta -Manifest $eff.manifest -Target $eff.target -Compiler $eff.compiler
                if ($shellExe) {
                    $shellArgs = @()
                } elseif ((Test-LlvmIsWindows) -or -not $env:SHELL) {
                    $shellExe = (Get-Process -Id $PID).Path
                    $shellArgs = @('-NoLogo')
                } else {
                    $shellExe = $env:SHELL
                    $shellArgs = @()
                }
                if ([IO.Path]::GetFileNameWithoutExtension($shellExe) -in @('pwsh', 'powershell') -and -not $shellArgs) { $shellArgs = @('-NoLogo') }
                Invoke-LlvmProcessWithDelta -Delta $delta -Executable $shellExe -Arguments $shellArgs -InheritShellOverride
                return
            }
            'cmake-toolchain' {
                $sel = ''; $comp = ''; $tgt = ''; $out = ''
                for ($i = 0; $i -lt $tokens.Count; $i++) {
                    switch ($tokens[$i]) {
                        '--target' { $tgt = $tokens[++$i] }
                        '--compiler' { $comp = $tokens[++$i] }
                        '--output' { $out = $tokens[++$i] }
                        '-o' { $out = $tokens[++$i] }
                        default { if ($tokens[$i].StartsWith('-')) { throw "Unknown cmake-toolchain option: $($tokens[$i])" }; $sel = $tokens[$i] }
                    }
                }
                $eff = Resolve-LlvmEffectiveSelection -ExplicitSelector $sel -CompilerOverride $comp -TargetOverride $tgt -ToolchainsPath $toolchainsPath -HomePath $homePath
                if (-not $eff) { throw 'No matching toolchain found for cmake-toolchain.' }
                return New-LlvmCMakeToolchainFile -Manifest $eff.manifest -Target $eff.target -Compiler $eff.compiler -OutputPath $out
            }
            'help' { return Show-LlvmHelp -Topic $(if ($tokens.Count) { [string]$tokens[0] } else { '' }) }
        }
    } catch {
        # This facade reports handled command failures by returning false.
        # Keep an ambient ErrorActionPreference=Stop (as used by GitHub
        # Actions) from turning that handled result into a new exception.
        $lines = @(Split-LlvmUpMessage -Message $_.Exception.Message)
        Write-Error $lines[0] -ErrorAction Continue
        Write-LlvmUpGuidance -Lines $lines
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
