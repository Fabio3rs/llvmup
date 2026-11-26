#!/bin/sh
# Shared completion helpers for Bash and Zsh.

LLVM_COMPLETION_CACHE_DIR="${LLVM_COMPLETION_CACHE_DIR:-$HOME/.cache/llvmup}"
LLVM_REMOTE_CACHE_FILE="${LLVM_REMOTE_CACHE_FILE:-$LLVM_COMPLETION_CACHE_DIR/remote_versions.cache}"
LLVM_CACHE_EXPIRY_HOURS="${LLVM_CACHE_EXPIRY_HOURS:-24}"

_llvmup_completion_cache_init() {
    mkdir -p "$LLVM_COMPLETION_CACHE_DIR" 2>/dev/null
}

_llvmup_completion_cache_init

_llvmup_cache_valid() {
    if [ ! -f "$LLVM_REMOTE_CACHE_FILE" ]; then
        return 1
    fi

    local cache_age
    local max_age
    cache_age=$(( $(date +%s) - $(stat -c %Y "$LLVM_REMOTE_CACHE_FILE" 2>/dev/null || echo 0) ))
    max_age=$(( LLVM_CACHE_EXPIRY_HOURS * 3600 ))

    [ "$cache_age" -lt "$max_age" ]
}

_llvmup_get_remote_versions() {
    if _llvmup_cache_valid && [ -s "$LLVM_REMOTE_CACHE_FILE" ]; then
        cat "$LLVM_REMOTE_CACHE_FILE"
        return 0
    fi

    local versions
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        versions=$(curl -fsSL --connect-timeout 3 --max-time 5 "https://api.github.com/repos/llvm/llvm-project/releases" 2>/dev/null | \
            jq -r '.[].tag_name' 2>/dev/null | \
            grep -E '^llvmorg-[0-9]+\.[0-9]+\.[0-9]+$' | \
            head -20)

        if [ $? -eq 0 ] && [ -n "$versions" ]; then
            echo "$versions" > "$LLVM_REMOTE_CACHE_FILE" 2>/dev/null
            echo "$versions"
            return 0
        fi
    fi

    cat <<'EOF'
llvmorg-22.1.8
llvmorg-21.1.0
llvmorg-20.1.8
llvmorg-19.1.0
llvmorg-18.1.8
llvmorg-17.0.6
EOF
}

_llvmup_get_local_versions() {
    local toolchains_dir
    if [ -n "${LLVM_TOOLCHAINS_DIR:-}" ]; then
        toolchains_dir="$LLVM_TOOLCHAINS_DIR"
    elif [ -n "${LLVM_CUSTOM_TOOLCHAINS_DIR:-}" ]; then
        toolchains_dir="$LLVM_CUSTOM_TOOLCHAINS_DIR"
    elif [ -n "${LLVM_HOME:-}" ]; then
        toolchains_dir="$LLVM_HOME/toolchains"
    elif [ -n "${LLVM_CUSTOM_HOME:-}" ]; then
        toolchains_dir="$LLVM_CUSTOM_HOME/toolchains"
    else
        toolchains_dir="$HOME/.llvm/toolchains"
    fi
    if [ -d "$toolchains_dir" ]; then
        find "$toolchains_dir" -maxdepth 1 -type d -exec basename {} \; | grep -v "^toolchains$" | sort
    fi
}

_llvmup_get_major_minor_templates() {
    (
        _llvmup_get_local_versions
        _llvmup_get_remote_versions
    ) 2>/dev/null | awk '
        {
            version=$0
            sub(/^source-llvmorg-/, "", version)
            sub(/^llvmorg-/, "", version)
            if (match(version, /^[0-9]+\.[0-9]+/)) {
                mm=substr(version, RSTART, RLENGTH)
                split(mm, parts, ".")
                major=parts[1]
                if (!seen_mm[mm]++) print "mm\t" mm
                if (!seen_major[major]++) print "major\t" major
            }
        }
    ' | sort -u
}

_llvmup_get_main_command_items() {
    cat <<'EOF'
doctor	command	Diagnose installation and environment
install	command	Install an LLVM version
activate	command	Activate an installed LLVM version in the current shell
deactivate	command	Deactivate the current LLVM version in the current shell
env	command	Print shell exports for CI/non-interactive usage
resolve	command	Resolve a stable remote LLVM release without installing it
vscode-activate	command	Configure the current workspace for an installed LLVM version
status	command	Show the current LLVM environment status
list	command	List installed LLVM versions
remove	command	Remove one installed LLVM version
disk-usage	command	Show disk usage of installed LLVM versions
default	command	Manage the global default LLVM version
config	command	Manage project configuration
use	command	Select a toolchain for the current shell session
run	command	Run a command with a toolchain without changing the shell
which	command	Show the real path of a tool in the selected toolchain
where	command	Show the installation root of a toolchain
provides	command	List installed toolchains that provide a tool
info	command	Show the manifest of an installed toolchain
alias	command	Manage aliases for installed toolchains
pin	command	Pin the project toolchain in .llvmup-config
sync	command	Install the toolchain declared by the project
update	command	Install the newest release of the same provider and major
pick	command	Choose an installed toolchain interactively
toolchain	command	Register external toolchains (link/unlink/list)
shell	command	Start a subshell with a toolchain active
cmake-toolchain	command	Generate a CMake toolchain file
help	command	Show help
EOF
}

