# LLVMUP

LLVMUP installs and switches between LLVM toolchains on Linux and Windows. It
supports stable prebuilt releases, source builds, project configuration, and a
reusable GitHub Action.

The current release line is `v0.5.0`. The project is functional but remains
pre-1.0, so interfaces may change between minor releases. Development is focused
on bug fixes, regression tests, cross-platform consistency, and documentation
accuracy. New features are not currently a priority; see the
[maintenance roadmap](docs/ROADMAP.md).

## What it does

- Installs stable LLVM releases or builds a release from source
- Activates and deactivates installed toolchains in the current shell
- Lists, removes, and reports disk usage for installed toolchains
- Resolves version selectors and ranges such as `latest`, `~22.1`, and `22.*`
- Reads project settings from `.llvmup-config`
- Provides Bash, Zsh, PowerShell, and GitHub Actions entrypoints
- Verifies prebuilt downloads according to a configurable security policy

## Linux quick start

Requirements for prebuilt installs are `curl`, `jq`, and `tar`. Source builds
also require `git`, `cmake`, and `ninja`.

```bash
git clone https://github.com/Fabio3rs/llvmup.git
cd llvmup
./install.sh
source ~/.bashrc

llvmup install 22.1.8
llvmup activate llvmorg-22.1.8
clang --version
```

The installer copies the commands to `~/.local/bin` by default and configures
Bash or Zsh to load the shell functions. Activation changes the environment of
the current shell, so reload the configured profile before using it.

To install without changing shell profiles:

```bash
./install.sh --no-profile
```

See [the installation guide](docs/INSTALL.md) for custom prefixes, system-wide
installation, and CI setup.

## Windows quick start

Use PowerShell 5.0 or newer:

```powershell
git clone https://github.com/Fabio3rs/llvmup.git
Set-Location llvmup
Import-Module .\Llvm-Functions.psm1 -Force

llvmup install 22.1.8
llvmup activate llvmorg-22.1.8
clang --version
```

Import the module in each new PowerShell session where the `llvmup` function is
needed. Release verification can use GPG or an authenticated GitHub CLI when
those tools are installed.

## Main commands

```text
llvmup install [version]          Install a stable prebuilt release
llvmup install --from-source      Build an LLVM release from source
llvmup resolve <expression>       Resolve a stable release without installing it
llvmup activate <version>         Activate an installed version in this shell
llvmup deactivate                 Restore the previous shell environment
llvmup status                     Show the active version and paths
llvmup list                       List installed versions
llvmup list --remote              List stable remote releases
llvmup remove <version>           Remove one installed toolchain
llvmup disk-usage [-h]            Show space used by installed toolchains
llvmup default set <version>      Set the default installed version
llvmup default show               Show the current default
llvmup default unset              Clear the current default
llvmup config init                Create a project configuration
llvmup config apply               Install from project configuration
llvmup config activate            Activate the configured installed version
llvmup help                       Show command help
```

`llvmup` also accepts the legacy short form `llvmup 22.1.8` for a prebuilt
install. Prefer the explicit `llvmup install` form in scripts.

## Version expressions

Installed-version matching supports:

- Selectors: `latest`, `oldest`, `newest`, `earliest`
- Installation types: `prebuilt`, `source`, `latest-prebuilt`, `latest-source`
- Ranges: `>=18.0.0`, `<=19.1.0`, `~19.1`, `18.*`
- Exact identifiers: `llvmorg-22.1.8`, `source-llvmorg-22.1.8`

For example:

```bash
llvmup resolve latest
llvmup resolve '~22.1'
llvmup activate "$(llvm-match-versions latest-prebuilt)"
```

The `llvm-match-versions` helper searches installed versions. `llvmup resolve`
searches stable remote releases and accepts `latest`, exact releases, and ranges
such as `~22.1` or `22.*`; source-only expressions do not apply to prebuilt
release resolution.

## Project configuration

Create a `.llvmup-config` with `llvmup config init`, then adjust only the values
needed by the project. A minimal example is:

```ini
[version]
default = "llvmorg-22.1.8"

[profile]
type = "minimal"

[components]
include = ["clang", "lld"]
```

