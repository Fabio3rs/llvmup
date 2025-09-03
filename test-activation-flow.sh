#!/bin/bash
# test-activation-flow.sh: Teste do fluxo completo de ativação/desativação

echo "=== Teste do Fluxo de Ativação/Desativação LLVM ==="
echo ""

# Carregar funções
if ! source ./llvm-functions.sh 2>/dev/null; then
    echo "❌ Erro ao carregar funções LLVM"
    exit 1
fi

# Encontrar primeira versão disponível
toolchains_dir="$HOME/.llvm/toolchains"
test_version=""

if [ -d "$toolchains_dir" ]; then
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ] && [ -d "$dir/bin" ] && [ -x "$dir/bin/clang" ]; then
            test_version=$(basename "$dir")
            break
        fi
    done
fi

if [ -z "$test_version" ]; then
    echo "❌ Nenhuma versão válida encontrada para teste"
    echo "Execute 'llvmup' para instalar uma versão do LLVM"
    exit 1
fi

echo "🧪 Usando versão para teste: $test_version"
echo ""

# Salvar estado inicial
initial_path="$PATH"
initial_cc="$CC"
initial_cxx="$CXX"
initial_ld="$LD"
initial_ps1="$PS1"

echo "1. Estado inicial:"
echo "  PATH (primeiros 100 chars): ${PATH:0:100}..."
echo "  CC: ${CC:-'(não definido)'}"
echo "  CXX: ${CXX:-'(não definido)'}"
echo "  Status LLVM:"
llvm-status
echo ""

# Testar which commands antes da ativação
echo "2. Comandos 'which' antes da ativação:"
for cmd in clang clang++ clangd; do
    which_result=$(which $cmd 2>/dev/null || echo "não encontrado")
    echo "  which $cmd: $which_result"
done
echo ""

# Simular ativação usando o script diretamente
echo "3. Simulando ativação da versão $test_version..."

# Como não podemos realmente fazer source dentro de uma função de forma que afete
# o shell pai, vamos simular o que aconteceria
LLVM_DIR="$toolchains_dir/$test_version"

# Simular o que o script de ativação faria
if [ -d "$LLVM_DIR" ]; then
    echo "  ✅ Diretório LLVM encontrado: $LLVM_DIR"

    # Simular atualizações de variáveis
    simulated_path="$LLVM_DIR/bin:$PATH"
    simulated_cc="$LLVM_DIR/bin/clang"
    simulated_cxx="$LLVM_DIR/bin/clang++"

    echo "  📝 PATH seria atualizado para incluir: $LLVM_DIR/bin"
    echo "  📝 CC seria definido como: $simulated_cc"
    echo "  📝 CXX seria definido como: $simulated_cxx"

    # Testar se os binários existem
    echo ""
    echo "4. Verificando binários que seriam ativados:"
    for binary in clang clang++ clangd lld llvm-config; do
        binary_path="$LLVM_DIR/bin/$binary"
        if [ -x "$binary_path" ]; then
            echo "  ✅ $binary: $binary_path"
        else
            echo "  ❌ $binary: não encontrado ou não executável"
        fi
    done

    # Testar which com PATH simulado
    echo ""
    echo "5. Comandos 'which' com PATH simulado:"
    for cmd in clang clang++ clangd; do
        which_result=$(PATH="$simulated_path" which $cmd 2>/dev/null || echo "não encontrado")
        echo "  which $cmd: $which_result"
    done

    # Verificar versões
    echo ""
    echo "6. Verificando versões dos binários:"
    if [ -x "$LLVM_DIR/bin/clang" ]; then
        clang_version=$("$LLVM_DIR/bin/clang" --version 2>/dev/null | head -1)
        echo "  Clang version: $clang_version"
    fi

    if [ -x "$LLVM_DIR/bin/llvm-config" ]; then
        llvm_version=$("$LLVM_DIR/bin/llvm-config" --version 2>/dev/null)
        echo "  LLVM version: $llvm_version"
    fi

else
    echo "  ❌ Diretório LLVM não encontrado: $LLVM_DIR"
fi

echo ""
echo "7. Testando funcionalidade das funções bash:"

# Testar função de status (deve mostrar que não há versão ativa)
echo "  Status atual:"
llvm-status

# Testar função de listagem
echo ""
echo "  Versões disponíveis:"
llvm-list

echo ""
echo "8. Verificando integridade do ambiente:"
echo "  PATH ainda está intacto: $([ "$PATH" = "$initial_path" ] && echo "✅ Sim" || echo "❌ Não")"
echo "  CC ainda está intacto: $([ "$CC" = "$initial_cc" ] && echo "✅ Sim" || echo "❌ Não")"
echo "  CXX ainda está intacto: $([ "$CXX" = "$initial_cxx" ] && echo "✅ Sim" || echo "❌ Não")"

echo ""
echo "=== Teste do Fluxo Concluído ==="
echo ""
echo "💡 Nota: Este teste simula o comportamento dos scripts sem realmente"
echo "    modificar o ambiente atual. Para teste real, use:"
echo "    source llvm-activate $test_version"
echo "    llvm-status"
echo "    source llvm-deactivate"
