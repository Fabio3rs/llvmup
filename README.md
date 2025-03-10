# LLVMUP: LLVM Version Manager (Concept Test)

This project is a minimal viable test software inspired by tools like **rustup**, **Python venv**, and **Node Version Manager (nvm)**. It demonstrates a concept for managing multiple LLVM versions on a Linux system by downloading, extracting, and switching between different LLVM releases.

**WARNING:**
This is a concept test version and may contain bugs. Use it at your own risk and feel free to contribute improvements or report issues.

## Features

- **Download & Install:**
  - Fetch available LLVM releases from the GitHub API.
  - Download the Linux X64 tarball for the selected version.
  - Extract the tarball (which creates a directory with the release name) and move it to the designated toolchains directory (`~/.llvm/toolchains/<version>`).
  - Mark already installed versions when listing available releases.

- **Version Activation:**
  - Activate a specific LLVM version for the current terminal session by:
    - Updating the `PATH` to include the selected LLVM's `bin` directory.
    - Backing up and then setting `CC`, `CXX`, and `LD` (if available) to point to the LLVM binaries.
    - Modifying the terminal prompt (`PS1`) to indicate the active LLVM version.
  - This behavior is similar to how `python venv` activates an isolated environment.

- **Version Deactivation:**
  - Revert the environment changes made during activation by restoring the original values of `PATH`, `CC`, `CXX`, `LD`, and `PS1`.

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
     - `llvm_manager.sh` as `llvm-manager`
     - `activate_llvm.sh` as `llvm-activate`
     - `deactivate_llvm.sh` as `llvm-deactivate`
   - Set the appropriate executable permissions on these scripts.

2. **Verify PATH:**
   The installer checks if `$HOME/.local/bin` is in your PATH. If it isn’t, you'll receive a warning along with instructions to add it:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```
   You may add this line to your shell’s startup file (e.g., `~/.bashrc` or `~/.profile`) for persistence.

3. **Using the Commands:**
   After installation, you can run the commands from anywhere in your terminal:
   - Use `llvm-manager` to download and install LLVM versions.
   - Use `llvm-activate` to activate a specific LLVM version for the current terminal session.
   - Use `llvm-deactivate` to revert the activation.

## Files

- **llvm_manager.sh:**
  - Interacts with the GitHub API to list available LLVM releases.
  - Allows you to choose a version for download and installation.
  - Downloads, extracts, and installs the selected LLVM release into `~/.llvm/toolchains/<version>`.

- **activate_llvm.sh:**
  - A script intended to be **sourced** in the shell.
  - If no argument is provided, it lists the installed LLVM versions.
  - When a version is provided (e.g., `llvmorg-20.1.0`), it:
    - Checks if an LLVM version is already active.
    - Backs up current environment variables (`PATH`, `CC`, `CXX`, `LD`, and `PS1`).
    - Updates these variables to use the selected LLVM version.
    - Alters the shell prompt to indicate the active LLVM version.

- **deactivate_llvm.sh:**
  - A script intended to be **sourced** in the shell.
  - Restores the environment variables to their original state, effectively deactivating the LLVM version.

## Usage

### 1. Install an LLVM Version

Run the manager script to download and install an LLVM version:

```bash
./llvm_manager.sh
```

Follow the on-screen instructions to select the version you wish to install. The release will be installed into `~/.llvm/toolchains/<version>`.

### 2. Activate an LLVM Version

To list installed versions:

```bash
source activate_llvm.sh
```

To activate a specific version (for example, `llvmorg-20.1.0`):

```bash
source activate_llvm.sh llvmorg-20.1.0
```

This command will update your environment for the current session by modifying `PATH`, `CC`, `CXX`, `LD`, and `PS1`.

### 3. Deactivate the LLVM Version

To revert the changes and restore your original environment, run:

```bash
source deactivate_llvm.sh
```

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
