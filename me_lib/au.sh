#!/usr/bin/env bash
#true_method
# au.sh — CLI-менеджер автозапуска: список автозапуска + добавление бинарников
# Навигация (стек экранов):
#   root → «В автозапуске» → действие
#   root → «Найти бинарник и добавить» → подтверждение создания
#   Esc — назад на предыдущий экран; на корневом меню Esc — выход из программы.

AUTOSTART_DIR="$HOME/.config/autostart"
BIN_PATHS=(/usr/bin /usr/local/bin "$HOME/.local/bin")

die() {
    notify-send -i dialog-error -t 3000 "au" "$1" 2>/dev/null || true
    echo "au: Ошибка: $1" >&2
    exit 1
}

notify() {
    notify-send -i dialog-information -t 2500 "au" "$1" 2>/dev/null || true
}

command -v fzf >/dev/null 2>&1 || die "требуется fzf"
mkdir -p "$AUTOSTART_DIR" || die "не удалось создать $AUTOSTART_DIR"

screen="root"

while :; do
    case "$screen" in

    # --- Корневое меню -------------------------------------------------
    root)
        mode=$(printf 'В автозапуске\nНайти бинарник и добавить\n' \
            | fzf --reverse --no-multi \
                  --header='me au — менеджер автозапуска (Enter — выбрать, Esc — выход)')
        [ -z "$mode" ] && exit 0
        case "$mode" in
            "В автозапуске") screen="list" ;;
            *)               screen="bins" ;;
        esac
        ;;

    # --- Список того, что уже в автозапуске -----------------------------
    list)
        desktop=$(find "$AUTOSTART_DIR" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null \
            | sort \
            | while IFS= read -r f; do
                name=$(sed -n 's/^Name=//p' "$f" | head -1)
                [ -z "$name" ] && name=$(sed -n 's/^Name\[.*\]=//p' "$f" | head -1)
                [ -z "$name" ] && name=$(basename "$f")
                printf '%s\t%s\n' "$name" "$f"
            done \
            | fzf --reverse --no-multi \
                  --delimiter=$'\t' --with-nth=1 \
                  --header='В автозапуске (Enter — действие, Esc — назад)' \
                  --preview='sed -n "1,40p" {2}' \
                  --preview-window='right:60%:wrap')
        [ -z "$desktop" ] && { screen="root"; continue; }

        file="${desktop#*$'\t'}"

        state="enabled"
        if [ "$(sed -n 's/^Hidden=//p' "$file" | head -1)" = "true" ]; then
            state="disabled"
        elif [ "$(sed -n 's/^X-GNOME-Autostart-enabled=//p' "$file" | head -1)" = "false" ]; then
            state="disabled"
        fi
        case "$state" in
            disabled) toggle="Включить автозапуск" ;;
            *)        toggle="Отключить автозапуск" ;;
        esac

        action=$(printf 'Удалить из автозапуска\n%s\nОткрыть в редакторе\nПоказать содержимое\n' "$toggle" \
            | fzf --reverse --no-multi --header="$(basename "$file") — действие (Esc — назад)")
        [ -z "$action" ] && { screen="list"; continue; }

        case "$action" in
            Удалить*)
                echo -n "Удалить ${file}? [y/N] " >&2
                read -r an
                [[ "$an" =~ ^[yY] ]] || { screen="list"; continue; }
                rm -f "$file" && notify "Удалено: $(basename "$file")" \
                    || die "не удалось удалить $file"
                ;;
            Включить*|Отключить*)
                if [ "$action" = "Включить автозапуск" ]; then
                    hidden_new="false"
                    gnome_new="true"
                else
                    hidden_new="true"
                    gnome_new="false"
                fi
                if grep -q '^Hidden=' "$file"; then
                    sed -i "s/^Hidden=.*/Hidden=$hidden_new/" "$file"
                else
                    printf 'Hidden=%s\n' "$hidden_new" >> "$file"
                fi
                if grep -q '^X-GNOME-Autostart-enabled=' "$file"; then
                    sed -i "s/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=$gnome_new/" "$file"
                else
                    printf 'X-GNOME-Autostart-enabled=%s\n' "$gnome_new" >> "$file"
                fi
                notify "Автозапуск: $( [ "$gnome_new" = "true" ] && echo включён || echo отключён) ($(basename "$file"))"
                ;;
            Открыть*)
                ${EDITOR:-nano} "$file"
                ;;
            Показать*)
                sed -n '1,40p' "$file"
                ;;
            *)
                continue
                ;;
        esac
        screen="list"
        ;;

    # --- Поиск бинарника/скрипта и добавление в автозапуск ---------------
    bins)
        bin=$( { for p in "${BIN_PATHS[@]}"; do
                     [ -d "$p" ] && find "$p" -xdev \( -type f -o -type l \) -executable -printf '%p\n' 2>/dev/null
                 done; } \
            | sort -u \
            | fzf --reverse --no-multi \
                  --header='Бинарники и скрипты (рекурсивно: /usr/bin, /usr/local/bin, ~/.local/bin; Esc — назад)' \
                  --preview='p={}; if file -b "$p" 2>/dev/null | grep -q script; then echo "скрипт"; else echo "бинарник"; fi; echo "---"; ls -la "$p" 2>/dev/null' \
                  --preview-window='right:50%:wrap')
        [ -z "$bin" ] && { screen="root"; continue; }

        name=$(basename "$bin")
        safe_name=$(printf '%s' "$name" | tr ' /' '__')
        desktop_file="$AUTOSTART_DIR/$safe_name.desktop"

        if [ -e "$desktop_file" ]; then
            echo -n "$desktop_file уже существует. Перезаписать? [y/N] " >&2
            read -r an
            [[ "$an" =~ ^[yY] ]] || { screen="bins"; continue; }
        fi

        if [[ "$bin" == *" "* ]]; then
            exec_line="Exec=\"$bin\""
        else
            exec_line="Exec=$bin"
        fi

        {
            printf '[Desktop Entry]\n'
            printf 'Type=Application\n'
            printf 'Name=%s\n' "$name"
            printf 'Comment=Запуск %s при входе в систему\n' "$name"
            printf '%s\n' "$exec_line"
            printf 'Terminal=false\n'
            printf 'NoDisplay=false\n'
            printf 'X-GNOME-Autostart-enabled=true\n'
        } > "$desktop_file" || die "не удалось записать $desktop_file"

        notify "Добавлено в автозапуск: $name"
        echo "Создан: $desktop_file"
        screen="bins"
        ;;

    esac
done
