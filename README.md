# LLVMUP

LLVMUP installs, selects and runs LLVM/C/C++ toolchains on Linux, macOS ARM64 and Windows. It
manages three distributions through one set of commands:

| Provider | What it is | Hosts |
| --- | --- | --- |
| `official` | LLVM releases from `llvm/llvm-project` (prebuilt, selective profiles, source builds) | Windows, Linux, macOS |
| `winlibs` | WinLibs MinGW-w64 bundles with GCC **and** LLVM/Clang in one tree | Windows |
| `llvm-mingw` | LLVM-MinGW: Clang/LLD with MinGW-w64 for several Windows targets | Windows, Linux, macOS (cross to Windows) |

LLVMUP is pre-1.0. The multi-provider architecture is described in
[docs/RECIPES.md](docs/RECIPES.md) and tracked in
[docs/ARCHITECTURE_EVOLUTION.md](docs/ARCHITECTURE_EVOLUTION.md).

## What it does

- Installs prebuilt releases of any provider, or builds an official release from source
- Selects a toolchain for the shell (`use`), runs one command with it (`run`, `+toolchain`) or opens
  a subshell (`shell`), without shims: the real `clang`, `gcc`, ... binaries are used
- Chooses GCC or Clang inside one WinLibs bundle and a target inside one LLVM-MinGW bundle
- Resolves `provider@version` selectors, ranges such as `~23.1` and `23.*`, and exact `--release` tags
- Verifies downloads (digests, checksums, GPG, attestations) under a `warn`/`strict`/`skip` policy
- Extracts with 7-Zip, tar, the built-in ZIP reader or Python, whichever can read the format
- Pins project toolchains (`.llvmup-config`), locks exact assets (`.llvmup-lock.json`) and syncs them
- Generates CMake toolchain files, including Linux -> Windows cross builds
- Provides Bash, Zsh, PowerShell, `llvmup.cmd` and GitHub Actions entrypoints

## Install from a release

