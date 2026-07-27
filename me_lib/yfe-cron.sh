#!/usr/bin/env bash
# yfe-cron.sh – Фоновое обновление кэша (только без mpv)

if pgrep -x mpv >/dev/null 2>&1; then
    exit 0
fi

exec "$HOME/.local/bin/me/me_lib/yfe.sh" --update
