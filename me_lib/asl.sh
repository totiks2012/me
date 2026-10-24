#!/usr/bin/env bash
#true_method
# asl.sh – anti sleep: запрещает экрану гаснуть и засыпать (X11/xset)
#   me asl          включить анти-слип (гашение + DPMS) + наблюдатель
#   me asl off      вернуть исходные настройки экрана, остановить наблюдатель
#   me asl status   показать текущее состояние
#   me asl -h       справка
#
# Наблюдатель: раз в 10 минут, если пользователь ничего не делает (нет
# нажатий клавиш и других действий), имитирует нажатие Shift через xdotool
# — сбрасывает таймер простоя X11 и встроенный таймер монитора, чтобы он
# не уснул. Мышь не двигается и не используется; детект простоя — только
# через xprintidle (sudo apt install xprintidle). Без xprintidle
# наблюдатель не срабатывает.

STATE="$HOME/.cache/me/asl.state"     # исходные параметры экрана
PIDF="$HOME/.cache/me/asl.pid"        # pid наблюдателя
LOG="$HOME/.cache/me/asl.log"         # журнал срабатываний наблюдателя
INTERVAL="${ASL_INTERVAL:-600}"       # период проверки, сек (10 мин)

usage() {
    cat <<'EOF'
asl — анти-слип: запрещает экрану гаснуть и засыпать (X11/xset)

Использование:
  me asl            включить анти-слип (гашение + DPMS выключены)
  me asl off        вернуть исходные настройки экрана
  me asl status     показать текущее состояние
  me asl -h         эта справка

Наблюдатель (запускается вместе с `me asl`): раз в 10 минут при простое
пользователя имитирует нажатие Shift через xdotool — монитор со встроенным
таймером не уснёт. Простой определяется только через xprintidle
(sudo apt install xprintidle); без него наблюдатель не срабатывает.
Мышь не двигается и не используется. Остановка: me asl off.
EOF
}

command -v xset >/dev/null 2>&1 || { echo "[asl] Ошибка: xset не найден (нужен X11)" >&2; exit 1; }
[ -n "$DISPLAY" ] || { echo "[asl] Ошибка: DISPLAY не установлен (нет X-сессии)" >&2; exit 1; }

# Исходные параметры гашения из `xset q` — строка "timeout:  N    cycle:  N"
saver_params() {
    xset q 2>/dev/null | awk '/timeout:/{print $2, $4; exit}'
}

# Таймеры DPMS из `xset q` — строка "Standby: N    Suspend: N    Off: N"
dpms_timers() {
    xset q 2>/dev/null | awk '/Standby:/{print $2, $4, $6; exit}'
}

dpms_enabled() {
    xset q 2>/dev/null | grep -q "DPMS is Enabled"
}

# ---------------------------------------------------------------------------
# Наблюдатель: имитация Shift раз в 10 минут при простое пользователя
# ---------------------------------------------------------------------------

# Милисекунды с последней активности (клавиатура/мышь) через xprintidle.
# Мышь не трогаем: детект простоя — только по xprintidle; если пакета нет,
# возвращаем пусто (unknown) — срабатывать не будем.
idle_ms() {
    command -v xprintidle >/dev/null 2>&1 || return
    xprintidle 2>/dev/null
}

simulate_shift() {
    # DISPLAY/XAUTHORITY фиксируем явно — на случай запуска без терминала
    export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
    xdotool keydown shift 2>>"$LOG"
    sleep 0.1
    xdotool keyup shift 2>>"$LOG"
    echo "[$(date '+%d.%m %H:%M:%S')] Простой ≥ ${INTERVAL} c: имитация Shift — сброс таймера монитора" >> "$LOG"
}

# Внутренний режим `asl.sh watchdog` — фоновый цикл (запускается через nohup).
watchdog_loop() {
    local idle
    if ! command -v xdotool >/dev/null 2>&1; then
        echo "[asl] Наблюдатель: xdotool не найден — имитация Shift невозможна." >&2
        exit 1
    fi
    if ! command -v xprintidle >/dev/null 2>&1; then
        echo "[asl] Наблюдатель: xprintidle не найден — простой не определяется, Shift не будет имитироваться. Установите: sudo apt install xprintidle" >&2
    fi
    while :; do
        sleep "$INTERVAL"
        idle=$(idle_ms)
        if [ -n "$idle" ] && [ "$idle" -ge $((INTERVAL * 1000)) ]; then
            simulate_shift
        fi
    done
}