Release packages install LLVMUP without a Git checkout on Linux and Windows. See the
[bootstrap commands](docs/INSTALL.md#release-bootstrap-no-git-checkout) for downloads, custom
directories, mirrors (`-BaseUrl`) and offline installation (`-PackageDir`). The commands install the
manager only. Use a release with published bootstrap, package and checksum assets for your platform.

## Windows quick start

Run this in PowerShell 5.1 or 7. The default user install requires no administrator privileges.
LLVM-MinGW can build Windows programs without Visual Studio. To read the bootstrap before running
it, use the [download and inspection instructions](docs/INSTALL.md#release-bootstrap-no-git-checkout).

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://github.com/Fabio3rs/llvmup/releases/download/v0.9.1/bootstrap.ps1 -ErrorAction Stop))) -Import
llvmup install llvm-mingw@latest --use
clang++ --version
clang++ -std=c++23 main.cpp -o main.exe
```

From an extracted current Windows package or source tree, run
`& .\packaging\Install-Llvmup.ps1 -Import` in place of the download. Builds that include
this development update show the manager version with `llvmup --version`.

For GCC plus Clang, use `llvmup install winlibs@latest --use`. WinLibs GCC needs a writable
toolchain directory without spaces. Set `LLVM_HOME` before installing the toolchain when necessary.
To see the available distributions, run `llvmup list --providers`.

`llvmup` is a PowerShell **function** when the module is imported: `use`, `activate`, `deactivate`
and `pick` change the current session. `llvmup.cmd` is a **child-process launcher** for cmd.exe,
scripts and CI: it can install, resolve, run programs and print environments
(`llvmup env win-dev --format cmd`), but it cannot change the caller's environment and rejects those
commands with exit code 2.

The official Windows LLVM targets MSVC and needs Visual Studio and the Windows SDK to build hosted
programs; it also needs 7-Zip (or a tar/Python able to read `.tar.zst`/`.tar.xz`), which llvmup
detects but never installs. WinLibs (`.7z`, or `.zip` without 7-Zip) and LLVM-MinGW (`.zip`) work on a
clean Windows installation.

## Linux quick start

From an extracted current Linux package or source tree, use Bash or Zsh. For prebuilt installs,
have `jq`, `tar`, and `curl` or `wget`. Archive formats may require `xz`, `zstd`, or a compatible extractor.
Source builds also require `git`, `cmake`, and `ninja`.

```bash
bash ./install.sh
source "$HOME/.local/bin/llvm-functions.sh"  # use the path printed by the installer for a custom prefix
llvmup install official@latest --use
clang --version

llvmup install llvm-mingw@23          # Linux-hosted LLVM-MinGW for Windows targets
llvmup cmake-toolchain llvm-mingw@23 --target x86_64-w64-mingw32 --output build/win64.cmake
```

The installer copies the commands to `~/.local/bin` by default and configures Bash or Zsh to load
the shell functions (`./install.sh --no-profile` skips that). See
[the installation guide](docs/INSTALL.md) for prefixes, system-wide installation and CI.

## Main commands

```text
llvmup install [provider@]<version> [--name N] [--crt C] [--release TAG] [--use]
llvmup install --from-source [version]   Build an official release from source
llvmup resolve [provider@]<expr>         Resolve a release without installing (--format json)
llvmup use <toolchain> [--compiler C] [--target T]   Select for this shell (function only)
llvmup use - | use --auto                Previous selection | back to project/default selection
llvmup run [toolchain] -- <cmd> [args]   Run one command with a toolchain; keeps the exit code
llvmup +<toolchain> -- <cmd> [args]      Same as run
llvmup shell [toolchain]                 Subshell with the toolchain active
llvmup activate | deactivate             Historical activation commands (still supported)
llvmup env [toolchain] --format shell|cmd|github|json
llvmup which <tool> [--toolchain T]      Real path of a tool in the selected toolchain
llvmup where [toolchain]                 Installation root
llvmup provides <tool>                   Installed toolchains that ship a tool
llvmup info [toolchain] [--json]         Manifest of an installation
llvmup status [--explain] [--json]       Selected vs active toolchain and why
llvmup list [--json] [--providers] [--remote [--provider P]]
llvmup alias set|list|show|remove        Names for installed toolchains
llvmup default [toolchain] | default set|show|unset
llvmup pin <toolchain>|--current [--fuzzy]   Write the project toolchain to .llvmup-config
llvmup config lock [--platform OS --arch A]  Record exact assets in .llvmup-lock.json
llvmup sync [--locked]                   Install what the project declares (non-interactive)
llvmup update [toolchain]                Newest release of the same provider, major and CRT
llvmup toolchain link|unlink <name> [path]   Register an external toolchain (never modified)
llvmup cmake-toolchain [toolchain] [--target T] [--compiler C] --output FILE
llvmup pick                              Interactive local selector (requires a terminal)
llvmup remove <toolchain> | disk-usage | doctor
llvmup help [command] | llvmup <command> --help   Overview, or usage and examples for one command
```

Directory auto-activation reacts to directory changes. Set `LLVMUP_WATCH_CONFIG=1` to also pick up edits to
the current project's `.llvmup-config` at the next prompt.

Help never touches the network or your installations. Errors name the real cause (for example an
ambiguous selector, a compiler the toolchain does not ship, or a missing installation) and, when it
helps, the command that fixes it. `--quiet` hides progress, never errors or warnings.

Selection precedence: explicit selector of the command, then the session (`use`), then the project
`.llvmup-config` (and `.llvmup-lock.json` with `--locked`), then the user default. `llvmup 22.1.8`
remains the legacy short form of `llvmup install 22.1.8`.

More: [providers and variants](docs/PROVIDERS.md), [verification](docs/VERIFICATION.md),
[extraction and 7-Zip](docs/EXTRACTION.md), [cross-compilation and CMake](docs/CROSS_COMPILATION.md),
[project configuration](docs/INSTALL.md#custom-directories).

## Diagnose problems

```bash
llvmup doctor
llvmup doctor --verbose
llvmup doctor --deep
llvmup doctor --network
llvmup doctor --json
```

Doctor is offline and read-only by default. It checks runtime files, dependency
availability, installed compiler files, default links, activation variables,
project configuration and shell integration. No installed LLVM is required.
It never repairs profiles or removes toolchains. Custom compiler overrides are
warnings, not definite errors; dependency warnings explain which operation needs
the tool.

`--deep` runs lifecycle, environment restoration, version matching and completion
checks using temporary fixtures and isolated processes. `--network` explicitly
checks GitHub release metadata and redirects with short timeouts; it does not
download LLVM archives. Options can be combined.

PASS means the stated check succeeded; WARN calls for review; FAIL identifies a
broken condition; SKIP means optional, unavailable or inapplicable. Exit codes
are 0 for no failures (warnings allowed), 1 for failures and 2 for invalid options.
The PowerShell function sets `$LASTEXITCODE`; `Llvm-Doctor.ps1` also exits with it.
`--json` emits a single schema-versioned object with check IDs and recommendations.
Paths and environment overrides can appear in diagnostics; review before sharing.

For missing runtime files, reinstall LLVMUP from a complete checkout. For an
incomplete toolchain, inspect permissions and reinstall that version. For a broken
default link, use `llvmup default unset` and select an installed version. For PATH
or profile warnings, check for duplicate initialization and reload the intended
shell integration. See [doctor details and regression history](docs/DOCTOR.md).

If the shell facade cannot load, run `bash /path/to/llvmup-doctor.sh` or
`pwsh -NoProfile -File /path/to/Llvm-Doctor.ps1` directly.

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

## Selecting installation components

Complete installations remain the default. Linux and Windows can install smaller
toolchains using the same profiles and component names:

```bash
llvmup install --profile compiler 22.1.8
llvmup install --profile minimal --component clang-tidy 22.1.8
llvmup install --component llvm-cov --component llvm-profdata --name coverage 22.1.8
llvmup install --profile compiler --strip --verbose --name ci-llvm 22.1.8 # Linux
llvmup install --from-source --profile compiler 22.1.8
```

| Profile | Installed content |
| --- | --- |
| `minimal` | Clang and aliases, LLD, Clang headers and runtimes |
| `compiler` | `minimal` plus `llvm-ar`, `llvm-ranlib`, `llvm-cov`, `llvm-profdata`, plus libc++ headers/runtime, libc++abi and libunwind on Unix |
| `custom` | Clang, headers and runtimes, plus explicit components |
| `full` | Complete distribution; the default without selection options |

Components without a profile imply `custom`; components with a profile add to it.
The catalog also supports binary inspection, symbolization, LLVM IR tools,
`llvm-xray`, and Clang analysis/formatting tools, including their helpers.
See the [component list](docs/INSTALL.md#selective-installations).
Selective installation and optional strip require Python 3.9+; plain `full`
installs retain their existing dependencies. Strip additionally requires
`llvm-strip` or `strip` on PATH and applies only to Linux ELF executables.

Prebuilt archives are downloaded and verified in full, then only selected files
are extracted. Symbolic links, hardlinks, Clang resources, and required bundled
shared libraries are retained. Changing the selection of an existing installation
requires another `--name` or explicit removal. See [installation details](docs/INSTALL.md#selective-installations)
for configuration, source builds, and disk diagnostics.

## Building from source

Source builds clone the selected LLVM release, configure it with CMake, build
with Ninja, and install it alongside prebuilt toolchains.

On Windows, run the command from **Developer PowerShell for Visual Studio**.
`compiler` bundles libc++ on Unix; select it with `-stdlib=libc++` and configure
the runtime library search path for your executables. Windows MSVC uses the Visual
Studio standard library. `minimal` continues to use the system C++ library.

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

The reusable Action supports Linux, macOS ARM64, and Windows stable prebuilt
releases. On macOS, use a release with a `macOS-ARM64.tar.xz` asset and the
default `full` profile; selective prebuilt installation is not supported there.
The Action uses `xcrun` to export `SDKROOT` when a macOS SDK is available. If
SDK discovery fails, it warns and still exposes tools that do not need the SDK.
Caching is enabled by default.

```yaml
- uses: actions/checkout@v6
- uses: Fabio3rs/llvmup@v0.9.1
  with:
    version: 22.1.8
- run: clang --version
```

Inputs:

- `version`: `latest`, an exact release, or a supported expression
- `cache`: `true` or `false` (default: `true`)
- `verify`: `warn`, `strict`, or `skip` (default: `warn`)
- `github-token`: optional token for API and attestation requests
- `provider`: `official` (default), `winlibs` or `llvm-mingw`; `version` is the LLVM version
- `release`, `crt`, `target`, `compiler`, `extractor`: provider options as on the CLI

Outputs are `version`, `llvm-path`, `cache-hit`, `verification`, and `provider`, `release`,
`llvm-version`, `toolchain-id`, `toolchain-path`.

```yaml
- uses: Fabio3rs/llvmup@<version>
  with:
    provider: llvm-mingw          # Linux, macOS or Windows runner; builds Windows programs
    version: '23'
    crt: ucrt
    target: aarch64-w64-mingw32
- shell: bash
  run: '"$CXX" -std=c++23 main.cpp -o main.exe'
```

The Action uses the CLI to resolve, install and export a toolchain. The official provider
supports profiles, component selection and stripping on supported hosts. The cache key includes
the provider, release, toolchain ID, asset digest, runner platform and verification policy.

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
[custom directories](docs/INSTALL.md#custom-directories) for the supported variables and
their precedence.

## Uninstalling

Run the uninstaller from the installed manager directory.

```bash
~/.local/bin/uninstall.sh
```

```powershell
& "$env:LOCALAPPDATA\llvmup\Uninstall-Llvmup.ps1"
```

For a custom installation, use the uninstaller in that location. Toolchains
are preserved. Use `llvmup remove <version>` to remove one separately.

## Documentation

- [Installation](docs/INSTALL.md)
- [Custom directories](docs/INSTALL.md#custom-directories)
- [Build examples](docs/BUILD_EXAMPLE.md)
- [Maintenance roadmap](docs/ROADMAP.md)
- [Changelog](CHANGELOG.md)

## Contributing

Bug reports should include a minimal reproducer, platform details, and the
relevant command output. Focused fixes should add a regression test when
practical. Please discuss feature proposals in an issue before implementing
them; the current priority is reliability of existing behavior.

Run `./tests/run_tests.sh` for the Bash suites (Bats) and, when PowerShell is
available, the PowerShell suites (Pester). The runner lists unit suites explicitly
and discovers `tests/integration/*.bats` automatically. GitHub Actions runs Bats
on Linux and Pester on Windows.

The download-size regression test requires Python 3 and uses its standard-library
HTTP server on `127.0.0.1` with an automatically assigned port. It exercises real
HEAD requests, redirects, downloads, checksum verification, and installation using
a small generated archive, without contacting GitHub. Run it with
`bats --verbose-run tests/integration/test_prebuilt_http.bats`; when using an agent,
run this network test through NativeLab MCP.

## License

LLVMUP is licensed under the [MIT License](LICENSE).
