# Sourced by install.sh. Keep the transaction in a subshell so traps stay local.
install_files() (
    set -e
    local manifest="$INSTALL_SOURCE_DIR/packaging/runtime-files.tsv"
    local platform mode name extra target previous i work committed=0 locked=0 recovery_failed=0 temporary
    local -a sources=() targets=() modes=() touched=() pending=() seen=()
    [[ -r $manifest ]] || { print_error "Missing runtime manifest: $manifest"; exit 1; }
    while read -r platform mode name extra; do
        [[ -z $platform || $platform == \#* ]] && continue
        [[ $platform == common || $platform == bash ]] || continue
        [[ $name =~ ^(libexec/)?[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ && $mode =~ ^(644|755)$ && -z $extra ]] || { print_error 'Invalid runtime manifest'; exit 1; }
        [[ -f $INSTALL_SOURCE_DIR/$name && ! -L $INSTALL_SOURCE_DIR/$name ]] || { print_error "Script '$name' not found in $INSTALL_SOURCE_DIR."; exit 1; }
        sources+=("$INSTALL_SOURCE_DIR/$name"); targets+=("$INSTALL_DIR/$name"); modes+=("$mode")
    done < "$manifest"
    sources+=("$manifest" "$INSTALL_SOURCE_DIR/llvmup-completion.sh" "$INSTALL_SOURCE_DIR/_llvmup")
    targets+=("$INSTALL_DIR/llvmup-files.tsv" "$COMPLETION_DIR/llvmup" "$ZSH_COMPLETION_DIR/_llvmup")
    modes+=(644 644 644)
    if [[ -f $INSTALL_SOURCE_DIR/VERSION ]]; then
        sources+=("$INSTALL_SOURCE_DIR/VERSION"); targets+=("$INSTALL_DIR/llvmup-version"); modes+=(644)
    fi
    for target in "$INSTALL_DIR" "$COMPLETION_DIR" "$ZSH_COMPLETION_DIR"; do
        [[ $target != *$'\n'* && $target != *$'\r'* ]] || { print_error 'Installation paths cannot contain line breaks'; exit 1; }
    done
    target="$INSTALL_DIR/llvmup-install-paths"
    [[ ! -L $target && ( ! -e $target || -f $target ) ]] || { print_error "Refusing non-regular destination: $target"; exit 1; }
    [[ ! -L $INSTALL_DIR/libexec && ( ! -e $INSTALL_DIR/libexec || -d $INSTALL_DIR/libexec ) ]] || { print_error 'Unsafe libexec directory'; exit 1; }
    # Validate the entire destination set before copying anything.
    for target in "${targets[@]}"; do
        for previous in "${seen[@]}"; do
            [[ $previous != "$target" ]] || { print_error "Overlapping installation destinations: $target"; exit 1; }
        done
        seen+=("$target")
        [[ ! -L $target && ( ! -e $target || -f $target ) ]] || { print_error "Refusing non-regular destination: $target"; exit 1; }
    done
    work=$(mktemp -d)
    cleanup() {
        local rc=$? n dest
        trap - EXIT HUP INT TERM
        set +e
        if (( ! committed )); then
            for n in "${touched[@]}"; do
                dest=${targets[n]}
                if [[ -f $work/$n ]]; then
                    $SUDO_CMD cp -p -- "$work/$n" "$dest" || { recovery_failed=1; print_error "Recovery failed: backup retained in $work"; }
                else
                    $SUDO_CMD rm -f -- "$dest"
                fi
            done
        fi
        for dest in "${pending[@]}"; do $SUDO_CMD rm -f -- "$dest"; done
        (( ! locked )) || $SUDO_CMD rmdir -- "$INSTALL_DIR/.llvmup-install.lock"
        (( recovery_failed )) || rm -rf -- "$work"
        exit "$rc"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    # Stage all files first; no existing installation has been changed yet.
    for i in "${!sources[@]}"; do
        cp -- "${sources[i]}" "$work/new-$i"
        chmod "${modes[i]}" "$work/new-$i"
    done
    # Record effective locations so uninstall works after the checkout is gone.
    printf '%s\n' "$INSTALL_DIR" "$COMPLETION_DIR" "$ZSH_COMPLETION_DIR" "${LLVMUP_SYSTEM_INSTALL:-0}" > "$work/paths"
    sources+=("$work/paths"); targets+=("$INSTALL_DIR/llvmup-install-paths"); modes+=(644)
    cp "$work/paths" "$work/new-$((${#sources[@]}-1))"
    create_install_directories
    $SUDO_CMD mkdir -p -- "$INSTALL_DIR/libexec"
    $SUDO_CMD mkdir -- "$INSTALL_DIR/.llvmup-install.lock" || { print_error 'Another installation is running (or a stale .llvmup-install.lock remains).'; exit 1; }
    locked=1
    for i in "${!targets[@]}"; do
        target=${targets[i]}
        [[ ! -f $target ]] || cp -p -- "$target" "$work/$i"
        temporary=$($SUDO_CMD mktemp "$target.llvmup-new-XXXXXX")
        pending+=("$temporary")
        $SUDO_CMD cp -- "$work/new-$i" "$temporary"
        $SUDO_CMD chmod "${modes[i]}" "$temporary"
        touched+=("$i")
        $SUDO_CMD mv -f -- "$temporary" "$target"
    done
    committed=1
    print_success "Installed LLVMUP files to $INSTALL_DIR"
)