_llvmup_get_list_flag_items() {
    cat <<'EOF'
--remote	flag	List stable remote releases
--json	flag	Emit machine-readable JSON
--help	flag	Show help
EOF
}

_llvmup_get_remove_flag_items() {
    cat <<'EOF'
--force	flag	Allow removal of the active or default version
--help	flag	Show help
EOF
}

_llvmup_get_disk_usage_flag_items() {
    cat <<'EOF'
-h	flag	Show human-readable sizes
--human-readable	flag	Show human-readable sizes
--help	flag	Show help
EOF
}

_llvmup_get_resolve_flag_items() {
    cat <<'EOF'
--format	flag	Choose tag or JSON output
--platform	flag	Override platform detection
--arch	flag	Override architecture detection
--config	flag	Resolve the expression from .llvmup-config
--help	flag	Show help
EOF
}

_llvmup_get_config_action_items() {
    if [ -f ".llvmup-config" ]; then
        cat <<'EOF'
load	config	Load and display the current project configuration
apply	config	Install using the loaded project configuration
lock	config	Record the exact assets in .llvmup-lock.json
activate	config	Activate an installed version from the project configuration
init	config	Recreate or update the current project configuration
EOF
    else
        cat <<'EOF'
init	config	Create a new .llvmup-config for this project
load	config	Load a project configuration after creating one
apply	config	Install using a project configuration after creating one
activate	config	Activate a configured version after creating one
EOF
    fi
}

