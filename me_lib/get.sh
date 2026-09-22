#!/usr/bin/env bash
# get.sh — fzf-выбор txt с URL в текущем каталоге, последовательное скачивание wget
# Использование: get.sh   (env GET_FILE для неинтерактивного выбора файла)

die() { echo "[get] $*" >&2; exit 1; }

command -v fzf &>/dev/null || die "Требуется fzf"
command -v wget &>/dev/null || die "Требуется wget"

CWD="$PWD"

# Выбор txt-файла в текущем каталоге
if [ -n "$GET_FILE" ]; then
    FILE="$GET_FILE"
else
    shopt -s nullglob
    TXT_LIST=("$CWD"/*.txt)
    if [ "${#TXT_LIST[@]}" -eq 0 ]; then
        die "В каталоге $CWD нет *.txt файлов"
    fi
    FILE=$(printf '%s\n' "${TXT_LIST[@]}" | fzf --height=40% --header="Выбери txt с URL (каталог: $CWD)")
fi

[ -f "$FILE" ] || die "Файл не найден: $FILE"

# Извлекаем только http(s)-ссылки
URLS=$(grep -oE 'https?://[^[:space:]]+' "$FILE" 2>/dev/null | sort -u)
[ -z "$URLS" ] && die "В $FILE нет http(s) ссылок"

COUNT=$(printf '%s\n' "$URLS" | grep -c .)
echo "[get] Файл: $FILE"
echo "[get] Найдено URL: $COUNT"
echo "[get] Скачиваю в: $CWD"

cd "$CWD" || die "Не могу войти в $CWD"

n=0
while IFS= read -r url; do
    n=$((n + 1))
    echo "[get] ($n/$COUNT) $url"
    wget -c --show-progress "$url" || echo "[get] ! Ошибка: $url" >&2
done <<< "$URLS"

echo "[get] Готово: $COUNT ссылок обработано"