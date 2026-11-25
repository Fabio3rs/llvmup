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

| Milestone | Scope | Status | Notes |
| --- | --- | --- | --- |
| A | Diagnostic & baseline tracking | Completed | `docs/ARCHITECTURE_EVOLUTION.md` |
| B | Windows PS 5.1 compatibility, `llvmup.cmd` launcher & packaging | Completed | PS 5.1 & PS 7.7 both pass 176/176 Pester tests; packaged `llvmup.cmd` validated outside checkout |
| C | Recipe contract, `.llvmup-toolchain.json` & `official` migration | In Progress | |
| D | Shared downloader, cache, verifier, 7-Zip extractor & benchmark | Pending | |
| E | Normalized resolver, precedence & capability-based environment | Pending | |
| F | `winlibs` and `llvm-mingw` providers & real Windows validation | Pending | |
| G | Ergonomic CLI (`run`, `+toolchain`, `use`, `alias`, `pin`, `sync`, `which`, `where`, `provides`, `status --explain`, `pick`, `toolchain link`, `shell`) | Pending | |
| H | Lockfile, CMake toolchain generator, `action.yml`, completion, doctor & docs | Pending | |
| I | Final test suites, benchmarks, security/perf audit & report | Pending | |
