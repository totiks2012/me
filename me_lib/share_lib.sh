#!/usr/bin/env bash
# cit: share.sh__22-10-2026_19-57-43 — изм�рефакторинг скрипта по контракту @scripts

ME_CONF="${HOME}/.config/me/me.conf"
CONF_DIR="${HOME}/.config/me"
ME_LIB="${HOME}/.local/bin/me/me_lib"
ME_DIR="${HOME}/.local/bin/me"

# Извлечение мета-блока метода из me.conf по контракту #@script:
# (без тел функций: от строки #@method: <name> до следующего #@method: или EOF)
extract_method_block() {
    local conf="$1" name="$2"
    local in_block=0
    local -a lines=()
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$in_block" -eq 0 ]; then
            if [[ "$line" =~ ^#@method:[[:space:]]*"$name"[[:space:]]*$ ]]; then
                in_block=1
                lines+=("$line")
            fi
        else
            if [[ "$line" =~ ^#@method:[[:space:]]*[^[:space:]]+[[:space:]]*$ ]]; then
                break
            fi
            lines+=("$line")
        fi
    done < "$conf"

    [ "$in_block" -eq 0 ] && return 1

    local last=${#lines[@]}
    while [ "$last" -gt 0 ] && [[ -z "${lines[$((last - 1))]//[[:space:]]/}" ]]; do
        last=$((last - 1))
    done

    local j
    for ((j = 0; j < last; j++)); do
        printf '%s\n' "${lines[$j]}"
    done
    return 0
}

# Резолв пути скрипта из #@script: (семантика движка `me` в script_dir())
resolve_script() {
    local name="$1"
    awk -v t="$name" '
        /^#@method:[ \t]*/ { m = $2 }
        m == t && /^#@script:[ \t]*/ {
            sub(/^#@script:[ \t]*/, "")
            print
            exit
        }
        m != "" && m != t && /^#@script:/ { m = "" }
    ' "$ME_CONF"
    return 0
}

find_refs_in() {
    local text="$1"
    text=$(printf '%s\n' "$text" | grep -v '^[[:space:]]*#')
    printf '%s\n' "$text" | grep -oE '\$HOME/[^'\'\"']*me_lib/[a-zA-Z0-9_.-]+' 2>/dev/null | sed "s|\$HOME|$HOME|"
    printf '%s\n' "$text" | grep -oE '\$HOME/\.local/bin/me/[a-zA-Z0-9_.-]+' 2>/dev/null | sed "s|\$HOME|$HOME|"
    printf '%s\n' "$text" | grep -oE "$HOME/[^'\'\"']*me_lib/[a-zA-Z0-9_.-]+" 2>/dev/null
    printf '%s\n' "$text" | grep -oE "$HOME/\.local/bin/me/[a-zA-Z0-9_.-]+" 2>/dev/null
    printf '%s\n' "$text" | grep -oE '\$HOME/\.config/me/[a-zA-Z0-9_.-]+' 2>/dev/null | sed "s|\$HOME|$HOME|"
    printf '%s\n' "$text" | grep -oE "$HOME/\.config/me/[a-zA-Z0-9_.-]+" 2>/dev/null
}

find_method_deps() {
    local name="$1"
    local rpath srp

    rpath=$(resolve_script "$name")
    [ -z "$rpath" ] && return 0
    case "$rpath" in
        /*) srp="$rpath" ;;
        *)  srp="$ME_DIR/$rpath" ;;
    esac
    [ -f "$srp" ] || return 0

    local -a deps=()
    local -a queue=("$srp")
    local item seen=""

    while [ ${#queue[@]} -gt 0 ]; do
        item="${queue[0]}"
        queue=("${queue[@]:1}")

        echo "$seen" | grep -qF "$item" && continue
        seen="$seen"$'\n'"$item"
        deps+=("$item")

        local content
        content=$(cat "$item" 2>/dev/null) || continue
        while IFS= read -r ref; do
            [ -f "$ref" ] || continue
            [ "$ref" = "$ME_CONF" ] && continue
            echo "$seen" | grep -qF "$ref" && continue
            queue+=("$ref")
        done <<< "$(find_refs_in "$content" | sort -u)"
    done

    printf '%s\n' "${deps[@]}"
}

install_lib_script() {
    local name="$1" content="$2" force="${3:-0}"
    local target="$ME_LIB/$name"
    if [ -f "$target" ] && [ "$force" != 1 ]; then
        echo -n "[me] Скрипт '$name' уже существует. Заменить? [y/N] " >&2
        read -r answer
        if [[ ! "$answer" =~ ^[yY] ]]; then
            echo "[me]   $name — пропущен" >&2
            return
        fi
        echo "[me]   $name — заменён" >&2
    elif [ -f "$target" ]; then
        echo "[me]   $name — заменён (force)" >&2
    else
        echo "[me]   $name — добавлен" >&2
    fi
    printf '%s\n' "$content" > "$target"
    chmod +x "$target" 2>/dev/null || true
}

# Гард контракта: блок метода обязан содержать #@script:
# (старые пакеты — блоки с телом me_method_* без #@script: — не импортируются)
block_has_script() {
    grep -q '^#@script:' <<< "$1"
}

cmd_share() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "[me] Укажи имя метода: me share <method>" >&2
        return 1
    fi

    if ! grep -q "^#@method:[[:space:]]*$name[[:space:]]*\$" "$ME_CONF" 2>/dev/null; then
        echo "[me] Метод '$name' не найден в $ME_CONF" >&2
        return 1
    fi

    extract_method_block "$ME_CONF" "$name" || {
        echo "[me] Ошибка извлечения метода '$name'" >&2
        return 1
    }
}

generate_installer() {
    local tmpdir="$1"
    cat > "$tmpdir/install.sh" << 'INSEOF'
#!/usr/bin/env bash
set -e

ME_CONF="${HOME}/.config/me/me.conf"
ME_LIB="${HOME}/.local/bin/me/me_lib"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

FORCE=0
[ "${1:-}" = "-f" ] && FORCE=1

mkdir -p "$(dirname "$ME_CONF")"
[ -f "$ME_CONF" ] || : > "$ME_CONF"

ask_replace() {
    [ "$FORCE" = 1 ] && return 0
    echo -n "[me] $1 существует. Заменить? [y/N] " >&2
    read -r answer
    [[ "$answer" =~ ^[yY] ]]
}

METHOD_BLOCK=$(cat "$SELF_DIR/method.block")
METHOD_NAME=$(echo "$METHOD_BLOCK" | awk '/^#@method:/ {print $2; exit}')
[ -z "$METHOD_NAME" ] && { echo "[me] #@method: не найден" >&2; exit 1; }

echo "$METHOD_BLOCK" | bash -n /dev/stdin 2>/dev/null || {
    echo "[me] Ошибка синтаксиса метода" >&2
    exit 1
}

if grep -q "^#@method:[[:space:]]*${METHOD_NAME}[[:space:]]*\$" "$ME_CONF" 2>/dev/null; then
    if [ "$FORCE" != 1 ]; then
        echo -n "[me] Метод '${METHOD_NAME}' существует. Заменить? [y/N] " >&2
        read -r answer
        [[ "$answer" =~ ^[yY] ]] || { echo "[me] Отменено" >&2; exit 0; }
    fi
fi

TMP_CONF=$(mktemp "/tmp/me_install_XXXXXX.conf")
awk -v name="$METHOD_NAME" '
    /^#@method:[ \t]*/ {
        if ($2 == name) { skip = 1; next }
        skip = 0
    }
    !skip { print }
' "$ME_CONF" > "$TMP_CONF"

printf '\n%s\n' "$METHOD_BLOCK" >> "$TMP_CONF"

bash -n "$TMP_CONF" 2>/dev/null || {
    echo "[me] Ошибка: конфиг после установки содержит ошибки" >&2
    rm -f "$TMP_CONF"
    exit 1
}
[ -s "$ME_CONF" ] && cp "$ME_CONF" "$ME_CONF.bak.$(date +%s)"
cp "$TMP_CONF" "$ME_CONF"
rm -f "$TMP_CONF"
echo "[me] Метод '${METHOD_NAME}' — OK" >&2

if [ -d "$SELF_DIR/lib" ] || [ -d "$SELF_DIR/conf" ] || [ -d "$SELF_DIR/root" ] || [ -d "$SELF_DIR/confhome" ]; then
    install_files() {
        local srcdir="$1" dstdir="$2" msg
        [ -d "$srcdir" ] || return 0
        mkdir -p "$dstdir"
        for f in "$srcdir/"*; do
            [ -f "$f" ] || continue
            bn=$(basename "$f")
            if [ -e "$dstdir/$bn" ]; then
                if ! ask_replace "$bn"; then
                    echo "[me]   $bn — пропущен" >&2
                    continue
                fi
                msg="заменён"
            else
                msg="добавлен"
            fi
            cp "$f" "$dstdir/$bn"
            chmod +x "$dstdir/$bn" 2>/dev/null || true
            echo "[me]   $bn — $msg" >&2
        done
    }
    install_files "$SELF_DIR/lib" "$ME_LIB"
    install_files "$SELF_DIR/conf" "$HOME/.local/bin/me"
    install_files "$SELF_DIR/root" "$HOME/.local/bin/me"
    install_files "$SELF_DIR/confhome" "$HOME/.config/me"
fi

echo "[me] Установка завершена." >&2
INSEOF
    chmod +x "$tmpdir/install.sh"
}

cmd_share_package() {
    local name="$1"
    local tmpdir
    tmpdir=$(mktemp -d "/tmp/me_pkg_XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN

    if ! cmd_share "$name" > "$tmpdir/method.block"; then
        return 1
    fi

    echo "[me] Метод '$name' упакован." >&2

    local deps
    deps=$(find_method_deps "$name") || true
    if [ -n "$deps" ]; then
        echo "[me] Найдены зависимости:" >&2
        while IFS= read -r dep; do
            [ -f "$dep" ] || continue
            if [[ "$dep" == "$CONF_DIR/"* ]]; then
                [ "$(basename "$dep")" = "me.conf" ] && {
                    echo "  - me.conf — пропущен (не упаковывается)" >&2
                    continue
                }
                mkdir -p "$tmpdir/confhome"
                cp "$dep" "$tmpdir/confhome/"
                echo "  - $(basename "$dep") → confhome/" >&2
                continue
            fi
            local rel
            rel=$(echo "$dep" | sed "s|$ME_DIR/||")
            local dn
            dn=$(dirname "$rel")
            if [ "$dn" = "me_lib" ]; then
                mkdir -p "$tmpdir/lib"
                cp "$dep" "$tmpdir/lib/"
                echo "  - $rel → lib/" >&2
            elif [ "$dn" = "." ] && [[ "$rel" == *.conf ]]; then
                mkdir -p "$tmpdir/conf"
                cp "$dep" "$tmpdir/conf/"
                echo "  - $rel → conf/" >&2
            elif [ "$dn" = "." ]; then
                mkdir -p "$tmpdir/root"
                cp "$dep" "$tmpdir/root/"
                echo "  - $rel → root/" >&2
            else
                mkdir -p "$tmpdir/$dn"
                cp "$dep" "$tmpdir/$dn/"
                echo "  - $rel" >&2
            fi
        done <<< "$deps"
    fi

    generate_installer "$tmpdir"

    local import_dir="$ME_DIR/import"
    mkdir -p "$import_dir"
    local archive="$import_dir/${name}.tar.gz"
    tar -czf "$archive" -C "$tmpdir" . 2>/dev/null
    echo "[me] Пакет: $archive" >&2
    printf '%s\n' "$archive"
}

import_method_block() {
    local conf="$1" name="$2" block="$3"
    local tmp
    tmp=$(mktemp "/tmp/me_import_XXXXXX")
    trap 'rm -f "$tmp"' RETURN

    if grep -q "^#@method:[[:space:]]*${name}[[:space:]]*$" "$conf"; then
        awk -v name="$name" '
            /^#@method:[ \t]*/ {
                if ($2 == name) { skip = 1; next }
                skip = 0
            }
            !skip { print }
        ' "$conf" > "$tmp"
        printf '\n%s\n' "$block" >> "$tmp"
    else
        {
            cat "$conf"
            echo ""
            printf '%s\n' "$block"
        } > "$tmp"
    fi

    local err
    if ! err=$(bash -n "$tmp" 2>&1); then
        echo "[me] Ошибка синтаксиса импортируемого метода:" >&2
        echo "$err" | sed 's/^/  /' >&2
        return 1
    fi

    cp "$tmp" "$conf"
    return 0
}

cmd_import() {
    local mode="single" FORCE=0 source=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -all)  mode="all" ;;
            -diff) mode="diff" ;;
            -f)    FORCE=1 ;;
            -*)    echo "[me] Неизвестная опция: $1" >&2; return 1 ;;
            *)     source="$1" ;;
        esac
        shift
    done

    if [ "$mode" = "all" ]; then
        cmd_import_all "$source" "$FORCE"
        return $?
    fi
    if [ "$mode" = "diff" ]; then
        cmd_import_diff "$source"
        return $?
    fi

    if [ -z "$source" ]; then
        echo "[me] Укажи имя метода или путь к tar.gz: me import <method|file>" >&2
        echo "  me import gifx        — из ~/.local/bin/me/import/gifx.tar.gz" >&2
        echo "  me import ./pkg.tar.gz — из произвольного пути" >&2
        echo "  me import -f <архив|method>       — импорт без вопросов (force)" >&2
        echo "  me import -all [-f] [<архив>] — batch-импорт (по умолчанию me_all.tar.gz)" >&2
        echo "  me import -diff [<архив>]     — dry-run сравнение (по умолчанию me_all.tar.gz)" >&2
        return 1
    fi

    local archive=""

    if [ -f "$source" ]; then
        archive="$source"
    else
        archive="$ME_DIR/import/${source}.tar.gz"
        if [ ! -f "$archive" ]; then
            echo "[me] Не найден: ни '$source' как файл, ни '${source}.tar.gz' в import/" >&2
            return 1
        fi
    fi

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/me_import_XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN

    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null || {
        echo "[me] Ошибка распаковки архива" >&2
        return 1
    }

    if [ -f "$tmpdir/method.block" ] && ! grep -q '^#@script:' "$tmpdir/method.block"; then
        echo "[me] Пакет в старом формате (в method.block нет #@script:)" >&2
        echo "Пересобери пакет заново: me share <метод> / me share -all" >&2
        return 1
    fi

    if [ -f "$tmpdir/install.sh" ]; then
        if [ "$FORCE" = 1 ]; then
            bash "$tmpdir/install.sh" -f
        else
            bash "$tmpdir/install.sh"
        fi
        return $?
    fi

    [ -f "$tmpdir/method.block" ] && {
        local block
        block=$(cat "$tmpdir/method.block")
        local mname
        mname=$(echo "$block" | awk '/^#@method:/ {print $2; exit}')
        [ -n "$mname" ] && block_has_script "$block" && import_method_block "$ME_CONF" "$mname" "$block" && {
            echo "[me] Метод '$mname' импортирован." >&2
            if [ -d "$tmpdir/lib" ]; then
                local count=0
                for f in "$tmpdir/lib/"*; do
                    [ -f "$f" ] || continue
                    install_lib_script "$(basename "$f")" "$(cat "$f")" "$FORCE"
                    count=$((count + 1))
                done
                [ "$count" -gt 0 ] && echo "[me] Скриптов импортировано: $count" >&2
            fi
            return 0
        }
    }

    echo "[me] Архив не содержит method.block или install.sh" >&2
    return 1
}

