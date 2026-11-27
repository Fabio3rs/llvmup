# LLVMUP multi-provider evolution: final report

## Stabilization on `dev`

The baseline at `14fc405` passed all 180 Pester tests on each Windows engine,
343 Bats tests with one skip in WSL2, 20 Python selection tests, and all 19
release-resolution parity cases against Linux PowerShell.

- The consolidation in `14fc405` routed the root Action and historical prebuilt
  entry points through the provider installers and removed the redundant
  `Download-Llvm-Enhanced.ps1` forwarder. Source builds and selective extraction
  retain their specialized paths. Shell adapters still activate real binaries in
  the current session and delegate temporary execution to a child process.
- `4a1821a` prevents aliases from silently switching identity after a name is
  reused. Locked operations bypass aliases and validate the recorded asset and
  any pinned digest. PowerShell strict reuse recognizes publisher-pinned
  Authenticode recorded at install time. The local Bats runner discovers all
  suites.
- `93d5ed3` produces LF Unix packages from Windows checkouts, removes the
  matching managed Windows profile block when the recorded path uses a short
  name, and removes repeated PowerShell module reloads. Regression coverage
  exercises CRLF packaging and equivalent Windows profile paths.
- `30ee5f0` checks that recorded compiler executables exist when an existing
  toolchain is reused, including Action cache restores and locked operations.
  It also accepts CRLF runtime inventories when installing or uninstalling
  directly from a Windows checkout.

Verification under `--locked` checks provider, release, host, asset identity,
and any digest pinned by the lockfile. Locks for upstream assets without a
published digest can still pin the release and asset ID. The digest describes
the original archive. Reuse checks its recorded verification result and the
presence of compiler executables.

On the Windows host, the matrix installed real archives from a copied cache
using recorded metadata. LLVM-MinGW x64 and WinLibs x64 UCRT with Clang and GCC
passed all ten checks, including C/C++ compile and link, execution, DLL and
static library creation, resource compilation, debug and header inspection, and
CMake. Official LLVM 23.1.6 passed freestanding compilation and object
inspection. Its hosted MSVC checks require Visual Studio and the Windows SDK.

Both release packages installed and upgraded from local package version
`v0.0.1` to `v0.0.2` outside the checkout. The
Windows bootstrap used the generated ZIP and checksum file. The Linux package
in WSL2 built and ran a native C executable with official LLVM and built a
Windows x64 PE with LLVM-MinGW. Bash and Zsh switched between the actual
toolchains and restored the prior PATH and CC. Uninstall preserved the test
toolchains and personal profile content on both platforms.
The Windows package lifecycle also passed on a network-disabled Windows
Sandbox using Windows PowerShell 5.1. Both Windows engines passed a separate
real-toolchain session test that switched from official LLVM to WinLibs,
executed LLVM-MinGW through `+toolchain`, then restored PATH and CC.

The Windows and Unix composite Action steps were run locally with the offline
official release fixture. Resolve, install, reuse and export succeeded. Both
engines rejected a restored manifest with a different digest. The Unix Action
step also rejected a cache missing its recorded compiler. The root `action.yml`
continues to use the same installers as the CLI.

Nine interleaved fresh process measurements on the Windows host gave these
median times for a temporary empty toolchain directory. The change avoids
forcing helper modules to reload and reuses the core module for disk usage.
PowerShell 7 showed a small improvement in this run. PowerShell 5.1 showed no
speedup.

| Windows engine | Profile module import, before → after | Import and `llvmup list`, before → after |
| --- | ---: | ---: |
| PowerShell 7.7.0 (Store) | 825 → 796 ms | 860 → 818 ms |
| Windows PowerShell 5.1 | 866 → 877 ms | 1,021 → 1,038 ms |

On WSL2, nine interleaved runs with both checkouts on the Linux filesystem
and two installed toolchains gave `list` 585 → 567 ms, `status --json`
41 → 42 ms, `which clang` 189 → 187 ms, and profile function load plus
`use` 759 → 792 ms. These measurements did not show a consistent Bash gain.

