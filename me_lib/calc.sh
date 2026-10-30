#!/bin/bash
#true_method
#@method: calc
#@description: Универсальный калькулятор. Поддерживает арифметику, степени, корни, тригонометрию (sin, cos, tan, atan), логарифмы (log, log10), константы pi и e, а также переменные окружения. Формулы пишутся в привычной инфиксной нотации.
#@example: I="$(calc "(P * 1000) / (sqrt(3) * U * 0.7)")" ; A="$(calc "(2+4)/3")" 
calc() {
    local expr="$*"

    # Замена по границам токена (GNU sed -E). from/to без /, \, &.
    replace_token() {
        local s="$1" from="$2" to="$3"
        printf '%s' "$s" | sed -E "s/(^|[^A-Za-z0-9_])${from}([^A-Za-z0-9_]|$)/\1${to}\2/g"
    }

    # Порядок строго: длинные имена первыми (log10 до log, atan до tan);
    # e -> числовая константа (не exp(1)): exp(1) содержит e и ломает замену.
    # Регистрозависимо: ATAN не заменяется (известное ограничение).
    # asin/acos НЕ поддерживаются: их нет в bc -l (проверено фактом) — честная ошибка bc.
    expr=$(replace_token "$expr" "log10" "l10")
    expr=$(replace_token "$expr" "log"   "l")
    expr=$(replace_token "$expr" "atan"  "a")
    expr=$(replace_token "$expr" "sin"   "s")
    expr=$(replace_token "$expr" "cos"   "c")
    expr=$(replace_token "$expr" "tan"   "t")
    expr=$(replace_token "$expr" "pi"    "4*a(1)")
    expr=$(replace_token "$expr" "e"     "2.718281828459045")

    # Подстановка переменных окружения: только целые токены, длинные первыми.
    # Незаданные переменные не подставляются. ВНИМАНИЕ: bc 1.07.1 молча трактует
    # заглавные буквы как цифры (A=10..Z=35), так что незаданный P даст число,
    # а НЕ "undefined" — тихий мусор. Это не чинится здесь (см. SEED).
    if [[ "$expr" =~ [A-Z_] ]]; then
        local var
        while IFS= read -r var; do
            [ -n "$var" ] && [ -n "${!var:-}" ] && expr=$(replace_token "$expr" "$var" "${!var}")
        done < <(
            printf '%s' "$expr" \
            | grep -oE '\b[A-Z_][A-Z0-9_]*\b' \
            | sort -u \
            | awk '{ print length, $0 }' \
            | sort -rn \
            | cut -d' ' -f2-
        )
    fi

    # log10 нет в bc 1.07.1 (проверено фактом) — l10 определяется через ln(x)/ln(10).
    echo "define l10(x) { return l(x)/l(10); }; scale=10; $expr" | bc -l
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    calc "$@"
fi
