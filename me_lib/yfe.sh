#!/usr/bin/env bash
# yfe.sh – YouTube Feed Explorer: sfeed + fzf + yt-dlp + mpv

CONF_FILE="$HOME/.config/me/yfe.conf"
CACHE_DIR="$HOME/.cache/me/yfe"
CACHE_FILE="$CACHE_DIR/entries"
LOCK_FILE="$CACHE_DIR/update.lock"
TTL=30
HISTORY_FILE="$CACHE_DIR/history"
mkdir -p "$CACHE_DIR"

cleanup() {
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
}

trap cleanup EXIT

update() {
    if [ -f "$LOCK_FILE" ]; then
        age_lock=$(( ($(date +%s) - $(stat -c %Y "$LOCK_FILE")) / 60 ))
        [ "$age_lock" -lt 10 ] && return 0
    fi

    [ ! -f "$CONF_FILE" ] && echo "[yfe] Конфиг не найден" >&2 && exit 1

    touch "$LOCK_FILE"

    notify-send -i media-playback-start -t 2000 "YouTube Feeds" "Загружаю..." 2>/dev/null || true

    > "$CACHE_FILE.tmp"
    pids=()
    feed_n=0
    cat=""
    while IFS='|' read -r label url || [ -n "$label" ]; do
        [[ "$label" == \[*\] ]] && cat="${label#[}" && cat="${cat%]}" && continue
        [[ -z "$url" || "$label" == \#* ]] && continue
        [ -z "$url" ] && url="$label" && label=""
        tdir=$(mktemp -d /tmp/yfe_feed_XXXXXX)
        tmpf=$(mktemp -u /tmp/yfe_feed_XXXXXX)
        (
            curl -sL --max-time 15 "$url" > "$tdir/xml" 2>/dev/null
            sfeed < "$tdir/xml" 2>/dev/null | awk -F'\t' -v lbl="$label" -v cat="$cat" \
                '{ch=lbl ? lbl : $7; disp=(cat ? "[" cat "]" : "") "[" ch "] " $2; print disp "\t" $3 "\t" ch "\t" cat}' \
                > "$tdir/sfeed"
            grep -oP '<published>\K[^<]+' "$tdir/xml" > "$tdir/d" 2>/dev/null
            paste "$tdir/sfeed" "$tdir/d" | awk -F'\t' 'length($1)>0' > "$tmpf" 2>/dev/null
            rm -rf "$tdir"
        ) &
        feed_n=$((feed_n + 1))
        pids+=("$!")
        eval "feed_${feed_n}=\"\$tmpf\""
    done < "$CONF_FILE"

    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done

    for i in $(seq 1 "$feed_n"); do
        tmpvar="feed_$i"
        f="${!tmpvar}"
        [ -s "$f" ] && cat "$f" >> "$CACHE_FILE.tmp"
        rm -f "$f"
    done

    [ ! -s "$CACHE_FILE.tmp" ] && echo "[yfe] Нет записей" >&2 && rm -f "$CACHE_FILE.tmp" "$LOCK_FILE" && exit 1
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    rm -f "$LOCK_FILE"
}

pick() {
    [ ! -s "$CACHE_FILE" ] && return 1
    LC_ALL=C sort -t$'\t' -k4,4 -k3,3 -k5,5r "$CACHE_FILE" 2>/dev/null | awk -F'\t' 'length($1)>0' | \
        awk -F'\t' 'BEGIN{OFS="\t"} {gsub(/T.*/,"",$5); if(length($5)==10) $5=substr($5,9,2)"-"substr($5,6,2)"-"substr($5,3,2)} 1' | fzf --reverse \
        --delimiter=$'\t' --with-nth=1 \
        --preview='bash -c '"'"'
url="$1"; channel="$2"; category="$3"; dt="$4"
hist="$HOME/.cache/me/yfe/history"; tag="● НОВОЕ"
[ -f "$hist" ] && grep -qF "$url" "$hist" 2>/dev/null && tag="★ ПРОСМОТРЕНО"
[ -z "$dt" ] && dt="н/д"
printf "%s  Дата: %s\nКатегория: %s\nКанал: %s\nСсылка: %s" "$tag" "$dt" "$category" "$channel" "$url"
'"'"' -- {2} {3} {4} {5}' \
        --preview-window='right:50%:nowrap' 2>/dev/null | cut -f2
}

# Выбор формата: 720p по умолчанию; если 720p недоступен — уведомление и откат к 480p
pick_fmt() {
    local url="$1"
    if yt-dlp --simulate --no-warnings -f "bestvideo[height=720]/best[height=720]" -O "%(format_id)s" "$url" >/dev/null 2>&1; then
        echo "bestvideo[height<=720]+bestaudio/best[height<=720]"
    else
        notify-send -i dialog-warning -t 3500 "YouTube" "720p недоступен — отдаю 480p" 2>/dev/null || true
        echo "bestvideo[height<=480]+bestaudio/best[height<=480]"
    fi
}

case "$1" in
    --update|-r)
        update
        ;;
    -u)
        [ -s "$CACHE_FILE" ] || update
        pick
        ;;
    *)
        if [ ! -s "$CACHE_FILE" ]; then
            update
        else
            age=$(( ($(date +%s) - $(stat -c %Y "$CACHE_FILE")) / 60 ))
            [ "$age" -gt "$TTL" ] && update
        fi

        [ ! -s "$CACHE_FILE" ] && echo "[yfe] Нет записей" >&2 && exit 1

        chosen=$(pick)
        if [ -n "$chosen" ]; then
            streamed=0
            notify-send -i video-display -t 2000 "YouTube" "Стримлю..." 2>/dev/null || true
            if mpv --ytdl-format="$(pick_fmt "$chosen")" "$chosen" 2>/dev/null; then
                streamed=1
            fi
            if [ "$streamed" -eq 1 ]; then
                echo "$chosen" >> "$HISTORY_FILE"
            else
                notify-send -i video-display -t 2000 "YouTube" "Стрим упал, качаю..." 2>/dev/null || true
                tmp_base=$(mktemp -u /tmp/yfe_XXXXXX)
                trap 'rm -f "$tmp_base"* "$LOCK_FILE"' EXIT
                for i in 1 2 3; do
                    yt-dlp --force-ipv4 --downloader native \
                        --extractor-retries 10 --retry-sleep 5 \
                        -f "bestvideo[height<=720]+bestaudio/best[height<=720]" \
                        --merge-output-format mp4 \
                        --retries 10 --fragment-retries 10 --no-mtime \
                        -o "$tmp_base.%(ext)s" "$chosen"
                    for f in "$tmp_base"*; do [ -s "$f" ] && real_file="$f" && break 2; done
                    sleep 3
                done
                if [ -n "$real_file" ] && [ -s "$real_file" ]; then
                    notify-send -i video-display -t 2000 "YouTube" "Воспроизвожу..." 2>/dev/null || true
                    mpv "$real_file"
                    echo "$chosen" >> "$HISTORY_FILE"
                fi
            fi
        fi
        ;;
esac
