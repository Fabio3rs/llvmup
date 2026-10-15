doctor_environment() {
    local active=${_ACTIVE_LLVM:-${LLVMUP_ACTIVE_VERSION:-${LLVM_ACTIVE_VERSION:-}}} expected tool resolved value entry seen=':' installs=':' count=0 profile line n profiles=0 source_path
    if [[ -n $active ]]; then
        expected=${_ACTIVE_LLVM_PATH:-$doctor_toolchains/$active}/bin
        if [[ -x $expected/clang && -x $expected/clang++ ]]; then
            doctor_emit environment.active environment PASS 'Active toolchain exists.' '' "$expected"
        else
            doctor_emit environment.active environment FAIL 'Active version points to missing compiler files.' 'Deactivate, then activate an installed version.' "$expected"
        fi
        for tool in clang clang++; do
            if [[ ${LLVMUP_DOCTOR_SHELL_FUNCTION:-} == 1 ]]; then
                case $tool in clang) resolved=${LLVMUP_DOCTOR_CLANG:-} ;; clang++) resolved=${LLVMUP_DOCTOR_CLANGXX:-} ;; esac
            else
                resolved=$(command -v "$tool" 2>/dev/null) || resolved=''
            fi
            if [[ $resolved == "$expected/$tool" || ( -n $resolved && $resolved -ef $expected/$tool ) ]]; then
                doctor_emit environment.compiler environment PASS 'Compiler resolves to the active toolchain.' '' "$tool"
            else
                doctor_emit environment.compiler environment WARN 'Compiler resolution differs from the active toolchain.' 'Check PATH order, aliases and intentional wrappers; reactivate if unintended.' "$tool: $resolved"
            fi
        done
        for tool in CC CXX LD; do
            value=${!tool:-}; [[ -n $value ]] || continue
            case $tool in CC) resolved=$expected/clang ;; CXX) resolved=$expected/clang++ ;; LD) resolved=$expected/lld ;; esac
            [[ $value == "$resolved" ]] || doctor_emit environment.override environment WARN 'Compiler variable differs from activation defaults; it may be intentional.' 'Review the override; CC/CXX must not point to clangd.' "$tool=$value"
        done
        [[ -n ${_OLD_PATH:-} ]] || doctor_emit environment.restore environment WARN 'Active environment has no saved PATH.' 'Expected for llvmup env exports; shell activation should save deactivation state.'
    elif [[ -n ${_ACTIVE_LLVM_PATH:-}${_OLD_PATH:-}${_OLD_CC_SET:-}${_OLD_CXX_SET:-} ]]; then
        doctor_emit environment.stale environment WARN 'Saved activation state exists without an active version.' 'Start a fresh shell and activate the intended version.'
    else
        doctor_emit environment.active environment SKIP 'No active toolchain.' ''
    fi
    local remaining=$PATH
    while :; do
        entry=${remaining%%:*}
        if [[ -z $entry ]]; then
            doctor_emit environment.path environment WARN 'PATH contains an empty entry (current directory).' 'Review PATH construction.'
        elif [[ $entry == *llvm* || $entry == "$doctor_toolchains"/* || -f $entry/llvmup ]]; then
            if [[ $seen == *":$entry:"* ]]; then
                doctor_emit environment.path environment WARN 'Duplicate LLVMUP-related PATH entry.' 'Remove duplicate activation or profile initialization.' "$entry"
            fi
            seen="$seen$entry:"
            if [[ -x $entry/llvmup && $installs != *":$entry:"* ]]; then installs="$installs$entry:"; count=$((count+1)); fi
        fi
        [[ $remaining == *:* ]] || break
        remaining=${remaining#*:}
    done
    ((count < 2)) || doctor_emit installation.conflict installation WARN 'Multiple LLVMUP executables are on PATH.' 'Keep the intended installation first; review obsolete profile entries.' "$installs"
    # Profiles are inspected as text only, never sourced. Separate shells are not duplicates.
    for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "${ZDOTDIR:-$HOME}/.zshrc"; do
        [[ -f $profile ]] || continue
        profiles=$((profiles+1))
        n=0
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ ^[[:space:]]*(source|\.)[[:space:]]+(.*llvm-functions\.sh.*)$ ]]; then
                n=$((n+1))
                source_path=${BASH_REMATCH[2]}
                source_path="${source_path%"${source_path##*[![:space:]]}"}"
                case $source_path in \"*\"|\'*\') source_path=${source_path:1:${#source_path}-2} ;; esac
                case $source_path in
                    *'$'*|*'`'*|*';'*) ;; # Indirect shell expressions cannot be resolved safely.
                    *)
                        [[ $source_path != '~/'* ]] || source_path="$HOME/${source_path:2}"
                        if [[ ! -r $source_path ]]; then
                            doctor_emit shell.source shell WARN 'Profile source target is missing or unreadable.' 'Update this source statement to the intended llvm-functions.sh path.' "$source_path"
                        fi ;;
                esac
            fi
            if [[ $line =~ ^[[:space:]]*#[[:space:]]*LLVM\ Manager\ Functions[[:space:]]*$ ]]; then
                doctor_emit shell.legacy shell WARN 'Legacy initialization marker found.' 'Review the old block against current installation instructions; do not delete unrelated profile content.' "$profile"
            fi
        done < "$profile"
        if ((n > 1)); then doctor_emit shell.initialization shell WARN 'Duplicate LLVMUP initialization in profile.' 'Keep one source statement in this profile.' "$profile"
        elif ((n == 1)); then doctor_emit shell.initialization shell PASS 'LLVMUP source statement found (not executed).' '' "$profile"
        else doctor_emit shell.initialization shell WARN 'No LLVMUP source statement found in this profile.' 'If this profile starts your interactive shell, source llvm-functions.sh there; CI needs no profile.' "$profile"; fi
    done
    ((profiles)) || doctor_emit shell.initialization shell WARN 'No shell profiles found.' 'Source llvm-functions.sh in interactive shells; CI needs no profile.'
    if [[ -r $doctor_root/llvmup-completion-common.sh ]]; then
        doctor_emit shell.completion shell PASS 'Shared completion helper is readable.' 'Use --deep to test loading in isolated shells.'
    else
        doctor_emit shell.completion shell FAIL 'Shared completion helper is missing.' 'Reinstall LLVMUP including completion helpers.'
    fi
    if [[ ${LLVMUP_DOCTOR_SHELL_FUNCTION:-} == 1 ]]; then
        doctor_emit shell.function shell PASS 'Invoked through the sourced shell function; compiler lookup uses caller evidence.' ''
        if [[ ${LLVMUP_DOCTOR_COMPLETION:-0} == 1 ]]; then
            doctor_emit shell.registration shell PASS 'Completion function is discoverable in the calling shell.' 'Actual key bindings and lazy loading remain shell-specific.'
        else
            doctor_emit shell.registration shell WARN 'Completion function is not yet loaded in the calling shell.' 'Load shell completion; lazy-loading frameworks may load it on first Tab.'
        fi
    fi
    doctor_emit shell.parent shell SKIP 'Executable cannot inspect parent-shell aliases, completion registration or hooks.' 'Invoke the sourced llvmup doctor function for current-shell integration evidence.'
}
