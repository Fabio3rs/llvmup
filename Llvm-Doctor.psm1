# Read-only checks. Does not import the facade (which may load shell integration).
function Add-DoctorCheck {
    param($Checks, $Id, $Category, $Status, $Description, $Recommendation = '', $Subject = '')
    $severity = switch ($Status) { FAIL { 'error' } WARN { 'warning' } default { 'info' } }
    $Checks.Add([pscustomobject][ordered]@{ id=$Id; category=$Category; severity=$severity; status=$Status; description=$Description; recommendation=$Recommendation; subject=$Subject })
}
function Test-DoctorCompiler {
    param([string]$Directory, [string]$Name)
    foreach ($suffix in @('.exe', '.cmd', '')) {
        $candidate = Join-Path $Directory "bin/$Name$suffix"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}
function Get-DoctorInstallation {
    param($Checks, $Root, $Toolchains, $LlvmHome)
    $files = @('Llvm-Functions.psm1','Llvm-Functions-Core.psm1','Get-UserHome.psm1','Llvm-Completion.psm1','Activate-Llvm.ps1','Deactivate-Llvm.ps1','Install-Llvm.ps1','Download-Llvm.ps1','Llvm-Config.ps1','Llvm-Default.ps1','Llvm-Doctor.psm1','Llvm-Doctor.ps1','Llvm-Doctor-Deep.ps1')
    $manifest = Join-Path $Root 'llvmup-files.tsv'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { $manifest = Join-Path $Root 'packaging/runtime-files.tsv' }
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        try {
            foreach ($line in Get-Content -LiteralPath $manifest -ErrorAction Stop) {
                $parts = $line -split '\s+'
                if ($parts[0] -notin @('common', 'powershell')) { continue }
                if ($parts.Count -ne 3 -or $parts[2] -notmatch '^(libexec/)?[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid manifest entry' }
                if ($parts[2] -notin $files) { $files += $parts[2] }
            }
        } catch { Add-DoctorCheck $Checks installation.manifest installation FAIL 'Cannot read runtime inventory.' 'Reinstall a complete LLVMUP package.' $manifest }
    }
    foreach ($file in $files) {
        $path = Join-Path $Root $file
        try {
            $stream = [IO.File]::OpenRead($path); $stream.Dispose()
            Add-DoctorCheck $Checks installation.file installation PASS 'Runtime file is readable.' '' $path
        } catch { Add-DoctorCheck $Checks installation.file installation FAIL 'Runtime file is missing or unreadable.' 'Restore the complete LLVMUP checkout.' $path }
    }
    foreach ($tool in @('tar','git','cmake','ninja','gpg','gh')) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) { Add-DoctorCheck $Checks "dependency.$tool" dependencies PASS 'Tool available.' '' $tool }
        else { Add-DoctorCheck $Checks "dependency.$tool" dependencies WARN 'Tool unavailable.' 'tar supports extraction; git/cmake/ninja are for source builds; gpg/gh are optional verification tools.' $tool }
    }
    $bootstrap = @('cl','clang','gcc') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }
    if ($bootstrap) { Add-DoctorCheck $Checks dependency.bootstrap dependencies PASS 'Bootstrap compiler discoverable (not executed).' 'Source builds also need C++ support and development libraries.' }
    else { Add-DoctorCheck $Checks dependency.bootstrap dependencies WARN 'No bootstrap compiler found.' 'For Windows source builds, use Developer PowerShell with Visual Studio C++ tools.' }
    Add-DoctorCheck $Checks dependency.powershell dependencies PASS "PowerShell $($PSVersionTable.PSVersion)." 'PowerShell 7 is recommended for all lifecycle helpers.'
    if (Test-Path -LiteralPath $Toolchains) {
        try {
            foreach ($dir in Get-ChildItem -LiteralPath $Toolchains -Directory -Force -ErrorAction Stop) {
                if ($dir.Name -match '\.installing[.-]') {
                    Add-DoctorCheck $Checks toolchain.staging toolchains WARN 'Installation staging directory remains.' 'Check for a running installer before manually cleaning up.' $dir.FullName
                    continue
                }
                if ((Test-DoctorCompiler $dir.FullName clang) -and (Test-DoctorCompiler $dir.FullName 'clang++')) {
                    Add-DoctorCheck $Checks toolchain.compilers toolchains PASS 'Compiler files exist (not executed).' '' $dir.FullName
                } else { Add-DoctorCheck $Checks toolchain.compilers toolchains FAIL 'Incomplete toolchain: compiler files missing.' 'Inspect permissions or reinstall this version.' $dir.FullName }
                $marker = Join-Path $dir.FullName '.llvmup-verification.json'
                if (Test-Path -LiteralPath $marker) {
                    try {
                        $record = Get-Content -LiteralPath $marker -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                        if ($record.schema -ne 1 -or -not $record.version -or $record.policy -notin @('warn','strict','skip')) { throw 'Unsupported record' }
                        Add-DoctorCheck $Checks toolchain.metadata toolchains PASS 'Recognized verification record; this does not authenticate installed files.' 'Reinstall with strict verification when provenance is uncertain.' $marker
                    } catch { Add-DoctorCheck $Checks toolchain.metadata toolchains WARN 'Malformed or unsupported verification record.' 'Inspect the record or reinstall with verification.' $marker }
                } else { Add-DoctorCheck $Checks toolchain.metadata toolchains SKIP 'No verification record; normal for source or legacy installs.' '' $dir.FullName }
            }
        } catch { Add-DoctorCheck $Checks toolchain.directory toolchains FAIL 'Toolchain directory cannot be enumerated.' 'Check directory type and permissions.' $Toolchains }
    } else { Add-DoctorCheck $Checks toolchain.empty toolchains SKIP 'No toolchain directory; installation is optional.' '' $Toolchains }
    $defaultPath = Join-Path $LlvmHome default
    # Get-Item can see a dangling junction/link without traversing or removing its target.
    $defaultItem = Get-Item -LiteralPath $defaultPath -Force -ErrorAction SilentlyContinue
    if ($defaultItem) {
        if ((Test-DoctorCompiler $defaultPath clang) -and (Test-DoctorCompiler $defaultPath 'clang++')) {
            Add-DoctorCheck $Checks toolchain.default toolchains PASS 'Default target has compiler files.' '' $defaultPath
        } else { Add-DoctorCheck $Checks toolchain.default toolchains FAIL 'Default link/target is broken or incomplete.' 'Select a complete installed version with llvmup default set.' $defaultPath }
    } else { Add-DoctorCheck $Checks toolchain.default toolchains SKIP 'No default configured.' 'Optional: llvmup default set <version>.' }
}
function Get-DoctorEnvironment {
    param($Checks, $Toolchains, $Root)
    $active = if ($env:_ACTIVE_LLVM) { $env:_ACTIVE_LLVM } elseif ($env:LLVMUP_ACTIVE_VERSION) { $env:LLVMUP_ACTIVE_VERSION } else { $env:LLVM_ACTIVE_VERSION }
    if ($active) {
        $directory = if ($env:_ACTIVE_LLVM_PATH) { $env:_ACTIVE_LLVM_PATH } else { Join-Path $Toolchains $active }
        if ((Test-DoctorCompiler $directory clang) -and (Test-DoctorCompiler $directory 'clang++')) {
            Add-DoctorCheck $Checks environment.active environment PASS 'Active toolchain exists.' '' $directory
        } else { Add-DoctorCheck $Checks environment.active environment FAIL 'Active version points to missing compiler files.' 'Deactivate and activate an installed version.' $directory }
        foreach ($name in @('clang','clang++')) {
            $command = Get-Command $name -ErrorAction SilentlyContinue
            $expected = Test-DoctorCompiler $directory $name
            if (-not $command -or -not $expected -or $command.Source -ne $expected) {
                Add-DoctorCheck $Checks environment.compiler environment WARN 'Compiler resolution differs from active version.' 'Review PATH, aliases and intentional wrappers.' $name
            } else { Add-DoctorCheck $Checks environment.compiler environment PASS 'Compiler resolves to active toolchain.' '' $name }
        }
        foreach ($pair in @(@('CC','clang'),@('CXX','clang++'),@('LD','lld'))) {
            $value = [Environment]::GetEnvironmentVariable($pair[0])
            if ($value -and $value -ne (Test-DoctorCompiler $directory $pair[1])) {
                Add-DoctorCheck $Checks environment.override environment WARN 'Compiler variable differs from defaults; it may be intentional.' 'Review overrides; CC/CXX must not point to clangd.' "$($pair[0])=$value"
            }
        }
        if (-not $env:_LLVM_BACKUP -and -not $env:_OLD_PATH) {
            Add-DoctorCheck $Checks environment.restore environment WARN 'Active environment has no saved restoration state.' 'Expected for env exports; module activation should save state.'
        }
    } elseif ($env:_LLVM_BACKUP -or $env:_OLD_PATH -or $env:_ACTIVE_LLVM_PATH) {
        Add-DoctorCheck $Checks environment.stale environment WARN 'Saved state exists without an active version.' 'Start a fresh shell.'
    } else { Add-DoctorCheck $Checks environment.active environment SKIP 'No active toolchain.' }
    if ($env:_LLVM_BACKUP) {
        try { $null = $env:_LLVM_BACKUP | ConvertFrom-Json -ErrorAction Stop }
        catch { Add-DoctorCheck $Checks environment.restore environment WARN 'Saved environment JSON is invalid.' 'Start a fresh shell before activating.' }
    }
    if ($env:LLVMUP_INSTALL_DIR -and $env:LLVMUP_INSTALL_DIR -ne $Root) {
        Add-DoctorCheck $Checks installation.path installation WARN 'LLVMUP_INSTALL_DIR differs from the loaded module directory.' 'Review which checkout and profile import should be used.' $env:LLVMUP_INSTALL_DIR
    }
    $executables = @(Get-Command llvmup -All -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -Unique)
    if ($executables.Count -gt 1) { Add-DoctorCheck $Checks installation.conflict installation WARN 'Multiple LLVMUP executables found on PATH.' 'Review PATH order and obsolete profile entries.' ($executables -join ', ') }
    $seen = @{}
    foreach ($entry in ($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator))) {
        if (-not $entry) { Add-DoctorCheck $Checks environment.path environment WARN 'PATH has an empty entry.' 'Review PATH construction.'; continue }
        if ($entry -match 'llvm' -or $entry.StartsWith($Toolchains)) {
            if ($seen.ContainsKey($entry)) { Add-DoctorCheck $Checks environment.path environment WARN 'Duplicate LLVMUP-related PATH entry.' 'Review duplicate activation/profile initialization.' $entry }
            $seen[$entry] = $true
        }
    }
    $profiles = @($PROFILE.CurrentUserCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.AllUsersAllHosts) | Select-Object -Unique
    $found = $false
    foreach ($profilePath in $profiles) {
        if (-not $profilePath -or -not (Test-Path -LiteralPath $profilePath)) { continue }
        try {
            $lines = @(Get-Content -LiteralPath $profilePath -ErrorAction Stop | Where-Object { $_ -match '^\s*Import-Module\s+.*Llvm-Functions\.psm1' })
            if ($lines.Count) { $found = $true }
            if ($lines.Count -gt 1) { Add-DoctorCheck $Checks shell.initialization shell WARN 'Duplicate LLVMUP imports in profile.' 'Keep one import; preserve unrelated profile content.' $profilePath }
            elseif ($lines.Count) { Add-DoctorCheck $Checks shell.initialization shell PASS 'LLVMUP import statement found (not executed).' '' $profilePath }
        } catch { Add-DoctorCheck $Checks shell.initialization shell WARN 'Profile is unreadable.' 'Check permissions.' $profilePath }
    }
    if (-not $found) { Add-DoctorCheck $Checks shell.initialization shell WARN 'No LLVMUP profile import found.' 'Import Llvm-Functions.psm1 in interactive sessions; CI needs no profile.' }
    if (Test-Path -LiteralPath (Join-Path $Root 'Llvm-Completion.psm1')) { Add-DoctorCheck $Checks shell.completion shell PASS 'Completion module exists.' 'Use --deep for an isolated load test.' }
    else { Add-DoctorCheck $Checks shell.completion shell FAIL 'Completion module missing.' 'Restore Llvm-Completion.psm1.' }
}
function Get-DoctorProject {
    param($Checks, $Toolchains, $Root)
    $directory = (Get-Location).Path
    $config = $null
    while ($directory) {
        $candidate = Join-Path $directory '.llvmup-config'
        if (Test-Path -LiteralPath $candidate) { $config = $candidate; break }
        $directory = Split-Path -Parent $directory
    }
    if (-not $config) { Add-DoctorCheck $Checks project.config project SKIP 'No project configuration found.'; return }
    try {
        # Parse as data, not script. Keep this independent of install/config-apply side effects.
        $section = ''; $values = @{}; $inArray = $false
        foreach ($line in Get-Content -LiteralPath $config -ErrorAction Stop) {
            $line = $line.Trim()
            if (-not $line -or $line -match '^[#;]') { continue }
            if ($inArray) { if ($line.Contains(']')) { $inArray = $false }; continue }
            if ($line -match '^\[([^]]+)\]$') { $section = $matches[1]; continue }
            if ($line -match '^([\w_]+)\s*=\s*(.*?)\s*$') {
                $key = "$section.$($matches[1])"
                if ($values.ContainsKey($key)) { throw "Duplicate setting: $key" }
                $value = $matches[2]
                if ($value.StartsWith('[') -and -not $value.Contains(']')) { $inArray = $true }
                if (($value.StartsWith('"') -or $value.StartsWith("'")) -and -not $value.Substring(1).Contains($value.Substring(0,1))) { throw 'Unclosed quoted value' }
                $values[$key] = $value.Trim('"', "'")
            } else { throw 'Malformed configuration assignment'
            }
        }
        if ($inArray) { throw 'Unclosed array' }
        $expression = if ($values['version.default']) { $values['version.default'] } else { $values['.version'] }
        if (-not $expression) { throw 'No version specified' }
        $auto = if ($values['project.auto_activate']) { $values['project.auto_activate'] } else { $values['.auto_activate'] }
        if ($auto -and $auto -notin @('true','false')) { throw 'Invalid auto_activate value' }
        if ($values['profile.type'] -and $values['profile.type'] -notin @('minimal','compiler','full','custom')) { throw 'Invalid profile' }
        $core = Join-Path $Root 'Llvm-Functions-Core.psm1'
        if (-not (Test-Path -LiteralPath $core)) { Add-DoctorCheck $Checks project.version project SKIP 'Version matcher missing.' 'Restore the core module.'; return }
        Import-Module $core -DisableNameChecking -ErrorAction Stop
        $null = Invoke-LlvmParseVersionExpression $expression
        Add-DoctorCheck $Checks project.config project PASS 'Project configuration parsed without activation.' '' $config
        $selected = @(Invoke-LlvmMatchVersions -Expression $expression -ToolchainsPath $Toolchains)
        if ($selected.Count) { Add-DoctorCheck $Checks project.version project PASS 'Configured expression matches installed versions.' '' ($selected -join ', ') }
        else { Add-DoctorCheck $Checks project.version project WARN 'No installed version matches configuration.' 'Install the configured version when ready.' $expression }
        if ($auto -eq 'true' -and -not $env:_ACTIVE_LLVM) { Add-DoctorCheck $Checks project.autoactivate project WARN 'Automatic activation requested but no active version.' 'Check module initialization and use llvmup config activate.' }
        foreach ($key in @('paths.llvm_home','paths.toolchains_dir','paths.sources_dir')) {
            if ($values[$key]) { Add-DoctorCheck $Checks project.paths project WARN 'Project path override requires review against session directory settings.' 'PowerShell configuration paths and activation settings may differ; set LLVM_HOME/LLVM_TOOLCHAINS_DIR explicitly.' "$key=$($values[$key])" }
        }
    } catch { Add-DoctorCheck $Checks project.config project FAIL "Invalid or unreadable project configuration: $($_.Exception.Message)" 'Check .llvmup-config against the documented format.' $config }
}
function Invoke-LlvmDoctor {
    param([string[]]$Tokens = @(), [string]$Root = $PSScriptRoot)
    $checks = [Collections.Generic.List[object]]::new()
    $invalid = @($Tokens | Where-Object { $_ -notin @('--verbose','--deep','--network','--json','--help','-h') })
    $code = 0
    if ($invalid.Count) {
        Add-DoctorCheck $checks arguments cli FAIL "Unknown doctor option: $($invalid[0])" 'Use doctor --help.'
        $code = 2
    } elseif ($Tokens -contains '--help' -or $Tokens -contains '-h') {
        'Usage: llvmup doctor [--verbose] [--deep] [--network] [--json]'
        $global:LASTEXITCODE = 0
        return
    } else {
        $userDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $llvmHome = if ($env:LLVM_HOME) { $env:LLVM_HOME } elseif ($env:LLVM_CUSTOM_HOME) { $env:LLVM_CUSTOM_HOME } else { Join-Path $userDirectory '.llvm' }
        $toolchains = if ($env:LLVM_TOOLCHAINS_DIR) { $env:LLVM_TOOLCHAINS_DIR } elseif ($env:LLVM_CUSTOM_TOOLCHAINS_DIR) { $env:LLVM_CUSTOM_TOOLCHAINS_DIR } else { Join-Path $llvmHome toolchains }
        foreach ($category in @('Installation','Environment','Project')) {
            try {
                switch ($category) {
                    Installation { Get-DoctorInstallation $checks $Root $toolchains $llvmHome }
                    Environment { Get-DoctorEnvironment $checks $toolchains $Root }
                    Project { Get-DoctorProject $checks $toolchains $Root }
                }
            } catch { Add-DoctorCheck $checks "doctor.$category" $category.ToLowerInvariant() FAIL "Check could not complete: $($_.Exception.Message)" 'Inspect paths and access permissions.' }
        }
        if ($Tokens -contains '--deep') {
            try {
                $engine = (Get-Process -Id $PID).Path
                $probeOutput = & $engine -NoProfile -NonInteractive -File (Join-Path $Root 'Llvm-Doctor-Deep.ps1') 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($probeOutput -join "`n") }
                Add-DoctorCheck $checks deep.activation deep PASS 'Isolated activation, restoration, matching and completion probes passed.'
            } catch { Add-DoctorCheck $checks deep.activation deep FAIL 'Isolated functional probes failed.' 'Run the PowerShell lifecycle regression suite.' }
        } else { Add-DoctorCheck $checks deep.activation deep SKIP 'Functional probes disabled.' 'Use --deep for isolated child-process checks.' }
        if ($Tokens -contains '--network') {
            try {
                $releases = Invoke-RestMethod 'https://api.github.com/repos/llvm/llvm-project/releases?per_page=1' -TimeoutSec 8 -MaximumRedirection 5 -ErrorAction Stop
                if (-not $releases[0].tag_name) { throw 'No release metadata returned' }
                Add-DoctorCheck $checks network.github network PASS 'GitHub release metadata retrieved and parsed.'
            } catch { Add-DoctorCheck $checks network.github network FAIL 'GitHub release metadata request failed.' 'Check proxy, TLS certificates and API rate limits.' }
            try {
                $null = Invoke-WebRequest 'https://github.com/llvm/llvm-project/releases/latest' -Method Head -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 5 -ErrorAction Stop
                Add-DoctorCheck $checks network.redirect network PASS 'Release page HEAD request and redirects succeeded.'
            } catch { Add-DoctorCheck $checks network.redirect network WARN 'Release page HEAD request failed.' 'Check proxy policy; HEAD may be blocked even when downloads work.' }
        } else { Add-DoctorCheck $checks network.github network SKIP 'Network checks disabled; no requests made.' 'Use --network to check GitHub.' }
    }
    if ($code -eq 0 -and @($checks | Where-Object status -eq FAIL).Count) { $code = 1 }
    if ($Tokens -contains '--json') { [ordered]@{ schema_version=1; checks=@($checks.ToArray()); exit_code=$code } | ConvertTo-Json -Depth 6 -Compress }
    else {
        foreach ($check in $checks) {
            "$($check.status) [$($check.id)] $($check.description) $($check.subject)"
            if ($check.recommendation -and ($check.status -in @('WARN','FAIL') -or $Tokens -contains '--verbose')) { "     $($check.recommendation)" }
        }
    }
    $global:LASTEXITCODE = $code
}
Export-ModuleMember -Function Invoke-LlvmDoctor
