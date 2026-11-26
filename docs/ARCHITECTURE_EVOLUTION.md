# LLVMUP Architecture Evolution & Tracking Log

This document records the baseline diagnostic, architectural decisions, implementation milestones, test progress, benchmarks, and platform verification status for evolving LLVMUP into a multiplatform, recipe-based LLVM/C/C++ distribution manager.

---

## 1. Initial Diagnostic (Baseline at `v0.8.0` / branch `dev`)

### 1.1 Entry Points & Runtime Surface
- **Bash / Zsh**:
  - CLI entrypoint: `llvmup`
  - Shell integration & functions: `llvm-functions.sh` (3,379 lines; contains CLI wrapper, release queries, verification, version matching, activation, auto-activation, project config)
  - Helper executables: `llvm-prebuilt`, `llvm-build`, `llvm-activate`, `llvm-deactivate`, `llvm-vscode-activate`
  - Doctor: `llvmup-doctor.sh` + `llvmup-doctor-{filesystem,environment,project,probes}.sh`
  - Completion: `llvmup-completion.sh`, `_llvmup`, `llvmup-completion-common.sh`
- **PowerShell**:
  - Facade module: `Llvm-Functions.psm1`
  - Core module: `Llvm-Functions-Core.psm1`
  - Helper scripts: `Download-Llvm.ps1`, `Download-Llvm-Enhanced.ps1` (thin compatibility forwarder), `Install-Llvm.ps1`, `Activate-Llvm.ps1`, `Deactivate-Llvm.ps1`, `Activate-LlvmVsCode.ps1`, `Llvm-Config.ps1`, `Llvm-Default.ps1`, `Get-UserHome.psm1`
  - Doctor: `Llvm-Doctor.psm1`, `Llvm-Doctor.ps1`, `Llvm-Doctor-Deep.ps1`
  - Completion: `Llvm-Completion.psm1`
- **Shared Selective Extraction Engine**:
  - `libexec/llvmup-selection.py`, `libexec/llvmup-components.json`, `libexec/llvmup-selection.sh`, `libexec/Llvm-Selection.psm1`
- **CI / Packaging / Distribution**:
  - `action.yml`, `.github/workflows/{tests,release,action-e2e}.yml`
  - `packaging/{runtime-files.tsv,build.py,bootstrap.sh,bootstrap.ps1,install-files.sh,Install-Llvmup.ps1,publish.sh}`
  - `install.sh`, `uninstall.sh`, `Uninstall-Llvmup.ps1`

### 1.2 Pre-Existing Bugs, Duplications, and Platform Gaps
1. **Windows PowerShell 5.1 Encoding & Parser Failures**:
   - `Llvm-Functions.psm1`, `Download-Llvm.ps1`, `Install-Llvm.ps1`, `Llvm-Default.ps1`, `tests/unit/ActivationDeactivation.Tests.ps1`, and `tests/unit/CompleteIdempotencyWorkflow.Tests.ps1` are encoded as UTF-8 without BOM while containing literal multi-byte UTF-8 emojis/Unicode characters (`📋`, `⚠️`, `✅`, `❌`, `💡`, `→`), causing PowerShell 5.1 (`powershell.exe`) to misdecode them under the ANSI codepage and fail with `ParseException`.
2. **PowerShell 5.1 Runtime Incompatibilities**:
   - `Llvm-Functions-Core.psm1` (`Restore-LlvmEnvironment`) uses `ConvertFrom-Json -AsHashtable` (introduced in PowerShell 6.0).
   - `Restore-LlvmEnvironment` assigns `$env:CC = $Backup.CC` directly instead of distinguishing `$null` (unset) vs empty string, leaving empty variables behind on PS 5.1/7.
   - `Llvm-Completion.psm1` references `$IsWindows` without fallback for PowerShell 5.1.
   - `Download-Llvm.ps1` uses `System.Net.WebClient` without configuring TLS 1.2+ on PS 5.1 or applying `$TimeoutSec` to `WebClient`.
   - `Llvm-Functions.psm1` (`llvmup`) binds `param($First)` + `$args`, risking parameter collisions and preventing clean pass-through of flags/separators.
3. **Missing Non-Interactive Windows CLI Launcher**:
   - No `llvmup.cmd` / standalone CLI entrypoint exists on Windows; child processes (CMake, scripts, `cmd.exe`, CI) cannot invoke `llvmup` without manually importing `Llvm-Functions.psm1`.
