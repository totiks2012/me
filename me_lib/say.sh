#!/usr/bin/env bash
# me say — уведомление на экран: текст, заголовок, иконка, таймаут
title=""
body=""
icon=""
timeout=3000
case "$#" in
    1) title="Системное уведомление"; body="$1"; icon=""; timeout=3000 ;;
    2) title="$1"; body="$2"; icon=""; timeout=3000 ;;
    3) title="$1"; body="$2"; icon="$3"; timeout=3000 ;;
    *) title="$1"; body="$2"; icon="$3"; timeout="${4:-3000}" ;;
esac
notify-send ${icon:+-i "$icon"} -t "$timeout" "$title" "$body" 2>/dev/null || true
