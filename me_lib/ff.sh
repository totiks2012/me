#!/usr/bin/env bash
# me ff — интерактивный конструктор команд ffmpeg

trap 'stty sane 2>/dev/null' EXIT

for cmd in ffmpeg fzf; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[me ff] Ошибка: $cmd не установлен" >&2
        exit 1
    fi
done

CMD_FILE="/tmp/me_ff_cmd.sh"
VIDEO_CACHE="/dev/shm/me_$USER/video.cache"
VIDEO_DIRS=("$HOME/Videos" "$HOME/Video" "$HOME/Видео" "$HOME/Downloads" ".")

find_videos() {
    local dir
    for dir in "${VIDEO_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 3 -type f -iregex '.*\.\(mp4\|mkv\|avi\|mov\|webm\)$' 2>/dev/null
    done | sort -u
}
get_videos() {
    if [ -f "$VIDEO_CACHE" ] && [ $(( $(date +%s) - $(stat -c%Y "$VIDEO_CACHE") )) -lt 30 ]; then
        cat "$VIDEO_CACHE"
    else
        mkdir -p "$(dirname "$VIDEO_CACHE")" && find_videos > "$VIDEO_CACHE" 2>/dev/null; cat "$VIDEO_CACHE"
    fi
}

parse_time() {
    local input=$1
    [[ $input =~ ^([0-9]{1,2}):([0-9]{2}):([0-9]{2})$ ]] && { echo $(( (${BASH_REMATCH[1]}*3600) + (${BASH_REMATCH[2]}*60) + ${BASH_REMATCH[3]} )); return 0; }
    [[ $input =~ ^([0-9]{1,2}):([0-9]{2})$ ]] && { echo $(( (${BASH_REMATCH[1]}*60) + ${BASH_REMATCH[2]} )); return 0; }
    [[ $input =~ ^([0-9]+)$ ]] && { echo $((${BASH_REMATCH[1]})); return 0; }
    return 1
}
seconds_to_hms() { local s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }
scale_filter() {
    case "$1" in 480) echo "scale=854:480";; 720) echo "scale=1280:720";; 1080) echo "scale=1920:1080";; *) echo "";; esac
}

