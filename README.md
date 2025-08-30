# LLVMUP: LLVM Version Manager (Concept Test)

This project is a minimal viable test software inspired by tools like **rustup**, **Python venv**, and **Node Version Manager (nvm)**. It demonstrates a concept for managing multiple LLVM versions by downloading, extracting, and switching between different LLVM releases. Additionally, it provides an option to build LLVM from source.

**WARNING:**
This is a concept test version and may contain bugs. Use it at your own risk and feel free to contribute improvements or report issues.

## Quick Start

### Linux
1. Clone this repository:
   ```bash
   git clone https://github.com/Fabio3rs/llvm-manager.git
   cd llvm-manager
   ```

2. Run the installation script:
   ```bash
   ./install.sh
   ```

3. Install an LLVM version:
   ```bash
   llvmup
   ```

4. Activate the version (the functions are automatically loaded in new terminals):
   ```bash
   llvm-activate <version>
   ```

### Windows
1. Clone this repository:
   ```powershell
   git clone https://github.com/Fabio3rs/llvm-manager.git
   cd llvm-manager
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

4. Activate the version (must be sourced to modify environment variables):
   ```powershell
   . .\Activate-Llvm.ps1 <version>
   ```

## Prerequisites

### Linux
- `curl`: For downloading files
- `jq`: For parsing JSON responses
- `tar`: For extracting archives
- `git`: For building from source (optional)
- `ninja`: For building from source (optional)
- `cmake`: For building from source (optional)
- `bash-completion`: For command completion (optional)

### Windows
- PowerShell 5.0 or later
- Pester module (for testing)
- Internet connection for downloading releases
- Administrator privileges for installation
- Execution policy set to RemoteSigned (at least for CurrentUser)

## Features

- **Download & Install (Pre-built Releases):**
  - Fetch available LLVM releases from the GitHub API.
  - **Linux:** Download the Linux X64 tarball for the selected version, extract it (which creates a directory with the release name), and move it to the designated toolchains directory (`~/.llvm/toolchains/<version>`).
  - **Windows:** Download the LLVM NSIS installer for the selected release and perform a silent installation into `%USERPROFILE%\.llvm\toolchains\<version>`.
  - Marks already installed versions when listing available releases.

- **Build From Source (Linux):**
  - Alternatively, build LLVM from source using the provided build script.
  - The build script shallowly clones the LLVM repository for the selected release tag into `~/.llvm/sources/<tag>`, then configures, builds, and installs LLVM (using Ninja) to a directory under `~/.llvm/toolchains/source-<version>`.
  - Use the wrapper command with the `--from-source` flag to trigger a source build.

- **Version Activation:**
  - **Linux:** Activate a specific LLVM version for the current terminal session using the `llvm-activate <version>` bash function (no need for manual sourcing):
    - Updates the `PATH` to include the selected LLVM's `bin` directory.
    - Backs up and then sets `CC`, `CXX`, and `LD` (if available) to point to the LLVM binaries.
    - Modifies the terminal prompt (`PS1`) to indicate the active LLVM version.
  - **Windows:** Use PowerShell scripts (`Activate-Llvm.ps1`) to update environment variables (`PATH`, `CC`, and `CXX`) and modify the PowerShell prompt to indicate the active LLVM version.
  - The scripts prevent activating a new version if one is already active until deactivation.

- **Version Deactivation:**
  - **Linux:** Revert the environment changes made during activation using the `llvm-deactivate` bash function, which restores the original values of `PATH`, `CC`, `CXX`, `LD`, and `PS1`.
  - **Windows:** Use PowerShell scripts (`Deactivate-Llvm.ps1`) to restore the original environment variables and prompt.

- **VSCode Integration:**
  - **Linux:** Use the `llvm-vscode-activate <version>` bash function to merge LLVM-specific settings into your `.vscode/settings.json` file. This configures:
    - `cmake.additionalCompilerSearchDirs`
    - `clangd.path`
    - `clangd.fallbackFlags`
    - `cmake.configureEnvironment` (with an updated `PATH`)
  - **Windows:** Use the PowerShell script (`Activate-LlvmVsCode.ps1`) to merge LLVM configuration settings into your `.vscode\settings.json` file. This script sets:
    - `cmake.additionalCompilerSearchDirs` to point to the LLVM `bin` directory.
    - `clangd.path` to the LLVM `clangd.exe` executable.
    - `clangd.fallbackFlags` to include the proper LLVM include paths.
    - `cmake.configureEnvironment` with the updated `PATH` (prepending the LLVM `bin` directory).
  - In both cases, the integration script merges settings so that any pre-existing VSCode settings are preserved.

- **Command Completion:**
  - **Linux:** Bash completion script (`llvmup-completion.sh`) is installed to provide tab completion for:
    - Available LLVM versions
    - Command options
    - Subcommands
  - **LLVM Functions:** The bash functions also provide tab completion for installed LLVM versions.

- **Wrapper Command:**
  - A wrapper script called `llvmup` is provided that accepts an optional `--from-source` flag. When used, it calls the build-from-source script; otherwise, it uses the pre-built release manager.

- **Profile Integration:**
  - The installation script automatically configures your shell profile (`.bashrc` or `.profile`) to load LLVM functions
  - Safe installation: checks if already configured before adding entries
  - Graceful handling: functions provide warnings instead of errors if scripts are missing

## Installation Script (install.sh)

To make it easier to call the LLVM version manager tools from anywhere, an installation script (`install.sh`) is provided. This script copies the project's commands to a directory (by default, `$HOME/.local/bin`) that is typically included in your PATH.

## Uninstallation Script (uninstall.sh)

For complete removal of the LLVM manager, an uninstallation script (`uninstall.sh`) is provided. This script removes all installed components and cleans up profile configurations.

### How to Use the Uninstallation Script

1. **Run the Uninstaller:**
   ```bash
   ./uninstall.sh
   ```
   This will:
   - Remove all LLVM manager scripts from `$HOME/.local/bin`
   - Remove bash completion files
   - Clean up shell profile configuration (removes LLVM function loading from `.bashrc` or `.profile`)
   - Provide instructions for manual cleanup if needed

2. **Note:** The uninstaller preserves your LLVM toolchain installations in `~/.llvm/toolchains/`. If you want to completely remove all LLVM installations, you can manually run:
   ```bash
   rm -rf ~/.llvm
   ```

### How to Use the Installation Script

1. **Run the Installer:**
   ```bash
   ./install.sh
   ```
   This will:
   - Create the installation directory (`$HOME/.local/bin`) if it doesn't exist.
   - Copy the following scripts into that directory:
     - `llvm-prebuilt`
     - `llvm-activate`
     - `llvm-deactivate`
     - `llvm-vscode-activate`
     - `llvm-build` (for building from source)
     - `llvmup` (wrapper command)
     - `llvm-functions.sh` (bash functions)
   - Install bash completion script to `$HOME/.local/share/bash-completion/completions`
   - Set the appropriate executable permissions on these scripts.
   - **Automatically configure your shell profile** (`.bashrc` or `.profile`) to load the LLVM bash functions.

2. **Verify PATH:**
   The installer checks if `$HOME/.local/bin` is in your PATH. If it isn't, you'll receive a warning along with instructions to add it:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```
   You may add this line to your shell's startup file (e.g., `~/.bashrc` or `~/.profile`) for persistence.

