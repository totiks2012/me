#!/usr/bin/env bash
# id.sh – Менеджер заметок: сохранение, fzf --reverse с превью справа

mkdir -p "$HOME/.local/bin/me/my_ideas"
NOTES_DIR="$HOME/.local/bin/me/my_ideas"
NOTES_FILE="$NOTES_DIR/ideas.txt"

mkdir -p "$NOTES_DIR"
touch "$NOTES_FILE"

case "$1" in
    -s)
        shift
        if [ -z "$1" ]; then
            echo "Ошибка: Текст идеи пуст." >&2
            exit 1
        fi

        title="$1"
        shift
        if [ -n "$1" ]; then
            body="$*"
        else
            body="$title"
        fi

        echo "$(date '+%Y-%m-%d %H:%M') | $title"$'\t'"$body" >> "$NOTES_FILE"
        echo "---" >> "$NOTES_FILE"
        notify-send -i dialog-information -t 1500 "Заметки" "Идея успешно сохранена" 2>/dev/null || true
        ;;
    -r)
        if [ ! -s "$NOTES_FILE" ]; then
            echo "Список идей пока пуст."
            exit 0
        fi

        grep -v '^---$' "$NOTES_FILE" | fzf --reverse \
            --header="Выберите идею (Esc — выход)" \
            --delimiter=$'\t' \
            --with-nth=1 \
            --preview='cut -f2- <<< {} | fold -s -w $((FZF_PREVIEW_COLUMNS - 2))' \
            --preview-window='right:55%:wrap'
        ;;
    *)
        echo "Использование: id.sh -s 'заголовок' 'тело' | id.sh -r" >&2
        exit 1
        ;;
esac
