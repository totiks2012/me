#!/usr/bin/env bash
# Скриншот через scrot

CONFIG="$HOME/.local/bin/me/scr.conf"
[ -f "$CONFIG" ] && source "$CONFIG"

: "${OUTPUT_DIR:="$HOME/Pictures/scrot"}"
: "${DELAY:=0}"
: "${NOTIFICATIONS:=true}"

notify() { [ "$NOTIFICATIONS" = "true" ] && notify-send "$@" 2>/dev/null || true; }
die() { notify -i dialog-error "scr: Ошибка" "$1"; exit 1; }

command -v scrot &>/dev/null || die "Требуется scrot"

mkdir -p "$OUTPUT_DIR"

sleep "$DELAY"

scrot -s "$OUTPUT_DIR/scrot_%Y-%m-%d_%H%M%S.png" || die "scrot не удался"

notify -t 3000 "scr" "Скриншот сохранён"
