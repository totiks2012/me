#!/usr/bin/env bash
# me make — идемпотентный сборщик реестра me.conf.
# Сканирует me_lib/*.sh; файл с #true_method второй строкой — это тело метода.
# Имя метода = имя файла без .sh. Отсутствующий блок #@method: дописывается в me.conf.
# Существующие блоки не трогаются (не синхронизатор, только добавление).
# me make -r — fzf-выбор метода, инлайн-правка #@description: только выбранного.

ME_BASE="$HOME/.local/bin/me"
ME_LIB="$ME_BASE/me_lib"
CONF="$HOME/.config/me/me.conf"

report() { printf 'добавлено %d, уже зарегистрировано %d, проигнорировано %d\n' "$added" "$known" "$ignored"; }

# ═══════════════ me make -r: инлайн-правка категории/описания выбранного метода ═══════════════
cmd_edit_desc() {
    command -v fzf >/dev/null 2>&1 || { echo "me make -r: требуется fzf" >&2; exit 1; }
    [ -f "$CONF" ] || { echo "me make -r: файл me.conf не найден: $CONF" >&2; exit 1; }

    list=$(awk '
    BEGIN{m="";d=""}
    /^#@method:[ \t]*/{if(m!="")print m"\t"d;m=$2;d="";next}
    /^#@description:[ \t]*/{sub(/^#@description:[ \t]*/,"");d=$0;next}
    /^me_method_.*\(\)/{if(m!="")print m"\t"d;m="";next}
    END{if(m!="")print m"\t"d}
    ' "$CONF")
    [ -z "$list" ] && { echo "me make -r: в me.conf нет методов" >&2; exit 1; }

    chosen=$(printf '%s\n' "$list" | fzf --reverse \
        --header='me make -r: выберите метод для правки категории/описания' \
        --delimiter=$'\t' --with-nth=1 \
        --preview='printf "\033[1;32m%s\033[0m\n" {2}' \
        --preview-window='right:60%:wrap' \
        --prompt='Правка > ' 2>/dev/null) || exit 0
    [ -z "$chosen" ] && exit 0

    name="${chosen%%$'\t'*}"
    current="${chosen#*$'\t'}"
    [ -z "$name" ] && exit 0

    # разбор текущего описания на [cat: X] + текст
    if [[ "$current" =~ ^\[cat:[[:space:]]+([^]]*)\][[:space:]]*(.*)$ ]]; then
        cat_current="${BASH_REMATCH[1]}"
        desc_current="${BASH_REMATCH[2]}"
    else
        cat_current=""
        desc_current="$current"
    fi

    printf 'Метод: %s\n' "$name"
    printf 'Категория сейчас: %s\n' "${cat_current:-(нет)}"
    printf 'Описание сейчас: %s\n' "${desc_current:-(пусто)}"
    printf 'Новая категория (Enter — оставить, "-" — убрать): '
    IFS= read -r newcat
    printf 'Новое описание (Enter — оставить): '
    IFS= read -r newdesc

    if [ -n "$newdesc" ]; then
        final_desc="$newdesc"
    else
        final_desc="$desc_current"
    fi

    if [ "$newcat" = "-" ]; then
        new_desc="$final_desc"
    elif [ -n "$newcat" ]; then
        new_desc="[cat: $newcat]${final_desc:+ $final_desc}"
    elif [ -n "$cat_current" ]; then
        new_desc="[cat: $cat_current]${final_desc:+ $final_desc}"
    else
        new_desc="$final_desc"
    fi

    [ "$new_desc" = "$current" ] && { echo "me make -r: без изменений"; exit 0; }

    tmp=$(mktemp "$(dirname "$CONF")/.me_make_r_XXXXXX") || exit 1
    if awk -v name="$name" -v new="$new_desc" '
        $0 ~ "^#@method:[ \t]*" name "[ \t]*$" { f=1; print; next }
        f && $0 ~ "^#@method:" { f=0 }
        f && /^#@description:/ { print "#@description: " new; f=0; next }
        { print }
    ' "$CONF" > "$tmp"; then
        if grep -q "^#@method:[ \t]*$name[ \t]*\$" "$tmp"; then
            mv "$tmp" "$CONF"
            echo "me make -r: категория/описание метода '$name' обновлено"
        else
            rm -f "$tmp"
            echo "me make -r: метод '$name' не найден в me.conf" >&2
            exit 1
        fi
    else
        rm -f "$tmp"
        echo "me make -r: ошибка записи" >&2
        exit 1
    fi
    exit 0
}

if [ "${1:-}" = "-r" ]; then
    cmd_edit_desc
fi

added=0
known=0
ignored=0

if [ ! -d "$ME_LIB" ]; then
    echo "me make: каталог me_lib не найден: $ME_LIB" >&2
    exit 1
fi
if [ ! -f "$CONF" ]; then
    echo "me make: файл me.conf не найден: $CONF" >&2
    exit 1
fi

shopt -s nullglob
for f in "$ME_LIB"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    name="${name%.sh}"

    line2="$(sed -n '2p' "$f")"
    if [ "$line2" != "#true_method" ]; then
        ignored=$((ignored + 1))
        continue
    fi

    if ! printf '%s' "$name" | grep -qE '^[a-z_][a-z0-9_]*$'; then
        echo "me make: пропущено (недопустимое имя): $name" >&2
        ignored=$((ignored + 1))
        continue
    fi

    if grep -qE "^#@method: $name\$" "$CONF" || grep -qE "^#@script: me_lib/$name\.sh\$" "$CONF"; then
        known=$((known + 1))
        continue
    fi

    desc="метод $name"
    example="me $name"
    if [ -t 0 ] && [ -t 1 ]; then
        cat=""
        printf 'Категория для метода %s (Enter — без категории): ' "$name"
        IFS= read -r line
        [ -n "$line" ] && cat="$line"
        printf 'Описание для метода %s: ' "$name"
        IFS= read -r line
        if [ -n "$line" ]; then
            if [ -n "$cat" ]; then
                desc="[cat: $cat] $line"
            else
                desc="$line"
            fi
        fi
        printf 'Пример (Enter = "me %s"): ' "$name"
        IFS= read -r line
        [ -n "$line" ] && example="$line"
    fi

    block="#@method: $name
#@description: $desc
#@example: $example
#@script: me_lib/$name.sh"

    [ -s "$CONF" ] && [ "$(tail -c 1 "$CONF" | wc -l)" -eq 0 ] && printf '\n' >> "$CONF"
    printf '\n%s\n' "$block" >> "$CONF"
    added=$((added + 1))
done

report
[ "$added" -gt 0 ] && exit 0 || exit 0