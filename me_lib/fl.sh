#!/usr/bin/env bash
#true_method
# fl.sh – Контекстный поиск и fallback-запуск (дополнение к me la, не второй лаунчер)
#   fl -con 'контекст' [путь] — поиск по содержимому с переходом к строке
#   fl -cat 'категория'       — приложения категории из общего кэша la (apps_cache.txt)
#   fl -app 'имя'             — запуск: кэш la → fallback на locate по PATH
#
# Общий ресурс с la.sh: apps_cache.txt (Name|Exec|desktop_path). Своего кэша нет.

command_exists() { command -v "$1" >/dev/null 2>&1; }

LA_BASE="${FL_CACHE_DIR:-/root/.local/bin/arcturus_cli}"
CACHE="$LA_BASE/apps_cache.txt"
LA_SH="$LA_BASE/la.sh"

usage() {
    echo "Использование:"
    echo "  fl -con 'контекст' [путь] — поиск по содержимому, Enter — micro на строке"
    echo "  fl -cat 'категория'       — приложения категории (Editor, Development…)"
    echo "  fl -app 'имя'             — запуск: меню (кэш la) → PATH (locate)"
    exit 1
}

# Запуск как в la.sh: setsid -f sh -c "$exec"
launch_exec() {
    setsid -f sh -c "$1" >/dev/null 2>&1 </dev/null
}

# Гарантировать наличие кэша: если нет — пересобрать через la.sh, иначе подсказка
ensure_cache() {
    [ -s "$CACHE" ] && return 0
    [ -x "$LA_SH" ] && "$LA_SH" --update-cache >/dev/null 2>&1
    [ -s "$CACHE" ]
}

# Словарь алиасов: запрос -> список токенов Categories=. Файл ~/.config/me/fl_cat_dict
cat_tokens() {
    local q="$1" alias tokens
    DICT="${FL_CAT_DICT:-$HOME/.config/me/fl_cat_dict}"
    [ -f "$DICT" ] || { printf '%s\n' "$q"; return; }
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        alias="${line%%|*}"
        tokens="${line#*|}"
        [ -n "$alias" ] && [ -n "$tokens" ] || continue
        if [ "${alias,,}" = "${q,,}" ]; then
            printf '%s\n' "$tokens" | tr ';' '\n'
            return 0
        fi
    done <"$DICT"
    # fallback: точное совпадение токена
    printf '%s\n' "$q"
}

# Строки кэша = Name|Exec|path
cache_rows() {
    local q="$1" line name rest exec path
    [ -s "$CACHE" ] || return 1
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line%%|*}"
        rest="${line#*|}"
        exec="${rest%%|*}"
        path="${rest#*|}"
        [ -n "$path" ] || continue
        case "${name,,}|${exec,,}" in
            *"${q,,}"*) printf '%s\t%s\t%s\n' "$name" "$path" "$exec" ;;
        esac
    done <"$CACHE"
}

