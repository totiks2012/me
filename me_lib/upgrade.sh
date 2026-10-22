#!/usr/bin/env bash
# me upgrade — автономное тотальное обновление пакетов (pacman/apt/apk)
echo "=== Запуск тотального обновления ==="
if command -v pacman &>/dev/null; then
    sudo pacman -Syu --noconfirm
elif command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get upgrade -y
elif command -v apk &>/dev/null; then
    sudo apk update && sudo apk upgrade
else
    echo "Неизвестный пакетный менеджер" >&2
    exit 1
fi
