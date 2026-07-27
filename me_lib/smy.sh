#!/usr/bin/env bash
# smy.sh – Поиск аудио на YouTube: yt-dlp → fzf → mpv --no-video

if [ -z "$1" ]; then
    echo "Ошибка: Отсутствует поисковый запрос." >&2
    exit 1
fi

notify-send -i media-playback-start -t 2000 "YouTube" "Ищу и запускаю аудио: $1" 2>/dev/null || true

url=$(yt-dlp --flat-playlist --print $'%(title)s\t%(url)s' "ytsearch20:$1" 2>/dev/null | \
    fzf --reverse --delimiter=$'\t' --with-nth=1 | \
    cut -f2)

[ -n "$url" ] && mpv --no-video "$url"
