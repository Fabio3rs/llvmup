# 🚀 LLVMUP: LLVM Version Manager

An LLVM version manager inspired by tools like **rustup**, **Python venv**, and **Node Version Manager (nvm)**. LLVMUP allows you to download, install, compile from source, and switch between different LLVM versions easily and efficiently.

**⚠️ WARNING:**
This is a proof-of-concept test version and may contain bugs. Use at your own risk. Contributions and bug reports are welcome!

## ✨ Key Features

- 📦 **Pre-built LLVM version installation**
- 🛠️ **Build from source** with native optimizations
- 🔄 **Fast switching** between installed versions
- 💻 **Automatic VSCode integration**
- 🎯 **Rich visual interface** with emojis and formatting
- ⌨️ **TAB auto-completion** for version names
- 📊 **Detailed status** of active environment

## 🚀 Quick Start

### Linux

#### 1. Installation
```bash
# Clone the repository
git clone https://github.com/Fabio3rs/llvmup.git
cd llvmup

# Run the installation script
./install.sh

# Restart terminal or reload profile
source ~/.bashrc
```

#### 2. Installing an LLVM version
```bash
# Install the latest version
llvmup

# Install a specific version
llvmup 18.1.8

# Build a version from source
llvmup --from-source

# Installation with verbose output
llvmup --verbose 19.1.0
```

#### 3. Activating and using a version
```bash
# Activate a specific version
llvm-activate 18.1.8

# Check current status
llvm-status

# List all installed versions
llvm-list

# Get complete help
llvm-help
```

#### 4. VSCode Integration
```bash
# Go to your project and configure VSCode
cd /your/project
llvm-vscode-activate 18.1.8

# Reload VSCode window to apply settings
# Ctrl+Shift+P → "Developer: Reload Window"
```

### Windows
1. Clone the repository:
   ```powershell
   git clone https://github.com/Fabio3rs/llvmup.git
   cd llvmup
   ```

2. Open PowerShell as Administrator and run:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   Install-Module -Name Pester -Force -SkipPublisherCheck
   ```

3. Install an LLVM version:
   ```powershell
   .\Download-Llvm.ps1
   ```

4. Activate the version (must be "sourced" to modify environment variables):
   ```powershell
   . .\Activate-Llvm.ps1 <version>
   ```

## 📋 Prerequisites

### Linux
- `curl`: For file downloads
- `jq`: For JSON response parsing
- `tar`: For file extraction
- `git`: For building from source (optional)
- `ninja`: For building from source (optional)
- `cmake`: For building from source (optional)
- `bash-completion`: For command auto-completion (optional)

### Windows
- PowerShell 5.0 or higher
- Pester module (for tests)
- Internet connection for downloads
- Administrator privileges for installation
- Execution policy set to RemoteSigned (at least for CurrentUser)

## 🛠️ Available Commands

### 📦 Installation Commands
```bash
llvmup                      # Install latest pre-built version
llvmup 18.1.8              # Install specific version
llvmup --from-source        # Build from source
llvmup --verbose            # Show detailed output
llvmup --quiet             # Suppress non-essential output
```

### 🔧 Environment Management
```bash
llvm-activate <version>      # Activate an LLVM version
llvm-deactivate            # Deactivate current version
llvm-status                # Show detailed current status
llvm-list                  # List installed versions
llvm-help                  # Show complete usage guide
```

### 💻 Development Integration
```bash
llvm-vscode-activate <ver>  # Configure VSCode integration
```

### 🎯 Intuitive Visual Interface

LLVM Manager provides rich visual feedback with:
- ✅ **Success status** with clear confirmations
- ❌ **Informative error messages**
- 💡 **Contextual hints** for next steps
- 🔄 **Progress indicators** during operations
- 📊 **Detailed information** about the active environment

## 🚀 Available Tools After Activation

When you activate an LLVM version, the following tools become available:

- **clang/clang++**: C/C++ compilers
- **ld.lld**: LLVM linker
- **lldb**: LLVM debugger
- **clangd**: Language server for IDEs
- **llvm-ar**: Archiver
- **llvm-nm**: Symbol table dumper
- **opt**: LLVM optimizer
- And many other LLVM tools!

## 📚 Example Workflows

### 🔄 Basic Workflow
```bash
# 1. Install and activate LLVM
llvmup 18.1.8
llvm-activate 18.1.8

