# 🚀 LLVMUP: LLVM Version Manager

Um gerenciador de versões LLVM inspirado em ferramentas como **rustup**, **Python venv** e **Node Version Manager (nvm)**. O LLVMUP permite baixar, instalar, compilar a partir do código-fonte e alternar entre diferentes versões do LLVM de forma fácil e eficiente.

**⚠️ AVISO:**
Esta é uma versão de teste conceitual e pode conter bugs. Use por sua conta e risco. Contribuições e relatórios de problemas são bem-vindos!

## ✨ Recursos Principais

- 📦 **Instalação de versões pré-compiladas** do LLVM
- 🛠️ **Compilação a partir do código-fonte** com otimizações nativas
- 🔄 **Alternância rápida** entre versões instaladas
- 💻 **Integração com VSCode** automática
- 🎯 **Interface visual rica** com emojis e formatação
- ⌨️ **Auto-completar** com TAB para nomes de versões
- 📊 **Status detalhado** do ambiente ativo

## 🚀 Início Rápido

### Linux

#### 1. Instalação
```bash
# Clone o repositório
git clone https://github.com/Fabio3rs/llvm-manager.git
cd llvm-manager

# Execute o script de instalação
./install.sh

# Reinicie o terminal ou recarregue o perfil
source ~/.bashrc
```

#### 2. Instalando uma versão LLVM
```bash
# Instala a versão mais recente
llvmup

# Instala uma versão específica
llvmup 18.1.8

# Compila uma versão a partir do código-fonte
llvmup --from-source

# Instalação com saída detalhada
llvmup --verbose 19.1.0
```

#### 3. Ativando e usando uma versão
```bash
# Ativa uma versão específica
llvm-activate 18.1.8

# Verifica o status atual
llvm-status

# Lista todas as versões instaladas
llvm-list

# Obtém ajuda completa
llvm-help
```

#### 4. Integração com VSCode
```bash
# Vai para seu projeto e configura o VSCode
cd /seu/projeto
llvm-vscode-activate 18.1.8

# Recarrega a janela do VSCode para aplicar as configurações
# Ctrl+Shift+P → "Developer: Reload Window"
```

### Windows
1. Clone o repositório:
   ```powershell
   git clone https://github.com/Fabio3rs/llvm-manager.git
   cd llvm-manager
   ```

2. Abra PowerShell como Administrador e execute:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   Install-Module -Name Pester -Force -SkipPublisherCheck
   ```

3. Instale uma versão LLVM:
   ```powershell
   .\Download-Llvm.ps1
   ```

4. Ative a versão (deve ser "sourced" para modificar variáveis de ambiente):
   ```powershell
   . .\Activate-Llvm.ps1 <versão>
   ```

## 📋 Pré-requisitos

### Linux
- `curl`: Para download de arquivos
- `jq`: Para parsing de respostas JSON
- `tar`: Para extração de arquivos
- `git`: Para compilação a partir do código-fonte (opcional)
- `ninja`: Para compilação a partir do código-fonte (opcional)
- `cmake`: Para compilação a partir do código-fonte (opcional)
- `bash-completion`: Para auto-completar comandos (opcional)

### Windows
- PowerShell 5.0 ou superior
- Módulo Pester (para testes)
- Conexão com internet para downloads
- Privilégios de administrador para instalação
- Política de execução definida como RemoteSigned (pelo menos para CurrentUser)

## 🛠️ Comandos Disponíveis

### 📦 Comandos de Instalação
```bash
llvmup                      # Instala versão pré-compilada mais recente
llvmup 18.1.8              # Instala versão específica
llvmup --from-source        # Compila a partir do código-fonte
llvmup --verbose            # Mostra saída detalhada
llvmup --quiet             # Suprime saída não essencial
```

### 🔧 Gerenciamento de Ambiente
```bash
llvm-activate <versão>      # Ativa uma versão LLVM
llvm-deactivate            # Desativa a versão atual
llvm-status                # Mostra status atual detalhado
llvm-list                  # Lista versões instaladas
llvm-help                  # Mostra guia completo de uso
```

### 💻 Integração de Desenvolvimento
```bash
llvm-vscode-activate <ver>  # Configura integração com VSCode
```

### 🎯 Interface Visual Intuitiva

O LLVM Manager fornece feedback visual rico com:
- ✅ **Status de sucesso** com confirmações claras
- ❌ **Mensagens de erro** informativas
- 💡 **Dicas contextuais** para próximos passos
- 🔄 **Indicadores de progresso** durante operações
- 📊 **Informações detalhadas** sobre o ambiente ativo

## 🚀 Ferramentas Disponíveis Após Ativação

Quando você ativa uma versão LLVM, as seguintes ferramentas ficam disponíveis:

- **clang/clang++**: Compiladores C/C++
- **ld.lld**: Linker LLVM
- **lldb**: Debugger LLVM
- **clangd**: Servidor de linguagem para IDEs
- **llvm-ar**: Arquivador
- **llvm-nm**: Dumper de tabela de símbolos
- **opt**: Otimizador LLVM
- E muitas outras ferramentas LLVM!

## 📚 Fluxos de Trabalho Exemplo

### 🔄 Workflow Básico
```bash
# 1. Instalar e ativar LLVM
llvmup 18.1.8
llvm-activate 18.1.8

