#!/usr/bin/env bash
# me create — интерактивное создание метода в me.conf
# Спрашивает имя, описание, команду — генерирует me_method_*() с мета-тегами

CONF_FILE="$HOME/.config/me/me.conf"

name=""
desc=""
cmd=""
example=""

echo "=== Создание нового метода для me ==="
echo

while true; do
    read -p "Имя метода: " name
    name="${name// /_}"
    name=$(echo "$name" | tr 'A-Z' 'a-z')
    if [ -z "$name" ]; then
        echo "Имя не может быть пустым." >&2
        continue
    fi
    if ! echo "$name" | grep -qE '^[a-z_][a-z0-9_]*$'; then
        echo "Имя: только a-z, 0-9, _, начинается с буквы или _." >&2
        continue
    fi
    if grep -q "^#@method: $name" "$CONF_FILE" 2>/dev/null; then
        echo "Метод '$name' уже существует в $CONF_FILE" >&2
        continue
    fi
    break
done

echo
while true; do
    read -p "Описание: " desc
    [ -n "$desc" ] && break
    echo "Описание не может быть пустым." >&2
done

echo
echo "Введите команду — bash-код, который будет выполняться:"
echo "(примеры: playerctl play 2>/dev/null || true"
echo "          \$HOME/.local/bin/me/me_lib/my_script.sh \"\$@\""
echo "          notify-send -i info \"Заголовок\" \"Текст\")"
echo
while true; do
    read -p "> " cmd
    [ -n "$cmd" ] && break
    echo "Команда не может быть пустой." >&2
done

echo
read -p "Пример (Enter = 'me $name'): " example
[ -z "$example" ] && example="me $name"

block="#@method: $name
#@description: $desc
#@example: $example
me_method_${name}() {
    $cmd
}"

echo
echo "--- Будет добавлено в $CONF_FILE ---"
echo "$block"
echo "------------------------------------"

read -p $'\nДобавить? (Y/n): ' confirm
case "$confirm" in
    n|N|no|NO) echo "Отменено."; exit 0 ;;
esac

tmpfile=$(mktemp /tmp/me_create_XXXXXX.sh)
echo "$block" > "$tmpfile"
if ! bash -n "$tmpfile" 2>/dev/null; then
    echo "[me] Ошибка: синтаксическая ошибка в сгенерированном коде." >&2
    bash -n "$tmpfile" 2>&1 | sed 's/^/  /' >&2
    rm -f "$tmpfile"
    exit 1
fi
rm -f "$tmpfile"

if [ -s "$CONF_FILE" ] && [ "$(tail -c 1 "$CONF_FILE" | wc -l)" -eq 0 ]; then
    echo "" >> "$CONF_FILE"
fi
echo "" >> "$CONF_FILE"
echo "$block" >> "$CONF_FILE"

echo "Метод '$name' создан в $CONF_FILE."
echo "Запусти: me $name"
