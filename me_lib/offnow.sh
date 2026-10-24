#!/usr/bin/env bash
#true_method
# me offnow — корректное и быстрое выключение через systemctl
notify-send -i system-shutdown -t 3000 "Выключение" "Завершение работы операционной системы..." 2>/dev/null || true
echo "Выключение..."
sleep 0.5
exec /usr/bin/systemctl poweroff
