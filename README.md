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
- ⌨️ **Enhanced TAB auto-completion** with remote version fetching
- 🌐 **Smart caching system** (24h intelligent cache with 99% speed improvement)
- 📊 **Detailed status** of active environment
- ⚙️ **Project-specific configuration** via `.llvmup-config` files
- 🏗️ **Customizable build profiles** (minimal, full, custom)
- 🔧 **CMake flags support** for advanced builds
- 🎯 **Default version management** with symlinks
- 📋 **Component selection** for targeted installations
- 🪟 **Windows PowerShell parity** with equivalent scripts
- 🔁 **Subcommand structure** (install, config, default)
- 📝 **Custom installation naming** for multiple variants
- 🧪 **Comprehensive test suite** with 24 automated tests
- 🔄 **LIBC_WNO_ERROR control** for compatibility with different systems
- ♻️ **CMake reconfiguration** with `--reconfigure` flag for clean rebuilds
- 🎨 **Enhanced logging system** with verbose/quiet mode controls

## 🆕 Latest Enhancements (v3.0)

### 🔧 **Enhanced Build & Configuration System**
- **LIBC_WNO_ERROR Control**: Fine-grained control over compatibility flags
- **CMake Reconfiguration**: Force clean rebuilds with `--reconfigure`
- **Separated Config Functions**: Load, Apply, and Activate workflows
- **CMake Presets**: Built-in Debug, Release, RelWithDebInfo, MinSizeRel presets
- **Auto Version Detection**: Intelligent detection of installed versions

### 🎨 **Improved User Experience**
- **Enhanced Logging**: Intelligent verbosity with specialized log functions
- **Clean Output**: Reduced "noise" with verbose/quiet mode controls
- **Better Error Handling**: Clear error messages and recovery suggestions
- **Variable Trimming**: Robust config parsing with proper whitespace handling

### 🪟 **Complete Windows Parity**
- **Unified PowerShell Script**: `Install-Llvm.ps1` with all bash features
- **Enhanced Logging**: Same intelligent logging system in PowerShell
- **Full Config Support**: Complete config management with load/apply/activate
- **Force Reconfiguration**: `-Reconfigure` parameter for clean rebuilds

## 🆕 Previous Enhancements (v2.0)

### 🚀 Enhanced Auto-Completion System
- **Remote Version Fetching**: Automatically fetches latest LLVM versions from GitHub API
- **Intelligent Caching**: 24-hour cache system with 99% performance improvement
- **Context-Aware Completion**: Differentiates between prebuilt (⚡) and source (📦) installations
- **Smart Filtering**: Filters suggestions based on current context and input

### 🏗️ Improved Project Structure
- **Organized Documentation**: All docs moved to `docs/` directory with cross-references
- **Example Scripts**: Interactive demos and tests in `examples/` directory
- **Comprehensive Testing**: Full test suite with unit and integration tests

## 🚀 Latest Features (v3.0)

### 🔧 **Enhanced Build System**
- **LIBC_WNO_ERROR Control**: `--disable-libc-wno-error` flag for system compatibility
- **CMake Reconfiguration**: `--reconfigure` flag for clean rebuilds
- **Improved Logging**: Verbose/quiet mode controls with specialized log functions
- **Enhanced Config System**: Separated load/apply/activate functions for better workflow

### ⚙️ **Advanced Configuration Management**
- **Config Subcommands**: `config load`, `config apply`, `config activate` for better separation of concerns
- **CMake Presets**: Built-in presets (Debug, Release, RelWithDebInfo, MinSizeRel)
- **Auto Version Detection**: Automatic detection of installed versions during config init
- **Variable Trimming**: Robust parsing with whitespace and quote handling

### 🪟 **Windows PowerShell Enhancements**
- **Complete Parity**: All bash features now available in PowerShell
- **Enhanced Logging**: Same intelligent logging system as bash version
- **Force Reconfiguration**: `-Reconfigure` switch for PowerShell builds
- **Config Management**: Full config system with load/apply/activate functions

## 🚀 Quick Start

### Linux

#### 1. Installation

##### One line standard installation
```bash
git clone https://github.com/Fabio3rs/llvmup.git && cd llvmup && ./install.sh && source ~/.bashrc
```

##### Standard Installation
```bash
# Clone the repository
git clone https://github.com/Fabio3rs/llvmup.git
cd llvmup

# Run the installation script
./install.sh

# Restart terminal or reload profile
source ~/.bashrc
```

##### Custom Installation Paths
```bash
# Install to custom location
LLVMUP_PREFIX=/opt/llvmup ./install.sh

# System-wide installation (requires sudo)
LLVMUP_SYSTEM_INSTALL=1 ./install.sh

# User installation with custom directory
LLVMUP_INSTALL_DIR=$HOME/bin ./install.sh

# Interactive installation helper
./install-examples.sh
```

