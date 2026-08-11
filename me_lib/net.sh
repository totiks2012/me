#!/usr/bin/env bash
# net.sh — диагностика причин пропажи сети (NetworkManager)
# Вызывается методом `me net`. Никаких аргументов не принимает.
set -u

if ! command -v nmcli &>/dev/null; then
    echo "Причина: nmcli не установлен"
    echo "Исправить: установить network-manager (sudo apt install network-manager)"
    exit 1
fi

conn="" iface="" state="" ip="" gw="" sig=""
root="" inet_ok=0
probs=() fixes=() dets=()

# 1. Работает ли NetworkManager
if { command -v systemctl &>/dev/null && systemctl is-active --quiet NetworkManager 2>/dev/null; } || \
   pgrep -x NetworkManager &>/dev/null; then
    :
else
    probs+=("NetworkManager не запущен")
    fixes+=("Запустить: systemctl --user start NetworkManager или sudo systemctl start NetworkManager")
    dets+=("Сервис NetworkManager не работает, сетью некому управлять.")
    root=${root:-"NetworkManager не запущен"}
fi

# 2. Активные соединения
conn=$(timeout 10 nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | head -n1)
if [ -n "$conn" ]; then
    iface="${conn##*:}"
else
    probs+=("Нет активного соединения")
    fixes+=("Подключить: nmcli connection up <имя> или выбрать через nmtui")
    dets+=("Ни одно сохранённое соединение не поднято. Список: nmcli connection show")
    root=${root:-"Нет активного соединения"}
fi

# 3. Состояние интерфейса
if [ -n "$iface" ]; then
    state=$(timeout 10 nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$iface" '$1==d{print $2}')
    if [ "$state" = "connected" ]; then
        :
    elif [ "$state" = "disconnected" ]; then
        probs+=("Интерфейс $iface в состоянии disconnected")
        fixes+=("Переподключить Wi-Fi: nmcli device connect $iface")
        dets+=("Интерфейс $iface не подключён. Попробуйте переподключить устройство.")
        root=${root:-"Интерфейс $iface не подключён"}
    elif [ "$state" = "unavailable" ]; then
        probs+=("Интерфейс $iface недоступен (unavailable)")
        fixes+=("Проверить rfkill: rfkill list ; включить: nmcli radio wifi on")
        dets+=("Состояние $state — интерфейс обычно выключен физически или через rfkill/режим полёта.")
        root=${root:-"Интерфейс $iface недоступен"}
    fi
fi

# 4. Получен ли IP-адрес
ip=$(timeout 10 nmcli -t -f IP4.ADDRESS device show "$iface" 2>/dev/null | head -n1)
ip="${ip#*:}"
if [ -z "$ip" ]; then
    probs+=("IP-адрес не получен")
    fixes+=("Обновить DHCP: nmcli connection down <имя> && nmcli connection up <имя>")
    dets+=("$iface не получил IPv4 по DHCP. Переподключите соединение.")
    root=${root:-"IP-адрес не получен"}
fi

# 5. Есть ли маршрут по умолчанию
gw=$(timeout 10 nmcli -t -f IP4.GATEWAY device show "$iface" 2>/dev/null | head -n1)
gw="${gw#*:}"
if [ -z "$gw" ]; then
    probs+=("Нет маршрута по умолчанию")
    fixes+=("Проверить шлюз и переподключить соединение")
    dets+=("Отсутствует IP4.GATEWAY у $iface — шлюз не назначен.")
    root=${root:-"Нет маршрута по умолчанию"}
fi

# 6. Доступен ли шлюз
if [ -n "$gw" ] && command -v ping &>/dev/null && ! ping -c1 -W2 "$gw" >/dev/null 2>&1; then
    probs+=("Шлюз $gw недоступен")
    fixes+=("Проверить кабель / роутер / сигнал Wi-Fi")
    dets+=("Ping до шлюза $gw не проходит — физическая связь с роутером/сетью нарушена.")
    root=${root:-"Шлюз недоступен"}
fi

# 7. Доступен ли интернет
if command -v ping &>/dev/null && ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
    inet_ok=1
else
    probs+=("Интернет недоступен (1.1.1.1 не отвечает)")
    fixes+=("Проблема за шлюзом (провайдер или DNS)")
    dets+=("Пинг до 1.1.1.1 не проходит — связи с глобальной сетью нет.")
    root=${root:-"Интернет недоступен"}
fi

# 8. Состояние DNS
if command -v getent &>/dev/null && ! timeout 5 getent ahosts example.com >/dev/null 2>&1; then
    probs+=("DNS не работает (example.com не резолвится)")
    fixes+=("Проверить /etc/resolv.conf: sudo nano /etc/resolv.conf ; nameserver 1.1.1.1")
    dets+=("Резолвер не отвечает или в /etc/resolv.conf нет nameserver.")
    root=${root:-"DNS не работает"}
fi

# 9. Wi-Fi: уровень сигнала
if [[ "$iface" == wl* ]]; then
    sig=$(timeout 5 nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')
    [ -z "$sig" ] && sig=$(awk -v d="$iface" '$1 ~ ("^" d) {print $3}' /proc/net/wireless 2>/dev/null | sed 's/\.$//')
    if [ -n "$sig" ] && [ "$sig" -lt 20 ] 2>/dev/null; then
        probs+=("Слабый Wi-Fi сигнал: $sig%")
        fixes+=("Подойти ближе к роутеру или использовать кабель/репитер")
        dets+=("Уровень сигнала $iface низкий — возможны обрывы и потери пакетов.")
        root=${root:-"Слабый Wi-Fi сигнал"}
    fi
fi

# Контекст (если соединение есть)
echo "=== Диагностика сети ==="
if [ -n "$conn" ]; then
    short_ip="${ip%%/*}"
    echo "Соединение: ${conn%%:*} (${iface:-?}) | IP: ${short_ip:-нет} | Шлюз: ${gw:-нет}"
fi

# Проблем не найдено
if [ "${#probs[@]}" -eq 0 ]; then
    echo "Проблем не найдено — сеть работает."
    exit 0
fi

# Вывод проблем: fzf с превью или простой текст
if command -v fzf &>/dev/null && [ -t 1 ]; then
    tab=$'\t' list=""
    for i in "${!probs[@]}"; do
        list+="${probs[$i]}${tab}${dets[$i]}${tab}${fixes[$i]}"$'\n'
    done
    printf "%b" "$list" | fzf --reverse --delimiter="$tab" --with-nth=1 \
        --preview 'echo {} | tr "\t" "\n"' \
        --preview-window=wrap:right:60% \
        --header="Найдено проблем: ${#probs[@]} (Enter — закрыть)"
else
    for i in "${!probs[@]}"; do
        echo "Причина: ${probs[$i]}"
        echo "Исправить: ${fixes[$i]}"
        echo
    done
fi

# Итог
echo "--- Итог ---"
if [ "$inet_ok" -eq 1 ]; then
    echo "Сеть работает частично (проблем: ${#probs[@]}). Главная причина: $root"
else
    echo "Сеть полностью недоступна. Главная причина: $root"
fi
