#!/bin/bash
# test-real-activation.sh: Teste real de ativação em subshell

echo "=== Teste Real de Ativação/Desativação em Subshell ==="
echo ""

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
    exit 1
fi

echo "🧪 Testando ativação real da versão: $test_version"
echo ""

# Executar teste real em subshell
(
    echo "1. Carregando funções e ativando versão..."
    source ./llvm-functions.sh 2>/dev/null

    echo "   Estado antes da ativação:"
    echo "   - Status LLVM: $(llvm-status 2>&1)"
    echo "   - which clang: $(which clang 2>/dev/null || echo 'não encontrado')"

    # Tentar ativação real
    echo ""
    echo "2. Ativando versão $test_version..."
    if source ./llvm-activate "$test_version" 2>/dev/null; then
        echo "   ✅ Ativação bem-sucedida!"

        echo ""
        echo "3. Verificando estado após ativação:"
        echo "   - Status LLVM:"
        llvm-status

        echo ""
        echo "   - Variáveis de ambiente:"
        echo "     PATH (início): ${PATH%%:*}"
        echo "     CC: ${CC:-'não definido'}"
        echo "     CXX: ${CXX:-'não definido'}"
        echo "     LD: ${LD:-'não definido'}"

        echo ""
        echo "   - Comandos which:"
        for cmd in clang clang++ clangd lld llvm-config; do
            which_result=$(which $cmd 2>/dev/null || echo "não encontrado")
            echo "     which $cmd: $which_result"
        done

        echo ""
        echo "   - Testando execução de clang:"
        if command -v clang >/dev/null 2>&1; then
            clang_version=$(clang --version 2>/dev/null | head -1)
            echo "     Clang version: $clang_version"
        else
            echo "     ❌ Comando clang não disponível"
        fi

        echo ""
        echo "4. Testando desativação..."
        if source ./llvm-deactivate 2>/dev/null; then
            echo "   ✅ Desativação bem-sucedida!"

            echo ""
            echo "5. Estado após desativação:"
            echo "   - Status LLVM:"
            llvm-status

            echo "   - which clang: $(which clang 2>/dev/null || echo 'não encontrado')"
        else
            echo "   ❌ Erro na desativação"
        fi

    else
        echo "   ❌ Erro na ativação"
    fi

    echo ""
    echo "=== Teste Real Concluído ==="
)

echo ""
echo "💡 O teste foi executado em um subshell isolado para não afetar o ambiente atual."