# Разбивает method.block (несколько #@method:) на отдельные блоки в outdir/*.block
split_method_blocks() {
    local src="$1" outdir="$2"
    local current="" outfile=""
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^#@method:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
            current="${BASH_REMATCH[1]}"
            outfile="$outdir/$current.block"
            : > "$outfile"
        fi
        if [ -n "$current" ]; then
            printf '%s\n' "$line" >> "$outfile"
        fi
    done < "$src"
    return 0
}

colorize_diff() {
    local C_RESET=$'\033[0m' C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_CYAN=$'\033[36m'
    while IFS= read -r l; do
        case "$l" in
            @@*) printf '%s%s%s\n' "$C_CYAN" "$l" "$C_RESET" ;;
            +++*) printf '%s%s%s\n' "$C_GREEN" "$l" "$C_RESET" ;;
            ---*) printf '%s%s%s\n' "$C_RED" "$l" "$C_RESET" ;;
            +*) printf '%s%s%s\n' "$C_GREEN" "$l" "$C_RESET" ;;
            -*) printf '%s%s%s\n' "$C_RED" "$l" "$C_RESET" ;;
            *) printf '%s\n' "$l" ;;
        esac
    done
}

# Неразрушающая пакетная установка файлов из lib/conf/root (для fallback-импорта)
install_batch_files() {
    local tmpdir="$1" force="$2"
    local ok=0 skip=0 f dstdir sub rel target

    for sub in "lib:$ME_LIB" "conf:$ME_DIR" "root:$ME_DIR" "confhome:$HOME/.config/me"; do
        local srcdir="${sub%%:*}"
        dstdir="${sub##*:}"
        [ -d "$tmpdir/$srcdir" ] || continue
        mkdir -p "$dstdir"
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            rel="${f#"$tmpdir/$srcdir"/}"
            target="$dstdir/$rel"
            mkdir -p "$(dirname "$target")"
            if [ -e "$target" ] && [ "$force" != 1 ]; then
                echo "[SKIP] $srcdir/$rel — уже существует" >&2
                skip=$((skip + 1))
            else
                cp "$f" "$target"
                chmod +x "$target" 2>/dev/null || true
                echo "[OK] $srcdir/$rel" >&2
                ok=$((ok + 1))
            fi
        done < <(find "$tmpdir/$srcdir" -type f 2>/dev/null)
    done

    [ "$ok" -gt 0 ] || [ "$skip" -gt 0 ] && echo "[me] Файлы: [OK] $ok, [SKIP] $skip" >&2
}

