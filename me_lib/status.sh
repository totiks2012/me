#!/usr/bin/env bash
# me status — статус пользовательских сервисов: всех активных или конкретного
if [ -z "$1" ]; then
    systemctl --user list-units --type=service --state=running
else
    systemctl --user status "$@"
fi
