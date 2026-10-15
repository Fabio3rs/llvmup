# Maintenance review

Review focused on fixes, cleanup, and fragile behavior. This is not a feature
backlog.

## High priority

1. [x] **Windows source builds reported success without building anything.** The
   public `--from-source` option already promises this behavior, so completing
   it is a bug fix, not a new feature. Fixed in the current work.
2. [x] **Bash deactivation can leave `CC` and `CXX` set** when they were unset before
   activation. Preserve the distinction between an unset and an empty value.
3. [x] **`Llvm-Functions.psm1` shadows functions from the core module** with older
   copies. Remove the duplicates and keep one implementation.
4. [x] **Legacy PowerShell default-link code removes junctions recursively.** Route
   every caller through the safe core implementation.

## Medium priority

5. [x] Bash accepts source-only install options and forwards them to the prebuilt
   installer, which rejects them. Validate options according to install mode.
6. [x] `llvmup install --help` uses an unquoted heredoc and executes command
   substitutions from its examples. Make help output inert.
7. [x] Project path settings can leak from one Bash project configuration into the
   next. Reset values that came from the previous configuration.
8. [x] The lower bound for `~1.2.3` is implemented as `1.2.0` in Bash and
   PowerShell. Preserve the requested patch version.
9. [x] Verbose archive extraction can hide a failing `tar` exit status, and install
   validation happens after publishing the destination. Propagate failures and
   install through a staging directory.
10. [x] `docs/ROADMAP.md` is referenced by tracked documentation. The file is now
    present in the working tree and must be included in the next commit.

## Low priority

11. [x] The local test runner sources an interactive user shell to look for
    PowerShell. Skip PowerShell tests cleanly when `pwsh` is unavailable.
12. [x] Shell completion ignores the canonical `LLVM_TOOLCHAINS_DIR` and
    `LLVM_HOME` variables. Use the same directory precedence as the commands.

For each confirmed defect, prefer a small regression test and a localized fix.
Avoid new abstraction layers unless they remove an existing duplicate.

All items above have regression coverage where the behavior can be exercised
without downloading or compiling a complete LLVM release.
