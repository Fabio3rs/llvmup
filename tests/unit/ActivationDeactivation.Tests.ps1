Describe "Environment Activation and Deactivation" {
    BeforeAll {
        # Import the module
        $ModulePath = Join-Path $PSScriptRoot "..\..\Llvm-Functions-Core.psm1"
        Import-Module $ModulePath -Force

        # Helper function to create mock LLVM installation
        function New-MockLlvmInstallation {
            param(
                [string]$ToolchainsPath,
                [string]$Version
            )

            $versionPath = Join-Path $ToolchainsPath $Version
            $binPath = Join-Path $versionPath "bin"
            $libPath = Join-Path $versionPath "lib"
            $includePath = Join-Path $versionPath "include"

            New-Item -ItemType Directory -Path $binPath -Force | Out-Null
            New-Item -ItemType Directory -Path $libPath -Force | Out-Null
            New-Item -ItemType Directory -Path $includePath -Force | Out-Null

            # Create mock executables (empty files)
            @(
                "clang.exe", "clang++.exe", "llvm-config.exe",
                "llvm-ar.exe", "llvm-ranlib.exe"
            ) | ForEach-Object {
                New-Item -ItemType File -Path (Join-Path $binPath $_) -Force | Out-Null
            }

            # Create mock library
            New-Item -ItemType File -Path (Join-Path $libPath "libclang.dll") -Force | Out-Null

            return $versionPath
        }
    }

    BeforeEach {
        # Create isolated test environment
        $TestToolchainsPath = Join-Path $TestDrive "toolchains"
        New-Item -ItemType Directory -Path $TestToolchainsPath -Force | Out-Null

        # Clear any existing LLVM environment variables
        Get-ChildItem Env: | Where-Object { $_.Name -match '^(LLVM_|CC|CXX|AR|RANLIB|_ACTIVE_LLVM|_LLVM_BACKUP)' } | ForEach-Object {
            Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
        }

        # Store original PATH for restoration
        $script:OriginalPath = $env:PATH
    }

    AfterEach {
        # Restore original environment
        $env:PATH = $script:OriginalPath

        # Clear test environment variables
        Get-ChildItem Env: | Where-Object { $_.Name -match '^(LLVM_|CC|CXX|AR|RANLIB|_ACTIVE_LLVM|_LLVM_BACKUP)' } | ForEach-Object {
            Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
        }
    }

    Context "Environment Backup and Restore" {
        It "Should create environment backup" {
            # Arrange - set some environment variables
            $env:CC = "test-cc"
            $env:LLVM_CONFIG_PATH = "test-llvm-config"

            # Act
            $backup = Backup-LlvmEnvironment

            # Assert
            $backup | Should -Not -BeNullOrEmpty
            $backup.CC | Should -Be "test-cc"
            $backup.LLVM_CONFIG_PATH | Should -Be "test-llvm-config"
            $backup.PATH | Should -Be $env:PATH
            $backup.Timestamp | Should -Not -BeNullOrEmpty

            # Environment backup should be stored
            $env:_LLVM_BACKUP | Should -Not -BeNullOrEmpty
        }

        It "Should restore environment from backup" {
            # Arrange - create backup
            $env:CC = "original-cc"
            $env:LLVM_CONFIG_PATH = "original-config"
            $originalPath = $env:PATH

            $backup = Backup-LlvmEnvironment

            # Modify environment
            $env:CC = "modified-cc"
            $env:LLVM_CONFIG_PATH = "modified-config"
            $env:PATH = "modified-path"
            $env:_ACTIVE_LLVM = "test-version"

            # Act
            $result = Restore-LlvmEnvironment -Backup $backup

            # Assert
            $result | Should -Be $true
            $env:CC | Should -Be "original-cc"
            $env:LLVM_CONFIG_PATH | Should -Be "original-config"
            $env:PATH | Should -Be $originalPath
            $env:_ACTIVE_LLVM | Should -BeNullOrEmpty
            $env:_LLVM_BACKUP | Should -BeNullOrEmpty
        }

        It "Should restore from environment variable when no backup provided" {
            # Arrange - create backup in environment
            $env:CC = "env-original"
            $originalPath = $env:PATH
            $backup = Backup-LlvmEnvironment

            # Modify environment
            $env:CC = "env-modified"
            $env:PATH = "env-modified-path"

            # Act - restore without explicit backup parameter
            $result = Restore-LlvmEnvironment

            # Assert
            $result | Should -Be $true
            $env:CC | Should -Be "env-original"
            $env:PATH | Should -Be $originalPath
        }

        It "Should handle missing backup gracefully" {
            # Arrange - no backup exists
            Remove-Item Env:_LLVM_BACKUP -ErrorAction SilentlyContinue

            # Act
            $result = Restore-LlvmEnvironment

            # Assert
            $result | Should -Be $false
        }

        It "Should backup and restore LLVM_SYS variables dynamically" {
            # Arrange - set some pre-existing LLVM_SYS variables
            $env:LLVM_SYS_180_PREFIX = "/pre-existing/path1"
            $env:LLVM_SYS_220_PREFIX = "/pre-existing/path2"
            $env:LLVM_SYS_999_PREFIX = "/pre-existing/path3"  # Future version

            # Act - create backup
            $backup = Backup-LlvmEnvironment

            # Modify environment to simulate activation
            $env:LLVM_SYS_180_PREFIX = "/modified/path1"
            Remove-Item Env:LLVM_SYS_220_PREFIX -ErrorAction SilentlyContinue
            $env:LLVM_SYS_210_PREFIX = "/new/path"

            # Restore from backup
            $result = Restore-LlvmEnvironment -Backup $backup

            # Assert
            $result | Should -Be $true
            $env:LLVM_SYS_180_PREFIX | Should -Be "/pre-existing/path1"
            $env:LLVM_SYS_220_PREFIX | Should -Be "/pre-existing/path2"
            $env:LLVM_SYS_999_PREFIX | Should -Be "/pre-existing/path3"
            $env:LLVM_SYS_210_PREFIX | Should -BeNullOrEmpty  # Should be cleared
        }
    }

    Context "LLVM Activation" {
        It "Should activate LLVM version successfully" {
            # Arrange
            $testVersion = "18.1.8"
            $mockPath = New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $testVersion

            # Act
            $result = Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath

            # Assert
            $result | Should -Be $true
            $env:_ACTIVE_LLVM | Should -Be $testVersion
            $env:PATH | Should -Match ([regex]::Escape((Join-Path $mockPath "bin")))
            $env:LLVM_CONFIG_PATH | Should -Be (Join-Path $mockPath "bin\llvm-config.exe")
            $env:LIBCLANG_PATH | Should -Be (Join-Path $mockPath "lib\libclang.dll")
            $env:CC | Should -Be (Join-Path $mockPath "bin\clang.exe")
            $env:CXX | Should -Be (Join-Path $mockPath "bin\clang++.exe")
            $env:AR | Should -Be (Join-Path $mockPath "bin\llvm-ar.exe")
            $env:RANLIB | Should -Be (Join-Path $mockPath "bin\llvm-ranlib.exe")
            $env:LLVM_SYS_180_PREFIX | Should -Be $mockPath
            $env:_LLVM_BACKUP | Should -Not -BeNullOrEmpty
        }

        It "Should fail when version doesn't exist" {
            # Arrange - no mock installation
            $nonExistentVersion = "99.99.99"

            # Act & Assert
            { Invoke-LlvmActivate -Version $nonExistentVersion -ToolchainsPath $TestToolchainsPath } | Should -Throw
        }

        It "Should not reactivate same version without force" {
            # Arrange
            $testVersion = "19.1.0"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $testVersion

            # First activation
            $result1 = Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath
            $originalPath = $env:PATH

            # Act - try to activate same version again
            $result2 = Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath

            # Assert
            $result1 | Should -Be $true
            $result2 | Should -Be $true
            $env:PATH | Should -Be $originalPath  # PATH shouldn't change
        }

        It "Should force reactivation when Force flag is used" {
            # Arrange
            $testVersion = "20.1.0"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $testVersion

            # First activation
            Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath

            # Modify PATH to test force reactivation
            $env:PATH = "modified-path"

            # Act - force reactivation
            $result = Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath -Force

            # Assert
            $result | Should -Be $true
            $env:PATH | Should -Match ([regex]::Escape((Join-Path $TestToolchainsPath $testVersion "bin")))
        }

        It "Should set version-specific environment variables correctly for various versions" {
            # Test various LLVM versions to ensure the dynamic pattern works
            $testCases = @(
                @{ Version = "18.1.8"; Expected = "LLVM_SYS_180_PREFIX" },
                @{ Version = "19.1.0"; Expected = "LLVM_SYS_190_PREFIX" },
                @{ Version = "20.0.1"; Expected = "LLVM_SYS_200_PREFIX" },
                @{ Version = "21.1.0"; Expected = "LLVM_SYS_210_PREFIX" },
                @{ Version = "22.0.0"; Expected = "LLVM_SYS_220_PREFIX" },
                @{ Version = "25.1.5"; Expected = "LLVM_SYS_250_PREFIX" }
            )

            foreach ($testCase in $testCases) {
                # Clear previous test state
                Get-ChildItem Env: | Where-Object { $_.Name -match '^LLVM_SYS_\d+_PREFIX$' } | ForEach-Object {
                    Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
                }
                Remove-Item "Env:_ACTIVE_LLVM" -ErrorAction SilentlyContinue
                Remove-Item "Env:_LLVM_BACKUP" -ErrorAction SilentlyContinue

                # Arrange
                $version = $testCase.Version
                $expectedEnvVar = $testCase.Expected
                $mockPath = New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version

                # Act
                $result = Invoke-LlvmActivate -Version $version -ToolchainsPath $TestToolchainsPath

                # Assert
                $result | Should -Be $true
                (Get-Item "Env:$expectedEnvVar" -ErrorAction SilentlyContinue).Value | Should -Be $mockPath
                Write-Host "✓ $version → $expectedEnvVar = $mockPath"
            }
        }

        It "Should clean up old LLVM_SYS variables when switching versions" {
            # Arrange - create two different versions
            $version1 = "18.1.8"
            $version2 = "21.1.0"
            $mockPath1 = New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version1
            $mockPath2 = New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version2

            # Activate first version
            $result1 = Invoke-LlvmActivate -Version $version1 -ToolchainsPath $TestToolchainsPath
            $result1 | Should -Be $true
            $env:LLVM_SYS_180_PREFIX | Should -Be $mockPath1

            # Act - activate second version (should clean up first)
            $result2 = Invoke-LlvmActivate -Version $version2 -ToolchainsPath $TestToolchainsPath -Force

            # Assert
            $result2 | Should -Be $true
            $env:LLVM_SYS_210_PREFIX | Should -Be $mockPath2
            # Old variable should be cleared
            $env:LLVM_SYS_180_PREFIX | Should -BeNullOrEmpty
        }
    }

    Context "LLVM Deactivation" {
        It "Should deactivate LLVM version successfully" {
            # Arrange - activate a version first
            $testVersion = "18.1.8"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $testVersion
            Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath

            $originalPath = $script:OriginalPath

            # Act
            $result = Invoke-LlvmDeactivate

            # Assert
            $result | Should -Be $true
            $env:_ACTIVE_LLVM | Should -BeNullOrEmpty
            $env:_LLVM_BACKUP | Should -BeNullOrEmpty
            $env:PATH | Should -Be $originalPath
        }

        It "Should handle deactivation when nothing is active" {
            # Arrange - ensure nothing is active
            Remove-Item Env:_ACTIVE_LLVM -ErrorAction SilentlyContinue

            # Act
            $result = Invoke-LlvmDeactivate

            # Assert
            $result | Should -Be $true
        }

        It "Should restore all environment variables during deactivation" {
            # Arrange - set original environment and activate LLVM
            $env:CC = "original-cc"
            $env:CXX = "original-cxx"
            $env:LLVM_CONFIG_PATH = "original-config"

            $testVersion = "19.1.0"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $testVersion
            Invoke-LlvmActivate -Version $testVersion -ToolchainsPath $TestToolchainsPath

            # Verify activation changed the environment
            $env:CC | Should -Not -Be "original-cc"
            $env:_ACTIVE_LLVM | Should -Be $testVersion

            # Act
            $result = Invoke-LlvmDeactivate

            # Assert
            $result | Should -Be $true
            $env:CC | Should -Be "original-cc"
            $env:CXX | Should -Be "original-cxx"
            $env:LLVM_CONFIG_PATH | Should -Be "original-config"
            $env:_ACTIVE_LLVM | Should -BeNullOrEmpty
        }
    }

    Context "Integration with Auto-Activation" {
        It "Should integrate with auto-activation workflow" {
            # Arrange - create versions and config
            $version1 = "18.1.8"
            $version2 = "19.1.0"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version1
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version2

            # Activate first version
            Invoke-LlvmActivate -Version $version1 -ToolchainsPath $TestToolchainsPath

            # Act - test auto-activation decision (should recommend staying with current)
            $decision = Invoke-LlvmAutoActivateEnhanced -ConfigExpression $version1 -ToolchainsPath $TestToolchainsPath

            # Assert
            $decision.Action | Should -Be "NoChange"
            $decision.ActiveVersion | Should -Be $version1
            $env:_ACTIVE_LLVM | Should -Be $version1
        }

        It "Should recommend activation when current version doesn't satisfy expression" {
            # Arrange
            $version1 = "18.1.8"
            $version2 = "19.1.0"
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version1
            New-MockLlvmInstallation -ToolchainsPath $TestToolchainsPath -Version $version2

            # Activate version1 but require version2
            Invoke-LlvmActivate -Version $version1 -ToolchainsPath $TestToolchainsPath

            # Act
            $decision = Invoke-LlvmAutoActivateEnhanced -ConfigExpression $version2 -ToolchainsPath $TestToolchainsPath

            # Assert
            $decision.Action | Should -Be "ShouldDeactivateAndReactivate"
            $decision.ActiveVersion | Should -Be $version1
            $decision.Expression | Should -Be $version2
        }
    }
}
