#!/usr/bin/env bash
#true_method
# yd.sh — YouTube Fallback Downloader
# Берёт URL из буфера обмена (или аргумента), скачивает в текущую директорию
# 7 методов с последовательным fallback

readonly YTDLP="/usr/local/bin/yt-dlp"
readonly LOG_FILE="$HOME/Videos/yout/yt-dlp_fallback.log"

log() {
    local level="$1" msg="$2" ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

get_url() {
    if [[ $# -ge 1 && -n "$1" ]]; then
        echo "$1"
        return 0
    fi
    local clip
    clip=$(xsel -ob 2>/dev/null || xclip -o -sel clip 2>/dev/null || true)
    if [[ -n "$clip" ]]; then
        echo "$clip"
        return 0
    fi
    echo "Ошибка: URL не передан и не найден в буфере обмена" >&2
    exit 1
}

fallback_download() {
    local url="$1"
    local out_dir="$2"

    mkdir -p "$out_dir"
    cd "$out_dir" || exit 1

    local ff=""
    if ff=$(command -v ffmpeg); then
        :
    else
        log "WARN" "ffmpeg не найден, склейка может не работать"
        ff=""
    fi

    local ffargs=()
    [[ -n "$ff" ]] && ffargs=(--ffmpeg-location "$ff")

    local ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    log "INFO" "fallback: $url -> $out_dir"

    if "$YTDLP" "${ffargs[@]}" -f "bestvideo[height<=720]+bestaudio/best[height<=720]" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "A-720p: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" -f "bestvideo[height<=480]+bestaudio/best[height<=480]" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "B-480p: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" -f "bestvideo+bestaudio/best" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "C-best: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" -f "best" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "D-simple: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" -f "worstvideo+worstaudio/worst" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "E-worst: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" --no-check-certificate --add-header "User-Agent: $ua" -f "bestvideo[height<=720]+bestaudio/best[height<=720]" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "F-nocheck: $url"; return 0; fi
    if "$YTDLP" "${ffargs[@]}" --no-check-certificate --add-header "User-Agent: $ua" -f "best" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$url"; then log "OK" "G-nocheck-best: $url"; return 0; fi

    log "ERROR" "Все методы провалились: $url"
    echo "Ошибка: не удалось скачать $url" >&2
    return 1
}

main() {
    local url
    url=$(get_url "$@")
    local dir
    dir=$(pwd)
    echo "Скачивание: $url"
    echo "Каталог: $dir"
    fallback_download "$url" "$dir"
}

main "$@"