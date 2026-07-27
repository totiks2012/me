#!/usr/bin/env bash
# svy.sh – Поиск видео на YouTube: yt-dlp → fzf → mpv (720p)

if [ "$1" = "-u" ]; then
    url="$2"
    if [ -z "$url" ]; then
        echo "Ошибка: после -u укажите URL видео." >&2
        exit 1
    fi
    notify-send -i video-display -t 2000 "YouTube" "Запускаю видео (720p)" 2>/dev/null || true
    mpv --ytdl-format="bestvideo[height<=720]+bestaudio/best" "$url"
    exit 0
fi

if [ -z "$1" ]; then
    echo "Ошибка: Отсутствует поисковый запрос." >&2
    exit 1
fi

notify-send -i video-display -t 2000 "YouTube" "Ищу и запускаю видео (720p): $1" 2>/dev/null || true

url=$(yt-dlp --flat-playlist --print $'%(title)s\t%(url)s' "ytsearch20:$1" 2>/dev/null | \
    fzf --reverse --delimiter=$'\t' --with-nth=1 | \
    cut -f2)

[ -n "$url" ] && mpv --ytdl-format="bestvideo[height<=720]+bestaudio/best" "$url"
