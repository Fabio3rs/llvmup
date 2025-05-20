# Import the script under test
$scriptPath = Join-Path $PSScriptRoot "../../Activate-LlvmVsCode.ps1"

# Define the test function in script scope
function Test-ActivateLlvmVsCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    . $scriptPath -Version $Version
}

# Define the path to the script under test inside BeforeAll
Describe "Activate-LlvmVsCode" {
    BeforeAll {
        # Locate the script under test
        $scriptPath = Join-Path $PSScriptRoot "../../Activate-LlvmVsCode.ps1"

        # Create test directories
        $testDir        = "TestDrive:\test"
        $vscodeDir      = Join-Path $testDir ".vscode"
        $toolchainsDir  = Join-Path $testDir ".llvm\toolchains"
        $testVersion    = "llvmorg-15.0.0"
        $versionDir     = Join-Path $toolchainsDir $testVersion

        # Create directory structure
        New-Item -ItemType Directory -Path $vscodeDir     -Force | Out-Null
        New-Item -ItemType Directory -Path $versionDir     -Force | Out-Null

        # Create mock LLVM binaries
        New-Item -ItemType File      -Path (Join-Path $versionDir "clangd.exe") -Force | Out-Null
        New-Item -ItemType File      -Path (Join-Path $versionDir "lldb.exe")   -Force | Out-Null

        # Mock environment variables
        $env:USERPROFILE = $testDir

        # Save original environment
        $script:originalPath = $env:PATH
        $script:originalCC   = $env:CC
        $script:originalCXX  = $env:CXX
        $script:originalLD   = $env:LD

        # Expose for use in Test-ActivateLlvmVsCode
        Set-Variable scriptPath  $scriptPath    -Scope Script
        Set-Variable testVersion $testVersion   -Scope Script
        Set-Variable versionDir  $versionDir    -Scope Script
        Set-Variable vscodeDir   $vscodeDir     -Scope Script
        Set-Variable testDir     $testDir       -Scope Script
    }

    AfterAll {
        # Restore original environment
        $env:PATH = $script:originalPath
        $env:CC   = $script:originalCC
        $env:CXX  = $script:originalCXX
        $env:LD   = $script:originalLD

        # Clean up test directory
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "When version is not installed" {
        It "Should throw an error for nonexistent version" {
            { Test-ActivateLlvmVsCode -Version "nonexistent-version" } |
                Should -Throw -ExpectedMessage "*not installed*"
        }
    }

    Context "When executed outside VSCode workspace" {
        It "Should throw an error when not in VSCode workspace" {
            $env:VSCODE_CWD = $null
            { Test-ActivateLlvmVsCode -Version $testVersion } |
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
            Test-ActivateLlvmVsCode -Version $testVersion
            Test-Path (Join-Path $vscodeDir "settings.json") | Should -BeTrue
        }

        It "Should set correct compiler paths in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir "settings.json") | ConvertFrom-Json

            $settings.'C_Cpp.default.compilerPath'      | Should -Be (Join-Path $versionDir "clangd.exe")
            $settings.'C_Cpp.default.intelliSenseMode'  | Should -Be "clang-x64"
        }

        It "Should set correct debugger configuration in settings.json" {
            Test-ActivateLlvmVsCode -Version $testVersion
            $settings = Get-Content (Join-Path $vscodeDir "settings.json") | ConvertFrom-Json

            $settings.'cmake.debuggerPath' | Should -Be (Join-Path $versionDir "lldb.exe")
        }

        It "Should set environment variables correctly" {
            Test-ActivateLlvmVsCode -Version $testVersion

            $env:PATH  | Should -Contain $versionDir
            $env:CC    | Should -Be (Join-Path $versionDir "clangd.exe")
            $env:CXX   | Should -Be (Join-Path $versionDir "clangd.exe")
        }

        It "Should prevent multiple activations" {
            Test-ActivateLlvmVsCode -Version $testVersion
            { Test-ActivateLlvmVsCode -Version "llvmorg-16.0.0" } |
                Should -Throw -ExpectedMessage "*already active*"
        }

        It "Should restore environment on deactivation" {
            # Store original values
            $originalPath = $env:PATH
            $originalCC   = $env:CC
            $originalCXX  = $env:CXX
            $originalLD   = $env:LD

            # Activate then deactivate
            Test-ActivateLlvmVsCode -Version $testVersion
            Deactivate-LlvmVsCode

            # Verify environment is restored
            $env:PATH | Should -Be $originalPath
            $env:CC   | Should -Be $originalCC
            $env:CXX  | Should -Be $originalCXX
            $env:LD   | Should -Be $originalLD
        }
    }
}
