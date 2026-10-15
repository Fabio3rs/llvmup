# Load the existing parser only inside an isolated process; never evaluate config as shell code.
doctor_project() {
    local root=$PWD found='' result selected
    while :; do
        if [[ -e $root/.llvmup-config ]]; then found=$root; break; fi
        [[ $root == / ]] && break
        root=${root%/*}; root=${root:-/}
    done
    if [[ -z $found ]]; then
        doctor_emit project.config project SKIP 'No project configuration found in this directory or its parents.' ''
        return
    fi
    if [[ ! -r $found/.llvmup-config ]]; then
        doctor_emit project.config project FAIL 'Project configuration is unreadable.' 'Check file permissions.' "$found/.llvmup-config"; return
    fi
    if [[ ! -r $doctor_root/llvm-functions.sh ]]; then
        doctor_emit project.config project SKIP 'Configuration parser is unavailable.' 'Reinstall the missing runtime module.'; return
    fi
    local helper
    for helper in sed tr grep sort head cut; do
        if ! command -v "$helper" >/dev/null 2>&1; then
            doctor_emit project.config project SKIP 'A helper required by the configuration parser is unavailable.' 'Install the standard text utilities to enable configuration checks.' "$helper"
            return
        fi
    done
    result=$(
        export LLVMUP_DISABLE_AUTOACTIVATE=1 LLVM_TEST_MODE=1
        source "$doctor_root/llvm-functions.sh" >/dev/null 2>&1
        cd -- "$found" || exit 1
        # Reject malformed/duplicate assignments rather than silently ignoring them.
        local section='' key value array=0 text trimmed seen_keys='|' quote
        while IFS= read -r text || [[ -n $text ]]; do
            trimmed="${text#"${text%%[![:space:]]*}"}"
            [[ -z $trimmed || $trimmed == \#* || $trimmed == \;* ]] && continue
            if ((array)); then [[ $trimmed == *']'* ]] && array=0; continue; fi
            if [[ $trimmed =~ ^\[([^]]+)\][[:space:]]*$ ]]; then section=${BASH_REMATCH[1]}; continue; fi
            [[ $trimmed =~ ^([a-zA-Z_][a-zA-Z_0-9]*)[[:space:]]*=(.*)$ ]] || exit 1
            key=$section.${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
            [[ $seen_keys != *"|$key|"* ]] || exit 1
            seen_keys="$seen_keys$key|"
            value="${value#"${value%%[![:space:]]*}"}"
            case "$value" in
                \[*) [[ $value == *']'* ]] || array=1 ;;
                \"*|\'*) quote=${value:0:1}; [[ ${value:1} == *"$quote"* ]] || exit 1 ;;
            esac
        done < .llvmup-config
        ((array == 0)) || exit 1
        llvm-config-load >/dev/null 2>&1 || exit 1
        local configured_path
        for configured_path in "$LLVM_CONFIG_LLVM_HOME" "$LLVM_CONFIG_TOOLCHAINS_DIR" "$LLVM_CONFIG_SOURCES_DIR"; do
            [[ -z $configured_path ]] && continue
            [[ ! -e $configured_path || -d $configured_path ]] || exit 1
        done
        if [[ $LLVM_CONFIG_VERSION == *['~<>=*']* ]]; then
            [[ $LLVM_CONFIG_VERSION =~ ^([~\<\>]=?|=)?[[:space:]]*[0-9]+(\.[0-9]+)*(\.\*)?$ || $LLVM_CONFIG_VERSION =~ ^[0-9]+\*$ ]] || exit 1
        fi
        case "$LLVM_CONFIG_AUTO_ACTIVATE" in true|false) ;; *) exit 1 ;; esac
        case "$LLVM_CONFIG_PROFILE" in ''|minimal|full|custom) ;; *) exit 1 ;; esac
        # Exact custom installation names remain supported.
        if [[ ! -d "$(llvm-get-toolchains-dir)/$LLVM_CONFIG_VERSION" ]]; then
            llvm-parse-version-expression "$LLVM_CONFIG_VERSION" >/dev/null 2>&1 || exit 1
        fi
        printf '%s\n' "$LLVM_CONFIG_VERSION" "$LLVM_CONFIG_AUTO_ACTIVATE"
        if [[ -d "$(llvm-get-toolchains-dir)/$LLVM_CONFIG_VERSION" ]]; then
            printf '%s\n' "$LLVM_CONFIG_VERSION"
        else
            llvm-match-versions "$LLVM_CONFIG_VERSION" 2>/dev/null | head -n 1
        fi
    )
    if [[ $? != 0 || -z $result ]]; then
        doctor_emit project.config project FAIL 'Invalid project configuration: version, profile or auto_activate value.' 'Check .llvmup-config against the documented format.' "$found/.llvmup-config"; return
    fi
    doctor_emit project.config project PASS 'Project configuration parsed without activation.' '' "$found/.llvmup-config"
    selected=$(printf '%s\n' "$result" | sed -n '3p')
    if [[ -n $selected ]]; then
        doctor_emit project.version project PASS 'Configured expression matches an installed version.' '' "$selected"
    else
        doctor_emit project.version project WARN 'No installed version matches the configured expression.' 'Run llvmup config apply when ready to install; doctor never fetches releases by default.' "${result%%$'\n'*}"
    fi
    if [[ ${_LLVMUP_AUTOACTIVATE_ROOT:-$found} != "$found" ]]; then
        doctor_emit project.stale project WARN 'Automatic activation belongs to a different project.' 'Reactivate from the current configuration or start a fresh shell.' "${_LLVMUP_AUTOACTIVATE_ROOT:-}"
    fi
    if [[ $result == *$'\ntrue'* && -z ${_ACTIVE_LLVM:-} ]]; then
        doctor_emit project.autoactivate project WARN 'Project requests automatic activation but no version is active.' 'Check the installed match and shell initialization; use llvmup config activate.'
    fi
}