4. **Hardcoded Single-Provider Assumptions**:
   - Release discovery hardcodes `llvm/llvm-project` and `llvmorg-X.Y.Z`, lacks GitHub `Link` pagination (`Download-Llvm.ps1` fetches only the default 30 releases), and lacks support for `winlibs` and `llvm-mingw`.
   - `Download-Llvm.ps1` checks `.exe` installers while LLVM 23+ publishes `.msi` and `.tar.zst` alongside `.tar.xz`; `llvm-functions.sh` lacks Windows archive mappings.
   - Toolchain identity relies solely on directory naming (`llvmorg-*`, `source-*`) rather than a versioned manifest.
5. **Extraction, Download, Cache & Concurrency Gaps**:
   - `Download-Llvm.ps1` probes `C:\Program Files\7-Zip\7z.exe` in `Test-ExtractorAvailable` but invokes bare `7z` in `Extract-Archive`, ignores `7z` exit codes, and uses recursive `Copy-Item` instead of directory moves.
   - No download cache, no concurrent-install lock on toolchain operations, and `.sha512` checksums are unsupported.
6. **Duplications & Legacy Divergences**:
   - `Activate-Llvm.ps1`, `Deactivate-Llvm.ps1`, `Activate-LlvmVsCode.ps1`, and `Llvm-Config.ps1` duplicate logic from `Llvm-Functions-Core.psm1` and ignore `LLVM_HOME` / `LLVM_TOOLCHAINS_DIR`.
   - Both `llvm-config-apply` and `Invoke-LlvmUpConfig` (`apply`) unconditionally route to `--from-source` instead of distinguishing `prebuilt` vs `source`.
   - `action.yml` duplicates Windows resolution/activation inline instead of sharing CLI logic.
7. **Test Runner Gaps**:
   - `tests/_pester_runner.ps1` requires Pester 5/6 (`-Output Detailed`), while Windows ships Pester 3.4.0 by default.

### 1.3 Baseline Test Results (Before Any Implementation Changes)
- **PowerShell 7.7.0 (`pwsh -NoProfile`) with Pester 6.1.0**:
  - `174 Passed, 0 Failed, 0 Skipped` across 19 `.Tests.ps1` files.
- **Windows PowerShell 5.1 (`powershell.exe -NoProfile`) with Pester 6.1.0**:
  - `91 Passed, 60 Failed, 0 Skipped` (plus 3 discovery failures: `ActivationDeactivation.Tests.ps1`, `CompleteIdempotencyWorkflow.Tests.ps1`, `Download-Llvm.Tests.ps1`; and 1 `BeforeAll` failure: `Install-Llvm.Tests.ps1` — primarily driven by UTF-8 without BOM parse errors and `Selection.Tests.ps1` Windows `libc++` check).
- **Python Selection Tests (`python tests/unit/test_selection.py` on Windows)**:
  - `20 tests: 8 ok, 3 skipped, 1 FAIL, 8 ERROR` (pre-existing Windows issues: `libc++` excluded on Windows MSVC in `test_libcxx_selection_and_platform_defaults` and `test_normalized_selection_and_defaults`; `WinError 193` launching bash script `llvm-prebuilt`; `WinError 4390` `os.readlink` on Windows without symlink privileges; `.exe` suffix mismatch in synthetic test fixtures).
- **Bash Syntax Check (`bash -n` via Git Bash 4.4.23)**:
  - All 19 Bash/Zsh runtime and packaging scripts passed `bash -n`.
- **Bats Integration/Unit Tests**:
  - No WSL distro or native Windows `jq` installed locally; Bash test suite requires Linux/macOS CI or WSL/Docker environment (tracked as platform pending for full Bats execution if no compatible environment is present).

---

## 2. Architectural Decisions

1. **Declarative Recipes + Dual Native Engines (Zero Mandatory New Runtime Dependencies)**:
   - Provider definitions live in declarative JSON recipes under `libexec/recipes/` (`official.json`, `winlibs.json`, `llvm-mingw.json`).
   - Native PowerShell (`libexec/pwsh/*.psm1`) and Bash (`libexec/sh/*.sh`) engines consume the same recipes and emit/consume identical JSON schemas (`.llvmup-toolchain.json`, `.llvmup-lock.json`, `aliases.json`, `--json` outputs).
   - Python remains strictly optional (used only for selective `official` extraction/builds).
