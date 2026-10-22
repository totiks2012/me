#!/usr/bin/env bash
#
# mov — переименование файлов в текущей директории по маске.
#
# Режимы (определяются по виду первого аргумента):
#   1. "XY"              литеральная замена символа X на Y во всех именах
#                        (спецсимволы * ? [ ] трактуются как литералы)
#   2. "[]шаблон_1"      нумерация ИМЕНИ ЦЕЛИКОМ: база + счётчик
#                        разделитель = последний символ перед числом
#                        ширина счётчика = число ведущих нулей в шаблоне
#   3. "шаблон#часть"    якорь # : номер подставляется на место #
#                        (## подряд → ширина 2; ### → 3 и т.д.)
#
# Родное расширение файла всегда сохраняется (кроме режима 1).
# Каталоги и скрытые файлы (.foo) не трогаются.
#
# Безопасность: полный граф переименований строится заранее, таргет считается
# коллизией, только если существует И не сдвигается сам; применение идёт
# двумя фазами через временный каталог (та же ФС), при ошибке — откат.

usage() {
    cat >&2 <<'EOF'
mov: переименование файлов в текущей директории по маске

Замена символа:
  me mov XY         во всех именах заменить X на Y (X, Y — одиночные символы)

Нумерация имени целиком (тег []):
  me mov []фото_1           → фото_1, фото_2, фото_3 ...
  me mov []архив_001        → архив_001, архив_002 ... (ширина 3)
  me mov []_1               → _1, _2 ...
  me mov []5                → 5, 6, 7 ...
  me mov []фото             → фото_1, фото_2 ... (нет числа → старт 1)

Нумерация по месту # (якорь):
  me mov "копия_#_готово"   → копия_1_готово, копия_2_готово ...
  me mov "img_##_fhd"       → img_01_fhd, img_02_fhd ... (ширина 2)

Расширение файла сохраняется автоматически (a.jpg → фото_1.jpg).
EOF
    exit 1
}

esc_glob() {     # экранировать glob-метасимволы для литеральной замены
    local s="$1" out="" c
    while [ -n "$s" ]; do
        c="${s:0:1}"
        case "$c" in
            '\'|'*'|'?'|'['|']') out+="\\$c" ;;
            *) out+="$c" ;;
        esac
        s="${s:1}"
    done
    printf '%s' "$out"
}

