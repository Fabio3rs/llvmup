# PowerShell Version - Implementação das Funcionalidades do Bash

## ✅ Funcionalidades Implementadas

### 1. **Sistema de Logging Aprimorado**
- Similar ao bash, com controle por `VERBOSE_MODE` e `LLVM_TEST_MODE`
- Funções específicas: `Write-VerboseLog`, `Write-InfoLog`, `Write-ErrorLog`, etc.
- Logs informativos só aparecem em modo verbose ou teste
- Erros sempre são mostrados

### 2. **Suporte ao Flag LIBC_WNO_ERROR**
- Novo parâmetro: `-DisableLibcWnoError`
- Configuração via `.llvmup-config`: `disable_libc_wno_error = true`
- Funcionalidade idêntica à versão bash

### 3. **Detecção Automática de Versões Instaladas**
- `Initialize-LlvmConfig` detecta versões já instaladas
- Lista versões disponíveis para facilitar a configuração
- Sugere a primeira versão encontrada como padrão

### 4. **Função Trim Robusta**
- `Get-TrimmedString`: remove espaços e aspas
- Utilizada em todo o parsing de configuração
- Garante limpeza consistente dos valores

### 5. **Funções Separadas de Config**
- `Invoke-LlvmConfigLoad`: apenas carrega e valida configuração
- `Invoke-LlvmConfigApply`: instala com base na configuração
- `Invoke-LlvmConfigActivate`: ativa versão já instalada
- Separação clara de responsabilidades

### 6. **Melhor Tratamento de Arrays**
- Parser robusto para arrays em `.llvmup-config`
- Suporte a arrays multi-linha
- Funcionalidade `Parse-ArrayContent` para processamento consistente

### 7. **Suporte a CMake Presets**
- Presets: Debug, Release, RelWithDebInfo, MinSizeRel
- Aplicação automática de flags CMAKE baseadas no preset
- Configuração via `cmake_preset` na seção `[project]`

## 🆕 Comandos Adicionados

### Config Management
```powershell
# Inicializar configuração do projeto
.\Install-Llvm.ps1 config init

# Carregar e exibir configuração
.\Install-Llvm.ps1 config load

# Instalar usando configuração
.\Install-Llvm.ps1 config apply

# Ativar versão existente baseada na configuração
.\Install-Llvm.ps1 config activate
```

### Opções de Build Avançadas
```powershell
# Desabilitar flag LIBC_WNO_ERROR
.\Install-Llvm.ps1 install -FromSource -DisableLibcWnoError

# Build com configuração verbose
.\Install-Llvm.ps1 install -FromSource -Verbose

# Build usando perfil mínimo
.\Install-Llvm.ps1 install -FromSource -Profile minimal
```

## 📋 Exemplo de .llvmup-config Melhorado

```ini
# .llvmup-config - LLVM project configuration
[version]
default = "llvmorg-21.1.0"

[build]
name = "21.1.0-debug"
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Debug",
  "-DLLVM_ENABLE_ASSERTIONS=ON"
]
disable_libc_wno_error = false

[profile]
type = "full"

[components]
include = ["clang", "lld", "lldb", "compiler-rt"]

[project]
auto_activate = true
cmake_preset = "Debug"
```

## 🔄 Equivalência com Bash

| Funcionalidade Bash | Equivalente PowerShell |
|---------------------|------------------------|
| `log_verbose()` | `Write-VerboseLog` |
| `log_info()` | `Write-InfoLog` |
| `log_error()` | `Write-ErrorLog` |
| `trim()` | `Get-TrimmedString` |
| `llvm-config-load` | `Invoke-LlvmConfigLoad` |
| `llvm-config-apply` | `Invoke-LlvmConfigApply` |
| `llvm-config-activate` | `Invoke-LlvmConfigActivate` |
| `--disable-libc-wno-error` | `-DisableLibcWnoError` |

## 🧪 Modo de Teste

Similar ao bash, suporta variáveis de ambiente para testes:
- `$env:LLVM_TEST_MODE = "1"` - Ativa modo de teste
- `$env:LLVM_TEST_VERSION` - Define versão para teste
- `$env:LLVM_TEST_PROFILE` - Define perfil para teste

## 📊 Status da Implementação

- ✅ Sistema de logging controlado por verbose
- ✅ Suporte completo ao LIBC_WNO_ERROR
- ✅ Detecção automática de versões instaladas
- ✅ Função trim robusta
- ✅ Separação de funções de config (load/apply/activate)
- ✅ Parser de array melhorado
- ✅ Suporte a CMake presets
- ✅ Modo de teste compatível
- ✅ Help atualizado com novas funcionalidades

**Total: 866 linhas** (incremento significativo das ~453 originais)

A versão PowerShell agora tem paridade funcional completa com a versão bash, incluindo todas as melhorias implementadas durante esta iteração.
