Describe 'PowerShell llvmup lifecycle facade' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:modulePath = Join-Path $script:repoRoot 'Llvm-Functions.psm1'
    }

    BeforeEach {
        Remove-Module Llvm-Functions -Force -ErrorAction SilentlyContinue
        Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
        $env:LLVM_HOME = Join-Path $TestDrive 'llvm-home'
        $env:LLVM_TOOLCHAINS_DIR = Join-Path $TestDrive 'toolchains'
        $env:LLVMUP_RELEASES_FILE = Join-Path $script:repoRoot 'githubreleases.json'
        New-Item -ItemType Directory -Force -Path $env:LLVM_HOME, $env:LLVM_TOOLCHAINS_DIR | Out-Null
        Import-Module $script:modulePath -Force -DisableNameChecking
    }

    AfterEach {
        Remove-Item Env:_ACTIVE_LLVM -ErrorAction SilentlyContinue
        Remove-Item Env:_LLVM_BACKUP -ErrorAction SilentlyContinue
        Remove-Item Env:LLVMUP_ACTIVE_VERSION -ErrorAction SilentlyContinue
        Remove-Item Env:LLVM_HOME -ErrorAction SilentlyContinue
        Remove-Item Env:LLVM_TOOLCHAINS_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:LLVMUP_RELEASES_FILE -ErrorAction SilentlyContinue
    }

    It 'exports the canonical facade and advertised commands' {
        foreach ($name in @('llvmup', 'Activate-Llvm', 'Deactivate-Llvm', 'Get-LlvmStatus', 'Get-LlvmList', 'Initialize-LlvmConfig', 'Import-LlvmConfig', 'Show-LlvmHelp')) {
            Get-Command $name -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It 're-exports the core matcher with candidate-version support' {
        $command = Get-Command Invoke-LlvmMatchVersions
        $command.Parameters.Keys | Should -Contain 'CandidateVersions'

        Invoke-LlvmMatchVersions -Expression '~22.1.3' -CandidateVersions @(
            'llvmorg-22.1.2', 'llvmorg-22.1.3', 'llvmorg-22.1.8'
        ) | Should -BeExactly @('llvmorg-22.1.3', 'llvmorg-22.1.8')
    }

    It 'lists installed versions as valid JSON with active and default metadata' {
        $version = 'llvmorg-18.1.8'
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LLVM_TOOLCHAINS_DIR "$version/bin") | Out-Null
        llvmup default set $version | Should -BeTrue
        llvmup activate $version | Should -BeTrue

        $result = llvmup list --json | ConvertFrom-Json

        $result.active_version | Should -Be $version
        $result.default_version | Should -Be $version
        $result.installed_versions[0].active | Should -BeTrue
        $result.installed_versions[0].default | Should -BeTrue
    }

    It 'protects active and default versions and force removes only the toolchain' {
        $version = 'llvmorg-18.1.8'
        $sourcePath = Join-Path $TestDrive "sources/$version"
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LLVM_TOOLCHAINS_DIR "$version/bin"), $sourcePath | Out-Null
        llvmup default set $version | Should -BeTrue
        llvmup activate $version | Should -BeTrue

        $previousErrorActionPreference = $global:ErrorActionPreference
        try {
            # Match the environment created by GitHub Actions' pwsh runner.
            $global:ErrorActionPreference = 'Stop'
            $blocked = & { llvmup remove $version } 2>$null
        } finally {
            $global:ErrorActionPreference = $previousErrorActionPreference
        }
        $blocked | Should -BeFalse
        Test-Path (Join-Path $env:LLVM_TOOLCHAINS_DIR $version) | Should -BeTrue

        llvmup remove $version --force | Should -BeTrue
        Test-Path (Join-Path $env:LLVM_TOOLCHAINS_DIR $version) | Should -BeFalse
        Test-Path $sourcePath | Should -BeTrue
        Test-Path (Join-Path $env:LLVM_HOME 'default') | Should -BeFalse
        $env:_ACTIVE_LLVM | Should -BeNullOrEmpty
    }

    It 'clears the default link without deleting its toolchain target' {
        $version = 'llvmorg-18.1.8'
        $versionPath = Join-Path $env:LLVM_TOOLCHAINS_DIR $version
        $sentinelPath = Join-Path $versionPath 'bin/sentinel.txt'
        New-Item -ItemType Directory -Force -Path (Split-Path $sentinelPath -Parent) | Out-Null
        Set-Content -LiteralPath $sentinelPath -Value 'keep'

        llvmup default set $version | Should -BeTrue
        llvmup default unset | Should -BeTrue

        Test-Path -LiteralPath (Join-Path $env:LLVM_HOME 'default') | Should -BeFalse
        Test-Path -LiteralPath $sentinelPath | Should -BeTrue
    }

    It 'activates the nearest project configuration in the current session' {
        $version = 'llvmorg-18.1.8'
        $project = Join-Path $TestDrive 'project'
        $subdirectory = Join-Path $project 'nested'
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LLVM_TOOLCHAINS_DIR "$version/bin"), $subdirectory | Out-Null
        Set-Content -LiteralPath (Join-Path $project '.llvmup-config') -Value "[version]`ndefault = `"$version`""

        Push-Location $subdirectory
        try { llvmup config activate | Should -BeTrue }
        finally { Pop-Location }

        $env:_ACTIVE_LLVM | Should -Be $version
    }

    It 'lists stable remote releases as JSON using the fixture' {
        $result = llvmup list --remote --json | ConvertFrom-Json

        $result.remote_versions.Count | Should -BeGreaterThan 1
        $result.remote_versions[0] | Should -Be 'llvmorg-21.1.0'
    }

    It 'falls back to LLVM_HOME when no toolchains override is set' {
        Remove-Item Env:LLVM_TOOLCHAINS_DIR -ErrorAction SilentlyContinue
        $fallback = Join-Path $env:LLVM_HOME 'toolchains/llvmorg-20.1.8/bin'
        New-Item -ItemType Directory -Force -Path $fallback | Out-Null

        $result = llvmup list --json | ConvertFrom-Json

        $result.installed_versions[0].name | Should -Be 'llvmorg-20.1.8'
    }
}
