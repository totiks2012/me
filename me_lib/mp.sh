#!/usr/bin/env bash
#true_method
# mp.sh — универсальная обёртка над пакетными менеджерами (apt/dnf/pacman)
# Вызывается методом `me mp`. Пакетный менеджер определяется при первом запуске
# и запоминается в ~/.cache/me/mp.pm, чтобы не проверять заново.
set -u

STATE="$HOME/.cache/me/mp.pm"
PAM4="/root/.local/bin/pam4/pam4.sh"

usage() {
    cat <<'EOF'
Использование: me mp -<опция> [аргументы]

Пакетный менеджер определяется автоматически при первом вызове (apt/dnf/pacman)
и запоминается, чтобы не проверять заново. Сброс и переопределение: me mp -pm reset

  -l [пакет]   список пакетов (без имени — установленные)
  -lu          список пакетов, доступных к обновлению
  -s <запрос>  поиск пакетов
  -S <пакет>   информация о пакете
  -i <пакет>   установить пакет
  -r <пакет>   переустановить пакет
  -d <пакет>   удалить пакет
  -a           удалить неиспользуемые пакеты (autoremove)
  -u           обновить список доступных пакетов
  -U           обновить установленные пакеты
  -UD          полное обновление (dist-upgrade)
  -es          редактировать источники/репозитории
  -ms          конвертация .list → .sources (только apt)
  -sat <зав.>  удовлетворить строки зависимостей (только apt)
  -pam         запустить pam4 (AppImage-менеджер)
  -pm [reset]  показать текущий ПМ / сбросить и переопределить
  -h, --help   эта справка
EOF
    [ -n "${PM:-}" ] && echo "Текущий менеджер пакетов: $PM ($STATE)"
}

# Выполнение с привилегиями: sudo, если текущий пользователь не root
PRIV() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        printf '>>> %s\n' "$*" >&2
        sudo "$@"
    else
        echo "Ошибка: требуются права root, а sudo не найден." >&2
        return 1
    fi
}

# Проверка наличия аргумента у операции
need_arg() {
    local n="$1"
    shift
    if [ "$n" -eq 0 ]; then
        echo "Ошибка: $* — аргумент обязателен." >&2
        usage >&2
        exit 1
    fi
}

# Определение пакетного менеджера по наличию бинарника (приоритет pacman > dnf > apt)
detect_pm() {
    if command -v pacman >/dev/null 2>&1; then
        echo pacman
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    else
        return 1
    fi
}

# Загрузка ПМ: из кэша или новый детект с сохранением
load_pm() {
    if [ -s "$STATE" ]; then
        PM="$(tr -d '[:space:]' < "$STATE")"
        case "$PM" in
            apt|dnf|pacman) return 0 ;;
        esac
        PM=""
    fi

    if ! PM="$(detect_pm)"; then
        echo "Ошибка: не удалось определить пакетный менеджер (нет apt/dnf/pacman)." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$PM" > "$STATE"
    echo "Определён пакетный менеджер: $PM (запомнен в $STATE)" >&2
}

op="${1:-}"
shift 2>/dev/null || true

# Опции, не требующие определения ПМ
case "$op" in
    -h|--help|"")
        usage
        exit 0
        ;;
    -pam)
        if [ -x "$PAM4" ]; then
            exec "$PAM4"
        else
            echo "Ошибка: $PAM4 не найден или не исполняемый." >&2
            exit 1
        fi
        ;;
esac

load_pm

case "$op" in
    -l)
        case "$PM" in
            apt)    [ "$#" -eq 0 ] && apt list --installed || apt list "$@" ;;
            dnf)    [ "$#" -eq 0 ] && dnf list --installed || dnf list "$@" ;;
            pacman) [ "$#" -eq 0 ] && pacman -Q || pacman -Sl "$@" ;;
        esac
        ;;
