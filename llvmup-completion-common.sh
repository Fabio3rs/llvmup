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
        versions=$(timeout 5 curl -s "https://api.github.com/repos/llvm/llvm-project/releases" 2>/dev/null | \
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
llvmorg-21.1.0
llvmorg-20.1.8
llvmorg-19.1.0
llvmorg-18.1.8
llvmorg-17.0.6
EOF
}

_llvmup_get_local_versions() {
    local toolchains_dir="${LLVM_CUSTOM_TOOLCHAINS_DIR:-$HOME/.llvm/toolchains}"
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
install	command	Install an LLVM version
activate	command	Activate an installed LLVM version in the current shell
deactivate	command	Deactivate the current LLVM version in the current shell
vscode-activate	command	Configure the current workspace for an installed LLVM version
status	command	Show the current LLVM environment status
list	command	List installed LLVM versions
disk-usage	command	Show disk usage of installed LLVM versions
default	command	Manage the global default LLVM version
config	command	Manage project configuration
help	command	Show help
EOF
}

_llvmup_get_disk_usage_flag_items() {
    cat <<'EOF'
-h	flag	Show human-readable sizes
--human-readable	flag	Show human-readable sizes
--help	flag	Show help
EOF
}

_llvmup_get_config_action_items() {
    if [ -f ".llvmup-config" ]; then
        cat <<'EOF'
load	config	Load and display the current project configuration
apply	config	Install using the loaded project configuration
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
--profile	flag	Choose a build profile
--component	flag	Select build components
--disable-libc-wno-error	flag	Disable LIBC_WNO_ERROR
--reconfigure	flag	Force CMake reconfiguration
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
minimal	profile	Build essential LLVM components only
full	profile	Build the full default profile
custom	profile	Build only explicitly selected components
EOF
}

_llvmup_get_component_items() {
    cat <<'EOF'
clang	component	Clang C/C++ compiler front-end
clang++	component	Clang++ frontend alias
lld	component	LLVM linker
lldb	component	LLVM debugger
compiler-rt	component	Compiler runtime support library
libcxx	component	C++ standard library
libcxxabi	component	C++ ABI library
llvm-ar	component	LLVM archiver
llvm-nm	component	LLVM symbol table tool
opt	component	LLVM optimizer
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
