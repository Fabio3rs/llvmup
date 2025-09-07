BeforeAll {
    Import-Module "/mnt/projects/Projects/llvm-manager/Llvm-Functions-Core.psm1" -Force
}

Describe 'Auto-Activation Idempotency' {

    BeforeEach {
        # Setup do ambiente para cada teste
        $script:TestToolchainsPath = Join-Path $TestDrive "toolchains"
        New-Item -Type Directory -Path $script:TestToolchainsPath -Force | Out-Null

        # Criar versões mock
        $mockVersions = @(
            'llvmorg-19.1.5',
            'llvmorg-19.1.2',
            'llvmorg-18.1.8',
            'source-llvmorg-19.1.5',
            'source-llvmorg-18.1.8'
        )

        foreach ($version in $mockVersions) {
            New-Item -Type Directory -Path (Join-Path $script:TestToolchainsPath $version) -Force | Out-Null
        }
    }

    AfterEach {
        # Teardown do ambiente
        if (Test-Path $script:TestToolchainsPath) {
            Remove-Item -Path $script:TestToolchainsPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Version Matching Logic' {
        It 'should find latest version when specified' {
            # Teste: verificar se encontra a versão mais recente
            $result = Get-LlvmVersionsSimple -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Contain 'llvmorg-19.1.5'
            $result | Should -Contain 'source-llvmorg-19.1.5'
            $result.Count | Should -Be 5
        }

        It 'should match latest-prebuilt expression' {
            # Teste: verificar matching de latest-prebuilt
            $result = Invoke-LlvmMatchVersions -Expression 'latest-prebuilt' -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be 'llvmorg-19.1.5'
        }

        It 'should match latest-source expression' {
            # Teste: verificar matching de latest-source
            $result = Invoke-LlvmMatchVersions -Expression 'latest-source' -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be 'source-llvmorg-19.1.5'
        }
    }

    Context 'Version Satisfaction Logic' {
        It 'should detect when active version satisfies expression' {
            # Setup: simular versão ativa
            $activeVersion = 'llvmorg-19.1.5'
            $expression = 'latest-prebuilt'

            # Teste: verificar se versão ativa satisfaz expressão
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true
        }

        It 'should detect when active version does not satisfy expression' {
            # Setup: simular versão ativa diferente
            $activeVersion = 'llvmorg-18.1.8'
            $expression = 'latest-prebuilt'

            # Teste: verificar se versão ativa NÃO satisfaz expressão
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $false
        }

        It 'should handle wildcard expressions correctly' {
            # Setup: versão ativa e expressão wildcard
            $activeVersion = 'llvmorg-19.1.2'
            $expression = '19.1.*'

            # Teste: verificar matching com wildcard
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true
        }

        It 'should handle source vs prebuilt distinction' {
            # Setup: versão source ativa
            $activeVersion = 'source-llvmorg-19.1.5'
            $expression = 'latest-source'

            # Teste: verificar se source satisfaz latest-source
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true

            # Setup: versão prebuilt com expressão source
            $activeVersion2 = 'llvmorg-19.1.5'
            $expression2 = 'latest-source'

            # Teste: verificar se prebuilt NÃO satisfaz latest-source
            $result2 = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion2 -Expression $expression2 -ToolchainsPath $script:TestToolchainsPath
            $result2 | Should -Be $false
        }
    }

    Context 'Enhanced Auto-Activation Logic' {
        BeforeEach {
            # Setup adicional: criar arquivo de configuração
            $script:ConfigDir = Join-Path $TestDrive "project"
            New-Item -Type Directory -Path $script:ConfigDir -Force | Out-Null
            $script:ConfigFile = Join-Path $script:ConfigDir ".llvmup-config"
        }

        AfterEach {
            # Teardown: limpar configuração
            if (Test-Path $script:ConfigFile) {
                Remove-Item -Path $script:ConfigFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should read config and determine required version' {
            # Setup: criar arquivo de configuração
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Teste: verificar leitura da configuração
            $result = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $result | Should -Be 'latest-prebuilt'
        }

        It 'should return null when no config file exists' {
            # Teste: verificar comportamento sem arquivo de config
            $result = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $result | Should -BeNullOrEmpty
        }

        It 'should determine if activation is needed' {
            # Setup: criar configuração e simular versão ativa
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8
            $activeVersion = 'llvmorg-19.1.5'  # Esta é a latest-prebuilt no nosso mock

            # Teste: verificar se ativação é necessária (não deveria ser)
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $isActivationNeeded = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)

            $isActivationNeeded | Should -Be $false
        }

        It 'should detect when activation is needed for different version' {
            # Setup: configuração pede latest, mas versão ativa é antiga
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8
            $activeVersion = 'llvmorg-18.1.8'  # Versão mais antiga

            # Teste: verificar se ativação é necessária (deveria ser)
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $isActivationNeeded = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)

            $isActivationNeeded | Should -Be $true
        }
    }
}

AfterAll {
    Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
}
