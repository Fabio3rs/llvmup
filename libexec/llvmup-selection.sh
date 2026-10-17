# Shared adapters for the optional Python selection engine.
llvm_selection_init() {
    LLVM_SELECTION_ARGS=()
    [ -z "${PROFILE:-}" ] || LLVM_SELECTION_ARGS+=(--profile "$PROFILE")
    local component
    for component in "${COMPONENTS[@]+"${COMPONENTS[@]}"}"; do
        LLVM_SELECTION_ARGS+=(--component "$component")
    done
    [ "${STRIP:-0}" -eq 0 ] || LLVM_SELECTION_ARGS+=(--strip)
    [ "${1:-}" != source ] || LLVM_SELECTION_ARGS+=(--source)
    LLVM_SELECTION_ENABLED=0
    LLVM_SELECTION_JSON='{"selective":false,"legacy":false,"key":"full"}'
    if { [ -n "${PROFILE:-}" ] && [ "$PROFILE" != full ]; } || [ -n "${COMPONENTS[*]-}" ] || [ "${STRIP:-0}" -eq 1 ]; then
        command -v python3 >/dev/null || { echo 'Selective installation requires Python 3.' >&2; return 1; }
        LLVM_SELECTION_JSON=$(python3 "$SCRIPT_DIR/libexec/llvmup-selection.py" selection "${LLVM_SELECTION_ARGS[@]}") || return 1
        LLVM_SELECTION_ENABLED=1
    fi
    if [ "${STRIP:-0}" -eq 1 ]; then
        command -v llvm-strip >/dev/null || command -v strip >/dev/null || { echo '--strip requires llvm-strip or strip on PATH.' >&2; return 1; }
    fi
}

llvm_selection_check() {
    if [ "$LLVM_SELECTION_ENABLED" -eq 1 ]; then
        python3 "$SCRIPT_DIR/libexec/llvmup-selection.py" check --root "$1" "${LLVM_SELECTION_ARGS[@]}"
    elif [ -f "$1/.llvmup-installation.json" ]; then
        jq -e '.schema == 1 and .components == ["*"] and .strip == false' "$1/.llvmup-installation.json" >/dev/null || {
            echo 'Installed components/strip differ; use another --name or remove it explicitly.' >&2; return 1;
        }
    fi
}

llvm_selection_finalize() {
    if [ "$LLVM_SELECTION_ENABLED" -eq 1 ]; then
        python3 "$SCRIPT_DIR/libexec/llvmup-selection.py" finalize --root "$1" "${LLVM_SELECTION_ARGS[@]}"
    else
        jq -n '{schema:1, profile:"full", components:["*"], strip:false, key:"full", files:[]}' > "$1/.llvmup-installation.json"
    fi
}

llvm_space_snapshot() {
    [ "${VERBOSE:-0}" -eq 1 ] || return 0
    local label=$1 path probe
    shift
    echo "Disk usage: $label" >&2
    for path in "$@"; do
        [ -n "$path" ] || continue
        probe=$path
        while [ ! -e "$probe" ]; do probe=$(dirname -- "$probe"); done
        df -Pk -- "$probe" >&2 || true
        [ -e "$path" ] || continue
        du -sk -- "$path" >&2 || true
        if [ -d "$path" ]; then
            du -k --max-depth=1 -- "$path" 2>/dev/null >&2 || true
            find "$path" -type f -printf '%s %p\n' 2>/dev/null | sort -nr | head -20 >&2 || true
        fi
    done
    return 0
}
