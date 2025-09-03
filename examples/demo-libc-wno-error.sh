#!/bin/bash
# demo-libc-wno-error.sh - Demonstração da funcionalidade LIBC_WNO_ERROR

echo "🔧 Demonstração: Controle da Flag LIBC_WNO_ERROR"
echo "================================================="
echo

# Configurar modo de teste
export LLVM_TEST_MODE=1
export LLVM_TEST_VERSION="llvmorg-18.1.8"

echo "1️⃣  Comportamento padrão (flag habilitada):"
echo "-------------------------------------------"
echo "Comando: llvm-build --verbose llvmorg-18.1.8"
echo
./llvm-build --verbose llvmorg-18.1.8 2>&1 | grep -E "(LIBC_WNO_ERROR|Added.*flag)"
echo

echo "2️⃣  Desabilitando via linha de comando:"
echo "--------------------------------------"
echo "Comando: llvm-build --verbose --disable-libc-wno-error llvmorg-18.1.8"
echo
./llvm-build --verbose --disable-libc-wno-error llvmorg-18.1.8 2>&1 | grep -E "(LIBC_WNO_ERROR|Skipped.*flag)"
echo

echo "3️⃣  Desabilitando via arquivo de configuração:"
echo "----------------------------------------------"
echo "Criando .llvmup-config com disable_libc_wno_error = true"

cat > .llvmup-config.demo << 'EOF'
[build]
name = "demo-build"
disable_libc_wno_error = true
EOF

echo "Conteúdo do arquivo:"
cat .llvmup-config.demo
echo

mv .llvmup-config.demo .llvmup-config
echo "Comando: llvm-build --verbose llvmorg-18.1.8"
echo
./llvm-build --verbose llvmorg-18.1.8 2>&1 | grep -E "(LIBC_WNO_ERROR|Config:|Skipped.*flag)"
echo

echo "4️⃣  Linha de comando sobrescreve configuração:"
echo "---------------------------------------------"
echo "Com arquivo de configuração disable_libc_wno_error = true"
echo "Comando: llvm-build --verbose (sem --disable-libc-wno-error)"
echo
./llvm-build --verbose llvmorg-18.1.8 2>&1 | grep -E "(LIBC_WNO_ERROR|Config:|Skipped.*flag)"
echo

# Limpar
rm -f .llvmup-config

echo "✅ Demonstração completa!"
echo
echo "📖 Resumo:"
echo "- Por padrão, LIBC_WNO_ERROR=ON é adicionada aos argumentos CMake"
echo "- Use --disable-libc-wno-error para desabilitar via linha de comando"
echo "- Use disable_libc_wno_error = true no .llvmup-config para desabilitar via arquivo"
echo "- A linha de comando sempre tem prioridade sobre o arquivo de configuração"
echo
echo "🔗 Consulte docs/BUILD_EXAMPLE.md para mais detalhes!"