main() {
    local mask="$1" mode="" from to pat
    local base="" sep="" start=1 width=1 numstr last counter
    local fname base_n ext newname
    local i j
    local -a files=() all_src=() all_dst=() psrc=() pdst=()
    local -A srcset=() moved=() seen=()

    [ "$#" -eq 1 ] || { echo "mov: нужен ровно один аргумент" >&2; usage; }

    # --- определение режима -----------------------------------------------
    if [ "${mask:0:2}" = "[]" ] && [ "${#mask}" -ge 3 ]; then
        mode="bracket"        # [ ]-тег: имя целиком
        local tpl="${mask:2}"
        if [[ "$tpl" =~ ([0-9]+)$ ]]; then
            numstr="${BASH_REMATCH[1]}"
            start=$((10#$numstr))
            width=${#numstr}
            local rest="${tpl%$numstr}"
            last="${rest: -1}"
            if [ -n "$last" ] && [[ "$last" != [0-9] ]]; then
                sep="$last"
                base="${rest%$last}"
            else
                sep=""
                base="$rest"
            fi
        else
            base="$tpl"; sep="_"; start=1; width=1
        fi
    elif [ "${#mask}" -eq 2 ]; then
        mode="pair"            # замена одного символа
        from="${mask:0:1}" ; to="${mask:1:1}"
        if [ "$from" = "/" ] || [ "$to" = "/" ]; then
            echo "mov: символ '/' запрещён в паре замен (это разделитель путей)" >&2
            return 1
        fi
        pat="$(esc_glob "$from")"
    elif [[ "$mask" == *"#"* ]]; then
        mode="anchor"         # якорь #
        if [[ "$mask" =~ \#{2,} ]]; then
            width="${#BASH_REMATCH[0]}"
        else
            width=1
        fi
    else
        echo "mov: не могу разобрать маску: $mask" >&2
        usage
    fi

    # --- сбор кандидатов (обычные файлы, 1 уровень) ------------------------
    for fname in *; do
        [ -f "$fname" ] && files+=("$fname")
    done
    if [ "${#files[@]}" -eq 0 ]; then
        echo "mov: в текущей директории нет обычных файлов (или они скрытые)"
        return 0
    fi

    # --- детерминированный порядок: естественная сортировка версий (1<2<10) ----
    mapfile -d '' files < <(printf '%s\0' "${files[@]}" | sort -zV)

    # --- проход 1: граф src→dst для ВСЕХ кандидатов (детерминированный) -----
    counter="$start"
    for fname in "${files[@]}"; do
        base_n="$fname"; ext=""
        if [ "$mode" != "pair" ]; then
            if [[ "$fname" == *.* && "$fname" != .* ]]; then
                base_n="${fname%.*}"
                ext="${fname##*.}"
            fi
        fi
        case "$mode" in
            pair)
                newname="${fname//$pat/$to}"
                ;;
            bracket)
                newname="$(printf "%s%s%0${width}d" "$base" "$sep" "$counter")"
                if [ -n "$ext" ]; then newname+=".$ext"; fi
                counter=$((counter + 1))
                ;;
            anchor)
                local seg="" seg_esc="" rep=""
                if [[ "$mask" =~ \#{1,} ]]; then
                    seg="${BASH_REMATCH[0]}"
                    seg_esc="${seg//#/\\#}"
                    rep="$(printf "%0*d" "${#seg}" "$counter")"
                fi
                newname="${mask/$seg_esc/$rep}"
                if [ -n "$ext" ]; then newname+=".$ext"; fi
                counter=$((counter + 1))
                ;;
        esac
        all_src+=("$fname")
        all_dst+=("$newname")
        srcset[$fname]=1
        [ "$newname" != "$fname" ] && moved[$fname]=1
    done

    # --- проход 2: план с проверкой коллизий --------------------------------
    for ((i=0; i<${#all_src[@]}; i++)); do
        fname="${all_src[$i]}"
        newname="${all_dst[$i]}"
        [ "$newname" = "$fname" ] && continue
        if [ -n "${seen[$newname]+x}" ]; then
            echo "mov: пропущено (дубль цели): '$fname' → '$newname'" >&2
            continue
        fi
        if [ -e "$newname" ] && [ -z "${moved[$newname]+x}" ]; then
            echo "mov: пропущено (уже существует): '$fname' → '$newname'" >&2
            continue
        fi
        seen[$newname]=1
        psrc+=("$fname")
        pdst+=("$newname")
    done

    # --- фаза 1: всё в временный каталог (та же ФС) -------------------------
    if [ "${#psrc[@]}" -eq 0 ]; then
        echo "mov: переименовано файлов: 0"
        return 0
    fi

    local tmpdir=""
    tmpdir="$(mktemp -d .mov_tmp.XXXXXX)" || {
        echo "mov: не могу создать временный каталог" >&2
        return 1
    }

    for ((i=0; i<${#psrc[@]}; i++)); do
        if ! mv -- "${psrc[$i]}" "$tmpdir/$i"; then
            echo "mov: ошибка mv (фаза 1): '${psrc[$i]}'" >&2
            for ((j=0; j<i; j++)); do
                mv -- "$tmpdir/$j" "${psrc[$j]}" 2>/dev/null
            done
            rmdir "$tmpdir" 2>/dev/null
            return 1
        fi
    done

    # --- фаза 2: из временного каталога в целевые имена --------------------
    for ((i=0; i<${#psrc[@]}; i++)); do
        if mv -- "$tmpdir/$i" "${pdst[$i]}"; then
            echo "'${psrc[$i]}' → '${pdst[$i]}'"
        else
            echo "mov: ошибка mv (фаза 2): '${psrc[$i]}' → '${pdst[$i]}'" >&2
            for ((j=0; j<${#psrc[@]}; j++)); do
                [ -e "$tmpdir/$j" ] && mv -- "$tmpdir/$j" "${psrc[$j]}" 2>/dev/null
                [ -e "${pdst[$j]}" ] && [ -z "${moved[${pdst[$j]}]+x}" ] &&
                    mv -- "${pdst[$j]}" "${psrc[$j]}" 2>/dev/null
            done
            rmdir "$tmpdir" 2>/dev/null
            return 1
        fi
    done
    rmdir "$tmpdir" 2>/dev/null

    echo "mov: переименовано файлов: ${#psrc[@]}"
    return 0
}

main "$@"