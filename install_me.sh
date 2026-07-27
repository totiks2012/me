#!/usr/bin/env bash
set -euo pipefail

$HOME/.local/bin/me/gifx_install.sh
$HOME/.local/bin/me/scr_install.sh

ME_DIR="$HOME/.local/bin/me"
CONFIG_DEST="$HOME/.config/me"

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

# 3. Скопировать me.conf в ~/.config/me/ (не затирать существующий)
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

# 4. Установка зависимостей (ripgrep для me fi)
if ! command -v rg &>/dev/null; then
    echo "[me] Устанавливаю ripgrep..."
    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq ripgrep 2>/dev/null && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm ripgrep 2>/dev/null && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    elif command -v apk &>/dev/null; then
        apk add ripgrep 2>/dev/null && echo "[me] ripgrep установлен" || echo "[me] Предупреждение: не удалось установить ripgrep"
    else
        echo "[me] Предупреждение: неизвестный пакетный менеджер, установи ripgrep вручную"
    fi
else
    echo "[me] ripgrep уже установлен"
fi

echo "[me] Установка завершена."
echo "[me] Проверка: $(which me)"
