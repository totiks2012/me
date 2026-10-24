#!/usr/bin/env bash
#true_method
# ffl.sh — форматирование USB-флеш-дисков (список → выбор ФС → формат)
# Вызывается методом `me ffl`. Аргументов не принимает.
#
# Безопасность:
#   * В список попадают только диски: trans=usb И /sys/block/<name>/removable=1
#   * Системные диски (блокирующие / и swap), sda и nvme/mmcblk исключаются всегда
#   * Перед mkfs выбор заново проверяется по тем же критериям
#   * Форматирование подтверждается ручным вводом имени диска
set -u

trap 'stty sane 2>/dev/null' EXIT

for cmd in lsblk fzf wipefs; do
    command -v "$cmd" &>/dev/null || { echo "[me ffl] Ошибка: $cmd не установлен" >&2; exit 1; }
done

# Устройства, форматировать которые запрещено в любом случае (диск, на котором / и swap)
sysdevs() {
    local src dev m
    src=$(findmnt -no SOURCE / 2>/dev/null) || true
    if [ -n "$src" ]; then
        dev=$(basename "$src")
        printf '%s\n' "${dev%%[0-9]*}"
    fi
    if command -v swapon &>/dev/null; then
        while read -r m; do
            [ -n "$m" ] || continue
            dev=$(basename "$m")
            printf '%s\n' "${dev%%[0-9]*}"
        done < <(swapon --noheadings --show=NAME 2>/dev/null)
    fi
}

# Список безопасных USB-флеш-дисков: строки "имя<TAB>размер<TAB>инфо"
list_usb_disks() {
    local name tran rem model vendor size s
    local -a sys=()
    while read -r s; do [ -n "$s" ] && sys+=("$s"); done < <(sysdevs)
    while read -r name tran; do
        [ "$tran" = "usb" ] || continue
        [ -f "/sys/block/$name/removable" ] || continue
        rem=$(cat "/sys/block/$name/removable")
        [ "$rem" = "1" ] || continue
        case "$name" in
            sda|nvme*|mmcblk*) continue ;;
        esac
        for s in "${sys[@]}"; do
            [ "$name" = "$s" ] && continue 2
        done
        model=$(cat "/sys/block/$name/device/model" 2>/dev/null || true)
        vendor=$(cat "/sys/block/$name/device/vendor" 2>/dev/null || true)
        size=$(lsblk -dnr -o SIZE "/dev/$name" 2>/dev/null || echo "?")
        printf '%s\t%s\t%s %s\n' "$name" "$size" "$vendor" "$model"
    done < <(lsblk -dnr -o NAME,TRAN 2>/dev/null)
}

# Перепроверка перед форматированием: диск снова в списке безопасных?
check_disk_ok() {
    local name=$1
    [ -n "$name" ] || return 1
    [ -b "/dev/$name" ] || return 1
    list_usb_disks | cut -f1 | grep -qx "$name"
}

run() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# --- 1. Выбор диска ---
disks=$(list_usb_disks)
if [ -z "$disks" ]; then
    echo "[me ffl] Не найдено USB-флеш-дисков (usb + removable). Подключи флешку." >&2
    exit 1
fi

selected=$(printf "%b" "$disks" | fzf --reverse \
    --prompt="Флеш-диск > " \
    --header="Форматируется ВЕСЬ диск. Системный диск исключён." \
    --with-nth=1,2,3) || exit 0
[ -z "$selected" ] && exit 0
dev=$(printf "%s" "$selected" | cut -f1)

# --- 2. Выбор файловой системы ---
fslist=""
if command -v mkfs.fat &>/dev/null || command -v mkfs.vfat &>/dev/null; then
    fslist+="fat32\tFAT32 — совместимость везде (Windows/macOS)\n"
else
    fslist+="fat32\tFAT32 — нужен dosfstools (mkfs.fat не найден)\n"
fi
if command -v mkfs.ext4 &>/dev/null; then
    fslist+="ext4\tEXT4 — Linux, журналирование\n"