# 2. Verify installation
llvm-status
clang --version

# 3. Compile a program
echo '#include <stdio.h>
int main() { printf("Hello LLVM!\n"); return 0; }' > hello.c
clang hello.c -o hello
./hello
```

### 💻 VSCode Development Setup
```bash
# 1. Go to your C/C++ project
cd /my/cpp/project

# 2. Configure LLVM for VSCode
llvm-vscode-activate 18.1.8

# 3. Open VSCode (settings are applied automatically)
code .

# 4. Reload VSCode window
# Ctrl+Shift+P → "Developer: Reload Window"
```

### 🔀 Switching Between Versions
```bash
# 1. List available versions
llvm-list

# 2. Deactivate current version
llvm-deactivate

# 3. Activate another version
llvm-activate 19.1.0

# 4. Check new active version
llvm-status
```

### 🛠️ Building from Source
```bash
# 1. Build specific version
llvmup --from-source 18.1.8

# 2. Build with verbose output
llvmup --from-source --verbose

# 3. Activate the built version
llvm-activate source-llvmorg-18.1.8
```

## 🔧 Advanced Features

### TAB Auto-completion
```bash
llvm-activate <TAB><TAB>     # List installed versions
llvmup --<TAB><TAB>         # List available options
```

### Detailed Status Verification
The `llvm-status` command provides complete information about the active environment:

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

## ✨ Key Functionalities

### 📦 **Download & Install (Pre-built Versions)**
- Fetches available LLVM versions through GitHub API
- **Linux**: Downloads Linux X64 tarball for selected version, extracts and installs to `~/.llvm/toolchains/<version>`
- **Windows**: Downloads LLVM NSIS installer and silently installs to `%USERPROFILE%\.llvm\toolchains\<version>`
- Marks already installed versions when listing available releases

### 🛠️ **Build From Source (Linux)**
- Compiles LLVM from source code using build script
- Shallow clone of LLVM repository for selected release tag to `~/.llvm/sources/<tag>`
- Configuration, compilation and installation using Ninja to `~/.llvm/toolchains/source-<version>`
- Use wrapper command with `--from-source` flag for source builds

### 🔄 **Version Activation**
- **Linux**: Activate a specific LLVM version using bash function `llvm-activate <version>` (no manual sourcing required):
  - Updates `PATH` to include selected LLVM's `bin` directory
  - Backs up and sets `CC`, `CXX`, and `LD` to point to LLVM binaries
  - Modifies terminal prompt (`PS1`) to indicate active LLVM version
- **Windows**: Use PowerShell scripts (`Activate-Llvm.ps1`) to update environment variables
- Scripts prevent activation of new version if one is already active until deactivation

### ❌ **Version Deactivation**
- **Linux**: Reverts environment changes using bash function `llvm-deactivate`, restoring original `PATH`, `CC`, `CXX`, `LD`, and `PS1` values
- **Windows**: Use PowerShell scripts (`Deactivate-Llvm.ps1`) to restore original environment variables

### 💻 **VSCode Integration**
- **Linux**: Use `llvm-vscode-activate <version>` to merge LLVM-specific settings into `.vscode/settings.json`:
  - `cmake.additionalCompilerSearchDirs`
  - `clangd.path`
  - `clangd.fallbackFlags`
  - `cmake.configureEnvironment` (with updated `PATH`)
- **Windows**: Use PowerShell script to merge settings into `.vscode\settings.json`
- Integration preserves pre-existing VSCode settings

### ⌨️ **Command Auto-completion**
- **Linux**: Bash completion script (`llvmup-completion.sh`) installed to provide TAB completion for:
  - Available LLVM versions
  - Command options
  - Subcommands
- **LLVM Functions**: Bash functions also provide TAB completion for installed versions

### 🎯 **Wrapper Command**
- Wrapper script `llvmup` that accepts optional `--from-source` flag
- When used, calls build-from-source script; otherwise uses pre-built release manager

### 🔧 **Profile Integration**
- Installation script automatically configures your shell profile (`.bashrc` or `.profile`) to load LLVM functions
- Safe installation: checks if already configured before adding entries
- Graceful handling: functions provide warnings instead of errors if scripts are missing

## 📥 Installation Script (install.sh)

To facilitate the use of LLVM version manager tools from anywhere, an installation script (`install.sh`) is provided. This script copies the project commands to a directory (by default, `$HOME/.local/bin`) that is typically included in your PATH.

### How to Use the Installation Script

1. **Run the Installer:**
   ```bash
   ./install.sh
   ```
   This will:
   - Create the installation directory (`$HOME/.local/bin`) if it doesn't exist
   - Copy the following scripts to that directory:
     - `llvm-prebuilt`
     - `llvm-activate`
     - `llvm-deactivate`
     - `llvm-vscode-activate`
     - `llvm-build` (for source code compilation)
     - `llvmup` (wrapper command)
     - `llvm-functions.sh` (bash functions)
   - Install bash completion script to `$HOME/.local/share/bash-completion/completions`
   - Set appropriate executable permissions on these scripts
   - **Automatically configure your shell profile** (`.bashrc` or `.profile`) to load LLVM bash functions

2. **Check PATH:**
   The installer checks if `$HOME/.local/bin` is in your PATH. If not, you'll receive a warning along with instructions to add it:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```
   You can add this line to your shell's startup file (e.g., `~/.bashrc` or `~/.profile`) for persistence.