# Первый исполняемый файл в PATH-каталогах, basename содержит name (case-insens)
find_exec() {
    local name="$1" f d out="" hits=""
    if command_exists locate; then
        hits=$(locate -i -b -e -- "$name" 2>/dev/null)
        if [ -n "$hits" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                for d in "${pathdirs[@]}"; do
                    [ -n "$d" ] && [ -d "$d" ] || continue
                    case "$f" in
                        "$d"/*) printf '%s\n' "$f"; return 0 ;;
                    esac
                done
            done <<<"$hits"
        fi
    fi
    for d in "${pathdirs[@]}"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        f=$(find "$d" -maxdepth 1 -type f -iname "*$name*" -executable 2>/dev/null | head -1)
        [ -n "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    return 1
}

IFS=':' read -r -a pathdirs <<<"$PATH"

case "$1" in
    -con)
        shift
        ctx="$1"
        [ -z "$ctx" ] && usage
        shift

        path="${1:-/}"
        [ -d "$path" ] || path="/"

        command_exists fzf || { echo "fl: нужен fzf" >&2; exit 1; }
        if command_exists micro; then
            editor=micro
        elif command_exists geany; then
            editor=geany
        else
            echo "fl: ни micro, ни geany не установлены" >&2
            exit 1
        fi

        # Экранирование одиночных кавычек для встраивания в preview/bind
        esc=$(printf '%s' "$ctx" | sed "s/'/'\\\\''/g")

        # Ограничение области по умолчанию: только реальная ФС, без чужих разделов и чужих пользователей
        rg_args=(-l -i)
        if [ "$path" = "/" ]; then
            rg_args+=(--one-file-system)
            for g in 'mnt/**' 'media/**' 'proc/**' 'sys/**' 'dev/**' 'run/**' 'tmp/**'; do
                rg_args+=(-g "!**/$g")
            done
            for h in /home/*; do
                [ -d "$h" ] && [ "$h" != "$HOME" ] && rg_args+=(-g "!**/${h#/}/**")
            done
        fi
        rg_args+=(-- "$ctx" "$path")

        rg "${rg_args[@]}" 2>/dev/null | fzf --reverse \
            --header="Контекст: '$ctx' | Путь: $path | Enter — $editor на строке" \
            --preview="rg --color=always -n -C 5 -i '$esc' {} 2>/dev/null" \
            --preview-window='right:60%:wrap' \
            --bind="enter:execute($editor +\$(rg -n -i '$esc' {} 2>/dev/null | head -1 | cut -d: -f1) {})"
        ;;

    -cat)
        shift
        cat="$1"
        [ -z "$cat" ] && usage
        shift
        catl="${cat,,}"

        ensure_cache || { echo "fl: кэш приложений не найден — сначала запусти 'me la' (или FL_CACHE_DIR=$LA_BASE)" >&2; exit 1; }

        # токены из словаря (алиас -> список); fallback на точное совпадение
        toks=$(cat_tokens "$cat" | paste -sd' ' -)
        [ -n "$toks" ] || toks="$catl"

        rows=""
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            name="${line%%|*}"
            rest="${line#*|}"
            exec="${rest%%|*}"
            path="${rest#*|}"
            [ -n "$path" ] || continue
            if awk -F= -v q="$toks" '
                BEGIN { n=split(tolower(q), qt, / /); for (i=1;i<=n;i++) want[qt[i]]=1 }
                /^Categories=/ {
                    n=split(tolower($2), a, ";")
                    for (i=1; i<=n; i++) { gsub(/[ \t]/, "", a[i]); if (want[a[i]]) ok=1 }
                }
                END { exit !ok }
            ' "$path" 2>/dev/null; then
                rows+="$name"$'\t'"$path"$'\t'"$exec"$'\n'
            fi
        done <"$CACHE"

        [ -z "$rows" ] && { echo "fl: категория '$cat' не найдена" >&2; exit 1; }

        selected="$(printf '%s' "$rows" | fzf --reverse \
            --header="Категория: '$cat' | Enter — запустить | Esc — выход" \
            --delimiter=$'\t' --with-nth=1 \
            --preview="grep -E '^(Categories|Comment)=' {2}" \
            --preview-window='right:50%:wrap')"
        [ -z "$selected" ] && exit 0

        launch_exec "$(printf '%s' "$selected" | sed $'s/^[^\\t]*\\t[^\\t]*\\t//')"
        ;;

    -app)
        shift
        name="$1"
        [ -z "$name" ] && usage
        shift

        rows=""
        if ensure_cache; then
            rows="$(cache_rows "$name")"
        fi

        if [ -n "$rows" ]; then
            selected="$(printf '%s' "$rows" | fzf --reverse \
                --header="Приложения '${name}' | Enter — запустить | Esc — выход" \
                --delimiter=$'\t' --with-nth=1 \
                --preview="sed -n '1,20p' {2}" \
                --preview-window='right:60%:wrap')"
            [ -z "$selected" ] && exit 0
            launch_exec "$(printf '%s' "$selected" | sed $'s/^[^\\t]*\\t[^\\t]*\\t//')"
        else
            bin=$(find_exec "$name")
            if [ -n "$bin" ]; then
                launch_exec "$bin"
            else
                echo "fl: '$name' не найден ни в меню, ни в PATH" >&2
                exit 1
            fi
        fi
        ;;

    -h|--help) usage ;;

    *) usage ;;
esac