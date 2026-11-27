# Recipes

A recipe describes one toolchain distribution (a *provider*). Recipes are JSON files shipped with
llvmup in `libexec/recipes/`; they are trusted, local data. llvmup never downloads or executes a
remote recipe.

| Provider | Recipe | Upstream |
| --- | --- | --- |
| `official` | `libexec/recipes/official.json` | `llvm/llvm-project` GitHub releases |
| `winlibs` | `libexec/recipes/winlibs.json` | `brechtsanders/winlibs_mingw` GitHub releases |
| `llvm-mingw` | `libexec/recipes/llvm-mingw.json` | `mstorsjo/llvm-mingw` GitHub releases |

Both engines read the same files: the PowerShell engine (`libexec/pwsh/Llvm-Recipes.psm1`) and the
Bash engine (`libexec/sh/llvmup-engine.sh`, which needs `jq`). `tests/integration/engine_parity.sh`
checks that both resolve the same release, asset, digest and identity from recorded upstream metadata.

## Contract

```text
resolve(request, releases, host)   -> install plan   (release, asset, digest, variant, canonical id)
finalize(plan, staging)            -> normalized tree (single top directory unwrapped, bin/ present)
validate(plan, staging)            -> capabilities    (compilers, linkers, tools found on disk)
environment(manifest, target, cc)  -> environment delta (PATH, CC, CXX, AR, RANLIB, RC, LD, ...)
```

The shared infrastructure around these steps is provider independent: release listing with
pagination and fixtures, download with retries and a digest-keyed cache, verification, extraction,
staging and atomic publication, the toolchain manifest, aliases, the lockfile and process execution.

## Fields

| Field | Meaning |
| --- | --- |
| `provider`, `display_name`, `repository`, `api_url` | Identity and release source |
| `supports_source` | Whether `--from-source` builds exist (official only) |
| `profiles`, `default_profile` | Installation profiles; non-official providers only offer `full` |
| `available_compilers`, `default_compiler` | Compilers selectable with `--compiler` inside one bundle |
| `default_variant`, `supported_crts`, `supported_threads` | Variant axes (CRT, threads, exceptions, C++ library) |
| `tag_rules` | Release tag pattern and where the LLVM version comes from (`tag`, `asset_or_tag`, `release_metadata`) |
| `asset_rules` | Asset name pattern, host/arch mapping, target triples, ignored companion files |
| `verification` | Checksum/signature/attestation companions and the authorized identities |
| `layout` | Expected top directories and whether a single root is unwrapped |
| `tools` | Logical tool name -> relative path candidates (per OS where needed) |
| `path_constraints` | Documented, verified limitations of an installation path (see below) |

### `path_constraints`

WinLibs GCC (collect2/ld) cannot link when the installation prefix contains spaces; Clang from the
same bundle works. This was reproduced with real extractions of GCC 16.2.0 r3 under a prefix without
spaces (works), an accented prefix (works) and a prefix with spaces (`C:/Users/Fulano: file not
recognized`). The recipe declares it:

```json
"path_constraints": [
  { "compilers": ["gcc"], "forbid_whitespace": true, "reason": "...", "remedy": "..." }
]
```

`install` warns when the destination matches a constraint, and environment construction (`use`,
`run`, `env`, `shell`, `cmake-toolchain`) warns when the selected compiler is affected. Nothing is
blocked: Clang remains usable from the same installation.

## Adding a provider

1. Write `libexec/recipes/<provider>.json` with the fields above.
2. Add asset selection for its naming scheme to both engines (`Select-Llvm*Asset` in PowerShell and
   `ENG_CANDIDATES_JQ` in Bash) only if the declarative `asset_rules` are not enough.
3. Record real upstream metadata in `tests/fixtures/releases/<provider>.json` and add parity cases.
4. Add the file to `packaging/runtime-files.tsv` so packages and installers ship it.
