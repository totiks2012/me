#!/usr/bin/env bash
#true_method
# me logo — включение/выключение логотипа \me/
flag_file="$HOME/.config/me/.logo"
case "${1:-}" in
    on|1|yes|true)
        echo "1" > "$flag_file"
        echo "\me/ Включён" ;;
    off|0|no|false)
        echo "0" > "$flag_file"
        echo "\me/ Выключен" ;;
    *)
        echo "Использование: me logo on|off" >&2
        exit 1 ;;
esac
