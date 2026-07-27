#!/usr/bin/env bash
cmd="$*"
method=$(echo "$cmd" | awk '{print $2}')
[ -z "$method" ] && exit
CONF_FILE="$HOME/.config/me/me.conf"
tmpf=$(mktemp /tmp/me_help_XXXXXX 2>/dev/null) || exit
trap 'rm -f "$tmpf"' EXIT
awk -v m="$method" '
    $1 == "#@method:" && $2 == m { f = 1; next }
    f && /^#@description:/ { sub(/^#@description:[ \t]*/, ""); printf "  %s\n\n", $0; next }
    f && /^#@example:/ { sub(/^#@example:[ \t]*/, ""); printf "  Пример: %s\n", $0; exit }
' "$CONF_FILE" > "$tmpf"
[ -s "$tmpf" ] && micro "$tmpf"