The extraction and runner suites cover TAR.ZST and streaming behavior
separately from this startup benchmark. Extraction throughput was outside
this comparison.

The final code passed 184 Pester tests on each Windows engine. The local runner
on WSL2 passed 347 Bats tests and all 20 Python selection tests. One legacy
Bats command-parsing stub was skipped by design. The WSL1 full run at
`93d5ed3` passed 345 Bats tests with the same skip and all 20 Python selection
tests. Release-resolution parity against Linux PowerShell passed all 19 cases.
The suites cover shell completion, environment restoration, child exit codes,
lock recovery, interrupted replacements and archive extraction failures.

Hosted `tests.yml`, `action-e2e.yml`, and `release.yml` still require GitHub
CI. macOS, Windows ARM64 execution, WinLibs MCF and i686/MSVCRT, LLVM-MinGW
MSVCRT/armv7, and hosted MSVC compilation were outside this verification.
WinLibs GCC still requires an installation directory without spaces to link.
The local changes are suitable for CI validation before considering a merge.

## Earlier multi-provider verification

State of the `dev` branch after the last verification run (2026-11-26). Details and raw numbers live
in `docs/ARCHITECTURE_EVOLUTION.md`, `docs/PROVIDERS.md` and `docs/EXTRACTION.md`. Nothing was pushed,
tagged or released; every commit is local.

## 1. Summary

LLVMUP manages three providers (`official`, `winlibs`, `llvm-mingw`) from JSON recipes, with a
PowerShell engine (`libexec/pwsh`) and a Bash engine (`libexec/sh`) that share schemas, manifests
and lockfiles. Windows is first class (PowerShell 5.1 and 7, `llvmup.cmd`, a bootstrap package).

## 2. Architecture

- `libexec/recipes/*.json`: provider recipes (trusted internal data, never fetched or executed
  remotely).
- Resolver, downloader (cache by digest, retries, lock, staging, atomic publish, rollback), verifier
  (SHA-256/512, API digest, GPG, attestations through `gh`, Authenticode; `warn`/`strict`/`skip`),
  extractors (7-Zip stream/pipe, tar, native ZIP, optional Python, `.tar.zst`), manifest
  `.llvmup-toolchain.json`, declarative environment delta, runner, CMake toolchain generator.
- No compiler shims or proxies. `llvmup.cmd` only launches llvmup itself.

## 3. Providers and variants

| Provider | Hosts | Variants |
| --- | --- | --- |
| official | Windows (MSVC target), Linux, macOS | profile (`full`, selective components) |
| winlibs | Windows | CRT (UCRT/MSVCRT), arch, threads, compiler (Clang or GCC) |
| llvm-mingw | Windows, Linux, macOS | CRT, target (x86_64, i686, aarch64, armv7) |

## 4. Commands

`install`, `use` (`-`, `--auto`, `--install`), `run`, `+toolchain`, `shell`, `alias`, `default`,
`pin`, `sync [--locked]`, `config lock`, `run --locked`, `update`, `pick`, `which`, `where`,
`provides`, `info`, `status --explain/--json`, `toolchain link/unlink`, `cmake-toolchain`,
`list --providers`, `list --remote --provider`, `resolve --config`, `install --use`.

```powershell
llvmup install winlibs@23 --crt ucrt
llvmup run winlibs@23 --compiler clang -- clang++ -std=c++23 main.cpp -o main.exe
llvmup cmake-toolchain llvm-mingw@23 --target aarch64-w64-mingw32 --output toolchain.cmake
```

## 5. Compatibility

Windows PowerShell 5.1 and PowerShell 7 (Windows), Bash and Zsh (Linux/macOS code paths), Bats on
WSL1 Ubuntu 24.04. Existing commands and the official provider behaviour are preserved.

## 6. Bugs fixed in the last verification rounds

