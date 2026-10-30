#!/usr/bin/env bash
#true_method
# tomv.sh — per-hash magnet cache, detached aria2c
CACHE_DIR="$HOME/.cache/me/tomv"
LIST_FILE="$CACHE_DIR/.list"
TIMEOUT="${TOMV_TIMEOUT:-120}"
TRACKERS="udp://tracker.opentrackr.org:1337/announce,udp://open.tracker.cl:1337/announce,udp://opentracker.i2p.rocks:6969/announce,udp://tracker.openbittorrent.com:6969/announce"

mkdir -p "$CACHE_DIR"

ME_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEARCH_BIN="$ME_LIB/torsearch"

hash_from_magnet() {
    local m=$1
    if [[ "$m" =~ btih:([^&]+) ]]; then
        echo "${BASH_REMATCH[1],,}"
    elif [[ "$m" =~ btmh:([^&]+) ]]; then
        echo "${BASH_REMATCH[1],,}"
    else
        echo ""
    fi
}

start_aria() {
    local magnet=$1 dir=$2
    local log="$dir/aria.log"
    notify-send -i network-transmit "tomv" "aria2c стартует..." 2>/dev/null || true
    nohup aria2c --enable-dht --dht-listen-port=6881 \
        --seed-time=60 \
        --max-upload-limit=100K \
        --force-sequential=true \
        --allow-overwrite=true \
        --bt-tracker="$TRACKERS" \
        --bt-prioritize-piece=head=10M,tail=2M \
        --bt-save-metadata=true \
        --bt-load-saved-metadata=true \
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
    find "$dir" -type f -size +128k \
        \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.avi' -o -iname '*.mov' \
           -o -iname '*.webm' -o -iname '*.m4v' -o -iname '*.flv' -o -iname '*.ts' \
           -o -iname '*.m2ts' -o -iname '*.mpg' -o -iname '*.mpeg' -o -iname '*.3gp' \
           -o -iname '*.divx' \) -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -f2-
}

list_hashes() {
    local h v
    for h in "${hashes[@]}"; do
        v=$(find_video "$CACHE_DIR/$h")
        if [ -n "$v" ]; then
            printf '%s:%s\n' "$h" "$(basename "$v")"
        else
            printf '%s:нет видео\n' "$h"
        fi
    done
}

del_hash() {
    local h=$1
    pkill -f "aria2c.*--dir=$CACHE_DIR/$h" 2>/dev/null || true
    rm -rf "$CACHE_DIR/$h"
    sed -i "/^${h}$/d" "$LIST_FILE"
    notify-send -i dialog-warning "tomv" "Удалён $h" 2>/dev/null || true
}

stream_hash() {
    local magnet=$1 hash=$2 dir="$CACHE_DIR/$2"
    mkdir -p "$dir"
    echo "$magnet" > "$dir/magnet.link"
    grep -qxF "$hash" "$LIST_FILE" 2>/dev/null || echo "$hash" >> "$LIST_FILE"

    pkill -f "aria2c.*--dir=$dir" 2>/dev/null || true
    start_aria "$magnet" "$dir"

    notify-send -i media-playback-start "tomv" "Ожидание видео..." 2>/dev/null || true

    deadline=$((SECONDS + TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do
        sleep 1
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

    notify-send -i dialog-error "tomv" "Таймаут ${TIMEOUT}с: видео не готово (нет сидов?). aria2c продолжает качать — проверь позже: me tomv -l" 2>/dev/null || true
    exit 1
}

if [ "$1" = "-s" ]; then
    q="$2"
    if [ -z "$q" ]; then
        read -r -p "Поисковый запрос: " q < /dev/tty 2>/dev/null || exit 1
    fi
    [ -z "$q" ] && exit 1
    if [ ! -x "$SEARCH_BIN" ]; then
        notify-send -i dialog-error "tomv" "Поиск недоступен: нет $SEARCH_BIN" 2>/dev/null || true
        exit 1
    fi
    sel=$( "$SEARCH_BIN" -q "$q" 2>/dev/null | fzf --reverse -d $'\t' --with-nth=4,2,3 \
        --header 'Enter — стримить (aria2c+mpv)   Esc — выход' )
    [ -z "$sel" ] && exit 0
    magnet=$(printf '%s\n' "$sel" | cut -f1)
    hash=$(hash_from_magnet "$magnet")
    if [ -z "$hash" ]; then
        notify-send -i dialog-error "tomv" "Не удалось извлечь хеш из результата" 2>/dev/null || true
        exit 1
    fi
    stream_hash "$magnet" "$hash"
    exit 0
fi

if [ "$1" = "-d" ]; then
    if [ -f "$LIST_FILE" ] && [ -s "$LIST_FILE" ]; then
        mapfile -t hashes < "$LIST_FILE"
        sel=$( { printf 'ALL:удалить ВСЁ кэши целиком\n'; list_hashes; } \
            | fzf -m --reverse --with-nth=2.. -d: \
            --header 'Tab — отметить   Enter — удалить   Esc — отмена')
        [ -z "$sel" ] && exit 0
        mapfile -t sel <<< "$sel"
        for h in "${sel[@]%%:*}"; do
            if [ "$h" = "ALL" ]; then
                pkill -f "aria2c.*--dir=$CACHE_DIR/" 2>/dev/null || true
                rm -rf "$CACHE_DIR"
                notify-send -i dialog-information "tomv" "Все кэши очищены" 2>/dev/null || true
                exit 0
            fi
        done
        for h in "${sel[@]%%:*}"; do del_hash "$h"; done
        [ ${#sel[@]} -gt 0 ] && notify-send -i dialog-information "tomv" "Удалено: ${#sel[@]}" 2>/dev/null || true
        exit 0
    fi
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
        while :; do
            res=$(list_hashes | fzf --reverse --with-nth=2.. -d: \
                --expect=enter,ctrl-d \
                --header 'Enter — запустить   Ctrl-D — удалить   Esc — выход')
            [ -z "$res" ] && exit 0
            mapfile -t res <<< "$res"
            key="${res[0]}"
            hash="${res[1]%%:*}"
            [ -z "$hash" ] && exit 0
            if [ "$key" = "ctrl-d" ]; then
                del_hash "$hash"
                mapfile -t hashes < "$LIST_FILE"
                if [ ${#hashes[@]} -eq 0 ]; then
                    notify-send -i dialog-error "tomv" "Список пуст" 2>/dev/null || true
                    exit 1
                fi
                [ ${#hashes[@]} -eq 1 ] && { hash="${hashes[0]}"; break; }
                continue
            fi
            break
        done
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

stream_hash "$magnet" "$hash"
