#!/bin/bash
# llvm_manager.sh: Gerencia o download e a instalação de versões do LLVM a partir da API do GitHub.
# Requer: curl, jq, tar

# Verifica se os comandos necessários estão instalados
command -v curl >/dev/null 2>&1 || { echo "The curl command is necessary, but it is not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "The jq command is necessary, but it is not installed. Aborting."; exit 1; }

# URL da API do GitHub para as releases do llvm-project
API_URL="https://api.github.com/repos/llvm/llvm-project/releases"

echo "Buscando releases..."
echo "Fetching releases..."
RELEASES=$(curl -s "$API_URL")

if [ -z "$RELEASES" ]; then
  echo "Nenhuma release encontrada ou erro ao buscar os dados."
  echo "No releases found or error fetching data."
  exit 1
fi

# Extrai as tags (versões) disponíveis
VERSOES=$(echo "$RELEASES" | jq -r '.[].tag_name')
IFS=$'\n' read -rd '' -a listaVersoes <<<"$VERSOES"

if [ ${#listaVersoes[@]} -eq 0 ]; then
  echo "Nenhuma versão encontrada."
  echo "No versions found."
  exit 1
fi

echo "Versões disponíveis:"
echo "Available versions:"
for i in "${!listaVersoes[@]}"; do
    versao="${listaVersoes[$i]}"
    INSTALLED_FLAG=""
    if [ -d "$HOME/.llvm/toolchains/$versao" ]; then
        INSTALLED_FLAG=" [installed]"
    fi
    echo "$((i+1))) $versao$INSTALLED_FLAG"
done

# Solicita que o usuário selecione uma versão
read -p "Selecione uma versão pelo número | Select a version by the Number: " escolha

if ! [[ "$escolha" =~ ^[0-9]+$ ]] || [ "$escolha" -lt 1 ] || [ "$escolha" -gt ${#listaVersoes[@]} ]; then
  echo "Seleção inválida."
  echo "Invalid selection."
  exit 1
fi

VERSAO_SELECIONADA="${listaVersoes[$((escolha-1))]}"
echo "Você selecionou: $VERSAO_SELECIONADA"
echo "You selected: $VERSAO_SELECIONADA"

# Procura o asset que contenha "Linux-X64.tar.xz" no nome para a versão selecionada
ASSET_URL=$(echo "$RELEASES" | jq -r --arg versao "$VERSAO_SELECIONADA" '
  .[] | select(.tag_name == $versao) |
  .assets[] | select(.name | test("Linux-X64.tar.xz$")) |
  .browser_download_url
')

if [ -z "$ASSET_URL" ]; then
  echo "Não foi encontrado um asset para Linux (X64) na versão $VERSAO_SELECIONADA."
  echo "No asset found for Linux (X64) in version $VERSAO_SELECIONADA."
  exit 1
fi

echo "URL para download encontrada: $ASSET_URL"
echo "Download URL found: $ASSET_URL"

# Define diretórios: uma área temporária e o diretório final de instalação
TEMP_DIR="$HOME/llvm_temp/$VERSAO_SELECIONADA"
mkdir -p "$TEMP_DIR"

ARQUIVO_DESTINO="$TEMP_DIR/$(basename "$ASSET_URL")"
echo "Baixando o asset..."
echo "Downloading the asset..."
curl -L "$ASSET_URL" -o "$ARQUIVO_DESTINO"

echo "Download concluído: $ARQUIVO_DESTINO"
echo "Extraindo o arquivo..."
echo "Extracting the file..."
tar -xvf "$ARQUIVO_DESTINO" -C "$TEMP_DIR"

# Identifica a pasta extraída (supondo que o tarball contenha uma única pasta principal)
EXTRACTED_DIR=$(tar -tf "$ARQUIVO_DESTINO" | head -1 | cut -d/ -f1)
echo "Pasta extraída: $EXTRACTED_DIR"
echo "Extracted directory: $EXTRACTED_DIR"

# Define a pasta final de instalação (usada pelo script de ativação)
LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"
TARGET_DIR="$LLVM_TOOLCHAINS_DIR/$VERSAO_SELECIONADA"
mkdir -p "$LLVM_TOOLCHAINS_DIR"

# Move a pasta extraída para o diretório final
mv "$TEMP_DIR/$EXTRACTED_DIR" "$TARGET_DIR"

echo "LLVM $VERSAO_SELECIONADA instalado em $TARGET_DIR."
echo "LLVM $VERSAO_SELECIONADA installed in $TARGET_DIR."

# Limpa os arquivos temporários
rm -rf "$TEMP_DIR"

echo "Execute 'source activate_llvm.sh $VERSAO_SELECIONADA' para ativar a versão instalada."
echo "Run 'source activate_llvm.sh $VERSAO_SELECIONADA' to activate the installed version."

