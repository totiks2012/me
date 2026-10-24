#!/usr/bin/env bash
# me make — идемпотентный сборщик реестра me.conf.
# Сканирует me_lib/*.sh; файл с #true_method второй строкой — это тело метода.
# Имя метода = имя файла без .sh. Отсутствующий блок #@method: дописывается в me.conf.
# Существующие блоки не трогаются (не синхронизатор, только добавление).

ME_BASE="$HOME/.local/bin/me"
ME_LIB="$ME_BASE/me_lib"
CONF="$HOME/.config/me/me.conf"

report() { printf 'добавлено %d, уже зарегистрировано %d, проигнорировано %d\n' "$added" "$known" "$ignored"; }

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
        printf 'Описание для метода %s: ' "$name"
        IFS= read -r line
        [ -n "$line" ] && desc="$line"
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