doctor_filesystem() {
    local file dir tool count=0
    for file in llvmup llvm-functions.sh llvm-activate llvm-deactivate llvm-prebuilt llvm-build llvm-vscode-activate llvmup-completion-common.sh; do
        if [[ ! -r $doctor_root/$file ]]; then
            doctor_emit installation.file installation FAIL 'Required runtime file is missing or unreadable.' 'Reinstall LLVMUP from a complete checkout.' "$doctor_root/$file"
        elif [[ $file != *.sh && ! -x $doctor_root/$file ]]; then
            doctor_emit installation.permission installation FAIL 'Runtime helper is not executable.' 'Restore executable permission or reinstall LLVMUP.' "$doctor_root/$file"
        else
            doctor_emit installation.file installation PASS 'Runtime file is accessible.' '' "$doctor_root/$file"
        fi
    done
    if [[ -n ${LLVMUP_INSTALL_DIR:-} && $LLVMUP_INSTALL_DIR != "$doctor_root" ]]; then
        doctor_emit installation.path installation WARN 'LLVMUP_INSTALL_DIR differs from this executable directory.' 'Check that shell functions and PATH use the intended installation.' "$LLVMUP_INSTALL_DIR"
    fi
    for tool in curl jq tar xz sha256sum git cmake ninja timeout gpg gh; do
        if command -v "$tool" >/dev/null 2>&1; then
            doctor_emit "dependency.$tool" dependencies PASS 'Tool is available.' '' "$tool"
        else
            case "$tool" in
                git|cmake|ninja) dir='Needed only for source builds.' ;;
                timeout|gpg|gh) dir='Optional: timeout bounds legacy requests; gpg/gh enable origin verification.' ;;
                *) dir='Install before using prebuilt downloads; doctor itself remains usable.' ;;
            esac
            doctor_emit "dependency.$tool" dependencies WARN 'Tool is unavailable.' "$dir" "$tool"
        fi
    done
    if command -v clang >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
        doctor_emit dependency.bootstrap dependencies PASS 'A bootstrap compiler is discoverable (not executed).' 'Source builds also need its C++ compiler and development libraries.'
    else
        doctor_emit dependency.bootstrap dependencies WARN 'No bootstrap compiler found.' 'Install GCC/G++ or Clang before building LLVM from source.'
    fi
    if [[ -e $doctor_toolchains && ( ! -d $doctor_toolchains || ! -r $doctor_toolchains || ! -x $doctor_toolchains ) ]]; then
        doctor_emit toolchain.directory toolchains FAIL 'Toolchain directory cannot be searched.' 'Check directory type and permissions.' "$doctor_toolchains"
    else
        for dir in "$doctor_toolchains"/* "$doctor_toolchains"/.llvmup-*.installing.*; do
            [[ -e $dir || -L $dir ]] || continue
            case ${dir##*/} in .llvmup-*.installing.*)
                doctor_emit toolchain.staging toolchains WARN 'Installation staging directory remains.' 'Check for a running installer before manually cleaning up an interrupted installation.' "$dir"; continue ;; esac
            [[ -d $dir || -L $dir ]] || continue
            count=$((count+1))
            if [[ -x $dir/bin/clang && -x $dir/bin/clang++ ]]; then
                doctor_emit toolchain.compilers toolchains PASS 'Compiler files are executable (not executed).' '' "$dir"
            else
                doctor_emit toolchain.compilers toolchains FAIL 'Incomplete or inaccessible toolchain: clang/clang++ missing or not executable.' 'Inspect permissions; reinstall the affected version if incomplete.' "$dir"
            fi
            file=$dir/.llvmup-verification.json
            if [[ -f $file ]]; then
                if ! command -v jq >/dev/null 2>&1; then
                    doctor_emit toolchain.metadata toolchains SKIP 'Cannot parse verification record without jq.' 'Install jq to inspect the record.' "$file"
                elif jq -e 'type == "object" and .schema == 1 and (.version | type == "string") and (.policy | IN("warn","strict","skip"))' "$file" >/dev/null 2>&1; then
                    doctor_emit toolchain.metadata toolchains PASS 'Verification record has a recognized structure; this does not authenticate installed files.' 'Use strict verification when reinstalling to require origin authentication.' "$file"
                else
                    doctor_emit toolchain.metadata toolchains WARN 'Malformed or unsupported verification record.' 'Reinstall with verification if provenance is uncertain.' "$file"
                fi
            else
                doctor_emit toolchain.metadata toolchains SKIP 'No verification record (normal for source or legacy installs).' '' "$dir"
            fi
        done
        ((count)) || doctor_emit toolchain.empty toolchains SKIP 'No installed toolchains; doctor does not require one.' '' "$doctor_toolchains"
    fi
    dir=$doctor_home/default
    if [[ -L $dir && ! -e $dir ]]; then
        doctor_emit toolchain.default toolchains FAIL 'Default link is broken.' 'Run llvmup default unset, then default set with an installed version.' "$dir"
    elif [[ -e $dir ]]; then
        if [[ -x $dir/bin/clang && -x $dir/bin/clang++ ]]; then
            doctor_emit toolchain.default toolchains PASS 'Default toolchain is accessible.' '' "$dir"
        else
            doctor_emit toolchain.default toolchains FAIL 'Default target lacks usable compiler files.' 'Inspect the target and select a complete installed version.' "$dir"
        fi
    else
        doctor_emit toolchain.default toolchains SKIP 'No default configured.' 'Optional: llvmup default set <version>.' "$dir"
    fi
}