3. **Using the Commands:**
   After installation, you can run the commands from anywhere in your terminal:
   - Use `llvm-prebuilt` to download and install pre-built LLVM versions.
   - Use `llvmup` to choose between a pre-built installation or a build-from-source:
     - To install a pre-built release:
       ```bash
       llvmup [additional arguments...]
       ```
     - To build from source:
       ```bash
       llvmup --from-source [additional arguments...]
       ```
   - Use `llvm-activate <version>` to activate a specific LLVM version (bash function - no manual sourcing needed).
   - Use `llvm-deactivate` to revert the activation (bash function).
   - Use `llvm-vscode-activate <version>` to update your VSCode workspace settings with the selected LLVM configuration (bash function).
   - Use `llvm-status` to check which LLVM version is currently active (bash function).
   - Use `llvm-list` to see all installed LLVM versions (bash function).

## Windows Scripts

For Windows users, PowerShell scripts are provided to manage the LLVM toolchains:

- **Download-Llvm.ps1:**
  - Fetches available LLVM releases from the GitHub API.
  - Allows you to select a release.
  - Downloads the Windows 64-bit NSIS installer for the selected release.
  - Runs the installer in silent mode, installing the LLVM toolchain into `%USERPROFILE%\.llvm\toolchains\<version>`.

