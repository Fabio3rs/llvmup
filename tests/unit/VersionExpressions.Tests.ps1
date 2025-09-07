Describe 'Version expression parsing and matching' {
    BeforeAll {
        Import-Module -Force (Join-Path $PSScriptRoot '../../Llvm-Functions-Core.psm1')
        # Setup fake toolchains dir
        $Script:testDir = Join-Path $PSScriptRoot 'ps-test'
        New-Item -ItemType Directory -Path $Script:testDir -Force | Out-Null
        $env:USERPROFILE = $Script:testDir
        $global:toolchains = Join-Path $env:USERPROFILE '.llvm\toolchains'
        New-Item -ItemType Directory -Path $global:toolchains -Force | Out-Null
        # Create some fake versions
        New-Item -ItemType Directory -Path (Join-Path $global:toolchains 'llvmorg-18.1.0') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $global:toolchains 'llvmorg-18.1.8') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $global:toolchains 'llvmorg-19.1.7') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $global:toolchains 'source-llvmorg-20.1.0') -Force | Out-Null
    }

    AfterAll {
        Remove-Item -Path $Script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'parses specific source version match' {
        $result = ConvertFrom-LlvmVersion 'source-llvmorg-20.1.0'
        $result.Version | Should -Be '20.1.0'
        $result.Display | Should -Be '20.1.0'
    }

    It 'parses plain and prefixed versions' {
        $result1 = ConvertFrom-LlvmVersion 'llvmorg-18.1.8'
        $result1.Version | Should -Be '18.1.8'

        $result2 = ConvertFrom-LlvmVersion 'source-llvmorg-20.1.0'
        $result2.Version | Should -Be '20.1.0'

        $result3 = ConvertFrom-LlvmVersion '19.1.7'
        $result3.Version | Should -Be '19.1.7'
    }

    It 'compares versions correctly' {
        (Compare-LlvmVersion '18.1.8' '19.1.7') | Should -BeLessThan 0
        (Compare-LlvmVersion '19.1.7' '19.1.7') | Should -Be 0
        (Compare-LlvmVersion '20.1.0' '19.1.7') | Should -BeGreaterThan 0
    }

    It 'parses expressions' {
        $p = Invoke-LlvmParseVersionExpression 'latest'
        $p.selector | Should -Be 'latest'

        $p2 = Invoke-LlvmParseVersionExpression '~19.1'
        $p2.kind | Should -Be 'range'
        $p2.range.op | Should -Be '~'
    }

    It 'tilde range matches correctly' {
        $result = Invoke-LlvmVersionMatchesRange 'llvmorg-19.1.7' '~19.1'
        $result | Should -BeTrue
    }

    It 'matches range expressions' {
        $matches = Invoke-LlvmMatchVersions '~19.1'
        $matches | Should -Contain 'llvmorg-19.1.7'
        $matches | Should -Not -Contain 'llvmorg-18.1.8'
    }

    It 'matches selectors' {
        $latest = Invoke-LlvmMatchVersions 'latest'
        $latest | Should -Contain 'source-llvmorg-20.1.0'
    }
}
