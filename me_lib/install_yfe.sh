#!/usr/bin/env bash
# install_yfe.sh — Установка/регистрация me yfe

YFE_SRC="$HOME/.local/bin/me/me_lib/yfe.sh"
YFE_CRON="$HOME/.local/bin/me/me_lib/yfe-cron.sh"
ME_CONF="$HOME/.config/me/me.conf"
YFE_CONF="$HOME/.config/me/yfe.conf"

echo ">>> Установка me yfe..."

# 1. Проверка наличия yfe.sh
if [ ! -f "$YFE_SRC" ]; then
    echo "[install_yfe] Ошибка: $YFE_SRC не найден" >&2
    exit 1
fi
chmod +x "$YFE_SRC"
chmod +x "$YFE_CRON" 2>/dev/null

# 2. Регистрация метода в me.conf
if grep -q "^me_method_yfe()" "$ME_CONF" 2>/dev/null; then
    echo "[install_yfe] Метод yfe уже зарегистрирован"
else
    cat >> "$ME_CONF" << 'EOF'

#@method: yfe
#@description: YouTube RSS Feed Explorer — фиды → fzf → mpv (кэш 30 мин)
#@example: me yfe ; me yfe -u ; me yfe -r
#@variants:
#   me yfe     # Выбрать видео и запустить в mpv
#   me yfe -u  # Только вывод URL (для пайпа)
#   me yfe -r  # Принудительно обновить кэш
me_method_yfe() {
    local script_path="$HOME/.local/bin/me/me_lib/yfe.sh"
    if [ -x "$script_path" ]; then
        "$script_path" "$@"
    else
        notify-send -i dialog-error -t 3000 "Ошибка пульта" "yfe.sh не найден" 2>/dev/null || true
        echo "[me] Ошибка: Файл $script_path не найден или не имеет прав +x." >&2
        return 1
    fi
}
EOF
    echo "[install_yfe] Метод yfe зарегистрирован"
fi

# 3. Создание yfe.conf по умолчанию
if [ ! -f "$YFE_CONF" ]; then
    cat > "$YFE_CONF" << 'EOF'
# YouTube RSS подписки для me yfe
# Категория: [Название категории]
# Формат: Название|URL

[Технологии]
Google for Developers|https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw
EOF
    echo "[install_yfe] Создан конфиг: $YFE_CONF"
fi

# 4. Cron: обновление каждый час без mpv
if crontab -l 2>/dev/null | grep -q "yfe-cron"; then
    echo "[install_yfe] Cron уже настроен"
else
    (crontab -l 2>/dev/null; echo "0 * * * * $YFE_CRON") | crontab -
    echo "[install_yfe] Cron: обновление каждый час (без mpv)"
fi

# 5. mpv: лимит 720p
MPV_CONF="$HOME/.config/mpv/mpv.conf"
if [ ! -f "$MPV_CONF" ]; then
    mkdir -p "$(dirname "$MPV_CONF")"
    echo 'ytdl-format=bestvideo[height<=720]+bestaudio/best[height<=720]' > "$MPV_CONF"
    echo "[install_yfe] Создан $MPV_CONF (720p лимит)"
elif ! grep -q "ytdl-format" "$MPV_CONF" 2>/dev/null; then
    echo 'ytdl-format=bestvideo[height<=720]+bestaudio/best[height<=720]' >> "$MPV_CONF"
    echo "[install_yfe] Добавлен 720p лимит в $MPV_CONF"
else
    echo "[install_yfe] mpv.conf уже настроен"
fi

# 6. Зависимости
DEPS="curl sfeed fzf mpv"
for dep in $DEPS; do
    command -v "$dep" &>/dev/null || echo "[install_yfe] Нет: $dep" >&2
done

echo ">>> Готово. me yfe"