- **Activate-Llvm.ps1:**
  - A PowerShell script that **must be sourced** to modify the current session's environment.
  - Activates a specific LLVM version in a PowerShell session.
  - Updates environment variables (`PATH`, `CC`, and `CXX`) and modifies the PowerShell prompt.
  - Checks if another LLVM version is already active and prevents reactivation until the current one is deactivated.
  - Usage: `. .\Activate-Llvm.ps1 <version>`

- **Deactivate-Llvm.ps1:**
  - A PowerShell script that **must be sourced** to modify the current session's environment.
  - Reverts the changes made by `Activate-Llvm.ps1`.
  - Restores the original environment variables and PowerShell prompt.
  - Usage: `. .\Deactivate-Llvm.ps1`

- **Activate-LlvmVsCode.ps1:**
  - PowerShell script for VSCode integration.
  - Updates Windows-specific VSCode settings.

## Files

- **llvm-prebuilt (Linux):**
  - Interacts with the GitHub API to list available LLVM releases.
  - Allows you to choose a version for download and installation.
  - Downloads, extracts, and installs the selected LLVM release into `~/.llvm/toolchains/<version>`.

- **llvm-build (Linux):**
  - Implements a build-from-source workflow.
  - Shallow clones the LLVM project at the selected release into `~/.llvm/sources/<tag>`.
  - Configures, builds, and installs LLVM (using Ninja) to `~/.llvm/toolchains/source-<version>`.

- **llvmup (Linux):**
  - A wrapper script that accepts an optional `--from-source` flag.
  - If `--from-source` is passed, it calls the build-from-source script.
  - Otherwise, it calls the pre-built release manager (`llvm-prebuilt`).

- **llvm-activate (Linux):**
  - A script that **must be sourced** to modify the current shell's environment.
  - Activates a specific LLVM version for the current shell session.
  - Updates environment variables and modifies the shell prompt.
  - Prevents multiple activations until deactivation.
  - Usage: `source llvm-activate <version>` or use the `llvm-activate <version>` bash function

- **llvm-deactivate (Linux):**
  - A script that **must be sourced** to modify the current shell's environment.
  - Reverts the changes made by `llvm-activate`.
  - Restores the original environment variables and shell prompt.
  - Usage: `source llvm-deactivate` or use the `llvm-deactivate` bash function

- **llvm-vscode-activate (Linux):**
  - Updates VSCode workspace settings for LLVM integration.
  - Configures compiler paths, clangd settings, and environment variables.
  - Usage: Direct execution or use the `llvm-vscode-activate <version>` bash function

- **llvm-functions.sh (Linux):**
  - Provides convenient bash functions for LLVM management.
  - Automatically loaded in new terminal sessions after installation.
  - Functions include: `llvm-activate`, `llvm-deactivate`, `llvm-vscode-activate`, `llvm-status`, `llvm-list`.
  - Includes tab completion for version names.
  - Graceful error handling with fallbacks.

- **llvmup-completion.sh (Linux):**
  - Provides bash completion for llvmup commands.
  - Supports completion of versions, options, and subcommands.

- **Download-Llvm.ps1 (Windows):**
  - PowerShell script for downloading and installing LLVM releases.
  - Handles Windows-specific installation requirements.

- **Activate-LlvmVsCode.ps1 (Windows):**
  - PowerShell script for VSCode integration.
  - Updates Windows-specific VSCode settings.

## Contributing

Feel free to contribute to this project by:
1. Reporting bugs
2. Suggesting new features
3. Submitting pull requests
4. Improving documentation

## New Features in Latest Version

### Bash Functions for Simplified Usage
- **No more manual sourcing**: Use `llvm-activate <version>` directly instead of `source llvm-activate <version>`
- **Automatic loading**: Functions are automatically available in new terminal sessions
- **Enhanced usability**: Additional functions like `llvm-status` and `llvm-list` for better version management
- **Tab completion**: All functions support tab completion for version names
- **Graceful fallbacks**: If scripts are missing, functions show helpful warnings instead of errors

### Improved Installation Process
- **Automatic profile configuration**: Shell profile is automatically configured during installation
- **Smart detection**: Installer chooses the best profile file (`.bashrc` or `.profile`) or creates one if needed
- **Safe installation**: Checks for existing configuration before making changes
- **Clean uninstallation**: Uninstaller removes all traces including profile configuration

### Better User Experience
- **Consistent interface**: All operations use simple function calls
- **Status checking**: `llvm-status` shows current active version and path
- **Version listing**: `llvm-list` shows installed versions with active indicator
- **Error handling**: Better error messages and user guidance

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
