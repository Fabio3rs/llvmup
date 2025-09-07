BeforeAll {
    Import-Module -Force (Join-Path $PSScriptRoot '../../Llvm-Functions-Core.psm1')
}

Describe 'Advanced PowerShell Engine - Feature Demonstration' {
    Context 'Enhanced Version Parsing with Structured Data' {
        It 'should parse version with suffix and return complete object' {
            $result = ConvertFrom-LlvmVersion 'llvmorg-19.1.0-rc2'

            $result.Version | Should -Be '19.1.0'
            $result.Suffix | Should -Be 'rc2'
            $result.Full | Should -Be 'llvmorg-19.1.0-rc2'
            $result.Display | Should -Be '19.1.0-rc2'
        }
    }

    Context 'Advanced Version Normalization Engine' {
        It 'should normalize partial versions for System.Version compatibility' {
            Normalize-LlvmSemver '19.1' | Should -Be '19.1.0'
            Normalize-LlvmSemver '18.1.8' | Should -Be '18.1.8'
            Normalize-LlvmSemver '20.0.1.2' | Should -Be '20.0.1'
        }
    }

    Context 'Suffix-Aware Version Comparison' {
        It 'should handle RC version comparison correctly' {
            Compare-LlvmVersion 'llvmorg-19.1.0-rc1' 'llvmorg-19.1.0-rc2' | Should -BeLessThan 0
            Compare-LlvmVersion 'llvmorg-19.1.0-rc2' 'llvmorg-19.1.0' | Should -BeLessThan 0
            Compare-LlvmVersion 'llvmorg-19.1.0' 'llvmorg-19.1.1' | Should -BeLessThan 0
        }
    }

    Context 'Combined Selector Expressions (Bash Parity)' {
        It 'should parse combined selector expressions correctly' {
            $result = Invoke-LlvmParseVersionExpression 'latest-prebuilt'
            $result.kind | Should -Be 'combined'
            $result.selector | Should -Be 'latest'
            $result.type | Should -Be 'prebuilt'

            $result2 = Invoke-LlvmParseVersionExpression 'oldest-source'
            $result2.kind | Should -Be 'combined'
            $result2.selector | Should -Be 'oldest'
            $result2.type | Should -Be 'source'
        }
    }

    Context 'Enhanced Wildcard Pattern Matching' {
        It 'should parse version-specific wildcard patterns' {
            $result1 = Invoke-LlvmParseVersionExpression '19.1.*'
            $result1.kind | Should -Be 'wildcard'
            $result1.major | Should -Be '19'
            $result1.minor | Should -Be '1'

            $result2 = Invoke-LlvmParseVersionExpression '18.*'
            $result2.kind | Should -Be 'wildcard'
            $result2.major | Should -Be '18'
            $result2.minor | Should -BeNullOrEmpty
        }
    }

    Context 'Case-Insensitive Expression Processing' {
        It 'should handle mixed case expressions correctly' {
            $result1 = Invoke-LlvmParseVersionExpression 'LATEST-PREBUILT'
            $result1.kind | Should -Be 'combined'
            $result1.selector | Should -Be 'latest'

            $result2 = Invoke-LlvmParseVersionExpression 'Source'
            $result2.kind | Should -Be 'type'
            $result2.type | Should -Be 'source'
        }
    }

    Context 'Advanced Tilde Range Processing' {
        It 'should use normalized System.Version for range calculations' {
            $result = Invoke-LlvmParseVersionExpression '~19.1'
            $result.kind | Should -Be 'range'
            $result.range.op | Should -Be '~'
            $result.range.version | Should -Be '19.1'
        }
    }
}

AfterAll {
    Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
}
