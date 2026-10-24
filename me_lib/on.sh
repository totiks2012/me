#!/usr/bin/env bash
#true_method
# me on — запуск фонового пользовательского сервиса systemd (--user)
[ -z "$1" ] && { echo "Какой сервис запустить?" >&2; exit 1; }
exec systemctl --user start "$@"
