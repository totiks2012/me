#!/usr/bin/env bash

ME_DIR="$HOME/.local/bin/me"
CONF_DIR="$HOME/.config/me"

echo "[scr] Установка зависимостей..."

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null && sudo -v; then
        SUDO="sudo"
    else
        echo "[scr] Нужны права root: введите пароль sudo в терминале или запустите от root." >&2
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

check_dep scrot       scrot          "scrot"
check_dep notify-send libnotify-bin "notify-send"

echo "[scr] Зависимости проверены."

echo "[scr] Регистрация метода в me.conf..."

METHOD_BLOCK=$(cat <<'EOF'

#@method: scr
#@description: Создание скриншота
#@example: me scr
me_method_scr() {
    local script_path="$HOME/.local/bin/me/me_lib/scr.sh"
    if [ -x "$script_path" ]; then
        "$script_path"
    else
        notify-send -i dialog-error -t 3000 "Ошибка пульта" "scr.sh не найден" 2>/dev/null || true
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
    if grep -q "#@method: scr" "$conf" 2>/dev/null; then
        echo "  $conf — уже зарегистрирован"
    else
        echo "$METHOD_BLOCK" >> "$conf"
        echo "  $conf — метод scr добавлен"
    fi
}

register "$ME_DIR/me.conf"
register "$CONF_DIR/me.conf"

echo "[scr] Готово. me scr"