3. **Using the Commands:**
   After installation, you can run the commands from anywhere in your terminal:
   - Use `llvmup` to install LLVM versions
   - Use `llvm-activate <version>` to activate a specific version
   - Use `llvm-deactivate` to revert activation
   - Use `llvm-vscode-activate <version>` to configure VSCode integration
   - Use `llvm-status` to check active version
   - Use `llvm-list` to see all installed versions
   - Use `llvm-help` for complete usage guide

## 🗑️ Uninstallation Script (uninstall.sh)

For complete removal of the LLVM manager, an uninstallation script (`uninstall.sh`) is provided. This script removes all installed components and cleans up profile configurations.

### How to Use the Uninstallation Script

1. **Run the Uninstaller:**
   ```bash
   ./uninstall.sh
   ```
   This will:
   - Remove all LLVM manager scripts from `$HOME/.local/bin`
   - Remove bash completion files
   - Clean up shell profile configuration (removes LLVM functions loading from `.bashrc` or `.profile`)
   - Provide instructions for manual cleanup if needed

2. **Note:** The uninstaller preserves your LLVM toolchain installations in `~/.llvm/toolchains/`. If you want to completely remove all LLVM installations, you can manually run:
   ```bash
   rm -rf ~/.llvm
   ```

## 🪟 Windows Scripts

For Windows users, PowerShell scripts are provided to manage LLVM toolchains:

- **Download-Llvm.ps1**: Fetches LLVM releases and installs Windows versions
- **Activate-Llvm.ps1**: Activates specific LLVM version in PowerShell (must be sourced)
- **Deactivate-Llvm.ps1**: Reverts changes made by Activate-Llvm.ps1
- **Activate-LlvmVsCode.ps1**: PowerShell script for VSCode integration

## 🆕 Latest Version Features

### Bash Functions for Simplified Usage
- **No manual sourcing**: Use `llvm-activate <version>` directly
- **Automatic loading**: Functions automatically available in new terminals
- **Enhanced usability**: Additional functions like `llvm-status`, `llvm-list`, and `llvm-help`
- **TAB completion**: All functions support auto-completion for version names
- **Graceful fallbacks**: If scripts are missing, functions show helpful warnings

### Improved Installation Process
- **Automatic profile configuration**: Shell profile configured automatically during installation
- **Smart detection**: Installer chooses the best profile file or creates one if needed
- **Safe installation**: Checks existing configuration before making changes
- **Clean uninstallation**: Uninstaller removes all traces including profile configuration

### Better User Experience
- **Consistent interface**: All operations use simple function calls
- **Status verification**: `llvm-status` shows current active version and path
- **Version listing**: `llvm-list` shows installed versions with active indicator
- **Error handling**: Better error messages and user guidance
- **Rich visual interface**: Feedback with emojis and attractive visual formatting

## 🤝 Contributing

Feel free to contribute to this project:
1. Reporting bugs
2. Suggesting new features
3. Submitting pull requests
4. Improving documentation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Useful Links

- [GitHub Repository](https://github.com/Fabio3rs/llvmup)
- [LLVM Project](https://llvm.org/)
- [LLVM Documentation](https://llvm.org/docs/)
- [Clang Documentation](https://clang.llvm.org/docs/)

---

**💡 Tip**: For complete help on all available commands, run `llvm-help` after installation!
