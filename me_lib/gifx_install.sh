#!/usr/bin/env bash

ME_DIR="$HOME/.local/bin/me"
CONF_DIR="$HOME/.config/me"

echo "[gifx] Установка зависимостей..."

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null && sudo -v; then
        SUDO="sudo"
    else
        echo "[gifx] Нужны права root: введите пароль sudo в терминале или запустите от root." >&2
        exit 1
    fi
fi

install_pkg() {
    $SUDO apt-get install -y "$1" 2>&1 | grep -v "^$"
}

check_dep() {
    local bin="$1" pkg="$2" label="$3"
    if command -v "$bin" &>/dev/null; then
        echo "  $label — OK"
    else
        echo "  Устанавливаю $label ($pkg)..."
        install_pkg "$pkg" && echo "  $label — OK" || echo "  ! Не удалось установить $label"
    fi
}

check_dep ffmpeg      ffmpeg        "ffmpeg"
check_dep notify-send libnotify-bin "notify-send"
check_dep maim        maim          "maim"
check_dep xdotool     xdotool       "xdotool"
check_dep xwininfo    x11-utils     "xwininfo (x11-utils)"

echo "[gifx] Зависимости проверены."

echo "[gifx] Регистрация метода в me.conf..."

METHOD_BLOCK=$(cat <<'EOF'

#@method: gifx
#@description: Запись GIF/MP4 выбранной области экрана (F5 старт/стоп)
#@example: me gifx
me_method_gifx() {
    local script_path="$HOME/.local/bin/me/me_lib/gifx.sh"
    if [ -x "$script_path" ]; then
        "$script_path" "$@"
    else
        notify-send -i dialog-error -t 3000 "Ошибка пульта" "gifx.sh не найден" 2>/dev/null || true
        echo "[me] Ошибка: Файл $script_path не найден или не имеет прав +x." >&2
        return 1
    fi
}
EOF
)

register() {
    local conf="$1"
    if [ ! -f "$conf" ]; then
        mkdir -p "$(dirname "$conf")"
        touch "$conf"
    fi
    if grep -q "#@method: gifx" "$conf" 2>/dev/null; then
        echo "  $conf — уже зарегистрирован"
    else
        echo "$METHOD_BLOCK" >> "$conf"
        echo "  $conf — метод gifx добавлен"
    fi
}

register "$ME_DIR/me.conf"
register "$CONF_DIR/me.conf"

echo "[gifx] Готово. me gifx"
