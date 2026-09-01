# LLVMUP Feature Wishlist

This document outlines potential features for LLVMUP based on observations from similar version managers (rustup, nvm, pyenv, rbenv) and LLVM-specific user needs.

## High Impact Features

### 1. Automatic Version Switching on Directory Change

**Problem**: Users must manually activate LLVM versions when switching between projects.

**Solution**: Shell hooks that detect `.llvmup-config` and auto-activate the appropriate version.

**Implementation approach**:
- Hook into `PROMPT_COMMAND` (bash), `chpwd` (zsh), or `prompt` (PowerShell)
- Walk up directory tree looking for `.llvmup-config`
- Parse config and activate version if different from current
- Cache results to avoid performance impact
- Add `auto_activate = true/false` config option

**User experience**:
```bash
$ cd ~/project-a/
(llvm:18.1.8) $ cd ~/project-b/
(llvm:19.1.0) $  # Automatically switched!
```

**Similar to**: nvm's `.nvmrc`, rustup's `rust-toolchain.toml`

---

### 2. Disk Space Management

**Problem**: LLVM toolchains are massive (5-20GB each). Users accumulate versions and run out of disk space.

**Solution**: Commands to manage and clean up old versions.

**Implemented now**:
- `llvmup disk-usage` - Show space used per version and total space
- `llvmup disk-usage -h` - Show sizes in human-readable binary units

**Still needed**:
- `llvmup cleanup` - Interactive removal of unused versions
- `llvmup cleanup --aggressive` - Remove all non-active, non-default versions
- `llvmup prune` - Keep only latest patch version of each minor (remove 18.1.6, 18.1.7 if 18.1.8 exists)
- Warning when disk space is low during installation

**Example output**:
```
$ llvmup disk-usage
8343552	llvmorg-19.1.7
10493952	llvmorg-20.1.0
total	18837504	~/.llvm/toolchains/

$ llvmup disk-usage -h
8.0 MiB	llvmorg-19.1.7
10.0 MiB	llvmorg-20.1.0
total	18.0 MiB	~/.llvm/toolchains/
```

---

### 3. Faster Installation Experience

**Problem**: LLVM downloads are large (100MB-2GB) and builds take hours. Interruptions waste time.

**Features needed**:
- **Resume interrupted downloads** - Use `curl -C -` or `wget -c`
- **Parallel component downloads** - Download source + dependencies concurrently
- **Mirror/CDN support** - Configure alternate download sources
- **Better progress indicators** - Show percentage, speed, ETA
- **Download verification caching** - Don't re-verify on resume

**Configuration example**:
```ini
[download]
mirrors = [
  "https://github.com/llvm/llvm-project/releases",
  "https://mirror.example.com/llvm"
]
parallel_downloads = true
resume_downloads = true
```

---

### 4. Build Time Optimizations

**Problem**: Building LLVM from source takes 30 minutes to several hours. Rebuilding for patches is wasteful.

**Features needed**:
- **ccache/sccache integration** - `--use-ccache` flag, automatic detection
- **Shared build artifacts** - Reuse common objects between patch versions
- **Incremental updates** - For patch versions (18.1.7 → 18.1.8), only rebuild changed files
- **Distributed builds** - `--distributed` for distcc/icecc support
- **Build caching for CI** - Export/import build cache

**Usage**:
```bash
$ llvmup install --from-source --use-ccache llvmorg-18.1.8
# First build: 2 hours
$ llvmup install --from-source --use-ccache llvmorg-18.1.9
# Incremental: 15 minutes
```

---

### 5. Shims / Automatic PATH Management

**Problem**: Users must activate a version or manually manage PATH. Activation doesn't persist across terminal sessions.

**Solution**: Single `~/.llvm/shims/` directory with smart wrappers that delegate to the active/default version.

**How it works**:
- Install creates shims for `clang`, `clang++`, `llvm-config`, etc. in `~/.llvm/shims/`
- Add `~/.llvm/shims/` to PATH once (in profile)
- Shims check `$_ACTIVE_LLVM` or read `~/.llvm/active` file
- Delegate to appropriate version's binary

**Benefits**:
- `clang` "just works" without activation
- No shell modification needed
- Persists across terminal sessions
- Works with sudo, cron, scripts

**Similar to**: pyenv shims, rbenv shims

---

## Medium Impact Features

### 6. Version Recommendation System

**Problem**: Users don't know which LLVM version to use for their project.

**Solution**: Analyze project files and suggest compatible versions.

**Implementation**:
```bash
$ llvmup suggest
Analyzing project...
  Found: CMakeLists.txt with "LLVM 18.0 or newer"
  Found: .github/workflows/ci.yml testing LLVM 18, 19
  Recommendation: llvmorg-18.1.8 (stable, matches CI)
  Alternative: llvmorg-19.1.0 (latest stable)
```

**Detection methods**:
- Parse `CMakeLists.txt` for `find_package(LLVM ...)`
- Read `.llvmup-config` in dependencies
- Check CI configs (GitHub Actions, GitLab CI)
- Analyze compiler flags for version-specific features

---

### 7. Update Notifications

**Problem**: Users miss new LLVM releases.

**Solution**: Check for updates periodically and notify users.

**Features**:
- Check on startup (with cache to limit frequency)
- `llvmup update-check` manual check
- `llvmup upgrade <version>` - Upgrade and migrate configs
- Configurable: `update_check_frequency = daily/weekly/never`

**Example**:
```bash
$ llvmup list
New version available: llvmorg-19.1.1 (you have 19.1.0)
Run 'llvmup install llvmorg-19.1.1' to upgrade
```

---

### 8. Better Build Failure Diagnostics

