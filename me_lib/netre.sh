#!/usr/bin/env bash
# netre.sh — перезапуск сети: мягкий (nmcli off/on) или жёсткий (restart NetworkManager)
# Вызывается методом `me netre`.
#   netre.sh        # Мягкий перезапуск: nmcli networking off → on
#   netre.sh hard   # Жёсткий перезапуск NetworkManager (требует sudo)
set -u

mode="${1:-soft}"

if ! command -v nmcli &>/dev/null; then
    echo "[me] Ошибка: nmcli не установлен (network-manager)." >&2
    exit 1
fi

case "$mode" in
    soft)
        echo "Мягкий перезапуск сети..."
        nmcli networking off
        sleep 3
        nmcli networking on
        ;;
    hard)
        if ! command -v systemctl &>/dev/null; then
            echo "[me] Ошибка: systemctl не найден." >&2
            exit 1
        fi
        echo "Жёсткий перезапуск NetworkManager..."
        if [ "$(id -u)" -eq 0 ]; then
            systemctl restart NetworkManager
        else
            sudo systemctl restart NetworkManager
        fi
        ;;
    *)
        echo "Использование: me netre [soft|hard]" >&2
        exit 1
        ;;
esac

echo "Ждём подъём сети..."
tries=0
until [ "$tries" -ge 10 ]; do
    if timeout 5 nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q ':connected' && \
       command -v ping &>/dev/null && ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        break
    fi
    sleep 2
    tries=$((tries+1))
done

echo "--- Статус после перезапуска ---"
timeout 10 nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$3=="connected"{printf "Интерфейс %s (%s): подключён\n", $1, $2}'
active=""
while IFS=: read -r name dev; do
    [ -n "$name" ] && active+="Соединение: $name ($dev)"$'\n'
done < <(timeout 10 nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null)
[ -n "$active" ] && echo "$active"

if command -v ping &>/dev/null && ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
    echo "Результат: сеть работает."
else
    echo "Результат: сеть не поднялась. Проверь: me net"
fi