# 2. Verificar instalação
llvm-status
clang --version

# 3. Compilar um programa
echo '#include <stdio.h>
int main() { printf("Hello LLVM!\n"); return 0; }' > hello.c
clang hello.c -o hello
./hello
```

### 💻 Configuração para Desenvolvimento VSCode
```bash
# 1. Vá para seu projeto C/C++
cd /meu/projeto/cpp

# 2. Configure LLVM para VSCode
llvm-vscode-activate 18.1.8

# 3. Abra VSCode (as configurações são aplicadas automaticamente)
code .

# 4. Recarregue a janela VSCode
# Ctrl+Shift+P → "Developer: Reload Window"
```

### 🔀 Alternando Entre Versões
```bash
# 1. Listar versões disponíveis
llvm-list

# 2. Desativar versão atual
llvm-deactivate

# 3. Ativar outra versão
llvm-activate 19.1.0

# 4. Verificar nova versão ativa
llvm-status
```

### 🛠️ Compilação a Partir do Código-fonte
```bash
# 1. Compilar versão específica
llvmup --from-source 18.1.8

# 2. Compilação com saída detalhada
llvmup --from-source --verbose

# 3. Ativar versão compilada
llvm-activate source-llvmorg-18.1.8
```

## 🔧 Recursos Avançados

### Auto-completar com TAB
```bash
llvm-activate <TAB><TAB>     # Lista versões instaladas
llvmup --<TAB><TAB>         # Lista opções disponíveis
```

### Verificação de Status Detalhado
O comando `llvm-status` fornece informações completas sobre o ambiente ativo:

```bash
llvm-status
# ╭─ LLVM Environment Status ──────────────────────────────────╮
# │ ✅ Status: ACTIVE                                          │
# │ 📦 Version: 18.1.8                                        │
# │ 📁 Path: ~/.llvm/toolchains/18.1.8                       │
# │                                                           │
# │ 🛠️  Available tools:                                       │
# │   • clang (C compiler)                                    │
# │   • clang++ (C++ compiler)                                │
# │   • clangd (Language Server)                              │
# │   • lldb (Debugger)                                       │
# │                                                           │
# │ 💡 To deactivate: llvm-deactivate                         │
# ╰───────────────────────────────────────────────────────────╯
```

## ✨ Funcionalidades Principais

### 📦 **Download & Install (Versões Pré-compiladas)**
- Busca versões disponíveis do LLVM através da API do GitHub
- **Linux**: Download do tarball Linux X64 para a versão selecionada, extração e instalação em `~/.llvm/toolchains/<version>`
- **Windows**: Download do instalador NSIS LLVM e instalação silenciosa em `%USERPROFILE%\.llvm\toolchains\<version>`
- Marca versões já instaladas ao listar releases disponíveis

### 🛠️ **Build From Source (Linux)**
- Compilação do LLVM a partir do código-fonte usando script de build
- Clone shallow do repositório LLVM para a tag de release selecionada em `~/.llvm/sources/<tag>`
- Configuração, compilação e instalação usando Ninja em `~/.llvm/toolchains/source-<version>`
- Use o comando wrapper com flag `--from-source` para build do código-fonte

### 🔄 **Ativação de Versão**
- **Linux**: Ative uma versão específica do LLVM usando a função bash `llvm-activate <version>` (sem necessidade de sourcing manual):
  - Atualiza o `PATH` para incluir o diretório `bin` do LLVM selecionado
  - Faz backup e define `CC`, `CXX`, e `LD` para apontar para binários LLVM
  - Modifica o prompt do terminal (`PS1`) para indicar a versão ativa do LLVM
- **Windows**: Use scripts PowerShell (`Activate-Llvm.ps1`) para atualizar variáveis de ambiente
- Os scripts previnem ativação de nova versão se uma já estiver ativa até a desativação

### ❌ **Desativação de Versão**
- **Linux**: Reverte mudanças do ambiente usando função bash `llvm-deactivate`, restaurando valores originais de `PATH`, `CC`, `CXX`, `LD`, e `PS1`
- **Windows**: Use scripts PowerShell (`Deactivate-Llvm.ps1`) para restaurar variáveis de ambiente originais

### 💻 **Integração VSCode**
- **Linux**: Use `llvm-vscode-activate <version>` para mesclar configurações específicas do LLVM em `.vscode/settings.json`:
  - `cmake.additionalCompilerSearchDirs`
  - `clangd.path`
  - `clangd.fallbackFlags`
  - `cmake.configureEnvironment` (com `PATH` atualizado)
- **Windows**: Use script PowerShell para mesclar configurações no `.vscode\settings.json`
- Integração preserva configurações VSCode pré-existentes

### ⌨️ **Auto-completar de Comandos**
- **Linux**: Script de completion bash (`llvmup-completion.sh`) instalado para fornecer completion com TAB para:
  - Versões LLVM disponíveis
  - Opções de comando
  - Subcomandos
- **Funções LLVM**: Funções bash também fornecem TAB completion para versões instaladas

### 🎯 **Comando Wrapper**
- Script wrapper `llvmup` que aceita flag opcional `--from-source`
- Quando usado, chama script build-from-source; caso contrário, usa gerenciador de releases pré-compilados

### 🔧 **Integração de Perfil**
- Script de instalação configura automaticamente seu perfil shell (`.bashrc` ou `.profile`) para carregar funções LLVM
- Instalação segura: verifica se já configurado antes de adicionar entradas
- Tratamento gracioso: funções fornecem avisos ao invés de erros se scripts estiverem faltando

## 📥 Script de Instalação (install.sh)

Para facilitar o uso das ferramentas do gerenciador de versões LLVM de qualquer lugar, um script de instalação (`install.sh`) é fornecido. Este script copia os comandos do projeto para um diretório (por padrão, `$HOME/.local/bin`) que geralmente está incluído no seu PATH.

### Como Usar o Script de Instalação

1. **Execute o Instalador:**
   ```bash
   ./install.sh
   ```
   Isto irá:
   - Criar o diretório de instalação (`$HOME/.local/bin`) se não existir
   - Copiar os seguintes scripts para esse diretório:
     - `llvm-prebuilt`
     - `llvm-activate`
     - `llvm-deactivate`
     - `llvm-vscode-activate`
     - `llvm-build` (para compilação do código-fonte)
     - `llvmup` (comando wrapper)
     - `llvm-functions.sh` (funções bash)
   - Instalar script de bash completion em `$HOME/.local/share/bash-completion/completions`
   - Definir permissões executáveis apropriadas nesses scripts
   - **Configurar automaticamente seu perfil shell** (`.bashrc` ou `.profile`) para carregar as funções bash LLVM

2. **Verificar PATH:**
   O instalador verifica se `$HOME/.local/bin` está no seu PATH. Se não estiver, você receberá um aviso junto com instruções para adicioná-lo:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```
   Você pode adicionar esta linha ao arquivo de inicialização do seu shell (ex: `~/.bashrc` ou `~/.profile`) para persistência.

