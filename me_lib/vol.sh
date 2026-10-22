#!/usr/bin/env bash
# me vol — уровень громкости аудиопотока [up|down|mute]
case "$1" in
    up)   pactl set-sink-volume @DEFAULT_SINK@ +5% 2>/dev/null || amixer set Master 5%+ >/dev/null
          notify-send -i audio-volume-high -t 1500 "Звук" "Громкость увеличена" 2>/dev/null || true ;;
    down) pactl set-sink-volume @DEFAULT_SINK@ -5% 2>/dev/null || amixer set Master 5%- >/dev/null
          notify-send -i audio-volume-low -t 1500 "Звук" "Громкость уменьшена" 2>/dev/null || true ;;
    mute) pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null || amixer set Master toggle >/dev/null
          notify-send -i audio-volume-muted -t 1500 "Звук" "Режим тишины переключен" 2>/dev/null || true ;;
    *)    echo "Используй: me vol [up|down|mute]" >&2 ;;
esac
