#!/bin/bash
#@method: calc
#@description: Универсальный калькулятор. Поддерживает арифметику, степени, корни, тригонометрию (sin, cos, tan, atan), логарифмы (log, log10), константы pi и e, а также переменные окружения. Формулы пишутся в привычной инфиксной нотации.
#@example: I="$(calc "(P * 1000) / (sqrt(3) * U * 0.7)")" ; A="$(calc "(2+4)/3")" 
calc() {
    local expr="$*"
    
    # Замена человеческих функций на bc-совместимые
    expr="${expr//sin/s}"
    expr="${expr//cos/c}"
    expr="${expr//tan/t}"
    expr="${expr//atan/a}"
    expr="${expr//asin/asin}"
    expr="${expr//acos/acos}"
    expr="${expr//atan/atan}"
    expr="${expr//sqrt/sqrt}"
    expr="${expr//log/l}"           # натуральный логарифм
    expr="${expr//log10/l10}"       # десятичный логарифм
    expr="${expr//pi/4*a(1)}"       # pi = 4*arctan(1)
    expr="${expr//e/exp(1)}"        # e
    
    # Подстановка переменных из окружения
    if [[ "$expr" =~ [A-Z_]+ ]]; then
        for var in $(echo "$expr" | grep -oE '\b[A-Z_]+\b'); do
            if [[ -n "${!var}" ]]; then
                expr="${expr//$var/${!var}}"
            fi
        done
    fi
    
    echo "scale=10; $expr" | bc -l
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    calc "$@"
fi