watchdog_running() {
    local pid
    [ -f "$PIDF" ] || return 1
    pid=$(cat "$PIDF" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
    return 1
}

start_watchdog() {
    if watchdog_running; then
        echo "[asl] Наблюдатель уже запущен (pid $(cat "$PIDF"))."
        return 0
    fi
    if ! command -v xdotool >/dev/null 2>&1; then
        echo "[asl] Ошибка: xdotool не найден — имитация Shift каждые $INTERVAL c невозможна." >&2
        return 1
    fi
    mkdir -p "$(dirname "$PIDF")"
    nohup "$0" watchdog >>"$LOG" 2>&1 &
    echo "$!" > "$PIDF"
    echo "[asl] Наблюдатель запущен (pid $!): раз в ${INTERVAL} c при простое имитируется Shift."
    echo "      Журнал срабатываний: $LOG"
    if ! command -v xprintidle >/dev/null 2>&1; then
        echo "[asl] Внимание: xprintidle не найден — простой не определяется, имитация Shift работать не будет."
        echo "      Установите: sudo apt install xprintidle"
    fi
}

stop_watchdog() {
    local pid i
    [ -f "$PIDF" ] || { echo "[asl] Наблюдатель не запущен."; return 0; }
    pid=$(cat "$PIDF" 2>/dev/null)
    rm -f "$PIDF"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        for i in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        echo "[asl] Наблюдатель остановлен."
    else
        echo "[asl] Наблюдатель не запущен."
    fi
}

# ---------------------------------------------------------------------------

status_show() {
    local t c st su so dpms active="off" wd="не запущен"
    read -r t c <<< "$(saver_params)"
    read -r st su so <<< "$(dpms_timers)"
    if dpms_enabled; then dpms="включён"; else dpms="выключен"; fi
    if [ "${t:-0}" -eq 0 ] && ! dpms_enabled; then active="ON"; fi
    if watchdog_running; then
        wd="pid $(cat "$PIDF") (следующая проверка через ${INTERVAL} c)"
    fi
    echo "Гашение (screen saver): timeout=${t:-?}s cycle=${c:-?}s"
    echo "DPMS: $dpms (standby=${st:-?} suspend=${su:-?} off=${so:-?})"
    echo "Анти-слип: $active"
    echo "Наблюдатель (Shift раз в ${INTERVAL} c при простое): $wd"
}

asl_on() {
    local t c st su so en=0
    if [ ! -f "$STATE" ]; then
        read -r t c <<< "$(saver_params)"
        # Сохраняем состояние только если гашение реально было включено (timeout>0):
        # иначе залипший state с timeout=0 после ребута оставил бы экран вечно бодрым.
        if [ -n "$t" ] && [ "$t" -gt 0 ]; then
            read -r st su so <<< "$(dpms_timers)"
            dpms_enabled && en=1
            mkdir -p "$(dirname "$STATE")"
            printf '%s %s %s %s %s %s\n' "$t" "$c" "${st:-0}" "${su:-0}" "${so:-0}" "$en" > "$STATE"
        fi
    fi
    xset s off -dpms 2>/dev/null
    echo "[asl] Анти-слип включён: гашение выключено, DPMS отключён."
    echo "      Вернуть обратно: me asl off"
    start_watchdog
}

asl_off() {
    local t c st su so en
    stop_watchdog
    if [ -f "$STATE" ]; then
        read -r t c st su so en < "$STATE" 2>/dev/null
        xset s "${t:-600}" "${c:-600}" 2>/dev/null
        xset dpms "${st:-0}" "${su:-0}" "${so:-0}" 2>/dev/null
        if [ "${en:-1}" = "1" ]; then
            xset +dpms 2>/dev/null
            echo "[asl] Анти-слип выключен: восстановлено гашение (timeout=${t:-600}s cycle=${c:-600}s), DPMS включён."
        else
            xset -dpms 2>/dev/null
            echo "[asl] Анти-слип выключен: восстановлено гашение (timeout=${t:-600}s cycle=${c:-600}s), DPMS остаётся выключен (как было)."
        fi
        rm -f "$STATE"
    else
        xset s on +dpms 2>/dev/null
        echo "[asl] Анти-слип выключен: гашение и DPMS включены (сохранённого состояния не было)."
    fi
}

case "${1:-}" in
    watchdog)
        watchdog_loop
        ;;
    off)
        asl_off
        ;;
    status)
        status_show
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        asl_on
        ;;
esac