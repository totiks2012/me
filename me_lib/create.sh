#!/usr/bin/env bash
#true_method
# me create — интерактивное создание метода в me.conf (архитектура без eval).
# Спрашивает имя, описание, путь к бинарнику/скрипту — генерирует лаунчер в
# me_lib/<имя>.sh и мета-блок (#@method/#@description/#@example/#@script) в me.conf.

CONF_FILE="$HOME/.config/me/me.conf"
ME_BASE="$HOME/.local/bin/me"
ME_LIB="$ME_BASE/me_lib"

name=""
desc=""
example=""
target=""
args_mode=""

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
echo "Путь к бинарнику или скрипту, который будет запускать метод:"
echo "(примеры: /usr/bin/playerctl play 2>/dev/null || true"
echo "          \$HOME/.local/bin/my_script.sh"
echo "          notify-send -i info \"Заголовок\" \"Текст\")"
echo
while true; do
    read -p "> " target
    [ -n "$target" ] && break
    echo "Команда не может быть пустым." >&2
done

echo
echo "Создаю лаунчер из команды: '$target'"
echo
read -p "Пример (Enter = 'me $name'): " example
[ -z "$example" ] && example="me $name"

# --- Лаунчер-скрипт: bash -n до записи на диск ---
mkdir -p "$ME_LIB"
launcher="$ME_LIB/${name}.sh"
tmp_launcher=$(mktemp /tmp/me_create_XXXXXX.sh)
{
    printf '#!/usr/bin/env bash\n'
    printf '#true_method\n'
    printf '# Метод: %s\n' "$name"
    printf '# Описание: %s\n' "$desc"
    printf '# Создан: %s\n' "$(date '+%d-%m-%Y %H:%M')"
    printf '\n'
    printf 'exec %s "$@"\n' "$target"
} > "$tmp_launcher"

if ! bash -n "$tmp_launcher" 2>/dev/null; then
    echo "[me] Ошибка: синтаксическая ошибка в сгенерированном лаунчере." >&2
    bash -n "$tmp_launcher" 2>&1 | sed 's/^/  /' >&2
    rm -f "$tmp_launcher"
    exit 1
fi

# --- Мета-блок в me.conf (#@script: указывает на лаунчер) ---
block="#@method: $name
#@description: $desc
#@example: $example
#@script: me_lib/${name}.sh"

echo
echo "--- Будет добавлено в $CONF_FILE ---"
echo "$block"
echo "------------------------------------"
echo "Лаунчер: $launcher"
echo

read -p $'\nДобавить? (Y/n): ' confirm
case "$confirm" in
    n|N|no|NO) echo "Отменено."; rm -f "$tmp_launcher"; exit 0 ;;
esac

# --- Запись: лаунчер на место, мета-блок в конец me.conf ---
install -m 755 "$tmp_launcher" "$launcher"
rm -f "$tmp_launcher"

mkdir -p "$(dirname "$CONF_FILE")"
if [ -s "$CONF_FILE" ] && [ "$(tail -c 1 "$CONF_FILE" | wc -l)" -eq 0 ]; then
    echo "" >> "$CONF_FILE"
fi
echo "" >> "$CONF_FILE"
echo "$block" >> "$CONF_FILE"

echo "Метод '$name' создан."
echo "Лаунчер:   $launcher"
echo "Конфиг:    $CONF_FILE (+ блок #@script:)"
echo "Запусти:   me $name"
