# LLVMUP Roadmap

The multi-provider evolution (recipes for `official`, `winlibs` and `llvm-mingw`, the shared
engines, Windows installation, verification, extraction, lockfiles and the ergonomic CLI) is
implemented; see `docs/ARCHITECTURE_EVOLUTION.md` for what was verified and how. The priority now is
to make it predictable on every platform before adding more.

## Current priorities

1. Run the prepared CI jobs (`tests.yml`: Pester on PowerShell 5.1 and 7, Bats, engine parity;
   `action-e2e.yml`: provider matrix) and fix whatever real runners reveal.
2. Verify macOS hosts (official ARM64 and llvm-mingw universal) and Windows ARM64 execution;
   both are implemented but not yet executed.
3. Keep Bash and PowerShell behaviour aligned: extend `tests/integration/engine_parity.sh` beyond
   resolution (environment deltas, lockfile entries, manifests).
4. Release packages: add build provenance attestations for `llvmup-windows.zip` and
   `llvmup-linux.tar.gz` in the release workflow (checksums are already published and verified by
   the bootstraps); no self-generated certificates.
5. Fix reproducible bugs with a regression test each.

## Under consideration

- Selective profiles for WinLibs and LLVM-MinGW. Only `full` is offered today because their
  runtimes, sysroots and wrappers have dependencies the official component catalog does not model;
  a reduced profile must be shown to preserve them first.
- Further WinLibs variants (MCF threads, i686 MSVCRT) beyond the ones exercised in tests: the
  resolver selects them, but they have not been installed and validated end to end.
- A bounded download cache size and `llvmup cache prune`.

## Out of scope

- Transparent shims or proxies for `clang`, `gcc` and other toolchain binaries.
- Executing recipes fetched from the network.
- Building WinLibs or LLVM-MinGW from source.