- Windows PowerShell 5.1 hit MAX_PATH while extracting ZIP archives on a clean Windows: staging
  suffixes are now 8 hex characters and ZIP targets of 240+ characters use `\\?\`.
- The Bash engine hid the compiler's own message when validation failed.
- Earlier in the branch: 7-Zip streaming deadlocks and end-of-archive handling, permanent locks
  after a crash, interrupted replacements, `LLVM_SYS_<major><minor>_PREFIX`, `use -` history,
  target runtime DLL ordering for llvm-mingw, PowerShell 5.1 argument and encoding issues.

## 7. Tests (executed)

| Suite | Environment | Result |
| --- | --- | --- |
| Pester 6.2.0 | PowerShell 7.7, Windows 10 22H2 | 218/218 |
| Pester 6.2.0 | Windows PowerShell 5.1 | 218/218 |
| Bats 1.10 | WSL1 Ubuntu 24.04 | 354/354 |
| Engine parity Bash x PowerShell | WSL, Store `pwsh.exe` and PowerShell 7.7 for Linux | 19/19 each |
| Real-toolchain matrix (`scripts/toolchain_matrix.ps1`) | Windows host, PS 7 and 5.1 | all PASS except WinLibs GCC with a space in the path (documented upstream limit) |
| Same matrix, clean Windows Sandbox | PS 5.1, package from `packaging/build.py` installed outside the checkout | llvm-mingw x64/i686/arm64 and WinLibs Clang/GCC: every step PASS (arm64 Execute SKIP) |
| Official Linux install + native build | WSL2 (kernel 6.18, Ubuntu 24.04) | PASS (C17, C++23) |
| Linux -> Windows cross | WSL1 + Windows host | x86_64 and aarch64 build; x86_64 executed on Windows; CMake cross PASS |

## 8. Benchmarks

`docs/EXTRACTION.md`. Idle host, PowerShell 7.7: llvm-mingw ZIP 12.1 s (.NET ZIP), 13.9 s (Python),
17.1 s (7-Zip); WinLibs 7z 27.6 s (7-Zip), WinLibs ZIP 27.6 s (.NET), 34.1 s (Python), 38.9 s
(7-Zip). All backends produced identical trees. Command latency: Bash engine 0.10-0.44 s,
PowerShell CLI child process about 1 s (0.45 s is module import).

## 9. Upstream limitations

- WinLibs GCC (`collect2`/`ld`) cannot link when the installation path has spaces (Clang from the
  same bundle can). llvmup warns at install and in `env`.
- llvm-mingw C++ programs need `libc++.dll` and `libunwind.dll` from the toolchain at run time.
- Official Windows LLVM targets MSVC and needs Visual Studio/Windows SDK for hosted builds.
- Windows PowerShell 5.1 `-File` rejects a lone `-` argument.
- No upstream signatures exist for WinLibs and llvm-mingw archives: checksums prove integrity only,
  and llvmup reports authentication as not provided.

## 10. Not tested / pending

- macOS hosts and Windows ARM64 execution: no such hardware here; the CI jobs are prepared.
- GitHub workflows (`tests.yml`, `action-e2e.yml`, `release.yml` attestation): never run; running
  them requires pushing, which the project rules forbid and for which no credentials exist here
  (the maintainer will push manually). The attestation action is pinned by SHA.
- Official LLVM for Linux: verified on WSL2 (unassisted install in 3 min 53 s, native C17/C++23
  build and run; Bats 354/354 and parity 19/19 repeated there). WSL1 cannot exec the 282 MB `clang`.
- WinLibs MCF threads, WinLibs i686/MSVCRT and llvm-mingw MSVCRT/armv7 end to end.

## 11. Git

Branch `dev`; all work is in local commits. Untracked and left alone: `C/`, `PLAN.md`,
`implementation_plan.md`.

## 12. Windows quick start

```powershell
# from the release package
.\packaging\Install-Llvmup.ps1
llvmup install llvm-mingw@latest
llvmup run llvm-mingw@latest -- clang --version
llvmup use winlibs@23 --install     # in a PowerShell session with the module loaded
```