**Problem**: LLVM builds fail with cryptic errors. Common issues repeat across users.

**Solution**: Detect common failure patterns and suggest fixes.

**Common issues**:
- Insufficient RAM (needs 16GB+) → Suggest swap or `-j` reduction
- Missing dependencies → Suggest package install commands
- Incompatible CMake version → Show required version
- Ninja not found → Suggest installation
- Disk space exhausted → Show space requirements

**Example**:
```bash
$ llvmup install --from-source llvmorg-19.1.0
...
ERROR: Build failed (out of memory)

DIAGNOSIS:
  LLVM builds require at least 16GB RAM
  You have: 8GB

SUGGESTIONS:
  1. Reduce parallelism: --cmake-flags="-j2"
  2. Enable swap: sudo fallocate -l 16G /swapfile && ...
  3. Use prebuilt: llvmup install llvmorg-19.1.0
```

---

### 9. Partial Installations

**Problem**: Full LLVM installs include many unused tools, wasting gigabytes.

**Solution**: Install only needed components, remove unused tools post-install.

**Features**:
```bash
# Install only clang, clang++, lld
$ llvmup install --minimal llvmorg-18.1.8

# Remove unused tools from existing installation
$ llvmup slim llvmorg-18.1.8
Analyzing installation...
  Can remove: llvm-ar, llvm-nm, llvm-objdump, ... (saves 2.3GB)
Proceed? [y/N]
```

**Configuration**:
```ini
[install]
components = ["clang", "clang++", "lld", "llvm-config"]
strip_binaries = true
remove_static_libs = false
```

---

### 10. CI/CD Optimizations

**Problem**: CI builds waste time downloading/building LLVM repeatedly.

**Solution**: CI-specific features for caching and speed.

**Features**:
- GitHub Actions integration: `llvmup-action`
- Export/import cached toolchains
- Docker layer-friendly installation
- Lock file generation for reproducible builds

**GitHub Actions example**:
```yaml
- name: Setup LLVM
  uses: llvmup/setup-llvmup@v1
  with:
    version: '18.1.8'
    cache: true
```

**Cache export**:
```bash
$ llvmup cache export llvmorg-18.1.8 > llvm-cache.tar.gz
$ llvmup cache import llvm-cache.tar.gz
```

---

## Nice to Have Features

### 11. Multi-Version Testing

**Problem**: Projects need to test against multiple LLVM versions for compatibility.

**Solution**: Commands to run tests across version ranges.

**Usage**:
```bash
# Test with all installed 18.x versions
$ llvmup test-across '18.*' -- make test

# Test with specific versions
$ llvmup test-across 18.1.8 19.1.0 20.0.0 -- cmake --build build && ctest

# Output:
Testing with llvmorg-18.1.8... PASS (2.3s)
Testing with llvmorg-19.1.0... PASS (2.1s)
Testing with llvmorg-20.0.0... FAIL (see logs)
```

---

### 12. Platform-Specific Optimizations

**Problem**: Generic builds don't take advantage of CPU-specific features.

**Solution**: Auto-detect platform and optimize builds.

**Features**:
- Auto-detect ARM64 vs x86_64
- CPU-specific optimizations (`-march=native`)
- Cross-compilation support
- Multiple architectures side-by-side

**Usage**:
```bash
$ llvmup install --optimize-for-cpu llvmorg-18.1.8
Detected: AMD Ryzen 9 5950X (x86_64, AVX2, AVX512)
Building with -march=znver3...

$ llvmup install --cross-compile aarch64-linux llvmorg-18.1.8
```

---

### 13. Plugin System

**Problem**: Different users have different workflows and IDE integrations.

**Solution**: Allow community plugins to extend LLVMUP.

**Plugin types**:
- IDE integrations (VSCode, CLion, Vim)
- Build system integrations (Bazel, Meson)
- Custom version sources (corporate mirrors)
- Workflow extensions (automatic builds, notifications)

**Usage**:
```bash
$ llvmup plugin install llvmup-vscode
$ llvmup plugin install llvmup-bazel
$ llvmup plugin list
llvmup-vscode (active) - VSCode integration
llvmup-bazel (active) - Bazel toolchain support
```

---

## Implementation Priority

Based on impact vs. effort:

**Phase 1** (Foundation):
1. Shell hooks for auto-switching
2. Shims system
3. Disk space management

**Phase 2** (Quality of Life):
4. Resume downloads
5. Build diagnostics
6. Update notifications

**Phase 3** (Advanced):
7. Build time optimizations (ccache)
8. Version recommendation
9. CI/CD tooling

**Phase 4** (Ecosystem):
10. Multi-version testing
11. Plugin system
12. Platform optimizations

---

## Comparison with Other Version Managers

| Feature | rustup | nvm | pyenv | LLVMUP (current) | LLVMUP (proposed) |
|---------|--------|-----|-------|------------------|-------------------|
| Auto-switching | ✅ | ✅ | ✅ | ❌ | ✅ (Phase 1) |
| Shims | ❌ | ❌ | ✅ | ❌ | ✅ (Phase 1) |
| Disk cleanup | ❌ | ❌ | ✅ | ❌ | ✅ (Phase 1) |
| Resume downloads | ❌ | ❌ | ❌ | ❌ | ✅ (Phase 2) |
| Build caching | ❌ | N/A | ❌ | ❌ | ✅ (Phase 3) |
| Multi-version test | ❌ | ❌ | ❌ | ❌ | ✅ (Phase 4) |

---

## Feedback Welcome

These suggestions are based on observations from similar tools and LLVM-specific pain points. User feedback and priorities may differ. Please open an issue to discuss any of these features or suggest new ones.