# Fallback batch-импорт для архивов без install.sh
import_batch() {
    local tmpdir="$1" force="$2"
    local blockfile="$tmpdir/method.block"
    [ -f "$blockfile" ] || return 1

    local blocksdir
    blocksdir=$(mktemp -d "/tmp/me_batch_blocks_XXXXXX")
    trap 'rm -rf "$blocksdir"' RETURN
    split_method_blocks "$blockfile" "$blocksdir" || return 1

    local ok=0 skip=0 bf name
    for bf in "$blocksdir"/*.block; do
        [ -f "$bf" ] || continue
        name=$(basename "$bf" .block)
        if ! grep -q '^#@script:' "$bf"; then
            echo "[SKIP] метод '$name' — старый формат (нет #@script:), пересобери пакет" >&2
            skip=$((skip + 1))
            continue
        fi
        if grep -q "^#@method:[[:space:]]*${name}[[:space:]]*\$" "$ME_CONF" 2>/dev/null; then
            if [ "$force" = 1 ]; then
                import_method_block "$ME_CONF" "$name" "$(cat "$bf")" || return 1
                echo "[OK] метод '$name' — заменён" >&2
                ok=$((ok + 1))
            else
                echo "[SKIP] метод '$name' — уже существует" >&2
                skip=$((skip + 1))
            fi
        else
            import_method_block "$ME_CONF" "$name" "$(cat "$bf")" || return 1
            echo "[OK] метод '$name' — добавлен" >&2
            ok=$((ok + 1))
        fi
    done

    install_batch_files "$tmpdir" "$force"
    echo "[me] Импорт завершён: [OK] $ok, [SKIP] $skip" >&2
    return 0
}

cmd_import_all() {
    local source="$1" force="$2"
    local archive=""

    if [ -z "$source" ]; then
        archive="$ME_DIR/import/me_all.tar.gz"
        if [ ! -f "$archive" ]; then
            echo "[me] Не найден архив по умолчанию: $archive" >&2
            echo "[me] Сначала собери его: me share -all" >&2
            return 1
        fi
    elif [ -f "$source" ]; then
        archive="$source"
    else
        archive="$ME_DIR/import/${source}.tar.gz"
        if [ ! -f "$archive" ]; then
            echo "[me] Не найден: ни '$source' как файл, ни '${source}.tar.gz' в import/" >&2
            return 1
        fi
    fi

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/me_import_all_XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN

    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null || {
        echo "[me] Ошибка распаковки архива" >&2
        return 1
    }

    echo "[me] Batch-импорт: $(basename "$archive")" >&2

    if [ -f "$tmpdir/method.block" ] && ! grep -q '^#@script:' "$tmpdir/method.block"; then
        echo "[me] Пакет в старом формате (в method.block нет #@script:)" >&2
        echo "Пересобери пакет заново: me share -all" >&2
        return 1
    fi

    if [ -f "$tmpdir/install.sh" ]; then
        if [ "$force" = 1 ]; then
            bash "$tmpdir/install.sh" -f
        else
            bash "$tmpdir/install.sh"
        fi
        return $?
    fi

    if [ -f "$tmpdir/method.block" ]; then
        echo "[me] В архиве нет install.sh — использую встроенный batch-импорт" >&2
        import_batch "$tmpdir" "$force"
        return $?
    fi

    echo "[me] Архив не содержит install.sh или method.block" >&2
    return 1
}

diff_files() {
    local tmpdir="$1" sub="$2" localdir="$3"
    [ -d "$tmpdir/$sub" ] || return 0
    local f rel
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        rel="${f#"$tmpdir/$sub"/}"
        echo "" >&2
        if [ -f "$localdir/$rel" ]; then
            if diff -q "$f" "$localdir/$rel" >/dev/null 2>&1; then
                echo "[OK] $sub/$rel — идентичен" >&2
            else
                echo "[DIFF] $sub/$rel — конфликт:" >&2
                diff -u "$localdir/$rel" "$f" | colorize_diff | sed 's/^/  /' >&2
            fi
        else
            echo "[OK] $sub/$rel — отсутствует локально (будет добавлен)" >&2
        fi
    done < <(find "$tmpdir/$sub" -type f 2>/dev/null)
}

cmd_import_diff() {
    local source="$1"
    local archive=""

    if [ -z "$source" ]; then
        archive="$ME_DIR/import/me_all.tar.gz"
        if [ ! -f "$archive" ]; then
            echo "[me] Не найден архив по умолчанию: $archive" >&2
            echo "[me] Сначала собери его: me share -all" >&2
            return 1
        fi
    elif [ -f "$source" ]; then
        archive="$source"
    else
        archive="$ME_DIR/import/${source}.tar.gz"
        if [ ! -f "$archive" ]; then
            echo "[me] Не найден: ни '$source' как файл, ни '${source}.tar.gz' в import/" >&2
            return 1
        fi
    fi

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/me_diff_XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN

    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null || {
        echo "[me] Ошибка распаковки архива" >&2
        return 1
    }

    echo "[me] DIFF-анализ: $(basename "$archive") (dry-run, ничего не применяется)" >&2

    if [ -f "$tmpdir/method.block" ]; then
        local blocksdir
        blocksdir=$(mktemp -d "/tmp/me_diff_blocks_XXXXXX")
        trap 'rm -rf "$blocksdir"' RETURN
        split_method_blocks "$tmpdir/method.block" "$blocksdir"

        local bf name existing incoming tmpa tmpb
        for bf in "$blocksdir"/*.block; do
            [ -f "$bf" ] || continue
            name=$(basename "$bf" .block)
            existing=$(extract_method_block "$ME_CONF" "$name" 2>/dev/null) || existing=""
            if [ -z "$existing" ]; then
                echo "[OK] метод '$name' — отсутствует локально (будет добавлен)" >&2
                continue
            fi
            incoming=$(cat "$bf")
            if [ "$incoming" = "$existing" ]; then
                echo "[OK] метод '$name' — идентичен" >&2
            else
                echo "[DIFF] метод '$name' — конфликт:" >&2
                tmpa=$(mktemp "/tmp/me_da_XXXXXX")
                tmpb=$(mktemp "/tmp/me_db_XXXXXX")
                printf '%s\n' "$existing" > "$tmpa"
                printf '%s\n' "$incoming" > "$tmpb"
                diff -u "$tmpa" "$tmpb" | colorize_diff | sed 's/^/  /' >&2
                rm -f "$tmpa" "$tmpb"
            fi
        done
    fi

    diff_files "$tmpdir" "lib" "$ME_LIB"
    diff_files "$tmpdir" "conf" "$ME_DIR"
    diff_files "$tmpdir" "root" "$ME_DIR"
    diff_files "$tmpdir" "confhome" "$HOME/.config/me"

    echo "[me] DIFF-анализ завершён. Изменения не применялись." >&2
    return 0
}

cmd_share_all() {
    local outname="${1:-}"
    local tmpdir
    tmpdir=$(mktemp -d "/tmp/me_pkg_all_XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN

    local names
    names=$(awk '/^#@method:/ {print $2}' "$ME_CONF" 2>/dev/null | sort -u)
    [ -z "$names" ] && { echo "[me] Нет методов в $ME_CONF" >&2; return 1; }

    local count=0 name
    : > "$tmpdir/method.block"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if extract_method_block "$ME_CONF" "$name" >> "$tmpdir/method.block" 2>/dev/null; then
            count=$((count + 1))
        else
            echo "[me] Ошибка извлечения метода '$name' — пропуск" >&2
        fi
    done <<< "$names"

    echo "[me] Методов упаковано: $count" >&2

    local all_deps=""
    local deps
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        deps=$(find_method_deps "$name") || true
        [ -n "$deps" ] && all_deps="$all_deps"$'\n'"$deps"
    done <<< "$names"

    local dep rel dn
    echo "$all_deps" | grep -v '^[[:space:]]*$' | sort -u | while IFS= read -r dep; do
        [ -f "$dep" ] || continue
        if [[ "$dep" == "$CONF_DIR/"* ]]; then
            [ "$(basename "$dep")" = "me.conf" ] && continue
            mkdir -p "$tmpdir/confhome"
            cp "$dep" "$tmpdir/confhome/"
            echo "  - $(basename "$dep") → confhome/ (конфиг ~/.config/me)" >&2
            continue
        fi
        rel=$(echo "$dep" | sed "s|$ME_DIR/||")
        dn=$(dirname "$rel")
        if [ "$dn" = "me_lib" ]; then
            subrel=$(echo "$rel" | sed "s|^me_lib/||")
            mkdir -p "$tmpdir/lib/$(dirname "$subrel")"
            cp "$dep" "$tmpdir/lib/$subrel"
            echo "  - $rel → lib/$subrel" >&2
        elif [ "$dn" = "." ] && [[ "$rel" == *.conf ]]; then
            mkdir -p "$tmpdir/conf"
            cp "$dep" "$tmpdir/conf/"
            echo "  - $rel → conf/" >&2
        elif [ "$dn" = "." ]; then
            mkdir -p "$tmpdir/root"
            cp "$dep" "$tmpdir/root/"
            echo "  - $rel → root/" >&2
        else
            mkdir -p "$tmpdir/$dn"
            cp "$dep" "$tmpdir/$dn/"
            echo "  - $rel" >&2
        fi
    done

    # Сопутствующие скрипты из me_lib, не упомянутые в me.conf — в архив без регистрации
    local referenced
    referenced=$(echo "$all_deps" | grep -v '^[[:space:]]*$' | sort -u)
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$f" in
            "$ME_LIB/"*)
                local subrel
                subrel="${f#"$ME_LIB"/}"
                [ -e "$tmpdir/lib/$subrel" ] && continue
                mkdir -p "$tmpdir/lib/$(dirname "$subrel")"
                cp "$f" "$tmpdir/lib/$subrel"
                echo "  - me_lib/$subrel → lib/$subrel (сопутствующий, без регистрации)" >&2
                ;;
        esac
    done < <(find "$ME_LIB" -type f 2>/dev/null)

    # Пользовательские конфиги из ~/.config/me/ (кроме me.conf) в confhome/ попадают
    # автоматически через find_method_deps — только реально используемые методом файлы.

    generate_batch_installer "$tmpdir"

    local import_dir="$ME_DIR/import"
    mkdir -p "$import_dir"
    local archive
    if [ -n "$outname" ]; then
        case "$outname" in
            */*) archive="$outname" ;;
            *)    archive="$import_dir/$outname" ;;
        esac
    else
        archive="$import_dir/me_all.tar.gz"
    fi
    tar -czf "$archive" -C "$tmpdir" . 2>/dev/null
    echo "[me] Batch-пакет: $archive" >&2
    printf '%s\n' "$archive"
}

