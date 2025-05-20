# LLVMUP: LLVM Version Manager (Concept Test)

This project is a minimal viable test software inspired by tools like **rustup**, **Python venv**, and **Node Version Manager (nvm)**. It demonstrates a concept for managing multiple LLVM versions by downloading, extracting, and switching between different LLVM releases. Additionally, it provides an option to build LLVM from source.

**WARNING:**
This is a concept test version and may contain bugs. Use it at your own risk and feel free to contribute improvements or report issues.

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
  - **Linux:** Activate a specific LLVM version for the current terminal session by:
    - Updating the `PATH` to include the selected LLVM's `bin` directory.
    - Backing up and then setting `CC`, `CXX`, and `LD` (if available) to point to the LLVM binaries.
    - Modifying the terminal prompt (`PS1`) to indicate the active LLVM version.
  - **Windows:** Use PowerShell scripts (`Activate-Llvm.ps1`) to update environment variables (`PATH`, `CC`, and `CXX`) and modify the PowerShell prompt to indicate the active LLVM version.
  - The scripts prevent activating a new version if one is already active until deactivation.

- **Version Deactivation:**
  - **Linux:** Revert the environment changes made during activation by restoring the original values of `PATH`, `CC`, `CXX`, `LD`, and `PS1`.
  - **Windows:** Use PowerShell scripts (`Deactivate-Llvm.ps1`) to restore the original environment variables and prompt.

- **VSCode Integration:**
  - **Linux:** Use the `activate_llvm_vscode.sh` script to merge LLVM-specific settings into your `.vscode/settings.json` file. This configures:
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

- **Wrapper Command:**
  - A wrapper script called `llvmup` is provided that accepts an optional `--from-source` flag. When used, it calls the build-from-source script; otherwise, it uses the pre-built release manager.

## Installation Script (install.sh)

To make it easier to call the LLVM version manager tools from anywhere, an installation script (`install.sh`) is provided. This script copies the project’s commands to a directory (by default, `$HOME/.local/bin`) that is typically included in your PATH.

### How to Use the Installation Script

1. **Run the Installer:**
   ```bash
   ./install.sh
   ```
   This will:
   - Create the installation directory (`$HOME/.local/bin`) if it doesn't exist.
   - Copy the following scripts into that directory:
     - `llvm_prebuilt.sh` as `llvm-prebuilt`
     - `activate_llvm.sh` as `llvm-activate`
     - `deactivate_llvm.sh` as `llvm-deactivate`
     - `activate_llvm_vscode.sh` as `llvm-vscode-activate`
     - `build_llvm_source.sh` (for building from source)
     - `llvmup` (wrapper command)
   - Set the appropriate executable permissions on these scripts.

2. **Verify PATH:**
   The installer checks if `$HOME/.local/bin` is in your PATH. If it isn’t, you'll receive a warning along with instructions to add it:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```
   You may add this line to your shell’s startup file (e.g., `~/.bashrc` or `~/.profile`) for persistence.

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
   - Use `llvm-activate` to activate a specific LLVM version for the current terminal session.
   - Use `llvm-deactivate` to revert the activation.
   - Use `llvm-vscode-activate` to update your VSCode workspace settings with the selected LLVM configuration.

## Windows Scripts

For Windows users, PowerShell scripts are provided to manage the LLVM toolchains:

- **Download-Llvm.ps1:**
  - Fetches available LLVM releases from the GitHub API.
  - Allows you to select a release.
  - Downloads the Windows 64-bit NSIS installer for the selected release.
  - Runs the installer in silent mode, installing the LLVM toolchain into `%USERPROFILE%\.llvm\toolchains\<version>`.

- **Activate-Llvm.ps1:**
  - Activates a specific LLVM version in a PowerShell session.
  - Updates environment variables (`PATH`, `CC`, and `CXX`) and modifies the PowerShell prompt to indicate the active LLVM version.
  - Checks if another LLVM version is already active and prevents reactivation until the current one is deactivated.

- **Deactivate-Llvm.ps1:**
  - Reverts the changes made by `Activate-Llvm.ps1`.
  - Restores the original environment variables and PowerShell prompt.

- **Activate-LlvmVsCode.ps1:**
  - Updates your VSCode workspace settings (`.vscode\settings.json`) by merging LLVM-specific configuration.
  - Sets:
    - `cmake.additionalCompilerSearchDirs`
    - `clangd.path`
    - `clangd.fallbackFlags`
    - `cmake.configureEnvironment` (with updated `PATH`)
  - After running the script, reload your VSCode workspace for the changes to take effect.

## Files

- **llvm_prebuilt.sh (Linux):**
  - Interacts with the GitHub API to list available LLVM releases.
  - Allows you to choose a version for download and installation.
  - Downloads, extracts, and installs the selected LLVM release into `~/.llvm/toolchains/<version>`.

- **build_llvm_source.sh (Linux):**
  - Implements a build-from-source workflow.
  - Shallow clones the LLVM project at the selected release into `~/.llvm/sources/<tag>`.
  - Configures, builds, and installs LLVM (using Ninja) to `~/.llvm/toolchains/source-<version>`.

- **llvmup (Linux):**
  - A wrapper script that accepts an optional `--from-source` flag.
  - If `--from-source` is passed, it calls the build-from-source script.
  - Otherwise, it calls the pre-built release manager (`llvm_prebuilt.sh`).

