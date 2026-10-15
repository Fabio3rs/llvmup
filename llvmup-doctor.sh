#!/bin/bash
# Standalone coordinator: deliberately does not load activation or completion hooks.
# Check modules use doctor_emit ID CATEGORY STATUS DESCRIPTION RECOMMENDATION [SUBJECT].
doctor_quote() {
    local value=$1 char code i LC_ALL=C
    printf '"'
    for ((i=0; i<${#value}; i++)); do
        char=${value:i:1}
        case "$char" in
            '"') printf '\\"' ;; '\') printf '\\\\' ;;
            *) printf -v code '%d' "'$char"
               if ((code < 32)); then printf '\\u%04x' "$code"; else printf '%s' "$char"; fi ;;
        esac
    done
    printf '"'
}
doctor_emit() {
    local severity=info key value
    case "$3" in FAIL) severity=error; doctor_exit=1 ;; WARN) severity=warning ;; esac
    if ((doctor_json)); then
        printf '%s{' "$doctor_separator"; doctor_separator=,
        local fields=(id "$1" category "$2" severity "$severity" status "$3" description "$4" recommendation "$5" subject "${6:-}")
        local i
        for ((i=0;i<${#fields[@]};i+=2)); do
            ((i == 0)) || printf ','
            doctor_quote "${fields[i]}"; printf ':'; doctor_quote "${fields[i+1]}"
        done
        printf '}'
    else
        printf '%-4s [%s] %s' "$3" "$1" "$4"
        [[ -z ${6:-} ]] || printf ' (%s)' "$6"
        printf '\n'
        if [[ -n $5 ]] && { ((doctor_verbose)) || [[ $3 == WARN || $3 == FAIL ]]; }; then printf '     %s\n' "$5"; fi
    fi
}
doctor_main() {
    local doctor_json=0 doctor_verbose=0 doctor_deep=0 doctor_network=0 doctor_help=0 doctor_exit=0 doctor_separator=''
    local arg invalid='' invalid_found=0
    for arg in "$@"; do
        case "$arg" in --json) doctor_json=1 ;; --verbose) doctor_verbose=1 ;; --deep) doctor_deep=1 ;; --network) doctor_network=1 ;;
            --help|-h) doctor_help=1 ;;
            *) invalid=$arg; invalid_found=1 ;;
        esac
    done
    ((doctor_json)) && printf '{"schema_version":1,"checks":['
    if ((invalid_found)); then
        doctor_emit arguments cli FAIL "Unknown doctor option: $invalid" 'Use doctor --help.'
        doctor_exit=2
    elif ((doctor_help)); then
        doctor_emit help cli PASS 'Usage: llvmup doctor [--verbose] [--deep] [--network] [--json]' 'Exit: 0 no failures, 1 failures, 2 invalid arguments. Offline and read-only by default.'
    else
        local doctor_root
        doctor_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
        local doctor_home=${LLVM_HOME:-${LLVM_CUSTOM_HOME:-$HOME/.llvm}}
        local doctor_toolchains=${LLVM_TOOLCHAINS_DIR:-${LLVM_CUSTOM_TOOLCHAINS_DIR:-$doctor_home/toolchains}}
        # Preserve the legacy default-path normalization used by llvm-get-toolchains-dir.
        if [[ ${LLVM_TOOLCHAINS_DIR:-} == "$HOME/.llvm/toolchains" && -n ${LLVM_HOME:-} ]]; then
            doctor_toolchains=${LLVM_CUSTOM_TOOLCHAINS_DIR:-$LLVM_HOME/toolchains}
        fi
        local module
        for module in filesystem environment project probes; do
            if [[ -r $doctor_root/llvmup-doctor-$module.sh ]]; then
                source "$doctor_root/llvmup-doctor-$module.sh"
                "doctor_$module"
            else
                doctor_emit installation.module installation FAIL 'Doctor component missing or unreadable.' 'Reinstall LLVMUP from a complete checkout.' "llvmup-doctor-$module.sh"
            fi
        done
    fi
    ((doctor_json)) && printf '],"exit_code":%d}\n' "$doctor_exit"
    return "$doctor_exit"
}
doctor_main "$@"
