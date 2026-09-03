Describe 'Windows LLVM source installation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:installScript = Join-Path $script:repoRoot 'Install-Llvm.ps1'
        . $script:installScript -Help | Out-Null
    }

    BeforeEach {
        $script:LLVM_HOME = Join-Path $TestDrive "llvm-home-$([guid]::NewGuid().ToString('N'))"
        $script:TOOLCHAINS_DIR = Join-Path $script:LLVM_HOME 'toolchains'
        $script:SOURCES_DIR = Join-Path $script:LLVM_HOME 'sources'
        New-Item -ItemType Directory -Path $script:TOOLCHAINS_DIR, $script:SOURCES_DIR -Force | Out-Null
    }

    It 'explains all missing source build tools' {
        Mock Get-LlvmCommandPath { $null }
        Mock Write-ErrorLog {}
        Mock Write-Host {}

        $result = Get-LlvmSourceBuildTools

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-ErrorLog -Times 1 -Exactly -ParameterFilter {
            $Message -match 'git, cmake, ninja'
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match 'git --version; cmake --version; ninja --version'
        }
    }

    It 'explains how to provide a bootstrap compiler on Windows' {
        Mock Get-LlvmCommandPath {
            if ($Name -in @('git', 'cmake', 'ninja')) { return "C:\tools\$Name.exe" }
            return $null
        }
        Mock Write-ErrorLog {}
        Mock Write-Host {}

        $result = Get-LlvmSourceBuildTools

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-ErrorLog -Times 1 -Exactly -ParameterFilter {
            $Message -match 'bootstrap toolchain'
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match 'Developer PowerShell for VS'
        }
    }

    It 'normalizes an exact source version without listing remote tags' {
        Mock Invoke-LlvmNativeCommand { throw 'remote lookup should not run' }

        Resolve-LlvmSourceVersion -Expression '22.1.8' -GitCommand 'git' |
            Should -Be 'llvmorg-22.1.8'
        Should -Invoke Invoke-LlvmNativeCommand -Times 0 -Exactly
    }

    It 'resolves latest from stable upstream tags' {
        Mock Invoke-LlvmNativeCommand {
            @(
                "a refs/tags/llvmorg-18.1.8",
                "b refs/tags/llvmorg-22.1.8",
                "c refs/tags/llvmorg-22.1.8^{}",
                "d refs/tags/llvmorg-23.0.0-rc1"
            )
        }

        Resolve-LlvmSourceVersion -Expression 'latest' -GitCommand 'git' |
            Should -Be 'llvmorg-22.1.8'
    }

    It 'creates the default link under the configured LLVM home' {
        $version = 'llvmorg-22.1.8'
        New-Item -ItemType Directory -Path (Join-Path $script:TOOLCHAINS_DIR $version) -Force | Out-Null

        Set-DefaultVersion $version | Should -BeTrue

        $defaultPath = Join-Path $script:LLVM_HOME 'default'
        Test-Path -LiteralPath $defaultPath | Should -BeTrue
        (Get-Item -LiteralPath $defaultPath).Target | Should -Be (Join-Path $script:TOOLCHAINS_DIR $version)
    }

    It 'configures, builds, installs, and validates an existing checkout' {
        $version = 'llvmorg-22.1.8'
        $sourceDir = Join-Path $script:SOURCES_DIR $version
        New-Item -ItemType Directory -Path (Join-Path $sourceDir '.git'), (Join-Path $sourceDir 'llvm') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $sourceDir 'llvm/CMakeLists.txt') -Force | Out-Null

        Mock Get-LlvmSourceBuildTools {
            @{ git = 'git'; cmake = 'cmake'; ninja = 'ninja'; compiler = 'cl.exe' }
        }
        Mock Resolve-LlvmSourceVersion { $version }
        Mock Invoke-LlvmNativeCommand {}
        Mock Test-LlvmBuiltToolchain { $true }
        Mock Move-Item {}

        $result = Install-FromSource -Version $version -CmakeFlags @() -Name '' `
            -SetDefault $false -Profile 'minimal' -Components @()

        $result | Should -BeTrue
        Should -Invoke Invoke-LlvmNativeCommand -Times 1 -Exactly -ParameterFilter {
            $Description -eq 'CMake configuration' -and $Arguments -contains '-G' -and
            $Arguments -contains 'Ninja' -and $Arguments -contains '-DLLVM_ENABLE_PROJECTS=clang;lld'
        }
        Should -Invoke Invoke-LlvmNativeCommand -Times 1 -Exactly -ParameterFilter {
            $Description -eq 'LLVM build' -and $Arguments -contains '--parallel'
        }
        Should -Invoke Invoke-LlvmNativeCommand -Times 1 -Exactly -ParameterFilter {
            $Description -eq 'LLVM installation' -and $Arguments -contains 'install'
        }
        Should -Invoke Test-LlvmBuiltToolchain -Times 1 -Exactly
        Should -Invoke Move-Item -Times 1 -Exactly
    }
}
