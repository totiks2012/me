#!/bin/bash
#@method: color
#@description: Окрашивание текста (без автоматического перевода строки)
#@example: red "Успех: выполнено"

# Неяркие (0;XX) с переводом строки
red_nl() { echo -e "\033[0;31m$*\033[0m"; }
green_nl() { echo -e "\033[0;32m$*\033[0m"; }
yellow_nl() { echo -e "\033[0;33m$*\033[0m"; }
blue_nl() { echo -e "\033[0;34m$*\033[0m"; }
magenta_nl() { echo -e "\033[0;35m$*\033[0m"; }
cyan_nl() { echo -e "\033[0;36m$*\033[0m"; }
gray_nl() { echo -e "\033[0;37m$*\033[0m"; }

# Яркие (1;XX) с переводом строки
bred_nl() { echo -e "\033[1;31m$*\033[0m"; }
bgreen_nl() { echo -e "\033[1;32m$*\033[0m"; }
byellow_nl() { echo -e "\033[1;33m$*\033[0m"; }
bblue_nl() { echo -e "\033[1;34m$*\033[0m"; }
bmagenta_nl() { echo -e "\033[1;35m$*\033[0m"; }
bcyan_nl() { echo -e "\033[1;36m$*\033[0m"; }
bgray_nl() { echo -e "\033[1;37m$*\033[0m"; }

# Неяркие (0;XX) без перевода строки (для таблиц)
red() { printf "\033[0;31m%s\033[0m" "$*"; }
green() { printf "\033[0;32m%s\033[0m" "$*"; }
yellow() { printf "\033[0;33m%s\033[0m" "$*"; }
blue() { printf "\033[0;34m%s\033[0m" "$*"; }
magenta() { printf "\033[0;35m%s\033[0m" "$*"; }
cyan() { printf "\033[0;36m%s\033[0m" "$*"; }
gray() { printf "\033[0;37m%s\033[0m" "$*"; }

# Яркие (1;XX) без перевода строки (для таблиц)
bred() { printf "\033[1;31m%s\033[0m" "$*"; }
bgreen() { printf "\033[1;32m%s\033[0m" "$*"; }
byellow() { printf "\033[1;33m%s\033[0m" "$*"; }
bblue() { printf "\033[1;34m%s\033[0m" "$*"; }
bmagenta() { printf "\033[1;35m%s\033[0m" "$*"; }
bcyan() { printf "\033[1;36m%s\033[0m" "$*"; }
bgray() { printf "\033[1;37m%s\033[0m" "$*"; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if declare -f "$1" >/dev/null; then
        "$@"
    else
        echo "Доступные функции: red, green, yellow, blue, magenta, cyan, gray, bred, bgreen, byellow, bblue, bmagenta, bcyan, bgray" >&2
        echo "С суффиксом _nl — с переводом строки" >&2
        exit 1
    fi
fi