#!/bin/bash
# activate_llvm.sh: Ativa uma versão específica do LLVM apenas para a sessão atual.
# Se nenhum argumento for passado, lista as versões instaladas.
# Uso:
#   source activate_llvm.sh             -> Lista as versões disponíveis
#   source activate_llvm.sh <versao>      -> Ativa a versão especificada

LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"

# Se nenhum argumento for passado, lista as versões instaladas
if [ "$#" -eq 0 ]; then
    echo "Versões instaladas em $LLVM_TOOLCHAINS_DIR:"
    echo "Installed versions in $LLVM_TOOLCHAINS_DIR:"
    if [ -d "$LLVM_TOOLCHAINS_DIR" ]; then
        for dir in "$LLVM_TOOLCHAINS_DIR"/*; do
            if [ -d "$dir" ]; then
                echo "  - $(basename "$dir")"
            fi
        done
    else
        echo "Nenhuma versão instalada em $LLVM_TOOLCHAINS_DIR."
        echo "No versions installed in $LLVM_TOOLCHAINS_DIR."
    fi
    return 0 2>/dev/null || exit 0
fi

VERSAO="$1"
export LLVM_DIR="$LLVM_TOOLCHAINS_DIR/$VERSAO"

if [ ! -d "$LLVM_DIR" ]; then
    echo "A versão '$VERSAO' não está instalada em $LLVM_TOOLCHAINS_DIR."
    echo "The version '$VERSAO' is not installed in $LLVM_TOOLCHAINS_DIR."
    return 1 2>/dev/null || exit 1
fi

# Verifica se já há uma versão ativa
if [ -n "$_ACTIVE_LLVM" ]; then
    echo "Uma versão já está ativa: $_ACTIVE_LLVM."
    echo "Para alterar, execute 'source deactivate_llvm.sh' primeiro."
    echo "One version is already active: $_ACTIVE_LLVM."
    echo "To change, run 'source deactivate_llvm.sh' first."
    return 1 2>/dev/null || exit 1
fi

# Faz backup das variáveis que serão modificadas (somente se ainda não foram definidas)
[ -z "$_OLD_PATH" ] && export _OLD_PATH="$PATH"
[ -z "$_OLD_CC" ] && export _OLD_CC="${CC:-}"
[ -z "$_OLD_CXX" ] && export _OLD_CXX="${CXX:-}"
[ -z "$_OLD_LD" ] && export _OLD_LD="${LD:-}"
[ -z "$_OLD_PS1" ] && export _OLD_PS1="$PS1"

# Atualiza o PATH para incluir os binários da versão selecionada
export PATH="$LLVM_DIR/bin:$PATH"

# Atualiza variáveis de compilador (CC e CXX)
export CC="$LLVM_DIR/bin/clang"
export CXX="$LLVM_DIR/bin/clang++"

# Se existir o linker lld no diretório, atualiza LD
if [ -x "$LLVM_DIR/bin/lld" ]; then
    export LD="$LLVM_DIR/bin/lld"
fi

# Altera o prompt (PS1) para indicar a versão ativa
export PS1="(LLVM: $(basename "$LLVM_DIR")) $_OLD_PS1"

# Seta variável interna para indicar que uma versão está ativa
export _ACTIVE_LLVM="$VERSAO"

echo "LLVM versão '$VERSAO' ativada para esta sessão."
echo "CC, CXX e LD foram configurados; PATH e PS1 foram atualizados."
echo "Para desativar, execute 'source deactivate_llvm.sh'."

echo "LLVM version '$VERSAO' activated for this session."
echo "CC, CXX, and LD have been set; PATH and PS1 have been updated."
echo "To deactivate, run 'source deactivate_llvm.sh'."
