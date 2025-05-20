# Path to the script under test (will be captured in BeforeAll)
# $scriptPath = Join-Path $PSScriptRoot '../../Activate-LlvmVsCode.ps1'

Describe "Activate-LlvmVsCode" {
    BeforeAll {
        #––– Locate your script under test
        $scriptPath = Join-Path $PSScriptRoot '../../Activate-LlvmVsCode.ps1'

        #––– Define the helper *inside* BeforeAll
        function Test-ActivateLlvmVsCode {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [string]$Version
            )
            . $scriptPath -Version $Version
        }

        #––– Test fixtures
        $Script:testDir       = 'TestDrive:\test'
        $Script:vscodeDir     = Join-Path $testDir '.vscode'
        $Script:toolchainsDir = Join-Path $testDir '.llvm\toolchains'
        $Script:testVersion   = 'llvmorg-15.0.0'
        $Script:versionDir    = Join-Path $toolchainsDir $testVersion

        #––– Create directories and fake binaries
        New-Item -ItemType Directory -Path $vscodeDir     -Force | Out-Null
        New-Item -ItemType Directory -Path $versionDir     -Force | Out-Null
        New-Item -ItemType File      -Path (Join-Path $versionDir 'clangd.exe') -Force | Out-Null
        New-Item -ItemType File      -Path (Join-Path $versionDir 'lldb.exe')   -Force | Out-Null

        #––– Mock HOME and save environment
        $env:USERPROFILE      = $testDir
        $script:originalPath  = $env:PATH
        $script:originalCC    = $env:CC
        $script:originalCXX   = $env:CXX
        $script:originalLD    = $env:LD
    }

    AfterAll {
        #––– Restore environment and clean up
        $env:PATH = $script:originalPath
        $env:CC   = $script:originalCC
        $env:CXX  = $script:originalCXX
        $env:LD   = $script:originalLD

        Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "When version is not installed" {
        It "Should throw an error for nonexistent version" {
            { Test-ActivateLlvmVsCode -Version 'nonexistent-version' } |
                Should -Throw -ExpectedMessage '*not installed*'
        }
    }

    Context "When executed outside VSCode workspace" {
        It "Should throw an error when not in VSCode workspace" {
            $env:VSCODE_CWD = $null
            { Test-ActivateLlvmVsCode -Version $testVersion } |
                Should -Throw -ExpectedMessage '*VSCode workspace*'
        }
    }

    Context "When executed in valid VSCode workspace with valid version" {
        BeforeEach {
            $env:VSCODE_CWD = $testDir
            $settingsJson = Join-Path $vscodeDir 'settings.json'
            if (Test-Path $settingsJson) { Remove-Item $settingsJson -Force }
        }

        It "Should create settings.json if it doesn't exist" {
            Test-ActivateLlvmVsCode -Version $testVersion
            Test-Path (Join-Path $vscodeDir 'settings.json') | Should -BeTrue
        }

        It "Should set correct compiler paths in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir 'settings.json') | ConvertFrom-Json

            $settings.'C_Cpp.default.compilerPath'     | Should -Be (Join-Path $versionDir 'clangd.exe')
            $settings.'C_Cpp.default.intelliSenseMode' | Should -Be 'clang-x64'
        }

        It "Should set correct debugger configuration in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir 'settings.json') | ConvertFrom-Json

            $settings.'cmake.debuggerPath' | Should -Be (Join-Path $versionDir 'lldb.exe')
        }

        It "Should set environment variables correctly" {
            Test-ActivateLlvmVsCode -Version $testVersion

            $env:PATH | Should -Contain $versionDir
            $env:CC   | Should -Be (Join-Path $versionDir 'clangd.exe')
            $env:CXX  | Should -Be (Join-Path $versionDir 'clangd.exe')
        }

        It "Should prevent multiple activations" {
            Test-ActivateLlvmVsCode -Version $testVersion
            { Test-ActivateLlvmVsCode -Version 'llvmorg-16.0.0' } |
                Should -Throw -ExpectedMessage '*already active*'
        }

        It "Should restore environment on deactivation" {
            $origPath = $env:PATH; $origCC = $env:CC; $origCXX = $env:CXX; $origLD = $env:LD
            Test-ActivateLlvmVsCode -Version $testVersion
            Deactivate-LlvmVsCode

            $env:PATH | Should -Be $origPath
            $env:CC   | Should -Be $origCC
            $env:CXX  | Should -Be $origCXX
            $env:LD   | Should -Be $origLD
        }
    }
}
