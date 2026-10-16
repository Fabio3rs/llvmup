# LLVMUP distribution

`runtime-files.tsv` is the explicit inventory shared by the package builder and
installers. Keep runtime filenames flat for compatibility with public scripts,
relative module loading and the root GitHub Action. The repository's runtime
files remain at their existing paths; packaging code lives here. New runtime
files belong in the inventory. `githubreleases.json` stays available to release
resolution and tests. Local reports and untracked files are never globbed into
release packages.

Build from any working directory with Python 3 (maintainers only):

```bash
python3 packaging/build.py v0.6.0 --output /tmp/llvmup-dist
```

The builder creates reproducible Linux and Windows packages, two bootstraps
pinned to that version, and `SHA256SUMS`. File modes and timestamps are normalized;
the same inputs and Python/compression implementation produce identical output.
Release packages include `VERSION`; installations record it as `llvmup-version`.

After committing and pushing the changes, create an unused release tag on that
commit, for example:

```bash
git tag -a v0.6.0 -m 'LLVMUP v0.6.0'
git push origin v0.6.0
```

Use the next appropriate version; `v0.6.0` is only an example. The release workflow
runs the Linux and Windows test workflow first, builds the assets, and publishes
them with generated notes using the existing tag. Tags with a suffix, such as
`v0.6.0-rc.1`, produce prereleases and do not supply the stable `latest` URL.
A first prerelease is useful for validating the real download path before a
stable release. The workflow does not overwrite existing releases or assets.
Repository Actions must have permission to create releases with `GITHUB_TOKEN`.
No release or tag is created by running the local builder.

Validation:

```bash
bats tests/unit/test_packaging.bats tests/unit/test_install_customization.bats
```

```powershell
Invoke-Pester tests/unit/Packaging.Tests.ps1 -Output Detailed
```

Routine tests mock HTTPS downloads and use lightweight packages; the Windows CI
also installs and diagnoses the ZIP produced by the actual builder. Publishing
and live GitHub downloads are exercised only after creating a release tag.

See [installation](../docs/INSTALL.md#release-bootstrap-no-git-checkout) for user
commands and the checksum trust model. A future source-layout migration can move
implementations behind compatibility entrypoints independently of this release
pipeline. Self-update and automatic repair are outside this change.
