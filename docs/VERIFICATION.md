# Download verification

llvmup separates **integrity** (the bytes are the ones the source published) from **authentication
of origin** (a cryptographic proof that an authorized identity produced them). Each provider recipe
lists which mechanisms its upstream actually publishes; llvmup never invents signatures or identities.

## Mechanisms

| Mechanism | Proves | Used for |
| --- | --- | --- |
| Digest from the GitHub API (`asset.digest`) | Integrity | All providers when GitHub reports it |
| Companion checksum (`.sha256`, `.sha512`, ...) | Integrity | WinLibs, llvm-mingw, official (when present) |
| GPG signature (`.sig`) against `release-keys.asc` | Origin | Official releases that publish it |
| Sigstore / GitHub attestation (`.jsonl`, `gh attestation verify --repo llvm/llvm-project`) | Origin | Official releases that publish it |
| Authenticode | Signature of one PE file | Official installers; no publisher identity is pinned because upstream does not document one |

An Authenticode signature, when present, proves only the signed executable, not the rest of the
archive. WinLibs and llvm-mingw publish no signatures or attestations; for them the strongest
available result is a verified checksum.

## Policies

| Policy | Behaviour |
| --- | --- |
| `warn` (default) | Verify everything available. A digest mismatch, a bad signature or a wrong identity fails. When nothing authenticates the origin, install with a warning. |
| `strict` | Additionally require an authenticated origin from the provider's authorized identity. Providers without signatures cannot be installed in strict mode; llvmup never downgrades strict to warn. |
| `skip` | Skip signature, attestation and companion checksum verification. A SHA256 digest supplied by release metadata or a lockfile still constrains the download. |

Select it with `--verify`, `LLVMUP_VERIFY_POLICY`, or the Action's `verify` input. Locked operations
(`sync --locked`, `run --locked`) require the recorded provider, release, host, asset and any pinned
digest to match the installed manifest. Locked operations under `strict` also require a recorded
GPG or Sigstore verification, or Authenticode verification against a publisher pinned by the
Windows recipe. The lockfile can pin an archive digest when upstream provides one.
The installed manifest records the archive verification result from installation time.
Locked commands resolve the recorded toolchain identity directly, even when a local alias
has the same name.
Reuse, including Action cache hits, also checks that the recorded compiler executables are
present. The archive digest records what was installed. It does not hash the extracted tree
on every reuse.

## What is recorded

Each installation stores the result in `.llvmup-toolchain.json` (`verification`) and the legacy
`.llvmup-verification.json`:

```json
"verification": {
  "policy": "warn",
  "checksum": "valid",
  "gpg": "not-provided",
  "attestation": "unavailable",
  "methods": ["checksum-only"],
  "authenticated_identity": null,
  "scope": "archive"
}
```

`not-provided` means upstream publishes no such proof; `unavailable` means it exists but the
verifier (for example `gh`) is not installed; `valid`/`invalid` are actual results. Installations made
before manifests existed are reported as `unverified` rather than given an invented history.

A download reused from the cache is checked again against the expected digest before extraction.
The GitHub Action uses the same provider engines for `official`, `winlibs` and `llvm-mingw`.
Its cache key includes the asset identity, component selection and policy. Installation checks that
resolution still returns the asset announced before cache restore.
Tokens (`GH_TOKEN`, `GITHUB_TOKEN`) are passed only to the processes that need them and never written
to manifests, lockfiles or logs.

## llvmup's own packages

Release packages ship `SHA256SUMS`; `bootstrap.ps1` and `bootstrap.sh` refuse a package whose
checksum does not match. A checksum detects corruption; it does not authenticate a mirror. Signing or
attesting the packages in CI is prepared in the release workflow but is not active until the
repository enables it (see `docs/ROADMAP.md`).
