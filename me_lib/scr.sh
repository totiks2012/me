#!/usr/bin/env bash

set -euo pipefail
sleep 5
dir="${HOME}/Pictures"
mkdir -p "$dir"

file="${dir}/scr_$(date +'%Y-%m-%d_%H-%M-%S').png"

# -s запускает slop для выделения области
# артефакты рамки не попадут на снимок
maim -s "$file"
me say "От scr" "Скриншот по пути -- /$HOME/Pictures" dialog-warning 5000