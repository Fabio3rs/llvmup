#!/usr/bin/env bash
# llvmup-engine.sh - recipe-driven provider engine for Bash/Zsh hosts (Linux, macOS, MSYS).
#
# It reads the same declarative recipes (libexec/recipes/*.json) as the PowerShell engine and
# reads/writes the same JSON documents (.llvmup-toolchain.json, aliases.json,
# external-toolchains.json, resolve/env JSON), so both engines can manage one LLVM_HOME.
#
# Requirements: bash, jq, tar, curl or wget, sha256sum or shasum. Optional: xz, zstd, unzip, 7z,
# gpg, gh, python3 (never required).
#
# This script runs as a child process: it never modifies the caller's shell. Session-changing
# commands (use/activate/deactivate) are implemented by the llvmup shell function, which applies
# the exports printed by "env --format shell".

set -o pipefail

ENGINE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd -- "$ENGINE_DIR/../.." && pwd)"
RECIPES_DIR="$ENGINE_ROOT/libexec/recipes"
[ -d "$RECIPES_DIR" ] || RECIPES_DIR="$ENGINE_DIR/../recipes"

ENGINE_QUIET="${LLVMUP_QUIET:-0}"

eng_err() { printf 'Error: %s\n' "$*" >&2; }
eng_warn() { printf 'Warning: %s\n' "$*" >&2; }
eng_info() { [ "$ENGINE_QUIET" = 1 ] || printf '%s\n' "$*" >&2; }
eng_die() { eng_err "$*"; exit 1; }

eng_require() {
    command -v "$1" >/dev/null 2>&1 || eng_die "'$1' is required for this operation${2:+ ($2)}"
}

# Reuse the version-expression matcher from llvm-functions.sh without registering shell hooks.
eng_load_functions() {
    local f
    for f in "$ENGINE_ROOT/llvm-functions.sh" "$ENGINE_DIR/../../llvm-functions.sh"; do
        if [ -f "$f" ]; then
            # shellcheck source=/dev/null
            LLVMUP_DISABLE_AUTOACTIVATE=1 source "$f" >/dev/null 2>&1 && return 0
        fi
    done
    return 1
}
eng_load_functions || true

# ---------------------------------------------------------------------------------------------
# Paths and host detection
# ---------------------------------------------------------------------------------------------

eng_home() {
    if [ -n "${LLVM_HOME:-}" ]; then printf '%s\n' "$LLVM_HOME"
    elif [ -n "${LLVM_CUSTOM_HOME:-}" ]; then printf '%s\n' "$LLVM_CUSTOM_HOME"
    else printf '%s\n' "$HOME/.llvm"; fi
}

eng_toolchains() {
    if command -v llvm-get-toolchains-dir >/dev/null 2>&1; then
        llvm-get-toolchains-dir
    elif [ -n "${LLVM_TOOLCHAINS_DIR:-}" ]; then
        printf '%s\n' "$LLVM_TOOLCHAINS_DIR"
    else
        printf '%s\n' "$(eng_home)/toolchains"
    fi
}

eng_cache_dir() {
    if [ -n "${LLVMUP_CACHE_DIR:-}" ]; then printf '%s\n' "$LLVMUP_CACHE_DIR"
    else printf '%s\n' "$(eng_home)/cache/downloads"; fi
}

eng_norm_os() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        "") case "$(uname -s)" in
                Linux) echo linux ;;
                Darwin) echo macos ;;
                MINGW*|MSYS*|CYGWIN*) echo windows ;;
                *) eng_die "Unsupported host OS: $(uname -s)" ;;
            esac ;;
        linux) echo linux ;;
        macos|darwin|osx) echo macos ;;
        windows|win) echo windows ;;
        *) eng_die "Unsupported platform: $1" ;;
    esac
}

eng_norm_arch() {
    local a="${1:-}"
    [ -n "$a" ] || a="$(uname -m)"
    case "$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')" in
        x64|x86_64|amd64) echo x64 ;;
        arm64|aarch64) echo arm64 ;;
        armv7a|armv7|armv7l|arm) echo armv7a ;;
        x86|i386|i686) echo x86 ;;
        *) eng_die "Unsupported architecture: $a" ;;
    esac
}

eng_exe_suffix() { [ "$(eng_norm_os)" = windows ] && echo .exe || echo ""; }

eng_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print tolower($1)}'
    else eng_die "sha256sum or shasum is required"; fi
}

eng_sha512() {
    if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | awk '{print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 512 "$1" | awk '{print tolower($1)}'
    else return 1; fi
}

eng_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---------------------------------------------------------------------------------------------
# Selectors and recipes
# ---------------------------------------------------------------------------------------------

# Prints "<provider>\t<expression>" ("" provider when none was given).
eng_split_selector() {
    local sel="$1" explicit="${2:-}" prov="" expr="$1"
    if [[ "$sel" =~ ^([A-Za-z0-9][A-Za-z0-9-]*)@(.+)$ ]]; then
        prov="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
        expr="${BASH_REMATCH[2]}"
    fi
    explicit="$(printf '%s' "$explicit" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$explicit" ] && [ -n "$prov" ] && [ "$explicit" != "$prov" ]; then
        eng_die "Conflicting providers: --provider '$explicit' vs selector '$sel'."
    fi
    [ -n "$prov" ] || prov="$explicit"
    case "$expr" in
        *,*) eng_die "Compound version expressions such as '$expr' are not supported; use a single selector (e.g. '23', '~23.1', '>=23.1.4' or '23.*')." ;;
    esac
    printf '%s\t%s\n' "$prov" "$expr"
}

eng_recipe_path() {
    local p="$RECIPES_DIR/$1.json"
    if [ ! -f "$p" ]; then
        local avail
        avail="$(cd "$RECIPES_DIR" && ls ./*.json 2>/dev/null | sed 's|^\./||; s|\.json$||' | paste -sd, -)"
        eng_die "Unknown provider '$1'. Available providers: $avail"
    fi
    printf '%s\n' "$p"
}

# ---------------------------------------------------------------------------------------------
# GitHub releases (fixtures, pagination, retries)
# ---------------------------------------------------------------------------------------------

# eng_path_warnings <provider> <root> [compiler]: print the recipe's documented path limitations for root.
eng_path_warnings() {
    local rp
    rp="$(eng_recipe_path "$1" 2>/dev/null)" || return 0
    jq -r --arg root "$2" --arg cc "${3:-}" '
        (.path_constraints // [])[]
        | select($cc == "" or ((.compilers // []) | length) == 0 or ((.compilers // []) | index($cc)))
        | select(.forbid_whitespace == true and ($root | test("\\s")))
        | "Path \"\($root)\" contains whitespace (affects: \((.compilers // []) | join(", "))). \(.reason) \(.remedy)"' "$rp" |
        while IFS= read -r w; do eng_warn "$w"; done
}

eng_http_get() {
    # eng_http_get <url> <out-file> [headers-file]
    local url="$1" out="$2" hdr="${3:-/dev/null}"
    local auth=()
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "$token" ] && [[ "$url" =~ ^https://(api\.)?github\.com/ ]]; then
        auth=(-H "Authorization: Bearer $token")
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 \
            -H 'Accept: application/vnd.github+json' -H 'User-Agent: llvmup' \
            "${auth[@]}" -D "$hdr" -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        local wauth=()
        [ ${#auth[@]} -eq 0 ] || wauth=(--header "${auth[1]}")
        wget -q --tries=3 --timeout=30 --header='Accept: application/vnd.github+json' \
            --user-agent=llvmup "${wauth[@]}" -S -O "$out" "$url" 2>"$hdr"
    else
        eng_die "curl or wget is required"
    fi
}

eng_releases() {
    # eng_releases <provider> -> JSON array on stdout
    local provider="$1"
    local key
    key="LLVMUP_$(printf '%s' "$provider" | tr '[:lower:]-' '[:upper:]_')_RELEASES_FILE"
    local fixture="${!key:-}"
    if [ -z "$fixture" ] && [ "$provider" = official ] && [ -n "${LLVMUP_RELEASES_FILE:-}" ]; then
        fixture="$LLVMUP_RELEASES_FILE"
    fi
    if [ -n "$fixture" ]; then
        [ -f "$fixture" ] || eng_die "$key does not exist: $fixture"
        jq -c 'if type == "array" then . else [.] end' "$fixture"
        return
    fi

    local api
    api="$(jq -r '.api_url' "$(eng_recipe_path "$provider")")"
    local tmp
    tmp="$(mktemp -d)"
    local url="$api?per_page=100" page=1 max_pages="${LLVMUP_MAX_RELEASE_PAGES:-5}"
    local files=()
    while [ -n "$url" ] && [ "$page" -le "$max_pages" ]; do
        if ! eng_http_get "$url" "$tmp/p$page.json" "$tmp/h$page.txt"; then
            rm -rf "$tmp"
            eng_die "GitHub API request failed for provider '$provider' (page $page)"
        fi
        files+=("$tmp/p$page.json")
        url="$(tr -d '\r' < "$tmp/h$page.txt" | grep -i '^link:' | grep -o '<[^>]*>; rel="next"' | sed 's/^<//; s/>; rel="next"$//' | head -1)"
        page=$((page + 1))
    done
    jq -cs 'add' "${files[@]}"
    rm -rf "$tmp"
}

# ---------------------------------------------------------------------------------------------
# Extractor capabilities
# ---------------------------------------------------------------------------------------------

eng_find_7z() {
    local c
    for c in "${LLVMUP_7Z_PATH:-}" 7zz 7z 7za; do
        [ -n "$c" ] || continue
        if command -v "$c" >/dev/null 2>&1; then
            # Require a modern 7-Zip (LZMA2/BCJ2, -so/-si).
            local v
            v="$("$c" i 2>/dev/null | head -4 | grep -o '7-Zip[^0-9]*[0-9][0-9]*\.[0-9]*' | grep -o '[0-9][0-9]*\.[0-9]*$' | head -1)"
            if [ -n "$v" ] && [ "${v%%.*}" -ge 15 ]; then command -v "$c"; return 0; fi
        fi
    done
    return 1
}

eng_tar_flavor() {
    local v
    v="$(tar --version 2>/dev/null | head -1)"
    case "$v" in
        *GNU*) echo gnu ;;
        *bsdtar*) echo bsd ;;
        *) echo unknown ;;
    esac
}

eng_tar_supports() {
    # eng_tar_supports xz|zstd|gz
    local fmt="$1" flavor v
    command -v tar >/dev/null 2>&1 || return 1
    flavor="$(eng_tar_flavor)"
    v="$(tar --version 2>/dev/null | head -1)"
    case "$fmt" in
        gz) return 0 ;;
        xz) if [ "$flavor" = bsd ]; then [[ "$v" == *liblzma* ]]; else command -v xz >/dev/null 2>&1; fi ;;
        zstd) if [ "$flavor" = bsd ]; then [[ "$v" == *libzstd* ]]; else command -v zstd >/dev/null 2>&1; fi ;;
        *) return 1 ;;
    esac
}

