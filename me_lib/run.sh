#!/usr/bin/env bash
#true_method
# me run — поиск и запуск скрипта по имени в ~/.local/bin/
name="$1"
shift
script=$(find "$HOME/.local/bin" -maxdepth 3 -type f -executable -name "$name" 2>/dev/null | head -1)
if [ -n "$script" ] && [ -x "$script" ]; then
    exec "$script" "$@"
else
    echo "[me] Скрипт '$name' не найден в ~/.local/bin/" >&2
    exit 1
fi