-lu)
        case "$PM" in
            apt)    apt list --upgradable ;;
            dnf)    dnf list --upgradable ;;
            pacman) pacman -Qu ;;
        esac
        ;;
    -s)
        need_arg "$#" "поиск (-s)"
        case "$PM" in
            apt)    apt search "$@" ;;
            dnf)    dnf search "$@" ;;
            pacman) pacman -Ss "$@" ;;
        esac
        ;;
    -S)
        need_arg "$#" "просмотр (-S)"
        case "$PM" in
            apt)    apt show "$@" ;;
            dnf)    dnf info "$@" ;;
            pacman) pacman -Si "$@" ;;
        esac
        ;;
    -i)
        need_arg "$#" "установка (-i)"
        case "$PM" in
            apt)    PRIV apt install "$@" ;;
            dnf)    PRIV dnf install "$@" ;;
            pacman) PRIV pacman -S "$@" ;;
        esac
        ;;
    -r)
        need_arg "$#" "переустановка (-r)"
        case "$PM" in
            apt)    PRIV apt install --reinstall "$@" ;;
            dnf)    PRIV dnf reinstall "$@" ;;
            pacman) PRIV pacman -S "$@" ;;
        esac
        ;;
    -d)
        need_arg "$#" "удаление (-d)"
        case "$PM" in
            apt)    PRIV apt remove "$@" ;;
            dnf)    PRIV dnf remove "$@" ;;
            pacman) PRIV pacman -R "$@" ;;
        esac
        ;;
    -a)
        case "$PM" in
            apt)
                PRIV apt autoremove
                ;;
            dnf)
                PRIV dnf autoremove
                ;;
            pacman)
                orphans="$(pacman -Qtdq 2>/dev/null || true)"
                if [ -z "$orphans" ]; then
                    echo "Нет осиротевших пакетов (autoremove не требуется)."
                else
                    PRIV pacman -Rns $orphans
                fi
                ;;
        esac
        ;;
    -u)
        case "$PM" in
            apt)    PRIV apt update ;;
            dnf)    PRIV dnf makecache ;;
            pacman) PRIV pacman -Sy ;;
        esac
        ;;
    -U)
        case "$PM" in
            apt)    PRIV apt upgrade "$@" ;;
            dnf)    PRIV dnf upgrade "$@" ;;
            pacman) PRIV pacman -Su "$@" ;;
        esac
        ;;
    -UD)
        case "$PM" in
            apt)    PRIV apt full-upgrade "$@" ;;
            dnf)    PRIV dnf distro-sync ;;
            pacman) PRIV pacman -Syu ;;
        esac
        ;;
    -es)
        case "$PM" in
            apt)
                PRIV apt edit-sources
                ;;
            dnf)
                files=(/etc/yum.repos.d/*.repo)
                if [ -f "${files[0]:-}" ]; then
                    PRIV "${EDITOR:-nano}" "${files[@]}"
                else
                    echo "Файлы репозиториев /etc/yum.repos.d/*.repo не найдены." >&2
                    exit 1
                fi
                ;;
            pacman)
                PRIV "${EDITOR:-nano}" /etc/pacman.conf /etc/pacman.d/mirrorlist
                ;;
        esac
        ;;
    -ms)
        case "$PM" in
            apt)
                PRIV apt modernize-sources
                ;;
            *)
                echo "modernize-sources поддерживается только для apt (текущий ПМ: $PM)." >&2
                exit 1
                ;;
        esac
        ;;
    -sat)
        need_arg "$#" "удовлетворение зависимостей (-sat)"
        case "$PM" in
            apt)
                PRIV apt satisfy "$@"
                ;;
            *)
                echo "satisfy поддерживается только для apt (текущий ПМ: $PM)." >&2
                exit 1
                ;;
        esac
        ;;
    -pm)
        if [ "${1:-}" = "reset" ]; then
            rm -f "$STATE"
            load_pm
        fi
        echo "$PM"
        ;;
    *)
        echo "Неизвестная опция: $op" >&2
        usage >&2
        exit 1
        ;;
esac
exit $?