generate_batch_installer() {
    local tmpdir="$1"
    cat > "$tmpdir/install.sh" << 'BATSEOF'
#!/usr/bin/env bash
set -e

ME_CONF="${HOME}/.config/me/me.conf"
ME_LIB="${HOME}/.local/bin/me/me_lib"
ME_DIR="${HOME}/.local/bin/me"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

FORCE=0
[ "${1:-}" = "-f" ] && FORCE=1

BLOCK_FILE="$SELF_DIR/method.block"
[ -f "$BLOCK_FILE" ] || { echo "[me] method.block не найден" >&2; exit 1; }

bash -n "$BLOCK_FILE" 2>/dev/null || {
    echo "[me] Ошибка синтаксиса в method.block" >&2
    exit 1
}

BLOCKS_DIR=$(mktemp -d "/tmp/me_batch_install_XXXXXX")
trap 'rm -rf "$BLOCKS_DIR"' RETURN EXIT

current=""
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^#@method:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
        current="${BASH_REMATCH[1]}"
        : > "$BLOCKS_DIR/$current.block"
    fi
    if [ -n "$current" ]; then
        printf '%s\n' "$line" >> "$BLOCKS_DIR/$current.block"
    fi
done < "$BLOCK_FILE"

apply_block() {
    local conf="$1" name="$2" blockfile="$3"
    local tmp
    tmp=$(mktemp "/tmp/me_apply_XXXXXX")
    awk -v name="$name" '
        /^#@method:[ \t]*/ {
            if ($2 == name) { skip = 1; next }
            skip = 0
        }
        !skip { print }
    ' "$conf" > "$tmp"
    printf '\n' >> "$tmp"
    cat "$blockfile" >> "$tmp"
    mv "$tmp" "$conf"
}