For advanced installation options and troubleshooting, see [INSTALL.md](INSTALL.md).

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
   # Pre-built installation
   .\Download-Llvm.ps1

   # From source with advanced options
   .\Install-Llvm.ps1 install -FromSource -Profile minimal -Reconfigure -Verbose

   # Using project configuration
   .\Install-Llvm.ps1 config init
   .\Install-Llvm.ps1 config apply
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

# Enhanced build options (from source)
llvmup install --from-source --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" 18.1.8
llvmup install --from-source --profile minimal --name "llvm-18-min" 18.1.8
llvmup install --from-source --component clang --component lld 18.1.8
llvmup install --from-source --disable-libc-wno-error 18.1.8  # Disable LIBC_WNO_ERROR flag
llvmup install --from-source --reconfigure 18.1.8            # Force CMake reconfiguration
llvmup install --from-source --default 18.1.8               # Set as default after build
llvmup install --from-source --verbose 18.1.8               # Show verbose output
```

### 🔧 Environment Management
```bash
llvm-activate <version>      # Activate an LLVM version
llvm-deactivate            # Deactivate current version
llvm-status                # Show detailed current status
llvm-list                  # List installed versions
llvm-help                  # Show complete usage guide
```

### ⚙️ Configuration Management
```bash
llvmup config init         # Create .llvmup-config file
llvmup config load         # Load and display config
llvmup config apply        # Install using config settings
llvmup config activate     # Activate existing installation from config
llvm-config-init           # Initialize config (function)
llvm-config-load           # Load config (function)
llvm-config-apply          # Apply config (function)
llvm-config-activate       # Activate config (function)
```

### 🎯 Default Version Management
```bash
llvmup default set <version>  # Set default LLVM version
llvmup default show           # Show current default version
```

### 💻 Development Integration
```bash
llvm-vscode-activate <ver>  # Configure VSCode integration
```

### 🏗️ Build Profiles
- **minimal**: Only `clang` and `lld` (fastest build)
- **full**: All available LLVM projects (comprehensive)
- **custom**: User-defined components via config or flags

## ⚙️ Installation Configuration

LLVMUP supports flexible installation paths through environment variables:

### Environment Variables
```bash
# Installation prefix (default: ~/.local)
LLVMUP_PREFIX=/opt/llvmup

# Specific installation directory (overrides PREFIX)
LLVMUP_INSTALL_DIR=$HOME/bin

# Shell completion directory
LLVMUP_COMPLETION_DIR=/usr/share/bash-completion/completions

# System-wide installation (requires sudo)
LLVMUP_SYSTEM_INSTALL=1
```

### Installation Examples
```bash
# User installation (default)
./install.sh

# Custom user location
LLVMUP_PREFIX=$HOME/tools ./install.sh

# System-wide installation
sudo LLVMUP_SYSTEM_INSTALL=1 ./install.sh

# Custom installation directory
LLVMUP_INSTALL_DIR=/usr/local/bin ./install.sh
```

### Interactive Helper
Use the interactive installation helper for guided setup:
```bash
./install-examples.sh
```

For complete installation documentation, see [INSTALL.md](INSTALL.md).

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

### 🛠️ Building from Source with Custom Options
```bash
# 1. Basic build from source
llvmup install --from-source 18.1.8

# 2. Minimal build (faster)
llvmup install --from-source --profile minimal 18.1.8

# 3. Custom build with specific flags
llvmup install --from-source --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" --name "llvm-18-debug" 18.1.8

# 4. Build specific components only
llvmup install --from-source --component clang --component lld 18.1.8

# 5. Build and set as default
llvmup install --from-source --profile full --default 18.1.8
```

### ⚙️ Project Configuration Workflow
```bash
# 1. Initialize configuration in project
cd /my/cpp/project
llvmup config init

# 2. Edit .llvmup-config file as needed
# Configure build settings, profiles, cmake flags, etc.

# 3. Install and activate based on config
llvmup config load

# 4. Verify installation
llvm-status
```

### 🎯 Default Version Management
```bash
# 1. Set a version as system default
llvmup default set 18.1.8

# 2. Check current default
llvmup default show

# 3. Use default in new terminals (automatic)
# New terminals will have the default version available
```

## 🔧 Advanced Features

### 📋 Project Configuration Files
LLVMUP supports project-specific configuration through `.llvmup-config` files:

```ini
# .llvmup-config - LLVM project configuration

[version]
default = "llvmorg-18.1.8"

[build]
name = "my-custom-llvm"
cmake_flags = [
  "-DCMAKE_BUILD_TYPE=Debug",
  "-DCMAKE_CXX_STANDARD=17"
]
disable_libc_wno_error = false

[profile]
type = "minimal"  # or "full", "custom"

[components]
include = ["clang", "lld", "lldb"]

