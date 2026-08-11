#!/usr/bin/env bash
# title: Запись экрана в GIF/MP4
# desk: Захват области экрана (maim/xdotool) и конвертация через ffmpeg
# usage: me gifx
# source: me.conf

set -e

CONFIG="$HOME/.config/me/gifx.conf"
[ -f "$CONFIG" ] || CONFIG="$HOME/.local/bin/me/gifx.conf"
[ -f "$CONFIG" ] && source "$CONFIG"

: "${OUTPUT_DIR:="$HOME/Pictures/gifx"}"
: "${FPS:=10}"
: "${WIDTH:=800}"
: "${DELAY:=0}"
: "${OUTPUT_FORMAT:=gif}"
: "${NOTIFICATIONS:=true}"

notify() { [ "$NOTIFICATIONS" = "true" ] && notify-send "$@" 2>/dev/null || true; }
die() { notify -i dialog-error "gifx: Ошибка" "$1"; exit 1; }

for cmd in ffmpeg notify-send; do
    command -v "$cmd" &>/dev/null || die "Требуется $cmd"
done

[ "$DELAY" -gt 0 ] && notify -t $((DELAY * 1000)) "gifx" "Запись начнётся через ${DELAY}с..." && sleep "$DELAY"

X=""; Y=""; W=""; H=""

if command -v maim &>/dev/null; then
    notify -t 3000 "gifx" "Выберите область для захвата"
    if region=$(maim -s -f xyz 2>/dev/null); then
        [[ "$region" =~ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]] || die "Не удалось разобрать геометрию maim"
        W=${BASH_REMATCH[1]}; H=${BASH_REMATCH[2]}
        X=${BASH_REMATCH[3]}; Y=${BASH_REMATCH[4]}
    fi
fi

if [ -z "$X" ] && command -v xdotool &>/dev/null && command -v xwininfo &>/dev/null; then
    notify -t 2000 "gifx" "Кликните на окно для захвата"
    wid=$(xdotool selectwindow 2>/dev/null) || die "Выбор окна отменён"
    sleep 0.2
    eval $(xwininfo -id "$wid" 2>/dev/null | awk '
        /Absolute upper-left X:/ {print "X=" $4}
        /Absolute upper-left Y:/ {print "Y=" $4}
        /Width:/ {print "W=" $2}
        /Height:/ {print "H=" $2}
    ')
fi

[ -z "$X" ] && die "Выбор области отменён или не выполнен"
[ $((W % 2)) -eq 1 ] && W=$((W - 1))
[ $((H % 2)) -eq 1 ] && H=$((H - 1))
[ "$W" -le 0 ] || [ "$H" -le 0 ] && die "Нулевой размер области"

mkdir -p "$OUTPUT_DIR"
timestamp=$(date +%Y%m%d_%H%M%S)
output_mp4="$OUTPUT_DIR/gifx_${timestamp}.mp4"

display="${DISPLAY:-:0}"
[[ "$display" == *.* ]] || display="${display}.0"

ffmpeg -y -f x11grab -r "$FPS" -s "${W}x${H}" -i "${display}+${X},${Y}" \
    -vcodec libx264 -pix_fmt yuv420p -crf 23 -loglevel error "$output_mp4" &
ffpid=$!
trap 'kill "$ffpid" 2>/dev/null; exit' EXIT INT TERM

notify -t 0 "gifx" "Запись... нажмите Escape для остановки"

while kill -0 "$ffpid" 2>/dev/null; do
    if read -t 0.05 -n 1 key 2>/dev/null; then
        [ "$key" = $'\e' ] && kill -INT "$ffpid" 2>/dev/null && break
    fi
done
notify -t 1000 "gifx" "Запись остановлена, финализация..."
wait "$ffpid" 2>/dev/null || true

notify -t 2000 "gifx" "Запись завершена, конвертация..."
[ ! -s "$output_mp4" ] && die "Файл не создан"

final="$output_mp4"
if [ "$OUTPUT_FORMAT" = "gif" ]; then
    output_gif="${output_mp4%.mp4}.gif"
    sc=""
    [ "$W" -gt "$WIDTH" ] && sc="scale=$WIDTH:-1:flags=lanczos,"
    ffmpeg -y -i "$output_mp4" -vf "${sc}split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 -loglevel error "$output_gif"
    if [ -s "$output_gif" ]; then
        rm -f "$output_mp4"
        final="$output_gif"
    fi
fi

notify -t 3000 "gifx" "Сохранено: $(basename "$final")"
echo "$final"