eng_formats() {
    if [ -n "${LLVMUP_ASSET_FORMATS:-}" ]; then
        printf '%s' "$LLVMUP_ASSET_FORMATS" | tr ',; ' '\n\n\n' | sed '/^$/d' | jq -Rsc 'split("\n") | map(select(length > 0))'
        return
    fi
    local f=()
    if command -v unzip >/dev/null 2>&1 || [ "$(eng_tar_flavor)" = bsd ] || eng_find_7z >/dev/null; then f+=(zip); fi
    if eng_find_7z >/dev/null; then f+=(7z); fi
    if eng_tar_supports xz || eng_find_7z >/dev/null; then f+=(tar.xz); fi
    if eng_tar_supports zstd; then f+=(tar.zst); fi
    if command -v tar >/dev/null 2>&1; then f+=(tar.gz tar); fi
    printf '%s\n' "${f[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# ---------------------------------------------------------------------------------------------
# Resolution (shared jq program; behaviour mirrors Resolve-LlvmRecipeInstallPlan)
# ---------------------------------------------------------------------------------------------

# jq program: emits one candidate object per compatible (release, asset) pair.
read -r -d '' ENG_CANDIDATES_JQ <<'JQ'
def num($s): ($s // "0" | tostring | split(".") | map(tonumber? // 0));
def ignored: test("\\.(sig|jsonl|sha256|sha512|sha256sum|txt)$");
def verif($assets; $name):
  {
    sig: ([$assets[] | select(.name == ($name + ".sig"))][0]),
    jsonl: ([$assets[] | select(.name == ($name + ".jsonl"))][0]),
    sha256: ([$assets[] | select(.name as $n | [$name + ".sha256", $name + ".sha256sum", $name + ".sha256.txt", $name + ".sha256sum.txt"] | index($n))][0]),
    sha512: ([$assets[] | select(.name as $n | [$name + ".sha512", $name + ".sha512sum", $name + ".sha512.txt"] | index($n))][0])
  };
def asset_obj($a; $fmt): {name: $a.name, url: ($a.browser_download_url // ""), size: ($a.size // 0), digest: ($a.digest // ""), id: (($a.id // "") | tostring), format: $fmt};

$recipe as $r
| ($os + ":" + $arch) as $key
| [ $releases[]
    | select((.draft // false) | not) | select((.prerelease // false) | not)
    | . as $rel
    | ($rel.tag_name // "") as $tag
    | select($tag != "")
    | select(if $release != "" then $tag == $release else ($tag | test($r.tag_rules.release_tag_pattern)) end)
    | ($rel.assets // []) as $assets
    | if $r.provider == "official" then
        ($r.asset_rules.targets[$key]) as $spec
        | select($spec != null)
        | ([ $assets[] | select(.name | ignored | not) | select(.name | test("(\\.src\\.|_doxygen|_man_pages|test-suite)") | not)
             | . as $a | $spec.archive_patterns[] | . as $rule
             | select($a.name | test($rule.pattern)) | select($formats | index($rule.format))
             | {a: $a, prio: $rule.priority, fmt: $rule.format} ] | sort_by(-.prio) | .[0]) as $best
        | select($best != null)
        | {
            tag: $tag,
            llvm_version: ($tag | capture("^llvmorg-(?<v>[0-9]+\\.[0-9]+\\.[0-9]+)$").v // ""),
            gcc_version: null, mingw_version: null, revision: null, datenum: 0,
            asset: asset_obj($best.a; $best.fmt),
            verification_assets: verif($assets; $best.a.name),
            supported_targets: $spec.supported_targets,
            default_target: $spec.supported_targets[0],
            variant: {crt: "system", threads: "system", exceptions: "system",
                      cxx_stdlib: (if $os == "windows" then "msvc" elif $os == "macos" then "libc++" else "libstdc++" end),
                      default_compiler: "clang"}
          }
      elif $r.provider == "winlibs" then
        select($os == "windows")
        | ({x64: "x86_64", x86: "i686"}[$arch]) as $an
        | select($an != null)
        | (if $crt == "" then "ucrt" else $crt end) as $wc
        | (if $threads == "" then "posix" else $threads end) as $wt
        | ([ $assets[] | select(.name | ignored | not) | . as $a
             | ($a.name | match($r.asset_rules.filename_pattern)? ) as $m
             | select($m != null)
             | ($m.captures | map(.string)) as $c
             | select($c[4] != null)
             | select($c[0] == $an and $c[5] == $wc and $c[1] == $wt)
             | select($c[8] as $e | $formats | index($e))
             | {a: $a, c: $c, score: (if ($formats | index("7z")) then (if $c[8] == "7z" then 20 else 10 end) else (if $c[8] == "zip" then 20 else 5 end) end)} ]
           | sort_by(-.score) | .[0]) as $best
        | select($best != null)
        | ({x64: "x86_64-w64-mingw32", x86: "i686-w64-mingw32"}[$arch]) as $tt
        | {
            tag: $tag, llvm_version: $best.c[4], gcc_version: $best.c[3], mingw_version: $best.c[6],
            revision: ($best.c[7] | tonumber), datenum: 0,
            asset: asset_obj($best.a; $best.c[8]),
            verification_assets: verif($assets; $best.a.name),
            supported_targets: [$tt], default_target: $tt,
            variant: {crt: $best.c[5], threads: $best.c[1], exceptions: $best.c[2], cxx_stdlib: "libstdc++", default_compiler: "clang"}
          }
      else
        ($r.asset_rules.host_patterns[$key]) as $pat
        | select($pat != null)
        | (if $crt == "" then "ucrt" else $crt end) as $mc
        | ([ $assets[] | select(.name | ignored | not) | . as $a
             | ($a.name | match($pat)?) as $m | select($m != null)
             | select(($m.captures[0].string | ascii_downcase) == $mc) | $a ][0]) as $a
        | select($a != null)
        | (if ($a.name | test("\\.tar\\.xz$")) then "tar.xz" elif ($a.name | test("\\.zip$")) then "zip" else "archive" end) as $fmt
        | select($formats | index($fmt))
        | {
            tag: $tag,
            llvm_version: ((($rel.name // "") + "\n" + ($rel.body // "")) | [match($r.tag_rules.llvm_version_metadata_regex)?][0].captures[0].string // ""),
            gcc_version: null, mingw_version: null, revision: null,
            datenum: (if ($tag | test("^[0-9]{8}$")) then ($tag | tonumber) else 0 end),
            asset: asset_obj($a; $fmt),
            verification_assets: verif($assets; $a.name),
            supported_targets: $r.asset_rules.multi_target_triples,
            default_target: ($r.asset_rules.default_target_map[$arch] // "x86_64-w64-mingw32"),
            variant: {crt: $mc, threads: "posix", exceptions: "seh", cxx_stdlib: "libc++", default_compiler: "clang"}
          }
      end
  ]
| sort_by([num(.llvm_version), .datenum, num(.gcc_version), (.revision // 0)]) | reverse
JQ

eng_version_satisfies() {
    # eng_version_satisfies <candidate> <expression>
    local cand="$1" expr="$2"
    case "$expr" in
        latest|newest|prebuilt|"") return 0 ;;
    esac
    if [[ "$expr" =~ ^[0-9]+$ ]]; then [[ "$cand" == "$expr".* ]]; return; fi
    if [[ "$expr" =~ ^[0-9]+\.[0-9]+$ ]]; then [[ "$cand" == "$expr".* ]]; return; fi
    if [[ "$expr" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then [ "$cand" = "$expr" ]; return; fi
    if [[ "$expr" =~ ^llvmorg-([0-9.]+)$ ]]; then [ "$cand" = "${BASH_REMATCH[1]}" ]; return; fi
    if command -v llvm-match-version-list >/dev/null 2>&1; then
        local out
        out="$(EXPRESSION_DEBUG=0 EXPRESSION_VERBOSE=0 llvm-match-version-list "$expr" "llvmorg-$cand" 2>/dev/null)" || return 1
        [ -n "$out" ]
        return
    fi
    eng_die "Version expression '$expr' needs llvm-functions.sh"
}

# eng_resolve_plan <provider> <expr> <release> <crt> <threads> <os> <arch> <target> -> plan JSON
eng_resolve_plan() {
    local provider="$1" expr="$2" release="$3" crt="$4" threads="$5" os="$6" arch="$7" target="$8"
    eng_require jq "release resolution"
    local recipe releases formats cands
    recipe="$(eng_recipe_path "$provider")"
    local hosts
    hosts="$(jq -r '(.asset_rules.supported_hosts // (.asset_rules.targets | keys | map(split(":")[0]))) | unique | join(", ")' "$recipe")"
    case ", $hosts, " in
        *", $os, "*) ;;
        *) eng_die "Provider '$provider' does not publish toolchains for host '$os' (supported hosts: $hosts)." ;;
    esac
    releases="$(eng_releases "$provider")" || exit 1
    if [ "$os" != "$(eng_norm_os)" ] && [ -z "${LLVMUP_ASSET_FORMATS:-}" ]; then
        formats='["tar.xz","tar.gz","tar","zip","7z"]'   # portable baseline for other hosts
    else
        formats="$(eng_formats)"
    fi
    cands="$(jq -c -n --slurpfile rs <(printf '%s' "$releases") --slurpfile rc "$recipe" \
        --arg os "$os" --arg arch "$arch" --arg crt "$crt" --arg threads "$threads" --arg release "$release" \
        --argjson formats "$formats" \
        '$rs[0] as $releases | $rc[0] as $recipe | '"$ENG_CANDIDATES_JQ")" || eng_die "Failed to evaluate releases for '$provider'"

    local n i c tag llvm chosen=""
    n="$(jq 'length' <<<"$cands")"
    for ((i = 0; i < n; i++)); do
        c="$(jq -c ".[$i]" <<<"$cands")"
        tag="$(jq -r '.tag' <<<"$c")"
        llvm="$(jq -r '.llvm_version' <<<"$c")"
        if [ -n "$target" ] && ! jq -e --arg t "$target" '.supported_targets | index($t)' <<<"$c" >/dev/null; then continue; fi
        if [ -z "$release" ] && [ "$tag" != "$expr" ]; then
            [ -n "$llvm" ] || continue
            eng_version_satisfies "$llvm" "$expr" || continue
        fi
        chosen="$c"
        break
    done
    if [ -z "$chosen" ]; then
        if [ -n "$release" ]; then
            eng_die "No compatible asset found in provider '$provider' release '$release' for $os $arch (crt=${crt:-default})."
        fi
        eng_die "No stable release of provider '$provider' matches '$expr' for $os $arch (crt=${crt:-default})."
    fi

    jq -c --arg p "$provider" --arg os "$os" --arg arch "$arch" --arg target "$target" '
        . as $c
        | {
            provider: $p,
            release_tag: $c.tag,
            revision: $c.revision,
            llvm_version: $c.llvm_version,
            gcc_version: $c.gcc_version,
            mingw_version: $c.mingw_version,
            canonical_id: (if $p == "official" then $c.tag
                           elif $p == "winlibs" then "winlibs-" + $c.tag + "-" + $arch
                           else "llvm-mingw-" + $c.tag + "-" + $c.variant.crt + "-" + $os + "-" + $arch end),
            host: {os: $os, arch: $arch},
            supported_targets: $c.supported_targets,
            default_target: (if $target != "" then $target else $c.default_target end),
            variant: ($c.variant + {profile: "full"}),
            asset: $c.asset,
            verification_assets: $c.verification_assets
          }' <<<"$chosen"
}

# ---------------------------------------------------------------------------------------------
# Download, cache, verification
# ---------------------------------------------------------------------------------------------

eng_download() {
    # eng_download <url> <dest>
    local url="$1" dest="$2"
    case "$url" in
        file://*)
            [ "${LLVMUP_ALLOW_FILE_URLS:-0}" = 1 ] || eng_die "Refusing unsupported download scheme: $url"
            ;;
        http://*|https://*) ;;
        *) eng_die "Refusing unsupported download scheme: $url" ;;
    esac
    mkdir -p "$(dirname "$dest")"
    local part="$dest.part-$$"
    rm -f "$part"
    local ok=1
    if command -v curl >/dev/null 2>&1; then
        local progress=(-sS)
        [ "$ENGINE_QUIET" = 1 ] || [ ! -t 2 ] || progress=(-#)
        curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 "${progress[@]}" -H 'User-Agent: llvmup' -o "$part" "$url" && ok=0
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=60 -O "$part" "$url" && ok=0
    else
        eng_die "curl or wget is required"
    fi
    if [ "$ok" -ne 0 ] || [ ! -s "$part" ]; then
        rm -f "$part"
        eng_die "Download failed: $url"
    fi
    mv -f "$part" "$dest"
}

eng_fetch_asset() {
    # eng_fetch_asset <plan> <workdir> -> path to verified-by-digest (if known) archive
    local plan="$1" work="$2"
    local provider name url digest id key cache_dir dest
    provider="$(jq -r '.provider' <<<"$plan")"
    name="$(jq -r '.asset.name' <<<"$plan")"
    url="$(jq -r '.asset.url' <<<"$plan")"
    digest="$(jq -r '.asset.digest // ""' <<<"$plan")"
    id="$(jq -r '.asset.id // ""' <<<"$plan")"
    if [ -n "$digest" ]; then key="$digest"; elif [ -n "$id" ]; then key="id-$id"; else key="$name"; fi
    key="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)"
    if [ "${LLVMUP_NO_CACHE:-0}" != 1 ] && [ "${ENG_NO_CACHE:-0}" != 1 ]; then
        cache_dir="$(eng_cache_dir)/$provider/$key"
        dest="$cache_dir/$name"
        if [ -f "$dest" ]; then
            if [[ "$digest" =~ ^(sha256:)?([0-9a-fA-F]{64})$ ]]; then
                local want="${BASH_REMATCH[2],,}"
                if [ "$(eng_sha256 "$dest")" = "$want" ]; then
                    ENG_CACHE_HIT=1
                    printf '%s\n' "$dest"
                    return 0
                fi
                eng_warn "Cached $name does not match its digest; downloading again"
                rm -f "$dest"
            else
                ENG_CACHE_HIT=1
                printf '%s\n' "$dest"
                return 0
            fi
        fi
    else
        dest="$work/$name"
    fi
    eng_info "Downloading $name"
    eng_download "$url" "$dest"
    if [[ "$digest" =~ ^(sha256:)?([0-9a-fA-F]{64})$ ]]; then
        local want="${BASH_REMATCH[2],,}" got
        got="$(eng_sha256 "$dest")"
        if [ "$got" != "$want" ]; then
            rm -f "$dest"
            eng_die "SHA256 digest mismatch for $name. Expected: $want, Actual: $got"
        fi
    fi
    ENG_CACHE_HIT=0
    printf '%s\n' "$dest"
}

eng_policy() {
    local p="${1:-${LLVMUP_VERIFY_POLICY:-}}"
    if [ -z "$p" ]; then
        if [ "${LLVMUP_SKIP_VERIFY:-0}" = 1 ] && [ "${LLVMUP_REQUIRE_VERIFY:-0}" = 1 ]; then
            eng_die "LLVMUP_SKIP_VERIFY and LLVMUP_REQUIRE_VERIFY cannot both be enabled."
        fi
        if [ "${LLVMUP_SKIP_VERIFY:-0}" = 1 ]; then p=skip
        elif [ "${LLVMUP_REQUIRE_VERIFY:-0}" = 1 ]; then p=strict
        else p=warn; fi
    fi
    p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
    case "$p" in warn|strict|skip) printf '%s\n' "$p" ;; *) eng_die "Invalid verification policy '$p'. Expected warn, strict, or skip." ;; esac
}

eng_checksum_from_file() {
    # eng_checksum_from_file <file> <asset-name> <hexlen>
    local f="$1" name="$2" len="$3"
    awk -v n="$name" -v l="$len" '
        { gsub("\r", ""); h = $1; fn = $2; sub(/^\*/, "", fn); sub(/.*\//, "", fn)
          if (length(h) == l && h ~ /^[0-9a-fA-F]+$/ && (fn == n || NR == 1 && NF == 1)) { print tolower(h); exit } }' "$f"
}

eng_verify() {
    # eng_verify <plan> <archive> <workdir> <policy> -> verification JSON
    local plan="$1" file="$2" work="$3" policy="$4"
    local name provider digest repo keys_url
    name="$(jq -r '.asset.name' <<<"$plan")"
    provider="$(jq -r '.provider' <<<"$plan")"
    digest="$(jq -r '.asset.digest // ""' <<<"$plan")"
    repo="$(jq -r '.verification.attestation_repo // ""' "$(eng_recipe_path "$provider")")"
    keys_url="$(jq -r '.verification.gpg_keys_url // ""' "$(eng_recipe_path "$provider")")"
    local origin_avail
    origin_avail="$(jq -r '.verification.origin_authentication_available // false' "$(eng_recipe_path "$provider")")"

    local checksum=not-provided algo="" expected="" actual="" gpg=not-provided att=not-provided fpr="" ident="" methods=()
    if [ "$policy" = skip ]; then
        jq -n --arg p "$provider" '{policy:"skip", provider:$p, checksum:"skipped", gpg:"skipped", attestation:"skipped", methods:["skipped"], authenticated_identity:null, scope:"archive"}'
        return
    fi

    if [[ "$digest" =~ ^(sha256:)?([0-9a-fA-F]{64})$ ]]; then
        expected="${BASH_REMATCH[2],,}"; actual="$(eng_sha256 "$file")"; algo=sha256
        [ "$expected" = "$actual" ] || eng_die "SHA256 digest mismatch for $name. Expected: $expected, Actual: $actual"
        checksum=valid
    fi
    local u
    u="$(jq -r '.verification_assets.sha256.browser_download_url // ""' <<<"$plan")"
    if [ "$checksum" != valid ] && [ -n "$u" ]; then
        if (eng_download "$u" "$work/sum256") 2>/dev/null; then
            expected="$(eng_checksum_from_file "$work/sum256" "$name" 64)"
            [ -n "$expected" ] || eng_die "Checksum file for $name does not contain a SHA256 digest."
            actual="$(eng_sha256 "$file")"; algo=sha256
            [ "$expected" = "$actual" ] || eng_die "SHA256 checksum mismatch for $name. Expected: $expected, Actual: $actual"
            checksum=valid
        else
            checksum=unavailable
        fi
    fi
    u="$(jq -r '.verification_assets.sha512.browser_download_url // ""' <<<"$plan")"
    if [ -n "$u" ]; then
        if (eng_download "$u" "$work/sum512") 2>/dev/null; then
            local e512 a512
            e512="$(eng_checksum_from_file "$work/sum512" "$name" 128)"
            [ -n "$e512" ] || eng_die "Checksum file for $name does not contain a SHA512 digest."
            a512="$(eng_sha512 "$file")" || a512=""
            if [ -n "$a512" ]; then
                [ "$e512" = "$a512" ] || eng_die "SHA512 checksum mismatch for $name."
                checksum=valid
                [ -n "$algo" ] || { algo=sha512; expected="$e512"; actual="$a512"; }
            fi
        elif [ "$checksum" = not-provided ]; then
            checksum=unavailable
        fi
    fi

    u="$(jq -r '.verification_assets.sig.browser_download_url // ""' <<<"$plan")"
    if [ -n "$u" ]; then
        gpg=unavailable
        local keys="${LLVMUP_RELEASE_KEYS_FILE:-}"
        if command -v gpg >/dev/null 2>&1 && { [ -n "$keys" ] || [ -n "$keys_url" ]; }; then
            if (eng_download "$u" "$work/asset.sig") 2>/dev/null; then
                if [ -n "$keys" ]; then
                    [ -f "$keys" ] || eng_die "Release keys file does not exist: $keys"
                    cp "$keys" "$work/keys.asc"
                else
                    (eng_download "$keys_url" "$work/keys.asc") 2>/dev/null || true
                fi
                if [ -s "$work/keys.asc" ]; then
                    mkdir -p "$work/gnupg"; chmod 700 "$work/gnupg"
                    if gpg --batch --homedir "$work/gnupg" --import "$work/keys.asc" >/dev/null 2>&1; then
                        local st
                        st="$(gpg --batch --homedir "$work/gnupg" --status-fd 1 --verify "$work/asset.sig" "$file" 2>/dev/null)" || true
                        if grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$st"; then
                            gpg=valid; fpr="$(grep '^\[GNUPG:\] VALIDSIG ' <<<"$st" | awk '{print $3}' | head -1)"
                            methods+=(gpg); ident="gpg:$fpr"
                        elif grep -q '^\[GNUPG:\] NO_PUBKEY ' <<<"$st"; then
                            gpg=unavailable
                        else
                            eng_die "GPG signature validation failed for $name (provider: $provider)."
                        fi
                    fi
                fi
            fi
        fi
    fi

    u="$(jq -r '.verification_assets.jsonl.browser_download_url // ""' <<<"$plan")"
    if [ -n "$u" ]; then
        att=unavailable
        if [ -n "$repo" ] && command -v gh >/dev/null 2>&1 && gh attestation verify --help >/dev/null 2>&1; then
            if (eng_download "$u" "$work/att.jsonl") 2>/dev/null; then
                local out
                if out="$(GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" gh attestation verify "$file" --repo "$repo" --bundle "$work/att.jsonl" 2>&1)"; then
                    att=valid; methods+=(sigstore); [ -n "$ident" ] || ident="github:$repo"
                elif grep -qiE 'auth|login|token' <<<"$out"; then
                    att=unavailable   # gh is present but cannot authenticate; not a verification failure
                else
                    eng_die "GitHub/Sigstore attestation validation failed for $name against $repo"
                fi
            fi
        fi
    fi

    if [ "$gpg" != valid ] && [ "$att" != valid ]; then
        if [ "$policy" = strict ]; then
            if [ "$origin_avail" != true ]; then
                eng_die "Strict verification failed: provider '$provider' does not publish cryptographic origin signatures or attestations upstream (only checksums)."
            fi
            eng_die "Strict verification requires a valid GPG signature or GitHub/Sigstore attestation for '$provider'."
        fi
        if [ ${#methods[@]} -eq 0 ]; then
            if [ "$checksum" = valid ]; then methods=(checksum-only); else methods=(unverified); fi
        fi
        if [ "$checksum" = valid ]; then
            eng_warn "Integrity of $name verified ($algo), but its origin is not authenticated (gpg=$gpg, attestation=$att)."
        else
            eng_warn "$name could not be verified: no digest, checksum, signature, or attestation was available."
        fi
    fi

    jq -n --arg policy "$policy" --arg p "$provider" --arg cs "$checksum" --arg algo "$algo" \
        --arg exp "${expected:+$algo:$expected}" --arg act "${actual:+$algo:$actual}" \
        --arg gpg "$gpg" --arg fpr "$fpr" --arg att "$att" --arg ident "$ident" \
        --args '{policy:$policy, provider:$p, checksum:$cs, checksum_algorithm:$algo, expected_digest:$exp,
                 actual_digest:$act, gpg:$gpg, gpg_fingerprint:$fpr, attestation:$att, authenticode:"not-applicable",
                 methods:$ARGS.positional, authenticated_identity:(if $ident == "" then null else $ident end), scope:"archive"}' \
        "${methods[@]}"
}

# ---------------------------------------------------------------------------------------------
# Extraction, staging, discovery, manifest
# ---------------------------------------------------------------------------------------------

eng_check_tree() {
    # Reject links that escape the staging root.
    local root="$1" l t
    local real_root
    real_root="$(cd "$root" && pwd -P)"
    while IFS= read -r -d '' l; do
        t="$(readlink "$l")"
        case "$t" in
            /*) eng_die "Unsafe absolute link in archive: ${l#"$root"/} -> $t" ;;
        esac
        local dir resolved
        dir="$(cd "$(dirname "$l")" && pwd -P)"
        resolved="$dir/$t"
        # Normalize ".." segments lexically.
        resolved="$(printf '%s' "$resolved" | awk -F/ '{n=0; for(i=1;i<=NF;i++){ if($i==""||$i==".") continue; if($i==".."){ if(n>0) n--; continue } s[++n]=$i } o=""; for(i=1;i<=n;i++) o=o"/"s[i]; print (o==""?"/":o)}')"
        case "$resolved/" in
            "$real_root"/*) ;;
            *) eng_die "Unsafe link escaping staging root: ${l#"$root"/} -> $t" ;;
        esac
    done < <(find "$root" -type l -print0)
}

eng_extract() {
    # eng_extract <archive> <dest> <extractor>
    local arc="$1" dest="$2" ext="${3:-${LLVMUP_EXTRACTOR:-auto}}"
    local raw="$dest.raw-$$"
    rm -rf "$raw"; mkdir -p "$raw"
    local fmt
    case "$arc" in
        *.tar.xz|*.txz) fmt=tar.xz ;;
        *.tar.zst|*.tzst) fmt=tar.zst ;;
        *.tar.gz|*.tgz) fmt=tar.gz ;;
        *.tar) fmt=tar ;;
        *.zip) fmt=zip ;;
        *.7z) fmt=7z ;;
        *) rm -rf "$raw"; eng_die "Unsupported archive format: $arc" ;;
    esac
    local sz=""
    sz="$(eng_find_7z 2>/dev/null)" || sz=""
    if [ "$ext" = auto ]; then
        case "$fmt" in
            tar.xz) if eng_tar_supports xz; then ext=tar; elif [ -n "$sz" ]; then ext=7z; else ext=none; fi ;;
            tar.zst) if eng_tar_supports zstd; then ext=tar; else ext=none; fi ;;
            tar.gz|tar) ext=tar ;;
            zip) if command -v unzip >/dev/null 2>&1; then ext=zip; elif [ -n "$sz" ]; then ext=7z; elif [ "$(eng_tar_flavor)" = bsd ]; then ext=tar; else ext=none; fi ;;
            7z) if [ -n "$sz" ]; then ext=7z; else ext=none; fi ;;
        esac
        [ "$ext" != none ] || { rm -rf "$raw"; eng_die "No extractor available for .$fmt archives on this host."; }
    fi
    local rc=0
    case "$ext" in
        tar)
            case "$fmt" in
                tar.xz) eng_tar_supports xz || { rm -rf "$raw"; eng_die "Requested extractor 'tar' cannot decompress xz."; } ;;
                tar.zst) eng_tar_supports zstd || { rm -rf "$raw"; eng_die "Requested extractor 'tar' cannot decompress zstd."; } ;;
                zip|7z) [ "$(eng_tar_flavor)" = bsd ] || { rm -rf "$raw"; eng_die "Extractor 'tar' cannot handle .$fmt"; } ;;
            esac
            if [ "$fmt" = tar.zst ] && [ "$(eng_tar_flavor)" = gnu ]; then
                # LLVM .tar.zst assets use a 1 GiB window (windowLog 30): zstd refuses it without --long.
                tar -I 'zstd -d --long=31' -xf "$arc" -C "$raw" --no-same-owner || rc=$?
            else
                tar -xf "$arc" -C "$raw" --no-same-owner || rc=$?
            fi ;;
        zip)
            [ "$fmt" = zip ] || { rm -rf "$raw"; eng_die "Extractor 'zip' only supports .zip archives"; }
            command -v unzip >/dev/null 2>&1 || { rm -rf "$raw"; eng_die "Requested extractor 'zip' (unzip) is not available."; }
            unzip -q "$arc" -d "$raw" || rc=$? ;;
        7z)
            [ -n "$sz" ] || { rm -rf "$raw"; eng_die "Requested extractor '7z' is not available."; }
            if [ "$fmt" = tar.xz ] || [ "$fmt" = tar.gz ]; then
                "$sz" x -so -bd "$arc" | "$sz" x -si -ttar -bd -bso0 -y "-o$raw" || rc=$?
            else
                "$sz" x -bd -bso0 -y "-o$raw" "$arc" || rc=$?
            fi ;;
        *) rm -rf "$raw"; eng_die "Invalid extractor '$ext'. Expected auto, 7z, tar, or zip." ;;
    esac
    if [ "$rc" -ne 0 ]; then rm -rf "$raw"; eng_die "Extraction failed ($ext, exit $rc): $arc"; fi
    if [ -z "$(ls -A "$raw")" ]; then rm -rf "$raw"; eng_die "Extraction produced no files: $arc"; fi
    eng_check_tree "$raw" || { rm -rf "$raw"; exit 1; }

    # Unwrap a single top-level directory (directory rename, no copy).
    rm -rf "$dest"
    local entries=("$raw"/* "$raw"/.[!.]*)
    local real=()
    local e
    for e in "${entries[@]}"; do [ -e "$e" ] || [ -L "$e" ] && real+=("$e"); done
    if [ ${#real[@]} -eq 1 ] && [ -d "${real[0]}" ] && [ ! -L "${real[0]}" ]; then
        mv "${real[0]}" "$dest"; rm -rf "$raw"
    else
        local top
        for top in mingw64 mingw32; do
            if [ -d "$raw/$top/bin" ]; then mv "$raw/$top" "$dest"; rm -rf "$raw"; ENG_EXTRACTOR="$ext"; return 0; fi
        done
        mv "$raw" "$dest"
    fi
    ENG_EXTRACTOR="$ext"
}

eng_find_rel() {
    # eng_find_rel <root> <rel-without-ext>... -> first existing relative path (with extension)
    local root="$1"; shift
    local r v
    for r in "$@"; do
        for v in "$r" "$r.exe" "$r.cmd"; do
            if [ -f "$root/$v" ]; then printf '%s\n' "$v"; return 0; fi
        done
    done
    return 1
}

eng_discover() {
    # eng_discover <root> <provider> -> {"tools":{...},"capabilities":{...}}
    local root="$1" provider="$2"
    local args=() k v
    local -a keys=(
        "clang:bin/clang" "clang++:bin/clang++" "clang-cl:bin/clang-cl"
        "lld-link:bin/lld-link" "ld.lld:bin/ld.lld" "lld:bin/lld" "ld:bin/ld"
        "llvm-ar:bin/llvm-ar" "ar:bin/ar" "llvm-ranlib:bin/llvm-ranlib" "ranlib:bin/ranlib"
        "gcc-ar:bin/gcc-ar" "gcc-ranlib:bin/gcc-ranlib" "gcc-nm:bin/gcc-nm"
        "nm:bin/nm" "llvm-nm:bin/llvm-nm" "strip:bin/strip" "llvm-strip:bin/llvm-strip"
        "objcopy:bin/objcopy" "llvm-objcopy:bin/llvm-objcopy" "dlltool:bin/dlltool" "llvm-dlltool:bin/llvm-dlltool"
        "llvm-windres:bin/llvm-windres" "windres:bin/windres" "llvm-rc:bin/llvm-rc"
        "llvm-config:bin/llvm-config" "clangd:bin/clangd" "clang-format:bin/clang-format" "clang-tidy:bin/clang-tidy"
        "lldb:bin/lldb" "gdb:bin/gdb" "pkgconf:bin/pkgconf" "pkg-config:bin/pkg-config"
        "cmake:bin/cmake" "ninja:bin/ninja" "mingw32-make:bin/mingw32-make" "gfortran:bin/gfortran"
    )
    for k in "${keys[@]}"; do
        if v="$(eng_find_rel "$root" "${k#*:}")"; then args+=(--arg "t_${k%%:*}" "$v"); fi
    done
    local gcc gxx
    gcc="$(eng_find_rel "$root" bin/gcc)" || gcc=""
    gxx="$(eng_find_rel "$root" bin/g++)" || gxx=""
    local libclang
    libclang="$(eng_find_rel "$root" bin/libclang.dll lib/libclang.dll lib/libclang.so lib/libclang.dylib)" || libclang=""

    # Target-prefixed wrappers (llvm-mingw / winlibs): <triple>-clang, <triple>-gcc, ...
    local wrappers='{}' triple suf w
    if [ -d "$root/bin" ]; then
        while IFS= read -r triple; do
            local tw='{}'
            for suf in clang clang++ ar ranlib windres ld gcc g++ nm strip dlltool objcopy; do
                if w="$(eng_find_rel "$root" "bin/$triple-$suf")"; then tw="$(jq -c --arg k "$suf" --arg v "$w" '. + {($k): $v}' <<<"$tw")"; fi
            done
            wrappers="$(jq -c --arg t "$triple" --argjson tw "$tw" '. + {($t): $tw}' <<<"$wrappers")"
        done < <(cd "$root/bin" && ls -1 2>/dev/null | sed -n 's/^\([a-z0-9_]*-w64-mingw32\)-clang\(\.exe\)\{0,1\}$/\1/p' | sort -u)
    fi

    jq -n "${args[@]}" --arg gcc "$gcc" --arg gxx "$gxx" --arg prov "$provider" --arg libclang "$libclang" \
        --argjson wrappers "$wrappers" '
        ($ARGS.named | to_entries | map(select(.key | startswith("t_"))) | map({key: (.key | ltrimstr("t_")), value}) | from_entries) as $t
        | ($prov == "llvm-mingw") as $gccIsWrapper
        | ($t
           + (if $gcc != "" then (if $gccIsWrapper then {gcc_wrapper: $gcc} else {gcc: $gcc} end) else {} end)
           + (if $gxx != "" then (if $gccIsWrapper then {gxx_wrapper: $gxx} else {"g++": $gxx} end) else {} end)
           + (if $libclang != "" then {libclang: $libclang} else {} end)
           + (if ($wrappers | length) > 0 then {target_wrappers: $wrappers} else {} end)) as $tools
        | {
            tools: $tools,
            capabilities: {
              compilers: ([if $t.clang then "clang" else empty end] + [if ($gcc != "" and ($gccIsWrapper | not)) then "gcc" else empty end]),
              linkers: [("lld-link", "ld.lld", "lld", "ld") as $l | select($t[$l]) | $l],
              resource_compilers: [("llvm-windres", "windres", "llvm-rc") as $r | select($t[$r]) | $r],
              debuggers: [("lldb", "gdb") as $d | select($t[$d]) | $d],
              has_llvm_config: ($t["llvm-config"] != null),
              has_libclang: ($libclang != ""),
              has_clangd: ($t.clangd != null),
              multi_target: (($wrappers | length) > 1),
              discovered_targets: ($wrappers | keys)
            }
          }'
}

eng_write_manifest() {
    # eng_write_manifest <root> <plan> <install-name> <verification-json> <origin>
    local root="$1" plan="$2" name="$3" ver="$4" origin="${5:-managed}"
    local disc
    disc="$(eng_discover "$root" "$(jq -r '.provider' <<<"$plan")")"
    jq -n --argjson p "$plan" --argjson d "$disc" --argjson v "$ver" --arg name "$name" --arg origin "$origin" \
        --arg now "$(eng_now)" --arg ext "${ENG_EXTRACTOR:-}" --argjson hit "${ENG_CACHE_HIT:-0}" '
        ($p.supported_targets + $d.capabilities.discovered_targets | unique) as $targets
        | {
            schema: 1, id: $p.canonical_id, install_name: $name, origin: $origin, provider: $p.provider,
            provider_release: $p.release_tag, provider_revision: $p.revision, llvm_version: $p.llvm_version,
            gcc_version: $p.gcc_version, mingw_version: $p.mingw_version, host: $p.host,
            supported_targets: ([$p.supported_targets[]] + ($d.capabilities.discovered_targets - $p.supported_targets)),
            default_target: $p.default_target, variant: $p.variant, tools: $d.tools, capabilities: $d.capabilities,
            asset: ($p.asset | del(.format) + {format: $p.asset.format}), verification: $v, installed_at: $now,
            installation: {extractor: $ext, cache_hit: ($hit == 1), engine: "bash"}
          }' > "$root/.llvmup-toolchain.json"
    jq -n --argjson p "$plan" --argjson v "$ver" '{schema:1, version:$p.release_tag, provider:$p.provider, asset_name:$p.asset.name,
        asset_digest:$p.asset.digest, policy:$v.policy, checksum:$v.checksum, gpg:$v.gpg, attestation:$v.attestation,
        methods:($v.methods | join("+")), gpg_fingerprint:$v.gpg_fingerprint, authenticated_identity:$v.authenticated_identity}' \
        > "$root/.llvmup-verification.json"
}

# ---------------------------------------------------------------------------------------------
# Installed toolchain registry
# ---------------------------------------------------------------------------------------------

eng_read_manifest() {
    # eng_read_manifest <root> <install-name> [origin-override] -> manifest JSON with root_path
    local root="$1" name="$2" origin="${3:-}"
    [ -d "$root" ] || return 1
    if [ -f "$root/.llvmup-toolchain.json" ] && jq -e '.schema == 1' "$root/.llvmup-toolchain.json" >/dev/null 2>&1; then
        jq -c --arg n "$name" --arg r "$root" --arg o "$origin" '. + {install_name: $n, root_path: $r} + (if $o != "" then {origin: $o} else {} end)' "$root/.llvmup-toolchain.json"
        return 0
    fi
    # Legacy install: describe what is on disk; never invent provenance or verification.
    local disc ver=""
    disc="$(eng_discover "$root" official)"
    [[ "$name" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && ver="${BASH_REMATCH[1]}"
    local o="${origin:-legacy}"
    [[ "$name" == source-* ]] && [ -z "$origin" ] && o=source
    jq -c -n --arg n "$name" --arg r "$root" --arg o "$o" --arg v "$ver" --argjson d "$disc" \
        --arg prov "$( [ "$o" = external ] && echo external || echo official )" '
        {schema:1, id:$n, install_name:$n, root_path:$r, origin:$o, provider:$prov, provider_release:$n, provider_revision:null,
         llvm_version:$v, gcc_version:null, mingw_version:null, host:{os:"unknown", arch:"unknown"},
         supported_targets:$d.capabilities.discovered_targets, default_target:($d.capabilities.discovered_targets[0] // ""),
         variant:{crt:"unknown", threads:"unknown", exceptions:"unknown", cxx_stdlib:"unknown", default_compiler:(if ($d.capabilities.compilers | index("clang")) then "clang" else ($d.capabilities.compilers[0] // "") end)},
         tools:$d.tools, capabilities:$d.capabilities, asset:{}, verification:{policy:"unknown", methods:"unverified", authenticated_identity:null, scope:"none"}}'
}

eng_all_toolchains() {
    # JSON array of manifests (managed + external)
    local tc d name items=()
    tc="$(eng_toolchains)"
    if [ -d "$tc" ]; then
        for d in "$tc"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"; name="$(basename "$d")"
            case "$name" in *.installing-*|*.backup-*|*.raw-*|*.staging-*) continue ;; esac
            items+=("$(eng_read_manifest "$d" "$name")")
        done
    fi
    local ext
    ext="$(eng_home)/external-toolchains.json"
    if [ -f "$ext" ]; then
        while IFS=$'\t' read -r name d; do
            [ -n "$name" ] || continue
            if [ -d "$d" ]; then
                items+=("$(eng_read_manifest "$d" "$name" external | jq -c '. + {external_registered: true}')")
            else
                items+=("$(jq -cn --arg n "$name" --arg r "$d" '{schema:1, id:$n, install_name:$n, root_path:$r, origin:"external-missing", provider:"external", llvm_version:"", tools:{}, capabilities:{compilers:[]}, missing_on_disk:true}')")
            fi
        done < <(jq -r '.toolchains // {} | to_entries[] | [.key, .value.path] | @tsv' "$ext")
    fi
    if [ ${#items[@]} -eq 0 ]; then echo '[]'; else printf '%s\n' "${items[@]}" | jq -cs '.'; fi
}

eng_resolve_installed() {
    # eng_resolve_installed <selector> [crt] -> manifest JSON (exit 1 when nothing matches)
    local sel="$1" crt="${2:-}" all
    all="$(eng_all_toolchains)"
    local aliases
    aliases="$(eng_home)/aliases.json"
    if [ -f "$aliases" ] && jq -e --arg s "$sel" '.aliases[$s]' "$aliases" >/dev/null 2>&1; then
        local target
        target="$(jq -r --arg s "$sel" '.aliases[$s].target_name' "$aliases")"
        local m
        m="$(jq -c --arg n "$target" '[.[] | select(.install_name == $n)][0] // empty' <<<"$all")"
        [ -n "$m" ] || eng_die "Alias '$sel' points to '$target', which is no longer installed. Remove the alias or reinstall '$target'."
        jq -c --arg a "$sel" '. + {resolved_via: ("alias:" + $a)}' <<<"$m"
        return 0
    fi
    local prov="" expr="$sel"
    if [[ "$sel" =~ ^([a-z0-9][a-z0-9-]*)@(.+)$ ]]; then prov="${BASH_REMATCH[1]}"; expr="${BASH_REMATCH[2]}"; fi
    local exact
    exact="$(jq -c --arg s "$sel" --arg p "$prov" --arg c "$crt" '[.[] | select((.install_name == $s or .id == $s) and ($p == "" or .provider == $p) and ($c == "" or .variant.crt == $c))] | if length == 1 then .[0] else empty end' <<<"$all")"
    if [ -n "$exact" ]; then printf '%s\n' "$exact"; return 0; fi
    local cands
    cands="$(jq -c --arg p "$prov" --arg c "$crt" '[.[] | select((.missing_on_disk // false) | not) | select($p == "" or .provider == $p) | select($c == "" or .variant.crt == $c)]' <<<"$all")"
    local n i m matched=()
    n="$(jq 'length' <<<"$cands")"
    for ((i = 0; i < n; i++)); do
        m="$(jq -c ".[$i]" <<<"$cands")"
        local iname rel ver
        iname="$(jq -r '.install_name' <<<"$m")"; rel="$(jq -r '.provider_release // ""' <<<"$m")"; ver="$(jq -r '.llvm_version // ""' <<<"$m")"
        if [ "$iname" = "$expr" ] || [ "$rel" = "$expr" ]; then matched+=("$m"); continue; fi
        if [ -n "$ver" ] && eng_version_satisfies "$ver" "$expr" 2>/dev/null; then matched+=("$m"); fi
    done
    [ ${#matched[@]} -gt 0 ] || return 1
    local arr
    arr="$(printf '%s\n' "${matched[@]}" | jq -cs '.')"
    if [ -z "$prov" ] && [ "$(jq '[.[].provider] | unique | length' <<<"$arr")" -gt 1 ]; then
        eng_die "Selector '$sel' is ambiguous across providers: $(jq -r 'map("\(.install_name) (\(.provider), LLVM \(.llvm_version))") | join(", ")' <<<"$arr"). Specify provider@version or an exact name."
    fi
    jq -c 'def num($s): ($s // "0" | tostring | split(".") | map(tonumber? // 0)); sort_by(num(.llvm_version)) | last' <<<"$arr"
}

eng_default_name() {
    local link
    link="$(eng_home)/default"
    [ -L "$link" ] || return 1
    basename "$(readlink "$link")"
}

eng_project_config() {
    # Prints the nearest .llvmup-config path
    local d="$PWD"
    while [ -n "$d" ]; do
        [ -f "$d/.llvmup-config" ] && { printf '%s\n' "$d/.llvmup-config"; return 0; }
        [ "$d" = / ] && break
        d="$(dirname "$d")"
    done
    return 1
}

eng_config_get() {
    # eng_config_get <file> <section> <key>
    awk -v sec="$2" -v key="$3" '
        /^[[:space:]]*[#;]/ { next }
        /^[[:space:]]*\[/ { s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s); cur = tolower(s); next }
        cur == sec {
            line = $0; i = index(line, "="); if (i == 0) next
            k = substr(line, 1, i - 1); v = substr(line, i + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            gsub(/^"|"$/, "", v); gsub(/^'"'"'|'"'"'$/, "", v)
            if (tolower(k) == key) { print v; exit }
        }' "$1"
}

# eng_effective <explicit-selector> -> TSV: origin\treason\tmanifest-json
eng_effective() {
    local sel="${1:-}" m=""
    if [ -n "$sel" ]; then
        m="$(eng_resolve_installed "$sel")" || eng_die "No installed toolchain matches selector '$sel'."
        printf 'explicit\tExplicitly selected %s\t%s\n' "$sel" "$m"; return 0
    fi
    if [ -n "${LLVMUP_SESSION_OVERRIDE:-}" ] && m="$(eng_resolve_installed "$LLVMUP_SESSION_OVERRIDE" 2>/dev/null)"; then
        printf 'session-override\tSession override (%s)\t%s\n' "$LLVMUP_SESSION_OVERRIDE" "$m"; return 0
    fi
    local cfg
    if [ "${LLVMUP_IGNORE_CONFIG:-0}" != 1 ] && cfg="$(eng_project_config)"; then
        local v p
        v="$(eng_config_get "$cfg" version default)"
        p="$(eng_config_get "$cfg" toolchain provider)"
        if [ -n "$v" ]; then
            local s="$v"; [ -z "$p" ] || s="$p@$v"
            if m="$(eng_resolve_installed "$s" "$(eng_config_get "$cfg" toolchain crt)" 2>/dev/null)"; then
                printf 'project-config\tProject config %s (%s)\t%s\n' "$cfg" "$s" "$m"; return 0
            fi
        fi
    fi
    if [ -n "${_ACTIVE_LLVM:-}" ] && m="$(eng_resolve_installed "$_ACTIVE_LLVM" 2>/dev/null)"; then
        printf 'active-session\tActive environment (%s)\t%s\n' "$_ACTIVE_LLVM" "$m"; return 0
    fi
    local def
    if def="$(eng_default_name)" && m="$(eng_resolve_installed "$def" 2>/dev/null)"; then
        printf 'default\tGlobal default (%s)\t%s\n' "$def" "$m"; return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------------------------
# Environment delta (mirrors Get-LlvmEnvironmentDelta)
# ---------------------------------------------------------------------------------------------

# eng_delta <manifest> <target> <compiler> -> {"prepend_path":[...],"set":{...},"unset":[...]}
eng_delta() {
    local m="$1" target="${2:-}" compiler="${3:-}"
    local root
    root="$(jq -r '.root_path' <<<"$m")"
    [ -d "$root" ] || eng_die "Toolchain root directory does not exist: $root"
    jq -c --arg target "$target" --arg compiler "$compiler" '
        . as $m
        | $m.root_path as $root
        | ($m.provider // "official") as $prov
        | (if $compiler != "" then ($compiler | ascii_downcase) elif ($m.variant.default_compiler // "") != "" then $m.variant.default_compiler else "clang" end) as $cc
        | (($m.capabilities.compilers // [])) as $avail
        | if ($avail | length) > 0 and ($avail | index($cc) | not) then
            error("Toolchain \($m.install_name) (\($prov)) does not provide compiler \($cc). Available: \($avail | join(", "))")
          else . end
        | (if $target != "" then $target else ($m.default_target // "") end) as $tgt
        | if $target != "" and (($m.supported_targets // []) | length) > 0 and (($m.supported_targets | index($target)) | not) then
            error("Toolchain \($m.install_name) (\($prov)) does not support target \($target). Supported: \($m.supported_targets | join(", "))")
          else . end
        | ($m.tools // {}) as $t
        | (if $prov == "llvm-mingw" and $tgt != "" then ($t.target_wrappers[$tgt] // {}) else {} end) as $w
        | def abs($rel): if $rel == null or $rel == "" then null else $root + "/" + $rel end;
          def first_of($map; $keys): [ $keys[] as $k | $map[$k] | select(. != null) ][0];
          (if $cc == "gcc" then
             {CC: first_of($w; ["gcc"]) // $t.gcc, CXX: first_of($w; ["g++"]) // $t["g++"],
              AR: first_of($t; ["gcc-ar", "ar"]), RANLIB: first_of($t; ["gcc-ranlib", "ranlib"]), NM: first_of($t; ["gcc-nm", "nm"]),
              STRIP: $t.strip, DLLTOOL: $t.dlltool, RC: $t.windres, LD: $t.ld}
           else
             {CC: (first_of($w; ["clang"]) // $t.clang), CXX: (first_of($w; ["clang++"]) // $t["clang++"]),
              AR: (first_of($w; ["ar"]) // first_of($t; ["llvm-ar", "ar"])), RANLIB: (first_of($w; ["ranlib"]) // first_of($t; ["llvm-ranlib", "ranlib"])),
              NM: (first_of($w; ["nm"]) // first_of($t; ["llvm-nm", "nm"])), STRIP: (first_of($w; ["strip"]) // first_of($t; ["llvm-strip", "strip"])),
              DLLTOOL: (first_of($w; ["dlltool"]) // first_of($t; ["llvm-dlltool", "dlltool"])),
              RC: (first_of($w; ["windres"]) // first_of($t; ["llvm-windres", "windres", "llvm-rc"])),
              LD: (first_of($w; ["ld"]) // (if $prov == "official" and ($root | test("^[A-Za-z]:")) then $t["lld-link"] else null end) // first_of($t; ["ld.lld", "lld"]))}
           end) as $tools
        | ($tools + {WINDRES: (if (($tools.RC // "") | test("windres")) then $tools.RC else null end),
                     PKG_CONFIG: first_of($t; ["pkgconf", "pkg-config"]), LIBCLANG_PATH: $t.libclang,
                     LLVM_CONFIG_PATH: $t["llvm-config"]}) as $rels
        | ($rels | to_entries | map({key, value: abs(.value)})) as $resolved
        | {
            prepend_path: [$root + "/bin"],
            set: (($resolved | map(select(.value != null)) | from_entries)
                  + (if (($m.llvm_version // "") | test("^[0-9]+\\.[0-9]+")) then
                       ((($m.llvm_version | split(".")[0] | tonumber) * 10 + ($m.llvm_version | split(".")[1] | tonumber)) as $mm
                        | {("LLVM_SYS_" + ($mm / 10 | floor * 10 | tostring) + "_PREFIX"): $root,
                           ("LLVM_SYS_" + ($mm | tostring) + "_PREFIX"): $root})
                     else {} end)
                  + {_ACTIVE_LLVM: $m.install_name, _ACTIVE_LLVM_PATH: $root, LLVMUP_ACTIVE_VERSION: $m.install_name,
                     LLVMUP_ACTIVE_PATH: $root, LLVMUP_ACTIVE_ID: ($m.id // $m.install_name), LLVMUP_ACTIVE_PROVIDER: $prov,
                     LLVMUP_ACTIVE_COMPILER: $cc}
                  + (if $tgt != "" then {LLVMUP_ACTIVE_TARGET: $tgt} else {} end)),
            unset: (($resolved | map(select(.value == null) | .key)) + (if $tgt == "" then ["LLVMUP_ACTIVE_TARGET"] else [] end))
          }' <<<"$m" 2> >(sed 's/^jq: error (at <stdin>:[0-9]*): /Error: /' >&2)
}

eng_print_delta() {
    # eng_print_delta <delta> <format>
    local d="$1" fmt="${2:-shell}"
    case "$fmt" in
        json) jq '{schema: 1} + .' <<<"$d" ;;
        shell|sh|bash|zsh)
            local k v p
            while IFS= read -r k; do printf 'unset %s\n' "$k"; done < <(jq -r '.unset[]' <<<"$d")
            while IFS=$'\t' read -r k v; do printf 'export %s=%q\n' "$k" "$v"; done < <(jq -r '.set | to_entries[] | [.key, .value] | @tsv' <<<"$d")
            p="$(jq -r '.prepend_path | join(":")' <<<"$d")"
            [ -z "$p" ] || printf 'export PATH=%q:"$PATH"\n' "$p"
            ;;
        github)
            [ -n "${GITHUB_PATH:-}" ] && [ -n "${GITHUB_ENV:-}" ] || eng_die "GITHUB_PATH and GITHUB_ENV are required for github format"
            jq -r '.prepend_path[]' <<<"$d" >> "$GITHUB_PATH"
            jq -r '.set | to_entries[] | select(.key | startswith("_") | not) | "\(.key)=\(.value)"' <<<"$d" >> "$GITHUB_ENV"
            ;;
        *) eng_die "Unsupported env format: $fmt (expected shell, github, or json)" ;;
    esac
}

eng_apply_delta_to_process() {
    # Apply a delta to the current (child) process environment without eval.
    local d="$1" k v
    while IFS= read -r k; do unset "$k"; done < <(jq -r '.unset[]' <<<"$d")
    while IFS=$'\t' read -r k v; do export "$k=$v"; done < <(jq -r '.set | to_entries[] | [.key, .value] | @tsv' <<<"$d")
    local p
    p="$(jq -r '.prepend_path | join(":")' <<<"$d")"
    [ -z "$p" ] || export PATH="$p:$PATH"
}

eng_resolve_exe() {
    # eng_resolve_exe <command> <delta> <manifest>
    local cmd="$1" d="$2" m="$3"
    case "$cmd" in
        */*) printf '%s\n' "$cmd"; return 0 ;;
    esac
    local mapped=""
    case "$cmd" in
        cc) mapped="$(jq -r '.set.CC // ""' <<<"$d")" ;;
        c++|cxx) mapped="$(jq -r '.set.CXX // ""' <<<"$d")" ;;
        ld) mapped="$(jq -r '.set.LD // ""' <<<"$d")" ;;
    esac
    if [ -n "$mapped" ] && [ -f "$mapped" ]; then printf '%s\n' "$mapped"; return 0; fi
    local rel
    rel="$(jq -r --arg k "$cmd" '.tools[$k] // empty | strings' <<<"$m")"
    if [ -n "$rel" ]; then
        local root
        root="$(jq -r '.root_path' <<<"$m")"
        [ -f "$root/$rel" ] && { printf '%s\n' "$root/$rel"; return 0; }
    fi
    local p
    p="$(jq -r '.prepend_path | join(":")' <<<"$d")"
    PATH="$p:$PATH" command -v "$cmd" 2>/dev/null && return 0
    eng_die "Executable '$cmd' was not found in toolchain '$(jq -r '.install_name' <<<"$m")' or PATH."
}

# ---------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------

ENG_OPT_PROVIDER="" ENG_OPT_RELEASE="" ENG_OPT_CRT="" ENG_OPT_THREADS="" ENG_OPT_TARGET="" ENG_OPT_COMPILER=""
ENG_OPT_PLATFORM="" ENG_OPT_ARCH="" ENG_OPT_NAME="" ENG_OPT_FORMAT="" ENG_OPT_VERIFY="" ENG_OPT_EXTRACTOR=""
ENG_OPT_FORCE=0 ENG_OPT_INSTALL=0 ENG_OPT_JSON=0 ENG_OPT_OUTPUT="" ENG_OPT_TOOLCHAIN="" ENG_OPT_PROFILE=""
ENG_POSITIONAL=()

eng_parse_common() {
    ENG_POSITIONAL=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --provider) ENG_OPT_PROVIDER="${2:?--provider requires a value}"; shift 2 ;;
            --release) ENG_OPT_RELEASE="${2:?--release requires a value}"; shift 2 ;;
            --crt) ENG_OPT_CRT="$(printf '%s' "${2:?--crt requires a value}" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
            --threads) ENG_OPT_THREADS="${2:?--threads requires a value}"; shift 2 ;;
            --target) ENG_OPT_TARGET="${2:?--target requires a value}"; shift 2 ;;
            --compiler) ENG_OPT_COMPILER="$(printf '%s' "${2:?--compiler requires a value}" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
            --platform) ENG_OPT_PLATFORM="${2:?--platform requires a value}"; shift 2 ;;
            --arch|--architecture) ENG_OPT_ARCH="${2:?--arch requires a value}"; shift 2 ;;
            --name|-n) ENG_OPT_NAME="${2:?--name requires a value}"; shift 2 ;;
            --format) ENG_OPT_FORMAT="${2:?--format requires a value}"; shift 2 ;;
            --verify) ENG_OPT_VERIFY="${2:?--verify requires a value}"; shift 2 ;;
            --extractor) ENG_OPT_EXTRACTOR="${2:?--extractor requires a value}"; shift 2 ;;
            --profile|-p) ENG_OPT_PROFILE="${2:?--profile requires a value}"; shift 2 ;;
            --output|-o) ENG_OPT_OUTPUT="${2:?--output requires a value}"; shift 2 ;;
            --toolchain) ENG_OPT_TOOLCHAIN="${2:?--toolchain requires a value}"; shift 2 ;;
            --force) ENG_OPT_FORCE=1; shift ;;
            --install) ENG_OPT_INSTALL=1; shift ;;
            --json) ENG_OPT_JSON=1; shift ;;
            --no-cache) ENG_NO_CACHE=1; shift ;;
            --quiet|-q) ENGINE_QUIET=1; shift ;;
            --) shift; ENG_POSITIONAL+=(--); ENG_POSITIONAL+=("$@"); break ;;
            -*) eng_die "Unknown option: $1" ;;
            *) ENG_POSITIONAL+=("$1"); shift ;;
        esac
    done
}