Use `llvmup config apply` to install from the file or `llvmup config activate`
when the matching toolchain is already installed.

## Building from source

Source builds clone the selected LLVM release, configure it with CMake, build
with Ninja, and install it alongside prebuilt toolchains.

On Windows, run the command from **Developer PowerShell for Visual Studio**.
Source builds require Git, CMake, Ninja, and an existing C/C++ compiler such as
MSVC (`cl.exe`) or Clang. Installing CMake and Ninja alone is not enough because
LLVM needs a bootstrap compiler.

```bash
# Default source build
llvmup install --from-source 22.1.8

# Smaller clang and lld build
llvmup install --from-source --profile minimal 22.1.8

# Select projects explicitly
llvmup install --from-source \
  --component clang \
  --component lld \
  22.1.8

# Pass a CMake option
llvmup install --from-source \
  --cmake-flags "-DCMAKE_BUILD_TYPE=Debug" \
  22.1.8
```

Run `llvmup help` before using build customization in automation; the
project is pre-1.0 and these options may still change.

## Download verification

Prebuilt installs support three verification policies:

- `warn` (default): verify when supported and warn when origin authentication is
  unavailable.
- `strict`: require a valid GPG signature or Sigstore attestation.
- `skip`: explicitly bypass verification.

```bash
llvmup install --verify strict 22.1.8
```

LLVMUP checks a published SHA256 digest or exact checksum companion when one is
available. Exact `.sig` companions are checked with GPG against LLVM release
keys; exact `.jsonl` companions are checked with `gh attestation verify` for the
`llvm/llvm-project` repository. LLVMUP does not install verification tools.

A digest mismatch or an invalid signature or attestation is fatal under `warn`
and `strict`. Verification applies to prebuilt release assets, not source builds.

The equivalent PowerShell option is:

```powershell
.\Download-Llvm.ps1 -Version 22.1.8 -VerifyPolicy Strict
```

## GitHub Actions

The reusable Action supports Linux and Windows stable prebuilt releases. Caching
is enabled by default.

```yaml
- uses: actions/checkout@v6
- uses: Fabio3rs/llvmup@v0.5.0
  with:
    version: 22.1.8
    verify: strict
- run: clang --version
```

Inputs:

- `version`: `latest`, an exact release, or a supported expression
- `cache`: `true` or `false` (default: `true`)
- `verify`: `warn`, `strict`, or `skip` (default: `warn`)
- `github-token`: optional token for API and attestation requests

Outputs are `version`, `llvm-path`, `cache-hit`, and `verification`.

For other CI systems, install without modifying profiles and export the selected
environment explicitly:

```bash
LLVMUP_PREFIX="$RUNNER_TEMP/llvmup" ./install.sh --ci
export PATH="$RUNNER_TEMP/llvmup/bin:$PATH"
llvmup install 22.1.8
eval "$(llvmup env llvmorg-22.1.8)"
```

## Data and installation paths

User installations default to:

```text
~/.local/bin/          LLVMUP commands
~/.llvm/toolchains/    Installed LLVM toolchains
~/.llvm/sources/       Source checkouts and build data
```

Installation paths and LLVM data directories can be overridden. See
[custom directories](docs/CUSTOM_DIRECTORIES.md) for the supported variables and
their precedence.

## Uninstalling

Run the uninstaller from the repository checkout:

```bash
./uninstall.sh
```

Use the same installation variables that were used with `install.sh` when the
prefix was customized. The uninstaller preserves installed LLVM toolchains. Use
`llvmup remove <version>` to remove toolchains individually.

## Documentation

- [Installation](docs/INSTALL.md)
- [Custom directories](docs/CUSTOM_DIRECTORIES.md)
- [Build examples](docs/BUILD_EXAMPLE.md)
- [Maintenance roadmap](docs/ROADMAP.md)
- [Changelog](CHANGELOG.md)

## Contributing

Bug reports should include a minimal reproducer, platform details, and the
relevant command output. Focused fixes should add a regression test when
practical. Please discuss feature proposals in an issue before implementing
them; the current priority is reliability of existing behavior.

## License

LLVMUP is licensed under the [MIT License](LICENSE).
