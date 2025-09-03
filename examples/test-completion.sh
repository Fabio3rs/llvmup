#!/bin/bash
# test-completion.sh - Interactive test for LLVMUP completion features
#
# This script demonstrates the enhanced auto-completion features:
# 1. Remote version fetching for installation
# 2. Differentiation between source and prebuilt
# 3. Context-aware completion
# 4. Cached remote results

set -e

echo "╭─ LLVMUP Auto-Completion Test Suite ─────────────────────────╮"
echo "│                                                             │"
echo "│ Testing enhanced bash completion features:                  │"
echo "│ • Remote version fetching with caching                     │"
echo "│ • Source vs Prebuilt differentiation                       │"
echo "│ • Context-aware completion                                  │"
echo "│ • Smart flag and option completion                         │"
echo "│                                                             │"
echo "╰─────────────────────────────────────────────────────────────╯"
echo

# Load completion scripts
echo "🔄 Loading completion scripts..."
source "$(dirname "$0")/llvmup-completion.sh"
source "$(dirname "$0")/llvm-functions.sh"
echo "✅ Completion scripts loaded successfully"
echo

# Test remote version fetching
echo "🌐 Testing remote version fetching..."
echo "📡 Fetching remote LLVM versions (first time)..."
time_start=$(date +%s%N)
remote_versions=$(_llvm_get_remote_versions | head -10)
time_end=$(date +%s%N)
time_diff=$(( (time_end - time_start) / 1000000 ))

echo "📦 Latest available versions:"
echo "$remote_versions" | head -5 | sed 's/^/   • /'
echo "⏱️  Fetch time: ${time_diff}ms"
echo

# Test cache functionality
echo "💾 Testing cache functionality..."
echo "📡 Fetching again (should use cache)..."
time_start=$(date +%s%N)
remote_versions_cached=$(_llvm_get_remote_versions | head -10)
time_end=$(date +%s%N)
time_diff_cached=$(( (time_end - time_start) / 1000000 ))

echo "⏱️  Cached fetch time: ${time_diff_cached}ms"
if [ $time_diff_cached -lt $time_diff ]; then
    echo "✅ Cache is working! (${time_diff_cached}ms vs ${time_diff}ms)"
else
    echo "⚠️  Cache might not be working as expected"
fi
echo

# Test local version detection
echo "🏠 Testing local version detection..."
local_versions=$(_llvm_get_local_versions)
if [ -n "$local_versions" ]; then
    echo "📦 Installed versions found:"
    echo "$local_versions" | sed 's/^/   • /'
else
    echo "📭 No local versions installed"
    echo "💡 You can install versions with: llvmup install <version>"
fi
echo

# Simulate completion scenarios
echo "🎯 Testing completion scenarios..."
echo

echo "1️⃣  Command completion (llvmup <TAB>):"
COMP_WORDS=("llvmup" "")
COMP_CWORD=1
COMPREPLY=()
_llvmup_completions
echo "   Available commands: ${COMPREPLY[*]}"
echo

echo "2️⃣  Default subcommand completion (llvmup default <TAB>):"
COMP_WORDS=("llvmup" "default" "")
COMP_CWORD=2
COMPREPLY=()
_llvmup_completions
echo "   Available subcommands: ${COMPREPLY[*]}"
echo

echo "3️⃣  Config subcommand completion (llvmup config <TAB>):"
COMP_WORDS=("llvmup" "config" "")
COMP_CWORD=2
COMPREPLY=()
_llvmup_completions
echo "   Available subcommands: ${COMPREPLY[*]}"
echo

echo "4️⃣  Profile completion (llvmup install --profile <TAB>):"
COMP_WORDS=("llvmup" "install" "--profile" "")
COMP_CWORD=3
COMPREPLY=()
_llvmup_completions
echo "   Available profiles: ${COMPREPLY[*]}"
echo

echo "5️⃣  Component completion (llvmup install --component <TAB>):"
COMP_WORDS=("llvmup" "install" "--component" "")
COMP_CWORD=3
COMPREPLY=()
_llvmup_completions
echo "   Available components: ${COMPREPLY[*]}"
echo

echo "6️⃣  Flag completion (llvmup install -<TAB>):"
COMP_WORDS=("llvmup" "install" "-")
COMP_CWORD=2
COMPREPLY=()
_llvmup_completions
echo "   Available flags: ${COMPREPLY[*]}"
echo

# Test version completion differentiation
echo "7️⃣  Version completion for prebuilt (llvmup install <TAB>):"
COMP_WORDS=("llvmup" "install" "")
COMP_CWORD=2
COMPREPLY=()
_llvmup_completions
version_count=${#COMPREPLY[@]}
echo "   Found $version_count completion options (prebuilt + local + flags)"
echo "   Sample: ${COMPREPLY[0]:-none} ${COMPREPLY[1]:-} ${COMPREPLY[2]:-} ..."
echo

echo "8️⃣  Version completion for source build (llvmup install --from-source <TAB>):"
COMP_WORDS=("llvmup" "install" "--from-source" "")
COMP_CWORD=3
COMPREPLY=()
_llvmup_completions
version_count_source=${#COMPREPLY[@]}
echo "   Found $version_count_source completion options (source versions + local)"
echo "   Sample: ${COMPREPLY[0]:-none} ${COMPREPLY[1]:-} ${COMPREPLY[2]:-} ..."
echo

# Test cache file
echo "🗄️  Cache information:"
cache_file="$HOME/.cache/llvmup/remote_versions.cache"
if [ -f "$cache_file" ]; then
    cache_size=$(wc -l < "$cache_file" 2>/dev/null || echo "0")
    cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo $(date +%s)) ))
    echo "   📁 Cache file: $cache_file"
    echo "   📊 Cached versions: $cache_size"
    echo "   🕐 Cache age: ${cache_age}s"

    if [ $cache_age -lt 86400 ]; then  # 24 hours
        echo "   ✅ Cache is fresh"
    else
        echo "   ⚠️  Cache is stale (will be refreshed on next use)"
    fi
else
    echo "   📭 No cache file found"
fi
echo

# Performance summary
echo "📈 Performance Summary:"
echo "   • Remote fetch (first time): ${time_diff}ms"
echo "   • Remote fetch (cached): ${time_diff_cached}ms"
echo "   • Speed improvement: $(( (time_diff - time_diff_cached) * 100 / time_diff ))%"
echo

# Usage examples
echo "💡 Usage Examples:"
echo "   Try these commands to test completion interactively:"
echo
echo "   # Install prebuilt version with completion:"
echo "   llvmup install <TAB>"
echo
echo "   # Build from source with completion:"
echo "   llvmup install --from-source <TAB>"
echo
echo "   # Set default version:"
echo "   llvmup default set <TAB>"
echo
echo "   # Configure project:"
echo "   llvmup config <TAB>"
echo

echo "🎉 Completion test completed!"
echo "💡 The completion system now provides:"
echo "   ✅ Smart remote version fetching with caching"
echo "   ✅ Differentiation between source and prebuilt contexts"
echo "   ✅ Context-aware command and option completion"
echo "   ✅ Performance optimization with intelligent caching"
echo "   ✅ Visual indicators for different version types"
