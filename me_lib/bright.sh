#!/usr/bin/env bash
# me bright — яркость экрана с верификацией через D-Bus интерфейсы
case "$1" in
    up)
        if busctl --user call org.xfce.PowerManager /org/xfce/PowerManager org.xfce.Power.Backlight IncreaseBrightness 2>/dev/null || \
           busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Screen StepUp 2>/dev/null; then
            notify-send -i display-brightness -t 1500 "Экран" "Яркость увеличена" 2>/dev/null || true
            echo "Яркость увеличена"
        else
            notify-send -i dialog-error -t 2000 "Ошибка" "Менеджер питания D-Bus не отвечает" 2>/dev/null || true
            echo "[me] Ошибка: Окружение не поддерживает управление подсветкой." >&2
        fi
        ;;
    down)
        if busctl --user call org.xfce.PowerManager /org/xfce/PowerManager org.xfce.Power.Backlight DecreaseBrightness 2>/dev/null || \
           busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Screen StepDown 2>/dev/null; then
            notify-send -i display-brightness -t 1500 "Экран" "Яркость уменьшена" 2>/dev/null || true
            echo "Яркость уменьшена"
        else
            notify-send -i dialog-error -t 2000 "Ошибка" "Менеджер питания D-Bus не отвечает" 2>/dev/null || true
            echo "[me] Ошибка: Окружение не поддерживает управление подсветкой." >&2
        fi
        ;;
    *)
        echo "Используй: me bright [up|down]" >&2
        exit 1
        ;;
esac
