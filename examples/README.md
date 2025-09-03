# 📚 LLVMUP Examples and Demos

This directory contains example scripts, demonstrations, and configuration files for LLVMUP.

## 🎯 Demo Scripts

### Auto-Completion Demos
- **`demo-completion.sh`**: Interactive demonstration of the enhanced auto-completion features
- **`completion-summary.sh`**: Summary overview of completion improvements
- **`test-completion-summary.sh`**: Detailed test suite summary for completion
- **`test-completion.sh`**: Interactive completion testing script

### System Testing
- **`test-activation-flow.sh`**: Test the activation/deactivation workflow
- **`test-compatibility.sh`**: Test system compatibility and requirements
- **`test-real-activation.sh`**: Real activation testing in isolated subshell

## ⚙️ Configuration Examples

- **`.llvmup-config.example`**: Example project configuration file

## 🚀 How to Use

### Running Demos
```bash
# Interactive completion demo
./examples/demo-completion.sh

# Completion system overview
./examples/completion-summary.sh

# Test activation workflow
./examples/test-real-activation.sh
```

### Using Configuration Example
```bash
# Copy example config to your project
cp examples/.llvmup-config.example .llvmup-config

# Edit the configuration
nano .llvmup-config

# Load the configuration
llvmup config load
```

## 📋 What These Demos Show

### Completion Features
- 🌐 Remote version fetching from GitHub API
- 💾 Intelligent caching system (24h expiry)
- ⚡ Prebuilt vs 📦 source build differentiation
- 🎯 Context-aware completion
- 🏠 Local version management
- ⭐ Default version indicators

### System Capabilities
- 🔄 Full activation/deactivation cycle
- 🛠️ Build customization options
- 📦 Version management
- 🎨 Rich terminal output with colors and emojis
- 🔧 Configuration file support

## 💡 Tips

1. **Make scripts executable**: `chmod +x examples/*.sh`
2. **Run in project root**: Most scripts expect to be run from the project root
3. **Check requirements**: Some demos require installed LLVM versions
4. **Safe testing**: Scripts use subshells to avoid affecting your environment

## 📖 Documentation

For complete documentation, see the `docs/` directory:
- `docs/FEATURE_SUMMARY.md` - Complete feature overview
- `docs/COMPLETION_UX_REPORT.md` - Detailed completion system documentation
- `docs/BUILD_EXAMPLE.md` - Build system examples
- `docs/INSTALL.md` - Installation guide

---

These examples demonstrate the full capabilities of LLVMUP and serve as both documentation and testing tools! 🎉
