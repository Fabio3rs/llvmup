BeforeAll {
    Import-Module "/mnt/projects/Projects/llvm-manager/Llvm-Functions-Core.psm1" -Force
}

Describe 'Complete Auto-Activation Idempotency Workflow' {

    BeforeEach {
        # Setup completo do ambiente de teste
        $script:TestToolchainsPath = Join-Path $TestDrive "toolchains"
        $script:TestProjectPath = Join-Path $TestDrive "project"

        # Criar estrutura de diretórios
        New-Item -Type Directory -Path $script:TestToolchainsPath -Force | Out-Null
        New-Item -Type Directory -Path $script:TestProjectPath -Force | Out-Null

        # Criar versões LLVM mock realistas
        $mockVersions = @(
            'llvmorg-19.1.5',      # Latest prebuilt
            'llvmorg-19.1.2',
            'llvmorg-18.1.8',
            'llvmorg-17.0.6',      # Oldest prebuilt
            'source-llvmorg-19.1.5', # Latest source
            'source-llvmorg-18.1.8',
            'llvmorg-19.1.0-rc1',    # RC version
            'llvmorg-19.1.0-rc2'
        )

        foreach ($version in $mockVersions) {
            New-Item -Type Directory -Path (Join-Path $script:TestToolchainsPath $version) -Force | Out-Null
        }

        # Criar arquivo de configuração do projeto
        $script:ConfigFile = Join-Path $script:TestProjectPath ".llvmup-config"
    }

    AfterEach {
        # Teardown completo
        if (Test-Path $script:TestToolchainsPath) {
            Remove-Item -Path $script:TestToolchainsPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:TestProjectPath) {
            Remove-Item -Path $script:TestProjectPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Scenario 1: Already on Latest Version' {
        It 'should detect no activation needed when on latest-prebuilt' {
            # Setup: configuração pede latest-prebuilt
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: simular que já estamos na versão mais recente
            $currentlyActive = 'llvmorg-19.1.5'

            # Teste: verificar fluxo completo
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $configExpression | Should -Be 'latest-prebuilt'

            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $false

            Write-Host "✅ Already on latest version ($currentlyActive), no activation needed" -ForegroundColor Green
        }
    }

    Context 'Scenario 2: Version Upgrade Required' {
        It 'should detect activation needed when on older version' {
            # Setup: configuração pede latest-prebuilt
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: simular versão ativa mais antiga
            $currentlyActive = 'llvmorg-18.1.8'

            # Teste: verificar que ativação é necessária
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $true

            # Teste: encontrar qual versão deveria ser ativada
            $targetVersion = Invoke-LlvmMatchVersions -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath
            $targetVersion | Should -Be 'llvmorg-19.1.5'

            Write-Host "🔄 Version upgrade needed: $currentlyActive → $targetVersion" -ForegroundColor Yellow
        }
    }

    Context 'Scenario 3: Source vs Prebuilt Switching' {
        It 'should detect type change requirement' {
            # Setup: configuração pede latest-source
            'default = "latest-source"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: atualmente em versão prebuilt
            $currentlyActive = 'llvmorg-19.1.5'

            # Teste: verificar que mudança de tipo é necessária
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $true

            # Teste: encontrar versão source apropriada
            $targetVersion = Invoke-LlvmMatchVersions -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath
            $targetVersion | Should -Be 'source-llvmorg-19.1.5'

            Write-Host "🔀 Type change needed: prebuilt → source ($targetVersion)" -ForegroundColor Cyan
        }
    }

    Context 'Scenario 4: Wildcard Pattern Satisfaction' {
        It 'should detect satisfaction with wildcard patterns' {
            # Setup: configuração usa wildcard
            'default = "19.1.*"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: versão ativa que satisfaz o wildcard
            $currentlyActive = 'llvmorg-19.1.2'

            # Teste: verificar que não precisa ativar
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $false

            Write-Host "✅ Wildcard pattern satisfied: $currentlyActive matches $configExpression" -ForegroundColor Green
        }

        It 'should detect wildcard pattern violation' {
            # Setup: configuração usa wildcard específico
            'default = "19.1.*"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: versão ativa que NÃO satisfaz o wildcard
            $currentlyActive = 'llvmorg-18.1.8'

            # Teste: verificar que precisa ativar
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $true

            Write-Host "❌ Wildcard pattern violated: $currentlyActive doesn't match $configExpression" -ForegroundColor Red
        }
    }

    Context 'Scenario 5: RC Version Handling' {
        It 'should handle RC versions correctly' {
            # Setup: configuração pede versão específica RC
            'default = "llvmorg-19.1.0-rc2"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Setup: atualmente em RC1
            $currentlyActive = 'llvmorg-19.1.0-rc1'

            # Teste: verificar que upgrade de RC é necessário
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
            $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $currentlyActive -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)
            $needsActivation | Should -Be $true

            Write-Host "🔄 RC upgrade needed: $currentlyActive → rc2" -ForegroundColor Magenta
        }
    }

    Context 'Complete Workflow Integration Test' {
        It 'should demonstrate complete idempotency logic' {
            # Setup: múltiplas configurações para testar
            $testCases = @(
                @{ Config = 'latest-prebuilt'; Active = 'llvmorg-19.1.5'; ShouldActivate = $false; Scenario = 'Already latest' },
                @{ Config = 'latest-prebuilt'; Active = 'llvmorg-18.1.8'; ShouldActivate = $true; Scenario = 'Upgrade needed' },
                @{ Config = 'latest-source'; Active = 'llvmorg-19.1.5'; ShouldActivate = $true; Scenario = 'Type change' },
                @{ Config = '19.1.*'; Active = 'llvmorg-19.1.2'; ShouldActivate = $false; Scenario = 'Wildcard match' },
                @{ Config = '18.*'; Active = 'llvmorg-19.1.5'; ShouldActivate = $true; Scenario = 'Wildcard mismatch' }
            )

            foreach ($case in $testCases) {
                # Setup para cada caso
                "default = `"$($case.Config)`"" | Out-File -FilePath $script:ConfigFile -Encoding utf8 -Force

                # Teste o fluxo
                $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:TestProjectPath
                $needsActivation = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $case.Active -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)

                # Verificação
                $needsActivation | Should -Be $case.ShouldActivate

                $status = if ($needsActivation) { "🔄 ACTIVATE" } else { "✅ SKIP" }
                Write-Host "$status - $($case.Scenario): config=$($case.Config), active=$($case.Active)" -ForegroundColor $(if ($needsActivation) { 'Yellow' } else { 'Green' })
            }
        }
    }
}

AfterAll {
    Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
}
