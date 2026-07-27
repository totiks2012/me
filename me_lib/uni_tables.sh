#!/bin/bash
#@method: uni_tables
#@description: Универсальный вывод форматированных таблиц. Автоматически рассчитывает ширину колонок и сохраняет цвета color.sh.
#@example: uni_tables "Параметр" "Значение" ; uni_tables "---" "---" ; uni_tables "Ток двигателя" "$(green '14.2 A')"
# uni_tables "---" Это Команда отрисовки , без нее в конце выключается вывод таблицы
uni_tables_reset() {
    _UNI_TABLE_RECORDS=""
}

uni_tables() {
    [ $# -eq 0 ] && return 0

    if [ "$1" != "---" ]; then
        local row=""
        for arg in "$@"; do
            local clean="$arg"
            row="${row}${clean}"$'\t'
        done
        _UNI_TABLE_RECORDS+="${row%$'\t'}"$'\n'
        return 0
    fi

    [ -z "$_UNI_TABLE_RECORDS" ] && return 0

    # Убираем хвостовой перевод строки, чтобы не плодить пустые строки
    _UNI_TABLE_RECORDS="${_UNI_TABLE_RECORDS%$'\n'}"

    # Разбираем строки на колонки
    local columns=()
    local max_widths=()
    
    # Первый проход: определяем количество колонок и максимальную ширину каждой
    while IFS=$'\t' read -ra fields; do
        for i in "${!fields[@]}"; do
            # Удаляем ANSI для подсчета ширины
            local clean_field=$(printf '%s' "${fields[$i]}" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g')
            local len=${#clean_field}
            
            if [ -z "${max_widths[$i]}" ] || [ $len -gt ${max_widths[$i]} ]; then
                max_widths[$i]=$len
            fi
        done
    done <<< "$_UNI_TABLE_RECORDS"
    
    # Строим рамку
    local border="+"
    for width in "${max_widths[@]}"; do
        border+=$(printf '%*s' "$((width + 2))" '' | tr ' ' '-')
        border+="+"
    done
    
    # Вывод таблицы
    local total_lines=$(echo "$_UNI_TABLE_RECORDS" | wc -l)
    echo "$border"
    local line_num=0
    while IFS=$'\t' read -ra fields; do
        printf '|'
        for i in "${!fields[@]}"; do
            local clean_field=$(printf '%s' "${fields[$i]}" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g')
            local visible_len=${#clean_field}
            local padding=$((max_widths[$i] - visible_len))
            printf ' %s%*s |' "${fields[$i]}" "$padding" ''
        done
        printf '\n'
        
        line_num=$((line_num + 1))
        [ $line_num -eq 1 ] && [ $total_lines -gt 1 ] && echo "$border"
    done <<< "$_UNI_TABLE_RECORDS"
    echo "$border"
    
    uni_tables_reset
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Собираем все строки, "---" разделяет ряды, в конце — один рендер
    row=()
    for arg in "$@"; do
        if [ "$arg" = "---" ]; then
            if [ ${#row[@]} -gt 0 ]; then
                uni_tables "${row[@]}"
            fi
            row=()
        else
            row+=("$arg")
        fi
    done
    if [ ${#row[@]} -gt 0 ]; then
        uni_tables "${row[@]}"
    fi
    uni_tables "---"
fi