build_cmd() {
    local cmd cc="-c copy"; [ -n "$SCALE" ] && cc="-c:a copy"
    if [ "$MODE" = "cut" ]; then
        case "$TEMPLATE" in
            "⏹ [start][end]")
                cmd="ffmpeg -i \"$FILE\" -ss $START_HMS -to $END_HMS"
                [ -n "$SCALE" ] && cmd="$cmd -vf $SCALE"
                cmd="$cmd $cc \"$OUTPUT_FILE\""
                ;;
            "⏹ *[start][end]*"*)
                _fc="[0:v]trim=start=${START_SEC}:end=${END_SEC},setpts=PTS-STARTPTS[v0];[0:a]atrim=start=${START_SEC}:end=${END_SEC},asetpts=PTS-STARTPTS[a0]"
                _mv="-map \"[v0]\" -map \"[a0]\""
                [ -n "$SCALE" ] && _fc="[0:v]trim=start=${START_SEC}:end=${END_SEC},setpts=PTS-STARTPTS,${SCALE}[v0];[0:a]atrim=start=${START_SEC}:end=${END_SEC},asetpts=PTS-STARTPTS[a0]"
                cmd="ffmpeg -i \"$FILE\" -filter_complex \"${_fc}\" ${_mv} \"$OUTPUT_FILE\""
                ;;
            "⏹ [start][end]**"*)
                cmd="ffmpeg -i \"$FILE\" -ss $START_HMS"
                [ -n "$SCALE" ] && cmd="$cmd -vf $SCALE"
                cmd="$cmd $cc \"$OUTPUT_FILE\""
                ;;
        esac
    else
        local scale_filt=""
        [ -n "$SCALE" ] && scale_filt=",$SCALE"
        local dur inputs fc="" cin="" chains=()
        local idx=0

        dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TARGET_FILE" 2>/dev/null)
        dur=${dur%.*}

        if [ "$START_SEC" -le 0 ] 2>/dev/null; then
            for ef in "${INSERT_FILES[@]}"; do
                inputs="$inputs -i \"$ef\""
                chains+=("[$idx:v]setpts=PTS-STARTPTS${scale_filt}[s${idx}_v];[$idx:a]asetpts=PTS-STARTPTS[s${idx}_a]")
                cin="${cin}[s${idx}_v][s${idx}_a]"
                idx=$((idx+1))
            done
            inputs="$inputs -i \"$TARGET_FILE\""
            chains+=("[$idx:v]setpts=PTS-STARTPTS${scale_filt}[s${idx}_v];[$idx:a]asetpts=PTS-STARTPTS[s${idx}_a]")
            cin="${cin}[s${idx}_v][s${idx}_a]"
            idx=$((idx+1))

        elif [ -n "$dur" ] && [ "$START_SEC" -ge "$dur" ] 2>/dev/null; then
            inputs="-i \"$TARGET_FILE\""
            chains+=("[0:v]setpts=PTS-STARTPTS${scale_filt}[s0_v];[0:a]asetpts=PTS-STARTPTS[s0_a]")
            cin="[s0_v][s0_a]"
            idx=1
            for ef in "${INSERT_FILES[@]}"; do
                inputs="$inputs -i \"$ef\""
                chains+=("[$idx:v]setpts=PTS-STARTPTS${scale_filt}[s${idx}_v];[$idx:a]asetpts=PTS-STARTPTS[s${idx}_a]")
                cin="${cin}[s${idx}_v][s${idx}_a]"
                idx=$((idx+1))
            done

        else
            inputs="-i \"$TARGET_FILE\""
            chains+=("[0:v]trim=0:${START_SEC},setpts=PTS-STARTPTS${scale_filt}[s0_v];[0:a]atrim=0:${START_SEC},asetpts=PTS-STARTPTS[s0_a]")
            cin="[s0_v][s0_a]"
            idx=1
            for ef in "${INSERT_FILES[@]}"; do
                inputs="$inputs -i \"$ef\""
                chains+=("[$idx:v]setpts=PTS-STARTPTS${scale_filt}[s${idx}_v];[$idx:a]asetpts=PTS-STARTPTS[s${idx}_a]")
                cin="${cin}[s${idx}_v][s${idx}_a]"
                idx=$((idx+1))
            done
            chains+=("[0:v]trim=${START_SEC},setpts=PTS-STARTPTS${scale_filt}[s${idx}_v];[0:a]atrim=${START_SEC},asetpts=PTS-STARTPTS[s${idx}_a]")
            cin="${cin}[s${idx}_v][s${idx}_a]"
            idx=$((idx+1))
        fi

        local IFS=';'
        fc="${chains[*]};${cin}concat=n=${idx}:v=1:a=1[out]"
        cmd="ffmpeg $inputs -filter_complex \"${fc}\" -map \"[out]\" \"$OUTPUT_FILE\""
    fi
    echo "$cmd"
}

# --- Переменные ---
MODE=""; RES=""; SCALE=""; FILE=""; TARGET_FILE=""; INSERT_FILES=()
TEMPLATE=""; START_SEC=""; END_SEC=""; START_HMS=""; END_HMS=""; OUTPUT_FILE=""

PREVIEW_FILE="/tmp/me_ff_preview.txt"
PREVIEW_WIN='right:60%:wrap'

