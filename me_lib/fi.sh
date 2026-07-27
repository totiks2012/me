#!/usr/bin/env bash
# fi.sh – Универсальный поиск файлов и контекста по системе
#   fi -c "контекст" [путь] [фильтр]
#   fi -s "имя" [путь]

usage() {
    echo "Использование:"
    echo "  fi -c 'контекст' [путь] [фильтр_имени]  — поиск по содержимому"
    echo "  fi -s 'имя' [путь]                      — поиск по имени"
    exit 1
}

case "$1" in
    -c)
        shift
        context="$1"
        [ -z "$context" ] && usage
        shift

        path="${1:-/}"
        [ -d "$path" ] || path="/"

        filename_filter="${*:2}"

        if [ -n "$filename_filter" ]; then
            rg -l -i "$context" "$path" 2>/dev/null | grep -i "$filename_filter"
        else
            rg -l -i "$context" "$path" 2>/dev/null
        fi | fzf --reverse \
            --header="Контекст: '$context' | Путь: $path | Enter — micro" \
            --preview="rg --color=always -n -C 5 -i '$context' {} 2>/dev/null" \
            --preview-window='right:60%:wrap' \
            --bind="enter:execute(micro +\$(rg -n -i '$context' {} 2>/dev/null | head -1 | cut -d: -f1) {})"
        ;;
    -s)
        shift
        name="$1"
        [ -z "$name" ] && usage
        shift

        path="${1:-/}"
        [ -d "$path" ] || path="/"

        find "$path" -name "*$name*" \
            -not -path '*/proc/*' -not -path '*/sys/*' \
            -not -path '*/dev/*' -not -path '*/run/*' \
            -not -path '*/tmp/*' -not -path '*/var/cache/*' \
            2>/dev/null | fzf --reverse \
            --header="Имя: '$name' | Путь: $path | Enter — открыть" \
            --preview='file -b {}' \
            --preview-window='right:40%' \
            --bind="enter:execute(
                if file {} | grep -qi 'script\|text\|ascii\|shell script'; then
                    micro {}
                else
                    thunar \$(dirname {}) 2>/dev/null || ls -la \$(dirname {})
                fi
            )"
        ;;
    *)
        usage
        ;;
esac
