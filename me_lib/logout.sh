#!/usr/bin/env bash
#true_method
# me logout — немедленный выход из сессии через loginctl
notify-send -i system-log-out -t 3000 "Завершение сессии" "Выход пользователя $USER..." 2>/dev/null || true
echo "Выход из сеанса..."
sleep 0.5
exec /usr/bin/loginctl terminate-user "$USER"
