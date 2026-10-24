#!/usr/bin/env bash
#true_method
# me restart — безопасная перезагрузка через systemctl
notify-send -i system-reboot -t 3000 "Перезагрузка" "Система уходит на перезапуск..." 2>/dev/null || true
echo "Перезагрузка..."
sleep 0.5
exec /usr/bin/systemctl reboot
