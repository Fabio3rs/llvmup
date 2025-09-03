#!/bin/bash
# test-compatibility.sh: Script para testar a compatibilidade entre os componentes

echo "=== Teste de Compatibilidade dos Scripts LLVM ==="
echo ""

# Test 1: Verificar se as funções carregam sem erro
echo "1. Testando carregamento das funções..."
if source ./llvm-functions.sh 2>/dev/null; then
    echo "✅ Funções carregadas com sucesso"
else
    echo "❌ Erro ao carregar funções"
    exit 1
fi

# Test 2: Verificar comandos de status
echo ""
echo "2. Testando comando de status..."
llvm-status

# Test 3: Verificar listagem de versões
echo ""
echo "3. Testando listagem de versões..."
llvm-list

# Test 4: Verificar mensagens de ajuda
echo ""
echo "4. Testando mensagens de ajuda..."
echo "llvm-activate sem argumentos:"
llvm-activate 2>/dev/null || true
echo ""
echo "llvm-vscode-activate sem argumentos:"
llvm-vscode-activate 2>/dev/null || true

# Test 5: Verificar se completion function está registrada
echo ""
echo "5. Testando função de completion..."
if declare -F _llvm_complete_versions >/dev/null; then
    echo "✅ Função de completion registrada"
else
    echo "❌ Função de completion não encontrada"
fi

# Test 6: Verificar se os caminhos dos scripts estão corretos
echo ""
echo "6. Verificando caminhos dos scripts..."
for script in llvm-activate llvm-deactivate llvm-vscode-activate; do
    if [ -f "$script" ]; then
        echo "✅ $script existe no diretório atual"
    else
        echo "⚠️  $script não encontrado no diretório atual (normal, será instalado em ~/.local/bin)"
    fi
done

# Test 7: Verificar binários LLVM quando uma versão está ativa
echo ""
echo "7. Testando detecção de binários LLVM..."

# Lista de binários LLVM importantes
llvm_binaries=(
    "clang"
    "clang++"
    "clangd"
    "lld"
    "llvm-config"
    "lldb"
    "opt"
    "llc"
    "lli"
    "llvm-objdump"
    "llvm-nm"
    "llvm-strip"
)

# Função para testar binários em um diretório específico
test_llvm_binaries() {
    local llvm_dir="$1"
    local version="$2"

    echo "  Testando binários na versão: $version"
    echo "  Diretório: $llvm_dir/bin"

    if [ ! -d "$llvm_dir/bin" ]; then
        echo "  ❌ Diretório bin não encontrado: $llvm_dir/bin"
        return 1
    fi

    local found_count=0
    local total_count=${#llvm_binaries[@]}

    for binary in "${llvm_binaries[@]}"; do
        local binary_path="$llvm_dir/bin/$binary"
        if [ -x "$binary_path" ]; then
            echo "  ✅ $binary encontrado e executável"
            found_count=$((found_count + 1))
        else
            echo "  ⚠️  $binary não encontrado ou não executável"
        fi
    done

    echo "  📊 Resumo: $found_count/$total_count binários encontrados"

    # Testar alguns binários importantes
    echo "  🔍 Testando funcionalidade básica..."
    if [ -x "$llvm_dir/bin/clang" ]; then
        local clang_version=$("$llvm_dir/bin/clang" --version 2>/dev/null | head -1)
        echo "  📋 Clang version: $clang_version"
    fi

    if [ -x "$llvm_dir/bin/llvm-config" ]; then
        local llvm_version=$("$llvm_dir/bin/llvm-config" --version 2>/dev/null)
        echo "  📋 LLVM version: $llvm_version"
    fi

    return 0
}

# Testar todas as versões instaladas
toolchains_dir="$HOME/.llvm/toolchains"
if [ -d "$toolchains_dir" ]; then
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ]; then
            version=$(basename "$dir")
            echo ""
            test_llvm_binaries "$dir" "$version"
        fi
    done
else
    echo "  ⚠️  Nenhuma versão do LLVM encontrada em $toolchains_dir"
fi

# Test 8: Simular ativação e verificar PATH
echo ""
echo "8. Testando simulação de ativação..."

# Criar um script temporário que simula ativação
temp_activation_test=$(mktemp)
cat > "$temp_activation_test" << 'EOF'
#!/bin/bash
# Simular ativação de uma versão LLVM

# Encontrar primeira versão disponível
toolchains_dir="$HOME/.llvm/toolchains"
if [ -d "$toolchains_dir" ]; then
    first_version=""
    for dir in "$toolchains_dir"/*; do
        if [ -d "$dir" ] && [ -d "$dir/bin" ]; then
            first_version=$(basename "$dir")
            break
        fi
    done

    if [ -n "$first_version" ]; then
        echo "Simulando ativação da versão: $first_version"

        # Simular adição ao PATH
        test_path="$toolchains_dir/$first_version/bin:$PATH"

        # Testar which commands com o PATH simulado
        echo "Testando 'which' commands com PATH simulado:"
        for binary in clang clang++ clangd lld llvm-config; do
            binary_path=$(PATH="$test_path" which "$binary" 2>/dev/null)
            if [ -n "$binary_path" ]; then
                echo "  ✅ which $binary: $binary_path"
            else
                echo "  ❌ which $binary: não encontrado"
            fi
        done
    else
        echo "❌ Nenhuma versão válida encontrada para teste"
    fi
else
    echo "❌ Diretório de toolchains não encontrado"
fi
EOF

bash "$temp_activation_test"
rm -f "$temp_activation_test"

# Test 9: Verificar environment variables consistency
echo ""
echo "9. Testando consistência de variáveis de ambiente..."

# Verificar se as variáveis usadas pelos scripts são consistentes
echo "  Variáveis de controle utilizadas pelos scripts:"
echo "  - _ACTIVE_LLVM (usado por llvm-activate/deactivate)"
echo "  - _ACTIVE_LLVM_PATH (usado para mostrar o caminho)"
echo "  - _OLD_PATH, _OLD_CC, _OLD_CXX, _OLD_LD, _OLD_PS1 (backup das variáveis originais)"

if [ -n "$_ACTIVE_LLVM" ]; then
    echo "  ✅ Versão ativa detectada: $_ACTIVE_LLVM"
    echo "  📍 Caminho ativo: $_ACTIVE_LLVM_PATH"
else
    echo "  ℹ️  Nenhuma versão LLVM ativa no momento"
fi

echo ""
echo "=== Teste de Compatibilidade Concluído ==="
echo ""
echo "📋 Resumo dos Testes:"
echo "✅ = Passou  ⚠️ = Aviso  ❌ = Falhou  ℹ️ = Informação"
