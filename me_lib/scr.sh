
#!/usr/bin/env bash

# scr — screenshot
# ЛКМ: снимок окна
# ПКМ: задержка 5 секунд, затем выделение области
# зависимости : apt install maim slop xinput xdotool coreutils gawk
set -u

dir="$HOME/Pictures"
mkdir -p "$dir"

file="$dir/scr_$(date +'%Y-%m-%d_%H-%M-%S').png"

for cmd in maim slop xinput xdotool; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Не найдена команда: $cmd" >&2
        exit 1
    }
done

notify() {
    me say "От scr" "$1" dialog-information 3000 \
        2>/dev/null || true
}

# FIFO для чтения событий мыши
tmp=$(mktemp -d)
fifo="$tmp/mouse"
mkfifo "$fifo"

pid=""

cleanup() {
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}

trap cleanup EXIT
trap 'exit 0' INT TERM

# Запускаем мониторинг XInput2
stdbuf -oL xinput test-xi2 --root >"$fifo" 2>/dev/null &
pid=$!

button=""
waiting=0

# Открываем FIFO
exec 3<"$fifo"

# Читаем события до первого нажатия ЛКМ/ПКМ
while IFS= read -r line <&3; do
    if [[ "$line" == *"EVENT type 4 (ButtonPress)"* ]]; then
        waiting=1
        continue
    fi

    if (( waiting )) && [[ "$line" =~ detail:[[:space:]]*([0-9]+) ]]; then
        case "${BASH_REMATCH[1]}" in
            1|3)
                button="${BASH_REMATCH[1]}"
                break
                ;;
        esac
        waiting=0
    fi
done

exec 3<&-

# Останавливаем мониторинг
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=""

case "$button" in
    1)
        # Определяем окно под курсором
        win=$(xdotool getmouselocation --shell |
              sed -n 's/^WINDOW=//p')

        [[ "$win" =~ ^[0-9]+$ ]] || exit 0
        (( win > 0 )) || exit 0

        maim -i "$win" "$file" 2>/dev/null || exit 1
        ;;

    3)
        # Ожидаем отпускания ПКМ
        sleep 0.15

        notify "Через 5 секунд выделите область"
        sleep 5

        # Выделение области
        geom=$(slop -f '%g' -n 2>/dev/null) || exit 0
        [[ -n "$geom" ]] || exit 0

        maim -g "$geom" "$file" 2>/dev/null || exit 1
        ;;

    *)
        exit 0
        ;;
esac

notify "Скриншот сохранён:\n$file"
