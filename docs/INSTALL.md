# Install and update LLVMUP

Start with the [Windows and Linux quick starts](../README.md#install-from-a-release).
Use a release package, an extracted source archive, or a checkout. Toolchains are
installed separately.

## Custom directories

The manager and your toolchains have separate locations.

| Setting | Purpose | Default |
| --- | --- | --- |
| `LLVMUP_PREFIX` | Unix manager and completion prefix | `$HOME/.local` |
| `LLVMUP_INSTALL_DIR` | Manager commands on Unix, manager directory on Windows | `$LLVMUP_PREFIX/bin` or `%LOCALAPPDATA%/llvmup` |
| `LLVMUP_COMPLETION_DIR` | Bash completion directory | `$LLVMUP_PREFIX/share/bash-completion/completions` |
| `LLVMUP_ZSH_COMPLETION_DIR` | Zsh completion directory | `$LLVMUP_PREFIX/share/zsh/site-functions` |
| `LLVM_HOME` | Toolchain data and configuration | `$HOME/.llvm` |
| `LLVM_TOOLCHAINS_DIR` | Installed toolchains | `$LLVM_HOME/toolchains` |
| `LLVM_SOURCES_DIR` | Source checkouts and build data | `$LLVM_HOME/sources` |

Set the data paths before starting LLVMUP. The dedicated directory variables
override directories derived from `LLVM_HOME`. Some project and source build
commands also use `[paths]` in `.llvmup-config`.

```toml
[paths]
llvm_home = "./llvm-data"
toolchains_dir = "./llvm-data/toolchains"
sources_dir = "./llvm-data/sources"
```

For a Unix CI or manual install, use `--no-profile` or `--ci`. To configure
profiles later, run `install.sh --configure-shell` with the same settings.
`LLVMUP_SYSTEM_INSTALL=1` explicitly opts into a Unix system installation
under `/usr/local` and may require sudo.

## Release bootstrap (no Git checkout)

The examples use the packaged `v0.9.1` prerelease. For a different release, select
an explicit tag with a published bootstrap, package, and `SHA256SUMS`. Use the
`latest` URL once a stable release ships all three assets. The bootstrap installs
the manager. Choose a toolchain afterwards.

Linux (Bash installer, Bash/Zsh integration):

```bash
( t=$(mktemp) && trap 'rm -f "$t"' EXIT && curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 https://github.com/Fabio3rs/llvmup/releases/download/v0.9.1/bootstrap.sh -o "$t" && bash "$t" )
```

Windows PowerShell 5.1 or PowerShell 7, with inspection before execution:

```powershell
$p = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-bootstrap-' + [guid]::NewGuid() + '.ps1')
Invoke-WebRequest https://github.com/Fabio3rs/llvmup/releases/download/v0.9.1/bootstrap.ps1 -UseBasicParsing -OutFile $p -TimeoutSec 120 -ErrorAction Stop
Get-Content -LiteralPath $p
# Run after reviewing the script.
& $p -Import
```

On Linux, save the bootstrap to a named file if you want to inspect it before
running it. The bootstrap is pinned to the release that supplied it. Replace
`v0.9.1` in the URL to select a different published release.

The bootstrap verifies the package against the release's `SHA256SUMS` before
extraction and rejects unsafe archive entries. Checksums detect corruption;
they are not independent proof of authorship. Bootstrap and package authenticity
rely on HTTPS and control of the GitHub repository/release. There is no unsigned
fallback on a checksum failure. No Git, Python, GitHub CLI, or LLVM compiler is
needed by the bootstrap. Linux requires Bash 4+, curl, tar, gzip, sha256sum and
standard core utilities. Prebuilt LLVM downloads separately require jq and the
dependencies listed above.

With `-Import`, a successful install makes `llvmup` available as a PowerShell
function in the same session. From an extracted package, run
`& ./packaging/Install-Llvmup.ps1 -Import`.

When you save the bootstrap as `bootstrap.sh` or `bootstrap.ps1`, you can
customize the install:

```bash
LLVMUP_PREFIX="$HOME/tools/llvmup" bash bootstrap.sh --no-profile
bash bootstrap.sh --version vX.Y.Z --ci
```

```powershell
.\bootstrap.ps1 -InstallDir 'D:\Tools\llvmup' -NoProfile -NoPath -Import
.\bootstrap.ps1 -Version vX.Y.Z
```

The Windows installer defaults to `$env:LOCALAPPDATA\llvmup` (or
`$HOME/.local/share/llvmup` when LOCALAPPDATA is absent), respects
`LLVMUP_INSTALL_DIR`, and adds a marked import to the current user's all-hosts
PowerShell profile. `-NoProfile` leaves profiles unchanged and `-NoPath` suppresses
the automatic PATH update. If PowerShell blocks an import, the installer reports
the error and prints the full path to `llvmup.cmd` for commands such as `list`
and `run`. Execution policy is controlled by the user or administrator. The
Windows PowerShell 5.1 HTTPS bootstrap requires TLS 1.2.

Linux prints the commands to load LLVMUP in the current Bash or Zsh session.
The installer updates its marked profile blocks and uses the exported `ZDOTDIR`
for `.zshrc`, defaulting to the home directory. An interactive Zsh session can reuse
an already initialized completion system.

On builds that include this development update, run `llvmup --version` to check the manager. It reports `development` when
installed from a checkout without release metadata. To update the manager, run
the newer release's bootstrap with the same destination. To reinstall, run the
same version again. Both installers preserve toolchains and leave files outside
the incoming runtime inventory in place. `llvmup update` updates toolchains.
The updated bootstraps accept `--quiet` on Linux or `-Quiet` on PowerShell to
suppress progress while keeping warnings and errors visible.

For offline installation, transfer and verify the package and `SHA256SUMS`,
extract it, then run `bash llvmup/install.sh --no-profile` or
`& ./llvmup/packaging/Install-Llvmup.ps1 -NoProfile`.

The PowerShell bootstrap also installs from a directory holding `SHA256SUMS` and
`llvmup-windows.zip`, or from a mirror of the release assets; the checksum is verified in
both cases (a checksum detects corruption, not a malicious mirror):

```powershell
.\bootstrap.ps1 -PackageDir '\\fileserver\tools\llvmup\vX.Y.Z' -Import
.\bootstrap.ps1 -BaseUrl 'https://mirror.example.com/llvmup/vX.Y.Z'   # or LLVMUP_BOOTSTRAP_BASE_URL
```

### Windows: function versus launcher

The installer adds two entry points:

- the **`llvmup` PowerShell function** (module imported by the profile block, with
  `-DisableNameChecking`). It runs in the current session, so `use`, `activate`,
  `deactivate` and `pick` can change `PATH`, `CC`, `CXX`, ...;
- **`llvmup.cmd`** on the user `PATH`, a launcher for cmd.exe, batch files, CMake and CI. It runs
  llvmup in a child PowerShell process (PowerShell 7 when present, otherwise Windows PowerShell
  5.1, with `-ExecutionPolicy Bypass` for that process only). It returns the exit code of the
  command (for `run`, `+toolchain` and `shell`, the exit code of the program), prints errors as a
  single `Error: ...` line, and rejects session-changing commands with exit code 2. Use
  `llvmup run <toolchain> -- <command>` or `for /f "delims=" %i in ('llvmup env <toolchain> --format cmd') do %i`
  there instead.

If a Windows execution policy prevents the profile or the module from loading,
run `Get-ExecutionPolicy -List` to see the applicable policies. Use your
organization's approved script policy or try the standalone launcher at the
path printed by the installer.

### Windows: where toolchains live

Toolchains go to `%LLVM_HOME%\toolchains` (default `%USERPROFILE%\.llvm\toolchains`). WinLibs GCC
cannot link from a directory whose path contains spaces (a GCC/binutils limitation; Clang from the
same bundle works, and accented paths work). If your user name contains spaces, set a different
location before installing WinLibs:

```powershell
[Environment]::SetEnvironmentVariable('LLVM_HOME', 'C:\llvmup', 'User'); $env:LLVM_HOME = 'C:\llvmup'
```

llvmup warns at install time and whenever GCC is selected from such a path.

## Reinstallation and removal

Re-run the installer to replace LLVMUP's own files. All required source files are
validated and staged first. Ordinary copy errors roll back replaced runtime
files; profiles are configured only after the file installation succeeds.
Unrelated files and LLVM toolchains are preserved. This is not a transaction
across power loss or forced process termination. Do not run installs concurrently;
if an interrupted install leaves `.llvmup-install.lock`, first confirm that no
installer is running, then remove that lock and reinstall the complete package.

Installed uninstallers remain available after deleting the download:

```bash
~/.local/bin/uninstall.sh
```

```powershell
& "$env:LOCALAPPDATA\llvmup\Uninstall-Llvmup.ps1"
```

For custom locations, invoke the uninstaller there. Linux records completion
locations during installation. PowerShell accepts `-NoProfile` or `-ProfilePath`
if you used a different profile. Removal does not remove LLVM toolchains.

## Selective installations

Use `llvmup install --profile compiler VERSION` for Clang, LLD, archive tools,
and coverage/profiling. `minimal` contains Clang and LLD; `full` remains the
default. Every reduced profile includes Clang resource headers and runtimes.
`compiler` also includes libc++ headers, libc++abi and libunwind on Unix platforms;
`minimal` uses the existing C++ standard library. Windows MSVC builds use the
Visual Studio standard library. All profiles still require the system SDK.
Use `-std=c++23 -stdlib=libc++` to select the bundled library on Unix; installing
it does not change Clang's default standard library. For shared-library execution,
configure an rpath to the installed library directory (which may be under
`lib/<target-triple>`), or configure your runtime loader accordingly.
The available C++23/experimental features depend on the selected LLVM release.

Selectable components include:

| Purpose | Components |
| --- | --- |
| Compiler and linker | `clang`, `lld`, `llvm-ar`, `llvm-ranlib`, `libc++` (Unix) |
| Coverage and profiling | `llvm-cov`, `llvm-profdata`, `llvm-profgen`, `llvm-xray` |
| Analysis and formatting | `clangd`, `clang-format`, `clang-tidy`, `clang-apply-replacements`, `clang-scan-deps`, `clang-query`, `clang-check` |
| Binary inspection | `llvm-nm`, `llvm-objdump`, `llvm-readobj`, `llvm-readelf`, `llvm-size`, `llvm-strings` |
| Binary editing | `llvm-objcopy`, `llvm-strip` |
| Debug information | `llvm-symbolizer`, `llvm-addr2line`, `llvm-cxxfilt`, `llvm-dwarfdump`, `llvm-dwp`, `llvm-pdbutil` |
| LLVM IR and code generation | `llvm-as`, `llvm-dis`, `llvm-link`, `llvm-extract`, `llvm-bcanalyzer`, `llvm-diff`, `llvm-mc`, `llvm-mca`, `llc`, `lli`, `opt` |

Repeat the option or
pass a comma-separated list. Without a profile, components select `custom` with
Clang as its base. With a profile, they extend that profile. Explicit CLI lists
replace `[components] include` from `.llvmup-config`; an explicit profile
overrides `[profile] type`. `custom` requires at least one component.

`clang-format` includes `clang-format-diff.py`, `git-clang-format`, and its
available editor integration scripts. `clang-tidy` also selects
`clang-apply-replacements` for applying fixes with `run-clang-tidy`.

`clang-tidy` includes `share/clang/clang-tidy-diff.py` and `bin/run-clang-tidy`
(or the corresponding alternate paths provided by the archive). Missing helpers
cause an error. These scripts use Python; they are not executed as native tools
during validation. `llvm-xray` can be selected independently without LLD.

These additions do not expand `minimal` or `compiler` automatically. Support is
limited to the catalog; specialized project suites such as MLIR, Flang and LLDB
are not selectable prebuilt components. Use `full` for the complete archive.
A selected tool must exist in the chosen release; no external package fallback
is performed. The selection preserves bundled dependencies but does not install
missing system libraries such as ICU.

For a CI toolchain with XRay and clang-tidy, without LLD:

```yaml
profile: custom
components: llvm-ar llvm-ranlib clang-tidy llvm-cov llvm-profdata llvm-xray
strip: true # Linux
verbose: true
```

Clang is included by the custom profile; clang-tidy pulls in its helpers and
`clang-apply-replacements`. On Linux, the XRay runtime/tool combination can be
checked with `python3 tests/integration/xray_smoke.py /path/to/toolchain`.
This smoke test uses GNU BFD and explicitly initializes and flushes FDR logging.

Python 3.9+ is required for selective modes and optional stripping. Plain `full`
installs do not require Python. On PowerShell the direct entry points expose
`-Profile`, `-Component`, `-Strip`, and `-VerboseMode`; the `llvmup` facade accepts
the same flags as Bash. Selective prebuilts support Linux and Windows archives;
they cannot use Windows `.exe` installers. An unavailable archive or component
is reported as an error instead of installing the full distribution.

macOS ARM64 can install complete prebuilt archives from releases that publish a
`macOS-ARM64.tar.xz` asset. Selective profiles and `--strip` are not supported
for macOS prebuilts.

The full compressed archive is downloaded and authenticated before selection.
Filtering happens during extraction, so excluded files never occupy staging
space. Selected executables retain their aliases, versioned targets and bundled
ELF/PE shared-library dependencies. The complete Clang resource tree is retained;
selected libc++ headers and libraries are retained as well; unrelated static
libraries and tools are omitted. Missing selected libc++ files cause an error. Archives containing unsafe
selected links, traversal paths or duplicate members are rejected.
The downloaded archive and temporary staging files are cleaned up automatically
when installation finishes, including failures; no cleanup flag is needed.
During extraction, disk usage includes the compressed archive and selected files.

Selective TAR extraction reads forward, writing selected files as they arrive.
Links are created after their targets; dependencies that appeared earlier in the
archive are collected for an additional sequential pass. No uncompressed TAR is
stored on disk. Each pass reports its decompressor, elapsed time and file count.

For `.tar.xz`, llvmup automatically uses native `xz` 5.4+ when available. It uses
up to four threads (bounded by the available CPUs) and a 256 MiB memory budget for
multithreaded decompression. XZ can reduce parallelism when blocks or memory do not
permit it. Other TAR formats, or systems without compatible `xz`, use the Python
sequential reader. ZIP handling is unchanged. Both TAR readers share selection,
link and dependency handling.

Environment variables can override the decompressor for selective TAR installs:

```bash
LLVMUP_EXTRACT_THREADS=2 llvmup install --profile compiler 23.1.2
LLVMUP_EXTRACTOR=python llvmup install --profile compiler 23.1.2
LLVMUP_EXTRACTOR=xz LLVMUP_EXTRACT_THREADS=4 llvmup install --profile compiler 23.1.2
```

`LLVMUP_EXTRACTOR` accepts `auto` (default), `python`, or `xz`; the explicit `xz`
choice requires an XZ archive and compatible executable. `LLVMUP_EXTRACT_THREADS`
must be positive and applies only to XZ. The subprocess ignores `XZ_OPT` and
`XZ_DEFAULTS` so they cannot override its settings. A decompression failure aborts
installation; it does not silently retry using Python. These settings do not
change installed content or cache identity, and do not affect the `full` profile.
Full prebuilt installs use `tar` to extract the archive in one pass. On macOS,
`tar` handles `.tar.xz`; llvmup does not invoke external `xz` for this profile.

Source builds use the same catalog with `distribution`/`install-distribution`
targets, enabling compiler-rt for runtime support and libcxx/libcxxabi/libunwind
when libc++ is selected. New selective source clones
request a shallow partial clone and sparse checkout; Git reports when the server
does not support filtering. Existing sparse checkouts expand when additional
projects or a full build are requested. Legacy source project names continue to
use the previous project-level build path; unsupported mixtures with fine-grained
tool names are rejected. Explicit CMake flags cannot redefine projects, runtimes,
or distribution components while a catalog selection is active.

`--strip` is opt-in and supports Linux ELF executables only. It requires
`llvm-strip` or `strip` on PATH, runs in staging, reports byte savings, and leaves
libraries and runtimes unchanged. A failure prevents publication. The
`.llvmup-verification.json` marker authenticates the original downloaded archive;
`.llvmup-installation.json` records the selection and whether stripping occurred.

Existing installations must match the requested components and strip setting.
Use `--name` for a separate variant, or explicitly remove the existing toolchain.
Legacy installations without a selection manifest remain usable through the
default full-install path.

## GitHub Action disk diagnostics

```yaml
- uses: Fabio3rs/llvmup@main
  with:
    version: 22.1.8
    profile: compiler
    components: clang-tidy
    strip: false # Linux only when true
    verbose: true
```

`components` accepts commas, spaces, or multiple lines. Without a profile or
components, the Action installs `full`; `strip` and `verbose` default to false.
Cache keys include the normalized selection, manifest schema, strip setting,
release asset, architecture, OS, and verification policy.

Verbose logs show filesystem free space, download/staging/toolchain sizes and
the 20 largest files. Snapshots run before and after extraction and before cleanup,
including failure paths; they are phase measurements, not a continuous peak-space
measurement. The manually triggered `action-e2e` workflow enables verbose output
for installation and cache restoration on Linux, macOS ARM64, and Windows, then
compiles C/C++ and generates a coverage report. On Linux it also compiles and runs C++23 `std::println`
with the bundled libc++. No fixed installed-size guarantee applies across releases.
