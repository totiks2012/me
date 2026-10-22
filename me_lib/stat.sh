#!/usr/bin/env bash
# me stat — срез состояния системы: температура CPU, громкость, батарея
vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{print $5}' | head -n 1 || echo "N/A")
cpu_temp=$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo "N/A")

bat_cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
bat_stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)

if [ -n "$bat_cap" ]; then
    out="Батарея: ${bat_cap}% (${bat_stat:-N/A}) | "
else
    out=""
fi
echo "${out}Температура: ${cpu_temp}°C | Звук: ${vol}"
