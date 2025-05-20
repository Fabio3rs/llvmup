# Import the script under test
. $PSScriptRoot/../../Activate-LlvmVsCode.ps1

Describe "Activate-LlvmVsCode" {
    BeforeAll {
        # Create test directories
        $testDir = "TestDrive:\test"
        $vscodeDir = Join-Path $testDir ".vscode"
        $toolchainsDir = Join-Path $testDir ".llvm\toolchains"
        $testVersion = "llvmorg-15.0.0"
        $versionDir = Join-Path $toolchainsDir $testVersion

        # Create directory structure
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null

        # Create mock LLVM binaries
        New-Item -ItemType File -Path (Join-Path $versionDir "clangd.exe") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $versionDir "lldb.exe") -Force | Out-Null

        # Mock environment variable
        $env:USERPROFILE = $testDir

        # Save original environment
        $script:originalPath = $env:PATH
        $script:originalCC = $env:CC
        $script:originalCXX = $env:CXX
        $script:originalLD = $env:LD
    }

    AfterAll {
        # Restore original environment
        $env:PATH = $script:originalPath
        $env:CC = $script:originalCC
        $env:CXX = $script:originalCXX
        $env:LD = $script:originalLD

        # Clean up test directory
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "When version is not installed" {
        It "Should throw an error for nonexistent version" {
            { Activate-LlvmVsCode -Version "nonexistent-version" } | 
                Should -Throw -ExpectedMessage "*not installed*"
        }
    }

    Context "When executed outside VSCode workspace" {
        It "Should throw an error when not in VSCode workspace" {
            $env:VSCODE_CWD = $null
            { Activate-LlvmVsCode -Version $testVersion } | 
                Should -Throw -ExpectedMessage "*VSCode workspace*"
        }
    }

    Context "When executed in valid VSCode workspace with valid version" {
        BeforeEach {
            # Set up VSCode workspace
            $env:VSCODE_CWD = $testDir
            $settingsPath = Join-Path $vscodeDir "settings.json"
            if (Test-Path $settingsPath) {
                Remove-Item $settingsPath -Force
            }
        }

        It "Should create settings.json if it doesn't exist" {
            Activate-LlvmVsCode -Version $testVersion
            Test-Path (Join-Path $vscodeDir "settings.json") | Should -BeTrue
        }

        It "Should set correct compiler paths in settings.json" {
            Activate-LlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir "settings.json") | ConvertFrom-Json
            
            $settings.'C_Cpp.default.compilerPath' | Should -Be (Join-Path $versionDir "clangd.exe")
            $settings.'C_Cpp.default.intelliSenseMode' | Should -Be "clang-x64"
        }

        It "Should set correct debugger configuration in settings.json" {
            Activate-LlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir "settings.json") | ConvertFrom-Json
            
            $debuggerPath = $settings.'cmake.debuggerPath'
            $debuggerPath | Should -Be (Join-Path $versionDir "lldb.exe")
        }

        It "Should set environment variables correctly" {
            Activate-LlvmVsCode -Version $testVersion
            
            $env:PATH | Should -Contain $versionDir
            $env:CC | Should -Be (Join-Path $versionDir "clangd.exe")
            $env:CXX | Should -Be (Join-Path $versionDir "clangd.exe")
        }

        It "Should prevent multiple activations" {
            Activate-LlvmVsCode -Version $testVersion
            { Activate-LlvmVsCode -Version "llvmorg-16.0.0" } | 
                Should -Throw -ExpectedMessage "*already active*"
        }

        It "Should restore environment on deactivation" {
            # Store original values
            $originalPath = $env:PATH
            $originalCC = $env:CC
            $originalCXX = $env:CXX
            $originalLD = $env:LD

            # Activate
            Activate-LlvmVsCode -Version $testVersion

            # Deactivate
            Deactivate-LlvmVsCode

            # Verify environment is restored
            $env:PATH | Should -Be $originalPath
            $env:CC | Should -Be $originalCC
            $env:CXX | Should -Be $originalCXX
            $env:LD | Should -Be $originalLD
        }
    }
} 