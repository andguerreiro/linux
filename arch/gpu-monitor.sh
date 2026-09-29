#!/bin/bash

H="/sys/class/drm/card0/device"
M="$H/hwmon/hwmon2"

while true; do
    clear

    GPU=$(cat "$H/gpu_busy_percent")

    EDGE=$(awk '{printf "%.0f", $1/1000}' "$M/temp1_input")
    JUNCTION=$(awk '{printf "%.0f", $1/1000}' "$M/temp2_input")
    MEMTEMP=$(awk '{printf "%.0f", $1/1000}' "$M/temp3_input")

    SCLK=$(awk '{printf "%.0f", $1/1000000}' "$M/freq1_input")
    MCLK=$(awk '{printf "%.0f", $1/1000000}' "$M/freq2_input")

    POWER=$(awk '{printf "%.1f", $1/1000000}' "$M/power1_average")
    FAN=$(cat "$M/fan1_input")

    VRAM_USED=$(awk '{printf "%.2f", $1/1024/1024/1024}' \
        "$H/mem_info_vram_used")

    VRAM_TOTAL=$(awk '{printf "%.2f", $1/1024/1024/1024}' \
        "$H/mem_info_vram_total")

    VRAM_PERCENT=$(awk \
        -v used="$VRAM_USED" \
        -v total="$VRAM_TOTAL" \
        'BEGIN {printf "%.1f", (used/total)*100}')

    printf "\n"
    printf "╔═══════════════════════════════════════╗\n"
    printf "║             AMD RX 7600               ║\n"
    printf "╠═══════════════════════════════════════╣\n"
    printf "║ GPU          %3s %%                    ║\n" "$GPU"
    printf "║ VRAM         %4s / %4s GiB (%4s%%)  ║\n" \
        "$VRAM_USED" "$VRAM_TOTAL" "$VRAM_PERCENT"
    printf "║ Edge         %3s °C                   ║\n" "$EDGE"
    printf "║ Junction     %3s °C                   ║\n" "$JUNCTION"
    printf "║ Memory       %3s °C                   ║\n" "$MEMTEMP"
    printf "║ Core clock   %4s MHz                 ║\n" "$SCLK"
    printf "║ Memory clock %4s MHz                 ║\n" "$MCLK"
    printf "║ Power        %5s W                  ║\n" "$POWER"
    printf "║ Fan          %4s RPM                 ║\n" "$FAN"
    printf "╚═══════════════════════════════════════╝\n"

    sleep 1
done
