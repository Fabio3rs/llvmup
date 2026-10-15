doctor_probes() {
    local result temp
    if ((doctor_deep)); then
        if ! command -v mktemp >/dev/null 2>&1; then
            doctor_emit deep.activation deep SKIP 'mktemp is unavailable.' 'Install coreutils for isolated deep checks.'
        else
            # This subshell owns all temporary state and its cleanup trap.
            result=$(
                temp=$(mktemp -d "${TMPDIR:-/tmp}/llvmup-doctor.XXXXXXXX") || exit 1
                trap 'rm -rf -- "$temp"' EXIT
                export LLVM_TOOLCHAINS_DIR="$temp/toolchains" LLVM_HOME="$temp/llvm" LLVM_CUSTOM_HOME="$temp/llvm" LLVM_CUSTOM_TOOLCHAINS_DIR="$temp/toolchains"
                export LLVMUP_INSTALL_DIR="$doctor_root" LLVMUP_DISABLE_AUTOACTIVATE=1 LLVM_TEST_MODE=1 LLVM_COMPLETION_CACHE_DIR="$temp/cache"
                unset _ACTIVE_LLVM _ACTIVE_LLVM_PATH _OLD_PATH _OLD_CC _OLD_CXX _OLD_LD _OLD_CC_SET _OLD_CXX_SET _OLD_LD_SET CC CXX LD
                mkdir -p "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin" || exit 1
                for tool in clang clang++; do printf '#!/bin/sh\nexit 0\n' > "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin/$tool"; chmod +x "$LLVM_TOOLCHAINS_DIR/llvmorg-18.1.8/bin/$tool"; done
                original_path=$PATH
                source "$doctor_root/llvm-activate" llvmorg-18.1.8 >/dev/null || exit 1
                source "$doctor_root/llvm-deactivate" >/dev/null || exit 1
                [[ $PATH == "$original_path" && ! ${CC+x} && ! ${CXX+x} && ! ${LD+x} ]] || exit 1
                export CC='' CXX='custom c++' LD=custom-linker
                source "$doctor_root/llvm-activate" llvmorg-18.1.8 >/dev/null || exit 1
                source "$doctor_root/llvm-deactivate" >/dev/null || exit 1
                [[ ${CC+x} && $CC == '' && $CXX == 'custom c++' && $LD == custom-linker && $PATH == "$original_path" ]] || exit 1
                source "$doctor_root/llvm-functions.sh" >/dev/null 2>&1 || exit 1
                [[ $(llvm-match-version-list '~18.1.8' llvmorg-18.1.7 llvmorg-18.1.8 2>/dev/null) == llvmorg-18.1.8 ]] || exit 1
                unset _LLVM_CONFIG_DIRECTORY_STATE_INITIALIZED
                LLVM_CONFIG_LLVM_HOME="$temp/project-a" LLVM_CONFIG_TOOLCHAINS_DIR='' LLVM_CONFIG_SOURCES_DIR=''
                llvm-config-apply-directories >/dev/null 2>&1
                LLVM_CONFIG_LLVM_HOME=''
                llvm-config-apply-directories >/dev/null 2>&1
                [[ $(llvm-get-toolchains-dir) == "$temp/toolchains" ]] || exit 1
                printf ok
            ) 2>/dev/null
            if [[ $result == ok ]]; then
                doctor_emit deep.activation deep PASS 'Isolated activation restores unset/empty/custom variables; version matching and project directory restoration passed.' ''
            else
                doctor_emit deep.activation deep FAIL 'Isolated lifecycle or configuration probe failed.' 'Run the activation and project regression suites; reinstall matching runtime files.'
            fi
            if [[ -r $doctor_root/llvmup-completion.sh ]]; then
                if (temp=$(mktemp -d "${TMPDIR:-/tmp}/llvmup-doctor.XXXXXXXX") || exit 1
                    trap 'rm -rf -- "$temp"' EXIT
                    export LLVM_COMPLETION_CACHE_DIR="$temp/cache"
                    llvmup() { :; }
                    source "$doctor_root/llvmup-completion.sh" >/dev/null 2>&1
                    declare -F _llvmup_completions >/dev/null && declare -F _llvmup_get_main_command_items >/dev/null
                ); then
                    doctor_emit deep.completion deep PASS 'Bash completion loads with a shadowing llvmup function.' ''
                else doctor_emit deep.completion deep FAIL 'Bash completion failed to load.' 'Reinstall completion and its shared helper.'; fi
            else
                doctor_emit deep.completion deep SKIP 'Adjacent Bash completion script unavailable.' 'Check the configured completion installation directory.'
            fi
            if command -v zsh >/dev/null 2>&1 && [[ -r $doctor_root/_llvmup ]]; then
                if (temp=$(mktemp -d "${TMPDIR:-/tmp}/llvmup-doctor.XXXXXXXX") || exit 1
                    trap 'rm -rf -- "$temp"' EXIT
                    LLVM_COMPLETION_CACHE_DIR="$temp/cache" zsh -f -c '
                        source "$1/_llvmup" || exit 1
                        (( $+functions[_llvmup] && $+functions[_llvmup_get_main_command_items] ))
                    ' _ "$doctor_root" >/dev/null 2>&1
                ); then
                    doctor_emit deep.zsh deep PASS 'Zsh completion loads before compinit without errors.' ''
                else doctor_emit deep.zsh deep FAIL 'Zsh completion loading failed.' 'Reinstall _llvmup and its shared helper.'; fi
            else
                doctor_emit deep.zsh deep SKIP 'Zsh or its completion file is unavailable.' 'Install Zsh to enable its isolated loading probe.'
            fi
        fi
    else
        doctor_emit deep.activation deep SKIP 'Functional probes are opt-in.' 'Use --deep for isolated temporary lifecycle and completion tests.'
    fi
    if ((doctor_network)); then
        if ! command -v curl >/dev/null 2>&1; then
            doctor_emit network.github network FAIL 'curl is required for requested network checks.' 'Install curl.'
        else
            result=$(curl -fsSL --connect-timeout 3 --max-time 8 --max-filesize 1048576 'https://api.github.com/repos/llvm/llvm-project/releases?per_page=1' 2>/dev/null)
            if [[ $? != 0 ]]; then
                doctor_emit network.github network FAIL 'GitHub release metadata request failed.' 'Check proxy, TLS certificates, connectivity and GitHub rate limits.'
            elif command -v jq >/dev/null 2>&1 && printf '%s' "$result" | jq -e 'type == "array" and length > 0 and (.[0].tag_name | type == "string")' >/dev/null 2>&1; then
                doctor_emit network.github network PASS 'GitHub release metadata retrieved and parsed with redirects enabled.' ''
            else
                doctor_emit network.github network WARN 'Response received but release metadata could not be validated.' 'Check jq availability and proxy/API responses.'
            fi
            if curl -fsIL --connect-timeout 3 --max-time 8 --max-redirs 5 https://github.com/llvm/llvm-project/releases/latest >/dev/null 2>&1; then
                doctor_emit network.redirect network PASS 'Release page HEAD request and redirect chain succeeded.' 'Archive Content-Length is optional and is not tested here.'
            else doctor_emit network.redirect network WARN 'Release page HEAD request failed.' 'Check proxy policy; some networks reject HEAD while downloads still work.'; fi
        fi
    else
        doctor_emit network.github network SKIP 'Network checks disabled; no requests made.' 'Use --network to check GitHub metadata and release redirects.'
    fi
}
