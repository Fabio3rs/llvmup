BeforeAll {
    Import-Module -Force (Join-Path $PSScriptRoot '../../Llvm-Functions-Core.psm1')

    $script:ToolchainsPath = Join-Path $TestDrive 'toolchains-range'
    New-Item -ItemType Directory -Path $script:ToolchainsPath -Force | Out-Null

    $versions = @(
        'llvmorg-18.0.0',
        'llvmorg-18.1.8',
        'llvmorg-19.0.0',
        'llvmorg-19.1.0',
        'llvmorg-19.1.5',
        'source-llvmorg-19.1.0',
        'llvmorg-20.0.0'
    )

    foreach ($v in $versions) {
        New-Item -ItemType Directory -Path (Join-Path $script:ToolchainsPath $v) -Force | Out-Null
    }
}

AfterAll {
    if (Test-Path $script:ToolchainsPath) {
        Remove-Item -Path $script:ToolchainsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Range expression matching' {
    It 'supports >= ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '>=18.0.0' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Contain 'llvmorg-20.0.0'
        $matches | Should -Contain 'llvmorg-18.0.0'
    }

    It 'supports <= ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '<=19.1.0' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Not -Contain 'llvmorg-20.0.0'
        $matches | Should -Contain 'llvmorg-18.0.0'
        $matches | Should -Contain 'llvmorg-19.1.0'
    }

    It 'supports > and < ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '>18.1.8' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Contain 'llvmorg-19.0.0'
        $matches | Should -Not -Contain 'llvmorg-18.1.8'

        $matchesLt = Invoke-LlvmMatchVersions -Expression '<19.0.0' -ToolchainsPath $script:ToolchainsPath
        $matchesLt | Should -Contain 'llvmorg-18.1.8'
        $matchesLt | Should -Not -Contain 'llvmorg-19.0.0'
    }

    It 'supports = ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '=19.1.0' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -BeExactly @('llvmorg-19.1.0')
    }

    It 'supports tilde ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '~19.1' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Contain 'llvmorg-19.1.0'
        $matches | Should -Contain 'llvmorg-19.1.5'
        $matches | Should -Not -Contain 'llvmorg-20.0.0'
    }

    It 'supports wildcard ranges' {
        $matches = Invoke-LlvmMatchVersions -Expression '18.*' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Contain 'llvmorg-18.0.0'
        $matches | Should -Contain 'llvmorg-18.1.8'

        $matchesMinor = Invoke-LlvmMatchVersions -Expression '19.1.*' -ToolchainsPath $script:ToolchainsPath
        $matchesMinor | Should -Contain 'llvmorg-19.1.0'
        $matchesMinor | Should -Contain 'llvmorg-19.1.5'
        $matchesMinor | Should -Not -Contain 'llvmorg-19.0.0'
    }

    It 'works with prebuilt/source filters' {
        $matches = Invoke-LlvmMatchVersions -Expression 'latest-prebuilt' -ToolchainsPath $script:ToolchainsPath
        $matches | Should -Be 'llvmorg-20.0.0'

        $matchesSource = Invoke-LlvmMatchVersions -Expression 'latest-source' -ToolchainsPath $script:ToolchainsPath
        $matchesSource | Should -Be 'source-llvmorg-19.1.0'
    }
}
