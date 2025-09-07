BeforeAll {
    # Mock USERPROFILE for tests
    $env:USERPROFILE = $TestDrive

    # Create mock toolchain directories
    $toolchainsDir = "$env:USERPROFILE\.llvm\toolchains"
    New-Item -Type Directory -Path $toolchainsDir -Force | Out-Null

    # Create diverse mock toolchains
    $versions = @(
        'llvmorg-19.1.5',
        'llvmorg-19.1.2',
        'llvmorg-18.1.8',
        'llvmorg-18.1.2',
        'llvmorg-17.0.6',
        'source-llvmorg-19.1.5',
        'source-llvmorg-18.1.8',
        'source-release-branch-18.1',
        'llvmorg-19.1.0-rc1',
        'llvmorg-19.1.0-rc2'
    )

    foreach ($version in $versions) {
        New-Item -Type Directory -Path "$toolchainsDir\$version" -Force | Out-Null
    }

    Import-Module -Force "/mnt/projects/Projects/llvm-manager/Llvm-Functions-Core.psm1"
}

Describe 'Enhanced Expression Engine' {
    Context 'Combined Selectors' {
        It 'latest-prebuilt should find latest prebuilt version' {
            $result = Invoke-LlvmMatchVersions -Expression 'latest-prebuilt'
            $result | Should -Be 'llvmorg-19.1.5'
        }

        It 'latest-source should find latest source version' {
            $result = Invoke-LlvmMatchVersions -Expression 'latest-source'
            $result | Should -Be 'source-llvmorg-19.1.5'
        }

        It 'oldest-prebuilt should find oldest prebuilt version' {
            $result = Invoke-LlvmMatchVersions -Expression 'oldest-prebuilt'
            $result | Should -Be 'llvmorg-17.0.6'
        }
    }

    Context 'Wildcard Patterns' {
        It '19.1.* should match all 19.1.x versions' {
            $result = Invoke-LlvmMatchVersions -Expression '19.1.*'
            $result | Should -Contain 'llvmorg-19.1.5'
            $result | Should -Contain 'llvmorg-19.1.2'
            $result | Should -Contain 'source-llvmorg-19.1.5'
            $result | Should -Not -Contain 'llvmorg-18.1.8'
        }

        It '18.* should match all 18.x versions' {
            $result = Invoke-LlvmMatchVersions -Expression '18.*'
            $result | Should -Contain 'llvmorg-18.1.8'
            $result | Should -Contain 'llvmorg-18.1.2'
            $result | Should -Contain 'source-llvmorg-18.1.8'
            $result | Should -Not -Contain 'llvmorg-19.1.5'
        }
    }

    Context 'Version Normalization' {
        It 'should normalize partial versions correctly' {
            $result = Normalize-LlvmSemver '19.1'
            $result | Should -Be '19.1.0'
        }

        It 'should handle full versions' {
            $result = Normalize-LlvmSemver '19.1.5'
            $result | Should -Be '19.1.5'
        }

        It 'should handle four-part versions' {
            $result = Normalize-LlvmSemver '19.1.5.1'
            $result | Should -Be '19.1.5'
        }
    }

    Context 'Enhanced Version Parsing' {
        It 'should return structured data for simple version' {
            $result = ConvertFrom-LlvmVersion 'llvmorg-19.1.5'
            $result.Version | Should -Be '19.1.5'
            $result.Suffix | Should -Be ''
            $result.Full | Should -Be 'llvmorg-19.1.5'
            $result.Display | Should -Be '19.1.5'
        }

        It 'should handle RC versions with suffixes' {
            $result = ConvertFrom-LlvmVersion 'llvmorg-19.1.0-rc2'
            $result.Version | Should -Be '19.1.0'
            $result.Suffix | Should -Be 'rc2'
            $result.Full | Should -Be 'llvmorg-19.1.0-rc2'
            $result.Display | Should -Be '19.1.0-rc2'
        }
    }

    Context 'Suffix Comparison' {
        It 'should compare RC versions correctly' {
            $result = Compare-LlvmVersion 'llvmorg-19.1.0-rc1' 'llvmorg-19.1.0-rc2'
            $result | Should -BeLessThan 0
        }

        It 'should compare RC vs final correctly' {
            $result = Compare-LlvmVersion 'llvmorg-19.1.0-rc2' 'llvmorg-19.1.0'
            $result | Should -BeLessThan 0
        }

        It 'should handle same base version with different suffixes' {
            $result = Compare-LlvmVersion 'llvmorg-19.1.0-rc1' 'llvmorg-19.1.0-rc1'
            $result | Should -Be 0
        }
    }
}

AfterAll {
    Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
}
