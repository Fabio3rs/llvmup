# LLVM Build Example

## ✅ Funcionalidade Real Restaurada

O `llvm-build` agora está funcionando em modo real completo, mas mantém o modo de teste para automação.

## Como Usar

### 1. Modo de Teste (para desenvolvimento/testes)
```bash
# Mock build rápido
LLVM_TEST_MODE=1 ./llvm-build --profile minimal --name "test-build" llvmorg-18.1.8
```

### 2. Build Real Completo
```bash
# Build real do LLVM (pode levar horas!)
./llvm-build --profile minimal --cmake-flags "-DCMAKE_BUILD_TYPE=Release" --name "llvm-18-minimal" --default llvmorg-18.1.8
```

### 3. Listar Versões Disponíveis
```bash
./llvm-build --list-only
```

### 4. Build com Configuração de Arquivo
```bash
# Criar configuração
llvmup config init

# Editar .llvmup-config e depois
./llvm-build llvmorg-18.1.8
```

## Perfis Disponíveis

- **minimal**: apenas `clang;lld`
- **full**: todos os projetos LLVM principais
- **custom**: usar componentes especificados

## Processo Real de Build

Quando não está em `LLVM_TEST_MODE=1`:

1. 🔄 Clona repositório LLVM do GitHub
2. 🔧 Configura CMake com flags personalizadas
3. 🔨 Compila usando Ninja (pode levar 30+ minutos)
4. 📦 Instala em `~/.llvm/toolchains/`
5. 🔗 Opcionalmente define como versão padrão

## Funcionalidades Mantidas

✅ Parsing de arquivos `.llvmup-config`
✅ Suporte a CMake flags customizadas
✅ Perfis de build (minimal/full/custom)
✅ Nomes customizados
✅ Definição automática como padrão
✅ Logs coloridos e informativos
✅ Modo de teste para automação
✅ Listagem de versões disponíveis

O sistema agora é **completo e funcional** tanto para desenvolvimento quanto para uso real!