- **activate_llvm.sh (Linux):**
  - A script intended to be **sourced** in the shell.
  - If no argument is provided, it lists the installed LLVM versions.
  - When a version is provided (e.g., `llvmorg-20.1.0`), it:
    - Checks if an LLVM version is already active.
    - Backs up current environment variables (`PATH`, `CC`, `CXX`, `LD`, and `PS1`).
    - Updates these variables to use the selected LLVM version.
    - Alters the shell prompt to indicate the active LLVM version.

- **deactivate_llvm.sh (Linux):**
  - A script intended to be **sourced** in the shell.
  - Restores the environment variables to their original state, effectively deactivating the LLVM version.

- **activate_llvm_vscode.sh (Linux):**
  - A script to update your VSCode workspace settings by merging LLVM-specific configuration.
  - Uses `jq` to merge settings into `.vscode/settings.json` without replacing existing settings.
  - Configures:
    - `cmake.additionalCompilerSearchDirs`
    - `clangd.path`
    - `clangd.fallbackFlags`
    - `cmake.configureEnvironment` (with updated `PATH`)
  - This integration ensures that clangd and CMake in VSCode use the correct LLVM toolchain.

- **Download-Llvm.ps1 (Windows):**
  - Downloads the Windows 64-bit NSIS installer for the selected LLVM release.
  - Installs the LLVM toolchain silently into `%USERPROFILE%\.llvm\toolchains\<version>`.

- **Activate-Llvm.ps1 (Windows):**
  - Activates a specific LLVM version in a PowerShell session.
  - Updates environment variables (`PATH`, `CC`, and `CXX`) and modifies the PowerShell prompt.
  - Prevents activation if another LLVM version is already active.

- **Deactivate-Llvm.ps1 (Windows):**
  - Reverts the changes made by `Activate-Llvm.ps1`.
  - Restores the original environment variables and PowerShell prompt.

- **Activate-LlvmVsCode.ps1 (Windows):**
  - Updates your VSCode workspace settings (`.vscode\settings.json`) by merging LLVM-specific configuration.
  - Sets:
    - `cmake.additionalCompilerSearchDirs`
    - `clangd.path`
    - `clangd.fallbackFlags`
    - `cmake.configureEnvironment` (with updated `PATH`)
  - After running the script, reload your VSCode workspace for the changes to take effect.

## Usage

### 1. Install an LLVM Version

- **Pre-built (Linux):**
  Run the manager script to download and install a pre-built LLVM version:
  ```bash
  ./llvm_prebuilt.sh
  ```
  Follow the on-screen instructions. The release will be installed into `~/.llvm/toolchains/<version>`.

- **Build from Source (Linux):**
  Use the wrapper script with the `--from-source` flag:
  ```bash
  llvmup --from-source
  ```
  This will prompt you to select a release and then build LLVM from source. The source will be cloned into `~/.llvm/sources/<tag>`, and the installation will be placed into `~/.llvm/toolchains/source-<version>`.

### 2. Activate an LLVM Version (Linux)

To list installed versions:
```bash
source activate_llvm.sh
```
To activate a specific version (e.g., `llvmorg-20.1.0`):
```bash
source activate_llvm.sh llvmorg-20.1.0
```
This updates your environment (e.g., `PATH`, `CC`, `CXX`, `LD`, and `PS1`).

### 3. Deactivate the LLVM Version (Linux)

To revert the changes and restore your original environment, run:
```bash
source deactivate_llvm.sh
```

### 4. Activate LLVM for VSCode (Linux)

To update your VSCode workspace settings with the selected LLVM configuration, run:
```bash
./activate_llvm_vscode.sh llvmorg-20.1.0
```
This merges LLVM configuration settings into your `.vscode/settings.json` file. Reload your VSCode workspace for changes to take effect.

### 5. Windows Usage

- **Download and Install:**
  Run `Download-Llvm.ps1` in PowerShell to fetch the desired LLVM NSIS installer and perform a silent installation into `%USERPROFILE%\.llvm\toolchains\<version>`.

- **Activate in PowerShell:**
  Run:
  ```powershell
  .\Activate-Llvm.ps1 llvmorg-20.1.0
  ```
  This activates the LLVM version for the current session, updating environment variables and the prompt.

- **Deactivate in PowerShell:**
  Run:
  ```powershell
  .\Deactivate-Llvm.ps1
  ```
  This reverts the changes made by the activation script.

- **Activate LLVM for VSCode in PowerShell:**
  Run:
  ```powershell
  .\Activate-LlvmVsCode.ps1 llvmorg-20.1.0
  ```
  This updates your `.vscode\settings.json` file with the LLVM configuration. Reload your VSCode workspace for the changes to take effect.

## Inspiration

This project takes inspiration from:

- **rustup:** A tool for managing Rust toolchains.
- **Python venv:** Which provides isolated Python environments.
- **Node Version Manager (nvm):** Allows switching between different Node.js versions.

## Disclaimer

This is a concept test version designed as a minimal viable product (MVP). It is intended for experimental purposes and may contain bugs or unexpected behavior. Contributions, feedback, and bug reports are welcome!

## Contributing

Feel free to fork this project and submit pull requests with improvements or bug fixes.

## License

This project is released under the MIT License.
