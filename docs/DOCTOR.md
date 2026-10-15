# Doctor diagnostics

`llvmup doctor [--verbose] [--deep] [--network] [--json]` performs no repair.
Default checks inspect files and environment without running installed compiler
binaries, loading profiles, invoking activation or fetching remote releases.
Missing installation dependencies are warnings because they are needed for
installation operations, not to run doctor. Bootstrap compiler discovery is not
proof that the compiler can build LLVM.

The Bash coordinator is independent of `llvm-functions.sh`; focused filesystem,
environment, project and probe modules report through one output function.
PowerShell has an independent `Llvm-Doctor.psm1`, a standalone script for broken
facade installations, and a child-process deep probe. Linux installation packages
all diagnostic modules. Windows uses the complete checkout, like the existing
PowerShell entrypoints. Existing public wrappers and `action.yml` are retained.

## Scope and interpretation

- Runtime files must be readable; executable Bash helpers must be executable.
- Toolchains need clang and clang++ files. Default links are inspected without
  removal or target traversal for cleanup. Staging remnants are warnings: a
  concurrent installer may still own them.
- Verification records are checked for a recognized structure. A record is
  **not proof of authenticity** or proof that installed bytes remain unchanged.
- Compiler PATH and CC/CXX/LD mismatches are warnings because wrappers and custom
  linkers can be deliberate. Missing active compiler files are failures.
- Profile checks inspect text only. Conditional imports, indirect setup scripts,
  aliases and hooks may need manual review. The Bash/Zsh function can report that
  it is loaded; a child executable cannot inspect its parent's full shell state.
- Project configuration is data, never executable code. Doctor validates basic
  assignments, required version and known profile/activation values, then uses
  the existing local version matcher. It does not claim full TOML validation.
  PowerShell reports project path overrides for review against session paths.
- A missing default, no installed LLVM, or no active LLVM is normal (SKIP).

Deep checks create and clean private temporary directories. Bash checks unset,
empty and custom environment values, range floors and project directory
restoration; PowerShell checks unset/custom restoration and range floors in a
fresh process. Completion loading is checked where packaged helpers are present.
Neither mode runs real installed compilers. Network mode requests one release
metadata page and the latest release page headers, with an eight-second timeout
per request; it follows redirects without downloading archives. GPG/gh discovery
does not establish key trust, authentication or verification-service availability.

## JSON contract

Schema version 1 is an object with `schema_version`, `checks` and `exit_code`.
Each check has `id`, `category`, `severity` (`info`, `warning`, `error`), `status`
(`PASS`, `WARN`, `FAIL`, `SKIP`), `description`, `recommendation` and `subject`.
IDs identify check types; repeated checks (files, compilers, profiles) have
separate subjects. Consumers should match IDs and subjects, not message text or
array position. Missing optional checks and new IDs must be tolerated.
Exit codes: 0 no failures, 1 diagnostic failures, 2 invalid arguments.
PowerShell's function sets `$LASTEXITCODE` without adding a Boolean to output.

## Historical motivations and regression coverage

These entries are based on commit diffs, not just subjects. Existing tests remain
the authority for algorithm and destructive-operation regressions; doctor checks
conditions a user can encounter without repeating the whole test suite.

| Commit | Failure and contributing condition | Doctor checks | Regression coverage |
| --- | --- | --- | --- |
| `9e9f957` | Redirect/proxy Content-Length was mistaken for final asset length; HEAD may fail or omit length. | Opt-in `network.github`, `network.redirect`; no assumption that length exists. | Existing `test_prebuilt_http.bats` and Python HTTP fixture cover redirects, absent/invalid lengths and HEAD failure. |
| `667c13f` | A shell function named llvmup hid the executable during completion helper discovery. | `shell.completion`, `deep.completion`; executable discovery avoids shell functions. | Existing completion integration test; doctor shadowed-function loading test. |
| `48ef082` | Zsh evaluated its source filename inside a function and called compdef before compinit. | Completion file checks; isolated shell loading. | Existing `test_zsh_completion.bats`; doctor sourced Zsh dispatch test. |
| `61d2b67`, `184182c` | Activation restoration needed coverage; later empty versus unset variables were restored incorrectly. The earlier commit primarily added tests. | `environment.restore`, `environment.stale`, `deep.activation`. | Existing activation/deactivation Bats and Pester tests; new isolated doctor probes preserve caller state. |
| `08f44d1` | Broad profile edits could remove unrelated configuration; legacy or repeated initialization compounded issues. | `shell.initialization`, `shell.legacy`; profiles are never edited. | Existing `test_safe_profile_removal.bats`; doctor duplicate and read-only tests. |
| `bdc943e`, `184182c` | Canonical/custom directory variables diverged; project overrides leaked into the next project. | Custom-path resolution, `installation.path`, `project.config`, `project.stale`; deep directory restoration. | Existing `test_enhanced_config.bats`; doctor custom paths with spaces and installer-from-another-directory tests. |
| `184182c` | Extraction could publish incomplete installs; Windows source builds lacked actual build prerequisites. | `toolchain.compilers`, `toolchain.staging`, dependency checks. | Existing prebuilt/source-install suites; incomplete/healthy fake-toolchain doctor tests. |
| `fcf809f` | Windows junction removal could fail or risk deleting target content. | Read-only `toolchain.default`; no removal probe. | Existing `LlvmUpLifecycle.Tests.ps1` target-preservation test; doctor broken-default preservation checks. |
| `6062fe0` | A one-shot autoactivation flag prevented activation in later projects. | `project.autoactivate`, `project.stale`. | Existing autoactivation and project suites; doctor inactive-project warning test. |
| `84b1386` | Missing timeout stopped prebuilt downloads despite curl's own timeout support. | `dependency.timeout` is optional; network probes use built-in request deadlines. | Doctor missing-dependency test; completion timeout fallback regression. |
| `16d1de3` | ErrorActionPreference=Stop converted handled PowerShell errors into uncaught failures. | Structured check failures and exit codes, independent of preference. | Existing lifecycle test; new Pester doctor invalid-arguments JSON test under Stop. |
| `4bbf57a` | VS Code activation assigned clangd to CC/CXX. | `environment.override`, compiler resolution warnings. | Existing `Activate-LlvmVsCode.Tests.ps1`; doctor override test. |
| `46791cd`, `4ab3ac8` | Platform separators and compiler bin paths were wrong. | Native path joining, active compiler checks. | Existing cross-platform activation tests; custom-path doctor fixtures. |
| `184182c` (range fix) | Tilde ranges discarded an explicit patch lower bound. | Controlled deep probe only; no default self-test of the parsing algorithm. | Existing Bash/Pester range suites; deep probe asserts `~18.1.8` excludes 18.1.7. |

Run `bats tests/unit/test_doctor.bats` and
`Invoke-Pester tests/unit/Llvm-Doctor.Tests.ps1` for focused coverage. The normal
runner includes the doctor suite; Windows CI discovers the Pester tests.
