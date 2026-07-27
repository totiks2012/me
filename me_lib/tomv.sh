#!/usr/bin/env bash
# tomv.sh — per-hash magnet cache, detached aria2c
set -x
CACHE_DIR="$HOME/.cache/me/tomv"
LIST_FILE="$CACHE_DIR/.list"

mkdir -p "$CACHE_DIR"

hash_from_magnet() {
    local m=$1
    [[ "$m" =~ btih:([^&]+) ]] && echo "${BASH_REMATCH[1]}" || echo ""
}

start_aria() {
    local magnet=$1 dir=$2
    local log="$dir/aria.log"
    notify-send -i network-transmit "tomv" "aria2c стартует..." 2>/dev/null || true
    nohup aria2c --enable-dht --dht-listen-port=6881 \
        --seed-time=60 \
        --max-upload-limit=100K \
        --max-connection-per-server=16 \
        --force-sequential=true \
        --allow-overwrite=true \
        --console-log-level=error --summary-interval=0 \
        --dir="$dir" \
        "$magnet" > "$log" 2>&1 &
    disown $!
}

aria_running() {
    local dir=$1
    pgrep -f "aria2c.*--dir=$dir" >/dev/null 2>&1
}

find_video() {
    local dir=$1
    find "$dir" -type f -size +1M \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.avi' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.m4v' -o -iname '*.flv' -o -iname '*.ts' -o -iname '*.m2ts' -o -iname '*.mpg' -o -iname '*.mpeg' -o -iname '*.3gp' -o -iname '*.divx' \) 2>/dev/null | head -1
}

if [ "$1" = "-d" ]; then
    pkill -f "aria2c.*--dir=$CACHE_DIR/" 2>/dev/null || true
    rm -rf "$CACHE_DIR"
    notify-send -i dialog-information "tomv" "Все кэши очищены" 2>/dev/null || true
    exit 0
fi

if [ "$1" = "-l" ]; then
    if [ ! -f "$LIST_FILE" ]; then
        notify-send -i dialog-error "tomv" "Нет сохранённых торрентов" 2>/dev/null || true
        exit 1
    fi

    mapfile -t hashes < "$LIST_FILE"
    if [ ${#hashes[@]} -eq 0 ]; then
        notify-send -i dialog-error "tomv" "Список пуст" 2>/dev/null || true
        exit 1
    fi

    if [ ${#hashes[@]} -eq 1 ]; then
        hash="${hashes[0]}"
    else
        list=()
        for h in "${hashes[@]}"; do
            v=$(find_video "$CACHE_DIR/$h")
            [ -n "$v" ] && list+=("$h:$(basename "$v")") || list+=("$h:нет видео")
        done
        hash=$(printf "%s\n" "${list[@]}" | fzf --reverse --with-nth=2.. -d: | cut -d: -f1)
        if [ -z "$hash" ]; then
            exit 0
        fi
    fi

    dir="$CACHE_DIR/$hash"
    video=$(find_video "$dir")
    if [ -z "$video" ]; then
        notify-send -i dialog-error "tomv" "Видео не найдено для хеша $hash" 2>/dev/null || true
        exit 1
    fi

    ftype=$(file -b "$video" 2>/dev/null)
    case "$ftype" in
        *Matroska*|*RIFF*|*ISOM*|*ISO\ Media*|*Apple\ QuickTime*|*MPEG\ 4*|*WebM*)
            ;;
        *)
            notify-send -i dialog-error "tomv" "Файл ещё не готов (формат не распознан)" 2>/dev/null || true
            exit 1
            ;;
    esac

    if ! aria_running "$dir"; then
        magnet=$(cat "$dir/magnet.link" 2>/dev/null)
        [ -n "$magnet" ] && start_aria "$magnet" "$dir"
    fi

    notify-send -i media-playback-start "tomv" "$hash" 2>/dev/null || true
    mpv "$video"
    exit 0
fi

magnet=$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || true)
if [ -z "$magnet" ]; then
    notify-send -i dialog-error "tomv" "Буфер обмена пуст" 2>/dev/null || true
    exit 1
fi
if [[ "$magnet" != magnet:* ]]; then
    notify-send -i dialog-error "tomv" "В буфере не magnet-ссылка" 2>/dev/null || true
    exit 1
fi

hash=$(hash_from_magnet "$magnet")
if [ -z "$hash" ]; then
    notify-send -i dialog-error "tomv" "Не удалось извлечь хеш" 2>/dev/null || true
    exit 1
fi

dir="$CACHE_DIR/$hash"
mkdir -p "$dir"
echo "$magnet" > "$dir/magnet.link"
grep -qxF "$hash" "$LIST_FILE" 2>/dev/null || echo "$hash" >> "$LIST_FILE"

pkill -f "aria2c.*--dir=$dir" 2>/dev/null || true
start_aria "$magnet" "$dir"

notify-send -i media-playback-start "tomv" "Ожидание видео..." 2>/dev/null || true

while true; do
    sleep 5
    video=$(find_video "$dir")
    if [ -n "$video" ]; then
        ftype=$(file -b "$video" 2>/dev/null)
        case "$ftype" in
            *Matroska*|*RIFF*|*ISOM*|*ISO\ Media*|*Apple\ QuickTime*|*MPEG\ 4*|*WebM*)
                notify-send -i video-display -t 2000 "tomv" "Воспроизвожу..." 2>/dev/null || true
                mpv "$video"
                exit 0
                ;;
        esac
    fi
done