[project]
auto_activate = true
cmake_preset = "Debug"  # Debug, Release, RelWithDebInfo, MinSizeRel
```

### 🏗️ Build Customization Options

#### CMake Flags Support
```bash
# Single flag
llvmup install --from-source --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" 18.1.8

# Multiple flags
llvmup install --from-source \
  --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" \
  --cmake-flags "-DCMAKE_CXX_STANDARD=17" \
  18.1.8
```

#### Build Profiles
- **minimal**: `clang;lld` - Essential compiler and linker only
- **full**: `all` - All available LLVM projects (automatic version-aware)
- **custom**: User-defined via `--component` flags or config file

#### Component Selection
```bash
# Install specific components
llvmup install --from-source --component clang --component lld --component lldb 18.1.8
```

#### Advanced Build Options
```bash
# Disable LIBC_WNO_ERROR flag for compatibility
llvmup install --from-source --disable-libc-wno-error 18.1.8

# Force CMake reconfiguration (clean rebuild)
llvmup install --from-source --reconfigure 18.1.8

# Combine multiple options
llvmup install --from-source \
  --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" \
  --profile minimal \
  --name "llvm-18-debug-min" \
  --reconfigure \
  --verbose \
  18.1.8
```

### 🎯 Default Version System
LLVMUP can manage system-wide default versions:

```bash
# Set default (creates symlinks)
llvmup default set 18.1.8

# Check current default
llvmup default show

# New terminals automatically have default available
```

### 🪟 Windows PowerShell Support
Enhanced Windows support with equivalent PowerShell scripts:

```powershell
# Configuration management
.\Llvm-Config.ps1 -Command init
.\Llvm-Config.ps1 -Command load

# Default version management
.\Llvm-Default.ps1 -Command set -Version "18.1.8"
.\Llvm-Default.ps1 -Command show

# Enhanced downloads with build options
.\Download-Llvm.ps1 -CMakeFlags "-DCMAKE_BUILD_TYPE=Debug" -Name "llvm-18-debug" -Profile minimal
```

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

### 🛠️ **Enhanced Build From Source**
- **Subcommand structure**: `llvmup install --from-source` with advanced options
- **Build profiles**: minimal (clang+lld), full (all projects), custom (user-defined)
- **CMake flags support**: `--cmake-flags` for custom build configuration
- **Component selection**: `--component` for specific LLVM projects
- **Custom naming**: `--name` for multiple build variants
- **Auto-default**: `--default` to set as system default after build
- **Version-aware builds**: Automatic handling of LLVM project changes across versions
- Shallow clone of LLVM repository for selected release tag to `~/.llvm/sources/<tag>`
- Configuration, compilation and installation using Ninja to `~/.llvm/toolchains/<name>`

### ⚙️ **Project Configuration System**
- **Configuration files**: `.llvmup-config` with INI-style format
- **Array support**: cmake_flags and components as arrays
- **Subcommands**: `llvmup config init`, `llvmup config load`, and `llvmup config activate`
- **Profile integration**: Automatic profile selection from config
- **Override capability**: Command line options override config file settings

### � **Enhanced Logging System**
- **Intelligent verbosity**: Logs only appear in verbose mode or test mode
- **Error handling**: Errors always shown, informational logs controlled
- **Specialized functions**: `log_verbose`, `log_info`, `log_error`, `log_config`, etc.
- **Visual feedback**: Rich emoji-based status indicators
- **Clean output**: Reduces "noise" during normal operations
- **Subcommands**: `llvmup default set <version>` and `llvmup default show`
- **Symbolic links**: Automatic creation of default version links
- **Cross-platform**: Linux symlinks, Windows junction points
- **Shell integration**: New terminals automatically have access to default version

### 🔄 **Version Activation**
- **Linux**: Activate a specific LLVM version using bash function `llvm-activate <version>` (no manual sourcing required):
  - Updates `PATH` to include selected LLVM's `bin` directory
  - Backs up and sets `CC`, `CXX`, and `LD` to point to LLVM binaries
  - Modifies terminal prompt (`PS1`) to indicate active LLVM version
- **Windows**: Use PowerShell scripts with enhanced parameter support
- Scripts prevent activation of new version if one is already active until deactivation

### ❌ **Version Deactivation**
- **Linux**: Reverts environment changes using bash function `llvm-deactivate`, restoring original `PATH`, `CC`, `CXX`, `LD`, and `PS1` values
- **Windows**: Use PowerShell scripts to restore original environment variables

### 💻 **Enhanced VSCode Integration**
- **Linux**: Use `llvm-vscode-activate <version>` to merge LLVM-specific settings into `.vscode/settings.json`:
  - `cmake.additionalCompilerSearchDirs`
  - `clangd.path`
  - `clangd.fallbackFlags`
  - `cmake.configureEnvironment` (with updated `PATH`)
  - `cmake.debuggerPath` and debugger environment
- **Windows**: Use PowerShell script with equivalent functionality
- Integration preserves pre-existing VSCode settings

### ⌨️ **Command Auto-completion**
- **Linux**: Enhanced bash completion script for:
  - Available LLVM versions
  - Subcommands (install, config, default)
  - All command options and flags
  - Installed versions for activation
- **Function completion**: All LLVM functions support TAB completion

### 🪟 **Windows PowerShell Parity**
- **Install-Llvm.ps1**: Complete installation management with all build options
  - Configuration management (`config init`, `config load`, `config apply`, `config activate`)
  - Enhanced build options (`-DisableLibcWnoError`, `-Reconfigure`, `-Verbose`)
  - Default version management (`default set`, `default show`)
- **Enhanced logging**: Same intelligent logging system as bash version
- **Parameter validation**: PowerShell parameter sets and validation
- **Junction links**: Windows-specific default version management
- **Auto version detection**: Detects existing installations during config init

### 🎯 **Enhanced Wrapper System**
- **Subcommand structure**: `llvmup <command> [options]` format
- **Commands**: install (default), config, default
- **Backward compatibility**: Original `llvmup --from-source` still works
- **Enhanced options**: All new build customization features
- **Intelligent routing**: Commands route to appropriate scripts/functions

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

## 🗑️ Uninstallation

For complete removal of the LLVM manager, an uninstallation script (`uninstall.sh`) is provided. This script removes all installed components and cleans up profile configurations.

### Standard Uninstallation
```bash
./uninstall.sh
```

### Custom Uninstallation
If you used custom installation paths, use the same environment variables:
```bash
# Uninstall from custom prefix
LLVMUP_PREFIX=/opt/llvmup ./uninstall.sh

