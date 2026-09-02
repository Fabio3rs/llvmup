Describe 'Legacy PowerShell default command' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:defaultScript = Join-Path $script:repoRoot 'Llvm-Default.ps1'
    }

    BeforeEach {
        $env:LLVM_HOME = Join-Path $TestDrive "llvm-home-$([guid]::NewGuid().ToString('N'))"
        $env:LLVM_TOOLCHAINS_DIR = Join-Path $env:LLVM_HOME 'toolchains'
        $script:version = 'llvmorg-22.1.8'
        $script:versionPath = Join-Path $env:LLVM_TOOLCHAINS_DIR $script:version
        New-Item -ItemType Directory -Path (Join-Path $script:versionPath 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:versionPath 'bin/sentinel.txt') -Value 'keep'
    }

    AfterEach {
        Remove-Item Env:LLVM_HOME -ErrorAction SilentlyContinue
        Remove-Item Env:LLVM_TOOLCHAINS_DIR -ErrorAction SilentlyContinue
    }

    It 'replaces the default link without traversing its target' {
        & $script:defaultScript -Command set -Version $script:version
        & $script:defaultScript -Command set -Version $script:version

        Test-Path -LiteralPath (Join-Path $script:versionPath 'bin/sentinel.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:LLVM_HOME 'default') | Should -BeTrue
    }

    It 'refuses to clear an ordinary directory' {
        New-Item -ItemType Directory -Path (Join-Path $env:LLVM_HOME 'default') -Force | Out-Null

        $previousErrorActionPreference = $global:ErrorActionPreference
        try {
            $global:ErrorActionPreference = 'Stop'
            { & $script:defaultScript -Command unset } | Should -Throw '*Refusing to remove non-link*'
        } finally {
            $global:ErrorActionPreference = $previousErrorActionPreference
        }
        Test-Path -LiteralPath (Join-Path $env:LLVM_HOME 'default') | Should -BeTrue
    }
}
