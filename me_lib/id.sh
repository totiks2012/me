#!/usr/bin/env bash
#true_method
# id.sh – Менеджер заметок: сохранение, fzf-выбор с диалогом действий, список

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
        if [ -n "$*" ]; then
            body="$*"
        else
            body="$title"
        fi

        # Защита формата «одна запись = одна строка»: режем переносы и табы
        title=$(printf '%s' "$title" | tr '\t' ' ' | tr -d '\n')
        body=$(printf '%s' "$body" | tr '\t' ' ' | tr -d '\n')
        [ -z "$title" ] && { echo "Ошибка: Текст идеи пуст." >&2; exit 1; }

        echo "$(date '+%Y-%m-%d %H:%M') | $title"$'\t'"$body" >> "$NOTES_FILE"
        echo "---" >> "$NOTES_FILE"
        notify-send -i dialog-information -t 1500 "Заметки" "Идея успешно сохранена" 2>/dev/null || true
        ;;
    -r)
        if [ ! -s "$NOTES_FILE" ]; then
            echo "Список идей пока пуст."
            exit 0
        fi

        chosen=$(grep -v '^---$' "$NOTES_FILE" | fzf --reverse \
            --header="Выберите заметку (Enter — действие, Esc — выход)" \
            --delimiter=$'\t' \
            --with-nth=1 \
            --nth=1,2 \
            --preview='cut -f2- <<< {} | fold -s -w $((FZF_PREVIEW_COLUMNS - 2))' \
            --preview-window='right:55%:wrap')
        [ -z "$chosen" ] && exit 0

        action=$(printf 'Копировать в буфер\nРедактировать в micro\nВывести полный текст\nУдалить заметку\n' | fzf --reverse \
            --header="Заметка: ${chosen%%$'\t'*} — действие")

        case "$action" in
            Копировать*)
                if command -v xclip >/dev/null 2>&1; then
                    printf '%s' "$chosen" | xclip -selection clipboard
                    echo "Заметка скопирована в буфер (xclip)." >&2
                elif command -v wl-copy >/dev/null 2>&1; then
                    printf '%s' "$chosen" | wl-copy
                    echo "Заметка скопирована в буфер (wl-copy)." >&2
                else
                    echo "Ошибка: нет xclip/wl-copy для буфера обмена." >&2
                    printf '%s\n' "$chosen"
                fi
                ;;
            Редактировать*)
                idx=$(grep -v '^---$' "$NOTES_FILE" | grep -nF "$chosen" | head -1 | cut -d: -f1)
                line=$((idx * 2 - 1))
                if command -v micro >/dev/null 2>&1; then
                    micro "+$line" "$NOTES_FILE"
                else
                    "${EDITOR:-vi}" "$NOTES_FILE"
                fi
                ;;
            Вывести*)
                printf '%s\n' "$chosen"
                ;;
            Удалить*)
                echo -n "Удалить заметку? [y/N] " >&2
                read -r an
                [[ "$an" =~ ^[yY] ]] || exit 0
                if awk -v del="$chosen" '
                    $0 == del { skip=1; next }
                    skip && $0 == "---" { skip=0; next }
                    { print }
                ' "$NOTES_FILE" > "$NOTES_FILE.tmp.$$" && mv "$NOTES_FILE.tmp.$$" "$NOTES_FILE"; then
                    echo "Заметка удалена." >&2
                else
                    rm -f "$NOTES_FILE.tmp.$$"
                    echo "Ошибка удаления." >&2
                    exit 1
                fi
                ;;
            "")
                exit 0
                ;;
            *)
                echo "Действие не распознано: $action" >&2
                exit 1
                ;;
        esac
        ;;
    -l)
        grep -v '^---$' "$NOTES_FILE"
        ;;
    *)
        echo "Использование: id.sh -s 'заголовок' ['тело'] | id.sh -r | id.sh -l" >&2
        exit 1
        ;;
esac