# System-wide uninstallation (requires sudo)
sudo LLVMUP_SYSTEM_INSTALL=1 ./uninstall.sh

# Custom installation directory
LLVMUP_INSTALL_DIR=/usr/local/bin ./uninstall.sh
```

### What Gets Removed
The uninstaller will:
- Remove all LLVM manager scripts from the installation directory
- Remove bash completion files
- Clean up shell profile configuration (with backup)
- Provide instructions for manual cleanup if needed

**Note:** The uninstaller preserves your LLVM toolchain installations in `~/.llvm/toolchains/`. To completely remove all LLVM installations:
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

## � Project Organization

### 📁 Directory Structure
```
llvmup/
├── 📖 docs/              # Complete documentation
├── 🎯 examples/          # Demos and test scripts
├── 🧪 tests/             # Automated test suite
├── 🛠️ scripts/          # Development utilities
└── 🔧 Core scripts       # Main functionality
```

### 📖 Documentation (`docs/`)
- **[INSTALL.md](docs/INSTALL.md)**: Complete installation guide
- **[FEATURE_SUMMARY.md](docs/FEATURE_SUMMARY.md)**: All features overview
- **[COMPLETION_UX_REPORT.md](docs/COMPLETION_UX_REPORT.md)**: Auto-completion system
- **[BUILD_EXAMPLE.md](docs/BUILD_EXAMPLE.md)**: Build system examples
- **[test-powershell-features.md](docs/test-powershell-features.md)**: PowerShell feature documentation

### 🎯 Examples & Demos (`examples/`)
- **Demo scripts**: Interactive completion and feature demonstrations
- **Test scripts**: Real activation and compatibility testing
- **Config examples**: Sample configuration files with LIBC_WNO_ERROR control
- **[examples/demo-libc-wno-error.sh](examples/demo-libc-wno-error.sh)**: LIBC warning flag demonstration
- **[examples/README.md](examples/README.md)**: Detailed examples guide

### 🧪 Testing (`tests/`)
- **Unit tests**: 24+ comprehensive automated tests (BATS framework)
- **Integration tests**: Full workflow validation and cross-platform compatibility
- **PowerShell tests**: Windows-specific functionality validation
- **LIBC_WNO_ERROR tests**: Warning flag control system validation
- **Performance tests**: Speed and efficiency benchmarks

## �🔗 Useful Links

- [GitHub Repository](https://github.com/Fabio3rs/llvmup)
- [LLVM Project](https://llvm.org/)
- [LLVM Documentation](https://llvm.org/docs/)
- [Clang Documentation](https://clang.llvm.org/docs/)

---

## 📊 Project Status

**✅ v3.0 - Complete Feature Set**
- Cross-platform parity (Linux + Windows PowerShell)
- Enhanced logging with specialized functions
- LIBC_WNO_ERROR flag control system
- CMake force reconfiguration capability
- Comprehensive test coverage (24+ tests)
- Complete documentation in `docs/` folder

---

**💡 Tip**: For complete help on all available commands, run `llvm-help` after installation!
