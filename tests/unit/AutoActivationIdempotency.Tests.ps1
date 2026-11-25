BeforeAll {
    Import-Module -Force (Join-Path $PSScriptRoot '../../Llvm-Functions-Core.psm1')
}

Describe 'Auto-Activation Idempotency' {

    BeforeEach {
        # Setup do ambiente para cada teste
        $script:TestToolchainsPath = Join-Path $TestDrive "toolchains"
        New-Item -Type Directory -Path $script:TestToolchainsPath -Force | Out-Null

        # Criar versoes mock
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
            # Teste: verificar se encontra a versao mais recente
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
            # Setup: simular versao ativa
            $activeVersion = 'llvmorg-19.1.5'
            $expression = 'latest-prebuilt'

            # Teste: verificar se versao ativa satisfaz expressao
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true
        }

        It 'should detect when active version does not satisfy expression' {
            # Setup: simular versao ativa diferente
            $activeVersion = 'llvmorg-18.1.8'
            $expression = 'latest-prebuilt'

            # Teste: verificar se versao ativa NAO satisfaz expressao
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $false
        }

        It 'should handle wildcard expressions correctly' {
            # Setup: versao ativa e expressao wildcard
            $activeVersion = 'llvmorg-19.1.2'
            $expression = '19.1.*'

            # Teste: verificar matching com wildcard
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true
        }

        It 'should handle source vs prebuilt distinction' {
            # Setup: versao source ativa
            $activeVersion = 'source-llvmorg-19.1.5'
            $expression = 'latest-source'

            # Teste: verificar se source satisfaz latest-source
            $result = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $expression -ToolchainsPath $script:TestToolchainsPath
            $result | Should -Be $true

            # Setup: versao prebuilt com expressao source
            $activeVersion2 = 'llvmorg-19.1.5'
            $expression2 = 'latest-source'

            # Teste: verificar se prebuilt NAO satisfaz latest-source
            $result2 = Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion2 -Expression $expression2 -ToolchainsPath $script:TestToolchainsPath
            $result2 | Should -Be $false
        }
    }

    Context 'Enhanced Auto-Activation Logic' {
        BeforeEach {
            # Setup adicional: criar arquivo de configuracao
            $script:ConfigDir = Join-Path $TestDrive "project"
            New-Item -Type Directory -Path $script:ConfigDir -Force | Out-Null
            $script:ConfigFile = Join-Path $script:ConfigDir ".llvmup-config"
        }

        AfterEach {
            # Teardown: limpar configuracao
            if (Test-Path $script:ConfigFile) {
                Remove-Item -Path $script:ConfigFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should read config and determine required version' {
            # Setup: criar arquivo de configuracao
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8

            # Teste: verificar leitura da configuracao
            $result = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $result | Should -Be 'latest-prebuilt'
        }

        It 'should return null when no config file exists' {
            # Teste: verificar comportamento sem arquivo de config
            $result = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $result | Should -BeNullOrEmpty
        }

        It 'should determine if activation is needed' {
            # Setup: criar configuracao e simular versao ativa
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8
            $activeVersion = 'llvmorg-19.1.5'  # Esta e a latest-prebuilt no nosso mock

            # Teste: verificar se ativacao e necessaria (nao deveria ser)
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $isActivationNeeded = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)

            $isActivationNeeded | Should -Be $false
        }

        It 'should detect when activation is needed for different version' {
            # Setup: configuracao pede latest, mas versao ativa e antiga
            'default = "latest-prebuilt"' | Out-File -FilePath $script:ConfigFile -Encoding utf8
            $activeVersion = 'llvmorg-18.1.8'  # Versao mais antiga

            # Teste: verificar se ativacao e necessaria (deveria ser)
            $configExpression = Invoke-LlvmAutoActivate -StartDirectory $script:ConfigDir
            $isActivationNeeded = -not (Test-LlvmVersionSatisfiesExpression -ActiveVersion $activeVersion -Expression $configExpression -ToolchainsPath $script:TestToolchainsPath)

            $isActivationNeeded | Should -Be $true
        }
    }
}

AfterAll {
    Remove-Module Llvm-Functions-Core -Force -ErrorAction SilentlyContinue
}
