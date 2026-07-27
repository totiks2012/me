#!/usr/bin/env bash
# del.sh — Удаление/восстановление методов me (пулл)

ME_LIB="$HOME/.local/bin/me/me_lib"
CONF="$HOME/.config/me/me.conf"
TRASH="$ME_LIB/tr_me"

mkdir -p "$TRASH"

conf_block() {
    awk -v n="$1" -v m="$2" '
    BEGIN{p=0;d=0}
    $0~"^#@method:[ \t]*" n "[ \t]*$"{p=1;if(m=="x")print;next}
    p&&$0~"^me_method_" n "\\(\\).*"{d=1;if(m=="x")print;next}
    p{if(d>0){for(i=1;i<=length;i++){c=substr($0,i,1);if(c=="{")d++;if(c=="}")d--};if(d<=0)p=0};if(m=="x")print;next}
    m=="r"{print}
    ' "$CONF"
}

find_script() {
    local body
    body=$(awk -v f="me_method_$1" '
        $0~"^" f "\\(\\).*"{flag=1;depth=1;next}
        flag{for(i=1;i<=length;i++){c=substr($0,i,1);if(c=="{")depth++;if(c=="}")depth--};if(depth>0)print;else flag=0}
    ' "$CONF")
    [ -z "$body" ] && return 1
    local p
    p=$(printf '%s\n' "$body" | grep -oP '\$HOME/\.local/bin/me/me_lib/[^"'"'"' )]+' | head -1)
    [ -z "$p" ] && p=$(printf '%s\n' "$body" | grep -oP 'script_path="([^"]+me_lib[^"]+)"' | sed 's/script_path="//;s/"$//')
    [ -z "$p" ] && return 1
    p="${p/#\$HOME/$HOME}"
    printf '%s' "$p"
}

method_list() {
    awk '
    BEGIN{m="";d="";e=""}
    /^#@method:[ \t]*/{if(m!="")print m"\t"d"\t"e;m="me "$2;d="";e="";next}
    /^#@description:[ \t]*/{sub(/^#@description:[ \t]*/,"");d=$0;next}
    /^#@example:[ \t]*/{sub(/^#@example:[ \t]*/,"");e=$0;next}
    /^me_method_.*\(\)/{if(m!="")print m"\t"d"\t"e;m="";next}
    END{if(m!="")print m"\t"d"\t"e}
    ' "$CONF"
}

# ═══════════════ RESTORE ═══════════════
restore() {
    dirs=$(find "$TRASH" -mindepth 1 -maxdepth 1 -type d | sort)
    [ -z "$dirs" ] && { notify-send -i dialog-error -t 1500 "me del" "Корзина пуста" 2>/dev/null || true; exit 0; }

    list=""
    for d in $dirs; do
        n=$(basename "$d")
        [ ! -f "$d/config.block" ] && continue
        desc=$(grep -m1 '#@description:' "$d/config.block" | sed 's/#@description: *//')
        [ -z "$desc" ] && desc="(нет описания)"
        list="$list$n"$'\t'"$desc"$'\n'
    done
    [ -z "$list" ] && { notify-send -i dialog-error -t 1500 "me del" "Корзина пуста" 2>/dev/null || true; exit 0; }

    chosen=$(printf '%b' "$list" | fzf --reverse \
        --header='Восстановить метод из корзины' \
        --delimiter=$'\t' --with-nth=1 \
        --preview='printf "\033[1;32m%s\033[0m\n" {2}' \
        --preview-window='right:60%:wrap' \
        --prompt='Восстановить > ' 2>/dev/null) || exit 0

    name="${chosen%%$'\t'*}"
    dir="$TRASH/$name"

    for sf in "$dir"/*; do
        [ -f "$sf" ] || continue
        b=$(basename "$sf"); [ "$b" = "config.block" ] && continue
        cp "$sf" "$ME_LIB/$b" && chmod +x "$ME_LIB/$b"
    done

    if [ -f "$dir/config.block" ] && ! grep -qs "^#@method:[ \t]*$name[ \t]*\$" "$CONF" 2>/dev/null; then
        printf '\n' >> "$CONF"; cat "$dir/config.block" >> "$CONF"; printf '\n' >> "$CONF"
    fi

    rm -rf "$dir"
    notify-send -i user-trash-full -t 2000 "me del" "Метод '$name' восстановлен" 2>/dev/null || true
    exit 0
}

# ═══════════════ DELETE ═══════════════
delete() {
    list=$(method_list) || exit 1
    [ -z "$list" ] && { notify-send -i dialog-error -t 1500 "me del" "Нет методов" 2>/dev/null || true; exit 1; }

    chosen=$(printf '%s\n' "$list" | fzf --reverse --multi \
        --header='Выберите метод для удаления в корзину' \
        --delimiter=$'\t' --with-nth=1 \
        --preview='printf "\033[1;32m%s\033[0m\n\033[0;36mПример:\033[0m %s\n" {2} {3}' \
        --preview-window='right:60%:wrap' \
        --prompt='Удалить > ' 2>/dev/null) || exit 0
    [ -z "$chosen" ] && exit 0

    IFS=$'\n'
    for entry in $chosen; do
        name="${entry#me }"; name="${name%%$'\t'*}"
        [ -z "$name" ] && continue
        dir="$TRASH/$name"
        mkdir -p "$dir"

        block=$(conf_block "$name" x)
        [ -n "$block" ] && printf '%s\n' "$block" > "$dir/config.block"

        tmp=$(mktemp /dev/shm/me_del_XXXXXX)
        conf_block "$name" r > "$tmp" 2>/dev/null
        if [ $? -eq 0 ] && [ -s "$tmp" ]; then
            mv "$tmp" "$CONF"
        else
            rm -f "$tmp"; rm -rf "$dir"
            echo "[del] Ошибка: $name" >&2
            continue
        fi

        sp=$(find_script "$name") && [ -f "$sp" ] && mv "$sp" "$dir/"
    done
    notify-send -i user-trash-full -t 2000 "me del" "Метод удалён в корзину" 2>/dev/null || true
    exit 0
}

# ═══════════════ MAIN MENU ═══════════════
case "${1:-}" in
    -r|--restore) restore ;;
    -d|--delete)  delete  ;;
esac

if command -v fzf &>/dev/null; then
    action=$(printf 'Удалить метод в корзину\nВосстановить метод из корзины' | fzf --reverse \
        --header='me del: выберите действие' \
        --prompt='Действие > ' 2>/dev/null) || exit 0
    case "$action" in
        *Удалить*)   delete  ;;
        *Восстановить*) restore ;;
    esac
else
    echo "me del — управление методами"
    echo "1. Удалить метод в корзину"
    echo "2. Восстановить метод из корзины"
    echo -n "Выберите [1-2]: "
    read -r c
    case "$c" in
        1) delete  ;;
        2) restore ;;
    esac
fi
