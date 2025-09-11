# Custom Directory Configuration

## 🎯 **Problema Resolvido**

Adicionada funcionalidade para customizar diretórios de instalação via arquivo `.llvmup-config`, resolvendo limitações do ambiente Docker onde apenas o working directory e seus subdiretorios são acessíveis.

## ✅ **Nova Funcionalidade**

### Seção `[paths]` no `.llvmup-config`

```toml
[paths]
llvm_home = "./llvm"                    # Diretório base personalizado
toolchains_dir = "./llvm/toolchains"   # Diretório de instalações
sources_dir = "./llvm/sources"         # Diretório de código fonte
```

# Custom Directory Configuration

## 🎯 Problema resolvido

É possível customizar diretórios de instalação via um arquivo de configuração `.llvmup-config`. Isso resolve limitações comuns em ambientes como Docker — onde apenas o diretório de trabalho e seus subdiretórios estão disponíveis — e facilita testes locais com estruturas personalizadas.

## ✅ Nova funcionalidade

Adicione a seção `[paths]` no `.llvmup-config` para sobrepor os diretórios padrão:

```toml
[paths]
llvm_home = "./llvm"                    # Diretório base personalizado
toolchains_dir = "./llvm/toolchains"   # Diretório de instalações
sources_dir = "./llvm/sources"         # Diretório de código fonte
```

### Exemplos

1) Ambiente Docker (caminhos relativos)

```toml
[version]
default = "llvmorg-21.1.0"

[paths]
llvm_home = "./docker-llvm"
toolchains_dir = "./docker-llvm/toolchains"
sources_dir = "./docker-llvm/sources"
```

2) Instalação personalizada (caminhos absolutos)

```toml
[version]
default = "llvmorg-21.1.0"

[paths]
llvm_home = "/opt/llvm"
toolchains_dir = "/opt/llvm/toolchains"
sources_dir = "/opt/llvm/sources"
```

3) Instalação local do usuário (note a expansão de `~`)

```toml
[version]
default = "llvmorg-21.1.0"

[paths]
llvm_home = "~/my-llvm"
toolchains_dir = "~/my-llvm/toolchains"
sources_dir = "~/my-llvm/sources"
```

> Observação: o parser TOML pode retornar as chaves exatamente como escritas. O código que carrega a configuração converte e normaliza as chaves (ex.: `llvm_home`) antes de usar. Além disso, `~` não é automaticamente expandido pelo TOML; nossa implementação chama `Expand-Path` / `Resolve-Path` ao aplicar os diretórios.

## 🔧 Como funciona (resumo)

1. Carregamento antecipado: as configurações de diretório são aplicadas antes da criação dos diretórios.
2. Logs verbosos: quando executado com `-Verbose` ou `-VerboseMode`, o script informa quais caminhos personalizados estão sendo usados.
3. Fallback inteligente: se apenas `llvm_home` for informado, os outros diretórios são derivados a partir dele.

### Ordem de prioridade

1. Configuração explícita: `toolchains_dir` e `sources_dir` definidos no `.llvmup-config` (ou variáveis de ambiente equivalentes, se aplicável).
2. Configuração base: `llvm_home` + subdiretórios padrão.
3. Padrão do sistema: `$HOME/.llvm` + subdiretórios.

## 🧪 Exemplo de teste

Crie um arquivo de configuração de teste e execute o instalador em modo verboso:

```bash
# Criar configuração de teste
cat > .llvmup-config << 'EOF'
[version]
default = "llvmorg-21.1.0"

[paths]
llvm_home = "./test-llvm"
toolchains_dir = "./test-llvm/toolchains"
sources_dir = "./test-llvm/sources"
EOF

# Testar com logs verbose (forma recomendada portátil)
pwsh -NoProfile -Command '. ./Install-Llvm.ps1; # chame a função ou script conforme a API do projeto'
```

Saída esperada (exemplo):

```
[VERBOSE] Using custom LLVM_HOME: ./test-llvm
[VERBOSE] Using custom TOOLCHAINS_DIR: ./test-llvm/toolchains
[VERBOSE] Using custom SOURCES_DIR: ./test-llvm/sources
```

## 🎉 Benefícios

- Docker friendly: funciona em containers com volumes limitados.
- Flexibilidade: permite qualquer estrutura de diretórios.
- Backward compatible: configurações antigas continuam válidas.
- Logs claros: modo verbose mostra exatamente os caminhos usados.
- Fácil debug: diretórios customizados facilitam testes e desenvolvimento.

## 🔍 Implementação técnica (exemplo portátil)

O exemplo abaixo assume que o resultado do parser TOML é um hashtable com chaves em snake_case (ex.: `llvm_home`). Ajuste conforme a função `Read-LlvmConfig` do projeto.

```powershell
function Apply-DirectoryConfiguration {
    param([hashtable]$Config)

    # Helper local para expandir ~ e caminhos relativos sem falhar
    function Expand-PathSafe($p) {
        if (-not $p) { return $null }
        try { return (Resolve-Path -LiteralPath (Expand-Path $p) -ErrorAction Stop).Path } catch { return (Expand-Path $p) }
    }

    $llvmHomeRaw = $null
    if ($Config.ContainsKey('llvm_home')) { $llvmHomeRaw = $Config['llvm_home'] }
    elseif ($Config.ContainsKey('LlvmHome')) { $llvmHomeRaw = $Config['LlvmHome'] }

    if ($llvmHomeRaw) {
        $script:LLVM_HOME = Expand-PathSafe $llvmHomeRaw
        Write-Verbose "Using custom LLVM_HOME: $script:LLVM_HOME"
    } else {
        $script:LLVM_HOME = Join-Path $HOME '.llvm'
    }

    if ($Config.ContainsKey('toolchains_dir')) {
        $script:TOOLCHAINS_DIR = Expand-PathSafe $Config['toolchains_dir']
        Write-Verbose "Using custom TOOLCHAINS_DIR: $script:TOOLCHAINS_DIR"
    } else {
        $script:TOOLCHAINS_DIR = Join-Path $script:LLVM_HOME 'toolchains'
    }

    if ($Config.ContainsKey('sources_dir')) {
        $script:SOURCES_DIR = Expand-PathSafe $Config['sources_dir']
        Write-Verbose "Using custom SOURCES_DIR: $script:SOURCES_DIR"
    } else {
        $script:SOURCES_DIR = Join-Path $script:LLVM_HOME 'sources'
    }

    # Ensure directories exist
    foreach ($p in @($script:TOOLCHAINS_DIR, $script:SOURCES_DIR)) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }
}
```

### Carregamento antecipado (exemplo)

```powershell
# Ler config e aplicar diretórios antes das operações que escrevem em disco
$earlyConfig = Read-LlvmConfig
if ($earlyConfig) { Apply-DirectoryConfiguration -Config $earlyConfig }
```

## Resultado

Agora o LLVM Manager pode ser usado em qualquer ambiente (incluindo Docker) apontando para diretórios customizados dentro do volume montado. Os testes e operações de instalação respeitam a configuração fornecida.

---

Se quiser, eu aplico essas mudanças diretamente no arquivo e crio um commit com a mensagem: `docs: melhorar CUSTOM_DIRECTORIES.md — snippets e notas de portabilidade`.