3. **Usando os Comandos:**
   Após a instalação, você pode executar os comandos de qualquer lugar no seu terminal:
   - Use `llvmup` para instalar versões LLVM
   - Use `llvm-activate <version>` para ativar uma versão específica
   - Use `llvm-deactivate` para reverter a ativação
   - Use `llvm-vscode-activate <version>` para configurar integração VSCode
   - Use `llvm-status` para verificar versão ativa
   - Use `llvm-list` para ver todas as versões instaladas
   - Use `llvm-help` para guia completo de uso

## 🗑️ Script de Desinstalação (uninstall.sh)

Para remoção completa do gerenciador LLVM, um script de desinstalação (`uninstall.sh`) é fornecido. Este script remove todos os componentes instalados e limpa configurações de perfil.

### Como Usar o Script de Desinstalação

1. **Execute o Desinstalador:**
   ```bash
   ./uninstall.sh
   ```
   Isto irá:
   - Remover todos os scripts do gerenciador LLVM de `$HOME/.local/bin`
   - Remover arquivos de bash completion
   - Limpar configuração do perfil shell (remove carregamento de funções LLVM de `.bashrc` ou `.profile`)
   - Fornecer instruções para limpeza manual se necessário

2. **Nota:** O desinstalador preserva suas instalações de toolchain LLVM em `~/.llvm/toolchains/`. Se quiser remover completamente todas as instalações LLVM, você pode executar manualmente:
   ```bash
   rm -rf ~/.llvm
   ```