print_params() {
    [ -n "$MODE" ] && echo "Режим: $MODE"
    [ -n "$RES" ] && echo "Разрешение: $RES"
    [ -n "$FILE" ] && echo "Файл: $FILE"
    [ -n "$TARGET_FILE" ] && echo "Целевой: $TARGET_FILE"
    [ ${#INSERT_FILES[@]} -gt 0 ] && echo "Вставка: ${INSERT_FILES[*]}"
    [ -n "$TEMPLATE" ] && echo "Шаблон: $TEMPLATE"
    [ -n "$START_HMS" ] && echo "Start: $START_HMS"
    [ -n "$END_HMS" ] && echo "End: $END_HMS"
    [ -n "$OUTPUT_FILE" ] && echo "Выход: $OUTPUT_FILE"
}

build_cmd_preview() {
    [ -z "$MODE" ] && { echo "(шаг 1/7)"; return; }
    if [ "$MODE" = "cut" ]; then
        [ -z "$FILE" ] && { echo "(шаг 3/7 — файл)"; return; }
        [ -z "$TEMPLATE" ] && { echo "(шаг 4/7 — шаблон)"; return; }
        [ -z "$START_HMS" ] && [[ "$TEMPLATE" != *"**"* ]] && { echo "(шаг 5/7 — время)"; return; }
    else
        [ -z "$TARGET_FILE" ] && { echo "(шаг 3/7 — файл)"; return; }
        [ ${#INSERT_FILES[@]} -eq 0 ] && { echo "(шаг 4/7 — вставка)"; return; }
        [ -z "$START_HMS" ] && { echo "(шаг 5/7 — время)"; return; }
    fi
    [ -z "$OUTPUT_FILE" ] && { echo "(шаг 6/7 — имя)"; return; }
    build_cmd
}

update_preview() {
    { echo "=== Параметры ==="; print_params; echo "=== Команда ==="; build_cmd_preview; } > "$PREVIEW_FILE"
}

pick() {
    local prompt=$1 list=$2
    printf "%b" "$list" | fzf --prompt="$prompt " --reverse --preview='cat /tmp/me_ff_preview.txt 2>/dev/null' --preview-window="$PREVIEW_WIN" 2>/dev/null
}

pick_file() {
    get_videos | fzf --prompt="$1 " --reverse \
        --preview='ffprobe -v quiet -print_format json -show_format -show_streams "{}" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
f=d.get(\"format\",{})
print(f\"{f.get(\"filename\",\"\")} ({f.get(\"format_long_name\",\"\")})\")
print(f\"Duration: {round(float(f.get(\"duration\",0)),2)}s | Size: {f.get(\"size\",\"?\")} bytes\")
for s in d.get(\"streams\",[]):
    t=s.get(\"codec_type\",\"?\")
    if t==\"video\": print(f\"Video: {s.get(\"codec_name\",\"?\")} {s.get(\"width\",\"?\")}x{s.get(\"height\",\"?\")} {s.get(\"r_frame_rate\",\"?\")} fps\")
    elif t==\"audio\": print(f\"Audio: {s.get(\"codec_name\",\"?\")} {s.get(\"sample_rate\",\"?\")}Hz {s.get(\"channels\",\"?\")}ch\")
" 2>/dev/null || file "{}"' \
        --preview-window='right:60%:wrap' 2>/dev/null
}

read_time() {
    local prompt=$1 var=$2 input val
    while true; do
        read -p "$prompt " input || return 1
        [ -z "$input" ] && return 1
        val=$(parse_time "$input")
        [ -n "$val" ] && { eval "$var=\$val"; return 0; }
        echo "Неверный формат. Используйте: 30, 1:30, 00:01:30" >&2
    done
}

while true; do
    FILE=""; TARGET_FILE=""; INSERT_FILES=(); TEMPLATE=""
    START_SEC=""; END_SEC=""; START_HMS=""; END_HMS=""; OUTPUT_FILE=""

# --- Шаг 1: режим ---
MODE=$(pick "Режим > " "cut\nglue") || exit 0; [ -z "$MODE" ] && exit 0
update_preview

# --- Шаг 2: разрешение ---
RES=$(pick "Разрешение > " "none\n1080\n720\n480") || exit 0; [ -z "$RES" ] && exit 0
SCALE=$(scale_filter "$RES")
update_preview

# --- Шаг 3: файлы ---
[ -z "$(get_videos)" ] && { echo "[me ff] Видеофайлы не найдены" >&2; exit 1; }

if [ "$MODE" = "cut" ]; then
    FILE=$(pick_file "Файл > ") || exit 0; [ -z "$FILE" ] && exit 0
else
    CHOSEN_FILES=()
    while true; do
        ef=$(pick_file "Файл #$(( ${#CHOSEN_FILES[@]} + 1 )) (ESC = готово, основной — последний) > ") || break
        [ -z "$ef" ] && break
        CHOSEN_FILES+=("$ef")
    done
    [ ${#CHOSEN_FILES[@]} -eq 0 ] && echo "Нет файлов" >&2 && continue
    TARGET_FILE="${CHOSEN_FILES[-1]}"
    unset 'CHOSEN_FILES[-1]'
    INSERT_FILES=("${CHOSEN_FILES[@]}")
    echo "Точка врезки — после какого времени вставить клип?"
    echo "Форматы: секунды (30), минуты:секунды (1:30), чч:мм:сс (00:01:30)"
    read_time "Врезка после > " START_SEC || continue
    START_HMS=$(seconds_to_hms "$START_SEC")
    END_SEC=""
    TEMPLATE=""
fi
update_preview

# --- Шаг 4: шаблон (cut only) ---
if [ "$MODE" = "cut" ]; then
    TEMPLATE=$(pick "Шаблон > " "⏹ [start][end]\n⏹ *[start][end]*\n⏹ [start][end]**") || exit 0; [ -z "$TEMPLATE" ] && exit 0
    update_preview
fi

# --- Шаг 5: время (cut only) ---
if [ "$MODE" = "cut" ]; then
    echo "Введите время: секунды (30), минуты:секунды (1:30), чч:мм:сс (00:01:30)"
    case "$TEMPLATE" in
        *"[start][end]"*)
            read_time "Начало:" START_SEC || exit 0
            read_time "Конец:" END_SEC || exit 0
            [ "$START_SEC" -ge "$END_SEC" ] && { echo "Ошибка: start >= end" >&2; exit 1; }
            ;;
        *"[start][end]**"*)
            read_time "Начало:" START_SEC || exit 0
            END_SEC=""
            ;;
    esac
    START_HMS=$(seconds_to_hms "$START_SEC")
    [ -n "$END_SEC" ] && END_HMS=$(seconds_to_hms "$END_SEC")
    update_preview
fi

# --- Шаг 6: имя ---
if [ "$MODE" = "cut" ]; then
    DEFAULT_OUT="${FILE%.*}_cut.mp4"
else
    DEFAULT_OUT="${TARGET_FILE%.*}_glue.mp4"
fi
read -p "Выходной [$DEFAULT_OUT]: " OUTPUT_FILE || exit 0; [ -z "$OUTPUT_FILE" ] && OUTPUT_FILE="$DEFAULT_OUT"
update_preview

break
done

CMD=$(build_cmd)

# --- Финальный показ + действие ---
echo "$CMD" > "$CMD_FILE"; chmod +x "$CMD_FILE"
echo ""
echo "══════════════════════════════════════════"
echo "  Собранная команда:"
echo "$CMD" | fold -w 72 -s | sed 's/^/  /'
echo "══════════════════════════════════════════"
echo ""

result=$(printf "▶ Выполнить\n↺ Сбросить\n✕ Выйти" | fzf --expect=f8,f9 --reverse 2>/dev/null)
key=$(echo "$result" | head -1)
choice=$(echo "$result" | tail -1)

if [ "$key" = "f9" ] || [ "$choice" = "▶ Выполнить" ]; then
    read -p "Редактировать команду? [y/N] " edit_yn
    if [ "$edit_yn" = "y" ] || [ "$edit_yn" = "Y" ]; then
        ${EDITOR:-micro} "$CMD_FILE"
    fi
    echo "--- Выполнение ---"
    bash "$CMD_FILE"
    rc=$?
    echo ""
    echo "[me ff] Код возврата: $rc"
elif [ "$key" = "f8" ] || [ "$choice" = "↺ Сбросить" ]; then
    exit 0
fi