else
    fslist+="ext4\tEXT4 — нужен e2fsprogs (mkfs.ext4 не найден)\n"
fi
if command -v mkfs.exfat &>/dev/null; then
    fslist+="exfat\texFAT — большие файлы, Windows/macOS/Linux\n"
else
    fslist+="exfat\texFAT — нужен exfatprogs (mkfs.exfat не найден)\n"
fi

fs=$(printf "%b" "$fslist" | fzf --reverse \
    --prompt="Файловая система > " \
    --header="Форматирование /dev/$dev" \
    --with-nth=1) || exit 0
[ -z "$fs" ] && exit 0
fs=$(printf "%s" "$fs" | cut -f1)

# --- 3. Подбор mkfs-инструмента ---
case "$fs" in
    fat32)
        tool=$(command -v mkfs.fat || command -v mkfs.vfat)
        mkargs=(-F32)
        ;;
    ext4)
        tool=$(command -v mkfs.ext4)
        mkargs=(-F)
        ;;
    exfat)
        tool=$(command -v mkfs.exfat)
        mkargs=()
        ;;
    *)
        echo "[me ffl] Неизвестная ФС: $fs" >&2
        exit 1
        ;;
esac
if [ -z "$tool" ]; then
    echo "[me ffl] Инструмент для $fs не установлен." >&2
    echo "  fat32: sudo apt install dosfstools" >&2
    echo "  ext4:  sudo apt install e2fsprogs" >&2
    echo "  exfat: sudo apt install exfatprogs" >&2
    exit 1
fi

# --- 4. Подтверждение с ручным вводом имени диска ---
info=$(printf "%s" "$selected" | cut -f2-)
echo
echo "════════════════════════════════════════════"
echo "  Форматирование ВСЕГО диска: /dev/$dev"
echo "  $info"
echo "  Файловая система: $fs"
echo "  ВСЕ данные будут уничтожены безвозвратно!"
echo "════════════════════════════════════════════"
read -r -p "Введи имя диска для подтверждения ($dev): " confirm
[ "$confirm" = "$dev" ] || { echo "[me ffl] Отмена: имя не совпало." >&2; exit 1; }

# --- 5. Финальная перепроверка безопасности ---
if ! check_disk_ok "$dev"; then
    echo "[me ffl] ОТКАЗ: /dev/$dev больше не в списке безопасных USB-устройств." >&2
    echo "[me ffl] Форматирование отменено." >&2
    exit 1
fi

# --- 6. Размонтирование смонтированных разделов ---
mounted=()
while read -r part; do
    [ -n "$part" ] && mounted+=("$part")
done < <(lsblk -ln -o NAME,MOUNTPOINT "/dev/$dev" 2>/dev/null | awk '$2!=""{print $1}')
if [ ${#mounted[@]} -gt 0 ]; then
    echo "Смонтированные разделы /dev/$dev: ${mounted[*]}"
    read -r -p "Размонтировать и продолжить? [y/N] " um
    [ "$um" = "y" ] || [ "$um" = "Y" ] || { echo "[me ffl] Отмена." >&2; exit 1; }
    for part in "${mounted[@]}"; do
        run umount "/dev/$part"
    done
fi

# --- 7. Стирание разметки и форматирование всего устройства ---
echo "[me ffl] >>> wipefs -a /dev/$dev"
if ! run wipefs -a "/dev/$dev"; then
    echo "[me ffl] Ошибка стирания таблицы разделов." >&2
    exit 1
fi
sync

cmd=("$tool" "${mkargs[@]}" "/dev/$dev")
echo "[me ffl] >>> ${cmd[*]}"
if ! "${cmd[@]}"; then
    echo "[me ffl] Ошибка форматирования." >&2
    exit 1
fi
sync

echo
echo "[me ffl] Готово: /dev/$dev отформатирован в $fs"
lsblk -f "/dev/$dev" 2>/dev/null
