# LLVM Build Example

O `llvm-build` compila e instala LLVM a partir do código-fonte. O modo de teste é reservado para desenvolvimento.

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

# Build sem a flag LIBC_WNO_ERROR (pode ser necessário para algumas distribuições)
./llvm-build --disable-libc-wno-error --profile minimal llvmorg-18.1.8
```

### 3. Listar Versões Disponíveis
```bash
./llvm-build --list-only
```

### 4. Build com Configuração de Arquivo
```bash
# Criar configuração
llvmup config init

# Exemplo de configuração para desabilitar LIBC_WNO_ERROR
cat > .llvmup-config << 'EOF'
[version]
default = "llvmorg-18.1.8"

[build]
name = "custom-llvm-18"
disable_libc_wno_error = true
cmake_flags = ["-DCMAKE_BUILD_TYPE=Release"]

[profile]
type = "minimal"
EOF

# Build usando configuração
./llvm-build llvmorg-18.1.8
```

## Controle da Flag LIBC_WNO_ERROR

Por padrão, o LLVM é compilado com `-DLIBC_WNO_ERROR=ON` para evitar erros relacionados à libc. Esta flag pode ser controlada:

### Via Linha de Comando
```bash
# Desabilitar a flag via linha de comando
./llvm-build --disable-libc-wno-error llvmorg-18.1.8
```

### Via Arquivo de Configuração
```ini
[build]
disable_libc_wno_error = true  # Define como true para desabilitar a flag
```

**Nota**: A linha de comando sempre tem prioridade sobre o arquivo de configuração.

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
