#!/usr/bin/env bash

ME_CONF="${HOME}/.config/me/me.conf"
ME_LIB="${HOME}/.local/bin/me/me_lib"
ME_DIR="${HOME}/.local/bin/me"

extract_method_block() {
    local conf="$1" name="$2"
    local state=0 depth=0 line

    while IFS= read -r line || [ -n "$line" ]; do
        case $state in
            0)
                if [[ "$line" =~ ^#@method:[[:space:]]*"$name"[[:space:]]*$ ]]; then
                    printf '%s\n' "$line"
                    state=1
                fi
                ;;
            1)
                printf '%s\n' "$line"
                if [[ "$line" =~ ^me_method_"$name"\(\)[[:space:]]*\{ ]]; then
                    depth=1
                    state=2
                fi
                ;;
            2)
                local t="$line"
                while [[ "$t" =~ [\{\}] ]]; do
                    local c="${BASH_REMATCH[0]}"
                    [[ "$c" == "{" ]] && ((depth++))
                    [[ "$c" == "}" ]] && ((depth--))
                    t="${t#*"$c"}"
                done
                printf '%s\n' "$line"
                if (( depth <= 0 )); then
                    return 0
                fi
                ;;
        esac
    done < "$conf"

    return 1
}

find_refs_in() {
    local text="$1"
    echo "$text" | grep -oE '\$HOME/[^'\'\"']*me_lib/[a-zA-Z0-9_.-]+' 2>/dev/null | sed "s|\$HOME|$HOME|"
    echo "$text" | grep -oE '\$HOME/\.local/bin/me/[a-zA-Z0-9_.-]+' 2>/dev/null | sed "s|\$HOME|$HOME|"
    echo "$text" | grep -oE "$HOME/[^'\'\"']*me_lib/[a-zA-Z0-9_.-]+" 2>/dev/null
    echo "$text" | grep -oE "$HOME/\.local/bin/me/[a-zA-Z0-9_.-]+" 2>/dev/null
}

