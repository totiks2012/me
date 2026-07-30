#!/usr/bin/env bash
# wfb.sh — Open book in WReader
# Usage:
#   wfb.sh                    — читает путь из буфера обмена, запускает se-go сервер
#   wfb.sh /path/to/book.fb2  — использует переданный путь, bypass клипборда


WREADER_DIR="$HOME/.local/bin/wreader"
UI_DIR="$WREADER_DIR/ui"
WREADER_HTML="$UI_DIR/index.html"
SEGO_BIN="$WREADER_DIR/se-go"
SEGO_LOG="/tmp/me_wfb_sego.log"
WREADER_PORT=9999

# --- Разбор аргументов ---
DIRECT_MODE=false
BOOK_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --direct) DIRECT_MODE=true; shift ;;
        -h|--help)
            echo "Usage: wfb.sh [--direct] [<book-path>]"
            echo "  --direct   file:// режим (без сервера)"
            exit 0 ;;
        *) BOOK_PATH="$1"; shift ;;
    esac
done

# --- Если путь не передан — читаем из буфера обмена ---
if [ -z "$BOOK_PATH" ]; then
    try_clipboard() {
        local tmp="/tmp/me_wfb_try.txt"
        $1 > "$tmp" 2>/dev/null || true
        IFS= read -r line < "$tmp" 2>/dev/null || true
        line="${line#file://}"
        if [ -n "$line" ] && [ -f "$line" ]; then
            BOOK_PATH="$line"
            echo "[wfb] Got path from $*: '$line'" >&2
        fi
        rm -f "$tmp"
    }
    if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-paste &>/dev/null; then
        try_clipboard "wl-paste"
    fi
    if command -v xclip &>/dev/null; then
        try_clipboard "xclip -selection clipboard -o"
        [ -z "$BOOK_PATH" ] && try_clipboard "xclip -selection primary -o"
    fi
    [ -z "$BOOK_PATH" ] && [ -z "$WAYLAND_DISPLAY" ] && command -v wl-paste &>/dev/null && try_clipboard "wl-paste"
fi

if [ -z "$BOOK_PATH" ]; then
    echo "[wfb] Ошибка: укажите путь к книге или скопируйте его в буфер обмена" >&2
    exit 1
fi

if [ ! -f "$BOOK_PATH" ]; then
    echo "[wfb] Ошибка: файл не найден: $BOOK_PATH" >&2
    exit 1
fi

# --- URL-encode path (общая функция) ---
urlencode() {
    local s="$1" out=""
    LC_ALL=C
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            /) out+="%2F" ;;
            *) printf -v hex '%02X' "'$c"; out+="%${hex}" ;;
        esac
    done
    echo "$out"
}

SYMLINK="$UI_DIR/__book__"

# --- DIRECT MODE (file://, без сервера) ---
if [ "$DIRECT_MODE" = true ]; then
    ENC_PATH=$(urlencode "$BOOK_PATH")
    FINAL_URL="file://${WREADER_HTML}?book=${ENC_PATH}"
    echo "[wfb] DIRECT: $FINAL_URL" >&2
    /opt/firefox/firefox "$FINAL_URL"
    exit 0
fi

# --- SERVER MODE (se-go + symlink) ---
cleanup() {
    rm -f "$SYMLINK" "$SEGO_LOG"
}
trap cleanup EXIT INT TERM

kill_old() {
    local pid
    if command -v lsof &>/dev/null; then
        pid=$(lsof -ti:"$WREADER_PORT" 2>/dev/null) && kill "$pid" 2>/dev/null || true
    elif command -v fuser &>/dev/null; then
        fuser -k "${WREADER_PORT}/tcp" 2>/dev/null || true
    fi
}
kill_old
sleep 0.2

ln -sf "$BOOK_PATH" "$SYMLINK"
echo "[wfb] Symlink: $SYMLINK → $BOOK_PATH" >&2

"$SEGO_BIN" -root "$UI_DIR" -port "$WREADER_PORT" > "$SEGO_LOG" 2>&1 &
SEGO_PID=$!
disown

URL_LINE=""
for i in $(seq 1 20); do
    URL_LINE=$(grep -o "http://127.0.0.1:[0-9]*/?auth=[a-f0-9]*" "$SEGO_LOG" || true)
    [ -n "$URL_LINE" ] && break
    sleep 0.2
done

if [ -z "$URL_LINE" ]; then
    echo "[wfb] Ошибка: se-go не запустился" >&2
    exit 1
fi

BASE="${URL_LINE%%\?*}"
BASE="${BASE%/}"
TOKEN="${URL_LINE##*auth=}"
FINAL_URL="${BASE}/?auth=${TOKEN}&_=$(date +%s)&book=__book__"

echo "[wfb] URL: $FINAL_URL" >&2

/opt/firefox/firefox "$FINAL_URL"

sleep 1
