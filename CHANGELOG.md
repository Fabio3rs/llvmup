# CHANGELOG

All notable changes to LLVMUP will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Version Expression System
- Smart selectors: `latest`, `oldest`, `newest`, `earliest` for automatic version selection
- Type filters: `prebuilt`, `source`, `latest-prebuilt`, `latest-source` for targeted selection
- Version ranges: `>=18.0.0`, `<=19.1.0`, `~19.1`, `18.*` for flexible version matching
- Specific version support with intelligent parsing (`llvmorg-18.1.8`, `source-llvmorg-20.1.0`)
- Expression-based auto-activation in `.llvmup-config` files
- Project-specific intelligent version selection using comprehensive expressions
- Smart fallback logic when exact versions aren't available
- Core functions: `llvm-parse-version-expression`, `llvm-match-versions`, `llvm-version-matches-range`
- 46 specialized tests for expression system functionality

#### Auto-Completion System
- Remote version fetching from GitHub API
- Intelligent 24-hour caching system with 99% speed improvement
- Context-aware completion differentiating prebuilt vs source versions
- Smart filtering based on input context
- Performance optimization with minimal API calls
- Fallback to local versions when remote unavailable
- JSON-based cache with metadata (timestamp, source)
- Automatic cache expiry (24 hours)
- Cache validation and refresh mechanisms

#### Build System
- LIBC_WNO_ERROR flag control with `--disable-libc-wno-error` option
- Configuration file support for LIBC_WNO_ERROR control
- CMake reconfiguration with `--reconfigure` flag
- Build profiles: minimal, full, custom
- Component selection for targeted installations
- Custom installation naming for build variants
- Default version management with `--default` flag
- Better CMake flag management and visibility

#### Configuration System
- Project-specific `.llvmup-config` files (INI format with array support)
- Auto-activation support
- CMake presets: Debug, Release, RelWithDebInfo, MinSizeRel
- Auto version detection during config init
- Variable trimming and whitespace handling
- Subcommands: `llvmup config init`, `load`, `apply`, `activate`

#### Logging and Verbosity
- `LLVM_VERBOSE=1` for general verbose output
- `EXPRESSION_VERBOSE=1` for expression processing details
- `EXPRESSION_DEBUG=1` for full debug output and troubleshooting
- `QUIET_MODE=1` for clean script output
- `QUIET_SUCCESS=1` for minimal success messages
- Specialized log functions: `log_error`, `log_warn`, `log_success`, `log_info`, `log_debug`, `log_config`
- User-toggleable verbose functions: `llvm-verbose-on/off`, `llvm-expression-verbose-on/off`

#### Testing
- 90+ comprehensive automated tests (BATS + Pester)
- Unit tests for core functionality validation
- Integration tests for end-to-end workflow testing
- Performance validation tests
- Cache system testing
- Remote API integration tests
- Context-aware completion tests
- Version expression tests (46 tests)
- Cross-platform test coverage (Linux + Windows PowerShell)

#### Documentation
- Comprehensive `docs/` directory with organized documentation
- `examples/` directory with interactive demos and test scripts
- README files for both `docs/` and `examples/` directories
- `docs/INSTALL.md` - Detailed installation guide
- `docs/FEATURE_SUMMARY.md` - Complete feature list
- `docs/BUILD_EXAMPLE.md` - Build system examples
- `docs/VERSION_FUNCTIONS.md` - Version management functions
- `docs/COMPLETION_UX_REPORT.md` - Auto-completion system
- `docs/CUSTOM_DIRECTORIES.md` - Custom directory configuration
- `docs/commit-sha-support.md` - Git commit SHA support
- `CLAUDE.md` - AI assistant guidance for working with codebase

#### Windows PowerShell Support
- Full feature parity with Linux/Bash implementation
- PowerShell modules: `Llvm-Functions.psm1`, `Llvm-Functions-Core.psm1`, `Llvm-Completion.psm1`
- Scripts: `Install-Llvm.ps1`, `Download-Llvm.ps1`, `Activate-Llvm.ps1`, `Deactivate-Llvm.ps1`
- Configuration management via `Llvm-Config.ps1`
- Default version management via `Llvm-Default.ps1`
- PowerShell tab completion
- Pester test framework integration

#### Core Features
- LLVM version management (install, activate, deactivate)
- Pre-built LLVM version installation from GitHub releases
- Build from source with native optimizations
- Version switching between installed versions
- VSCode integration via `llvm-vscode-activate`
- Status display with `llvm-status`
- Version listing with `llvm-list`
- Default version management with symlinks/junctions
- Custom installation directories support
- Environment variable management (PATH, CC, CXX, LD, PS1)

#### Security
- Download verification via SHA256 checksums
- GPG signature verification support
- JSONL attestation support
- `LLVMUP_SKIP_VERIFY=1` to skip verification
- `LLVMUP_REQUIRE_VERIFY=1` to require verification

### Changed
- Removed all emoji usage from user-facing messages and tests
- Simplified log messages for better scriptability
- Improved error messages and debugging output
- Better cross-platform compatibility
- Modular code structure with reusable functions

### Fixed
- Tilde range (`~19.1`) parsing using `sed` instead of bash parameter expansion
- Source version specific matching with enhanced regex support (`source-llvmorg-`)
- Expression parsing edge cases and error handling
- Timeout handling in llvm-prebuilt
- Duplicate log function overrides

---

## Development Status

This project is currently in **active development** and has not had an official versioned release yet. All features are in the `Unreleased` section above.

When the project reaches a stable state, the first official release will be tagged as `v1.0.0`.

### Planned for v1.0.0 Release
- [ ] Comprehensive documentation review
- [ ] Full test coverage verification
- [ ] Performance benchmarking
- [ ] Installation script hardening
- [ ] Windows installer improvements

### Future Considerations
- Enhanced Windows PowerShell completion
- Configuration file validation
- Plugin system for extensions
- GUI interface (optional)
- Docker integration
- Multi-platform binary distribution
- Integration with more IDEs

---

## Version Numbering

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

## Contributing

See our [Contributing Guidelines](CONTRIBUTING.md) for information on how to contribute to this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