cmd_resolve() {
    eng_parse_common "$@"
    local sel="${ENG_POSITIONAL[0]:-latest}" prov expr split
    split="$(eng_split_selector "$sel" "$ENG_OPT_PROVIDER")" || exit 1
    IFS=$'\t' read -r prov expr <<<"$split"
    prov="${prov:-official}"; expr="${expr:-latest}"
    local plan
    plan="$(eng_resolve_plan "$prov" "$expr" "$ENG_OPT_RELEASE" "$ENG_OPT_CRT" "$ENG_OPT_THREADS" \
        "$(eng_norm_os "$ENG_OPT_PLATFORM")" "$(eng_norm_arch "$ENG_OPT_ARCH")" "$ENG_OPT_TARGET")" || exit 1
    case "${ENG_OPT_FORMAT:-tag}" in
        tag) jq -r '.release_tag' <<<"$plan" ;;
        json)
            jq '{provider, release: .release_tag, version: .release_tag, llvm_version, gcc_version, mingw_version, canonical_id,
                 asset_name: .asset.name, asset_url: .asset.url, asset_digest: .asset.digest, asset_id: .asset.id,
                 signature_url: (.verification_assets.sig.browser_download_url // ""),
                 checksum_url: (.verification_assets.sha256.browser_download_url // .verification_assets.sha512.browser_download_url // ""),
                 attestation_url: (.verification_assets.jsonl.browser_download_url // ""),
                 platform: .host.os, architecture: .host.arch, crt: .variant.crt, target: .default_target}' <<<"$plan" ;;
        plan) printf '%s\n' "$plan" ;;
        *) eng_die "--format must be tag, json, or plan" ;;
    esac
}

