#!/bin/bash

#@method: crossfade
#@description: Автоматическая склейка MP3 файлов из папки с плавным наложением звука
#@example: crossfade ; crossfade "./" 5 ; crossfade "/live/Music/my" 5
crossfade() {
    local input="${1:-.}"
    local dur="${2:-3}"
    local output="output.mp3"
    local f

    # Убираем символ 's' из длительности, если он передан (например, 3s -> 3)
    dur="${dur%s}"
    local files=()
    
    # Сбор файлов по паттерну или из каталога
    if [[ "$input" == *\* ]]; then
        for f in $input; do
            [[ -f "$f" ]] && files+=("$f")
        done
    else
        for f in "$input"/*.mp3; do
            [[ -f "$f" ]] && files+=("$f")
        done
    fi

    # Сортировка списка файлов
    IFS=$'\n' sorted_files=($(sort <<<"${files[*]}")); unset IFS
    local count=${#sorted_files[@]}
    
    if (( count == 0 )); then
        echo "FAIL: No MP3 files found in target pattern/directory." >&2
        return 1
    fi

    if (( count == 1 )); then
        echo "Only 1 file found. Copying without crossfade..." >&2
        cp "${sorted_files[0]}" "$output"
        return 0
    fi

    # Сборка аргументов для ffmpeg
    local inputs=()
    local filter_complex=""
    inputs+=("-i" "${sorted_files[0]}")
    inputs+=("-i" "${sorted_files[1]}")
    filter_complex="[0:a][1:a]acrossfade=d=${dur}[a1]"

    for ((i=2; i<count; i++)); do
        inputs+=("-i" "${sorted_files[$i]}")
        filter_complex="${filter_complex}; [a$((i-1))][$i:a]acrossfade=d=${dur}[a$i]"
    done

    local final_link="[a$((count-1))]"
    echo "Processing $count files with ${dur}s crossfade layer..." >&2

    # Запуск обработки
    command ffmpeg -y "${inputs[@]}" \
        -filter_complex "$filter_complex" \
        -map "$final_link" \
        -c:a libmp3lame -q:a 2 \
        "$output" 2>/dev/null

    if (( $? == 0 )); then
        echo "Created: $output"
    else
        echo "FAIL: ffmpeg crossfade processing failed." >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    crossfade "$@"
fi