2. **No Transparent Compiler Shims**:
   - Real binaries (`clang.exe`, `gcc.exe`, `ld.lld.exe`, etc.) are exposed directly via `PATH` and explicit environment variables (`CC`, `CXX`, `AR`, `RANLIB`, `RC`, `LD`).
   - Only `llvmup.cmd` (a launcher for the `llvmup` manager itself) is added for ergonomic non-interactive Windows execution.
3. **PowerShell 5.1 + 7 Compatibility Policy**:
   - All `.ps1`, `.psm1`, and `.Tests.ps1` files must avoid raw UTF-8 non-ASCII characters in source literals (use ASCII or explicit `[char]`/`[char]::ConvertFromUtf32` helpers, and save PowerShell files cleanly) and avoid PS 6+ APIs (`-AsHashtable`, unguarded `$IsWindows`).
4. **Transactional Staging & Manifest-Driven Identity**:
   - Installations write `.llvmup-toolchain.json` (schema v1) alongside compatible `.llvmup-verification.json` / `.llvmup-installation.json`. Legacy directories remain usable without fabricating provenance.

---

## 3. Milestone Tracker

| Milestone | Scope | Status | Evidence |
| --- | --- | --- | --- |
| A | Diagnostic & baseline | Done | Section 1 |
| B | PS 5.1/7 compatibility, `llvmup.cmd`, packaging | Done | Pester 5.1 + 7; package installed in Windows Sandbox (section 5) |
| C | Recipes, `.llvmup-toolchain.json`, official migration | Done | `libexec/recipes/*.json`, both engines |
| D | Download, cache, verification, extraction, 7-Zip, staging, rollback, benchmark | Done | `scripts/benchmark_extract.ps1`, `docs/EXTRACTION.md` |
| E | Resolver, identities, capability-based environment, overrides | Done | Pester, Bats, parity 19/19 |
| F | WinLibs and LLVM-MinGW, real Windows validation, cross | Done (see limits) | Section 5 |
| G | `run`, `+tc`, `use`, aliases, `pin`, `sync`, `which/where/provides`, `status --explain`, `pick`, `toolchain link`, `shell`, `update` | Done in both shells | Pester + Bats |
| H | Lockfile, CMake, Action, completion, packaging, docs | Done; CI jobs prepared, not executed | `action.yml`, workflows, docs |
| I | Final review | Done | Sections 4-7 |

## 4. Bugs found and fixed after the first implementation pass

Pre-existing in the committed code before this pass, found by real runs:

| Bug | Impact | Fix |
| --- | --- | --- |
| Bash `eng_delta` jq program did not compile (`{CC: a // b}` needs parentheses) | Bash `run`, `env`, `which`, `cmake-toolchain`, `shell` failed for every toolchain; untested | Parenthesized; Bats tests added |
| PowerShell completion was never registered (no PS version has `Get-ArgumentCompleter`, so the shim always replaced `Register-ArgumentCompleter`) | No tab completion at all | Shim also registers with the real cmdlet; tested through `TabExpansion2` |
| `llvmup.cmd` with a single argument used the first character as command (`if` unrolled the token array) | `llvmup.cmd help/list/status/doctor` failed | `@(if ...)`; regression test |
| Same unrolling in `update <sel>` and in verification `methods` | `update` always failed; manifests stored `methods` as a string | Fixed; tests |
| Profile block imported without `-DisableNameChecking` | "unapproved verbs" warning in every new PowerShell session | Fixed; uninstaller accepts old and new blocks |
| Bash ignored `compiler`/`target` from `.llvmup-config` and the session | Parity gap with PowerShell | `eng_effective` carries them |
| `which clang --target T` returned the generic `clang` | On Linux the generic clang cannot find the Windows sysroot | Known tools map to the target wrappers (both engines) |
| `env <toolchain> --format json` from Bash went to the legacy path | JSON flag ignored | Routing by manifest/alias/flags |
| No-extractor case reported "No stable release matches" | Misleading on a clean Windows without 7-Zip | Explains the unpackable matching asset and how to fix |
| `LLVM_SYS_<N>_PREFIX` rounded (230 for 23.1) | llvm-sys >= 18.1 reads 231 | Both names exported |
| WinLibs GCC under a prefix with spaces | Link fails (`C:/Users/Fulano: file not recognized`) | Upstream limitation documented in the recipe; warnings; docs |

