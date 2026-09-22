#!/usr/bin/env bash
set -euo pipefail

ME_DIR="$HOME/.local/bin/me"
CONFIG_DEST="$HOME/.config/me"

# 0. Права: выставить +x всем скриптам me и me_lib (по shebang), если бит не стоит
for f in "$ME_DIR"/me* "$ME_DIR"/install_me.sh "$ME_DIR"/me_lib/*; do
    [ -f "$f" ] || continue
    if [ "$(head -c2 "$f" 2>/dev/null)" = "#!" ]; then
        chmod +x "$f" 2>/dev/null || true
    fi
done

# 0.5 Скопировать me.conf в ~/.config/me/ (не затирать существующий)
#     ДО под-инсталляторов — иначе gifx/scr/yfe создадут урезанный me.conf
mkdir -p "$CONFIG_DEST"
if [ ! -f "$CONFIG_DEST/me.conf" ]; then
    if [ -f "me.conf" ]; then
        cp me.conf "$CONFIG_DEST/me.conf"
    else
        cp "$ME_DIR/me.conf" "$CONFIG_DEST/me.conf"
    fi
    echo "[me] me.conf скопирован в $CONFIG_DEST/"
else
    echo "[me] $CONFIG_DEST/me.conf уже существует — пропускаем"
fi

# Запуск под-инсталлятора: сначала корень me/, затем me_lib/
run_installer() {
    local name="$1"
    if [ -x "$ME_DIR/$name" ]; then
        "$ME_DIR/$name"
    elif [ -x "$ME_DIR/me_lib/$name" ]; then
        "$ME_DIR/me_lib/$name"
    else
        echo "[me] Ошибка: инсталлятор $name не найден (ни в $ME_DIR, ни в $ME_DIR/me_lib)" >&2
        return 1
    fi
}

run_installer gifx_install.sh
run_installer scr_install.sh
run_installer install_yfe.sh

# Привилегии: поднимаем sudo только в момент реальной установки пакета
priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        echo "[me] Установка пакета требует прав root" >&2
        sudo "$@"
    fi
}

# 1. Добавить me в PATH и комплишн через ~/.bashrc
if ! grep -q "me:\$PATH" "$HOME/.bashrc" 2>/dev/null; then
    echo "export PATH=\"$ME_DIR:\$PATH\"" >> "$HOME/.bashrc"
    echo "[me] PATH добавлен в ~/.bashrc"
else
    echo "[me] PATH уже прописан в ~/.bashrc"
fi

if [ -f "$ME_DIR/me_lib/me.completion" ] && ! grep -q "me_lib/me.completion" "$HOME/.bashrc" 2>/dev/null; then
    echo "source \"$ME_DIR/me_lib/me.completion\"" >> "$HOME/.bashrc"
    echo "[me] Автокомплит добавлен в ~/.bashrc"
    source "$ME_DIR/me_lib/me.completion" 2>/dev/null && echo "[me] Автокомплит активирован"
fi

# Применить bashrc в текущей сессии
source "$HOME/.bashrc" 2>/dev/null || true

# 2. Добавить me в PATH через ~/.profile
if ! grep -q "me:\$PATH" "$HOME/.profile" 2>/dev/null; then
    echo "export PATH=\"$ME_DIR:\$PATH\"" >> "$HOME/.profile"
    echo "[me] PATH добавлен в ~/.profile"
else
    echo "[me] PATH уже прописан в ~/.profile"
fi

# Применить profile в текущей сессии
echo " необходимо вручную в терминале выполнить <source "\$HOME/.profile">"

# 4. Установка зависимостей (ripgrep для me fi)
if ! command -v rg &>/dev/null; then
    echo "[me] Устанавливаю ripgrep..."
if command -v apt-get &>/dev/null; then
        priv apt-get install -y -qq ripgrep && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    elif command -v pacman &>/dev/null; then
        priv pacman -S --noconfirm ripgrep 2>/dev/null && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    elif command -v apk &>/dev/null; then
        priv apk add ripgrep 2>/dev/null && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    else
        echo "[me] Предупреждение: неизвестный пакетный менеджер, установи ripgrep вручную"
    fi
else
    echo "[me] ripgrep уже установлен"
fi

echo "[me] Установка завершена."
echo "[me] Проверка: $(which me)"