find_method_deps() {
    local name="$1"
    local body seen

    body=$(extract_method_block "$ME_CONF" "$name") 2>/dev/null || return 1

    local -a deps=()
    local -a queue=()
    local item

    while IFS= read -r item; do
        [ -f "$item" ] && queue+=("$item")
    done <<< "$(find_refs_in "$body" | sort -u)"

    seen=""
    while [ ${#queue[@]} -gt 0 ]; do
        item="${queue[0]}"
        queue=("${queue[@]:1}")

        echo "$seen" | grep -qF "$item" && continue
        seen="$seen"$'\n'"$item"
        deps+=("$item")

        local content
        content=$(cat "$item" 2>/dev/null) || continue
        while IFS= read -r ref; do
            [ -f "$ref" ] && echo "$seen" | grep -qF "$ref" || queue+=("$ref")
        done <<< "$(find_refs_in "$content" | sort -u)"
    done

    printf '%s\n' "${deps[@]}"
}

install_lib_script() {
    local name="$1" content="$2"
    local target="$ME_LIB/$name"
    if [ -f "$target" ]; then
        echo -n "[me] Скрипт '$name' уже существует. Заменить? [y/N] " >&2
        read -r answer
        if [[ ! "$answer" =~ ^[yY] ]]; then
            echo "[me]   $name — пропущен" >&2
            return
        fi
        echo "[me]   $name — заменён" >&2
    else
        echo "[me]   $name — добавлен" >&2
    fi
    printf '%s\n' "$content" > "$target"
    chmod +x "$target" 2>/dev/null || true
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

METHOD_BLOCK=$(cat "$SELF_DIR/method.block")
METHOD_NAME=$(echo "$METHOD_BLOCK" | grep -oP '^#@method:\s*\K\S+' | head -1)
[ -z "$METHOD_NAME" ] && { echo "[me] #@method: не найден" >&2; exit 1; }

echo "$METHOD_BLOCK" | bash -n /dev/stdin 2>/dev/null || {
    echo "[me] Ошибка синтаксиса метода" >&2
    exit 1
}

if grep -q "^#@method:[[:space:]]*${METHOD_NAME}[[:space:]]*\$" "$ME_CONF" 2>/dev/null; then
    echo -n "[me] Метод '${METHOD_NAME}' существует. Заменить? [y/N] " >&2
    read -r answer
    [[ "$answer" =~ ^[yY] ]] || { echo "[me] Отменено" >&2; exit 0; }
fi

TMP_CONF=$(mktemp "/tmp/me_install_XXXXXX.conf")
awk -v name="$METHOD_NAME" '
BEGIN { skip=0; depth=0 }
{
    if ($0 ~ "^#@method:[[:space:]]*" name "[[:space:]]*$") { skip=1; next }
    if (skip && $0 ~ "me_method_" name "\\(\\)") { depth=1; next }
    if (skip && depth > 0) {
        for (i=1; i<=length($0); i++) {
            c=substr($0,i,1)
            if (c=="{") depth++
            if (c=="}") depth--
        }
        if (depth <= 0) skip=0
        next
    }
    if (!skip) print
}
' "$ME_CONF" > "$TMP_CONF"

printf '\n%s\n' "$METHOD_BLOCK" >> "$TMP_CONF"

bash -n "$TMP_CONF" 2>/dev/null || {
    echo "[me] Ошибка: конфиг после установки содержит ошибки" >&2
    rm -f "$TMP_CONF"
    exit 1
}
cp "$TMP_CONF" "$ME_CONF"
rm -f "$TMP_CONF"
echo "[me] Метод '${METHOD_NAME}' — OK" >&2

if [ -d "$SELF_DIR/lib" ]; then
    mkdir -p "$ME_LIB"
    for f in "$SELF_DIR/lib/"*; do
        [ -f "$f" ] || continue
        bn=$(basename "$f")
        if [ -f "$ME_LIB/$bn" ]; then
            echo -n "[me] $bn существует. Заменить? [y/N] " >&2
            read -r answer
            if [[ ! "$answer" =~ ^[yY] ]]; then
                echo "[me]   $bn — пропущен" >&2
                continue
            fi
            echo "[me]   $bn — заменён" >&2
        else
            echo "[me]   $bn — добавлен" >&2
        fi
        cp "$f" "$ME_LIB/$bn"
        chmod +x "$ME_LIB/$bn"
    done
fi

if [ -d "$SELF_DIR/conf" ]; then
    for f in "$SELF_DIR/conf/"*; do
        [ -f "$f" ] || continue
        bn=$(basename "$f")
        if [ -f "$HOME/.local/bin/me/$bn" ]; then
            echo -n "[me] $bn существует. Заменить? [y/N] " >&2
            read -r answer
            if [[ ! "$answer" =~ ^[yY] ]]; then
                echo "[me]   $bn — пропущен" >&2
                continue
            fi
            echo "[me]   $bn — заменён" >&2
        else
            echo "[me]   $bn — conf" >&2
        fi
        cp "$f" "$HOME/.local/bin/me/"
    done
fi

if [ -d "$SELF_DIR/root" ]; then
    for f in "$SELF_DIR/root/"*; do
        [ -f "$f" ] || continue
        bn=$(basename "$f")
        if [ -f "$HOME/.local/bin/me/$bn" ]; then
            echo -n "[me] $bn существует. Заменить? [y/N] " >&2
            read -r answer
            if [[ ! "$answer" =~ ^[yY] ]]; then
                echo "[me]   $bn — пропущен" >&2
                continue
            fi
            echo "[me]   $bn — заменён" >&2
        else
            echo "[me]   $bn — root" >&2
        fi
        cp "$f" "$HOME/.local/bin/me/"
    done
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
    local start_line=0 end_line=0 state=0 depth=0 line_num=0 line

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        case $state in
            0)
                if [[ "$line" =~ ^#@method:[[:space:]]*"$name"[[:space:]]*$ ]]; then
                    start_line=$line_num
                    state=1
                fi
                ;;
            1)
                if [[ "$line" =~ ^me_method_"$name"\(\)[[:space:]]*\{ ]]; then
                    depth=1
                    state=2
                fi
                ;;
            2)
                local t="$line"
                while [[ "$t" =~ [\{\}] ]]; do
                    local c="${BASH_REMATCH[0]}"
                    [[ "$c" == "{" ]] && ((depth++))
                    [[ "$c" == "}" ]] && ((depth--))
                    t="${t#*"$c"}"
                done
                if (( depth <= 0 )); then
                    end_line=$line_num
                    break
                fi
                ;;
        esac
    done < "$conf"

    local tmp
    tmp=$(mktemp "/tmp/me_import_XXXXXX")
    trap 'rm -f "$tmp"' RETURN

    if [ "$start_line" -gt 0 ] && [ "$end_line" -gt 0 ]; then
        {
            head -n "$((start_line - 1))" "$conf"
            printf '%s\n' "$block"
            tail -n +"$((end_line + 1))" "$conf"
        } > "$tmp"
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
    local source="$1"

    if [ -z "$source" ]; then
        echo "[me] Укажи имя метода или путь к tar.gz: me import <method|file>" >&2
        echo "  me import gifx        — из ~/.local/bin/me/import/gifx.tar.gz" >&2
        echo "  me import ./pkg.tar.gz — из произвольного пути" >&2
        echo "  me import <url>       — из pastebin URL (текстовый бандл)" >&2
        return 1
    fi

    local archive=""

    if [[ "$source" =~ ^https?:// ]]; then
        cmd_import_url "$source"
        return $?
    fi

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

    if [ -f "$tmpdir/install.sh" ]; then
        bash "$tmpdir/install.sh"
        return $?
    fi

    [ -f "$tmpdir/method.block" ] && {
        local block
        block=$(cat "$tmpdir/method.block")
        local mname
        mname=$(echo "$block" | grep -oP '^#@method:\s*\K\S+' | head -1)
        [ -n "$mname" ] && import_method_block "$ME_CONF" "$mname" "$block" && {
            echo "[me] Метод '$mname' импортирован." >&2
            if [ -d "$tmpdir/lib" ]; then
                local count=0
                for f in "$tmpdir/lib/"*; do
                    [ -f "$f" ] || continue
                    install_lib_script "$(basename "$f")" "$(cat "$f")"
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

cmd_import_url() {
    local source="$1"
    local raw

    echo "[me] Скачиваю $source ..." >&2
    raw=$(curl -sfL "$source" 2>/dev/null) || {
        echo "[me] Ошибка загрузки $source" >&2
        return 1
    }

    [ -z "$raw" ] && { echo "[me] Пустой ответ" >&2; return 1; }

    local method_block libs_block
    if echo "$raw" | grep -q '^=== ME-LIB:'; then
        method_block=$(echo "$raw" | sed -n '1,/^=== ME-LIB:/p' | sed '$d')
        libs_block=$(echo "$raw" | sed -n '/^=== ME-LIB:/,$p')
    else
        method_block="$raw"
        libs_block=""
    fi

    method_block=$(echo "$method_block" | sed '/^#!/d')

    local method_name
    method_name=$(echo "$method_block" | grep -oP '^#@method:\s*\K\S+' | head -1)
    [ -z "$method_name" ] && { echo "[me] #@method: не найден" >&2; return 1; }

    if grep -q "^#@method:[[:space:]]*$method_name[[:space:]]*\$" "$ME_CONF" 2>/dev/null; then
        echo -n "[me] Метод '$method_name' уже существует. Заменить? [y/N] " >&2
        read -r answer
        if [[ ! "$answer" =~ ^[yY] ]]; then
            echo "[me] Отменено." >&2
            return 0
        fi
    fi

    import_method_block "$ME_CONF" "$method_name" "$method_block" || return 1
    echo "[me] Метод '$method_name' импортирован." >&2

    if [ -n "$libs_block" ]; then
        local count=0 lib_name="" lib_content=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^'=== ME-LIB: '([^ ]+)' ==='$ ]]; then
                if [ -n "$lib_name" ] && [ -n "$lib_content" ]; then
                    install_lib_script "$lib_name" "${lib_content%$'\n'}"
                    count=$((count + 1))
                fi
                lib_name="${BASH_REMATCH[1]}"
                lib_content=""
            elif [ -n "$lib_name" ]; then
                lib_content="${lib_content}${line}"$'\n'
            fi
        done <<< "$libs_block"
        if [ -n "$lib_name" ] && [ -n "$lib_content" ]; then
            install_lib_script "$lib_name" "${lib_content%$'\n'}"
            count=$((count + 1))
        fi
        [ "$count" -gt 0 ] && echo "[me] Скриптов импортировано: $count" >&2
    fi
}

case "${1:-}" in
    share|s)
        shift
        cmd_share_package "${1:-}"
        ;;
    import|i)
        shift
        cmd_import "${1:-}"
        ;;
    *)
        echo "Использование:" >&2
        echo "  me share <method>            — собрать пакет в import/<method>.tar.gz" >&2
        echo "  me import <method|file|url>  — импортировать метод" >&2
        exit 1
        ;;
esac