_llvmup_get_install_flag_items() {
    cat <<'EOF'
--from-source	flag	Build LLVM from source
--verbose	flag	Show verbose output
--quiet	flag	Suppress non-essential output
--help	flag	Show help
--cmake-flags	flag	Pass additional CMake flags
--name	flag	Use a custom installation name
--default	flag	Set the installed version as default
--profile	flag	Choose an installation profile
--component	flag	Select installation components
--strip	flag	Strip Linux ELF executables
--disable-libc-wno-error	flag	Disable LIBC_WNO_ERROR
--reconfigure	flag	Force CMake reconfiguration
--list-only	flag	List source releases without building
--verify	flag	Choose warn, strict, or skip release verification
--provider	flag	Choose the toolchain provider
--release	flag	Install an exact upstream release tag
--crt	flag	Choose the C runtime (ucrt, msvcrt)
--threads	flag	Choose the threading model (WinLibs)
--target	flag	Choose the default target triple
--compiler	flag	Choose the default compiler (clang, gcc)
--extractor	flag	Choose the archive extractor
--use	flag	Select the toolchain after installing it
--force	flag	Replace an existing installation
--no-cache	flag	Ignore the download cache
EOF
}
# --- Provider/alias/target items (offline: recipes, aliases.json and installed manifests) -------------
_llvmup_completion_dir() {
    if [ -n "${BASH_SOURCE:-}" ]; then
        (cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
    elif [ -n "${ZSH_VERSION:-}" ]; then
        # shellcheck disable=SC2296
        printf '%s\n' "${${(%):-%x}:A:h}"
    fi
}
_LLVMUP_COMPLETION_DIR="$(_llvmup_completion_dir)"

_llvmup_home_dir() {
    if [ -n "${LLVM_HOME:-}" ]; then printf '%s\n' "$LLVM_HOME"
    elif [ -n "${LLVM_CUSTOM_HOME:-}" ]; then printf '%s\n' "$LLVM_CUSTOM_HOME"
    else printf '%s\n' "$HOME/.llvm"; fi
}

_llvmup_get_provider_names() {
    local dir f
    for dir in "${LLVMUP_RECIPES_DIR:-}" "$_LLVMUP_COMPLETION_DIR/libexec/recipes" "$_LLVMUP_COMPLETION_DIR/../libexec/recipes"; do
        [ -n "$dir" ] && [ -d "$dir" ] || continue
        for f in "$dir"/*.json; do [ -f "$f" ] && basename "$f" .json; done
        return 0
    done
    printf '%s\n' official winlibs llvm-mingw
}

_llvmup_get_provider_items() {
    _llvmup_get_provider_names | while IFS= read -r p; do printf '%s\tprovider\tToolchain provider\n' "$p"; done
}

_llvmup_get_provider_selector_items() {
    _llvmup_get_provider_names | while IFS= read -r p; do
        printf '%s@latest\tselector\tNewest %s release\n' "$p" "$p"
    done
}

_llvmup_get_alias_names() {
    local f
    f="$(_llvmup_home_dir)/aliases.json"
    [ -f "$f" ] || return 0
    # Keys of the "aliases" object: lines like   "name": {
    sed -n 's/^[[:space:]]*"\([A-Za-z0-9_.+-]*\)"[[:space:]]*:[[:space:]]*{.*/\1/p' "$f" | grep -v '^aliases$'
}

_llvmup_get_alias_items() {
    _llvmup_get_alias_names | while IFS= read -r a; do printf '%s\talias\tToolchain alias\n' "$a"; done
}

_llvmup_get_external_names() {
    local f
    f="$(_llvmup_home_dir)/external-toolchains.json"
    [ -f "$f" ] || return 0
    sed -n 's/^[[:space:]]*"\([A-Za-z0-9_.+-]*\)"[[:space:]]*:[[:space:]]*{.*/\1/p' "$f" | grep -v '^toolchains$'
}

_llvmup_get_toolchain_items() {
    _llvmup_get_local_versions 2>/dev/null | while IFS= read -r v; do printf '%s\tinstalled\tInstalled toolchain\n' "$v"; done
    _llvmup_get_alias_items
    _llvmup_get_external_names | while IFS= read -r e; do printf '%s\texternal\tLinked external toolchain\n' "$e"; done
}

_llvmup_get_target_items() {
    local tc
    tc="${LLVM_TOOLCHAINS_DIR:-$(_llvmup_home_dir)/toolchains}"
    {
        printf '%s\n' x86_64-w64-mingw32 i686-w64-mingw32 aarch64-w64-mingw32 armv7-w64-mingw32
        cat "$tc"/*/.llvmup-toolchain.json 2>/dev/null | grep -o '"[a-z0-9_]*-[a-z0-9_]*-[a-z0-9_.-]*"' | tr -d '"' | grep -E -- '-(mingw32|linux-gnu|windows-msvc|apple-darwin)'
    } | sort -u | while IFS= read -r t; do printf '%s\ttarget\tTarget triple\n' "$t"; done
}

_llvmup_get_compiler_items() {
    printf '%s\tcompiler\t%s\n' clang 'LLVM Clang' gcc 'GNU GCC (WinLibs)'
}

_llvmup_get_crt_items() {
    printf '%s\tcrt\t%s\n' ucrt 'Universal CRT' msvcrt 'Legacy MSVCRT'
}

_llvmup_get_extractor_items() {
    printf '%s\textractor\t%s\n' auto 'Best available backend' 7z '7-Zip' tar 'tar' zip 'Built-in ZIP' python 'Python tarfile'
}

_llvmup_get_run_flag_items() {
    cat <<'EOF'
--compiler	flag	Choose clang or gcc inside the bundle
--target	flag	Choose a target triple of the bundle
--crt	flag	Filter by C runtime
--install	flag	Install the toolchain when missing
--locked	flag	Use the toolchain recorded in .llvmup-lock.json
--	flag	End of llvmup options; the command follows
EOF
}

_llvmup_get_use_flag_items() {
    cat <<'EOF'
--compiler	flag	Choose clang or gcc inside the bundle
--target	flag	Choose a target triple of the bundle
--crt	flag	Filter by C runtime
--install	flag	Install the toolchain when missing
--auto	flag	Drop the manual selection and follow project/default
EOF
}


_llvmup_get_expression_items() {
    cat <<'EOF'
latest	expression	Newest matching version
newest	expression	Alias for latest
oldest	expression	Oldest matching version
earliest	expression	Alias for oldest
prebuilt	expression	Any installed prebuilt version
source	expression	Any installed source build
latest-prebuilt	expression	Newest installed prebuilt version
latest-source	expression	Newest installed source build
EOF
}

_llvmup_get_range_template_items() {
    cat <<'EOF'
>=18.0.0	template	Version 18.0.0 or newer
<=19.1.0	template	Version 19.1.0 or older
>20.0.0	template	Version newer than 20.0.0
<18.0.0	template	Version older than 18.0.0
=19.1.0	template	Exactly version 19.1.0
~19.1	template	Any 19.1.x version
18.*	template	Any 18.x version
EOF

    _llvmup_get_major_minor_templates | while IFS=$'\t' read -r template_type template_value; do
        case "$template_type" in
            mm)
                printf '~%s\ttemplate\tAny %s.x version\n' "$template_value" "$template_value"
                ;;
            major)
                printf '%s.*\ttemplate\tAny %s.x version\n' "$template_value" "$template_value"
                printf '>=%s.0.0\ttemplate\tVersion %s.0.0 or newer\n' "$template_value" "$template_value"
                ;;
        esac
    done | sort -u
}

_llvmup_get_local_version_items() {
    _llvmup_get_local_versions | while IFS= read -r version; do
        [ -z "$version" ] && continue
        printf '%s\tlocal\tInstalled locally\n' "$version"
    done
}

_llvmup_get_remote_version_items() {
    local local_versions
    local_versions=$(_llvmup_get_local_versions)
    _llvmup_get_remote_versions | while IFS= read -r version; do
        [ -z "$version" ] && continue
        if printf '%s\n' "$local_versions" | grep -Fxq "$version"; then
            continue
        fi
        printf '%s\tremote\tAvailable remotely\n' "$version"
    done
}

_llvmup_get_profile_items() {
    cat <<'EOF'
minimal	profile	Clang, LLD, headers and runtimes
compiler	profile	Minimal plus libc++ on Unix, archive and coverage tools
full	profile	Build the full default profile
custom	profile	Build only explicitly selected components
EOF
}

_llvmup_get_component_items() {
    cat <<'EOF'
clang	component	Clang compiler and its aliases
lld	component	LLVM linker and its aliases
llvm-ar	component	LLVM archiver
llvm-ranlib	component	Archive index tool
llvm-cov	component	Coverage reports
llvm-profdata	component	Profile data processing
llvm-xray	component	XRay instrumentation analysis
libc++	component	Unix C++ headers, ABI and unwind runtimes
clangd	component	Clang language server
clang-format	component	Code formatting
clang-tidy	component	Static analysis
lldb	component	Source-only legacy debugger project
llvm-nm	component	LLVM nm tool
llvm-objcopy	component	LLVM objcopy tool
llvm-strip	component	LLVM strip tool
llvm-objdump	component	LLVM objdump tool
llvm-readobj	component	LLVM readobj tool
llvm-readelf	component	LLVM readelf tool
llvm-size	component	LLVM size tool
llvm-strings	component	LLVM strings tool
llvm-symbolizer	component	LLVM symbolizer tool
llvm-addr2line	component	LLVM addr2line tool
llvm-cxxfilt	component	LLVM cxxfilt tool
llvm-dwarfdump	component	LLVM dwarfdump tool
llvm-dwp	component	LLVM dwp tool
llvm-pdbutil	component	LLVM pdbutil tool
llvm-profgen	component	LLVM profgen tool
llvm-as	component	LLVM as tool
llvm-dis	component	LLVM dis tool
llvm-link	component	LLVM link tool
llvm-extract	component	LLVM extract tool
llvm-bcanalyzer	component	LLVM bcanalyzer tool
llvm-diff	component	LLVM diff tool
llvm-mc	component	LLVM mc tool
llvm-mca	component	LLVM mca tool
llc	component	LLVM llc tool
lli	component	LLVM lli tool
opt	component	LLVM opt tool
clang-apply-replacements	component	LLVM clang-apply-replacements tool
clang-query	component	LLVM clang-query tool
clang-scan-deps	component	LLVM clang-scan-deps tool
clang-check	component	LLVM clang-check tool
EOF
}

_llvmup_get_cmake_flag_items() {
    cat <<'EOF'
-DCMAKE_BUILD_TYPE=Release	cmake	Release build
-DCMAKE_BUILD_TYPE=Debug	cmake	Debug build
-DLLVM_ENABLE_PROJECTS=clang	cmake	Enable clang project
-DLLVM_ENABLE_RUNTIMES=libcxx	cmake	Enable libcxx runtime
-DLLVM_TARGETS_TO_BUILD=X86	cmake	Build only the X86 target
EOF
}

_llvmup_get_install_target_items() {
    _llvmup_get_expression_items
    _llvmup_get_range_template_items
    _llvmup_get_local_version_items
    _llvmup_get_remote_version_items
}

_llvmup_get_activation_version_items() {
    local default_version=""
    local active_version="${_ACTIVE_LLVM:-}"

    if [ -L "$HOME/.llvm/default" ]; then
        default_version=$(basename "$(readlink "$HOME/.llvm/default" 2>/dev/null)" 2>/dev/null)
    fi

    _llvmup_get_local_versions | while IFS= read -r version; do
        local desc="Installed locally"
        [ -z "$version" ] && continue

        if [ "$version" = "$default_version" ] && [ "$version" = "$active_version" ]; then
            desc="Installed locally; default and active"
        elif [ "$version" = "$default_version" ]; then
            desc="Installed locally; default version"
        elif [ "$version" = "$active_version" ]; then
            desc="Installed locally; active in this shell"
        fi

        printf '%s\tlocal\t%s\n' "$version" "$desc"
    done
}

# Backward-compatible helper names used by existing tests and scripts.
_llvm_get_remote_versions() { _llvmup_get_remote_versions "$@"; }
_llvm_get_local_versions() { _llvmup_get_local_versions "$@"; }