## 🪟 Scripts Windows

Para usuários Windows, scripts PowerShell são fornecidos para gerenciar toolchains LLVM:

- **Download-Llvm.ps1**: Busca releases LLVM e instala versões Windows
- **Activate-Llvm.ps1**: Ativa versão específica LLVM no PowerShell (deve ser sourced)
- **Deactivate-Llvm.ps1**: Reverte mudanças feitas pelo Activate-Llvm.ps1
- **Activate-LlvmVsCode.ps1**: Script PowerShell para integração VSCode

## 🆕 Novos Recursos na Versão Mais Recente

### Funções Bash para Uso Simplificado
- **Sem sourcing manual**: Use `llvm-activate <version>` diretamente
- **Carregamento automático**: Funções automaticamente disponíveis em novos terminais
- **Usabilidade aprimorada**: Funções adicionais como `llvm-status`, `llvm-list`, e `llvm-help`
- **TAB completion**: Todas as funções suportam auto-completar para nomes de versões
- **Fallbacks graciosos**: Se scripts estiverem faltando, funções mostram avisos úteis

### Processo de Instalação Melhorado
- **Configuração automática de perfil**: Perfil shell configurado automaticamente durante instalação
- **Detecção inteligente**: Instalador escolhe o melhor arquivo de perfil ou cria um se necessário
- **Instalação segura**: Verifica configuração existente antes de fazer mudanças
- **Desinstalação limpa**: Desinstalador remove todos os rastros incluindo configuração de perfil

### Melhor Experiência do Usuário
- **Interface consistente**: Todas as operações usam chamadas de função simples
- **Verificação de status**: `llvm-status` mostra versão ativa atual e caminho
- **Listagem de versões**: `llvm-list` mostra versões instaladas com indicador de ativo
- **Tratamento de erros**: Melhores mensagens de erro e orientação ao usuário
- **Interface visual rica**: Feedback com emojis e formatação visual atraente

## 🤝 Contribuindo

Sinta-se à vontade para contribuir com este projeto:
1. Relatando bugs
2. Sugerindo novos recursos
3. Enviando pull requests
4. Melhorando documentação

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 🔗 Links Úteis

- [Repositório GitHub](https://github.com/Fabio3rs/llvmup)
- [LLVM Project](https://llvm.org/)
- [Documentação LLVM](https://llvm.org/docs/)
- [Clang Documentation](https://clang.llvm.org/docs/)

---

**💡 Dica**: Para obter ajuda completa sobre todos os comandos disponíveis, execute `llvm-help` após a instalação!
