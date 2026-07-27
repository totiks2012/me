#!/usr/bin/env bash
# itag.sh — Редактор метаданных аудиофайлов: fzf + micro + mutagen

AUDIO_EXTS="*.mp3 *.flac"

get_music_dirs() {
    local dirs=()
    [ -d "$HOME/Music" ]   && dirs+=("$HOME/Music")
    [ -d "$HOME/Музыка" ]  && dirs+=("$HOME/Музыка")
    [ -d "$HOME/audio" ]   && dirs+=("$HOME/audio")
    [ "${#dirs[@]}" -eq 0 ] && dirs+=("$HOME")
    echo "${dirs[@]}"
}

check_deps() {
    local deps=("fzf" "micro" "ffprobe" "python3")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if ! python3 -c "import mutagen" 2>/dev/null; then
        missing+=("python3-mutagen")
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Отсутствуют зависимости: ${missing[*]}" >&2
        echo "Установи: sudo apt install ${missing[*]}" >&2
        notify-send -i dialog-error -t 4000 "itag" "Нет зависимостей: ${missing[*]}" 2>/dev/null || true
        exit 1
    fi
}

preview_tags() {
    local file="$1"
    [ ! -f "$file" ] && { echo "Не выбран файл"; return; }
    python3 -c "
import json, subprocess, sys, os
try:
    size = os.path.getsize(sys.argv[1])
    r = subprocess.run(['ffprobe', '-v', 'quiet', '-show_format',
        '-print_format', 'json', '--', sys.argv[1]],
        capture_output=True, text=True, timeout=5)
    d = json.loads(r.stdout).get('format', {}).get('tags', {})
    fmt = json.loads(r.stdout).get('format', {}).get('format_name', '?')
    for f in 'title artist album date genre track'.split():
        print(f'{f}: {d.get(f, d.get(f.upper(), \"—\"))}')
    dur = json.loads(r.stdout).get('format', {}).get('duration', '0')
    print(f'duration: {int(float(dur))//60}:{int(float(dur))%60:02d}')
    print(f'format: {fmt}')
    print(f'size: {size//1024} KB')
except Exception as e:
    print(f'Ошибка чтения: {e}')
" "$file"
}

extract_tags() {
    local file="$1"
    python3 -c "
import json, subprocess, sys
try:
    r = subprocess.run(['ffprobe', '-v', 'quiet', '-show_format',
        '-print_format', 'json', '--', sys.argv[1]],
        capture_output=True, text=True, timeout=5)
    d = json.loads(r.stdout).get('format', {}).get('tags', {})
    for f in 'title artist album date genre track tracknumber'.split():
        val = d.get(f, d.get(f.upper(), ''))
        print(f'{f}={val}')
except Exception:
    pass
" "$file"
}

write_tags() {
    local file="$1" tmp="$2"
    python3 -c "
import sys, os

path = sys.argv[1]
ext = os.path.splitext(path)[1].lower()

try:
    if ext == '.mp3':
        from mutagen.easyid3 import EasyID3
        try:
            audio = EasyID3(path)
        except Exception:
            from mutagen.mp3 import MP3
            audio = MP3(path)
            audio.add_tags()
            audio = EasyID3(path)
    elif ext == '.flac':
        from mutagen.flac import FLAC
        audio = FLAC(path)
    else:
        from mutagen import File
        audio = File(path)
        if audio is None:
            sys.exit(1)
except Exception:
    sys.exit(1)

tags = {}
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            k, v = line.split('=', 1)
            tags[k.strip()] = v.strip()

mapping = {
    'title': 'title', 'artist': 'artist', 'album': 'album',
    'date': 'date', 'year': 'date', 'genre': 'genre',
    'track': 'tracknumber', 'tracknumber': 'tracknumber',
    'comment': 'comment',
}

for k, v in tags.items():
    key = mapping.get(k)
    if not key or not v:
        continue
    audio[key] = v

audio.save()
" "$file" "$tmp"
}

find_audio() {
    local dirs=($(get_music_dirs))
    local expr=()
    for ext in $AUDIO_EXTS; do
        expr+=(-o -name "$ext")
    done
    unset "expr[0]"
    find "${dirs[@]}" -type f \( "${expr[@]}" \) 2>/dev/null | sort
}

main() {
    check_deps

    local audio_list
    audio_list=$(find_audio)
    [ -z "$audio_list" ] && {
        notify-send -i dialog-error -t 3000 "itag" "Аудиофайлы (*.mp3 *.flac) не найдены" 2>/dev/null
        exit 1
    }

    local selected
    selected=$(echo "$audio_list" | fzf --reverse \
        --header="Выберите файл для редактирования тегов (Esc — выход)" \
        --preview="'$0' --preview {}" \
        --preview-window='right:55%:wrap')

    [ -z "$selected" ] && exit 0
    [ ! -f "$selected" ] && exit 1

    local tmpfile
    tmpfile=$(mktemp /tmp/itag_XXXXXX.txt)
    trap 'rm -f "$tmpfile"' EXIT

    {
        echo "# Теги для: $selected"
        echo "# Редактируй строки KEY=VALUE. Строки с # и пустые игнорируются."
        echo "# Удали строку чтобы оставить поле без изменений."
        echo "#"
        extract_tags "$selected"
    } > "$tmpfile"

    micro "$tmpfile"

    write_tags "$selected" "$tmpfile"

    notify-send -i audio-x-generic -t 2000 "itag" "Теги сохранены: $(basename "$selected")" 2>/dev/null || true
}

case "${1:-}" in
    --preview) shift; preview_tags "$@" ;;
    *) main "$@" ;;
esac
