# llvmup-session.sh - save/restore of the shell environment around 'llvmup use' (sourced; bash/zsh).
#
# Every variable an activation may touch is saved together with whether it was set at all, so
# deactivation restores "unset" as unset and never leaves empty variables or duplicate PATH
# entries behind. Switching toolchains restores the original environment before applying the
# next one, so variables of the previous provider never leak into the next.
#
# Loops iterate over command substitutions because zsh does not word-split plain $VAR.

_LLVMUP_TRACKED_VARS="PATH CC CXX AR RANLIB RC LD NM STRIP DLLTOOL WINDRES PKG_CONFIG LIBCLANG_PATH LLVM_CONFIG_PATH SDKROOT _ACTIVE_LLVM _ACTIVE_LLVM_PATH LLVMUP_ACTIVE_VERSION LLVMUP_ACTIVE_PATH LLVMUP_ACTIVE_ID LLVMUP_ACTIVE_PROVIDER LLVMUP_ACTIVE_COMPILER LLVMUP_ACTIVE_TARGET"

_llvmup_words() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        eval 'printf "%s\n" ${=1}'
    else
        # shellcheck disable=SC2086
        printf '%s\n' $1
    fi
}

_llvmup_sys_vars() { env | sed -n 's/^\(LLVM_SYS_[0-9]*_PREFIX\)=.*/\1/p'; }

_llvmup_session_save() {
    [ "${_LLVMUP_ENV_SAVED:-0}" = 1 ] && return 0
    local v s
    for v in $(_llvmup_words "$_LLVMUP_TRACKED_VARS"); do
        if eval "[ -n \"\${$v+x}\" ]"; then
            eval "export _LLVMUP_SAVED_SET_$v=1 _LLVMUP_SAVED_$v=\"\${$v}\""
        else
            eval "export _LLVMUP_SAVED_SET_$v=0"
            unset "_LLVMUP_SAVED_$v"
        fi
    done
    # LLVM_SYS_<N>_PREFIX variables are dynamic; remember which ones existed before.
    _LLVMUP_SAVED_SYS_VARS="$(_llvmup_sys_vars | tr '\n' ' ')"
    export _LLVMUP_SAVED_SYS_VARS
    for s in $(_llvmup_words "$_LLVMUP_SAVED_SYS_VARS"); do
        eval "export _LLVMUP_SAVED_$s=\"\${$s}\""
    done
    export _LLVMUP_ENV_SAVED=1
}

_llvmup_session_restore() {
    [ "${_LLVMUP_ENV_SAVED:-0}" = 1 ] || return 1
    local v s set_flag
    for v in $(_llvmup_words "$_LLVMUP_TRACKED_VARS"); do
        eval "set_flag=\${_LLVMUP_SAVED_SET_$v:-0}"
        if [ "$set_flag" = 1 ]; then
            eval "export $v=\"\${_LLVMUP_SAVED_$v}\""
        else
            unset "$v"
        fi
        unset "_LLVMUP_SAVED_SET_$v" "_LLVMUP_SAVED_$v"
    done
    for s in $(_llvmup_sys_vars); do unset "$s"; done
    for s in $(_llvmup_words "${_LLVMUP_SAVED_SYS_VARS:-}"); do
        eval "export $s=\"\${_LLVMUP_SAVED_$s}\""
        unset "_LLVMUP_SAVED_$s"
    done
    unset _LLVMUP_SAVED_SYS_VARS _LLVMUP_ENV_SAVED
    return 0
}