## 5. Test results (2026-11-26)

| Suite | Environment | Result |
| --- | --- | --- |
| Pester 6.2.0 | PowerShell 7.7, Windows 10 22H2 | 218/218 |
| Pester 6.2.0 | Windows PowerShell 5.1 | 218/218 |
| Bats 1.10 | WSL1 Ubuntu 24.04 (`llvmup-test`, imported from a cached rootfs) | 354/354 |
| Engine parity (Bash vs PowerShell, recorded metadata) | WSL with `pwsh.exe` (Store) and with PowerShell 7.7 for Linux installed in the distro | 19/19 in both |
| Completion (Bash/Zsh Bats; PowerShell `TabExpansion2`) | WSL; PS 5.1 and 7 | passed |
| Action provider path (composite bash steps executed locally) | WSL Ubuntu 24.04, real GitHub | resolve + download + install + `env --format github` in 41 s |
| Linux -> Windows cross (llvm-mingw 20261117) | WSL + Windows host | x86_64/aarch64 compile/link/inspect PASS, x86_64 execute PASS, CMake cross PASS |
| Windows Sandbox end to end (clean Windows, PS 5.1 only, package built by `packaging/build.py` and bootstrapped outside the checkout) | Windows Sandbox + `scripts/toolchain_matrix.ps1` | llvm-mingw x64/i686/arm64 and WinLibs Clang/GCC: every step PASS (arm64 Execute SKIP); see `docs/PROVIDERS.md` |
| Real-toolchain matrix on the host (PS 7 and 5.1) | `scripts/toolchain_matrix.ps1` | all PASS; WinLibs GCC with a space in the path FAILs at link (documented upstream limit) |

Bugs found by these runs and fixed: Windows PowerShell 5.1 extraction exceeded MAX_PATH in a clean
Sandbox (long `.installing-<guid>.raw-<guid>` prefixes; now 8-hex suffixes and extended-length ZIP
targets); the Bash engine hid the compiler's own message when validation failed.

Not executed (prepared only): GitHub workflows (`tests.yml`, `action-e2e.yml`), macOS hosts,
Windows ARM64 execution. Official LLVM for Linux installs unassisted with the Bash engine on WSL2
(3 min 53 s) and builds/runs C17 and C++23; on WSL1 the kernel cannot exec the 282 MB `clang`.
Bats 354/354 and parity 19/19 were repeated on WSL2.

Performance (idle Windows 10 host, SSD, warm cache): Bash engine `status` 0.10 s, `list` 0.14 s,
`which` 0.44 s (WSL1); PowerShell CLI child process `status` 0.9 s, `list` 1.0 s, `which` 1.0 s
(about 0.45 s of that is importing the module); the session functions (`use`, `use --auto`) run in
the already-loaded module. Extraction benchmark: `docs/EXTRACTION.md`.

## 6. Decisions

1. Declarative JSON recipes, two native engines (PowerShell, Bash+jq); Python stays optional.
2. No compiler shims; `llvmup.cmd` is a launcher of llvmup itself.
3. Target selection maps known tool names to the distribution's target wrappers.
4. Locked mode never weakens policy, never changes provider/release/asset/digest, and fails
   with the available host keys when the current host is missing.
5. Recorded upstream metadata (`tests/fixtures/releases`) drives offline and parity tests; real
   downloads are used only for final validation.
6. The Action keeps the historical official path byte-for-byte and adds a provider path through
   the same CLI.

## 7. Platform status

| Host | Shell | Providers | Status |
| --- | --- | --- | --- |
| Windows 10 x64 | PowerShell 5.1 | official, winlibs, llvm-mingw | Tested (host and Windows Sandbox) |
| Windows 10 x64 | PowerShell 7.7 | official, winlibs, llvm-mingw | Tested (host) |
| Linux x64 (Ubuntu 24.04, WSL1) | Bash | llvm-mingw (real), official (fixtures/unit) | Tested; official real install not run here |
| Linux x64 | Zsh | completion and syntax | Tested (syntax, completion tests) |
| macOS ARM64 | Bash/Zsh | official, llvm-mingw | Not available locally; CI jobs prepared |
| Windows ARM64 | any | llvm-mingw aarch64 | Cross binaries inspected only; no ARM64 host |