OK_T=0; SKIP_T=0
mkdir -p "$(dirname "$ME_CONF")"
[ -f "$ME_CONF" ] || : > "$ME_CONF"
TMP_CONF=$(mktemp "/tmp/me_batch_conf_XXXXXX.conf")
cp "$ME_CONF" "$TMP_CONF"

for bf in "$BLOCKS_DIR"/*.block; do
    [ -f "$bf" ] || continue
    name=$(basename "$bf" .block)
    if grep -q "^#@method:[[:space:]]*${name}[[:space:]]*\$" "$TMP_CONF" 2>/dev/null; then
        if [ "$FORCE" = 1 ]; then
            apply_block "$TMP_CONF" "$name" "$bf"
            echo "[OK] метод '$name' — заменён" >&2
            OK_T=$((OK_T + 1))
        else
            echo "[SKIP] метод '$name' — уже существует" >&2
            SKIP_T=$((SKIP_T + 1))
        fi
    else
        apply_block "$TMP_CONF" "$name" "$bf"
        echo "[OK] метод '$name' — добавлен" >&2
        OK_T=$((OK_T + 1))
    fi
done

bash -n "$TMP_CONF" 2>/dev/null || {
    echo "[me] Ошибка: конфиг после установки содержит ошибки" >&2
    rm -f "$TMP_CONF"
    exit 1
}

install_files() {
    local srcdir="$1" dstdir="$2" label="$3"
    [ -d "$srcdir" ] || return 0
    mkdir -p "$dstdir"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        rel="${f#"$srcdir"/}"
        target="$dstdir/$rel"
        mkdir -p "$(dirname "$target")"
        if [ -e "$target" ] && [ "$FORCE" = 0 ]; then
            echo "[SKIP] $label/$rel — уже существует" >&2
            SKIP_T=$((SKIP_T + 1))
            continue
        fi
        cp "$f" "$target"
        chmod +x "$target" 2>/dev/null || true
        echo "[OK] $label/$rel" >&2
        OK_T=$((OK_T + 1))
    done < <(find "$srcdir" -type f 2>/dev/null)
}

install_files "$SELF_DIR/lib" "$ME_LIB" lib
install_files "$SELF_DIR/conf" "$ME_DIR" conf
install_files "$SELF_DIR/root" "$ME_DIR" root
install_files "$SELF_DIR/confhome" "$HOME/.config/me" confhome

[ -s "$ME_CONF" ] && cp "$ME_CONF" "$ME_CONF.bak.$(date +%s)"
cp "$TMP_CONF" "$ME_CONF"
rm -f "$TMP_CONF"
echo "[me] Установка завершена: [OK] $OK_T, [SKIP] $SKIP_T" >&2
exit 0
BATSEOF
    chmod +x "$tmpdir/install.sh"
}

cmd_share_route() {
    local mode="$1"
    if [ "$mode" = "-all" ]; then
        shift
        cmd_share_all "$@"
    else
        cmd_share_package "$mode"
    fi
}

case "${1:-}" in
    share|s)
        shift
        cmd_share_route "$@"
        ;;
    import|i)
        shift
        cmd_import "$@"
        ;;
    *)
        echo "Использование:" >&2
        echo "  me share <method>                 — собрать пакет в import/<method>.tar.gz" >&2
        echo "  me share -all [имя.tar.gz]        — собрать batch-пакет всех методов" >&2
        echo "  me import <method|file>        — импортировать метод" >&2
        echo "  me import -f <архив|method>       — импорт без вопросов (force)" >&2
        echo "  me import -all [-f] [<архив>]     — batch-импорт (архив необязателен: me_all.tar.gz)" >&2
        echo "  me import -diff [<архив>]         — dry-run сравнение (архив необязателен)" >&2
        exit 1
        ;;
esac
