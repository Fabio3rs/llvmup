# LLVMUP distribution

`runtime-files.tsv` is the explicit inventory shared by the package builder and
installers. Keep runtime filenames flat for compatibility with public scripts,
relative module loading and the root GitHub Action. The repository's runtime
files remain at their existing paths; packaging code lives here. New runtime
files belong in the inventory. `githubreleases.json` stays available to release
resolution and tests. Local reports and untracked files are never globbed into
release packages.

Build from any working directory with Python 3 (maintainers only). Replace
`vX.Y.Z` with the release tag to package:

```bash
python3 packaging/build.py vX.Y.Z --output /tmp/llvmup-dist
```

The builder creates reproducible Linux and Windows packages, two bootstraps
pinned to that version, and `SHA256SUMS`. File modes and timestamps are normalized;
the same inputs and Python/compression implementation produce identical output.
Release packages include `VERSION`; installations record it as `llvmup-version`.

After committing and pushing the changes, create an unused release tag on that
commit, for example:

```bash
git tag -a vX.Y.Z -m 'LLVMUP vX.Y.Z'
git push origin vX.Y.Z
```

Use the next appropriate version. The release workflow
runs the Linux and Windows test workflow first, builds the assets, and publishes
them with generated notes using the existing tag. Tags with a suffix, such as
`vX.Y.Z-rc.1`, produce prereleases and do not supply the stable `latest` URL.
A first prerelease is useful for validating the real download path before a
stable release. If the release already exists (including one created in the
GitHub UI), the workflow reuses it and uploads the missing assets, preserving
its title, notes and draft/prerelease status. A release marked as a prerelease
in GitHub remains a prerelease even if its tag has no suffix. Identical assets
are skipped on retries; differing assets cause an error rather than being
overwritten.

To complete an existing release after updating this workflow, open **Actions →
Release LLVMUP → Run workflow**, select `main`, and enter the existing tag (for
example `v0.8.0`). The workflow uses the updated publishing logic but checks out,
tests and packages the source from that tag. There is no need to move or recreate
the tag. Re-running an old failed run uses its old workflow, so use this manual
entrypoint for recovery instead.
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
