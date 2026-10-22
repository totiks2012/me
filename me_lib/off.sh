#!/usr/bin/env bash
# me off — остановка активного пользовательского сервиса systemd (--user)
[ -z "$1" ] && { echo "Какой сервис остановить?" >&2; exit 1; }
exec systemctl --user stop "$@"