cmd_install() {
    eng_parse_common "$@"
    local sel="${ENG_POSITIONAL[0]:-latest}" prov expr split
    split="$(eng_split_selector "$sel" "$ENG_OPT_PROVIDER")" || exit 1
    IFS=$'\t' read -r prov expr <<<"$split"
    prov="${prov:-official}"; expr="${expr:-latest}"
    if [ -n "$ENG_OPT_PROFILE" ] && [ "$ENG_OPT_PROFILE" != full ]; then
        eng_die "Provider '$prov' currently supports only the 'full' profile (requested '$ENG_OPT_PROFILE')."
    fi
    local os arch policy plan
    os="$(eng_norm_os "$ENG_OPT_PLATFORM")"; arch="$(eng_norm_arch "$ENG_OPT_ARCH")"
    [ "$os" = "$(eng_norm_os)" ] || eng_die "Cannot install a toolchain for host '$os' on $(eng_norm_os); use 'resolve --platform' to inspect it."
    policy="$(eng_policy "$ENG_OPT_VERIFY")"
    plan="$(eng_resolve_plan "$prov" "$expr" "$ENG_OPT_RELEASE" "$ENG_OPT_CRT" "$ENG_OPT_THREADS" "$os" "$arch" "$ENG_OPT_TARGET")" || exit 1
    if [ -n "${ENG_LOCKED_DIGEST:-}" ]; then
        local up
        up="$(jq -r '.asset.digest // ""' <<<"$plan")"
        [ -z "$up" ] || [ "$up" = "$ENG_LOCKED_DIGEST" ] || eng_die "Locked digest $ENG_LOCKED_DIGEST differs from the upstream digest $up."
        plan="$(jq -c --arg d "$ENG_LOCKED_DIGEST" '.asset.digest = $d' <<<"$plan")"
    fi
    if [ -n "$ENG_OPT_COMPILER" ]; then plan="$(jq -c --arg c "$ENG_OPT_COMPILER" '.variant.default_compiler = $c' <<<"$plan")"; fi

    local name tc dest
    name="${ENG_OPT_NAME:-$(jq -r '.canonical_id' <<<"$plan")}"
    case "$name" in ""|.|..|*/*|*\\*) eng_die "Invalid installation name: $name" ;; esac
    tc="$(eng_toolchains)"; dest="$tc/$name"
    mkdir -p "$tc"
    [ "$ENGINE_QUIET" = 1 ] || eng_path_warnings "$prov" "$dest"

    local lock="$tc/.$name.llvmup.lock"
    mkdir "$lock" 2>/dev/null || eng_die "Another llvmup operation is currently installing or modifying '$name' ($lock)."
    local work staging backup
    work="$(mktemp -d)"
    staging="$dest.installing-$$"
    backup="$dest.backup-$$"
    # shellcheck disable=SC2064
    trap "rm -rf '$work' '$staging' '$staging.raw-$$'; rmdir '$lock' 2>/dev/null" EXIT

    if [ -d "$dest" ] && [ "$ENG_OPT_FORCE" -ne 1 ]; then
        if [ -f "$dest/.llvmup-toolchain.json" ] && jq -e '(.capabilities.compilers // []) | length > 0' "$dest/.llvmup-toolchain.json" >/dev/null 2>&1; then
            if [ "$policy" = strict ] && ! jq -e '.verification.gpg == "valid" or .verification.attestation == "valid"' "$dest/.llvmup-toolchain.json" >/dev/null; then
                eng_die "Strict verification cannot trust the existing toolchain: no authenticated origin is recorded."
            fi
            eng_info "Toolchain '$name' is already installed at $dest"
            printf '%s\n' "$dest"
            return 0
        fi
        eng_die "Incomplete toolchain already exists at $dest. Remove it or pass --force."
    fi

    eng_info "Installing $prov ($(jq -r '.release_tag' <<<"$plan"), LLVM $(jq -r '.llvm_version' <<<"$plan")) -> $name"
    local archive ver
    archive="$(eng_fetch_asset "$plan" "$work")" || exit 1
    [ "$(basename "$archive")" != "" ] || exit 1
    case "$archive" in "$(eng_cache_dir)"/*) ENG_CACHE_HIT="${ENG_CACHE_HIT:-0}" ;; esac
    ver="$(eng_verify "$plan" "$archive" "$work" "$policy")" || exit 1
    eng_extract "$archive" "$staging" "${ENG_OPT_EXTRACTOR:-auto}"
    [ -d "$staging/bin" ] || eng_die "Staging directory is missing bin/ for $prov"

    # Validate: a compiler must exist and answer --version.
    local disc cc
    disc="$(eng_discover "$staging" "$prov")"
    jq -e '.capabilities.compilers | length > 0' <<<"$disc" >/dev/null || eng_die "Validation failed: no supported compiler found in $staging/bin"
    cc="$(jq -r '.tools.clang // .tools.gcc' <<<"$disc")"
    "$staging/$cc" --version >/dev/null 2>&1 || eng_die "Validation failed: '$cc --version' failed"

    eng_write_manifest "$staging" "$plan" "$name" "$ver" managed

    if [ -e "$dest" ]; then mv "$dest" "$backup" || eng_die "Cannot move existing installation aside"; fi
    if ! mv "$staging" "$dest"; then
        [ ! -e "$backup" ] || mv "$backup" "$dest"
        eng_die "Failed to publish $dest"
    fi
    rm -rf "$backup"
    eng_info "[OK] Installed '$name' at $dest (verify=$(jq -r '.methods | join("+")' <<<"$ver"))"
    printf '%s\n' "$dest"
}

cmd_env() {
    eng_parse_common "$@"
    local sel="${ENG_POSITIONAL[0]:-}" line origin reason m
    if [ "$sel" = --config ] || [ -z "$sel" ]; then
        line="$(eng_effective "")" || eng_die "No installed toolchain is selected, configured, or set as default."
    else
        line="$(eng_effective "$sel")" || exit 1
    fi
    IFS=$'\t' read -r origin reason m <<<"$line"
    local d
    d="$(eng_delta "$m" "$ENG_OPT_TARGET" "$ENG_OPT_COMPILER")" || exit 1
    eng_print_delta "$d" "${ENG_OPT_FORMAT:-shell}"
}

cmd_run() {
    # cmd_run [selector] [opts] -- command args...
    local sel="" before=() cmd=() seen=0
    while [ $# -gt 0 ]; do
        if [ "$seen" -eq 1 ]; then cmd+=("$1"); shift; continue; fi
        if [ "$1" = -- ]; then seen=1; shift; continue; fi
        before+=("$1"); shift
    done
    eng_parse_common "${before[@]}"
    if [ "$seen" -eq 0 ]; then
        eng_die "Missing command after -- (e.g., llvmup run official@23 -- clang++ --version)"
    fi
    [ ${#cmd[@]} -gt 0 ] || eng_die "Missing command after -- (e.g., llvmup run official@23 -- clang++ --version)"
    sel="${ENG_POSITIONAL[0]:-}"
    local line origin reason m
    if [ -n "$sel" ]; then
        if ! m="$(eng_resolve_installed "$sel" "$ENG_OPT_CRT")"; then
            [ "$ENG_OPT_INSTALL" -eq 1 ] || eng_die "No installed toolchain matches '$sel'. Pass --install to install on demand."
            (cmd_install "$sel" ${ENG_OPT_CRT:+--crt "$ENG_OPT_CRT"} --quiet) >/dev/null || exit 1
            m="$(eng_resolve_installed "$sel" "$ENG_OPT_CRT")" || eng_die "Installed toolchain for '$sel' could not be resolved."
        fi
    else
        line="$(eng_effective "")" || eng_die "No toolchain is selected, configured, or set as default."
        IFS=$'\t' read -r origin reason m <<<"$line"
    fi
    local d exe
    d="$(eng_delta "$m" "$ENG_OPT_TARGET" "$ENG_OPT_COMPILER")" || exit 1
    exe="$(eng_resolve_exe "${cmd[0]}" "$d" "$m")" || exit 1
    eng_apply_delta_to_process "$d"
    # exec preserves arguments verbatim, the working directory, stdio, signals and the exit code.
    exec "$exe" "${cmd[@]:1}"
}

cmd_which() {
    eng_parse_common "$@"
    local tool="${ENG_POSITIONAL[0]:-}"
    [ -n "$tool" ] || eng_die "Usage: llvmup which <tool> [--toolchain <selector>]"
    local line origin reason m d exe root
    line="$(eng_effective "$ENG_OPT_TOOLCHAIN")" || eng_die "No toolchain selected or installed."
    IFS=$'\t' read -r origin reason m <<<"$line"
    d="$(eng_delta "$m" "$ENG_OPT_TARGET" "$ENG_OPT_COMPILER")" || exit 1
    exe="$(eng_resolve_exe "$tool" "$d" "$m" 2>/dev/null)" || exe=""
    root="$(jq -r '.root_path' <<<"$m")"
    case "$exe" in
        "$root"/*) printf '%s\n' "$exe" ;;
        *) eng_die "Tool '$tool' is not available in toolchain '$(jq -r '.install_name' <<<"$m")' ($(jq -r '.provider' <<<"$m"))." ;;
    esac
}

cmd_where() {
    eng_parse_common "$@"
    local line origin reason m
    line="$(eng_effective "${ENG_POSITIONAL[0]:-}")" || eng_die "No matching toolchain found."
    IFS=$'\t' read -r origin reason m <<<"$line"
    jq -r '.root_path' <<<"$m"
}

cmd_info() {
    eng_parse_common "$@"
    local line origin reason m
    line="$(eng_effective "${ENG_POSITIONAL[0]:-}")" || eng_die "No matching toolchain found."
    IFS=$'\t' read -r origin reason m <<<"$line"
    if [ "$ENG_OPT_JSON" -eq 1 ]; then jq . <<<"$m"; return; fi
    jq -r '"Name:            \(.install_name)",
           "Provider:        \(.provider)",
           "Provider release:\(" " + (.provider_release // ""))",
           "LLVM version:    \(.llvm_version // "")",
           "GCC version:     \(.gcc_version // "-")",
           "Host:            \(.host.os // "?")/\(.host.arch // "?")",
           "Targets:         \((.supported_targets // []) | join(", "))",
           "CRT:             \(.variant.crt // "-")",
           "C++ stdlib:      \(.variant.cxx_stdlib // "-")",
           "Compilers:       \((.capabilities.compilers // []) | join(", "))",
           "Path:            \(.root_path)",
           "Origin:          \(.origin)",
           "Verification:    \(.verification.methods // "unverified" | if type == "array" then join("+") else . end)"' <<<"$m"
}

cmd_status() {
    eng_parse_common "$@"
    local line origin="" reason="" m="null"
    if line="$(eng_effective "" 2>/dev/null)"; then IFS=$'\t' read -r origin reason m <<<"$line"; fi
    local active="${_ACTIVE_LLVM:-}"
    if [ "$ENG_OPT_JSON" -eq 1 ]; then
        jq -n --arg active "$active" --arg o "$origin" --arg r "$reason" --argjson m "$m" '
            {schema: 1, active_version: (if $active == "" then null else $active end),
             active_provider: (env.LLVMUP_ACTIVE_PROVIDER // null), active_compiler: (env.LLVMUP_ACTIVE_COMPILER // null),
             active_target: (env.LLVMUP_ACTIVE_TARGET // null),
             selected_for_execution: (if $m == null then null else
               {name: $m.install_name, provider: $m.provider, provider_release: $m.provider_release, llvm_version: $m.llvm_version,
                gcc_version: $m.gcc_version, host: $m.host, target: $m.default_target, crt: $m.variant.crt,
                cxx_stdlib: $m.variant.cxx_stdlib, compiler: $m.variant.default_compiler, path: $m.root_path,
                origin: $o, reason: $r, verification: $m.verification} end)}'
        return
    fi
    if [ -n "$active" ]; then echo "Active in this shell: $active (${LLVMUP_ACTIVE_PROVIDER:-official}, compiler ${LLVMUP_ACTIVE_COMPILER:-clang})"
    else echo "Active in this shell: none"; fi
    if [ "$m" != null ]; then
        echo "Selected for execution: $(jq -r '.install_name' <<<"$m") [$origin] - $reason"
    else
        echo "Selected for execution: none"
    fi
}

cmd_provides() {
    eng_parse_common "$@"
    local tool="${ENG_POSITIONAL[0]:-}"
    [ -n "$tool" ] || eng_die "Usage: llvmup provides <tool>"
    local res
    res="$(eng_all_toolchains | jq -c --arg t "$tool" '[.[] | select((.missing_on_disk // false) | not)
        | select(((.tools // {}) | has($t)) or (.capabilities.compilers // [] | index($t)))
        | {name: .install_name, provider, llvm_version, path: .root_path}]')"
    if [ "$ENG_OPT_JSON" -eq 1 ]; then jq . <<<"$res"; else jq -r '.[] | "\(.name)\t\(.provider)\tLLVM \(.llvm_version)\t\(.path)"' <<<"$res"; fi
}

cmd_list_providers() {
    local f
    for f in "$RECIPES_DIR"/*.json; do
        jq -r '"\(.provider)\t\(.display_name)\thosts: \([.asset_rules.supported_hosts // (.asset_rules.targets | keys | map(split(":")[0]) | unique)] | flatten | unique | join(","))"' "$f"
    done
}

cmd_list_installed() {
    eng_parse_common "$@"
    local all
    all="$(eng_all_toolchains)"
    if [ "$ENG_OPT_JSON" -eq 1 ]; then jq '{schema: 1, toolchains: .}' <<<"$all"; return; fi
    jq -r '.[] | "\(.install_name)\t\(.provider)\tLLVM \(.llvm_version // "?")\t\(.origin)"' <<<"$all"
}

cmd_alias() {
    local sub="${1:-list}"; shift || true
    local file
    file="$(eng_home)/aliases.json"
    mkdir -p "$(eng_home)"
    [ -f "$file" ] || printf '{"schema":1,"aliases":{}}\n' > "$file"
    case "$sub" in
        set)
            [ $# -eq 2 ] || eng_die "Usage: llvmup alias set <alias> <installed-selector>"
            [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || eng_die "Invalid alias name '$1'."
            [ "$1" != "$2" ] || eng_die "Alias '$1' cannot reference itself."
            jq -e --arg s "$2" '.aliases[$s]' "$file" >/dev/null && eng_die "Alias chains are not allowed: '$2' is already an alias."
            local m
            m="$(ENG_NO_ALIAS=1 eng_resolve_installed "$2")" || eng_die "Cannot create alias '$1': target '$2' does not match any installed toolchain."
            local tmp="$file.tmp-$$"
            jq --arg a "$1" --argjson m "$m" --arg now "$(eng_now)" \
                '.aliases[$a] = {target_name: $m.install_name, target_id: $m.id, provider: $m.provider, llvm_version: $m.llvm_version, created_at: $now}' \
                "$file" > "$tmp" && mv "$tmp" "$file"
            jq -c --arg a "$1" '.aliases[$a]' "$file"
            ;;
        list) if [ "${1:-}" = --json ]; then jq '.aliases' "$file"; else jq -r '.aliases | to_entries[] | "\(.key)\t-> \(.value.target_name) (\(.value.provider), LLVM \(.value.llvm_version))"' "$file"; fi ;;
        show) [ $# -eq 1 ] || eng_die "Usage: llvmup alias show <alias>"; jq -e --arg a "$1" '.aliases[$a]' "$file" || eng_die "Alias '$1' does not exist." ;;
        remove)
            [ $# -eq 1 ] || eng_die "Usage: llvmup alias remove <alias>"
            jq -e --arg a "$1" '.aliases[$a]' "$file" >/dev/null || eng_die "Alias '$1' does not exist."
            local tmp="$file.tmp-$$"
            jq --arg a "$1" 'del(.aliases[$a])' "$file" > "$tmp" && mv "$tmp" "$file"
            ;;
        *) eng_die "Available alias subcommands: set, list, show, remove" ;;
    esac
}

cmd_toolchain() {
    local sub="${1:-list}"; shift || true
    local file
    file="$(eng_home)/external-toolchains.json"
    mkdir -p "$(eng_home)"
    case "$sub" in
        link)
            [ $# -eq 2 ] || eng_die "Usage: llvmup toolchain link <name> <path>"
            [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || eng_die "Invalid toolchain name '$1'."
            [ ! -e "$(eng_toolchains)/$1" ] || eng_die "A managed toolchain named '$1' already exists."
            [ -d "$2" ] || eng_die "External toolchain directory does not exist: $2"
            local path
            path="$(cd "$2" && pwd)"
            eng_discover "$path" external | jq -e '.capabilities.compilers | length > 0' >/dev/null \
                || eng_die "External toolchain directory '$path' does not contain a recognizable compiler under bin/."
            [ -f "$file" ] || printf '{"schema":1,"toolchains":{}}\n' > "$file"
            local tmp="$file.tmp-$$"
            jq --arg n "$1" --arg p "$path" --arg now "$(eng_now)" '.toolchains[$n] = {name: $n, path: $p, origin: "external", registered_at: $now}' "$file" > "$tmp" && mv "$tmp" "$file"
            eng_info "Registered external toolchain '$1' -> $path (files are never modified by llvmup)"
            ;;
        unlink)
            [ $# -eq 1 ] || eng_die "Usage: llvmup toolchain unlink <name>"
            [ -f "$file" ] && jq -e --arg n "$1" '.toolchains[$n]' "$file" >/dev/null || eng_die "External toolchain '$1' is not registered."
            local tmp="$file.tmp-$$"
            jq --arg n "$1" 'del(.toolchains[$n])' "$file" > "$tmp" && mv "$tmp" "$file"
            ;;
        list) cmd_list_installed ;;
        *) eng_die "Available toolchain subcommands: link, unlink, list" ;;
    esac
}

cmd_cmake_toolchain() {
    eng_parse_common "$@"
    local line origin reason m d
    line="$(eng_effective "${ENG_POSITIONAL[0]:-}")" || eng_die "No matching toolchain found for cmake-toolchain."
    IFS=$'\t' read -r origin reason m <<<"$line"
    d="$(eng_delta "$m" "$ENG_OPT_TARGET" "$ENG_OPT_COMPILER")" || exit 1
    local host_os host_arch
    host_os="$(eng_norm_os)"; host_arch="$(eng_norm_arch)"
    local text
    text="$(jq -r --argjson d "$d" --arg hos "$host_os" --arg harch "$host_arch" '
        . as $m
        | ($d.set.LLVMUP_ACTIVE_TARGET // "") as $t
        | (if ($t | test("linux")) then "Linux" elif ($t | test("darwin|apple")) then "Darwin" elif ($t | test("windows|mingw")) then "Windows"
           elif $hos == "linux" then "Linux" elif $hos == "macos" then "Darwin" else "Windows" end) as $sys
        | (if ($t | test("^(aarch64|arm64)")) then "ARM64" elif ($t | test("^(armv7|arm)")) then "ARM" elif ($t | test("^(i686|i386|x86)-")) then "X86" else "AMD64" end) as $proc
        | ({linux: "Linux", macos: "Darwin", windows: "Windows"}[$hos]) as $hsys
        | ({x64: "AMD64", arm64: "ARM64", x86: "X86", armv7a: "ARM"}[$harch]) as $hproc
        | ($t != "" and ($sys != $hsys or $proc != $hproc)) as $cross
        | ($m.root_path + "/" + $t) as $sysroot
        | [ "# Generated by LLVMUP cmake-toolchain",
            "# Provider: \($m.provider) | Release: \($m.provider_release) | LLVM: \($m.llvm_version)",
            "# Target: \($t) | Compiler: \($d.set.LLVMUP_ACTIVE_COMPILER) | CRT: \($m.variant.crt // "unknown") | C++ StdLib: \($m.variant.cxx_stdlib // "unknown") | Cross: \($cross)",
            "# NOTE: Use a dedicated CMake build directory per toolchain/ABI/CRT/stdlib combination.",
            "#       This file never overrides the compiler of an already configured build directory.",
            "" ]
          + (if $cross then ["set(CMAKE_SYSTEM_NAME \($sys))", "set(CMAKE_SYSTEM_PROCESSOR \($proc))"] else [] end)
          + (if $d.set.CC then ["set(CMAKE_C_COMPILER \"\($d.set.CC)\")"] else [] end)
          + (if $d.set.CXX then ["set(CMAKE_CXX_COMPILER \"\($d.set.CXX)\")"] else [] end)
          + (if $d.set.AR then ["set(CMAKE_AR \"\($d.set.AR)\" CACHE FILEPATH \"Archiver\")"] else [] end)
          + (if $d.set.RANLIB then ["set(CMAKE_RANLIB \"\($d.set.RANLIB)\" CACHE FILEPATH \"Ranlib\")"] else [] end)
          + (if $d.set.RC then ["set(CMAKE_RC_COMPILER \"\($d.set.RC)\" CACHE FILEPATH \"Resource compiler\")"] else [] end)
          + (if $cross then ["set(CMAKE_FIND_ROOT_PATH \"\($sysroot)\" \"\($m.root_path)\")", "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)",
                             "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)", "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)",
                             "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"] else [] end)
        | join("\n")' <<<"$m")"
    if [ -n "$ENG_OPT_OUTPUT" ]; then
        mkdir -p "$(dirname "$ENG_OPT_OUTPUT")"
        printf '%s\n' "$text" > "$ENG_OPT_OUTPUT"
        printf '%s\n' "$ENG_OPT_OUTPUT"
    else
        printf '%s\n' "$text"
    fi
}

cmd_shell() {
    eng_parse_common "$@"
    local line origin reason m d sh
    line="$(eng_effective "${ENG_POSITIONAL[0]:-}")" || eng_die "No matching toolchain found for shell."
    IFS=$'\t' read -r origin reason m <<<"$line"
    d="$(eng_delta "$m" "$ENG_OPT_TARGET" "$ENG_OPT_COMPILER")" || exit 1
    sh="${SHELL:-/bin/bash}"
    eng_apply_delta_to_process "$d"
    export LLVMUP_SESSION_OVERRIDE
    LLVMUP_SESSION_OVERRIDE="$(jq -r '.install_name' <<<"$m")"
    eng_info "Entering a subshell with $(jq -r '.install_name' <<<"$m") active; exit to return."
    exec "$sh" -i
}

cmd_pin() {
    eng_parse_common "$@"
    local sel="${ENG_POSITIONAL[0]:-}" cfg m ver prov rel tgt comp crt
    cfg="$(eng_project_config)" || cfg="$PWD/.llvmup-config"
    if [ "$sel" = --current ] || [ -z "$sel" ]; then
        local line origin reason
        line="$(eng_effective "")" || eng_die "No active or selected toolchain to pin."
        IFS=$'\t' read -r origin reason m <<<"$line"
    else
        m="$(eng_resolve_installed "$sel" "$ENG_OPT_CRT")" || eng_die "No installed toolchain matches '$sel' (pin resolves installed toolchains offline; install it first)."
    fi
    prov="$(jq -r '.provider' <<<"$m")"
    if [ "$prov" = official ]; then ver="$(jq -r '.provider_release' <<<"$m")"; rel=""; else ver="$(jq -r '.llvm_version' <<<"$m")"; rel="$(jq -r '.provider_release' <<<"$m")"; fi
    tgt="${ENG_OPT_TARGET:-$(jq -r '.default_target // ""' <<<"$m")}"
    comp="${ENG_OPT_COMPILER:-$(jq -r '.variant.default_compiler // ""' <<<"$m")}"
    crt="${ENG_OPT_CRT:-$(jq -r '.variant.crt // "" | select(. != "system" and . != "unknown")' <<<"$m")}"
    eng_ini_set "$cfg" version default "$ver"
    eng_ini_set "$cfg" toolchain provider "$prov"
    eng_ini_set "$cfg" toolchain kind "$( [ "$(jq -r '.origin' <<<"$m")" = source ] && echo source || echo prebuilt )"
    [ -z "$crt" ] || eng_ini_set "$cfg" toolchain crt "$crt"
    [ -z "$tgt" ] || eng_ini_set "$cfg" toolchain target "$tgt"
    [ -z "$comp" ] || eng_ini_set "$cfg" toolchain compiler "$comp"
    [ -z "$rel" ] || eng_ini_set "$cfg" toolchain release "$rel"
    printf '%s\n' "$cfg"
}

eng_ini_set() {
    # eng_ini_set <file> <section> <key> <value>: preserves comments and unrelated sections.
    local file="$1" sec="$2" key="$3" val="$4" tmp
    [ -f "$file" ] || printf '# .llvmup-config - LLVMUP project configuration\n' > "$file"
    tmp="$file.tmp-$$"
    awk -v sec="$sec" -v key="$key" -v val="$val" '
        function emit() { print key " = \"" val "\""; done = 1 }
        /^[[:space:]]*\[/ {
            s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s)
            if (insec && !done) emit()
            insec = (tolower(s) == sec); seen = seen || insec
            print; next
        }
        insec && !done && $0 !~ /^[[:space:]]*[#;]/ {
            line = $0; i = index(line, "=")
            if (i > 0) { k = substr(line, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); if (tolower(k) == key) { emit(); next } }
        }
        { print }
        END { if (insec && !done) emit(); else if (!seen) { print ""; print "[" sec "]"; emit() } }' "$file" > "$tmp" && mv "$tmp" "$file"
}

usage() {
    cat <<'EOF'
Usage: llvmup-engine.sh <command> [options]

Commands:
  resolve [provider@]<expr> [--provider P] [--release TAG] [--crt C] [--platform OS] [--arch A] [--format tag|json|plan]
  install [provider@]<expr> [--name N] [--crt C] [--release TAG] [--force] [--no-cache] [--verify warn|strict|skip] [--extractor auto|tar|7z|zip]
  env [selector|--config] [--target T] [--compiler C] [--format shell|github|json]
  run [selector] [--target T] [--compiler C] [--install] -- <command> [args...]
  which <tool> [--toolchain S]      where [S]      info [S] [--json]      status [--json]
  provides <tool> [--json]          list [--json]  list-providers
  alias set|list|show|remove        toolchain link|unlink|list
  cmake-toolchain [S] [--target T] [--compiler C] [--output FILE]
  pin [S|--current]                 shell [S]
EOF
}

main() {
    local cmd="${1:-help}"
    [ $# -eq 0 ] || shift
    case "$cmd" in
        resolve) cmd_resolve "$@" ;;
        install) cmd_install "$@" ;;
        env) cmd_env "$@" ;;
        run) cmd_run "$@" ;;
        +*) cmd_run "${cmd#+}" "$@" ;;
        which) cmd_which "$@" ;;
        where) cmd_where "$@" ;;
        info) cmd_info "$@" ;;
        status) cmd_status "$@" ;;
        provides) cmd_provides "$@" ;;
        list) cmd_list_installed "$@" ;;
        list-providers) cmd_list_providers ;;
        alias) cmd_alias "$@" ;;
        toolchain) cmd_toolchain "$@" ;;
        cmake-toolchain) cmd_cmake_toolchain "$@" ;;
        shell) cmd_shell "$@" ;;
        pin) cmd_pin "$@" ;;
        discover) eng_discover "${1:?root}" "${2:-official}" ;;
        delta) eng_delta "$(eng_resolve_installed "${1:?selector}")" "${2:-}" "${3:-}" ;;
        help|-h|--help) usage ;;
        *) eng_err "Unknown engine command: $cmd"; usage >&2; exit 2 ;;
    esac
}

main "$@"
