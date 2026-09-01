#!/bin/bash
# example-version-usage.sh: Exemplo prático de uso das funções de versão

# Carrega as funções LLVM
source "$(dirname "$0")/llvm-functions.sh"

# Ativa modo de teste para evitar auto-ativação
export LLVM_TEST_MODE=1

echo "🚀 Exemplo Prático: Usando as Funções de Versão LLVM"
echo "===================================================="

echo ""
echo "📋 1. Listando todas as versões instaladas:"
echo "---------------------------------------------"
llvm-get-versions list

echo ""
echo "📋 2. Obtendo lista simples para scripting:"
echo "--------------------------------------------"
versions_array=($(llvm-get-versions simple))
echo "Versões encontradas: ${#versions_array[@]}"
for version in "${versions_array[@]}"; do
    echo "  • $version"
done

echo ""
echo "📋 3. Verificando versões específicas:"
echo "--------------------------------------"
check_versions=("llvmorg-18.1.8" "llvmorg-19.1.7" "llvmorg-25.0.0")
for version in "${check_versions[@]}"; do
    if llvm-version-exists "$version"; then
        echo "  ✅ $version está instalada"
    else
        echo "  ❌ $version não encontrada"
    fi
done

echo ""
echo "📋 4. Parsing de diferentes formatos de versão:"
echo "-----------------------------------------------"
test_versions=(
    "llvmorg-18.1.8"
    "source-llvmorg-20.1.0"
    "source-llvmorg-21-init"
    "19.1.7"
)

for version in "${test_versions[@]}"; do
    parsed=$(llvm-parse-version "$version" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "  📦 $version → $parsed"
    else
        echo "  ❌ Falha ao fazer parse de: $version"
    fi
done

echo ""
echo "📋 5. Encontrando a versão mais recente:"
echo "----------------------------------------"
latest=$(llvm-get-latest-version 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "  🏆 Versão mais recente: $latest"

    # Parse da versão mais recente
    latest_parsed=$(llvm-parse-version "$latest" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "  📝 Versão parseada: $latest_parsed"
    fi
else
    echo "  ❌ Não foi possível determinar a versão mais recente"
fi

echo ""
echo "📋 6. Comparando versões:"
echo "-------------------------"
if [ ${#versions_array[@]} -ge 2 ]; then
    v1="${versions_array[0]}"
    v2="${versions_array[1]}"

    echo "  Comparando $v1 com $v2:"
    if llvm-version-compare "$v1" "$v2" 2>/dev/null; then
        echo "    ✅ $v1 >= $v2"
    else
        echo "    📉 $v1 < $v2"
    fi
fi

echo ""
echo "📋 7. Exemplo de script automático:"
echo "-----------------------------------"
cat << 'EOF'
# Função para ativar automaticamente a versão mais recente
auto_activate_latest() {
    local latest=$(llvm-get-latest-version 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Ativando versão mais recente: $latest"
        llvm-activate "$latest"
    else
        echo "Nenhuma versão LLVM encontrada"
        return 1
    fi
}

# Função para verificar se uma versão mínima está disponível
check_minimum_version() {
    local required="$1"
    local latest=$(llvm-get-latest-version 2>/dev/null)

    if [ $? -eq 0 ] && llvm-version-compare "$latest" "$required" 2>/dev/null; then
        echo "✅ Versão $latest satisfaz o requisito mínimo $required"
        return 0
    else
        echo "❌ Versão mínima $required não satisfeita"
        return 1
    fi
}

# Função para listar versões em formato customizado
list_custom_format() {
    echo "Versões LLVM Instaladas:"
    echo "========================"

    llvm-get-versions simple | while read -r version; do
        local parsed=$(llvm-parse-version "$version" 2>/dev/null)
        local status=""

        if [ -n "$_ACTIVE_LLVM" ] && [ "$version" = "$_ACTIVE_LLVM" ]; then
            status=" (ATIVA)"
        fi

        if echo "$version" | grep -q "^source-"; then
            echo "🔨 $version (v$parsed) [Source Build]$status"
        else
            echo "📦 $version (v$parsed) [Prebuilt]$status"
        fi
    done
}
EOF

echo ""
echo "📋 8. JSON para integração com outras ferramentas:"
echo "--------------------------------------------------"
echo "Exemplo de saída JSON (primeiras linhas):"
llvm-get-versions json | head -15

echo ""
echo "✨ Exemplo concluído! As funções estão prontas para uso."
echo ""
echo "💡 Dicas para uso prático:"
echo "  • Use llvm-get-versions simple em scripts para obter arrays"
echo "  • Use llvm-parse-version para normalizar identificadores"
echo "  • Use llvm-version-compare para validações de versão mínima"
echo "  • Use llvm-get-latest-version para sempre pegar a mais recente"
echo "  • Use o formato JSON para integração com ferramentas externas"
