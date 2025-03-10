#!/bin/bash
# deactivate_llvm.sh: Restaura as variáveis de ambiente alteradas pelo activate_llvm.sh.

if [ -n "$_ACTIVE_LLVM" ]; then
    # Restaura o PATH removendo a entrada do LLVM ativo
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${LLVM_DIR}/bin\$" | paste -sd ":" -)

    # Restaura CC e CXX
    [ -n "$_OLD_CC" ] && export CC="$_OLD_CC" || unset CC
    [ -n "$_OLD_CXX" ] && export CXX="$_OLD_CXX" || unset CXX

    # Restaura LD
    [ -n "$_OLD_LD" ] && export LD="$_OLD_LD" || unset LD

    # Restaura o prompt original (PS1)
    [ -n "$_OLD_PS1" ] && export PS1="$_OLD_PS1"

    # Remove variáveis de backup e de controle
    unset _ACTIVE_LLVM
    unset _OLD_PATH
    unset _OLD_CC
    unset _OLD_CXX
    unset _OLD_LD
    unset _OLD_PS1
    unset LLVM_DIR

    echo "LLVM desativado para esta sessão."
    echo "LLVM deactivated for this session."
else
    echo "Nenhuma versão do LLVM está ativa nesta sessão."
    echo "No LLVM version is active in this session."
fi
