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
        $Script:binDir        = Join-Path $versionDir 'bin'

        #––– Create directories and fake binaries
        New-Item -ItemType Directory -Path $vscodeDir     -Force | Out-Null
        New-Item -ItemType Directory -Path $versionDir     -Force | Out-Null
        New-Item -ItemType Directory -Path $binDir         -Force | Out-Null
        New-Item -ItemType File      -Path (Join-Path $binDir 'clangd.exe') -Force | Out-Null
        New-Item -ItemType File      -Path (Join-Path $binDir 'lldb.exe')   -Force | Out-Null

        #––– Mock HOME and save environment
        $env:USERPROFILE      = $testDir
        $script:originalPath  = $env:PATH
        $script:originalCC    = $env:CC
        $script:originalCXX   = $env:CXX
        $script:originalLD    = $env:LD
        $script:originalPWD   = $PWD

        #––– Change to test directory to simulate VSCode workspace
        Set-Location $testDir
    }

    AfterAll {
        #––– Restore environment and clean up
        $env:PATH = $script:originalPath
        $env:CC   = $script:originalCC
        $env:CXX  = $script:originalCXX
        $env:LD   = $script:originalLD
        $env:LLVM_ACTIVE_VERSION = $null
        Set-Location $script:originalPWD

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
            Set-Location $env:USERPROFILE
            Remove-Item -Path $vscodeDir -Recurse -Force -ErrorAction SilentlyContinue
            { Test-ActivateLlvmVsCode -Version $testVersion } |
                Should -Throw -ExpectedMessage '*VSCode workspace*'
            Set-Location $testDir
            New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
        }
    }

    Context "When executed in valid VSCode workspace with valid version" {
        BeforeEach {
            Set-Location $testDir
            $env:VSCODE_CWD = $testDir
            $settingsJson = Join-Path $vscodeDir 'settings.json'
            if (Test-Path $settingsJson) { Remove-Item $settingsJson -Force }
            # Reset environment variables
            $env:PATH = $script:originalPath
            $env:CC   = $script:originalCC
            $env:CXX  = $script:originalCXX
            $env:LD   = $script:originalLD
            $env:LLVM_ACTIVE_VERSION = $null
        }

        It "Should create settings.json if it doesn't exist" {
            Test-ActivateLlvmVsCode -Version $testVersion
            Test-Path (Join-Path $vscodeDir 'settings.json') | Should -BeTrue
        }

        It "Should set correct compiler paths in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir 'settings.json') | ConvertFrom-Json

            $settings.'clangd.path' | Should -Be (Join-Path $binDir 'clangd.exe')
        }

        It "Should set correct debugger configuration in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir 'settings.json') | ConvertFrom-Json

            $settings.'cmake.debuggerPath' | Should -Be (Join-Path $binDir 'lldb.exe')
        }

        It "Should set environment variables correctly" {
            Test-ActivateLlvmVsCode -Version $testVersion

            $env:PATH | Should -Contain $binDir
            $env:CC   | Should -Be (Join-Path $binDir 'clangd.exe')
            $env:CXX  | Should -Be (Join-Path $binDir 'clangd.exe')
            $env:LLVM_ACTIVE_VERSION | Should -Be $testVersion
        }

        It "Should prevent multiple activations" {
            Test-ActivateLlvmVsCode -Version $testVersion
            # Create a second version to test multiple activations
            $secondVersion = 'llvmorg-16.0.0'
            $secondDir = Join-Path $toolchainsDir $secondVersion
            $secondBinDir = Join-Path $secondDir 'bin'
            New-Item -ItemType Directory -Path $secondBinDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $secondBinDir 'clangd.exe') -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $secondBinDir 'lldb.exe') -Force | Out-Null

            { Test-ActivateLlvmVsCode -Version $secondVersion } |
                Should -Throw -ExpectedMessage "*already active*"
        }

        It "Should restore environment on deactivation" {
            $origPath = $env:PATH; $origCC = $env:CC; $origCXX = $env:CXX; $origLD = $env:LD
            Test-ActivateLlvmVsCode -Version $testVersion

            # Define deactivation function
            function Deactivate-LlvmVsCode {
                $env:PATH = $script:originalPath
                $env:CC   = $script:originalCC
                $env:CXX  = $script:originalCXX
                $env:LD   = $script:originalLD
                $env:LLVM_ACTIVE_VERSION = $null
            }

            Deactivate-LlvmVsCode

            $env:PATH | Should -Be $origPath
            $env:CC   | Should -Be $origCC
            $env:CXX  | Should -Be $origCXX
            $env:LD   | Should -Be $origLD
            $env:LLVM_ACTIVE_VERSION | Should -BeNullOrEmpty
        }
    }
}
